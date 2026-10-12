"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Badge } from "@/components/ui/badge"
import { FieldCard } from "@/components/ui/field-card"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Plus, Loader2, Download } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useCurrency, useFmt } from "@/lib/currency"
import {
  listPoultryProducts, listPoultryStockTransactions, addPoultryStockTransaction,
  listPoultryRawMaterialPurchases, listPoultryRawMaterialUsageHistory,
  listPoultryRawMaterialItems, listPoultryRawMaterialAdjustments, adjustPoultryRawMaterialItem,
  setPoultryProductStock, reconcilePoultryProductStock,
  listPoultryBirdAdjustmentOptions, postPoultryBirdAdjustment,
  type PoultryProduct, type PoultryStockTransaction, type PoultryRawMaterialItem, type PoultryBirdAdjustmentOption,
} from "@/lib/api/poultry-inventory"
import { getUserContext } from "@/lib/api/config"
import { RecalculateStockButton } from "@/components/poultry/recalculate-stock-button"
import { SetProductStockButton } from "@/components/inventory/set-product-stock-button"
import { ReconcileProductStockButton } from "@/components/inventory/reconcile-product-stock-button"
import { exportTableToPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"
import { fmtDateTime } from "@/lib/utils/company-datetime"

// Doc 5: movement types with sign. Positive = increase, negative = decrease.
// Manual movements only. 'Production' and 'Sale' are RESERVED for the posting
// paths that own them (production records and the sales module), which write the
// ledger row together with its source record and set RelatedId.
//
// 'Sale' used to be offered here. A hand-posted -1,000 'Sale' with no Sale row
// behind it is invisible to /egg-tracker — its sales come from the Sale table,
// and its stock-move pass skips txnType 'Sale' to avoid double-counting real
// sales — while /poultry-inventory counts it, because that page reads the ledger
// directly. That single row is why the two pages disagreed by exactly 1,000.
// A manual reduction belongs under Decrease, Damage/Loss or Adjustment.
const MOVEMENTS: { value: string; sign: 1 | -1 }[] = [
  { value: "Increase", sign: 1 }, { value: "Adjustment", sign: 1 },
  { value: "Decrease", sign: -1 }, { value: "Damage/Loss", sign: -1 },
]
const MOVE_COLORS: Record<string, string> = {
  Increase: "bg-green-100 text-green-700", Restock: "bg-green-100 text-green-700", Production: "bg-emerald-100 text-emerald-700",
  Adjustment: "bg-slate-100 text-slate-700", Adjust: "bg-slate-100 text-slate-700",
  Decrease: "bg-amber-100 text-amber-700", Sale: "bg-blue-100 text-blue-700", Return: "bg-amber-100 text-amber-700",
  "Damage/Loss": "bg-red-100 text-red-700", "Delivery Load": "bg-indigo-100 text-indigo-700", "Delivery Return": "bg-amber-100 text-amber-700",
  "Bird Adjustment": "bg-violet-100 text-violet-700",
}

// "flock" select value for a batch's birds not yet placed in any flock.
const UNPLACED = "unplaced"
const isBirdProduct = (p: PoultryProduct) => !!p.isBirdProduct || p.name === "Birds"
const EMPTY_FORM = { target: "", movementType: "Increase", quantity: 0, unitCost: 0, note: "", batchId: "", flockId: "" }
type Move = { key: string; date: string; item: string; parentType: string; movementType: string; qty: number; unitCost: number | null; total: number | null; source: string; note: string | null }

function sourceFor(txnType: string, relatedId?: number | null): string {
  if (txnType === "Production") return "Production Record"
  if (txnType === "Sale") return "Sale"
  if (txnType === "Restock" || txnType === "Increase") return "Manual / Product Stock Entry"
  return "Stock Page"
}

// Toolbar buttons sit two-up on a phone. They need to wrap and grow: the Button
// base is `whitespace-nowrap` at a fixed h-9, and "Recalculate product stock"
// wants ~220px against a ~170px half-width cell, so it would spill instead.
// Full width on mobile, but the LABEL never wraps -- "Recalculate stock" was
// breaking onto a second line and making the button twice as tall as its
// neighbours. Height stays fixed; only the button width is responsive.
const TOOLBAR_BTN = "w-full h-9 whitespace-nowrap sm:w-auto"

export default function PoultryStockPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const { code: currencyCode } = useCurrency()
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [rawItems, setRawItems] = useState<PoultryRawMaterialItem[]>([])
  const [txns, setTxns] = useState<PoultryStockTransaction[]>([])
  const [rawMoves, setRawMoves] = useState<Move[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  // `target` encodes the picked item: "p:<id>" = finished product, "r:<id>" = raw material / supply.
  // Birds also need batchId and flockId (a flock id, or UNPLACED for the batch's unplaced birds).
  const [form, setForm] = useState(EMPTY_FORM)
  // 359: batches and their flocks, loaded when Birds is picked.
  const [birdOptions, setBirdOptions] = useState<PoultryBirdAdjustmentOption[] | null>(null)

  // List filters + column sort.
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [parentTypeFilter, setParentTypeFilter] = useState("all")
  const [movementFilter, setMovementFilter] = useState("all")
  const [itemFilter, setItemFilter] = useState("all")
  const [sort, setSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [ps, items, ts, purch, usage, adjust] = await Promise.all([
        listPoultryProducts(), listPoultryRawMaterialItems().catch(() => []), listPoultryStockTransactions(),
        listPoultryRawMaterialPurchases().catch(() => []), listPoultryRawMaterialUsageHistory().catch(() => []),
        listPoultryRawMaterialAdjustments().catch(() => []),
      ])
      setProducts(ps); setRawItems(items); setTxns(ts)
      const rm: Move[] = [
        ...purch.map((p) => ({ key: `rp${p.poultryRawMaterialPurchaseId}`, date: p.purchaseDate, item: p.itemName ?? "", parentType: "Raw Material", movementType: "Increase", qty: p.quantity, unitCost: p.unitCost, total: p.totalCost, source: "Raw Material Purchase", note: p.notes ?? null })),
        ...usage.map((u) => ({ key: `ru${u.poultryRawMaterialUsageId}`, date: u.usedDate, item: u.itemName ?? "", parentType: "Raw Material", movementType: "Decrease", qty: -Math.abs(u.quantityUsed), unitCost: null, total: null, source: "Production Usage", note: u.varianceReason ?? null })),
        ...adjust.map((a) => ({ key: `ra${a.poultryRawMaterialAdjustmentId}`, date: a.adjustedDate, item: a.itemName ?? "", parentType: a.category === "Supplies" ? "Supplies" : "Raw Material", movementType: a.movementType || (a.quantity >= 0 ? "Increase" : "Decrease"), qty: a.quantity, unitCost: a.unitCost ?? null, total: a.unitCost != null ? Number((a.unitCost * Math.abs(a.quantity)).toFixed(2)) : null, source: "Manual Adjustment", note: a.note ?? null })),
      ]
      setRawMoves(rm)
    } catch (e: any) { toast({ title: "Could not load stock", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const moves: Move[] = useMemo(() => {
    const prod: Move[] = txns.map((t) => ({
      key: `pt${t.poultryStockTransactionId}`, date: t.createdDate, item: t.productName ?? "", parentType: "Finished Product",
      movementType: t.txnType, qty: t.quantity, unitCost: t.unitCost ?? null,
      total: t.unitCost != null ? Number((t.unitCost * Math.abs(t.quantity)).toFixed(2)) : null,
      source: sourceFor(t.txnType, t.relatedId), note: t.note ?? null,
    }))
    return [...prod, ...rawMoves].sort((a, b) => (b.date || "").localeCompare(a.date || ""))
  }, [txns, rawMoves])

  const parentTypeOptions = useMemo(() => Array.from(new Set(moves.map((m) => m.parentType).filter(Boolean))).sort(), [moves])
  const movementOptions = useMemo(() => Array.from(new Set(moves.map((m) => m.movementType).filter(Boolean))).sort(), [moves])
  const itemOptions = useMemo(() => Array.from(new Set(moves.map((m) => m.item).filter(Boolean))).sort(), [moves])

  const filteredMoves = useMemo(() => {
    let rows = filterByDateAndSearch(moves, { search, dateFrom, dateTo, searchKeys: ["item", "source", "note"], dateKey: "date" })
    if (itemFilter !== "all") rows = rows.filter((m) => m.item === itemFilter)
    if (parentTypeFilter !== "all") rows = rows.filter((m) => m.parentType === parentTypeFilter)
    if (movementFilter !== "all") rows = rows.filter((m) => m.movementType === movementFilter)
    return rows
  }, [moves, search, dateFrom, dateTo, itemFilter, parentTypeFilter, movementFilter])

  // Default order stays date-desc (moves is pre-sorted); a header click overrides.
  const sortedMoves = useMemo(() => sortData(filteredMoves, sort.key, sort.direction), [filteredMoves, sort])
  const pg = usePagination(sortedMoves)

  // ------------------------------------------------------------- PDF export
  //
  // Exports `sortedMoves`: every row the filters leave, in the order the table
  // is sorted, NOT just the page on screen. A PDF of page 1 of 9 is a trap —
  // it looks like the whole ledger.
  const buildPdfOpts = (): PdfExportOptions => {
    const filtersUsed = [
      itemFilter !== "all" ? { label: "Item", value: itemFilter } : null,
      parentTypeFilter !== "all" ? { label: "Parent type", value: parentTypeFilter } : null,
      movementFilter !== "all" ? { label: "Movement", value: movementFilter } : null,
      search.trim() ? { label: "Search", value: search.trim() } : null,
    ].filter((f): f is { label: string; value: string } => f !== null)

    // In and out are reported separately: a net figure across raw materials,
    // supplies and finished products would be adding kilograms to eggs.
    const totalIn = sortedMoves.reduce((sum, m) => sum + (m.qty > 0 ? m.qty : 0), 0)
    const totalOut = sortedMoves.reduce((sum, m) => sum + (m.qty < 0 ? -m.qty : 0), 0)

    return {
      title: "Stock Movements",
      filename: "poultry-stock-movements",
      orientation: "landscape",
      fromDate: dateFrom || undefined,
      toDate: dateTo || undefined,
      filtersUsed: filtersUsed.length > 0 ? filtersUsed : undefined,
      // Lets the letterhead read "Showing: 73 of 412 stock movements" instead
      // of a bare count that says nothing about what was left out.
      recordLabel: "stock movements",
      totalBeforeFilters: moves.length,
      currencyLabel: currencyCode,
      columns: [
        { header: "Date" },
        { header: "Item" },
        { header: "Parent Type" },
        { header: "Movement" },
        { header: "Qty", align: "right" },
        { header: "Unit Price", align: "right" },
        { header: "Total Value", align: "right" },
        { header: "Source" },
        { header: "Note" },
      ],
      rows: sortedMoves.map((m) => [
        (m.date || "").split("T")[0],
        m.item,
        m.parentType,
        m.movementType,
        // Keep the sign the table shows: "+120" and "-40" are the whole point
        // of a movements list.
        `${m.qty > 0 ? "+" : ""}${m.qty.toLocaleString()}`,
        m.unitCost != null ? gh(m.unitCost) : "—",
        m.total != null ? gh(m.total) : "—",
        m.source,
        m.note ?? "—",
      ]),
      summaryLines: [
        `Movements: ${sortedMoves.length.toLocaleString()}`,
        `Total in: +${totalIn.toLocaleString()}`,
        `Total out: -${totalOut.toLocaleString()}`,
      ],
      // Orange, matching /poultry-inventory — the two pages report on the same
      // stock and should not print in different colours.
      headFillColor: [234, 88, 12],
    }
  }

  /**
   * CSV of the same rows the PDF prints, for anyone who wants to total or pivot
   * them rather than read them.
   *
   * Built from buildPdfOpts() rather than from `sortedMoves` again, so the two
   * exports cannot list different columns or a different set of rows: one
   * definition, two file formats.
   */
  const handleExportCsv = () => {
    if (sortedMoves.length === 0) {
      toast({ title: "Nothing to export", description: "No stock movements match the current filters.", variant: "destructive" })
      return
    }
    const opts = buildPdfOpts()
    // Everything is quoted and inner quotes doubled — item names and notes are
    // free text and routinely contain commas.
    const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`
    const lines = [
      opts.columns.map((c) => esc(c.header)).join(","),
      ...opts.rows.map((row) => row.map(esc).join(",")),
    ]
    // The filters the rows were taken under, written under the table rather than
    // above it, so the header row stays the first line for a spreadsheet.
    const meta = [
      "",
      [esc("Movements"), esc(sortedMoves.length)].join(","),
      ...(opts.filtersUsed ?? []).map((f) => [esc(f.label), esc(f.value)].join(",")),
      ...(dateFrom || dateTo ? [[esc("Period"), esc(`${dateFrom || "start"} to ${dateTo || "today"}`)].join(",")] : []),
    ]
    // BOM first: Excel reads a UTF-8 CSV as ANSI without it, and mangles every
    // currency symbol and accented supplier name.
    const blob = new Blob(["\ufeff" + lines.concat(meta).join("\n")], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `poultry-stock-movements-${new Date().toISOString().split("T")[0]}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const handleExportPdf = async () => {
    if (sortedMoves.length === 0) {
      toast({ title: "Nothing to export", description: "No stock movements match the current filters.", variant: "destructive" })
      return
    }
    try {
      await exportTableToPdf(buildPdfOpts())
    } catch {
      toast({ title: "PDF export failed", description: "Could not generate the PDF. Please try again.", variant: "destructive" })
    }
  }

  // ------------------------------------------------------------ 359 birds
  // Birds are counted from flocks and their production records, not from the
  // stock ledger, so a bird movement names the batch and the flock it is for.
  const birdTarget = useMemo(() => {
    const [kind, idStr] = form.target.split(":")
    return kind === "p" && products.some((p) => p.poultryProductId === Number(idStr) && isBirdProduct(p))
  }, [form.target, products])

  useEffect(() => {
    if (!open || !birdTarget || birdOptions) return
    listPoultryBirdAdjustmentOptions()
      .then(setBirdOptions)
      .catch((e: any) => toast({ title: "Could not load flocks", description: e?.message, variant: "destructive" }))
  }, [open, birdTarget, birdOptions, toast])

  const birdBatches = useMemo(() => {
    const seen = new Map<number, PoultryBirdAdjustmentOption>()
    for (const o of birdOptions ?? []) if (!seen.has(o.batchId)) seen.set(o.batchId, o)
    return Array.from(seen.values())
  }, [birdOptions])
  const batchFlocks = useMemo(
    () => (birdOptions ?? []).filter((o) => String(o.batchId) === form.batchId && o.flockId != null),
    [birdOptions, form.batchId])
  const pickedBatch = birdBatches.find((b) => String(b.batchId) === form.batchId) ?? null
  const pickedFlock = batchFlocks.find((f) => String(f.flockId) === form.flockId) ?? null
  // Birds the chosen flock (or the batch's unplaced pool) holds now, and after this movement.
  const birdsNow = form.flockId === UNPLACED ? pickedBatch?.unplacedBirds ?? null : pickedFlock?.liveBirds ?? null
  const birdSign = MOVEMENTS.find((m) => m.value === form.movementType)?.sign ?? 1
  const birdsAfter = birdsNow == null ? null : birdsNow + birdSign * Math.abs(Math.round(form.quantity || 0))

  async function save() {
    if (!form.target) { toast({ title: "Pick an item", variant: "destructive" }); return }
    if (form.quantity <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    const mv = MOVEMENTS.find((m) => m.value === form.movementType)!
    const signed = mv.sign * Math.abs(form.quantity)
    const [kind, idStr] = form.target.split(":")
    const id = Number(idStr)
    if (birdTarget) {
      if (!form.batchId) { toast({ title: "Choose the batch", variant: "destructive" }); return }
      if (!form.flockId) { toast({ title: "Choose the flock", description: "Or \"Not placed in a flock\" for the batch's birds that are not in any flock yet.", variant: "destructive" }); return }
      if (!Number.isInteger(form.quantity)) { toast({ title: "Birds are whole numbers", variant: "destructive" }); return }
      if (birdsAfter != null && birdsAfter < 0) { toast({ title: "Not enough birds", description: `There are only ${birdsNow} birds there.`, variant: "destructive" }); return }
    }
    setSaving(true)
    try {
      if (birdTarget) {
        await postPoultryBirdAdjustment({
          batchId: Number(form.batchId),
          flockId: form.flockId === UNPLACED ? null : Number(form.flockId),
          movementType: form.movementType,
          quantity: signed,
          note: form.note || null,
          createdBy: getUserContext().userId || null,
        })
        setBirdOptions(null)      // the counts just moved
      } else if (kind === "r") {
        // Raw material / supply — adjust its stock directly (no expense/usage side effects).
        await adjustPoultryRawMaterialItem(id, { quantity: signed, unitCost: form.unitCost || null, movementType: form.movementType, note: form.note || "Manual stock adjustment" })
      } else {
        await addPoultryStockTransaction({ poultryProductId: id, txnType: form.movementType, quantity: signed, unitCost: form.unitCost || null, note: form.note || "Manual stock entry" })
      }
      toast({ title: birdTarget ? "Birds adjusted" : "Stock movement added" }); setOpen(false); setForm(EMPTY_FORM); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div><h1 className="text-2xl font-bold">Stock Movements</h1><p className="text-sm text-slate-500">All stock increases and decreases — finished products and raw materials. Production, sales, purchases and manual entries.</p></div>
            <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap sm:items-center">
              <RecalculateStockButton className={TOOLBAR_BTN} items={rawItems} onDone={load} />
              <ReconcileProductStockButton className={TOOLBAR_BTN} products={products.map((p) => ({ id: p.poultryProductId, name: p.name }))} reconcile={reconcilePoultryProductStock} onDone={load} />
              <SetProductStockButton className={TOOLBAR_BTN} products={products.map((p) => ({ id: p.poultryProductId, name: p.name, currentStock: p.stockOnHand, disabledReason: (p.isBirdProduct || p.name === "Birds") ? "Bird stock comes from the birds left in your flocks — correct it in the flock / production records (record mortality, or edit the flock)." : undefined }))} setStock={setPoultryProductStock} onDone={load} />
              <Button variant="outline" className={TOOLBAR_BTN} onClick={handleExportPdf} disabled={loading}>
                <Download className="w-4 h-4 mr-1" /> Export PDF
              </Button>
              <Button variant="outline" className={TOOLBAR_BTN} onClick={handleExportCsv} disabled={loading}>
                <Download className="w-4 h-4 mr-1" /> Export CSV
              </Button>
              <Button className={TOOLBAR_BTN} onClick={() => setOpen(true)}><Plus className="w-4 h-4 mr-1" /> New movement</Button>
            </div>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <>
              <div className="mb-3"><ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search item, source or note" extras={<>
                <Select value={itemFilter} onValueChange={setItemFilter}>
                  <SelectTrigger className="w-full sm:w-[160px]"><SelectValue placeholder="All items" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All items</SelectItem>
                    {itemOptions.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Select value={parentTypeFilter} onValueChange={setParentTypeFilter}>
                  <SelectTrigger className="w-full sm:w-[150px]"><SelectValue placeholder="All types" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All types</SelectItem>
                    {parentTypeOptions.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Select value={movementFilter} onValueChange={setMovementFilter}>
                  <SelectTrigger className="w-full sm:w-[150px]"><SelectValue placeholder="All movements" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All movements</SelectItem>
                    {movementOptions.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                  </SelectContent>
                </Select>
              </>} /></div>
              <div className="hidden md:block overflow-x-auto"><Table className="min-w-[640px]">
                <TableHeader><TableRow>
                  {(() => { const onSort = (k: string) => setSort((s) => toggleSort(k, s.key, s.direction)); const cs = sort.key, cd = sort.direction; return (<>
                  <SortableHeader label="Date" sortKey="date" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Item" sortKey="item" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Parent Type" sortKey="parentType" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Movement" sortKey="movementType" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Qty" sortKey="qty" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                  <SortableHeader label="Unit Price" sortKey="unitCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                  <SortableHeader label="Total Value" sortKey="total" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                  <SortableHeader label="Source" sortKey="source" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Note" sortKey="note" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  </>) })()}
                </TableRow></TableHeader>
                <TableBody>
                  {sortedMoves.length === 0 ? <TableRow><TableCell colSpan={9} className="text-center text-slate-500 py-6">No stock movements yet.</TableCell></TableRow>
                    : pg.pageItems.map((m) => (
                      <TableRow key={m.key}>
                        <TableCell>{fmtDateTime(m.date, m)}</TableCell>
                        <TableCell className="font-medium">{m.item}</TableCell>
                        <TableCell><Badge className={m.parentType === "Finished Product" ? "bg-blue-100 text-blue-700" : "bg-slate-100 text-slate-700"}>{m.parentType}</Badge></TableCell>
                        <TableCell><Badge className={MOVE_COLORS[m.movementType] ?? "bg-gray-100"}>{m.movementType}</Badge></TableCell>
                        <TableCell className={`text-right ${m.qty < 0 ? "text-red-600" : "text-green-700"}`}>{m.qty > 0 ? "+" : ""}{m.qty.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{m.unitCost != null ? gh(m.unitCost) : "—"}</TableCell>
                        <TableCell className="text-right">{m.total != null ? gh(m.total) : "—"}</TableCell>
                        <TableCell className="text-slate-500">{m.source}</TableCell>
                        <TableCell className="text-slate-500">{m.note ?? "—"}</TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table></div>
              {/* Mobile cards */}
              <div className="md:hidden space-y-2">
                {sortedMoves.length === 0 ? <div className="text-center text-slate-500 py-6">No stock movements yet.</div>
                  : pg.pageItems.map((m) => (
                    <FieldCard key={m.key} title={m.item}
                      badge={<Badge className={MOVE_COLORS[m.movementType] ?? "bg-gray-100"}>{m.movementType}</Badge>}
                      fields={[["Date", fmtDateTime(m.date, m)], ["Type", m.parentType], ["Qty", <span className={m.qty < 0 ? "text-red-600" : "text-green-700"}>{m.qty > 0 ? "+" : ""}{m.qty.toLocaleString()}</span>], ["Unit price", m.unitCost != null ? gh(m.unitCost) : "—"], ["Total", m.total != null ? gh(m.total) : "—"], ["Source", m.source]]} />
                  ))}
              </div>
              {/* Sits after BOTH lists, so it reads as "below the table" in either
                  layout — it used to render between them, which put it above
                  the cards on a phone. */}
              <DataPagination {...pg.paginationProps} /></>
            )}
          </CardContent></Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>New stock movement</DialogTitle></DialogHeader>
          <FormSection title="Movement" color="blue">
            <FormField label="Item *">
              <Select value={form.target} onValueChange={(v) => setForm({ ...form, target: v, batchId: "", flockId: "" })}>
                <SelectTrigger><SelectValue placeholder="Pick a finished product, raw material or supply" /></SelectTrigger>
                <SelectContent>
                  {products.filter((p) => p.isActive).length > 0 && (
                    <SelectGroup>
                      <SelectLabel>Finished products</SelectLabel>
                      {products.filter((p) => p.isActive).map((p) => <SelectItem key={`p${p.poultryProductId}`} value={`p:${p.poultryProductId}`}>{p.name}</SelectItem>)}
                    </SelectGroup>
                  )}
                  {rawItems.filter((i) => i.isActive).length > 0 && (
                    <SelectGroup>
                      <SelectLabel>Raw materials &amp; supplies</SelectLabel>
                      {rawItems.filter((i) => i.isActive).map((i) => (
                        <SelectItem key={`r${i.poultryRawMaterialItemId}`} value={`r:${i.poultryRawMaterialItemId}`}>
                          {i.itemName}{i.category ? ` — ${i.category}` : ""}
                        </SelectItem>
                      ))}
                    </SelectGroup>
                  )}
                </SelectContent>
              </Select>
            </FormField>
            {birdTarget && (
              <>
                <FormField label="Batch *" hint="Birds are counted per flock. Pick the batch, then the flock.">
                  <Select value={form.batchId} onValueChange={(v) => setForm({ ...form, batchId: v, flockId: "" })}>
                    <SelectTrigger><SelectValue placeholder={birdOptions ? "Choose the batch" : "Loading batches..."} /></SelectTrigger>
                    <SelectContent>
                      {birdBatches.map((b) => (
                        <SelectItem key={b.batchId} value={String(b.batchId)}>
                          {b.batchCode}{b.batchName ? ` — ${b.batchName}` : ""}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Flock *">
                  <Select value={form.flockId} onValueChange={(v) => setForm({ ...form, flockId: v })} disabled={!form.batchId}>
                    <SelectTrigger><SelectValue placeholder={form.batchId ? "Choose the flock" : "Choose the batch first"} /></SelectTrigger>
                    <SelectContent>
                      {batchFlocks.map((f) => {
                        const why = f.isClosed ? "closed" : !f.hasProductionRecord ? "no production record yet" : null
                        return (
                          <SelectItem key={f.flockId!} value={String(f.flockId)} disabled={!!why}>
                            {f.flockName} · {why ?? `${(f.liveBirds ?? 0).toLocaleString()} birds`}
                          </SelectItem>
                        )
                      })}
                      {pickedBatch && (
                        <SelectItem value={UNPLACED}>
                          Not placed in a flock · {pickedBatch.unplacedBirds.toLocaleString()} birds
                        </SelectItem>
                      )}
                    </SelectContent>
                  </Select>
                </FormField>
                {birdsNow != null && (
                  <p className="text-sm text-slate-600 sm:col-span-2">
                    {form.flockId === UNPLACED ? "Birds of this batch not in any flock" : `Birds in ${pickedFlock?.flockName ?? "this flock"}`}:{" "}
                    <span className="font-medium">{birdsNow.toLocaleString()}</span>
                    {birdsAfter != null && form.quantity > 0 && (
                      <> → <span className={birdsAfter < 0 ? "font-semibold text-red-600" : "font-semibold"}>{birdsAfter.toLocaleString()}</span></>
                    )}
                  </p>
                )}
                {pickedFlock && (
                  <p className="text-xs text-slate-500 sm:col-span-2">
                    The flock&apos;s latest production record{pickedFlock.lastCountDate ? ` (${pickedFlock.lastCountDate.slice(0, 10)})` : ""} takes the corrected count, so the next record starts from it.
                  </p>
                )}
              </>
            )}
            <FormField label="Movement type">
              <Select value={form.movementType} onValueChange={(v) => setForm({ ...form, movementType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{MOVEMENTS.map((m) => <SelectItem key={m.value} value={m.value}>{m.value}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label={birdTarget ? "Birds" : "Quantity"} hint="Always enter a positive number; the movement type sets the direction."><NumberInput min={0} step={birdTarget ? "1" : "0.001"} value={form.quantity} onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) || 0 })} /></FormField>
            {!birdTarget && <FormField label="Unit cost / value"><NumberInput min={0} step="0.01" value={form.unitCost} onChange={(e) => setForm({ ...form, unitCost: Number(e.target.value) || 0 })} /></FormField>}
            <FormField label="Note" full><Input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>

    </div>
  )
}

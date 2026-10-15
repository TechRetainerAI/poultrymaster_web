"use client"

import { STOCK_REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Badge } from "@/components/ui/badge"
import { FieldCard } from "@/components/ui/field-card"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Plus, Loader2, Download, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useCurrency, useFmt } from "@/lib/currency"
import {
  listPoultryProducts, listPoultryStockTransactions,
  listPoultryRawMaterialPurchases, listPoultryRawMaterialUsageHistory,
  listPoultryRawMaterialItems, listPoultryRawMaterialAdjustments,
  setPoultryProductStock, reconcilePoultryProductStock,
  listPoultryManualMovements, reversePoultryManualMovement,
  type PoultryProduct, type PoultryStockTransaction, type PoultryRawMaterialItem, type PoultryManualMovement,
} from "@/lib/api/poultry-inventory"
import { ManualStockMovementDialog } from "@/components/poultry/manual-stock-movement-dialog"
import { usePermissions } from "@/hooks/use-permissions"
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
// 373: the movement types now live in ManualStockMovementDialog.
const MOVE_COLORS: Record<string, string> = {
  Increase: "bg-green-100 text-green-700", Restock: "bg-green-100 text-green-700", Production: "bg-emerald-100 text-emerald-700",
  Adjustment: "bg-slate-100 text-slate-700", Adjust: "bg-slate-100 text-slate-700",
  Decrease: "bg-amber-100 text-amber-700", Sale: "bg-blue-100 text-blue-700", Return: "bg-amber-100 text-amber-700",
  "Damage/Loss": "bg-red-100 text-red-700", "Delivery Load": "bg-indigo-100 text-indigo-700", "Delivery Return": "bg-amber-100 text-amber-700",
  "Bird Adjustment": "bg-violet-100 text-violet-700",
  "Sale Reversal": "bg-sky-100 text-sky-800", "Bird Sale": "bg-blue-100 text-blue-700",
  "Sorting In": "bg-teal-100 text-teal-800", "Sorting Out": "bg-orange-100 text-orange-800", "Sorting Reversal": "bg-slate-200 text-slate-800",
  "Egg Loss": "bg-red-100 text-red-700", "Internal Use": "bg-amber-100 text-amber-800", Opening: "bg-slate-200 text-slate-800",
  // 372: byproduct stock (Broken Eggs / Dead Birds)
  "Broken Egg Prod": "bg-rose-100 text-rose-800", "Broken Egg Disposal": "bg-stone-200 text-stone-800",
  "Mortality In": "bg-rose-100 text-rose-800", "Mortality Disposal": "bg-stone-200 text-stone-800",
  "Sorting Breakage": "bg-rose-100 text-rose-800",
  // 373: manual movements
  Disposal: "bg-stone-200 text-stone-800", "Breakage In": "bg-rose-100 text-rose-800",
  "Hist Mortality In": "bg-rose-100 text-rose-800", "Hist Mortality Disp": "bg-stone-200 text-stone-800",
  Reversal: "bg-slate-200 text-slate-800",
}
// Any movement type not listed above: dark text on grey. The Badge's own
// default text is white, so a background-only fallback was unreadable.
const MOVE_COLOR_FALLBACK = "bg-slate-200 text-slate-800"

type Move = {
  key: string; date: string; item: string; parentType: string; movementType: string; qty: number; unitCost: number | null; total: number | null; source: string; note: string | null
  // 373: provenance; set on manual movements (and the byproducts they made)
  batchFlock: string; reason: string | null; manualMovementId: number | null; isReversal: boolean
}
const batchFlockLabel = (batch?: string | null, flock?: string | null) => [batch, flock].filter(Boolean).join(" / ")

function sourceFor(txnType: string, relatedId?: number | null): string {
  if (txnType === "Production") return "Production Record"
  // 372: byproducts generated (and disposed immediately) by a production record / egg sorting
  if (txnType === "Broken Egg Prod" || txnType === "Mortality In") return "Production Record"
  if (txnType === "Broken Egg Disposal" || txnType === "Mortality Disposal") return "Production Record (disposed immediately)"
  if (txnType === "Sorting Breakage") return "Egg Sorting"
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
  // 373: manual movements (MSM-00001), for their provenance and reversal.
  const [manual, setManual] = useState<PoultryManualMovement[]>([])
  const { isAdmin } = usePermissions()
  const [reverseTarget, setReverseTarget] = useState<PoultryManualMovement | null>(null)
  const [reverseReason, setReverseReason] = useState("")
  const [reversing, setReversing] = useState(false)

  // List filters + column sort.
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [parentTypeFilter, setParentTypeFilter] = useState("all")
  const [movementFilter, setMovementFilter] = useState("all")
  const [itemFilter, setItemFilter] = useState("all")
  const [flockFilter, setFlockFilter] = useState("all")
  const [reasonFilter, setReasonFilter] = useState("all")
  const [sort, setSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [ps, items, ts, purch, usage, adjust, mm] = await Promise.all([
        listPoultryProducts(), listPoultryRawMaterialItems().catch(() => []), listPoultryStockTransactions(),
        listPoultryRawMaterialPurchases().catch(() => []), listPoultryRawMaterialUsageHistory().catch(() => []),
        listPoultryRawMaterialAdjustments().catch(() => []), listPoultryManualMovements().catch(() => []),
      ])
      setProducts(ps); setRawItems(items); setTxns(ts); setManual(mm)
      const NO_PROV = { batchFlock: "", reason: null, manualMovementId: null, isReversal: false }
      // A raw-material adjustment made by a manual movement: its header.
      const rawHeader = new Map(mm.filter((m) => m.rawAdjustmentId != null).map((m) => [m.rawAdjustmentId!, m]))
      const rm: Move[] = [
        ...purch.map((p) => ({ key: `rp${p.poultryRawMaterialPurchaseId}`, date: p.purchaseDate, item: p.itemName ?? "", parentType: "Raw Material", movementType: "Increase", qty: p.quantity, unitCost: p.unitCost, total: p.totalCost, source: "Raw Material Purchase", note: p.notes ?? null, ...NO_PROV })),
        ...usage.map((u) => ({ key: `ru${u.poultryRawMaterialUsageId}`, date: u.usedDate, item: u.itemName ?? "", parentType: "Raw Material", movementType: "Decrease", qty: -Math.abs(u.quantityUsed), unitCost: null, total: null, source: "Production Usage", note: u.varianceReason ?? null, ...NO_PROV })),
        ...adjust.map((a) => {
          const h = rawHeader.get(a.poultryRawMaterialAdjustmentId)
          return {
            key: `ra${a.poultryRawMaterialAdjustmentId}`, date: a.adjustedDate, item: a.itemName ?? "", parentType: a.category === "Supplies" ? "Supplies" : "Raw Material", movementType: a.movementType || (a.quantity >= 0 ? "Increase" : "Decrease"), qty: a.quantity, unitCost: a.unitCost ?? null, total: a.unitCost != null ? Number((a.unitCost * Math.abs(a.quantity)).toFixed(2)) : null,
            source: h ? `Manual movement ${h.movementNo}` : a.movementType === "Reversal" ? "Manual movement reversal" : "Manual Adjustment", note: a.note ?? null,
            batchFlock: "", reason: h?.reason ?? (a.movementType === "Reversal" ? "Reversal" : null), manualMovementId: h?.movementId ?? null, isReversal: a.movementType === "Reversal",
          }
        }),
      ]
      setRawMoves(rm)
    } catch (e: any) { toast({ title: "Could not load stock", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const manualById = useMemo(() => new Map(manual.map((m) => [m.movementId, m])), [manual])
  const moves: Move[] = useMemo(() => {
    const prod: Move[] = txns.map((t) => ({
      key: `pt${t.poultryStockTransactionId}`, date: t.createdDate, item: t.productName ?? "", parentType: "Finished Product",
      movementType: t.txnType, qty: t.quantity, unitCost: t.unitCost ?? null,
      total: t.unitCost != null ? Number((t.unitCost * Math.abs(t.quantity)).toFixed(2)) : null,
      source: t.manualMovementId != null
        ? `${t.manualReversal ? "Reversal of " : "Manual movement "}${manualById.get(t.manualMovementId)?.movementNo ?? ""}`.trim()
        : sourceFor(t.txnType, t.relatedId),
      note: t.note ?? null,
      batchFlock: batchFlockLabel(t.batchCode, t.flockName), reason: t.reason ?? null,
      manualMovementId: t.manualMovementId ?? null, isReversal: !!t.manualReversal,
    }))
    return [...prod, ...rawMoves].sort((a, b) => (b.date || "").localeCompare(a.date || ""))
  }, [txns, rawMoves, manualById])

  const parentTypeOptions = useMemo(() => Array.from(new Set(moves.map((m) => m.parentType).filter(Boolean))).sort(), [moves])
  const movementOptions = useMemo(() => Array.from(new Set(moves.map((m) => m.movementType).filter(Boolean))).sort(), [moves])
  const itemOptions = useMemo(() => Array.from(new Set(moves.map((m) => m.item).filter(Boolean))).sort(), [moves])
  const flockOptions = useMemo(() => Array.from(new Set(moves.map((m) => m.batchFlock).filter(Boolean))).sort(), [moves])
  const reasonOptions = useMemo(() => Array.from(new Set(moves.map((m) => m.reason ?? "").filter(Boolean))).sort(), [moves])

  const filteredMoves = useMemo(() => {
    let rows = filterByDateAndSearch(moves, { search, dateFrom, dateTo, searchKeys: ["item", "source", "note"], dateKey: "date" })
    if (itemFilter !== "all") rows = rows.filter((m) => m.item === itemFilter)
    if (parentTypeFilter !== "all") rows = rows.filter((m) => m.parentType === parentTypeFilter)
    if (movementFilter !== "all") rows = rows.filter((m) => m.movementType === movementFilter)
    if (flockFilter !== "all") rows = rows.filter((m) => m.batchFlock === flockFilter)
    if (reasonFilter !== "all") rows = rows.filter((m) => m.reason === reasonFilter)
    return rows
  }, [moves, search, dateFrom, dateTo, itemFilter, parentTypeFilter, movementFilter, flockFilter, reasonFilter])

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
      flockFilter !== "all" ? { label: "Batch / flock", value: flockFilter } : null,
      reasonFilter !== "all" ? { label: "Reason", value: reasonFilter } : null,
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
        { header: "Batch / Flock" },
        { header: "Reason" },
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
        m.batchFlock || "—",
        m.reason ?? "—",
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

  // ------------------------------------------------------- 373 reversal
  async function reverse() {
    if (!reverseTarget) return
    if (!reverseReason.trim()) { toast({ title: "Say why it is being reversed", variant: "destructive" }); return }
    setReversing(true)
    try {
      await reversePoultryManualMovement(reverseTarget.movementId, reverseReason.trim())
      toast({ title: `${reverseTarget.movementNo} reversed` })
      setReverseTarget(null); setReverseReason(""); await load()
    } catch (e: any) { toast({ title: "Could not reverse", description: e?.message, variant: "destructive" }) }
    finally { setReversing(false) }
  }
  /** The Reverse action for a row of a posted manual movement (owner / admin). */
  const reverseButton = (m: Move) => {
    const h = m.manualMovementId != null && !m.isReversal ? manualById.get(m.manualMovementId) : undefined
    if (!isAdmin || !h || h.status !== "Posted") return null
    return (
      <Button variant="ghost" size="sm" title={`Reverse ${h.movementNo}`} onClick={() => { setReverseTarget(h); setReverseReason("") }}>
        <Undo2 className="w-4 h-4 text-slate-600" />
      </Button>
    )
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
                {flockOptions.length > 0 && (
                  <Select value={flockFilter} onValueChange={setFlockFilter}>
                    <SelectTrigger className="w-full sm:w-[170px]"><SelectValue placeholder="All batches / flocks" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All batches / flocks</SelectItem>
                      {flockOptions.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                    </SelectContent>
                  </Select>
                )}
                {reasonOptions.length > 0 && (
                  <Select value={reasonFilter} onValueChange={setReasonFilter}>
                    <SelectTrigger className="w-full sm:w-[170px]"><SelectValue placeholder="All reasons" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All reasons</SelectItem>
                      {reasonOptions.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                    </SelectContent>
                  </Select>
                )}
              </>} /></div>
              <div className="hidden md:block overflow-x-auto"><Table className="min-w-[900px]">
                <TableHeader><TableRow>
                  {(() => { const onSort = (k: string) => setSort((s) => toggleSort(k, s.key, s.direction)); const cs = sort.key, cd = sort.direction; return (<>
                  <SortableHeader label="Date" sortKey="date" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Item" sortKey="item" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Parent Type" sortKey="parentType" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Movement" sortKey="movementType" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Batch / Flock" sortKey="batchFlock" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Reason" sortKey="reason" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Qty" sortKey="qty" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                  <SortableHeader label="Unit Price" sortKey="unitCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                  <SortableHeader label="Total Value" sortKey="total" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                  <SortableHeader label="Source" sortKey="source" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <SortableHeader label="Note" sortKey="note" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  <TableHead className="w-10" />
                  </>) })()}
                </TableRow></TableHeader>
                <TableBody>
                  {sortedMoves.length === 0 ? <TableRow><TableCell colSpan={12} className="text-center text-slate-500 py-6">No stock movements yet.</TableCell></TableRow>
                    : pg.pageItems.map((m) => (
                      <TableRow key={m.key}>
                        <TableCell>{fmtDateTime(m.date, m)}</TableCell>
                        <TableCell className="font-medium">{m.item}</TableCell>
                        <TableCell><Badge className={m.parentType === "Finished Product" ? "bg-blue-100 text-blue-700" : "bg-slate-100 text-slate-700"}>{m.parentType}</Badge></TableCell>
                        <TableCell><Badge className={MOVE_COLORS[m.movementType] ?? MOVE_COLOR_FALLBACK}>{m.movementType}</Badge></TableCell>
                        <TableCell className="text-slate-600">{m.batchFlock || "—"}</TableCell>
                        <TableCell className="text-slate-600">{m.reason ?? "—"}</TableCell>
                        <TableCell className={`text-right ${m.qty < 0 ? "text-red-600" : "text-green-700"}`}>{m.qty > 0 ? "+" : ""}{m.qty.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{m.unitCost != null ? gh(m.unitCost) : "—"}</TableCell>
                        <TableCell className="text-right">{m.total != null ? gh(m.total) : "—"}</TableCell>
                        <TableCell className="text-slate-500">{m.source}</TableCell>
                        <TableCell className="text-slate-500">{m.note ?? "—"}</TableCell>
                        <TableCell className="text-right">{reverseButton(m)}</TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table></div>
              {/* Mobile cards */}
              <div className="md:hidden space-y-2">
                {sortedMoves.length === 0 ? <div className="text-center text-slate-500 py-6">No stock movements yet.</div>
                  : pg.pageItems.map((m) => (
                    <FieldCard key={m.key} title={m.item}
                      badge={<Badge className={MOVE_COLORS[m.movementType] ?? MOVE_COLOR_FALLBACK}>{m.movementType}</Badge>}
                      fields={[["Date", fmtDateTime(m.date, m)], ["Type", m.parentType], ["Qty", <span className={m.qty < 0 ? "text-red-600" : "text-green-700"}>{m.qty > 0 ? "+" : ""}{m.qty.toLocaleString()}</span>], ["Unit price", m.unitCost != null ? gh(m.unitCost) : "—"], ["Total", m.total != null ? gh(m.total) : "—"], ["Source", m.source],
                        ...(m.batchFlock ? [["Batch / Flock", m.batchFlock] as [string, string]] : []), ...(m.reason ? [["Reason", m.reason] as [string, string]] : [])]}
                      actions={reverseButton(m)} />
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

      <ManualStockMovementDialog open={open} onOpenChange={setOpen} products={products} rawItems={rawItems} onSaved={load} />

      {/* 373: reversal appends the opposite; the original stays in the list. */}
      <Dialog open={!!reverseTarget} onOpenChange={(o) => { if (!o) setReverseTarget(null) }}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Reverse {reverseTarget?.movementNo}</DialogTitle></DialogHeader>
          {reverseTarget && (
            <div className="space-y-3 text-sm">
              <p className="text-slate-600">
                {reverseTarget.itemName}: {reverseTarget.quantity > 0 ? "+" : ""}{Number(reverseTarget.quantity).toLocaleString()}
                {" · "}{reverseTarget.reason}{" · "}{reverseTarget.effectiveDate.slice(0, 10)}
                {batchFlockLabel(reverseTarget.batchCode, reverseTarget.flockName) ? ` · ${batchFlockLabel(reverseTarget.batchCode, reverseTarget.flockName)}` : ""}
              </p>
              <p className="text-slate-500">
                The opposite is posted today and the original stays in the list.
                {reverseTarget.itemKind === "Birds" ? " The flock's count goes back, and any Dead Birds it made come off." : ""}
                {reverseTarget.convertedToBroken ? " The Broken Eggs it made come off." : ""}
              </p>
              <FormField label="Why *" full><ReasonSelect options={STOCK_REVERSAL_REASONS} value={reverseReason} onChange={setReverseReason} /></FormField>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setReverseTarget(null)}>Cancel</Button>
                <Button onClick={reverse} disabled={reversing}>{reversing ? <Loader2 className="w-4 h-4 animate-spin" /> : "Reverse"}</Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

    </div>
  )
}

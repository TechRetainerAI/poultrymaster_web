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
import { Plus, Loader2, RefreshCw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryProducts, listPoultryStockTransactions, addPoultryStockTransaction,
  listPoultryRawMaterialPurchases, listPoultryRawMaterialUsageHistory,
  listPoultryRawMaterialItems, listPoultryRawMaterialAdjustments, adjustPoultryRawMaterialItem,
  recalculatePoultryRawMaterialStock,
  type PoultryProduct, type PoultryStockTransaction, type PoultryRawMaterialItem, type PoultryRawMaterialRecalcRow,
} from "@/lib/api/poultry-inventory"

// Doc 5: movement types with sign. Positive = increase, negative = decrease.
const MOVEMENTS: { value: string; sign: 1 | -1 }[] = [
  { value: "Increase", sign: 1 }, { value: "Adjustment", sign: 1 },
  { value: "Decrease", sign: -1 }, { value: "Sale", sign: -1 }, { value: "Damage/Loss", sign: -1 },
]
const MOVE_COLORS: Record<string, string> = {
  Increase: "bg-green-100 text-green-700", Restock: "bg-green-100 text-green-700", Production: "bg-emerald-100 text-emerald-700",
  Adjustment: "bg-slate-100 text-slate-700", Adjust: "bg-slate-100 text-slate-700",
  Decrease: "bg-amber-100 text-amber-700", Sale: "bg-blue-100 text-blue-700", Return: "bg-amber-100 text-amber-700",
  "Damage/Loss": "bg-red-100 text-red-700", "Delivery Load": "bg-indigo-100 text-indigo-700", "Delivery Return": "bg-amber-100 text-amber-700",
}
type Move = { key: string; date: string; item: string; parentType: string; movementType: string; qty: number; unitCost: number | null; total: number | null; source: string; note: string | null }

function sourceFor(txnType: string, relatedId?: number | null): string {
  if (txnType === "Production") return "Production Record"
  if (txnType === "Sale") return "Sale"
  if (txnType === "Restock" || txnType === "Increase") return "Manual / Product Stock Entry"
  return "Stock Page"
}

export default function PoultryStockPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [rawItems, setRawItems] = useState<PoultryRawMaterialItem[]>([])
  const [txns, setTxns] = useState<PoultryStockTransaction[]>([])
  const [rawMoves, setRawMoves] = useState<Move[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  // Recalculate-stock confirm dialog + last result.
  const [recalcOpen, setRecalcOpen] = useState(false)
  const [recalcing, setRecalcing] = useState(false)
  const [recalcResult, setRecalcResult] = useState<PoultryRawMaterialRecalcRow[] | null>(null)
  // `target` encodes the picked item: "p:<id>" = finished product, "r:<id>" = raw material / supply.
  const [form, setForm] = useState({ target: "", movementType: "Increase", quantity: 0, unitCost: 0, note: "" })

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

  async function save() {
    if (!form.target) { toast({ title: "Pick an item", variant: "destructive" }); return }
    if (form.quantity <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    const mv = MOVEMENTS.find((m) => m.value === form.movementType)!
    const signed = mv.sign * Math.abs(form.quantity)
    const [kind, idStr] = form.target.split(":")
    const id = Number(idStr)
    setSaving(true)
    try {
      if (kind === "r") {
        // Raw material / supply — adjust its stock directly (no expense/usage side effects).
        await adjustPoultryRawMaterialItem(id, { quantity: signed, unitCost: form.unitCost || null, movementType: form.movementType, note: form.note || "Manual stock adjustment" })
      } else {
        await addPoultryStockTransaction({ poultryProductId: id, txnType: form.movementType, quantity: signed, unitCost: form.unitCost || null, note: form.note || "Manual stock entry" })
      }
      toast({ title: "Stock movement added" }); setOpen(false); setForm({ target: "", movementType: "Increase", quantity: 0, unitCost: 0, note: "" }); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function recalcStock() {
    setRecalcing(true)
    try {
      const rows = await recalculatePoultryRawMaterialStock()
      const changed = rows.filter((r) => Number(r.delta) !== 0)
      setRecalcResult(changed)
      toast({ title: "Stock recalculated", description: `${rows.length} item(s) checked, ${changed.length} updated.` })
      await load()
    } catch (e: any) { toast({ title: "Recalculate failed", description: e?.message, variant: "destructive" }) }
    finally { setRecalcing(false) }
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold">Stock Movements</h1><p className="text-sm text-slate-500">All stock increases and decreases — finished products and raw materials. Production, sales, purchases and manual entries.</p></div>
            <div className="flex items-center gap-2">
              <Button variant="outline" onClick={() => { setRecalcResult(null); setRecalcOpen(true) }} title="Recompute raw-material stock from purchases, usage and adjustments">
                <RefreshCw className="w-4 h-4 mr-1" /> Recalculate stock
              </Button>
              <Button onClick={() => setOpen(true)}><Plus className="w-4 h-4 mr-1" /> New movement</Button>
            </div>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <>
              <div className="mb-3"><ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search item, source or note" extras={<>
                <Select value={itemFilter} onValueChange={setItemFilter}>
                  <SelectTrigger className="w-[160px]"><SelectValue placeholder="All items" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All items</SelectItem>
                    {itemOptions.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Select value={parentTypeFilter} onValueChange={setParentTypeFilter}>
                  <SelectTrigger className="w-[150px]"><SelectValue placeholder="All types" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All types</SelectItem>
                    {parentTypeOptions.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Select value={movementFilter} onValueChange={setMovementFilter}>
                  <SelectTrigger className="w-[150px]"><SelectValue placeholder="All movements" /></SelectTrigger>
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
                    : sortedMoves.map((m) => (
                      <TableRow key={m.key}>
                        <TableCell>{(m.date || "").split("T")[0]}</TableCell>
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
                  : sortedMoves.map((m) => (
                    <FieldCard key={m.key} title={m.item}
                      badge={<Badge className={MOVE_COLORS[m.movementType] ?? "bg-gray-100"}>{m.movementType}</Badge>}
                      fields={[["Date", (m.date || "").split("T")[0]], ["Type", m.parentType], ["Qty", <span className={m.qty < 0 ? "text-red-600" : "text-green-700"}>{m.qty > 0 ? "+" : ""}{m.qty.toLocaleString()}</span>], ["Unit price", m.unitCost != null ? gh(m.unitCost) : "—"], ["Total", m.total != null ? gh(m.total) : "—"], ["Source", m.source]]} />
                  ))}
              </div></>
            )}
          </CardContent></Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>New stock movement</DialogTitle></DialogHeader>
          <FormSection title="Movement" color="blue">
            <FormField label="Item *">
              <Select value={form.target} onValueChange={(v) => setForm({ ...form, target: v })}>
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
            <FormField label="Movement type">
              <Select value={form.movementType} onValueChange={(v) => setForm({ ...form, movementType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{MOVEMENTS.map((m) => <SelectItem key={m.value} value={m.value}>{m.value}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity" hint="Always enter a positive number; the movement type sets the direction."><NumberInput min={0} step="0.001" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Unit cost / value"><NumberInput min={0} step="0.01" value={form.unitCost} onChange={(e) => setForm({ ...form, unitCost: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Note" full><Input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Recalculate raw-material stock — confirm, then show what changed. */}
      <Dialog open={recalcOpen} onOpenChange={setRecalcOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Recalculate raw-material stock</DialogTitle></DialogHeader>
          {recalcResult === null ? (
            <div className="space-y-3">
              <p className="text-sm text-slate-600">
                This recomputes each raw material and supply's current stock from its history —
                <span className="font-medium"> total purchased (in production units) − used in production + manual adjustments</span>.
                Finished products are not affected. Use this if a raw-material stock figure looks wrong.
              </p>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setRecalcOpen(false)}>Cancel</Button>
                <Button onClick={recalcStock} disabled={recalcing}>{recalcing ? <Loader2 className="w-4 h-4 animate-spin" /> : "Recalculate"}</Button>
              </div>
            </div>
          ) : (
            <div className="space-y-3">
              {recalcResult.length === 0 ? (
                <p className="text-sm text-slate-600">Everything already matched — no stock figures needed changing.</p>
              ) : (
                <>
                  <p className="text-sm text-slate-600">{recalcResult.length} item(s) updated:</p>
                  <div className="max-h-72 overflow-y-auto rounded border">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Item</TableHead>
                        <TableHead className="text-right">Was</TableHead>
                        <TableHead className="text-right">Now</TableHead>
                        <TableHead className="text-right">Change</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {recalcResult.map((r) => (
                          <TableRow key={r.poultryRawMaterialItemId}>
                            <TableCell className="font-medium">{r.itemName}{r.category ? <span className="text-slate-400"> — {r.category}</span> : null}</TableCell>
                            <TableCell className="text-right">{Number(r.oldQuantity).toLocaleString()}</TableCell>
                            <TableCell className="text-right">{Number(r.newQuantity).toLocaleString()}</TableCell>
                            <TableCell className={`text-right ${Number(r.delta) < 0 ? "text-red-600" : "text-green-700"}`}>{Number(r.delta) > 0 ? "+" : ""}{Number(r.delta).toLocaleString()}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                </>
              )}
              <div className="flex justify-end"><Button onClick={() => setRecalcOpen(false)}>Done</Button></div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

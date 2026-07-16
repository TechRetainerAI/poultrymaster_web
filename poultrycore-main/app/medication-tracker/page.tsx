"use client"

// Medication Tracker — rebuilt to mirror the Feed tracker but PER MEDICATION.
// Each medication is a raw-material item (category "Medication"); its IN comes
// from raw-material purchases, its OUT from production usage, and "quantity
// left" is the item's live currentQuantity — exactly what the Raw Materials &
// Supplies page tracks. Every medication is treated separately: the by-med
// table shows each one's stock, and the ledger runs a per-medication balance.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Pill, RefreshCw, Loader2, AlertTriangle, Boxes } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import {
  listPoultryRawMaterialItems, listPoultryRawMaterialPurchases, listPoultryRawMaterialUsageHistory,
  type PoultryRawMaterialItem, type PoultryRawMaterialPurchase, type PoultryRawMaterialUsage,
} from "@/lib/api/poultry-inventory"

const LEDGER_PAGE_SIZE = 15

// One IN or OUT event for a single medication, with the running per-med balance.
type LedgerRow = {
  key: string; itemId: number; medication: string; unit: string
  date: string; type: "Purchase" | "Usage"; source: string
  inQty: number; outQty: number; balance: number
}

export default function MedicationTrackerPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [purchases, setPurchases] = useState<PoultryRawMaterialPurchase[]>([])
  const [usage, setUsage] = useState<PoultryRawMaterialUsage[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  // By-medication table sort.
  const [byMedSort, setByMedSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })

  // Ledger filters + sort + pagination.
  const [medFilter, setMedFilter] = useState("all")
  const [typeFilter, setTypeFilter] = useState("all")
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [sort, setSort] = useState<{ key: string | null; direction: SortDirection }>({ key: "date", direction: "desc" })
  const [page, setPage] = useState(1)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [its, ps, us] = await Promise.all([
        listPoultryRawMaterialItems(),
        listPoultryRawMaterialPurchases().catch(() => []),
        listPoultryRawMaterialUsageHistory().catch(() => []),
      ])
      setItems(its); setPurchases(ps as PoultryRawMaterialPurchase[]); setUsage(us as PoultryRawMaterialUsage[])
    } catch (e: any) {
      toast({ title: "Could not load medications", description: e?.message, variant: "destructive" })
    } finally { setLoading(false); setRefreshing(false) }
  }

  function refresh() { setRefreshing(true); void load() }

  // Medications = raw-material items in the Medication category.
  const meds = useMemo(() => items.filter((i) => i.category === "Medication"), [items])

  // Per-medication ledger: purchases (IN) + usage (OUT), sorted by date, with a
  // running balance kept SEPARATELY for each medication.
  const allLedger = useMemo<LedgerRow[]>(() => {
    const rows: LedgerRow[] = []
    for (const m of meds) {
      const events = [
        ...purchases.filter((p) => p.poultryRawMaterialItemId === m.poultryRawMaterialItemId).map((p) => ({
          date: p.purchaseDate, type: "Purchase" as const,
          source: p.supplierName ? `Purchase — ${p.supplierName}` : "Purchase",
          inQty: p.quantity, outQty: 0, key: `p${p.poultryRawMaterialPurchaseId}`,
        })),
        ...usage.filter((u) => u.poultryRawMaterialItemId === m.poultryRawMaterialItemId).map((u) => ({
          date: u.usedDate, type: "Usage" as const,
          source: u.varianceReason ? `Production usage — ${u.varianceReason}` : "Production usage",
          inQty: 0, outQty: Math.abs(u.quantityUsed), key: `u${u.poultryRawMaterialUsageId}`,
        })),
      ].sort((a, b) => (a.date || "").localeCompare(b.date || ""))
      let run = 0
      for (const e of events) {
        run += e.inQty - e.outQty
        rows.push({ key: e.key, itemId: m.poultryRawMaterialItemId, medication: m.itemName, unit: m.unitOfMeasure ?? "", date: e.date, type: e.type, source: e.source, inQty: e.inQty, outQty: e.outQty, balance: run })
      }
    }
    return rows
  }, [meds, purchases, usage])

  // Per-medication summary (quantity left is the item's authoritative stock).
  const byMed = useMemo(() => meds.map((m) => {
    const totalIn = purchases.filter((p) => p.poultryRawMaterialItemId === m.poultryRawMaterialItemId).reduce((s, p) => s + (p.quantity || 0), 0)
    const totalOut = usage.filter((u) => u.poultryRawMaterialItemId === m.poultryRawMaterialItemId).reduce((s, u) => s + Math.abs(u.quantityUsed || 0), 0)
    const left = m.currentQuantity
    return {
      id: m.poultryRawMaterialItemId, name: m.itemName, unit: m.unitOfMeasure ?? "—",
      totalIn, totalOut, left, minAlert: m.minimumStockAlert, isActive: m.isActive,
      isLow: m.isLowStock ?? (left <= m.minimumStockAlert),
      status: !m.isActive ? "Inactive" : left <= 0 ? "Finished" : (m.isLowStock ?? (left <= m.minimumStockAlert)) ? "Low" : "In stock",
    }
  }), [meds, purchases, usage])

  const sortedByMed = useMemo(() => sortData(byMed, byMedSort.key, byMedSort.direction), [byMed, byMedSort])

  const stats = useMemo(() => ({
    count: meds.length,
    low: byMed.filter((b) => b.isActive && b.status === "Low").length,
    finished: byMed.filter((b) => b.isActive && b.status === "Finished").length,
  }), [meds, byMed])

  // Ledger: filter by medication + type + search/date, then sort + paginate.
  const filteredLedger = useMemo(() => {
    let rows = allLedger
    if (medFilter !== "all") rows = rows.filter((r) => String(r.itemId) === medFilter)
    if (typeFilter !== "all") rows = rows.filter((r) => r.type === typeFilter)
    return filterByDateAndSearch(rows, { search, dateFrom, dateTo, searchKeys: ["medication", "source"], dateKey: "date" })
  }, [allLedger, medFilter, typeFilter, search, dateFrom, dateTo])

  const sortedLedger = useMemo(() => sortData(filteredLedger, sort.key, sort.direction, (r: LedgerRow, k: string) => {
    if (k === "date") return new Date(r.date)
    if (k === "in") return r.inQty
    if (k === "out") return r.outQty
    return (r as any)[k]
  }), [filteredLedger, sort])

  const totalPages = Math.max(1, Math.ceil(sortedLedger.length / LEDGER_PAGE_SIZE))
  const safePage = Math.min(page, totalPages)
  const pageRows = useMemo(() => sortedLedger.slice((safePage - 1) * LEDGER_PAGE_SIZE, safePage * LEDGER_PAGE_SIZE), [sortedLedger, safePage])
  useEffect(() => { setPage(1) }, [medFilter, typeFilter, search, dateFrom, dateTo, sort])

  const onSort = (k: string) => setSort((s) => toggleSort(k, s.key, s.direction))
  const onByMedSort = (k: string) => setByMedSort((s) => toggleSort(k, s.key, s.direction))
  const fmt = (n: number) => n.toLocaleString(undefined, { maximumFractionDigits: 2 })

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 bg-violet-100 rounded-lg flex items-center justify-center"><Pill className="w-5 h-5 text-violet-800" /></div>
              <div className="min-w-0">
                <h1 className="text-2xl font-bold text-slate-900">Medication Tracker</h1>
                <p className="text-sm text-slate-500">Each medication tracked separately — purchases in, production usage out, and the quantity left for each. Same source as Raw Materials &amp; Supplies.</p>
              </div>
            </div>
            <Button variant="outline" className="shrink-0 gap-2 self-start" onClick={refresh} disabled={refreshing || loading}>
              <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} /> Refresh
            </Button>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading medications…</div>
          ) : meds.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-slate-600">
              No medications yet. Add items with category <strong>Medication</strong> on the Raw Materials &amp; Supplies page, then record their purchases — usage appears automatically when medication is consumed in production.
            </CardContent></Card>
          ) : (
            <>
              {/* Summary */}
              <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide"><Boxes className="w-4 h-4 text-violet-600" /> Medications</div>
                  <div className="mt-1 text-2xl font-bold text-slate-900 tabular-nums">{stats.count.toLocaleString()}</div>
                </div>
                <div className={cn("p-4 rounded-xl border shadow-sm", stats.low > 0 ? "bg-amber-50 border-amber-200" : "bg-white border-slate-200")}>
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide"><AlertTriangle className={cn("w-4 h-4", stats.low > 0 ? "text-amber-600" : "text-slate-400")} /> Low stock</div>
                  <div className={cn("mt-1 text-2xl font-bold tabular-nums", stats.low > 0 ? "text-amber-700" : "text-slate-900")}>{stats.low.toLocaleString()}</div>
                </div>
                <div className={cn("p-4 rounded-xl border shadow-sm", stats.finished > 0 ? "bg-red-50 border-red-200" : "bg-white border-slate-200")}>
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide"><AlertTriangle className={cn("w-4 h-4", stats.finished > 0 ? "text-red-600" : "text-slate-400")} /> Finished</div>
                  <div className={cn("mt-1 text-2xl font-bold tabular-nums", stats.finished > 0 ? "text-red-600" : "text-slate-900")}>{stats.finished.toLocaleString()}</div>
                </div>
              </div>

              {/* By medication */}
              <Card><CardHeader className="pb-2">
                <CardTitle className="text-base">By medication</CardTitle>
                <CardDescription>Quantity left, total in and total out for each medication. Each one stands on its own.</CardDescription>
              </CardHeader><CardContent>
                <div className="overflow-x-auto"><Table className="min-w-[560px]">
                  <TableHeader><TableRow>
                    {(() => { const cs = byMedSort.key, cd = byMedSort.direction; return (<>
                    <SortableHeader label="Medication" sortKey="name" currentSort={cs} currentDirection={cd} onSort={onByMedSort} />
                    <SortableHeader label="Unit" sortKey="unit" currentSort={cs} currentDirection={cd} onSort={onByMedSort} />
                    <SortableHeader label="Total In" sortKey="totalIn" currentSort={cs} currentDirection={cd} onSort={onByMedSort} className="text-right" />
                    <SortableHeader label="Total Out" sortKey="totalOut" currentSort={cs} currentDirection={cd} onSort={onByMedSort} className="text-right" />
                    <SortableHeader label="Quantity Left" sortKey="left" currentSort={cs} currentDirection={cd} onSort={onByMedSort} className="text-right" />
                    <SortableHeader label="Status" sortKey="status" currentSort={cs} currentDirection={cd} onSort={onByMedSort} className="text-right" />
                    </>) })()}
                  </TableRow></TableHeader>
                  <TableBody>
                    {sortedByMed.map((b) => (
                      <TableRow key={b.id} className="cursor-pointer hover:bg-slate-50" onClick={() => { setMedFilter(String(b.id)); document.getElementById("med-ledger")?.scrollIntoView({ behavior: "smooth" }) }}>
                        <TableCell className="font-medium text-slate-900">{b.name}</TableCell>
                        <TableCell className="text-slate-500">{b.unit}</TableCell>
                        <TableCell className="text-right text-emerald-700 tabular-nums">{fmt(b.totalIn)}</TableCell>
                        <TableCell className="text-right text-red-600 tabular-nums">{fmt(b.totalOut)}</TableCell>
                        <TableCell className={cn("text-right font-semibold tabular-nums", b.left <= 0 ? "text-red-600" : "")}>{fmt(b.left)} {b.unit !== "—" ? b.unit : ""}</TableCell>
                        <TableCell className="text-right">
                          {b.status === "Inactive" ? <Badge variant="secondary">Inactive</Badge>
                            : b.status === "Finished" ? <Badge className="bg-red-100 text-red-700">Finished</Badge>
                            : b.status === "Low" ? <Badge className="bg-amber-100 text-amber-700">Low stock</Badge>
                            : <Badge className="bg-green-100 text-green-700">In stock</Badge>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table></div>
              </CardContent></Card>

              {/* Ledger */}
              <Card id="med-ledger"><CardHeader className="pb-2">
                <CardTitle className="text-base">Ins &amp; Outs ledger</CardTitle>
                <CardDescription>History of every purchase (in) and production usage (out). The <strong>Balance</strong> is the running quantity left for that medication. Pick a medication to focus on just one.</CardDescription>
                <div className="pt-3"><ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search medication or source" extras={<>
                  <Select value={medFilter} onValueChange={setMedFilter}>
                    <SelectTrigger className="w-[180px]"><SelectValue placeholder="All medications" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All medications</SelectItem>
                      {meds.map((m) => <SelectItem key={m.poultryRawMaterialItemId} value={String(m.poultryRawMaterialItemId)}>{m.itemName}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Select value={typeFilter} onValueChange={setTypeFilter}>
                    <SelectTrigger className="w-[130px]"><SelectValue placeholder="All types" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All types</SelectItem>
                      <SelectItem value="Purchase">Purchase (in)</SelectItem>
                      <SelectItem value="Usage">Usage (out)</SelectItem>
                    </SelectContent>
                  </Select>
                </>} /></div>
              </CardHeader><CardContent className="pt-0">
                {sortedLedger.length === 0 ? (
                  <p className="text-slate-600 py-8 text-center text-sm">No movements match. Record a purchase on Raw Materials &amp; Supplies, or use this medication in production.</p>
                ) : (
                  <div className="overflow-x-auto"><Table className="min-w-[720px]">
                    <TableHeader><TableRow>
                      {(() => { const cs = sort.key, cd = sort.direction; return (<>
                      <SortableHeader label="Date" sortKey="date" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Medication" sortKey="medication" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Type" sortKey="type" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Source" sortKey="source" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="In" sortKey="in" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Out" sortKey="out" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Balance" sortKey="balance" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      </>) })()}
                    </TableRow></TableHeader>
                    <TableBody>
                      {pageRows.map((r) => (
                        <TableRow key={r.key}>
                          <TableCell className="whitespace-nowrap">{(r.date || "").split("T")[0]}</TableCell>
                          <TableCell className="font-medium">{r.medication}</TableCell>
                          <TableCell><Badge className={r.type === "Purchase" ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700"}>{r.type === "Purchase" ? "In" : "Out"}</Badge></TableCell>
                          <TableCell className="text-slate-500 max-w-[260px] truncate" title={r.source}>{r.source}</TableCell>
                          <TableCell className="text-right text-emerald-700 tabular-nums">{r.inQty > 0 ? fmt(r.inQty) : "—"}</TableCell>
                          <TableCell className="text-right text-red-600 tabular-nums">{r.outQty > 0 ? fmt(r.outQty) : "—"}</TableCell>
                          <TableCell className="text-right font-medium tabular-nums">{fmt(r.balance)} {r.unit}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                )}
                {sortedLedger.length > 0 && (
                  <div className="flex flex-col gap-2 border-t px-2 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-4 bg-slate-50/80 mt-2">
                    <p className="text-xs text-slate-600 text-center sm:text-left">Showing {(safePage - 1) * LEDGER_PAGE_SIZE + 1}-{Math.min(safePage * LEDGER_PAGE_SIZE, sortedLedger.length)} of {sortedLedger.length}</p>
                    <div className="flex items-center justify-center gap-2">
                      <Button variant="outline" size="sm" disabled={safePage <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>Previous</Button>
                      <span className="text-xs text-slate-600 whitespace-nowrap">Page {safePage} of {totalPages}</span>
                      <Button variant="outline" size="sm" disabled={safePage >= totalPages} onClick={() => setPage((p) => Math.min(totalPages, p + 1))}>Next</Button>
                    </div>
                  </div>
                )}
              </CardContent></Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

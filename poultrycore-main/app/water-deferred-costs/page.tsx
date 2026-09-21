"use client"

// Deferred Inventory Cost (Sales, Expenses & Money → Expenses → Deferred
// inventory cost). The water twin of /poultry-deferred-costs.
//
// The page that makes deferred stock value explainable. An owner arrives here
// from the Expenses menu, sees the purchases behind the number, expands one,
// and reads the individual production draws that moved its cost into the P&L.
//
// READ-ONLY, DELIBERATELY. Everything shown is derived from the cost layers and
// their allocations. There is no action here that could change a recognised
// figure, because recognition happens where consumption happens and a second
// way to set it would immediately disagree with the P&L.
//
// TWO NUMBERS THAT ARE NOT THE SAME, AND ARE NOT PRESENTED AS IF THEY WERE
// -----------------------------------------------------------------------
//   Original cost   what the stock cost. Real on every purchase.
//   Deferred basis  what of it was held back from the P&L. ZERO on a purchase
//                   that was expensed when it was bought.
// A purchase expensed at purchase therefore shows a large original cost and no
// deferred anything, which is correct and is why the deferred columns are
// visually muted rather than showing a bare 0.00 that reads like a mistake.
//
// WHAT IS NOT HERE, AND WHY
// -------------------------
// The poultry page carries a "produced lot" shape: a feed-production batch can
// CREATE a raw-material lot, so a row there can have a batch instead of a
// supplier. Water has no feed production and no produced lots -- every water lot
// is bought -- so none of that is mirrored rather than invented. The other way
// round, a water draw belongs to a PRODUCTION BATCH (sachets/bottles) where the
// poultry one belongs to a flock, which is what the Source column shows.

import { Fragment, Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DateRangeFilter } from "@/components/ui/date-range-filter"
import { MOBILE_FILTER_SELECT_CONTENT_CLASS } from "@/components/dashboard/mobile-filters"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import {
  ChevronDown, ChevronRight, Loader2, AlertTriangle, Hourglass,
  CheckCircle2, Receipt, Package, Download, ExternalLink, Clock,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { explainLoadFailure } from "@/lib/api/http-error"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  RECOGNITION_TONE_CLASS, deferredStatusTone,
  REMAINING_DEFERRED_TOOLTIP, RECOGNIZED_COST_TOOLTIP, OPERATIONAL_COST_TOOLTIP,
  NEWLY_RECOGNIZED_TOOLTIP, DEFERRED_EXCEPTION_TOOLTIP,
  DEFERRED_PAGE_INTRO, NO_SECOND_PAYMENT_TOOLTIP,
} from "@/lib/water/cost-recognition"
import {
  getWaterDeferredCosts, getWaterDeferredCostHistory,
  type WaterDeferredCostResponse, type WaterDeferredPurchase,
  type WaterDeferredRecognition, type WaterDeferredCostScope,
} from "@/lib/api/water-deferred-costs"
import { fmtDateTime } from "@/lib/utils/company-datetime"

// The stored category codes, spelled the way the raw-materials page spells
// them. Anything the server sends that is not in this map falls through as-is,
// so a category added later shows its own name rather than a blank.
const CATEGORY_LABELS: Record<string, string> = {
  PackagingRoll: "Packaging Roll",
  SachetFilm: "Sachet Film",
  OuterBag: "Outer Bag",
  UVLamp: "UV Lamp",
  SparePart: "Spare Part",
  CleaningSupply: "Cleaning Supply",
}
const categoryLabel = (c?: string | null) => (c ? CATEGORY_LABELS[c] ?? c : "—")

// The four views, in the order an owner works through them: what is waiting,
// what is done, what is wrong, everything.
const SCOPES: { value: WaterDeferredCostScope; label: string; hint: string }[] = [
  { value: "DEFERRED", label: "Still to expense", hint: "Purchases with cost still waiting to reach Profit & Loss" },
  { value: "RECOGNIZED", label: "Fully expensed", hint: "Purchases that were deferred and are now completely expensed" },
  { value: "EXCEPTION", label: "Needs checking", hint: "Purchases whose figures do not agree with their usages" },
  { value: "ALL", label: "All purchases", hint: "Every raw material purchase, however its cost was recognised" },
]

/**
 * Why a deferred cost is not moving.
 *
 * A company that switches to "expense when used" keeps every lot it already
 * owns stamped as expensed-at-purchase, so the new deferred lot is the NEWEST
 * one -- and under FIFO the newest lot is drawn LAST. Production then correctly
 * recognises nothing, for as long as it takes to clear the older stock, and
 * correctly looks like a broken feature.
 *
 * Returns null when the lot is next in line, so the row stays quiet when there
 * is nothing to explain.
 */
function queueNote(p: WaterDeferredPurchase): string | null {
  const ahead = p.quantityAheadInQueue
  if (ahead == null || ahead <= 0) return null
  const unit = p.productionUnit ? ` ${p.productionUnit}` : ""
  const qty = ahead.toLocaleString(undefined, { maximumFractionDigits: 3 })
  return `${qty}${unit} of older stock is used before this cost starts reaching Profit & Loss (${p.costingMethod ?? "FIFO"}).`
}

const qtyFmt = (n: number, unit?: string | null) =>
  `${n.toLocaleString(undefined, { maximumFractionDigits: 3 })}${unit ? ` ${unit}` : ""}`

function WaterDeferredCostsInner() {
  const router = useRouter()
  const params = useSearchParams()
  const { toast } = useToast()
  const gh = useFmt()
  const { featureAccess, isAdmin } = usePermissions()

  // Costing detail is financial data. Anyone who cannot see expenses cannot see
  // what a purchase cost or where it went -- gated here as well as in the nav,
  // because a nav that hides a route does not stop somebody typing it. Same
  // predicate lib/utils/water-nav-access.ts uses for this href.
  const canView = isAdmin || featureAccess.canEnterExpenses || featureAccess.canViewFinancial

  const [data, setData] = useState<WaterDeferredCostResponse | null>(null)
  const [loading, setLoading] = useState(true)
  // Held separately from `data`, because "the call failed" and "there is
  // nothing to show" are different answers and the page must not give the
  // reassuring one when it means the alarming one.
  const [error, setError] = useState<string | null>(null)

  // Deep-link target: ?itemId= narrows to one raw material.
  const itemIdParam = params.get("itemId")
  const [scope, setScope] = useState<WaterDeferredCostScope>(
    (params.get("scope") as WaterDeferredCostScope) || "DEFERRED")
  const [itemId, setItemId] = useState<number | undefined>(
    itemIdParam ? Number(itemIdParam) : undefined)
  const [search, setSearch] = useState("")
  const [category, setCategory] = useState<string>("all")
  const [supplier, setSupplier] = useState<string>("all")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  // Expanded rows and their history, cached per purchase so collapsing and
  // re-expanding does not refetch.
  const [expanded, setExpanded] = useState<Set<number>>(new Set())
  const [history, setHistory] = useState<Record<number, WaterDeferredRecognition[]>>({})
  const [historyLoading, setHistoryLoading] = useState<Set<number>>(new Set())
  const [detail, setDetail] = useState<WaterDeferredPurchase | null>(null)

  const load = useCallback(async () => {
    if (!canView) { setLoading(false); return }
    setLoading(true)
    try {
      const res = await getWaterDeferredCosts({
        scope, itemId,
        category: category === "all" ? undefined : category,
        fromDate: dateFrom || undefined,
        toDate: dateTo || undefined,
        search: search.trim() || undefined,
      })
      setData(res)
      setError(null)
      // A filter change invalidates every cached history: the rows behind them
      // may no longer be on screen.
      setExpanded(new Set())
      setHistory({})
    } catch (e: any) {
      // No toast. A toast for a failure that leaves the whole page empty
      // disappears after a few seconds and takes the only explanation with it;
      // the card below stays until the problem is fixed.
      setData(null)
      setError(e?.message ?? String(e))
    } finally {
      setLoading(false)
    }
  }, [canView, scope, itemId, category, dateFrom, dateTo, search])

  useEffect(() => { void load() }, [load])

  // Supplier is filtered client-side: the list of suppliers worth offering is
  // the ones actually present in the result, and asking the server for that
  // separately would be a second round trip for a dropdown.
  const suppliers = useMemo(() => {
    const s = new Set<string>()
    for (const p of data?.purchases ?? []) if (p.supplierName) s.add(p.supplierName)
    return Array.from(s).sort()
  }, [data])

  const rows = useMemo(() => {
    const all = data?.purchases ?? []
    return supplier === "all" ? all : all.filter((p) => p.supplierName === supplier)
  }, [data, supplier])

  const pg = usePagination(rows)

  const toggle = async (p: WaterDeferredPurchase) => {
    const id = p.waterRawMaterialPurchaseId
    const next = new Set(expanded)
    if (next.has(id)) { next.delete(id); setExpanded(next); return }
    next.add(id)
    setExpanded(next)
    if (history[id]) return
    setHistoryLoading((s) => new Set(s).add(id))
    try {
      const h = await getWaterDeferredCostHistory(id)
      setHistory((m) => ({ ...m, [id]: h }))
    } catch (e: any) {
      // A per-row failure IS worth a toast -- the rest of the page is still
      // usable and the row can be collapsed -- but it carries the readable
      // headline, not the server's sentence.
      toast({
        title: explainLoadFailure(e?.message ?? String(e), "the recognition history").headline,
        description: explainLoadFailure(e?.message ?? String(e), "the recognition history").hint,
        variant: "destructive",
      })
    } finally {
      setHistoryLoading((s) => { const n = new Set(s); n.delete(id); return n })
    }
  }

  // CSV built from the rows on screen, so what is exported is what was filtered.
  const exportCsv = () => {
    const head = [
      "Purchase #", "Purchase Date", "Item", "Category", "Supplier",
      "Purchased Qty", "Unit", "Remaining Qty", "Original Cost", "Deferred Basis",
      "Recognized Cost", "Remaining Deferred", "Recognition %", "Method", "Status",
    ]
    const lines = rows.map((p) => [
      p.waterRawMaterialPurchaseId,
      p.purchaseDate?.slice(0, 10) ?? "",
      p.itemName ?? "",
      categoryLabel(p.category),
      p.supplierName ?? "",
      p.purchasedQuantity, p.productionUnit ?? "",
      p.remainingQuantity, p.operationalCost, p.deferredTotalCost,
      p.recognizedCost, p.deferredRemainingCost, p.recognitionPercent,
      p.recognitionMethodLabel ?? "", p.status ?? "",
    ])
    const esc = (v: any) => {
      const s = String(v ?? "")
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
    }
    const csv = [head, ...lines].map((r) => r.map(esc).join(",")).join("\n")
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8;" }))
    const a = document.createElement("a")
    a.href = url
    a.download = `water-deferred-inventory-costs-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  if (!canView) {
    return (
      <div className="flex min-h-screen bg-gray-50">
        <DashboardSidebar />
        <div className="flex-1 flex flex-col">
          <DashboardHeader />
          <main className="flex-1 p-4 sm:p-6">
            <Card><CardContent className="p-8 text-center text-slate-500">
              You do not have permission to view inventory costs.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  const s = data?.summary
  const activeScope = SCOPES.find((x) => x.value === scope)

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">

          <div className="flex flex-col gap-3 sm:flex-row sm:items-start">
            <div>
              <h1 className="text-xl font-semibold text-slate-900">Deferred inventory cost</h1>
              <p className="text-sm text-slate-500">
                Track raw material purchases whose costs are recognized in Profit &amp; Loss as production consumes the stock.
              </p>
            </div>
            <div className="sm:ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={exportCsv} disabled={rows.length === 0}>
                <Download className="w-4 h-4 mr-1" /> Export CSV
              </Button>
            </div>
          </div>

          {/* The explanation an owner needs before any number here means
              anything: this is not money still to be paid. */}
          <div className="rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-xs text-sky-900">
            {DEFERRED_PAGE_INTRO}
          </div>

          {/* Filters */}
          <Card><CardContent className="p-3">
            <div className="flex flex-wrap items-end gap-2">
              <div className="min-w-[180px]">
                <Label className="text-xs">Show</Label>
                <Select value={scope} onValueChange={(v) => setScope(v as WaterDeferredCostScope)}>
                  <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                  <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                    {SCOPES.map((x) => (
                      <SelectItem key={x.value} value={x.value} title={x.hint}>{x.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="min-w-[160px]">
                <Label className="text-xs">Category</Label>
                <Select value={category} onValueChange={setCategory}>
                  <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                  <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                    <SelectItem value="all">All categories</SelectItem>
                    {Array.from(new Set((data?.purchases ?? []).map((p) => p.category).filter(Boolean) as string[]))
                      .sort().map((c) => <SelectItem key={c} value={c}>{categoryLabel(c)}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="min-w-[160px]">
                <Label className="text-xs">Supplier</Label>
                <Select value={supplier} onValueChange={setSupplier}>
                  <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                  <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                    <SelectItem value="all">All suppliers</SelectItem>
                    {suppliers.map((x) => <SelectItem key={x} value={x}>{x}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <DateRangeFilter from={dateFrom} to={dateTo} onChange={(f, t) => { setDateFrom(f); setDateTo(t) }} />
              <div className="min-w-[180px] flex-1">
                <Label className="text-xs">Search</Label>
                <Input className="h-9" placeholder="Item, supplier or purchase #"
                       value={search} onChange={(e) => setSearch(e.target.value)} />
              </div>
              {itemId != null && (
                <Button variant="ghost" size="sm" className="h-9"
                        onClick={() => { setItemId(undefined); router.replace("/water-deferred-costs") }}>
                  Clear item filter
                </Button>
              )}
            </div>
            {activeScope && <p className="mt-2 text-[11px] text-slate-500">{activeScope.hint}</p>}
          </CardContent></Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8">
              <Loader2 className="w-4 h-4 animate-spin" /> Loading…
            </div>
          ) : error ? (
            // Checked BEFORE the summary and the table. A failed load leaves
            // `data` null, and without this branch the page falls through to
            // "no purchases are holding cost back" -- which is the one thing a
            // broken page must never say, because it reads as an all-clear.
            <Card><CardContent className="p-8">
              <div className="mx-auto max-w-md text-center">
                <AlertTriangle className="mx-auto h-8 w-8 text-amber-500" />
                <h2 className="mt-3 text-base font-semibold text-slate-900">
                  {explainLoadFailure(error, "deferred inventory costs").headline}
                </h2>
                <p className="mt-1 text-sm text-slate-500">
                  {explainLoadFailure(error, "deferred inventory costs").hint}
                </p>
                <Button variant="outline" size="sm" className="mt-4" onClick={() => void load()}>
                  Try again
                </Button>
                {/* Kept, but demoted: the person who can fix this needs the
                    real text, and the person who cannot should not have to
                    read it. */}
                <details className="mt-4 text-left">
                  <summary className="cursor-pointer text-[11px] text-slate-400 hover:text-slate-600">
                    Technical detail
                  </summary>
                  <p className="mt-1 break-words rounded bg-slate-50 p-2 font-mono text-[11px] text-slate-500">
                    {error}
                  </p>
                </details>
              </div>
            </CardContent></Card>
          ) : (
            <>
              {/* Summary cards. These come from the same SQL that produced the
                  rows, so they cannot drift from the table below. */}
              {s && (
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                  <div className="p-4 rounded-xl border border-amber-200 bg-amber-50 shadow-sm">
                    <div className="flex items-center gap-1.5 text-xs font-medium text-amber-700 uppercase tracking-wide"
                         title={REMAINING_DEFERRED_TOOLTIP}>
                      <Hourglass className="w-4 h-4" /> Deferred inventory cost
                    </div>
                    <div className="mt-1 text-2xl font-bold text-amber-900 tabular-nums">
                      {gh(s.remainingDeferredCost)}
                    </div>
                    <div className="text-xs text-amber-700 mt-0.5">
                      across {s.deferredPurchases.toLocaleString()} purchase{s.deferredPurchases === 1 ? "" : "s"}
                    </div>
                    {/* Without this, a company that has just switched method
                        sees a large number that never moves and concludes the
                        feature is broken. It is not -- the stock in front of it
                        has to be used first. */}
                    {s.blockedPurchases > 0 && (
                      <div className="mt-1 flex items-start gap-1 border-t border-amber-200 pt-1 text-[11px] text-amber-800">
                        <Clock className="w-3 h-3 mt-px flex-shrink-0" />
                        <span>
                          {gh(s.blockedCost)} of this is queued behind older stock and will not
                          move until that stock is used.
                        </span>
                      </div>
                    )}
                  </div>

                  <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                    <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide"
                         title={RECOGNIZED_COST_TOOLTIP}>
                      <CheckCircle2 className="w-4 h-4 text-emerald-600" /> Already expensed
                    </div>
                    <div className="mt-1 text-2xl font-bold text-slate-900 tabular-nums">{gh(s.recognizedCost)}</div>
                    <div className="text-xs text-slate-400 mt-0.5">
                      {s.recognitionPercent.toFixed(1)}% of {gh(s.deferredBasis)} deferred
                    </div>
                  </div>

                  <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                    <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide">
                      <Package className="w-4 h-4 text-blue-600" /> Purchases shown
                    </div>
                    <div className="mt-1 text-2xl font-bold text-slate-900 tabular-nums">
                      {s.purchaseCount.toLocaleString()}
                    </div>
                    <div className="text-xs text-slate-400 mt-0.5">
                      {s.fullyRecognized.toLocaleString()} fully expensed · {s.notRecognized.toLocaleString()} not started
                    </div>
                  </div>

                  <div className={cn("p-4 rounded-xl border shadow-sm",
                                     s.exceptions > 0 ? "bg-red-50 border-red-200" : "bg-white border-slate-200")}>
                    <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide"
                         title={DEFERRED_EXCEPTION_TOOLTIP}>
                      <AlertTriangle className={cn("w-4 h-4", s.exceptions > 0 ? "text-red-600" : "text-slate-400")} />
                      Needs checking
                    </div>
                    <div className={cn("mt-1 text-2xl font-bold tabular-nums",
                                       s.exceptions > 0 ? "text-red-700" : "text-slate-900")}>
                      {s.exceptions.toLocaleString()}
                    </div>
                    <div className="text-xs text-slate-400 mt-0.5">
                      {s.exceptions > 0 ? `${gh(Math.abs(s.exceptionDrift))} unexplained` : "all figures agree"}
                    </div>
                  </div>
                </div>
              )}

              <Card><CardContent className="p-4">
                {rows.length === 0 ? (
                  <div className="p-8 text-center text-sm text-slate-500">
                    {scope === "DEFERRED"
                      ? "No purchases are holding cost back from Profit & Loss. On a company that expenses stock when it is bought, this is the expected result."
                      : "No purchases match these filters."}
                  </div>
                ) : (
                  <>
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead className="w-8" />
                            <TableHead>Purchase</TableHead>
                            <TableHead>Item</TableHead>
                            <TableHead>Supplier</TableHead>
                            <TableHead className="text-right">Purchased</TableHead>
                            <TableHead className="text-right">Remaining</TableHead>
                            <TableHead className="text-right">Original cost</TableHead>
                            <TableHead className="text-right" title={RECOGNIZED_COST_TOOLTIP}>Expensed</TableHead>
                            <TableHead className="text-right whitespace-nowrap" title={REMAINING_DEFERRED_TOOLTIP}>Deferred inventory cost</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="w-8" />
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((p) => {
                            const id = p.waterRawMaterialPurchaseId
                            const open = expanded.has(id)
                            const isException = p.status === "Exception"
                            const neverDeferred = p.deferredTotalCost <= 0
                            return (
                              <Fragment key={id}>
                                <TableRow
                                          className={cn("cursor-pointer", isException && "bg-red-50/60")}
                                          onClick={() => void toggle(p)}>
                                  <TableCell className="px-1">
                                    {open ? <ChevronDown className="w-4 h-4 text-slate-400" />
                                          : <ChevronRight className="w-4 h-4 text-slate-400" />}
                                  </TableCell>
                                  <TableCell className="whitespace-nowrap">
                                    <div className="font-medium text-slate-900">#{id}</div>
                                    <div className="text-[11px] text-slate-500">
                                      {fmtDateTime(p.purchaseDate, p)}
                                    </div>
                                  </TableCell>
                                  <TableCell>
                                    <div className="text-slate-900">{p.itemName ?? "—"}</div>
                                    <div className="text-[11px] text-slate-500">{categoryLabel(p.category)}</div>
                                  </TableCell>
                                  {/* Always a supplier or nothing: water has no
                                      produced lots, so there is no second kind
                                      of origin to render here. */}
                                  <TableCell>{p.supplierName ?? "—"}</TableCell>
                                  <TableCell className="text-right whitespace-nowrap">
                                    {qtyFmt(p.purchasedQuantity, p.productionUnit)}
                                  </TableCell>
                                  <TableCell className="text-right whitespace-nowrap">
                                    {qtyFmt(p.remainingQuantity, p.productionUnit)}
                                  </TableCell>
                                  <TableCell className="text-right">{gh(p.operationalCost)}</TableCell>
                                  {/* Muted rather than 0.00 on a purchase that
                                      was never deferred: a bare zero here reads
                                      as a missing number, not a correct one. */}
                                  <TableCell className="text-right">
                                    {neverDeferred ? <span className="text-slate-300">—</span> : gh(p.recognizedCost)}
                                  </TableCell>
                                  <TableCell className="text-right">
                                    {neverDeferred ? <span className="text-slate-300">—</span> : (
                                      <span className={cn(p.deferredRemainingCost > 0 && "text-amber-700 font-medium")}>
                                        {gh(p.deferredRemainingCost)}
                                      </span>
                                    )}
                                  </TableCell>
                                  <TableCell>
                                    <Badge variant="outline"
                                           className={cn("text-[10px] font-normal",
                                                         isException ? "border-red-300 bg-red-50 text-red-700"
                                                                     : RECOGNITION_TONE_CLASS[deferredStatusTone(p.status)])}
                                           title={isException ? (p.exceptionReason ?? DEFERRED_EXCEPTION_TOOLTIP) : undefined}>
                                      {p.status}
                                    </Badge>
                                    {!neverDeferred && p.deferredTotalCost > 0 && (
                                      <div className="mt-0.5 text-[11px] text-slate-500">
                                        {p.recognitionPercent.toFixed(1)}% expensed
                                      </div>
                                    )}
                                    {/* The answer to "I ran a batch and nothing
                                        happened". Shown only when it is
                                        actually the explanation. */}
                                    {p.deferredRemainingCost > 0 && queueNote(p) && (
                                      <div className="mt-0.5 flex items-start gap-1 text-[11px] text-sky-700"
                                           title={queueNote(p)!}>
                                        <Clock className="w-3 h-3 mt-px flex-shrink-0" />
                                        <span>
                                          behind {qtyFmt(p.quantityAheadInQueue ?? 0, p.productionUnit)}
                                        </span>
                                      </div>
                                    )}
                                  </TableCell>
                                  <TableCell className="px-1">
                                    <Button variant="ghost" size="sm" title="Purchase detail"
                                            onClick={(e) => { e.stopPropagation(); setDetail(p) }}>
                                      <Receipt className="w-4 h-4 text-slate-500" />
                                    </Button>
                                  </TableCell>
                                </TableRow>

                                {open && (
                                  <TableRow>
                                    <TableCell colSpan={11} className="bg-slate-50 p-0">
                                      <HistoryPanel
                                        purchase={p}
                                        rows={history[id]}
                                        loading={historyLoading.has(id)}
                                        gh={gh}
                                        onOpenExpense={() => router.push("/water-expenses")}
                                        onOpenBatch={(bid) => router.push(`/water-production-batches/${bid}`)}
                                      />
                                    </TableCell>
                                  </TableRow>
                                )}
                              </Fragment>
                            )
                          })}
                        </TableBody>
                      </Table>
                    </div>
                    <DataPagination {...pg.paginationProps} />
                  </>
                )}
              </CardContent></Card>
            </>
          )}

          <PurchaseDetailDialog
            purchase={detail}
            rows={detail ? history[detail.waterRawMaterialPurchaseId] : undefined}
            gh={gh}
            onClose={() => setDetail(null)}
            onOpenItems={() => router.push("/water-raw-materials?tab=items")}
            onOpenPurchase={(pid) => router.push(`/water-raw-materials?tab=purchases&purchaseId=${pid}`)}
          />
        </main>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// The expanded row: every production draw that drew on this purchase.
// ---------------------------------------------------------------------------
function HistoryPanel({
  purchase, rows, loading, gh, onOpenExpense, onOpenBatch,
}: {
  purchase: WaterDeferredPurchase
  rows?: WaterDeferredRecognition[]
  loading: boolean
  gh: (n: number) => string
  onOpenExpense: () => void
  onOpenBatch: (batchId: number) => void
}) {
  if (loading) {
    return (
      <div className="flex items-center gap-2 p-4 text-sm text-slate-500">
        <Loader2 className="w-4 h-4 animate-spin" /> Loading recognition history…
      </div>
    )
  }
  if (!rows || rows.length === 0) {
    return (
      <div className="p-4 text-sm text-slate-500">
        Nothing has drawn on this purchase yet
        {purchase.deferredRemainingCost > 0
          ? ` — its ${gh(purchase.deferredRemainingCost)} is still held as stock value.`
          : "."}
      </div>
    )
  }

  const totalRecognized = rows.reduce((a, r) => a + (r.isReversed ? 0 : r.recognizedCost), 0)
  const totalOperational = rows.reduce((a, r) => a + (r.isReversed ? 0 : r.operationalCost), 0)

  return (
    <div className="p-3">
      <div className="mb-2 text-xs font-medium text-slate-600">
        Recognition history — what moved this purchase&rsquo;s cost into Profit &amp; Loss
      </div>
      <div className="overflow-x-auto rounded-md border border-slate-200 bg-white">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="text-xs">Date</TableHead>
              {/* Poultry asks which flock ate it; water asks which batch
                  packed it. Same column, different question. */}
              <TableHead className="text-xs">Production batch</TableHead>
              <TableHead className="text-xs text-right">Qty drawn</TableHead>
              <TableHead className="text-xs text-right">Unit cost</TableHead>
              <TableHead className="text-xs text-right" title={OPERATIONAL_COST_TOOLTIP}>Stock used</TableHead>
              <TableHead className="text-xs text-right" title={NEWLY_RECOGNIZED_TOOLTIP}>Expensed</TableHead>
              <TableHead className="text-xs">Outcome</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((r) => (
              <TableRow key={r.waterRawMaterialUsageId}
                        className={cn(r.isReversed && "opacity-60")}>
                <TableCell className="text-xs whitespace-nowrap">{fmtDateTime(r.usedDate, r)}</TableCell>
                <TableCell className="text-xs">
                  {/* Linked only when there is a batch to open. A draw can also
                      come from internal use or a loss record, which have no
                      batch page -- those show the server's label alone rather
                      than a link that goes nowhere. */}
                  {r.waterProductionBatchId != null ? (
                    <button type="button"
                            className="text-left text-sky-700 underline decoration-dotted underline-offset-2 hover:text-sky-900"
                            title="Open the production batch"
                            onClick={() => onOpenBatch(r.waterProductionBatchId!)}>
                      {r.sourceLabel ?? r.batchNumber ?? `Batch #${r.waterProductionBatchId}`}
                    </button>
                  ) : (
                    <div className="text-slate-900">{r.sourceLabel ?? "—"}</div>
                  )}
                  <div className="text-[11px] text-slate-500">
                    {r.productName ?? r.sourceType ?? ""}
                  </div>
                </TableCell>
                <TableCell className="text-xs text-right whitespace-nowrap">
                  {qtyFmt(r.quantityDrawn, r.productionUnit)}
                </TableCell>
                <TableCell className="text-xs text-right">{gh(r.unitCostAtDraw)}</TableCell>
                <TableCell className="text-xs text-right">{gh(r.operationalCost)}</TableCell>
                <TableCell className="text-xs text-right">
                  {r.recognizedCost > 0
                    ? <span className="font-medium text-emerald-700">{gh(r.recognizedCost)}</span>
                    : <span className="text-slate-300">—</span>}
                </TableCell>
                <TableCell className="text-xs">
                  <div className="flex items-center gap-1">
                    <span className={cn(r.isReversed ? "text-slate-500"
                                        : r.recognizedCost > 0 ? "text-emerald-700" : "text-slate-500")}>
                      {r.recognitionOutcome}
                    </span>
                    {r.waterExpenseId != null && !r.isReversed && (
                      <Button variant="ghost" size="sm" className="h-5 px-1"
                              title={`Expense #${r.waterExpenseId} — ${NO_SECOND_PAYMENT_TOOLTIP}`}
                              onClick={onOpenExpense}>
                        <ExternalLink className="w-3 h-3 text-slate-400" />
                      </Button>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            ))}
            {/* The decomposition, stated: these rows are what the headline is
                made of. */}
            <TableRow className="bg-slate-50 font-medium">
              <TableCell colSpan={4} className="text-xs text-slate-600">
                Live usages ({rows.filter((r) => !r.isReversed).length})
              </TableCell>
              <TableCell className="text-xs text-right">{gh(totalOperational)}</TableCell>
              <TableCell className="text-xs text-right text-emerald-700">{gh(totalRecognized)}</TableCell>
              <TableCell />
            </TableRow>
          </TableBody>
        </Table>
      </div>
      {purchase.status === "Exception" && purchase.exceptionReason && (
        <div className="mt-2 flex items-start gap-2 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-900">
          <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
          <span>{purchase.exceptionReason}</span>
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Purchase detail / audit view.
// ---------------------------------------------------------------------------
function PurchaseDetailDialog({
  purchase, rows, gh, onClose, onOpenItems, onOpenPurchase,
}: {
  purchase: WaterDeferredPurchase | null
  rows?: WaterDeferredRecognition[]
  gh: (n: number) => string
  onClose: () => void
  onOpenItems: () => void
  onOpenPurchase: (purchaseId: number) => void
}) {
  if (!purchase) return null
  const p = purchase
  const neverDeferred = p.deferredTotalCost <= 0

  const Row = ({ k, v, hint }: { k: string; v: React.ReactNode; hint?: string }) => (
    <div className="flex justify-between gap-4 py-1 text-sm">
      <span className="text-slate-500" title={hint}>{k}</span>
      <span className="text-slate-900 text-right">{v}</span>
    </div>
  )

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Purchase #{p.waterRawMaterialPurchaseId}</DialogTitle>
        </DialogHeader>

        <div className="space-y-3">
          <div>
            <div className="text-xs font-medium uppercase tracking-wide text-slate-500 mb-1">Purchase</div>
            <Row k="Item" v={p.itemName ?? "—"} />
            <Row k="Category" v={categoryLabel(p.category)} />
            <Row k="Purchase date" v={p.purchaseDate?.slice(0, 10) ?? "—"} />
            <Row k="Supplier" v={p.supplierName ?? "—"} />
            <Row k="Original quantity" v={qtyFmt(p.purchasedQuantity, p.productionUnit)} />
            <Row k="Original cost" v={gh(p.operationalCost)} />
            <Row k="Recognition" v={p.recognitionMethodLabel ?? "—"} />
          </div>

          <div className="border-t pt-2">
            <div className="text-xs font-medium uppercase tracking-wide text-slate-500 mb-1">Cost recognition</div>
            <Row k="Quantity used" v={qtyFmt(p.consumedQuantity, p.productionUnit)} />
            <Row k="Quantity remaining" v={qtyFmt(p.remainingQuantity, p.productionUnit)} />
            {neverDeferred ? (
              <p className="mt-1 text-xs text-slate-500">
                This purchase was charged to Profit &amp; Loss when it was bought, so none of its cost is waiting.
                Using the stock reduces the quantity but adds no new expense.
              </p>
            ) : (
              <>
                <Row k="Deferred to begin with" v={gh(p.deferredTotalCost)} />
                <Row k="Expensed so far" v={gh(p.recognizedCost)} hint={RECOGNIZED_COST_TOOLTIP} />
                <Row k="Still to expense" v={gh(p.deferredRemainingCost)} hint={REMAINING_DEFERRED_TOOLTIP} />
                <Row k="Progress" v={`${p.recognitionPercent.toFixed(2)}%`} />
                <div className="mt-1 h-1.5 w-full rounded-full bg-slate-200">
                  <div className="h-1.5 rounded-full bg-emerald-500"
                       style={{ width: `${Math.min(100, Math.max(0, p.recognitionPercent))}%` }} />
                </div>
              </>
            )}
          </div>

          {p.status === "Exception" && (
            <div className="flex items-start gap-2 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-900">
              <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
              <div>
                <div className="font-medium">Needs checking</div>
                <div>{p.exceptionReason}</div>
                <div className="mt-1">
                  Lot balance says {gh(p.recognizedCost)}; its usages say {gh(p.allocatedRecognizedCost)}.
                </div>
              </div>
            </div>
          )}

          {rows && rows.length > 0 && (
            <div className="border-t pt-2">
              <div className="text-xs font-medium uppercase tracking-wide text-slate-500 mb-1">
                Recognition history ({rows.length})
              </div>
              <div className="max-h-40 overflow-y-auto space-y-1">
                {rows.map((r) => (
                  <div key={r.waterRawMaterialUsageId}
                       className={cn("flex justify-between gap-2 text-xs", r.isReversed && "opacity-60 line-through")}>
                    <span className="text-slate-500">{fmtDateTime(r.usedDate, r)}</span>
                    <span className="flex-1 text-slate-700 truncate">{r.sourceLabel}</span>
                    <span className="text-slate-500">{qtyFmt(r.quantityDrawn, r.productionUnit)}</span>
                    <span className="text-emerald-700">{r.recognizedCost > 0 ? gh(r.recognizedCost) : "—"}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="flex gap-2 border-t pt-3">
            <Button variant="outline" size="sm" onClick={() => onOpenPurchase(p.waterRawMaterialPurchaseId)}>
              Open purchase
            </Button>
            {/* The raw-materials page takes ?purchaseId= but has no ?itemId=
                focus, so this opens the Items tab rather than pretending to
                deep-link a row. */}
            <Button variant="outline" size="sm" onClick={onOpenItems}>
              Open items
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

export default function WaterDeferredCostsPage() {
  return (
    <Suspense fallback={null}>
      <WaterDeferredCostsInner />
    </Suspense>
  )
}

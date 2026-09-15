"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { TRACKER_PAGE_SIZE_DEFAULT, TRACKER_PAGE_SIZE_OPTIONS } from "@/components/ui/data-pagination"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Bird, RefreshCw, ChevronDown, ChevronUp } from "lucide-react"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getSales, type Sale } from "@/lib/api/sale"
import { getUserContext } from "@/lib/utils/user-context"
import { formatDateShort, cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"
import { toLocalDateKey } from "@/lib/utils/date-key"
import {
  buildBirdsLeftLedger,
  summarizeBirdsLeftByFlock,
  type BirdsLeftLedgerRow,
} from "@/lib/utils/birds-left-ledger"
import { flockCountsTowardBirdTotals } from "@/lib/utils/flock-eligibility"


export default function BirdsLeftTrackerPage() {
  const router = useRouter()
  const isMobile = useIsMobile()
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [records, setRecords] = useState<ProductionRecord[]>([])
  const [sales, setSales] = useState<Sale[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [refreshing, setRefreshing] = useState(false)

  const [flockFilter, setFlockFilter] = useState("ALL")
  const [typeFilter, setTypeFilter] = useState<"ALL" | "IN" | "OUT">("ALL")
  const [ledgerDateFrom, setLedgerDateFrom] = useState("")
  const [ledgerDateTo, setLedgerDateTo] = useState("")
  const [ledgerSortKey, setLedgerSortKey] = useState<string | null>("date")
  const [ledgerSortDir, setLedgerSortDir] = useState<SortDirection>("desc")
  const [ledgerPage, setLedgerPage] = useState(1)
  const [ledgerPageSize, setLedgerPageSize] = useState(TRACKER_PAGE_SIZE_DEFAULT)
  // Phones open on scorecards; "View table format" flips to the table, the same
  // pair of views /poultry-daily-closing, /egg-tracker and /feed-tracker offer.
  // The two tables on this page toggle independently — reading one as a table
  // is no reason to change the other.
  const [showLedgerTableMobile, setShowLedgerTableMobile] = useState(false)
  const [showFlockTableMobile, setShowFlockTableMobile] = useState(false)

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  const loadData = useCallback(async () => {
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      setLoading(false)
      setRefreshing(false)
      return
    }
    const [flocksRes, prodRes, salesRes] = await Promise.all([
      getFlocks(userId, farmId),
      getProductionRecords(userId, farmId),
      getSales(userId, farmId),
    ])
    if (flocksRes.success && flocksRes.data) setFlocks(flocksRes.data)
    else setFlocks([])
    if (prodRes.success && prodRes.data) {
      setRecords(prodRes.data)
      setError("")
    } else {
      setRecords([])
      setError(prodRes.message || "Failed to load production records")
    }
    if (salesRes.success && salesRes.data) setSales(salesRes.data)
    else setSales([])
    setLoading(false)
    setRefreshing(false)
  }, [])

  useEffect(() => {
    void loadData()
  }, [loadData])

  const handleRefresh = () => {
    setRefreshing(true)
    void loadData()
  }

  const summaries = useMemo(
    () =>
      summarizeBirdsLeftByFlock(
        flocks.filter((f) => flockCountsTowardBirdTotals(f)),
        records,
        sales,
      ),
    [flocks, records, sales],
  )

  const totalPlaced = useMemo(() => summaries.reduce((s, r) => s + r.placedIn, 0), [summaries])
  const totalBirdsLeft = useMemo(
    () => summaries.reduce((s, r) => s + r.birdsLeftCalculated, 0),
    [summaries],
  )

  const ledger = useMemo(() => buildBirdsLeftLedger(flocks, records, sales), [flocks, records, sales])

  const filteredLedger = useMemo(() => {
    let list = ledger.slice()
    if (flockFilter !== "ALL") {
      const fid = parseInt(flockFilter, 10)
      list = list.filter((r) => r.flockId === fid)
    }
    if (typeFilter !== "ALL") list = list.filter((r) => r.type === typeFilter)
    if (ledgerDateFrom) list = list.filter((r) => r.date >= ledgerDateFrom)
    if (ledgerDateTo) list = list.filter((r) => r.date <= ledgerDateTo)
    return list
  }, [ledger, flockFilter, typeFilter, ledgerDateFrom, ledgerDateTo])

  const sortedLedger = useMemo(
    () =>
      sortData(filteredLedger, ledgerSortKey, ledgerSortDir, (item: BirdsLeftLedgerRow, key: string) => {
        if (key === "date") return item.date
        if (key === "quantity") return item.quantity
        if (key === "flockId") return item.flockId
        return (item as Record<string, unknown>)[key]
      }),
    [filteredLedger, ledgerSortKey, ledgerSortDir],
  )

  // Whole-ledger totals for the scorecards above. Deliberately NOT the filtered
  // figures below: these sit beside "Total birds placed" and "Birds left", which
  // are farm-wide, and a headline that moved when you filtered the table would
  // not agree with either of them.
  const ledgerTotals = useMemo(() => {
    let inQty = 0
    let outQty = 0
    for (const r of ledger) {
      const qty = Number(r.quantity) || 0
      if (r.type === "IN") inQty += qty
      else outQty += qty
    }
    return { in: inQty, out: outQty }
  }, [ledger])

  // Column totals across the filtered set, not just the visible page. The Qty
  // column carries its direction in `type` rather than the sign, so the two
  // directions are summed separately and the footer shows the net.
  const ledgerInTotal = useMemo(
    () => sortedLedger.filter((r) => r.type === "IN").reduce((s, r) => s + (Number(r.quantity) || 0), 0),
    [sortedLedger]
  )
  const ledgerOutTotal = useMemo(
    () => sortedLedger.filter((r) => r.type === "OUT").reduce((s, r) => s + (Number(r.quantity) || 0), 0),
    [sortedLedger]
  )
  const ledgerFiltersActive =
    flockFilter !== "ALL" || typeFilter !== "ALL" || ledgerDateFrom !== "" || ledgerDateTo !== ""

  // "By flock" column totals.
  const flockTotals = useMemo(
    () =>
      summaries.reduce(
        (acc, r) => ({
          placedIn: acc.placedIn + (Number(r.placedIn) || 0),
          mortalityOut: acc.mortalityOut + (Number(r.totalMortalityOut) || 0),
          salesOut: acc.salesOut + (Number(r.totalBirdSalesOut) || 0),
          left: acc.left + (Number(r.birdsLeftCalculated) || 0),
        }),
        { placedIn: 0, mortalityOut: 0, salesOut: 0, left: 0 }
      ),
    [summaries]
  )

  const ledgerTotalPages = Math.max(1, Math.ceil(sortedLedger.length / ledgerPageSize))
  const ledgerSafePage = Math.min(ledgerPage, ledgerTotalPages)
  const paginatedLedger = sortedLedger.slice(
    (ledgerSafePage - 1) * ledgerPageSize,
    ledgerSafePage * ledgerPageSize,
  )

  useEffect(() => {
    setLedgerPage(1)
  }, [flockFilter, typeFilter, ledgerDateFrom, ledgerDateTo])

  const handleLedgerSort = (key: string) => {
    const r = toggleSort(key, ledgerSortKey, ledgerSortDir)
    setLedgerSortKey(r.key)
    setLedgerSortDir(r.direction)
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-sky-100 rounded-lg flex items-center justify-center">
                  <Bird className="w-5 h-5 text-sky-700" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Birds left tracker</h1>
                  <p className="text-sm text-slate-600 mt-1">
                    One <strong>IN</strong> per flock (birds placed at purchase). Only{" "}
                    <strong>mortality</strong> (production records) and <strong>bird sales</strong> create{" "}
                    <strong>OUT</strong> rows and reduce the count.
                  </p>
                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm">
                    <Link href="/flocks" className="text-blue-600 hover:underline font-medium">
                      Flocks
                    </Link>
                    <Link href="/production-records" className="text-blue-600 hover:underline font-medium">
                      Production records
                    </Link>
                    <Link href="/sales" className="text-blue-600 hover:underline font-medium">
                      Sales
                    </Link>
                  </div>
                </div>
              </div>
              <Button
                type="button"
                variant="outline"
                className="shrink-0 gap-2"
                onClick={handleRefresh}
                disabled={refreshing || loading}
              >
                <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
                Refresh
              </Button>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center text-slate-600">Loading birds left…</CardContent>
              </Card>
            ) : (
              <>
                {/* Four across on a desktop, two on a phone: the two standing
                    figures and the two movement totals that produce them, all
                    on one band. placed + in are the same number by
                    construction — placement is the only IN — and left is
                    in − out, so the row reads as its own arithmetic. */}
                <div className={cn("grid gap-3", isMobile ? "grid-cols-2" : "grid-cols-2 lg:grid-cols-4")}>
                  <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                    <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">
                      Total birds placed (all flocks)
                    </div>
                    <div className="text-2xl font-bold text-emerald-700 tabular-nums mt-1">
                      {totalPlaced.toLocaleString()}
                    </div>
                  </div>
                  <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                    <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">
                      Birds left (placed − deaths − bird sales)
                    </div>
                    <div className="text-2xl font-bold text-sky-700 tabular-nums mt-1">
                      {totalBirdsLeft.toLocaleString()}
                    </div>
                  </div>
                  <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                    <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">
                      Total IN (ledger)
                    </div>
                    <div className="text-2xl font-bold text-emerald-600 tabular-nums mt-1">
                      {ledgerTotals.in.toLocaleString()}
                    </div>
                  </div>
                  <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                    <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">
                      Total OUT (deaths + bird sales)
                    </div>
                    <div className="text-2xl font-bold text-red-600 tabular-nums mt-1">
                      {ledgerTotals.out.toLocaleString()}
                    </div>
                  </div>
                </div>

                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">By flock</CardTitle>
                    <CardDescription>
                      Compare calculated balance with the latest &ldquo;birds left&rdquo; on production records.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto table-scroll-wrapper pb-2">
                    {isMobile && !showFlockTableMobile ? (
                      /* Scorecards, as on the ledger below: one card per flock,
                         open by default, striped. Placed and Birds left lead
                         because they are the two figures a flock is judged on;
                         what took the difference away — deaths, sales — and the
                         cross-check against the last production log sit inside.
                       */
                      <div className="space-y-3">
                        {summaries.length === 0 ? (
                          <p className="py-8 text-center text-sm text-slate-500">No flocks yet.</p>
                        ) : (
                          <>
                            {summaries.map((row, idx) => (
                              <Collapsible
                                key={row.flockId}
                                defaultOpen
                                className={cn(
                                  "group w-full overflow-hidden rounded-xl border shadow-sm",
                                  idx % 2 === 0 ? "border-blue-300 bg-blue-100" : "border-slate-200 bg-white"
                                )}
                              >
                                <div className={cn("px-2.5 py-3 transition-colors", idx % 2 === 0 ? "active:bg-black/10" : "active:bg-black/5")}>
                                  <CollapsibleTrigger asChild>
                                    <div className="relative cursor-pointer">
                                      <ChevronDown className="absolute right-0 top-0 h-4 w-4 shrink-0 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
                                      <div className="min-w-0">
                                        <div className="flex flex-wrap items-center gap-2 pr-6">
                                          <span className="font-semibold text-slate-900">{row.flockName}</span>
                                        </div>
                                        <div className="mt-3 grid grid-cols-2 gap-2">
                                          <div className="rounded-lg border border-emerald-300 bg-emerald-100 px-3 py-2 shadow-sm">
                                            <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">Placed (in)</p>
                                            <p className="text-xl font-extrabold leading-tight text-emerald-800 tabular-nums">
                                              {row.placedIn.toLocaleString()}
                                            </p>
                                          </div>
                                          <div className="rounded-lg border border-sky-300 bg-sky-100 px-3 py-2 shadow-sm">
                                            <p className="text-[11px] font-semibold uppercase tracking-wide text-sky-900">Birds left</p>
                                            <p className="text-xl font-extrabold leading-tight text-sky-800 tabular-nums">
                                              {row.birdsLeftCalculated.toLocaleString()}
                                            </p>
                                          </div>
                                        </div>
                                      </div>
                                    </div>
                                  </CollapsibleTrigger>
                                  <CollapsibleContent>
                                    <div className="mt-4 grid grid-cols-2 gap-2 border-t border-slate-200/70 pt-4 text-sm">
                                      <div>
                                        <span className="text-slate-500">Deaths OUT</span>{" "}
                                        <span className="font-medium tabular-nums text-red-700">
                                          {row.totalMortalityOut.toLocaleString()}
                                        </span>
                                      </div>
                                      <div>
                                        <span className="text-slate-500">Sales OUT</span>{" "}
                                        <span className="font-medium tabular-nums text-amber-800">
                                          {row.totalBirdSalesOut.toLocaleString()}
                                        </span>
                                      </div>
                                      <div className="col-span-2">
                                        <span className="text-slate-500">From last log</span>{" "}
                                        <span className="font-medium tabular-nums text-slate-700">
                                          {row.birdsLeftFromLatestLog != null
                                            ? row.birdsLeftFromLatestLog.toLocaleString()
                                            : "—"}
                                        </span>
                                      </div>
                                    </div>
                                  </CollapsibleContent>
                                </div>
                              </Collapsible>
                            ))}
                            {/* The table's footer row, which the cards would
                                otherwise drop. */}
                            <div className="rounded-xl border border-slate-300 bg-slate-100 px-3 py-3">
                              <p className="text-xs font-semibold uppercase tracking-wide text-slate-600">
                                Total — {summaries.length.toLocaleString()}{" "}
                                {summaries.length === 1 ? "flock" : "flocks"}
                              </p>
                              <div className="mt-2 grid grid-cols-2 gap-2 text-sm">
                                <div>
                                  <span className="text-slate-500">Placed</span>{" "}
                                  <span className="font-bold tabular-nums text-slate-900">
                                    {flockTotals.placedIn.toLocaleString()}
                                  </span>
                                </div>
                                <div>
                                  <span className="text-slate-500">Birds left</span>{" "}
                                  <span className="font-bold tabular-nums text-sky-800">
                                    {flockTotals.left.toLocaleString()}
                                  </span>
                                </div>
                                <div>
                                  <span className="text-slate-500">Deaths</span>{" "}
                                  <span className="font-bold tabular-nums text-red-700">
                                    {flockTotals.mortalityOut.toLocaleString()}
                                  </span>
                                </div>
                                <div>
                                  <span className="text-slate-500">Sales</span>{" "}
                                  <span className="font-bold tabular-nums text-amber-800">
                                    {flockTotals.salesOut.toLocaleString()}
                                  </span>
                                </div>
                              </div>
                            </div>
                          </>
                        )}
                        <div className="rounded-lg border bg-slate-50/60 px-4 py-2">
                          <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            className="w-full text-slate-600"
                            onClick={() => setShowFlockTableMobile(true)}
                          >
                            View table format <ChevronDown className="ml-1 h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    ) : (
                    <>
                    {isMobile && (
                      <div className="-mx-4 -mt-4 mb-3 flex items-center justify-between gap-2 border-b bg-slate-50 px-4 py-2">
                        <span className="text-xs text-slate-600">Table view - scroll for more</span>
                        <Button type="button" variant="ghost" size="sm" onClick={() => setShowFlockTableMobile(false)}>
                          <ChevronUp className="mr-1 h-4 w-4" /> Cards
                        </Button>
                      </div>
                    )}
                    <Table className="w-full min-w-[640px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Flock</TableHead>
                          <TableHead className="text-right">Placed (IN)</TableHead>
                          <TableHead className="text-right">Deaths OUT</TableHead>
                          <TableHead className="text-right">Sales OUT</TableHead>
                          <TableHead className="text-right">Birds left</TableHead>
                          <TableHead className="text-right">From last log</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {summaries.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={6} className="text-center text-slate-500 py-8">
                              No flocks yet.
                            </TableCell>
                          </TableRow>
                        ) : (
                          summaries.map((row) => (
                            <TableRow key={row.flockId}>
                              <TableCell className="font-medium">{row.flockName}</TableCell>
                              <TableCell className="text-right tabular-nums">
                                {row.placedIn.toLocaleString()}
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-red-700">
                                {row.totalMortalityOut.toLocaleString()}
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-amber-800">
                                {row.totalBirdSalesOut.toLocaleString()}
                              </TableCell>
                              <TableCell className="text-right tabular-nums font-semibold text-sky-800">
                                {row.birdsLeftCalculated.toLocaleString()}
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-slate-600">
                                {row.birdsLeftFromLatestLog != null
                                  ? row.birdsLeftFromLatestLog.toLocaleString()
                                  : "—"}
                              </TableCell>
                            </TableRow>
                          ))
                        )}
                      </TableBody>
                      {summaries.length > 0 && (
                        <TableFooter>
                          <TableRow className="bg-slate-50 hover:bg-slate-50">
                            <TableCell className="font-medium text-slate-700">
                              Total
                              <span className="ml-2 font-normal text-slate-500">
                                ({summaries.length.toLocaleString()} {summaries.length === 1 ? "flock" : "flocks"})
                              </span>
                            </TableCell>
                            <TableCell className="text-right tabular-nums font-bold">
                              {flockTotals.placedIn.toLocaleString()}
                            </TableCell>
                            <TableCell className="text-right tabular-nums font-bold text-red-700">
                              {flockTotals.mortalityOut.toLocaleString()}
                            </TableCell>
                            <TableCell className="text-right tabular-nums font-bold text-amber-800">
                              {flockTotals.salesOut.toLocaleString()}
                            </TableCell>
                            <TableCell className="text-right tabular-nums font-bold text-sky-800">
                              {flockTotals.left.toLocaleString()}
                            </TableCell>
                            <TableCell />
                          </TableRow>
                        </TableFooter>
                      )}
                    </Table>
                    </>
                    )}
                  </CardContent>
                </Card>

                <Card className="bg-white" id="birds-ledger">
                  <CardHeader>
                    <CardTitle>Ledger (IN / OUT)</CardTitle>
                    <CardDescription>
                      Bird sales are detected when the product name is not eggs (e.g. chicken, broiler, live bird).
                    </CardDescription>
                    <div
                      className={cn(
                        "grid gap-2 pt-3",
                        isMobile ? "grid-cols-1" : "grid-cols-2 lg:grid-cols-5",
                      )}
                    >
                      <Select value={flockFilter} onValueChange={setFlockFilter}>
                        <SelectTrigger>
                          <SelectValue placeholder="Flock" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All flocks</SelectItem>
                          {flocks.map((f) => (
                            <SelectItem key={f.flockId} value={String(f.flockId)}>
                              {f.name || `Flock #${f.flockId}`}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Select
                        value={typeFilter}
                        onValueChange={(v) => setTypeFilter(v as "ALL" | "IN" | "OUT")}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Type" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All types</SelectItem>
                          <SelectItem value="IN">IN only</SelectItem>
                          <SelectItem value="OUT">OUT only</SelectItem>
                        </SelectContent>
                      </Select>
                      <Input
                        type="date"
                        value={ledgerDateFrom}
                        onChange={(e) => setLedgerDateFrom(e.target.value)}
                        aria-label="From date"
                      />
                      <Input
                        type="date"
                        value={ledgerDateTo}
                        onChange={(e) => setLedgerDateTo(e.target.value)}
                        aria-label="To date"
                      />
                    </div>
                  </CardHeader>
                  <CardContent className="pt-0 overflow-x-auto table-scroll-wrapper pb-2">
                    {paginatedLedger.length === 0 ? (
                      <p className="text-slate-600 py-8 text-center text-sm">No ledger rows match these filters.</p>
                    ) : isMobile && !showLedgerTableMobile ? (
                      /* Scorecards, following the other trackers: one card per
                         row, open by default, striped so consecutive rows are
                         told apart at a glance. This ledger keeps its direction
                         in `type` rather than in the sign, so the quantity is
                         shown under IN or under OUT and the other box reads a
                         dash — the same two-box shape as the egg and feed
                         cards, with the same meaning. */
                      <div className="space-y-3">
                        {paginatedLedger.map((row, idx) => (
                          <Collapsible
                            key={row.id}
                            defaultOpen
                            className={cn(
                              "group w-full overflow-hidden rounded-xl border shadow-sm",
                              idx % 2 === 0 ? "border-blue-300 bg-blue-100" : "border-slate-200 bg-white"
                            )}
                          >
                            <div className={cn("px-2.5 py-3 transition-colors", idx % 2 === 0 ? "active:bg-black/10" : "active:bg-black/5")}>
                              <CollapsibleTrigger asChild>
                                <div className="relative cursor-pointer">
                                  <ChevronDown className="absolute right-0 top-0 h-4 w-4 shrink-0 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
                                  <div className="min-w-0">
                                    <div className="flex flex-wrap items-center gap-2 pr-6">
                                      <span className="font-semibold text-slate-900">{formatDateShort(row.date)}</span>
                                      <Badge className="bg-blue-200 text-blue-900 hover:bg-blue-200">{row.category}</Badge>
                                    </div>
                                    <div className="mt-3 grid grid-cols-2 gap-2">
                                      <div className="rounded-lg border border-emerald-300 bg-emerald-100 px-3 py-2 shadow-sm">
                                        <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">In</p>
                                        <p className="text-xl font-extrabold leading-tight text-emerald-800 tabular-nums">
                                          {row.type === "IN" ? row.quantity.toLocaleString() : "—"}
                                        </p>
                                      </div>
                                      <div className="rounded-lg border border-red-300 bg-red-100 px-3 py-2 shadow-sm">
                                        <p className="text-[11px] font-semibold uppercase tracking-wide text-red-900">Out</p>
                                        <p className="text-xl font-extrabold leading-tight text-red-800 tabular-nums">
                                          {row.type === "OUT" ? row.quantity.toLocaleString() : "—"}
                                        </p>
                                      </div>
                                    </div>
                                  </div>
                                </div>
                              </CollapsibleTrigger>
                              <CollapsibleContent>
                                <div className="mt-4 space-y-2 border-t border-slate-200/70 pt-4 text-sm">
                                  <div>
                                    <span className="text-slate-500">Flock</span>{" "}
                                    <span className="font-medium text-slate-900">{row.flockName}</span>
                                  </div>
                                  <div>
                                    <span className="text-slate-500">Description</span>{" "}
                                    <span className="font-medium text-slate-900">{row.description}</span>
                                  </div>
                                </div>
                              </CollapsibleContent>
                            </div>
                          </Collapsible>
                        ))}
                        <div className="rounded-lg border bg-slate-50/60 px-4 py-2">
                          <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            className="w-full text-slate-600"
                            onClick={() => setShowLedgerTableMobile(true)}
                          >
                            View table format <ChevronDown className="ml-1 h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    ) : (
                      <>
                      {isMobile && (
                        <div className="-mx-4 -mt-4 mb-3 flex items-center justify-between gap-2 border-b bg-slate-50 px-4 py-2">
                          <span className="text-xs text-slate-600">Table view - scroll for more</span>
                          <Button type="button" variant="ghost" size="sm" onClick={() => setShowLedgerTableMobile(false)}>
                            <ChevronUp className="mr-1 h-4 w-4" /> Cards
                          </Button>
                        </div>
                      )}
                      <Table className="w-full min-w-[560px]">
                        <TableHeader>
                          <TableRow>
                            <SortableHeader
                              label="Date"
                              sortKey="date"
                              currentSort={ledgerSortKey}
                              currentDirection={ledgerSortDir}
                              onSort={handleLedgerSort}
                            />
                            <TableHead>Type</TableHead>
                            <TableHead>Category</TableHead>
                            <TableHead>Flock</TableHead>
                            <SortableHeader
                              label="Qty"
                              sortKey="quantity"
                              currentSort={ledgerSortKey}
                              currentDirection={ledgerSortDir}
                              onSort={handleLedgerSort}
                              className="text-right"
                            />
                            <TableHead>Description</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {paginatedLedger.map((row) => (
                            <TableRow key={row.id}>
                              <TableCell>{formatDateShort(row.date)}</TableCell>
                              <TableCell>
                                <Badge
                                  variant={row.type === "IN" ? "default" : "secondary"}
                                  className={
                                    row.type === "IN"
                                      ? "bg-emerald-100 text-emerald-900"
                                      : "bg-red-50 text-red-800"
                                  }
                                >
                                  {row.type}
                                </Badge>
                              </TableCell>
                              <TableCell className="text-sm">{row.category}</TableCell>
                              <TableCell className="font-medium">{row.flockName}</TableCell>
                              <TableCell className="text-right tabular-nums font-medium">
                                {row.type === "OUT" ? "−" : "+"}
                                {row.quantity.toLocaleString()}
                              </TableCell>
                              <TableCell className="text-sm text-slate-600 max-w-[240px] truncate">
                                {row.description}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                        <TableFooter>
                          <TableRow className="bg-slate-50 hover:bg-slate-50">
                            <TableCell colSpan={4} className="font-medium text-slate-700">
                              {ledgerFiltersActive ? "Filtered total" : "Total"}
                              <span className="ml-2 font-normal text-slate-500">
                                ({sortedLedger.length.toLocaleString()} {sortedLedger.length === 1 ? "row" : "rows"})
                              </span>
                            </TableCell>
                            <TableCell className="text-right tabular-nums font-bold">
                              {ledgerInTotal - ledgerOutTotal >= 0 ? "+" : "−"}
                              {Math.abs(ledgerInTotal - ledgerOutTotal).toLocaleString()}
                            </TableCell>
                            <TableCell className="text-sm text-slate-600 whitespace-nowrap">
                              <span className="text-emerald-700">+{ledgerInTotal.toLocaleString()} in</span>
                              {" · "}
                              <span className="text-red-700">−{ledgerOutTotal.toLocaleString()} out</span>
                            </TableCell>
                          </TableRow>
                        </TableFooter>
                      </Table>
                      </>
                    )}
                    {sortedLedger.length > 0 && (
                      <div className="flex items-center justify-between gap-2 pt-4 border-t mt-4">
                        <div className="flex items-center gap-3">
                          <span className="text-xs text-slate-600">
                            Page {ledgerSafePage} of {ledgerTotalPages} ({sortedLedger.length} rows)
                          </span>
                          <Select
                            value={String(ledgerPageSize)}
                            onValueChange={(v) => {
                              setLedgerPageSize(Number(v))
                              setLedgerPage(1)
                            }}
                          >
                            <SelectTrigger className="h-8 w-[110px]" aria-label="Rows per page">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {TRACKER_PAGE_SIZE_OPTIONS.map((n) => (
                                <SelectItem key={n} value={String(n)}>
                                  {n} / page
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="flex gap-2">
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            disabled={ledgerSafePage <= 1}
                            onClick={() => setLedgerPage((p) => Math.max(1, p - 1))}
                          >
                            Previous
                          </Button>
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            disabled={ledgerSafePage >= ledgerTotalPages}
                            onClick={() => setLedgerPage((p) => Math.min(ledgerTotalPages, p + 1))}
                          >
                            Next
                          </Button>
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

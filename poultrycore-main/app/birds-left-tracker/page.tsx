"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Bird, RefreshCw } from "lucide-react"
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

const LEDGER_PAGE_SIZE = 20

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

  const ledgerTotalPages = Math.max(1, Math.ceil(sortedLedger.length / LEDGER_PAGE_SIZE))
  const ledgerSafePage = Math.min(ledgerPage, ledgerTotalPages)
  const paginatedLedger = sortedLedger.slice(
    (ledgerSafePage - 1) * LEDGER_PAGE_SIZE,
    ledgerSafePage * LEDGER_PAGE_SIZE,
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
                <div className={cn("grid gap-3", isMobile ? "grid-cols-1" : "grid-cols-1 sm:grid-cols-2")}>
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
                </div>

                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">By flock</CardTitle>
                    <CardDescription>
                      Compare calculated balance with the latest &ldquo;birds left&rdquo; on production records.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto table-scroll-wrapper pb-2">
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
                    </Table>
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
                    ) : (
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
                      </Table>
                    )}
                    {sortedLedger.length > LEDGER_PAGE_SIZE && (
                      <div className="flex items-center justify-between gap-2 pt-4 border-t mt-4">
                        <span className="text-xs text-slate-600">
                          Page {ledgerSafePage} of {ledgerTotalPages} ({sortedLedger.length} rows)
                        </span>
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

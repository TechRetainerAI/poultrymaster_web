"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { ChevronLeft, ChevronRight, RefreshCw, FileBarChart, Calendar as CalendarIcon } from "lucide-react"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getHouses, type House } from "@/lib/api/house"
import { getSales, type Sale } from "@/lib/api/sale"
import { getExpenses, type Expense } from "@/lib/api/expense"
import { getObservationByWeek, upsertObservation, type FarmObservation } from "@/lib/api/farm-observation"
import { getUserContext } from "@/lib/utils/user-context"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { cn } from "@/lib/utils"
import { Textarea } from "@/components/ui/textarea"
import { useToast } from "@/hooks/use-toast"
import { flockCountsTowardBirdTotals } from "@/lib/utils/flock-eligibility"

const EGGS_PER_CRATE = 30
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] as const

/** Date helpers — local-time Mon-anchored weeks. */
function startOfWeek(d: Date): Date {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  const day = (x.getDay() + 6) % 7 // Mon=0 … Sun=6
  x.setDate(x.getDate() - day)
  return x
}
function addDays(d: Date, n: number): Date {
  const x = new Date(d)
  x.setDate(x.getDate() + n)
  return x
}
function fmtShort(d: Date): string {
  return d.toLocaleDateString(undefined, { day: "numeric", month: "short" })
}

const isEggSale = (product: string | null | undefined) =>
  (product ?? "").toLowerCase().includes("egg")

export default function WeeklyReportPage() {
  const router = useRouter()
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [houses, setHouses] = useState<House[]>([])
  const [records, setRecords] = useState<ProductionRecord[]>([])
  const [sales, setSales] = useState<Sale[]>([])
  const [expenses, setExpenses] = useState<Expense[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState("")

  // Filters
  const [weekStart, setWeekStart] = useState<Date>(() => startOfWeek(new Date()))
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [flockFilter, setFlockFilter] = useState("ALL")
  const [houseFilter, setHouseFilter] = useState("ALL")

  // Observations (#15)
  const { toast } = useToast()
  const [observation, setObservation] = useState<FarmObservation | null>(null)
  const [obsNotes, setObsNotes] = useState("")
  const [obsSaving, setObsSaving] = useState(false)

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
    const [flocksRes, housesRes, prodRes, salesRes, expRes] = await Promise.all([
      getFlocks(userId, farmId),
      getHouses(userId, farmId),
      getProductionRecords(userId, farmId),
      getSales(userId, farmId),
      getExpenses(userId, farmId),
    ])
    setFlocks(flocksRes.success && flocksRes.data ? flocksRes.data : [])
    setHouses(housesRes.success && housesRes.data ? housesRes.data : [])
    if (prodRes.success && prodRes.data) {
      setRecords(prodRes.data)
      setError("")
    } else {
      setRecords([])
      setError(prodRes.message || "Failed to load production records")
    }
    setSales(salesRes.success && salesRes.data ? salesRes.data : [])
    setExpenses(expRes.success && expRes.data ? expRes.data : [])
    setLoading(false)
    setRefreshing(false)
  }, [])

  useEffect(() => {
    void loadData()
  }, [loadData])

  // Load weekly observation whenever the week changes.
  useEffect(() => {
    const { farmId } = getUserContext()
    if (!farmId) return
    const weekKey = toLocalDateKey(weekStart.toISOString())
    let cancelled = false
    ;(async () => {
      const res = await getObservationByWeek(farmId, weekKey)
      if (cancelled) return
      if (res.success) {
        setObservation(res.data ?? null)
        setObsNotes(res.data?.notes ?? "")
      } else {
        setObservation(null)
        setObsNotes("")
      }
    })()
    return () => {
      cancelled = true
    }
  }, [weekStart])

  const saveObservation = async () => {
    const { farmId, userId } = getUserContext()
    if (!farmId) return
    setObsSaving(true)
    const weekKey = toLocalDateKey(weekStart.toISOString())
    const res = await upsertObservation({
      farmId,
      userId: userId || null,
      weekStartDate: weekKey,
      notes: obsNotes.trim() ? obsNotes : null,
    })
    setObsSaving(false)
    if (res.success && res.data) {
      setObservation(res.data)
      toast({ title: "Observations saved", description: `Week of ${weekKey}` })
    } else {
      toast({ title: "Save failed", description: res.message || "Try again.", variant: "destructive" })
    }
  }

  // Effective date range: explicit From/To overrides the selected week.
  const range = useMemo(() => {
    if (dateFrom && dateTo) return { from: dateFrom, to: dateTo, label: `${dateFrom} → ${dateTo}` }
    const from = toLocalDateKey(weekStart.toISOString())
    const to = toLocalDateKey(addDays(weekStart, 6).toISOString())
    return { from, to, label: `${fmtShort(weekStart)} – ${fmtShort(addDays(weekStart, 6))}` }
  }, [weekStart, dateFrom, dateTo])

  // Filter active/started flocks for selectors (consistent with other pages).
  const eligibleFlocks = useMemo(
    () => flocks.filter((f) => flockCountsTowardBirdTotals(f)),
    [flocks],
  )

  // Apply filters to records / sales / expenses.
  const filteredRecords = useMemo(() => {
    return records.filter((r) => {
      const k = toLocalDateKey(r.date)
      if (k < range.from || k > range.to) return false
      if (flockFilter !== "ALL" && String(r.flockId) !== flockFilter) return false
      if (houseFilter !== "ALL") {
        const f = flocks.find((x) => x.flockId === r.flockId)
        if (!f || String(f.houseId ?? "") !== houseFilter) return false
      }
      return true
    })
  }, [records, range.from, range.to, flockFilter, houseFilter, flocks])

  const filteredSales = useMemo(() => {
    return sales.filter((s) => {
      const k = toLocalDateKey(s.saleDate)
      if (k < range.from || k > range.to) return false
      if (flockFilter !== "ALL" && String(s.flockId) !== flockFilter) return false
      if (houseFilter !== "ALL") {
        const f = flocks.find((x) => x.flockId === s.flockId)
        if (!f || String(f.houseId ?? "") !== houseFilter) return false
      }
      return true
    })
  }, [sales, range.from, range.to, flockFilter, houseFilter, flocks])

  const filteredExpenses = useMemo(() => {
    return expenses.filter((e) => {
      const k = toLocalDateKey(e.expenseDate)
      if (k < range.from || k > range.to) return false
      if (flockFilter !== "ALL" && String(e.flockId) !== flockFilter) return false
      return true
    })
  }, [expenses, range.from, range.to, flockFilter])

  // ---- Summary metrics (#16) ----
  const totalEggsCollected = useMemo(
    () => filteredRecords.reduce((s, r) => s + (Number(r.totalProduction) || 0), 0),
    [filteredRecords],
  )
  const eggSales = useMemo(() => filteredSales.filter((s) => isEggSale(s.product)), [filteredSales])
  const totalEggsSold = useMemo(
    () => eggSales.reduce((s, x) => s + (Number(x.quantity) || 0), 0),
    [eggSales],
  )
  const totalRevenue = useMemo(
    () => eggSales.reduce((s, x) => s + (Number(x.totalAmount) || 0), 0),
    [eggSales],
  )
  const totalExpenses = useMemo(
    () => filteredExpenses.reduce((s, e) => s + (Number(e.amount) || 0), 0),
    [filteredExpenses],
  )
  const remainingEggs = Math.max(0, totalEggsCollected - totalEggsSold)
  const netBalance = totalRevenue - totalExpenses

  // ---- Daily egg collection grid (#6 + #7) ----
  // Build a key map: flockId → 7-day array of eggs.
  const dailyByFlock = useMemo(() => {
    const map = new Map<number, number[]>()
    const visibleFlocks =
      flockFilter !== "ALL"
        ? flocks.filter((f) => String(f.flockId) === flockFilter)
        : eligibleFlocks
    for (const f of visibleFlocks) map.set(f.flockId, [0, 0, 0, 0, 0, 0, 0])

    for (const r of filteredRecords) {
      if (r.flockId == null) continue
      if (!map.has(r.flockId)) continue
      const d = new Date(r.date)
      const idx = (d.getDay() + 6) % 7 // Mon=0
      const arr = map.get(r.flockId)!
      arr[idx] += Number(r.totalProduction) || 0
    }
    return map
  }, [filteredRecords, flocks, eligibleFlocks, flockFilter])

  // ---- Room production summary (#10) ----
  const roomSummary = useMemo(() => {
    const houseMap = new Map<number, { name: string; eggs: number; sold: number }>()
    // Seed every house so empty ones still appear.
    for (const h of houses) houseMap.set(h.houseId, { name: h.name, eggs: 0, sold: 0 })
    // No house? Still show as "Unassigned".
    const unassigned = { name: "Unassigned", eggs: 0, sold: 0 }
    const flockToHouse = new Map<number, number | null>()
    for (const f of flocks) flockToHouse.set(f.flockId, f.houseId ?? null)

    for (const r of filteredRecords) {
      const eggs = Number(r.totalProduction) || 0
      if (eggs <= 0 || r.flockId == null) continue
      const hid = flockToHouse.get(r.flockId)
      if (hid != null && houseMap.has(hid)) houseMap.get(hid)!.eggs += eggs
      else unassigned.eggs += eggs
    }
    for (const s of filteredSales) {
      if (!isEggSale(s.product)) continue
      const q = Number(s.quantity) || 0
      if (q <= 0 || s.flockId == null) continue
      const hid = flockToHouse.get(s.flockId)
      if (hid != null && houseMap.has(hid)) houseMap.get(hid)!.sold += q
      else unassigned.sold += q
    }
    const rows = Array.from(houseMap.values()).filter((r) => r.eggs > 0 || r.sold > 0)
    if (unassigned.eggs > 0 || unassigned.sold > 0) rows.push(unassigned)
    return rows
      .map((r) => ({
        ...r,
        crates: Math.floor(r.eggs / EGGS_PER_CRATE),
        remaining: Math.max(0, r.eggs - r.sold),
      }))
      .sort((a, b) => b.eggs - a.eggs)
  }, [houses, flocks, filteredRecords, filteredSales])

  // ---- Weekly sales summary (#11) ----
  const totalCratesSold = Math.floor(totalEggsSold / EGGS_PER_CRATE)
  const totalCratesCollected = Math.floor(totalEggsCollected / EGGS_PER_CRATE)

  // ---- Expenditure list (#12) ----
  const expenseRows = useMemo(
    () =>
      filteredExpenses
        .slice()
        .sort((a, b) => (a.expenseDate < b.expenseDate ? -1 : a.expenseDate > b.expenseDate ? 1 : 0)),
    [filteredExpenses],
  )

  // ---- Egg sales by size (#8) ----
  const salesBySize = useMemo(() => {
    const m = new Map<string, { trays: number; revenue: number; totalUnitPrice: number; saleCount: number }>()
    for (const s of eggSales) {
      const key = (s.size && s.size.trim()) || "Unspecified"
      const trays = Number(s.quantity) || 0 // "trays" === Sale.quantity (caller-counted units)
      const revenue = Number(s.totalAmount) || 0
      const unit = Number(s.unitPrice) || 0
      const cur = m.get(key) ?? { trays: 0, revenue: 0, totalUnitPrice: 0, saleCount: 0 }
      cur.trays += trays
      cur.revenue += revenue
      cur.totalUnitPrice += unit
      cur.saleCount += 1
      m.set(key, cur)
    }
    return Array.from(m.entries())
      .map(([size, v]) => ({
        size,
        trays: v.trays,
        avgPrice: v.saleCount ? v.totalUnitPrice / v.saleCount : 0,
        revenue: v.revenue,
      }))
      .sort((a, b) => b.revenue - a.revenue)
  }, [eggSales])

  // ---- Egg loss (#9) ----
  const eggLoss = useMemo(() => {
    let broken = 0, meaty = 0, soft = 0, lost = 0
    for (const r of filteredRecords) {
      broken += Number(r.brokenEggs) || 0
      meaty += Number(r.meatyEggs) || 0
      soft += Number(r.softEggs) || 0
      lost += Number(r.lostEggs) || 0
    }
    return { broken, meaty, soft, lost, total: broken + meaty + soft + lost }
  }, [filteredRecords])

  // ---- Debtors (#14): unpaid sales in range, grouped by customer ----
  const debtors = useMemo(() => {
    const m = new Map<string, number>()
    for (const s of filteredSales) {
      if (s.paid) continue
      const name = (s.customerName || "Unknown").trim() || "Unknown"
      m.set(name, (m.get(name) ?? 0) + (Number(s.totalAmount) || 0))
    }
    return Array.from(m.entries())
      .map(([customer, amount]) => ({ customer, amount }))
      .filter((r) => r.amount > 0)
      .sort((a, b) => b.amount - a.amount)
  }, [filteredSales])
  const totalDebt = useMemo(() => debtors.reduce((s, d) => s + d.amount, 0), [debtors])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-emerald-100 rounded-lg flex items-center justify-center">
                  <FileBarChart className="w-5 h-5 text-emerald-700" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">
                    Weekly Poultry Production Report
                  </h1>
                  <p className="text-sm text-slate-600 mt-1">
                    Week of <span className="font-semibold">{range.label}</span>. All totals
                    update automatically based on the selected period.
                  </p>
                </div>
              </div>
              <Button
                type="button"
                variant="outline"
                className="shrink-0 gap-2"
                onClick={() => {
                  setRefreshing(true)
                  void loadData()
                }}
                disabled={refreshing || loading}
              >
                <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
                Refresh
              </Button>
            </div>

            {/* Filters (#5) */}
            <Card className="bg-white">
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Filters</CardTitle>
                <CardDescription>Pick a week, or override with an explicit date range.</CardDescription>
              </CardHeader>
              <CardContent className="grid gap-3 md:grid-cols-2 lg:grid-cols-5">
                <div className="flex items-center gap-1">
                  <Button
                    variant="outline"
                    size="icon"
                    aria-label="Previous week"
                    onClick={() => setWeekStart((w) => addDays(w, -7))}
                  >
                    <ChevronLeft className="h-4 w-4" />
                  </Button>
                  <div className="flex items-center gap-2 px-2 py-1 rounded-md bg-slate-50 border text-sm font-medium text-slate-700 flex-1 min-w-0 justify-center">
                    <CalendarIcon className="h-3.5 w-3.5 text-slate-500" />
                    <span className="truncate">{fmtShort(weekStart)} – {fmtShort(addDays(weekStart, 6))}</span>
                  </div>
                  <Button
                    variant="outline"
                    size="icon"
                    aria-label="Next week"
                    onClick={() => setWeekStart((w) => addDays(w, 7))}
                  >
                    <ChevronRight className="h-4 w-4" />
                  </Button>
                </div>
                <Input
                  type="date"
                  value={dateFrom}
                  onChange={(e) => setDateFrom(e.target.value)}
                  placeholder="From"
                />
                <Input
                  type="date"
                  value={dateTo}
                  onChange={(e) => setDateTo(e.target.value)}
                  placeholder="To"
                />
                <Select value={flockFilter} onValueChange={setFlockFilter}>
                  <SelectTrigger>
                    <SelectValue placeholder="Flock" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All flocks</SelectItem>
                    {eligibleFlocks.map((f) => (
                      <SelectItem key={f.flockId} value={String(f.flockId)}>
                        {f.name || `Flock #${f.flockId}`}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select value={houseFilter} onValueChange={setHouseFilter}>
                  <SelectTrigger>
                    <SelectValue placeholder="Room / House" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All rooms</SelectItem>
                    {houses.map((h) => (
                      <SelectItem key={h.houseId} value={String(h.houseId)}>
                        {h.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <div className="md:col-span-2 lg:col-span-5 flex justify-end">
                  {(dateFrom || dateTo || flockFilter !== "ALL" || houseFilter !== "ALL") && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => {
                        setDateFrom("")
                        setDateTo("")
                        setFlockFilter("ALL")
                        setHouseFilter("ALL")
                      }}
                    >
                      Reset filters
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center text-slate-600">Loading weekly report…</CardContent>
              </Card>
            ) : (
              <>
                {/* Summary cards (#16) */}
                <div className="grid gap-3 grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
                  <SummaryCard label="Total Eggs Collected" value={totalEggsCollected.toLocaleString()} accent="emerald" />
                  <SummaryCard label="Total Eggs Sold" value={totalEggsSold.toLocaleString()} accent="sky" />
                  <SummaryCard label="Total Revenue" value={totalRevenue.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })} accent="violet" />
                  <SummaryCard label="Total Expenses" value={totalExpenses.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })} accent="amber" />
                  <SummaryCard label="Remaining Eggs" value={remainingEggs.toLocaleString()} accent="slate" />
                  <SummaryCard
                    label="Net Balance"
                    value={netBalance.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })}
                    accent={netBalance >= 0 ? "emerald" : "rose"}
                  />
                </div>

                {/* Daily Egg Collection (#6 + #7) */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Daily Egg Collection</CardTitle>
                    <CardDescription>
                      Eggs collected per flock (Mon–Sun). Time-of-day rollup uses 9 AM, 12 PM and 4 PM fields already on each record.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table className="w-full min-w-[820px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Room / Flock</TableHead>
                          {WEEKDAYS.map((d) => (
                            <TableHead key={d} className="text-right">{d}</TableHead>
                          ))}
                          <TableHead className="text-right">Total</TableHead>
                          <TableHead className="text-right">Crates</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {dailyByFlock.size === 0 ? (
                          <TableRow>
                            <TableCell colSpan={WEEKDAYS.length + 3} className="text-center text-slate-500 py-8">
                              No flocks match the current filters.
                            </TableCell>
                          </TableRow>
                        ) : (
                          Array.from(dailyByFlock.entries()).map(([fid, days]) => {
                            const flock = flocks.find((f) => f.flockId === fid)
                            const flockName = flock?.name ?? `Flock #${fid}`
                            const house = houses.find((h) => h.houseId === flock?.houseId)?.name
                            const total = days.reduce((s, x) => s + x, 0)
                            const crates = Math.floor(total / EGGS_PER_CRATE)
                            return (
                              <TableRow key={fid}>
                                <TableCell className="font-medium">
                                  <div>{flockName}</div>
                                  {house && <div className="text-xs text-slate-500">{house}</div>}
                                </TableCell>
                                {days.map((n, i) => (
                                  <TableCell key={i} className="text-right tabular-nums">
                                    {n ? n.toLocaleString() : "—"}
                                  </TableCell>
                                ))}
                                <TableCell className="text-right tabular-nums font-semibold">{total.toLocaleString()}</TableCell>
                                <TableCell className="text-right tabular-nums text-slate-600">{crates.toLocaleString()}</TableCell>
                              </TableRow>
                            )
                          })
                        )}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                {/* Room Production Summary (#10) */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Room Production Summary</CardTitle>
                    <CardDescription>Eggs collected, crates and remaining eggs per room. Remaining = collected − sold.</CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table className="w-full min-w-[560px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Room</TableHead>
                          <TableHead className="text-right">Eggs Collected</TableHead>
                          <TableHead className="text-right">Crates</TableHead>
                          <TableHead className="text-right">Remaining Eggs</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {roomSummary.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={4} className="text-center text-slate-500 py-8">
                              No room data for this period.
                            </TableCell>
                          </TableRow>
                        ) : (
                          roomSummary.map((r) => (
                            <TableRow key={r.name}>
                              <TableCell className="font-medium">{r.name}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.eggs.toLocaleString()}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.crates.toLocaleString()}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.remaining.toLocaleString()}</TableCell>
                            </TableRow>
                          ))
                        )}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                {/* Weekly sales + financial (#11 + #13) */}
                <div className="grid gap-4 md:grid-cols-2">
                  <Card className="bg-white">
                    <CardHeader className="pb-2">
                      <CardTitle className="text-base">Weekly Sales Summary</CardTitle>
                      <CardDescription>Egg sales only (other product sales are excluded).</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <dl className="grid grid-cols-2 gap-y-3 text-sm">
                        <dt className="text-slate-600">Total eggs sold</dt>
                        <dd className="text-right font-semibold tabular-nums">{totalEggsSold.toLocaleString()}</dd>
                        <dt className="text-slate-600">Total crates sold</dt>
                        <dd className="text-right font-semibold tabular-nums">{totalCratesSold.toLocaleString()}</dd>
                        <dt className="text-slate-600">Crates collected</dt>
                        <dd className="text-right font-semibold tabular-nums">{totalCratesCollected.toLocaleString()}</dd>
                        <dt className="text-slate-600">Total revenue</dt>
                        <dd className="text-right font-bold text-emerald-700 tabular-nums">
                          {totalRevenue.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })}
                        </dd>
                      </dl>
                    </CardContent>
                  </Card>

                  <Card className="bg-white">
                    <CardHeader className="pb-2">
                      <CardTitle className="text-base">Weekly Financial Summary</CardTitle>
                      <CardDescription>Balance = Income − Expenditure.</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <dl className="grid grid-cols-2 gap-y-3 text-sm">
                        <dt className="text-slate-600">Income (egg sales)</dt>
                        <dd className="text-right font-semibold text-emerald-700 tabular-nums">
                          {totalRevenue.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })}
                        </dd>
                        <dt className="text-slate-600">Expenditure</dt>
                        <dd className="text-right font-semibold text-rose-700 tabular-nums">
                          {totalExpenses.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })}
                        </dd>
                        <dt className="text-slate-900 font-semibold pt-2 border-t">Balance</dt>
                        <dd
                          className={cn(
                            "text-right font-bold tabular-nums pt-2 border-t",
                            netBalance >= 0 ? "text-emerald-700" : "text-rose-700",
                          )}
                        >
                          {netBalance.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })}
                        </dd>
                      </dl>
                      <div className="mt-3">
                        <Badge variant={netBalance >= 0 ? "default" : "destructive"}>
                          {netBalance >= 0 ? "Profit for the period" : "Loss for the period"}
                        </Badge>
                      </div>
                    </CardContent>
                  </Card>
                </div>

                {/* Weekly Expenditure (#12) */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Weekly Expenditure</CardTitle>
                    <CardDescription>Every expense in the selected period.</CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table className="w-full min-w-[560px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Date</TableHead>
                          <TableHead>Item</TableHead>
                          <TableHead>Category</TableHead>
                          <TableHead className="text-right">Price</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {expenseRows.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={4} className="text-center text-slate-500 py-8">
                              No expenses in this period.
                            </TableCell>
                          </TableRow>
                        ) : (
                          <>
                            {expenseRows.map((e) => (
                              <TableRow key={e.expenseId}>
                                <TableCell className="font-mono text-xs">{toLocalDateKey(e.expenseDate)}</TableCell>
                                <TableCell className="font-medium">{e.description || "—"}</TableCell>
                                <TableCell className="text-slate-600">{e.category || "—"}</TableCell>
                                <TableCell className="text-right tabular-nums">
                                  {Number(e.amount).toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 })}
                                </TableCell>
                              </TableRow>
                            ))}
                            <TableRow className="bg-slate-50">
                              <TableCell colSpan={3} className="text-right font-semibold">Total Expenditure</TableCell>
                              <TableCell className="text-right font-bold text-rose-700 tabular-nums">
                                {totalExpenses.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 })}
                              </TableCell>
                            </TableRow>
                          </>
                        )}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                {/* Debtors (#14) */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Debtors</CardTitle>
                    <CardDescription>
                      Customers with unpaid sales in the selected period. Mark a sale as paid on the Sales page to clear.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table className="w-full min-w-[420px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Customer</TableHead>
                          <TableHead className="text-right">Amount Owed</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {debtors.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={2} className="text-center text-slate-500 py-8">
                              No outstanding debts in this period.
                            </TableCell>
                          </TableRow>
                        ) : (
                          <>
                            {debtors.map((d) => (
                              <TableRow key={d.customer}>
                                <TableCell className="font-medium">{d.customer}</TableCell>
                                <TableCell className="text-right tabular-nums text-amber-800 font-semibold">
                                  {d.amount.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 })}
                                </TableCell>
                              </TableRow>
                            ))}
                            <TableRow className="bg-slate-50">
                              <TableCell className="text-right font-semibold">Total Outstanding</TableCell>
                              <TableCell className="text-right font-bold text-amber-900 tabular-nums">
                                {totalDebt.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 })}
                              </TableCell>
                            </TableRow>
                          </>
                        )}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                {/* Egg Sales by Size (#8) */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Egg Sales by Size</CardTitle>
                    <CardDescription>
                      Grouped by the Sale.size field (added by migration 018). Sales without a size appear as &ldquo;Unspecified&rdquo;.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table className="w-full min-w-[520px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Size</TableHead>
                          <TableHead className="text-right">Trays</TableHead>
                          <TableHead className="text-right">Avg Price / Tray</TableHead>
                          <TableHead className="text-right">Total</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {salesBySize.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={4} className="text-center text-slate-500 py-8">
                              No egg sales in this period.
                            </TableCell>
                          </TableRow>
                        ) : (
                          <>
                            {salesBySize.map((s) => (
                              <TableRow key={s.size}>
                                <TableCell className="font-medium">{s.size}</TableCell>
                                <TableCell className="text-right tabular-nums">{s.trays.toLocaleString()}</TableCell>
                                <TableCell className="text-right tabular-nums text-slate-600">
                                  {s.avgPrice.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 })}
                                </TableCell>
                                <TableCell className="text-right tabular-nums font-semibold text-emerald-700">
                                  {s.revenue.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 })}
                                </TableCell>
                              </TableRow>
                            ))}
                            <TableRow className="bg-slate-50">
                              <TableCell className="font-semibold">Total</TableCell>
                              <TableCell className="text-right font-semibold tabular-nums">
                                {salesBySize.reduce((s, x) => s + x.trays, 0).toLocaleString()}
                              </TableCell>
                              <TableCell />
                              <TableCell className="text-right font-bold text-emerald-800 tabular-nums">
                                {salesBySize.reduce((s, x) => s + x.revenue, 0).toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 })}
                              </TableCell>
                            </TableRow>
                          </>
                        )}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                {/* Egg Loss Tracking (#9) */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Egg Loss Tracking</CardTitle>
                    <CardDescription>
                      Totals across production records in the selected period. New loss fields (Meaty / Soft / Lost) require entries logged via the production-record form to populate.
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <div className="grid gap-3 grid-cols-2 sm:grid-cols-4">
                      <LossStat label="Broken" value={eggLoss.broken} accent="rose" />
                      <LossStat label="Meaty" value={eggLoss.meaty} accent="amber" />
                      <LossStat label="Soft" value={eggLoss.soft} accent="violet" />
                      <LossStat label="Lost" value={eggLoss.lost} accent="slate" />
                    </div>
                    <div className="mt-4 pt-3 border-t flex items-baseline justify-between">
                      <span className="text-sm font-semibold text-slate-700">Total eggs lost</span>
                      <span className="text-xl font-bold tabular-nums text-rose-700">{eggLoss.total.toLocaleString()}</span>
                    </div>
                  </CardContent>
                </Card>

                {/* Observations / Notes (#15) */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Observations / Notes</CardTitle>
                    <CardDescription>
                      Free-text notes for week of {range.label}. Auto-saved per (farm, week).
                      {observation?.updatedAt && (
                        <span className="ml-2 text-xs text-slate-400">
                          Last saved {new Date(observation.updatedAt).toLocaleString()}
                        </span>
                      )}
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-3">
                    <Textarea
                      value={obsNotes}
                      onChange={(e) => setObsNotes(e.target.value)}
                      placeholder={"Eggs remaining for the week\nBirds remaining\nFeed purchases\nFeed debts\nMoney brought home"}
                      rows={6}
                      className="resize-y"
                    />
                    <div className="flex justify-end">
                      <Button onClick={saveObservation} disabled={obsSaving}>
                        {obsSaving ? "Saving…" : "Save observations"}
                      </Button>
                    </div>
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

function LossStat({
  label,
  value,
  accent,
}: {
  label: string
  value: number
  accent: "rose" | "amber" | "violet" | "slate"
}) {
  const colors: Record<string, string> = {
    rose: "text-rose-700 bg-rose-50 border-rose-200",
    amber: "text-amber-700 bg-amber-50 border-amber-200",
    violet: "text-violet-700 bg-violet-50 border-violet-200",
    slate: "text-slate-700 bg-slate-50 border-slate-200",
  }
  return (
    <div className={cn("p-3 rounded-lg border", colors[accent])}>
      <div className="text-xs font-medium uppercase tracking-wider opacity-80">{label}</div>
      <div className="text-xl font-bold tabular-nums mt-0.5">{value.toLocaleString()}</div>
    </div>
  )
}

function SummaryCard({
  label,
  value,
  accent,
}: {
  label: string
  value: string
  accent: "emerald" | "sky" | "violet" | "amber" | "slate" | "rose"
}) {
  const colors: Record<string, string> = {
    emerald: "text-emerald-700",
    sky: "text-sky-700",
    violet: "text-violet-700",
    amber: "text-amber-700",
    slate: "text-slate-800",
    rose: "text-rose-700",
  }
  return (
    <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
      <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">{label}</div>
      <div className={cn("text-xl sm:text-2xl font-bold tabular-nums mt-1", colors[accent])}>{value}</div>
    </div>
  )
}

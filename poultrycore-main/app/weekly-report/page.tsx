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
import { ChevronLeft, ChevronRight, RefreshCw, FileBarChart, Calendar as CalendarIcon, Printer } from "lucide-react"
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
type RangeMode = "week" | "month" | "range" | "all"
/** Sentinel range that effectively means "no date filter". */
const ALL_TIME_FROM = "1970-01-01"
const ALL_TIME_TO = "9999-12-31"

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
function fmtMonth(yyyymm: string): string {
  // "2026-05" → "May 2026"
  const [y, m] = yyyymm.split("-").map(Number)
  if (!y || !m) return yyyymm
  return new Date(y, m - 1, 1).toLocaleDateString(undefined, { month: "long", year: "numeric" })
}
function monthStart(yyyymm: string): string {
  return `${yyyymm}-01`
}
function monthEnd(yyyymm: string): string {
  const [y, m] = yyyymm.split("-").map(Number)
  const last = new Date(y, m, 0).getDate() // day 0 of next month = last day of this month
  return `${yyyymm}-${String(last).padStart(2, "0")}`
}
/** Build a list of months that appear in the loaded data, plus the current month. Newest first. */
function deriveMonthOptions(records: { date: string }[], sales: { saleDate: string }[]): string[] {
  const set = new Set<string>()
  const now = new Date()
  set.add(`${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`)
  for (const r of records) {
    const d = new Date(r.date)
    if (!Number.isNaN(d.getTime())) set.add(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`)
  }
  for (const s of sales) {
    const d = new Date(s.saleDate)
    if (!Number.isNaN(d.getTime())) set.add(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`)
  }
  return Array.from(set).sort().reverse()
}

const isEggSale = (product: string | null | undefined) =>
  (product ?? "").toLowerCase().includes("egg")

/**
 * Amount still owed on a sale. Mirrors `saleOwed` on the Sales page: `amountPaid`
 * (migration 145) is the source of truth, and the binary `paid` flag is only a
 * fallback for rows an older backend never populated.
 */
function saleOwed(s: Sale): number {
  const total = Number(s.totalAmount) || 0
  const paidAmt = s.amountPaid != null ? Number(s.amountPaid) : s.paid === false ? 0 : total
  return Math.max(0, total - paidAmt)
}

/**
 * Saleable eggs from one production record: the picks less every non-saleable
 * category, floored at 0 so an over-recorded loss can't post negative stock.
 * This is the definition migration 198 made canonical across the backend — keep
 * it in step with `EGG_LOSS_LINES` in lib/utils/egg-ledger.ts.
 */
function saleableEggsOf(r: ProductionRecord): number {
  const collected = Number(r.totalProduction) || 0
  const losses =
    (Number(r.brokenEggs) || 0) +
    (Number(r.meatyEggs) || 0) +
    (Number(r.softEggs) || 0) +
    (Number(r.lostEggs) || 0)
  return Math.max(0, collected - losses)
}

/**
 * Crates as "12" or "12 + 7" (crates plus loose eggs). Every crate figure is
 * derived from an egg count this way, so per-row crates never silently lose the
 * remainder and stop adding up to the total.
 */
function formatCrates(eggs: number): string {
  const n = Math.max(0, eggs)
  const crates = Math.floor(n / EGGS_PER_CRATE)
  const loose = n % EGGS_PER_CRATE
  return loose ? `${crates.toLocaleString()} + ${loose}` : crates.toLocaleString()
}

/** "2026-05-12" → local Date (midnight). Null when the key isn't a real date. */
function parseDateKey(key: string): Date | null {
  const [y, m, d] = key.split("-").map(Number)
  if (!y || !m || !d) return null
  return new Date(y, m - 1, d)
}

/** Beyond this many days the daily grid drops its per-day columns. */
const MAX_DAY_COLUMNS = 31

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
  const [mode, setMode] = useState<RangeMode>("week")
  const [weekStart, setWeekStart] = useState<Date>(() => startOfWeek(new Date()))
  const [selectedMonth, setSelectedMonth] = useState<string>(() => {
    const n = new Date()
    return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, "0")}`
  })
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

  // Effective date range derived from the active mode.
  const range = useMemo(() => {
    if (mode === "all") {
      return { from: ALL_TIME_FROM, to: ALL_TIME_TO, label: "All time" }
    }
    if (mode === "month") {
      return { from: monthStart(selectedMonth), to: monthEnd(selectedMonth), label: fmtMonth(selectedMonth) }
    }
    if (mode === "range" && dateFrom && dateTo) {
      return { from: dateFrom, to: dateTo, label: `${dateFrom} → ${dateTo}` }
    }
    // Default: week (Mon-Sun anchored on weekStart).
    const from = toLocalDateKey(weekStart.toISOString())
    const to = toLocalDateKey(addDays(weekStart, 6).toISOString())
    return { from, to, label: `${fmtShort(weekStart)} – ${fmtShort(addDays(weekStart, 6))}` }
  }, [mode, weekStart, selectedMonth, dateFrom, dateTo])

  const monthOptions = useMemo(() => deriveMonthOptions(records, sales), [records, sales])

  // Filter active/started flocks for selectors (consistent with other pages).
  const eligibleFlocks = useMemo(
    () => flocks.filter((f) => flockCountsTowardBirdTotals(f)),
    [flocks],
  )

  // Apply filters to records / sales / expenses.
  // The flock/room test is split out from the date test because the stock
  // figures below need the same scope over *all* history, not just this period.
  const inFlockScope = useCallback(
    (flockId: number | null | undefined) => {
      if (flockFilter !== "ALL" && String(flockId) !== flockFilter) return false
      if (houseFilter !== "ALL") {
        const f = flocks.find((x) => x.flockId === flockId)
        if (!f || String(f.houseId ?? "") !== houseFilter) return false
      }
      return true
    },
    [flockFilter, houseFilter, flocks],
  )

  const filteredRecords = useMemo(() => {
    return records.filter((r) => {
      const k = toLocalDateKey(r.date)
      if (k < range.from || k > range.to) return false
      return inFlockScope(r.flockId)
    })
  }, [records, range.from, range.to, inFlockScope])

  const filteredSales = useMemo(() => {
    return sales.filter((s) => {
      const k = toLocalDateKey(s.saleDate)
      if (k < range.from || k > range.to) return false
      return inFlockScope(s.flockId)
    })
  }, [sales, range.from, range.to, inFlockScope])

  /** Flocks housed in the selected room — null when no room filter is active. */
  const houseFlockIds = useMemo(() => {
    if (houseFilter === "ALL") return null
    return new Set(
      flocks.filter((f) => String(f.houseId ?? "") === houseFilter).map((f) => f.flockId),
    )
  }, [houseFilter, flocks])

  const filteredExpenses = useMemo(() => {
    return expenses.filter((e) => {
      const k = toLocalDateKey(e.expenseDate)
      if (k < range.from || k > range.to) return false
      if (flockFilter !== "ALL" && String(e.flockId) !== flockFilter) return false
      // Room filter: keep only expenses attributed to a flock in that room, so
      // the Balance below compares like with like. Farm-wide expenses (no flock)
      // drop out for the same reason sales without a flock do.
      if (houseFlockIds && (e.flockId == null || !houseFlockIds.has(Number(e.flockId)))) return false
      return true
    })
  }, [expenses, range.from, range.to, flockFilter, houseFlockIds])

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
  /** Egg-only revenue, kept separate so the Sales Summary can break it out. */
  const eggRevenue = useMemo(
    () => eggSales.reduce((s, x) => s + (Number(x.totalAmount) || 0), 0),
    [eggSales],
  )
  /** Income for the Financial Summary = every sale in the period, not just eggs. */
  const totalRevenue = useMemo(
    () => filteredSales.reduce((s, x) => s + (Number(x.totalAmount) || 0), 0),
    [filteredSales],
  )
  const otherRevenue = totalRevenue - eggRevenue
  const totalExpenses = useMemo(
    () => filteredExpenses.reduce((s, e) => s + (Number(e.amount) || 0), 0),
    [filteredExpenses],
  )
  const netBalance = totalRevenue - totalExpenses

  // ---- Egg stock (#9) ----
  // Saleable eggs collected in the period. Losses are deducted because an egg is
  // only on hand if it isn't broken, meaty, soft-shelled or lost — same rule as
  // migration 198 / spPoultryReport_EggStockBalance and lib/utils/egg-ledger.ts.
  const periodSaleableEggs = useMemo(
    () => filteredRecords.reduce((s, r) => s + saleableEggsOf(r), 0),
    [filteredRecords],
  )
  /**
   * Saleable minus sold *within the period only*. Goes negative when the period's
   * sales drew on stock collected earlier, which is real information — hence no
   * clamp at zero.
   */
  const periodUnsoldEggs = periodSaleableEggs - totalEggsSold
  /**
   * Actual eggs on hand as at the end of the period: every saleable egg ever
   * collected, less every egg ever sold, up to `range.to`. The old figure was
   * period-scoped collected − sold, which silently ignored losses and treated
   * carried-over stock as if it had never existed.
   */
  const eggsInStock = useMemo(() => {
    let collected = 0
    for (const r of records) {
      if (toLocalDateKey(r.date) > range.to) continue
      if (!inFlockScope(r.flockId)) continue
      collected += saleableEggsOf(r)
    }
    let sold = 0
    for (const s of sales) {
      if (!isEggSale(s.product)) continue
      if (toLocalDateKey(s.saleDate) > range.to) continue
      if (!inFlockScope(s.flockId)) continue
      sold += Number(s.quantity) || 0
    }
    return collected - sold
  }, [records, sales, range.to, inFlockScope])

  // ---- Daily egg collection grid (#6 + #7) ----
  // Columns are real calendar days, not weekday buckets — otherwise a month or
  // an all-time range would stack four-plus Mondays into a single "Mon" cell.
  const spanBounds = useMemo(() => {
    if (mode !== "all") return { from: range.from, to: range.to }
    // "All time" has sentinel bounds; use the span the data actually covers.
    const keys = filteredRecords.map((r) => toLocalDateKey(r.date)).filter(Boolean).sort()
    if (keys.length === 0) return null
    return { from: keys[0], to: keys[keys.length - 1] }
  }, [mode, range.from, range.to, filteredRecords])

  const dayColumns = useMemo(() => {
    if (!spanBounds) return []
    const from = parseDateKey(spanBounds.from)
    const to = parseDateKey(spanBounds.to)
    if (!from || !to || to < from) return []
    const days = Math.round((to.getTime() - from.getTime()) / 86_400_000) + 1
    if (days > MAX_DAY_COLUMNS) return []
    return Array.from({ length: days }, (_, i) => {
      const d = addDays(from, i)
      return {
        key: toLocalDateKey(d.toISOString()),
        // A single week reads best as Mon–Sun; longer spans need the date.
        label: days <= 7 ? WEEKDAYS[(d.getDay() + 6) % 7] : `${d.getDate()}/${d.getMonth() + 1}`,
      }
    })
  }, [spanBounds])

  /**
   * One row per flock that has production in range — including flocks that no
   * longer count toward bird totals, and an "Unassigned" row for records with no
   * flock. Anything less and these rows wouldn't add up to Total Eggs Collected.
   */
  const dailyRows = useMemo(() => {
    const colIndex = new Map(dayColumns.map((c, i) => [c.key, i]))
    const rows = new Map<string, { key: string; name: string; house?: string; days: number[]; total: number }>()
    const ensure = (key: string, name: string, house?: string) => {
      let row = rows.get(key)
      if (!row) {
        row = { key, name, house, days: dayColumns.map(() => 0), total: 0 }
        rows.set(key, row)
      }
      return row
    }
    const houseNameOf = (f: Flock | undefined) =>
      houses.find((h) => h.houseId === f?.houseId)?.name

    // Seed the flocks the filters select so an empty flock still shows a row.
    const visibleFlocks =
      flockFilter !== "ALL"
        ? flocks.filter((f) => String(f.flockId) === flockFilter)
        : eligibleFlocks
    for (const f of visibleFlocks) {
      ensure(String(f.flockId), f.name || `Flock #${f.flockId}`, houseNameOf(f))
    }

    for (const r of filteredRecords) {
      const eggs = Number(r.totalProduction) || 0
      const flock = r.flockId != null ? flocks.find((f) => f.flockId === r.flockId) : undefined
      const key = r.flockId != null ? String(r.flockId) : "unassigned"
      const name =
        flock?.name || (r.flockId != null ? `Flock #${r.flockId}` : "Unassigned")
      const row = ensure(key, name, houseNameOf(flock))
      row.total += eggs
      const i = colIndex.get(toLocalDateKey(r.date))
      if (i != null) row.days[i] += eggs
    }
    return Array.from(rows.values())
  }, [filteredRecords, flocks, houses, eligibleFlocks, flockFilter, dayColumns])

  const dailyDayTotals = useMemo(
    () => dayColumns.map((_, i) => dailyRows.reduce((s, r) => s + r.days[i], 0)),
    [dailyRows, dayColumns],
  )

  // ---- Room production summary (#10) ----
  const roomSummary = useMemo(() => {
    type RoomRow = { name: string; eggs: number; losses: number; saleable: number; sold: number }
    const blank = (name: string): RoomRow => ({ name, eggs: 0, losses: 0, saleable: 0, sold: 0 })
    const houseMap = new Map<number, RoomRow>()
    // Seed every house so empty ones still appear.
    for (const h of houses) houseMap.set(h.houseId, blank(h.name))
    // No house? Still show as "Unassigned".
    const unassigned = blank("Unassigned")
    const flockToHouse = new Map<number, number | null>()
    for (const f of flocks) flockToHouse.set(f.flockId, f.houseId ?? null)

    for (const r of filteredRecords) {
      const eggs = Number(r.totalProduction) || 0
      if (eggs <= 0 || r.flockId == null) continue
      const saleable = saleableEggsOf(r)
      const hid = flockToHouse.get(r.flockId)
      const row = hid != null && houseMap.has(hid) ? houseMap.get(hid)! : unassigned
      row.eggs += eggs
      row.saleable += saleable
      row.losses += eggs - saleable
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
      // Unsold is period-scoped and may be negative when the room's sales drew
      // on stock collected before the period started.
      .map((r) => ({ ...r, unsold: r.saleable - r.sold }))
      .sort((a, b) => b.eggs - a.eggs)
  }, [houses, flocks, filteredRecords, filteredSales])

  const roomTotals = useMemo(
    () =>
      roomSummary.reduce(
        (acc, r) => ({
          eggs: acc.eggs + r.eggs,
          losses: acc.losses + r.losses,
          saleable: acc.saleable + r.saleable,
          sold: acc.sold + r.sold,
          unsold: acc.unsold + r.unsold,
        }),
        { eggs: 0, losses: 0, saleable: 0, sold: 0, unsold: 0 },
      ),
    [roomSummary],
  )

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
    const m = new Map<string, { eggs: number; crates: number; revenue: number }>()
    for (const s of eggSales) {
      const key = (s.size && s.size.trim()) || "Unspecified"
      // Sale.quantity is egg pieces (crates × 30 + loose); UnitPrice is per crate,
      // and the sale's own total is crates × unit price — so crates, not pieces,
      // is what the price column can be compared against.
      const eggs = Number(s.quantity) || 0
      const cur = m.get(key) ?? { eggs: 0, crates: 0, revenue: 0 }
      cur.eggs += eggs
      cur.crates += Math.floor(eggs / EGGS_PER_CRATE)
      cur.revenue += Number(s.totalAmount) || 0
      m.set(key, cur)
    }
    return Array.from(m.entries())
      .map(([size, v]) => ({
        size,
        eggs: v.eggs,
        crates: v.crates,
        // Volume-weighted: a 1-crate sale shouldn't move this as much as a 100-crate one.
        avgPrice: v.crates ? v.revenue / v.crates : 0,
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
      const owed = saleOwed(s)
      if (owed <= 0) continue
      const name = (s.customerName || "Unknown").trim() || "Unknown"
      m.set(name, (m.get(name) ?? 0) + owed)
    }
    return Array.from(m.entries())
      .map(([customer, amount]) => ({ customer, amount }))
      .filter((r) => r.amount > 0)
      .sort((a, b) => b.amount - a.amount)
  }, [filteredSales])
  const totalDebt = useMemo(() => debtors.reduce((s, d) => s + d.amount, 0), [debtors])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <style>{`
        @media print {
          @page { size: A4 portrait; margin: 12mm; }
          body { background: white !important; }
          /* Hide dashboard chrome */
          .bg-slate-900, .dashboard-sidebar, header { display: none !important; }
          /* Hide page elements explicitly marked */
          .weekly-print-hide { display: none !important; }
          /* Tighten layout for print */
          main { padding: 0 !important; }
          /* Avoid breaking inside cards / tables */
          .rounded-xl, .rounded-lg, [class*="Card"], table { break-inside: avoid; page-break-inside: avoid; }
          /* Strip drop shadows that waste toner */
          .shadow-sm, .shadow, .shadow-md { box-shadow: none !important; }
        }
      `}</style>
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
                    Analytical Report
                  </h1>
                  <p className="text-sm text-slate-600 mt-1">
                    Showing <span className="font-semibold">{range.label}</span>. All totals
                    update automatically based on the selected period.
                  </p>
                </div>
              </div>
              <div className="flex gap-2 shrink-0 weekly-print-hide">
                <Button
                  type="button"
                  variant="outline"
                  className="gap-2"
                  onClick={() => {
                    setRefreshing(true)
                    void loadData()
                  }}
                  disabled={refreshing || loading}
                >
                  <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
                  Refresh
                </Button>
                <Button
                  type="button"
                  className="gap-2"
                  onClick={() => window.print()}
                  disabled={loading}
                >
                  <Printer className="h-4 w-4" />
                  Print
                </Button>
              </div>
            </div>

            {/* Filters (#5) */}
            <Card className="bg-white weekly-print-hide">
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Filters</CardTitle>
                <CardDescription>Pick a week, a month, a custom range, or all time.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                {/* Mode tabs */}
                <div className="inline-flex rounded-md border bg-slate-50 p-0.5">
                  {(["week", "month", "range", "all"] as RangeMode[]).map((m) => (
                    <button
                      key={m}
                      type="button"
                      onClick={() => setMode(m)}
                      className={cn(
                        "px-3 py-1.5 text-xs font-medium rounded transition-colors capitalize",
                        mode === m ? "bg-white shadow-sm text-slate-900" : "text-slate-600 hover:text-slate-900",
                      )}
                    >
                      {m === "range" ? "Custom range" : m === "all" ? "All time" : m}
                    </button>
                  ))}
                </div>

                <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
                  {/* Active scope control */}
                  {mode === "week" && (
                    <div className="flex items-center gap-1 lg:col-span-2">
                      <Button variant="outline" size="icon" aria-label="Previous week" onClick={() => setWeekStart((w) => addDays(w, -7))}>
                        <ChevronLeft className="h-4 w-4" />
                      </Button>
                      <div className="flex items-center gap-2 px-2 py-1 rounded-md bg-slate-50 border text-sm font-medium text-slate-700 flex-1 min-w-0 justify-center">
                        <CalendarIcon className="h-3.5 w-3.5 text-slate-500" />
                        <span className="truncate">{fmtShort(weekStart)} – {fmtShort(addDays(weekStart, 6))}</span>
                      </div>
                      <Button variant="outline" size="icon" aria-label="Next week" onClick={() => setWeekStart((w) => addDays(w, 7))}>
                        <ChevronRight className="h-4 w-4" />
                      </Button>
                    </div>
                  )}
                  {mode === "month" && (
                    <div className="lg:col-span-2">
                      <Select value={selectedMonth} onValueChange={setSelectedMonth}>
                        <SelectTrigger>
                          <SelectValue placeholder="Month" />
                        </SelectTrigger>
                        <SelectContent>
                          {monthOptions.map((m) => (
                            <SelectItem key={m} value={m}>{fmtMonth(m)}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )}
                  {mode === "range" && (
                    <>
                      <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} placeholder="From" />
                      <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} placeholder="To" />
                    </>
                  )}
                  {mode === "all" && (
                    <div className="lg:col-span-2 px-3 py-2 rounded-md bg-emerald-50 border border-emerald-200 text-sm text-emerald-800">
                      Showing every record ever logged for this farm.
                    </div>
                  )}

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
                </div>

                {(mode !== "week" || flockFilter !== "ALL" || houseFilter !== "ALL") && (
                  <div className="flex justify-end">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => {
                        setMode("week")
                        setWeekStart(startOfWeek(new Date()))
                        setDateFrom("")
                        setDateTo("")
                        setFlockFilter("ALL")
                        setHouseFilter("ALL")
                      }}
                    >
                      Reset filters
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center text-slate-600">Loading report…</CardContent>
              </Card>
            ) : (
              <>
                {/* Summary cards (#16) */}
                <div className="grid gap-3 grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
                  <SummaryCard label="Total Eggs Collected" value={totalEggsCollected.toLocaleString()} accent="emerald" />
                  <SummaryCard label="Total Eggs Sold" value={totalEggsSold.toLocaleString()} accent="sky" />
                  <SummaryCard label="Total Revenue" value={totalRevenue.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })} accent="violet" />
                  <SummaryCard label="Total Expenses" value={totalExpenses.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })} accent="amber" />
                  <SummaryCard
                    label="Eggs in Stock"
                    value={eggsInStock.toLocaleString()}
                    accent={eggsInStock >= 0 ? "slate" : "rose"}
                    hint={`Saleable eggs on hand as at ${range.to === ALL_TIME_TO ? "today" : range.to}. Excludes egg-tracker adjustments.`}
                  />
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
                      Eggs collected per flock, one column per day in the selected period. Crates show as
                      whole crates of {EGGS_PER_CRATE} plus any loose eggs.
                      {dayColumns.length === 0 && filteredRecords.length > 0 && (
                        <> The period is longer than {MAX_DAY_COLUMNS} days, so only period totals are shown.</>
                      )}
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto">
                    {/* A month's worth of day columns needs more room than a week's. */}
                    <Table className="w-full" style={{ minWidth: 320 + dayColumns.length * 56 }}>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Room / Flock</TableHead>
                          {dayColumns.map((c) => (
                            <TableHead key={c.key} className="text-right">{c.label}</TableHead>
                          ))}
                          <TableHead className="text-right">Total</TableHead>
                          <TableHead className="text-right">Crates</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {dailyRows.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={dayColumns.length + 3} className="text-center text-slate-500 py-8">
                              No flocks match the current filters.
                            </TableCell>
                          </TableRow>
                        ) : (
                          <>
                            {dailyRows.map((row) => (
                              <TableRow key={row.key}>
                                <TableCell className="font-medium">
                                  <div>{row.name}</div>
                                  {row.house && <div className="text-xs text-slate-500">{row.house}</div>}
                                </TableCell>
                                {row.days.map((n, i) => (
                                  <TableCell key={i} className="text-right tabular-nums">
                                    {n ? n.toLocaleString() : "—"}
                                  </TableCell>
                                ))}
                                <TableCell className="text-right tabular-nums font-semibold">{row.total.toLocaleString()}</TableCell>
                                <TableCell className="text-right tabular-nums text-slate-600">
                                  {formatCrates(row.total)}
                                </TableCell>
                              </TableRow>
                            ))}
                            <TableRow className="bg-slate-50">
                              <TableCell className="font-semibold">All flocks</TableCell>
                              {dailyDayTotals.map((n, i) => (
                                <TableCell key={i} className="text-right tabular-nums font-semibold">
                                  {n ? n.toLocaleString() : "—"}
                                </TableCell>
                              ))}
                              <TableCell className="text-right tabular-nums font-bold">{totalEggsCollected.toLocaleString()}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold text-slate-600">
                                {formatCrates(totalEggsCollected)}
                              </TableCell>
                            </TableRow>
                          </>
                        )}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                {/* Room Production Summary (#10) */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Room Production Summary</CardTitle>
                    <CardDescription>
                      Per room, for the selected period only. Saleable = collected − broken, meaty, soft and lost eggs.
                      Unsold = saleable − sold, and goes negative when a room&rsquo;s sales drew on stock collected
                      before this period.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table className="w-full min-w-[720px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Room</TableHead>
                          <TableHead className="text-right">Eggs Collected</TableHead>
                          <TableHead className="text-right">Crates (+ loose)</TableHead>
                          <TableHead className="text-right">Losses</TableHead>
                          <TableHead className="text-right">Saleable</TableHead>
                          <TableHead className="text-right">Sold</TableHead>
                          <TableHead className="text-right">Unsold</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {roomSummary.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={7} className="text-center text-slate-500 py-8">
                              No room data for this period.
                            </TableCell>
                          </TableRow>
                        ) : (
                          <>
                            {roomSummary.map((r) => (
                              <TableRow key={r.name}>
                                <TableCell className="font-medium">{r.name}</TableCell>
                                <TableCell className="text-right tabular-nums">{r.eggs.toLocaleString()}</TableCell>
                                <TableCell className="text-right tabular-nums text-slate-600">{formatCrates(r.eggs)}</TableCell>
                                <TableCell className="text-right tabular-nums text-rose-700">
                                  {r.losses ? r.losses.toLocaleString() : "—"}
                                </TableCell>
                                <TableCell className="text-right tabular-nums">{r.saleable.toLocaleString()}</TableCell>
                                <TableCell className="text-right tabular-nums">{r.sold.toLocaleString()}</TableCell>
                                <TableCell className={cn("text-right tabular-nums font-medium", r.unsold < 0 && "text-rose-700")}>
                                  {r.unsold.toLocaleString()}
                                </TableCell>
                              </TableRow>
                            ))}
                            <TableRow className="bg-slate-50">
                              <TableCell className="font-semibold">All rooms</TableCell>
                              <TableCell className="text-right tabular-nums font-bold">{roomTotals.eggs.toLocaleString()}</TableCell>
                              {/* Derived from the egg total, not from summing the rows' crate figures,
                                  so the loose eggs each room carries can't round away. */}
                              <TableCell className="text-right tabular-nums font-semibold text-slate-600">
                                {formatCrates(roomTotals.eggs)}
                              </TableCell>
                              <TableCell className="text-right tabular-nums font-semibold text-rose-700">
                                {roomTotals.losses ? roomTotals.losses.toLocaleString() : "—"}
                              </TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">{roomTotals.saleable.toLocaleString()}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">{roomTotals.sold.toLocaleString()}</TableCell>
                              <TableCell className={cn("text-right tabular-nums font-bold", roomTotals.unsold < 0 && "text-rose-700")}>
                                {roomTotals.unsold.toLocaleString()}
                              </TableCell>
                            </TableRow>
                          </>
                        )}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                {/* Weekly sales + financial (#11 + #13) */}
                <div className="grid gap-4 md:grid-cols-2">
                  <Card className="bg-white">
                    <CardHeader className="pb-2">
                      <CardTitle className="text-base">Sales Summary</CardTitle>
                      <CardDescription>
                        Egg volumes for the period, with revenue split into egg and non-egg sales. Crates read as
                        whole crates of {EGGS_PER_CRATE} plus loose eggs.
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <dl className="grid grid-cols-2 gap-y-3 text-sm">
                        <dt className="text-slate-600">Total eggs sold</dt>
                        <dd className="text-right font-semibold tabular-nums">{totalEggsSold.toLocaleString()}</dd>
                        <dt className="text-slate-600">Total crates sold</dt>
                        <dd className="text-right font-semibold tabular-nums">{formatCrates(totalEggsSold)}</dd>
                        <dt className="text-slate-600">Crates collected</dt>
                        <dd className="text-right font-semibold tabular-nums">{formatCrates(totalEggsCollected)}</dd>
                        <dt className="text-slate-600">Saleable eggs collected</dt>
                        <dd className="text-right font-semibold tabular-nums">{periodSaleableEggs.toLocaleString()}</dd>
                        <dt className="text-slate-600">
                          Unsold this period
                          {periodUnsoldEggs < 0 && (
                            <span className="block text-xs text-slate-400">sold more than collected — drawn from earlier stock</span>
                          )}
                        </dt>
                        <dd className={cn("text-right font-semibold tabular-nums", periodUnsoldEggs < 0 && "text-rose-700")}>
                          {periodUnsoldEggs.toLocaleString()}
                        </dd>
                        <dt className="text-slate-600">Egg sales revenue</dt>
                        <dd className="text-right font-semibold tabular-nums">
                          {eggRevenue.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })}
                        </dd>
                        <dt className="text-slate-600">Other sales revenue</dt>
                        <dd className="text-right font-semibold tabular-nums">
                          {otherRevenue.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })}
                        </dd>
                        <dt className="text-slate-900 font-semibold pt-2 border-t">Total revenue</dt>
                        <dd className="text-right font-bold text-emerald-700 tabular-nums pt-2 border-t">
                          {totalRevenue.toLocaleString(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 0 })}
                        </dd>
                      </dl>
                    </CardContent>
                  </Card>

                  <Card className="bg-white">
                    <CardHeader className="pb-2">
                      <CardTitle className="text-base">Financial Summary</CardTitle>
                      <CardDescription>Balance = Income − Expenditure. Income covers every sale in the period, not just eggs.</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <dl className="grid grid-cols-2 gap-y-3 text-sm">
                        <dt className="text-slate-600">Income (all sales)</dt>
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
                    <CardTitle className="text-base">Expenditure</CardTitle>
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
                      Customers with an outstanding balance on sales in the selected period. Partial payments are
                      netted off, so a part-paid sale shows only the remainder. Record payments on the Sales page to clear.
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
                      Egg sales are priced per crate of {EGGS_PER_CRATE}, so the average price is revenue ÷ crates.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table className="w-full min-w-[560px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Size</TableHead>
                          <TableHead className="text-right">Crates</TableHead>
                          <TableHead className="text-right">Eggs</TableHead>
                          <TableHead className="text-right">Avg Price / Crate</TableHead>
                          <TableHead className="text-right">Total</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {salesBySize.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={5} className="text-center text-slate-500 py-8">
                              No egg sales in this period.
                            </TableCell>
                          </TableRow>
                        ) : (
                          <>
                            {salesBySize.map((s) => (
                              <TableRow key={s.size}>
                                <TableCell className="font-medium">{s.size}</TableCell>
                                <TableCell className="text-right tabular-nums">{s.crates.toLocaleString()}</TableCell>
                                <TableCell className="text-right tabular-nums text-slate-600">{s.eggs.toLocaleString()}</TableCell>
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
                                {salesBySize.reduce((s, x) => s + x.crates, 0).toLocaleString()}
                              </TableCell>
                              <TableCell className="text-right font-semibold tabular-nums text-slate-600">
                                {salesBySize.reduce((s, x) => s + x.eggs, 0).toLocaleString()}
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
                      Totals across production records in the selected period. All four categories are deducted from
                      collected eggs to give the saleable figure used by Eggs in Stock. New loss fields
                      (Meaty / Soft / Lost) require entries logged via the production-record form to populate.
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
                      Free-text notes for week of <span className="font-medium">{fmtShort(weekStart)} – {fmtShort(addDays(weekStart, 6))}</span>. Stored per (farm, week) regardless of the filter mode above.
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
  hint,
}: {
  label: string
  value: string
  accent: "emerald" | "sky" | "violet" | "amber" | "slate" | "rose"
  /** Optional one-liner for figures whose basis isn't obvious from the label. */
  hint?: string
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
      {hint && <div className="text-[11px] leading-tight text-slate-400 mt-1">{hint}</div>}
    </div>
  )
}

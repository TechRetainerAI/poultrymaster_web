"use client"

import { useState, useEffect, useMemo } from "react"
import { useRouter } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { BarChart3, Plus, RotateCcw, Egg, Package, Bird, TrendingUp, TrendingDown, CalendarDays, Wallet, ReceiptText, Filter, Search } from "lucide-react"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { useIsMobile } from "@/hooks/use-mobile"
import { cn } from "@/lib/utils"
import { format } from "date-fns"
import { getReportContext, type ReportRequest } from "@/lib/api"
import { useToast } from "@/hooks/use-toast"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import { getSales, type Sale } from "@/lib/api/sale"
import { getExpenses, type Expense } from "@/lib/api/expense"
import { getFlocks } from "@/lib/api/flock"
import { ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart"
import { LineChart, Line, XAxis, YAxis, CartesianGrid, BarChart, Bar, Legend } from "recharts"
import { formatCurrency, getSelectedCurrency } from "@/lib/utils/currency"
import { getBirdsLeftForFlockFromRecords, sumLatestBirdsLeftByFlock } from "@/lib/utils/production-records"

export default function ReportsPage() {
  const isMobile = useIsMobile()
  const router = useRouter()
  const [reportRequest, setReportRequest] = useState<ReportRequest>({
    farmId: "",
    userId: "",
    reportType: "",
    startDate: "",
    endDate: "",
    flockId: undefined,
    customerId: undefined,
  })
  const { toast } = useToast()
  const [tab, setTab] = useState("production")
  const [records, setRecords] = useState<ProductionRecord[]>([])
  const [sales, setSales] = useState<Sale[]>([])
  const [expenses, setExpenses] = useState<Expense[]>([])
  const [flocks, setFlocks] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const currencyCode = getSelectedCurrency()

  // Filter states
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [selectedFlock, setSelectedFlock] = useState("ALL")
  const [searchQuery, setSearchQuery] = useState("")
  const [filtersOpen, setFiltersOpen] = useState(false)

  useEffect(() => {
    const { farmId, userId } = getReportContext()
    setReportRequest(prev => ({
      ...prev,
      farmId,
      userId,
    }))
  }, [])

  // Load all data
  useEffect(() => {
    const load = async () => {
      try {
        const { userId, farmId } = getReportContext()
        if (!userId || !farmId) return

        const [prodRes, salesRes, expRes, flocksRes] = await Promise.all([
          getProductionRecords(userId, farmId),
          getSales(userId, farmId),
          getExpenses(userId, farmId),
          getFlocks(userId, farmId),
        ])

        if (prodRes.success && prodRes.data) setRecords(prodRes.data)
        else toast({ title: "Failed to fetch", description: prodRes.message || "Could not load records", variant: "destructive" })
        if (salesRes.success && salesRes.data) setSales(salesRes.data)
        if (expRes.success && expRes.data) setExpenses(expRes.data)
        if (flocksRes.success && flocksRes.data) setFlocks(flocksRes.data)
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [])

  // ---------- Filtered data ----------
  const filteredRecords = useMemo(() => {
    let list = records
    if (dateFrom) {
      list = list.filter(r => new Date(r.date) >= new Date(dateFrom))
    }
    if (dateTo) {
      const to = new Date(dateTo)
      to.setHours(23, 59, 59, 999)
      list = list.filter(r => new Date(r.date) <= to)
    }
    if (selectedFlock !== "ALL") {
      const fid = parseInt(selectedFlock)
      list = list.filter(r => r.flockId === fid)
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      list = list.filter(r =>
        (r.flockName ?? "").toLowerCase().includes(q) ||
        (r.medication ?? "").toLowerCase().includes(q)
      )
    }
    return list
  }, [records, dateFrom, dateTo, selectedFlock, searchQuery])

  const filteredSales = useMemo(() => {
    let list = sales
    if (dateFrom) {
      list = list.filter(s => new Date(s.saleDate) >= new Date(dateFrom))
    }
    if (dateTo) {
      const to = new Date(dateTo)
      to.setHours(23, 59, 59, 999)
      list = list.filter(s => new Date(s.saleDate) <= to)
    }
    if (selectedFlock !== "ALL") {
      const fid = parseInt(selectedFlock)
      list = list.filter(s => s.flockId === fid)
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      list = list.filter(s =>
        (s.product ?? "").toLowerCase().includes(q) ||
        (s.customerName ?? "").toLowerCase().includes(q)
      )
    }
    return list
  }, [sales, dateFrom, dateTo, selectedFlock, searchQuery])

  const filteredExpenses = useMemo(() => {
    let list = expenses
    if (dateFrom) {
      list = list.filter((e: any) => new Date(e.expenseDate || e.expense_date) >= new Date(dateFrom))
    }
    if (dateTo) {
      const to = new Date(dateTo)
      to.setHours(23, 59, 59, 999)
      list = list.filter((e: any) => new Date(e.expenseDate || e.expense_date) <= to)
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      list = list.filter((e: any) =>
        (e.description ?? "").toLowerCase().includes(q) ||
        (e.category ?? "").toLowerCase().includes(q)
      )
    }
    return list
  }, [expenses, dateFrom, dateTo, searchQuery])

  // ---------- Production metrics ----------
  const totalEggs = useMemo(() => filteredRecords.reduce((s, r: any) => s + (r.totalProduction || 0), 0), [filteredRecords])
  const totalCrates = Math.floor(totalEggs / 30)
  const looseEggs = totalEggs % 30
  const avgDaily = filteredRecords.length ? Math.round(totalEggs / filteredRecords.length) : 0
  const totalMortality = useMemo(() => filteredRecords.reduce((s, r: any) => s + (r.mortality || 0), 0), [filteredRecords])
  /** Latest `noOfBirdsLeft` per flock from full production history (not date-filtered). */
  const birdsLeftLatestTotal = useMemo(() => {
    if (records.length === 0) return 0
    if (selectedFlock === "ALL") return sumLatestBirdsLeftByFlock(records)
    const fid = parseInt(selectedFlock, 10)
    if (!Number.isFinite(fid)) return 0
    return getBirdsLeftForFlockFromRecords(records, fid)
  }, [records, selectedFlock])
  const totalFeedKg = useMemo(() => filteredRecords.reduce((s, r: any) => s + (r.feedKg || 0), 0), [filteredRecords])
  const totalRevenue = useMemo(
    () => filteredSales.reduce((s: number, x: any) => s + Number(x.totalAmount || 0), 0),
    [filteredSales]
  )
  const totalExpensesAmount = useMemo(
    () => filteredExpenses.reduce((s: number, x: any) => s + Number(x.amount || 0), 0),
    [filteredExpenses]
  )
  const netProfit = totalRevenue - totalExpensesAmount

  // Build chart data from filtered records
  const prodDaily = useMemo(() =>
    filteredRecords
      .map((r: any) => ({ date: new Date(r.date).toLocaleDateString(), total: r.totalProduction || 0 }))
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime()),
    [filteredRecords]
  )

  const prodByTime = useMemo(() =>
    filteredRecords
      .map((r: any) => ({
        date: new Date(r.date).toLocaleDateString(),
        m9: r.production9AM || 0,
        m12: r.production12PM || 0,
        m4: r.production4PM || 0,
      }))
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime()),
    [filteredRecords]
  )

  // Financial chart data
  const revenueByDate = useMemo(() => {
    const acc: any[] = []
    filteredSales.forEach((s: any) => {
      const date = new Date(s.saleDate || s.sale_date).toLocaleDateString()
      const found = acc.find((x) => x.date === date)
      if (found) found.revenue += Number(s.totalAmount || 0)
      else acc.push({ date, revenue: Number(s.totalAmount || 0), expenses: 0 })
    })
    filteredExpenses.forEach((e: any) => {
      const date = new Date(e.expenseDate || e.expense_date).toLocaleDateString()
      const found = acc.find((x) => x.date === date)
      if (found) found.expenses += Number(e.amount || 0)
      else acc.push({ date, revenue: 0, expenses: Number(e.amount || 0) })
    })
    acc.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
    return acc
  }, [filteredSales, filteredExpenses])

  const dailyEggExpenseReport = useMemo(() => {
    const bucket = new Map<string, { eggs: number; expenses: number }>()

    filteredRecords.forEach((r: any) => {
      const d = new Date(r.date)
      const key = format(d, "yyyy-MM-dd")
      const existing = bucket.get(key) || { eggs: 0, expenses: 0 }
      existing.eggs += Number(r.totalProduction || 0)
      bucket.set(key, existing)
    })

    filteredExpenses.forEach((e: any) => {
      const d = new Date(e.expenseDate || e.expense_date)
      const key = format(d, "yyyy-MM-dd")
      const existing = bucket.get(key) || { eggs: 0, expenses: 0 }
      existing.expenses += Number(e.amount || 0)
      bucket.set(key, existing)
    })

    return Array.from(bucket.entries())
      .map(([date, value]) => ({
        date,
        eggs: value.eggs,
        crates: Math.floor(value.eggs / 30),
        looseEggs: value.eggs % 30,
        expenses: value.expenses,
        eggsPerExpenseUnit: value.expenses > 0 ? value.eggs / value.expenses : value.eggs,
      }))
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
  }, [filteredRecords, filteredExpenses])

  const bestEggDay = useMemo(() => {
    if (!dailyEggExpenseReport.length) return null
    return [...dailyEggExpenseReport].sort((a, b) => b.eggs - a.eggs)[0]
  }, [dailyEggExpenseReport])

  const highestExpenseDay = useMemo(() => {
    if (!dailyEggExpenseReport.length) return null
    return [...dailyEggExpenseReport].sort((a, b) => b.expenses - a.expenses)[0]
  }, [dailyEggExpenseReport])

  const salesByProduct = useMemo(() => {
    const productMap = new Map<string, { qty: number; revenue: number; salesCount: number }>()
    filteredSales.forEach((s: any) => {
      const key = (s.product || "Unknown").trim() || "Unknown"
      const current = productMap.get(key) || { qty: 0, revenue: 0, salesCount: 0 }
      current.qty += Number(s.quantity || 0)
      current.revenue += Number(s.totalAmount || 0)
      current.salesCount += 1
      productMap.set(key, current)
    })
    return Array.from(productMap.entries())
      .map(([product, value]) => ({
        product,
        quantity: value.qty,
        revenue: value.revenue,
        salesCount: value.salesCount,
      }))
      .sort((a, b) => b.revenue - a.revenue)
  }, [filteredSales])

  const expensesByCategory = useMemo(() => {
    const categoryMap = new Map<string, number>()
    filteredExpenses.forEach((e: any) => {
      const key = (e.category || "Uncategorized").trim() || "Uncategorized"
      categoryMap.set(key, (categoryMap.get(key) || 0) + Number(e.amount || 0))
    })
    return Array.from(categoryMap.entries())
      .map(([category, total]) => ({ category, total }))
      .sort((a, b) => b.total - a.total)
  }, [filteredExpenses])

  const flockProductionSummary = useMemo(() => {
    const map = new Map<number, { flockId: number; flockName: string; eggs: number; feedKg: number; mortality: number; days: number }>()
    filteredRecords.forEach((r: any) => {
      const id = Number(r.flockId || 0)
      const current = map.get(id) || {
        flockId: id,
        flockName: r.flockName || `Flock #${id}`,
        eggs: 0,
        feedKg: 0,
        mortality: 0,
        days: 0,
      }
      current.eggs += Number(r.totalProduction || 0)
      current.feedKg += Number(r.feedKg || 0)
      current.mortality += Number(r.mortality || 0)
      current.days += 1
      map.set(id, current)
    })
    return Array.from(map.values())
      .map((x) => ({
        ...x,
        avgEggsPerDay: x.days > 0 ? Math.round(x.eggs / x.days) : 0,
        birdsLeftLatest: getBirdsLeftForFlockFromRecords(records, x.flockId),
      }))
      .sort((a, b) => b.eggs - a.eggs)
  }, [filteredRecords, records])

  const clearFilters = () => {
    setDateFrom("")
    setDateTo("")
    setSelectedFlock("ALL")
    setSearchQuery("")
  }

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

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header — aligned with Health Records */}
            <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-center justify-between")}>
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-blue-100 rounded-lg flex items-center justify-center">
                  <BarChart3 className="w-5 h-5 text-blue-600" />
                </div>
                <div className="min-w-0">
                  <h1 className={cn("font-bold text-slate-900", isMobile ? "text-xl" : "text-2xl")}>Reports</h1>
                  <p className="text-sm text-slate-600">Comprehensive farm analytics and insights</p>
                </div>
              </div>
              <Button className={cn("gap-2 bg-blue-600 hover:bg-blue-700 shrink-0", isMobile && "w-full sm:w-auto h-11 sm:h-10")}>
                <Plus className="w-4 h-4" />
                New Report
              </Button>
            </div>

            {/* Tabs + filters — same pattern as Health Records (web + mobile) */}
            <Tabs value={tab} onValueChange={setTab} className="w-full">
              <TabsList
                className={cn(
                  "w-full",
                  isMobile && "grid h-auto grid-cols-2 gap-1 sm:grid-cols-4"
                )}
              >
                <TabsTrigger value="production" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <Egg className={cn("w-4 h-4 shrink-0", isMobile ? "mr-1" : "mr-2")} />
                  Production
                </TabsTrigger>
                <TabsTrigger value="financial" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <Wallet className={cn("w-4 h-4 shrink-0", isMobile ? "mr-1" : "mr-2")} />
                  Financial
                </TabsTrigger>
                <TabsTrigger value="daily" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <CalendarDays className={cn("w-4 h-4 shrink-0", isMobile ? "mr-1" : "mr-2")} />
                  {isMobile ? "Daily" : "Daily Report"}
                </TabsTrigger>
                <TabsTrigger value="insights" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <TrendingUp className={cn("w-4 h-4 shrink-0", isMobile ? "mr-1" : "mr-2")} />
                  {isMobile ? "More" : "More Reports"}
                </TabsTrigger>
              </TabsList>

              <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded-md border border-slate-200">
                {isMobile ? (
                  <>
                    <div className="relative flex-1 min-w-0">
                      <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                      <Input
                        placeholder="Search..."
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                        className="pl-9"
                      />
                    </div>
                    <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                      <SheetTrigger asChild>
                        <Button variant="outline" size="sm" className="gap-2 shrink-0">
                          <Filter className="h-4 w-4" />
                          Filters
                        </Button>
                      </SheetTrigger>
                      <SheetContent side="bottom" className="rounded-t-2xl max-h-[85vh]">
                        <SheetHeader>
                          <SheetTitle>Filters</SheetTitle>
                        </SheetHeader>
                        <div className="space-y-4 pt-4">
                          <div className="space-y-2">
                            <Label>Flock</Label>
                            <Select value={selectedFlock} onValueChange={setSelectedFlock}>
                              <SelectTrigger>
                                <SelectValue placeholder="All Flocks" />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectItem value="ALL">All Flocks</SelectItem>
                                {flocks.map((flock: any) => (
                                  <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                                    {flock.name}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                          <div className="grid grid-cols-2 gap-3">
                            <div className="space-y-2">
                              <Label>Date From</Label>
                              <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                            </div>
                            <div className="space-y-2">
                              <Label>Date To</Label>
                              <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                            </div>
                          </div>
                          <div className="flex gap-2 pt-2">
                            <Button variant="outline" className="flex-1" onClick={clearFilters}>
                              Clear
                            </Button>
                            <Button className="flex-1" onClick={() => setFiltersOpen(false)}>
                              Apply
                            </Button>
                          </div>
                        </div>
                      </SheetContent>
                    </Sheet>
                  </>
                ) : (
                  <>
                    <div className="relative w-[240px]">
                      <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                      <Input
                        placeholder="Search..."
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                        className="pl-9"
                      />
                    </div>
                    <Select value={selectedFlock} onValueChange={setSelectedFlock}>
                      <SelectTrigger className="w-[180px]">
                        <SelectValue placeholder="Flock" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="ALL">All Flocks</SelectItem>
                        {flocks.map((flock: any) => (
                          <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                            {flock.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <Input
                      type="date"
                      value={dateFrom}
                      onChange={(e) => setDateFrom(e.target.value)}
                      className="w-[140px]"
                    />
                    <Input
                      type="date"
                      value={dateTo}
                      onChange={(e) => setDateTo(e.target.value)}
                      className="w-[140px]"
                    />
                    <div className="ml-auto">
                      <Button variant="outline" size="sm" onClick={clearFilters}>
                        <RotateCcw className="h-4 w-4 mr-2" />
                        Reset
                      </Button>
                    </div>
                  </>
                )}
              </div>
            </Tabs>

            <div className="space-y-4">
            {/* Production content */}
            {tab === "production" && (
              <>
                {/* Metrics Row 1 */}
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Total Eggs</div>
                      <div className="text-2xl font-bold">{totalEggs.toLocaleString()}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="flex items-center gap-1.5 text-xs text-slate-500">
                        <Egg className="w-3.5 h-3.5 text-amber-500" />
                        Total Crates
                      </div>
                      <div className="text-2xl font-bold text-amber-700">{totalCrates.toLocaleString()}</div>
                      <div className="text-xs text-slate-400 mt-0.5">
                        + {looseEggs} loose egg{looseEggs !== 1 ? 's' : ''}
                      </div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Avg Daily Production</div>
                      <div className="text-2xl font-bold">{avgDaily.toLocaleString()}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Total Mortality</div>
                      <div className="text-2xl font-bold text-red-600">{totalMortality.toLocaleString()}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="flex items-center gap-1.5 text-xs text-slate-500">
                        <Package className="w-3.5 h-3.5 text-blue-500" />
                        Total Feed (kg)
                      </div>
                      <div className="text-2xl font-bold text-blue-700">{totalFeedKg.toLocaleString()}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="flex items-center gap-1.5 text-xs text-slate-500">
                        <Bird className="w-3.5 h-3.5 text-indigo-600" />
                        Birds left (latest)
                      </div>
                      <div className="text-2xl font-bold text-indigo-800">{birdsLeftLatestTotal.toLocaleString()}</div>
                      <div className="text-xs text-slate-400 mt-0.5">
                        {selectedFlock === "ALL" ? "Sum per flock" : "Selected flock"}
                      </div>
                    </CardContent>
                  </Card>
                </div>

                {/* Daily Egg Production Chart */}
                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Daily Egg Production</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <ChartContainer config={{ total: { label: 'Total', color: 'hsl(142, 76%, 36%)' } }} className="h-[360px] aspect-auto">
                      <LineChart data={prodDaily}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="date" />
                        <YAxis />
                        <ChartTooltip content={<ChartTooltipContent />} />
                        <Legend />
                        <Line type="monotone" dataKey="total" stroke="var(--color-total)" strokeWidth={2} dot={false} />
                      </LineChart>
                    </ChartContainer>
                  </CardContent>
                </Card>

                {/* Egg Collection by Time of Day Chart */}
                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Egg Collection by Time of Day</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <ChartContainer config={{ m9: { label: '9am', color: 'hsl(221, 83%, 53%)' }, m12: { label: '12pm', color: 'hsl(25, 95%, 53%)' }, m4: { label: '4pm', color: 'hsl(262, 83%, 58%)' } }} className="h-[360px] aspect-auto">
                      <BarChart data={prodByTime}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="date" />
                        <YAxis />
                        <ChartTooltip content={<ChartTooltipContent />} />
                        <Legend />
                        <Bar dataKey="m9" fill="var(--color-m9)" />
                        <Bar dataKey="m12" fill="var(--color-m12)" />
                        <Bar dataKey="m4" fill="var(--color-m4)" />
                      </BarChart>
                    </ChartContainer>
                  </CardContent>
                </Card>
              </>
            )}

            {/* Financial content */}
            {tab === "financial" && (
              <>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Revenue</div>
                      <div className="text-2xl font-bold text-emerald-700">
                        {formatCurrency(totalRevenue, currencyCode)}
                      </div>
                      <div className="text-xs text-slate-400 mt-0.5">{filteredSales.length} transaction{filteredSales.length !== 1 ? 's' : ''}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Expenses</div>
                      <div className="text-2xl font-bold text-red-600">
                        {formatCurrency(totalExpensesAmount, currencyCode)}
                      </div>
                      <div className="text-xs text-slate-400 mt-0.5">{filteredExpenses.length} expense{filteredExpenses.length !== 1 ? 's' : ''}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Net Profit / Loss</div>
                      <div className={`text-2xl font-bold ${netProfit >= 0 ? 'text-emerald-700' : 'text-red-600'}`}>
                        {formatCurrency(netProfit, currencyCode)}
                      </div>
                    </CardContent>
                  </Card>
                </div>
                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Revenue vs Expenses</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <ChartContainer config={{ revenue: { label: 'Revenue', color: 'hsl(142, 76%, 36%)' }, expenses: { label: 'Expenses', color: 'hsl(0, 84%, 60%)' } }} className="h-[360px] aspect-auto">
                      <LineChart data={revenueByDate}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="date" />
                        <YAxis />
                        <ChartTooltip content={<ChartTooltipContent />} />
                        <Legend />
                        <Line type="monotone" dataKey="revenue" stroke="var(--color-revenue)" strokeWidth={2} dot={false} />
                        <Line type="monotone" dataKey="expenses" stroke="var(--color-expenses)" strokeWidth={2} dot={false} />
                      </LineChart>
                    </ChartContainer>
                  </CardContent>
                </Card>
              </>
            )}

            {tab === "daily" && (
              <>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Daily Rows</div>
                      <div className="text-2xl font-bold">{dailyEggExpenseReport.length}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Best Egg Day</div>
                      <div className="text-xl font-bold text-emerald-700">{bestEggDay ? bestEggDay.eggs.toLocaleString() : 0}</div>
                      <div className="text-xs text-slate-400 mt-0.5">{bestEggDay ? format(new Date(bestEggDay.date), "MMM d, yyyy") : "No data"}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Highest Expense Day</div>
                      <div className="text-xl font-bold text-red-600">
                        {formatCurrency(highestExpenseDay ? highestExpenseDay.expenses : 0, currencyCode)}
                      </div>
                      <div className="text-xs text-slate-400 mt-0.5">
                        {highestExpenseDay ? format(new Date(highestExpenseDay.date), "MMM d, yyyy") : "No data"}
                      </div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Net Position</div>
                      <div className={`text-xl font-bold ${netProfit >= 0 ? "text-emerald-700" : "text-red-600"}`}>
                        {formatCurrency(netProfit, currencyCode)}
                      </div>
                    </CardContent>
                  </Card>
                </div>

                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Daily Eggs vs Expenses</CardTitle>
                    <CardDescription>Track same-day production volume and spending together.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <ChartContainer
                      config={{
                        eggs: { label: "Eggs", color: "hsl(142, 76%, 36%)" },
                        expenses: { label: "Expenses", color: "hsl(0, 84%, 60%)" },
                      }}
                      className="h-[360px] aspect-auto"
                    >
                      <LineChart
                        data={dailyEggExpenseReport.map((d) => ({
                          ...d,
                          label: format(new Date(d.date), "MM/dd"),
                        }))}
                      >
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="label" />
                        <YAxis />
                        <ChartTooltip content={<ChartTooltipContent />} />
                        <Legend />
                        <Line type="monotone" dataKey="eggs" stroke="var(--color-eggs)" strokeWidth={2} dot={false} />
                        <Line type="monotone" dataKey="expenses" stroke="var(--color-expenses)" strokeWidth={2} dot={false} />
                      </LineChart>
                    </ChartContainer>
                  </CardContent>
                </Card>

                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Daily Egg & Expense Report Table</CardTitle>
                    <CardDescription>Detailed daily report for eggs and expenses on the same day.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    {dailyEggExpenseReport.length === 0 ? (
                      <p className="text-sm text-slate-500">No daily report data for the selected filters.</p>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[760px] text-sm">
                          <thead className="bg-slate-50 text-left text-slate-600">
                            <tr>
                              <th className="px-3 py-2 font-semibold">Date</th>
                              <th className="px-3 py-2 font-semibold">Total Eggs</th>
                              <th className="px-3 py-2 font-semibold">Crates + Loose</th>
                              <th className="px-3 py-2 font-semibold">Daily Expenses</th>
                              <th className="px-3 py-2 font-semibold">Performance</th>
                            </tr>
                          </thead>
                          <tbody>
                            {dailyEggExpenseReport.map((row) => (
                              <tr key={row.date} className="border-t border-slate-200">
                                <td className="px-3 py-2">{format(new Date(row.date), "MMM d, yyyy")}</td>
                                <td className="px-3 py-2 font-medium">{row.eggs.toLocaleString()}</td>
                                <td className="px-3 py-2">{row.crates} crates + {row.looseEggs} loose</td>
                                <td className="px-3 py-2">{formatCurrency(row.expenses, currencyCode)}</td>
                                <td className="px-3 py-2">
                                  {row.expenses <= 0 ? (
                                    <span className="inline-flex items-center gap-1 text-emerald-700 font-medium">
                                      <TrendingUp className="w-4 h-4" /> No expense
                                    </span>
                                  ) : row.eggsPerExpenseUnit >= 1 ? (
                                    <span className="inline-flex items-center gap-1 text-emerald-700 font-medium">
                                      <TrendingUp className="w-4 h-4" /> Strong day
                                    </span>
                                  ) : (
                                    <span className="inline-flex items-center gap-1 text-amber-700 font-medium">
                                      <TrendingDown className="w-4 h-4" /> Review costs
                                    </span>
                                  )}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </>
            )}

            {tab === "insights" && (
              <>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="flex items-center gap-1.5 text-xs text-slate-500">
                        <Wallet className="w-3.5 h-3.5 text-emerald-600" />
                        Sales Products
                      </div>
                      <div className="text-2xl font-bold">{salesByProduct.length}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="flex items-center gap-1.5 text-xs text-slate-500">
                        <ReceiptText className="w-3.5 h-3.5 text-red-600" />
                        Expense Categories
                      </div>
                      <div className="text-2xl font-bold">{expensesByCategory.length}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Top Product Revenue</div>
                      <div className="text-xl font-bold text-emerald-700">
                        {formatCurrency(salesByProduct[0]?.revenue || 0, currencyCode)}
                      </div>
                      <div className="text-xs text-slate-400 mt-0.5">{salesByProduct[0]?.product || "No data"}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Top Expense Category</div>
                      <div className="text-xl font-bold text-red-600">
                        {formatCurrency(expensesByCategory[0]?.total || 0, currencyCode)}
                      </div>
                      <div className="text-xs text-slate-400 mt-0.5">{expensesByCategory[0]?.category || "No data"}</div>
                    </CardContent>
                  </Card>
                </div>

                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Sales by Product Report</CardTitle>
                    <CardDescription>See quantities and revenue split by product.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    {salesByProduct.length === 0 ? (
                      <p className="text-sm text-slate-500">No sales data for selected filters.</p>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[760px] text-sm">
                          <thead className="bg-slate-50 text-left text-slate-600">
                            <tr>
                              <th className="px-3 py-2 font-semibold">Product</th>
                              <th className="px-3 py-2 font-semibold">Transactions</th>
                              <th className="px-3 py-2 font-semibold">Quantity</th>
                              <th className="px-3 py-2 font-semibold">Revenue</th>
                            </tr>
                          </thead>
                          <tbody>
                            {salesByProduct.map((row) => (
                              <tr key={row.product} className="border-t border-slate-200">
                                <td className="px-3 py-2 font-medium">{row.product}</td>
                                <td className="px-3 py-2">{row.salesCount}</td>
                                <td className="px-3 py-2">{row.quantity.toLocaleString()}</td>
                                <td className="px-3 py-2">{formatCurrency(row.revenue, currencyCode)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </CardContent>
                </Card>

                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Expense Category Report</CardTitle>
                    <CardDescription>Track where most spending is happening.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    {expensesByCategory.length === 0 ? (
                      <p className="text-sm text-slate-500">No expense data for selected filters.</p>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[680px] text-sm">
                          <thead className="bg-slate-50 text-left text-slate-600">
                            <tr>
                              <th className="px-3 py-2 font-semibold">Category</th>
                              <th className="px-3 py-2 font-semibold">Total</th>
                            </tr>
                          </thead>
                          <tbody>
                            {expensesByCategory.map((row) => (
                              <tr key={row.category} className="border-t border-slate-200">
                                <td className="px-3 py-2 font-medium">{row.category}</td>
                                <td className="px-3 py-2">{formatCurrency(row.total, currencyCode)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </CardContent>
                </Card>

                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Flock Performance Report</CardTitle>
                    <CardDescription>Egg output, feed usage and mortality by flock.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    {flockProductionSummary.length === 0 ? (
                      <p className="text-sm text-slate-500">No production records for selected filters.</p>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[980px] text-sm">
                          <thead className="bg-slate-50 text-left text-slate-600">
                            <tr>
                              <th className="px-3 py-2 font-semibold">Flock</th>
                              <th className="px-3 py-2 font-semibold">Birds left (latest)</th>
                              <th className="px-3 py-2 font-semibold">Total Eggs</th>
                              <th className="px-3 py-2 font-semibold">Avg Eggs / Day</th>
                              <th className="px-3 py-2 font-semibold">Feed (kg)</th>
                              <th className="px-3 py-2 font-semibold">Mortality</th>
                            </tr>
                          </thead>
                          <tbody>
                            {flockProductionSummary.map((row) => (
                              <tr key={row.flockId} className="border-t border-slate-200">
                                <td className="px-3 py-2 font-medium">{row.flockName}</td>
                                <td className="px-3 py-2 font-medium text-indigo-800">{row.birdsLeftLatest.toLocaleString()}</td>
                                <td className="px-3 py-2">{row.eggs.toLocaleString()}</td>
                                <td className="px-3 py-2">{row.avgEggsPerDay.toLocaleString()}</td>
                                <td className="px-3 py-2">{row.feedKg.toLocaleString()}</td>
                                <td className="px-3 py-2">{row.mortality.toLocaleString()}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </>
            )}
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}

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
import { BarChart3, Plus, RotateCcw, Egg, Package } from "lucide-react"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
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

export default function ReportsPage() {
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
  const totalBirds = useMemo(() => {
    if (filteredRecords.length === 0) return 0
    // Get the latest record's noOfBirds
    const sorted = [...filteredRecords].sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
    return sorted[0]?.noOfBirds || 0
  }, [filteredRecords])
  const totalFeedKg = useMemo(() => filteredRecords.reduce((s, r: any) => s + (r.feedKg || 0), 0), [filteredRecords])

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
          <div className="space-y-4">
            {/* Page Header */}
            <div className="flex items-center justify-between">
              <div>
                <div className="flex items-center gap-3 mb-2">
                  <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                    <BarChart3 className="w-5 h-5 text-blue-600" />
                  </div>
                  <h1 className="text-2xl font-bold text-slate-900">Reports</h1>
                </div>
                <p className="text-slate-600">Comprehensive farm analytics and insights</p>
              </div>
              <Button className="gap-2 bg-blue-600 hover:bg-blue-700">
                <Plus className="w-4 h-4" />
                New Report
              </Button>
            </div>

            {/* Tabs + Filters toolbar */}
            <Card className="bg-white">
              <CardContent className="pt-4 pb-4">
                <div className="space-y-3">
                  <Tabs value={tab} onValueChange={setTab} className="w-full">
                    <TabsList>
                      <TabsTrigger value="production">Production</TabsTrigger>
                      <TabsTrigger value="financial">Financial</TabsTrigger>
                    </TabsList>
                  </Tabs>

                  {/* Filters Row */}
                  <div className="flex flex-wrap items-end gap-3">
                    <div className="w-full sm:w-auto">
                      <Label className="text-xs text-slate-500">Search</Label>
                      <Input
                        placeholder={tab === "production" ? "Search flock, medication..." : "Search product, customer..."}
                        className="w-full sm:w-[200px]"
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                      />
                    </div>
                    <div>
                      <Label className="text-xs text-slate-500">From</Label>
                      <Input
                        type="date"
                        className="w-[150px]"
                        value={dateFrom}
                        onChange={(e) => setDateFrom(e.target.value)}
                      />
                    </div>
                    <div>
                      <Label className="text-xs text-slate-500">To</Label>
                      <Input
                        type="date"
                        className="w-[150px]"
                        value={dateTo}
                        onChange={(e) => setDateTo(e.target.value)}
                      />
                    </div>
                    <div>
                      <Label className="text-xs text-slate-500">Flock</Label>
                      <Select value={selectedFlock} onValueChange={setSelectedFlock}>
                        <SelectTrigger className="w-[180px]">
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
                    <Button variant="outline" size="sm" onClick={clearFilters} className="gap-1 h-10">
                      <RotateCcw className="w-3.5 h-3.5" />
                      Reset
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Production content */}
            {tab === "production" && (
              <>
                {/* Metrics Row 1 */}
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
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
                        {formatCurrency(filteredSales.reduce((s: number, x: any) => s + Number(x.totalAmount || 0), 0), currencyCode)}
                      </div>
                      <div className="text-xs text-slate-400 mt-0.5">{filteredSales.length} transaction{filteredSales.length !== 1 ? 's' : ''}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Expenses</div>
                      <div className="text-2xl font-bold text-red-600">
                        {formatCurrency(filteredExpenses.reduce((s: number, x: any) => s + Number(x.amount || 0), 0), currencyCode)}
                      </div>
                      <div className="text-xs text-slate-400 mt-0.5">{filteredExpenses.length} expense{filteredExpenses.length !== 1 ? 's' : ''}</div>
                    </CardContent>
                  </Card>
                  <Card className="bg-white">
                    <CardContent className="py-4">
                      <div className="text-xs text-slate-500">Net Profit / Loss</div>
                      {(() => {
                        const rev = filteredSales.reduce((s: number, x: any) => s + Number(x.totalAmount || 0), 0)
                        const exp = filteredExpenses.reduce((s: number, x: any) => s + Number(x.amount || 0), 0)
                        const net = rev - exp
                        return (
                          <div className={`text-2xl font-bold ${net >= 0 ? 'text-emerald-700' : 'text-red-600'}`}>
                            {formatCurrency(net, currencyCode)}
                          </div>
                        )
                      })()}
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
          </div>
        </main>
      </div>
    </div>
  )
}

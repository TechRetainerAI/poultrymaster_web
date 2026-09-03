"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { BarChart3, DollarSign, TrendingUp, Clock, Users, UtensilsCrossed, ChevronLeft, ChevronRight, Utensils, LayoutDashboard, Download } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  BarChart, Bar, LineChart, Line, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from "recharts"
import { downloadPdf } from "@/lib/utils/download-pdf"
import {
  getDailySalesReport, getSalesByItem, getSalesByCategory, getSalesByHour,
  getRevenueTrend, getFoodCostReport, getServerPerformance,
  getCustomerStats, getDeliveryStats, getWasteSummary, listOrders,
  type DailySalesReport, type SalesByItemRow, type SalesByCategoryRow,
  type SalesByHourRow, type FoodCostRow, type ServerPerformanceRow, type RevenueTrendRow,
  type CustomerStats, type DeliveryStats, type WasteSummary, type Order,
} from "@/lib/api/restaurant"

const PIE_COLORS = ["#e11d48", "#f43f5e", "#fb7185", "#fda4af", "#fecdd3", "#9f1239", "#be123c", "#881337"]

export default function RestaurantReportsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)

  const [loading, setLoading] = useState(true)
  const [date, setDate] = useState(new Date().toISOString().split("T")[0])
  const [fromDate, setFromDate] = useState(() => { const d = new Date(); d.setDate(d.getDate() - 7); return d.toISOString().split("T")[0] })
  const [toDate, setToDate] = useState(new Date().toISOString().split("T")[0])

  const [dailySales, setDailySales] = useState<DailySalesReport | null>(null)
  const [salesByItem, setSalesByItem] = useState<SalesByItemRow[]>([])
  const [salesByCategory, setSalesByCategory] = useState<SalesByCategoryRow[]>([])
  const [salesByHour, setSalesByHour] = useState<SalesByHourRow[]>([])
  const [foodCost, setFoodCost] = useState<FoodCostRow[]>([])
  const [serverPerf, setServerPerf] = useState<ServerPerformanceRow[]>([])
  const [revenueTrend, setRevenueTrend] = useState<RevenueTrendRow[]>([])
  const [custStats, setCustStats] = useState<CustomerStats | null>(null)
  const [delStats, setDelStats] = useState<DeliveryStats | null>(null)
  const [wasteSummaryData, setWasteSummaryData] = useState<WasteSummary[]>([])
  const [allOrders, setAllOrders] = useState<Order[]>([])

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [ds, si, sc, sh, fc, sp, rt, cs, del, ws, ord] = await Promise.all([
        getDailySalesReport(date).catch(() => null),
        getSalesByItem(fromDate, toDate).catch(() => []),
        getSalesByCategory(fromDate, toDate).catch(() => []),
        getSalesByHour(date).catch(() => []),
        getFoodCostReport().catch(() => []),
        getServerPerformance(fromDate, toDate).catch(() => []),
        getRevenueTrend(fromDate, toDate).catch(() => []),
        getCustomerStats().catch(() => null),
        getDeliveryStats().catch(() => null),
        getWasteSummary().catch(() => []),
        listOrders().catch(() => []),
      ])
      setDailySales(ds); setSalesByItem(si); setSalesByCategory(sc); setSalesByHour(sh)
      setFoodCost(fc); setServerPerf(sp); setRevenueTrend(rt)
      setCustStats(cs); setDelStats(del); setWasteSummaryData(ws); setAllOrders(ord)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function changeDate(d: number) { const dt = new Date(date); dt.setDate(dt.getDate() + d); setDate(dt.toISOString().split("T")[0]) }

  useEffect(() => { if (!loading) loadAll() }, [date, fromDate, toDate])

  const avgFoodCost = foodCost.length > 0 ? foodCost.reduce((s, f) => s + f.foodCostPercent, 0) / foodCost.length : 0

  function downloadReport(tab: string) {
    const hn = activeFarmName || "Restaurant"
    switch (tab) {
      case "daily": {
        if (!dailySales) return
        downloadPdf({
          title: "Daily Sales Report",
          subtitle: `Report for ${date}`,
          filename: `daily-sales-${date}`,
          hotelName: hn,
          summaryCards: [
            { label: "Revenue", value: dailySales.totalRevenue.toFixed(2) },
            { label: "Orders", value: `${dailySales.completedOrders}/${dailySales.totalOrders}` },
            { label: "Avg Ticket", value: dailySales.avgTicket.toFixed(2) },
            { label: "Covers", value: String(dailySales.totalCovers) },
          ],
          headers: ["Metric", "Value"],
          rows: [
            ["Dine-In Orders", String(dailySales.dineInCount)],
            ["Dine-In Revenue", dailySales.dineInRevenue.toFixed(2)],
            ["Takeaway Orders", String(dailySales.takeawayCount)],
            ["Takeaway Revenue", dailySales.takeawayRevenue.toFixed(2)],
            ["Delivery Orders", String(dailySales.deliveryCount)],
            ["Delivery Revenue", dailySales.deliveryRevenue.toFixed(2)],
            ["Cash", dailySales.cashAmount.toFixed(2)],
            ["Card", dailySales.cardAmount.toFixed(2)],
            ["Mobile Money", dailySales.mobileAmount.toFixed(2)],
            ["Other", dailySales.otherAmount.toFixed(2)],
          ],
        })
        break
      }
      case "items": {
        downloadPdf({
          title: "Top Selling Items",
          filename: "top-items",
          hotelName: hn,
          dateRange: { from: fromDate, to: toDate },
          headers: ["Rank", "Item", "Qty Sold", "Orders", "Revenue"],
          rows: salesByItem.map((s, i) => [i + 1, s.itemName, s.quantitySold, s.orderCount, s.totalRevenue.toFixed(2)]),
        })
        break
      }
      case "foodcost": {
        downloadPdf({
          title: "Food Cost Report",
          filename: "food-cost",
          hotelName: hn,
          summaryCards: [{ label: "Avg Food Cost", value: avgFoodCost.toFixed(1) + "%" }],
          headers: ["Item", "Category", "Selling Price", "Recipe Cost", "Food Cost %", "Margin"],
          rows: foodCost.map(f => [f.itemName, f.categoryName, f.sellingPrice.toFixed(2), f.recipeCost.toFixed(2), f.foodCostPercent.toFixed(1) + "%", f.margin.toFixed(2)]),
        })
        break
      }
      case "hours": {
        downloadPdf({
          title: "Peak Hours Report",
          subtitle: `Date: ${date}`,
          filename: `peak-hours-${date}`,
          hotelName: hn,
          headers: ["Hour", "Orders", "Revenue"],
          rows: salesByHour.map(h => [`${String(h.hourOfDay).padStart(2, "0")}:00`, h.orderCount, h.totalRevenue.toFixed(2)]),
        })
        break
      }
      case "servers": {
        downloadPdf({
          title: "Server Performance Report",
          filename: "server-performance",
          hotelName: hn,
          dateRange: { from: fromDate, to: toDate },
          headers: ["Server", "Orders", "Covers", "Revenue", "Avg Ticket"],
          rows: serverPerf.map(s => [s.servedBy, s.orderCount, s.totalCovers, s.totalRevenue.toFixed(2), s.avgTicket.toFixed(2)]),
        })
        break
      }
      case "overview": {
        const todayOrders = allOrders.filter(o => new Date(o.createdAt).toDateString() === new Date().toDateString())
        const todayRevenue = todayOrders.filter(o => o.paymentStatus === "Paid").reduce((s, o) => s + o.totalAmount, 0)
        const activeOrders = allOrders.filter(o => !["Completed","Cancelled","Refunded"].includes(o.status))
        const avgTicket = todayOrders.length > 0 ? (todayRevenue / todayOrders.length).toFixed(2) : "0.00"
        downloadPdf({
          title: "Restaurant Overview",
          filename: "overview",
          hotelName: hn,
          summaryCards: [
            { label: "Today's Revenue", value: todayRevenue.toFixed(2) },
            { label: "Orders", value: String(todayOrders.length) },
            { label: "Active Orders", value: String(activeOrders.length) },
            { label: "Avg Ticket", value: avgTicket },
          ],
          headers: ["Metric", "Value"],
          rows: [
            ["Today's Revenue", todayRevenue.toFixed(2)],
            ["Today's Orders", String(todayOrders.length)],
            ["Active Orders", String(activeOrders.length)],
            ["Avg Ticket", avgTicket],
            ["Dine-In Orders", String(todayOrders.filter(o => o.orderType === "DineIn").length)],
            ["Takeaway Orders", String(todayOrders.filter(o => o.orderType === "Takeaway").length)],
            ["Delivery Orders", String(todayOrders.filter(o => o.orderType === "Delivery").length)],
            ["Cancelled Orders", String(allOrders.filter(o => o.status === "Cancelled").length)],
            ["Avg Food Cost", avgFoodCost > 0 ? avgFoodCost.toFixed(1) + "%" : "N/A"],
            ["Total Waste Cost", wasteSummaryData.reduce((s, w) => s + w.totalCost, 0).toFixed(2)],
            ["Total Customers", custStats ? String(custStats.totalCustomers) : "N/A"],
            ["VIP Customers", custStats ? String(custStats.vipCount) : "N/A"],
          ],
        })
        break
      }
    }
  }

  if (loading) return <PageSkeleton statCards={4} listRows={6} />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center"><BarChart3 className="h-5 w-5 text-rose-600" /></div>
                <div><h1 className="text-2xl font-bold text-gray-900">Reports & Analytics</h1><p className="text-sm text-muted-foreground">Sales, food cost, and performance insights</p></div>
              </div>
            </div>

            <Tabs defaultValue="overview" className="space-y-4">
              <TabsList className="bg-white border shadow-sm flex-wrap">
                <TabsTrigger value="overview" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><LayoutDashboard className="h-4 w-4 mr-2" />Overview</TabsTrigger>
                <TabsTrigger value="daily" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><DollarSign className="h-4 w-4 mr-2" />Daily Sales</TabsTrigger>
                <TabsTrigger value="trends" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><TrendingUp className="h-4 w-4 mr-2" />Trends</TabsTrigger>
                <TabsTrigger value="items" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><UtensilsCrossed className="h-4 w-4 mr-2" />Top Items</TabsTrigger>
                <TabsTrigger value="foodcost" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><Utensils className="h-4 w-4 mr-2" />Food Cost</TabsTrigger>
                <TabsTrigger value="hours" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><Clock className="h-4 w-4 mr-2" />Peak Hours</TabsTrigger>
                <TabsTrigger value="servers" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><Users className="h-4 w-4 mr-2" />Server Performance</TabsTrigger>
              </TabsList>

              {/* Overview */}
              <TabsContent value="overview" className="space-y-4">
                <div className="flex justify-end">
                  <Button variant="outline" size="sm" onClick={() => downloadReport("overview")}><Download className="h-4 w-4 mr-2" />Download PDF</Button>
                </div>
                {(() => {
                  const todayOrders = allOrders.filter(o => new Date(o.createdAt).toDateString() === new Date().toDateString())
                  const todayRevenue = todayOrders.filter(o => o.paymentStatus === "Paid").reduce((s, o) => s + o.totalAmount, 0)
                  const activeOrders = allOrders.filter(o => !["Completed","Cancelled","Refunded"].includes(o.status))
                  const cancelledOrders = allOrders.filter(o => o.status === "Cancelled")
                  const totalWaste = wasteSummaryData.reduce((s, w) => s + w.totalCost, 0)
                  const dineInOrders = todayOrders.filter(o => o.orderType === "DineIn")
                  const takeawayOrders = todayOrders.filter(o => o.orderType === "Takeaway")
                  const deliveryOrders = todayOrders.filter(o => o.orderType === "Delivery")
                  return (
                    <>
                      <h3 className="text-lg font-semibold">Today at a Glance</h3>
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                        {[
                          { l: "Today's Revenue", v: todayRevenue.toFixed(2), c: "text-green-700", bg: "border-l-green-500" },
                          { l: "Today's Orders", v: String(todayOrders.length), c: "text-blue-700", bg: "border-l-blue-500" },
                          { l: "Active Orders", v: String(activeOrders.length), c: "text-purple-700", bg: "border-l-purple-500" },
                          { l: "Avg Ticket", v: todayOrders.length > 0 ? (todayRevenue / todayOrders.length).toFixed(2) : "0.00", c: "text-amber-700", bg: "border-l-amber-500" },
                        ].map(s => (
                          <Card key={s.l} className={`border-l-4 ${s.bg}`}><CardContent className="py-3 px-4">
                            <div className={`text-2xl font-bold ${s.c}`}>{s.v}</div>
                            <div className="text-xs text-muted-foreground">{s.l}</div>
                          </CardContent></Card>
                        ))}
                      </div>

                      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                        {/* Order Breakdown */}
                        <Card><CardHeader className="pb-2"><CardTitle className="text-base">Order Types (Today)</CardTitle></CardHeader>
                          <CardContent>
                            {[["Dine-In", dineInOrders.length], ["Takeaway", takeawayOrders.length], ["Delivery", deliveryOrders.length]].map(([type, cnt]) => (
                              <div key={String(type)} className="flex justify-between py-2 border-b last:border-0">
                                <span className="text-sm">{type}</span>
                                <span className="font-bold">{cnt}</span>
                              </div>
                            ))}
                          </CardContent>
                        </Card>

                        {/* Customers */}
                        <Card><CardHeader className="pb-2"><CardTitle className="text-base">Customers</CardTitle></CardHeader>
                          <CardContent>
                            {custStats ? (
                              <>
                                {[["Total Customers", custStats.totalCustomers], ["VIP", custStats.vipCount], ["Regular", custStats.regularCount], ["New", custStats.newCount]].map(([l, v]) => (
                                  <div key={String(l)} className="flex justify-between py-2 border-b last:border-0">
                                    <span className="text-sm">{l}</span><span className="font-bold">{v}</span>
                                  </div>
                                ))}
                                <div className="flex justify-between py-2 mt-1">
                                  <span className="text-sm font-medium">Lifetime Value</span>
                                  <span className="font-bold text-rose-600">{custStats.totalLifetimeValue.toFixed(0)}</span>
                                </div>
                              </>
                            ) : <p className="text-sm text-muted-foreground">No customer data</p>}
                          </CardContent>
                        </Card>

                        {/* Delivery & Waste */}
                        <Card><CardHeader className="pb-2"><CardTitle className="text-base">Operations</CardTitle></CardHeader>
                          <CardContent>
                            {delStats && (
                              <>
                                <div className="flex justify-between py-2 border-b"><span className="text-sm">Available Drivers</span><span className="font-bold text-green-600">{delStats.availableDrivers}</span></div>
                                <div className="flex justify-between py-2 border-b"><span className="text-sm">On Delivery</span><span className="font-bold text-blue-600">{delStats.onDeliveryDrivers}</span></div>
                                <div className="flex justify-between py-2 border-b"><span className="text-sm">Avg Delivery Time</span><span className="font-bold">{delStats.avgDeliveryMins ? `${delStats.avgDeliveryMins.toFixed(0)}m` : "—"}</span></div>
                              </>
                            )}
                            <div className="flex justify-between py-2 border-b"><span className="text-sm">Cancelled Orders</span><span className="font-bold text-red-600">{cancelledOrders.length}</span></div>
                            <div className="flex justify-between py-2"><span className="text-sm">Total Waste Cost</span><span className="font-bold text-amber-600">{totalWaste.toFixed(2)}</span></div>
                          </CardContent>
                        </Card>
                      </div>

                      {/* Food Cost Summary */}
                      {avgFoodCost > 0 && (
                        <Card className={avgFoodCost > 35 ? "border-red-200 bg-red-50" : avgFoodCost > 30 ? "border-amber-200 bg-amber-50" : "border-green-200 bg-green-50"}>
                          <CardContent className="py-3 flex items-center gap-3">
                            <Utensils className={`h-5 w-5 ${avgFoodCost > 35 ? "text-red-600" : avgFoodCost > 30 ? "text-amber-600" : "text-green-600"}`} />
                            <span className="text-sm">Average food cost: <strong>{avgFoodCost.toFixed(1)}%</strong> — {avgFoodCost > 35 ? "Above target, review high-cost items" : avgFoodCost > 30 ? "Moderate, room for improvement" : "Healthy margins"}</span>
                          </CardContent>
                        </Card>
                      )}
                    </>
                  )
                })()}
              </TabsContent>

              {/* Daily Sales */}
              <TabsContent value="daily" className="space-y-4">
                <div className="flex items-center gap-2">
                  <Button variant="outline" size="icon" className="h-9 w-9" onClick={() => changeDate(-1)}><ChevronLeft className="h-4 w-4" /></Button>
                  <Input type="date" className="w-[170px] h-9" value={date} onChange={e => setDate(e.target.value)} />
                  <Button variant="outline" size="icon" className="h-9 w-9" onClick={() => changeDate(1)}><ChevronRight className="h-4 w-4" /></Button>
                  <Button variant="outline" size="sm" className="h-9" onClick={() => setDate(new Date().toISOString().split("T")[0])}>Today</Button>
                  <div className="ml-auto"><Button variant="outline" size="sm" onClick={() => downloadReport("daily")}><Download className="h-4 w-4 mr-2" />Download PDF</Button></div>
                </div>
                {dailySales && (
                  <>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                      {[
                        { l: "Total Revenue", v: dailySales.totalRevenue.toFixed(2), c: "text-green-700", bg: "border-l-green-500" },
                        { l: "Orders", v: `${dailySales.completedOrders}/${dailySales.totalOrders}`, c: "text-blue-700", bg: "border-l-blue-500" },
                        { l: "Avg Ticket", v: dailySales.avgTicket.toFixed(2), c: "text-purple-700", bg: "border-l-purple-500" },
                        { l: "Covers", v: String(dailySales.totalCovers), c: "text-amber-700", bg: "border-l-amber-500" },
                      ].map(s => (
                        <Card key={s.l} className={`border-l-4 ${s.bg}`}><CardContent className="py-3 px-4">
                          <div className={`text-2xl font-bold ${s.c}`}>{s.v}</div>
                          <div className="text-xs text-muted-foreground">{s.l}</div>
                        </CardContent></Card>
                      ))}
                    </div>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <Card><CardHeader className="pb-2"><CardTitle className="text-base">By Order Type</CardTitle></CardHeader>
                        <CardContent>
                          {[["Dine-In", dailySales.dineInCount, dailySales.dineInRevenue], ["Takeaway", dailySales.takeawayCount, dailySales.takeawayRevenue], ["Delivery", dailySales.deliveryCount, dailySales.deliveryRevenue]].map(([type, cnt, rev]) => (
                            <div key={String(type)} className="flex justify-between py-2 border-b last:border-0">
                              <span className="text-sm">{type}</span>
                              <div className="text-right"><span className="font-medium">{(rev as number).toFixed(2)}</span><span className="text-xs text-muted-foreground ml-2">({cnt} orders)</span></div>
                            </div>
                          ))}
                        </CardContent>
                      </Card>
                      <Card><CardHeader className="pb-2"><CardTitle className="text-base">By Payment Method</CardTitle></CardHeader>
                        <CardContent>
                          {[["Cash", dailySales.cashAmount], ["Card", dailySales.cardAmount], ["Mobile Money", dailySales.mobileAmount], ["Other", dailySales.otherAmount]].filter(([, v]) => (v as number) > 0).map(([method, amt]) => (
                            <div key={String(method)} className="flex justify-between py-2 border-b last:border-0">
                              <span className="text-sm">{method}</span>
                              <span className="font-medium">{(amt as number).toFixed(2)}</span>
                            </div>
                          ))}
                        </CardContent>
                      </Card>
                    </div>
                  </>
                )}
              </TabsContent>

              {/* Revenue Trends */}
              <TabsContent value="trends" className="space-y-4">
                <div className="flex items-center gap-2">
                  <Label className="text-sm">From</Label><Input type="date" className="w-[150px] h-9" value={fromDate} onChange={e => setFromDate(e.target.value)} />
                  <Label className="text-sm">To</Label><Input type="date" className="w-[150px] h-9" value={toDate} onChange={e => setToDate(e.target.value)} />
                </div>
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Revenue Trend</CardTitle><CardDescription>Daily revenue over selected period</CardDescription></CardHeader>
                  <CardContent>
                    {revenueTrend.length === 0 ? <p className="text-sm text-muted-foreground text-center py-8">No data for this period</p> : (
                      <ResponsiveContainer width="100%" height={350}>
                        <LineChart data={revenueTrend.map(r => ({ ...r, date: r.reportDate?.split("T")[0] ?? "" }))}>
                          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                          <XAxis dataKey="date" tick={{ fontSize: 12 }} />
                          <YAxis tick={{ fontSize: 12 }} />
                          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
                          <Legend />
                          <Line type="monotone" dataKey="totalRevenue" name="Revenue" stroke="#e11d48" strokeWidth={2} dot={{ fill: "#e11d48", r: 3 }} activeDot={{ r: 5 }} />
                          <Line type="monotone" dataKey="orderCount" name="Orders" stroke="#f43f5e" strokeWidth={2} strokeDasharray="5 5" dot={false} />
                        </LineChart>
                      </ResponsiveContainer>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Top Items */}
              <TabsContent value="items" className="space-y-4">
                <div className="flex items-center gap-2"><Label className="text-sm">From</Label><Input type="date" className="w-[150px] h-9" value={fromDate} onChange={e => setFromDate(e.target.value)} />
                  <Label className="text-sm">To</Label><Input type="date" className="w-[150px] h-9" value={toDate} onChange={e => setToDate(e.target.value)} />
                  <div className="ml-auto"><Button variant="outline" size="sm" onClick={() => downloadReport("items")}><Download className="h-4 w-4 mr-2" />Download PDF</Button></div></div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <Card><CardHeader className="pb-2"><CardTitle className="text-base">Top Selling Items</CardTitle></CardHeader>
                    <CardContent>{salesByItem.length === 0 ? <p className="text-sm text-muted-foreground text-center py-4">No data</p> :
                      salesByItem.slice(0, 10).map((s, i) => (
                        <div key={s.menuItemId} className="flex items-center gap-3 py-2 border-b last:border-0">
                          <span className="text-sm font-bold text-muted-foreground w-6">{i + 1}</span>
                          <div className="flex-1"><div className="text-sm font-medium">{s.itemName}</div><div className="text-xs text-muted-foreground">{s.quantitySold} sold | {s.orderCount} orders</div></div>
                          <span className="font-bold">{s.totalRevenue.toFixed(2)}</span>
                        </div>
                      ))}
                    </CardContent>
                  </Card>
                  <Card><CardHeader className="pb-2"><CardTitle className="text-base">Sales by Category</CardTitle></CardHeader>
                    <CardContent>
                      {salesByCategory.length === 0 ? <p className="text-sm text-muted-foreground text-center py-4">No data</p> : (
                        <>
                          <ResponsiveContainer width="100%" height={220}>
                            <PieChart>
                              <Pie data={salesByCategory} dataKey="totalRevenue" nameKey="categoryName" cx="50%" cy="50%" outerRadius={80} label={({ categoryName, percent }) => `${categoryName} ${(percent * 100).toFixed(0)}%`} labelLine={false}>
                                {salesByCategory.map((_, i) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
                              </Pie>
                              <Tooltip formatter={(v: number) => v.toFixed(2)} />
                            </PieChart>
                          </ResponsiveContainer>
                          {salesByCategory.map(c => (
                            <div key={c.categoryName} className="flex items-center justify-between py-2 border-b last:border-0">
                              <div><div className="text-sm font-medium">{c.categoryName}</div><div className="text-xs text-muted-foreground">{c.itemCount} items | {c.quantitySold} sold</div></div>
                              <span className="font-bold">{c.totalRevenue.toFixed(2)}</span>
                            </div>
                          ))}
                        </>
                      )}
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Food Cost */}
              <TabsContent value="foodcost" className="space-y-4">
                <div className="flex justify-end">
                  <Button variant="outline" size="sm" onClick={() => downloadReport("foodcost")}><Download className="h-4 w-4 mr-2" />Download PDF</Button>
                </div>
                <Card className={avgFoodCost > 35 ? "border-red-200 bg-red-50" : avgFoodCost > 30 ? "border-amber-200 bg-amber-50" : ""}>
                  <CardContent className="py-3 flex items-center gap-3">
                    <Utensils className={`h-5 w-5 ${avgFoodCost > 35 ? "text-red-600" : avgFoodCost > 30 ? "text-amber-600" : "text-green-600"}`} />
                    <span className="text-sm">Average food cost: <strong className={avgFoodCost > 35 ? "text-red-700" : avgFoodCost > 30 ? "text-amber-700" : "text-green-700"}>{avgFoodCost.toFixed(1)}%</strong> {avgFoodCost > 35 ? "(Above target)" : avgFoodCost > 30 ? "(Moderate)" : "(Healthy)"}</span>
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Food Cost by Menu Item</CardTitle><CardDescription>Items with recipes — sorted by food cost %</CardDescription></CardHeader>
                  <CardContent>
                    {foodCost.length === 0 ? <p className="text-sm text-muted-foreground text-center py-8">No recipe data — add recipes to menu items to see food cost analysis</p> : (
                      <div className="space-y-1">
                        <div className="grid grid-cols-6 gap-2 px-3 py-2 text-xs font-medium text-muted-foreground uppercase tracking-wide border-b">
                          <span className="col-span-2">Item</span><span>Selling</span><span>Cost</span><span>Food Cost %</span><span>Margin</span>
                        </div>
                        {foodCost.map(f => (
                          <div key={f.menuItemId} className={`grid grid-cols-6 gap-2 px-3 py-2 rounded-lg text-sm ${f.foodCostPercent > 35 ? "bg-red-50" : f.foodCostPercent > 30 ? "bg-amber-50" : ""}`}>
                            <div className="col-span-2"><span className="font-medium">{f.itemName}</span><div className="text-xs text-muted-foreground">{f.categoryName}</div></div>
                            <span>{f.sellingPrice.toFixed(2)}</span>
                            <span>{f.recipeCost.toFixed(2)}</span>
                            <span className={`font-bold ${f.foodCostPercent > 35 ? "text-red-700" : f.foodCostPercent > 30 ? "text-amber-700" : "text-green-700"}`}>{f.foodCostPercent.toFixed(1)}%</span>
                            <span className="font-medium">{f.margin.toFixed(2)}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Peak Hours — recharts BarChart */}
              <TabsContent value="hours" className="space-y-4">
                <div className="flex items-center gap-2">
                  <Button variant="outline" size="icon" className="h-9 w-9" onClick={() => changeDate(-1)}><ChevronLeft className="h-4 w-4" /></Button>
                  <Input type="date" className="w-[170px] h-9" value={date} onChange={e => setDate(e.target.value)} />
                  <Button variant="outline" size="icon" className="h-9 w-9" onClick={() => changeDate(1)}><ChevronRight className="h-4 w-4" /></Button>
                  <div className="ml-auto"><Button variant="outline" size="sm" onClick={() => downloadReport("hours")}><Download className="h-4 w-4 mr-2" />Download PDF</Button></div>
                </div>
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Orders & Revenue by Hour</CardTitle></CardHeader>
                  <CardContent>
                    {salesByHour.length === 0 ? <p className="text-sm text-muted-foreground text-center py-8">No data for this date</p> : (
                      <ResponsiveContainer width="100%" height={350}>
                        <BarChart data={salesByHour.map(h => ({ ...h, hour: `${String(h.hourOfDay).padStart(2, "0")}:00` }))}>
                          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                          <XAxis dataKey="hour" tick={{ fontSize: 11 }} />
                          <YAxis yAxisId="left" tick={{ fontSize: 12 }} />
                          <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 12 }} />
                          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
                          <Legend />
                          <Bar yAxisId="left" dataKey="totalRevenue" name="Revenue" fill="#e11d48" radius={[4, 4, 0, 0]} />
                          <Bar yAxisId="right" dataKey="orderCount" name="Orders" fill="#fda4af" radius={[4, 4, 0, 0]} />
                        </BarChart>
                      </ResponsiveContainer>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Server Performance */}
              <TabsContent value="servers" className="space-y-4">
                <div className="flex items-center gap-2"><Label className="text-sm">From</Label><Input type="date" className="w-[150px] h-9" value={fromDate} onChange={e => setFromDate(e.target.value)} />
                  <Label className="text-sm">To</Label><Input type="date" className="w-[150px] h-9" value={toDate} onChange={e => setToDate(e.target.value)} />
                  <div className="ml-auto"><Button variant="outline" size="sm" onClick={() => downloadReport("servers")}><Download className="h-4 w-4 mr-2" />Download PDF</Button></div></div>
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Server / Waiter Performance</CardTitle></CardHeader>
                  <CardContent>
                    {serverPerf.length === 0 ? <p className="text-sm text-muted-foreground text-center py-8">No data</p> : (
                      <div className="space-y-2">
                        {serverPerf.map((s, i) => (
                          <div key={s.servedBy} className="flex items-center gap-4 p-3 border rounded-lg">
                            <div className="h-10 w-10 rounded-xl bg-rose-100 flex items-center justify-center font-bold text-rose-700 flex-shrink-0">{i + 1}</div>
                            <div className="flex-1">
                              <div className="font-semibold">{s.servedBy}</div>
                              <div className="text-xs text-muted-foreground">{s.orderCount} orders | {s.totalCovers} covers | Avg: {s.avgTicket.toFixed(2)}</div>
                            </div>
                            <div className="text-right"><div className="font-bold text-lg">{s.totalRevenue.toFixed(2)}</div><div className="text-xs text-muted-foreground">revenue</div></div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>
    </div>
  )
}

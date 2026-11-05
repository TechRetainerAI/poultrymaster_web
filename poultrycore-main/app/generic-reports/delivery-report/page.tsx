"use client"

// Delivery Report — driver performance, product sell-through, and route profitability.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ListFilters } from "@/components/ui/list-filters"
import { Truck, Users2, ShoppingBag, MapPin, Loader2, Download, TrendingUp, TrendingDown, Package } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import {
  getDriverReport, getProductDeliveryReport, getRouteReport,
  type GenericDriverReport, type GenericProductDeliveryReport, type GenericRouteReport,
} from "@/lib/api/generic"
import { exportTableToPdf } from "@/lib/utils/pdf-export"

const DEFAULT = defaultReportRange()
type Tab = "drivers" | "products" | "routes"

export default function GenericDeliveryReportPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [tab, setTab] = useState<Tab>("drivers")
  const [loading, setLoading] = useState(true)
  const [dateFrom, setDateFrom] = useState(DEFAULT.from)
  const [dateTo, setDateTo] = useState(DEFAULT.to)
  const [search, setSearch] = useState("")

  const [drivers, setDrivers] = useState<GenericDriverReport[]>([])
  const [products, setProducts] = useState<GenericProductDeliveryReport[]>([])
  const [routes, setRoutes] = useState<GenericRouteReport[]>([])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [d, p, r] = await Promise.allSettled([
        getDriverReport(dateFrom, dateTo),
        getProductDeliveryReport(dateFrom, dateTo),
        getRouteReport(dateFrom, dateTo),
      ])
      setDrivers(d.status === "fulfilled" ? d.value : [])
      setProducts(p.status === "fulfilled" ? p.value : [])
      setRoutes(r.status === "fulfilled" ? r.value : [])
    } catch (e: any) {
      toast({ title: "Could not load report", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  // KPI totals across all drivers
  const driverTotals = useMemo(() => {
    let deliveries = 0, sales = 0, cash = 0, expenses = 0, loaded = 0, sold = 0
    for (const d of drivers) {
      deliveries += d.totalDeliveries; sales += d.totalSales; cash += d.totalCashCollected
      expenses += d.totalExpenses; loaded += d.totalLoaded; sold += d.totalSold
    }
    return { deliveries, sales, cash, expenses, loaded, sold, rate: loaded > 0 ? Math.round(sold / loaded * 100) : 0 }
  }, [drivers])

  const TABS: { id: Tab; label: string; icon: any }[] = [
    { id: "drivers", label: "By Driver", icon: Users2 },
    { id: "products", label: "By Product", icon: ShoppingBag },
    { id: "routes", label: "By Route", icon: MapPin },
  ]

  function doExport() {
    if (tab === "drivers") {
      exportTableToPdf({
        title: "Delivery Report — By Driver", subtitle: `${dateFrom} to ${dateTo}`,
        columns: [
          { header: "Driver", key: "driverName", width: 100 },
          { header: "Deliveries", key: "totalDeliveries", width: 60, align: "right" },
          { header: "Loaded", key: "totalLoaded", width: 60, align: "right" },
          { header: "Sold", key: "totalSold", width: 60, align: "right" },
          { header: "Sales", key: "totalSales", width: 80, align: "right", format: "currency" },
          { header: "Rate %", key: "deliveryRate", width: 50, align: "right" },
        ],
        rows: drivers,
      })
    } else if (tab === "products") {
      exportTableToPdf({
        title: "Delivery Report — By Product", subtitle: `${dateFrom} to ${dateTo}`,
        columns: [
          { header: "Product", key: "productName", width: 120 },
          { header: "Deliveries", key: "totalDeliveries", width: 60, align: "right" },
          { header: "Loaded", key: "totalLoaded", width: 60, align: "right" },
          { header: "Sold", key: "totalSold", width: 60, align: "right" },
          { header: "Sales", key: "totalSales", width: 80, align: "right", format: "currency" },
          { header: "Sell-through %", key: "sellThroughRate", width: 70, align: "right" },
        ],
        rows: products,
      })
    } else {
      exportTableToPdf({
        title: "Delivery Report — By Route", subtitle: `${dateFrom} to ${dateTo}`,
        columns: [
          { header: "Route", key: "route", width: 120 },
          { header: "Deliveries", key: "totalDeliveries", width: 60, align: "right" },
          { header: "Sales", key: "totalSales", width: 80, align: "right", format: "currency" },
          { header: "Expenses", key: "totalExpenses", width: 80, align: "right", format: "currency" },
          { header: "Net Revenue", key: "netRevenue", width: 80, align: "right", format: "currency" },
        ],
        rows: routes,
      })
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Truck className="h-5 w-5 text-emerald-600" /> Delivery Report
              </h1>
              <p className="text-xs text-slate-500">Driver performance, product sell-through, and route profitability.</p>
            </div>
            <Button size="sm" variant="outline" onClick={doExport} disabled={loading}>
              <Download className="h-4 w-4 mr-1" /> Export PDF
            </Button>
          </div>

          {/* KPI summary */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><Package className="h-3.5 w-3.5" /> Total Deliveries</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{driverTotals.deliveries}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><TrendingUp className="h-3.5 w-3.5" /> Total Sales</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{gh(driverTotals.sales)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><TrendingDown className="h-3.5 w-3.5" /> Total Expenses</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-red-700">{gh(driverTotals.expenses)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><Truck className="h-3.5 w-3.5" /> Sell-through Rate</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{driverTotals.rate}%</div>
            </CardContent></Card>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchPlaceholder="Search driver, product, route…"
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
          />

          {/* Tabs */}
          <div className="flex gap-1">
            {TABS.map((t) => (
              <Button key={t.id} size="sm" variant={tab === t.id ? "default" : "outline"}
                onClick={() => setTab(t.id)}>
                <t.icon className="h-4 w-4 mr-1" /> {t.label}
              </Button>
            ))}
            <Button size="sm" variant="ghost" onClick={load} disabled={loading} className="ml-auto">
              {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : "Refresh"}
            </Button>
          </div>

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600"><Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading report…</CardContent></Card>
          ) : tab === "drivers" ? (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Driver Performance</CardTitle>
                <CardDescription className="text-xs">{drivers.length} driver(s) in period</CardDescription>
              </CardHeader>
              <CardContent className="p-0 md:p-2">
                {drivers.length === 0 ? (
                  <p className="p-8 text-center text-slate-500">No delivery data for this period.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Driver</TableHead>
                        <TableHead>Transport</TableHead>
                        <TableHead className="text-right">Trips</TableHead>
                        <TableHead className="text-right">Loaded</TableHead>
                        <TableHead className="text-right">Sold</TableHead>
                        <TableHead className="text-right">Returned</TableHead>
                        <TableHead className="text-right">Damaged</TableHead>
                        <TableHead className="text-right">Short</TableHead>
                        <TableHead className="text-right">Sales</TableHead>
                        <TableHead className="text-right">Cash</TableHead>
                        <TableHead className="text-right">Expenses</TableHead>
                        <TableHead className="text-right">Rate</TableHead>
                        <TableHead>Status Breakdown</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {drivers.filter((d) => !search || d.driverName.toLowerCase().includes(search.toLowerCase())).map((d) => (
                          <TableRow key={d.driverName}>
                            <TableCell className="font-medium">{d.driverName}</TableCell>
                            <TableCell><Badge className="bg-blue-100 text-blue-700">{d.transportMode ?? "Car"}</Badge></TableCell>
                            <TableCell className="text-right tabular-nums">{d.totalDeliveries}</TableCell>
                            <TableCell className="text-right tabular-nums">{d.totalLoaded}</TableCell>
                            <TableCell className="text-right tabular-nums text-emerald-700">{d.totalSold}</TableCell>
                            <TableCell className="text-right tabular-nums">{d.totalReturned}</TableCell>
                            <TableCell className="text-right tabular-nums text-red-600">{d.totalDamaged}</TableCell>
                            <TableCell className="text-right tabular-nums text-amber-600">{d.totalShort}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold">{gh(d.totalSales)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(d.totalCashCollected)}</TableCell>
                            <TableCell className="text-right tabular-nums text-red-600">{gh(d.totalExpenses)}</TableCell>
                            <TableCell className="text-right">
                              <span className={cn("font-semibold", d.deliveryRate >= 80 ? "text-emerald-700" : d.deliveryRate >= 50 ? "text-amber-600" : "text-red-600")}>
                                {d.deliveryRate}%
                              </span>
                            </TableCell>
                            <TableCell>
                              <div className="flex gap-1 flex-wrap">
                                {d.loadedDeliveries > 0 && <Badge className="bg-slate-100 text-slate-700 text-[10px]">{d.loadedDeliveries} loaded</Badge>}
                                {d.inTransitDeliveries > 0 && <Badge className="bg-blue-100 text-blue-700 text-[10px]">{d.inTransitDeliveries} transit</Badge>}
                                {d.deliveredDeliveries > 0 && <Badge className="bg-emerald-100 text-emerald-700 text-[10px]">{d.deliveredDeliveries} delivered</Badge>}
                                {d.reconciledDeliveries > 0 && <Badge className="bg-green-100 text-green-700 text-[10px]">{d.reconciledDeliveries} done</Badge>}
                                {d.cancelledDeliveries > 0 && <Badge className="bg-amber-100 text-amber-700 text-[10px]">{d.cancelledDeliveries} cancelled</Badge>}
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </CardContent>
            </Card>
          ) : tab === "products" ? (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Product Delivery Performance</CardTitle>
                <CardDescription className="text-xs">{products.length} product(s) delivered in period</CardDescription>
              </CardHeader>
              <CardContent className="p-0 md:p-2">
                {products.length === 0 ? (
                  <p className="p-8 text-center text-slate-500">No reconciled deliveries in this period.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Product</TableHead>
                        <TableHead className="text-right">Deliveries</TableHead>
                        <TableHead className="text-right">Loaded</TableHead>
                        <TableHead className="text-right">Sold</TableHead>
                        <TableHead className="text-right">Returned</TableHead>
                        <TableHead className="text-right">Damaged</TableHead>
                        <TableHead className="text-right">Short</TableHead>
                        <TableHead className="text-right">Sales</TableHead>
                        <TableHead className="text-right">Sell-through</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {products.filter((p) => !search || p.productName.toLowerCase().includes(search.toLowerCase())).map((p) => (
                          <TableRow key={p.productName}>
                            <TableCell className="font-medium">{p.productName}</TableCell>
                            <TableCell className="text-right tabular-nums">{p.totalDeliveries}</TableCell>
                            <TableCell className="text-right tabular-nums">{p.totalLoaded}</TableCell>
                            <TableCell className="text-right tabular-nums text-emerald-700">{p.totalSold}</TableCell>
                            <TableCell className="text-right tabular-nums">{p.totalReturned}</TableCell>
                            <TableCell className="text-right tabular-nums text-red-600">{p.totalDamaged}</TableCell>
                            <TableCell className="text-right tabular-nums text-amber-600">{p.totalShort}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold">{gh(p.totalSales)}</TableCell>
                            <TableCell className="text-right">
                              <span className={cn("font-semibold", p.sellThroughRate >= 80 ? "text-emerald-700" : p.sellThroughRate >= 50 ? "text-amber-600" : "text-red-600")}>
                                {p.sellThroughRate}%
                              </span>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </CardContent>
            </Card>
          ) : (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Route Profitability</CardTitle>
                <CardDescription className="text-xs">{routes.length} route(s) in period</CardDescription>
              </CardHeader>
              <CardContent className="p-0 md:p-2">
                {routes.length === 0 ? (
                  <p className="p-8 text-center text-slate-500">No reconciled deliveries in this period.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Route</TableHead>
                        <TableHead className="text-right">Deliveries</TableHead>
                        <TableHead className="text-right">Loaded</TableHead>
                        <TableHead className="text-right">Sold</TableHead>
                        <TableHead className="text-right">Sales</TableHead>
                        <TableHead className="text-right">Expenses</TableHead>
                        <TableHead className="text-right">Net Revenue</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {routes.filter((r) => !search || r.route.toLowerCase().includes(search.toLowerCase())).map((r) => (
                          <TableRow key={r.route}>
                            <TableCell className="font-medium">{r.route}</TableCell>
                            <TableCell className="text-right tabular-nums">{r.totalDeliveries}</TableCell>
                            <TableCell className="text-right tabular-nums">{r.totalLoaded}</TableCell>
                            <TableCell className="text-right tabular-nums">{r.totalSold}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(r.totalSales)}</TableCell>
                            <TableCell className="text-right tabular-nums text-red-600">{gh(r.totalExpenses)}</TableCell>
                            <TableCell className={cn("text-right tabular-nums font-semibold", r.netRevenue >= 0 ? "text-emerald-700" : "text-red-600")}>
                              {gh(r.netRevenue)}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

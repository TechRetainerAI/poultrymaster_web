"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Loader2, BarChart3, RefreshCw } from "lucide-react"
import { DataPagination } from "@/components/ui/data-pagination"
import { ReportTableCards } from "@/components/reports/report-shell"
import { usePagination } from "@/hooks/use-pagination"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getWaterPeriodPnL, getWaterRouteProfitability, getWaterDriverReconciliation, getWaterRawMaterialVariance,
  type WaterPeriodPnL, type WaterRouteProfitabilityRow, type WaterDriverReconciliationRow, type WaterRawMaterialVarianceRow,
} from "@/lib/api/water"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod, defaultReportRange } from "@/lib/date-ranges"

// Helpers for the default date range — last 7 days
function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 7); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function WaterReportsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()

  const DEFAULT_RANGE = defaultReportRange("last7")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)

  const [pnl, setPnl] = useState<WaterPeriodPnL | null>(null)
  const [routes, setRoutes] = useState<WaterRouteProfitabilityRow[]>([])
  const [drivers, setDrivers] = useState<WaterDriverReconciliationRow[]>([])
  const [variance, setVariance] = useState<WaterRawMaterialVarianceRow[]>([])
  // One pager per tab. DataPagination hides itself while a tab is short, so a
  // three-route farm sees no change.
  const pgRoutes = usePagination(routes)
  const pgDrivers = usePagination(drivers)
  const pgVariance = usePagination(variance)
  const [loading, setLoading] = useState(true)

  // Auto-refetch when the company resolves or the date range changes — matches
  // the behaviour of every other water report (no manual "Apply" needed).
  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, fromDate, toDate])

  async function load() {
    setLoading(true)
    // Each report independent — Promise.allSettled so one failure doesn't blank the page.
    const [pnlR, routeR, driverR, varianceR] = await Promise.allSettled([
      getWaterPeriodPnL(fromDate, toDate),
      getWaterRouteProfitability(fromDate, toDate),
      getWaterDriverReconciliation(fromDate, toDate),
      getWaterRawMaterialVariance(fromDate, toDate),
    ])
    if (pnlR.status === "fulfilled") setPnl(pnlR.value); else setPnl(null)
    if (routeR.status === "fulfilled") setRoutes(routeR.value); else setRoutes([])
    if (driverR.status === "fulfilled") setDrivers(driverR.value); else setDrivers([])
    if (varianceR.status === "fulfilled") setVariance(varianceR.value); else setVariance([])
    // Only surface error when every report failed (suggests auth/backend issue).
    if ([pnlR, routeR, driverR, varianceR].every(r => r.status === "rejected")) {
      const reason = (pnlR.status === "rejected" ? (pnlR.reason as any)?.message : null) ?? "Reports could not be loaded"
      toast({ title: "Could not load reports", description: reason, variant: "destructive" })
    }
    setLoading(false)
  }

  function setRange(days: number) {
    const t = new Date(); const f = new Date(); f.setDate(f.getDate() - days)
    setFromDate(isoDate(f)); setToDate(isoDate(t))
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2 flex-wrap">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <BarChart3 className="h-6 w-6 text-sky-600" /> Water reports
            </h1>
            <Button variant="outline" onClick={load} disabled={loading}><RefreshCw className={`h-4 w-4 mr-1 ${loading ? "animate-spin" : ""}`} /> Refresh</Button>
          </div>

          <Card className="mb-4">
            <CardContent className="p-4 flex flex-wrap items-end gap-3">
              <PeriodSelect value={rangeToPeriod(fromDate, toDate)} onChange={(_p, rg) => { if (rg) { setFromDate(rg.from); setToDate(rg.to) } }} />
              <div><Label>From</Label>
                <Input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} /></div>
              <div><Label>To</Label>
                <Input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} /></div>
              <div className="flex gap-1 ml-auto">
                <Button size="sm" variant="outline" onClick={() => setRange(7)}>7d</Button>
                <Button size="sm" variant="outline" onClick={() => setRange(30)}>30d</Button>
                <Button size="sm" variant="outline" onClick={() => setRange(90)}>90d</Button>
                <Button size="sm" onClick={load}>Apply</Button>
              </div>
            </CardContent>
          </Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading reports…</div>
          ) : (
            <Tabs defaultValue="pnl">
              <TabsList>
                <TabsTrigger value="pnl">Period P&amp;L</TabsTrigger>
                <TabsTrigger value="routes">Route profitability ({routes.length})</TabsTrigger>
                <TabsTrigger value="drivers">Driver reconciliation ({drivers.length})</TabsTrigger>
                <TabsTrigger value="variance">Raw material variance ({variance.length})</TabsTrigger>
              </TabsList>

              <TabsContent value="pnl">
                {pnl ? (
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                    <Stat label="Period" value={`${pnl.periodStart?.split("T")[0]} → ${pnl.periodEnd?.split("T")[0]}`} />
                    <Stat label="Bags produced" value={String(pnl.bagsProduced ?? 0)} />
                    <Stat label="Bags sold" value={String(pnl.bagsSold ?? 0)} />
                    <Stat label="Total income" value={gh(pnl.totalIncome)} accent="green" />
                    <Stat label="Raw materials & supplies" value={gh(pnl.rawMaterialCost)} accent="rose" />
                    <Stat label="Production cost" value={gh(pnl.productionCost)} accent="rose" />
                    <Stat label="Total expenses" value={gh(pnl.totalExpenses)} accent="rose" />
                    <Stat label="Net profit" value={gh(pnl.netProfit)} accent={(pnl.netProfit ?? 0) >= 0 ? "green" : "rose"} />
                    <Stat label="Profit margin" value={`${(pnl.profitMarginPct ?? 0).toFixed(1)}%`} accent={(pnl.profitMarginPct ?? 0) >= 0 ? "green" : "rose"} />
                    <Stat label="Avg profit per bag" value={gh(pnl.avgProfitPerBag)} accent={(pnl.avgProfitPerBag ?? 0) >= 0 ? "green" : "rose"} />
                  </div>
                ) : (
                  <div className="text-slate-500 p-8 text-center">No P&amp;L data for this period.</div>
                )}
              </TabsContent>

              <TabsContent value="routes">
                <Card>
                  <CardContent className="p-0">
                    {routes.length === 0 ? <div className="p-8 text-center text-slate-500">No route data.</div> : (
                      <ReportTableCards
                        columns={[
                          { header: "Route" }, { header: "Loaded", align: "right" }, { header: "Sold", align: "right" },
                          { header: "Revenue", align: "right" }, { header: "Shortages", align: "right" }, { header: "Net", align: "right" },
                        ]}
                        rows={routes.map((r) => [
                          r.routeName, r.totalBagsLoaded, r.totalBagsSold,
                          gh(r.totalRevenue), gh(r.totalShortages), gh(r.netRouteIncome),
                        ])}
                      >
                      <div className="overflow-x-auto">
                      <Table>
                        <TableHeader><TableRow><TableHead>Route</TableHead><TableHead className="text-right">Loaded</TableHead><TableHead className="text-right">Sold</TableHead><TableHead className="text-right">Revenue</TableHead><TableHead className="text-right">Shortages</TableHead><TableHead className="text-right">Net</TableHead></TableRow></TableHeader>
                        <TableBody>
                          {pgRoutes.pageItems.map((r) => (
                            <TableRow key={r.waterRouteId}>
                              <TableCell className="font-medium">{r.routeName}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.totalBagsLoaded}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.totalBagsSold}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.totalRevenue)}</TableCell>
                              <TableCell className="text-right tabular-nums text-rose-600">{gh(r.totalShortages)}</TableCell>
                              <TableCell className={`text-right tabular-nums font-semibold ${r.netRouteIncome >= 0 ? "text-green-700" : "text-rose-600"}`}>{gh(r.netRouteIncome)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      </div>
                      <DataPagination {...pgRoutes.paginationProps} className="px-4 pb-4" />
                      </ReportTableCards>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="drivers">
                <Card>
                  <CardContent className="p-0">
                    {drivers.length === 0 ? <div className="p-8 text-center text-slate-500">No driver data.</div> : (
                      <ReportTableCards
                        columns={[
                          { header: "Driver" }, { header: "Loaded", align: "right" }, { header: "Sold", align: "right" },
                          { header: "Expected", align: "right" }, { header: "Accounted", align: "right" }, { header: "Shortages", align: "right" },
                        ]}
                        rows={drivers.map((d) => [
                          d.driverName, d.totalBagsLoaded, d.totalBagsSold,
                          gh(d.expectedRevenue), gh(d.actualAccountedFor), gh(d.totalShortages),
                        ])}
                      >
                      <div className="overflow-x-auto">
                      <Table>
                        <TableHeader><TableRow><TableHead>Driver</TableHead><TableHead className="text-right">Loaded</TableHead><TableHead className="text-right">Sold</TableHead><TableHead className="text-right">Expected</TableHead><TableHead className="text-right">Accounted</TableHead><TableHead className="text-right">Shortages</TableHead></TableRow></TableHeader>
                        <TableBody>
                          {pgDrivers.pageItems.map((d) => (
                            <TableRow key={d.waterDriverId}>
                              <TableCell className="font-medium">{d.driverName}</TableCell>
                              <TableCell className="text-right tabular-nums">{d.totalBagsLoaded}</TableCell>
                              <TableCell className="text-right tabular-nums">{d.totalBagsSold}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(d.expectedRevenue)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(d.actualAccountedFor)}</TableCell>
                              <TableCell className={`text-right tabular-nums ${d.totalShortages > 0 ? "text-rose-600" : ""}`}>{gh(d.totalShortages)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      </div>
                      <DataPagination {...pgDrivers.paginationProps} className="px-4 pb-4" />
                      </ReportTableCards>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="variance">
                <Card>
                  <CardContent className="p-0">
                    {variance.length === 0 ? <div className="p-8 text-center text-slate-500">No usage data.</div> : (
                      <ReportTableCards
                        columns={[
                          { header: "Item" }, { header: "Category" }, { header: "Expected", align: "right" },
                          { header: "Actual", align: "right" }, { header: "Variance", align: "right" }, { header: "Usage count", align: "right" },
                        ]}
                        rows={variance.map((v) => [
                          v.itemName, v.category, v.totalExpected,
                          v.totalActual, v.totalVariance, v.usageCount,
                        ])}
                      >
                      <div className="overflow-x-auto">
                      <Table>
                        <TableHeader><TableRow><TableHead>Item</TableHead><TableHead>Category</TableHead><TableHead className="text-right">Expected</TableHead><TableHead className="text-right">Actual</TableHead><TableHead className="text-right">Variance</TableHead><TableHead className="text-right">Usage count</TableHead></TableRow></TableHeader>
                        <TableBody>
                          {pgVariance.pageItems.map((v) => (
                            <TableRow key={v.waterRawMaterialItemId}>
                              <TableCell className="font-medium">{v.itemName}</TableCell>
                              <TableCell>{v.category}</TableCell>
                              <TableCell className="text-right tabular-nums">{v.totalExpected}</TableCell>
                              <TableCell className="text-right tabular-nums">{v.totalActual}</TableCell>
                              <TableCell className={`text-right tabular-nums ${v.totalVariance > 0 ? "text-rose-600" : v.totalVariance < 0 ? "text-green-700" : ""}`}>{v.totalVariance}</TableCell>
                              <TableCell className="text-right tabular-nums">{v.usageCount}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      </div>
                      <DataPagination {...pgVariance.paginationProps} className="px-4 pb-4" />
                      </ReportTableCards>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          )}
        </main>
      </div>
    </div>
  )
}

function Stat({ label, value, accent }: { label: string; value: string; accent?: "green" | "rose" }) {
  const color = accent === "green" ? "text-green-700" : accent === "rose" ? "text-rose-600" : "text-slate-900"
  return (
    <div className="rounded border bg-white p-3">
      <div className="text-xs text-slate-500">{label}</div>
      <div className={`font-semibold tabular-nums ${color}`}>{value}</div>
    </div>
  )
}

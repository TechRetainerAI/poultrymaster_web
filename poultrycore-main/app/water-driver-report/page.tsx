"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { BarChart3, Loader2, RefreshCw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getWaterDriverCollection, listWaterDrivers,
  type WaterDriverCollectionReport, type WaterDriver,
} from "@/lib/api/water"
import { useFmt, useCurrency } from "@/lib/currency"
import { PeriodSelect } from "@/components/ui/period-select"
import { periodToRange, type PeriodKey } from "@/lib/date-ranges"

export default function WaterDriverCollectionReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()
  // Column-header / Stat-card unit suffix. Hardcoding " (GHC)" leaked the
  // currency symbol even when the user toggled "Show currency symbol" off in
  // setup (and was always wrong when the currency wasn't GHC). Drive it from
  // the same store fmtMoney reads so labels and values flip together.
  const { symbol, showSymbol } = useCurrency()
  // James (2026-05-30): currency symbols belong on the *values* (driven by
  // fmtMoney + the showCurrencySymbol toggle), never duplicated into the
  // column header. Force empty so headers stay clean regardless of toggle.
  const cur = ""

  const def = periodToRange("last30")!
  const [fromDate, setFromDate] = useState(def.from)
  const [toDate,   setToDate]   = useState(def.to)
  const [period,   setPeriod]   = useState<PeriodKey>("last30")
  const [driverId, setDriverId] = useState<number>(0) // 0 = all drivers

  const [drivers, setDrivers] = useState<WaterDriver[]>([])
  const [report,  setReport]  = useState<WaterDriverCollectionReport | null>(null)
  const [busy,    setBusy]    = useState(true)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load(fromOverride?: string, toOverride?: string) {
    setBusy(true)
    try {
      const [ds, rep] = await Promise.all([
        listWaterDrivers().catch(() => []),
        getWaterDriverCollection(fromOverride ?? fromDate, toOverride ?? toDate, driverId || undefined),
      ])
      setDrivers(ds); setReport(rep)
    } catch (e: any) {
      toast({ title: "Could not load driver report", description: e?.message ?? String(e), variant: "destructive" })
      setReport(null)
    } finally {
      setBusy(false)
    }
  }

  // All delivery detail rows in ONE flat list (sorted by driver, then product)
  // so the report shows a single consolidated "Deliveries" list/table instead
  // of one table per driver.
  const flatDetail = useMemo(() => {
    if (!report) return [] as WaterDriverCollectionReport["detail"]
    return [...report.detail].sort((a, b) =>
      (a.driverName ?? "Unassigned").localeCompare(b.driverName ?? "Unassigned")
      || (a.productName ?? "").localeCompare(b.productName ?? ""),
    )
  }, [report])

  // Paging for the consolidated deliveries list. The per-driver totals table
  // above it is one row per driver, so it stays unpaged.
  const pgDetail = usePagination(flatDetail)

  const headlineTotals = useMemo(() => {
    if (!report?.totals.length) return null
    return report.totals.reduce(
      (acc, t) => ({
        runs:     acc.runs     + t.deliveryRuns,
        cash:     acc.cash     + t.cashCollected,
        momo:     acc.momo     + t.moMoCollected,
        bank:     acc.bank     + t.bankCollected,
        credit:   acc.credit   + t.creditSales,
        shortage: acc.shortage + t.shortage,
      }),
      { runs: 0, cash: 0, momo: 0, bank: 0, credit: 0, shortage: 0 },
    )
  }, [report])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <BarChart3 className="h-6 w-6 text-sky-600" /> Driver collection report
            </h1>
          </div>

          {/* Filters */}
          <Card className="mb-4">
            <CardContent className="p-3 flex flex-wrap items-end gap-3">
              <PeriodSelect
                value={period}
                onChange={(p, range) => {
                  setPeriod(p)
                  if (range) { setFromDate(range.from); setToDate(range.to); void load(range.from, range.to) }
                }}
              />
              <div><Label className="text-xs">From</Label>
                <Input type="date" value={fromDate} onChange={(e) => { setFromDate(e.target.value); setPeriod("custom") }} className="w-40" />
              </div>
              <div><Label className="text-xs">To</Label>
                <Input type="date" value={toDate} onChange={(e) => { setToDate(e.target.value); setPeriod("custom") }} className="w-40" />
              </div>
              <div><Label className="text-xs">Driver</Label>
                <Select value={String(driverId)} onValueChange={(v) => setDriverId(Number(v))}>
                  <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="0">— all drivers —</SelectItem>
                    {drivers.filter(d => d.isActive).map(d => (
                      <SelectItem key={d.waterDriverId} value={String(d.waterDriverId)}>{d.driverName}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <Button onClick={load} disabled={busy} className="gap-1">
                <RefreshCw className={`h-4 w-4 ${busy ? "animate-spin" : ""}`} /> Refresh
              </Button>
            </CardContent>
          </Card>

          {busy ? (
            <Card><CardContent className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading report…</CardContent></Card>
          ) : !report || report.totals.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500">No delivery activity in this period.</CardContent></Card>
          ) : (
            <>
              {headlineTotals && (
                <div className="mb-4 grid grid-cols-2 md:grid-cols-6 gap-3">
                  <Stat label="Delivery runs" value={String(headlineTotals.runs)} />
                  <Stat label={`Cash${cur}`} value={gh(headlineTotals.cash)} />
                  <Stat label={`MoMo${cur}`} value={gh(headlineTotals.momo)} />
                  <Stat label={`Bank${cur}`} value={gh(headlineTotals.bank)} />
                  <Stat label={`Credit${cur}`} value={gh(headlineTotals.credit)} />
                  <Stat label={`Shortage${cur}`} value={gh(headlineTotals.shortage)} tone={headlineTotals.shortage > 0 ? "rose" : undefined} />
                </div>
              )}

              {/* Per-driver totals strip */}
              <Card className="mb-4">
                <CardContent className="p-0">
                  <MobileCardList
                    striped
                    items={report.totals}
                    defaultOpen
                    getKey={(t) => t.waterDriverId ?? `none-${t.driverName}`}
                    primary={(t) => t.driverName ?? "Unassigned"}
                    secondary={(t) => (
                      <>
                        <span>{t.deliveryRuns} runs</span>
                        <span>·</span>
                        <span>Cash {gh(t.cashCollected)}</span>
                      </>
                    )}
                    highlights={(t) => [
                      { label: `Cash${cur}`, value: gh(t.cashCollected), accent: "emerald" },
                      { label: `Shortage${cur}`, value: gh(t.shortage), accent: t.shortage > 0 ? "rose" : "slate" },
                    ]}
                    details={(t) => [
                      { label: "Runs", value: t.deliveryRuns },
                      { label: "Reconciled", value: t.reconciledRuns },
                      { label: `MoMo${cur}`, value: gh(t.moMoCollected) },
                      { label: `Bank${cur}`, value: gh(t.bankCollected) },
                      { label: `Credit${cur}`, value: gh(t.creditSales) },
                      { label: `Overage${cur}`, value: <span className={t.overage > 0 ? "text-emerald-600 font-semibold" : ""}>{gh(t.overage)}</span> },
                    ]}
                    desktopTable={
                      <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Driver</TableHead>
                            <TableHead className="text-right">Runs</TableHead>
                            <TableHead className="text-right">Reconciled</TableHead>
                            <TableHead className="text-right">Cash{cur}</TableHead>
                            <TableHead className="text-right">MoMo{cur}</TableHead>
                            <TableHead className="text-right">Bank{cur}</TableHead>
                            <TableHead className="text-right">Credit{cur}</TableHead>
                            <TableHead className="text-right">Shortage{cur}</TableHead>
                            <TableHead className="text-right">Overage{cur}</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {report.totals.map(t => (
                            <TableRow key={t.waterDriverId ?? `none-${t.driverName}`}>
                              <TableCell className="font-medium">{t.driverName ?? "Unassigned"}</TableCell>
                              <TableCell className="text-right tabular-nums">{t.deliveryRuns}</TableCell>
                              <TableCell className="text-right tabular-nums">{t.reconciledRuns}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(t.cashCollected)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(t.moMoCollected)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(t.bankCollected)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(t.creditSales)}</TableCell>
                              <TableCell className={`text-right tabular-nums ${t.shortage > 0 ? "text-rose-600 font-semibold" : ""}`}>{gh(t.shortage)}</TableCell>
                              <TableCell className={`text-right tabular-nums ${t.overage > 0 ? "text-emerald-600 font-semibold" : ""}`}>{gh(t.overage)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      </div>
                    }
                  />
                </CardContent>
              </Card>

              {/* Per-delivery detail — ALL drivers/products in ONE list so there
                  is a single "View table format" at the bottom (not one table
                  per driver). Cards open by default; each card/table row shows
                  which driver the delivery belongs to. */}
              <Card className="mb-4">
                <CardContent className="p-0">
                  <div className="px-4 pt-4 font-medium text-slate-800">Deliveries</div>
                  <MobileCardList
                    striped
                    items={pgDetail.pageItems}
                    pagination={pgDetail.paginationProps}
                    defaultOpen
                    getKey={(r) => `${r.waterDriverId ?? "none"}-${r.waterProductId}`}
                    primary={(r) => `${r.driverName ?? "Unassigned"} · ${r.productName ?? `Product #${r.waterProductId}`}`}
                    secondary={(r) => (
                      <>
                        <span>{r.bagsSold}/{r.bagsLoaded} sold</span>
                        <span>·</span>
                        <span>{gh(r.salesValue)}</span>
                      </>
                    )}
                    highlights={(r) => [
                      { label: "Loaded (bags)", value: r.bagsLoaded, accent: "blue" },
                      { label: "Sold (bags)", value: r.bagsSold, accent: "emerald" },
                      { label: `Expected${cur}`, value: gh(r.expectedCash), accent: "violet", wide: true },
                    ]}
                    details={(r) => [
                      { label: "Driver", value: r.driverName ?? "Unassigned" },
                      { label: "Product", value: r.productName ?? `Product #${r.waterProductId}` },
                      { label: "Returned (bags)", value: r.bagsReturned },
                      { label: "Damaged (bags)", value: r.bagsDamaged },
                      { label: `Sales${cur}`, value: gh(r.salesValue) },
                    ]}
                    desktopTable={
                      <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Driver</TableHead>
                            <TableHead>Product</TableHead>
                            <TableHead className="text-right">Loaded (bags)</TableHead>
                            <TableHead className="text-right">Sold (bags)</TableHead>
                            <TableHead className="text-right">Returned (bags)</TableHead>
                            <TableHead className="text-right">Damaged (bags)</TableHead>
                            <TableHead className="text-right">Expected{cur}</TableHead>
                            <TableHead className="text-right">Sales{cur}</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pgDetail.pageItems.map((r, i) => (
                            <TableRow key={`${r.waterDriverId ?? "none"}-${r.waterProductId}-${i}`}>
                              <TableCell className="font-medium">{r.driverName ?? "Unassigned"}</TableCell>
                              <TableCell>{r.productName ?? `Product #${r.waterProductId}`}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.bagsLoaded}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.bagsSold}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.bagsReturned}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.bagsDamaged}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.expectedCash)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.salesValue)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      </div>
                    }
                  />
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "rose" }) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="text-xs text-slate-500">{label}</div>
        <div className={`text-lg font-semibold tabular-nums ${tone === "rose" ? "text-rose-600" : ""}`}>{value}</div>
      </CardContent>
    </Card>
  )
}

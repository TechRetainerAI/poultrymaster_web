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
import { BarChart3, Loader2, RefreshCw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getPoultryDriverCollection, listPoultryDrivers,
  type PoultryDriverCollectionReport, type PoultryDriver,
} from "@/lib/api/poultry-distribution"
import { useFmt, useCurrency } from "@/lib/currency"
import { PeriodSelect } from "@/components/ui/period-select"
import { periodToRange, type PeriodKey } from "@/lib/date-ranges"

export default function PoultryDriverCollectionReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()
  // Column-header / Stat-card unit suffix. Driven from the same store fmtMoney
  // reads so labels and values flip together.
  const { symbol, showSymbol } = useCurrency()
  // Currency symbols belong on the *values* (driven by fmtMoney + the
  // showCurrencySymbol toggle), never duplicated into the column header. Force
  // empty so headers stay clean regardless of toggle.
  const cur = ""

  const def = periodToRange("last30")!
  const [fromDate, setFromDate] = useState(def.from)
  const [toDate,   setToDate]   = useState(def.to)
  const [period,   setPeriod]   = useState<PeriodKey>("last30")
  const [driverId, setDriverId] = useState<number>(0) // 0 = all drivers

  const [drivers, setDrivers] = useState<PoultryDriver[]>([])
  const [report,  setReport]  = useState<PoultryDriverCollectionReport | null>(null)
  const [busy,    setBusy]    = useState(true)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load(fromOverride?: string, toOverride?: string) {
    setBusy(true)
    try {
      const [ds, rep] = await Promise.all([
        listPoultryDrivers().catch(() => []),
        getPoultryDriverCollection({ fromDate: fromOverride ?? fromDate, toDate: toOverride ?? toDate, poultryDriverId: driverId || undefined }),
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
    if (!report) return [] as PoultryDriverCollectionReport["detail"]
    return [...report.detail].sort((a, b) =>
      (a.driverName ?? "Unassigned").localeCompare(b.driverName ?? "Unassigned")
      || (a.productName ?? "").localeCompare(b.productName ?? ""),
    )
  }, [report])

  const headlineTotals = useMemo(() => {
    if (!report?.totals.length) return null
    return report.totals.reduce(
      (acc, t) => ({
        runs:      acc.runs      + t.deliveryRuns,
        cratesSold: acc.cratesSold + t.totalCratesSold,
        expected:  acc.expected  + t.totalExpected,
        collected: acc.collected + t.totalCollected,
        shortage:  acc.shortage  + t.totalShortage,
      }),
      { runs: 0, cratesSold: 0, expected: 0, collected: 0, shortage: 0 },
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
                      <SelectItem key={d.poultryDriverId} value={String(d.poultryDriverId)}>{d.driverName}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <Button onClick={() => load()} disabled={busy} className="gap-1">
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
                <div className="mb-4 grid grid-cols-2 md:grid-cols-5 gap-3">
                  <Stat label="Delivery runs" value={String(headlineTotals.runs)} />
                  <Stat label="Crates sold" value={headlineTotals.cratesSold.toLocaleString()} />
                  <Stat label={`Expected${cur}`} value={gh(headlineTotals.expected)} />
                  <Stat label={`Collected${cur}`} value={gh(headlineTotals.collected)} />
                  <Stat label={`Shortage${cur}`} value={gh(headlineTotals.shortage)} tone={headlineTotals.shortage > 0 ? "rose" : undefined} />
                </div>
              )}

              {/* Per-driver totals strip */}
              <Card className="mb-4">
                <CardContent className="p-0">
                  <MobileCardList
                    items={report.totals}
                    defaultOpen
                    getKey={(t) => t.poultryDriverId ?? `none-${t.driverName}`}
                    primary={(t) => t.driverName ?? "Unassigned"}
                    secondary={(t) => (
                      <>
                        <span>{t.deliveryRuns} runs</span>
                        <span>·</span>
                        <span>Collected {gh(t.totalCollected)}</span>
                      </>
                    )}
                    details={(t) => [
                      { label: "Runs", value: t.deliveryRuns },
                      { label: "Crates loaded", value: t.totalCratesLoaded },
                      { label: "Crates sold", value: t.totalCratesSold },
                      { label: "Crates returned", value: t.totalCratesReturned },
                      { label: "Crates lost", value: t.totalCratesLost },
                      { label: `Expected${cur}`, value: gh(t.totalExpected) },
                      { label: `Collected${cur}`, value: gh(t.totalCollected) },
                      { label: `Shortage${cur}`, value: <span className={t.totalShortage > 0 ? "text-rose-600 font-semibold" : ""}>{gh(t.totalShortage)}</span> },
                    ]}
                    desktopTable={
                      <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Driver</TableHead>
                            <TableHead className="text-right">Runs</TableHead>
                            <TableHead className="text-right">Loaded</TableHead>
                            <TableHead className="text-right">Sold</TableHead>
                            <TableHead className="text-right">Returned</TableHead>
                            <TableHead className="text-right">Lost</TableHead>
                            <TableHead className="text-right">Expected{cur}</TableHead>
                            <TableHead className="text-right">Collected{cur}</TableHead>
                            <TableHead className="text-right">Shortage{cur}</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {report.totals.map(t => (
                            <TableRow key={t.poultryDriverId ?? `none-${t.driverName}`}>
                              <TableCell className="font-medium">{t.driverName ?? "Unassigned"}</TableCell>
                              <TableCell className="text-right tabular-nums">{t.deliveryRuns}</TableCell>
                              <TableCell className="text-right tabular-nums">{t.totalCratesLoaded}</TableCell>
                              <TableCell className="text-right tabular-nums">{t.totalCratesSold}</TableCell>
                              <TableCell className="text-right tabular-nums">{t.totalCratesReturned}</TableCell>
                              <TableCell className="text-right tabular-nums">{t.totalCratesLost}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(t.totalExpected)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(t.totalCollected)}</TableCell>
                              <TableCell className={`text-right tabular-nums ${t.totalShortage > 0 ? "text-rose-600 font-semibold" : ""}`}>{gh(t.totalShortage)}</TableCell>
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
                    items={flatDetail}
                    defaultOpen
                    getKey={(r) => `${r.poultryDriverReturnId}-${r.productName ?? "none"}`}
                    primary={(r) => `${r.driverName ?? "Unassigned"} · ${r.productName ?? "Product"}`}
                    secondary={(r) => (
                      <>
                        <span>{r.cratesSold}/{r.cratesLoaded} sold</span>
                        <span>·</span>
                        <span>{gh(r.expectedAmount)}</span>
                      </>
                    )}
                    details={(r) => [
                      { label: "Driver", value: r.driverName ?? "Unassigned" },
                      { label: "Date", value: (r.returnDate ?? "").slice(0, 10) },
                      { label: "Product", value: r.productName ?? "Product" },
                      { label: "Loaded (crates)", value: r.cratesLoaded },
                      { label: "Sold (crates)", value: r.cratesSold },
                      { label: "Returned (crates)", value: r.cratesReturned },
                      { label: "Damaged (crates)", value: r.cratesDamaged },
                      { label: `Expected${cur}`, value: gh(r.expectedAmount) },
                    ]}
                    desktopTable={
                      <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Driver</TableHead>
                            <TableHead>Date</TableHead>
                            <TableHead>Product</TableHead>
                            <TableHead className="text-right">Loaded (crates)</TableHead>
                            <TableHead className="text-right">Sold (crates)</TableHead>
                            <TableHead className="text-right">Returned (crates)</TableHead>
                            <TableHead className="text-right">Damaged (crates)</TableHead>
                            <TableHead className="text-right">Expected{cur}</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {flatDetail.map((r, i) => (
                            <TableRow key={`${r.poultryDriverReturnId}-${r.productName ?? "none"}-${i}`}>
                              <TableCell className="font-medium">{r.driverName ?? "Unassigned"}</TableCell>
                              <TableCell className="whitespace-nowrap">{(r.returnDate ?? "").slice(0, 10)}</TableCell>
                              <TableCell>{r.productName ?? "Product"}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.cratesLoaded}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.cratesSold}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.cratesReturned}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.cratesDamaged}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.expectedAmount)}</TableCell>
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

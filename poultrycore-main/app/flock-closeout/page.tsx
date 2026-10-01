"use client"

// Flock Closeout (Tools menu) -- the home of the end-of-flock workflow
// (migrations 332/333). Three views over ONE read, fnflock_lifetimesummary:
//
//   Ready to close  flocks whose birds have arrived and that are still open,
//                   with what is standing -- Close opens the wizard
//   Closed          finished flocks and how they did -- Lifetime opens the
//                   summary, closeout history and Reopen
//   Compare         the same rows grouped by batch, breed, supplier, house or
//                   flock (groupLifetimeSummaries), so every comparison is a
//                   grouping, never a second definition of profit
//
// The Flocks page still shows a closed flock's badge; the actions live here.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { BarChart3, Flag, Loader2, RefreshCw, Lock } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import { usePermissions } from "@/hooks/use-permissions"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useAuthStore } from "@/lib/store/auth-store"
import { getUserContext } from "@/lib/utils/user-context"
import { clearFlocksCache } from "@/lib/utils/flock-utils"
import { formatCurrency } from "@/lib/utils/currency"
import { getFlockLifetimeSummaries, type FlockLifetimeSummary } from "@/lib/api/flock-closeout"
import { groupLifetimeSummaries, type LifetimeGroupBy } from "@/lib/flocks/closeout"
import { FlockCloseoutWizard } from "@/components/poultry/flock-closeout-wizard"
import { FlockLifetimeDialog } from "@/components/poultry/flock-lifetime-dialog"

const n = (v: number | null | undefined) => (v == null ? "—" : Number(v).toLocaleString())
const pct = (v: number | null | undefined) => (v == null ? "—" : `${(Number(v) * 100).toFixed(2)}%`)
const money = (v: number | null | undefined) => (v == null ? "—" : formatCurrency(Number(v)))
const day = (v: string | null | undefined) => (v ? v.slice(0, 10) : "—")

const GROUP_OPTIONS: { value: LifetimeGroupBy; label: string }[] = [
  { value: "batch", label: "Batch" },
  { value: "breed", label: "Breed" },
  { value: "supplier", label: "Supplier" },
  { value: "house", label: "House" },
  { value: "flock", label: "Flock" },
]

type Tab = "open" | "closed" | "compare"

export default function FlockCloseoutPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const canView = permissions.can("poultry.flock-closeout.view")
  const canClose = permissions.can("poultry.flock-closeout.create")
  const canReopen = permissions.can("poultry.flock-closeout.approve")

  const [rows, setRows] = useState<FlockLifetimeSummary[]>([])
  const [loading, setLoading] = useState(true)
  const [tab, setTab] = useState<Tab>("open")
  const [search, setSearch] = useState("")
  const [groupBy, setGroupBy] = useState<LifetimeGroupBy>("batch")
  const [compareScope, setCompareScope] = useState<"closed" | "all">("closed")
  const [closeoutFlockId, setCloseoutFlockId] = useState<number | null>(null)
  const [lifetimeFlockId, setLifetimeFlockId] = useState<number | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    const { farmId } = getUserContext()
    if (!farmId) { setLoading(false); return }
    setLoading(true)
    const res = await getFlockLifetimeSummaries(farmId)
    if (res.success && res.data) setRows(res.data)
    else toast({ title: "Could not load flocks", description: res.message, variant: "destructive" })
    setLoading(false)
  }

  const matches = (r: FlockLifetimeSummary) => {
    const q = search.trim().toLowerCase()
    if (!q) return true
    return [r.flockName, r.breed, r.batchCode, r.batchName, r.houseName].some((v) => (v ?? "").toLowerCase().includes(q))
  }

  // Pending flocks have no birds to close out; they are simply not listed.
  const openRows = useMemo(() => rows.filter((r) => r.status === "Active" || r.status === "Inactive").filter(matches),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rows, search])
  const closedRows = useMemo(
    () => rows.filter((r) => r.status === "Closed").filter(matches)
      .sort((a, b) => (b.closedDate ?? "").localeCompare(a.closedDate ?? "")),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rows, search])
  const groups = useMemo(
    () => groupLifetimeSummaries(rows.filter((r) => compareScope === "all" || r.status === "Closed"), groupBy)
      .sort((a, b) => b.profit - a.profit),
    [rows, groupBy, compareScope])

  const openPg = usePagination(openRows)
  const closedPg = usePagination(closedRows)

  const standing = rows.filter((r) => r.status === "Active" || r.status === "Inactive").reduce((a, r) => a + r.finalBirds, 0)
  const closedCount = rows.filter((r) => r.status === "Closed").length

  // Other pages read flocks through a 5-minute cache; a close or reopen must
  // not leave them offering a flock that just changed state.
  const refresh = () => { clearFlocksCache(); void load() }

  if (!permissions.isLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-4 md:p-6">
            <Card><CardContent className="p-8 text-center text-slate-600">
              <Lock className="mx-auto mb-2 h-6 w-6 text-slate-400" />
              You do not have access to Flock Closeout.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Flag className="h-6 w-6 text-orange-600" /> Flock Closeout
              </h1>
              <p className="text-sm text-slate-600 max-w-2xl">
                End a flock's life: account for every bird still standing, sell, cull or transfer the last of them,
                and free its house. Closed flocks keep their full history and their lifetime performance.
              </p>
            </div>
            <Button variant="outline" onClick={refresh} disabled={loading} className="h-10">
              <RefreshCw className={loading ? "h-4 w-4 mr-1 animate-spin" : "h-4 w-4 mr-1"} /> Refresh
            </Button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Open flocks</div>
              <div className="text-2xl font-semibold tabular-nums">{n(rows.filter((r) => r.status === "Active" || r.status === "Inactive").length)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Birds standing in them</div>
              <div className="text-2xl font-semibold tabular-nums text-blue-700">{n(standing)}</div>
            </CardContent></Card>
            <Card className="col-span-2 sm:col-span-1"><CardContent className="p-4">
              <div className="text-xs text-slate-500">Closed flocks</div>
              <div className="text-2xl font-semibold tabular-nums">{n(closedCount)}</div>
            </CardContent></Card>
          </div>

          <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)}>
            <TabsList>
              <TabsTrigger value="open">Ready to close</TabsTrigger>
              <TabsTrigger value="closed">Closed</TabsTrigger>
              <TabsTrigger value="compare">Compare</TabsTrigger>
            </TabsList>

            {tab !== "compare" && (
              <div className="mt-3">
                <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search flock, breed, batch or house" />
              </div>
            )}

            {/* ------------------------------------------------ open flocks */}
            <TabsContent value="open">
              <Card>
                <CardContent className="p-0">
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : openRows.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No open flocks with birds on the farm.</div>
                  ) : (
                    <MobileCardList
                      items={openPg.pageItems}
                      pagination={openPg.paginationProps}
                      getKey={(r) => r.flockId}
                      primary={(r) => r.flockName}
                      secondary={(r) => <span>{[r.batchCode, r.houseName].filter(Boolean).join(" · ") || "—"}</span>}
                      trailing={(r) => r.status === "Inactive" ? <Badge variant="secondary">Inactive</Badge> : null}
                      highlights={(r) => [
                        { label: "Birds standing", value: n(r.finalBirds), accent: "blue" },
                        { label: "Days", value: n(r.daysInProduction), accent: "slate" },
                      ]}
                      details={(r) => [
                        { label: "Breed", value: r.breed || "—" },
                        { label: "Started", value: day(r.startDate) },
                        { label: "Placed", value: n(r.originallyPlaced) },
                        { label: "Mortality", value: `${n(r.recordedMortality)} (${pct(r.trackedMortalityRate)})` },
                      ]}
                      actions={(r) => (
                        <>
                          <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                            <Link href={`/flock-closeout/${r.flockId}`}><BarChart3 className="h-4 w-4 mr-1" /> Lifetime</Link>
                          </Button>
                          {canClose && (
                            <Button size="sm" className="flex-1 h-10" onClick={() => setCloseoutFlockId(r.flockId)}>
                              <Flag className="h-4 w-4 mr-1" /> Close flock
                            </Button>
                          )}
                        </>
                      )}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Flock</TableHead><TableHead>Batch</TableHead><TableHead>House</TableHead>
                                <TableHead>Started</TableHead><TableHead className="text-right">Placed</TableHead>
                                <TableHead className="text-right">Mortality</TableHead><TableHead className="text-right">Birds standing</TableHead>
                                <TableHead className="text-right">Actions</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {openPg.pageItems.map((r) => (
                                <TableRow key={r.flockId}>
                                  <TableCell className="font-medium">
                                    <Link href={`/flock-closeout/${r.flockId}`} className="text-blue-700 hover:underline">{r.flockName}</Link>
                                    {r.status === "Inactive" && <Badge variant="secondary" className="ml-2">Inactive</Badge>}
                                  </TableCell>
                                  <TableCell>{r.batchCode || "—"}</TableCell>
                                  <TableCell>{r.houseName || "—"}</TableCell>
                                  <TableCell>{day(r.startDate)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{n(r.originallyPlaced)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{n(r.recordedMortality)} <span className="text-xs text-slate-500">({pct(r.trackedMortalityRate)})</span></TableCell>
                                  <TableCell className="text-right tabular-nums font-semibold text-blue-700">{n(r.finalBirds)}</TableCell>
                                  <TableCell className="text-right whitespace-nowrap">
                                    <Button size="sm" variant="ghost" title="Lifetime performance" onClick={() => setLifetimeFlockId(r.flockId)}>
                                      <BarChart3 className="h-4 w-4" />
                                    </Button>
                                    {canClose && (
                                      <Button size="sm" variant="outline" onClick={() => setCloseoutFlockId(r.flockId)}>
                                        <Flag className="h-4 w-4 mr-1" /> Close
                                      </Button>
                                    )}
                                  </TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        </div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </TabsContent>

            {/* ---------------------------------------------- closed flocks */}
            <TabsContent value="closed">
              <Card>
                <CardContent className="p-0">
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : closedRows.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No flock has been closed yet.</div>
                  ) : (
                    <MobileCardList
                      items={closedPg.pageItems}
                      pagination={closedPg.paginationProps}
                      getKey={(r) => r.flockId}
                      primary={(r) => r.flockName}
                      secondary={(r) => <span>Closed {day(r.closedDate)}{r.houseName ? ` · ${r.houseName}` : ""}</span>}
                      highlights={(r) => [
                        { label: "Profit", value: money(r.profit), accent: r.profit >= 0 ? "emerald" : "rose" },
                        { label: "Per bird", value: money(r.profitPerOriginalBird), accent: "slate" },
                      ]}
                      details={(r) => [
                        { label: "Batch", value: r.batchCode || "—" },
                        { label: "Placed", value: n(r.originallyPlaced) },
                        { label: "Mortality", value: pct(r.trackedMortalityRate) },
                        { label: "Eggs", value: n(r.totalEggs) },
                        { label: "Revenue", value: money(r.totalRevenue) },
                        { label: "Cost", value: money(r.totalCost) },
                      ]}
                      actions={(r) => (
                        <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                          <Link href={`/flock-closeout/${r.flockId}`}><BarChart3 className="h-4 w-4 mr-1" /> Lifetime{canReopen ? " & reopen" : ""}</Link>
                        </Button>
                      )}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Flock</TableHead><TableHead>Closed</TableHead><TableHead>Batch</TableHead>
                                <TableHead className="text-right">Placed</TableHead><TableHead className="text-right">Mortality</TableHead>
                                <TableHead className="text-right">Eggs</TableHead><TableHead className="text-right">Revenue</TableHead>
                                <TableHead className="text-right">Cost</TableHead><TableHead className="text-right">Profit</TableHead>
                                <TableHead className="text-right">Per bird</TableHead><TableHead className="text-right">Actions</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {closedPg.pageItems.map((r) => (
                                <TableRow key={r.flockId}>
                                  <TableCell className="font-medium">
                                    <Link href={`/flock-closeout/${r.flockId}`} className="text-blue-700 hover:underline">{r.flockName}</Link>
                                  </TableCell>
                                  <TableCell>{day(r.closedDate)}</TableCell>
                                  <TableCell>{r.batchCode || "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums">{n(r.originallyPlaced)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{pct(r.trackedMortalityRate)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{n(r.totalEggs)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{money(r.totalRevenue)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{money(r.totalCost)}</TableCell>
                                  <TableCell className={r.profit >= 0 ? "text-right tabular-nums text-emerald-700 font-semibold" : "text-right tabular-nums text-rose-700 font-semibold"}>{money(r.profit)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{money(r.profitPerOriginalBird)}</TableCell>
                                  <TableCell className="text-right">
                                    <Button size="sm" variant="outline" onClick={() => setLifetimeFlockId(r.flockId)}>
                                      <BarChart3 className="h-4 w-4 mr-1" /> {canReopen ? "Lifetime & reopen" : "Lifetime"}
                                    </Button>
                                  </TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        </div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </TabsContent>

            {/* ---------------------------------------------------- compare */}
            <TabsContent value="compare" className="space-y-3">
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-sm text-slate-600">Compare by</span>
                <Select value={groupBy} onValueChange={(v) => setGroupBy(v as LifetimeGroupBy)}>
                  <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                  <SelectContent>{GROUP_OPTIONS.map((g) => <SelectItem key={g.value} value={g.value}>{g.label}</SelectItem>)}</SelectContent>
                </Select>
                <Select value={compareScope} onValueChange={(v) => setCompareScope(v as "closed" | "all")}>
                  <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="closed">Closed flocks only</SelectItem>
                    <SelectItem value="all">Include open flocks</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <p className="text-xs text-slate-500">
                Ratios are worked out from each group's totals, not averaged across flocks, so a large flock counts
                for more than a small one. Closed flocks give the fairest comparison: an open flock's story is not finished.
              </p>
              <Card>
                <CardContent className="p-0">
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : groups.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">
                      {compareScope === "closed" ? "Close a flock to start comparing." : "No flocks yet."}
                    </div>
                  ) : (
                    <MobileCardList
                      items={groups}
                      getKey={(g) => g.key}
                      primary={(g) => g.label}
                      secondary={(g) => <span>{n(g.flocks)} flock{g.flocks === 1 ? "" : "s"} · {n(g.originallyPlaced)} birds placed</span>}
                      highlights={(g) => [
                        { label: "Profit per bird", value: money(g.profitPerOriginalBird), accent: (g.profitPerOriginalBird ?? 0) >= 0 ? "emerald" : "rose" },
                        { label: "Mortality", value: pct(g.trackedMortalityRate), accent: "slate" },
                      ]}
                      details={(g) => [
                        { label: "Revenue", value: money(g.totalRevenue) },
                        { label: "Cost", value: money(g.totalCost) },
                        { label: "Profit", value: money(g.profit) },
                        { label: "Eggs", value: n(g.totalEggs) },
                        { label: "Feed / dozen", value: g.feedKgPerDozenEggs == null ? "—" : `${g.feedKgPerDozenEggs.toFixed(3)} kg` },
                        { label: "Revenue per bird", value: money(g.revenuePerOriginalBird) },
                      ]}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>{GROUP_OPTIONS.find((o) => o.value === groupBy)?.label}</TableHead>
                                <TableHead className="text-right">Flocks</TableHead><TableHead className="text-right">Placed</TableHead>
                                <TableHead className="text-right">Mortality</TableHead><TableHead className="text-right">Eggs</TableHead>
                                <TableHead className="text-right">Feed / dozen</TableHead><TableHead className="text-right">Revenue</TableHead>
                                <TableHead className="text-right">Cost</TableHead><TableHead className="text-right">Profit</TableHead>
                                <TableHead className="text-right">Profit / bird</TableHead><TableHead className="text-right">Revenue / bird</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {groups.map((g) => (
                                <TableRow key={g.key}>
                                  <TableCell className="font-medium">{g.label}</TableCell>
                                  <TableCell className="text-right tabular-nums">{n(g.flocks)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{n(g.originallyPlaced)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{pct(g.trackedMortalityRate)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{n(g.totalEggs)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{g.feedKgPerDozenEggs == null ? "—" : `${g.feedKgPerDozenEggs.toFixed(3)} kg`}</TableCell>
                                  <TableCell className="text-right tabular-nums">{money(g.totalRevenue)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{money(g.totalCost)}</TableCell>
                                  <TableCell className={g.profit >= 0 ? "text-right tabular-nums text-emerald-700 font-semibold" : "text-right tabular-nums text-rose-700 font-semibold"}>{money(g.profit)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{money(g.profitPerOriginalBird)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{money(g.revenuePerOriginalBird)}</TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        </div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </main>
      </div>

      <FlockCloseoutWizard
        flockId={closeoutFlockId}
        open={closeoutFlockId != null}
        onOpenChange={(o) => { if (!o) setCloseoutFlockId(null) }}
        onClosed={refresh}
      />
      <FlockLifetimeDialog
        flockId={lifetimeFlockId}
        open={lifetimeFlockId != null}
        onOpenChange={(o) => { if (!o) setLifetimeFlockId(null) }}
        canReopen={canReopen}
        onReopened={refresh}
      />
    </div>
  )
}

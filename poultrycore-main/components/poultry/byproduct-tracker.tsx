"use client"

/**
 * Broken Eggs / Dead Birds trackers -- one component, two pages
 * (/broken-eggs-tracker, /dead-birds-tracker), like the feed trackers.
 *
 * Byproduct stock (372-381) is its own ledger, apart from saleable eggs and
 * live birds: what production and egg sorting generated, what was sold,
 * disposed, used or adjusted by hand, and what is left -- per flock, with
 * pooled entries (no flock) on their own row. Records entered before tracking
 * started show as generated and disposed (381).
 *
 * Everything comes from GET /Poultry/stock/byproduct-tracker, built on the same
 * functions as the Byproduct Inventory & Disposition report, so the tracker and
 * the report always agree. The flock and movement filters work on the loaded
 * period; changing the period reloads.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Bird, ChevronDown, ChevronUp, Egg, RefreshCw } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DataPagination, TRACKER_PAGE_SIZE_DEFAULT } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useIsMobile } from "@/hooks/use-mobile"
import { useLogout } from "@/hooks/use-logout"
import { useFmt } from "@/lib/currency"
import { cn, formatDateShort } from "@/lib/utils"
import { PERIOD_GROUPS, periodToRange, type PeriodKey } from "@/lib/date-ranges"
import {
  getByproductTracker,
  type ByproductRole, type ByproductTracker, type ByproductTrackerFlockRow, type ByproductTrackerMovement,
} from "@/lib/api/poultry-inventory"

type Copy = {
  title: string
  unit: string
  intro: React.ReactNode
  generated: string
  icon: typeof Egg
  accent: string
  links: { href: string; label: string }[]
}

const COPY: Record<ByproductRole, Copy> = {
  BrokenEggs: {
    title: "Broken eggs tracker",
    unit: "eggs",
    intro: <>Broken eggs from <strong>production records</strong> and <strong>egg sorting</strong>, and what happened to them:
      sold, disposed, used or adjusted by hand. They are never counted as saleable eggs.</>,
    generated: "Broken eggs recorded",
    icon: Egg,
    accent: "bg-amber-100 text-amber-700",
    links: [
      { href: "/production-records", label: "Production records" },
      { href: "/poultry-egg-sorting", label: "Egg sorting" },
      { href: "/poultry-stock", label: "Stock movements" },
      { href: "/poultry/reports/byproduct-inventory", label: "Byproduct report" },
    ],
  },
  DeadBirds: {
    title: "Dead birds tracker",
    unit: "birds",
    intro: <>Deaths recorded on <strong>production records</strong> and what happened to the carcasses: sold, disposed
      or still held. They are never counted as live birds; the Birds tracker shows those.</>,
    generated: "Deaths recorded",
    icon: Bird,
    accent: "bg-rose-100 text-rose-700",
    links: [
      { href: "/production-records", label: "Production records" },
      { href: "/birds-left-tracker", label: "Birds tracker" },
      { href: "/poultry-stock", label: "Stock movements" },
      { href: "/poultry/reports/byproduct-inventory", label: "Byproduct report" },
    ],
  },
}

const CATEGORY_LABEL: Record<string, string> = {
  Generated: "Recorded",
  Sold: "Sold",
  Disposed: "Disposed",
  InternalUse: "Internal use",
  ManualIn: "Added by hand",
  ManualOut: "Removed by hand",
  Reversal: "Reversal",
}
const CATEGORY_TONE: Record<string, string> = {
  Generated: "border-emerald-300 bg-emerald-50 text-emerald-800",
  Sold: "border-blue-300 bg-blue-50 text-blue-800",
  Disposed: "border-rose-300 bg-rose-50 text-rose-800",
  InternalUse: "border-violet-300 bg-violet-50 text-violet-800",
  ManualIn: "border-teal-300 bg-teal-50 text-teal-800",
  ManualOut: "border-orange-300 bg-orange-50 text-orange-800",
  Reversal: "border-slate-300 bg-slate-50 text-slate-700",
}
/** Where a movement came from, in words. */
const SOURCE_LABEL: Record<string, string> = {
  "Broken Egg Prod": "Production record",
  "Broken Egg Disposal": "Disposed at once (production record)",
  "Sorting Breakage": "Egg sorting",
  "Breakage In": "Unrecorded breakage",
  "Mortality In": "Production record",
  "Mortality Disposal": "Disposed at once (production record)",
  "Hist Mortality In": "Historical mortality",
  "Hist Mortality Disp": "Historical mortality, disposed",
  "Disposal": "Disposal",
  "Sale": "Sale",
  "Sale Reversal": "Sale reversed",
  "InternalUse": "Internal use",
}

const POOLED = "__pooled__"
const flockKey = (id: number | null) => (id == null ? POOLED : String(id))
const flockLabel = (r: { flockName: string | null; flockId: number | null }) =>
  r.flockId == null ? "Pooled (no flock)" : (r.flockName ?? `Flock ${r.flockId}`)
const n = (v: number) => (Number(v) || 0).toLocaleString(undefined, { maximumFractionDigits: 3 })

/**
 * A movement against its category's usual direction is a correction: a record
 * edited down or deleted (Recorded, negative), or a disposal taken back
 * (Disposed, positive). The report nets them into their category; here they
 * are named for what they are.
 */
function CategoryBadge({ m }: { m: ByproductTrackerMovement }) {
  const correction = (m.category === "Generated" && m.quantity < 0) || (m.category === "Disposed" && m.quantity > 0)
  const key = correction ? "Correction" : m.category
  return (
    <Badge variant="outline" className={correction ? "border-slate-300 bg-slate-50 text-slate-700" : (CATEGORY_TONE[key] ?? "")}>
      {correction ? "Correction" : (CATEGORY_LABEL[key] ?? key)}
    </Badge>
  )
}

type LedgerRow = ByproductTrackerMovement & { balance: number }

export function ByproductTracker({ role }: { role: ByproductRole }) {
  const copy = COPY[role]
  const Icon = copy.icon
  const handleLogout = useLogout()
  const isMobile = useIsMobile()
  const fmt = useFmt()

  const [period, setPeriod] = useState<PeriodKey>("last30")
  const initial = periodToRange("last30")!
  const [from, setFrom] = useState(initial.from)
  const [to, setTo] = useState(initial.to)
  const [data, setData] = useState<ByproductTracker | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState("")
  const [flockFilter, setFlockFilter] = useState("ALL")
  const [categoryFilter, setCategoryFilter] = useState("ALL")
  const [showFlockTableMobile, setShowFlockTableMobile] = useState(false)
  const [showLedgerTableMobile, setShowLedgerTableMobile] = useState(false)

  const load = useCallback(async (soft = false) => {
    if (!from || !to) return
    soft ? setRefreshing(true) : setLoading(true)
    setError("")
    try {
      setData(await getByproductTracker(role, { fromDate: from, toDate: to }))
    } catch (e: any) {
      setError(e?.message ?? "Could not load the tracker.")
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [role, from, to])

  useEffect(() => { void load() }, [load])

  const pickPeriod = (p: PeriodKey) => {
    setPeriod(p)
    const r = p === "allTime" ? { from: "2000-01-01", to: periodToRange("today")!.to } : periodToRange(p)
    if (r) { setFrom(r.from); setTo(r.to) }
  }

  // ---- filtered views --------------------------------------------------------
  const flockOptions = useMemo(() => {
    const seen = new Map<string, string>()
    for (const r of data?.flocks ?? []) seen.set(flockKey(r.flockId), flockLabel(r))
    for (const m of data?.movements ?? []) if (!seen.has(flockKey(m.flockId))) seen.set(flockKey(m.flockId), flockLabel(m))
    return [...seen.entries()].sort((a, b) => (a[0] === POOLED ? 1 : b[0] === POOLED ? -1 : a[1].localeCompare(b[1])))
  }, [data])

  // First and last movement per flock in the period (a flock with only an
  // opening balance has none).
  const flockDates = useMemo(() => {
    const m = new Map<string, { first: string; last: string }>()
    for (const mv of data?.movements ?? []) {
      const k = flockKey(mv.flockId)
      const d = m.get(k)
      if (!d) m.set(k, { first: mv.date, last: mv.date })
      else {
        if (mv.date < d.first) d.first = mv.date
        if (mv.date > d.last) d.last = mv.date
      }
    }
    return m
  }, [data])
  const datesOf = (r: ByproductTrackerFlockRow) => flockDates.get(flockKey(r.flockId))

  const flocks = useMemo<ByproductTrackerFlockRow[]>(() =>
    (data?.flocks ?? []).filter((r) => flockFilter === "ALL" || flockKey(r.flockId) === flockFilter),
  [data, flockFilter])

  const totals = useMemo(() => flocks.reduce((t, r) => ({
    opening: t.opening + r.opening, generated: t.generated + r.generated, sold: t.sold + r.sold,
    disposed: t.disposed + r.disposed, internalUse: t.internalUse + r.internalUse, manualIn: t.manualIn + r.manualIn,
    manualOut: t.manualOut + r.manualOut, reversals: t.reversals + r.reversals, closing: t.closing + r.closing,
    revenue: t.revenue + r.revenue,
  }), { opening: 0, generated: 0, sold: 0, disposed: 0, internalUse: 0, manualIn: 0, manualOut: 0, reversals: 0, closing: 0, revenue: 0 }), [flocks])

  // Running balance from the period's opening (for the chosen flock), oldest
  // first; shown newest first.
  const ledger = useMemo<LedgerRow[]>(() => {
    const moves = (data?.movements ?? [])
      .filter((m) => flockFilter === "ALL" || flockKey(m.flockId) === flockFilter)
      .slice()
      .sort((a, b) => (a.date === b.date ? a.txnId - b.txnId : a.date.localeCompare(b.date)))
    let bal = totals.opening
    const rows = moves.map((m) => { bal += Number(m.quantity) || 0; return { ...m, balance: bal } })
    return rows
      .filter((m) => categoryFilter === "ALL" || m.category === categoryFilter)
      .reverse()
  }, [data, flockFilter, categoryFilter, totals.opening])

  const ledgerIn = ledger.reduce((t, m) => t + Math.max(0, m.quantity), 0)
  const ledgerOut = ledger.reduce((t, m) => t + Math.max(0, -m.quantity), 0)
  const pg = usePagination(ledger, TRACKER_PAGE_SIZE_DEFAULT)

  const otherOut = totals.internalUse + totals.manualOut
  const cards = [
    { label: "On hand now", value: n(data?.onHand ?? 0), tone: "text-sky-700", note: "All flocks, today" },
    { label: copy.generated, value: n(totals.generated), tone: "text-emerald-700", note: "In the period" },
    { label: "Sold", value: n(totals.sold), tone: "text-blue-700", note: totals.revenue ? `${fmt(totals.revenue)} revenue` : "In the period" },
    { label: "Disposed", value: n(totals.disposed), tone: "text-rose-700", note: "In the period" },
    { label: "Left at end of period", value: n(totals.closing), tone: "text-slate-900",
      note: `Opening ${n(totals.opening)}${totals.manualIn ? ` · added ${n(totals.manualIn)}` : ""}${otherOut ? ` · other out ${n(otherOut)}` : ""}${totals.reversals ? ` · reversals ${n(totals.reversals)}` : ""}` },
  ]

  const reference = (m: ByproductTrackerMovement) =>
    m.movementNo ? m.movementNo
      : m.saleId ? <Link href={`/sales?saleId=${m.saleId}`} className="text-blue-600 hover:underline">Sale #{m.saleId}</Link>
      : "—"

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* ---- header ---- */}
            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className={cn("w-10 h-10 shrink-0 rounded-lg flex items-center justify-center", copy.accent)}>
                  <Icon className="w-5 h-5" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">{copy.title}</h1>
                  <p className="text-sm text-slate-600 mt-1">{copy.intro}</p>
                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm">
                    {copy.links.map((l) => (
                      <Link key={l.href} href={l.href} className="text-blue-600 hover:underline font-medium">{l.label}</Link>
                    ))}
                  </div>
                </div>
              </div>
              <Button type="button" variant="outline" className="shrink-0 gap-2" onClick={() => void load(true)} disabled={refreshing || loading}>
                <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} /> Refresh
              </Button>
            </div>

            {/* ---- filters ---- */}
            <Card className="bg-white">
              <CardContent className="grid gap-3 pt-4 sm:grid-cols-2 lg:grid-cols-5">
                <div className="space-y-1">
                  <Label className="text-xs text-slate-500">Period</Label>
                  <Select value={period} onValueChange={(v) => pickPeriod(v as PeriodKey)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {PERIOD_GROUPS.map((g) => (
                        <SelectGroup key={g.label}>
                          <SelectLabel>{g.label}</SelectLabel>
                          {g.options.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                        </SelectGroup>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-slate-500">From</Label>
                  <Input type="date" value={from} max={to} onChange={(e) => { setPeriod("custom"); setFrom(e.target.value) }} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-slate-500">To</Label>
                  <Input type="date" value={to} min={from} onChange={(e) => { setPeriod("custom"); setTo(e.target.value) }} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-slate-500">Flock</Label>
                  <Select value={flockFilter} onValueChange={setFlockFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All flocks</SelectItem>
                      {flockOptions.map(([k, label]) => <SelectItem key={k} value={k}>{label}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-slate-500">Movement</Label>
                  <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All movements</SelectItem>
                      {Object.entries(CATEGORY_LABEL).map(([k, label]) => <SelectItem key={k} value={k}>{label}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </CardContent>
            </Card>

            {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

            {loading ? (
              <Card className="bg-white"><CardContent className="py-12 text-center text-slate-600">Loading {copy.title.toLowerCase()}…</CardContent></Card>
            ) : (
              <>
                {/* ---- cards ---- */}
                <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
                  {cards.map((c, i) => (
                    <div key={c.label} className={cn("p-4 bg-white rounded-xl border border-slate-200 shadow-sm", i === cards.length - 1 && "col-span-2 lg:col-span-1")}>
                      <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">{c.label}</div>
                      <div className={cn("text-2xl font-bold tabular-nums mt-1", c.tone)}>{c.value}</div>
                      <div className="mt-1 text-xs text-slate-500">{c.note}</div>
                    </div>
                  ))}
                </div>

                {/* ---- by flock ---- */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">By flock</CardTitle>
                    <CardDescription>
                      <span className="font-medium text-slate-700">{formatDateShort(from)} – {formatDateShort(to)}.</span>{" "}
                      First / Last are the flock's first and last movement in the period.
                      Opening + recorded + added − sold − disposed − used − removed ± reversals = left, for the period.
                      Entries with no flock (e.g. egg sorting, pooled stock) sit on their own row.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto pb-2">
                    {isMobile && !showFlockTableMobile ? (
                      <div className="space-y-3">
                        {flocks.length === 0 ? (
                          <p className="py-8 text-center text-sm text-slate-500">Nothing in this period.</p>
                        ) : flocks.map((r, idx) => (
                          <div key={flockKey(r.flockId)} className={cn("rounded-xl border px-3 py-3 shadow-sm", idx % 2 === 0 ? "border-blue-300 bg-blue-50" : "border-slate-200 bg-white")}>
                            <div className="font-semibold text-slate-900">{flockLabel(r)}{r.batchCode ? <span className="ml-1 text-xs font-normal text-slate-500">{r.batchCode}</span> : null}</div>
                            <div className="text-xs text-slate-500">
                              {datesOf(r) ? `${formatDateShort(datesOf(r)!.first)} – ${formatDateShort(datesOf(r)!.last)}` : "No movements in the period"}
                            </div>
                            <div className="mt-2 grid grid-cols-2 gap-2">
                              <div className="rounded-lg border border-emerald-300 bg-emerald-100 px-3 py-2">
                                <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">Recorded</p>
                                <p className="text-xl font-extrabold text-emerald-800 tabular-nums">{n(r.generated)}</p>
                              </div>
                              <div className="rounded-lg border border-sky-300 bg-sky-100 px-3 py-2">
                                <p className="text-[11px] font-semibold uppercase tracking-wide text-sky-900">Left</p>
                                <p className="text-xl font-extrabold text-sky-800 tabular-nums">{n(r.closing)}</p>
                              </div>
                            </div>
                            <div className="mt-2 grid grid-cols-2 gap-1 text-sm">
                              <span className="text-slate-500">Opening <b className="tabular-nums text-slate-800">{n(r.opening)}</b></span>
                              <span className="text-slate-500">Sold <b className="tabular-nums text-blue-700">{n(r.sold)}</b></span>
                              <span className="text-slate-500">Disposed <b className="tabular-nums text-rose-700">{n(r.disposed)}</b></span>
                              <span className="text-slate-500">Other ± <b className="tabular-nums text-slate-800">{n(r.manualIn - r.manualOut - r.internalUse + r.reversals)}</b></span>
                            </div>
                          </div>
                        ))}
                        <Button type="button" variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowFlockTableMobile(true)}>
                          View table format <ChevronDown className="ml-1 h-4 w-4" />
                        </Button>
                      </div>
                    ) : (
                      <>
                        {isMobile && (
                          <div className="mb-2 flex justify-end">
                            <Button type="button" variant="ghost" size="sm" onClick={() => setShowFlockTableMobile(false)}>
                              <ChevronUp className="mr-1 h-4 w-4" /> Cards
                            </Button>
                          </div>
                        )}
                        <Table className="w-full min-w-[1050px]">
                          <TableHeader>
                            <TableRow>
                              <TableHead>Flock</TableHead>
                              <TableHead>Batch</TableHead>
                              <TableHead>First</TableHead>
                              <TableHead>Last</TableHead>
                              <TableHead className="text-right">Opening</TableHead>
                              <TableHead className="text-right">Recorded</TableHead>
                              <TableHead className="text-right">Added</TableHead>
                              <TableHead className="text-right">Sold</TableHead>
                              <TableHead className="text-right">Disposed</TableHead>
                              <TableHead className="text-right">Used</TableHead>
                              <TableHead className="text-right">Removed</TableHead>
                              <TableHead className="text-right">Reversals</TableHead>
                              <TableHead className="text-right">Left</TableHead>
                              <TableHead className="text-right">Revenue</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {flocks.length === 0 ? (
                              <TableRow><TableCell colSpan={14} className="py-8 text-center text-slate-500">Nothing in this period.</TableCell></TableRow>
                            ) : flocks.map((r) => (
                              <TableRow key={flockKey(r.flockId)}>
                                <TableCell className={cn("font-medium", r.flockId == null && "italic text-slate-600")}>{flockLabel(r)}</TableCell>
                                <TableCell className="text-slate-600">{r.batchCode ?? "—"}</TableCell>
                                <TableCell className="whitespace-nowrap text-slate-600">{datesOf(r) ? formatDateShort(datesOf(r)!.first) : "—"}</TableCell>
                                <TableCell className="whitespace-nowrap text-slate-600">{datesOf(r) ? formatDateShort(datesOf(r)!.last) : "—"}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(r.opening)}</TableCell>
                                <TableCell className="text-right tabular-nums text-emerald-700">{n(r.generated)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(r.manualIn)}</TableCell>
                                <TableCell className="text-right tabular-nums text-blue-700">{n(r.sold)}</TableCell>
                                <TableCell className="text-right tabular-nums text-rose-700">{n(r.disposed)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(r.internalUse)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(r.manualOut)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(r.reversals)}</TableCell>
                                <TableCell className="text-right font-semibold tabular-nums">{n(r.closing)}</TableCell>
                                <TableCell className="text-right tabular-nums">{r.revenue ? fmt(r.revenue) : "—"}</TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                          {flocks.length > 1 && (
                            <TableFooter>
                              <TableRow>
                                <TableCell colSpan={4} className="font-semibold">Total</TableCell>
                                <TableCell className="text-right tabular-nums">{n(totals.opening)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(totals.generated)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(totals.manualIn)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(totals.sold)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(totals.disposed)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(totals.internalUse)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(totals.manualOut)}</TableCell>
                                <TableCell className="text-right tabular-nums">{n(totals.reversals)}</TableCell>
                                <TableCell className="text-right font-bold tabular-nums">{n(totals.closing)}</TableCell>
                                <TableCell className="text-right tabular-nums">{totals.revenue ? fmt(totals.revenue) : "—"}</TableCell>
                              </TableRow>
                            </TableFooter>
                          )}
                        </Table>
                      </>
                    )}
                  </CardContent>
                </Card>

                {/* ---- movements ---- */}
                <Card className="bg-white">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Movements</CardTitle>
                    <CardDescription>
                      Every {copy.unit === "eggs" ? "broken egg" : "dead bird"} movement in the period, newest first, with the
                      running balance. In {n(ledgerIn)} · Out {n(ledgerOut)}.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="overflow-x-auto pb-2">
                    {isMobile && !showLedgerTableMobile ? (
                      <div className="space-y-3">
                        {pg.pageItems.length === 0 ? (
                          <p className="py-8 text-center text-sm text-slate-500">No movements in this period.</p>
                        ) : pg.pageItems.map((m, idx) => (
                          <div key={m.txnId} className={cn("rounded-xl border px-3 py-3 shadow-sm", idx % 2 === 0 ? "border-slate-300 bg-slate-50" : "border-slate-200 bg-white")}>
                            <div className="flex items-start justify-between gap-2">
                              <div className="min-w-0">
                                <CategoryBadge m={m} />
                                <div className="mt-1 text-xs text-slate-500">{formatDateShort(m.date)} · {SOURCE_LABEL[m.txnType] ?? m.txnType}</div>
                              </div>
                              <div className={cn("text-lg font-bold tabular-nums", m.quantity >= 0 ? "text-emerald-700" : "text-rose-700")}>
                                {m.quantity >= 0 ? "+" : "−"}{n(Math.abs(m.quantity))}
                              </div>
                            </div>
                            <div className="mt-2 grid grid-cols-2 gap-1 text-sm">
                              <span className="text-slate-500">{flockLabel(m)}</span>
                              <span className="text-right text-slate-500">Balance <b className="tabular-nums text-slate-800">{n(m.balance)}</b></span>
                              {(m.movementNo || m.saleId) && <span className="col-span-2 text-slate-600">{reference(m)}</span>}
                              {m.note && <span className="col-span-2 truncate text-xs text-slate-500">{m.note}</span>}
                            </div>
                          </div>
                        ))}
                        <Button type="button" variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowLedgerTableMobile(true)}>
                          View table format <ChevronDown className="ml-1 h-4 w-4" />
                        </Button>
                      </div>
                    ) : (
                      <>
                        {isMobile && (
                          <div className="mb-2 flex justify-end">
                            <Button type="button" variant="ghost" size="sm" onClick={() => setShowLedgerTableMobile(false)}>
                              <ChevronUp className="mr-1 h-4 w-4" /> Cards
                            </Button>
                          </div>
                        )}
                        <Table className="w-full min-w-[900px]">
                          <TableHeader>
                            <TableRow>
                              <TableHead>Date</TableHead>
                              <TableHead>Movement</TableHead>
                              <TableHead>From</TableHead>
                              <TableHead>Flock</TableHead>
                              <TableHead className="text-right">In</TableHead>
                              <TableHead className="text-right">Out</TableHead>
                              <TableHead className="text-right">Balance</TableHead>
                              <TableHead>Reference</TableHead>
                              <TableHead>Note</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pg.pageItems.length === 0 ? (
                              <TableRow><TableCell colSpan={9} className="py-8 text-center text-slate-500">No movements in this period.</TableCell></TableRow>
                            ) : pg.pageItems.map((m) => (
                              <TableRow key={m.txnId}>
                                <TableCell className="whitespace-nowrap">{formatDateShort(m.date)}</TableCell>
                                <TableCell><CategoryBadge m={m} /></TableCell>
                                <TableCell className="text-slate-600">{SOURCE_LABEL[m.txnType] ?? m.txnType}</TableCell>
                                <TableCell className={cn(m.flockId == null && "italic text-slate-500")}>
                                  {flockLabel(m)}{m.batchCode ? <span className="ml-1 text-xs text-slate-500">{m.batchCode}</span> : null}
                                </TableCell>
                                <TableCell className="text-right tabular-nums text-emerald-700">{m.quantity > 0 ? n(m.quantity) : ""}</TableCell>
                                <TableCell className="text-right tabular-nums text-rose-700">{m.quantity < 0 ? n(-m.quantity) : ""}</TableCell>
                                <TableCell className="text-right font-semibold tabular-nums">{n(m.balance)}</TableCell>
                                <TableCell className="whitespace-nowrap">{reference(m)}</TableCell>
                                <TableCell className="max-w-[18rem] truncate text-xs text-slate-500" title={m.note ?? undefined}>{m.note ?? ""}</TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </>
                    )}
                    <DataPagination {...pg.paginationProps} variant="records" className="mt-3" />
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

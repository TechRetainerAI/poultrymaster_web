"use client"

// Egg Sorting Workspace (migrations 341-343). NEW page beside the legacy
// /egg-production ("Egg sorting"), which is unchanged.
//
//   PRODUCTION CREATES EGGS. SORTING DOES NOT CREATE EGGS -- IT RECLASSIFIES
//   EGGS THAT ALREADY EXIST (Unsorted -> sizes + losses).
//
// Both ways farms work are supported, and can be mixed on the same day:
//   Sort a pick              -- sort right after each collection
//   Sort all available eggs  -- collect everything, sort later (FIFO by day, pick)
// Partial sorting, many sessions per pick, and sorting on a later day all work;
// what is left is always read from the production record, never retyped.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { AlertTriangle, ChevronDown, ChevronUp, Egg, Layers, Loader2, Pencil, RotateCcw, Trash2 } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { useBusinessDate } from "@/hooks/use-business-date"
import { useCompanyDateTime } from "@/hooks/use-company-datetime"
import { usePermissions } from "@/hooks/use-permissions"
import { usePickSettings } from "@/hooks/use-pick-settings"
import { useAuthStore } from "@/lib/store/auth-store"
import {
  discardEggSorting,
  getEggClasses,
  getEggSortingPicks,
  getEggSortingSettings,
  getEggSortingSummary,
  getProductionDuplicates,
  listEggSortingSessions,
  reverseEggSorting,
  type EggClass,
  type EggSortingPick,
  type EggSortingSession,
  type EggSortingSettings,
  type EggSortingSummary,
  type ProductionDuplicateGroup,
  type SortingStatus,
} from "@/lib/api/egg-sorting"
import {
  STATUS_LABEL,
  cratesText,
  fmtCount,
  groupProductionDays,
  lineTypeLabel,
  pct,
  pickLabel,
  pickRemaining,
  pickStatus,
  type PickStatus,
  type ProductionDay,
} from "@/lib/production/egg-sorting"
import { formatLongDate } from "@/lib/closing/daily-closing"
import { shiftBusinessDate, toBusinessDate } from "@/lib/activity/completeness"
import { ReasonDialog } from "@/components/closing/daily-closing-dialogs"
import { SortEggsDialog, type SortTarget } from "@/components/egg-sorting/sort-eggs-dialog"
import { SizesSettingsPanel } from "@/components/egg-sorting/sizes-settings-panel"
import { CompositionReport } from "@/components/egg-sorting/composition-report"
import { EggSortingAuditList } from "@/components/egg-sorting/egg-sorting-audit-list"
import { useEggsPerCrate } from "@/hooks/use-eggs-per-crate"
import { usePagination } from "@/hooks/use-pagination"
import { DataPagination } from "@/components/ui/data-pagination"

const STATUS_STYLE: Record<PickStatus, string> = {
  NotStarted: "bg-slate-100 text-slate-700",
  Partial: "bg-amber-100 text-amber-800",
  Complete: "bg-emerald-100 text-emerald-800",
}

function Stat({ label, value, sub, tone }: { label: string; value: string; sub?: string; tone?: "warn" | "good" }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className={cn("font-semibold tabular-nums", tone === "warn" ? "text-amber-700" : tone === "good" ? "text-emerald-700" : "text-slate-900")}>{value}</div>
      {sub && <div className="text-[11px] text-slate-500">{sub}</div>}
    </div>
  )
}

function StatusChip({ status }: { status: PickStatus }) {
  return <span className={cn("rounded px-1.5 py-0.5 text-[11px] font-medium", STATUS_STYLE[status])}>{STATUS_LABEL[status]}</span>
}

function EggSortingInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const logout = useLogout()
  const { toast } = useToast()
  const { fmtInstant } = useCompanyDateTime()
  const { businessDate: today } = useBusinessDate()
  const permissions = usePermissions()
  const { labels } = usePickSettings()
  useEggsPerCrate()   // crate figures follow the farm's setting
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const canSort = permissions.can("poultry.egg-sorting.create") || permissions.canCreate
  const canEdit = permissions.can("poultry.egg-sorting.edit") || permissions.canEdit
  const canRemove = permissions.can("poultry.egg-sorting.delete") || permissions.canDelete

  // ?record=<id> (from Production Records) focuses one production record.
  const recordParam = Number(searchParams.get("record")) || null
  const [from, setFrom] = useState(() => shiftBusinessDate(today, -6) ?? today)
  const [to, setTo] = useState(today)
  useEffect(() => { setTo(today); setFrom((f) => (f > today ? shiftBusinessDate(today, -6) ?? today : f)) }, [today])
  const [flockFilter, setFlockFilter] = useState<string>("all")
  const [statusFilter, setStatusFilter] = useState<"open" | "all" | PickStatus>("open")
  const [search, setSearch] = useState("")
  const [tab, setTab] = useState(searchParams.get("tab") ?? "workspace")

  const [settings, setSettings] = useState<EggSortingSettings | null>(null)
  const [classes, setClasses] = useState<EggClass[]>([])
  const [summary, setSummary] = useState<EggSortingSummary | null>(null)
  const [picks, setPicks] = useState<EggSortingPick[] | null>(null)
  const [duplicates, setDuplicates] = useState<ProductionDuplicateGroup[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [target, setTarget] = useState<SortTarget | null>(null)
  const [lastDone, setLastDone] = useState<string | null>(null)

  const [sessions, setSessions] = useState<EggSortingSession[] | null>(null)
  const [sessionStatus, setSessionStatus] = useState<"all" | SortingStatus>("all")
  const [openSession, setOpenSession] = useState<number | null>(null)
  const [reverseTarget, setReverseTarget] = useState<EggSortingSession | null>(null)
  const [reversing, setReversing] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const loadSetup = useCallback(async () => {
    try {
      const s = await getEggSortingSettings()
      setSettings(s)
      setClasses(await getEggClasses({ includeInactive: true, ensure: s.enableEggSorting }))
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load egg sorting settings.")
    }
  }, [])

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [p, sm, dups] = await Promise.all([
        recordParam ? getEggSortingPicks({ recordIds: [recordParam] }) : getEggSortingPicks({ fromDate: from, toDate: to }),
        getEggSortingSummary(),
        getProductionDuplicates().catch(() => [] as ProductionDuplicateGroup[]),
      ])
      setPicks(p)
      setSummary(sm)
      setDuplicates(dups)
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load production.")
    } finally {
      setLoading(false)
    }
  }, [from, to, recordParam])

  const loadSessions = useCallback(async () => {
    try {
      setSessions(await listEggSortingSessions({
        fromDate: shiftBusinessDate(from, -30) ?? from, toDate: today,
        status: sessionStatus === "all" ? undefined : sessionStatus,
      }))
    } catch (e) {
      toast({ title: "Could not load sortings", description: e instanceof Error ? e.message : "", variant: "destructive" })
    }
  }, [from, today, sessionStatus, toast])

  useEffect(() => { if (activeFarmId) void loadSetup() }, [activeFarmId, loadSetup])
  useEffect(() => { if (activeFarmId) void load() }, [activeFarmId, load])
  useEffect(() => { if (tab === "sessions" && activeFarmId) void loadSessions() }, [tab, activeFarmId, loadSessions])

  const days = useMemo(() => groupProductionDays(picks ?? []), [picks])
  const flocks = useMemo(() => {
    const m = new Map<number, string>()
    for (const d of days) m.set(d.flockId, d.flockName)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [days])
  const shownDays = useMemo(() => days.filter((d) =>
    (flockFilter === "all" || String(d.flockId) === flockFilter)
    && (statusFilter === "all" || (statusFilter === "open" ? d.left > 0 : d.status === statusFilter))
    && (!search.trim() || `${d.flockName} ${d.batchName ?? ""} ${d.houseName ?? ""}`.toLowerCase().includes(search.trim().toLowerCase())),
  ), [days, flockFilter, statusFilter, search])

  const sizes = useMemo(() => classes.filter((c) => c.classKind === "Size"), [classes])
  // Paged like every other list page (hooks/use-pagination + DataPagination).
  const daysPg = usePagination(shownDays, 5)
  const sessionsPg = usePagination(sessions ?? [], 10)
  const sortingOn = settings?.enableEggSorting ?? false

  const onDone = (message: string, refresh: boolean) => {
    if (message) { setTarget(null); setLastDone(message); toast({ title: message.startsWith("Draft") ? "Draft saved" : "Sorting posted", description: message }) }
    if (refresh) { void load(); void loadSetup(); if (tab === "sessions") void loadSessions() }
  }

  const sortAll = (day: ProductionDay) => setTarget({
    mode: "Combined", day,
    otherDays: days.filter((d) => d.flockId === day.flockId && d.productionRecordId !== day.productionRecordId && d.left > 0),
  })

  // Re-open a draft against fresh availability for its own records.
  const editDraft = async (s: EggSortingSession) => {
    try {
      const rows = await getEggSortingPicks({ recordIds: s.scopeRecordIds })
      const ds = groupProductionDays(rows)
      const day = ds.find((d) => d.productionRecordId === (s.productionRecordId ?? s.scopeRecordIds[0])) ?? ds[0]
      if (!day) throw new Error("The production record behind this draft no longer exists.")
      setTarget({
        mode: s.sortingMode, day, draft: s,
        pick: s.sortingMode === "ByPick" ? day.picks.find((p) => p.pickNumber === s.pickNumber) ?? null : null,
        otherDays: ds.filter((d) => d.productionRecordId !== day.productionRecordId),
      })
    } catch (e) {
      toast({ title: "Could not open the draft", description: e instanceof Error ? e.message : "", variant: "destructive" })
    }
  }

  const discard = async (s: EggSortingSession) => {
    try {
      await discardEggSorting(s.sessionId)
      toast({ title: `Draft ${s.sessionNo} discarded` })
      void loadSessions()
    } catch (e) {
      toast({ title: "Not discarded", description: e instanceof Error ? e.message : "", variant: "destructive" })
    }
  }

  const doReverse = async (reason: string) => {
    if (!reverseTarget) return
    setReversing(true)
    try {
      await reverseEggSorting(reverseTarget.sessionId, reason)
      toast({ title: `${reverseTarget.sessionNo} reversed`, description: "The sized eggs went back into Unsorted, and the picks can be sorted again." })
      setReverseTarget(null)
      void loadSessions(); void load(); void loadSetup()
    } catch (e) {
      toast({ title: "Not reversed", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally {
      setReversing(false)
    }
  }

  const unsortedClass = classes.find((c) => c.classKind === "Unsorted")
  const remainingToSort = summary ? Math.min(summary.productionLeft, Math.max(0, Math.trunc(summary.unsortedOnHand))) : 0

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-x-hidden p-4 pb-6 sm:p-6">
          <div className="space-y-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-amber-100">
                  <Egg className="h-5 w-5 text-amber-700" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Egg Sorting Workspace</h1>
                  <p className="text-sm text-slate-600">
                    Sort collected eggs into sizes — one pick at a time, or everything at once. Sorting never creates eggs:
                    it moves them from Unsorted into sizes, and records what was lost.
                  </p>
                </div>
              </div>
              <div className="flex gap-2">
                <Button variant="outline" size="sm" asChild><Link href="/egg-tracker">View Egg Tracker</Link></Button>
                <Button variant="outline" size="sm" asChild><Link href="/production-records">View production</Link></Button>
              </div>
            </div>

            {settings && !sortingOn && (
              <Card className="border-amber-200 bg-amber-50">
                <CardContent className="flex flex-wrap items-center justify-between gap-3 p-4 text-sm text-amber-900">
                  <span>
                    Egg sorting is <b>off</b> for this farm. Production goes into Unsorted / General eggs, which you can sell directly.
                    Turn sorting on to grade eggs into sizes.
                  </span>
                  {canEdit && <Button size="sm" variant="outline" onClick={() => setTab("settings")}>Sizes &amp; settings</Button>}
                </CardContent>
              </Card>
            )}

            {duplicates.length > 0 && (
              <Card className="border-rose-200 bg-rose-50">
                <CardContent className="flex items-start gap-2 p-4 text-sm text-rose-900">
                  <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                  <div>
                    <b>{duplicates.length} flock-day{duplicates.length === 1 ? " has" : "s have"} more than one production record</b>, from before
                    the one-record-per-day rule. Each record is sorted on its own; merge them in Production Records when you can.
                    <div className="mt-1 text-xs text-rose-800">
                      {duplicates.slice(0, 6).map((d) => `${d.flockName ?? "Flock " + d.flockId} — ${formatLongDate(d.productionDate.slice(0, 10))} (${d.recordCount} records)`).join(" · ")}
                      {duplicates.length > 6 ? " …" : ""}
                    </div>
                  </div>
                </CardContent>
              </Card>
            )}

            {summary && (
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
                <Stat label="Unsorted in stock" value={fmtCount(summary.unsortedOnHand)} sub={cratesText(summary.unsortedOnHand)} />
                <Stat label="Remaining to sort" value={fmtCount(remainingToSort)}
                  sub={summary.oldestLeftDate ? `oldest ${formatLongDate(summary.oldestLeftDate.slice(0, 10))}` : undefined}
                  tone={remainingToSort > 0 ? "warn" : "good"} />
                <Stat label="Sorted today" value={fmtCount(summary.sortedToday)} sub={`${summary.sessionsToday} sorting${summary.sessionsToday === 1 ? "" : "s"}`} />
                <Stat label="Sized eggs created" value={fmtCount(summary.sizedCreatedToday)} sub="today" />
                <Stat label="Sorting loss" value={fmtCount(summary.lossToday)} sub={`today · ${pct(summary.lossToday, summary.sortedToday)}`} />
                <Stat label="Sized in stock" value={fmtCount(summary.sizedOnHand)} sub={cratesText(summary.sizedOnHand)} />
              </div>
            )}

            {lastDone && (
              <Card className="border-emerald-200 bg-emerald-50"><CardContent className="p-3 text-sm text-emerald-900">{lastDone}</CardContent></Card>
            )}

            <Tabs value={tab} onValueChange={setTab}>
              <TabsList className="flex-wrap">
                <TabsTrigger value="workspace">Workspace</TabsTrigger>
                <TabsTrigger value="sessions">Sortings</TabsTrigger>
                <TabsTrigger value="reports">Size reports</TabsTrigger>
                <TabsTrigger value="settings">Sizes &amp; settings</TabsTrigger>
              </TabsList>

              {/* ------------------------------------------------- workspace */}
              <TabsContent value="workspace" className="mt-4 space-y-4">
                {recordParam ? (
                  <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                    <CardContent className="flex flex-wrap items-center justify-between gap-2 p-3 text-sm text-slate-700">
                      Showing one production record (#{recordParam}).
                      <Button size="sm" variant="outline" onClick={() => router.replace("/poultry-egg-sorting")}>Show all production</Button>
                    </CardContent>
                  </Card>
                ) : (
                  <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                    <CardContent className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 lg:grid-cols-5">
                      <div className="space-y-1">
                        <Label className="text-xs text-slate-500">Production from</Label>
                        <Input type="date" value={from} max={to} onChange={(e) => toBusinessDate(e.target.value) && setFrom(e.target.value)} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs text-slate-500">Production to</Label>
                        <Input type="date" value={to} min={from} max={today} onChange={(e) => toBusinessDate(e.target.value) && setTo(e.target.value)} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs text-slate-500">Flock</Label>
                        <Select value={flockFilter} onValueChange={setFlockFilter}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="all">All flocks</SelectItem>
                            {flocks.map(([id, name]) => <SelectItem key={id} value={String(id)}>{name}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs text-slate-500">Status</Label>
                        <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v as typeof statusFilter)}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="open">Eggs left to sort</SelectItem>
                            <SelectItem value="all">All</SelectItem>
                            <SelectItem value="NotStarted">Not started</SelectItem>
                            <SelectItem value="Partial">Partial</SelectItem>
                            <SelectItem value="Complete">Complete</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs text-slate-500">Search</Label>
                        <Input value={search} placeholder="Flock, batch, house" onChange={(e) => setSearch(e.target.value)} />
                      </div>
                    </CardContent>
                  </Card>
                )}

                {error && <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>}
                {loading && !picks && <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading production…</p>}
                {picks && shownDays.length === 0 && (
                  <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                    <CardContent className="p-6 text-center text-sm text-slate-500">
                      {days.length === 0
                        ? "No production recorded in this period. Eggs appear here once a production record is saved — sorting never needs one of its own."
                        : "Nothing matches these filters."}
                    </CardContent>
                  </Card>
                )}

                {daysPg.pageItems.map((d) => {
                  const progress = d.saleable > 0 ? Math.min(100, (d.sorted / d.saleable) * 100) : 0
                  return (
                    <Card key={d.productionRecordId} className="rounded-xl border border-slate-200 bg-white shadow-sm">
                      <CardContent className="space-y-3 p-4">
                        <div className="flex flex-wrap items-start justify-between gap-3">
                          <div>
                            <div className="text-base font-semibold text-slate-900">
                              {d.flockName} — {formatLongDate(d.productionDate)}
                            </div>
                            <div className="text-xs text-slate-500">
                              {[d.batchName, d.houseName].filter(Boolean).join(" · ") || " "}
                            </div>
                          </div>
                          <div className="flex flex-wrap gap-2">
                            <Button size="sm" variant="outline" asChild>
                              <Link href={`/production-records/${d.productionRecordId}`}>View production</Link>
                            </Button>
                            <Button size="sm" disabled={!canSort || !sortingOn || d.left <= 0} onClick={() => sortAll(d)}
                              className="bg-emerald-600 text-white hover:bg-emerald-700">
                              <Layers className="mr-1.5 h-4 w-4" /> Sort all available eggs
                            </Button>
                          </div>
                        </div>

                        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                          <Stat label="Production (saleable)" value={fmtCount(d.saleable)}
                            sub={d.collectionLoss ? `${fmtCount(d.gross)} collected, ${fmtCount(d.collectionLoss)} broken/lost` : cratesText(d.saleable)} />
                          <Stat label="Sorted" value={fmtCount(d.sorted)} />
                          <Stat label="Remaining" value={fmtCount(d.left)} tone={d.left > 0 ? "warn" : "good"} />
                          <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
                            <div className="flex items-center justify-between text-[11px] uppercase tracking-wide text-slate-500">
                              Progress <StatusChip status={d.status} />
                            </div>
                            <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-slate-100">
                              <div className={cn("h-full", d.left <= 0 ? "bg-emerald-500" : "bg-amber-500")} style={{ width: `${progress}%` }} />
                            </div>
                            <div className="mt-0.5 text-[11px] text-slate-500">{progress.toFixed(1)}%</div>
                          </div>
                        </div>

                        <div className="overflow-x-auto">
                          <table className="w-full min-w-[36rem] text-sm">
                            <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                              <tr>
                                <th className="px-3 py-2 font-medium">Pick</th>
                                <th className="px-3 py-2 text-right font-medium">Collected</th>
                                <th className="px-3 py-2 text-right font-medium">Sorted</th>
                                <th className="px-3 py-2 text-right font-medium">Remaining</th>
                                <th className="px-3 py-2 font-medium">Status</th>
                                <th className="px-3 py-2" />
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100">
                              {d.picks.map((p) => {
                                const left = pickRemaining(p)
                                return (
                                  <tr key={p.pickNumber}>
                                    <td className="px-3 py-2 font-medium text-slate-900">{pickLabel(p.pickNumber, labels)}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{fmtCount(p.pickGross)}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{fmtCount(p.pickSorted)}</td>
                                    <td className="px-3 py-2 text-right tabular-nums font-medium">{fmtCount(left)}</td>
                                    <td className="px-3 py-2"><StatusChip status={pickStatus(p)} /></td>
                                    <td className="px-3 py-2 text-right">
                                      <Button size="sm" variant="outline" disabled={!canSort || !sortingOn || left <= 0}
                                        onClick={() => setTarget({ mode: "ByPick", day: d, pick: p })}>
                                        {p.pickSorted > 0 && left > 0 ? "Continue sorting" : "Sort pick"}
                                      </Button>
                                    </td>
                                  </tr>
                                )
                              })}
                            </tbody>
                          </table>
                        </div>
                        {d.collectionLoss > 0 && (
                          <p className="text-xs text-slate-500">
                            Broken, meaty, soft and lost eggs are recorded for the whole day, not per pick, so the day can be sorted up to its {fmtCount(d.saleable)} saleable eggs.
                          </p>
                        )}
                      </CardContent>
                    </Card>
                  )
                })}
                <DataPagination {...daysPg.paginationProps} />
              </TabsContent>

              {/* -------------------------------------------------- sessions */}
              <TabsContent value="sessions" className="mt-4 space-y-3">
                <div className="flex flex-wrap items-end gap-3">
                  <div className="space-y-1">
                    <Label className="text-xs text-slate-500">Status</Label>
                    <Select value={sessionStatus} onValueChange={(v) => setSessionStatus(v as typeof sessionStatus)}>
                      <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All</SelectItem>
                        <SelectItem value="Draft">Drafts</SelectItem>
                        <SelectItem value="Posted">Posted</SelectItem>
                        <SelectItem value="Reversed">Reversed</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <p className="pb-2 text-xs text-slate-500">Last 30 days before {formatLongDate(from)} to today.</p>
                </div>
                {!sessions && <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>}
                {sessions && sessions.length === 0 && <p className="text-sm text-slate-500">No sortings yet.</p>}
                {sessions && sessions.length > 0 && (
                  <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                    <CardContent className="p-0">
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[52rem] text-sm">
                          <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                            <tr>
                              <th className="px-3 py-2 font-medium">Sorting</th>
                              <th className="px-3 py-2 font-medium">Sorted on</th>
                              <th className="px-3 py-2 font-medium">Flock / production</th>
                              <th className="px-3 py-2 font-medium">How</th>
                              <th className="px-3 py-2 text-right font-medium">Sorted</th>
                              <th className="px-3 py-2 text-right font-medium">Into sizes</th>
                              <th className="px-3 py-2 text-right font-medium">Loss</th>
                              <th className="px-3 py-2 font-medium">Status</th>
                              <th className="px-3 py-2" />
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-slate-100">
                            {sessionsPg.pageItems.map((s) => {
                              const open = openSession === s.sessionId
                              const prodDates = s.firstProductionDate
                                ? s.firstProductionDate === s.lastProductionDate
                                  ? formatLongDate(s.firstProductionDate.slice(0, 10))
                                  : `${formatLongDate(s.firstProductionDate.slice(0, 10))} – ${formatLongDate((s.lastProductionDate ?? "").slice(0, 10))}`
                                : "—"
                              return (
                                <FragmentRows key={s.sessionId}>
                                  <tr className={cn(s.status === "Reversed" && "text-slate-500")}>
                                    <td className="px-3 py-2">
                                      <button type="button" className="flex items-center gap-1 font-medium text-slate-900" onClick={() => setOpenSession(open ? null : s.sessionId)}>
                                        {open ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />} {s.sessionNo}
                                      </button>
                                    </td>
                                    <td className="px-3 py-2">{formatLongDate(s.sortingDate.slice(0, 10))}</td>
                                    <td className="px-3 py-2">
                                      <div className="font-medium">{s.flockName ?? `Flock ${s.flockId}`}</div>
                                      <div className="text-xs text-slate-500">produced {prodDates}</div>
                                    </td>
                                    <td className="px-3 py-2">{s.sortingMode === "ByPick" ? pickLabel(s.pickNumber ?? 0, labels).split(" (")[0] : "All available"}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{fmtCount(s.inputQuantity)}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{fmtCount(s.outputQuantity)}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{fmtCount(s.lossQuantity)}</td>
                                    <td className="px-3 py-2">
                                      <span className={cn("rounded px-1.5 py-0.5 text-[11px] font-medium",
                                        s.status === "Posted" ? "bg-emerald-100 text-emerald-800" : s.status === "Draft" ? "bg-sky-100 text-sky-800" : "bg-slate-200 text-slate-700")}>
                                        {s.status}
                                      </span>
                                    </td>
                                    <td className="whitespace-nowrap px-3 py-2 text-right">
                                      {s.status === "Draft" && (
                                        <>
                                          <Button size="sm" variant="ghost" disabled={!canSort} onClick={() => void editDraft(s)}><Pencil className="mr-1 h-3.5 w-3.5" /> Open</Button>
                                          <Button size="sm" variant="ghost" className="text-rose-700" disabled={!canRemove} onClick={() => void discard(s)}><Trash2 className="mr-1 h-3.5 w-3.5" /> Discard</Button>
                                        </>
                                      )}
                                      {s.status === "Posted" && (
                                        <Button size="sm" variant="ghost" className="text-rose-700" disabled={!canRemove} onClick={() => setReverseTarget(s)}>
                                          <RotateCcw className="mr-1 h-3.5 w-3.5" /> Reverse
                                        </Button>
                                      )}
                                    </td>
                                  </tr>
                                  {open && (
                                    <tr className="bg-slate-50/60">
                                      <td colSpan={9} className="px-3 py-3">
                                        <div className="grid gap-4 md:grid-cols-2">
                                          <div>
                                            <div className="mb-1 text-xs font-medium uppercase tracking-wide text-slate-500">Grading</div>
                                            {s.lines.map((l, i) => (
                                              <div key={i} className="flex justify-between border-b border-slate-100 py-1 text-sm">
                                                <span className={l.lineType !== "SizedOutput" ? "text-rose-800" : ""}>{lineTypeLabel(l.lineType, l.sizeName)}</span>
                                                <span className="tabular-nums">{fmtCount(l.quantity)} <span className="text-xs text-slate-500">({pct(l.quantity, s.inputQuantity)})</span></span>
                                              </div>
                                            ))}
                                          </div>
                                          <div>
                                            <div className="mb-1 text-xs font-medium uppercase tracking-wide text-slate-500">Came from</div>
                                            {s.sources.length === 0 && <p className="text-sm text-slate-500">Allocated when posted.</p>}
                                            {s.sources.map((src, i) => (
                                              <div key={i} className="flex justify-between border-b border-slate-100 py-1 text-sm">
                                                <span>{formatLongDate(src.productionDate.slice(0, 10))} · {pickLabel(src.pickNumber, labels).split(" (")[0]}</span>
                                                <span className="tabular-nums">{fmtCount(src.quantity)}</span>
                                              </div>
                                            ))}
                                            <p className="mt-2 text-xs text-slate-500">
                                              {s.postedAtUtc ? `Posted ${fmtInstant(s.postedAtUtc)} by ${s.postedBy ?? "—"}.` : `Saved by ${s.createdBy ?? "—"}.`}
                                              {s.reversedAtUtc ? ` Reversed ${fmtInstant(s.reversedAtUtc)} by ${s.reversedBy ?? "—"}: ${s.reversalReason ?? ""}` : ""}
                                              {s.notes ? ` Note: ${s.notes}` : ""}
                                            </p>
                                          </div>
                                        </div>
                                        <div className="mt-3">
                                          <div className="mb-1 text-xs font-medium uppercase tracking-wide text-slate-500">History</div>
                                          <EggSortingAuditList bare entity="Sorting" entityId={s.sessionId} limit={20} />
                                        </div>
                                      </td>
                                    </tr>
                                  )}
                                </FragmentRows>
                              )
                            })}
                          </tbody>
                        </table>
                      </div>
                      <div className="border-t border-slate-100 px-3 py-2">
                        <DataPagination {...sessionsPg.paginationProps} />
                      </div>
                    </CardContent>
                  </Card>
                )}
              </TabsContent>

              {/* --------------------------------------------------- reports */}
              <TabsContent value="reports" className="mt-4">
                {tab === "reports" && (
                  <CompositionReport from={shiftBusinessDate(today, -29) ?? from} to={today}
                    flockId={flockFilter === "all" ? null : Number(flockFilter)} />
                )}
              </TabsContent>

              {/* -------------------------------------------------- settings */}
              <TabsContent value="settings" className="mt-4">
                <SizesSettingsPanel settings={settings} classes={classes} canEdit={canEdit} onChanged={() => void loadSetup()} />
                {unsortedClass && (
                  <p className="mt-3 text-xs text-slate-500">
                    Unsorted / General eggs on hand: {fmtCount(unsortedClass.onHand)} ({cratesText(unsortedClass.onHand)}). Production always adds to Unsorted.
                  </p>
                )}
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      <SortEggsDialog target={target} onClose={() => setTarget(null)} sizes={sizes} today={today}
        labels={labels} canPost={canSort} onDone={onDone} />

      <ReasonDialog
        open={!!reverseTarget} onOpenChange={(v) => { if (!v) setReverseTarget(null) }} busy={reversing} destructive
        title={`Reverse ${reverseTarget?.sessionNo ?? "this sorting"}?`}
        description="The sized eggs go back into Unsorted and the picks can be sorted again. The sorting stays in the history, marked Reversed. If any of its sized eggs were already sold or used, reverse those first."
        confirmLabel="Reverse" onConfirm={(r) => void doReverse(r)} />
    </div>
  )
}

function FragmentRows({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}

export default function EggSortingWorkspacePage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <EggSortingInner />
    </Suspense>
  )
}

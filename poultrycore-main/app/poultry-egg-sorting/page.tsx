"use client"

// Egg Sorting Workspace (migrations 341-343). Replaces the legacy
// /egg-production ("Egg sorting") in the menus; that page is unchanged.
//
//   PRODUCTION CREATES EGGS. SORTING DOES NOT CREATE EGGS -- IT RECLASSIFIES
//   EGGS THAT ALREADY EXIST (Unsorted -> sizes + losses).
//
// Both ways farms work are supported, and can be mixed on the same day:
//   Sort a pick              -- sort right after each collection
//   Sort all available eggs  -- collect everything, sort later (FIFO by day, pick)
// Partial sorting, many sessions per pick, and sorting on a later day all work;
// what is left is always read from the production record, never retyped.

import { STOCK_REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { AlertTriangle, BarChart3, ChevronDown, ChevronUp, Egg, History, Layers, Loader2, Pencil, RotateCcw, Settings2, Trash2 } from "lucide-react"
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
  capToSortable,
  cratesText,
  fmtCount,
  groupProductionDays,
  lineTypeLabel,
  pct,
  pickLabel,
  pickRemaining,
  pickStatus,
  sortableByRecord,
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

// One accent per flock, so "All flocks" reads as separate sections at a
// glance. Literal class names: Tailwind only ships classes it can see.
const FLOCK_ACCENTS = [
  { edge: "border-l-amber-400", dot: "bg-amber-400" },
  { edge: "border-l-sky-400", dot: "bg-sky-400" },
  { edge: "border-l-violet-400", dot: "bg-violet-400" },
  { edge: "border-l-emerald-400", dot: "bg-emerald-400" },
  { edge: "border-l-rose-400", dot: "bg-rose-400" },
  { edge: "border-l-teal-400", dot: "bg-teal-400" },
]

function Stat({ label, value, sub, tone }: { label: string; value: string; sub?: string; tone?: "warn" | "good" }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className={cn("font-semibold tabular-nums", tone === "warn" ? "text-amber-700" : tone === "good" ? "text-emerald-700" : "text-slate-900")}>{value}</div>
      {sub && <div className="text-[11px] text-slate-500">{sub}</div>}
    </div>
  )
}

function StatusChip({ status, sold }: { status: PickStatus; sold?: boolean }) {
  // Nothing sorted and nothing left because the eggs were sold unsorted: not
  // "Complete", which would read as graded.
  if (sold) return <span className="rounded bg-slate-200 px-1.5 py-0.5 text-[11px] font-medium text-slate-700">Sold unsorted</span>
  return <span className={cn("rounded px-1.5 py-0.5 text-[11px] font-medium", STATUS_STYLE[status])}>{STATUS_LABEL[status]}</span>
}

// Each tab its own colour, so the four read as separate places at a glance.
// Literal class names: Tailwind only ships classes it can see.
const TAB_STYLE = {
  workspace: "data-[state=active]:bg-amber-500 data-[state=active]:border-amber-600 hover:bg-amber-50",
  sessions: "data-[state=active]:bg-sky-600 data-[state=active]:border-sky-700 hover:bg-sky-50",
  reports: "data-[state=active]:bg-violet-600 data-[state=active]:border-violet-700 hover:bg-violet-50",
  settings: "data-[state=active]:bg-emerald-600 data-[state=active]:border-emerald-700 hover:bg-emerald-50",
} as const
const TAB_BASE = "h-10 gap-2 rounded-lg border-slate-200 bg-white px-4 text-sm font-semibold text-slate-700 shadow-sm data-[state=active]:text-white data-[state=active]:shadow-md sm:h-9"

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
  // Blank From/To = no limit that side. The default is "All months": every
  // production day, so nothing waiting to be sorted is hidden behind a date.
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  // "all" = no dates; a "YYYY-MM" sets From/To to that month; "custom" =
  // dates typed by hand.
  const [month, setMonth] = useState("all")
  const monthOptions = useMemo(() => {
    const [y, m] = today.split("-").map(Number)
    return Array.from({ length: 12 }, (_, i) => {
      const d = new Date(Date.UTC(y, m - 1 - i, 1))
      return {
        value: `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`,
        label: d.toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" }),
      }
    })
  }, [today])
  const pickMonth = (v: string) => {
    if (v === "custom") return
    setMonth(v)
    if (v === "all") { setFrom(""); setTo(""); return }
    const [y, m] = v.split("-").map(Number)
    const last = `${v}-${String(new Date(Date.UTC(y, m, 0)).getUTCDate()).padStart(2, "0")}`
    setFrom(`${v}-01`)
    setTo(last > today ? today : last)
  }
  const [flockFilter, setFlockFilter] = useState<string>("all")
  const [statusFilter, setStatusFilter] = useState<"open" | "all" | PickStatus>("open")
  const [search, setSearch] = useState("")
  const [tab, setTab] = useState(searchParams.get("tab") ?? "workspace")
  // Setup > Production > Egg Sorting Settings links here with ?tab=settings;
  // follow it even when the page is already open on another tab.
  const tabParam = searchParams.get("tab")
  useEffect(() => { if (tabParam) setTab(tabParam) }, [tabParam])

  const [settings, setSettings] = useState<EggSortingSettings | null>(null)
  const [classes, setClasses] = useState<EggClass[]>([])
  const [summary, setSummary] = useState<EggSortingSummary | null>(null)
  const [picks, setPicks] = useState<EggSortingPick[] | null>(null)
  // Every record with eggs left, to see which of them the Unsorted shelf can
  // still cover (eggs sold unsorted are not sortable).
  const [openPicks, setOpenPicks] = useState<EggSortingPick[] | null>(null)
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
        recordParam ? getEggSortingPicks({ recordIds: [recordParam] }) : getEggSortingPicks({ fromDate: from || undefined, toDate: to || undefined }),
        getEggSortingSummary(),
        getProductionDuplicates().catch(() => [] as ProductionDuplicateGroup[]),
      ])
      const open = sm.recordsWithLeft > 0 && sm.oldestLeftDate
        ? await getEggSortingPicks({ fromDate: sm.oldestLeftDate.slice(0, 10), toDate: sm.businessDate.slice(0, 10) }).catch(() => null)
        : []
      setPicks(p)
      setSummary(sm)
      setOpenPicks(open)
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
        fromDate: from ? shiftBusinessDate(from, -30) ?? from : undefined, toDate: today,
        status: sessionStatus === "all" ? undefined : sessionStatus,
      }))
    } catch (e) {
      toast({ title: "Could not load sortings", description: e instanceof Error ? e.message : "", variant: "destructive" })
    }
  }, [from, today, sessionStatus, toast])

  useEffect(() => { if (activeFarmId) void loadSetup() }, [activeFarmId, loadSetup])
  useEffect(() => { if (activeFarmId) void load() }, [activeFarmId, load])
  useEffect(() => { if (tab === "sessions" && activeFarmId) void loadSessions() }, [tab, activeFarmId, loadSessions])

  // Production left, cut down to what Unsorted stock can still give: eggs
  // sold or used unsorted are not shown as waiting to be sorted.
  const sortable = useMemo(
    () => (openPicks && summary ? sortableByRecord(groupProductionDays(openPicks), summary.unsortedOnHand) : new Map<number, number>()),
    [openPicks, summary])
  const days = useMemo(
    () => groupProductionDays(picks ?? []).map((d) => capToSortable(d, sortable.get(d.productionRecordId))),
    [picks, sortable])
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

  // "All flocks": one section per flock instead of every flock's days mixed
  // by date. Days are ordered flock by flock (newest day first inside each),
  // then paged as before; a section split across pages says "continued".
  const groupByFlock = flockFilter === "all" && !recordParam
  const orderedDays = useMemo(() => (groupByFlock
    ? [...shownDays].sort((a, b) =>
        a.flockName.localeCompare(b.flockName) || a.flockId - b.flockId || b.productionDate.localeCompare(a.productionDate))
    : shownDays), [shownDays, groupByFlock])
  const flockTotals = useMemo(() => {
    const m = new Map<number, { days: number; saleable: number; sorted: number; left: number; firstRecordId: number }>()
    for (const d of orderedDays) {
      const t = m.get(d.flockId)
      if (t) { t.days += 1; t.saleable += d.saleable; t.sorted += d.sorted; t.left += d.left }
      else m.set(d.flockId, { days: 1, saleable: d.saleable, sorted: d.sorted, left: d.left, firstRecordId: d.productionRecordId })
    }
    return m
  }, [orderedDays])
  const flockAccent = (flockId: number) => {
    const i = flocks.findIndex(([id]) => id === flockId)
    return FLOCK_ACCENTS[(i < 0 ? 0 : i) % FLOCK_ACCENTS.length]
  }

  const sizes = useMemo(() => classes.filter((c) => c.classKind === "Size"), [classes])
  // Paged like every other list page (hooks/use-pagination + DataPagination).
  const daysPg = usePagination(orderedDays, 5)
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

  const renderDay = (d: ProductionDay, grouped: boolean) => {
    const progress = d.saleable > 0 ? Math.min(100, (d.sorted / d.saleable) * 100) : 0
    return (
      <Card key={d.productionRecordId} className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="space-y-3 p-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div className="text-base font-semibold text-slate-900">
                {grouped ? formatLongDate(d.productionDate) : `${d.flockName} — ${formatLongDate(d.productionDate)}`}
              </div>
              <div className="text-xs text-slate-500">
                {[d.batchName, d.houseName].filter(Boolean).join(" · ") || " "}
              </div>
            </div>
            <div className="grid w-full grid-cols-2 gap-2 sm:flex sm:w-auto">
              <Button size="sm" variant="outline" asChild>
                <Link href={`/production-records/${d.productionRecordId}?returnTo=${encodeURIComponent(returnHere)}`}>View production</Link>
              </Button>
              <Button size="sm" disabled={!canSort || !sortingOn || d.left <= 0} onClick={() => sortAll(d)}
                className="bg-emerald-600 text-white hover:bg-emerald-700">
                <Layers className="mr-1.5 h-4 w-4" />
                <span className="sm:hidden">Sort all</span>
                <span className="hidden sm:inline">Sort all available eggs</span>
              </Button>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Stat label="Production (saleable)" value={fmtCount(d.saleable)}
              sub={d.collectionLoss ? `${fmtCount(d.gross)} collected, ${fmtCount(d.collectionLoss)} broken/lost` : cratesText(d.saleable)} />
            <Stat label="Sorted" value={fmtCount(d.sorted)} />
            <Stat label="Can be sorted" value={fmtCount(d.left)} tone={d.left > 0 ? "warn" : "good"}
              sub={d.soldUnsorted ? `${fmtCount(d.soldUnsorted)} sold unsorted` : undefined} />
            <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
              <div className="flex items-center justify-between text-[11px] uppercase tracking-wide text-slate-500">
                Progress <StatusChip status={d.status} sold={!!d.soldUnsorted && d.left <= 0 && d.sorted <= 0} />
              </div>
              <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-slate-100">
                <div className={cn("h-full", d.left <= 0 ? "bg-emerald-500" : "bg-amber-500")} style={{ width: `${progress}%` }} />
              </div>
              <div className="mt-0.5 text-[11px] text-slate-500">{progress.toFixed(1)}%</div>
            </div>
          </div>

          {/* Phone: one compact block per pick instead of a six-column table. */}
          <div className="divide-y divide-slate-100 rounded-lg border border-slate-200 sm:hidden">
            {d.picks.map((p) => {
              const left = pickRemaining(p)
              return (
                <div key={p.pickNumber} className="space-y-2 p-3">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium text-slate-900">{pickLabel(p.pickNumber, labels)}</span>
                    <StatusChip status={pickStatus(p)} sold={!!d.soldUnsorted && left <= 0 && p.pickLeft > 0} />
                  </div>
                  <div className="grid grid-cols-3 gap-2 text-center text-xs">
                    <div><div className="text-slate-500">Collected</div><div className="font-semibold tabular-nums text-slate-900">{fmtCount(p.pickGross)}</div></div>
                    <div><div className="text-slate-500">Sorted</div><div className="font-semibold tabular-nums text-slate-900">{fmtCount(p.pickSorted)}</div></div>
                    <div><div className="text-slate-500">Can sort</div><div className={cn("font-semibold tabular-nums", left > 0 ? "text-amber-700" : "text-emerald-700")}>{fmtCount(left)}</div></div>
                  </div>
                  <Button size="sm" variant="outline" className="w-full" disabled={!canSort || !sortingOn || left <= 0}
                    onClick={() => setTarget({ mode: "ByPick", day: d, pick: p })}>
                    {p.pickSorted > 0 && left > 0 ? "Continue sorting" : "Sort pick"}
                  </Button>
                </div>
              )
            })}
          </div>
          <div className="hidden overflow-x-auto sm:block">
            <table className="w-full min-w-[36rem] text-sm">
              <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                <tr>
                  <th className="px-3 py-2 font-medium">Pick</th>
                  <th className="px-3 py-2 text-right font-medium">Collected</th>
                  <th className="px-3 py-2 text-right font-medium">Sorted</th>
                  <th className="px-3 py-2 text-right font-medium">Can be sorted</th>
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
                      <td className="px-3 py-2"><StatusChip status={pickStatus(p)} sold={!!d.soldUnsorted && left <= 0 && p.pickLeft > 0} /></td>
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
          {!!d.soldUnsorted && (
            <p className="text-xs text-slate-500">
              {fmtCount(d.soldUnsorted)} of this day&apos;s eggs were sold or used unsorted, so they cannot be sorted.
              Sold eggs are counted from the oldest days first.
            </p>
          )}
          {d.collectionLoss > 0 && (
            <p className="text-xs text-slate-500">
              Broken, meaty, soft and lost eggs are recorded for the whole day, not per pick, so the day can be sorted up to its {fmtCount(d.saleable)} saleable eggs.
            </p>
          )}
        </CardContent>
      </Card>
    )
  }

  // What a sorting graded, where its eggs came from and its history: under
  // its row in the table, and inside its card on a phone.
  const sessionDetail = (s: EggSortingSession) => (
    <>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
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
    </>
  )

  // The current page, cut into runs of one flock each.
  const pageRuns = (() => {
    const runs: { flockId: number; days: ProductionDay[] }[] = []
    for (const d of daysPg.pageItems) {
      const last = runs[runs.length - 1]
      if (last && last.flockId === d.flockId) last.days.push(d)
      else runs.push({ flockId: d.flockId, days: [d] })
    }
    return runs
  })()

  const unsortedClass = classes.find((c) => c.classKind === "Unsorted")
  // Where "View production" comes back to: this page, on the same record.
  const returnHere = recordParam ? `/poultry-egg-sorting?record=${recordParam}` : "/poultry-egg-sorting"
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
                  <h1 className="text-xl font-bold text-slate-900 sm:text-2xl">Egg Sorting</h1>
                  <p className="text-sm text-slate-600">
                    Sort collected eggs into sizes — one pick at a time, or everything at once. Sorting never creates eggs:
                    it moves them from Unsorted into sizes, and records what was lost.
                  </p>
                </div>
              </div>
              <div className="grid w-full grid-cols-2 gap-2 sm:flex sm:w-auto">
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
              {/* Phone: a 2 x 2 grid, so every tab is visible without scrolling. */}
              <TabsList className="grid h-auto w-full grid-cols-2 gap-2 rounded-xl border border-slate-200 bg-slate-100 p-1.5 sm:inline-flex sm:w-auto">
                <TabsTrigger value="workspace" className={cn(TAB_BASE, TAB_STYLE.workspace)}><Egg className="h-4 w-4" /> Workspace</TabsTrigger>
                <TabsTrigger value="sessions" className={cn(TAB_BASE, TAB_STYLE.sessions)}><History className="h-4 w-4" /> Sortings</TabsTrigger>
                <TabsTrigger value="reports" className={cn(TAB_BASE, TAB_STYLE.reports)}><BarChart3 className="h-4 w-4" /> Size reports</TabsTrigger>
                <TabsTrigger value="settings" className={cn(TAB_BASE, TAB_STYLE.settings)}><Settings2 className="h-4 w-4" /> Sizes &amp; settings</TabsTrigger>
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
                    <CardContent className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 lg:grid-cols-6">
                      <div className="space-y-1">
                        <Label className="text-xs text-slate-500">Month</Label>
                        <Select value={month} onValueChange={pickMonth}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="all">All months</SelectItem>
                            {month === "custom" && <SelectItem value="custom">Custom dates</SelectItem>}
                            {monthOptions.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs text-slate-500">Production from</Label>
                        <Input type="date" value={from} max={to || today} onChange={(e) => { setFrom(toBusinessDate(e.target.value) ? e.target.value : ""); setMonth("custom") }} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs text-slate-500">Production to</Label>
                        <Input type="date" value={to} min={from || undefined} max={today} onChange={(e) => { setTo(toBusinessDate(e.target.value) ? e.target.value : ""); setMonth("custom") }} />
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
                            <SelectItem value="open">Can be sorted</SelectItem>
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
                        : statusFilter === "open"
                          ? "Nothing left to sort here — every egg was sorted, or sold before it could be. Set Status to All to see these days."
                          : "Nothing matches these filters."}
                    </CardContent>
                  </Card>
                )}

                {groupByFlock
                  ? pageRuns.map((run) => {
                      const first = run.days[0]
                      const t = flockTotals.get(run.flockId)
                      const accent = flockAccent(run.flockId)
                      const continued = t ? t.firstRecordId !== first.productionRecordId : false
                      return (
                        <section key={`${run.flockId}-${first.productionRecordId}`}
                          className={cn("overflow-hidden rounded-xl border border-l-4 border-slate-200 bg-slate-100/70", accent.edge)}>
                          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-white px-4 py-3">
                            <div className="flex min-w-0 items-center gap-2.5">
                              <span className={cn("h-3 w-3 shrink-0 rounded-full", accent.dot)} aria-hidden />
                              <div className="min-w-0">
                                <h2 className="truncate text-lg font-bold text-slate-900">
                                  {first.flockName}
                                  {continued && <span className="ml-2 text-xs font-normal text-slate-500">(continued)</span>}
                                </h2>
                                <div className="text-xs text-slate-500">
                                  {[first.batchName, first.houseName].filter(Boolean).join(" · ") || "Flock"}
                                </div>
                              </div>
                            </div>
                            {t && (
                              <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600">
                                <span><b className="tabular-nums text-slate-900">{t.days}</b> day{t.days === 1 ? "" : "s"}</span>
                                <span>Sorted <b className="tabular-nums text-slate-900">{fmtCount(t.sorted)}</b> of {fmtCount(t.saleable)}</span>
                                <span className={t.left > 0 ? "text-amber-700" : "text-emerald-700"}>
                                  {t.left > 0 ? <>Remaining <b className="tabular-nums">{fmtCount(t.left)}</b></> : "All sorted"}
                                </span>
                              </div>
                            )}
                          </div>
                          <div className="space-y-3 p-2 sm:p-3">
                            {run.days.map((d) => renderDay(d, true))}
                          </div>
                        </section>
                      )
                    })
                  : daysPg.pageItems.map((d) => renderDay(d, false))}
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
                  <p className="pb-2 text-xs text-slate-500">{from ? <>Last 30 days before {formatLongDate(from)} to today.</> : "All sortings."}</p>
                </div>
                {!sessions && <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>}
                {sessions && sessions.length === 0 && <p className="text-sm text-slate-500">No sortings yet.</p>}
                {sessions && sessions.length > 0 && (
                  <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                    <CardContent className="p-0">
                      {/* Phone: one card per sorting; tap it to see the grading. */}
                      <div className="divide-y divide-slate-100 sm:hidden">
                        {sessionsPg.pageItems.map((s) => {
                          const open = openSession === s.sessionId
                          return (
                            <div key={s.sessionId} className={cn("space-y-2 p-3", s.status === "Reversed" && "text-slate-500")}>
                              <button type="button" className="flex w-full items-start justify-between gap-2 text-left"
                                aria-expanded={open} onClick={() => setOpenSession(open ? null : s.sessionId)}>
                                <span className="min-w-0">
                                  <span className="flex items-center gap-1 font-medium text-slate-900">
                                    {open ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />} {s.sessionNo}
                                  </span>
                                  <span className="block truncate text-xs text-slate-500">
                                    {s.flockName ?? `Flock ${s.flockId}`} · sorted {formatLongDate(s.sortingDate.slice(0, 10))}
                                  </span>
                                  <span className="block text-xs text-slate-500">
                                    {s.sortingMode === "ByPick" ? pickLabel(s.pickNumber ?? 0, labels).split(" (")[0] : "All available"}
                                  </span>
                                </span>
                                <span className={cn("shrink-0 rounded px-1.5 py-0.5 text-[11px] font-medium",
                                  s.status === "Posted" ? "bg-emerald-100 text-emerald-800" : s.status === "Draft" ? "bg-sky-100 text-sky-800" : "bg-slate-200 text-slate-700")}>
                                  {s.status}
                                </span>
                              </button>
                              <div className="grid grid-cols-3 gap-2 text-center text-xs">
                                <div><div className="text-slate-500">Sorted</div><div className="font-semibold tabular-nums">{fmtCount(s.inputQuantity)}</div></div>
                                <div><div className="text-slate-500">Into sizes</div><div className="font-semibold tabular-nums">{fmtCount(s.outputQuantity)}</div></div>
                                <div><div className="text-slate-500">Loss</div><div className="font-semibold tabular-nums">{fmtCount(s.lossQuantity)}</div></div>
                              </div>
                              {s.status === "Draft" && (
                                <div className="grid grid-cols-2 gap-2">
                                  <Button size="sm" variant="outline" disabled={!canSort} onClick={() => void editDraft(s)}><Pencil className="mr-1 h-3.5 w-3.5" /> Open</Button>
                                  <Button size="sm" variant="outline" className="text-rose-700" disabled={!canRemove} onClick={() => void discard(s)}><Trash2 className="mr-1 h-3.5 w-3.5" /> Discard</Button>
                                </div>
                              )}
                              {s.status === "Posted" && (
                                <Button size="sm" variant="outline" className="w-full text-rose-700" disabled={!canRemove} onClick={() => setReverseTarget(s)}>
                                  <RotateCcw className="mr-1 h-3.5 w-3.5" /> Reverse
                                </Button>
                              )}
                              {open && <div className="rounded-md bg-slate-50 p-2">{sessionDetail(s)}</div>}
                            </div>
                          )
                        })}
                      </div>
                      <div className="hidden overflow-x-auto sm:block">
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
                                      <td colSpan={9} className="px-3 py-3">{sessionDetail(s)}</td>
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
                  <CompositionReport from={shiftBusinessDate(today, -29) ?? today} to={today}
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
        options={STOCK_REVERSAL_REASONS}
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

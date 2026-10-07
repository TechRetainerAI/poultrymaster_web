"use client"

// Today's Farm Completeness — the Missing Activity Detector on the poultry
// dashboard (migration 332).
//
// Everything shown is DERIVED by the Farm API from records that already exist;
// this card owns no state beyond the last response. Recording the missing
// production is the only way to clear it, which is the point.
//
// Permission: the card renders whatever checks the API returns. The API gates
// each check on its own permission and follows Iam:Enforced, so the server is
// the one owner of "may this user see it" — a 403 simply hides the card. A
// client-side can() gate here would disagree with the production pages, which
// the nav shows to everyone in the legacy era.
//
// Dates: report.businessDate is the company's day, from the server. The browser
// clock is never consulted.

import { Fragment, useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { AlertTriangle, CheckCircle2, ChevronDown, ChevronUp, ClipboardCheck, Loader2, RefreshCw } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { FlockMissingDateRows } from "@/components/dashboard/flock-missing-dates"
import { MissingByDateTable } from "@/components/dashboard/missing-by-date"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import {
  ActivityChecksForbiddenError,
  getActivityChecks,
  getMissingProductionByDate,
  type ActivityCompletenessReport,
  type MissingProductionEntry,
} from "@/lib/api/activity-checks"
import {
  PRODUCTION_CHECK_KEY,
  completeMissingProductionHref,
  completenessHeadline,
  earlierGapActionHref,
  findCheck,
  flocksWithEarlierGaps,
  formatDaysOutstanding,
  formatShortDate,
  itemActionHref,
  itemActionLabel,
  severityStyle,
  toBusinessDate,
} from "@/lib/activity/completeness"

type LoadState =
  | { kind: "loading" }
  | { kind: "hidden" }
  | { kind: "error"; message: string }
  | { kind: "ready"; report: ActivityCompletenessReport }

export interface FarmCompletenessCardProps {
  /** "yyyy-MM-dd". Omitted means the company's today, decided by the server. */
  businessDate?: string
  /** Open the missing-flock table straight away (the Tools page does). */
  defaultExpanded?: boolean
  /**
   * The dashboard's version: the headline only -- no refresh button, no
   * missing-flock table -- and "Complete Missing Production" goes to the Tools
   * page (/poultry-farm-completeness), which has the full list and its own
   * route into Batch Production Entry. It still re-reads when the tab regains
   * focus.
   */
  compact?: boolean
}

export function FarmCompletenessCard({
  businessDate: requestedDate, defaultExpanded = false, compact = false,
}: FarmCompletenessCardProps = {}) {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const [state, setState] = useState<LoadState>({ kind: "loading" })
  const [refreshing, setRefreshing] = useState(false)
  const [expanded, setExpanded] = useState(defaultExpanded)
  // By flock: one row per flock (one flock behind by several days -> step
  // through the form). By date: one row per day (many flocks missing the same
  // day -> one Batch Production Entry).
  const [view, setView] = useState<"flock" | "date">("flock")
  // Flocks that reported on the business date but have EARLIER missing days.
  // The check's items are only the flocks missing on that one day, so without
  // this the By flock list would be empty exactly when the backlog is the
  // problem. Loaded only when there is a backlog and the table can show.
  const [earlier, setEarlier] = useState<MissingProductionEntry[] | null>(null)
  const readyReport = state.kind === "ready" ? state.report : null
  const reportDate = readyReport ? toBusinessDate(readyReport.businessDate) : null
  const reportBacklog = readyReport
    ? (findCheck(readyReport, PRODUCTION_CHECK_KEY)?.counters?.backlogDates ?? 0)
    : 0
  useEffect(() => {
    if (compact || !reportDate || reportBacklog === 0) { setEarlier(null); return }
    let cancelled = false
    getMissingProductionByDate(reportDate, 30)
      .then((d) => { if (!cancelled) setEarlier(d.entries) })
      .catch(() => { if (!cancelled) setEarlier([]) })
    return () => { cancelled = true }
  }, [compact, reportDate, reportBacklog])
  // Rows whose missing-days dropdown is open.
  const [openRows, setOpenRows] = useState<Set<string>>(() => new Set())
  const toggleRow = (key: string) =>
    setOpenRows((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })

  const load = useCallback(async (quiet: boolean) => {
    if (quiet) setRefreshing(true)
    try {
      const report = await getActivityChecks(requestedDate)
      setState({ kind: "ready", report })
    } catch (e) {
      if (e instanceof ActivityChecksForbiddenError) setState({ kind: "hidden" })
      // A failed background refresh keeps what is on screen.
      else if (!quiet) setState({ kind: "error", message: e instanceof Error ? e.message : "Could not load." })
    } finally {
      if (quiet) setRefreshing(false)
    }
  }, [requestedDate])

  // Re-read on company switch, and when the tab regains focus — the farmer has
  // usually just been off recording production, and the card should agree.
  useEffect(() => {
    if (!activeFarmId) return
    setState({ kind: "loading" })
    setExpanded(defaultExpanded)
    setOpenRows(new Set())
    void load(false)
    const onVisible = () => {
      if (document.visibilityState === "visible") void load(true)
    }
    document.addEventListener("visibilitychange", onVisible)
    return () => document.removeEventListener("visibilitychange", onVisible)
  }, [activeFarmId, load, defaultExpanded])

  if (!activeFarmId || state.kind === "hidden") return null

  if (state.kind === "loading") {
    return (
      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="flex items-center gap-2 p-4 text-sm text-slate-500">
          <Loader2 className="h-4 w-4 animate-spin" /> Checking today&apos;s farm activity…
        </CardContent>
      </Card>
    )
  }

  if (state.kind === "error") {
    return (
      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="flex flex-wrap items-center justify-between gap-2 p-4 text-sm text-slate-500">
          <span>Farm completeness is unavailable right now.</span>
          <Button variant="outline" size="sm" className="gap-1.5" onClick={() => { setState({ kind: "loading" }); void load(false) }}>
            <RefreshCw className="h-3.5 w-3.5" /> Retry
          </Button>
        </CardContent>
      </Card>
    )
  }

  const { report } = state
  const production = findCheck(report, PRODUCTION_CHECK_KEY)
  // 344: shown only when the farm sorts and earlier days' eggs are waiting.
  const unsorted = findCheck(report, "poultry.eggs.unsorted")
  // Not a poultry company, or no check it may see: nothing to say.
  if (!production) return null

  const businessDate = toBusinessDate(report.businessDate) ?? ""
  const isToday = businessDate === toBusinessDate(report.companyToday)
  const title = isToday ? "Today's Farm Completeness" : `Farm Completeness — ${formatShortDate(businessDate)}`
  const style = severityStyle(production.severity)
  const missing = production.outstandingCount
  const awaitingPosting = production.counters?.awaitingPosting ?? 0
  const duplicateFlocks = production.counters?.duplicateFlocks ?? 0
  // Earlier days still missing. The headline is ONE day; without these, filling
  // today's gap read as "all recorded" while last week was still empty.
  const backlogDates = production.counters?.backlogDates ?? 0
  const backlogFlockDays = production.counters?.backlogFlockDays ?? 0
  const hasWork = missing > 0 || backlogDates > 0
  const completeHref = compact
    ? (hasWork ? "/poultry-farm-completeness" : null)
    : completeMissingProductionHref(businessDate, production)
  const effectiveView = view
  const earlierFlocks = earlier ? flocksWithEarlierGaps(earlier, production.items.map((i) => i.subjectId)) : []
  const notApplicable = production.status === "NotApplicable"

  return (
    <Card className={cn("rounded-xl border border-l-4 border-slate-200 bg-white shadow-sm", style.accent)}>
      <CardContent className="p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex min-w-0 items-start gap-3">
            <div
              className={cn(
                "flex h-10 w-10 shrink-0 items-center justify-center rounded-lg",
                hasWork ? "bg-amber-500" : "bg-emerald-500",
              )}
            >
              {hasWork
                ? <AlertTriangle className="h-5 w-5 text-white" />
                : <ClipboardCheck className="h-5 w-5 text-white" />}
            </div>
            <div className="min-w-0">
              <p className="text-xs font-medium uppercase tracking-wider text-slate-500">{title}</p>
              {notApplicable ? (
                <p className="mt-1 text-sm text-slate-600">No active flocks are expected to report production.</p>
              ) : (
                <>
                  <div className="mt-1 flex flex-wrap items-baseline gap-x-4 gap-y-1">
                    {/* Which day the count is for, so "4 / 4" is never read as
                        "everything is done" while earlier days are empty. */}
                    <p className="text-sm text-slate-600">
                      {isToday ? "Today" : formatShortDate(businessDate)}:{" "}
                      <span className="text-lg font-bold tabular-nums text-slate-900">
                        {completenessHeadline(production)}
                      </span>
                    </p>
                    {missing > 0 && (
                      <p className="text-sm text-slate-600">
                        Missing: <span className="font-semibold tabular-nums text-slate-900">{missing}</span>
                      </p>
                    )}
                    {backlogFlockDays > 0 && (
                      <p className="text-sm text-slate-600">
                        Earlier:{" "}
                        <span className="font-semibold tabular-nums text-rose-700">{backlogFlockDays} missing</span>
                      </p>
                    )}
                    <span className={cn("rounded-full border px-2 py-0.5 text-xs font-medium", style.badge)}>
                      {style.label}
                    </span>
                  </div>
                  {missing === 0 && backlogDates === 0 ? (
                    <p className="mt-1 flex items-center gap-1.5 text-sm text-emerald-700">
                      <CheckCircle2 className="h-4 w-4" /> All expected flock production has been recorded.
                    </p>
                  ) : backlogDates > 0 ? (
                    // One sentence when earlier days are missing -- the reason
                    // line would only repeat it in vaguer words.
                    <p className="mt-1 text-sm font-medium text-rose-700">
                      {missing === 0 ? `${isToday ? "Today" : "This day"} is complete, but ` : "Also missing: "}
                      {backlogFlockDays} production record{backlogFlockDays === 1 ? "" : "s"}
                      {missing === 0 ? (backlogFlockDays === 1 ? " is" : " are") + " still missing" : ""} across{" "}
                      {backlogDates} earlier day{backlogDates === 1 ? "" : "s"}.
                    </p>
                  ) : (
                    production.severityReason && (
                      <p className="mt-1 text-xs text-slate-500">{production.severityReason}</p>
                    )
                  )}
                  {awaitingPosting > 0 && (
                    <p className="mt-1 text-xs text-slate-500">
                      {awaitingPosting} of these {awaitingPosting === 1 ? "is" : "are"} in a batch production entry
                      that has not been posted yet.
                    </p>
                  )}
                  {duplicateFlocks > 0 && (
                    <p className="mt-1 text-xs text-amber-700">
                      {duplicateFlocks} flock{duplicateFlocks === 1 ? " has" : "s have"} more than one production
                      record for this day.
                    </p>
                  )}
                  {unsorted && unsorted.outstandingCount > 0 && (
                    // Egg sorting (344): earlier days' eggs still unsorted.
                    <p className="mt-1 text-xs text-amber-700">
                      {unsorted.severityReason ?? `${(unsorted.counters?.eggs ?? 0).toLocaleString()} eggs from earlier days are still unsorted.`}{" "}
                      <Link href="/poultry-egg-sorting" className="font-medium underline">Sort eggs</Link>
                    </p>
                  )}
                </>
              )}
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {!compact && (
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 text-slate-500"
                aria-label="Refresh farm completeness"
                onClick={() => void load(true)}
                disabled={refreshing}
              >
                <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
              </Button>
            )}
            {!compact && hasWork && (
              <Button
                variant="outline"
                size="sm"
                className="gap-1"
                aria-expanded={expanded}
                aria-controls="farm-completeness-missing"
                onClick={() => setExpanded((v) => !v)}
              >
                {expanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                {expanded ? "Hide" : "Show"} missing
              </Button>
            )}
            {completeHref && (
              <Button asChild size="sm" className="bg-amber-600 text-white hover:bg-amber-700">
                <Link href={completeHref}>
                  {/* Batch entry is one day at a time: say which day this one is. */}
                  {!compact && backlogDates > 0 ? `Complete ${isToday ? "Today's" : "This Day's"} Production` : "Complete Missing Production"}
                </Link>
              </Button>
            )}
          </div>
        </div>

        {!compact && expanded && hasWork && (
          <div className="mt-4 space-y-2">
          <div className="inline-flex rounded-md border border-slate-200 bg-slate-50 p-0.5 text-sm" role="tablist">
            {(["flock", "date"] as const).map((v) => (
              <button
                key={v}
                type="button"
                role="tab"
                aria-selected={effectiveView === v}
                className={cn(
                  "rounded px-3 py-1",
                  effectiveView === v ? "bg-white font-medium text-slate-900 shadow-sm" : "text-slate-600 hover:text-slate-900",
                )}
                onClick={() => setView(v)}
              >
                {v === "flock" ? "By flock" : "By date"}
              </button>
            ))}
          </div>
          {effectiveView === "date" ? (
            <MissingByDateTable businessDate={businessDate} />
          ) : (
          <div id="farm-completeness-missing" className="overflow-x-auto rounded-lg border border-slate-200">
            <table className="w-full min-w-[36rem] text-sm">
              <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                <tr>
                  <th className="px-3 py-2 font-medium">Flock</th>
                  <th className="px-3 py-2 font-medium">Batch</th>
                  <th className="px-3 py-2 font-medium">House/Pen</th>
                  <th className="px-3 py-2 font-medium">Last Production</th>
                  <th className="px-3 py-2 font-medium">Days Missing</th>
                  <th className="px-3 py-2 text-right font-medium">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {production.items.map((i) => {
                  const rowStyle = severityStyle(i.severity)
                  const rowKey = `${i.subjectType}-${i.subjectId}`
                  const rowOpen = openRows.has(rowKey)
                  return (
                    <Fragment key={rowKey}>
                    {/* Click anywhere on the flock to open its missing days.
                        The Record link stops the click so it only navigates. */}
                    <tr
                      className={cn("cursor-pointer hover:bg-slate-50", rowOpen && "bg-slate-50")}
                      role="button"
                      tabIndex={0}
                      aria-expanded={rowOpen}
                      aria-label={`${rowOpen ? "Hide" : "Show"} missing days for ${i.label}`}
                      onClick={() => toggleRow(rowKey)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggleRow(rowKey) }
                      }}
                    >
                      <td className="px-3 py-2 font-medium text-slate-900">
                        <span className="mr-1.5 inline-flex h-5 w-5 items-center justify-center align-middle text-slate-500">
                          {rowOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                        </span>
                        {i.label}
                        {i.state === "AwaitingPosting" && (
                          <span className="ml-2 rounded bg-sky-50 px-1.5 py-0.5 text-[11px] font-normal text-sky-700">
                            awaiting posting
                          </span>
                        )}
                      </td>
                      <td className="px-3 py-2 text-slate-600">{i.groupLabel ?? "—"}</td>
                      <td className="px-3 py-2 text-slate-600">{i.locationLabel ?? "—"}</td>
                      <td className="px-3 py-2 text-slate-600">
                        {i.lastCompletedDate ? formatShortDate(i.lastCompletedDate) : "Never"}
                      </td>
                      <td className="px-3 py-2">
                        <span className={cn("rounded-full border px-2 py-0.5 text-xs tabular-nums", rowStyle.badge)}>
                          {formatDaysOutstanding(i.daysOutstanding)}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-right">
                        <Button asChild size="sm" variant="outline" className="h-7 px-2.5 text-xs">
                          <Link href={itemActionHref(i, businessDate)} onClick={(e) => e.stopPropagation()}>
                            {itemActionLabel(i)}
                          </Link>
                        </Button>
                      </td>
                    </tr>
                    {rowOpen && <FlockMissingDateRows flockId={i.subjectId} businessDate={businessDate} />}
                    </Fragment>
                  )
                })}
                {/* Flocks complete on this day with EARLIER missing days. */}
                {backlogDates > 0 && earlier == null && (
                  <tr><td colSpan={6} className="px-3 py-2 text-xs text-slate-500">
                    <span className="inline-flex items-center gap-1.5"><Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading flocks with earlier missing days…</span>
                  </td></tr>
                )}
                {earlierFlocks.length > 0 && missing > 0 && (
                  <tr className="bg-slate-50"><td colSpan={6} className="px-3 py-1.5 text-xs font-medium uppercase tracking-wider text-slate-500">
                    Earlier days missing
                  </td></tr>
                )}
                {earlierFlocks.map((f) => {
                  const rowKey = `earlier-${f.flockId}`
                  const rowOpen = openRows.has(rowKey)
                  return (
                    <Fragment key={rowKey}>
                    <tr
                      className={cn("cursor-pointer hover:bg-slate-50", rowOpen && "bg-slate-50")}
                      role="button"
                      tabIndex={0}
                      aria-expanded={rowOpen}
                      aria-label={`${rowOpen ? "Hide" : "Show"} missing days for ${f.flockName}`}
                      onClick={() => toggleRow(rowKey)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggleRow(rowKey) }
                      }}
                    >
                      <td className="px-3 py-2 font-medium text-slate-900">
                        <span className="mr-1.5 inline-flex h-5 w-5 items-center justify-center align-middle text-slate-500">
                          {rowOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                        </span>
                        {f.flockName}
                      </td>
                      <td className="px-3 py-2 text-slate-600">{f.batchName ?? "—"}</td>
                      <td className="px-3 py-2 text-slate-600">{f.houseName ?? "—"}</td>
                      {/* Not in today's missing list, so it reported on this day. */}
                      <td className="px-3 py-2 text-slate-600">{formatShortDate(businessDate)}</td>
                      <td className="px-3 py-2">
                        <span className={cn("rounded-full border px-2 py-0.5 text-xs tabular-nums", severityStyle("Critical").badge)}>
                          {formatDaysOutstanding(f.missingDays)} earlier
                        </span>
                      </td>
                      <td className="px-3 py-2 text-right">
                        <Button asChild size="sm" variant="outline" className="h-7 px-2.5 text-xs">
                          <Link href={earlierGapActionHref(f, businessDate)} onClick={(e) => e.stopPropagation()}>
                            {f.missingDays > 1 ? `Record ${f.missingDays} days` : "Record"}
                          </Link>
                        </Button>
                      </td>
                    </tr>
                    {rowOpen && <FlockMissingDateRows flockId={f.flockId} businessDate={businessDate} />}
                    </Fragment>
                  )
                })}
              </tbody>
            </table>
          </div>
          )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

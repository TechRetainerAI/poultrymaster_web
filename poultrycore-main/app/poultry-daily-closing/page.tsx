"use client"

// Poultry Daily Closing — "Is today's farm activity complete, internally
// consistent, and ready to be closed?" (migration 333).
//
// One business date at a time: every section, the closing checklist, and
// Close Business Day. A closed day shows its State At Closing (the snapshot the
// close stored) and, if records changed afterwards, what moved. History lists
// previous closings with their figures as closed.
//
// This replaced the list-of-closings page. The Draft -> Submitted -> Approved
// workflow is still here: a user without the close right submits the day, and
// someone with it closes (approves) it through the same guarded close.
//
// The date is the COMPANY's business date (useBusinessDate / the server), never
// the browser's. ?date=yyyy-MM-dd opens a specific day.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import {
  CalendarCheck, ChevronLeft, ChevronRight, Loader2, Lock, LockOpen, RefreshCw, Send, Settings2, XCircle,
} from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useBusinessDate } from "@/hooks/use-business-date"
import { useCompanyDateTime } from "@/hooks/use-company-datetime"
import { useFmt } from "@/lib/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import {
  CloseDayConflictError,
  closeBusinessDay,
  getClosingDay,
  getClosingEventSnapshot,
  getClosingHistory,
  getClosingPolicy,
  reopenBusinessDay,
  saveClosingPolicy,
  type ClosingDayView,
  type ClosingEvent,
  type ClosingHistoryRow,
  type ClosingPolicy,
  type ClosingWorkspace,
} from "@/lib/api/poultry-daily-closing"
import {
  createPoultryDailyClosing,
  rejectPoultryDailyClosing,
  submitPoultryDailyClosing,
} from "@/lib/api/poultry-inventory"
import { shiftBusinessDate, toBusinessDate } from "@/lib/activity/completeness"
import {
  closeReadiness,
  closingStatusLabel,
  diffClosingState,
  formatLongDate,
} from "@/lib/closing/daily-closing"
import {
  ChangesSinceClosing, ClosedSummary, ClosingChecklist, ClosingSections, ClosingTimeline,
} from "@/components/closing/daily-closing-parts"
import { CloseDayDialog, ClosingPolicyDialog, ReasonDialog } from "@/components/closing/daily-closing-dialogs"

const CLOSE_RIGHT = "poultry.daily-closing.approve"

function PoultryDailyClosingInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()
  const { fmtInstant } = useCompanyDateTime()
  const { businessDate: today } = useBusinessDate()
  const { can } = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  // The close right. The API checks it too (under Iam:Enforced); this only
  // decides which buttons to offer. Without it, the day can be submitted.
  const mayClose = can(CLOSE_RIGHT)

  // null = the company's today, decided by the server.
  // The URL is the one source for the day shown. Links to this same page
  // ("Sep 22 is not closed" -> Review) only change ?date= without reloading,
  // so reading it once into state ignored them until a refresh. Changing the
  // day writes the URL back, which also makes Back and refresh keep the day.
  const picked = toBusinessDate(searchParams.get("date"))
  const setPicked = useCallback((d: string | null) => {
    router.replace(d ? `/poultry-daily-closing?date=${d}` : "/poultry-daily-closing", { scroll: false })
  }, [router])
  const [tab, setTab] = useState("day")
  const [view, setView] = useState<ClosingDayView | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [showAtClose, setShowAtClose] = useState(true)
  const [closeOpen, setCloseOpen] = useState(false)
  const [reopenOpen, setReopenOpen] = useState(false)
  const [rejectOpen, setRejectOpen] = useState(false)
  const [policyOpen, setPolicyOpen] = useState(false)
  const [policy, setPolicy] = useState<ClosingPolicy | null>(null)
  const [history, setHistory] = useState<ClosingHistoryRow[] | null>(null)
  const [snapshot, setSnapshot] = useState<{ event: ClosingEvent; ws: ClosingWorkspace } | null>(null)
  const pg = usePagination(history ?? [])

  const requested = picked && picked !== today ? picked : undefined

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const v = await getClosingDay(requested)
      setView(v)
      setShowAtClose(v.closing?.isClosed ?? false)
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load the day.")
    } finally {
      setLoading(false)
    }
  }, [requested])

  useEffect(() => {
    if (activeFarmId) void load()
  }, [activeFarmId, load])

  const loadHistory = useCallback(async () => {
    try { setHistory(await getClosingHistory()) }
    catch (e) { toast({ title: "Could not load history", description: e instanceof Error ? e.message : "", variant: "destructive" }) }
  }, [toast])

  useEffect(() => {
    if (tab === "history" && activeFarmId) void loadHistory()
  }, [tab, activeFarmId, loadHistory])

  const choose = (value: string | null) => {
    const d = toBusinessDate(value)
    setPicked(!d || d >= today ? null : d)
    setTab("day")
  }

  const live = view?.live ?? null
  const record = view?.closing ?? null
  const isClosed = record?.isClosed ?? false
  const atClose = view?.atClose ?? null
  const businessDate = live?.businessDate ?? today
  const readiness = useMemo(() => (live ? closeReadiness(live, record) : null), [live, record])
  const changes = useMemo(() => (isClosed ? diffClosingState(atClose, live) : []), [isClosed, atClose, live])
  const shown: ClosingWorkspace | null = isClosed && showAtClose && atClose ? atClose : live

  async function run(fn: () => Promise<unknown>, ok: string) {
    setBusy(true)
    try {
      await fn()
      toast({ title: ok })
      await load()
      if (history) void loadHistory()
      return true
    } catch (e) {
      const blocked = e instanceof CloseDayConflictError
      toast({
        title: blocked ? "The day was not closed" : "That did not work",
        description: e instanceof Error ? e.message : "",
        variant: "destructive",
      })
      if (blocked) await load()
      return false
    } finally {
      setBusy(false)
    }
  }

  const doClose = async (notes: string) => {
    if (await run(() => closeBusinessDay(businessDate, notes), `${formatLongDate(businessDate)} closed`)) setCloseOpen(false)
  }
  const doReopen = async (reason: string) => {
    if (!record) return
    if (await run(() => reopenBusinessDay(record.poultryDailyClosingId, reason), "Day reopened")) setReopenOpen(false)
  }
  const doReject = async (reason: string) => {
    if (!record) return
    if (await run(() => rejectPoultryDailyClosing(record.poultryDailyClosingId, reason), "Submission rejected")) setRejectOpen(false)
  }
  const doSubmit = () =>
    run(async () => {
      const id = record?.poultryDailyClosingId
        ?? (await createPoultryDailyClosing({ closingDate: businessDate })).poultryDailyClosingId
      await submitPoultryDailyClosing(id, { actualCashCounted: 0, managerNotes: record?.managerNotes ?? null })
    }, "Submitted for approval")

  const openPolicy = async () => {
    try { setPolicy(await getClosingPolicy()); setPolicyOpen(true) }
    catch (e) { toast({ title: "Could not load the policy", description: e instanceof Error ? e.message : "", variant: "destructive" }) }
  }
  const doSavePolicy = async (p: ClosingPolicy) => {
    if (await run(() => saveClosingPolicy(p), "Closing policy saved")) setPolicyOpen(false)
  }
  const viewSnapshot = async (event: ClosingEvent) => {
    try { setSnapshot({ event, ws: await getClosingEventSnapshot(event.eventId) }) }
    catch (e) { toast({ title: "Could not load that closing", description: e instanceof Error ? e.message : "", variant: "destructive" }) }
  }

  const canSubmit = !isClosed && record?.status !== "Submitted"

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-4">
          <div className="space-y-4">
            {/* ---------------------------------------------------- header */}
            <div className="flex flex-wrap items-end justify-between gap-4">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-emerald-100">
                  <CalendarCheck className="h-5 w-5 text-emerald-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-2xl font-bold text-slate-900">Daily Closing</h1>
                  <p className="text-sm text-slate-600">Check that everything that should have happened today has, then close the day.</p>
                </div>
              </div>
              <div className="flex flex-wrap items-end gap-2">
                <Button variant="outline" size="icon" aria-label="Previous day" onClick={() => choose(shiftBusinessDate(businessDate, -1))}>
                  <ChevronLeft className="h-4 w-4" />
                </Button>
                <div className="space-y-1">
                  <Label htmlFor="closing-date" className="text-xs text-slate-500">Business date</Label>
                  <Input id="closing-date" type="date" className="w-40" value={businessDate} max={today}
                    onChange={(e) => choose(e.target.value)} />
                </div>
                <Button variant="outline" size="icon" aria-label="Next day" disabled={businessDate >= today}
                  onClick={() => choose(shiftBusinessDate(businessDate, 1))}>
                  <ChevronRight className="h-4 w-4" />
                </Button>
                {businessDate !== today && <Button variant="ghost" size="sm" onClick={() => choose(null)}>Today</Button>}
                <Button variant="ghost" size="icon" aria-label="Refresh" onClick={() => void load()} disabled={loading}>
                  <RefreshCw className={cn("h-4 w-4", loading && "animate-spin")} />
                </Button>
                {mayClose && (
                  <Button variant="outline" size="sm" className="gap-1.5" onClick={() => void openPolicy()}>
                    <Settings2 className="h-4 w-4" /> Policy
                  </Button>
                )}
              </div>
            </div>

            <Tabs value={tab} onValueChange={setTab}>
              <TabsList>
                <TabsTrigger value="day">Day</TabsTrigger>
                <TabsTrigger value="history">Previous closings</TabsTrigger>
              </TabsList>

              {/* ------------------------------------------------- day */}
              <TabsContent value="day" className="mt-4 space-y-4">
                {loading && !view && (
                  <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Checking the day…</p>
                )}
                {error && (
                  <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>
                )}

                {live && readiness && (
                  <>
                    {isClosed && record && atClose && (
                      <ClosedSummary record={record} atClose={atClose} fmt={fmt} fmtInstant={fmtInstant} />
                    )}
                    {isClosed && <ChangesSinceClosing changes={changes} fmt={fmt} />}

                    {/* ----------------------------- status + actions */}
                    <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                      <CardContent className="space-y-3 p-4">
                        <div className="flex flex-wrap items-start justify-between gap-3">
                          <div>
                            <p className="text-xs font-medium uppercase tracking-wider text-slate-500">
                              {formatLongDate(businessDate)}
                            </p>
                            <p className="text-lg font-bold text-slate-900">
                              {closingStatusLabel(record)}
                              <span className="ml-3 text-sm font-normal text-slate-500">
                                {live.counts.blocking} blocking · {live.counts.warning} warning{live.counts.warning === 1 ? "" : "s"} · {live.counts.complete} complete
                              </span>
                            </p>
                            {record?.status === "Submitted" && (
                              <p className="text-xs text-slate-500">Submitted by {record.submittedBy ?? "unknown"} — waiting for someone with the close right.</p>
                            )}
                            {record?.status === "Rejected" && record.rejectionReason && (
                              <p className="text-xs text-rose-700">Rejected: {record.rejectionReason}</p>
                            )}
                            {!isClosed && record?.lastReopenReason && (
                              <p className="text-xs text-amber-800">
                                Reopened by {record.lastReopenedBy ?? "unknown"} ({fmtInstant(record.lastReopenedAtUtc)}): {record.lastReopenReason}
                              </p>
                            )}
                            {!isClosed && readiness.reason && <p className="text-xs text-rose-700">{readiness.reason}</p>}
                          </div>
                          <div className="flex flex-wrap gap-2">
                            {isClosed && mayClose && record && (
                              <Button variant="outline" className="gap-1.5" onClick={() => setReopenOpen(true)} disabled={busy}>
                                <LockOpen className="h-4 w-4" /> Reopen Day
                              </Button>
                            )}
                            {!isClosed && record?.status === "Submitted" && mayClose && (
                              <Button variant="outline" className="gap-1.5 text-rose-700" onClick={() => setRejectOpen(true)} disabled={busy}>
                                <XCircle className="h-4 w-4" /> Reject
                              </Button>
                            )}
                            {!isClosed && !mayClose && canSubmit && (
                              <Button variant="outline" className="gap-1.5" onClick={() => void doSubmit()} disabled={busy}>
                                <Send className="h-4 w-4" /> Submit for approval
                              </Button>
                            )}
                            {!isClosed && mayClose && (
                              <Button
                                className="gap-1.5 bg-emerald-600 text-white hover:bg-emerald-700"
                                onClick={() => setCloseOpen(true)}
                                disabled={busy || !readiness.canClose}
                                title={readiness.reason ?? undefined}
                              >
                                <Lock className="h-4 w-4" /> Close Business Day
                              </Button>
                            )}
                          </div>
                        </div>

                        <div>
                          <h2 className="mb-1 text-xs font-semibold uppercase tracking-wider text-slate-500">
                            Closing checklist {isClosed && "(current)"}
                          </h2>
                          <ClosingChecklist checks={live.checklist} businessDate={businessDate} />
                        </div>
                      </CardContent>
                    </Card>

                    {/* ------------------------------- sections */}
                    {isClosed && atClose && (
                      <div className="flex items-center gap-2 text-sm">
                        <span className="text-slate-500">Showing:</span>
                        <Button size="sm" variant={showAtClose ? "default" : "outline"} onClick={() => setShowAtClose(true)}>
                          State at closing
                        </Button>
                        <Button size="sm" variant={!showAtClose ? "default" : "outline"} onClick={() => setShowAtClose(false)}>
                          Current corrected state
                        </Button>
                      </div>
                    )}
                    {shown && <ClosingSections ws={shown} fmt={fmt} />}

                    <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                      <CardContent className="space-y-2 p-4">
                        <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-500">History of this day</h2>
                        <ClosingTimeline events={view?.history ?? []} fmtInstant={fmtInstant} onViewSnapshot={viewSnapshot} />
                      </CardContent>
                    </Card>
                  </>
                )}
              </TabsContent>

              {/* ---------------------------------------------- history */}
              <TabsContent value="history" className="mt-4">
                <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                  <CardContent className="p-0">
                    {!history ? (
                      <p className="flex items-center gap-2 p-4 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>
                    ) : history.length === 0 ? (
                      <p className="p-4 text-sm text-slate-500">No days have been closed yet.</p>
                    ) : (
                      // Phones get the house card list (coloured tiles, striped,
                      // open by default) -- the look the old closing list had;
                      // lg and up keep the table. Tapping "Open day" jumps to it.
                      <MobileCardList
                        defaultOpen
                        striped
                        stripeAccent="blue"
                        items={pg.pageItems}
                        pagination={pg.paginationProps}
                        getKey={(h) => h.poultryDailyClosingId}
                        primary={(h) => formatLongDate(h.closingDate)}
                        secondary={(h) => h.closedBy
                          ? `Closed by ${h.closedBy}${h.closedAtUtc ? ` · ${fmtInstant(h.closedAtUtc)}` : ""}`
                          : closingStatusLabel(h)}
                        trailing={(h) => (
                          <span className={cn("rounded-full px-2 py-0.5 text-xs",
                            h.isClosed ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600")}>
                            {closingStatusLabel(h)}
                          </span>
                        )}
                        highlights={(h) => [
                          { label: "Sales", value: h.revenue != null ? fmt(h.revenue) : "—", accent: "emerald" },
                          {
                            label: "Net cash",
                            value: h.netCashFlow != null ? fmt(h.netCashFlow) : "—",
                            accent: (h.netCashFlow ?? 0) < 0 ? "rose" : "blue",
                          },
                        ]}
                        details={(h) => [
                          { label: "Warnings at closing", value: h.warningsAtClose ?? "—" },
                          { label: "Eggs produced", value: h.eggsProduced != null ? Number(h.eggsProduced).toLocaleString() : "—" },
                          {
                            label: "Reopened",
                            value: h.reopenCount > 0
                              ? `${h.reopenCount}×${h.lastReopenReason ? ` — ${h.lastReopenReason}` : ""}`
                              : "—",
                          },
                        ]}
                        actions={(h) => (
                          <Button size="sm" variant="outline" className="h-10 flex-1"
                            onClick={() => choose(toBusinessDate(h.closingDate))}>
                            Open day
                          </Button>
                        )}
                        desktopTable={
                          <div className="overflow-x-auto">
                            <table className="w-full min-w-[44rem] text-sm">
                              <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                                <tr>
                                  <th className="px-3 py-2 font-medium">Date</th>
                                  <th className="px-3 py-2 font-medium">Status</th>
                                  <th className="px-3 py-2 font-medium">Closed by</th>
                                  <th className="px-3 py-2 text-right font-medium">Sales</th>
                                  <th className="px-3 py-2 text-right font-medium">Net cash</th>
                                  <th className="px-3 py-2 text-right font-medium">Warnings</th>
                                  <th className="px-3 py-2 font-medium">Reopened</th>
                                </tr>
                              </thead>
                              <tbody className="divide-y divide-slate-100">
                                {pg.pageItems.map((h) => (
                                  <tr key={h.poultryDailyClosingId} className="cursor-pointer hover:bg-slate-50"
                                    onClick={() => choose(toBusinessDate(h.closingDate))}>
                                    <td className="px-3 py-2 font-medium text-slate-900">{formatLongDate(h.closingDate)}</td>
                                    <td className="px-3 py-2">
                                      <span className={cn("rounded-full px-2 py-0.5 text-xs",
                                        h.isClosed ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600")}>
                                        {closingStatusLabel(h)}
                                      </span>
                                    </td>
                                    <td className="px-3 py-2 text-slate-600">
                                      {h.closedBy ?? "—"}{h.closedAtUtc ? ` · ${fmtInstant(h.closedAtUtc)}` : ""}
                                    </td>
                                    <td className="px-3 py-2 text-right tabular-nums">{h.revenue != null ? fmt(h.revenue) : "—"}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{h.netCashFlow != null ? fmt(h.netCashFlow) : "—"}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{h.warningsAtClose ?? "—"}</td>
                                    <td className="px-3 py-2 text-slate-600">
                                      {h.reopenCount > 0 ? `${h.reopenCount}×${h.lastReopenReason ? ` — ${h.lastReopenReason}` : ""}` : "—"}
                                    </td>
                                  </tr>
                                ))}
                              </tbody>
                            </table>
                          </div>
                        }
                      />
                    )}
                  </CardContent>
                </Card>
                <p className="mt-2 text-xs text-slate-500">
                  Figures are as each day was closed. Days closed before this version show their status only.
                </p>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      <CloseDayDialog open={closeOpen} onOpenChange={setCloseOpen} businessDate={businessDate}
        warnings={readiness?.warnings ?? []} busy={busy} onConfirm={(n) => void doClose(n)} />
      <ReasonDialog open={reopenOpen} onOpenChange={setReopenOpen} busy={busy}
        title={`Reopen ${formatLongDate(businessDate)}?`}
        description="The day will be open for correction. Its closing, who closed it and this reason stay in the history."
        confirmLabel="Reopen Day" onConfirm={(r) => void doReopen(r)} />
      <ReasonDialog open={rejectOpen} onOpenChange={setRejectOpen} busy={busy} destructive
        title="Reject this submission?" description="The person who submitted it will see your reason."
        confirmLabel="Reject" onConfirm={(r) => void doReject(r)} />
      <ClosingPolicyDialog open={policyOpen} onOpenChange={setPolicyOpen} policy={policy} busy={busy}
        onSave={(p) => void doSavePolicy(p)} />

      <Dialog open={!!snapshot} onOpenChange={(v) => { if (!v) setSnapshot(null) }}>
        <DialogContent className="max-h-[90vh] max-w-4xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              {snapshot && `${formatLongDate(snapshot.ws.businessDate)} as closed (v${snapshot.event.closeVersion ?? "?"}) by ${snapshot.event.actor ?? "unknown"}`}
            </DialogTitle>
          </DialogHeader>
          {snapshot && (
            <div className="space-y-4">
              <ClosingChecklist checks={snapshot.ws.checklist} businessDate={snapshot.ws.businessDate} />
              <ClosingSections ws={snapshot.ws} fmt={fmt} />
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

export default function PoultryDailyClosingPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <PoultryDailyClosingInner />
    </Suspense>
  )
}

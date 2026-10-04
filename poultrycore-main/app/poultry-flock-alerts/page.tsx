"use client"

// Flock Alerts (migration 338): deterministic anomaly detection per flock.
// Every alert shows exactly why it fired — today's figure, the flock's own
// baseline, the thresholds and what was observed — and keeps its full history
// (acknowledge, notes, resolve; nothing is ever deleted). "Today's checks"
// shows every signal for every flock, including the ones that did not fire and
// why (not enough history, first recorded day, duplicate records...).

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { Activity, ChevronDown, Loader2, RefreshCw, Settings2 } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { useAuthStore } from "@/lib/store/auth-store"
import {
  acknowledgeFlockAlert,
  addFlockAlertNote,
  getFlockAlert,
  getFlockAlerts,
  getFlockAnomalySettings,
  getFlockEvaluation,
  rescanFlockAlerts,
  resetFlockAnomalySetting,
  resolveFlockAlert,
  saveFlockAnomalySetting,
  type AlertStatusFilter,
} from "@/lib/api/flock-alerts"
import {
  METHOD_OPTIONS,
  alertHeadline,
  dayOf,
  evaluationStatusText,
  eventText,
  flockLabel,
  guardText,
  isActiveStatus,
  methodUnit,
  severityStyle,
  sortAlerts,
  statusStyle,
  summarizeAlerts,
  thresholdExample,
  thresholdHelp,
  validateSetting,
  type FlockAlert,
  type FlockAlertEvent,
  type FlockAnomalySignalSetting,
  type FlockSignalEvaluation,
} from "@/lib/production/flock-anomalies"
import { formatLongDate } from "@/lib/closing/daily-closing"

const FILTERS: { value: AlertStatusFilter; label: string }[] = [
  { value: "active", label: "Needs attention" },
  { value: "Resolved", label: "Resolved" },
  { value: "Cleared", label: "Cleared by data" },
  { value: "all", label: "All" },
]

function fmtWhen(utc: string | null | undefined): string {
  if (!utc) return ""
  const d = new Date(utc)
  return Number.isNaN(d.getTime()) ? "" : d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })
}

function fmtNum(v: number | null | undefined, dp = 1): string {
  return v == null || !Number.isFinite(v) ? "—" : Number(v.toFixed(dp)).toLocaleString()
}

function FlockAlertsInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const [tab, setTab] = useState<"alerts" | "checks">("alerts")
  const [filter, setFilter] = useState<AlertStatusFilter>("active")
  const [alerts, setAlerts] = useState<FlockAlert[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [rescanning, setRescanning] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)

  const openId = Number(searchParams.get("alert")) || null

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    setError(null)
    try { setAlerts(sortAlerts(await getFlockAlerts({ status: filter }))) }
    catch (e) { setError(e instanceof Error ? e.message : "Could not load flock alerts.") }
  }, [filter])
  useEffect(() => { if (activeFarmId) void load() }, [activeFarmId, load])

  const openAlert = (id: number | null) => {
    const qs = new URLSearchParams(searchParams.toString())
    if (id) qs.set("alert", String(id)); else qs.delete("alert")
    router.replace(`/poultry-flock-alerts${qs.toString() ? `?${qs}` : ""}`, { scroll: false })
  }

  const rescan = async () => {
    setRescanning(true)
    try {
      const to = new Date()
      const from = new Date(to.getTime() - 13 * 86400000)
      const iso = (d: Date) => d.toISOString().slice(0, 10)
      await rescanFlockAlerts(iso(from), iso(to))
      toast({ title: "Re-checked the last 14 days" })
      await load()
    } catch (e) {
      toast({ title: "Re-check failed", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally {
      setRescanning(false)
    }
  }

  const s = summarizeAlerts(alerts ?? [])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-6">
          <div className="space-y-4">
            <div className="flex flex-wrap items-end justify-between gap-3">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-rose-100">
                  <Activity className="h-5 w-5 text-rose-700" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Flock Alerts</h1>
                  <p className="text-sm text-slate-600">
                    Each flock&apos;s figures today against its own recent history — with the numbers behind every alert.
                  </p>
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button variant="outline" size="sm" onClick={rescan} disabled={rescanning}
                  title="Re-check the last 14 days, e.g. after correcting back-dated records">
                  {rescanning ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <RefreshCw className="mr-1.5 h-4 w-4" />}
                  Re-check
                </Button>
                <Button variant="outline" size="sm" onClick={() => setSettingsOpen(true)}>
                  <Settings2 className="mr-1.5 h-4 w-4" /> Alert settings
                </Button>
              </div>
            </div>

            <div className="inline-flex rounded-md border border-slate-200 bg-white p-0.5 text-sm">
              {([["alerts", "Alerts"], ["checks", "Daily checks"]] as const).map(([k, l]) => (
                <button key={k} type="button" onClick={() => setTab(k)}
                  className={cn("rounded px-3 py-1.5", tab === k ? "bg-slate-900 text-white" : "text-slate-600 hover:text-slate-900")}>
                  {l}
                </button>
              ))}
            </div>

            {tab === "alerts" ? (
              <>
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="inline-flex flex-wrap rounded-md border border-slate-200 bg-slate-50 p-0.5 text-sm">
                    {FILTERS.map((f) => (
                      <button key={f.value} type="button" onClick={() => setFilter(f.value)}
                        className={cn("rounded px-3 py-1", filter === f.value ? "bg-white font-medium text-slate-900 shadow-sm" : "text-slate-600")}>
                        {f.label}
                      </button>
                    ))}
                  </div>
                  {alerts && filter === "active" && (
                    <p className="text-sm text-slate-600">
                      {s.critical} critical · {s.warning} warning · {s.information} information
                    </p>
                  )}
                </div>

                {error && <Card><CardContent className="p-4 text-sm text-rose-700">{error}</CardContent></Card>}
                {!alerts && !error && (
                  <div className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Checking flocks…</div>
                )}
                {alerts && alerts.length === 0 && (
                  <Card><CardContent className="p-6 text-center text-sm text-slate-600">
                    {filter === "active" ? "No flock needs attention. Every flock with a record is within its normal range, or does not yet have enough history to judge — see Daily checks."
                      : "Nothing here."}
                  </CardContent></Card>
                )}
                <div className="space-y-2">
                  {alerts?.map((a) => <AlertRow key={a.alertId} alert={a} onOpen={() => openAlert(a.alertId)} />)}
                </div>
              </>
            ) : (
              <DailyChecks />
            )}
          </div>
        </main>
      </div>

      <AlertDetail alertId={openId} onClose={() => openAlert(null)} onChanged={load} />
      <SettingsDialog open={settingsOpen} onOpenChange={setSettingsOpen} onSaved={load} />
    </div>
  )
}

function AlertRow({ alert: a, onOpen }: { alert: FlockAlert; onOpen: () => void }) {
  const sev = severityStyle(a.severity)
  const st = statusStyle(a.status)
  const lead = a.signals.find((x) => x.isActive) ?? a.signals[0]
  return (
    <button type="button" onClick={onOpen}
      className={cn("block w-full rounded-xl border border-l-4 border-slate-200 bg-white p-3 text-left shadow-sm hover:bg-slate-50",
        isActiveStatus(a.status) ? sev.border : "border-l-slate-300")}>
      <div className="flex flex-wrap items-center gap-2">
        <span className={cn("rounded-full border px-2 py-0.5 text-[11px] font-medium uppercase", sev.badge)}>{sev.label}</span>
        <span className={cn("rounded-full border px-2 py-0.5 text-[11px]", st.badge)}>{st.label}</span>
        <span className="font-medium text-slate-900">{flockLabel(a)}</span>
        <span className="text-sm text-slate-500">{formatLongDate(dayOf(a.businessDate))}</span>
        {a.consecutiveDays > 1 && (
          <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] text-slate-700">{a.consecutiveDays} days in a row</span>
        )}
      </div>
      <p className="mt-1 text-sm font-medium text-slate-800">{alertHeadline(a)}</p>
      {lead && (
        <p className="mt-0.5 text-xs text-slate-600">
          {lead.explanation.filter((l) => !l.startsWith("Alert levels") && !l.startsWith("Result")).join(" · ")}
        </p>
      )}
      {a.noteCount > 0 && <p className="mt-1 text-xs text-slate-500">{a.noteCount} note{a.noteCount === 1 ? "" : "s"}</p>}
    </button>
  )
}

function AlertDetail({ alertId, onClose, onChanged }: { alertId: number | null; onClose: () => void; onChanged: () => void }) {
  const { toast } = useToast()
  const [data, setData] = useState<{ alert: FlockAlert; events: FlockAlertEvent[] } | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState("")
  const [busy, setBusy] = useState(false)
  const [showEvidence, setShowEvidence] = useState(false)

  const load = useCallback(async () => {
    if (!alertId) return
    setError(null)
    try { setData(await getFlockAlert(alertId)) }
    catch (e) { setError(e instanceof Error ? e.message : "Could not load the alert.") }
  }, [alertId])
  useEffect(() => { setData(null); setNote(""); setShowEvidence(false); void load() }, [load])

  const act = async (kind: "ack" | "note" | "resolve") => {
    if (!alertId) return
    if ((kind === "note" || kind === "resolve") && !note.trim()) {
      toast({ title: kind === "resolve" ? "Say what was found or done before resolving." : "Write a note first.", variant: "destructive" })
      return
    }
    setBusy(true)
    try {
      if (kind === "ack") await acknowledgeFlockAlert(alertId, note.trim() || undefined)
      if (kind === "note") await addFlockAlertNote(alertId, note.trim())
      if (kind === "resolve") await resolveFlockAlert(alertId, note.trim())
      toast({ title: kind === "ack" ? "Acknowledged" : kind === "note" ? "Note added" : "Resolved" })
      setNote("")
      await load()
      onChanged()
    } catch (e) {
      toast({ title: "Not saved", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  const a = data?.alert
  const labels = useMemo(() => Object.fromEntries((a?.signals ?? []).map((s) => [s.signalKey, s.label])), [a])

  return (
    <Sheet open={alertId != null} onOpenChange={(o) => { if (!o) onClose() }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>{a ? flockLabel(a) : "Flock alert"}</SheetTitle>
          <SheetDescription>
            {a ? `${formatLongDate(dayOf(a.businessDate))} — ${alertHeadline(a)}` : " "}
          </SheetDescription>
        </SheetHeader>

        {error && <p className="mt-4 text-sm text-rose-700">{error}</p>}
        {!a && !error && <div className="mt-6 flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>}

        {a && (
          <div className="mt-4 space-y-5 pb-8">
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <span className={cn("rounded-full border px-2 py-0.5 text-[11px] font-medium uppercase", severityStyle(a.severity).badge)}>
                {severityStyle(a.severity).label}
              </span>
              <span className={cn("rounded-full border px-2 py-0.5 text-[11px]", statusStyle(a.status).badge)}>{statusStyle(a.status).label}</span>
              {a.peakSeverity !== a.severity && <span className="text-xs text-slate-500">peaked at {a.peakSeverity}</span>}
              {a.consecutiveDays > 1 && <span className="text-xs text-slate-500">· {a.consecutiveDays} days in a row</span>}
              <Link href="/production-records" className="ml-auto text-xs text-sky-700 underline">Production records</Link>
            </div>

            <section className="space-y-3">
              <h3 className="text-sm font-semibold text-slate-900">Why it fired</h3>
              {a.signals.map((sg) => (
                <div key={sg.signalKey} className={cn("rounded-lg border p-3", sg.isActive ? "border-slate-200 bg-white" : "border-dashed border-slate-200 bg-slate-50")}>
                  <div className="mb-1.5 flex flex-wrap items-center gap-2">
                    <span className="text-sm font-medium text-slate-900">{sg.label}</span>
                    <span className={cn("rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase", severityStyle(sg.severity).badge)}>{sg.severity}</span>
                    {!sg.isActive && <span className="text-xs text-slate-500">no longer firing{sg.clearedAtUtc ? ` since ${fmtWhen(sg.clearedAtUtc)}` : ""}</span>}
                  </div>
                  <ul className="space-y-0.5 text-sm text-slate-700">
                    {sg.explanation.map((line, i) => <li key={i} className="tabular-nums">{line}</li>)}
                  </ul>
                </div>
              ))}
              <p className="text-xs text-slate-500">
                Figures come from production records only. Opening-position history (birds lost before tracking began)
                is never counted, and days with duplicate records or a flock&apos;s first recorded day are left out when working out what is normal.
              </p>
              <button type="button" onClick={() => setShowEvidence((v) => !v)} className="flex items-center gap-1 text-xs text-slate-600 hover:text-slate-900">
                <ChevronDown className={cn("h-3.5 w-3.5 transition-transform", showEvidence && "rotate-180")} />
                Structured evidence
              </button>
              {showEvidence && (
                <pre className="max-h-72 overflow-auto rounded-md bg-slate-900 p-3 text-[11px] leading-snug text-slate-100">
                  {JSON.stringify(a.signals.map((x) => x.evidence), null, 2)}
                </pre>
              )}
            </section>

            <section className="space-y-2">
              <h3 className="text-sm font-semibold text-slate-900">Action</h3>
              <Textarea value={note} onChange={(e) => setNote(e.target.value)} rows={3} maxLength={2000}
                placeholder={a.status === "Resolved" ? "Add a note…" : "What was checked, found or done…"} />
              <div className="flex flex-wrap gap-2">
                {(a.status === "Open" || (a.status === "Cleared" && !a.acknowledgedAtUtc)) && (
                  <Button size="sm" variant="outline" disabled={busy} onClick={() => act("ack")}>Acknowledge</Button>
                )}
                <Button size="sm" variant="outline" disabled={busy} onClick={() => act("note")}>Add note</Button>
                {a.status !== "Resolved" && (
                  <Button size="sm" disabled={busy} onClick={() => act("resolve")}>Resolve</Button>
                )}
              </div>
              <p className="text-xs text-slate-500">Resolving needs a note. Nothing is ever deleted — every step stays in the history below.</p>
            </section>

            <section className="space-y-2">
              <h3 className="text-sm font-semibold text-slate-900">History</h3>
              <ol className="space-y-2 border-l border-slate-200 pl-4">
                {data!.events.map((e) => (
                  <li key={e.eventId} className="text-sm">
                    <p className="text-slate-800">{eventText(e, labels)}</p>
                    {e.note && <p className="whitespace-pre-wrap text-slate-600">“{e.note}”</p>}
                    <p className="text-xs text-slate-500">{fmtWhen(e.atUtc)}{e.actor ? ` · ${e.actor}` : ""}</p>
                  </li>
                ))}
              </ol>
            </section>
          </div>
        )}
      </SheetContent>
    </Sheet>
  )
}

function DailyChecks() {
  const [date, setDate] = useState<string>("")
  const [rows, setRows] = useState<FlockSignalEvaluation[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    setRows(null); setError(null)
    getFlockEvaluation(date || undefined)
      .then((r) => { if (!cancelled) setRows(r) })
      .catch((e) => { if (!cancelled) setError(e instanceof Error ? e.message : "Could not load checks.") })
    return () => { cancelled = true }
  }, [date])

  const flocks = useMemo(() => {
    const m = new Map<number, FlockSignalEvaluation[]>()
    for (const r of rows ?? []) m.set(r.flockId, [...(m.get(r.flockId) ?? []), r])
    return [...m.values()].sort((x, y) =>
      Math.max(...y.map((r) => r.severityRank)) - Math.max(...x.map((r) => r.severityRank))
      || x[0].flockName.localeCompare(y[0].flockName))
  }, [rows])
  const shownDate = rows?.[0]?.businessDate ? dayOf(rows[0].businessDate) : date

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-end gap-3">
        <div className="space-y-1">
          <Label className="text-xs text-slate-500">Business date</Label>
          <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="h-9 w-44" />
        </div>
        <p className="pb-2 text-sm text-slate-600">
          {shownDate ? formatLongDate(shownDate) : "Today"} — every signal for every flock with a production record, fired or not.
        </p>
      </div>
      {error && <Card><CardContent className="p-4 text-sm text-rose-700">{error}</CardContent></Card>}
      {!rows && !error && <div className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Evaluating…</div>}
      {rows && rows.length === 0 && (
        <Card><CardContent className="p-6 text-center text-sm text-slate-600">No production records on this date, so there is nothing to check.</CardContent></Card>
      )}
      {flocks.map((list) => (
        <Card key={list[0].flockId} className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <CardContent className="p-3">
            <p className="mb-2 font-medium text-slate-900">{flockLabel(list[0])}</p>
            <div className="divide-y divide-slate-100">
              {list.map((r) => {
                const key = `${r.flockId}:${r.signalKey}`
                const fired = r.status === "Fired"
                return (
                  <div key={key} className="py-1.5">
                    <button type="button" onClick={() => setOpen(open === key ? null : key)}
                      className="flex w-full flex-wrap items-center gap-x-3 gap-y-1 text-left text-sm">
                      <span className="w-48 shrink-0 text-slate-700">{r.signalLabel}</span>
                      <span className={cn("rounded-full border px-2 py-0.5 text-[11px]",
                        fired ? severityStyle(r.severity).badge
                          : r.status === "Normal" ? "border-emerald-200 bg-emerald-50 text-emerald-700"
                          : "border-slate-200 bg-slate-50 text-slate-600")}>
                        {fired ? r.severity : evaluationStatusText(r.status)}
                      </span>
                      <span className="tabular-nums text-slate-600">
                        {fmtNum(r.currentValue, 2)} vs {fmtNum(r.baselineMean, 2)} {r.metricUnit}
                        {r.observed != null && ` · ${fmtNum(r.observed, 2)}${methodUnit(r.method)}`}
                      </span>
                      <ChevronDown className={cn("ml-auto h-4 w-4 text-slate-400 transition-transform", open === key && "rotate-180")} />
                    </button>
                    {open === key && (
                      <ul className="mt-1.5 space-y-0.5 rounded-md bg-slate-50 p-2 text-xs text-slate-700">
                        {r.explanation.map((l, i) => <li key={i}>{l}</li>)}
                      </ul>
                    )}
                  </div>
                )
              })}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

function SettingsDialog({ open, onOpenChange, onSaved }: { open: boolean; onOpenChange: (o: boolean) => void; onSaved: () => void }) {
  const { toast } = useToast()
  const [rows, setRows] = useState<FlockAnomalySignalSetting[] | null>(null)
  const [saving, setSaving] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setRows(null)
    getFlockAnomalySettings().then(setRows).catch((e) =>
      toast({ title: "Could not load alert settings", description: e instanceof Error ? e.message : "", variant: "destructive" }))
  }, [open, toast])

  const patch = (key: string, p: Partial<FlockAnomalySignalSetting>) =>
    setRows((rs) => rs?.map((r) => (r.signalKey === key ? { ...r, ...p } : r)) ?? rs)

  const save = async (r: FlockAnomalySignalSetting) => {
    const problem = validateSetting(r)
    if (problem) { toast({ title: "Not saved", description: problem, variant: "destructive" }); return }
    setSaving(r.signalKey)
    try {
      await saveFlockAnomalySetting(r)
      toast({ title: `${r.label} saved` })
      setRows(await getFlockAnomalySettings())
      onSaved()
    } catch (e) {
      toast({ title: "Not saved", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally { setSaving(null) }
  }

  const reset = async (r: FlockAnomalySignalSetting) => {
    setSaving(r.signalKey)
    try {
      await resetFlockAnomalySetting(r.signalKey)
      setRows(await getFlockAnomalySettings())
      onSaved()
    } catch (e) {
      toast({ title: "Not reset", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally { setSaving(null) }
  }

  const num = (v: string): number | null => (v.trim() === "" ? null : Number(v))

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>Alert settings</DialogTitle>
          <DialogDescription>
            Each alert compares a flock&apos;s figure today with what is <strong>normal for that same flock</strong>, worked
            out from its own recent records. Raise the numbers for fewer alerts, lower them for more. Changes apply from the
            next check; alerts already raised keep the figures they were raised with.
          </DialogDescription>
        </DialogHeader>
        {!rows && <div className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>}
        <div className="space-y-4">
          {rows?.map((r) => {
            const unit = methodUnit(r.method)
            const hint = METHOD_OPTIONS.find((m) => m.value === r.method)?.hint
            const guard = guardText(r)
            const example = thresholdExample(r)
            return (
              <div key={r.signalKey} className="space-y-3 rounded-lg border border-slate-200 p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <p className="font-medium text-slate-900">{r.label}</p>
                    <p className="text-xs text-slate-500">
                      Alerts when a flock&apos;s {r.metricLabel.toLowerCase()} ({r.metricUnit}) goes {r.direction === "up" ? "above" : "below"} its normal.
                    </p>
                  </div>
                  <div className="flex items-center gap-2 text-sm">
                    <Switch checked={r.enabled} onCheckedChange={(v) => patch(r.signalKey, { enabled: v })} />
                    <span>{r.enabled ? "On" : "Off"}</span>
                  </div>
                </div>

                <div className="space-y-2">
                  <div className="grid grid-cols-3 gap-3">
                    <Field label={`Information (${unit})`} value={r.informationThreshold} step="0.1"
                      help="Optional. Leave empty to skip."
                      onChange={(v) => patch(r.signalKey, { informationThreshold: num(v) })} />
                    <Field label={`Warning (${unit})`} value={r.warningThreshold} step="0.1"
                      onChange={(v) => patch(r.signalKey, { warningThreshold: num(v) ?? 0 })} />
                    <Field label={`Critical (${unit})`} value={r.criticalThreshold} step="0.1"
                      onChange={(v) => patch(r.signalKey, { criticalThreshold: num(v) ?? 0 })} />
                  </div>
                  <p className="text-xs text-slate-500">{thresholdHelp(r)}</p>
                  {example && <p className="rounded-md bg-slate-50 px-2 py-1.5 text-xs text-slate-700">{example}</p>}
                </div>

                {r.guardField && (
                  <div className="sm:w-1/2">
                    <Field label={guard.label} value={r.guardMinimum} step="0.1" help={guard.help}
                      onChange={(v) => patch(r.signalKey, { guardMinimum: num(v) })} />
                  </div>
                )}

                <details className="group rounded-md border border-slate-100 bg-slate-50/50 px-3 py-2">
                  <summary className="flex cursor-pointer list-none items-center gap-1 text-xs font-medium text-slate-600 hover:text-slate-900">
                    <ChevronDown className="h-3.5 w-3.5 transition-transform group-open:rotate-180" />
                    Advanced — how &ldquo;normal&rdquo; is worked out
                  </summary>
                  <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <div className="space-y-1 sm:col-span-2">
                      <Label className="text-xs">Compare today with normal as</Label>
                      <select value={r.method} onChange={(e) => patch(r.signalKey, { method: e.target.value as FlockAnomalySignalSetting["method"] })}
                        className="h-9 w-full rounded-md border border-slate-200 bg-white px-2 text-sm">
                        {METHOD_OPTIONS.map((m) => <option key={m.value} value={m.value}>{m.label}</option>)}
                      </select>
                      {hint && <p className="text-xs text-slate-500">{hint}</p>}
                    </div>
                    <Field label="Work out normal from the last (days)" value={r.baselineDays}
                      help="Normal is the flock's average over these days. Today is never included."
                      onChange={(v) => patch(r.signalKey, { baselineDays: num(v) ?? 0 })} />
                    <Field label="Days of records needed first" value={r.minBaselineDays}
                      help="A flock with fewer days of records isn't checked yet. This stops false alarms on new flocks."
                      onChange={(v) => patch(r.signalKey, { minBaselineDays: num(v) ?? 0 })} />
                    <div className="sm:col-span-2">
                      <Field label={`Treat normal as at least (${r.metricUnit})`} value={r.baselineFloor} step="0.01"
                        help="Stops silly results when normal is zero or nearly zero. E.g. after weeks with no deaths, 3 deaths would otherwise be “infinity times normal”. Rarely needs changing."
                        onChange={(v) => patch(r.signalKey, { baselineFloor: num(v) ?? 0 })} />
                    </div>
                  </div>
                </details>

                <div className="flex flex-wrap items-center justify-end gap-2">
                  {r.isCustomised && <span className="mr-auto text-xs text-slate-500">Customised{r.updatedBy ? ` by ${r.updatedBy}` : ""}</span>}
                  {r.isCustomised && (
                    <Button size="sm" variant="ghost" disabled={saving === r.signalKey} onClick={() => reset(r)}>Reset to default</Button>
                  )}
                  <Button size="sm" disabled={saving === r.signalKey} onClick={() => save(r)}>
                    {saving === r.signalKey && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Save
                  </Button>
                </div>
              </div>
            )
          })}
        </div>
      </DialogContent>
    </Dialog>
  )
}

function Field({ label, value, onChange, step = "1", help }: {
  label: string; value: number | null | undefined; onChange: (v: string) => void; step?: string; help?: string
}) {
  return (
    <div className="space-y-1">
      <Label className="text-xs">{label}</Label>
      <Input type="number" inputMode="decimal" step={step} value={value ?? ""} onChange={(e) => onChange(e.target.value)} className="h-9" />
      {help && <p className="text-xs text-slate-500">{help}</p>}
    </div>
  )
}

export default function FlockAlertsPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <FlockAlertsInner />
    </Suspense>
  )
}

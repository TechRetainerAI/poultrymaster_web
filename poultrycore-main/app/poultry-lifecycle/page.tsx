"use client"

// Flock Lifecycle (Tools menu, migration 347) -- farm-defined lifecycle plans
// and the reminders they raise for each flock.
//
//   Tasks        what needs attention: overdue, due, upcoming (or any status),
//                with Complete / Skip / Reopen and the status history
//   Plans        the farm's own templates and their milestones
//   Assignments  which plan each batch (its flocks inherit) or flock follows
//
// VisibilityCore ships no milestones and recommends nothing: every week,
// title and treatment here was typed by the farm. Tasks only LINK to the
// ordinary pages (flock, health records, production, closeout); nothing is
// executed from here.

import { Suspense, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import {
  AlertTriangle, CalendarClock, CheckCircle2, ExternalLink, History, Loader2, Lock, Pencil, Plus,
  RefreshCw, RotateCcw, SkipForward, Trash2, Unlink, ListChecks, ClipboardList, Link2,
} from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { SuggestInput } from "@/components/ui/suggest-input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { usePermissions } from "@/hooks/use-permissions"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { tabCountCls, tabListCls, tabTriggerCls } from "@/lib/ui/tab-styles"
import { useAuthStore } from "@/lib/store/auth-store"
import { getUserContext } from "@/lib/utils/user-context"
import { fmtInstant } from "@/lib/utils/company-datetime"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import {
  assignLifecycleTemplate, createLifecycleTemplate, deleteLifecycleTemplate, getLifecycleSummary,
  getLifecycleTaskHistory, getLifecycleTemplate, listLifecycleAssignments, listLifecycleTasks,
  listLifecycleTemplates, removeLifecycleAssignment, setLifecycleTaskStatus, updateLifecycleTemplate,
  type LifecycleActionType, type LifecycleAgeUnit, type LifecycleAssignment, type LifecycleMilestone,
  type LifecycleSummary, type LifecycleTask, type LifecycleTaskEvent, type LifecycleTemplate, type LifecycleView,
} from "@/lib/api/poultry-lifecycle"
import {
  ACTION_TYPES, AGE_UNITS, CATEGORY_SUGGESTIONS, STATUS_TONE, actionLabel, ageAtStartDays, dueLabel,
  formatAgeDays, lifecycleActionHref, milestoneAgeLabel, sortTasks, taskSentence, validatePlan,
} from "@/lib/poultry/lifecycle"

const day = (v: string | null | undefined) => (v ? v.slice(0, 10) : "—")
const isClosed = (f: Flock) => Boolean(f.closedDate)

const VIEWS: { value: LifecycleView; label: string }[] = [
  { value: "Open", label: "Needs attention" },
  { value: "Overdue", label: "Overdue" },
  { value: "Due", label: "Due" },
  { value: "Upcoming", label: "Upcoming" },
  { value: "Scheduled", label: "Later" },
  { value: "Completed", label: "Completed" },
  { value: "Skipped", label: "Skipped" },
  { value: "All", label: "Everything" },
]

function LifecycleInner() {
  const router = useRouter()
  const params = useSearchParams()
  const { toast } = useToast()
  const logout = useLogout()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const canView = permissions.can("poultry.lifecycle.view")
  const canCreate = permissions.can("poultry.lifecycle.create")
  const canEdit = permissions.can("poultry.lifecycle.edit")
  const canDelete = permissions.can("poultry.lifecycle.delete")

  const [tab, setTab] = useState<"tasks" | "plans" | "assignments">((params.get("tab") as any) || "tasks")
  const [view, setView] = useState<LifecycleView>("Open")
  const [flockFilter, setFlockFilter] = useState<string>(params.get("flockId") ?? "all")
  const [tasks, setTasks] = useState<LifecycleTask[]>([])
  const [summary, setSummary] = useState<LifecycleSummary | null>(null)
  const [templates, setTemplates] = useState<LifecycleTemplate[]>([])
  const [assignments, setAssignments] = useState<LifecycleAssignment[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [batches, setBatches] = useState<FlockBatch[]>([])
  const [loading, setLoading] = useState(true)

  const [planEditor, setPlanEditor] = useState<{ open: boolean; template: LifecycleTemplate | null }>({ open: false, template: null })
  const [assignOpen, setAssignOpen] = useState(false)
  const [skipping, setSkipping] = useState<LifecycleTask | null>(null)
  const [reopening, setReopening] = useState<LifecycleTask | null>(null)
  const [historyFor, setHistoryFor] = useState<LifecycleTask | null>(null)
  const [deletingPlan, setDeletingPlan] = useState<LifecycleTemplate | null>(null)
  const [removingAssignment, setRemovingAssignment] = useState<LifecycleAssignment | null>(null)
  const [busyKey, setBusyKey] = useState<string | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void loadAll()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  useEffect(() => { void loadTasks() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [view, flockFilter])

  async function loadTasks() {
    try {
      const [t, s] = await Promise.all([
        listLifecycleTasks({ view, flockId: flockFilter === "all" ? null : Number(flockFilter) }),
        getLifecycleSummary(),
      ])
      setTasks(sortTasks(t)); setSummary(s)
    } catch (e: any) {
      toast({ title: "Could not load lifecycle tasks", description: e?.message, variant: "destructive" })
    }
  }

  async function loadAll() {
    setLoading(true)
    const { farmId, userId } = getUserContext()
    try {
      const [tp, as, fl, bt] = await Promise.all([
        listLifecycleTemplates(),
        listLifecycleAssignments(),
        getFlocks(userId || undefined, farmId || undefined),
        getFlockBatches(userId || undefined, farmId || undefined),
      ])
      setTemplates(tp); setAssignments(as)
      setFlocks((fl.success && fl.data) ? fl.data : [])
      setBatches((bt.success && bt.data) ? bt.data : [])
      await loadTasks()
    } catch (e: any) {
      toast({ title: "Could not load the lifecycle assistant", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  async function complete(t: LifecycleTask) {
    const key = `${t.flockId}-${t.milestoneId}`
    setBusyKey(key)
    try {
      await setLifecycleTaskStatus({ flockId: t.flockId, milestoneId: t.milestoneId, status: "Completed" })
      toast({ title: "Marked complete", description: `${t.title} — ${t.flockName}` })
      await loadTasks()
    } catch (e: any) {
      toast({ title: "Could not complete the task", description: e?.message, variant: "destructive" })
    } finally { setBusyKey(null) }
  }

  const tasksPg = usePagination(tasks)
  const openFlocks = useMemo(() => flocks.filter((f) => !isClosed(f)).sort((a, b) => a.name.localeCompare(b.name)), [flocks])
  const estimatedShown = tasks.some((t) => t.isEstimated)

  if (!permissions.isLoading && !canView) {
    return (
      <Shell logout={logout}>
        <Card><CardContent className="p-8 text-center text-slate-600">
          <Lock className="mx-auto mb-2 h-6 w-6 text-slate-400" />
          You do not have access to the Flock Lifecycle assistant.
        </CardContent></Card>
      </Shell>
    )
  }

  return (
    <Shell logout={logout}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
            <CalendarClock className="h-6 w-6 text-indigo-600" /> Flock Lifecycle
          </h1>
          <p className="text-sm text-slate-600 max-w-3xl">
            Reminders for the milestones <strong>your farm</strong> defines — housing moves, reviews, treatments your vet
            prescribes — worked out from each flock&apos;s age. VisibilityCore does not recommend any schedule; it only
            reminds you of the one you write.
          </p>
        </div>
        <Button variant="outline" onClick={() => void loadAll()} disabled={loading} className="h-10">
          <RefreshCw className={loading ? "h-4 w-4 mr-1 animate-spin" : "h-4 w-4 mr-1"} /> Refresh
        </Button>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Tile label="Overdue" value={summary?.overdue} tone="rose" onClick={() => { setTab("tasks"); setView("Overdue") }} />
        <Tile label="Due now" value={summary?.due} tone="amber" onClick={() => { setTab("tasks"); setView("Due") }} />
        <Tile label="Coming up" value={summary?.upcoming} tone="blue" onClick={() => { setTab("tasks"); setView("Upcoming") }} />
        <Tile label="Completed (30 days)" value={summary?.completedLast30} tone="emerald" onClick={() => { setTab("tasks"); setView("Completed") }} />
      </div>

      <Tabs value={tab} onValueChange={(v) => setTab(v as typeof tab)}>
        <TabsList className={tabListCls}>
          <TabsTrigger value="tasks" className={tabTriggerCls}>
            <ListChecks className="h-4 w-4" /> Tasks
            {summary && summary.overdue + summary.due > 0 && <span className={tabCountCls} title="Due or overdue">{summary.overdue + summary.due}</span>}
          </TabsTrigger>
          <TabsTrigger value="plans" className={tabTriggerCls}>
            <ClipboardList className="h-4 w-4" /> Plans
            <span className={tabCountCls}>{templates.filter((t) => t.isActive).length}</span>
          </TabsTrigger>
          <TabsTrigger value="assignments" className={tabTriggerCls}>
            <Link2 className="h-4 w-4" /> Assignments
            <span className={tabCountCls}>{assignments.length}</span>
          </TabsTrigger>
        </TabsList>

        {/* ------------------------------------------------------------- tasks */}
        <TabsContent value="tasks" className="space-y-3">
          <div className="flex flex-col sm:flex-row gap-2">
            <Select value={view} onValueChange={(v) => setView(v as LifecycleView)}>
              <SelectTrigger className="sm:w-52 h-10"><SelectValue /></SelectTrigger>
              <SelectContent>{VIEWS.map((v) => <SelectItem key={v.value} value={v.value}>{v.label}</SelectItem>)}</SelectContent>
            </Select>
            <Select value={flockFilter} onValueChange={setFlockFilter}>
              <SelectTrigger className="sm:w-64 h-10"><SelectValue placeholder="All flocks" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All flocks</SelectItem>
                {openFlocks.map((f) => <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name}{f.batchName ? ` · ${f.batchName}` : ""}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          {estimatedShown && (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-2.5 text-sm text-amber-900 flex gap-2">
              <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
              Dates marked <strong>Estimated</strong> come from a flock whose start date was worked out from an age entered during farm setup.
            </div>
          )}

          {loading ? (
            <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : tasks.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500 space-y-2">
              {assignments.length === 0 ? (
                <>
                  <div>No flock follows a lifecycle plan yet.</div>
                  <div className="text-sm">Write a plan on the <button className="text-blue-700 underline" onClick={() => setTab("plans")}>Plans</button> tab, then assign it to a batch.</div>
                </>
              ) : <div>Nothing here — you&apos;re up to date.</div>}
            </CardContent></Card>
          ) : (
            <div className="space-y-2">
              {tasksPg.pageItems.map((t) => {
                const key = `${t.flockId}-${t.milestoneId}`
                const href = lifecycleActionHref(t)
                const done = t.status === "Completed" || t.status === "Skipped"
                return (
                  <div key={key} className="rounded-lg border border-slate-200 bg-white p-3 space-y-2">
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <div className="min-w-0">
                        <div className="font-medium text-slate-900">{t.title}</div>
                        <div className="text-sm text-slate-600">{taskSentence(t)}</div>
                      </div>
                      <div className="flex flex-wrap items-center gap-1.5">
                        <Badge variant="outline" className={STATUS_TONE[t.status]}>{t.status}</Badge>
                        {t.isEstimated && <Badge variant="outline" className="border-amber-300 text-amber-800 bg-amber-50">Estimated</Badge>}
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-500">
                      <span>{milestoneAgeLabel(t.ageUnit, t.ageValue)} · due {day(t.dueDate)}{t.ageUnit === "Week" ? `–${day(t.dueWindowEnd)}` : ""}</span>
                      <span>{dueLabel(t)}</span>
                      <span>Flock age {formatAgeDays(t.currentAgeDays)}</span>
                      <span>{t.templateName}{t.assignedVia === "Batch" ? ` (via batch ${t.batchCode ?? ""})` : ""}</span>
                      {t.category && <span>{t.category}</span>}
                    </div>
                    {t.description && <p className="text-sm text-slate-700 whitespace-pre-wrap">{t.description}</p>}
                    {done && (
                      <p className="text-xs text-slate-500">
                        {t.status} {t.actedAt ? fmtInstant(t.actedAt) : ""}{t.actedBy ? ` by ${t.actedBy}` : ""}{t.note ? ` — ${t.note}` : ""}
                      </p>
                    )}
                    <div className="flex flex-wrap gap-2">
                      {href && (
                        <Button asChild size="sm" variant="outline" className="h-9">
                          <Link href={href}><ExternalLink className="h-4 w-4 mr-1" /> {actionLabel(t.actionType)}</Link>
                        </Button>
                      )}
                      {canEdit && !done && t.status !== "Scheduled" && (
                        <>
                          <Button size="sm" className="h-9" disabled={busyKey === key} onClick={() => void complete(t)}>
                            {busyKey === key ? <Loader2 className="h-4 w-4 animate-spin" /> : <><CheckCircle2 className="h-4 w-4 mr-1" /> Complete</>}
                          </Button>
                          <Button size="sm" variant="outline" className="h-9" onClick={() => setSkipping(t)}>
                            <SkipForward className="h-4 w-4 mr-1" /> Skip
                          </Button>
                        </>
                      )}
                      {canEdit && done && (
                        <Button size="sm" variant="outline" className="h-9" onClick={() => setReopening(t)}>
                          <RotateCcw className="h-4 w-4 mr-1" /> Reopen
                        </Button>
                      )}
                      {t.taskId != null && (
                        <Button size="sm" variant="ghost" className="h-9" onClick={() => setHistoryFor(t)}>
                          <History className="h-4 w-4 mr-1" /> History
                        </Button>
                      )}
                    </div>
                  </div>
                )
              })}
              <DataPagination {...tasksPg.paginationProps} />
            </div>
          )}
        </TabsContent>

        {/* ------------------------------------------------------------- plans */}
        <TabsContent value="plans" className="space-y-3">
          <div className="flex justify-between items-center gap-2">
            <p className="text-sm text-slate-600">Each plan is a list of milestones at ages your farm chooses.</p>
            {canCreate && (
              <Button onClick={() => setPlanEditor({ open: true, template: null })}><Plus className="h-4 w-4 mr-1" /> New plan</Button>
            )}
          </div>
          {templates.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500">No plans yet. Plans are written by your farm — none are built in.</CardContent></Card>
          ) : (
            <div className="grid gap-3 md:grid-cols-2">
              {templates.map((t) => (
                <Card key={t.templateId} className={cn(!t.isActive && "opacity-60")}>
                  <CardContent className="p-4 space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <div className="font-semibold text-slate-900">{t.name}</div>
                        <div className="text-xs text-slate-500">{t.breed ? `For ${t.breed}` : "Any breed"}{!t.isActive && " · Inactive"}</div>
                      </div>
                      <div className="flex gap-1">
                        {canEdit && (
                          <Button size="sm" variant="ghost" title="Edit plan" onClick={async () => {
                            try { setPlanEditor({ open: true, template: await getLifecycleTemplate(t.templateId) }) }
                            catch (e: any) { toast({ title: "Could not open the plan", description: e?.message, variant: "destructive" }) }
                          }}><Pencil className="h-4 w-4" /></Button>
                        )}
                        {canDelete && (
                          <Button size="sm" variant="ghost" title="Delete plan" onClick={() => setDeletingPlan(t)}><Trash2 className="h-4 w-4 text-rose-600" /></Button>
                        )}
                      </div>
                    </div>
                    {t.description && <p className="text-sm text-slate-600">{t.description}</p>}
                    <div className="text-xs text-slate-500">
                      {t.milestoneCount} milestone{t.milestoneCount === 1 ? "" : "s"} · used by {t.assignedBatches} batch{t.assignedBatches === 1 ? "" : "es"} and {t.assignedFlocks} flock{t.assignedFlocks === 1 ? "" : "s"} directly
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </TabsContent>

        {/* ------------------------------------------------------- assignments */}
        <TabsContent value="assignments" className="space-y-3">
          <div className="flex justify-between items-center gap-2">
            <p className="text-sm text-slate-600">
              Assign a plan to a <strong>batch</strong> and all its flocks follow it; assign one to a <strong>flock</strong> to override its batch.
            </p>
            {canCreate && (
              <Button onClick={() => setAssignOpen(true)} disabled={templates.filter((t) => t.isActive).length === 0}>
                <Plus className="h-4 w-4 mr-1" /> Assign plan
              </Button>
            )}
          </div>
          {assignments.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500">No plan is assigned yet.</CardContent></Card>
          ) : (
            <div className="space-y-2">
              {assignments.map((a) => (
                <div key={a.assignmentId} className="rounded-lg border border-slate-200 bg-white p-3 flex flex-wrap items-center justify-between gap-2">
                  <div className="min-w-0">
                    <div className="font-medium text-slate-900">
                      {a.batchId ? <>Batch {a.batchCode}{a.batchName ? ` · ${a.batchName}` : ""}</> : <>Flock {a.flockName}</>}
                      <span className="text-slate-500 font-normal"> → {a.templateName}</span>
                    </div>
                    <div className="text-xs text-slate-500">
                      {a.batchId ? `${a.flockCount} open flock${a.flockCount === 1 ? "" : "s"}` : "Overrides its batch"}
                      {" · "}age at start {a.ageAtStartDays === 0 ? "day-old" : formatAgeDays(a.ageAtStartDays)}
                    </div>
                    {a.breedMismatch && (
                      <div className="text-xs text-amber-700 flex items-center gap-1 mt-0.5">
                        <AlertTriangle className="h-3.5 w-3.5" /> Plan written for {a.templateBreed}; this is {a.targetBreed}.
                      </div>
                    )}
                  </div>
                  {canDelete && (
                    <Button size="sm" variant="outline" onClick={() => setRemovingAssignment(a)}>
                      <Unlink className="h-4 w-4 mr-1" /> Remove
                    </Button>
                  )}
                </div>
              ))}
            </div>
          )}
        </TabsContent>
      </Tabs>

      <PlanEditorDialog
        open={planEditor.open}
        template={planEditor.template}
        onOpenChange={(o) => setPlanEditor((p) => ({ ...p, open: o }))}
        onSaved={async () => { setPlanEditor({ open: false, template: null }); await loadAll() }}
      />
      <AssignDialog
        open={assignOpen}
        onOpenChange={setAssignOpen}
        templates={templates.filter((t) => t.isActive)}
        batches={batches}
        flocks={openFlocks}
        onSaved={async () => { setAssignOpen(false); await loadAll() }}
      />
      <HistoryDialog task={historyFor} onClose={() => setHistoryFor(null)} />

      <PromptDialog
        open={skipping != null}
        onOpenChange={(o) => { if (!o) setSkipping(null) }}
        title={skipping ? `Skip "${skipping.title}"?` : "Skip task"}
        description={skipping ? `${skipping.flockName}. The reason is kept in the task's history.` : undefined}
        label="Why is it being skipped?"
        confirmLabel="Skip task"
        onSubmit={async (note) => {
          if (!skipping) return
          try {
            await setLifecycleTaskStatus({ flockId: skipping.flockId, milestoneId: skipping.milestoneId, status: "Skipped", note })
            toast({ title: "Task skipped" }); setSkipping(null); await loadTasks()
          } catch (e: any) { toast({ title: "Could not skip the task", description: e?.message, variant: "destructive" }); throw e }
        }}
      />
      <PromptDialog
        open={reopening != null}
        onOpenChange={(o) => { if (!o) setReopening(null) }}
        title={reopening ? `Reopen "${reopening.title}"?` : "Reopen task"}
        description="It goes back to the list with its current status. The earlier completion stays in the history."
        label="Note (optional)"
        allowEmpty
        confirmLabel="Reopen"
        onSubmit={async (note) => {
          if (!reopening) return
          try {
            await setLifecycleTaskStatus({ flockId: reopening.flockId, milestoneId: reopening.milestoneId, status: "Open", note: note || null })
            toast({ title: "Task reopened" }); setReopening(null); await loadTasks()
          } catch (e: any) { toast({ title: "Could not reopen the task", description: e?.message, variant: "destructive" }); throw e }
        }}
      />
      <ConfirmDeleteDialog
        open={removingAssignment != null}
        onOpenChange={(o) => { if (!o) setRemovingAssignment(null) }}
        title={removingAssignment
          ? `Remove "${removingAssignment.templateName}" from ${removingAssignment.batchId
            ? `batch ${removingAssignment.batchCode ?? ""}`.trim()
            : `flock ${removingAssignment.flockName ?? ""}`.trim()}?`
          : "Remove assignment"}
        description={removingAssignment && (
          <>
            <span className="block">
              {removingAssignment.batchId
                ? <>Its {removingAssignment.flockCount} open flock{removingAssignment.flockCount === 1 ? "" : "s"} will stop getting these reminders, unless a flock has its own plan.</>
                : <>This flock will go back to its batch&apos;s plan, or get no reminders if the batch has none.</>}
            </span>
            <span className="block mt-2">Completed and skipped tasks and their history are kept. Assigning the plan again brings the reminders back.</span>
          </>
        )}
        confirmLabel="Remove"
        busyLabel="Removing…"
        successTitle="Assignment removed"
        errorTitle="Could not remove it"
        onConfirm={async () => {
          if (!removingAssignment) return
          await removeLifecycleAssignment(removingAssignment.assignmentId)
          setRemovingAssignment(null); await loadAll()
        }}
      />
      <ConfirmDeleteDialog
        open={deletingPlan != null}
        onOpenChange={(o) => { if (!o) setDeletingPlan(null) }}
        title={deletingPlan ? `Delete "${deletingPlan.name}"?` : "Delete plan"}
        description="A plan with task history is retired (made inactive) instead of deleted, so its history stays readable."
        successTitle=""
        errorTitle="Could not delete the plan"
        onConfirm={async () => {
          if (!deletingPlan) return
          const r = await deleteLifecycleTemplate(deletingPlan.templateId)
          toast({ title: r.outcome === "Retired" ? "Plan retired (it has history)" : "Plan deleted" })
          setDeletingPlan(null); await loadAll()
        }}
      />
    </Shell>
  )
}

function Shell({ children, logout }: { children: React.ReactNode; logout: () => void }) {
  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">{children}</main>
      </div>
    </div>
  )
}

const TILE_TONES = {
  rose: "bg-rose-100 border-rose-300 text-rose-800",
  amber: "bg-amber-100 border-amber-300 text-amber-800",
  blue: "bg-blue-100 border-blue-300 text-blue-800",
  emerald: "bg-emerald-100 border-emerald-300 text-emerald-800",
}

function Tile({ label, value, tone, onClick }: { label: string; value?: number; tone: keyof typeof TILE_TONES; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className={cn("rounded-lg border px-3 py-2 shadow-sm text-left", TILE_TONES[tone])}>
      <div className="text-xs">{label}</div>
      <div className="text-xl font-semibold tabular-nums">{value ?? "—"}</div>
    </button>
  )
}

// ------------------------------------------------------------- plan editor --
interface MilestoneRow extends LifecycleMilestone { key: number }

function PlanEditorDialog({ open, template, onOpenChange, onSaved }: {
  open: boolean; template: LifecycleTemplate | null; onOpenChange: (o: boolean) => void; onSaved: () => void | Promise<void>
}) {
  const { toast } = useToast()
  const [name, setName] = useState("")
  const [breed, setBreed] = useState("")
  const [description, setDescription] = useState("")
  const [isActive, setIsActive] = useState(true)
  const [rows, setRows] = useState<MilestoneRow[]>([])
  const [errors, setErrors] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const [nextKey, setNextKey] = useState(1)

  useEffect(() => {
    if (!open) return
    setName(template?.name ?? ""); setBreed(template?.breed ?? ""); setDescription(template?.description ?? "")
    setIsActive(template?.isActive ?? true); setErrors([])
    const ms = (template?.milestones ?? []).map((m, i) => ({ ...m, key: i + 1 }))
    setRows(ms.length ? ms : [{ key: 1, ageUnit: "Week", ageValue: 0, title: "", leadTimeDays: 3 }])
    setNextKey(ms.length + 2)
  }, [open, template])

  const set = (key: number, patch: Partial<MilestoneRow>) => setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...patch } : r)))

  async function save() {
    const errs = validatePlan(name, rows.map((r) => ({ title: r.title, ageUnit: r.ageUnit, ageValue: r.ageValue, leadTimeDays: r.leadTimeDays })))
    setErrors(errs)
    if (errs.length) return
    setSaving(true)
    try {
      const input = {
        name: name.trim(), breed: breed.trim() || null, description: description.trim() || null, isActive,
        milestones: rows.map(({ key, ...m }) => ({ ...m, title: m.title.trim(), actionType: m.actionType || null })),
      }
      if (template) await updateLifecycleTemplate(template.templateId, input)
      else await createLifecycleTemplate(input)
      toast({ title: template ? "Plan saved" : "Plan created" })
      await onSaved()
    } catch (e: any) {
      toast({ title: "Could not save the plan", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] max-w-[1000px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{template ? `Edit "${template.name}"` : "New lifecycle plan"}</DialogTitle>
          <DialogDescription>
            Your farm&apos;s own milestones. Ages are the birds&apos; age, in days or weeks. Lead time is how many days ahead the reminder appears.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-3 sm:grid-cols-2">
          <div><label className="text-xs text-slate-500">Plan name *</label><Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Our layer plan" /></div>
          <div><label className="text-xs text-slate-500">Breed (optional)</label><Input value={breed} onChange={(e) => setBreed(e.target.value)} placeholder="Any breed" /></div>
          <div className="sm:col-span-2"><label className="text-xs text-slate-500">Description</label><Textarea rows={2} value={description} onChange={(e) => setDescription(e.target.value)} /></div>
          <div className="flex items-center gap-2"><Switch checked={isActive} onCheckedChange={setIsActive} /><span className="text-sm text-slate-700">Active</span></div>
        </div>

        <div className="space-y-2">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">Milestones</div>
          {rows.map((r, idx) => (
            <div key={r.key} className="rounded-lg border border-slate-200 p-3 space-y-2">
              <div className="grid grid-cols-2 sm:grid-cols-12 gap-2 items-end">
                <div className="col-span-1 sm:col-span-2">
                  <label className="text-xs text-slate-500">Age</label>
                  <NumberInput min={0} step="1" value={r.ageValue} onChange={(e) => set(r.key, { ageValue: Math.floor(Number(e.target.value) || 0) })} />
                </div>
                <div className="col-span-1 sm:col-span-2">
                  <label className="text-xs text-slate-500">Unit</label>
                  <Select value={r.ageUnit} onValueChange={(v) => set(r.key, { ageUnit: v as LifecycleAgeUnit })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{AGE_UNITS.map((u) => <SelectItem key={u} value={u}>{u === "Week" ? "Weeks" : "Days"}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                <div className="col-span-2 sm:col-span-5">
                  <label className="text-xs text-slate-500">Title * (Milestone {idx + 1})</label>
                  <Input value={r.title} onChange={(e) => set(r.key, { title: e.target.value })} placeholder="e.g. Review housing" />
                </div>
                <div className="col-span-1 sm:col-span-2">
                  <label className="text-xs text-slate-500">Lead time (days)</label>
                  <NumberInput min={0} step="1" value={r.leadTimeDays} onChange={(e) => set(r.key, { leadTimeDays: Math.floor(Number(e.target.value) || 0) })} />
                </div>
                <div className="col-span-1 sm:col-span-1 flex justify-end">
                  {rows.length > 1 && (
                    <Button type="button" size="sm" variant="ghost" className="text-rose-600" title="Remove milestone"
                      onClick={() => setRows((rs) => rs.filter((x) => x.key !== r.key))}><Trash2 className="h-4 w-4" /></Button>
                  )}
                </div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-12 gap-2">
                <div className="sm:col-span-3">
                  <label className="text-xs text-slate-500">Category</label>
                  <SuggestInput value={r.category ?? ""} onChange={(v) => set(r.key, { category: v })} suggestions={CATEGORY_SUGGESTIONS} placeholder="e.g. Housing" />
                </div>
                <div className="sm:col-span-3">
                  <label className="text-xs text-slate-500">Action link (optional)</label>
                  <Select value={r.actionType ?? "none"} onValueChange={(v) => set(r.key, { actionType: v === "none" ? null : (v as LifecycleActionType) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">No link</SelectItem>
                      {ACTION_TYPES.map((a) => <SelectItem key={a.value} value={a.value}>{a.label}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="sm:col-span-6">
                  <label className="text-xs text-slate-500">Description</label>
                  <Input value={r.description ?? ""} onChange={(e) => set(r.key, { description: e.target.value })} placeholder="What to check or prepare" />
                </div>
              </div>
            </div>
          ))}
          <Button type="button" variant="outline" size="sm" onClick={() => { setRows((rs) => [...rs, { key: nextKey, ageUnit: "Week", ageValue: 0, title: "", leadTimeDays: 3 }]); setNextKey((k) => k + 1) }}>
            <Plus className="h-4 w-4 mr-1" /> Add milestone
          </Button>
          {template && <p className="text-xs text-slate-500">Removing a milestone that already has task history retires it instead of deleting it.</p>}
        </div>

        {errors.length > 0 && (
          <div className="rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800 space-y-1">
            {errors.map((e) => <div key={e}>{e}</div>)}
          </div>
        )}
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={() => void save()} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save plan"}</Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ------------------------------------------------------------ assign dialog --
function AssignDialog({ open, onOpenChange, templates, batches, flocks, onSaved }: {
  open: boolean; onOpenChange: (o: boolean) => void; templates: LifecycleTemplate[]
  batches: FlockBatch[]; flocks: Flock[]; onSaved: () => void | Promise<void>
}) {
  const { toast } = useToast()
  const [templateId, setTemplateId] = useState("")
  const [target, setTarget] = useState<"batch" | "flock">("batch")
  const [targetId, setTargetId] = useState("")
  const [weeks, setWeeks] = useState(0)
  const [days, setDays] = useState(0)
  const [saving, setSaving] = useState(false)

  useEffect(() => { if (open) { setTemplateId(""); setTarget("batch"); setTargetId(""); setWeeks(0); setDays(0) } }, [open])

  const tpl = templates.find((t) => String(t.templateId) === templateId)
  const targetBreed = target === "batch"
    ? batches.find((b) => String(b.batchId) === targetId)?.breed
    : flocks.find((f) => String(f.flockId) === targetId)?.breed
  const mismatch = Boolean(tpl?.breed && targetBreed && tpl.breed.trim().toLowerCase() !== targetBreed.trim().toLowerCase())

  async function save() {
    if (!templateId || !targetId) { toast({ title: "Choose a plan and a batch or flock", variant: "destructive" }); return }
    setSaving(true)
    try {
      await assignLifecycleTemplate({
        templateId: Number(templateId),
        batchId: target === "batch" ? Number(targetId) : null,
        flockId: target === "flock" ? Number(targetId) : null,
        ageAtStartDays: ageAtStartDays(weeks, days),
      })
      toast({ title: "Plan assigned" })
      await onSaved()
    } catch (e: any) {
      toast({ title: "Could not assign the plan", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Assign a lifecycle plan</DialogTitle>
          <DialogDescription>Re-assigning a batch or flock replaces its current plan; the old assignment is kept in history.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <label className="text-xs text-slate-500">Plan *</label>
            <Select value={templateId} onValueChange={setTemplateId}>
              <SelectTrigger><SelectValue placeholder="Choose a plan" /></SelectTrigger>
              <SelectContent>{templates.map((t) => <SelectItem key={t.templateId} value={String(t.templateId)}>{t.name}{t.breed ? ` (${t.breed})` : ""}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-2">
            {(["batch", "flock"] as const).map((k) => (
              <button key={k} type="button" onClick={() => { setTarget(k); setTargetId("") }}
                className={cn("rounded-lg border p-2.5 text-left text-sm", target === k ? "border-indigo-500 bg-indigo-50 ring-1 ring-indigo-500" : "border-slate-200")}>
                <div className="font-medium">{k === "batch" ? "A batch" : "One flock"}</div>
                <div className="text-xs text-slate-500">{k === "batch" ? "All its flocks follow it" : "Overrides its batch's plan"}</div>
              </button>
            ))}
          </div>
          <div>
            <label className="text-xs text-slate-500">{target === "batch" ? "Batch *" : "Flock *"}</label>
            <Select value={targetId} onValueChange={setTargetId}>
              <SelectTrigger><SelectValue placeholder={target === "batch" ? "Choose a batch" : "Choose a flock"} /></SelectTrigger>
              <SelectContent>
                {target === "batch"
                  ? batches.map((b) => <SelectItem key={b.batchId} value={String(b.batchId)}>{b.batchCode} · {b.batchName}</SelectItem>)
                  : flocks.map((f) => <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name}{f.batchName ? ` · ${f.batchName}` : ""}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div>
            <label className="text-xs text-slate-500">Birds&apos; age on the flock&apos;s start date</label>
            <div className="grid grid-cols-2 gap-2">
              <div className="flex items-center gap-2"><NumberInput min={0} step="1" value={weeks} onChange={(e) => setWeeks(Number(e.target.value) || 0)} /><span className="text-sm text-slate-500">weeks</span></div>
              <div className="flex items-center gap-2"><NumberInput min={0} step="1" value={days} onChange={(e) => setDays(Number(e.target.value) || 0)} /><span className="text-sm text-slate-500">days</span></div>
            </div>
            <p className="text-xs text-slate-500 mt-1">Leave at 0 for day-old chicks. For birds bought older (e.g. point-of-lay pullets), enter their age when they arrived.</p>
          </div>
          {mismatch && (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-2.5 text-sm text-amber-900 flex gap-2">
              <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" /> This plan was written for {tpl?.breed}; this is {targetBreed}. You can still assign it.
            </div>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={() => void save()} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Assign"}</Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ----------------------------------------------------------- history dialog --
function HistoryDialog({ task, onClose }: { task: LifecycleTask | null; onClose: () => void }) {
  const [events, setEvents] = useState<LifecycleTaskEvent[] | null>(null)
  useEffect(() => {
    setEvents(null)
    if (!task) return
    getLifecycleTaskHistory(task.flockId, task.milestoneId).then(setEvents).catch(() => setEvents([]))
  }, [task])
  return (
    <Dialog open={task != null} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        {task && (
          <>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2"><History className="h-5 w-5" /> {task.title}</DialogTitle>
              <DialogDescription>{task.flockName} · {milestoneAgeLabel(task.ageUnit, task.ageValue)} · due {day(task.dueDate)}</DialogDescription>
            </DialogHeader>
            {events == null ? (
              <div className="p-4 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : events.length === 0 ? (
              <p className="text-sm text-slate-500">No history yet.</p>
            ) : (
              <div className="space-y-2">
                {events.map((e) => (
                  <div key={e.eventId} className="rounded-md border p-3">
                    <div className="text-sm font-medium text-slate-800">{e.fromStatus} → {e.toStatus}</div>
                    <div className="text-xs text-slate-500">{fmtInstant(e.atUtc)}{e.actor ? ` · ${e.actor}` : ""}</div>
                    {e.note && <p className="text-sm text-slate-700 mt-1">{e.note}</p>}
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}

export default function PoultryLifecyclePage() {
  return (
    <Suspense fallback={null}>
      <LifecycleInner />
    </Suspense>
  )
}

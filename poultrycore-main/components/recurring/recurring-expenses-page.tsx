"use client"

// Recurring Expenses (migration 348) -- ONE page for every company type.
//
//   To review   drafts the engine raised when they fell due: edit the amount,
//               date or cash account, then Post or Skip
//   Upcoming    what falls due in the next 7 / 30 days (not raised yet)
//   Templates   the recurring expenses themselves: create, edit, pause,
//               resume, end
//
// Posting hands the draft to the company's OWN Expenses module, through the
// same service its Expenses page uses -- so cash, payables and approvals are
// that module's. In Water, Generic and Hotel the expense then waits for
// approval there, exactly like one typed in by hand.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import {
  AlertTriangle, CalendarClock, CheckCircle2, Loader2, Lock, Pause, Pencil, Play, Plus, Repeat,
  RotateCcw, SkipForward, Square, Trash2, Unlink, Inbox, CalendarDays,
} from "lucide-react"
import { filterGroupCls, filterLabelCls, filterPillCls, tabCountCls, tabListCls, tabTriggerCls } from "@/lib/ui/tab-styles"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { usePermissions } from "@/hooks/use-permissions"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { fmtInstant } from "@/lib/utils/company-datetime"
import {
  createRecurringTemplate, deleteRecurringTemplate, editRecurringOccurrence, generateRecurringExpenses,
  linkRecurringOccurrence, listRecurringOccurrences, listRecurringTemplates, listUpcomingRecurring,
  loadModuleLookups, moduleForFarmType, postRecurringOccurrence, releaseRecurringOccurrence,
  restoreRecurringOccurrence, setRecurringTemplateStatus, skipRecurringOccurrence, updateRecurringTemplate,
  type ModuleLookups, type RecurringFrequency, type RecurringOccurrence, type RecurringTemplate,
  type RecurringTemplateInput, type RecurringUpcoming,
} from "@/lib/api/recurring-expenses"
import { FREQUENCIES, frequencyLabel, paymentEffect, previewDates, validateTemplate } from "@/lib/recurring/recurring-expense"

const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Card", "Credit"]
const day = (v?: string | null) => (v ? v.slice(0, 10) : "—")
const OCC_VIEWS: { value: "Open" | "Posted" | "Skipped" | "All"; label: string }[] = [
  { value: "Open", label: "To review" }, { value: "Posted", label: "Posted" },
  { value: "Skipped", label: "Skipped" }, { value: "All", label: "Everything" },
]

const OCC_TONE: Record<string, string> = {
  Draft: "bg-amber-100 text-amber-800 border-amber-300",
  Posting: "bg-blue-100 text-blue-800 border-blue-300",
  Posted: "bg-emerald-100 text-emerald-800 border-emerald-300",
  Skipped: "bg-slate-100 text-slate-500 border-slate-300",
}
const TPL_TONE: Record<string, string> = {
  Active: "bg-emerald-100 text-emerald-800 border-emerald-300",
  Paused: "bg-amber-100 text-amber-800 border-amber-300",
  Ended: "bg-slate-100 text-slate-500 border-slate-300",
}

export default function RecurringExpensesPage() {
  const { toast } = useToast()
  const logout = useLogout()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const module = moduleForFarmType(activeFarmType)

  const canView = permissions.can(`${module}.expenses.view`)
  const canCreate = permissions.can(`${module}.expenses.create`)
  const canEdit = permissions.can(`${module}.expenses.edit`)
  const canDelete = permissions.can(`${module}.expenses.delete`)

  const [tab, setTab] = useState<"review" | "upcoming" | "templates">("review")
  const [lookups, setLookups] = useState<ModuleLookups | null>(null)
  const [templates, setTemplates] = useState<RecurringTemplate[]>([])
  const [occurrences, setOccurrences] = useState<RecurringOccurrence[]>([])
  const [upcoming, setUpcoming] = useState<RecurringUpcoming[]>([])
  const [days, setDays] = useState<7 | 30>(30)
  const [occView, setOccView] = useState<"Open" | "Posted" | "Skipped" | "All">("Open")
  const [loading, setLoading] = useState(true)
  const [editor, setEditor] = useState<{ open: boolean; template: RecurringTemplate | null }>({ open: false, template: null })
  const [reviewing, setReviewing] = useState<RecurringOccurrence | null>(null)
  const [skipping, setSkipping] = useState<RecurringOccurrence | null>(null)
  const [ending, setEnding] = useState<RecurringTemplate | null>(null)
  const [linking, setLinking] = useState<RecurringOccurrence | null>(null)
  const [busy, setBusy] = useState<number | null>(null)

  useEffect(() => {
    if (!activeFarmType) return
    void (async () => {
      setLoading(true)
      try {
        // Raise anything that has fallen due first. Idempotent: opening this
        // page twice, or alongside the scheduler, never raises a period twice.
        if (canCreate) {
          const g = await generateRecurringExpenses().catch(() => null)
          if (g && g.autoPostFailures.length) {
            toast({ title: "Some automatic posts need attention", description: g.autoPostFailures.join("; "), variant: "destructive" })
          }
        }
        setLookups(await loadModuleLookups(module))
        await reload()
      } finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  useEffect(() => { if (!loading) void reloadOccurrences() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [occView])
  useEffect(() => { if (!loading) void listUpcomingRecurring(days).then(setUpcoming).catch(() => {}) /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [days])

  async function reloadOccurrences() {
    setOccurrences(await listRecurringOccurrences(occView).catch(() => []))
  }
  async function reload() {
    try {
      const [t, u] = await Promise.all([listRecurringTemplates(), listUpcomingRecurring(days)])
      setTemplates(t); setUpcoming(u)
      await reloadOccurrences()
    } catch (e: any) {
      toast({ title: "Could not load recurring expenses", description: e?.message, variant: "destructive" })
    }
  }

  async function post(o: RecurringOccurrence) {
    // "Paid" with no cash account would be recorded as paid while no money
    // leaves any account, so send the user to choose one first.
    if (o.paymentMethod !== "Credit" && !o.cashAccountId) {
      toast({ title: "Choose a cash account first", description: "Pick the account this is paid from, then post." })
      setReviewing(o)
      return
    }
    setBusy(o.occurrenceId)
    try {
      const r = await postRecurringOccurrence(o.occurrenceId)
      toast({ title: `${o.templateName} posted`, description: r.message })
      setReviewing(null)
      await reload()
    } catch (e: any) {
      toast({ title: "Could not post it", description: e?.message, variant: "destructive" })
      await reloadOccurrences()
    } finally { setBusy(null) }
  }

  const cashName = (id?: number | null) => lookups?.cashAccounts.find((a) => a.id === id)?.name
  const supplierName = (id?: number | null) => lookups?.suppliers.find((s) => s.id === id)?.name
  const drafts = occurrences.filter((o) => o.status === "Draft" || o.status === "Posting")
  const draftTotal = drafts.reduce((s, o) => s + o.amount, 0)
  const upcomingTotal = upcoming.reduce((s, u) => s + u.amount, 0)

  if (!permissions.isLoading && !canView) {
    return (
      <Shell logout={logout}>
        <Card><CardContent className="p-8 text-center text-slate-600">
          <Lock className="mx-auto mb-2 h-6 w-6 text-slate-400" /> You do not have access to expenses in this company.
        </CardContent></Card>
      </Shell>
    )
  }

  return (
    <Shell logout={logout}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
            <Repeat className="h-6 w-6 text-indigo-600" /> Recurring Expenses
          </h1>
          <p className="text-sm text-slate-600 max-w-3xl">
            Rent, security, internet, software, waste collection — set it up once. When one falls due it waits here as a
            <strong> draft</strong> for you to check and post; nothing is paid or recorded until you do.
            {lookups?.moduleApproves && <> Posted expenses then follow the normal approval on <Link className="text-blue-700 hover:underline" href={lookups.expensesHref}>Expenses</Link>.</>}
          </p>
        </div>
        {canCreate && <Button onClick={() => setEditor({ open: true, template: null })} className="h-10"><Plus className="h-4 w-4 mr-1" /> New recurring expense</Button>}
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Tile label="Drafts to review" value={String(drafts.length)} tone="amber" />
        <Tile label="Drafts total" value={gh(draftTotal)} tone="amber" />
        <Tile label={`Due in next ${days} days`} value={String(upcoming.length)} tone="blue" />
        <Tile label="Expected" value={gh(upcomingTotal)} tone="blue" />
      </div>

      <Tabs value={tab} onValueChange={(v) => setTab(v as typeof tab)}>
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <TabsList className={tabListCls}>
          <TabsTrigger value="review" className={tabTriggerCls}>
            <Inbox className="h-4 w-4" /> To review
            <span className={tabCountCls}>{drafts.length}</span>
          </TabsTrigger>
          <TabsTrigger value="upcoming" className={tabTriggerCls}>
            <CalendarDays className="h-4 w-4" /> Upcoming
          </TabsTrigger>
          <TabsTrigger value="templates" className={tabTriggerCls}>
            <Repeat className="h-4 w-4" /> Templates
            <span className={tabCountCls}>{templates.length}</span>
          </TabsTrigger>
        </TabsList>
          {tab === "review" && (
            <div className={filterGroupCls} role="group" aria-label="Show">
              <span className={filterLabelCls}>Show</span>
              {OCC_VIEWS.map((v) => (
                <button key={v.value} type="button" aria-pressed={occView === v.value} className={filterPillCls(occView === v.value)}
                  onClick={() => setOccView(v.value)}>{v.label}</button>
              ))}
            </div>
          )}
          {tab === "upcoming" && (
            <div className={filterGroupCls} role="group" aria-label="Show">
              <span className={filterLabelCls}>Show</span>
              {([7, 30] as const).map((d) => (
                <button key={d} type="button" aria-pressed={days === d} className={filterPillCls(days === d)}
                  onClick={() => setDays(d)}>Next {d} days</button>
              ))}
            </div>
          )}
        </div>

        {/* ------------------------------------------------------------ review */}
        <TabsContent value="review" className="space-y-3">
          {loading ? (
            <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : occurrences.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500">
              {occView === "Open" ? <span className="inline-flex items-center gap-2"><CheckCircle2 className="h-4 w-4 text-emerald-600" /> Nothing waiting for review.</span> : "Nothing here."}
            </CardContent></Card>
          ) : (
            <div className="space-y-2">
              {occurrences.map((o) => (
                <div key={o.occurrenceId} className="rounded-lg border border-slate-200 bg-white p-3 space-y-2">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="font-medium text-slate-900">{o.templateName}</div>
                      <div className="text-xs text-slate-500">
                        Due {day(o.scheduledDate)} · {o.categoryName ?? "—"}{o.supplierId ? ` · ${supplierName(o.supplierId) ?? "supplier"}` : ""}
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="font-semibold tabular-nums">{gh(o.amount)}</div>
                      {o.isVariable && o.amount === o.templateAmount && o.status === "Draft" && (
                        <div className="text-[11px] text-amber-700">Estimate — confirm the actual amount</div>
                      )}
                      {o.amount !== o.templateAmount && <div className="text-[11px] text-slate-500">usually {gh(o.templateAmount)}</div>}
                    </div>
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5 text-xs">
                    <Badge variant="outline" className={OCC_TONE[o.status]}>{o.isInterrupted ? "Posting interrupted" : o.status}</Badge>
                    <span className="text-slate-500">
                      {o.paymentMethod === "Credit" ? "On credit (will be owed)" : `${o.paymentMethod}${o.cashAccountId ? ` · ${cashName(o.cashAccountId) ?? "account"}` : " · no cash account"}`}
                      {" · "}dated {day(o.expenseDate)}
                    </span>
                    {o.status === "Posted" && <span className="text-slate-500">· expense #{o.expenseId} by {o.postedBy ?? "—"} {o.postedAt ? fmtInstant(o.postedAt) : ""}</span>}
                    {o.status === "Skipped" && <span className="text-slate-500">· {o.skipReason}</span>}
                  </div>
                  {o.note && <p className="text-xs text-slate-600">{o.note}</p>}
                  <div className="flex flex-wrap gap-2">
                    {o.status === "Draft" && canEdit && <Button size="sm" variant="outline" className="h-9" onClick={() => setReviewing(o)}><Pencil className="h-4 w-4 mr-1" /> Review</Button>}
                    {o.status === "Draft" && canCreate && (
                      <Button size="sm" className="h-9" disabled={busy === o.occurrenceId} onClick={() => void post(o)}>
                        {busy === o.occurrenceId ? <Loader2 className="h-4 w-4 animate-spin" /> : <><CheckCircle2 className="h-4 w-4 mr-1" /> Post</>}
                      </Button>
                    )}
                    {o.status === "Draft" && canEdit && <Button size="sm" variant="ghost" className="h-9" onClick={() => setSkipping(o)}><SkipForward className="h-4 w-4 mr-1" /> Skip</Button>}
                    {o.status === "Skipped" && canEdit && (
                      <Button size="sm" variant="outline" className="h-9" onClick={async () => {
                        try { await restoreRecurringOccurrence(o.occurrenceId); toast({ title: "Restored to draft" }); await reloadOccurrences() }
                        catch (e: any) { toast({ title: "Could not restore it", description: e?.message, variant: "destructive" }) }
                      }}><RotateCcw className="h-4 w-4 mr-1" /> Restore</Button>
                    )}
                    {o.isInterrupted && canEdit && (
                      <>
                        <Button size="sm" variant="outline" className="h-9" onClick={() => setLinking(o)}><Unlink className="h-4 w-4 mr-1" /> It was recorded — link it</Button>
                        <Button size="sm" variant="outline" className="h-9" onClick={async () => {
                          try { await releaseRecurringOccurrence(o.occurrenceId, "Checked Expenses: not recorded"); toast({ title: "Back to draft" }); await reloadOccurrences() }
                          catch (e: any) { toast({ title: "Could not release it", description: e?.message, variant: "destructive" }) }
                        }}>It wasn&apos;t — back to draft</Button>
                      </>
                    )}
                  </div>
                  {o.isInterrupted && (
                    <p className="text-xs text-amber-800 flex gap-1"><AlertTriangle className="h-3.5 w-3.5 mt-0.5" /> Posting started {o.claimedAt ? fmtInstant(o.claimedAt) : ""} and never finished. Check <Link className="underline" href={lookups?.expensesHref ?? "#"}>Expenses</Link> for it before choosing.</p>
                  )}
                </div>
              ))}
            </div>
          )}
        </TabsContent>

        {/* ---------------------------------------------------------- upcoming */}
        <TabsContent value="upcoming" className="space-y-3">
          {upcoming.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500">Nothing falls due in the next {days} days.</CardContent></Card>
          ) : (
            <div className="space-y-2">
              {upcoming.map((u) => (
                <div key={`${u.templateId}-${u.occurrenceNo}`} className="rounded-lg border border-slate-200 bg-white p-3 flex items-center justify-between gap-2">
                  <div>
                    <div className="font-medium text-slate-900">{u.name}</div>
                    <div className="text-xs text-slate-500">{day(u.scheduledDate)} · {u.daysAway === 1 ? "tomorrow" : `in ${u.daysAway} days`} · {frequencyLabel(u.frequency)}</div>
                  </div>
                  <div className="text-right">
                    <div className="font-semibold tabular-nums">{gh(u.amount)}</div>
                    {u.isVariable && <div className="text-[11px] text-slate-500">estimate</div>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </TabsContent>

        {/* --------------------------------------------------------- templates */}
        <TabsContent value="templates" className="space-y-2">
          {templates.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500">No recurring expenses yet.</CardContent></Card>
          ) : templates.map((t) => (
            <div key={t.templateId} className={cn("rounded-lg border border-slate-200 bg-white p-3 space-y-2", t.status === "Ended" && "opacity-70")}>
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="font-medium text-slate-900 flex items-center gap-2">
                    {t.name} <Badge variant="outline" className={TPL_TONE[t.status]}>{t.status}</Badge>
                    {t.approvalMode === "AutoPost" && <Badge variant="outline">Posts automatically</Badge>}
                  </div>
                  <div className="text-xs text-slate-500">
                    {frequencyLabel(t.frequency)} from {day(t.startDate)}{t.endDate ? ` to ${day(t.endDate)}` : ""} · {t.categoryName ?? "—"}
                    {t.nextDueDate && t.status === "Active" ? ` · next ${day(t.nextDueDate)}` : ""}
                  </div>
                  <div className="text-xs text-slate-500">{t.posted} posted · {t.drafts} waiting · {t.skipped} skipped{t.endReason ? ` · ended: ${t.endReason}` : ""}</div>
                </div>
                <div className="text-right">
                  <div className="font-semibold tabular-nums">{gh(t.amount)}</div>
                  {t.isVariable && <div className="text-[11px] text-slate-500">varies</div>}
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                {canEdit && t.status !== "Ended" && <Button size="sm" variant="outline" onClick={() => setEditor({ open: true, template: t })}><Pencil className="h-4 w-4 mr-1" /> Edit</Button>}
                {canEdit && t.status === "Active" && <Button size="sm" variant="outline" onClick={() => void act(t, "Pause")}><Pause className="h-4 w-4 mr-1" /> Pause</Button>}
                {canEdit && t.status === "Paused" && <Button size="sm" variant="outline" onClick={() => void act(t, "Resume")}><Play className="h-4 w-4 mr-1" /> Resume</Button>}
                {canEdit && t.status !== "Ended" && <Button size="sm" variant="ghost" onClick={() => setEnding(t)}><Square className="h-4 w-4 mr-1" /> End</Button>}
                {canDelete && t.posted + t.drafts + t.skipped === 0 && (
                  <Button size="sm" variant="ghost" className="text-rose-600" onClick={async () => {
                    try { await deleteRecurringTemplate(t.templateId); toast({ title: "Deleted" }); await reload() }
                    catch (e: any) { toast({ title: "Could not delete it", description: e?.message, variant: "destructive" }) }
                  }}><Trash2 className="h-4 w-4 mr-1" /> Delete</Button>
                )}
              </div>
            </div>
          ))}
        </TabsContent>
      </Tabs>

      {lookups && (
        <TemplateEditor
          open={editor.open} template={editor.template} lookups={lookups}
          onOpenChange={(o) => setEditor((e) => ({ ...e, open: o }))}
          onSaved={async () => {
            setEditor({ open: false, template: null })
            await generateRecurringExpenses().catch(() => null)
            await reload()
          }}
        />
      )}
      {lookups && (
        <ReviewDialog occurrence={reviewing} lookups={lookups} busy={busy != null}
          onClose={() => setReviewing(null)}
          onSaved={async (andPost, saved) => {
            const o = reviewing
            await reloadOccurrences()
            if (andPost && o) await post({ ...o, ...saved }); else setReviewing(null)
          }} />
      )}
      <PromptDialog
        open={skipping != null} onOpenChange={(o) => { if (!o) setSkipping(null) }}
        title={skipping ? `Skip ${skipping.templateName} (${day(skipping.scheduledDate)})?` : "Skip"}
        description="Nothing is recorded for this period. You can restore it later."
        label="Why?" confirmLabel="Skip"
        onSubmit={async (reason) => {
          if (!skipping) return
          try { await skipRecurringOccurrence(skipping.occurrenceId, reason); toast({ title: "Skipped" }); setSkipping(null); await reloadOccurrences() }
          catch (e: any) { toast({ title: "Could not skip it", description: e?.message, variant: "destructive" }); throw e }
        }}
      />
      <PromptDialog
        open={ending != null} onOpenChange={(o) => { if (!o) setEnding(null) }}
        title={ending ? `End "${ending.name}"?` : "End"}
        description="No more drafts will be raised. Drafts already waiting stay for review, and posted expenses are not touched."
        label="Reason (optional)" allowEmpty confirmLabel="End it" confirmVariant="destructive"
        onSubmit={async (reason) => {
          if (!ending) return
          try { await setRecurringTemplateStatus(ending.templateId, "End", reason || null); toast({ title: "Ended" }); setEnding(null); await reload() }
          catch (e: any) { toast({ title: "Could not end it", description: e?.message, variant: "destructive" }); throw e }
        }}
      />
      <PromptDialog
        open={linking != null} onOpenChange={(o) => { if (!o) setLinking(null) }}
        title="Link the expense that was recorded"
        description="Enter the expense number from the Expenses page, so this period is not recorded twice."
        label="Expense number" singleLine confirmLabel="Link"
        onSubmit={async (v) => {
          if (!linking) return
          const id = Number(v)
          if (!Number.isInteger(id) || id <= 0) { toast({ title: "Enter the expense number", variant: "destructive" }); throw new Error("bad id") }
          try { await linkRecurringOccurrence(linking.occurrenceId, id); toast({ title: "Linked" }); setLinking(null); await reloadOccurrences() }
          catch (e: any) { toast({ title: "Could not link it", description: e?.message, variant: "destructive" }); throw e }
        }}
      />
    </Shell>
  )

  async function act(t: RecurringTemplate, action: "Pause" | "Resume") {
    try {
      await setRecurringTemplateStatus(t.templateId, action)
      toast({ title: action === "Pause" ? "Paused" : "Resumed", description: action === "Resume" ? "It continues from today; periods missed while paused are not raised." : undefined })
      await reload()
    } catch (e: any) { toast({ title: `Could not ${action.toLowerCase()} it`, description: e?.message, variant: "destructive" }) }
  }
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

// The tone colours only apply below lg, where the tiles sit two to a row; on the
// desktop's single row of four they all share the blue.
function Tile({ label, value, tone }: { label: string; value: string; tone: "amber" | "blue" }) {
  return (
    <div className={cn("rounded-lg border px-3 py-2 shadow-sm lg:bg-blue-100 lg:border-blue-300 lg:text-blue-900",
      tone === "amber" ? "bg-amber-100 border-amber-300 text-amber-900" : "bg-blue-100 border-blue-300 text-blue-900")}>
      <div className="text-xs">{label}</div>
      <div className="text-xl font-semibold tabular-nums">{value}</div>
    </div>
  )
}

// ------------------------------------------------------------ template editor
function TemplateEditor({ open, template, lookups, onOpenChange, onSaved }: {
  open: boolean; template: RecurringTemplate | null; lookups: ModuleLookups
  onOpenChange: (o: boolean) => void; onSaved: () => void | Promise<void>
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const today = new Date().toISOString().slice(0, 10)
  const blank: RecurringTemplateInput = {
    name: "", categoryId: null, categoryName: null, supplierId: null, payeeName: null, amount: 0, isVariable: false,
    frequency: "Monthly", startDate: today, endDate: null, paymentMethod: "Cash", cashAccountId: null, description: null, approvalMode: "Draft",
  }
  const [f, setF] = useState<RecurringTemplateInput>(blank)
  const [errors, setErrors] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const frozen = Boolean(template && template.posted + template.drafts + template.skipped > 0)

  useEffect(() => {
    if (!open) return
    setErrors([])
    setF(template ? {
      name: template.name, categoryId: template.categoryId ?? null, categoryName: template.categoryName ?? null,
      supplierId: template.supplierId ?? null, payeeName: template.payeeName ?? null, amount: template.amount,
      isVariable: template.isVariable, frequency: template.frequency, startDate: day(template.startDate),
      endDate: template.endDate ? day(template.endDate) : null, paymentMethod: template.paymentMethod,
      cashAccountId: template.cashAccountId ?? null, description: template.description ?? null, approvalMode: template.approvalMode,
    } : blank)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, template])

  const dates = useMemo(() => (f.startDate ? previewDates(f.startDate, f.frequency, 4, f.endDate) : []), [f.startDate, f.frequency, f.endDate])

  async function save() {
    const errs = validateTemplate({
      name: f.name, amount: f.amount, frequency: f.frequency, startDate: f.startDate, endDate: f.endDate,
      categoryOk: lookups.categoriesAreText ? Boolean(f.categoryName) : Boolean(f.categoryId),
      paymentMethod: f.paymentMethod, supplierId: f.supplierId,
      cashAccountId: f.cashAccountId, approvalMode: f.approvalMode,
    })
    setErrors(errs)
    if (errs.length) return
    setSaving(true)
    try {
      const input = { ...f, categoryName: lookups.categoriesAreText ? f.categoryName : (lookups.categories.find((c) => c.id === f.categoryId)?.name ?? null) }
      if (template) await updateRecurringTemplate(template.templateId, input)
      else await createRecurringTemplate(input)
      toast({ title: template ? "Saved" : "Recurring expense created" })
      await onSaved()
    } catch (e: any) {
      toast({ title: "Could not save it", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  const set = (p: Partial<RecurringTemplateInput>) => setF((x) => ({ ...x, ...p }))
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] max-w-[760px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><CalendarClock className="h-5 w-5" /> {template ? `Edit "${template.name}"` : "New recurring expense"}</DialogTitle>
          <DialogDescription>Each time it falls due, a draft waits for review — nothing is posted on its own unless you choose that below.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Name *" full><Input value={f.name} onChange={(e) => set({ name: e.target.value })} placeholder="e.g. Office rent" /></Field>
          <Field label="Category *">
            {lookups.categoriesAreText ? (
              <Select value={f.categoryName ?? ""} onValueChange={(v) => set({ categoryName: v })}>
                <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                <SelectContent>{lookups.textCategories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            ) : (
              <Select value={f.categoryId ? String(f.categoryId) : ""} onValueChange={(v) => set({ categoryId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                <SelectContent>{lookups.categories.map((c) => <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>)}</SelectContent>
              </Select>
            )}
          </Field>
          <Field label="Supplier / payee">
            <Select value={f.supplierId ? String(f.supplierId) : "none"} onValueChange={(v) => set({ supplierId: v === "none" ? null : Number(v) })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">No supplier</SelectItem>
                {lookups.suppliers.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </Field>
          <Field label="Amount *"><NumberInput min={0} step="0.01" value={f.amount} onChange={(e) => set({ amount: Number(e.target.value) || 0 })} /></Field>
          <Field label="Amount varies">
            <div className="flex items-center gap-2 h-10"><Switch checked={f.isVariable} onCheckedChange={(v) => set({ isVariable: v })} /><span className="text-sm text-slate-600">Treat as an estimate (e.g. electricity)</span></div>
          </Field>
          <Field label="Repeats *">
            <Select value={f.frequency} onValueChange={(v) => set({ frequency: v as RecurringFrequency })} disabled={frozen}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{FREQUENCIES.map((x) => <SelectItem key={x.value} value={x.value}>{x.label}</SelectItem>)}</SelectContent>
            </Select>
          </Field>
          <Field label="First due date *"><Input type="date" value={f.startDate} disabled={frozen} onChange={(e) => set({ startDate: e.target.value })} /></Field>
          <Field label="End date (optional)"><Input type="date" value={f.endDate ?? ""} onChange={(e) => set({ endDate: e.target.value || null })} /></Field>
          <Field label="Payment method">
            <Select value={f.paymentMethod} onValueChange={(v) => set({ paymentMethod: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m === "Credit" ? "Credit (pay later)" : m}</SelectItem>)}</SelectContent>
            </Select>
          </Field>
          {f.paymentMethod !== "Credit" && (
            <Field label="Cash account">
              <Select value={f.cashAccountId ? String(f.cashAccountId) : "none"} onValueChange={(v) => set({ cashAccountId: v === "none" ? null : Number(v) })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Choose when posting</SelectItem>
                  {lookups.cashAccounts.map((a) => <SelectItem key={a.id} value={String(a.id)}>{a.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </Field>
          )}
          <Field label="When it falls due" full>
            <div className="grid sm:grid-cols-2 gap-2">
              {([["Draft", "Draft for review (recommended)", "Waits here; you check the amount and post it."],
                 ["AutoPost", "Post automatically", "Recorded as soon as it falls due, with the default amount."]] as const).map(([v, l, h]) => (
                <button key={v} type="button" onClick={() => set({ approvalMode: v })}
                  className={cn("rounded-lg border p-2.5 text-left text-sm", f.approvalMode === v ? "border-indigo-500 bg-indigo-50 ring-1 ring-indigo-500" : "border-slate-200")}>
                  <div className="font-medium">{l}</div><div className="text-xs text-slate-500">{h}</div>
                </button>
              ))}
            </div>
          </Field>
          <Field label="Description" full><Textarea rows={2} value={f.description ?? ""} onChange={(e) => set({ description: e.target.value || null })} /></Field>
        </div>
        <div className="rounded-md border border-slate-200 bg-slate-50 p-2.5 text-xs text-slate-600 space-y-1">
          <div><strong>Next dates:</strong> {dates.join(" · ") || "—"}</div>
          <div>{paymentEffect(f.paymentMethod, Boolean(f.cashAccountId), lookups.moduleApproves)}</div>
          {f.amount > 0 && <div>{gh(f.amount)} {frequencyLabel(f.frequency).toLowerCase()}{f.isVariable ? " (estimate)" : ""}.</div>}
          {frozen && <div className="text-amber-800">Frequency and first date are fixed once a period has been raised — they define which period each one is.</div>}
        </div>
        {errors.length > 0 && <div className="rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">{errors.map((e) => <div key={e}>{e}</div>)}</div>}
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={() => void save()} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save"}</Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function Field({ label, children, full }: { label: string; children: React.ReactNode; full?: boolean }) {
  return <div className={cn(full && "sm:col-span-2")}><label className="text-xs text-slate-500">{label}</label>{children}</div>
}

// --------------------------------------------------------------- review dialog
function ReviewDialog({ occurrence, lookups, busy, onClose, onSaved }: {
  occurrence: RecurringOccurrence | null; lookups: ModuleLookups; busy: boolean
  onClose: () => void
  onSaved: (andPost: boolean, saved: Pick<RecurringOccurrence, "paymentMethod" | "cashAccountId" | "supplierId">) => void | Promise<void>
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [amount, setAmount] = useState(0)
  const [date, setDate] = useState("")
  const [method, setMethod] = useState("Cash")
  const [cash, setCash] = useState<number | null>(null)
  const [supplier, setSupplier] = useState<number | null>(null)
  const [note, setNote] = useState("")
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!occurrence) return
    setAmount(occurrence.amount); setDate(day(occurrence.expenseDate)); setMethod(occurrence.paymentMethod)
    setCash(occurrence.cashAccountId ?? null); setSupplier(occurrence.supplierId ?? null); setNote(occurrence.note ?? "")
  }, [occurrence])

  const postBlocker = method === "Credit"
    ? (!supplier ? "Choose the supplier it will be owed to." : null)
    : (!cash ? "Choose the cash account it is paid from." : null)
  const canPost = postBlocker == null

  async function save(andPost: boolean) {
    if (!occurrence) return
    setSaving(true)
    try {
      await editRecurringOccurrence(occurrence.occurrenceId, {
        amount, expenseDate: date, paymentMethod: method, cashAccountId: method === "Credit" ? null : cash,
        supplierId: supplier, note: note || null,
      })
      await onSaved(andPost, { paymentMethod: method, cashAccountId: method === "Credit" ? null : cash, supplierId: supplier })
    } catch (e: any) {
      toast({ title: "Could not save the draft", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={occurrence != null} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="max-w-lg">
        {occurrence && (
          <>
            <DialogHeader>
              <DialogTitle>{occurrence.templateName}</DialogTitle>
              <DialogDescription>Due {day(occurrence.scheduledDate)} · usually {gh(occurrence.templateAmount)}</DialogDescription>
            </DialogHeader>
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="Actual amount *"><NumberInput min={0} step="0.01" value={amount} onChange={(e) => setAmount(Number(e.target.value) || 0)} /></Field>
              <Field label="Expense date *"><Input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
              <Field label="Payment method">
                <Select value={method} onValueChange={setMethod}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m === "Credit" ? "Credit (pay later)" : m}</SelectItem>)}</SelectContent>
                </Select>
              </Field>
              {method !== "Credit" ? (
                <Field label="Cash account">
                  <Select value={cash ? String(cash) : ""} onValueChange={(v) => setCash(Number(v))}>
                    <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                    <SelectContent>{lookups.cashAccounts.map((a) => <SelectItem key={a.id} value={String(a.id)}>{a.name}</SelectItem>)}</SelectContent>
                  </Select>
                </Field>
              ) : (
                <Field label="Supplier *">
                  <Select value={supplier ? String(supplier) : ""} onValueChange={(v) => setSupplier(Number(v))}>
                    <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                    <SelectContent>{lookups.suppliers.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.name}</SelectItem>)}</SelectContent>
                  </Select>
                </Field>
              )}
              <Field label="Note" full><Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. meter reading 4,512" /></Field>
            </div>
            <p className={cn("text-xs", canPost ? "text-slate-500" : "text-amber-700")}>{postBlocker ?? paymentEffect(method, Boolean(cash), lookups.moduleApproves)}</p>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => void save(false)} disabled={saving || busy}>Save draft</Button>
              <Button onClick={() => void save(true)} disabled={saving || busy || !canPost} title={canPost ? undefined : postBlocker ?? undefined}>{saving || busy ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save and post"}</Button>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}

"use client"

// 428. Payroll templates: the standard payroll, set up once and used every
// period. A run is created from a template as a Draft (so this month's extras
// can still be changed); editing a template changes future runs only.

import { useEffect, useMemo, useState } from "react"
import { Archive, ArchiveRestore, CalendarPlus, FileStack, Loader2, Pencil, Plus, Trash2, UserPlus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  getPoultryPayrollTemplate, listPoultryPayrollTemplates, savePoultryPayrollTemplate, setPoultryPayrollTemplateActive,
  PAYROLL_FREQUENCIES, POULTRY_PAYMENT_METHODS,
  type PoultryCashAccount, type PoultryPayrollTemplate, type PoultryPayrollTemplateLine, type PoultryStaff,
} from "@/lib/api/poultry-finance"

const staffName = (s: PoultryStaff) => `${s.firstName ?? ""} ${s.lastName ?? ""}`.trim()
const lineNet = (l: PoultryPayrollTemplateLine) =>
  (Number(l.basicPay) || 0) + (Number(l.dailyWage) || 0) + (Number(l.commission) || 0) + (Number(l.bonus) || 0) - (Number(l.deductions) || 0)
const blankLine = (s: PoultryStaff): PoultryPayrollTemplateLine => ({
  poultryStaffId: s.poultryStaffId, staffName: staffName(s), staffRole: s.role, staffIsActive: s.isActive,
  basicPay: s.basePay ?? 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "",
})

export function PayrollTemplatesPanel({
  staff, accounts, canEdit, onUse, refreshKey,
}: {
  staff: PoultryStaff[]
  accounts: PoultryCashAccount[]
  canEdit: boolean
  /** Opens the New payroll run dialog with this template picked. */
  onUse: (t: PoultryPayrollTemplate) => void
  /** Bumped by the page after a run is created, so "last run" stays current. */
  refreshKey: number
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [templates, setTemplates] = useState<PoultryPayrollTemplate[]>([])
  const [loading, setLoading] = useState(true)
  const [showArchived, setShowArchived] = useState(false)
  const [editing, setEditing] = useState<{ id: number | null } | null>(null)

  async function load() {
    setLoading(true)
    try { setTemplates(await listPoultryPayrollTemplates(true)) }
    catch (e: any) { toast({ title: "Could not load templates", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }
  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [refreshKey])

  const visible = templates.filter((t) => showArchived || t.isActive)
  const archivedCount = templates.filter((t) => !t.isActive).length

  async function toggleActive(t: PoultryPayrollTemplate) {
    try {
      await setPoultryPayrollTemplateActive(t.poultryPayrollTemplateId, !t.isActive)
      toast({ title: t.isActive ? `"${t.name}" archived` : `"${t.name}" restored` })
      await load()
    } catch (e: any) { toast({ title: "Could not update the template", description: e?.message, variant: "destructive" }) }
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-slate-600 max-w-2xl">
          Set up your standard payroll once — staff, pay and fixed deductions. Each pay period, create the run from the
          template, adjust anything that changed this time, then approve. Editing a template only affects future runs.
        </p>
        <div className="flex items-center gap-3">
          {archivedCount > 0 && (
            <label className="flex items-center gap-2 text-sm text-slate-600">
              <Switch checked={showArchived} onCheckedChange={setShowArchived} /> Show archived ({archivedCount})
            </label>
          )}
          {canEdit && <Button onClick={() => setEditing({ id: null })}><Plus className="h-4 w-4 mr-1" /> New template</Button>}
        </div>
      </div>

      {loading ? (
        <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
      ) : visible.length === 0 ? (
        <Card><CardContent className="p-8 text-center text-slate-500">
          <FileStack className="mx-auto mb-2 h-8 w-8 text-slate-300" />
          No payroll templates yet. Create one with your regular staff and their pay, then use it every period.
        </CardContent></Card>
      ) : (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {visible.map((t) => (
            <Card key={t.poultryPayrollTemplateId} className={cn(!t.isActive && "opacity-60")}>
              <CardContent className="p-4 space-y-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="font-semibold text-slate-900 break-words">{t.name}</div>
                    <div className="text-xs text-slate-500">
                      {t.frequency} · {t.lineCount} staff · {t.cashAccountName ?? "No cash account"}
                    </div>
                  </div>
                  {!t.isActive && <Badge variant="secondary">Archived</Badge>}
                </div>
                <div className="grid grid-cols-3 gap-2 text-sm">
                  <div><div className="text-[11px] text-slate-500">Gross</div><div className="font-medium tabular-nums">{gh(t.totalGross)}</div></div>
                  <div><div className="text-[11px] text-slate-500">Deductions</div><div className="font-medium tabular-nums">{gh(t.totalDeductions)}</div></div>
                  <div><div className="text-[11px] text-slate-500">Net</div><div className="font-semibold tabular-nums text-green-700">{gh(t.totalNet)}</div></div>
                </div>
                <div className="text-xs text-slate-500">
                  {t.runCount === 0 ? "Not used yet" : `Used ${t.runCount} time${t.runCount === 1 ? "" : "s"} · last period ${t.lastPeriodStart?.split("T")[0]} → ${t.lastPeriodEnd?.split("T")[0]}`}
                </div>
                {t.staffInactiveCount > 0 && (
                  <div className="rounded bg-amber-50 px-2 py-1 text-xs text-amber-800">
                    {t.staffInactiveCount} staff on it {t.staffInactiveCount === 1 ? "is" : "are"} no longer active and will be skipped.
                  </div>
                )}
                <div className="flex flex-wrap gap-2 pt-1">
                  {t.isActive && canEdit && (
                    <Button size="sm" onClick={() => onUse(t)}><CalendarPlus className="h-4 w-4 mr-1" /> Create run</Button>
                  )}
                  {canEdit && (
                    <Button size="sm" variant="outline" onClick={() => setEditing({ id: t.poultryPayrollTemplateId })}>
                      <Pencil className="h-4 w-4 mr-1" /> Edit
                    </Button>
                  )}
                  {canEdit && (
                    <Button size="sm" variant="ghost" onClick={() => toggleActive(t)}>
                      {t.isActive ? <><Archive className="h-4 w-4 mr-1" /> Archive</> : <><ArchiveRestore className="h-4 w-4 mr-1" /> Restore</>}
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {editing && (
        <TemplateEditor
          id={editing.id}
          staff={staff}
          accounts={accounts}
          onClose={() => setEditing(null)}
          onSaved={async () => { setEditing(null); await load() }}
        />
      )}
    </div>
  )
}

function TemplateEditor({
  id, staff, accounts, onClose, onSaved,
}: {
  id: number | null
  staff: PoultryStaff[]
  accounts: PoultryCashAccount[]
  onClose: () => void
  onSaved: () => void
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [loading, setLoading] = useState(id != null)
  const [saving, setSaving] = useState(false)
  const [name, setName] = useState("")
  const [frequency, setFrequency] = useState("Monthly")
  const [accountId, setAccountId] = useState(0)
  const [notes, setNotes] = useState("")
  const [lines, setLines] = useState<PoultryPayrollTemplateLine[]>([])
  const [addStaffId, setAddStaffId] = useState("0")

  useEffect(() => {
    if (id == null) return
    void (async () => {
      try {
        const t = await getPoultryPayrollTemplate(id)
        setName(t.name); setFrequency(t.frequency); setAccountId(t.poultryCashAccountId ?? 0); setNotes(t.notes ?? "")
        setLines(t.lines.map((l) => ({ ...l, paymentMethod: l.paymentMethod ?? "Cash", notes: l.notes ?? "" })))
      } catch (e: any) {
        toast({ title: "Could not open the template", description: e?.message, variant: "destructive" }); onClose()
      } finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id])

  const activeStaff = useMemo(() => staff.filter((s) => s.isActive && !s.isDeleted), [staff])
  const onTemplate = new Set(lines.map((l) => l.poultryStaffId))
  const addable = activeStaff.filter((s) => !onTemplate.has(s.poultryStaffId))

  const setLine = (i: number, patch: Partial<PoultryPayrollTemplateLine>) =>
    setLines((ls) => ls.map((l, j) => (j === i ? { ...l, ...patch } : l)))

  function addStaff() {
    const s = staff.find((x) => x.poultryStaffId === Number(addStaffId))
    if (!s) return
    setLines((ls) => [...ls, blankLine(s)]); setAddStaffId("0")
  }
  function addAllActive() {
    setLines((ls) => [...ls, ...addable.map(blankLine)])
  }

  const totals = lines.reduce((a, l) => ({
    gross: a.gross + lineNet(l) + (Number(l.deductions) || 0),
    ded: a.ded + (Number(l.deductions) || 0),
  }), { gross: 0, ded: 0 })

  async function save() {
    if (!name.trim()) return toast({ title: "Give the template a name", variant: "destructive" })
    if (lines.length === 0) return toast({ title: "Add at least one staff member", variant: "destructive" })
    const bad = lines.find((l) => lineNet(l) < 0)
    if (bad) return toast({ title: `${bad.staffName ?? "A line"}: deductions are more than the pay`, variant: "destructive" })
    setSaving(true)
    try {
      await savePoultryPayrollTemplate(id, { name: name.trim(), frequency, poultryCashAccountId: accountId || null, notes: notes || null, lines })
      toast({ title: id ? "Template saved" : "Template created", description: id ? "Future runs will use the new figures." : undefined })
      onSaved()
    } catch (e: any) { toast({ title: "Could not save the template", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const num = (v: number, on: (n: number) => void) => (
    <NumberInput min={0} value={v} className="h-8 w-24 text-right" onChange={(e) => on(Number(e.target.value) || 0)} />
  )

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="w-[95vw] sm:max-w-6xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><FileStack className="h-5 w-5 text-indigo-600" /> {id ? "Edit payroll template" : "New payroll template"}</DialogTitle>
          <DialogDescription>Changes apply to runs created from now on. Runs already created keep their figures.</DialogDescription>
        </DialogHeader>
        {loading ? (
          <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : (
          <div className="space-y-5">
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div className="space-y-1.5 lg:col-span-2"><Label>Template name *</Label>
                <Input value={name} placeholder="e.g. Monthly staff" onChange={(e) => setName(e.target.value)} /></div>
              <div className="space-y-1.5"><Label>Pay frequency</Label>
                <Select value={frequency} onValueChange={setFrequency}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PAYROLL_FREQUENCIES.map((f) => <SelectItem key={f} value={f}>{f}</SelectItem>)}</SelectContent>
                </Select></div>
              <div className="space-y-1.5"><Label>Paid from (cash account)</Label>
                <Select value={String(accountId)} onValueChange={(v) => setAccountId(Number(v))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="0">— None —</SelectItem>
                    {accounts.filter((a) => a.isActive || a.poultryCashAccountId === accountId).map((a) =>
                      <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>)}
                  </SelectContent>
                </Select></div>
              <div className="space-y-1.5 sm:col-span-2 lg:col-span-4"><Label>Notes</Label>
                <Input value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
            </div>

            <div className="flex flex-wrap items-end gap-2">
              <div className="space-y-1.5 min-w-[14rem]"><Label>Add staff</Label>
                <Select value={addStaffId} onValueChange={setAddStaffId}>
                  <SelectTrigger><SelectValue placeholder="Pick a staff member" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="0">— Pick a staff member —</SelectItem>
                    {addable.map((s) => <SelectItem key={s.poultryStaffId} value={String(s.poultryStaffId)}>{staffName(s)}{s.role ? ` · ${s.role}` : ""}</SelectItem>)}
                  </SelectContent>
                </Select></div>
              <Button variant="outline" onClick={addStaff} disabled={addStaffId === "0"}><UserPlus className="h-4 w-4 mr-1" /> Add</Button>
              {addable.length > 0 && <Button variant="ghost" onClick={addAllActive}>Add all active staff ({addable.length})</Button>}
            </div>

            <div className="overflow-x-auto rounded-lg border border-slate-200">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 text-slate-600">
                  <tr>
                    <th className="px-3 py-2 text-left font-medium">Staff</th>
                    <th className="px-2 py-2 text-right font-medium">Basic</th>
                    <th className="px-2 py-2 text-right font-medium">Daily wage</th>
                    <th className="px-2 py-2 text-right font-medium">Commission</th>
                    <th className="px-2 py-2 text-right font-medium">Bonus</th>
                    <th className="px-2 py-2 text-right font-medium">Deductions</th>
                    <th className="px-2 py-2 text-right font-medium">Net</th>
                    <th className="px-2 py-2 text-left font-medium">Paid by</th>
                    <th className="w-10"></th>
                  </tr>
                </thead>
                <tbody>
                  {lines.length === 0 ? (
                    <tr><td colSpan={9} className="px-3 py-6 text-center text-slate-500">No staff yet. Add them above.</td></tr>
                  ) : lines.map((l, i) => (
                    <tr key={l.poultryStaffId} className="border-t border-slate-100">
                      <td className="px-3 py-1.5 min-w-[10rem]">
                        <div className="font-medium text-slate-900">{l.staffName ?? `#${l.poultryStaffId}`}</div>
                        {l.staffIsActive === false && <div className="text-[11px] text-amber-700">Not active — skipped on new runs</div>}
                      </td>
                      <td className="px-2 py-1.5 text-right">{num(l.basicPay, (n) => setLine(i, { basicPay: n }))}</td>
                      <td className="px-2 py-1.5 text-right">{num(l.dailyWage, (n) => setLine(i, { dailyWage: n }))}</td>
                      <td className="px-2 py-1.5 text-right">{num(l.commission, (n) => setLine(i, { commission: n }))}</td>
                      <td className="px-2 py-1.5 text-right">{num(l.bonus, (n) => setLine(i, { bonus: n }))}</td>
                      <td className="px-2 py-1.5 text-right">{num(l.deductions, (n) => setLine(i, { deductions: n }))}</td>
                      <td className={cn("px-2 py-1.5 text-right font-semibold tabular-nums whitespace-nowrap", lineNet(l) < 0 && "text-red-600")}>{gh(lineNet(l))}</td>
                      <td className="px-2 py-1.5">
                        <Select value={l.paymentMethod ?? "Cash"} onValueChange={(v) => setLine(i, { paymentMethod: v })}>
                          <SelectTrigger className="h-8 w-24"><SelectValue /></SelectTrigger>
                          <SelectContent>{POULTRY_PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                        </Select>
                      </td>
                      <td className="px-2 py-1.5">
                        <Button size="sm" variant="ghost" aria-label="Remove from template" onClick={() => setLines((ls) => ls.filter((_, j) => j !== i))}>
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
                {lines.length > 0 && (
                  <tfoot className="border-t border-slate-200 bg-slate-50 font-medium">
                    <tr>
                      <td className="px-3 py-2">{lines.length} staff</td>
                      <td colSpan={4} className="px-2 py-2 text-right text-slate-500">Gross {gh(totals.gross)}</td>
                      <td className="px-2 py-2 text-right tabular-nums">{gh(totals.ded)}</td>
                      <td className="px-2 py-2 text-right tabular-nums text-green-700">{gh(totals.gross - totals.ded)}</td>
                      <td colSpan={2}></td>
                    </tr>
                  </tfoot>
                )}
              </table>
            </div>
            <p className="text-xs text-slate-500">
              Deductions here are the fixed ones you take every period. Advance and loan repayments are added to each run
              automatically from Employee Loans &amp; Advances, so don&apos;t include them.
            </p>

            <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <Button variant="outline" onClick={onClose} disabled={saving}>Cancel</Button>
              <Button onClick={save} disabled={saving} className="min-w-[140px]">
                {saving ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : id ? "Save template" : "Create template"}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}

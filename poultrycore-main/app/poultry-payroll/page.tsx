"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, Banknote, Eye, Users, Trash2, CheckCircle2, RotateCcw, XCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryPayrollRuns, createPoultryPayrollRun, getPoultryPayrollRun,
  upsertPoultryPayrollItem, deletePoultryPayrollItem,
  approvePoultryPayrollRun, markPoultryPayrollRunPaid, cancelPoultryPayrollRun,
  unapprovePoultryPayrollRun, deletePoultryPayrollRun,
  listPoultryCashAccounts, listPoultryStaff,
  POULTRY_PAYMENT_METHODS,
  type PoultryPayrollRun, type PoultryCashAccount, type PoultryStaff,
} from "@/lib/api/poultry-finance"

const today = () => new Date().toISOString().split("T")[0]
const STATUS_STYLE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-blue-100 text-blue-700",
  Paid: "bg-green-100 text-green-700",
  Reopened: "bg-amber-100 text-amber-700",
  Cancelled: "bg-rose-100 text-rose-700",
}

export default function PoultryPayrollPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [runs, setRuns] = useState<PoultryPayrollRun[]>([])
  const [accounts, setAccounts] = useState<PoultryCashAccount[]>([])
  const [staff, setStaff] = useState<PoultryStaff[]>([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState("all")

  const visible = useMemo(() => statusFilter === "all" ? runs : runs.filter(r => r.status === statusFilter), [runs, statusFilter])

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visible)

  // create run
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState({ periodStart: today(), periodEnd: today(), payDate: "", poultryCashAccountId: 0, notes: "" })
  const [saving, setSaving] = useState(false)

  // items dialog
  const [itemsRun, setItemsRun] = useState<PoultryPayrollRun | null>(null)
  const [itemForm, setItemForm] = useState({ poultryStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })
  const [itemSaving, setItemSaving] = useState(false)

  // mark paid
  const [paidRun, setPaidRun] = useState<PoultryPayrollRun | null>(null)
  const [payDate, setPayDate] = useState(today())

  // reason (cancel / unapprove)
  const [reasonDlg, setReasonDlg] = useState<{ open: boolean; run?: PoultryPayrollRun; kind?: "cancel" | "unapprove" }>({ open: false })
  const [reason, setReason] = useState("")

  const [deleteTarget, setDeleteTarget] = useState<PoultryPayrollRun | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [r, a, s] = await Promise.all([listPoultryPayrollRuns(), listPoultryCashAccounts(), listPoultryStaff()])
      setRuns(r); setAccounts(a); setStaff(s)
    } catch (e: any) { toast({ title: "Could not load payroll", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function createRun() {
    setSaving(true)
    try {
      await createPoultryPayrollRun({
        periodStart: form.periodStart, periodEnd: form.periodEnd,
        payDate: form.payDate || null,
        poultryCashAccountId: form.poultryCashAccountId || null,
        notes: form.notes || null,
      })
      toast({ title: "Payroll run created" })
      setOpen(false); setForm({ periodStart: today(), periodEnd: today(), payDate: "", poultryCashAccountId: 0, notes: "" })
      await load()
    } catch (e: any) { toast({ title: "Could not create run", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function openItems(run: PoultryPayrollRun) {
    try {
      const full = await getPoultryPayrollRun(run.poultryPayrollRunId)
      setItemsRun(full)
      setItemForm({ poultryStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })
    } catch (e: any) { toast({ title: "Could not open run", description: e?.message, variant: "destructive" }) }
  }
  async function refreshItems(runId: number) {
    const full = await getPoultryPayrollRun(runId)
    setItemsRun(full)
    setRuns((prev) => prev.map(r => r.poultryPayrollRunId === runId ? full : r))
  }
  async function addItem() {
    if (!itemsRun) return
    if (!itemForm.poultryStaffId) return toast({ title: "Pick a staff member", variant: "destructive" })
    setItemSaving(true)
    try {
      await upsertPoultryPayrollItem(itemsRun.poultryPayrollRunId, {
        poultryStaffId: itemForm.poultryStaffId,
        basicPay: Number(itemForm.basicPay) || 0, dailyWage: Number(itemForm.dailyWage) || 0,
        commission: Number(itemForm.commission) || 0, bonus: Number(itemForm.bonus) || 0,
        deductions: Number(itemForm.deductions) || 0, paymentMethod: itemForm.paymentMethod, notes: itemForm.notes || null,
      })
      setItemForm({ poultryStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })
      await refreshItems(itemsRun.poultryPayrollRunId)
    } catch (e: any) { toast({ title: "Could not save line", description: e?.message, variant: "destructive" }) }
    finally { setItemSaving(false) }
  }
  async function removeItem(itemId: number) {
    if (!itemsRun) return
    try { await deletePoultryPayrollItem(itemId); await refreshItems(itemsRun.poultryPayrollRunId) }
    catch (e: any) { toast({ title: "Could not remove line", description: e?.message, variant: "destructive" }) }
  }
  function prefillFromStaff(staffId: number) {
    const s = staff.find(x => x.poultryStaffId === staffId)
    setItemForm((f) => ({ ...f, poultryStaffId: staffId, basicPay: s ? s.basePay : f.basicPay }))
  }

  async function approve(run: PoultryPayrollRun) {
    try { await approvePoultryPayrollRun(run.poultryPayrollRunId); toast({ title: "Run approved", description: "A linked expense was created." }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }
  async function confirmMarkPaid() {
    if (!paidRun) return
    try { await markPoultryPayrollRunPaid(paidRun.poultryPayrollRunId, payDate); toast({ title: "Run marked paid", description: "Cash-out posted to the selected account." }); setPaidRun(null); await load() }
    catch (e: any) { toast({ title: "Mark paid failed", description: e?.message, variant: "destructive" }) }
  }
  async function confirmReason() {
    if (!reasonDlg.run || !reasonDlg.kind) return
    try {
      if (reasonDlg.kind === "cancel") { await cancelPoultryPayrollRun(reasonDlg.run.poultryPayrollRunId, reason); toast({ title: "Run cancelled" }) }
      else { if (!reason.trim()) return toast({ title: "A reason is required", variant: "destructive" }); await unapprovePoultryPayrollRun(reasonDlg.run.poultryPayrollRunId, reason); toast({ title: "Run reopened", description: "Expense and cash-out reversed." }) }
      setReasonDlg({ open: false }); setReason(""); await load()
    } catch (e: any) { toast({ title: "Action failed", description: e?.message, variant: "destructive" }) }
  }
  async function performDelete(run: PoultryPayrollRun) {
    await deletePoultryPayrollRun(run.poultryPayrollRunId)
    toast({ title: "Run deleted" })
    await load()
  }

  const totalNetPaid = runs.filter(r => r.status === "Paid").reduce((s, r) => s + r.totalNetPay, 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Banknote className="h-6 w-6 text-green-600" /> Payroll
            </h1>
            <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> New payroll run</Button>
          </div>

          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total runs</div><div className="text-xl font-semibold">{runs.length}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Draft</div><div className="text-xl font-semibold">{runs.filter(r => r.status === "Draft").length}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved</div><div className="text-xl font-semibold">{runs.filter(r => r.status === "Approved").length}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total net paid</div><div className="text-xl font-semibold tabular-nums text-green-700">{gh(totalNetPaid)}</div></CardContent></Card>
          </div>

          <div className="mb-3 flex items-center gap-2">
            <span className="text-sm text-slate-600">Status</span>
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All</SelectItem>
                {["Draft", "Approved", "Paid", "Reopened", "Cancelled"].map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : runs.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No payroll runs yet. Create one to start paying staff.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r) => r.poultryPayrollRunId}
                  primary={(r) => `${r.periodStart.split("T")[0]} → ${r.periodEnd.split("T")[0]}`}
                  secondary={(r) => (<><span>Net {gh(r.totalNetPay)}</span><Badge className={STATUS_STYLE[r.status] ?? ""}>{r.status}</Badge></>)}
                  details={(r) => [
                    { label: "Period", value: `${r.periodStart.split("T")[0]} → ${r.periodEnd.split("T")[0]}` },
                    { label: "Gross", value: gh(r.totalGrossPay) },
                    { label: "Deductions", value: gh(r.totalDeductions) },
                    { label: "Net", value: gh(r.totalNetPay) },
                    { label: "Cash account", value: r.cashAccountName ?? "—" },
                    { label: "Status", value: r.status },
                  ]}
                  actions={(r) => renderActions(r, true)}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Period</TableHead>
                            <TableHead className="text-right">Gross</TableHead>
                            <TableHead className="text-right">Deductions</TableHead>
                            <TableHead className="text-right">Net</TableHead>
                            <TableHead>Cash account</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((r) => (
                            <TableRow key={r.poultryPayrollRunId}>
                              <TableCell className="whitespace-nowrap font-medium">{r.periodStart.split("T")[0]} → {r.periodEnd.split("T")[0]}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.totalGrossPay)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.totalDeductions)}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">{gh(r.totalNetPay)}</TableCell>
                              <TableCell>{r.cashAccountName ?? "—"}</TableCell>
                              <TableCell><Badge className={STATUS_STYLE[r.status] ?? ""}>{r.status}</Badge></TableCell>
                              <TableCell className="text-right whitespace-nowrap">{renderActions(r, false)}</TableCell>
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
        </main>
      </div>

      {/* Create run */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Banknote className="w-5 h-5 text-green-600" /> New payroll run</DialogTitle>
            <DialogDescription>Create a Draft run, then add staff lines</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Period" color="indigo">
              <FormField label="Period start *"><Input type="date" value={form.periodStart} onChange={(e) => setForm({ ...form, periodStart: e.target.value })} /></FormField>
              <FormField label="Period end *"><Input type="date" value={form.periodEnd} onChange={(e) => setForm({ ...form, periodEnd: e.target.value })} /></FormField>
              <FormField label="Pay date"><Input type="date" value={form.payDate} onChange={(e) => setForm({ ...form, payDate: e.target.value })} /></FormField>
              <FormField label="Cash account (paid from)">
                <Select value={String(form.poultryCashAccountId)} onValueChange={(v) => setForm({ ...form, poultryCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Select account" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="0">— None —</SelectItem>
                    {accounts.filter(a => a.isActive).map(a => <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>
            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes"><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
            </FormSection>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={createRun} disabled={saving}>{saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating…</>) : "Create run"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Items management */}
      <Dialog open={!!itemsRun} onOpenChange={(v) => { if (!v) setItemsRun(null) }}>
        <DialogContent className="w-[95vw] max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Users className="w-5 h-5 text-indigo-600" /> Staff lines</DialogTitle>
            <DialogDescription>{itemsRun ? `${itemsRun.periodStart.split("T")[0]} → ${itemsRun.periodEnd.split("T")[0]} · Net ${gh(itemsRun.totalNetPay)}` : ""}</DialogDescription>
          </DialogHeader>
          {itemsRun && (
            <div className="space-y-4">
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Staff</TableHead>
                      <TableHead className="text-right">Basic</TableHead>
                      <TableHead className="text-right">Daily</TableHead>
                      <TableHead className="text-right">Comm.</TableHead>
                      <TableHead className="text-right">Bonus</TableHead>
                      <TableHead className="text-right">Deduct</TableHead>
                      <TableHead className="text-right">Net</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(itemsRun.items ?? []).length === 0 ? (
                      <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-4">No lines yet.</TableCell></TableRow>
                    ) : (itemsRun.items ?? []).map((it) => (
                      <TableRow key={it.poultryPayrollItemId}>
                        <TableCell className="font-medium">{it.staffName ?? `#${it.poultryStaffId}`}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(it.basicPay)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(it.dailyWage)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(it.commission)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(it.bonus)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(it.deductions)}</TableCell>
                        <TableCell className="text-right tabular-nums font-semibold">{gh(it.netPay)}</TableCell>
                        <TableCell className="text-right">
                          {itemsRun.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => removeItem(it.poultryPayrollItemId)}><Trash2 className="h-4 w-4 text-red-500" /></Button>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              {itemsRun.status === "Draft" ? (
                <FormSection title="Add / update a line" color="amber">
                  <FormField label="Staff">
                    <Select value={String(itemForm.poultryStaffId)} onValueChange={(v) => prefillFromStaff(Number(v))}>
                      <SelectTrigger><SelectValue placeholder="Pick staff" /></SelectTrigger>
                      <SelectContent>{staff.filter(s => s.isActive).map(s => <SelectItem key={s.poultryStaffId} value={String(s.poultryStaffId)}>{s.firstName} {s.lastName}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Payment method">
                    <Select value={itemForm.paymentMethod} onValueChange={(v) => setItemForm({ ...itemForm, paymentMethod: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{[...POULTRY_PAYMENT_METHODS].map(m => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Basic pay"><NumberInput step="0.01" value={itemForm.basicPay} onChange={(e) => setItemForm({ ...itemForm, basicPay: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Daily wage"><NumberInput step="0.01" value={itemForm.dailyWage} onChange={(e) => setItemForm({ ...itemForm, dailyWage: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Commission"><NumberInput step="0.01" value={itemForm.commission} onChange={(e) => setItemForm({ ...itemForm, commission: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Bonus"><NumberInput step="0.01" value={itemForm.bonus} onChange={(e) => setItemForm({ ...itemForm, bonus: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Deductions"><NumberInput step="0.01" value={itemForm.deductions} onChange={(e) => setItemForm({ ...itemForm, deductions: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Notes"><Input value={itemForm.notes} onChange={(e) => setItemForm({ ...itemForm, notes: e.target.value })} /></FormField>
                  <FormField label="&nbsp;" full>
                    <Button onClick={addItem} disabled={itemSaving} className="w-full">{itemSaving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Add / update line"}</Button>
                  </FormField>
                </FormSection>
              ) : (
                <p className="text-sm text-slate-500">Lines can only be edited while the run is a Draft.</p>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Mark paid */}
      <Dialog open={!!paidRun} onOpenChange={(v) => { if (!v) setPaidRun(null) }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><CheckCircle2 className="w-5 h-5 text-green-600" /> Mark paid</DialogTitle>
            <DialogDescription>Posts a cash-out of {paidRun ? gh(paidRun.totalNetPay) : ""} to {paidRun?.cashAccountName ?? "the run's cash account"}.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormField label="Pay date"><Input type="date" value={payDate} onChange={(e) => setPayDate(e.target.value)} /></FormField>
            {paidRun && !paidRun.poultryCashAccountId && <p className="text-xs text-amber-700">No cash account is set on this run — no cash-out will be posted. Edit the run to set one first if you want the balance to move.</p>}
            <div className="flex gap-3 justify-end pt-2">
              <Button variant="ghost" onClick={() => setPaidRun(null)}>Cancel</Button>
              <Button onClick={confirmMarkPaid}>Mark paid</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reason (cancel / unapprove) */}
      <Dialog open={reasonDlg.open} onOpenChange={(v) => { if (!v) { setReasonDlg({ open: false }); setReason("") } }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{reasonDlg.kind === "unapprove" ? "Reopen run" : "Cancel run"}</DialogTitle>
            <DialogDescription>{reasonDlg.kind === "unapprove" ? "Reverses the linked expense and any cash-out, and returns the run to Reopened." : "Cancels this run and removes any linked expense."}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormField label={reasonDlg.kind === "unapprove" ? "Reason *" : "Reason"}><Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Why?" /></FormField>
            <div className="flex gap-3 justify-end pt-2">
              <Button variant="ghost" onClick={() => { setReasonDlg({ open: false }); setReason("") }}>Back</Button>
              <Button onClick={confirmReason}>{reasonDlg.kind === "unapprove" ? "Reopen" : "Cancel run"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete this payroll run?"
        description="Permanently deletes the run and its lines. Only Draft, Reopened or Cancelled runs can be deleted."
        confirmLabel="Delete run"
        errorTitle="Could not delete run"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )

  function renderActions(r: PoultryPayrollRun, mobile: boolean) {
    const cls = mobile ? "flex-1 h-10" : ""
    const v = mobile ? "outline" : "ghost"
    return (
      <>
        <Button size="sm" variant={v} className={cls} onClick={() => router.push(`/poultry-payroll/${r.poultryPayrollRunId}`)} title="Details"><Eye className="h-4 w-4 mr-1" />{mobile ? "Details" : ""}</Button>
        {r.status === "Draft" && <Button size="sm" variant={v} className={cls} onClick={() => openItems(r)} title="Edit lines"><Users className="h-4 w-4 mr-1" />{mobile ? "Lines" : ""}</Button>}
        {r.status !== "Draft" && <Button size="sm" variant={v} className={cls} onClick={() => openItems(r)} title="View lines"><Users className="h-4 w-4" /></Button>}
        {(r.status === "Draft" || r.status === "Reopened") && <Button size="sm" variant={v} className={`${cls} text-blue-700`} onClick={() => approve(r)} title="Approve"><CheckCircle2 className="h-4 w-4 mr-1" />{mobile ? "Approve" : ""}</Button>}
        {r.status === "Approved" && <Button size="sm" variant={v} className={`${cls} text-green-700`} onClick={() => { setPaidRun(r); setPayDate(today()) }} title="Mark paid"><Banknote className="h-4 w-4 mr-1" />{mobile ? "Mark paid" : ""}</Button>}
        {(r.status === "Approved" || r.status === "Paid") && <Button size="sm" variant={v} className={`${cls} text-amber-700`} onClick={() => { setReasonDlg({ open: true, run: r, kind: "unapprove" }); setReason("") }} title="Reopen"><RotateCcw className="h-4 w-4" /></Button>}
        {(r.status === "Draft" || r.status === "Approved") && <Button size="sm" variant={v} className={`${cls} text-rose-600`} onClick={() => { setReasonDlg({ open: true, run: r, kind: "cancel" }); setReason("") }} title="Cancel"><XCircle className="h-4 w-4" /></Button>}
        {(r.status === "Draft" || r.status === "Reopened" || r.status === "Cancelled") && <Button size="sm" variant={v} className={`${cls} text-red-600`} onClick={() => setDeleteTarget(r)} title="Delete"><Trash2 className="h-4 w-4" /></Button>}
      </>
    )
  }
}

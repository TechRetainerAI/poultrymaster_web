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
import { Plus, Loader2, Banknote, Eye, Users, Trash2, CheckCircle2, RotateCcw, XCircle, HandCoins } from "lucide-react"
import Link from "next/link"
import {
  PayrollDeductionsDialog, type PayrollDeductionTarget,
} from "@/components/poultry/payroll-deductions-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryPayrollRuns, createPoultryPayrollRun, getPoultryPayrollRun,
  listPoultryPayrollDeductionsForRun, type PoultryPayrollDeductionRunRow,
  listEligiblePoultryEmployeeLoans, listPoultryPayrollDeductions,
  type PoultryEmployeeLoanEligible,
  savePoultryPayrollDeduction,
  upsertPoultryPayrollItem, deletePoultryPayrollItem,
  approvePoultryPayrollRun, markPoultryPayrollRunPaid, cancelPoultryPayrollRun,
  unapprovePoultryPayrollRun, deletePoultryPayrollRun,
  listPoultryCashAccounts, listPoultryStaff,
  POULTRY_PAYMENT_METHODS,
  type PoultryPayrollRun, type PoultryCashAccount, type PoultryStaff,
} from "@/lib/api/poultry-finance"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const today = () => new Date().toISOString().split("T")[0]
const STATUS_STYLE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-blue-100 text-blue-700",
  Paid: "bg-green-100 text-green-700",
  Reopened: "bg-amber-100 text-amber-700",
  Cancelled: "bg-rose-100 text-rose-700",
}

/**
 * What payroll will take off for one advance.
 *
 * ONE definition, used by three things that must agree: the panel that promises
 * it before the line is saved, the Deductions box that is pre-filled with it,
 * and autoAddSuggestedDeductions which actually posts it. Three copies of this
 * arithmetic would eventually promise one number and deduct another.
 *
 * Zero means "nothing automatic here" -- either the advance is repaid outside
 * payroll, or no amount was ever suggested for it.
 */
function payrollDeductionFor(e: PoultryEmployeeLoanEligible): number {
  const byPayroll = e.repaymentMethod === "PayrollDeduction" || e.repaymentMethod === "Mixed"
  if (!byPayroll) return 0
  // Never more than is left: the server would refuse it, and the user would be
  // reading an error about an amount they never chose.
  return Math.min(e.defaultPayrollDeduction ?? 0, e.outstandingBalance)
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
  // 306. Which payslip line's deduction breakdown is open, if any.
  const [deductionsFor, setDeductionsFor] = useState<PayrollDeductionTarget | null>(null)
  /**
   * Section 50. Which lines have advances outstanding, keyed by payroll item.
   *
   * One request for the whole run rather than one per line: the function
   * behind it already aggregates, and 30 staff would otherwise be 30 calls
   * to draw a hint.
   */
  const [loanHints, setLoanHints] =
    useState<Map<number, PoultryPayrollDeductionRunRow>>(new Map())
  /**
   * The advances of whoever is selected in the Add-a-line form.
   *
   * Shown BEFORE the line is added, because the deduction is applied
   * automatically when it is -- and a deduction that appears out of
   * nowhere after saving is worse than one you were told about first.
   */
  const [staffLoans, setStaffLoans] = useState<PoultryEmployeeLoanEligible[]>([])
  const [staffLoansBusy, setStaffLoansBusy] = useState(false)
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

  /**
   * A run is editable while Draft OR Reopened.
   *
   * sppoultrypayrollrun_unapprove sets a reopened run to 'Reopened', and
   * _approve accepts both -- so gating the lines on 'Draft' alone made
   * reopening a payroll a dead end: you could unapprove it and then not be
   * allowed to change the thing you reopened it for. That matters most for
   * advance deductions, where reopen, change the amount, re-approve is the
   * documented way to correct one (spec section 44).
   */
  const isEditable = (status?: string) => status === "Draft" || status === "Reopened"

  async function openItems(run: PoultryPayrollRun) {
    try {
      const full = await getPoultryPayrollRun(run.poultryPayrollRunId)
      setItemsRun(full)
      setItemForm({ poultryStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })
      void loadLoanHints(run.poultryPayrollRunId)
    } catch (e: any) { toast({ title: "Could not open run", description: e?.message, variant: "destructive" }) }
  }
  async function refreshItems(runId: number) {
    const full = await getPoultryPayrollRun(runId)
    setItemsRun(full)
    setRuns((prev) => prev.map(r => r.poultryPayrollRunId === runId ? full : r))
    await loadLoanHints(runId)
  }

  async function loadLoanHints(runId: number) {
    try {
      const rows = await listPoultryPayrollDeductionsForRun(runId)
      setLoanHints(new Map(rows.map((r) => [r.poultryPayrollItemId, r])))
    } catch {
      // A missing hint is a missing hint. It must never stop the payroll
      // itself from opening.
      setLoanHints(new Map())
    }
  }
  /**
   * Put the worker's scheduled advance repayments on the line automatically
   * (spec sections 36 and 37).
   *
   * These are DRAFT deductions. Nothing is repaid and no balance moves until
   * the run is approved -- which is what section 36 actually forbids doing
   * silently. Making the user re-type an amount they already set on the advance
   * was not caution, it was just work.
   *
   * Three rules it follows:
   *   * only advances the farm said would be repaid BY PAYROLL. One set to
   *     repay in cash is left alone -- it is on the Employee Loans page and
   *     will be paid there.
   *   * never more than is left. A suggestion of 500 against 300 outstanding
   *     adds 300, because the server would refuse 500 and the user would be
   *     left reading an error about an amount they never typed.
   *   * never twice. Re-saving a line that already carries a deduction for an
   *     advance adds nothing -- upsert is called again every time a figure on
   *     the line is edited.
   *
   * Failures are swallowed on purpose: the payroll LINE saved, and losing that
   * because a convenience could not be applied would be the worse outcome. The
   * deduction can still be added by hand.
   */
  async function autoAddSuggestedDeductions(
    item: { poultryPayrollItemId: number }, staffId: number,
  ): Promise<string[]> {
    try {
      const [eligible, existing] = await Promise.all([
        listEligiblePoultryEmployeeLoans(staffId),
        listPoultryPayrollDeductions(item.poultryPayrollItemId),
      ])
      const already = new Set(
        existing.filter((d) => d.poultryEmployeeLoanId != null)
                .map((d) => d.poultryEmployeeLoanId as number))

      const added: string[] = []
      for (const e of eligible) {
        if (already.has(e.poultryEmployeeLoanId)) continue
        const amount = payrollDeductionFor(e)
        if (amount <= 0) continue
        await savePoultryPayrollDeduction({
          poultryPayrollItemId: item.poultryPayrollItemId,
          deductionType: e.loanType === "SalaryAdvance"
            ? "SalaryAdvanceRepayment" : "EmployeeLoanRepayment",
          amount,
          poultryEmployeeLoanId: e.poultryEmployeeLoanId,
        })
        added.push(`${e.loanNumber ?? `#${e.poultryEmployeeLoanId}`} ${gh(amount)}`)
      }
      return added
    } catch {
      return []
    }
  }

  async function addItem() {
    if (!itemsRun) return
    if (!itemForm.poultryStaffId) return toast({ title: "Pick a staff member", variant: "destructive" })
    setItemSaving(true)
    try {
      const saved = await upsertPoultryPayrollItem(itemsRun.poultryPayrollRunId, {
        poultryStaffId: itemForm.poultryStaffId,
        basicPay: Number(itemForm.basicPay) || 0, dailyWage: Number(itemForm.dailyWage) || 0,
        commission: Number(itemForm.commission) || 0, bonus: Number(itemForm.bonus) || 0,
        deductions: Number(itemForm.deductions) || 0, paymentMethod: itemForm.paymentMethod, notes: itemForm.notes || null,
      })
      const added = await autoAddSuggestedDeductions(saved, itemForm.poultryStaffId)
      setItemForm({ poultryStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })
      setStaffLoans([])
      await refreshItems(itemsRun.poultryPayrollRunId)
      if (added.length > 0) {
        toast({
          title: added.length === 1 ? "Advance repayment added" : `${added.length} advance repayments added`,
          description: `${added.join(", ")} — review before approving. Nothing is repaid until you approve.`,
        })
      }
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
    void loadStaffLoans(staffId)
  }

  async function loadStaffLoans(staffId: number) {
    if (!staffId) { setStaffLoans([]); return }
    setStaffLoansBusy(true)
    try {
      const list = await listEligiblePoultryEmployeeLoans(staffId)
      setStaffLoans(list)
      // Put the figure in the box, so the line shows what it will actually
      // deduct rather than 0 followed by a number appearing after saving.
      const auto = list.reduce((sum, e) => sum + payrollDeductionFor(e), 0)
      setItemForm((f) => ({ ...f, deductions: auto }))
    } catch {
      // Not knowing about an advance must never stop a line being added.
      setStaffLoans([])
    } finally {
      setStaffLoansBusy(false)
    }
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
            <div className="flex flex-wrap gap-2">
              {/* Section 51. A shortcut only -- Employee Loans & Advances is
                  where advances are created, disbursed and repaid. Nothing is
                  duplicated here. */}
              <Button variant="outline" asChild>
                <Link href="/poultry-employee-loans">
                  <HandCoins className="h-4 w-4 mr-1" /> Employee Loans &amp; Advances
                </Link>
              </Button>
              <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> New payroll run</Button>
            </div>
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
                  defaultOpen
                  striped
                  stripeAccent="blue"
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r) => r.poultryPayrollRunId}
                  primary={(r) => `${r.periodStart.split("T")[0]} → ${r.periodEnd.split("T")[0]}`}
                  secondary={(r) => (<><span>{r.cashAccountName ?? "No cash account"}</span><Badge className={STATUS_STYLE[r.status] ?? ""}>{r.status}</Badge></>)}
                  highlights={(r) => [
                    // What a run comes down to: what the staff take home, and
                    // what was held back. Net was a line of the subtitle before,
                    // where the number a card exists to state read as a caption.
                    { label: "Net pay", value: gh(r.totalNetPay), accent: "blue" },
                    { label: "Deductions", value: gh(r.totalDeductions), accent: "rose" },
                  ]}
                  details={(r) => [
                    { label: "Period", value: `${fmtDateTime(r.periodStart, r)} → ${fmtDateTime(r.periodEnd, r)}` },
                    { label: "Gross", value: gh(r.totalGrossPay) },
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
                              <TableCell className="whitespace-nowrap font-medium">{fmtDateTime(r.periodStart, r)} → {fmtDateTime(r.periodEnd, r)}</TableCell>
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
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
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
            <div className="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-end sm:gap-3">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={createRun} disabled={saving}>{saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating…</>) : "Create run"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Items management */}
      <Dialog open={!!itemsRun} onOpenChange={(v) => { if (!v) setItemsRun(null) }}>
        <DialogContent className="w-[95vw] sm:max-w-6xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Users className="w-5 h-5 text-indigo-600" /> Staff lines</DialogTitle>
            <DialogDescription>{itemsRun ? `${itemsRun.periodStart.split("T")[0]} → ${itemsRun.periodEnd.split("T")[0]} · Net ${gh(itemsRun.totalNetPay)}` : ""}</DialogDescription>
          </DialogHeader>
          {itemsRun && (
            <div className="space-y-4">
              {/* Eight money columns do not fit a phone. Same rows, stacked. */}
              <div className="space-y-2 lg:hidden">
                {(itemsRun.items ?? []).length === 0 ? (
                  <p className="py-4 text-center text-sm text-slate-500">No lines yet.</p>
                ) : (itemsRun.items ?? []).map((it) => (
                  <div key={it.poultryPayrollItemId} className="rounded-lg border border-slate-200 bg-white p-3 shadow-sm">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <div className="font-medium text-slate-900 break-words">{it.staffName ?? `#${it.poultryStaffId}`}</div>
                        <div className="text-xs text-slate-500">Net <span className="font-semibold tabular-nums text-slate-700">{gh(it.netPay)}</span></div>
                      </div>
                      {isEditable(itemsRun.status) && (
                        <Button size="sm" variant="ghost" className="shrink-0" onClick={() => removeItem(it.poultryPayrollItemId)} aria-label="Remove line">
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      )}
                    </div>
                    <div className="mt-2 grid grid-cols-2 gap-1.5 text-sm">
                      <div><span className="text-slate-500">Basic</span> <span className="font-medium tabular-nums">{gh(it.basicPay)}</span></div>
                      <div><span className="text-slate-500">Daily</span> <span className="font-medium tabular-nums">{gh(it.dailyWage)}</span></div>
                      <div><span className="text-slate-500">Comm.</span> <span className="font-medium tabular-nums">{gh(it.commission)}</span></div>
                      <div><span className="text-slate-500">Bonus</span> <span className="font-medium tabular-nums">{gh(it.bonus)}</span></div>
                      <div className="col-span-2">
                        <span className="text-slate-500">Deductions</span>{" "}
                        <button
                          type="button"
                          className="font-medium tabular-nums underline decoration-dotted underline-offset-2"
                          onClick={() => setDeductionsFor({
                            poultryPayrollItemId: it.poultryPayrollItemId,
                            poultryStaffId: it.poultryStaffId,
                            staffName: it.staffName ?? `#${it.poultryStaffId}`,
                            runStatus: itemsRun.status,
                          })}
                        >
                          {gh(it.deductions)}
                        </button>
                        <span className="ml-1 text-[11px] text-slate-400">view breakdown</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>

              <div className="hidden lg:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Staff</TableHead>
                      <TableHead className="text-right px-2 whitespace-nowrap">Basic</TableHead>
                      <TableHead className="text-right px-2 whitespace-nowrap">Daily</TableHead>
                      <TableHead className="text-right px-2 whitespace-nowrap">Comm.</TableHead>
                      <TableHead className="text-right px-2 whitespace-nowrap">Bonus</TableHead>
                      <TableHead className="text-right px-2 whitespace-nowrap">Deduct</TableHead>
                      <TableHead className="text-right px-2 whitespace-nowrap">Net</TableHead>
                      <TableHead className="w-10"></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(itemsRun.items ?? []).length === 0 ? (
                      <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-4">No lines yet.</TableCell></TableRow>
                    ) : (itemsRun.items ?? []).map((it) => (
                      <TableRow key={it.poultryPayrollItemId}>
                        <TableCell className="font-medium min-w-[9rem]">
                          {it.staffName ?? `#${it.poultryStaffId}`}
                          {/* Subtle on purpose: it is a prompt to open the
                              breakdown, not a call to action. Nothing is
                              deducted because an advance exists. */}
                          {(loanHints.get(it.poultryPayrollItemId)?.activeLoanCount ?? 0) > 0 && (
                            <span
                              className="ml-2 rounded bg-indigo-50 px-1.5 py-0.5 text-[10px] font-normal text-indigo-700"
                              title={`${gh(loanHints.get(it.poultryPayrollItemId)!.activeLoanOutstanding)} outstanding across ${loanHints.get(it.poultryPayrollItemId)!.activeLoanCount} advance(s)`}
                            >
                              {loanHints.get(it.poultryPayrollItemId)!.activeLoanCount === 1
                                ? "active advance"
                                : `${loanHints.get(it.poultryPayrollItemId)!.activeLoanCount} active advances`}
                            </span>
                          )}
                        </TableCell>
                        <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">{gh(it.basicPay)}</TableCell>
                        <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">{gh(it.dailyWage)}</TableCell>
                        <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">{gh(it.commission)}</TableCell>
                        <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">{gh(it.bonus)}</TableCell>
                        <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">
                          {/* Section 49: still ONE column. The total is the way
                              in to what it is made of, rather than a column per
                              deduction type that no phone could hold. */}
                          <button
                            type="button"
                            className="underline decoration-dotted underline-offset-2 hover:text-indigo-700"
                            title="What is this made of?"
                            onClick={() => setDeductionsFor({
                              poultryPayrollItemId: it.poultryPayrollItemId,
                              poultryStaffId: it.poultryStaffId,
                              staffName: it.staffName ?? `#${it.poultryStaffId}`,
                              runStatus: itemsRun.status,
                            })}
                          >
                            {gh(it.deductions)}
                          </button>
                        </TableCell>
                        <TableCell className="text-right tabular-nums font-semibold px-2 whitespace-nowrap">{gh(it.netPay)}</TableCell>
                        <TableCell className="text-right">
                          {isEditable(itemsRun.status) && <Button size="sm" variant="ghost" onClick={() => removeItem(it.poultryPayrollItemId)}><Trash2 className="h-4 w-4 text-red-500" /></Button>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              {isEditable(itemsRun.status) ? (
                <FormSection title="Add / update a line" color="amber" columns={4} stackOnMobile>
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
                  <FormField label="Deductions">
                    <NumberInput step="0.01" value={itemForm.deductions}
                                 onChange={(e) => setItemForm({ ...itemForm, deductions: Number(e.target.value) || 0 })} />
                    {/* Where the figure came from. Without this the box quietly
                        fills itself and looks like something the user typed and
                        forgot. Raising it above the advances adds the extra as
                        an ordinary deduction; lowering it does NOT cancel the
                        advance repayment, which is the one thing worth saying
                        out loud -- remove that from the breakdown instead. */}
                    {itemForm.poultryStaffId > 0 && staffLoans.some((e) => payrollDeductionFor(e) > 0) && (
                      <p className="mt-1 text-[11px] text-slate-500">
                        Includes {gh(staffLoans.reduce((t, e) => t + payrollDeductionFor(e), 0))} of
                        advance repayment. Anything above that is recorded as an other deduction.
                      </p>
                    )}
                  </FormField>
                  <FormField label="Notes"><Input value={itemForm.notes} onChange={(e) => setItemForm({ ...itemForm, notes: e.target.value })} /></FormField>

                  {/* What this person already owes, BEFORE the line is added.
                      The advance repayment is applied automatically on save, so
                      without this the Deductions figure on the new line would be
                      a number the user never typed and cannot account for.
                      Section 50, moved to where the decision is actually made. */}
                  {itemForm.poultryStaffId > 0 && (staffLoansBusy || staffLoans.length > 0) && (
                    <FormField label="&nbsp;" full>
                      <div className="rounded-md border border-indigo-200 bg-indigo-50 p-3 text-sm">
                        {staffLoansBusy ? (
                          <span className="flex items-center gap-2 text-slate-500">
                            <Loader2 className="h-4 w-4 animate-spin" /> Checking advances…
                          </span>
                        ) : (
                          <>
                            <div className="flex items-center gap-2 font-medium text-indigo-900">
                              <HandCoins className="h-4 w-4" />
                              {staffLoans.length === 1
                                ? "1 active advance"
                                : `${staffLoans.length} active advances`}
                            </div>
                            <ul className="mt-1.5 space-y-1">
                              {staffLoans.map((e) => {
                                // The SAME rules autoAddSuggestedDeductions
                                // applies, so what is promised here is what
                                // actually happens on save.
                                const byPayroll = e.repaymentMethod === "PayrollDeduction"
                                               || e.repaymentMethod === "Mixed"
                                const willDeduct = payrollDeductionFor(e)
                                return (
                                  <li key={e.poultryEmployeeLoanId}
                                      className="flex flex-wrap items-baseline justify-between gap-x-3 text-indigo-900">
                                    <span>
                                      {e.loanNumber}
                                      <span className="text-indigo-700/70"> · {gh(e.outstandingBalance)} outstanding</span>
                                    </span>
                                    <span className="text-xs">
                                      {willDeduct > 0
                                        ? <>will deduct <strong className="tabular-nums">{gh(willDeduct)}</strong></>
                                        : byPayroll
                                          ? "no amount set — add it by hand"
                                          : `repaid by ${e.repaymentMethod?.toLowerCase()} — not deducted here`}
                                    </span>
                                  </li>
                                )
                              })}
                            </ul>
                            <p className="mt-2 text-[11px] text-indigo-700/80">
                              Added automatically when you add the line, and editable afterwards from the
                              Deductions figure. Nothing is repaid until the payroll is approved.
                            </p>
                          </>
                        )}
                      </div>
                    </FormField>
                  )}

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

      {/* 306. Opens on the Deductions figure, from either surface. */}
      <PayrollDeductionsDialog
        target={deductionsFor}
        onClose={() => setDeductionsFor(null)}
        fmt={gh}
        onChanged={async () => {
          // A deduction rewrites the line's total AND the run's totals, so both
          // have to be re-read. refreshItems already does exactly that -- it
          // reloads the open run and swaps it into the list behind the dialog.
          if (itemsRun) await refreshItems(itemsRun.poultryPayrollRunId)
        }}
      />

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

  // A Draft run offers five actions. On desktop they are icon-only ghost
  // buttons in a table cell; on mobile that same row overflowed the card, and
  // the icon-only ones (Reopen / Cancel / Delete) carried their meaning solely
  // in a `title` tooltip, which never opens on touch. So mobile gets a
  // two-column grid and every button gets a word.
  function renderActions(r: PoultryPayrollRun, mobile: boolean) {
    const cls = mobile ? "h-10 w-full" : ""
    const v = mobile ? "outline" : "ghost"
    const label = (text: string) => (mobile ? text : "")
    const buttons = (
      <>
        <Button size="sm" variant={v} className={cls} onClick={() => router.push(`/poultry-payroll/${r.poultryPayrollRunId}`)} title="Details"><Eye className="h-4 w-4 mr-1" />{label("Details")}</Button>
        {r.status === "Draft" && <Button size="sm" variant={v} className={cls} onClick={() => openItems(r)} title="Edit lines"><Users className="h-4 w-4 mr-1" />{label("Lines")}</Button>}
        {r.status !== "Draft" && <Button size="sm" variant={v} className={cls} onClick={() => openItems(r)} title="View lines"><Users className="h-4 w-4 mr-1" />{label("Lines")}</Button>}
        {(r.status === "Draft" || r.status === "Reopened") && <Button size="sm" variant={v} className={`${cls} text-blue-700`} onClick={() => approve(r)} title="Approve"><CheckCircle2 className="h-4 w-4 mr-1" />{label("Approve")}</Button>}
        {r.status === "Approved" && <Button size="sm" variant={v} className={`${cls} text-green-700`} onClick={() => { setPaidRun(r); setPayDate(today()) }} title="Mark paid"><Banknote className="h-4 w-4 mr-1" />{label("Mark paid")}</Button>}
        {(r.status === "Approved" || r.status === "Paid") && <Button size="sm" variant={v} className={`${cls} text-amber-700`} onClick={() => { setReasonDlg({ open: true, run: r, kind: "unapprove" }); setReason("") }} title="Reopen"><RotateCcw className="h-4 w-4 mr-1" />{label("Reopen")}</Button>}
        {(r.status === "Draft" || r.status === "Approved") && <Button size="sm" variant={v} className={`${cls} text-rose-600`} onClick={() => { setReasonDlg({ open: true, run: r, kind: "cancel" }); setReason("") }} title="Cancel"><XCircle className="h-4 w-4 mr-1" />{label("Cancel")}</Button>}
        {(r.status === "Draft" || r.status === "Reopened" || r.status === "Cancelled") && <Button size="sm" variant={v} className={`${cls} text-red-600`} onClick={() => setDeleteTarget(r)} title="Delete"><Trash2 className="h-4 w-4 mr-1" />{label("Delete")}</Button>}
      </>
    )
    // w-full so the grid fills MobileCardList's flex row rather than shrinking
    // to its content.
    return mobile ? <div className="grid w-full grid-cols-2 gap-2">{buttons}</div> : buttons
  }
}

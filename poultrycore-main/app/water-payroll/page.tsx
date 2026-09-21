"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import {
  PayrollDeductionsDialog, type PayrollDeductionTarget,
} from "@/components/water/payroll-deductions-dialog"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, Banknote, CheckCircle2, XCircle, Trash2, ExternalLink, HandCoins } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  listWaterPayrollRuns, getWaterPayrollRun, createWaterPayrollRun,
  upsertWaterPayrollItem, deleteWaterPayrollItem,
  listEligibleWaterEmployeeLoans, listWaterPayrollDeductions,
  listWaterPayrollDeductionsForRun, type WaterPayrollDeductionRunRow,
  saveWaterPayrollDeduction,
  type WaterEmployeeLoanEligible,
  approveWaterPayrollRun, markWaterPayrollRunPaid, cancelWaterPayrollRun,
  unapproveWaterPayrollRun, deleteWaterPayrollRun,
  listWaterStaff, listWaterCashAccounts,
  type WaterPayrollRun, type WaterStaff, type WaterCashAccount, type WaterPayrollItem,
} from "@/lib/api/water"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const STATUS_COLORS: Record<string, string> = {
  Draft:     "bg-slate-100 text-slate-700",
  Pending:   "bg-slate-100 text-slate-700",
  Approved:  "bg-blue-100 text-blue-700",
  Paid:      "bg-green-100 text-green-700",
  Reopened:  "bg-amber-100 text-amber-800",
  Cancelled: "bg-rose-100 text-rose-700",
}

// Editable / deletable status set. Reopened sits with Draft/Pending so
// corrections can be made after an Unapprove (Prompt 3 §1 + §5).
const EDITABLE_STATUSES = new Set(["Draft", "Pending", "Reopened"])
const isEditable = (r: WaterPayrollRun) => EDITABLE_STATUSES.has(r.status)

/**
 * What payroll will take off for one advance.
 *
 * ONE definition, shared by the panel that promises it before the item is
 * saved, the Deductions box that is pre-filled with it, and the auto-add that
 * actually posts it. Three copies would eventually promise one number and
 * deduct another.
 *
 * Zero means nothing automatic: either the advance is repaid outside payroll,
 * or no amount was ever suggested for it.
 */
function payrollDeductionFor(e: WaterEmployeeLoanEligible): number {
  const byPayroll = e.repaymentMethod === "PayrollDeduction" || e.repaymentMethod === "Mixed"
  if (!byPayroll) return 0
  // Never more than is left: the server would refuse it, and the user would be
  // reading an error about an amount they never chose.
  return Math.min(e.defaultPayrollDeduction ?? 0, e.outstandingBalance)
}

export default function WaterPayrollPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [runs, setRuns] = useState<WaterPayrollRun[]>([])
  const [staff, setStaff] = useState<WaterStaff[]>([])
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleRuns = useMemo(
    () => filterByDateAndSearch(runs, {
      search, dateFrom, dateTo,
      searchKeys: ["status", "notes"],
      dateKey: "periodStart",
    }),
    [runs, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleRuns)

  const [newRunDlg, setNewRunDlg] = useState(false)
  const [runForm, setRunForm] = useState({ periodStart: "", periodEnd: "", waterCashAccountId: 0, notes: "" })
  // Cancel target → opens the PromptDialog (replaces window.prompt).
  const [cancelTarget, setCancelTarget] = useState<WaterPayrollRun | null>(null)
  // Unapprove target → reopen reason required (Prompt 3 §3).
  const [unapproveTarget, setUnapproveTarget] = useState<WaterPayrollRun | null>(null)
  // Delete target (Draft/Pending/Reopened with no linked active expense).
  const [deleteTarget, setDeleteTarget] = useState<WaterPayrollRun | null>(null)

  const [editing, setEditing] = useState<WaterPayrollRun | null>(null)
  // 314. Which payslip line's deduction breakdown is open, if any.
  const [deductionsFor, setDeductionsFor] = useState<PayrollDeductionTarget | null>(null)
  /** The advances of whoever is selected in the Add-an-item form. */
  const [staffLoans, setStaffLoans] = useState<WaterEmployeeLoanEligible[]>([])
  const [staffLoansBusy, setStaffLoansBusy] = useState(false)
  /**
   * Which lines have advances outstanding, keyed by payroll item.
   *
   * One request for the whole run rather than one per line: the function behind
   * it already aggregates, and 30 staff would otherwise be 30 calls to draw a
   * hint.
   */
  const [loanHints, setLoanHints] =
    useState<Map<number, WaterPayrollDeductionRunRow>>(new Map())
  const [itemForm, setItemForm] = useState({ waterStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [rs, ss, accs] = await Promise.all([listWaterPayrollRuns(), listWaterStaff(), listWaterCashAccounts()])
      setRuns(rs); setStaff(ss); setAccounts(accs)
    } catch (e: any) { toast({ title: "Could not load payroll", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function createRun() {
    if (!runForm.periodStart || !runForm.periodEnd) return toast({ title: "Period required", variant: "destructive" })
    try {
      await createWaterPayrollRun({ ...runForm, waterCashAccountId: runForm.waterCashAccountId || null, notes: runForm.notes || null })
      toast({ title: "Run created" })
      setNewRunDlg(false); setRunForm({ periodStart: "", periodEnd: "", waterCashAccountId: 0, notes: "" })
      await load()
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
  }

  async function openEditing(r: WaterPayrollRun) {
    try {
      const full = await getWaterPayrollRun(r.waterPayrollRunId)
      setEditing(full)
      void loadLoanHints(full.waterPayrollRunId)
    } catch (e: any) { toast({ title: "Load failed", description: e?.message, variant: "destructive" }) }
  }

  async function refreshEditing() {
    if (!editing) return
    try {
      const full = await getWaterPayrollRun(editing.waterPayrollRunId)
      setEditing(full)
      await loadLoanHints(full.waterPayrollRunId)
    } catch { /* no-op */ }
  }

  async function loadLoanHints(runId: number) {
    try {
      const rows = await listWaterPayrollDeductionsForRun(runId)
      setLoanHints(new Map(rows.map((r) => [r.waterPayrollItemId, r])))
    } catch {
      // A missing hint is a missing hint. It must never stop the payroll
      // itself from opening.
      setLoanHints(new Map())
    }
  }

  /**
   * Picking a member of staff fills in what is known about them.
   *
   * Basic comes from the staff record's basePay -- the figure already agreed
   * with that person -- so the common case is "pick the name, press save".
   * Leaving it at 0 meant every line had to be retyped from a number held
   * somewhere else on the system, which is how a payslip ends up wrong.
   *
   * It is a starting point, not a lock: the box stays editable for the month
   * someone is paid differently.
   */
  function prefillFromStaff(staffId: number) {
    const m = staff.find((x) => x.waterStaffId === staffId)
    setItemForm((f) => ({ ...f, waterStaffId: staffId, basicPay: m ? m.basePay : f.basicPay }))
    void loadStaffLoans(staffId)
  }

  async function loadStaffLoans(staffId: number) {
    if (!staffId) { setStaffLoans([]); return }
    setStaffLoansBusy(true)
    try {
      const list = await listEligibleWaterEmployeeLoans(staffId)
      setStaffLoans(list)
      // Put the figure in the box, so the item shows what it will actually
      // deduct rather than 0 followed by a number appearing after saving.
      const auto = list.reduce((sum, e) => sum + payrollDeductionFor(e), 0)
      setItemForm((f) => ({ ...f, deductions: auto }))
    } catch {
      // Not knowing about an advance must never stop an item being added.
      setStaffLoans([])
    } finally {
      setStaffLoansBusy(false)
    }
  }

  /**
   * Put the worker's scheduled advance repayments on the item automatically
   * (spec sections 36 and 37).
   *
   * DRAFT deductions. Nothing is repaid and no balance moves until the run is
   * approved, which is what section 36 forbids doing silently -- making the
   * user retype an amount they already set on the advance was not caution.
   *
   * Only advances the company said would be repaid BY PAYROLL, never more than
   * is left, and never twice: upsert is called again every time a figure on the
   * item is edited.
   */
  async function autoAddSuggestedDeductions(itemId: number, staffId: number): Promise<string[]> {
    try {
      const [eligible, existing] = await Promise.all([
        listEligibleWaterEmployeeLoans(staffId),
        listWaterPayrollDeductions(itemId),
      ])
      const already = new Set(
        existing.filter((d) => d.waterEmployeeLoanId != null)
                .map((d) => d.waterEmployeeLoanId as number))
      const added: string[] = []
      for (const e of eligible) {
        if (already.has(e.waterEmployeeLoanId)) continue
        const amount = payrollDeductionFor(e)
        if (amount <= 0) continue
        await saveWaterPayrollDeduction({
          waterPayrollItemId: itemId,
          deductionType: e.loanType === "SalaryAdvance"
            ? "SalaryAdvanceRepayment" : "EmployeeLoanRepayment",
          amount,
          waterEmployeeLoanId: e.waterEmployeeLoanId,
        })
        added.push(`${e.loanNumber ?? `#${e.waterEmployeeLoanId}`} ${amount.toFixed(2)}`)
      }
      return added
    } catch {
      // The ITEM saved. Losing that because a convenience could not be applied
      // would be the worse outcome; the deduction can still be added by hand.
      return []
    }
  }

  async function addItem() {
    if (!editing) return
    if (!itemForm.waterStaffId) return toast({ title: "Pick staff", variant: "destructive" })
    try {
      const saved = await upsertWaterPayrollItem(editing.waterPayrollRunId, itemForm)
      const added = await autoAddSuggestedDeductions(
        (saved as any).waterPayrollItemId, itemForm.waterStaffId)
      setItemForm({ waterStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })
      setStaffLoans([])
      await refreshEditing(); await load()
      toast({
        title: "Item saved",
        description: added.length > 0
          ? `${added.join(", ")} — review before approving. Nothing is repaid until you approve.`
          : undefined,
      })
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
  }

  async function removeItem(item: WaterPayrollItem) {
    try { await deleteWaterPayrollItem(item.waterPayrollItemId); await refreshEditing(); await load() }
    catch (e: any) { toast({ title: "Remove failed", description: e?.message, variant: "destructive" }) }
  }

  async function doAction(r: WaterPayrollRun, action: "approve" | "pay") {
    try {
      if (action === "approve") await approveWaterPayrollRun(r.waterPayrollRunId)
      if (action === "pay") await markWaterPayrollRunPaid(r.waterPayrollRunId)
      toast({ title: `Run ${action === "pay" ? "marked paid" : action + "d"}` })
      if (editing && editing.waterPayrollRunId === r.waterPayrollRunId) await refreshEditing()
      await load()
    } catch (e: any) { toast({ title: `${action} failed`, description: e?.message, variant: "destructive" }) }
  }

  async function confirmCancelRun(reason: string) {
    if (!cancelTarget) return
    try {
      await cancelWaterPayrollRun(cancelTarget.waterPayrollRunId, reason || undefined)
      toast({ title: "Payroll run cancelled" })
      if (editing && editing.waterPayrollRunId === cancelTarget.waterPayrollRunId) await refreshEditing()
      setCancelTarget(null); await load()
    } catch (e: any) {
      toast({ title: "Cancel failed", description: e?.message, variant: "destructive" })
      throw e
    }
  }

  // Reopen approved/paid run for corrections. Reverses the linked expense
  // (and refunds cash if the run was Paid). See migration 080.
  async function confirmUnapproveRun(reason: string) {
    if (!unapproveTarget) return
    if (!reason || !reason.trim()) {
      toast({ title: "Reason required", description: "Tell future-you why this payroll is being reopened.", variant: "destructive" })
      throw new Error("Reason required")
    }
    try {
      await unapproveWaterPayrollRun(unapproveTarget.waterPayrollRunId, reason.trim())
      toast({ title: "Payroll reopened", description: "Linked expense reversed. Make corrections and approve again." })
      if (editing && editing.waterPayrollRunId === unapproveTarget.waterPayrollRunId) await refreshEditing()
      setUnapproveTarget(null); await load()
    } catch (e: any) {
      toast({ title: "Reopen failed", description: e?.message, variant: "destructive" })
      throw e
    }
  }

  async function performDelete(r: WaterPayrollRun) {
    await deleteWaterPayrollRun(r.waterPayrollRunId)
    if (editing && editing.waterPayrollRunId === r.waterPayrollRunId) setEditing(null)
    await load()
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Banknote className="h-6 w-6 text-sky-600" /> Payroll
            </h1>
            <div className="flex w-full flex-wrap gap-2 sm:w-auto">
              {/* Section 51. A shortcut only -- Employee Loans & Advances is
                  where advances are created, disbursed and repaid. Nothing is
                  duplicated here. */}
              <Button variant="outline" asChild className="h-11 sm:h-10">
                <Link href="/water-employee-loans">
                  <HandCoins className="h-4 w-4 mr-1" /> Employee Loans &amp; Advances
                </Link>
              </Button>
              <Button onClick={() => setNewRunDlg(true)} className="h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New run</Button>
            </div>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search status or notes"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : runs.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No payroll runs yet.</div>
              ) : (
                <MobileCardList
                  striped
                  defaultOpen
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r) => r.waterPayrollRunId}
                  primary={(r) => `${r.periodStart.split("T")[0]} → ${r.periodEnd.split("T")[0]}`}
                  secondary={(r) => (
                    <>
                      <span>Net {r.totalNetPay.toFixed(2)}</span>
                      <Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge>
                    </>
                  )}
                  highlights={(r) => [
                    { label: "Gross", value: r.totalGrossPay.toFixed(2), accent: "blue" },
                    { label: "Net", value: r.totalNetPay.toFixed(2), accent: "emerald" },
                  ]}
                  details={(r) => [
                    { label: "Period", value: `${fmtDateTime(r.periodStart, r)} → ${fmtDateTime(r.periodEnd, r)}` },
                    { label: "Cash account", value: r.cashAccountName ?? "—" },
                    { label: "Status", value: r.status },
                  ]}
                  actions={(r) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => router.push(`/water-payroll/${r.waterPayrollRunId}`)}>
                        <ExternalLink className="h-4 w-4 mr-1" /> Details
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEditing(r)}>Open</Button>
                      {isEditable(r) && (
                        <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => doAction(r, "approve")}>
                          <CheckCircle2 className="h-4 w-4 mr-1" /> {r.status === "Reopened" ? "Re-approve" : "Approve"}
                        </Button>
                      )}
                      {r.status === "Approved" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={() => doAction(r, "pay")}>Mark paid</Button>
                      )}
                      {(r.status === "Approved" || r.status === "Paid") && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => setUnapproveTarget(r)}>
                          Reopen
                        </Button>
                      )}
                      {isEditable(r) && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(r)}>
                          <Trash2 className="h-4 w-4 mr-1" /> Delete
                        </Button>
                      )}
                      {r.status !== "Cancelled" && r.status !== "Paid" && r.status !== "Approved" && r.status !== "Reopened" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setCancelTarget(r)}>
                          <XCircle className="h-4 w-4 mr-1" /> Cancel
                        </Button>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Period</TableHead><TableHead className="text-right">Gross</TableHead><TableHead className="text-right">Net</TableHead><TableHead>Cash account</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((r) => (
                          <TableRow key={r.waterPayrollRunId}>
                            <TableCell className="font-medium">{fmtDateTime(r.periodStart, r)} → {fmtDateTime(r.periodEnd, r)}</TableCell>
                            <TableCell className="text-right tabular-nums">{r.totalGrossPay.toFixed(2)}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold">{r.totalNetPay.toFixed(2)}</TableCell>
                            <TableCell>{r.cashAccountName ?? "—"}</TableCell>
                            <TableCell><Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" title="Open details page" onClick={() => router.push(`/water-payroll/${r.waterPayrollRunId}`)}>
                                <ExternalLink className="h-4 w-4 text-slate-500" />
                              </Button>
                              <Button size="sm" variant="ghost" onClick={() => openEditing(r)}>Open</Button>
                              {isEditable(r) && <Button size="sm" variant="ghost" title={r.status === "Reopened" ? "Re-approve" : "Approve"} onClick={() => doAction(r, "approve")}><CheckCircle2 className="h-4 w-4 text-blue-600" /></Button>}
                              {r.status === "Approved" && <Button size="sm" variant="ghost" onClick={() => doAction(r, "pay")}>Mark paid</Button>}
                              {(r.status === "Approved" || r.status === "Paid") && <Button size="sm" variant="ghost" className="text-amber-700" onClick={() => setUnapproveTarget(r)}>Reopen</Button>}
                              {isEditable(r) && <Button size="sm" variant="ghost" title="Delete run" onClick={() => setDeleteTarget(r)}><Trash2 className="h-4 w-4 text-red-500" /></Button>}
                              {r.status !== "Cancelled" && r.status !== "Paid" && r.status !== "Approved" && r.status !== "Reopened" && <Button size="sm" variant="ghost" title="Cancel run" onClick={() => setCancelTarget(r)}><XCircle className="h-4 w-4 text-rose-500" /></Button>}
                            </TableCell>
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

      {/* New run */}
      <Dialog open={newRunDlg} onOpenChange={setNewRunDlg}>
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Banknote className="w-5 h-5 text-blue-600" /> New payroll run
            </DialogTitle>
            <DialogDescription>Open a payroll run for a pay period</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Period" color="indigo">
              <FormField label="Period start *">
                <Input type="date" value={runForm.periodStart} onChange={(e) => setRunForm({ ...runForm, periodStart: e.target.value })} />
              </FormField>
              <FormField label="Period end *">
                <Input type="date" value={runForm.periodEnd} onChange={(e) => setRunForm({ ...runForm, periodEnd: e.target.value })} />
              </FormField>
            </FormSection>

            <FormSection title="Payment" color="amber" columns={1}>
              <FormField label="Cash account (used at Mark-Paid)">
                <Select value={String(runForm.waterCashAccountId)} onValueChange={(v) => setRunForm({ ...runForm, waterCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Pick account" /></SelectTrigger>
                  <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName} ({a.currentBalance.toFixed(2)})</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={runForm.notes} onChange={(e) => setRunForm({ ...runForm, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setNewRunDlg(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={createRun}>Create</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Open run / edit items */}
      {/* 314. Opens on the Deductions figure. */}
      <PayrollDeductionsDialog
        target={deductionsFor}
        onClose={() => setDeductionsFor(null)}
        fmt={(n) => n.toFixed(2)}
        onChanged={async () => {
          // A deduction rewrites the item's total AND the run's totals, so both
          // have to be re-read.
          await refreshEditing(); await load()
        }}
      />

      <Dialog open={!!editing} onOpenChange={(v) => { if (!v) setEditing(null) }}>
        <DialogContent className="w-[95vw] sm:max-w-6xl max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>
            {editing && (<>Run: {editing.periodStart.split("T")[0]} → {editing.periodEnd.split("T")[0]} <Badge className={STATUS_COLORS[editing.status] ?? ""}>{editing.status}</Badge></>)}
          </DialogTitle></DialogHeader>
          {editing && (
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-3 text-sm">
                <div><span className="text-slate-500">Gross:</span> <span className="font-semibold tabular-nums">{editing.totalGrossPay.toFixed(2)}</span></div>
                <div><span className="text-slate-500">Deductions:</span> <span className="font-semibold tabular-nums">{editing.totalDeductions.toFixed(2)}</span></div>
                <div><span className="text-slate-500">Net:</span> <span className="font-semibold text-green-700 tabular-nums">{editing.totalNetPay.toFixed(2)}</span></div>
              </div>

              <div className="border-t pt-3">
                <div className="font-medium mb-2">Items</div>
                {editing.items && editing.items.length > 0 ? (
                  <>
                  {/* Eight money columns do not fit a phone, and a table you can
                      only read by dragging it sideways loses the staff name the
                      moment you scroll to the net pay. Same rows, stacked,
                      below lg -- which is where the table gets the room. */}
                  <div className="space-y-2 lg:hidden">
                    {editing.items.map((i) => (
                      <div key={i.waterPayrollItemId} className="rounded-lg border bg-white p-3">
                        <div className="flex items-start justify-between gap-2">
                          <div className="font-medium">
                            {i.staffName ?? `#${i.waterStaffId}`}
                            {(loanHints.get(i.waterPayrollItemId)?.activeLoanCount ?? 0) > 0 && (
                              <span className="ml-2 rounded bg-sky-50 px-1.5 py-0.5 text-[10px] font-normal text-sky-700">
                                {loanHints.get(i.waterPayrollItemId)!.activeLoanCount === 1
                                  ? "active advance"
                                  : `${loanHints.get(i.waterPayrollItemId)!.activeLoanCount} active advances`}
                              </span>
                            )}
                          </div>
                          {isEditable(editing) && (
                            <Button size="sm" variant="ghost" onClick={() => removeItem(i)}>
                              <Trash2 className="h-4 w-4 text-red-500" />
                            </Button>
                          )}
                        </div>
                        <div className="mt-2 grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                          <div><span className="text-slate-500">Basic</span> <span className="font-medium tabular-nums">{i.basicPay.toFixed(2)}</span></div>
                          <div><span className="text-slate-500">Daily</span> <span className="font-medium tabular-nums">{i.dailyWage.toFixed(2)}</span></div>
                          <div><span className="text-slate-500">Commission</span> <span className="font-medium tabular-nums">{i.commission.toFixed(2)}</span></div>
                          <div><span className="text-slate-500">Bonus</span> <span className="font-medium tabular-nums">{i.bonus.toFixed(2)}</span></div>
                          <div className="col-span-2">
                            <span className="text-slate-500">Deductions</span>{" "}
                            <button
                              type="button"
                              className="font-medium tabular-nums underline decoration-dotted underline-offset-2"
                              onClick={() => setDeductionsFor({
                                waterPayrollItemId: i.waterPayrollItemId,
                                waterStaffId: i.waterStaffId,
                                staffName: i.staffName ?? `#${i.waterStaffId}`,
                                runStatus: editing.status,
                              })}
                            >
                              {i.deductions.toFixed(2)}
                            </button>
                            <span className="ml-1 text-[11px] text-slate-400">view breakdown</span>
                          </div>
                          <div className="col-span-2 border-t pt-1">
                            <span className="text-slate-500">Net</span>{" "}
                            <span className="font-semibold tabular-nums">{i.netPay.toFixed(2)}</span>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>

                  <div className="hidden lg:block">
                  <Table>
                    <TableHeader>
                      <TableRow><TableHead>Staff</TableHead><TableHead className="text-right px-2 whitespace-nowrap">Basic</TableHead><TableHead className="text-right px-2 whitespace-nowrap">Daily</TableHead><TableHead className="text-right px-2 whitespace-nowrap">Comm.</TableHead><TableHead className="text-right px-2 whitespace-nowrap">Bonus</TableHead><TableHead className="text-right px-2 whitespace-nowrap">Deduct</TableHead><TableHead className="text-right px-2 whitespace-nowrap">Net</TableHead><TableHead className="w-10" /></TableRow>
                    </TableHeader>
                    <TableBody>
                      {editing.items.map((i) => (
                        <TableRow key={i.waterPayrollItemId}>
                          <TableCell className="font-medium min-w-[9rem]">
                            {i.staffName ?? i.waterStaffId}
                            {/* Subtle on purpose: a prompt to open the
                                breakdown, not a call to action. Nothing is
                                deducted because an advance exists. */}
                            {(loanHints.get(i.waterPayrollItemId)?.activeLoanCount ?? 0) > 0 && (
                              <span
                                className="ml-2 rounded bg-sky-50 px-1.5 py-0.5 text-[10px] font-normal text-sky-700"
                                title={`${loanHints.get(i.waterPayrollItemId)!.activeLoanOutstanding.toFixed(2)} outstanding across ${loanHints.get(i.waterPayrollItemId)!.activeLoanCount} advance(s)`}
                              >
                                {loanHints.get(i.waterPayrollItemId)!.activeLoanCount === 1
                                  ? "active advance"
                                  : `${loanHints.get(i.waterPayrollItemId)!.activeLoanCount} active advances`}
                              </span>
                            )}
                          </TableCell>
                          <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">{i.basicPay.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">{i.dailyWage.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">{i.commission.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">{i.bonus.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums px-2 whitespace-nowrap">
                            {/* Still ONE column. The total is the way in to
                                what it is made of, rather than a column per
                                deduction type that no phone could hold. */}
                            <button
                              type="button"
                              className="underline decoration-dotted underline-offset-2 hover:text-sky-700"
                              title="What is this made of?"
                              onClick={() => setDeductionsFor({
                                waterPayrollItemId: i.waterPayrollItemId,
                                waterStaffId: i.waterStaffId,
                                staffName: i.staffName ?? `#${i.waterStaffId}`,
                                runStatus: editing.status,
                              })}
                            >
                              {i.deductions.toFixed(2)}
                            </button>
                          </TableCell>
                          <TableCell className="text-right tabular-nums font-semibold px-2 whitespace-nowrap">{i.netPay.toFixed(2)}</TableCell>
                          <TableCell>
                            {isEditable(editing) && <Button size="sm" variant="ghost" onClick={() => removeItem(i)}><Trash2 className="h-4 w-4 text-red-500" /></Button>}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  </div>
                  </>
                ) : <div className="text-slate-500 text-sm">No items yet.</div>}
              </div>

              {/* Audit panel — visible whenever any audit field is populated.
                  Tracks both the initial approval cycle and any reopen/reapprove
                  cycles (migration 080). */}
              {(editing.approvedBy || editing.paidBy || editing.reopenedBy || editing.reapprovedBy) && (
                <div className="border-t pt-3">
                  <div className="font-medium mb-2">History</div>
                  <ul className="text-sm text-slate-600 space-y-1">
                    {editing.approvedBy && (
                      <li>Approved by <span className="font-medium">{editing.approvedBy}</span>{editing.approvedAt ? ` on ${fmtDateTime(editing.approvedAt, editing)}` : ""}</li>
                    )}
                    {editing.paidBy && (
                      <li>Paid by <span className="font-medium">{editing.paidBy}</span>{editing.paidAt ? ` on ${fmtDateTime(editing.paidAt, editing)}` : ""}</li>
                    )}
                    {editing.reopenedBy && (
                      <li>
                        Reopened by <span className="font-medium">{editing.reopenedBy}</span>
                        {editing.reopenedAt ? ` on ${editing.reopenedAt.split("T")[0]}` : ""}
                        {editing.reopenReason ? <> — <span className="italic">"{editing.reopenReason}"</span></> : null}
                      </li>
                    )}
                    {editing.reapprovedBy && (
                      <li>Re-approved by <span className="font-medium">{editing.reapprovedBy}</span>{editing.reapprovedAt ? ` on ${fmtDateTime(editing.reapprovedAt, editing)}` : ""}</li>
                    )}
                  </ul>
                </div>
              )}

              {isEditable(editing) && (
                <div className="border-t pt-3">
                  <div className="font-medium mb-2">Add / replace item</div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                    <div className="md:col-span-2"><Label>Staff</Label>
                      <Select value={String(itemForm.waterStaffId)} onValueChange={(v) => prefillFromStaff(Number(v))}>
                        <SelectTrigger><SelectValue placeholder="Pick staff" /></SelectTrigger>
                        <SelectContent>{staff.filter(s => s.isActive).map(s => <SelectItem key={s.waterStaffId} value={String(s.waterStaffId)}>{s.firstName} {s.lastName} ({s.role})</SelectItem>)}</SelectContent>
                      </Select></div>
                    <div><Label>Basic</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.basicPay} onChange={(e) => setItemForm({ ...itemForm, basicPay: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Daily</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.dailyWage} onChange={(e) => setItemForm({ ...itemForm, dailyWage: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Commission</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.commission} onChange={(e) => setItemForm({ ...itemForm, commission: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Bonus</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.bonus} onChange={(e) => setItemForm({ ...itemForm, bonus: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Deductions</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.deductions} onChange={(e) => setItemForm({ ...itemForm, deductions: Number(e.target.value) || 0 })} /></div>
                    {/* What this person already owes, BEFORE the item is
                        saved. The advance repayment is applied automatically on
                        save, so without this the Deductions figure would be a
                        number the user never typed and cannot account for. */}
                    {itemForm.waterStaffId > 0 && (staffLoansBusy || staffLoans.length > 0) && (
                      <div className="col-span-2 md:col-span-4 rounded-md border border-sky-200 bg-sky-50 p-3 text-sm">
                        {staffLoansBusy ? (
                          <span className="text-slate-500">Checking advances…</span>
                        ) : (
                          <>
                            <div className="font-medium text-sky-900">
                              {staffLoans.length === 1
                                ? "1 active advance"
                                : `${staffLoans.length} active advances`}
                            </div>
                            <ul className="mt-1.5 space-y-1">
                              {staffLoans.map((e) => {
                                const byPayroll = e.repaymentMethod === "PayrollDeduction"
                                               || e.repaymentMethod === "Mixed"
                                const willDeduct = payrollDeductionFor(e)
                                return (
                                  <li key={e.waterEmployeeLoanId}
                                      className="flex flex-wrap items-baseline justify-between gap-x-3 text-sky-900">
                                    <span>
                                      {e.loanNumber}
                                      <span className="text-sky-700/70"> · {e.outstandingBalance.toFixed(2)} outstanding</span>
                                    </span>
                                    <span className="text-xs">
                                      {willDeduct > 0
                                        ? <>will deduct <strong className="tabular-nums">{willDeduct.toFixed(2)}</strong></>
                                        : byPayroll
                                          ? "no amount set — add it by hand"
                                          : `repaid by ${e.repaymentMethod?.toLowerCase()} — not deducted here`}
                                    </span>
                                  </li>
                                )
                              })}
                            </ul>
                            <p className="mt-2 text-[11px] text-sky-700/80">
                              Added automatically when you save the item, and editable afterwards from the
                              Deductions figure. Nothing is repaid until the payroll is approved.
                            </p>
                          </>
                        )}
                      </div>
                    )}

                    <div className="md:col-span-2 flex items-end">
                      <Button className="w-full" onClick={addItem}>Save item</Button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      <PromptDialog
        open={!!cancelTarget}
        onOpenChange={(v) => { if (!v) setCancelTarget(null) }}
        title="Cancel payroll run"
        description={cancelTarget ? `Run for ${cancelTarget.periodStart?.split("T")[0]} → ${cancelTarget.periodEnd?.split("T")[0]} will be cancelled.` : ""}
        label="Reason (optional)"
        placeholder="e.g. ran twice, wrong period, replacing with corrected run…"
        confirmLabel="Cancel run"
        confirmVariant="destructive"
        allowEmpty
        onSubmit={confirmCancelRun}
      />

      <PromptDialog
        open={!!unapproveTarget}
        onOpenChange={(v) => { if (!v) setUnapproveTarget(null) }}
        title="Reopen payroll run"
        description={
          unapproveTarget
            ? `Run for ${unapproveTarget.periodStart?.split("T")[0]} → ${unapproveTarget.periodEnd?.split("T")[0]} will be reopened. The linked payroll expense will be reversed${unapproveTarget.status === "Paid" ? " and the cash account refunded" : ""}.`
            : ""
        }
        label="Reason *"
        placeholder="e.g. wrong amount for Kofi, missed bonus, correcting period…"
        confirmLabel="Reopen run"
        confirmVariant="destructive"
        onSubmit={confirmUnapproveRun}
      />

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete payroll run?"
        description="This removes the payroll run and all its employee payroll lines. Only available while the run is Draft, Pending, or Reopened — and never while an approved expense is still linked."
        itemLabel={deleteTarget ? `${deleteTarget.periodStart?.split("T")[0]} → ${deleteTarget.periodEnd?.split("T")[0]}` : undefined}
        successTitle="Payroll run removed"
        errorTitle="Delete failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

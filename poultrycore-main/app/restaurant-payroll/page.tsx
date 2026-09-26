"use client"

/**
 * Restaurant — Payroll.
 *
 * A run goes Draft -> Approved -> Paid (migration 326):
 *   Draft     lines are added and edited; staff loan deductions are set here
 *   Approved  each loan deduction becomes a repayment; nothing leaves the till
 *   Paid      NET pay leaves the chosen account (default: Main Cash Box)
 * An Approved run can be reopened (repayments reversed) or cancelled. The P&L
 * shows wages at GROSS pay; Cash Flow shows the net pay that actually left.
 * Closed days are locked and wages cannot be paid on a future date.
 */

import Link from "next/link"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Banknote, Plus, Eye, CheckCircle2, Wallet, Undo2, Ban, Trash2, Users, Pencil, HandCoins, CalendarDays, Info,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "@/lib/api/config"
import { listCashAccounts, todayIso, type CashAccount } from "@/lib/api/restaurant-finance"
import {
  listPayrollRuns, getPayrollRun, createPayrollRun, deletePayrollRun, savePayrollLine, deletePayrollLine,
  addAllStaffToPayroll, approvePayrollRun, reopenPayrollRun, cancelPayrollRun, markPayrollRunPaid,
  listEligibleStaffLoans, staffLoanTypeLabel,
  type PayrollRun, type PayrollRunDetail, type PayrollLine,
} from "@/lib/api/restaurant-payroll"

interface StaffRow { restaurantStaffId: number; firstName: string; lastName: string; role: string; salaryType: string; basePay: number; isActive: boolean }

async function listRestaurantStaff(): Promise<StaffRow[]> {
  const { farmId } = getUserContext()
  const res = await fetch(farmApiUrl(`/Restaurant/staff?farmId=${encodeURIComponent(farmId ?? "")}`), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

const STATUS_STYLE: Record<string, string> = {
  Draft: "bg-gray-100 text-gray-700 border-gray-200",
  Approved: "bg-blue-50 text-blue-700 border-blue-200",
  Paid: "bg-green-50 text-green-700 border-green-200",
  Cancelled: "bg-red-50 text-red-700 border-red-200",
}
const dateOnly = (s?: string | null) => (s ? s.split("T")[0] : "—")
const n = (s: string) => (s.trim() ? parseFloat(s) || 0 : 0)
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01` }

interface LoanRow { loanId: number; loanNumber: string; loanType: string; outstanding: number; available: number; suggested: number; amount: string }
interface LineForm { staffId: string; basicPay: string; allowances: string; overtime: string; bonus: string; otherDeductions: string; paymentMethod: string }
const blankLine = (): LineForm => ({ staffId: "", basicPay: "", allowances: "", overtime: "", bonus: "", otherDeductions: "", paymentMethod: "Cash" })

export default function RestaurantPayrollPage() {
  const router = useRouter()
  const { toast } = useToast()
  const fmt = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canView = permissions.isAdmin || permissions.featureAccess.canViewRestaurantStaff

  const [loading, setLoading] = useState(true)
  const [runs, setRuns] = useState<PayrollRun[]>([])
  const [staff, setStaff] = useState<StaffRow[]>([])
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [statusFilter, setStatusFilter] = useState("ALL")
  const [saving, setSaving] = useState(false)

  const [newOpen, setNewOpen] = useState(false)
  const [newForm, setNewForm] = useState({ periodStart: firstOfMonth(), periodEnd: todayIso(), payDate: todayIso(), cashAccountId: "", notes: "" })

  const [detail, setDetail] = useState<PayrollRunDetail | null>(null)
  const [lineForm, setLineForm] = useState<LineForm>(blankLine())
  const [editingLineId, setEditingLineId] = useState<number | null>(null)
  const [loanRows, setLoanRows] = useState<LoanRow[]>([])

  const [payTarget, setPayTarget] = useState<PayrollRun | null>(null)
  const [payForm, setPayForm] = useState({ payDate: todayIso(), cashAccountId: "" })
  const [reasonAction, setReasonAction] = useState<null | { kind: "reopen" | "cancel"; run: PayrollRun }>(null)
  const [reason, setReason] = useState("")
  const [deleteTarget, setDeleteTarget] = useState<PayrollRun | null>(null)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    try {
      const [rs, st, accs] = await Promise.all([listPayrollRuns(), listRestaurantStaff(), listCashAccounts()])
      setRuns(rs ?? []); setStaff(st ?? []); setAccounts((accs ?? []).filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Could not load payroll", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally { setLoading(false) }
  }, [toast])

  useEffect(() => {
    if (!activeFarmId || !canView) { setLoading(false); return }
    void load()
  }, [activeFarmId, canView, load])

  async function reloadDetail(id: number) {
    setDetail(await getPayrollRun(id))
  }

  async function run<T>(label: string, fn: () => Promise<T>, done?: (r: T) => string | void): Promise<boolean> {
    setSaving(true)
    try {
      const r = await fn()
      const msg = done?.(r)
      if (msg) toast({ title: msg })
      return true
    } catch (e: any) {
      toast({ title: label, description: e?.message, variant: "destructive" })
      return false
    } finally { setSaving(false) }
  }

  // ----- runs -----
  async function createRun() {
    const ok = await run("Could not create the payroll run", () => createPayrollRun({
      periodStart: newForm.periodStart, periodEnd: newForm.periodEnd, payDate: newForm.payDate || null,
      cashAccountId: newForm.cashAccountId ? Number(newForm.cashAccountId) : null, notes: newForm.notes || null,
    }), () => "Payroll run created")
    if (ok) { setNewOpen(false); await load() }
  }

  async function openRun(r: PayrollRun) {
    resetLine()
    try { setDetail(await getPayrollRun(r.payrollRunId)) }
    catch (e: any) { toast({ title: "Could not open the run", description: e?.message, variant: "destructive" }) }
  }

  async function approve(r: PayrollRun) {
    const ok = await run("Could not approve", () => approvePayrollRun(r.payrollRunId),
      (x) => x.loanRepaymentsPosted ? `Approved — ${x.loanRepaymentsPosted} staff loan repayment(s) recorded` : "Payroll run approved")
    if (ok) { await load(); if (detail?.run.payrollRunId === r.payrollRunId) await reloadDetail(r.payrollRunId) }
  }

  async function markPaid() {
    if (!payTarget) return
    const ok = await run("Could not mark paid", () => markPayrollRunPaid(payTarget.payrollRunId, {
      payDate: payForm.payDate, cashAccountId: payForm.cashAccountId ? Number(payForm.cashAccountId) : null,
    }), () => `${fmt(payTarget.totalNet)} net pay paid out`)
    if (ok) { const id = payTarget.payrollRunId; setPayTarget(null); await load(); if (detail?.run.payrollRunId === id) await reloadDetail(id) }
  }

  async function submitReason() {
    if (!reasonAction) return
    if (reasonAction.kind === "reopen" && !reason.trim()) { toast({ title: "Give a reason", variant: "destructive" }); return }
    const r = reasonAction.run
    const ok = await run(reasonAction.kind === "reopen" ? "Could not reopen" : "Could not cancel",
      () => reasonAction.kind === "reopen" ? reopenPayrollRun(r.payrollRunId, reason) : cancelPayrollRun(r.payrollRunId, reason),
      () => reasonAction.kind === "reopen" ? "Payroll run reopened" : "Payroll run cancelled")
    if (ok) { setReasonAction(null); setReason(""); await load(); if (detail?.run.payrollRunId === r.payrollRunId) await reloadDetail(r.payrollRunId) }
  }

  async function confirmDelete() {
    if (!deleteTarget) return
    const ok = await run("Could not delete", () => deletePayrollRun(deleteTarget.payrollRunId), () => "Payroll run deleted")
    if (ok) { if (detail?.run.payrollRunId === deleteTarget.payrollRunId) setDetail(null); setDeleteTarget(null); await load() }
  }

  // ----- lines -----
  function resetLine() { setLineForm(blankLine()); setEditingLineId(null); setLoanRows([]) }

  async function loadLoans(staffId: number, lineId: number | null) {
    setLoanRows([])
    if (!staffId) return
    try {
      const rows = await listEligibleStaffLoans(staffId, lineId)
      setLoanRows(rows.map((l) => ({
        loanId: l.staffLoanId, loanNumber: l.loanNumber, loanType: l.loanType, outstanding: l.outstandingBalance,
        available: l.available, suggested: l.suggestedDeduction,
        amount: String(lineId ? l.currentDeduction : l.suggestedDeduction),
      })))
    } catch (e: any) { toast({ title: "Could not load staff loans", description: e?.message, variant: "destructive" }) }
  }

  function pickStaff(v: string) {
    const s = staff.find((x) => String(x.restaurantStaffId) === v)
    setLineForm({ ...blankLine(), staffId: v, basicPay: s ? String(s.basePay) : "" })
    void loadLoans(Number(v), null)
  }

  function editLine(l: PayrollLine) {
    setEditingLineId(l.payrollLineId)
    setLineForm({
      staffId: String(l.restaurantStaffId), basicPay: String(l.basicPay), allowances: l.allowances ? String(l.allowances) : "",
      overtime: l.overtime ? String(l.overtime) : "", bonus: l.bonus ? String(l.bonus) : "",
      otherDeductions: l.otherDeductions ? String(l.otherDeductions) : "", paymentMethod: l.paymentMethod || "Cash",
    })
    void loadLoans(l.restaurantStaffId, l.payrollLineId)
  }

  const lineGross = n(lineForm.basicPay) + n(lineForm.allowances) + n(lineForm.overtime) + n(lineForm.bonus)
  const lineLoans = loanRows.reduce((s, l) => s + n(l.amount), 0)
  const lineNet = lineGross - n(lineForm.otherDeductions) - lineLoans

  async function saveLine() {
    if (!detail) return
    if (!lineForm.staffId) { toast({ title: "Choose the staff member", variant: "destructive" }); return }
    const over = loanRows.find((l) => n(l.amount) > l.available + 0.001)
    if (over) { toast({ title: `At most ${fmt(over.available)} can be deducted for ${over.loanNumber}`, variant: "destructive" }); return }
    if (lineNet < 0) { toast({ title: "Deductions are more than the pay", variant: "destructive" }); return }
    const ok = await run("Could not save the line", () => savePayrollLine(detail.run.payrollRunId, {
      restaurantStaffId: Number(lineForm.staffId), basicPay: n(lineForm.basicPay), allowances: n(lineForm.allowances),
      overtime: n(lineForm.overtime), bonus: n(lineForm.bonus), otherDeductions: n(lineForm.otherDeductions),
      paymentMethod: lineForm.paymentMethod, loanDeductions: loanRows.map((l) => ({ loanId: l.loanId, amount: n(l.amount) })),
    }), () => editingLineId ? "Line updated" : "Line added")
    if (ok) { resetLine(); await reloadDetail(detail.run.payrollRunId); await load() }
  }

  async function removeLine(l: PayrollLine) {
    if (!detail) return
    const ok = await run("Could not remove the line", () => deletePayrollLine(l.payrollLineId), () => "Line removed")
    if (ok) { if (editingLineId === l.payrollLineId) resetLine(); await reloadDetail(detail.run.payrollRunId); await load() }
  }

  async function addAll() {
    if (!detail) return
    const ok = await run("Could not add staff", () => addAllStaffToPayroll(detail.run.payrollRunId),
      (x) => x.added ? `${x.added} staff member(s) added at their base pay, with suggested loan deductions` : "Every active staff member is already on this run")
    if (ok) { await reloadDetail(detail.run.payrollRunId); await load() }
  }

  // ----- derived -----
  const filtered = useMemo(() => runs.filter((r) => statusFilter === "ALL" || r.status === statusFilter), [runs, statusFilter])
  const draftCount = runs.filter((r) => r.status === "Draft").length
  const approved = runs.filter((r) => r.status === "Approved")
  const lastPaid = runs.find((r) => r.status === "Paid")
  const staffNotOnRun = detail ? staff.filter((s) => s.isActive && !detail.lines.some((l) => l.restaurantStaffId === s.restaurantStaffId)) : []

  const accountSelect = (value: string, onChange: (v: string) => void, placeholder: string) => (
    <Select value={value || "DEFAULT"} onValueChange={(v) => onChange(v === "DEFAULT" ? "" : v)}>
      <SelectTrigger><SelectValue /></SelectTrigger>
      <SelectContent>
        <SelectItem value="DEFAULT">{placeholder}</SelectItem>
        {accounts.map((a) => <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{a.name} ({fmt(a.currentBalance)})</SelectItem>)}
      </SelectContent>
    </Select>
  )

  if (loading) return <PageSkeleton statCards={4} listRows={6} />

  const shell = (children: React.ReactNode) => (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6"><div className="max-w-7xl mx-auto space-y-6">{children}</div></main>
      </div>
    </div>
  )

  if (!canView) return shell(
    <Card><CardContent className="py-12 text-center text-gray-600">You do not have access to payroll. Ask an admin for the Staff &amp; payroll permission.</CardContent></Card>
  )

  const d = detail
  const isDraft = d?.run.status === "Draft"

  return shell(<>
    <PageHeader icon={Banknote} title="Payroll" subtitle="Pay runs for restaurant staff, with staff loan deductions">
      <div className="flex gap-2">
        <Button variant="outline" asChild><Link href="/restaurant-staff-loans"><HandCoins className="h-4 w-4 mr-1" />Staff loans</Link></Button>
        <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => { setNewForm({ periodStart: firstOfMonth(), periodEnd: todayIso(), payDate: todayIso(), cashAccountId: "", notes: "" }); setNewOpen(true) }}>
          <Plus className="h-4 w-4 mr-1" />New payroll run
        </Button>
      </div>
    </PageHeader>

    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <StatCard label="Draft runs" value={String(draftCount)} icon={CalendarDays} color="blue" />
      <StatCard label={`Approved, not yet paid (${approved.length})`} value={fmt(approved.reduce((s, r) => s + r.totalNet, 0))} icon={CheckCircle2} color="amber" />
      <StatCard label={lastPaid ? `Last paid · ${lastPaid.runNumber}` : "Last paid"} value={lastPaid ? fmt(lastPaid.totalNet) : "—"} icon={Wallet} color="green" />
      <StatCard label="Active staff" value={String(staff.filter((s) => s.isActive).length)} icon={Users} color="rose" />
    </div>

    <div className="w-full sm:w-56">
      <Select value={statusFilter} onValueChange={setStatusFilter}>
        <SelectTrigger><SelectValue /></SelectTrigger>
        <SelectContent>
          {["ALL", "Draft", "Approved", "Paid", "Cancelled"].map((s) => <SelectItem key={s} value={s}>{s === "ALL" ? "All runs" : s}</SelectItem>)}
        </SelectContent>
      </Select>
    </div>

    {filtered.length === 0 ? (
      <EmptyState icon={Banknote} title={runs.length === 0 ? "No payroll runs yet" : "No runs with this status"}
        description="Create a run for the pay period, add your staff, approve it, then mark it paid."
        actionLabel="New payroll run" onAction={() => setNewOpen(true)} />
    ) : (
      <Card><CardContent className="p-0"><div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[860px]">
          <thead><tr className="border-b bg-gray-50 text-gray-600">
            <th className="text-left p-3">Run</th><th className="text-left p-3">Period</th><th className="text-right p-3">Staff</th>
            <th className="text-right p-3">Gross</th><th className="text-right p-3">Deductions</th><th className="text-right p-3">Net pay</th>
            <th className="text-center p-3">Status</th><th className="text-right p-3">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.map((r) => (
              <tr key={r.payrollRunId} className="border-b hover:bg-gray-50">
                <td className="p-3 font-mono text-xs font-semibold">{r.runNumber}<div className="font-sans font-normal text-gray-500">pay {dateOnly(r.payDate)}</div></td>
                <td className="p-3">{dateOnly(r.periodStart)} – {dateOnly(r.periodEnd)}</td>
                <td className="p-3 text-right">{r.lineCount}</td>
                <td className="p-3 text-right tabular-nums">{fmt(r.totalGross)}</td>
                <td className="p-3 text-right tabular-nums">{fmt(r.totalDeductions)}{r.totalLoanDeductions > 0 && <div className="text-xs text-rose-700">{fmt(r.totalLoanDeductions)} staff loans</div>}</td>
                <td className="p-3 text-right tabular-nums font-semibold">{fmt(r.totalNet)}</td>
                <td className="p-3 text-center"><Badge variant="outline" className={`text-xs ${STATUS_STYLE[r.status] ?? ""}`}>{r.status}</Badge></td>
                <td className="p-3 text-right whitespace-nowrap">
                  <Button size="icon" variant="ghost" title="Open" onClick={() => openRun(r)}><Eye className="h-4 w-4" /></Button>
                  {r.status === "Draft" && <>
                    <Button size="icon" variant="ghost" title="Approve" onClick={() => approve(r)} disabled={saving}><CheckCircle2 className="h-4 w-4 text-blue-600" /></Button>
                    <Button size="icon" variant="ghost" title="Cancel" onClick={() => setReasonAction({ kind: "cancel", run: r })}><Ban className="h-4 w-4 text-amber-600" /></Button>
                    <Button size="icon" variant="ghost" title="Delete" onClick={() => setDeleteTarget(r)}><Trash2 className="h-4 w-4 text-red-600" /></Button>
                  </>}
                  {r.status === "Approved" && <>
                    <Button size="icon" variant="ghost" title="Mark paid" onClick={() => { setPayTarget(r); setPayForm({ payDate: r.payDate && dateOnly(r.payDate) <= todayIso() ? dateOnly(r.payDate) : todayIso(), cashAccountId: r.cashAccountId ? String(r.cashAccountId) : "" }) }}><Wallet className="h-4 w-4 text-green-600" /></Button>
                    <Button size="icon" variant="ghost" title="Reopen to correct" onClick={() => setReasonAction({ kind: "reopen", run: r })}><Undo2 className="h-4 w-4 text-gray-600" /></Button>
                    <Button size="icon" variant="ghost" title="Cancel" onClick={() => setReasonAction({ kind: "cancel", run: r })}><Ban className="h-4 w-4 text-amber-600" /></Button>
                  </>}
                  {r.status === "Cancelled" && <Button size="icon" variant="ghost" title="Delete" onClick={() => setDeleteTarget(r)}><Trash2 className="h-4 w-4 text-red-600" /></Button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div></CardContent></Card>
    )}

    {/* ===== new run ===== */}
    <Dialog open={newOpen} onOpenChange={setNewOpen}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader><DialogTitle>New payroll run</DialogTitle><DialogDescription>Choose the pay period. Staff are added after the run is created.</DialogDescription></DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1"><Label>Period start *</Label><Input type="date" value={newForm.periodStart} onChange={(e) => setNewForm({ ...newForm, periodStart: e.target.value })} /></div>
          <div className="space-y-1"><Label>Period end *</Label><Input type="date" value={newForm.periodEnd} onChange={(e) => setNewForm({ ...newForm, periodEnd: e.target.value })} /></div>
          <div className="space-y-1"><Label>Pay date</Label><Input type="date" value={newForm.payDate} onChange={(e) => setNewForm({ ...newForm, payDate: e.target.value })} /></div>
          <div className="space-y-1"><Label>Pay from</Label>{accountSelect(newForm.cashAccountId, (v) => setNewForm({ ...newForm, cashAccountId: v }), "Main Cash Box (default)")}</div>
          <div className="space-y-1 sm:col-span-2"><Label>Notes</Label><Input value={newForm.notes} onChange={(e) => setNewForm({ ...newForm, notes: e.target.value })} /></div>
        </div>
        <DialogFooter><Button variant="outline" onClick={() => setNewOpen(false)}>Cancel</Button><Button className="bg-rose-600 hover:bg-rose-700" disabled={saving} onClick={createRun}>Create</Button></DialogFooter>
      </DialogContent>
    </Dialog>

    {/* ===== run detail ===== */}
    <Dialog open={!!d} onOpenChange={(v) => { if (!v) { setDetail(null); resetLine() } }}>
      <DialogContent className="sm:max-w-6xl max-h-[92vh] overflow-y-auto">
        {d && <>
          <DialogHeader>
            <DialogTitle className="flex flex-wrap items-center gap-2">{d.run.runNumber} · {dateOnly(d.run.periodStart)} – {dateOnly(d.run.periodEnd)}
              <Badge variant="outline" className={`text-xs ${STATUS_STYLE[d.run.status] ?? ""}`}>{d.run.status}</Badge></DialogTitle>
            <DialogDescription>Pay date {dateOnly(d.run.payDate)} · paid from {d.run.cashAccountName ?? "Main Cash Box"}</DialogDescription>
          </DialogHeader>

          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            {[["Gross pay", fmt(d.run.totalGross), ""], ["Other deductions", fmt(d.run.totalDeductions - d.run.totalLoanDeductions), "text-amber-700"],
              ["Staff loan repayments", fmt(d.run.totalLoanDeductions), "text-rose-700"], ["Net pay", fmt(d.run.totalNet), "text-green-700"]].map(([l, v, c]) => (
              <div key={l} className="rounded-lg border p-3"><div className="text-xs text-gray-500">{l}</div><div className={`text-lg font-bold tabular-nums ${c}`}>{v}</div></div>
            ))}
          </div>
          {d.run.totalLoanDeductions > 0 && (
            <p className="flex gap-2 text-xs text-gray-600"><Info className="h-3.5 w-3.5 mt-0.5 shrink-0" />
              {d.run.status === "Draft" ? "Staff loan deductions are recorded as repayments when this run is approved."
                : d.run.status === "Cancelled" ? "This run's staff loan repayments were reversed." : "These deductions are recorded against the staff members' loans."}
            </p>
          )}

          <div className="overflow-x-auto rounded-lg border">
            <table className="w-full text-sm min-w-[860px]">
              <thead><tr className="border-b bg-gray-50 text-gray-600">
                <th className="text-left p-2">Staff</th><th className="text-right p-2">Basic</th><th className="text-right p-2">Allowances</th>
                <th className="text-right p-2">Overtime</th><th className="text-right p-2">Bonus</th><th className="text-right p-2">Gross</th>
                <th className="text-right p-2">Deductions</th><th className="text-right p-2">Net</th>{isDraft && <th className="p-2"></th>}
              </tr></thead>
              <tbody>
                {d.lines.length === 0 && <tr><td colSpan={9} className="p-6 text-center text-gray-400">No staff on this run yet.</td></tr>}
                {d.lines.map((l) => (
                  <tr key={l.payrollLineId} className={`border-b ${editingLineId === l.payrollLineId ? "bg-rose-50" : ""}`}>
                    <td className="p-2"><div className="font-medium">{l.staffName}</div><div className="text-xs text-gray-500">{l.staffRole}{l.salaryType ? ` · ${l.salaryType}` : ""}</div></td>
                    <td className="p-2 text-right tabular-nums">{fmt(l.basicPay)}</td>
                    <td className="p-2 text-right tabular-nums">{fmt(l.allowances)}</td>
                    <td className="p-2 text-right tabular-nums">{fmt(l.overtime)}</td>
                    <td className="p-2 text-right tabular-nums">{fmt(l.bonus)}</td>
                    <td className="p-2 text-right tabular-nums">{fmt(l.grossPay)}</td>
                    <td className="p-2 text-right tabular-nums">
                      {fmt(l.otherDeductions + l.loanDeductions)}
                      {d.deductions.filter((x) => x.payrollLineId === l.payrollLineId).map((x) => (
                        <div key={x.payrollDeductionId} className={`text-xs ${x.status === "Reversed" ? "text-gray-400 line-through" : "text-rose-700"}`}>{x.loanNumber} {fmt(x.amount)}</div>
                      ))}
                    </td>
                    <td className="p-2 text-right tabular-nums font-semibold">{fmt(l.netPay)}</td>
                    {isDraft && <td className="p-2 text-right whitespace-nowrap">
                      <Button size="icon" variant="ghost" title="Edit" onClick={() => editLine(l)}><Pencil className="h-4 w-4" /></Button>
                      <Button size="icon" variant="ghost" title="Remove" onClick={() => removeLine(l)}><Trash2 className="h-4 w-4 text-red-600" /></Button>
                    </td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {isDraft && (
            <div className="space-y-3">
              {staffNotOnRun.length > 0 && !editingLineId && (
                <div className="flex flex-col gap-2 rounded-lg border border-rose-200 bg-rose-50 p-3 sm:flex-row sm:items-center">
                  <div className="flex-1 text-sm text-rose-800"><strong>{staffNotOnRun.length}</strong> active staff member(s) are not on this run yet.</div>
                  <Button variant="outline" className="border-rose-300 text-rose-700" disabled={saving} onClick={addAll}><Users className="h-4 w-4 mr-1" />Add all at base pay</Button>
                </div>
              )}
              {(editingLineId || staffNotOnRun.length > 0) && (
                <Card><CardContent className="p-4 space-y-3">
                  <div className="text-sm font-semibold">{editingLineId ? `Edit line: ${d.lines.find((l) => l.payrollLineId === editingLineId)?.staffName ?? ""}` : "Add one staff member"}</div>
                  <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
                    <div className="space-y-1 col-span-2"><Label>Staff *</Label>
                      <Select value={lineForm.staffId} onValueChange={pickStaff} disabled={!!editingLineId}>
                        <SelectTrigger><SelectValue placeholder="Choose staff" /></SelectTrigger>
                        <SelectContent>
                          {editingLineId && <SelectItem value={lineForm.staffId}>{d.lines.find((l) => l.payrollLineId === editingLineId)?.staffName}</SelectItem>}
                          {staffNotOnRun.map((s) => <SelectItem key={s.restaurantStaffId} value={String(s.restaurantStaffId)}>{`${s.firstName} ${s.lastName ?? ""}`.trim()} — {s.role} ({s.salaryType} {fmt(s.basePay)})</SelectItem>)}
                        </SelectContent>
                      </Select></div>
                    <div className="space-y-1"><Label>Basic pay</Label><Input type="number" min="0" step="0.01" value={lineForm.basicPay} onChange={(e) => setLineForm({ ...lineForm, basicPay: e.target.value })} /></div>
                    <div className="space-y-1"><Label>Allowances</Label><Input type="number" min="0" step="0.01" value={lineForm.allowances} onChange={(e) => setLineForm({ ...lineForm, allowances: e.target.value })} /></div>
                    <div className="space-y-1"><Label>Overtime</Label><Input type="number" min="0" step="0.01" value={lineForm.overtime} onChange={(e) => setLineForm({ ...lineForm, overtime: e.target.value })} /></div>
                    <div className="space-y-1"><Label>Bonus</Label><Input type="number" min="0" step="0.01" value={lineForm.bonus} onChange={(e) => setLineForm({ ...lineForm, bonus: e.target.value })} /></div>
                    <div className="space-y-1"><Label>Other deductions</Label><Input type="number" min="0" step="0.01" value={lineForm.otherDeductions} onChange={(e) => setLineForm({ ...lineForm, otherDeductions: e.target.value })} /></div>
                    <div className="space-y-1"><Label>Paid by</Label>
                      <Select value={lineForm.paymentMethod} onValueChange={(v) => setLineForm({ ...lineForm, paymentMethod: v })}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{["Cash", "MoMo", "Bank"].map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                      </Select></div>
                  </div>
                  {loanRows.length > 0 && (
                    <div className="rounded-lg border border-rose-200 bg-rose-50 p-3 space-y-2">
                      <div className="flex items-center gap-2 text-sm font-semibold text-rose-800"><HandCoins className="h-4 w-4" />Staff loan deductions</div>
                      {loanRows.map((l, i) => (
                        <div key={l.loanId} className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_10rem] sm:items-center">
                          <div className="text-sm"><span className="font-mono font-semibold">{l.loanNumber}</span> · {staffLoanTypeLabel(l.loanType)}
                            <span className="text-gray-600"> — owes {fmt(l.outstanding)}</span>
                            {l.available < l.outstanding && <span className="text-amber-700"> ({fmt(l.outstanding - l.available)} already on another draft run)</span>}
                            {l.suggested > 0 && <span className="text-gray-500"> · suggested {fmt(l.suggested)}</span>}</div>
                          <Input type="number" min="0" max={l.available} step="0.01" value={l.amount}
                            onChange={(e) => setLoanRows((rows) => rows.map((r, j) => (j === i ? { ...r, amount: e.target.value } : r)))} />
                        </div>
                      ))}
                      <p className="text-xs text-rose-800">Taken from net pay; nothing extra leaves the till. The loan balance falls when the run is approved. Set 0 to skip a loan this period.</p>
                    </div>
                  )}
                  <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                    <div className={`text-sm font-medium ${lineNet < 0 ? "text-red-600" : "text-gray-700"}`}>
                      Gross {fmt(lineGross)} · Net pay {fmt(lineNet)}{lineNet < 0 ? " — deductions are more than the pay" : ""}
                    </div>
                    <div className="flex gap-2">
                      {editingLineId && <Button variant="outline" onClick={resetLine}>Cancel</Button>}
                      <Button className="bg-rose-600 hover:bg-rose-700" disabled={saving} onClick={saveLine}>{editingLineId ? "Update line" : "Add line"}</Button>
                    </div>
                  </div>
                </CardContent></Card>
              )}
            </div>
          )}

          <div className="flex flex-wrap gap-2 border-t pt-3">
            {d.run.status === "Draft" && <Button className="bg-blue-600 hover:bg-blue-700" disabled={saving || d.lines.length === 0} onClick={() => approve(d.run)}><CheckCircle2 className="h-4 w-4 mr-1" />Approve</Button>}
            {d.run.status === "Approved" && <>
              <Button className="bg-green-600 hover:bg-green-700" onClick={() => { setPayTarget(d.run); setPayForm({ payDate: dateOnly(d.run.payDate) <= todayIso() ? dateOnly(d.run.payDate) : todayIso(), cashAccountId: d.run.cashAccountId ? String(d.run.cashAccountId) : "" }) }}><Wallet className="h-4 w-4 mr-1" />Mark paid</Button>
              <Button variant="outline" onClick={() => setReasonAction({ kind: "reopen", run: d.run })}><Undo2 className="h-4 w-4 mr-1" />Reopen</Button>
            </>}
          </div>
          <div className="text-xs text-gray-500 space-y-0.5">
            {d.run.createdBy && <p>Created by {d.run.createdBy}</p>}
            {d.run.approvedBy && <p>Approved by {d.run.approvedBy}</p>}
            {d.run.paidBy && <p>Paid by {d.run.paidBy} on {dateOnly(d.run.payDate)}</p>}
            {d.run.reopenedBy && <p>Last reopened by {d.run.reopenedBy}: {d.run.reopenReason}</p>}
            {d.run.cancelledBy && <p>Cancelled by {d.run.cancelledBy}{d.run.cancelReason ? `: ${d.run.cancelReason}` : ""}</p>}
          </div>
        </>}
      </DialogContent>
    </Dialog>

    {/* ===== mark paid ===== */}
    <Dialog open={!!payTarget} onOpenChange={(v) => { if (!v) setPayTarget(null) }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader><DialogTitle>Mark {payTarget?.runNumber} paid</DialogTitle>
          <DialogDescription>{payTarget ? `${fmt(payTarget.totalNet)} net pay leaves the account below. The P&L shows ${fmt(payTarget.totalGross)} of wages.` : ""}</DialogDescription></DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1"><Label>Paid on</Label><Input type="date" max={todayIso()} value={payForm.payDate} onChange={(e) => setPayForm({ ...payForm, payDate: e.target.value })} /></div>
          <div className="space-y-1"><Label>Paid from</Label>{accountSelect(payForm.cashAccountId, (v) => setPayForm({ ...payForm, cashAccountId: v }), "Main Cash Box (default)")}</div>
        </div>
        <DialogFooter><Button variant="outline" onClick={() => setPayTarget(null)}>Back</Button><Button className="bg-green-600 hover:bg-green-700" disabled={saving} onClick={markPaid}>Mark paid</Button></DialogFooter>
      </DialogContent>
    </Dialog>

    {/* ===== reopen / cancel ===== */}
    <Dialog open={!!reasonAction} onOpenChange={(v) => { if (!v) { setReasonAction(null); setReason("") } }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{reasonAction?.kind === "reopen" ? `Reopen ${reasonAction.run.runNumber}?` : `Cancel ${reasonAction?.run.runNumber}?`}</DialogTitle>
          <DialogDescription>{reasonAction?.kind === "reopen"
            ? "The run goes back to Draft so its lines can be corrected. Staff loan repayments it recorded are reversed, and come back when it is approved again."
            : "The run is closed. Any staff loan repayments it recorded are reversed; no money has left for it."}</DialogDescription>
        </DialogHeader>
        <div className="space-y-1"><Label>Reason{reasonAction?.kind === "reopen" ? " *" : " (optional)"}</Label><Textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></div>
        <DialogFooter><Button variant="outline" onClick={() => { setReasonAction(null); setReason("") }}>Back</Button>
          <Button variant={reasonAction?.kind === "cancel" ? "destructive" : "default"} disabled={saving} onClick={submitReason}>{reasonAction?.kind === "reopen" ? "Reopen" : "Cancel run"}</Button></DialogFooter>
      </DialogContent>
    </Dialog>

    {/* ===== delete ===== */}
    <Dialog open={!!deleteTarget} onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader><DialogTitle>Delete {deleteTarget?.runNumber}?</DialogTitle>
          <DialogDescription>The run and its lines are removed. Nothing was posted for a draft or cancelled run, so no money changes.</DialogDescription></DialogHeader>
        <DialogFooter><Button variant="outline" onClick={() => setDeleteTarget(null)}>Back</Button><Button variant="destructive" disabled={saving} onClick={confirmDelete}>Delete</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </>)
}

"use client"

/**
 * Restaurant — Staff Loans & Advances (money LENT TO STAFF).
 * Money the restaurant itself borrowed is on the Loans page (/restaurant-loans).
 *
 * The rules live in the database (migration 326):
 *   - Paying out moves the PRINCIPAL out of a cash account (default Main Cash Box).
 *     It is not an expense: the staff member owes it back.
 *   - A repayment handed back puts money into an account; interest is repaid
 *     first and is the only part that counts as income.
 *   - A payroll deduction moves no cash. It is set on a payroll line and becomes
 *     a repayment when that run is approved; it is undone by reopening or
 *     cancelling the run, never from here.
 *   - Closed days are locked, and money cannot be dated in the future.
 *
 * ?staffId=<id> opens the page filtered to one staff member (the Staff page links here).
 */

import Link from "next/link"
import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
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
import { HandCoins, Plus, Wallet, Users, CalendarClock, Info, Pencil, Undo2, Ban, Search, Banknote } from "lucide-react"
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
  listStaffLoans, getStaffLoanSummary, listStaffLoanRepayments, createStaffLoan, updateStaffLoan, disburseStaffLoan,
  cancelStaffLoan, reverseStaffLoan, repayStaffLoan, reverseStaffLoanRepayment,
  STAFF_LOAN_TYPES, STAFF_LOAN_METHODS, STAFF_LOAN_REPAY_SOURCES, staffLoanTypeLabel, staffLoanMethodLabel, staffLoanSourceLabel,
  type StaffLoan, type StaffLoanSummary, type StaffLoanRepayment,
} from "@/lib/api/restaurant-payroll"

interface StaffRow { restaurantStaffId: number; firstName: string; lastName: string; role: string; isActive: boolean; basePay: number }

/** The restaurant staff list (the Staff page keeps its own copy of this call). */
async function listRestaurantStaff(): Promise<StaffRow[]> {
  const { farmId } = getUserContext()
  const res = await fetch(farmApiUrl(`/Restaurant/staff?farmId=${encodeURIComponent(farmId ?? "")}`), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

const STATUS_STYLE: Record<string, string> = {
  Draft: "bg-gray-100 text-gray-700 border-gray-200",
  Active: "bg-blue-50 text-blue-700 border-blue-200",
  Paid: "bg-green-50 text-green-700 border-green-200",
  Cancelled: "bg-amber-50 text-amber-700 border-amber-200",
  Reversed: "bg-red-50 text-red-700 border-red-200",
}
const TABS = [
  { value: "OPEN", label: "Open" }, { value: "Active", label: "Active" }, { value: "Draft", label: "Draft" },
  { value: "Paid", label: "Paid" }, { value: "CLOSED", label: "Cancelled / reversed" }, { value: "ALL", label: "All" },
]
const dateOnly = (s?: string | null) => (s ? s.split("T")[0] : "—")
const num = (s: string) => (s.trim() ? parseFloat(s) : 0)

interface LoanForm {
  restaurantStaffId: string; loanType: string; principal: string; interest: string; method: string
  perPayroll: string; expectedEnd: string; reference: string; notes: string
  disburseNow: boolean; cashAccountId: string; disbursementDate: string
}
const blankForm = (staffId = ""): LoanForm => ({
  restaurantStaffId: staffId, loanType: "SalaryAdvance", principal: "", interest: "", method: "PayrollDeduction",
  perPayroll: "", expectedEnd: "", reference: "", notes: "", disburseNow: true, cashAccountId: "", disbursementDate: todayIso(),
})

export default function RestaurantStaffLoansPage() {
  return <Suspense fallback={<PageSkeleton statCards={4} listRows={6} />}><StaffLoansInner /></Suspense>
}

function StaffLoansInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { toast } = useToast()
  const fmt = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canView = permissions.isAdmin || permissions.featureAccess.canViewRestaurantStaff

  const [loading, setLoading] = useState(true)
  const [loans, setLoans] = useState<StaffLoan[]>([])
  const [summary, setSummary] = useState<StaffLoanSummary | null>(null)
  const [staff, setStaff] = useState<StaffRow[]>([])
  const [accounts, setAccounts] = useState<CashAccount[]>([])

  const [tab, setTab] = useState("OPEN")
  const [staffFilter, setStaffFilter] = useState(searchParams.get("staffId") ?? "ALL")
  const [search, setSearch] = useState("")

  const [formOpen, setFormOpen] = useState(false)
  const [editing, setEditing] = useState<StaffLoan | null>(null)
  const [form, setForm] = useState<LoanForm>(blankForm())
  const [saving, setSaving] = useState(false)

  const [detail, setDetail] = useState<StaffLoan | null>(null)
  const [repayments, setRepayments] = useState<StaffLoanRepayment[]>([])

  const [payOut, setPayOut] = useState<StaffLoan | null>(null)
  const [payOutForm, setPayOutForm] = useState({ cashAccountId: "", date: todayIso(), reference: "" })

  const [repayTarget, setRepayTarget] = useState<StaffLoan | null>(null)
  const [repayForm, setRepayForm] = useState({ amount: "", source: "Cash", cashAccountId: "", date: todayIso(), reference: "", notes: "" })

  const [reasonAction, setReasonAction] = useState<null | { kind: "cancel" | "reverse" | "reverseRepayment"; loan?: StaffLoan; repayment?: StaffLoanRepayment }>(null)
  const [reason, setReason] = useState("")

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    try {
      const [ls, s, st, accs] = await Promise.all([listStaffLoans(), getStaffLoanSummary(), listRestaurantStaff(), listCashAccounts()])
      setLoans(ls ?? []); setSummary(s); setStaff(st ?? []); setAccounts((accs ?? []).filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Could not load staff loans", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally { setLoading(false) }
  }, [toast])

  useEffect(() => {
    if (!activeFarmId || !canView) { setLoading(false); return }
    void load()
  }, [activeFarmId, canView, load])

  async function refresh(openId?: number) {
    await load()
    const id = openId ?? detail?.staffLoanId
    if (!id) return
    const fresh = (await listStaffLoans()).find((l) => l.staffLoanId === id) ?? null
    setDetail(fresh)
    if (fresh) setRepayments(await listStaffLoanRepayments(id))
  }

  async function openDetail(l: StaffLoan) {
    setDetail(l); setRepayments([])
    try { setRepayments(await listStaffLoanRepayments(l.staffLoanId)) }
    catch (e: any) { toast({ title: "Could not load repayments", description: e?.message, variant: "destructive" }) }
  }

  // ----- create / edit -----
  const activeStaff = useMemo(() => staff.filter((s) => s.isActive), [staff])
  const staffName = (s: StaffRow) => `${s.firstName} ${s.lastName ?? ""}`.trim()
  const total = num(form.principal) + num(form.interest)
  const byPayroll = form.method === "PayrollDeduction" || form.method === "Mixed"
  const locked = !!editing && editing.status !== "Draft"
  const periods = byPayroll && num(form.perPayroll) > 0 ? Math.ceil(total / num(form.perPayroll)) : 0

  function openCreate() {
    setEditing(null); setForm(blankForm(staffFilter !== "ALL" ? staffFilter : "")); setFormOpen(true)
  }
  function openEdit(l: StaffLoan) {
    setEditing(l)
    setForm({
      restaurantStaffId: String(l.restaurantStaffId), loanType: l.loanType, principal: String(l.principalAmount),
      interest: l.interestAmount ? String(l.interestAmount) : "", method: l.repaymentMethod,
      perPayroll: l.defaultPayrollDeduction ? String(l.defaultPayrollDeduction) : "",
      expectedEnd: l.expectedEndDate ? dateOnly(l.expectedEndDate) : "", reference: l.reference ?? "", notes: l.notes ?? "",
      disburseNow: false, cashAccountId: "", disbursementDate: todayIso(),
    })
    setFormOpen(true)
  }

  async function saveForm() {
    if (!editing && !form.restaurantStaffId) { toast({ title: "Choose the staff member", variant: "destructive" }); return }
    if (!(num(form.principal) > 0)) { toast({ title: "Enter the amount given", variant: "destructive" }); return }
    if (byPayroll && !(num(form.perPayroll) > 0)) { toast({ title: "Set how much to deduct from each payroll", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) {
        await updateStaffLoan(editing.staffLoanId, {
          loanType: form.loanType, principalAmount: num(form.principal), interestAmount: num(form.interest),
          repaymentMethod: form.method, defaultPayrollDeduction: num(form.perPayroll),
          expectedEndDate: form.expectedEnd || null, reference: form.reference || null, notes: form.notes || null,
        })
        toast({ title: "Loan updated" })
        setFormOpen(false); await refresh(editing.staffLoanId)
      } else {
        await createStaffLoan({
          restaurantStaffId: Number(form.restaurantStaffId), loanType: form.loanType, principalAmount: num(form.principal),
          interestAmount: num(form.interest), repaymentMethod: form.method, defaultPayrollDeduction: num(form.perPayroll),
          expectedEndDate: form.expectedEnd || null, reference: form.reference || null, notes: form.notes || null,
          disburseNow: form.disburseNow, cashAccountId: form.cashAccountId ? Number(form.cashAccountId) : null,
          disbursementDate: form.disburseNow ? form.disbursementDate : null,
        })
        toast({ title: form.disburseNow ? "Advance paid out" : "Saved as a draft — pay it out when the money is handed over" })
        setFormOpen(false); await load()
      }
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  async function savePayOut() {
    if (!payOut) return
    setSaving(true)
    try {
      await disburseStaffLoan(payOut.staffLoanId, {
        cashAccountId: payOutForm.cashAccountId ? Number(payOutForm.cashAccountId) : null,
        disbursementDate: payOutForm.date, reference: payOutForm.reference || null,
      })
      toast({ title: `${fmt(payOut.principalAmount)} paid out to ${payOut.staffName ?? "staff"}` })
      const id = payOut.staffLoanId; setPayOut(null); await refresh(detail ? id : undefined)
    } catch (e: any) { toast({ title: "Could not pay out", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function saveRepay() {
    if (!repayTarget) return
    const amt = num(repayForm.amount)
    if (!(amt > 0)) { toast({ title: "Enter the amount repaid", variant: "destructive" }); return }
    if (amt > repayTarget.outstandingBalance) { toast({ title: `That is more than the ${fmt(repayTarget.outstandingBalance)} still owed`, variant: "destructive" }); return }
    setSaving(true)
    try {
      await repayStaffLoan(repayTarget.staffLoanId, {
        amount: amt, sourceType: repayForm.source, cashAccountId: repayForm.cashAccountId ? Number(repayForm.cashAccountId) : null,
        repaymentDate: repayForm.date, reference: repayForm.reference || null, notes: repayForm.notes || null,
      })
      toast({ title: "Repayment recorded" })
      const id = repayTarget.staffLoanId; setRepayTarget(null); await refresh(detail ? id : undefined)
    } catch (e: any) { toast({ title: "Could not record repayment", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function submitReason() {
    if (!reasonAction) return
    if (reasonAction.kind !== "cancel" && !reason.trim()) { toast({ title: "Give a reason", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (reasonAction.kind === "cancel" && reasonAction.loan) await cancelStaffLoan(reasonAction.loan.staffLoanId, reason)
      if (reasonAction.kind === "reverse" && reasonAction.loan) await reverseStaffLoan(reasonAction.loan.staffLoanId, reason)
      if (reasonAction.kind === "reverseRepayment" && reasonAction.repayment) await reverseStaffLoanRepayment(reasonAction.repayment.repaymentId, reason)
      toast({ title: reasonAction.kind === "cancel" ? "Loan cancelled" : "Reversed" })
      const id = reasonAction.loan?.staffLoanId ?? reasonAction.repayment?.staffLoanId
      setReasonAction(null); setReason(""); await refresh(id)
    } catch (e: any) { toast({ title: "Could not do that", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  // ----- filtering -----
  const staffWithLoans = useMemo(() => {
    const m = new Map<number, string>()
    for (const l of loans) m.set(l.restaurantStaffId, l.staffName ?? `Staff #${l.restaurantStaffId}`)
    return Array.from(m.entries()).sort((a, b) => a[1].localeCompare(b[1]))
  }, [loans])

  const filtered = useMemo(() => {
    let list = loans
    if (tab === "OPEN") list = list.filter((l) => l.status === "Draft" || l.status === "Active")
    else if (tab === "CLOSED") list = list.filter((l) => l.status === "Cancelled" || l.status === "Reversed")
    else if (tab !== "ALL") list = list.filter((l) => l.status === tab)
    if (staffFilter !== "ALL") list = list.filter((l) => String(l.restaurantStaffId) === staffFilter)
    const q = search.trim().toLowerCase()
    if (q) list = list.filter((l) => (l.staffName ?? "").toLowerCase().includes(q) || l.loanNumber.toLowerCase().includes(q) || (l.reference ?? "").toLowerCase().includes(q))
    return list
  }, [loans, tab, staffFilter, search])

  const accountSelect = (value: string, onChange: (v: string) => void, placeholder: string) => (
    <Select value={value || "DEFAULT"} onValueChange={(v) => onChange(v === "DEFAULT" ? "" : v)}>
      <SelectTrigger><SelectValue placeholder={placeholder} /></SelectTrigger>
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
    <Card><CardContent className="py-12 text-center text-gray-600">You do not have access to staff loans. Ask an admin for the Staff &amp; payroll permission.</CardContent></Card>
  )

  return shell(<>
    <PageHeader icon={HandCoins} title="Staff Loans & Advances" subtitle="Money lent to staff, and how it is being paid back">
      <div className="flex gap-2">
        <Button variant="outline" asChild><Link href="/restaurant-payroll"><Banknote className="h-4 w-4 mr-1" />Payroll</Link></Button>
        <Button className="bg-rose-600 hover:bg-rose-700" onClick={openCreate}><Plus className="h-4 w-4 mr-1" />New advance</Button>
      </div>
    </PageHeader>

    <div className="flex gap-2 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900">
      <Info className="h-4 w-4 mt-0.5 shrink-0" />
      <p>
        An advance is <strong>not an expense</strong> — the staff member owes it back. Paying it out takes the amount from a cash account;
        money handed back puts it in again. Deductions set on a payroll line are repaid when that payroll is <strong>approved</strong>,
        and the P&amp;L still shows the full wage. This is separate from <Link href="/restaurant-loans" className="underline">Loans</Link>,
        which is money the restaurant borrowed.
      </p>
    </div>

    {summary && (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label={`Owed by staff · ${summary.activeCount} active`} value={fmt(summary.totalOutstanding)} icon={Wallet} color="red" />
        <StatCard label={`Given out · ${summary.draftCount} draft`} value={fmt(summary.totalDisbursed)} icon={HandCoins} color="rose" />
        <StatCard label={`Repaid · ${fmt(summary.repaidViaPayroll)} via payroll`} value={fmt(summary.totalRepaid)} icon={Users} color="green" />
        <StatCard label="Set aside on draft payroll" value={fmt(summary.draftPayrollClaims)} icon={CalendarClock} color="amber" />
      </div>
    )}

    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {TABS.map((t) => (
          <Button key={t.value} size="sm" variant={tab === t.value ? "default" : "outline"}
            className={tab === t.value ? "bg-rose-600 hover:bg-rose-700" : ""} onClick={() => setTab(t.value)}>{t.label}</Button>
        ))}
      </div>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <div className="relative">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-gray-400" />
          <Input className="pl-8" placeholder="Search staff, loan no., reference…" value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>
        <Select value={staffFilter} onValueChange={setStaffFilter}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">All staff</SelectItem>
            {staffWithLoans.map(([id, name]) => <SelectItem key={id} value={String(id)}>{name}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
    </div>

    {filtered.length === 0 ? (
      <EmptyState icon={HandCoins} title={loans.length === 0 ? "No staff loans or advances yet" : "Nothing matches these filters"}
        description="Give a staff member an advance and set how much comes off each payroll."
        actionLabel="New advance" onAction={openCreate} />
    ) : (
      <Card><CardContent className="p-0"><div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[820px]">
          <thead><tr className="border-b bg-gray-50 text-gray-600">
            <th className="text-left p-3">Loan</th><th className="text-left p-3">Staff</th><th className="text-left p-3">Type</th>
            <th className="text-right p-3">Given</th><th className="text-right p-3">Owed</th><th className="text-left p-3">Repayment</th>
            <th className="text-center p-3">Status</th><th className="text-right p-3"></th>
          </tr></thead>
          <tbody>
            {filtered.map((l) => (
              <tr key={l.staffLoanId} className="border-b hover:bg-gray-50 cursor-pointer" onClick={() => openDetail(l)}>
                <td className="p-3"><div className="font-mono text-xs font-semibold">{l.loanNumber}</div><div className="text-xs text-gray-500">{dateOnly(l.disbursementDate ?? l.createdAt)}</div></td>
                <td className="p-3"><div className="font-medium">{l.staffName ?? "—"}</div>{!l.staffIsActive && <div className="text-xs text-amber-600">inactive / removed</div>}</td>
                <td className="p-3">{staffLoanTypeLabel(l.loanType)}</td>
                <td className="p-3 text-right tabular-nums">{fmt(l.principalAmount)}{l.interestAmount > 0 && <div className="text-xs text-gray-500">+{fmt(l.interestAmount)} interest</div>}</td>
                <td className="p-3 text-right tabular-nums">
                  <span className={l.status === "Active" ? "text-red-600 font-semibold" : "text-gray-500"}>{l.status === "Active" || l.status === "Paid" ? fmt(l.outstandingBalance) : "—"}</span>
                  {l.draftPayrollClaims > 0 && <div className="text-xs text-amber-600">{fmt(l.draftPayrollClaims)} on draft payroll</div>}
                </td>
                <td className="p-3 text-xs">{staffLoanMethodLabel(l.repaymentMethod)}{l.defaultPayrollDeduction > 0 && <div className="text-gray-500">{fmt(l.defaultPayrollDeduction)} per payroll</div>}</td>
                <td className="p-3 text-center"><Badge variant="outline" className={`text-xs ${STATUS_STYLE[l.status] ?? ""}`}>{l.status}</Badge></td>
                <td className="p-3 text-right whitespace-nowrap" onClick={(e) => e.stopPropagation()}>
                  {l.status === "Draft" && <Button size="sm" variant="outline" onClick={() => { setPayOut(l); setPayOutForm({ cashAccountId: "", date: todayIso(), reference: l.reference ?? "" }) }}><HandCoins className="h-4 w-4 mr-1" />Pay out</Button>}
                  {l.status === "Active" && <Button size="sm" variant="outline" onClick={() => { setRepayTarget(l); setRepayForm({ amount: "", source: "Cash", cashAccountId: "", date: todayIso(), reference: "", notes: "" }) }}><Wallet className="h-4 w-4 mr-1" />Repay</Button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div></CardContent></Card>
    )}

    {/* ===== create / edit ===== */}
    <Dialog open={formOpen} onOpenChange={setFormOpen}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{editing ? `Edit ${editing.loanNumber}` : "New loan or advance"}</DialogTitle>
          <DialogDescription>{editing ? (locked ? "Money has moved, so only the repayment plan and notes can change." : "Still a draft: anything can change.") : "Who is borrowing, how much, and how they will pay it back."}</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1 sm:col-span-2"><Label>Staff member *</Label>
            <Select value={form.restaurantStaffId} onValueChange={(v) => setForm({ ...form, restaurantStaffId: v })} disabled={!!editing}>
              <SelectTrigger><SelectValue placeholder="Choose staff" /></SelectTrigger>
              <SelectContent>{(editing ? staff : activeStaff).map((s) => <SelectItem key={s.restaurantStaffId} value={String(s.restaurantStaffId)}>{staffName(s)} — {s.role}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="space-y-1"><Label>Type</Label>
            <Select value={form.loanType} onValueChange={(v) => setForm({ ...form, loanType: v })} disabled={locked}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{STAFF_LOAN_TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="space-y-1"><Label>Amount given *</Label><Input type="number" min="0" step="0.01" value={form.principal} disabled={locked} onChange={(e) => setForm({ ...form, principal: e.target.value })} /></div>
          <div className="space-y-1"><Label>Interest (flat amount)</Label><Input type="number" min="0" step="0.01" value={form.interest} disabled={locked} onChange={(e) => setForm({ ...form, interest: e.target.value })} /></div>
          <div className="space-y-1"><Label>Total to repay</Label><div className="h-10 flex items-center font-semibold tabular-nums">{fmt(total)}</div></div>
          <div className="space-y-1"><Label>Repayment method</Label>
            <Select value={form.method} onValueChange={(v) => setForm({ ...form, method: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{STAFF_LOAN_METHODS.map((m) => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="space-y-1"><Label>Deduct per payroll{byPayroll ? " *" : ""}</Label><Input type="number" min="0" step="0.01" value={form.perPayroll} onChange={(e) => setForm({ ...form, perPayroll: e.target.value })} /></div>
          <div className="space-y-1"><Label>Expected to finish</Label><Input type="date" value={form.expectedEnd} onChange={(e) => setForm({ ...form, expectedEnd: e.target.value })} /></div>
          <div className="space-y-1"><Label>Reference</Label><Input value={form.reference} onChange={(e) => setForm({ ...form, reference: e.target.value })} /></div>
          {periods > 0 && <p className="text-xs text-gray-500 sm:col-span-2">Cleared in about {periods} payroll run{periods === 1 ? "" : "s"}. Payroll will suggest this deduction automatically.</p>}
          <div className="space-y-1 sm:col-span-2"><Label>Notes</Label><Textarea rows={2} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>
          {!editing && (
            <div className="sm:col-span-2 rounded-lg border p-3 space-y-3">
              <label className="flex items-center gap-2 text-sm font-medium">
                <input type="checkbox" checked={form.disburseNow} onChange={(e) => setForm({ ...form, disburseNow: e.target.checked })} /> Pay the money out now
              </label>
              {form.disburseNow ? (
                <div className="grid gap-3 sm:grid-cols-2">
                  <div className="space-y-1"><Label>Paid from</Label>{accountSelect(form.cashAccountId, (v) => setForm({ ...form, cashAccountId: v }), "Main Cash Box (default)")}</div>
                  <div className="space-y-1"><Label>Date paid</Label><Input type="date" max={todayIso()} value={form.disbursementDate} onChange={(e) => setForm({ ...form, disbursementDate: e.target.value })} /></div>
                </div>
              ) : <p className="text-xs text-gray-500">Saved as a draft; nothing moves until you pay it out.</p>}
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setFormOpen(false)}>Cancel</Button>
          <Button className="bg-rose-600 hover:bg-rose-700" disabled={saving} onClick={saveForm}>
            {editing ? "Save changes" : form.disburseNow ? `Give ${fmt(num(form.principal))}` : "Save draft"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    {/* ===== detail ===== */}
    <Dialog open={!!detail} onOpenChange={(v) => { if (!v) setDetail(null) }}>
      <DialogContent className="sm:max-w-3xl max-h-[90vh] overflow-y-auto">
        {detail && <>
          <DialogHeader>
            <DialogTitle className="flex flex-wrap items-center gap-2">{detail.loanNumber} · {detail.staffName}
              <Badge variant="outline" className={`text-xs ${STATUS_STYLE[detail.status] ?? ""}`}>{detail.status}</Badge></DialogTitle>
            <DialogDescription>{staffLoanTypeLabel(detail.loanType)} · {staffLoanMethodLabel(detail.repaymentMethod)}{detail.defaultPayrollDeduction > 0 ? ` · ${fmt(detail.defaultPayrollDeduction)} per payroll` : ""}</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {[["Given", fmt(detail.principalAmount), ""], ["To repay", fmt(detail.totalRepayable), ""],
              ["Repaid", fmt(detail.totalPrincipalRepaid + detail.totalInterestRepaid), "text-green-600"],
              ["Owed", detail.status === "Active" || detail.status === "Paid" ? fmt(detail.outstandingBalance) : "—", "text-red-600"]].map(([l, v, c]) => (
              <div key={l} className="rounded-lg border p-3"><div className="text-xs text-gray-500">{l}</div><div className={`text-lg font-bold tabular-nums ${c}`}>{v}</div></div>
            ))}
          </div>
          <div className="grid gap-1 text-sm sm:grid-cols-2">
            <div><span className="text-gray-500">Paid out:</span> {detail.disbursementDate ? `${dateOnly(detail.disbursementDate)} from ${detail.cashAccountName ?? "—"}` : "not yet"}</div>
            <div><span className="text-gray-500">Expected to finish:</span> {dateOnly(detail.expectedEndDate)}</div>
            {detail.draftPayrollClaims > 0 && <div className="text-amber-700">{fmt(detail.draftPayrollClaims)} set to be deducted on a draft payroll</div>}
            {detail.notes && <div className="sm:col-span-2"><span className="text-gray-500">Notes:</span> {detail.notes}</div>}
            {detail.closedReason && <div className="sm:col-span-2 text-red-700">{detail.status}: {detail.closedReason}</div>}
          </div>
          <div className="flex flex-wrap gap-2">
            {detail.status === "Draft" && <>
              <Button size="sm" className="bg-rose-600 hover:bg-rose-700" onClick={() => { setPayOut(detail); setPayOutForm({ cashAccountId: "", date: todayIso(), reference: detail.reference ?? "" }) }}><HandCoins className="h-4 w-4 mr-1" />Pay out</Button>
              <Button size="sm" variant="outline" onClick={() => openEdit(detail)}><Pencil className="h-4 w-4 mr-1" />Edit</Button>
              <Button size="sm" variant="outline" className="text-amber-700" onClick={() => setReasonAction({ kind: "cancel", loan: detail })}><Ban className="h-4 w-4 mr-1" />Cancel</Button>
            </>}
            {(detail.status === "Active" || detail.status === "Paid") && <>
              {detail.status === "Active" && <Button size="sm" className="bg-rose-600 hover:bg-rose-700" onClick={() => { setRepayTarget(detail); setRepayForm({ amount: "", source: "Cash", cashAccountId: "", date: todayIso(), reference: "", notes: "" }) }}><Wallet className="h-4 w-4 mr-1" />Record repayment</Button>}
              <Button size="sm" variant="outline" onClick={() => openEdit(detail)}><Pencil className="h-4 w-4 mr-1" />Edit plan</Button>
              <Button size="sm" variant="outline" className="text-red-700" onClick={() => setReasonAction({ kind: "reverse", loan: detail })}><Undo2 className="h-4 w-4 mr-1" />Reverse loan</Button>
            </>}
          </div>
          <div>
            <h3 className="text-sm font-semibold mb-2">Repayments</h3>
            {repayments.length === 0 ? <p className="text-sm text-gray-500">No repayments yet.</p> : (
              <div className="overflow-x-auto rounded-lg border"><table className="w-full text-sm min-w-[600px]">
                <thead><tr className="border-b bg-gray-50 text-gray-600"><th className="text-left p-2">Date</th><th className="text-left p-2">How</th><th className="text-right p-2">Amount</th><th className="text-right p-2">Owed after</th><th className="text-center p-2">Status</th><th className="p-2"></th></tr></thead>
                <tbody>{repayments.map((rp) => (
                  <tr key={rp.repaymentId} className={`border-b ${rp.status === "Reversed" ? "opacity-60" : ""}`}>
                    <td className="p-2">{dateOnly(rp.repaymentDate)}</td>
                    <td className="p-2">{staffLoanSourceLabel(rp.sourceType)}<div className="text-xs text-gray-500">{rp.sourceType === "Payroll" ? `${rp.payrollRunNumber ?? "payroll"} · no cash moved` : `into ${rp.cashAccountName ?? "—"}`}</div></td>
                    <td className="p-2 text-right tabular-nums">{fmt(rp.amount)}{rp.interestAmount > 0 && <div className="text-xs text-gray-500">{fmt(rp.interestAmount)} interest</div>}</td>
                    <td className="p-2 text-right tabular-nums">{fmt(rp.balanceAfter)}</td>
                    <td className="p-2 text-center"><Badge variant="outline" className={`text-xs ${rp.status === "Posted" ? "bg-green-50 text-green-700 border-green-200" : "bg-red-50 text-red-700 border-red-200"}`}>{rp.status}</Badge>{rp.reversedReason && <div className="text-xs text-gray-500 mt-1">{rp.reversedReason}</div>}</td>
                    <td className="p-2 text-right">{rp.status === "Posted" && rp.sourceType !== "Payroll" && <Button size="sm" variant="ghost" title="Reverse this repayment" onClick={() => setReasonAction({ kind: "reverseRepayment", repayment: rp })}><Undo2 className="h-3.5 w-3.5" /></Button>}</td>
                  </tr>))}
                </tbody></table></div>
            )}
            <p className="text-xs text-gray-500 mt-2">A payroll repayment is undone by reopening or cancelling its payroll run, so the payroll and the loan always agree.</p>
          </div>
        </>}
      </DialogContent>
    </Dialog>

    {/* ===== pay out ===== */}
    <Dialog open={!!payOut} onOpenChange={(v) => { if (!v) setPayOut(null) }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader><DialogTitle>Pay out {payOut?.loanNumber}</DialogTitle>
          <DialogDescription>{payOut ? `${fmt(payOut.principalAmount)} to ${payOut.staffName}. ` : ""}The amount leaves the account you choose.</DialogDescription></DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1"><Label>Paid from</Label>{accountSelect(payOutForm.cashAccountId, (v) => setPayOutForm({ ...payOutForm, cashAccountId: v }), "Main Cash Box (default)")}</div>
          <div className="space-y-1"><Label>Date paid</Label><Input type="date" max={todayIso()} value={payOutForm.date} onChange={(e) => setPayOutForm({ ...payOutForm, date: e.target.value })} /></div>
          <div className="space-y-1"><Label>Reference</Label><Input value={payOutForm.reference} onChange={(e) => setPayOutForm({ ...payOutForm, reference: e.target.value })} /></div>
        </div>
        <DialogFooter><Button variant="outline" onClick={() => setPayOut(null)}>Back</Button><Button className="bg-rose-600 hover:bg-rose-700" disabled={saving} onClick={savePayOut}>Pay out</Button></DialogFooter>
      </DialogContent>
    </Dialog>

    {/* ===== repay ===== */}
    <Dialog open={!!repayTarget} onOpenChange={(v) => { if (!v) setRepayTarget(null) }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader><DialogTitle>Record a repayment</DialogTitle>
          <DialogDescription>{repayTarget ? `${repayTarget.staffName} · ${repayTarget.loanNumber} · owes ${fmt(repayTarget.outstandingBalance)}. ` : ""}For money handed back directly; payroll deductions are set on the payroll run.</DialogDescription></DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1"><Label>Amount *</Label>
            <div className="flex gap-2"><Input type="number" min="0" step="0.01" value={repayForm.amount} onChange={(e) => setRepayForm({ ...repayForm, amount: e.target.value })} />
              {repayTarget && <Button type="button" variant="outline" size="sm" onClick={() => setRepayForm({ ...repayForm, amount: String(repayTarget.outstandingBalance) })}>All</Button>}</div></div>
          <div className="space-y-1"><Label>Paid by</Label>
            <Select value={repayForm.source} onValueChange={(v) => setRepayForm({ ...repayForm, source: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{STAFF_LOAN_REPAY_SOURCES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
            </Select></div>
          <div className="space-y-1"><Label>Paid into</Label>{accountSelect(repayForm.cashAccountId, (v) => setRepayForm({ ...repayForm, cashAccountId: v }), "The default account for that method")}</div>
          <div className="space-y-1"><Label>Date</Label><Input type="date" max={todayIso()} value={repayForm.date} onChange={(e) => setRepayForm({ ...repayForm, date: e.target.value })} /></div>
          <div className="space-y-1"><Label>Reference</Label><Input value={repayForm.reference} onChange={(e) => setRepayForm({ ...repayForm, reference: e.target.value })} /></div>
        </div>
        <DialogFooter><Button variant="outline" onClick={() => setRepayTarget(null)}>Back</Button><Button className="bg-rose-600 hover:bg-rose-700" disabled={saving} onClick={saveRepay}>Record</Button></DialogFooter>
      </DialogContent>
    </Dialog>

    {/* ===== reason (cancel / reverse) ===== */}
    <Dialog open={!!reasonAction} onOpenChange={(v) => { if (!v) { setReasonAction(null); setReason("") } }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{reasonAction?.kind === "cancel" ? `Cancel ${reasonAction.loan?.loanNumber}?` : reasonAction?.kind === "reverse" ? `Reverse ${reasonAction.loan?.loanNumber}?` : "Reverse this repayment?"}</DialogTitle>
          <DialogDescription>
            {reasonAction?.kind === "cancel" && "The draft is closed. No money has moved."}
            {reasonAction?.kind === "reverse" && reasonAction.loan && `${fmt(reasonAction.loan.principalAmount)} goes back into ${reasonAction.loan.cashAccountName ?? "the account it came from"}, dated today. Any repayments must be reversed first.`}
            {reasonAction?.kind === "reverseRepayment" && reasonAction.repayment && `${fmt(reasonAction.repayment.amount)} goes back out of ${reasonAction.repayment.cashAccountName ?? "its account"}, dated today, and is owed again.`}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-1"><Label>Reason{reasonAction?.kind === "cancel" ? " (optional)" : " *"}</Label><Textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></div>
        <DialogFooter><Button variant="outline" onClick={() => { setReasonAction(null); setReason("") }}>Back</Button><Button variant="destructive" disabled={saving} onClick={submitReason}>Confirm</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </>)
}

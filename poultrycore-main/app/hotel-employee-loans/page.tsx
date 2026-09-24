"use client"

/**
 * Hotel — Staff Loans & Advances.
 *
 * The money rules (enforced in the database, migration 325):
 *   - Giving an advance moves the PRINCIPAL out of a cash account. It is not an
 *     expense: the staff member owes it back.
 *   - A cash / MoMo / bank repayment moves money back in. Interest is repaid
 *     first and is the only part that counts as income.
 *   - A payroll deduction moves no cash. It is set on the payroll line, and
 *     approving the payroll run turns it into a repayment. Payroll repayments
 *     are reversed by reopening or cancelling that run, never from here.
 *
 * ?staffId=<id> opens the page filtered to one staff member (the Staff page
 * links here from its "Owes" column).
 */

import Link from "next/link"
import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  Loader2, Plus, HandCoins, RotateCcw, XCircle, Coins, Pencil, Wallet, Banknote, Info, Search,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelEmployeeLoans, createHotelEmployeeLoan, updateHotelEmployeeLoan, disburseHotelEmployeeLoan,
  cancelHotelEmployeeLoan, reverseHotelEmployeeLoan, getHotelEmployeeLoanSummary,
  listHotelEmployeeLoanRepayments, recordHotelEmployeeLoanRepayment, reverseHotelEmployeeLoanRepayment,
  HOTEL_LOAN_TYPES, HOTEL_LOAN_REPAYMENT_METHODS, HOTEL_LOAN_REPAYMENT_SOURCES,
  hotelLoanTypeLabel, hotelLoanMethodLabel, hotelLoanSourceLabel,
  type HotelEmployeeLoan, type HotelEmployeeLoanSummary, type HotelEmployeeLoanRepayment,
} from "@/lib/api/hotel-employee-loans"
import { listHotelCashAccounts, listHotelStaff, type HotelCashAccount } from "@/lib/api/hotel"
import { businessDatePart, formatDateKey } from "@/lib/utils/company-datetime"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Active: "bg-blue-100 text-blue-700",
  Paid: "bg-emerald-100 text-emerald-700",
  Cancelled: "bg-amber-100 text-amber-700",
  Reversed: "bg-red-100 text-red-700",
  WrittenOff: "bg-purple-100 text-purple-700",
}

const STATUS_TABS = [
  { value: "OPEN", label: "Open" },        // Draft + Active
  { value: "Active", label: "Active" },
  { value: "Draft", label: "Draft" },
  { value: "Paid", label: "Paid" },
  { value: "CLOSED", label: "Cancelled / reversed" },
  { value: "ALL", label: "All" },
]

function todayLocal(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

const fmt = (n: number | null | undefined) =>
  (n ?? 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const fmtDate = (s?: string | null) => (s ? formatDateKey(businessDatePart(s)) || "—" : "—")

const staffIdOf = (s: any): number => s.hotelStaffId ?? s.hotelstaffid
const staffNameOf = (s: any): string => `${s.firstName ?? s.firstname ?? ""} ${s.lastName ?? s.lastname ?? ""}`.trim()
const staffActive = (s: any): boolean => (s.isActive ?? s.isactive) !== false

interface LoanForm {
  hotelStaffId: number
  loanType: string
  principalAmount: number
  interestAmount: number
  repaymentMethod: string
  defaultPayrollDeduction: number
  expectedEndDate: string
  reference: string
  notes: string
  disburseNow: boolean
  hotelCashAccountId: number | null
  disbursementDate: string
}

const EMPTY_FORM: LoanForm = {
  hotelStaffId: 0, loanType: "SalaryAdvance", principalAmount: 0, interestAmount: 0,
  repaymentMethod: "PayrollDeduction", defaultPayrollDeduction: 0, expectedEndDate: "",
  reference: "", notes: "", disburseNow: true, hotelCashAccountId: null, disbursementDate: todayLocal(),
}

export default function HotelEmployeeLoansPage() {
  return (
    <Suspense fallback={null}>
      <HotelEmployeeLoansInner />
    </Suspense>
  )
}

function HotelEmployeeLoansInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loans, setLoans] = useState<HotelEmployeeLoan[]>([])
  const [summary, setSummary] = useState<HotelEmployeeLoanSummary | null>(null)
  const [staff, setStaff] = useState<any[]>([])
  const [accounts, setAccounts] = useState<HotelCashAccount[]>([])
  const [loading, setLoading] = useState(true)

  const [statusTab, setStatusTab] = useState("OPEN")
  const [staffFilter, setStaffFilter] = useState<string>(searchParams.get("staffId") ?? "ALL")
  const [typeFilter, setTypeFilter] = useState("ALL")
  const [search, setSearch] = useState("")

  // Create / edit
  const [formOpen, setFormOpen] = useState(false)
  const [editing, setEditing] = useState<HotelEmployeeLoan | null>(null)
  const [form, setForm] = useState<LoanForm>(EMPTY_FORM)
  const [saving, setSaving] = useState(false)

  // Detail
  const [detail, setDetail] = useState<HotelEmployeeLoan | null>(null)
  const [repayments, setRepayments] = useState<HotelEmployeeLoanRepayment[]>([])
  const [repLoading, setRepLoading] = useState(false)

  // Disburse
  const [disburseLoan, setDisburseLoan] = useState<HotelEmployeeLoan | null>(null)
  const [disburseForm, setDisburseForm] = useState({ hotelCashAccountId: null as number | null, disbursementDate: todayLocal(), reference: "" })

  // Repay
  const [repayLoan, setRepayLoan] = useState<HotelEmployeeLoan | null>(null)
  const [repayForm, setRepayForm] = useState({ amount: 0, sourceType: "Cash", hotelCashAccountId: null as number | null, repaymentDate: todayLocal(), reference: "", notes: "" })

  // Reason prompts
  const [cancelTarget, setCancelTarget] = useState<HotelEmployeeLoan | null>(null)
  const [reverseTarget, setReverseTarget] = useState<HotelEmployeeLoan | null>(null)
  const [reverseRepTarget, setReverseRepTarget] = useState<HotelEmployeeLoanRepayment | null>(null)

  const activeAccounts = useMemo(() => accounts.filter((a) => a.isActive !== false), [accounts])
  const activeStaff = useMemo(() => staff.filter(staffActive), [staff])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [ls, s, st, accs] = await Promise.all([
        listHotelEmployeeLoans(), getHotelEmployeeLoanSummary(), listHotelStaff(), listHotelCashAccounts(),
      ])
      setLoans(ls); setSummary(s); setStaff(st); setAccounts(accs)
    } catch (e: any) {
      toast({ title: "Failed to load loans", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }, [toast])

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router, load])

  // Keep the open detail in step with the list after any change.
  async function refresh(openLoanId?: number) {
    await load()
    const id = openLoanId ?? detail?.hotelEmployeeLoanId
    if (id) {
      const fresh = (await listHotelEmployeeLoans()).find((l) => l.hotelEmployeeLoanId === id) ?? null
      setDetail(fresh)
      if (fresh) setRepayments(await listHotelEmployeeLoanRepayments(id))
    }
  }

  async function openDetail(l: HotelEmployeeLoan) {
    setDetail(l); setRepayments([]); setRepLoading(true)
    try { setRepayments(await listHotelEmployeeLoanRepayments(l.hotelEmployeeLoanId)) }
    catch (e: any) { toast({ title: "Failed to load repayments", description: e?.message, variant: "destructive" }) }
    finally { setRepLoading(false) }
  }

  // ----- Create / edit -----
  function openCreate() {
    const pre = staffFilter !== "ALL" ? Number(staffFilter) : 0
    setEditing(null)
    setForm({ ...EMPTY_FORM, hotelStaffId: pre, disbursementDate: todayLocal(), hotelCashAccountId: activeAccounts.length === 1 ? activeAccounts[0].hotelCashAccountId : null })
    setFormOpen(true)
  }

  function openEdit(l: HotelEmployeeLoan) {
    setEditing(l)
    setForm({
      hotelStaffId: l.hotelStaffId, loanType: l.loanType, principalAmount: l.principalAmount, interestAmount: l.interestAmount,
      repaymentMethod: l.repaymentMethod, defaultPayrollDeduction: l.defaultPayrollDeduction,
      expectedEndDate: businessDatePart(l.expectedEndDate), reference: l.reference ?? "", notes: l.notes ?? "",
      disburseNow: false, hotelCashAccountId: null, disbursementDate: todayLocal(),
    })
    setFormOpen(true)
  }

  const formTotal = (form.principalAmount || 0) + (form.interestAmount || 0)
  const byPayroll = form.repaymentMethod === "PayrollDeduction" || form.repaymentMethod === "Mixed"
  const payrollsToClear = byPayroll && form.defaultPayrollDeduction > 0 ? Math.ceil(formTotal / form.defaultPayrollDeduction) : 0
  const moneyLocked = !!editing && editing.status !== "Draft"

  async function saveForm() {
    if (!editing && !form.hotelStaffId) { toast({ title: "Choose the staff member", variant: "destructive" }); return }
    if (form.principalAmount <= 0) { toast({ title: "Enter the amount given", variant: "destructive" }); return }
    if (byPayroll && form.defaultPayrollDeduction <= 0) { toast({ title: "Set how much to deduct from each payroll", variant: "destructive" }); return }
    if (!editing && form.disburseNow && !form.hotelCashAccountId) { toast({ title: "Choose the cash account the money is paid from", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) {
        await updateHotelEmployeeLoan(editing.hotelEmployeeLoanId, {
          loanType: form.loanType, principalAmount: form.principalAmount, interestAmount: form.interestAmount,
          repaymentMethod: form.repaymentMethod, defaultPayrollDeduction: form.defaultPayrollDeduction,
          expectedEndDate: form.expectedEndDate || null, reference: form.reference || null, notes: form.notes || null,
        })
        toast({ title: "Loan updated" })
        setFormOpen(false)
        await refresh(editing.hotelEmployeeLoanId)
      } else {
        const s = staff.find((x) => staffIdOf(x) === form.hotelStaffId)
        await createHotelEmployeeLoan({
          ...form,
          staffName: s ? staffNameOf(s) : undefined,
          expectedEndDate: form.expectedEndDate || null,
          reference: form.reference || null,
          notes: form.notes || null,
          hotelCashAccountId: form.disburseNow ? form.hotelCashAccountId : null,
          disbursementDate: form.disburseNow ? form.disbursementDate : null,
        })
        toast({ title: form.disburseNow ? "Advance given and paid out" : "Loan saved as a draft — disburse it when the money is handed over" })
        setFormOpen(false)
        await load()
      }
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  // ----- Disburse -----
  function openDisburse(l: HotelEmployeeLoan) {
    setDisburseLoan(l)
    setDisburseForm({ hotelCashAccountId: activeAccounts.length === 1 ? activeAccounts[0].hotelCashAccountId : null, disbursementDate: todayLocal(), reference: l.reference ?? "" })
  }
  async function saveDisburse() {
    if (!disburseLoan) return
    if (!disburseForm.hotelCashAccountId) { toast({ title: "Choose the cash account the money is paid from", variant: "destructive" }); return }
    setSaving(true)
    try {
      await disburseHotelEmployeeLoan(disburseLoan.hotelEmployeeLoanId, disburseForm.hotelCashAccountId, disburseForm.disbursementDate, disburseForm.reference || null)
      toast({ title: `${fmt(disburseLoan.principalAmount)} paid out to ${disburseLoan.staffName ?? "staff"}` })
      const id = disburseLoan.hotelEmployeeLoanId
      setDisburseLoan(null)
      await refresh(detail ? id : undefined)
    } catch (e: any) {
      toast({ title: "Could not disburse", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  // ----- Repay -----
  function openRepay(l: HotelEmployeeLoan) {
    setRepayLoan(l)
    setRepayForm({ amount: 0, sourceType: "Cash", hotelCashAccountId: l.hotelCashAccountId ?? (activeAccounts.length === 1 ? activeAccounts[0].hotelCashAccountId : null), repaymentDate: todayLocal(), reference: "", notes: "" })
  }
  async function saveRepay() {
    if (!repayLoan) return
    if (repayForm.amount <= 0) { toast({ title: "Enter the amount repaid", variant: "destructive" }); return }
    if (repayForm.amount > repayLoan.outstandingBalance) { toast({ title: `That is more than the ${fmt(repayLoan.outstandingBalance)} still owed`, variant: "destructive" }); return }
    if (!repayForm.hotelCashAccountId) { toast({ title: "Choose the account the money went into", variant: "destructive" }); return }
    setSaving(true)
    try {
      await recordHotelEmployeeLoanRepayment({
        hotelEmployeeLoanId: repayLoan.hotelEmployeeLoanId, amount: repayForm.amount, sourceType: repayForm.sourceType,
        hotelCashAccountId: repayForm.hotelCashAccountId, repaymentDate: repayForm.repaymentDate,
        reference: repayForm.reference || null, notes: repayForm.notes || null,
      })
      toast({ title: "Repayment recorded" })
      const id = repayLoan.hotelEmployeeLoanId
      setRepayLoan(null)
      await refresh(detail ? id : undefined)
    } catch (e: any) {
      toast({ title: "Could not record repayment", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  // ----- Filtering -----
  const filtered = useMemo(() => {
    let list = loans
    if (statusTab === "OPEN") list = list.filter((l) => l.status === "Draft" || l.status === "Active")
    else if (statusTab === "CLOSED") list = list.filter((l) => l.status === "Cancelled" || l.status === "Reversed" || l.status === "WrittenOff")
    else if (statusTab !== "ALL") list = list.filter((l) => l.status === statusTab)
    if (staffFilter !== "ALL") list = list.filter((l) => String(l.hotelStaffId) === staffFilter)
    if (typeFilter !== "ALL") list = list.filter((l) => l.loanType === typeFilter)
    if (search.trim()) {
      const q = search.trim().toLowerCase()
      list = list.filter((l) =>
        (l.staffName ?? "").toLowerCase().includes(q) ||
        (l.loanNumber ?? "").toLowerCase().includes(q) ||
        (l.reference ?? "").toLowerCase().includes(q))
    }
    return list
  }, [loans, statusTab, staffFilter, typeFilter, search])

  const staffWithLoans = useMemo(() => {
    const ids = new Set(loans.map((l) => l.hotelStaffId))
    const fromList = staff.filter((s) => ids.has(staffIdOf(s)))
    // A staff member who has since been removed still shows by the name on the loan.
    const missing = loans.filter((l) => !staff.some((s) => staffIdOf(s) === l.hotelStaffId))
      .map((l) => ({ hotelStaffId: l.hotelStaffId, firstName: l.staffName ?? `Staff #${l.hotelStaffId}`, lastName: "" }))
    const uniq = new Map<number, any>()
    for (const s of [...fromList, ...missing]) uniq.set(staffIdOf(s), s)
    return Array.from(uniq.values()).sort((a, b) => staffNameOf(a).localeCompare(staffNameOf(b)))
  }, [loans, staff])

  const filteredOwed = filtered.filter((l) => l.status === "Active").reduce((s, l) => s + l.outstandingBalance, 0)

  if (loading) return (
    <div className="flex h-screen"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col"><DashboardHeader />
      <div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
    </div></div>
  )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6 space-y-5">
          {/* Header */}
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-3">
              <Coins className="h-6 w-6 text-violet-600" />
              <div>
                <h1 className="text-2xl font-bold">Staff Loans & Advances</h1>
                <p className="text-sm text-slate-500">Money lent to staff, and how it is being paid back.</p>
              </div>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" asChild><Link href="/hotel-payroll"><Banknote className="h-4 w-4 mr-1" />Payroll</Link></Button>
              <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" />New advance</Button>
            </div>
          </div>

          <div className="flex gap-2 rounded-lg border border-violet-200 bg-violet-50 p-3 text-sm text-violet-900">
            <Info className="h-4 w-4 mt-0.5 shrink-0" />
            <p>
              An advance is <strong>not an expense</strong> — the staff member owes it back. Paying it out takes the amount from a cash account;
              cash repayments put it back. Deductions set on a payroll line are repaid when that payroll run is <strong>approved</strong>,
              and the P&amp;L still shows the full wage.
            </p>
          </div>

          {/* Summary */}
          {summary && (
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
              <Card className="border-l-4 border-l-red-500"><CardContent className="p-4">
                <p className="text-xs text-slate-500">Owed by staff</p>
                <p className="text-xl sm:text-2xl font-bold text-red-600 tabular-nums">{fmt(summary.totalOutstanding)}</p>
                <p className="text-xs text-slate-500">{summary.activeCount} active · {summary.staffWithLoans} staff</p>
              </CardContent></Card>
              <Card className="border-l-4 border-l-violet-500"><CardContent className="p-4">
                <p className="text-xs text-slate-500">Given out (principal)</p>
                <p className="text-xl sm:text-2xl font-bold tabular-nums">{fmt(summary.totalDisbursed)}</p>
                <p className="text-xs text-slate-500">{summary.draftCount} draft not yet paid out</p>
              </CardContent></Card>
              <Card className="border-l-4 border-l-emerald-500"><CardContent className="p-4">
                <p className="text-xs text-slate-500">Repaid</p>
                <p className="text-xl sm:text-2xl font-bold text-emerald-600 tabular-nums">{fmt(summary.totalRepaid)}</p>
                <p className="text-xs text-slate-500">{fmt(summary.repaidViaPayroll)} via payroll · {fmt(summary.interestEarned)} interest</p>
              </CardContent></Card>
              <Card className="border-l-4 border-l-amber-500"><CardContent className="p-4">
                <p className="text-xs text-slate-500">Set aside on draft payroll</p>
                <p className="text-xl sm:text-2xl font-bold text-amber-600 tabular-nums">{fmt(summary.draftPayrollClaims)}</p>
                <p className="text-xs text-slate-500">repaid when the run is approved</p>
              </CardContent></Card>
            </div>
          )}

          {/* Filters */}
          <div className="space-y-3">
            <div className="flex flex-wrap gap-2">
              {STATUS_TABS.map((t) => (
                <Button key={t.value} size="sm" variant={statusTab === t.value ? "default" : "outline"}
                  className={statusTab === t.value ? "bg-violet-600 hover:bg-violet-700" : ""}
                  onClick={() => setStatusTab(t.value)}>{t.label}</Button>
              ))}
            </div>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <div className="relative">
                <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
                <Input placeholder="Search staff, loan no., reference…" value={search} onChange={(e) => setSearch(e.target.value)} className="pl-8" />
              </div>
              <Select value={staffFilter} onValueChange={setStaffFilter}>
                <SelectTrigger><SelectValue placeholder="All staff" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All staff</SelectItem>
                  {staffWithLoans.map((s) => <SelectItem key={staffIdOf(s)} value={String(staffIdOf(s))}>{staffNameOf(s)}</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={typeFilter} onValueChange={setTypeFilter}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All types</SelectItem>
                  {HOTEL_LOAN_TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            {filtered.length > 0 && (
              <p className="text-xs text-slate-500">{filtered.length} loan(s){filteredOwed > 0 ? ` · ${fmt(filteredOwed)} still owed` : ""}</p>
            )}
          </div>

          {/* List */}
          <Card>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-sm min-w-[860px]">
                  <thead><tr className="border-b bg-slate-50 text-slate-600">
                    <th className="text-left p-3">Loan</th>
                    <th className="text-left p-3">Staff</th>
                    <th className="text-left p-3">Type</th>
                    <th className="text-right p-3">Given</th>
                    <th className="text-right p-3">To repay</th>
                    <th className="text-right p-3">Owed</th>
                    <th className="text-left p-3">Repayment</th>
                    <th className="text-center p-3">Status</th>
                    <th className="text-right p-3">Actions</th>
                  </tr></thead>
                  <tbody>
                    {filtered.length === 0 && (
                      <tr><td colSpan={9} className="text-center p-8 text-slate-400">
                        {loans.length === 0 ? "No loans or advances yet." : "No loans match these filters."}
                      </td></tr>
                    )}
                    {filtered.map((l) => (
                      <tr key={l.hotelEmployeeLoanId} className="border-b hover:bg-slate-50 cursor-pointer" onClick={() => openDetail(l)}>
                        <td className="p-3">
                          <div className="font-mono text-xs font-semibold">{l.loanNumber ?? `#${l.hotelEmployeeLoanId}`}</div>
                          <div className="text-xs text-slate-500">{fmtDate(l.disbursementDate ?? l.createdAt)}</div>
                        </td>
                        <td className="p-3">
                          <div className="font-medium">{l.staffName || "—"}</div>
                          {!l.staffIsActive && <div className="text-xs text-amber-600">inactive</div>}
                        </td>
                        <td className="p-3">{hotelLoanTypeLabel(l.loanType)}</td>
                        <td className="p-3 text-right tabular-nums">{fmt(l.principalAmount)}</td>
                        <td className="p-3 text-right tabular-nums">
                          {fmt(l.totalRepayable)}
                          {l.interestAmount > 0 && <div className="text-xs text-slate-500">incl. {fmt(l.interestAmount)} interest</div>}
                        </td>
                        <td className="p-3 text-right tabular-nums">
                          <span className={l.status === "Active" && l.outstandingBalance > 0 ? "text-red-600 font-semibold" : "text-slate-500"}>
                            {l.status === "Active" || l.status === "Paid" ? fmt(l.outstandingBalance) : "—"}
                          </span>
                          {l.draftPayrollClaims > 0 && <div className="text-xs text-amber-600">{fmt(l.draftPayrollClaims)} on draft payroll</div>}
                        </td>
                        <td className="p-3 text-xs">
                          <div>{hotelLoanMethodLabel(l.repaymentMethod)}</div>
                          {l.defaultPayrollDeduction > 0 && <div className="text-slate-500">{fmt(l.defaultPayrollDeduction)} per payroll</div>}
                        </td>
                        <td className="p-3 text-center"><Badge className={STATUS_COLORS[l.status] ?? ""}>{l.status}</Badge></td>
                        <td className="p-3 text-right whitespace-nowrap" onClick={(e) => e.stopPropagation()}>
                          {l.status === "Draft" && (
                            <Button size="sm" variant="outline" onClick={() => openDisburse(l)}><HandCoins className="h-4 w-4 mr-1" />Pay out</Button>
                          )}
                          {l.status === "Active" && (
                            <Button size="sm" variant="outline" onClick={() => openRepay(l)}><Wallet className="h-4 w-4 mr-1" />Repay</Button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>

          {/* ========== CREATE / EDIT ========== */}
          <Dialog open={formOpen} onOpenChange={setFormOpen}>
            <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
              <DialogHeader>
                <DialogTitle>{editing ? `Edit ${editing.loanNumber ?? "loan"}` : "New loan or advance"}</DialogTitle>
                <DialogDescription>
                  {editing
                    ? moneyLocked ? "Money has already moved, so only the repayment plan and notes can change." : "This loan is still a draft; anything can change."
                    : "Who is borrowing, how much, and how they will pay it back."}
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <FormSection title="Staff and amount" color="purple" stackOnMobile>
                  <FormField label="Staff member *">
                    <Select value={form.hotelStaffId ? String(form.hotelStaffId) : ""} onValueChange={(v) => setForm({ ...form, hotelStaffId: Number(v) })} disabled={!!editing}>
                      <SelectTrigger><SelectValue placeholder="Choose staff" /></SelectTrigger>
                      <SelectContent>
                        {(editing ? staff : activeStaff).map((s) => (
                          <SelectItem key={staffIdOf(s)} value={String(staffIdOf(s))}>{staffNameOf(s)}{s.role ? ` — ${s.role}` : ""}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Type">
                    <Select value={form.loanType} onValueChange={(v) => setForm({ ...form, loanType: v })} disabled={moneyLocked}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{HOTEL_LOAN_TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Amount given *">
                    <NumberInput step="0.01" min={0} value={form.principalAmount || ""} disabled={moneyLocked}
                      onChange={(e) => setForm({ ...form, principalAmount: Number(e.target.value) || 0 })} />
                  </FormField>
                  <FormField label="Interest (flat amount)">
                    <NumberInput step="0.01" min={0} value={form.interestAmount || ""} disabled={moneyLocked}
                      onChange={(e) => setForm({ ...form, interestAmount: Number(e.target.value) || 0 })} />
                  </FormField>
                </FormSection>
                <p className="text-sm text-slate-600">Total to repay: <strong className="tabular-nums">{fmt(formTotal)}</strong></p>

                <FormSection title="How it is paid back" color="indigo" stackOnMobile>
                  <FormField label="Repayment method">
                    <Select value={form.repaymentMethod} onValueChange={(v) => setForm({ ...form, repaymentMethod: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{HOTEL_LOAN_REPAYMENT_METHODS.map((m) => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label={byPayroll ? "Deduct per payroll *" : "Deduct per payroll"}>
                    <NumberInput step="0.01" min={0} value={form.defaultPayrollDeduction || ""}
                      onChange={(e) => setForm({ ...form, defaultPayrollDeduction: Number(e.target.value) || 0 })} />
                  </FormField>
                  <FormField label="Expected to finish">
                    <Input type="date" value={form.expectedEndDate} onChange={(e) => setForm({ ...form, expectedEndDate: e.target.value })} />
                  </FormField>
                  <FormField label="Reference">
                    <Input value={form.reference} onChange={(e) => setForm({ ...form, reference: e.target.value })} placeholder="Voucher / note no." />
                  </FormField>
                </FormSection>
                {byPayroll && payrollsToClear > 0 && (
                  <p className="text-xs text-slate-500">
                    At {fmt(form.defaultPayrollDeduction)} per payroll this is cleared in about {payrollsToClear} payroll run{payrollsToClear === 1 ? "" : "s"}.
                    Payroll will suggest this deduction for the staff member automatically.
                  </p>
                )}

                <FormField label="Notes">
                  <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} rows={2} />
                </FormField>

                {!editing && (
                  <div className="rounded-lg border p-3 space-y-3">
                    <label className="flex items-center gap-2 text-sm font-medium">
                      <input type="checkbox" checked={form.disburseNow} onChange={(e) => setForm({ ...form, disburseNow: e.target.checked })} />
                      Pay the money out now
                    </label>
                    {form.disburseNow ? (
                      <div className="grid gap-3 sm:grid-cols-2">
                        <FormField label="Paid from *">
                          <Select value={form.hotelCashAccountId ? String(form.hotelCashAccountId) : ""} onValueChange={(v) => setForm({ ...form, hotelCashAccountId: Number(v) })}>
                            <SelectTrigger><SelectValue placeholder="Choose cash account" /></SelectTrigger>
                            <SelectContent>
                              {activeAccounts.map((a) => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName} ({fmt(a.currentBalance)})</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </FormField>
                        <FormField label="Date paid">
                          <Input type="date" value={form.disbursementDate} onChange={(e) => setForm({ ...form, disbursementDate: e.target.value })} />
                        </FormField>
                      </div>
                    ) : (
                      <p className="text-xs text-slate-500">Saved as a draft. Nothing moves until you pay it out.</p>
                    )}
                  </div>
                )}
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setFormOpen(false)}>Cancel</Button>
                <Button onClick={saveForm} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                  {saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
                  {editing ? "Save changes" : form.disburseNow ? `Give ${fmt(form.principalAmount)}` : "Save draft"}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* ========== DETAIL ========== */}
          <Dialog open={!!detail} onOpenChange={(v) => { if (!v) setDetail(null) }}>
            <DialogContent className="sm:max-w-3xl max-h-[90vh] overflow-y-auto">
              {detail && (
                <>
                  <DialogHeader>
                    <DialogTitle className="flex flex-wrap items-center gap-2">
                      {detail.loanNumber ?? "Loan"} · {detail.staffName}
                      <Badge className={STATUS_COLORS[detail.status] ?? ""}>{detail.status}</Badge>
                    </DialogTitle>
                    <DialogDescription>
                      {hotelLoanTypeLabel(detail.loanType)} · {hotelLoanMethodLabel(detail.repaymentMethod)}
                      {detail.defaultPayrollDeduction > 0 ? ` · ${fmt(detail.defaultPayrollDeduction)} per payroll` : ""}
                    </DialogDescription>
                  </DialogHeader>

                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    {[
                      ["Given", fmt(detail.principalAmount), ""],
                      ["To repay", fmt(detail.totalRepayable), ""],
                      ["Repaid", fmt(detail.totalPrincipalRepaid + detail.totalInterestRepaid), "text-emerald-600"],
                      ["Owed", detail.status === "Active" || detail.status === "Paid" ? fmt(detail.outstandingBalance) : "—", "text-red-600"],
                    ].map(([label, value, tone]) => (
                      <div key={label} className="rounded-lg border p-3">
                        <div className="text-xs text-slate-500">{label}</div>
                        <div className={`text-lg font-bold tabular-nums ${tone}`}>{value}</div>
                      </div>
                    ))}
                  </div>

                  <div className="grid gap-1 text-sm sm:grid-cols-2">
                    <div><span className="text-slate-500">Paid out:</span> {detail.disbursementDate ? `${fmtDate(detail.disbursementDate)} from ${detail.cashAccountName ?? "—"}` : "not yet"}</div>
                    <div><span className="text-slate-500">Expected to finish:</span> {fmtDate(detail.expectedEndDate)}</div>
                    {detail.interestAmount > 0 && <div><span className="text-slate-500">Interest repaid:</span> {fmt(detail.totalInterestRepaid)} of {fmt(detail.interestAmount)}</div>}
                    {detail.reference && <div><span className="text-slate-500">Reference:</span> {detail.reference}</div>}
                    {detail.draftPayrollClaims > 0 && <div className="text-amber-700">{fmt(detail.draftPayrollClaims)} set to be deducted on a draft payroll run</div>}
                    {detail.notes && <div className="sm:col-span-2"><span className="text-slate-500">Notes:</span> {detail.notes}</div>}
                    {detail.reversedReason && (
                      <div className="sm:col-span-2 text-red-700">{detail.status === "Cancelled" ? "Cancelled" : "Reversed"}: {detail.reversedReason}{detail.reversedBy ? ` — ${detail.reversedBy}` : ""}</div>
                    )}
                  </div>

                  <div className="flex flex-wrap gap-2">
                    {detail.status === "Draft" && <>
                      <Button size="sm" className="bg-violet-600 hover:bg-violet-700" onClick={() => openDisburse(detail)}><HandCoins className="h-4 w-4 mr-1" />Pay out</Button>
                      <Button size="sm" variant="outline" onClick={() => openEdit(detail)}><Pencil className="h-4 w-4 mr-1" />Edit</Button>
                      <Button size="sm" variant="outline" className="text-amber-700" onClick={() => setCancelTarget(detail)}><XCircle className="h-4 w-4 mr-1" />Cancel</Button>
                    </>}
                    {(detail.status === "Active" || detail.status === "Paid") && <>
                      {detail.status === "Active" && <Button size="sm" className="bg-violet-600 hover:bg-violet-700" onClick={() => openRepay(detail)}><Wallet className="h-4 w-4 mr-1" />Record repayment</Button>}
                      <Button size="sm" variant="outline" onClick={() => openEdit(detail)}><Pencil className="h-4 w-4 mr-1" />Edit plan</Button>
                      <Button size="sm" variant="outline" className="text-red-700" onClick={() => setReverseTarget(detail)}><RotateCcw className="h-4 w-4 mr-1" />Reverse loan</Button>
                    </>}
                  </div>

                  <div>
                    <h3 className="text-sm font-semibold mb-2">Repayments</h3>
                    {repLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : repayments.length === 0 ? (
                      <p className="text-sm text-slate-500">No repayments yet.</p>
                    ) : (
                      <div className="overflow-x-auto rounded-lg border">
                        <table className="w-full text-sm min-w-[620px]">
                          <thead><tr className="border-b bg-slate-50 text-slate-600">
                            <th className="text-left p-2">Date</th>
                            <th className="text-left p-2">How</th>
                            <th className="text-right p-2">Amount</th>
                            <th className="text-right p-2">Owed after</th>
                            <th className="text-center p-2">Status</th>
                            <th className="p-2"></th>
                          </tr></thead>
                          <tbody>
                            {repayments.map((rp) => (
                              <tr key={rp.hotelEmployeeLoanRepaymentId} className={`border-b ${rp.status === "Reversed" ? "opacity-60" : ""}`}>
                                <td className="p-2">{fmtDate(rp.repaymentDate)}</td>
                                <td className="p-2">
                                  <div>{hotelLoanSourceLabel(rp.sourceType)}</div>
                                  <div className="text-xs text-slate-500">
                                    {rp.sourceType === "Payroll"
                                      ? <>Payroll {rp.payrollPeriod ?? `#${rp.hotelPayrollRunId}`} · no cash moved</>
                                      : rp.cashAccountName ? <>into {rp.cashAccountName}</> : <>no cash account</>}
                                  </div>
                                </td>
                                <td className="p-2 text-right tabular-nums">
                                  {fmt(rp.amount)}
                                  {rp.interestAmount > 0 && <div className="text-xs text-slate-500">{fmt(rp.interestAmount)} interest</div>}
                                </td>
                                <td className="p-2 text-right tabular-nums">{fmt(rp.balanceAfter)}</td>
                                <td className="p-2 text-center">
                                  <Badge className={rp.status === "Posted" ? "bg-emerald-100 text-emerald-700" : "bg-red-100 text-red-700"}>{rp.status}</Badge>
                                  {rp.reversedReason && <div className="text-xs text-slate-500 mt-1">{rp.reversedReason}</div>}
                                </td>
                                <td className="p-2 text-right">
                                  {rp.status === "Posted" && rp.sourceType !== "Payroll" && (
                                    <Button size="sm" variant="ghost" title="Reverse this repayment" onClick={() => setReverseRepTarget(rp)}>
                                      <RotateCcw className="h-3.5 w-3.5" />
                                    </Button>
                                  )}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                    <p className="text-xs text-slate-500 mt-2">
                      A payroll repayment is undone by reopening or cancelling its payroll run, so the payroll and the loan always agree.
                    </p>
                  </div>
                </>
              )}
            </DialogContent>
          </Dialog>

          {/* ========== DISBURSE ========== */}
          <Dialog open={!!disburseLoan} onOpenChange={(v) => { if (!v) setDisburseLoan(null) }}>
            <DialogContent className="sm:max-w-md">
              <DialogHeader>
                <DialogTitle>Pay out {disburseLoan?.loanNumber}</DialogTitle>
                <DialogDescription>
                  {disburseLoan ? `${fmt(disburseLoan.principalAmount)} to ${disburseLoan.staffName}. ` : ""}
                  The amount leaves the cash account you choose; the loan becomes active.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3">
                <FormField label="Paid from *">
                  <Select value={disburseForm.hotelCashAccountId ? String(disburseForm.hotelCashAccountId) : ""} onValueChange={(v) => setDisburseForm({ ...disburseForm, hotelCashAccountId: Number(v) })}>
                    <SelectTrigger><SelectValue placeholder="Choose cash account" /></SelectTrigger>
                    <SelectContent>
                      {activeAccounts.map((a) => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName} ({fmt(a.currentBalance)})</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Date paid"><Input type="date" value={disburseForm.disbursementDate} onChange={(e) => setDisburseForm({ ...disburseForm, disbursementDate: e.target.value })} /></FormField>
                <FormField label="Reference"><Input value={disburseForm.reference} onChange={(e) => setDisburseForm({ ...disburseForm, reference: e.target.value })} /></FormField>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setDisburseLoan(null)}>Back</Button>
                <Button onClick={saveDisburse} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Pay out</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* ========== REPAY ========== */}
          <Dialog open={!!repayLoan} onOpenChange={(v) => { if (!v) setRepayLoan(null) }}>
            <DialogContent className="sm:max-w-md">
              <DialogHeader>
                <DialogTitle>Record a repayment</DialogTitle>
                <DialogDescription>
                  {repayLoan ? `${repayLoan.staffName} · ${repayLoan.loanNumber} · owes ${fmt(repayLoan.outstandingBalance)}. ` : ""}
                  For money handed back directly. Payroll deductions are set on the payroll run instead.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3">
                <FormField label="Amount *">
                  <div className="flex gap-2">
                    <NumberInput step="0.01" min={0} value={repayForm.amount || ""} onChange={(e) => setRepayForm({ ...repayForm, amount: Number(e.target.value) || 0 })} />
                    {repayLoan && <Button type="button" variant="outline" size="sm" onClick={() => setRepayForm({ ...repayForm, amount: repayLoan.outstandingBalance })}>All</Button>}
                  </div>
                </FormField>
                <FormField label="Paid by">
                  <Select value={repayForm.sourceType} onValueChange={(v) => setRepayForm({ ...repayForm, sourceType: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{HOTEL_LOAN_REPAYMENT_SOURCES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Paid into *">
                  <Select value={repayForm.hotelCashAccountId ? String(repayForm.hotelCashAccountId) : ""} onValueChange={(v) => setRepayForm({ ...repayForm, hotelCashAccountId: Number(v) })}>
                    <SelectTrigger><SelectValue placeholder="Choose cash account" /></SelectTrigger>
                    <SelectContent>
                      {activeAccounts.map((a) => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Date"><Input type="date" value={repayForm.repaymentDate} onChange={(e) => setRepayForm({ ...repayForm, repaymentDate: e.target.value })} /></FormField>
                <FormField label="Reference"><Input value={repayForm.reference} onChange={(e) => setRepayForm({ ...repayForm, reference: e.target.value })} /></FormField>
                <FormField label="Notes"><Textarea rows={2} value={repayForm.notes} onChange={(e) => setRepayForm({ ...repayForm, notes: e.target.value })} /></FormField>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setRepayLoan(null)}>Back</Button>
                <Button onClick={saveRepay} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Record</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* ========== REASON PROMPTS ========== */}
          <PromptDialog
            open={!!cancelTarget}
            onOpenChange={(v) => { if (!v) setCancelTarget(null) }}
            title={`Cancel ${cancelTarget?.loanNumber ?? "loan"}?`}
            description="The draft is closed. No money has moved, so nothing else changes."
            label="Reason (optional)"
            allowEmpty
            confirmLabel="Cancel loan"
            confirmVariant="destructive"
            onSubmit={async (reason) => {
              if (!cancelTarget) return
              try {
                await cancelHotelEmployeeLoan(cancelTarget.hotelEmployeeLoanId, reason || undefined)
                toast({ title: "Loan cancelled" })
                const id = cancelTarget.hotelEmployeeLoanId
                setCancelTarget(null)
                await refresh(detail ? id : undefined)
              } catch (e: any) { toast({ title: "Could not cancel", description: e?.message, variant: "destructive" }) }
            }}
          />
          <PromptDialog
            open={!!reverseTarget}
            onOpenChange={(v) => { if (!v) setReverseTarget(null) }}
            title={`Reverse ${reverseTarget?.loanNumber ?? "loan"}?`}
            description={reverseTarget ? `Use this when the loan was a mistake. ${fmt(reverseTarget.principalAmount)} goes back into ${reverseTarget.cashAccountName ?? "the account it came from"}. Any repayments must be reversed first.` : ""}
            label="Reason"
            confirmLabel="Reverse loan"
            confirmVariant="destructive"
            onSubmit={async (reason) => {
              if (!reverseTarget) return
              try {
                await reverseHotelEmployeeLoan(reverseTarget.hotelEmployeeLoanId, reason)
                toast({ title: "Loan reversed" })
                const id = reverseTarget.hotelEmployeeLoanId
                setReverseTarget(null)
                await refresh(detail ? id : undefined)
              } catch (e: any) { toast({ title: "Could not reverse", description: e?.message, variant: "destructive" }) }
            }}
          />
          <PromptDialog
            open={!!reverseRepTarget}
            onOpenChange={(v) => { if (!v) setReverseRepTarget(null) }}
            title="Reverse this repayment?"
            description={reverseRepTarget ? `${fmt(reverseRepTarget.amount)} goes back out of ${reverseRepTarget.cashAccountName ?? "its cash account"} and is owed again.` : ""}
            label="Reason"
            confirmLabel="Reverse repayment"
            confirmVariant="destructive"
            onSubmit={async (reason) => {
              if (!reverseRepTarget) return
              try {
                await reverseHotelEmployeeLoanRepayment(reverseRepTarget.hotelEmployeeLoanRepaymentId, reason)
                toast({ title: "Repayment reversed" })
                const id = reverseRepTarget.hotelEmployeeLoanId
                setReverseRepTarget(null)
                await refresh(id)
              } catch (e: any) { toast({ title: "Could not reverse", description: e?.message, variant: "destructive" }) }
            }}
          />
        </main>
      </div>
    </div>
  )
}

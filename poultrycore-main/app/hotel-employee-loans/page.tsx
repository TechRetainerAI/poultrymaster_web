"use client"
import { Fragment, useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Plus, HandCoins, RotateCcw, XCircle, ChevronDown, ChevronUp } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelEmployeeLoans, createHotelEmployeeLoan, disburseHotelEmployeeLoan,
  cancelHotelEmployeeLoan, reverseHotelEmployeeLoan, getHotelEmployeeLoanSummary,
  listHotelEmployeeLoanRepayments, recordHotelEmployeeLoanRepayment, reverseHotelEmployeeLoanRepayment,
  type HotelEmployeeLoan, type HotelEmployeeLoanSummary, type HotelEmployeeLoanRepayment,
} from "@/lib/api/hotel-employee-loans"
import { listHotelCashAccounts, listHotelStaff, type HotelCashAccount } from "@/lib/api/hotel"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Active: "bg-blue-100 text-blue-700",
  Paid: "bg-emerald-100 text-emerald-700",
  Cancelled: "bg-amber-100 text-amber-700",
  Reversed: "bg-red-100 text-red-700",
  WrittenOff: "bg-purple-100 text-purple-700",
}

const LOAN_TYPES = ["SalaryAdvance", "EmployeeLoan", "OtherAdvance"]
const REPAY_METHODS = ["Cash", "MoMo", "Bank", "PayrollDeduction", "Other"]
const REPAY_SOURCES = ["Cash", "MoMo", "Bank", "Other"]

function todayLocal(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export default function HotelEmployeeLoansPage() {
  const router = useRouter(); const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loans, setLoans] = useState<HotelEmployeeLoan[]>([])
  const [summary, setSummary] = useState<HotelEmployeeLoanSummary | null>(null)
  const [staff, setStaff] = useState<any[]>([])
  const [accounts, setAccounts] = useState<HotelCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState("ALL")
  const [search, setSearch] = useState("")

  // Create dialog
  const [createOpen, setCreateOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({
    hotelStaffId: 0, loanType: "SalaryAdvance", principalAmount: 0, interestAmount: 0,
    repaymentMethod: "Cash", defaultPayrollDeduction: 0, expectedEndDate: "",
    reference: "", notes: "", disburseNow: false, hotelCashAccountId: null as number | null,
    disbursementDate: todayLocal(),
  })

  // Expanded row for repayments
  const [expandedId, setExpandedId] = useState<number | null>(null)
  const [repayments, setRepayments] = useState<HotelEmployeeLoanRepayment[]>([])
  const [repLoading, setRepLoading] = useState(false)

  // Repay dialog
  const [repayOpen, setRepayOpen] = useState(false); const [repayLoan, setRepayLoan] = useState<HotelEmployeeLoan | null>(null)
  const [repayForm, setRepayForm] = useState({ amount: 0, sourceType: "Cash", hotelCashAccountId: null as number | null, repaymentDate: todayLocal(), reference: "", notes: "" })

  // Disburse dialog
  const [disburseOpen, setDisburseOpen] = useState(false); const [disburseLoan, setDisburseLoan] = useState<HotelEmployeeLoan | null>(null)
  const [disburseForm, setDisburseForm] = useState({ hotelCashAccountId: null as number | null, disbursementDate: todayLocal(), reference: "" })

  // Reason dialog (cancel/reverse)
  const [reasonOpen, setReasonOpen] = useState(false); const [reasonAction, setReasonAction] = useState<"cancel" | "reverse" | "reverseRepayment">("cancel")
  const [reasonTarget, setReasonTarget] = useState<any>(null); const [reason, setReason] = useState("")

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [ls, s, st, accs] = await Promise.all([
        listHotelEmployeeLoans(), getHotelEmployeeLoanSummary(), listHotelStaff(), listHotelCashAccounts(),
      ])
      setLoans(ls); setSummary(s); setStaff(st); setAccounts(accs)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function toggleExpand(id: number) {
    if (expandedId === id) { setExpandedId(null); return }
    setExpandedId(id); setRepLoading(true)
    try { setRepayments(await listHotelEmployeeLoanRepayments(id)) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setRepLoading(false) }
  }

  async function saveCreate() {
    if (!form.hotelStaffId) { toast({ title: "Select a staff member", variant: "destructive" }); return }
    if (form.principalAmount <= 0) { toast({ title: "Amount must be positive", variant: "destructive" }); return }
    setSaving(true)
    try {
      const s = staff.find((st: any) => (st.hotelStaffId ?? st.hotelstaffid) === form.hotelStaffId) as any
      const staffName = s ? `${s.firstName ?? s.firstname ?? ""} ${s.lastName ?? s.lastname ?? ""}`.trim() : undefined
      await createHotelEmployeeLoan({ ...form, farmId: "", staffName })
      toast({ title: form.disburseNow ? "Loan created and disbursed" : "Loan created as Draft" })
      setCreateOpen(false); await load()
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function openRepay(loan: HotelEmployeeLoan) {
    setRepayLoan(loan)
    setRepayForm({ amount: 0, sourceType: "Cash", hotelCashAccountId: null, repaymentDate: todayLocal(), reference: "", notes: "" })
    setRepayOpen(true)
  }

  async function saveRepay() {
    if (!repayLoan || repayForm.amount <= 0) { toast({ title: "Amount must be positive", variant: "destructive" }); return }
    setSaving(true)
    try {
      await recordHotelEmployeeLoanRepayment({ ...repayForm, farmId: "", hotelEmployeeLoanId: repayLoan.hotelEmployeeLoanId })
      toast({ title: "Repayment recorded" })
      setRepayOpen(false); await load()
      if (expandedId === repayLoan.hotelEmployeeLoanId) { setRepayments(await listHotelEmployeeLoanRepayments(repayLoan.hotelEmployeeLoanId)) }
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function openDisburse(loan: HotelEmployeeLoan) {
    setDisburseLoan(loan)
    setDisburseForm({ hotelCashAccountId: null, disbursementDate: todayLocal(), reference: "" })
    setDisburseOpen(true)
  }

  async function saveDisburse() {
    if (!disburseLoan) return
    setSaving(true)
    try {
      await disburseHotelEmployeeLoan(disburseLoan.hotelEmployeeLoanId, disburseForm.hotelCashAccountId, disburseForm.disbursementDate, disburseForm.reference)
      toast({ title: "Loan disbursed" })
      setDisburseOpen(false); await load()
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function openReason(action: "cancel" | "reverse" | "reverseRepayment", target: any) {
    setReasonAction(action); setReasonTarget(target); setReason(""); setReasonOpen(true)
  }

  async function submitReason() {
    try {
      if (reasonAction === "cancel") await cancelHotelEmployeeLoan(reasonTarget.hotelEmployeeLoanId, reason)
      else if (reasonAction === "reverse") await reverseHotelEmployeeLoan(reasonTarget.hotelEmployeeLoanId, reason)
      else if (reasonAction === "reverseRepayment") await reverseHotelEmployeeLoanRepayment(reasonTarget.hotelEmployeeLoanRepaymentId, reason)
      toast({ title: `${reasonAction === "cancel" ? "Cancelled" : "Reversed"} successfully` })
      setReasonOpen(false); await load()
      if (expandedId && reasonAction === "reverseRepayment") { setRepayments(await listHotelEmployeeLoanRepayments(expandedId)) }
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
  }

  const filtered = useMemo(() => {
    let list = loans
    if (statusFilter !== "ALL") list = list.filter(l => l.status === statusFilter)
    if (search) {
      const s = search.toLowerCase()
      list = list.filter(l => (l.staffName || "").toLowerCase().includes(s) || l.loanType.toLowerCase().includes(s))
    }
    return list
  }, [loans, statusFilter, search])

  const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  const fmtDate = (s?: string | null) => s ? new Date(s).toLocaleDateString() : "—"

  if (loading) return (
    <div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader />
      <div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-muted-foreground" /></div>
    </div></div>
  )

  return (
    <div className="flex h-screen">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6 space-y-6">
          <div className="flex items-center justify-between">
            <h1 className="text-2xl font-bold">Employee Loans & Advances</h1>
            <Button onClick={() => { setForm({ hotelStaffId: 0, loanType: "SalaryAdvance", principalAmount: 0, interestAmount: 0, repaymentMethod: "Cash", defaultPayrollDeduction: 0, expectedEndDate: "", reference: "", notes: "", disburseNow: false, hotelCashAccountId: null, disbursementDate: todayLocal() }); setCreateOpen(true) }}>
              <Plus className="h-4 w-4 mr-2" />New Advance
            </Button>
          </div>

          <p className="text-sm text-muted-foreground">An advance is NOT an expense. Disbursement reduces cash but posts no P&L entry. Getting money back is NOT revenue.</p>

          {/* Summary Cards */}
          {summary && (
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
              <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Outstanding</p><p className="text-2xl font-bold text-red-600">{fmt(summary.totalOutstanding)}</p></CardContent></Card>
              <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Total Disbursed</p><p className="text-2xl font-bold">{fmt(summary.totalDisbursed)}</p></CardContent></Card>
              <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Total Repaid</p><p className="text-2xl font-bold text-emerald-600">{fmt(summary.totalRepaid)}</p></CardContent></Card>
              <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Active Loans</p><p className="text-2xl font-bold">{summary.activeCount}</p></CardContent></Card>
            </div>
          )}

          {/* Filters */}
          <div className="flex gap-4 flex-wrap">
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">All</SelectItem>
                <SelectItem value="Draft">Draft</SelectItem>
                <SelectItem value="Active">Active</SelectItem>
                <SelectItem value="Paid">Paid</SelectItem>
                <SelectItem value="Cancelled">Cancelled</SelectItem>
                <SelectItem value="Reversed">Reversed</SelectItem>
              </SelectContent>
            </Select>
            <Input placeholder="Search by staff name..." value={search} onChange={(e) => setSearch(e.target.value)} className="max-w-xs" />
          </div>

          {/* Table */}
          <Card>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead><tr className="border-b bg-muted/50">
                    <th className="w-8 p-3"></th>
                    <th className="text-left p-3">Staff</th>
                    <th className="text-left p-3">Type</th>
                    <th className="text-right p-3">Amount</th>
                    <th className="text-right p-3">Outstanding</th>
                    <th className="text-center p-3">Status</th>
                    <th className="text-left p-3">Date</th>
                    <th className="text-right p-3">Actions</th>
                  </tr></thead>
                  <tbody>
                    {filtered.length === 0 && (
                      <tr><td colSpan={8} className="text-center p-8 text-muted-foreground">No loans found</td></tr>
                    )}
                    {filtered.map(l => (
                      <Fragment key={l.hotelEmployeeLoanId}>
                        <tr className="border-b hover:bg-muted/30 cursor-pointer" onClick={() => toggleExpand(l.hotelEmployeeLoanId)}>
                          <td className="p-3">{expandedId === l.hotelEmployeeLoanId ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}</td>
                          <td className="p-3 font-medium">{l.staffName || "—"}</td>
                          <td className="p-3"><Badge variant="outline">{l.loanType}</Badge></td>
                          <td className="p-3 text-right font-mono">{fmt(l.totalRepayable)}</td>
                          <td className="p-3 text-right font-mono"><span className={l.outstandingBalance > 0 ? "text-red-600 font-semibold" : "text-emerald-600"}>{fmt(l.outstandingBalance)}</span></td>
                          <td className="p-3 text-center"><Badge className={STATUS_COLORS[l.status] || ""}>{l.status}</Badge></td>
                          <td className="p-3">{fmtDate(l.disbursementDate || l.createdAt)}</td>
                          <td className="p-3 text-right space-x-1" onClick={(e) => e.stopPropagation()}>
                            {l.status === "Draft" && <>
                              <Button size="sm" variant="outline" onClick={() => openDisburse(l)}><HandCoins className="h-4 w-4 mr-1" />Disburse</Button>
                              <Button size="sm" variant="ghost" onClick={() => openReason("cancel", l)}><XCircle className="h-4 w-4 text-amber-500" /></Button>
                            </>}
                            {l.status === "Active" && <>
                              <Button size="sm" variant="outline" onClick={() => openRepay(l)}>Repay</Button>
                              <Button size="sm" variant="ghost" onClick={() => openReason("reverse", l)}><RotateCcw className="h-4 w-4 text-red-500" /></Button>
                            </>}
                          </td>
                        </tr>
                        {expandedId === l.hotelEmployeeLoanId && (
                          <tr key={`exp-${l.hotelEmployeeLoanId}`}><td colSpan={8} className="bg-muted/20 p-4">
                            {repLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : repayments.length === 0 ? <p className="text-sm text-muted-foreground">No repayments yet</p> : (
                              <table className="w-full text-sm">
                                <thead><tr className="border-b">
                                  <th className="text-left p-2">Date</th><th className="text-left p-2">Source</th>
                                  <th className="text-right p-2">Amount</th><th className="text-right p-2">Balance Before</th>
                                  <th className="text-right p-2">Balance After</th><th className="text-center p-2">Status</th><th className="text-right p-2"></th>
                                </tr></thead>
                                <tbody>
                                  {repayments.map(rp => (
                                    <tr key={rp.hotelEmployeeLoanRepaymentId} className="border-b">
                                      <td className="p-2">{fmtDate(rp.repaymentDate)}</td>
                                      <td className="p-2">{rp.sourceType}{rp.sourceType === "Payroll" ? " (no cash)" : ""}</td>
                                      <td className="p-2 text-right font-mono">{fmt(rp.amount)}</td>
                                      <td className="p-2 text-right font-mono">{fmt(rp.balanceBefore)}</td>
                                      <td className="p-2 text-right font-mono">{fmt(rp.balanceAfter)}</td>
                                      <td className="p-2 text-center"><Badge className={rp.status === "Posted" ? "bg-emerald-100 text-emerald-700" : "bg-red-100 text-red-700"}>{rp.status}</Badge></td>
                                      <td className="p-2 text-right">
                                        {rp.status === "Posted" && rp.sourceType !== "Payroll" && (
                                          <Button size="sm" variant="ghost" onClick={() => openReason("reverseRepayment", rp)}><RotateCcw className="h-3 w-3" /></Button>
                                        )}
                                      </td>
                                    </tr>
                                  ))}
                                </tbody>
                              </table>
                            )}
                          </td></tr>
                        )}
                      </Fragment>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>

          {/* Create Dialog */}
          <Dialog open={createOpen} onOpenChange={setCreateOpen}>
            <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
              <DialogHeader><DialogTitle>New Loan / Advance</DialogTitle><DialogDescription>Create a new employee loan or salary advance.</DialogDescription></DialogHeader>
              <div className="space-y-4">
                <FormField label="Staff Member *">
                  <Select value={form.hotelStaffId ? String(form.hotelStaffId) : ""} onValueChange={(v) => setForm({ ...form, hotelStaffId: Number(v) })}>
                    <SelectTrigger><SelectValue placeholder="Select staff" /></SelectTrigger>
                    <SelectContent>
                      {staff.map((s: any) => <SelectItem key={s.hotelStaffId ?? s.hotelstaffid} value={String(s.hotelStaffId ?? s.hotelstaffid)}>{s.firstName ?? s.firstname} {s.lastName ?? s.lastname}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Type">
                  <Select value={form.loanType} onValueChange={(v) => setForm({ ...form, loanType: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{LOAN_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Principal Amount *">
                  <Input type="number" step="0.01" value={form.principalAmount || ""} onChange={(e) => setForm({ ...form, principalAmount: Number(e.target.value) })} />
                </FormField>
                <FormField label="Interest Amount">
                  <Input type="number" step="0.01" value={form.interestAmount || ""} onChange={(e) => setForm({ ...form, interestAmount: Number(e.target.value) })} />
                </FormField>
                <FormField label="Repayment Method">
                  <Select value={form.repaymentMethod} onValueChange={(v) => setForm({ ...form, repaymentMethod: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{REPAY_METHODS.map(m => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>

                <div className="flex items-center gap-2">
                  <input type="checkbox" checked={form.disburseNow} onChange={(e) => setForm({ ...form, disburseNow: e.target.checked })} id="disburseNow" />
                  <label htmlFor="disburseNow" className="text-sm">Disburse immediately</label>
                </div>
                {form.disburseNow && (
                  <>
                    <FormField label="Cash Account">
                      <Select value={form.hotelCashAccountId ? String(form.hotelCashAccountId) : "none"} onValueChange={(v) => setForm({ ...form, hotelCashAccountId: v === "none" ? null : Number(v) })}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="none">No account</SelectItem>
                          {accounts.map(a => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName}</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Disbursement Date"><Input type="date" value={form.disbursementDate} onChange={(e) => setForm({ ...form, disbursementDate: e.target.value })} /></FormField>
                  </>
                )}
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
                <Button onClick={saveCreate} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Create</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Disburse Dialog */}
          <Dialog open={disburseOpen} onOpenChange={setDisburseOpen}>
            <DialogContent>
              <DialogHeader><DialogTitle>Disburse Loan</DialogTitle><DialogDescription>Hand over the advance to {disburseLoan?.staffName}. Amount: {disburseLoan ? fmt(disburseLoan.totalRepayable) : ""}</DialogDescription></DialogHeader>
              <div className="space-y-4">
                <FormField label="Cash Account">
                  <Select value={disburseForm.hotelCashAccountId ? String(disburseForm.hotelCashAccountId) : "none"} onValueChange={(v) => setDisburseForm({ ...disburseForm, hotelCashAccountId: v === "none" ? null : Number(v) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">No account</SelectItem>
                      {accounts.map(a => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Date"><Input type="date" value={disburseForm.disbursementDate} onChange={(e) => setDisburseForm({ ...disburseForm, disbursementDate: e.target.value })} /></FormField>
                <FormField label="Reference"><Input value={disburseForm.reference} onChange={(e) => setDisburseForm({ ...disburseForm, reference: e.target.value })} /></FormField>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setDisburseOpen(false)}>Cancel</Button>
                <Button onClick={saveDisburse} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Disburse</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Repay Dialog */}
          <Dialog open={repayOpen} onOpenChange={setRepayOpen}>
            <DialogContent>
              <DialogHeader><DialogTitle>Record Repayment</DialogTitle><DialogDescription>{repayLoan?.staffName} — Outstanding: {repayLoan ? fmt(repayLoan.outstandingBalance) : ""}</DialogDescription></DialogHeader>
              <div className="space-y-4">
                <FormField label="Amount *"><Input type="number" step="0.01" value={repayForm.amount || ""} onChange={(e) => setRepayForm({ ...repayForm, amount: Number(e.target.value) })} /></FormField>
                <FormField label="Source">
                  <Select value={repayForm.sourceType} onValueChange={(v) => setRepayForm({ ...repayForm, sourceType: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{REPAY_SOURCES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Cash Account">
                  <Select value={repayForm.hotelCashAccountId ? String(repayForm.hotelCashAccountId) : "none"} onValueChange={(v) => setRepayForm({ ...repayForm, hotelCashAccountId: v === "none" ? null : Number(v) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">No account</SelectItem>
                      {accounts.map(a => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Date"><Input type="date" value={repayForm.repaymentDate} onChange={(e) => setRepayForm({ ...repayForm, repaymentDate: e.target.value })} /></FormField>
                <FormField label="Notes"><Textarea value={repayForm.notes} onChange={(e) => setRepayForm({ ...repayForm, notes: e.target.value })} /></FormField>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setRepayOpen(false)}>Cancel</Button>
                <Button onClick={saveRepay} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Record</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Reason Dialog */}
          <Dialog open={reasonOpen} onOpenChange={setReasonOpen}>
            <DialogContent>
              <DialogHeader><DialogTitle>{reasonAction === "cancel" ? "Cancel Loan" : "Reverse"}</DialogTitle></DialogHeader>
              <FormField label="Reason"><Textarea value={reason} onChange={(e) => setReason(e.target.value)} /></FormField>
              <DialogFooter>
                <Button variant="outline" onClick={() => setReasonOpen(false)}>Back</Button>
                <Button variant="destructive" onClick={submitReason}>Confirm</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

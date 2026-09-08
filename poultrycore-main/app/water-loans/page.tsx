"use client"

// Water Loans.
//
// Who lent the company money, how much is still owed, and what each repayment was
// actually made of.
//
// THE ONE THING THIS PAGE MUST TEACH
// ----------------------------------
// A repayment is not one number. Paying 12,500 to the bank might be 10,000 of
// principal, 2,000 of interest and 500 of fees — and only the last two are a
// cost. The first is the company swapping cash for a smaller debt, and counting it
// as an expense would make a profitable month look like a loss.
//
// So the repayment dialog never asks for a total. It asks for the three parts
// and shows the total, alongside what the debt will be afterwards. The split is
// the input; the total is a consequence.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Banknote, HandCoins, Loader2, Plus, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { entryTimestamp } from "@/lib/utils/date-key"
import { useFmt } from "@/lib/currency"
import {
  listWaterCashAccounts, listWaterLoans, getWaterLoanSummary, createWaterLoan,
  listWaterLoanPayments, recordWaterLoanRepayment, reverseWaterLoanPayment,
  type WaterCashAccount, type WaterLoan, type WaterLoanPayment, type WaterLoanSummary,
} from "@/lib/api/water"

const LENDER_TYPES = ["Bank", "FinancialInstitution", "Individual", "Owner", "FamilyFriend", "Supplier", "Other"]
const INTEREST_TYPES = ["Simple", "ReducingBalance", "Flat", "Unknown"]
const FREQUENCIES = ["Weekly", "BiWeekly", "Monthly", "Quarterly", "Custom"]
const PAYMENT_METHODS = ["Cash", "BankTransfer", "MoMo", "Cheque", "Card", "Other"]
const STATUS_FILTERS = ["All", "Active", "PaidOff", "Draft", "Cancelled"] as const

function today() { return new Date().toISOString().slice(0, 10) }

function statusClass(l: WaterLoan) {
  if (l.status === "PaidOff") return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
  if (l.status === "Cancelled") return "bg-slate-100 text-slate-700 hover:bg-slate-100"
  if (l.isOverdue) return "bg-rose-100 text-rose-800 hover:bg-rose-100"
  if (l.status === "Draft") return "bg-sky-100 text-sky-800 hover:bg-sky-100"
  return "bg-amber-100 text-amber-800 hover:bg-amber-100"
}

export default function WaterLoansPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [loans, setLoans] = useState<WaterLoan[]>([])
  const [payments, setPayments] = useState<WaterLoanPayment[]>([])
  const [summary, setSummary] = useState<WaterLoanSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState<string>("All")

  const [newOpen, setNewOpen] = useState(false)
  const [form, setForm] = useState({
    lenderName: "", lenderType: "Bank", accountNumber: "",
    originalPrincipal: "0", amountReceived: "0", waterCashAccountId: "",
    startDate: today(), interestRate: "", interestType: "ReducingBalance",
    termMonths: "", paymentFrequency: "Monthly", nextPaymentDate: "", notes: "",
  })

  const [repaying, setRepaying] = useState<WaterLoan | null>(null)
  const [pay, setPay] = useState({
    principalAmount: "0", interestAmount: "0", feeAmount: "0", otherAmount: "0",
    waterCashAccountId: "", paymentDate: today(), paymentMethod: "BankTransfer",
    referenceNumber: "", notes: "", nextPaymentDate: "",
  })

  const [reversing, setReversing] = useState<WaterLoanPayment | null>(null)
  const [reason, setReason] = useState("")

  const load = async () => {
    setLoading(true)
    try {
      const [accs, ls, ps, sum] = await Promise.all([
        listWaterCashAccounts(), listWaterLoans(), listWaterLoanPayments(), getWaterLoanSummary(),
      ])
      setAccounts(accs); setLoans(ls); setPayments(ps); setSummary(sum)
    } catch (e: any) {
      toast({ title: "Could not load loans", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(
    () => (status === "All" ? loans : loans.filter((l) => l.status === status)),
    [loans, status],
  )
  const pg = usePagination(visible)

  // The split IS the input. The total is shown, never typed.
  const principal = Number(pay.principalAmount) || 0
  const interest = Number(pay.interestAmount) || 0
  const fee = Number(pay.feeAmount) || 0
  const other = Number(pay.otherAmount) || 0
  const payTotal = principal + interest + fee + other
  const costOfBorrowing = interest + fee
  const outstandingAfter = repaying ? repaying.outstandingPrincipal - principal : 0

  const balanceOf = (id: string) =>
    accounts.find((a) => String(a.waterCashAccountId) === id)?.currentBalance ?? 0
  const allowsNegative = (id: string) =>
    accounts.find((a) => String(a.waterCashAccountId) === id)?.allowNegativeBalance ?? false
  const payWouldOverdraw =
    !!pay.waterCashAccountId && payTotal > 0 &&
    balanceOf(pay.waterCashAccountId) - payTotal < 0 && !allowsNegative(pay.waterCashAccountId)

  const saveLoan = async () => {
    if (!form.lenderName.trim()) { toast({ title: "Who lent the money?", variant: "destructive" }); return }
    const princ = Number(form.originalPrincipal) || 0
    const recv = Number(form.amountReceived) || 0
    if (princ <= 0) { toast({ title: "Enter the loan amount", variant: "destructive" }); return }
    if (recv > princ) { toast({ title: "Received cannot exceed the principal", variant: "destructive" }); return }
    if (recv > 0 && !form.waterCashAccountId) {
      toast({ title: "Which account received it?", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      await createWaterLoan({
        lenderName: form.lenderName.trim(),
        lenderType: form.lenderType,
        accountNumber: form.accountNumber.trim() || null,
        originalPrincipal: princ,
        amountReceived: recv,
        waterCashAccountId: recv > 0 ? Number(form.waterCashAccountId) : null,
        startDate: form.startDate,
        interestRate: form.interestRate ? Number(form.interestRate) : null,
        interestType: form.interestType || null,
        termMonths: form.termMonths ? Number(form.termMonths) : null,
        paymentFrequency: form.paymentFrequency || null,
        nextPaymentDate: form.nextPaymentDate || null,
        notes: form.notes.trim() || null,
      })
      toast({
        title: "Loan recorded",
        description: recv > 0
          ? `${fmt(recv)} in. It is money in, not revenue — the company borrowed it.`
          : "No money recorded as received yet.",
      })
      setNewOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Could not record the loan", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const savePayment = async () => {
    if (!repaying) return
    if (!pay.waterCashAccountId) { toast({ title: "Pick a cash account", variant: "destructive" }); return }
    if (payTotal <= 0) { toast({ title: "Enter the repayment", variant: "destructive" }); return }
    if (principal > repaying.outstandingPrincipal) {
      toast({ title: "Principal is more than is owed", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      await recordWaterLoanRepayment(repaying.waterLoanId, {
        waterCashAccountId: Number(pay.waterCashAccountId),
        principalAmount: principal,
        interestAmount: interest,
        feeAmount: fee,
        otherAmount: other,
        // Today gets a real clock time so the repayment sorts to the top of
        // cash flow and of the history below. See entryTimestamp.
        paymentDate: entryTimestamp(pay.paymentDate),
        paymentMethod: pay.paymentMethod || null,
        referenceNumber: pay.referenceNumber.trim() || null,
        notes: pay.notes.trim() || null,
        nextPaymentDate: pay.nextPaymentDate || null,
      })
      toast({
        title: "Repayment recorded",
        description: costOfBorrowing > 0
          ? `${fmt(payTotal)} left the account; only ${fmt(costOfBorrowing)} of it is a cost.`
          : `${fmt(payTotal)} off the debt. None of it is an expense.`,
      })
      setRepaying(null)
      await load()
    } catch (e: any) {
      toast({ title: "Could not record the repayment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const doReverse = async () => {
    if (!reversing) return
    if (reason.trim().length < 3) {
      toast({ title: "Say why", description: "The reason is written to the audit trail.", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await reverseWaterLoanPayment(reversing.waterLoanPaymentId, reason.trim())
      toast({ title: "Repayment reversed", description: "The debt is back up and the cash returned." })
      setReversing(null); setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const openRepay = (l: WaterLoan) => {
    setRepaying(l)
    setPay({
      principalAmount: "0", interestAmount: "0", feeAmount: "0", otherAmount: "0",
      waterCashAccountId: l.waterCashAccountId ? String(l.waterCashAccountId) : "",
      paymentDate: today(), paymentMethod: "BankTransfer",
      referenceNumber: "", notes: "", nextPaymentDate: "",
    })
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Banknote className="h-6 w-6 text-violet-600" /> Loans
              </h1>
              <p className="text-sm text-slate-500 max-w-2xl">
                Money the company has borrowed. Borrowing is <strong>not income</strong> and repaying
                principal is <strong>not an expense</strong> — only the interest and the fees are the
                cost of borrowing.
              </p>
            </div>
            <Button onClick={() => setNewOpen(true)} className="h-11 sm:h-10">
              <Plus className="h-4 w-4 mr-1" /> Record loan
            </Button>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
            <Stat label="Still owed" value={fmt(summary?.outstandingPrincipal ?? 0)}
                  hint={`${summary?.activeLoans ?? 0} active loan(s)`} accent="violet" />
            <Stat label="Borrowed" value={fmt(summary?.totalBorrowed ?? 0)}
                  hint={`${fmt(summary?.totalReceived ?? 0)} received`} />
            <Stat label="Principal repaid" value={fmt(summary?.totalPrincipalRepaid ?? 0)} accent="emerald" />
            <Stat label="Cost of borrowing"
                  value={fmt((summary?.totalInterestPaid ?? 0) + (summary?.totalFeesPaid ?? 0))}
                  hint="Interest and fees — the only part that is an expense" accent="amber" />
            <Stat label="Next payment"
                  value={summary?.nextPaymentDate ? new Date(summary.nextPaymentDate).toLocaleDateString() : "—"}
                  hint={(summary?.overdueLoans ?? 0) > 0 ? `${summary!.overdueLoans} overdue` : undefined}
                  accent={(summary?.overdueLoans ?? 0) > 0 ? "rose" : "slate"} />
          </div>

          <div className="flex flex-wrap gap-2 mb-4">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={status === s ? "default" : "outline"}
                      onClick={() => setStatus(s)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : visible.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              {loans.length === 0 ? "No loans recorded yet." : "No loans match this filter."}
            </CardContent></Card>
          ) : (
            <MobileCardList
              items={pg.pageItems}
              getKey={(l) => l.waterLoanId}
              primary={(l) => `${l.loanNumber ?? `#${l.waterLoanId}`} · ${l.lenderName}`}
              secondary={(l) => (
                <>
                  <span>{new Date(l.startDate).toLocaleDateString()}</span>
                  <span>·</span>
                  <span className="text-xs">{l.lenderType}</span>
                </>
              )}
              trailing={(l) => (
                <Badge className={statusClass(l)}>{l.isOverdue ? "Overdue" : l.status}</Badge>
              )}
              highlights={(l) => [
                { label: "Still owed", value: fmt(l.outstandingPrincipal) },
                { label: "Borrowed", value: fmt(l.originalPrincipal) },
              ]}
              details={(l) => [
                { label: "Received", value: fmt(l.amountReceived) },
                { label: "Principal repaid", value: fmt(l.totalPrincipalRepaid) },
                { label: "Interest paid", value: fmt(l.totalInterestPaid) },
                { label: "Fees paid", value: fmt(l.totalFeesPaid) },
                { label: "Rate", value: l.interestRate != null ? `${l.interestRate}% ${l.interestType ?? ""}` : "–" },
                { label: "Next payment", value: l.nextPaymentDate ? new Date(l.nextPaymentDate).toLocaleDateString() : "–" },
                { label: "Repayments", value: String(l.paymentCount) },
              ]}
              actions={(l) => (
                <>
                  {(l.status === "Active" || l.status === "Overdue") && l.outstandingPrincipal > 0 && (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openRepay(l)}>
                      <HandCoins className="h-4 w-4 mr-1" /> Repay
                    </Button>
                  )}
                </>
              )}
              {...pg.paginationProps}
              desktopTable={
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Loan #</TableHead>
                        <TableHead>Lender</TableHead>
                        <TableHead className="text-right">Borrowed</TableHead>
                        <TableHead className="text-right">Received</TableHead>
                        <TableHead className="text-right">Repaid</TableHead>
                        <TableHead className="text-right">Still owed</TableHead>
                        <TableHead className="text-right">Interest</TableHead>
                        <TableHead className="text-right">Fees</TableHead>
                        <TableHead>Next payment</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {pg.pageItems.map((l) => (
                        <TableRow key={l.waterLoanId}>
                          <TableCell className="font-medium">{l.loanNumber ?? `#${l.waterLoanId}`}</TableCell>
                          <TableCell>{l.lenderName}<div className="text-xs text-slate-500">{l.lenderType}</div></TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.originalPrincipal)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.amountReceived)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.totalPrincipalRepaid)}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">{fmt(l.outstandingPrincipal)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalInterestPaid)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalFeesPaid)}</TableCell>
                          <TableCell className={l.isOverdue ? "text-rose-600" : ""}>
                            {l.nextPaymentDate ? new Date(l.nextPaymentDate).toLocaleDateString() : "–"}
                          </TableCell>
                          <TableCell><Badge className={statusClass(l)}>{l.isOverdue ? "Overdue" : l.status}</Badge></TableCell>
                          <TableCell className="text-right">
                            {(l.status === "Active" || l.status === "Overdue") && l.outstandingPrincipal > 0 && (
                              <Button size="sm" variant="outline" onClick={() => openRepay(l)}>
                                <HandCoins className="h-3 w-3 mr-1" /> Repay
                              </Button>
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              }
            />
          )}

          {/* ---- repayment history ---------------------------------------- */}
          {!loading && payments.length > 0 && (
            <Card className="mt-4">
              <CardContent className="pt-6">
                <div className="mb-2 font-medium text-slate-700">Repayment history</div>
                <p className="text-xs text-slate-500 mb-3">
                  The total is what left the bank. Only the interest and fee columns reach the profit
                  and loss.
                </p>
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Payment #</TableHead>
                        <TableHead>Loan</TableHead>
                        <TableHead className="text-right">Principal</TableHead>
                        <TableHead className="text-right">Interest</TableHead>
                        <TableHead className="text-right">Fees</TableHead>
                        <TableHead className="text-right">Total paid</TableHead>
                        <TableHead>Account</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {payments.map((p) => (
                        <TableRow key={p.waterLoanPaymentId}>
                          <TableCell className="whitespace-nowrap">{new Date(p.paymentDate).toLocaleDateString()}</TableCell>
                          <TableCell className="font-medium">{p.paymentNumber ?? `#${p.waterLoanPaymentId}`}</TableCell>
                          <TableCell>{p.loanNumber ?? p.waterLoanId}<div className="text-xs text-slate-500">{p.lenderName}</div></TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(p.principalAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(p.interestAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(p.feeAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">
                            <span className={p.status === "Reversed" ? "line-through text-slate-400" : ""}>
                              {fmt(p.totalAmount)}
                            </span>
                          </TableCell>
                          <TableCell className="text-slate-500">{p.accountName ?? "–"}</TableCell>
                          <TableCell>
                            <Badge className={p.status === "Reversed"
                              ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
                              : "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"}>
                              {p.status}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-right">
                            {p.status === "Posted" && (
                              <Button size="sm" variant="outline"
                                      onClick={() => { setReversing(p); setReason("") }}>
                                <Undo2 className="h-3 w-3 mr-1" /> Reverse
                              </Button>
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </CardContent>
            </Card>
          )}
        </main>
      </div>

      {/* ---- new loan --------------------------------------------------- */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Banknote className="w-5 h-5 text-violet-600" /> Record a Loan
            </DialogTitle>
            <DialogDescription>
              The money arriving is cash in, but it is not revenue — the company borrowed it and still
              owes it.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title="Lender" color="purple">
              <FormField label="Lender *" full>
                <Input value={form.lenderName} placeholder="Who lent the money?"
                       onChange={(e) => setForm((f) => ({ ...f, lenderName: e.target.value }))} />
              </FormField>
              <FormField label="Lender type">
                <Select value={form.lenderType} onValueChange={(v) => setForm((f) => ({ ...f, lenderType: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{LENDER_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Account number">
                <Input value={form.accountNumber}
                       onChange={(e) => setForm((f) => ({ ...f, accountNumber: e.target.value }))} />
              </FormField>
            </FormSection>

            <FormSection title="The money" color="green">
              <FormField label="Amount borrowed *"
                         info="What the company OWES. This is what the debt starts at.">
                <NumberInput value={form.originalPrincipal} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, originalPrincipal: e.target.value }))} />
              </FormField>
              <FormField label="Amount received"
                         info="What actually ARRIVED. Less than the principal when the lender withheld a fee.">
                <NumberInput value={form.amountReceived} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, amountReceived: e.target.value }))} />
              </FormField>
              <FormField label="Account that received it" full>
                <Select value={form.waterCashAccountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, waterCashAccountId: v }))}>
                  <SelectTrigger><SelectValue placeholder="Where did the money land?" /></SelectTrigger>
                  <SelectContent>
                    {accounts.filter((a) => a.isActive).map((a) => (
                      <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
                        {a.accountName} — {fmt(a.currentBalance)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              {/* The gap is a real and common case, so the form explains it
                  rather than treating it as an error. */}
              {Number(form.originalPrincipal) > Number(form.amountReceived) && Number(form.amountReceived) > 0 && (
                <div className="col-span-full text-xs text-slate-500">
                  {fmt(Number(form.originalPrincipal) - Number(form.amountReceived))} less than the
                  principal — usually a fee the lender withheld. You will still owe the full{" "}
                  {fmt(Number(form.originalPrincipal))}. Record the fee as an expense yourself if you
                  want it in the accounts.
                </div>
              )}
            </FormSection>

            <FormSection title="Terms" color="blue">
              <FormField label="Start date *">
                <Input type="date" value={form.startDate}
                       onChange={(e) => setForm((f) => ({ ...f, startDate: e.target.value }))} />
              </FormField>
              <FormField label="Next payment due">
                <Input type="date" value={form.nextPaymentDate}
                       onChange={(e) => setForm((f) => ({ ...f, nextPaymentDate: e.target.value }))} />
              </FormField>
              <FormField label="Interest rate (%)">
                <NumberInput value={form.interestRate} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, interestRate: e.target.value }))} />
              </FormField>
              <FormField label="Interest type">
                <Select value={form.interestType} onValueChange={(v) => setForm((f) => ({ ...f, interestType: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{INTEREST_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Term (months)">
                <NumberInput value={form.termMonths} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, termMonths: e.target.value }))} />
              </FormField>
              <FormField label="Repayment frequency">
                <Select value={form.paymentFrequency} onValueChange={(v) => setForm((f) => ({ ...f, paymentFrequency: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{FREQUENCIES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Textarea rows={2} value={form.notes}
                          onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
              </FormField>
            </FormSection>
          </div>

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => setNewOpen(false)}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={saveLoan} disabled={saving}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</>
                      : <><Banknote className="w-4 h-4 mr-2" />Record Loan</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- repayment -------------------------------------------------- */}
      <Dialog open={!!repaying} onOpenChange={(o) => { if (!o) setRepaying(null) }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <HandCoins className="w-5 h-5 text-violet-600" /> Record a Repayment
            </DialogTitle>
            <DialogDescription>
              Split the payment into what it was actually for. The total is worked out for you —
              only the interest and the fees are a cost to the company.
            </DialogDescription>
          </DialogHeader>

          {repaying && (
            <div className="space-y-4">
              <FormSection title="Loan" color="slate" columns={1}>
                <div className="text-sm">
                  <div className="font-medium">
                    {repaying.loanNumber ?? "#" + repaying.waterLoanId} · {repaying.lenderName}
                  </div>
                  <div className="text-slate-600 mt-1">Still owed {fmt(repaying.outstandingPrincipal)}</div>
                </div>
              </FormSection>

              <FormSection title="What the payment is for" color="purple">
                <FormField label="Principal" hint="Off the debt. Not an expense.">
                  <NumberInput value={pay.principalAmount} min={0}
                               onChange={(e) => setPay((q) => ({ ...q, principalAmount: e.target.value }))} />
                </FormField>
                <FormField label="Interest" hint="A cost. Reaches the P&L.">
                  <NumberInput value={pay.interestAmount} min={0}
                               onChange={(e) => setPay((q) => ({ ...q, interestAmount: e.target.value }))} />
                </FormField>
                <FormField label="Fees" hint="Also a cost.">
                  <NumberInput value={pay.feeAmount} min={0}
                               onChange={(e) => setPay((q) => ({ ...q, feeAmount: e.target.value }))} />
                </FormField>
                <FormField label="Other">
                  <NumberInput value={pay.otherAmount} min={0}
                               onChange={(e) => setPay((q) => ({ ...q, otherAmount: e.target.value }))} />
                </FormField>
              </FormSection>

              <FormSection title="What this does" color="slate" columns={1}>
                <div className="text-sm space-y-1">
                  <div className="flex items-center justify-between">
                    <span className="text-slate-500">Leaves the account</span>
                    <span className="font-semibold tabular-nums">{fmt(payTotal)}</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-slate-500">Of which a cost</span>
                    <span className="tabular-nums text-amber-700">{fmt(costOfBorrowing)}</span>
                  </div>
                  <div className="flex items-center justify-between border-t pt-1">
                    <span className="text-slate-500">Debt after</span>
                    <span className="tabular-nums">
                      <span className="text-slate-400">{fmt(repaying.outstandingPrincipal)}</span>
                      {" → "}
                      <span className="font-medium">{fmt(Math.max(outstandingAfter, 0))}</span>
                    </span>
                  </div>
                  {outstandingAfter === 0 && principal > 0 && (
                    <p className="text-emerald-700 text-xs pt-1">This clears the loan.</p>
                  )}
                  {outstandingAfter < 0 && (
                    <p className="text-rose-600 text-xs pt-1">
                      That is more principal than is still owed.
                    </p>
                  )}
                  {payWouldOverdraw && (
                    <p className="text-rose-600 text-xs pt-1">
                      The account does not hold this much and cannot go negative.
                    </p>
                  )}
                </div>
              </FormSection>

              <FormSection title="Payment details" color="blue">
                <FormField label="Paid from *" full>
                  <Select value={pay.waterCashAccountId}
                          onValueChange={(v) => setPay((q) => ({ ...q, waterCashAccountId: v }))}>
                    <SelectTrigger><SelectValue placeholder="Which account?" /></SelectTrigger>
                    <SelectContent>
                      {accounts.filter((a) => a.isActive).map((a) => (
                        <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
                          {a.accountName} — {fmt(a.currentBalance)}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Date">
                  <Input type="date" value={pay.paymentDate}
                         onChange={(e) => setPay((q) => ({ ...q, paymentDate: e.target.value }))} />
                </FormField>
                <FormField label="Next payment due">
                  <Input type="date" value={pay.nextPaymentDate}
                         onChange={(e) => setPay((q) => ({ ...q, nextPaymentDate: e.target.value }))} />
                </FormField>
                <FormField label="Method">
                  <Select value={pay.paymentMethod} onValueChange={(v) => setPay((q) => ({ ...q, paymentMethod: v }))}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Reference">
                  <Input value={pay.referenceNumber}
                         onChange={(e) => setPay((q) => ({ ...q, referenceNumber: e.target.value }))} />
                </FormField>
                <FormField label="Notes" full>
                  <Textarea rows={2} value={pay.notes}
                            onChange={(e) => setPay((q) => ({ ...q, notes: e.target.value }))} />
                </FormField>
              </FormSection>
            </div>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => setRepaying(null)}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={savePayment}
                    disabled={saving || payTotal <= 0 || outstandingAfter < 0 || payWouldOverdraw}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</>
                      : <><HandCoins className="w-4 h-4 mr-2" />Record {fmt(payTotal)}</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- reverse ---------------------------------------------------- */}
      <Dialog open={!!reversing} onOpenChange={(o) => { if (!o) { setReversing(null); setReason("") } }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Undo2 className="w-5 h-5 text-amber-600" /> Reverse Repayment
            </DialogTitle>
            <DialogDescription>
              The debt goes back up, the cash returns, and the interest and fee costs are cancelled.
              Every original row stays on the record.
            </DialogDescription>
          </DialogHeader>

          {reversing && (
            <div className="space-y-4">
              <FormSection title="Repayment being reversed" color="slate" columns={1}>
                <div className="text-sm">
                  <div className="font-medium">{reversing.paymentNumber ?? "#" + reversing.waterLoanPaymentId}</div>
                  <div className="mt-1">
                    {fmt(reversing.totalAmount)} on {new Date(reversing.paymentDate).toLocaleDateString()}
                  </div>
                  <div className="text-xs text-slate-500 mt-1">
                    {fmt(reversing.principalAmount)} principal · {fmt(reversing.interestAmount)} interest ·{" "}
                    {fmt(reversing.feeAmount)} fees
                  </div>
                </div>
              </FormSection>

              <FormSection title="Why" color="amber" columns={1}>
                <FormField label="Reason *" hint="Written to the audit trail.">
                  <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)}
                            placeholder="Why is this being reversed?" />
                </FormField>
              </FormSection>
            </div>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => { setReversing(null); setReason("") }}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button variant="destructive" onClick={doReverse} disabled={saving}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Reversing...</>
                      : <><Undo2 className="w-4 h-4 mr-2" />Reverse</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function Stat({
  label, value, hint, accent = "slate",
}: {
  label: string
  value: string
  hint?: string
  accent?: "slate" | "emerald" | "amber" | "rose" | "violet"
}) {
  const colour = {
    slate: "text-slate-900",
    emerald: "text-emerald-700",
    amber: "text-amber-700",
    rose: "text-rose-600",
    violet: "text-violet-700",
  }[accent]
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs font-medium text-slate-500 uppercase tracking-wider truncate">{label}</p>
        <div className={`text-lg sm:text-xl font-bold mt-1 truncate ${colour}`}>{value}</div>
        {hint && <div className="text-xs text-slate-500 mt-0.5 truncate">{hint}</div>}
      </CardContent>
    </Card>
  )
}

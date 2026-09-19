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
//
// That dialog is now shared — components/cash/loan-repayment-dialog.tsx — so
// the same lesson is taught on /water-cash-flow, where people who think in
// money rather than in loans go looking for it.
//
// ROWS THAT CAME FROM CASH FLOW
// -----------------------------
// Migration 291 unions the legacy "Loan received" cash adjustments into the
// read, so borrowing that was only ever typed on /water-cash-flow finally shows
// up as debt here. Those rows carry source 'CashAdjustment', have no loan
// record behind them, and are read-only on this page — see isFromCashFlow.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
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
import { useFmt } from "@/lib/currency"
import {
  LoanRepaymentDialog, isRepayableLoan, type RepayableLoanOption,
} from "@/components/cash/loan-repayment-dialog"
import {
  listWaterCashAccounts, listWaterLoans, getWaterLoanSummary, createWaterLoan,
  listWaterLoanPayments, recordWaterLoanRepayment, reverseWaterLoanPayment,
  type WaterCashAccount, type WaterLoan, type WaterLoanPayment, type WaterLoanSummary,
} from "@/lib/api/water"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const LENDER_TYPES = ["Bank", "FinancialInstitution", "Individual", "Owner", "FamilyFriend", "Supplier", "Other"]
const INTEREST_TYPES = ["Simple", "ReducingBalance", "Flat", "Unknown"]
const FREQUENCIES = ["Weekly", "BiWeekly", "Monthly", "Quarterly", "Custom"]
const STATUS_FILTERS = ["All", "Active", "PaidOff", "Draft", "Cancelled"] as const

function today() { return new Date().toISOString().slice(0, 10) }

// A "Loan received" recorded on the Cash / Cash Flow page (migration 291).
// There is no loan record behind it, so every action on this page — repay,
// reverse, cancel, the repayment history — needs a row that does not exist.
// The Cash Flow page owns it and is where it is edited.
const isFromCashFlow = (l: WaterLoan) => l.source === "CashAdjustment"

// A real loan can now arrive without a lender: the column is nullable and the
// old Cash Flow borrowings were backfilled blank. "–" would read as "nothing to
// say about this"; these rows are the opposite — there IS something to say and
// nobody has said it yet, so name the gap.
const lenderCell = (l: WaterLoan) => {
  if (isFromCashFlow(l)) return "Loan received"
  const name = (l.lenderName ?? "").trim()
  return name || <span className="italic text-slate-400">Lender not recorded</span>
}

// What the shared repayment dialog needs to know about a loan. Repayability is
// decided by isRepayableLoan on the other side of this, so the Repay buttons
// here and the picker on /water-cash-flow can never disagree about which rows
// have a loan record behind them.
const toLoanOption = (l: WaterLoan): RepayableLoanOption => ({
  loanId: l.waterLoanId,
  loanNumber: l.loanNumber,
  lenderName: l.lenderName,
  outstandingPrincipal: l.outstandingPrincipal,
  status: l.status,
  source: l.source,
  defaultAccountId: l.waterCashAccountId ?? null,
})

// Keyed on source + id: a Cash-Flow row carries waterLoanId 0, and the two id
// spaces overlap anyway. The fallbacks keep keys unique against a server that
// has not had 291 applied yet, where neither column comes back.
const rowKey = (l: WaterLoan) => `${l.source ?? "Loan"}:${l.sourceId ?? l.waterLoanId}`

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

  // The repayment dialog owns the split, the total and the overdraw guard now.
  // See components/cash/loan-repayment-dialog.tsx.
  const repayAccounts = useMemo(
    () => accounts.map((a) => ({
      accountId: a.waterCashAccountId,
      accountName: a.accountName,
      currentBalance: a.currentBalance,
      allowNegativeBalance: a.allowNegativeBalance,
      isActive: a.isActive,
    })),
    [accounts],
  )

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
    // Belt and braces: the button is hidden on these rows, because there is no
    // loan record to post a repayment against.
    if (isFromCashFlow(l)) return
    setRepaying(l)
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
                  value={summary?.nextPaymentDate ? fmtDateTime(summary.nextPaymentDate) : "—"}
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
              defaultOpen
              striped
              items={pg.pageItems}
              getKey={rowKey}
              primary={(l) => (
                <>{l.loanNumber ?? `#${l.waterLoanId}`} · {lenderCell(l)}</>
              )}
              secondary={(l) => (
                <>
                  <span>{fmtDateTime(l.startDate, l)}</span>
                  <span>·</span>
                  <span className="text-xs">
                    {isFromCashFlow(l) ? "Recorded on Cash Flow" : l.lenderType}
                  </span>
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
                { label: "Next payment", value: l.nextPaymentDate ? fmtDateTime(l.nextPaymentDate) : "–" },
                { label: "Repayments", value: String(l.paymentCount) },
              ]}
              actions={(l) => (
                <>
                  {/* Recorded on the Cash Flow page, so it is edited and deleted
                      there. Repaying from here would need a loan record that
                      does not exist. */}
                  {isRepayableLoan(toLoanOption(l)) && (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openRepay(l)}>
                      <HandCoins className="h-4 w-4 mr-1" /> Repay
                    </Button>
                  )}
                  {isFromCashFlow(l) && (
                    <Link href="/water-cash-flow"
                          className="basis-full text-[11px] text-slate-500 underline underline-offset-2">
                      Recorded on Cash Flow — edit the amount there.
                    </Link>
                  )}
                </>
              )}
              pagination={pg.paginationProps}
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
                        <TableRow key={rowKey(l)}>
                          <TableCell className="font-medium">
                            {l.loanNumber ?? `#${l.waterLoanId}`}
                            {isFromCashFlow(l) && (
                              <div className="text-[11px] font-normal text-slate-500">
                                Recorded on Cash Flow
                              </div>
                            )}
                          </TableCell>
                          <TableCell>
                            {lenderCell(l)}
                            <div className="text-xs text-slate-500">
                              {isFromCashFlow(l) ? "No lender recorded" : l.lenderType}
                            </div>
                          </TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.originalPrincipal)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.amountReceived)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.totalPrincipalRepaid)}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">{fmt(l.outstandingPrincipal)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalInterestPaid)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalFeesPaid)}</TableCell>
                          <TableCell className={l.isOverdue ? "text-rose-600" : ""}>
                            {l.nextPaymentDate ? fmtDateTime(l.nextPaymentDate) : "–"}
                          </TableCell>
                          <TableCell><Badge className={statusClass(l)}>{l.isOverdue ? "Overdue" : l.status}</Badge></TableCell>
                          <TableCell className="text-right">
                            {isRepayableLoan(toLoanOption(l)) && (
                              <Button size="sm" variant="outline" onClick={() => openRepay(l)}>
                                <HandCoins className="h-3 w-3 mr-1" /> Repay
                              </Button>
                            )}
                            {/* Repaying, reversing and cancelling all need a loan
                                record. This row is a cash adjustment, and the
                                Cash Flow page is where it is edited. */}
                            {isFromCashFlow(l) && (
                              <div className="flex items-center justify-end gap-2">
                                <Link href="/water-cash-flow"
                                      className="text-[11px] text-slate-500 underline underline-offset-2 hover:text-slate-700">
                                  Cash Flow
                                </Link>
                              </div>
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
                          <TableCell className="whitespace-nowrap">{fmtDateTime(p.paymentDate, p)}</TableCell>
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

      {/* ---- repayment --------------------------------------------------
          The loan is already chosen here — the user clicked Repay on a row —
          so the dialog opens straight on the split. /water-cash-flow passes a
          list instead and gets a picker. */}
      <LoanRepaymentDialog
        open={!!repaying}
        onOpenChange={(o) => { if (!o) setRepaying(null) }}
        accounts={repayAccounts}
        fmtMoney={fmt}
        loan={repaying ? toLoanOption(repaying) : null}
        entityLabel="company"
        onSubmit={async (input) => {
          await recordWaterLoanRepayment(input.loanId, {
            waterCashAccountId: input.accountId,
            principalAmount: input.principalAmount,
            interestAmount: input.interestAmount,
            feeAmount: input.feeAmount,
            otherAmount: input.otherAmount,
            paymentDate: input.paymentDate,
            paymentMethod: input.paymentMethod,
            referenceNumber: input.referenceNumber,
            notes: input.notes,
            nextPaymentDate: input.nextPaymentDate,
          })
        }}
        onDone={() => { setRepaying(null); void load() }}
      />

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
                    {fmt(reversing.totalAmount)} on {fmtDateTime(reversing.paymentDate, reversing)}
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

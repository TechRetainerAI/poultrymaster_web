"use client"

// Hotel Loans (Financing) — Poultry's /poultry-loans, word for word, in violet.
//
// Who lent the hotel money, how much is still owed, and what each repayment was
// actually made of. A repayment is not one number: principal is the hotel
// swapping cash for a smaller debt, only interest and fees are a cost. The
// shared repayment dialog (components/cash/loan-repayment-dialog.tsx) asks for
// the parts and shows the total. Migration 331 moves the cash once, for the
// total, and the P&L reads interest and fees into "Depreciation & Financing".

import { Fragment, useEffect, useMemo, useState } from "react"
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
import { Banknote, ChevronDown, ChevronRight, HandCoins, Loader2, Plus, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import {
  LoanRepaymentDialog, isRepayableLoan, type RepayableLoanOption,
} from "@/components/cash/loan-repayment-dialog"
import {
  listHotelMoneyAccounts, listHotelLoans, getHotelLoanSummary, createHotelLoan,
  listHotelLoanPayments, recordHotelLoanRepayment, reverseHotelLoanPayment,
  type HotelMoneyAccount, type HotelLoan, type HotelLoanPayment, type HotelLoanSummary,
} from "@/lib/api/hotel-money"

const LENDER_TYPES = ["Bank", "FinancialInstitution", "Individual", "Owner", "FamilyFriend", "Supplier", "Other"]
const INTEREST_TYPES = ["Simple", "ReducingBalance", "Flat", "Unknown"]
const FREQUENCIES = ["Weekly", "BiWeekly", "Monthly", "Quarterly", "Custom"]
const STATUS_FILTERS = ["All", "Active", "PaidOff", "Cancelled"] as const

function today() { return new Date().toISOString().slice(0, 10) }

const toLoanOption = (l: HotelLoan): RepayableLoanOption => ({
  loanId: l.hotelLoanId,
  loanNumber: l.loanNumber,
  lenderName: l.lenderName,
  outstandingPrincipal: l.outstandingPrincipal,
  status: l.status,
  source: "Loan",
  defaultAccountId: l.hotelCashAccountId ?? null,
})

function statusClass(l: HotelLoan) {
  if (l.status === "PaidOff") return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
  if (l.status === "Cancelled") return "bg-slate-100 text-slate-700 hover:bg-slate-100"
  if (l.isOverdue) return "bg-rose-100 text-rose-800 hover:bg-rose-100"
  return "bg-amber-100 text-amber-800 hover:bg-amber-100"
}

/** One loan's repayments, for the expanded desktop row. */
function LoanRepaymentTable({ payments, fmt, onReverse }: {
  payments: HotelLoanPayment[]
  fmt: (n: number) => string
  onReverse: (p: HotelLoanPayment) => void
}) {
  if (payments.length === 0) {
    return (
      <div className="px-4 py-3 text-sm text-slate-500">
        No repayments recorded against this loan yet.
      </div>
    )
  }
  return (
    <div className="px-4 py-3">
      <p className="mb-2 text-xs text-slate-500">The total is what left the bank. Only the interest and the fees reach the profit and loss.</p>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Payment #</TableHead>
              <TableHead className="text-right">Principal</TableHead>
              <TableHead className="text-right">Interest</TableHead>
              <TableHead className="text-right">Fees</TableHead>
              <TableHead className="text-right">Total paid</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Status</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {payments.map((p) => (
              <TableRow key={p.hotelLoanPaymentId} className="bg-white">
                <TableCell className="whitespace-nowrap">{fmtDateTime(p.paymentDate, p)}</TableCell>
                <TableCell className="font-medium">{p.paymentNumber ?? `#${p.hotelLoanPaymentId}`}</TableCell>
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
                    <Button size="sm" variant="outline" onClick={() => onReverse(p)}>
                      <Undo2 className="h-3 w-3 mr-1" /> Reverse
                    </Button>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}

/** The same repayments for the opened card, one stacked block each. */
function LoanRepaymentList({ payments, fmt, onReverse }: {
  payments: HotelLoanPayment[]
  fmt: (n: number) => string
  onReverse: (p: HotelLoanPayment) => void
}) {
  if (payments.length === 0) {
    return <div className="text-xs text-slate-500">No repayments recorded against this loan yet.</div>
  }
  return (
    <div className="space-y-2">
      <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
        Repayment history
      </div>
      <p className="text-[11px] text-slate-500">The total is what left the bank. Only the interest and the fees reach the profit and loss.</p>
      {payments.map((p) => (
        <div key={p.hotelLoanPaymentId} className="rounded-lg border border-slate-200 bg-white px-3 py-2">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="font-medium text-slate-900">
                {fmtDateTime(p.paymentDate, p)}
              </div>
              <div className="text-[11px] text-slate-500 truncate">
                {p.paymentNumber ?? `#${p.hotelLoanPaymentId}`}
                {p.accountName ? ` · ${p.accountName}` : ""}
              </div>
            </div>
            <div className="text-right shrink-0">
              <div className={cn("font-semibold tabular-nums",
                                 p.status === "Reversed" ? "text-slate-400 line-through" : "text-slate-900")}>
                {fmt(p.totalAmount)}
              </div>
              <Badge className={cn("mt-0.5 text-[10px]", p.status === "Reversed"
                ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
                : "bg-emerald-100 text-emerald-800 hover:bg-emerald-100")}>
                {p.status}
              </Badge>
            </div>
          </div>
          <div className="mt-2 grid grid-cols-3 gap-2 text-[11px]">
            <div>
              <div className="text-slate-500">Principal</div>
              <div className="font-medium tabular-nums">{fmt(p.principalAmount)}</div>
            </div>
            <div>
              <div className="text-slate-500">Interest</div>
              <div className="font-medium tabular-nums text-amber-700">{fmt(p.interestAmount)}</div>
            </div>
            <div>
              <div className="text-slate-500">Fees</div>
              <div className="font-medium tabular-nums text-amber-700">{fmt(p.feeAmount)}</div>
            </div>
          </div>
          {p.status === "Posted" && (
            <Button size="sm" variant="outline" className="mt-2 h-9 w-full"
                    onClick={() => onReverse(p)}>
              <Undo2 className="h-3 w-3 mr-1" /> Reverse
            </Button>
          )}
        </div>
      ))}
    </div>
  )
}

export default function HotelLoansPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [accounts, setAccounts] = useState<HotelMoneyAccount[]>([])
  const [loans, setLoans] = useState<HotelLoan[]>([])
  const [payments, setPayments] = useState<HotelLoanPayment[]>([])
  const [summary, setSummary] = useState<HotelLoanSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState<string>("All")

  const [newOpen, setNewOpen] = useState(false)
  const [form, setForm] = useState({
    lenderName: "", lenderType: "Bank", accountNumber: "",
    originalPrincipal: "0", amountReceived: "0", accountId: "",
    startDate: today(), interestRate: "", interestType: "ReducingBalance",
    termMonths: "", paymentFrequency: "Monthly", nextPaymentDate: "", notes: "",
  })

  const [repaying, setRepaying] = useState<HotelLoan | null>(null)
  const [reversing, setReversing] = useState<HotelLoanPayment | null>(null)
  const [reason, setReason] = useState("")

  const paymentsByLoan = useMemo(() => {
    const m = new Map<number, HotelLoanPayment[]>()
    for (const p of payments) {
      const list = m.get(p.hotelLoanId)
      if (list) list.push(p)
      else m.set(p.hotelLoanId, [p])
    }
    for (const list of m.values()) {
      list.sort((a, b) => (a.paymentDate < b.paymentDate ? 1 : a.paymentDate > b.paymentDate ? -1 : 0))
    }
    return m
  }, [payments])

  const [expanded, setExpanded] = useState<Set<number>>(new Set())
  const toggleExpanded = (id: number) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (!next.delete(id)) next.add(id)
      return next
    })

  const load = async () => {
    setLoading(true)
    try {
      const [accs, ls, ps, sum] = await Promise.all([
        listHotelMoneyAccounts(), listHotelLoans(), listHotelLoanPayments(), getHotelLoanSummary(),
      ])
      setAccounts(accs); setLoans(ls); setPayments(ps); setSummary(sum)
    } catch (e: any) {
      toast({ title: "Could not load loans", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(
    () => (status === "All" ? loans : loans.filter((l) => l.status === status)),
    [loans, status],
  )
  const pg = usePagination(visible)

  const repayAccounts = useMemo(
    () => accounts.map((a) => ({
      accountId: a.hotelCashAccountId,
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
    if (recv > 0 && !form.accountId) {
      toast({ title: "Which account received it?", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      await createHotelLoan({
        lenderName: form.lenderName.trim(),
        lenderType: form.lenderType,
        accountNumber: form.accountNumber.trim() || null,
        originalPrincipal: princ,
        amountReceived: recv,
        hotelCashAccountId: recv > 0 ? Number(form.accountId) : null,
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
          ? `${fmt(recv)} in. It is money in, not revenue — the hotel borrowed it.`
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
      await reverseHotelLoanPayment(reversing.hotelLoanPaymentId, reason.trim())
      toast({ title: "Repayment reversed", description: "The debt is back up and the cash returned." })
      setReversing(null); setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 min-w-0 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Banknote className="h-6 w-6 text-violet-600" /> Loans (Financing)
              </h1>
              <p className="text-sm text-slate-500 max-w-2xl">
                Money the hotel has borrowed. Borrowing is <strong>not income</strong> and repaying
                principal is <strong>not an expense</strong> — only the interest and the fees are the
                cost of borrowing.
              </p>
            </div>
            <Button onClick={() => setNewOpen(true)} className="h-11 sm:h-10 bg-violet-600 hover:bg-violet-700">
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
                      className={status === s ? "bg-violet-600 hover:bg-violet-700" : undefined}
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
              getKey={(l) => l.hotelLoanId}
              primary={(l) => (
                <>{l.loanNumber ?? `#${l.hotelLoanId}`} · {l.lenderName}</>
              )}
              secondary={(l) => (
                <>
                  <span>{fmtDateTime(l.startDate, l)}</span>
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
                { label: "Next payment", value: l.nextPaymentDate ? fmtDateTime(l.nextPaymentDate) : "–" },
                { label: "Repayments", value: String(l.paymentCount) },
              ]}
              extra={(l) => (
                <LoanRepaymentList
                  payments={paymentsByLoan.get(l.hotelLoanId) ?? []}
                  fmt={fmt}
                  onReverse={(p) => { setReversing(p); setReason("") }}
                />
              )}
              actions={(l) => (
                <>
                  {isRepayableLoan(toLoanOption(l)) && (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => setRepaying(l)}>
                      <HandCoins className="h-4 w-4 mr-1" /> Repay
                    </Button>
                  )}
                </>
              )}
              pagination={{ ...pg.paginationProps, variant: "records" }}
              desktopTable={
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="w-8" />
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
                      {pg.pageItems.map((l) => {
                        const loanPayments = paymentsByLoan.get(l.hotelLoanId) ?? []
                        const open = expanded.has(l.hotelLoanId)
                        return (
                        <Fragment key={l.hotelLoanId}>
                        <TableRow className="cursor-pointer" onClick={() => toggleExpanded(l.hotelLoanId)}>
                          <TableCell className="px-1">
                            {open ? <ChevronDown className="w-4 h-4 text-slate-400" />
                                  : <ChevronRight className="w-4 h-4 text-slate-400" />}
                          </TableCell>
                          <TableCell className="font-medium">
                            {l.loanNumber ?? `#${l.hotelLoanId}`}
                            <div className="text-xs text-slate-500">
                              {loanPayments.length === 0
                                ? "no repayments"
                                : `${loanPayments.length} repayment${loanPayments.length === 1 ? "" : "s"}`}
                            </div>
                          </TableCell>
                          <TableCell>{l.lenderName}<div className="text-xs text-slate-500">{l.lenderType}</div></TableCell>
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
                              <Button size="sm" variant="outline"
                                      onClick={(e) => { e.stopPropagation(); setRepaying(l) }}>
                                <HandCoins className="h-3 w-3 mr-1" /> Repay
                              </Button>
                            )}
                          </TableCell>
                        </TableRow>
                        {open && (
                          <TableRow>
                            <TableCell colSpan={12} className="bg-slate-50 p-0">
                              <LoanRepaymentTable
                                payments={loanPayments}
                                fmt={fmt}
                                onReverse={(p) => { setReversing(p); setReason("") }}
                              />
                            </TableCell>
                          </TableRow>
                        )}
                        </Fragment>
                        )
                      })}
                    </TableBody>
                  </Table>
                </div>
              }
            />
          )}

        </main>
      </div>

      {/* ---- new loan --------------------------------------------------- */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Banknote className="w-5 h-5 text-violet-600" /> Record a Loan
            </DialogTitle>
            <DialogDescription>
              The money arriving is cash in, but it is not revenue — the hotel borrowed it and still
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
                         info="What the hotel OWES. This is what the debt starts at.">
                <NumberInput value={form.originalPrincipal} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, originalPrincipal: e.target.value }))} />
              </FormField>
              <FormField label="Amount received"
                         info="What actually ARRIVED. Less than the principal when the lender withheld a fee.">
                <NumberInput value={form.amountReceived} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, amountReceived: e.target.value }))} />
              </FormField>
              <FormField label="Account that received it" full>
                <Select value={form.accountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, accountId: v }))}>
                  <SelectTrigger><SelectValue placeholder="Where did the money land?" /></SelectTrigger>
                  <SelectContent>
                    {accounts.filter((a) => a.isActive).map((a) => (
                      <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>
                        {a.accountName} — {fmt(a.currentBalance)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
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
            <Button onClick={saveLoan} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</>
                      : <><Banknote className="w-4 h-4 mr-2" />Record Loan</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- repayment: the shared dialog, opened on the chosen loan ----- */}
      <LoanRepaymentDialog
        open={!!repaying}
        onOpenChange={(o) => { if (!o) setRepaying(null) }}
        accounts={repayAccounts}
        fmtMoney={fmt}
        loan={repaying ? toLoanOption(repaying) : null}
        entityLabel="hotel"
        onSubmit={async (input) => {
          await recordHotelLoanRepayment(input.loanId, {
            hotelCashAccountId: input.accountId,
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
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
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
                  <div className="font-medium">{reversing.paymentNumber ?? "#" + reversing.hotelLoanPaymentId}</div>
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

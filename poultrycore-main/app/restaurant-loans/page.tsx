"use client"

/**
 * Restaurant Loans — money the restaurant borrowed and its repayments.
 * Principal moves cash and reduces what is owed; interest and fees are costs
 * and appear on the Profit & Loss.
 * API: lib/api/restaurant-finance.ts (migration 323).
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Landmark, Plus, Wallet, Percent, AlertTriangle, ListOrdered, Ban, Undo2, HandCoins } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listCashAccounts, listLoans, listLoanPayments, createLoan, repayLoan, reverseLoanPayment, cancelLoan, todayIso,
  type CashAccount, type RestaurantLoan, type LoanPayment,
} from "@/lib/api/restaurant-finance"

interface LoanForm {
  lenderName: string
  principal: string
  amountReceived: string
  receivedTouched: boolean
  receivedAccountId: string
  loanDate: string
  interestRate: string
  dueDate: string
  notes: string
}

interface RepayForm {
  cashAccountId: string
  principal: string
  interest: string
  fees: string
  paymentDate: string
  notes: string
}

const blankLoan = (): LoanForm => ({
  lenderName: "", principal: "", amountReceived: "", receivedTouched: false, receivedAccountId: "",
  loanDate: todayIso(), interestRate: "", dueDate: "", notes: "",
})

const blankRepay = (): RepayForm => ({
  cashAccountId: "", principal: "", interest: "", fees: "", paymentDate: todayIso(), notes: "",
})

/** Parse a money string; blank counts as 0, garbage as NaN. */
function num(s: string): number {
  if (!s.trim()) return 0
  return parseFloat(s)
}

const round2 = (n: number) => Math.round(n * 100) / 100
const dateOnly = (s?: string | null) => (s ? s.split("T")[0] : "—")

function StatusBadge({ status }: { status: string }) {
  if (status === "Active") return <Badge variant="outline" className="text-xs bg-blue-50 text-blue-700 border-blue-200">Active</Badge>
  if (status === "PaidOff") return <Badge variant="outline" className="text-xs bg-green-50 text-green-700 border-green-200">Paid off</Badge>
  return <Badge variant="outline" className="text-xs bg-gray-100 text-gray-600 border-gray-200">{status}</Badge>
}

export default function RestaurantLoansPage() {
  const router = useRouter()
  const { toast } = useToast()
  const fmt = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const [loading, setLoading] = useState(true)
  const [loans, setLoans] = useState<RestaurantLoan[]>([])
  const [accounts, setAccounts] = useState<CashAccount[]>([])

  // New loan
  const [loanOpen, setLoanOpen] = useState(false)
  const [loanForm, setLoanForm] = useState<LoanForm>(blankLoan())
  const [savingLoan, setSavingLoan] = useState(false)

  // Repay
  const [repayLoanTarget, setRepayLoanTarget] = useState<RestaurantLoan | null>(null)
  const [repayForm, setRepayForm] = useState<RepayForm>(blankRepay())
  const [savingRepay, setSavingRepay] = useState(false)

  // Payments
  const [paymentsLoan, setPaymentsLoan] = useState<RestaurantLoan | null>(null)
  const [payments, setPayments] = useState<LoanPayment[]>([])
  const [paymentsLoading, setPaymentsLoading] = useState(false)

  // Reverse payment
  const [reversePayment, setReversePayment] = useState<LoanPayment | null>(null)
  const [reverseReason, setReverseReason] = useState("")
  const [reversing, setReversing] = useState(false)

  // Cancel loan
  const [cancelTarget, setCancelTarget] = useState<RestaurantLoan | null>(null)
  const [cancelReason, setCancelReason] = useState("")
  const [cancelling, setCancelling] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    try {
      const [ls, accs] = await Promise.all([listLoans(), listCashAccounts()])
      setLoans(ls ?? [])
      setAccounts((accs ?? []).filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Could not load loans", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [toast])

  useEffect(() => {
    if (!activeFarmId || !canView) { setLoading(false); return }
    void load()
  }, [activeFarmId, canView, load])

  const loadPayments = useCallback(async (loanId: number) => {
    setPaymentsLoading(true)
    try {
      setPayments((await listLoanPayments(loanId)) ?? [])
    } catch (e: any) {
      toast({ title: "Could not load payments", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setPaymentsLoading(false)
    }
  }, [toast])

  /* ---------- stats ---------- */
  const stats = useMemo(() => {
    const active = loans.filter((l) => l.status === "Active")
    const live = loans.filter((l) => l.status !== "Cancelled")
    return {
      outstanding: active.reduce((s, l) => s + (l.outstandingPrincipal ?? 0), 0),
      activeCount: active.length,
      costsPaid: live.reduce((s, l) => s + (l.interestPaid ?? 0) + (l.feesPaid ?? 0), 0),
      overdue: loans.filter((l) => l.isOverdue).length,
    }
  }, [loans])

  const accountLabel = (a: CashAccount) => `${a.name} — ${fmt(a.currentBalance)}`
  const defaultAccountId = () => (accounts.length === 1 ? String(accounts[0].cashAccountId) : "")

  /* ---------- new loan ---------- */
  const openNewLoan = () => {
    setLoanForm({ ...blankLoan(), receivedAccountId: defaultAccountId() })
    setLoanOpen(true)
  }

  const handleCreateLoan = async () => {
    const principal = num(loanForm.principal)
    const received = loanForm.receivedTouched ? num(loanForm.amountReceived) : principal
    const rate = loanForm.interestRate.trim() ? parseFloat(loanForm.interestRate) : null

    if (!loanForm.lenderName.trim()) {
      toast({ title: "Enter the lender", description: "Who lent the money?", variant: "destructive" }); return
    }
    if (!Number.isFinite(principal) || principal <= 0) {
      toast({ title: "Enter the loan amount", description: "The loan amount must be more than zero.", variant: "destructive" }); return
    }
    if (!Number.isFinite(received) || received < 0) {
      toast({ title: "Check the amount received", description: "It cannot be negative.", variant: "destructive" }); return
    }
    if (received > principal) {
      toast({ title: "Check the amount received", description: "You cannot receive more than the loan amount.", variant: "destructive" }); return
    }
    if (received > 0 && !loanForm.receivedAccountId) {
      toast({ title: "Pick an account", description: "Choose the account the money was received into.", variant: "destructive" }); return
    }
    if (rate !== null && (!Number.isFinite(rate) || rate < 0)) {
      toast({ title: "Check the interest rate", description: "Leave it blank or enter a positive number.", variant: "destructive" }); return
    }
    if (loanForm.loanDate && loanForm.loanDate > todayIso()) {
      toast({ title: "Date is in the future", description: "Pick today or an earlier loan date.", variant: "destructive" }); return
    }
    if (loanForm.dueDate && loanForm.loanDate && loanForm.dueDate < loanForm.loanDate) {
      toast({ title: "Check the due date", description: "The due date cannot be before the loan date.", variant: "destructive" }); return
    }

    try {
      setSavingLoan(true)
      await createLoan({
        lenderName: loanForm.lenderName.trim(),
        principal,
        amountReceived: received,
        receivedAccountId: received > 0 ? Number(loanForm.receivedAccountId) : null,
        loanDate: loanForm.loanDate || undefined,
        interestRate: rate,
        dueDate: loanForm.dueDate || null,
        notes: loanForm.notes.trim() || null,
      })
      toast({ title: "Loan recorded", description: received > 0 ? `${fmt(received)} added to the account.` : "Loan recorded." })
      setLoanOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Could not save the loan", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setSavingLoan(false)
    }
  }

  /* ---------- repay ---------- */
  const openRepay = (loan: RestaurantLoan) => {
    setRepayForm({ ...blankRepay(), cashAccountId: defaultAccountId() })
    setRepayLoanTarget(loan)
  }

  const repayPrincipal = num(repayForm.principal)
  const repayInterest = num(repayForm.interest)
  const repayFees = num(repayForm.fees)
  const repayTotal = round2((repayPrincipal || 0) + (repayInterest || 0) + (repayFees || 0))
  const outstandingAfter = repayLoanTarget ? round2(repayLoanTarget.outstandingPrincipal - (repayPrincipal || 0)) : 0

  const handleRepay = async () => {
    if (!repayLoanTarget) return
    if (!repayForm.cashAccountId) {
      toast({ title: "Pick an account", description: "Choose the account the payment comes from.", variant: "destructive" }); return
    }
    for (const [label, v] of [["Principal", repayPrincipal], ["Interest", repayInterest], ["Fees", repayFees]] as const) {
      if (!Number.isFinite(v) || v < 0) {
        toast({ title: `Check ${label.toLowerCase()}`, description: `${label} cannot be negative.`, variant: "destructive" }); return
      }
    }
    if (repayTotal <= 0) {
      toast({ title: "Enter an amount", description: "Enter the principal, interest or fees being paid.", variant: "destructive" }); return
    }
    if (repayPrincipal > round2(repayLoanTarget.outstandingPrincipal)) {
      toast({
        title: "Too much principal",
        description: `Only ${fmt(repayLoanTarget.outstandingPrincipal)} is still owed on this loan.`,
        variant: "destructive",
      }); return
    }
    if (repayForm.paymentDate && repayForm.paymentDate > todayIso()) {
      toast({ title: "Date is in the future", description: "Pick today or an earlier date.", variant: "destructive" }); return
    }
    try {
      setSavingRepay(true)
      await repayLoan(repayLoanTarget.loanId, {
        cashAccountId: Number(repayForm.cashAccountId),
        principal: repayPrincipal,
        interest: repayInterest,
        fees: repayFees,
        paymentDate: repayForm.paymentDate || undefined,
        notes: repayForm.notes.trim() || null,
      })
      toast({ title: "Repayment recorded", description: `${fmt(repayTotal)} paid to ${repayLoanTarget.lenderName}.` })
      setRepayLoanTarget(null)
      await load()
    } catch (e: any) {
      toast({ title: "Could not record the repayment", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setSavingRepay(false)
    }
  }

  /* ---------- payments ---------- */
  const openPayments = (loan: RestaurantLoan) => {
    setPayments([])
    setPaymentsLoan(loan)
    void loadPayments(loan.loanId)
  }

  const handleReversePayment = async () => {
    if (!reversePayment || !reverseReason.trim()) return
    try {
      setReversing(true)
      await reverseLoanPayment(reversePayment.loanPaymentId, reverseReason.trim())
      toast({ title: "Repayment reversed", description: "The money went back into the account." })
      const loanId = reversePayment.loanId
      setReversePayment(null)
      setReverseReason("")
      await Promise.all([loadPayments(loanId), load()])
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setReversing(false)
    }
  }

  // Keep the Payments dialog header in sync with the reloaded loan.
  const paymentsLoanLive = paymentsLoan ? loans.find((l) => l.loanId === paymentsLoan.loanId) ?? paymentsLoan : null

  /* ---------- cancel ---------- */
  const handleCancelLoan = async () => {
    if (!cancelTarget || !cancelReason.trim()) return
    try {
      setCancelling(true)
      await cancelLoan(cancelTarget.loanId, cancelReason.trim())
      toast({ title: "Loan cancelled", description: "The money received was taken back out of the account." })
      setCancelTarget(null)
      setCancelReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not cancel the loan", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setCancelling(false)
    }
  }

  if (loading) return <PageSkeleton statCards={4} listRows={5} />

  if (!canView) return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto">
            <Card><CardContent className="py-12 text-center text-gray-600">You do not have access to Loans.</CardContent></Card>
          </div>
        </main>
      </div>
    </div>
  )

  const loanPrincipalNum = num(loanForm.principal)
  const loanReceivedDisplay = loanForm.receivedTouched ? loanForm.amountReceived : loanForm.principal
  const loanReceivedNum = num(loanReceivedDisplay)
  const loanKeptUpfront = Number.isFinite(loanPrincipalNum) && Number.isFinite(loanReceivedNum) && loanReceivedNum < loanPrincipalNum
    ? round2(loanPrincipalNum - loanReceivedNum) : 0

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto space-y-6">
            <PageHeader icon={Landmark} title="Loans" subtitle="Money the restaurant borrowed and its repayments">
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={openNewLoan}>
                <Plus className="h-4 w-4 mr-2" /> New loan
              </Button>
            </PageHeader>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <StatCard label="Outstanding principal" value={fmt(stats.outstanding)} icon={Wallet} color="rose" />
              <StatCard label="Active loans" value={stats.activeCount} icon={Landmark} color="blue" />
              <StatCard label="Interest & fees paid" value={fmt(stats.costsPaid)} icon={Percent} color="amber" />
              <StatCard label="Overdue" value={stats.overdue} icon={AlertTriangle} color={stats.overdue > 0 ? "red" : "green"} />
            </div>

            {loans.length === 0 ? (
              <Card>
                <CardContent className="pt-6">
                  <EmptyState
                    icon={Landmark}
                    title="No loans recorded"
                    description="Record money the restaurant has borrowed so repayments are tracked"
                    actionLabel="New loan"
                    onAction={openNewLoan}
                  />
                </CardContent>
              </Card>
            ) : (
              <Card>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm min-w-[640px]">
                      <thead className="bg-gray-50 border-b">
                        <tr>
                          <th className="text-left p-3">Loan</th>
                          <th className="text-left p-3">Date</th>
                          <th className="text-right p-3">Principal</th>
                          <th className="text-right p-3">Outstanding</th>
                          <th className="text-right p-3">Repaid</th>
                          <th className="text-right p-3">Interest + fees</th>
                          <th className="text-left p-3">Due</th>
                          <th className="text-left p-3">Status</th>
                          <th className="text-right p-3">Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        {loans.map((l) => {
                          const cancelled = l.status === "Cancelled"
                          return (
                            <tr key={l.loanId} className={`border-b align-top ${cancelled ? "text-gray-400" : ""}`}>
                              <td className="p-3">
                                <div className="font-medium text-gray-900">{l.lenderName}</div>
                                <div className="font-mono text-xs text-muted-foreground">{l.loanNumber || `#${l.loanId}`}</div>
                                {cancelled && l.cancelReason && <div className="text-xs mt-1 max-w-[14rem]">{l.cancelReason}</div>}
                              </td>
                              <td className="p-3 text-xs whitespace-nowrap">{dateOnly(l.loanDate)}</td>
                              <td className="p-3 text-right whitespace-nowrap">{fmt(l.principal)}</td>
                              <td className="p-3 text-right whitespace-nowrap font-bold">{fmt(l.outstandingPrincipal)}</td>
                              <td className="p-3 text-right whitespace-nowrap">{fmt(l.principalRepaid)}</td>
                              <td className="p-3 text-right whitespace-nowrap">{fmt((l.interestPaid ?? 0) + (l.feesPaid ?? 0))}</td>
                              <td className="p-3 text-xs whitespace-nowrap">
                                <div>{dateOnly(l.dueDate)}</div>
                                {l.isOverdue && <Badge className="mt-1 text-xs bg-red-600 hover:bg-red-600 text-white">Overdue</Badge>}
                              </td>
                              <td className="p-3"><StatusBadge status={l.status} /></td>
                              <td className="p-3">
                                <div className="flex flex-wrap justify-end gap-2">
                                  {l.status === "Active" && (
                                    <Button size="sm" className="bg-rose-600 hover:bg-rose-700" onClick={() => openRepay(l)}>
                                      <HandCoins className="h-4 w-4 mr-1" /> Repay
                                    </Button>
                                  )}
                                  <Button size="sm" variant="outline" onClick={() => openPayments(l)}>
                                    <ListOrdered className="h-4 w-4 mr-1" /> Payments
                                  </Button>
                                  {/* Same rule as sprestaurant_loan_cancel: only with no live
                                      repayments. Reversed repayments are backed out of these
                                      totals, so they read zero again once all are reversed. */}
                                  {l.status === "Active" && l.principalRepaid + l.interestPaid + l.feesPaid === 0 && (
                                    <Button size="sm" variant="outline" className="text-red-600" onClick={() => { setCancelTarget(l); setCancelReason("") }}>
                                      <Ban className="h-4 w-4 mr-1" /> Cancel
                                    </Button>
                                  )}
                                </div>
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      {/* New loan dialog */}
      <Dialog open={loanOpen} onOpenChange={(o) => { if (!savingLoan) setLoanOpen(o) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>New loan</DialogTitle>
            <DialogDescription>Money the restaurant borrowed. It is not income.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Lender <span className="text-rose-500">*</span></Label>
              <Input
                className="h-10" placeholder="e.g. First Bank, a family member"
                value={loanForm.lenderName}
                onChange={(e) => setLoanForm((f) => ({ ...f, lenderName: e.target.value }))}
              />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Loan amount <span className="text-rose-500">*</span></Label>
                <Input
                  type="number" inputMode="decimal" step="0.01" min="0" className="h-10"
                  value={loanForm.principal}
                  onChange={(e) => setLoanForm((f) => ({ ...f, principal: e.target.value }))}
                />
              </div>
              <div className="space-y-1.5">
                <Label>Amount actually received</Label>
                <Input
                  type="number" inputMode="decimal" step="0.01" min="0" className="h-10"
                  value={loanReceivedDisplay}
                  onChange={(e) => setLoanForm((f) => ({ ...f, amountReceived: e.target.value, receivedTouched: true }))}
                />
              </div>
            </div>
            <p className="text-xs text-muted-foreground -mt-2">
              Lower if the lender kept fees upfront.
              {loanKeptUpfront > 0 && <> The lender kept {fmt(loanKeptUpfront)}.</>}
            </p>
            <div className="space-y-1.5">
              <Label>Received into {loanReceivedNum > 0 && <span className="text-rose-500">*</span>}</Label>
              <Select value={loanForm.receivedAccountId} onValueChange={(v) => setLoanForm((f) => ({ ...f, receivedAccountId: v }))}>
                <SelectTrigger className="h-10"><SelectValue placeholder="Select account" /></SelectTrigger>
                <SelectContent>
                  {accounts.map((a) => (
                    <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{accountLabel(a)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Loan date</Label>
                <Input
                  type="date" className="h-10" max={todayIso()}
                  value={loanForm.loanDate}
                  onChange={(e) => setLoanForm((f) => ({ ...f, loanDate: e.target.value }))}
                />
              </div>
              <div className="space-y-1.5">
                <Label>Due date</Label>
                <Input
                  type="date" className="h-10" min={loanForm.loanDate || undefined}
                  value={loanForm.dueDate}
                  onChange={(e) => setLoanForm((f) => ({ ...f, dueDate: e.target.value }))}
                />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Interest rate %</Label>
              <Input
                type="number" inputMode="decimal" step="0.01" min="0" className="h-10" placeholder="Optional, for your records"
                value={loanForm.interestRate}
                onChange={(e) => setLoanForm((f) => ({ ...f, interestRate: e.target.value }))}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Notes</Label>
              <Input
                className="h-10" placeholder="Optional"
                value={loanForm.notes}
                onChange={(e) => setLoanForm((f) => ({ ...f, notes: e.target.value }))}
              />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setLoanOpen(false)} disabled={savingLoan}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleCreateLoan} disabled={savingLoan}>
              {savingLoan ? "Saving..." : "Record loan"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Repay dialog */}
      <Dialog open={!!repayLoanTarget} onOpenChange={(o) => { if (!o && !savingRepay) setRepayLoanTarget(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Repay {repayLoanTarget?.lenderName}</DialogTitle>
            <DialogDescription>
              Principal reduces what you owe. Interest and fees are costs and appear on the Profit & Loss.
            </DialogDescription>
          </DialogHeader>
          {repayLoanTarget && (
            <div className="space-y-4">
              <div className="rounded-lg bg-gray-50 border px-3 py-2 text-sm flex justify-between">
                <span className="text-muted-foreground">Still owed</span>
                <span className="font-semibold">{fmt(repayLoanTarget.outstandingPrincipal)}</span>
              </div>
              <div className="space-y-1.5">
                <Label>Paid from <span className="text-rose-500">*</span></Label>
                <Select value={repayForm.cashAccountId} onValueChange={(v) => setRepayForm((f) => ({ ...f, cashAccountId: v }))}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="Select account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.map((a) => (
                      <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{accountLabel(a)}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label>Principal</Label>
                  <Input
                    type="number" inputMode="decimal" step="0.01" min="0" className="h-10"
                    max={repayLoanTarget.outstandingPrincipal}
                    value={repayForm.principal}
                    onChange={(e) => setRepayForm((f) => ({ ...f, principal: e.target.value }))}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Interest</Label>
                  <Input
                    type="number" inputMode="decimal" step="0.01" min="0" className="h-10"
                    value={repayForm.interest}
                    onChange={(e) => setRepayForm((f) => ({ ...f, interest: e.target.value }))}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Fees</Label>
                  <Input
                    type="number" inputMode="decimal" step="0.01" min="0" className="h-10"
                    value={repayForm.fees}
                    onChange={(e) => setRepayForm((f) => ({ ...f, fees: e.target.value }))}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Date</Label>
                  <Input
                    type="date" className="h-10" max={todayIso()}
                    value={repayForm.paymentDate}
                    onChange={(e) => setRepayForm((f) => ({ ...f, paymentDate: e.target.value }))}
                  />
                </div>
              </div>
              <div className="space-y-1.5">
                <Label>Notes</Label>
                <Input
                  className="h-10" placeholder="Optional"
                  value={repayForm.notes}
                  onChange={(e) => setRepayForm((f) => ({ ...f, notes: e.target.value }))}
                />
              </div>
              <div className="rounded-lg border px-3 py-2 text-sm space-y-1">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Total leaving the account</span>
                  <span className="font-semibold">{Number.isFinite(repayTotal) ? fmt(repayTotal) : "—"}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Outstanding after</span>
                  <span className={`font-semibold ${outstandingAfter < 0 ? "text-red-600" : ""}`}>
                    {Number.isFinite(outstandingAfter) ? fmt(outstandingAfter) : "—"}
                  </span>
                </div>
                {outstandingAfter < 0 && (
                  <p className="text-xs text-red-600">Principal is more than what is still owed.</p>
                )}
              </div>
            </div>
          )}
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setRepayLoanTarget(null)} disabled={savingRepay}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleRepay} disabled={savingRepay || outstandingAfter < 0}>
              {savingRepay ? "Saving..." : "Record repayment"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Payments dialog */}
      <Dialog open={!!paymentsLoan} onOpenChange={(o) => { if (!o) setPaymentsLoan(null) }}>
        <DialogContent className="sm:max-w-2xl max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Payments — {paymentsLoanLive?.lenderName}</DialogTitle>
            <DialogDescription>
              {paymentsLoanLive && `${paymentsLoanLive.loanNumber || `#${paymentsLoanLive.loanId}`} · outstanding ${fmt(paymentsLoanLive.outstandingPrincipal)}`}
            </DialogDescription>
          </DialogHeader>
          {paymentsLoading ? (
            <p className="py-8 text-center text-sm text-muted-foreground">Loading…</p>
          ) : payments.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">No repayments yet.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm min-w-[640px]">
                <thead className="bg-gray-50 border-b">
                  <tr>
                    <th className="text-left p-2">Date</th>
                    <th className="text-left p-2">Account</th>
                    <th className="text-right p-2">Principal</th>
                    <th className="text-right p-2">Interest</th>
                    <th className="text-right p-2">Fees</th>
                    <th className="text-right p-2">Total</th>
                    <th className="text-left p-2">Status</th>
                    <th className="text-right p-2"></th>
                  </tr>
                </thead>
                <tbody>
                  {payments.map((p) => {
                    const reversed = p.status !== "Posted"
                    return (
                      <tr key={p.loanPaymentId} className={`border-b align-top ${reversed ? "text-gray-400" : ""}`}>
                        <td className="p-2 text-xs whitespace-nowrap">{dateOnly(p.paymentDate)}</td>
                        <td className="p-2">{p.accountName}</td>
                        <td className="p-2 text-right whitespace-nowrap">{fmt(p.principalAmount)}</td>
                        <td className="p-2 text-right whitespace-nowrap">{fmt(p.interestAmount)}</td>
                        <td className="p-2 text-right whitespace-nowrap">{fmt(p.feeAmount)}</td>
                        <td className={`p-2 text-right whitespace-nowrap font-semibold ${reversed ? "line-through" : ""}`}>{fmt(p.totalAmount)}</td>
                        <td className="p-2">
                          <Badge variant="outline" className="text-xs">{p.status}</Badge>
                          {reversed && p.reversalReason && <p className="text-xs mt-1 max-w-[12rem]">{p.reversalReason}</p>}
                        </td>
                        <td className="p-2 text-right">
                          {!reversed && (
                            <Button size="sm" variant="outline" onClick={() => { setReversePayment(p); setReverseReason("") }}>
                              <Undo2 className="h-4 w-4 mr-1" /> Reverse
                            </Button>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setPaymentsLoan(null)}>Close</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reverse payment dialog */}
      <Dialog open={!!reversePayment} onOpenChange={(o) => { if (!o && !reversing) setReversePayment(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Reverse repayment</DialogTitle>
            <DialogDescription>
              {reversePayment && `${fmt(reversePayment.totalAmount)} goes back into ${reversePayment.accountName}, and ${fmt(reversePayment.principalAmount)} is owed again.`}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label>Reason <span className="text-rose-500">*</span></Label>
            <Input
              className="h-10" placeholder="Why is this being reversed?" autoFocus
              value={reverseReason}
              onChange={(e) => setReverseReason(e.target.value)}
            />
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReversePayment(null)} disabled={reversing}>Keep it</Button>
            <Button variant="destructive" onClick={handleReversePayment} disabled={reversing || !reverseReason.trim()}>
              {reversing ? "Reversing..." : "Reverse"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Cancel loan dialog */}
      <Dialog open={!!cancelTarget} onOpenChange={(o) => { if (!o && !cancelling) setCancelTarget(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Cancel loan from {cancelTarget?.lenderName}</DialogTitle>
            <DialogDescription>
              Only possible when the loan has no repayments; it returns the money received
              {cancelTarget && cancelTarget.amountReceived > 0 && cancelTarget.receivedAccountName
                ? ` (${fmt(cancelTarget.amountReceived)} comes back out of ${cancelTarget.receivedAccountName}).`
                : "."}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label>Reason <span className="text-rose-500">*</span></Label>
            <Input
              className="h-10" placeholder="Why is this loan being cancelled?" autoFocus
              value={cancelReason}
              onChange={(e) => setCancelReason(e.target.value)}
            />
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setCancelTarget(null)} disabled={cancelling}>Keep loan</Button>
            <Button variant="destructive" onClick={handleCancelLoan} disabled={cancelling || !cancelReason.trim()}>
              {cancelling ? "Cancelling..." : "Cancel loan"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

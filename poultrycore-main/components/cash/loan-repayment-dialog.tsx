"use client"

/**
 * Record a Repayment — shared by the Loans pages and the Cash Flow pages,
 * poultry and water alike.
 *
 * THE ONE THING THIS DIALOG MUST TEACH
 * ------------------------------------
 * A repayment is not one number. Paying 12,500 to the bank might be 10,000 of
 * principal, 2,000 of interest and 500 of fees — and only the last two are a
 * cost. The first is the business swapping cash for a smaller debt, and
 * counting it as an expense would make a profitable month look like a loss.
 *
 * So this dialog never asks for a total. It asks for the parts and SHOWS the
 * total, alongside what the debt will be afterwards. The split is the input;
 * the total is a consequence. That is the whole reason the dialog exists, and
 * it is why the four amount fields can never be collapsed into one.
 *
 * TWO WAYS IN
 * -----------
 *   Loans page      the user clicked Repay on a row. `loan` is passed and the
 *                   dialog opens straight on the amounts.
 *   Cash Flow page  the user started from the money, not the loan. `loans` is
 *                   passed and the dialog asks WHICH loan first.
 *
 * WHICH LOANS CAN BE REPAID
 * -------------------------
 * Migrations 290/291 union the legacy "Loan received" cash adjustments into the
 * loan read, so borrowing that was only ever typed on Cash Flow finally shows
 * up as debt. Those rows carry source 'CashAdjustment' and loan id 0: there is
 * no loan record behind them, and the repayment SP needs a real loan id. They
 * are therefore never offered here. `isRepayableLoan` is the single place that
 * decides, and the Loans pages use it for their Repay buttons too, so the
 * picker and the row buttons cannot disagree.
 *
 * Module-agnostic on purpose, the way CashAdjustmentDialog is: it takes its
 * accounts, its loans and its submit as props and knows nothing about poultry
 * or water.
 */

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { HandCoins, Loader2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { entryTimestamp } from "@/lib/utils/date-key"

const PAYMENT_METHODS = ["Cash", "BankTransfer", "MoMo", "Cheque", "Card", "Other"]

function today() { return new Date().toISOString().slice(0, 10) }

/** A cash account the repayment can be paid from. */
export type LoanRepaymentAccountOption = {
  accountId: number
  accountName: string
  currentBalance: number
  /** Overdraft allowed? Drives the "cannot go negative" guard. */
  allowNegativeBalance: boolean
  isActive: boolean
}

/** A loan, flattened out of PoultryLoan / WaterLoan by the calling page. */
export type RepayableLoanOption = {
  /** The real loan id. 0 on a Cash-Flow row, which is why those are excluded. */
  loanId: number
  loanNumber?: string | null
  lenderName?: string | null
  outstandingPrincipal: number
  status: string
  /** 'Loan' or 'CashAdjustment' (migrations 290/291). Absent = an older read. */
  source?: string | null
  /** Where the loan money landed; seeds "Paid from". */
  defaultAccountId?: number | null
}

/**
 * Can a repayment be posted against this row?
 *
 * A 'CashAdjustment' row cannot: it is a "Loan received" typed on Cash Flow,
 * there is no loan record behind it, and the repayment SP needs a real loan id.
 * The id check is belt and braces for the same rows, which carry loan id 0.
 */
export function isRepayableLoan(l: RepayableLoanOption): boolean {
  if ((l.source ?? "Loan") !== "Loan") return false
  if (!l.loanId) return false
  if (l.status !== "Active" && l.status !== "Overdue") return false
  return l.outstandingPrincipal > 0
}

export type LoanRepaymentSubmit = {
  loanId: number
  accountId: number
  principalAmount: number
  interestAmount: number
  feeAmount: number
  otherAmount: number
  /** Already stamped with a clock time when it is today. See entryTimestamp. */
  paymentDate: string | null
  paymentMethod: string | null
  referenceNumber: string | null
  notes: string | null
  nextPaymentDate: string | null
}

const blankPay = (accountId?: number | null) => ({
  principalAmount: "0", interestAmount: "0", feeAmount: "0", otherAmount: "0",
  accountId: accountId ? String(accountId) : "",
  paymentDate: today(), paymentMethod: "BankTransfer",
  referenceNumber: "", notes: "", nextPaymentDate: "",
})

export function LoanRepaymentDialog({
  open,
  onOpenChange,
  accounts,
  fmtMoney,
  loan,
  loans,
  entityLabel = "business",
  loansHref,
  onSubmit,
  onDone,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  accounts: LoanRepaymentAccountOption[]
  fmtMoney: (n: number) => string
  /** The loan being repaid, when the page already knows it (Loans pages). */
  loan?: RepayableLoanOption | null
  /** Everything on record, when it does not (Cash Flow pages). Filtered here. */
  loans?: RepayableLoanOption[]
  /** "farm" on poultry, "company" on water. Only used in the copy. */
  entityLabel?: string
  /** Where to send someone who has no repayable loan yet. */
  loansHref?: string
  onSubmit: (input: LoanRepaymentSubmit) => Promise<unknown>
  onDone?: () => void
}) {
  const { toast } = useToast()
  const [loanId, setLoanId] = useState("")
  const [pay, setPay] = useState(blankPay())
  const [saving, setSaving] = useState(false)

  const activeAccounts = useMemo(() => accounts.filter((a) => a.isActive), [accounts])

  // Guarded even when the page hands one over: the Loans pages hide Repay on
  // Cash-Flow rows, and this makes that impossible to get wrong from elsewhere.
  const preselected = loan && isRepayableLoan(loan) ? loan : null
  const picking = !loan

  const repayable = useMemo(() => (loans ?? []).filter(isRepayableLoan), [loans])
  const hasCashFlowOnly =
    !!loans?.length && repayable.length === 0 &&
    loans.some((l) => (l.source ?? "Loan") === "CashAdjustment")

  const selected = preselected ?? repayable.find((l) => String(l.loanId) === loanId) ?? null

  useEffect(() => {
    if (!open) return
    // Nothing is auto-picked in the picker, even with a single loan: which debt
    // is being paid down is the user's statement, not ours to infer.
    setLoanId(preselected ? String(preselected.loanId) : "")
    setPay(blankPay(preselected?.defaultAccountId))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, preselected?.loanId])

  const chooseLoan = (v: string) => {
    setLoanId(v)
    const l = repayable.find((x) => String(x.loanId) === v)
    // A repayment usually leaves the account the money arrived in, so seed it —
    // but never overwrite an account the user has already chosen themselves.
    setPay((q) => ({
      ...q,
      accountId: q.accountId || (l?.defaultAccountId ? String(l.defaultAccountId) : ""),
    }))
  }

  // The split IS the input. The total is shown, never typed.
  const principal = Number(pay.principalAmount) || 0
  const interest = Number(pay.interestAmount) || 0
  const fee = Number(pay.feeAmount) || 0
  const other = Number(pay.otherAmount) || 0
  const payTotal = principal + interest + fee + other
  const costOfBorrowing = interest + fee
  const outstandingAfter = selected ? selected.outstandingPrincipal - principal : 0

  const balanceOf = (id: string) =>
    accounts.find((a) => String(a.accountId) === id)?.currentBalance ?? 0
  const allowsNegative = (id: string) =>
    accounts.find((a) => String(a.accountId) === id)?.allowNegativeBalance ?? false
  const payWouldOverdraw =
    !!pay.accountId && payTotal > 0 &&
    balanceOf(pay.accountId) - payTotal < 0 && !allowsNegative(pay.accountId)

  const save = async () => {
    if (!selected) { toast({ title: "Pick a loan", variant: "destructive" }); return }
    if (!pay.accountId) { toast({ title: "Pick a cash account", variant: "destructive" }); return }
    if (payTotal <= 0) { toast({ title: "Enter the repayment", variant: "destructive" }); return }
    if (principal > selected.outstandingPrincipal) {
      toast({ title: "Principal is more than is owed", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      await onSubmit({
        loanId: selected.loanId,
        accountId: Number(pay.accountId),
        principalAmount: principal,
        interestAmount: interest,
        feeAmount: fee,
        otherAmount: other,
        // Today gets a real clock time so the repayment sorts to the top of
        // cash flow and of the repayment history. See entryTimestamp.
        paymentDate: entryTimestamp(pay.paymentDate),
        paymentMethod: pay.paymentMethod || null,
        referenceNumber: pay.referenceNumber.trim() || null,
        notes: pay.notes.trim() || null,
        nextPaymentDate: pay.nextPaymentDate || null,
      })
      toast({
        title: "Repayment recorded",
        description: costOfBorrowing > 0
          ? `${fmtMoney(payTotal)} left the account; only ${fmtMoney(costOfBorrowing)} of it is a cost.`
          : `${fmtMoney(payTotal)} off the debt. None of it is an expense.`,
      })
      onOpenChange(false)
      onDone?.()
    } catch (e: any) {
      toast({
        title: "Could not record the repayment",
        description: e?.message ?? String(e), variant: "destructive",
      })
    } finally { setSaving(false) }
  }

  const loanLabel = (l: RepayableLoanOption) =>
    `${l.loanNumber ?? "#" + l.loanId} · ${l.lenderName ?? "–"}`

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <HandCoins className="w-5 h-5 text-violet-600" /> Record a Repayment
          </DialogTitle>
          <DialogDescription>
            Split the payment into what it was actually for. The total is worked out for you —
            only the interest and the fees are a cost to the {entityLabel}.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {/* ---- which loan ------------------------------------------------ */}
          <FormSection title="Loan" color="slate" columns={1}>
            {picking ? (
              repayable.length > 0 ? (
                <FormField label="Loan being repaid *">
                  <Select value={loanId} onValueChange={chooseLoan}>
                    <SelectTrigger><SelectValue placeholder="Which loan is this paying down?" /></SelectTrigger>
                    <SelectContent>
                      {repayable.map((l) => (
                        <SelectItem key={l.loanId} value={String(l.loanId)}>
                          {loanLabel(l)} — {fmtMoney(l.outstandingPrincipal)} owed
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
              ) : (
                // Not an empty dropdown. A business can have debt on record and
                // still have nothing repayable here, and the reason for that is
                // not guessable from a blank list.
                <div className="text-sm text-slate-600">
                  {hasCashFlowOnly ? (
                    <>
                      The borrowing on record was typed here as a <b>Loan received</b> adjustment.
                      There is no loan behind it, so there is no debt to post a repayment against
                      and no lender, rate or term to split a payment over.{" "}
                      {loansHref
                        ? <>Record it as a loan on the <Link href={loansHref} className="underline">Loans page</Link> first.</>
                        : <>Record it as a loan first.</>}
                    </>
                  ) : loans?.length ? (
                    <>Nothing is outstanding — every loan on record is paid off or cancelled.</>
                  ) : (
                    <>
                      No loans recorded yet.{" "}
                      {loansHref && <Link href={loansHref} className="underline">Record one first.</Link>}
                    </>
                  )}
                </div>
              )
            ) : selected ? (
              <div className="text-sm">
                <div className="font-medium">{loanLabel(selected)}</div>
                <div className="text-slate-600 mt-1">Still owed {fmtMoney(selected.outstandingPrincipal)}</div>
              </div>
            ) : (
              <div className="text-sm text-slate-600">
                This borrowing was recorded as a cash adjustment, not a loan, so there is nothing
                here to repay against.
              </div>
            )}
          </FormSection>

          {selected && (
            <>
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

              {/* The total is output, not input — this block is the consequence
                  of the split above, which is the point of the whole dialog. */}
              <FormSection title="What this does" color="slate" columns={1}>
                <div className="text-sm space-y-1">
                  <div className="flex items-center justify-between">
                    <span className="text-slate-500">Leaves the account</span>
                    <span className="font-semibold tabular-nums">{fmtMoney(payTotal)}</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-slate-500">Of which a cost</span>
                    <span className="tabular-nums text-amber-700">{fmtMoney(costOfBorrowing)}</span>
                  </div>
                  <div className="flex items-center justify-between border-t pt-1">
                    <span className="text-slate-500">Debt after</span>
                    <span className="tabular-nums">
                      <span className="text-slate-400">{fmtMoney(selected.outstandingPrincipal)}</span>
                      {" → "}
                      <span className="font-medium">{fmtMoney(Math.max(outstandingAfter, 0))}</span>
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
                  <Select value={pay.accountId}
                          onValueChange={(v) => setPay((q) => ({ ...q, accountId: v }))}>
                    <SelectTrigger><SelectValue placeholder="Which account?" /></SelectTrigger>
                    <SelectContent>
                      {activeAccounts.map((a) => (
                        <SelectItem key={a.accountId} value={String(a.accountId)}>
                          {a.accountName} — {fmtMoney(a.currentBalance)}
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
                  <Select value={pay.paymentMethod}
                          onValueChange={(v) => setPay((q) => ({ ...q, paymentMethod: v }))}>
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
            </>
          )}
        </div>

        <div className="flex gap-3 justify-end pt-2">
          <Button type="button" onClick={() => onOpenChange(false)} disabled={saving}
                  className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
          <Button onClick={save}
                  disabled={saving || !selected || payTotal <= 0 || outstandingAfter < 0 || payWouldOverdraw}>
            {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</>
                    : <><HandCoins className="w-4 h-4 mr-2" />Record {fmtMoney(payTotal)}</>}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

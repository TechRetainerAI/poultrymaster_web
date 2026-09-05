// Payment state for a single expense.
//
// Pure functions, no React and no API shapes, for the same reason
// lib/balances/allocate.ts is: the rules that decide whether a bill counts as
// paid, and what the form is allowed to submit, should be checkable on their own.
// The backend re-derives every one of these (migration 238 makes paymentstatus a
// GENERATED column, so it cannot drift from the amounts); this exists so the user
// finds out before they press the button.
//
// Money is handled in PESEWAS (integer minor units) throughout, for the reason
// spelled out in allocate.ts: 0.1 + 0.2 is 0.30000000000000004, and a form that
// shows two identical numbers and then refuses the submit is worse than useless.

import { toPesewas, fromPesewas } from "@/lib/balances/allocate"

/**
 * The four states an expense can be in.
 *
 * `NonCash` is not a payment state the user picks — it is what internal use
 * posts (migration 216) to record stock leaving with no money moving. It is
 * listed here because it comes back from the API and must never be offered as
 * something to pay.
 */
export type ExpensePaymentStatus = "Paid" | "PartiallyPaid" | "Unpaid" | "NonCash"

/** The three a person can actually choose on the expense form. */
export const SELECTABLE_PAYMENT_STATUSES = ["Paid", "PartiallyPaid", "Unpaid"] as const
export type SelectablePaymentStatus = (typeof SELECTABLE_PAYMENT_STATUSES)[number]

export const PAYMENT_STATUS_LABELS: Record<ExpensePaymentStatus, string> = {
  Paid: "Paid",
  PartiallyPaid: "Partially paid",
  Unpaid: "Unpaid",
  NonCash: "Non-cash",
}

/**
 * Derive the status from the amounts — the same CASE the SQL generated column
 * uses, in the same order.
 *
 * Order matters: NonCash wins outright, and "paid >= total" is tested before
 * "paid <= 0" so a zero-total row reads as Paid rather than Unpaid.
 */
export function derivePaymentStatus(
  total: number,
  paid: number,
  paymentMethod?: string | null,
): ExpensePaymentStatus {
  if ((paymentMethod ?? "").trim() === "NonCash") return "NonCash"
  const t = toPesewas(total)
  const p = toPesewas(paid)
  if (p >= t) return "Paid"
  if (p <= 0) return "Unpaid"
  return "PartiallyPaid"
}

/** What is still owed on an expense. Never negative. */
export function expenseBalance(total: number, paid: number): number {
  return fromPesewas(Math.max(toPesewas(total) - toPesewas(paid), 0))
}

/**
 * What the amount-paid field should hold for a chosen status.
 *
 * Returns `null` for Paid, and null is meaningful: it is what the API reads as
 * "paid in full", the shape every expense written before migration 238 has.
 * Sending 0 instead would silently turn a paid expense into a debt.
 */
export function amountPaidForStatus(
  status: SelectablePaymentStatus,
  total: number,
  enteredPaid: number,
): number | null {
  switch (status) {
    case "Paid":
      return null
    case "Unpaid":
      return 0
    case "PartiallyPaid":
      return fromPesewas(toPesewas(enteredPaid))
  }
}

/** A cash account and payment method are only required for money that moved. */
export function requiresCashAccount(status: SelectablePaymentStatus): boolean {
  return status === "Paid" || status === "PartiallyPaid"
}

export interface ExpensePaymentProblem {
  /** The form field to attach the message to, or null for the form as a whole. */
  field: "amount" | "amountPaid" | "cashAccountId" | "paymentMethod" | "supplierId" | null
  message: string
  /** A warning does not block the submit; a problem does. */
  severity: "error" | "warning"
}

export interface ExpensePaymentValidation {
  ok: boolean
  status: ExpensePaymentStatus
  amountPaid: number
  balance: number
  problems: ExpensePaymentProblem[]
  /** Errors only — what the submit button should key off. */
  errors: ExpensePaymentProblem[]
}

export interface ExpensePaymentDraft {
  total: number
  status: SelectablePaymentStatus
  /** Only read when status is PartiallyPaid. */
  amountPaid: number
  paymentMethod?: string | null
  cashAccountId?: number | null
  supplierId?: number | null
  /** Already settled by supplier payments. An edit may not go below this. */
  allocatedByPayments?: number
}

/**
 * Everything that would make the backend refuse this expense, checked up front.
 *
 * Mirrors spexpense_insert / spexpense_update (migration 238) rule for rule.
 * Keep the two in step: a rule enforced only here is a rule a direct API caller
 * walks straight past.
 */
export function validateExpensePayment(draft: ExpensePaymentDraft): ExpensePaymentValidation {
  const problems: ExpensePaymentProblem[] = []

  const totalP = toPesewas(draft.total)
  const allocatedP = toPesewas(draft.allocatedByPayments ?? 0)
  const resolvedPaid = amountPaidForStatus(draft.status, draft.total, draft.amountPaid)
  const paidP = resolvedPaid === null ? totalP : toPesewas(resolvedPaid)

  if (totalP <= 0) {
    problems.push({ field: "amount", message: "Enter an amount greater than 0.", severity: "error" })
  }

  if (paidP < 0) {
    problems.push({ field: "amountPaid", message: "Amount paid cannot be negative.", severity: "error" })
  }

  if (paidP > totalP && totalP > 0) {
    problems.push({
      field: "amountPaid",
      message: `Amount paid cannot exceed the ${fromPesewas(totalP).toFixed(2)} total.`,
      severity: "error",
    })
  }

  if (draft.status === "PartiallyPaid" && paidP <= 0) {
    problems.push({
      field: "amountPaid",
      message: "A partially paid expense must have something paid against it.",
      severity: "error",
    })
  }

  if (draft.status === "PartiallyPaid" && paidP >= totalP && totalP > 0) {
    problems.push({
      field: "amountPaid",
      message: 'That settles the whole bill — choose "Paid" instead.',
      severity: "error",
    })
  }

  // Editing must never contradict money that has already moved.
  if (allocatedP > 0 && totalP < allocatedP) {
    problems.push({
      field: "amount",
      message: `Supplier payments of ${fromPesewas(allocatedP).toFixed(2)} have been applied, so the total cannot go below that.`,
      severity: "error",
    })
  }
  if (allocatedP > 0 && paidP < allocatedP) {
    problems.push({
      field: "amountPaid",
      message: `Supplier payments of ${fromPesewas(allocatedP).toFixed(2)} have been applied, so amount paid cannot go below that.`,
      severity: "error",
    })
  }

  if (requiresCashAccount(draft.status)) {
    if (!draft.cashAccountId) {
      problems.push({
        field: "cashAccountId",
        message: "Choose the cash account this money came out of.",
        severity: "error",
      })
    }
    if (!(draft.paymentMethod ?? "").trim()) {
      problems.push({ field: "paymentMethod", message: "Choose a payment method.", severity: "error" })
    }
  }

  // Not an error: an unpaid expense with nobody to owe is a legitimate record,
  // it just cannot be chased. Saying so up front beats the user wondering later
  // why it never appeared on Supplier Balances.
  if (draft.status !== "Paid" && !draft.supplierId) {
    problems.push({
      field: "supplierId",
      message: "Select a supplier if you want this unpaid expense to appear in Supplier Balances.",
      severity: "warning",
    })
  }

  const errors = problems.filter((p) => p.severity === "error")

  return {
    ok: errors.length === 0,
    status: derivePaymentStatus(draft.total, fromPesewas(paidP), draft.paymentMethod),
    amountPaid: fromPesewas(paidP),
    balance: fromPesewas(Math.max(totalP - paidP, 0)),
    problems,
    errors,
  }
}

/**
 * Is this expense something a supplier payment can be applied to?
 *
 * Three conditions, all of which the SQL enforces too (fnpoultrypayables): it
 * must still owe something, it must not be a non-cash internal cost, and it must
 * name a supplier — otherwise there is no one to pay.
 */
export function isPayableExpense(e: {
  balance: number
  paymentStatus: ExpensePaymentStatus
  supplierId?: number | null
}): boolean {
  return e.balance > 0 && e.paymentStatus !== "NonCash" && !!e.supplierId
}

/**
 * Human label for where an expense came from.
 *
 * The raw values are the sourcetype strings the various posting SPs write. A
 * null means nobody wrote one, which in practice means it was typed in on the
 * Expenses page. An unrecognised value is returned unchanged rather than
 * dropped, so a workflow added later still reads sensibly.
 */
const SOURCE_LABELS: Record<string, string> = {
  PoultryRawMaterialPurchase: "Raw material purchase",
  MainFlockBatch: "Flock batch",
  Payroll: "Payroll",
  PoultryDelivery: "Delivery",
  PoultryDriverReturn: "Driver return",
  PoultryInternalUsage: "Internal use",
  WaterSupplierPayment: "Supplier payment",
  RawMaterialPurchase: "Raw material purchase",
  ProductionBatch: "Production batch",
}

export function expenseSourceLabel(sourceType: string | null | undefined): string {
  const s = (sourceType ?? "").trim()
  if (!s) return "Manual expense"
  return SOURCE_LABELS[s] ?? s
}

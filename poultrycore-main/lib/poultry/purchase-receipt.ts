/**
 * Receive Purchase (migration 345) — the arithmetic the form shows BEFORE it
 * saves, so the person receiving an invoice sees exactly what will be posted.
 *
 * Every rule here MIRRORS sppoultrypurchasereceipt_post; the database is the
 * authority and re-does all of it. The point of mirroring is that the preview
 * and the result never disagree — so if a rule changes there, change it here,
 * and the tests in purchase-receipt.test.ts pin the cases that matter:
 *
 *   - money is worked in whole pesewas, so 0.1 + 0.2 never shows as 0.30000004;
 *   - additional costs are spread by line VALUE (by QUANTITY when every line is
 *     free) and the last line takes the rounding pennies, so the lines always
 *     add up to the receipt total exactly;
 *   - a payment on receipt is applied to the lines in order, filling each;
 *   - only lines expensed at purchase book an expense now, and only for the
 *     part paid (the existing cash-basis rule, migration 207); lines expensed
 *     when used book nothing until consumption.
 */

import { EXPENSE_WHEN_CONSUMED } from "./cost-recognition"

/** To pesewas, half away from zero like Postgres round(numeric, 2). */
export function toCents(n: number): number {
  if (!Number.isFinite(n)) return 0
  const sign = n < 0 ? -1 : 1
  return sign * Math.round(Math.abs(n) * 100 + 1e-7)
}

export const fromCents = (c: number): number => c / 100

export interface ReceiptLineDraft {
  itemId: number | null
  /** Purchase units, as on the invoice. */
  quantity: number
  /** Invoice price per purchase unit. */
  unitCost: number
  /** Production units per purchase unit; null/0 means 1. */
  unitsPerPurchaseUnit?: number | null
  /** The item's effective method; anything but EXPENSE_WHEN_CONSUMED expenses as paid. */
  method?: string | null
}

export interface ReceiptLinePreview {
  subtotal: number
  allocatedAdditional: number
  total: number
  /** Landed cost per purchase unit — what FIFO/LIFO/HIFO will draw at. */
  landedUnitCost: number
  productionQuantity: number
  paidNow: number
  balance: number
  deferred: boolean
  /** Reaches the P&L today: the paid part of an expensed-as-paid line. */
  expenseNow: number
}

export type ReceiptPaymentStatus = "Paid" | "Part paid" | "Unpaid"

export interface ReceiptPreview {
  lines: ReceiptLinePreview[]
  subtotal: number
  additionalCosts: number
  total: number
  paid: number
  balance: number
  status: ReceiptPaymentStatus
  /** The posting matrix, as numbers. */
  inventoryIncrease: number
  cashOut: number
  payableIncrease: number
  expenseNow: number
  /** Cost held as inventory until the stock is used. */
  deferredToConsumption: number
  /** Expensed-as-paid cost that will reach the P&L when the balance is paid. */
  expenseWhenBalancePaid: number
}

/** Line value before additional costs, rounded like the database. */
export function lineSubtotalCents(quantity: number, unitCost: number): number {
  return toCents((quantity || 0) * (unitCost || 0))
}

/**
 * Spreads `additionalCents` over the lines: by value, or by quantity when the
 * whole invoice is free. The last line takes whatever rounding left over, so the
 * result always sums to exactly `additionalCents`.
 */
export function allocateAdditionalCents(
  lines: { subtotalCents: number; quantity: number }[],
  additionalCents: number,
): number[] {
  const out = lines.map(() => 0)
  if (lines.length === 0 || additionalCents <= 0) return out
  const valueTotal = lines.reduce((s, l) => s + l.subtotalCents, 0)
  const byValue = valueTotal > 0
  const weightTotal = byValue ? valueTotal : lines.reduce((s, l) => s + (l.quantity || 0), 0)
  let left = additionalCents
  lines.forEach((l, i) => {
    if (i === lines.length - 1) { out[i] = left; return }
    const w = byValue ? l.subtotalCents : (l.quantity || 0)
    const share = weightTotal > 0 ? Math.round((additionalCents * w) / weightTotal + 1e-9) : 0
    out[i] = Math.min(share, left)
    left -= out[i]
  })
  return out
}

/** Applies a payment to the lines in order, filling each before the next. */
export function allocatePaymentCents(lineTotalsCents: number[], paidCents: number): number[] {
  let left = Math.max(0, paidCents)
  return lineTotalsCents.map((t) => {
    if (t <= 0 || left <= 0) return 0
    const a = Math.min(left, t)
    left -= a
    return a
  })
}

export function paymentStatusFor(totalCents: number, paidCents: number): ReceiptPaymentStatus {
  if (paidCents <= 0) return "Unpaid"
  if (paidCents >= totalCents) return "Paid"
  return "Part paid"
}

export function previewReceipt(
  lines: ReceiptLineDraft[],
  additionalCosts: number,
  amountPaid: number,
): ReceiptPreview {
  const subs = lines.map((l) => lineSubtotalCents(l.quantity, l.unitCost))
  const addC = Math.max(0, toCents(additionalCosts))
  const alloc = allocateAdditionalCents(lines.map((l, i) => ({ subtotalCents: subs[i], quantity: l.quantity })), addC)
  const totals = subs.map((s, i) => s + alloc[i])
  const totalC = totals.reduce((a, b) => a + b, 0)
  const paidC = Math.min(Math.max(0, toCents(amountPaid)), totalC)
  const paidPer = allocatePaymentCents(totals, paidC)

  const previews: ReceiptLinePreview[] = lines.map((l, i) => {
    const deferred = l.method === EXPENSE_WHEN_CONSUMED
    const q = l.quantity || 0
    // The database keeps the invoice price when nothing was added, and rounds
    // the landed figure to the column's 2 dp otherwise.
    const landed = alloc[i] === 0 ? (l.unitCost || 0) : (q > 0 ? Math.round((totals[i] / q) + 1e-9) / 100 : 0)
    return {
      subtotal: fromCents(subs[i]),
      allocatedAdditional: fromCents(alloc[i]),
      total: fromCents(totals[i]),
      landedUnitCost: landed,
      productionQuantity: q * (l.unitsPerPurchaseUnit && l.unitsPerPurchaseUnit > 0 ? l.unitsPerPurchaseUnit : 1),
      paidNow: fromCents(paidPer[i]),
      balance: fromCents(totals[i] - paidPer[i]),
      deferred,
      expenseNow: deferred ? 0 : fromCents(paidPer[i]),
    }
  })

  const sumC = (f: (p: ReceiptLinePreview, i: number) => number) =>
    previews.reduce((s, p, i) => s + f(p, i), 0)

  return {
    lines: previews,
    subtotal: fromCents(subs.reduce((a, b) => a + b, 0)),
    additionalCosts: fromCents(addC),
    total: fromCents(totalC),
    paid: fromCents(paidC),
    balance: fromCents(totalC - paidC),
    status: paymentStatusFor(totalC, paidC),
    inventoryIncrease: fromCents(totalC),
    cashOut: fromCents(paidC),
    payableIncrease: fromCents(totalC - paidC),
    expenseNow: fromCents(sumC((p, i) => (p.deferred ? 0 : paidPer[i]))),
    deferredToConsumption: fromCents(sumC((p, i) => (p.deferred ? totals[i] : 0))),
    expenseWhenBalancePaid: fromCents(sumC((p, i) => (p.deferred ? 0 : totals[i] - paidPer[i]))),
  }
}

export interface ReceiptFormCheck {
  supplierChosen: boolean
  purchaseDate: string // yyyy-mm-dd
  today: string        // yyyy-mm-dd, the company's business date
  dueDate?: string | null
  lines: ReceiptLineDraft[]
  additionalCosts: number
  amountPaid: number
  cashAccountId?: number | null
}

/**
 * The same refusals the database makes, in the same words, so most mistakes are
 * caught before a round trip. Returns an empty list when the form may be saved.
 */
export function validateReceipt(f: ReceiptFormCheck): string[] {
  const errs: string[] = []
  if (!f.supplierChosen) errs.push("Choose the supplier you bought from.")
  if (f.purchaseDate && f.today && f.purchaseDate > f.today) {
    errs.push(`The purchase date (${f.purchaseDate}) is in the future. Goods can only be received on or before today (${f.today}).`)
  }
  if (f.lines.length === 0) errs.push("Add at least one item to the receipt.")
  if (f.lines.length > 50) errs.push(`A receipt can hold at most 50 lines (this one has ${f.lines.length}). Split the invoice into two receipts.`)
  f.lines.forEach((l, i) => {
    const n = i + 1
    if (!l.itemId) errs.push(`Line ${n}: choose an item.`)
    if (!(l.quantity > 0)) errs.push(`Line ${n}: quantity must be greater than 0.`)
    else if (Math.round(l.quantity * 1000) / 1000 !== l.quantity) errs.push(`Line ${n}: quantity can have at most 3 decimal places.`)
    if (l.unitCost < 0) errs.push(`Line ${n}: unit cost cannot be negative.`)
    if (l.unitsPerPurchaseUnit != null && l.unitsPerPurchaseUnit < 0) errs.push(`Line ${n}: units per purchase unit must be greater than 0.`)
  })
  if (f.additionalCosts < 0) errs.push("Additional costs cannot be negative.")
  const p = previewReceipt(f.lines, f.additionalCosts, 0)
  if (f.lines.length > 0 && p.total <= 0) errs.push("The receipt total must be greater than 0.")
  if (f.amountPaid < 0) errs.push("Amount paid cannot be negative.")
  if (toCents(f.amountPaid) > toCents(p.total) && p.total > 0) {
    errs.push(`Amount paid (${f.amountPaid.toFixed(2)}) is more than the purchase total (${p.total.toFixed(2)}).`)
  }
  if (f.amountPaid > 0 && !f.cashAccountId) errs.push("Choose the cash account the payment came from.")
  if (f.dueDate && f.purchaseDate && f.dueDate < f.purchaseDate && toCents(f.amountPaid) < toCents(p.total)) {
    errs.push(`The due date (${f.dueDate}) cannot be before the purchase date (${f.purchaseDate}).`)
  }
  return errs
}

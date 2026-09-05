// Allocation maths for the Customer Balances / Supplier Balances payment
// dialogs.
//
// Pure functions, deliberately free of React and of any module's API shapes, so
// the rules that decide where money lands can be reasoned about (and tested)
// on their own. The backend re-validates every one of these; this exists so the
// user finds out before they press the button, not after.
//
// Money is handled in PESEWAS (integer minor units) throughout. Allocating
// 0.1 + 0.2 in floating point gives 0.30000000000000004, which would fail the
// "allocated total must equal the payment" check the SQL enforces to two
// decimal places — and the user would see two identical numbers and a refusal.

/** A document that can receive part of a payment. */
export interface AllocatableDocument {
  /** "Sale" | "RawMaterialPurchase" | "FlockBatch" | "Purchase". */
  documentType: string
  documentId: number
  /** Oldest-first ordering key. */
  documentDate: string
  /** What is still owed on this document. */
  balance: number
}

/** documentType + documentId, as a map key. A bare id is not unique across types. */
export function docKey(d: Pick<AllocatableDocument, "documentType" | "documentId">): string {
  return `${d.documentType}:${d.documentId}`
}

/** Amounts to apply, keyed by docKey. */
export type AllocationMap = Record<string, number>

export const toPesewas = (amount: number): number => Math.round((Number(amount) || 0) * 100)
export const fromPesewas = (pesewas: number): number => Math.round(pesewas) / 100

/**
 * Spread `amount` across `documents`, oldest first, filling each to its balance
 * before moving on. The default the "Auto-allocate" button calls.
 *
 * A payment larger than the total open balance allocates everything it can and
 * leaves the rest unallocated — the caller surfaces that as the remaining
 * amount rather than silently overpaying a document, because overpayment is not
 * supported and the backend would reject it.
 */
export function autoAllocateOldestFirst(
  amount: number,
  documents: AllocatableDocument[],
): AllocationMap {
  let remaining = toPesewas(amount)
  const allocation: AllocationMap = {}
  if (remaining <= 0) return allocation

  const oldestFirst = [...documents].sort((a, b) => {
    const byDate = a.documentDate.localeCompare(b.documentDate)
    return byDate !== 0 ? byDate : a.documentId - b.documentId
  })

  for (const doc of oldestFirst) {
    if (remaining <= 0) break
    const balance = toPesewas(doc.balance)
    if (balance <= 0) continue
    const apply = Math.min(balance, remaining)
    allocation[docKey(doc)] = fromPesewas(apply)
    remaining -= apply
  }

  return allocation
}

export function totalAllocated(allocation: AllocationMap): number {
  const sum = Object.values(allocation).reduce((acc, v) => acc + toPesewas(v), 0)
  return fromPesewas(sum)
}

export function totalOpenBalance(documents: AllocatableDocument[]): number {
  return fromPesewas(documents.reduce((acc, d) => acc + toPesewas(d.balance), 0))
}

export interface AllocationProblem {
  /** docKey, or null for a problem with the payment as a whole. */
  key: string | null
  message: string
}

export interface AllocationValidation {
  ok: boolean
  allocated: number
  /** Payment amount minus what has been allocated. Negative means over-allocated. */
  unallocated: number
  problems: AllocationProblem[]
  /** Per-document over-allocation, for inline field errors. */
  overAllocated: Record<string, number>
}

/**
 * Everything that would make the backend refuse this payment, checked up front.
 *
 * Mirrors the validation in sppoultrycustomerpayment_record /
 * sppoultrysupplierpayment_record one for one. Keep the two in step: a rule
 * enforced only here is a rule a direct API caller can walk straight past.
 */
export function validateAllocations(
  amount: number,
  documents: AllocatableDocument[],
  allocation: AllocationMap,
  options: { cashAccountRequired?: boolean; cashAccountId?: number | null } = {},
): AllocationValidation {
  const problems: AllocationProblem[] = []
  const overAllocated: Record<string, number> = {}
  const byKey = new Map(documents.map((d) => [docKey(d), d]))

  const amountPesewas = toPesewas(amount)
  let allocatedPesewas = 0

  for (const [key, raw] of Object.entries(allocation)) {
    const value = toPesewas(raw)
    if (value === 0) continue
    allocatedPesewas += value

    if (value < 0) {
      problems.push({ key, message: "Amount to apply cannot be negative." })
      continue
    }

    const doc = byKey.get(key)
    if (!doc) {
      problems.push({ key, message: "This document is no longer open." })
      continue
    }

    const balance = toPesewas(doc.balance)
    if (value > balance) {
      overAllocated[key] = fromPesewas(value - balance)
      problems.push({
        key,
        message: `Cannot apply more than the ${fromPesewas(balance).toFixed(2)} still owed on this line.`,
      })
    }
  }

  if (amountPesewas <= 0) {
    problems.push({ key: null, message: "Enter a payment amount greater than 0." })
  }

  if (allocatedPesewas === 0 && amountPesewas > 0) {
    problems.push({ key: null, message: "Apply this payment to at least one line." })
  } else if (amountPesewas > 0 && allocatedPesewas !== amountPesewas) {
    // The one rule people trip over, so name both numbers rather than saying
    // "amounts do not match".
    problems.push({
      key: null,
      message:
        allocatedPesewas < amountPesewas
          ? `${fromPesewas(amountPesewas - allocatedPesewas).toFixed(2)} of this payment is still unallocated.`
          : `Applied amounts exceed the payment by ${fromPesewas(allocatedPesewas - amountPesewas).toFixed(2)}.`,
    })
  }

  if (options.cashAccountRequired && !options.cashAccountId) {
    problems.push({ key: null, message: "Choose the cash account this money moves through." })
  }

  return {
    ok: problems.length === 0,
    allocated: fromPesewas(allocatedPesewas),
    unallocated: fromPesewas(amountPesewas - allocatedPesewas),
    problems,
    overAllocated,
  }
}

/** Balance a document would be left with, for the "Balance After" column. */
export function balanceAfter(doc: AllocatableDocument, allocation: AllocationMap): number {
  const applied = toPesewas(allocation[docKey(doc)] ?? 0)
  return fromPesewas(toPesewas(doc.balance) - applied)
}

/**
 * An age that reads like an age.
 *
 * Opening balances are carried in as documents dated 1/1/2000, so their real age
 * renders as "9742d" — a number nobody can act on, and one that makes a genuinely
 * overdue 45-day bill sitting beside it look trivial. Anything older than five
 * years is called what it is instead.
 *
 * Five years, not one, because a real bill CAN go a year unpaid and that fact
 * should stay visible; nothing legitimately goes five.
 */
const OPENING_BALANCE_AGE_DAYS = 5 * 365

export function formatDocumentAge(ageDays: number): string {
  if (ageDays >= OPENING_BALANCE_AGE_DAYS) return "Opening balance"
  return `${Math.max(ageDays, 0)}d`
}

/** Aging bucket for a document, from its age in days. Matches the SQL's buckets. */
export function agingBucket(ageDays: number): "Current" | "1-30" | "31-60" | "61-90" | "90+" {
  if (ageDays <= 0) return "Current"
  if (ageDays <= 30) return "1-30"
  if (ageDays <= 60) return "31-60"
  if (ageDays <= 90) return "61-90"
  return "90+"
}

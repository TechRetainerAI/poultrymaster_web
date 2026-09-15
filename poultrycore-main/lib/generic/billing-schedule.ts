// Billing-period maths for Generic subscriptions.
//
// This deliberately mirrors fngenericnextbillingdate in migration 243, case for
// case. The SQL is the authority -- it is what actually raises invoices -- and
// this exists so a form can show "next bill: 4 Oct" without a round trip, and
// so a preview shown in the browser cannot disagree with what the server will
// bill. The first test asserts exactly that correspondence.
//
// Dates here are plain YYYY-MM-DD strings, never Date objects with a time.
// A billing period is a calendar fact; giving it a time zone is how you end up
// billing someone on the 31st in Accra and the 30th in London.

export type BillingFrequency =
  | "Weekly"
  | "Monthly"
  | "Quarterly"
  | "Termly"
  | "SemiAnnual"
  | "Annual"
  | "OneTime"

export const BILLING_FREQUENCIES: BillingFrequency[] = [
  "Weekly",
  "Monthly",
  "Quarterly",
  "Termly",
  "SemiAnnual",
  "Annual",
  "OneTime",
]

/** How many months each frequency advances. Weekly and OneTime are not months. */
const MONTHS: Partial<Record<BillingFrequency, number>> = {
  Monthly: 1,
  Quarterly: 3,
  Termly: 4,
  SemiAnnual: 6,
  Annual: 12,
}

export const FREQUENCY_LABELS: Record<BillingFrequency, string> = {
  Weekly: "Every week",
  Monthly: "Every month",
  Quarterly: "Every 3 months",
  Termly: "Every term (4 months)",
  SemiAnnual: "Every 6 months",
  Annual: "Every year",
  OneTime: "One time only",
}

function parse(date: string): { y: number; m: number; d: number } | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date)
  if (!m) return null
  return { y: Number(m[1]), m: Number(m[2]), d: Number(m[3]) }
}

function format(y: number, m: number, d: number): string {
  return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`
}

function daysInMonth(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate()
}

/**
 * The next billing date after `from`.
 *
 * Monthly from the 31st lands on the 28th/30th, not on the 1st of the month
 * after: PostgreSQL's `+ interval '1 month'` clamps, and a monthly plan that
 * started on the 31st should bill in February, not skip it. OneTime returns
 * null -- there is no next date, which is what stops the catch-up loop.
 */
export function nextBillingDate(
  from: string,
  frequency: BillingFrequency | string,
): string | null {
  const p = parse(from)
  if (!p) return null

  if (frequency === "Weekly") {
    const t = Date.UTC(p.y, p.m - 1, p.d + 7)
    const d = new Date(t)
    return format(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate())
  }

  const months = MONTHS[frequency as BillingFrequency]
  if (!months) return null // OneTime, or a frequency we do not know

  const total = p.m - 1 + months
  const y = p.y + Math.floor(total / 12)
  const m = (total % 12) + 1
  return format(y, m, Math.min(p.d, daysInMonth(y, m)))
}

/**
 * The period a bill dated `start` covers: from `start` up to the day before the
 * next one. A OneTime plan covers a single day, matching the SQL's
 * `COALESCE(next, start + 1) - 1`.
 */
export function billingPeriod(
  start: string,
  frequency: BillingFrequency | string,
): { start: string; end: string } | null {
  const p = parse(start)
  if (!p) return null
  const next = nextBillingDate(start, frequency)
  const endUtc = next
    ? Date.parse(`${next}T00:00:00Z`) - 86_400_000
    : Date.UTC(p.y, p.m - 1, p.d)
  const d = new Date(endUtc)
  return {
    start,
    end: format(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()),
  }
}

/** A bill's due date: the period start plus the plan's payment terms. */
export function dueDate(start: string, paymentDueDays: number): string | null {
  const p = parse(start)
  if (!p) return null
  const d = new Date(Date.UTC(p.y, p.m - 1, p.d + Math.max(0, Math.trunc(paymentDueDays))))
  return format(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate())
}

/**
 * Every period a subscription is behind, oldest first, up to and including
 * `asOf`. Mirrors the generate loop, guard and all: the server stops at 60
 * iterations so a bad frequency cannot spin forever, and so does this.
 *
 * Returns [] for a subscription that is not due, which is the normal case.
 */
export function periodsDue(
  nextBilling: string | null | undefined,
  frequency: BillingFrequency | string,
  asOf: string,
  endDate?: string | null,
): string[] {
  if (!nextBilling || !parse(nextBilling) || !parse(asOf)) return []

  const out: string[] = []
  let cursor: string | null = nextBilling
  let guard = 0

  while (cursor && cursor <= asOf && guard < 60) {
    if (endDate && cursor > endDate) break
    out.push(cursor)
    guard += 1
    cursor = nextBillingDate(cursor, frequency)
  }
  return out
}

/**
 * What a subscription bills per period, after its discount and tax. Kept here
 * rather than inline in a page so the plans list, the subscription form and the
 * billing preview cannot drift apart.
 */
export function periodTotal(
  billingAmount: number,
  discountAmount = 0,
  taxAmount = 0,
): number {
  const total = billingAmount - discountAmount + taxAmount
  return Math.round(Math.max(0, total) * 100) / 100
}

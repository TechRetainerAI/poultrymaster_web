/**
 * Recurring Expense Engine (migration 348) -- presentation helpers shared by
 * every company type.
 *
 * occurrenceDate MIRRORS fnrecurringexpense_occurrencedate: each date is
 * worked out from the START date, so a template starting on the 31st keeps
 * landing on the last day of short months and goes back to the 31st after
 * them (31 Jan -> 28 Feb -> 31 Mar). The database is the authority; this only
 * lets the form preview the first few dates before anything is saved.
 */

import type { RecurringFrequency } from "@/lib/api/recurring-expenses"

export const FREQUENCIES: { value: RecurringFrequency; label: string }[] = [
  { value: "Weekly", label: "Weekly" },
  { value: "Biweekly", label: "Every 2 weeks" },
  { value: "Monthly", label: "Monthly" },
  { value: "Quarterly", label: "Quarterly" },
  { value: "SemiAnnual", label: "Every 6 months" },
  { value: "Annual", label: "Yearly" },
]

export const frequencyLabel = (f: string) => FREQUENCIES.find((x) => x.value === f)?.label ?? f

const pad = (n: number) => String(n).padStart(2, "0")
const iso = (y: number, m: number, d: number) => `${y}-${pad(m)}-${pad(d)}`
const daysInMonth = (y: number, m: number) => new Date(Date.UTC(y, m, 0)).getUTCDate()   // m is 1-based

function addMonths(start: string, months: number): string {
  const [y, m, d] = start.split("-").map(Number)
  const total = (y * 12 + (m - 1)) + months
  const ny = Math.floor(total / 12)
  const nm = (total % 12) + 1
  return iso(ny, nm, Math.min(d, daysInMonth(ny, nm)))
}

function addDays(start: string, days: number): string {
  const [y, m, d] = start.split("-").map(Number)
  const t = new Date(Date.UTC(y, m - 1, d + days))
  return iso(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate())
}

/** Occurrence n (0-based) of a template starting on `start` (yyyy-mm-dd). */
export function occurrenceDate(start: string, frequency: RecurringFrequency, n: number): string {
  switch (frequency) {
    case "Weekly": return addDays(start, 7 * n)
    case "Biweekly": return addDays(start, 14 * n)
    case "Monthly": return addMonths(start, n)
    case "Quarterly": return addMonths(start, 3 * n)
    case "SemiAnnual": return addMonths(start, 6 * n)
    case "Annual": return addMonths(start, 12 * n)
  }
}

/** The first `count` dates, stopping at the end date. */
export function previewDates(start: string, frequency: RecurringFrequency, count: number, end?: string | null): string[] {
  const out: string[] = []
  for (let n = 0; out.length < count && n < 1000; n++) {
    const d = occurrenceDate(start, frequency, n)
    if (end && d > end) break
    out.push(d)
  }
  return out
}

/** How a payment method reads on a draft: "Credit" means it will be owed. */
export function paymentEffect(method: string, hasCashAccount: boolean, moduleApproves: boolean): string {
  if (method === "Credit") return "Posted unpaid — it becomes a supplier balance, no cash moves."
  if (!hasCashAccount) return "Choose the cash account it is paid from."
  return moduleApproves
    ? "Paid — cash leaves the account when the expense is approved on the Expenses page."
    : "Paid — cash leaves the account when you post it."
}

export interface TemplateFormCheck {
  name: string; amount: number; frequency: string; startDate: string; endDate?: string | null
  categoryOk: boolean; paymentMethod: string; supplierId?: number | null
  cashAccountId?: number | null; approvalMode?: string
}

/** The database's refusals, in its words. */
export function validateTemplate(f: TemplateFormCheck): string[] {
  const e: string[] = []
  if (!f.name.trim()) e.push("Give the recurring expense a name.")
  if (!(f.amount > 0)) e.push("The amount must be greater than 0.")
  if (!FREQUENCIES.some((x) => x.value === f.frequency)) e.push("Choose how often it repeats.")
  if (!f.startDate) e.push("Choose the first date it is due.")
  if (f.endDate && f.startDate && f.endDate < f.startDate) e.push(`The end date (${f.endDate}) is before the start date (${f.startDate}).`)
  if (!f.categoryOk) e.push("Choose a category.")
  if (f.paymentMethod === "Credit" && !f.supplierId) e.push("An expense bought on credit needs a supplier, so it can be owed to someone.")
  // A draft can leave the account to be chosen when posting; an automatic post can't ask.
  if (f.approvalMode === "AutoPost" && f.paymentMethod !== "Credit" && !f.cashAccountId)
    e.push("Automatic posting needs the cash account it is paid from.")
  return e
}

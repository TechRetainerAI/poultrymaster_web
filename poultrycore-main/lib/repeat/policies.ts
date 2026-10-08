/**
 * Smart Repeat — the copy policy of each form that supports "Repeat previous".
 *
 * Every field a form has is listed under exactly one of copy / review / never,
 * so the policy IS the documentation. Anything not listed is not copied.
 * Identity and audit fields (ids, reference numbers, created/posted/approved
 * stamps, status, reversal links) are stripped by the framework on top of this
 * (IDENTITY_AND_AUDIT_FIELDS) — no policy can copy them.
 *
 * Production Records are deliberately NOT here: Batch Production Entry and
 * the production catch-up flow already handle repeated daily production, and
 * mortality, damages and one-time adjustments must never be carried forward.
 */

import type { FeedUsage } from "@/lib/api/feed-usage"
import type { HealthRecord } from "@/lib/api/health"
import type { PoultryInternalUsage, InternalUseCategory } from "@/lib/api/internal-use"
import type { Expense } from "@/lib/api/expense"
import { mustBeValid, type CopyPolicy } from "./repeat-previous"

// ------------------------------------------------------------- Feed Usage --
/** The /feed-usage form state (all strings, as the form keeps them). */
export interface FeedUsageForm {
  flockId: string
  usageDate: string
  feedType: string
  quantityKg: string
}

export const feedUsagePolicy: CopyPolicy<FeedUsage, FeedUsageForm> = {
  formType: "poultry.feed-usage",
  noun: "feed usage",
  dateField: "usageDate",
  fields: {
    flockId:    { mode: "copy", from: (s) => (s.flockId ? String(s.flockId) : null), stillValid: mustBeValid("flock", "That flock") },
    // The feed list can change; a type no longer offered is dropped, not resubmitted.
    feedType:   { mode: "copy", from: (s) => s.feedType, stillValid: mustBeValid("feedType", "That feed type") },
    // Yesterday's quantity is a guess about today, never a fact.
    quantityKg: { mode: "review", from: (s) => (s.quantityKg ? String(s.quantityKg) : null),
                  reason: "Feed eaten changes day to day — confirm today's quantity." },
    usageDate:  { mode: "never", reason: "Today's business date is used." },
  },
  describe: (s) => `${s.feedType} · ${s.quantityKg} kg`,
  sourceId: (s) => s.feedUsageId,
  sourceDate: (s) => s.usageDate,
}

// ------------------------------------------------- Treatment (Health records)
export type HealthRecordType = "Vaccination" | "Medication" | "Treatment" | "Illness" | "Mortality"

export interface TreatmentForm {
  recordType: HealthRecordType
  flockId: number | null
  houseId: number | null
  itemId: number | null
  recordDate: string
  vaccination: string      // "Name"
  medication: string       // "Treatment"
  waterConsumption: number | undefined   // "Dosage"
  notes: string
}

/** [Type:X] prefix the Health page stores on notes. */
export function healthTypeFromNotes(notes?: string | null): HealthRecordType | null {
  const m = /^\[Type:(\w+)\]/.exec(notes ?? "")
  return m && ["Vaccination", "Medication", "Treatment", "Illness", "Mortality"].includes(m[1]) ? (m[1] as HealthRecordType) : null
}

export const treatmentPolicy: CopyPolicy<HealthRecord, TreatmentForm> = {
  formType: "poultry.health",
  noun: "health record",
  dateField: "recordDate",
  fields: {
    recordType:       { mode: "copy", from: (s) => {
                          const t = healthTypeFromNotes(s.notes)
                          // A death is an event, not a routine: never pre-set it.
                          return t === "Mortality" ? null : t
                        } },
    flockId:          { mode: "copy", from: (s) => s.flockId ?? null, stillValid: mustBeValid("flock", "That flock") },
    houseId:          { mode: "copy", from: (s) => s.houseId ?? null, stillValid: mustBeValid("house", "That house") },
    itemId:           { mode: "copy", from: (s) => s.itemId ?? null, stillValid: mustBeValid("item", "That item") },
    // Medical content is copied only as REVIEW and the form will not save
    // until the person confirms it: no dose is ever repeated silently.
    vaccination:      { mode: "review", from: (s) => s.vaccination ?? null, reason: "Confirm the vaccine/medicine name." },
    medication:       { mode: "review", from: (s) => s.medication ?? null, reason: "Confirm the treatment is still prescribed." },
    waterConsumption: { mode: "review", from: (s) => (s.waterConsumption ?? null) as number | null | undefined,
                        reason: "Confirm the dosage — never assume last time's dose." },
    notes:            { mode: "never", reason: "Observations belong to the day they were made." },
    recordDate:       { mode: "never", reason: "Today's business date is used." },
  },
  describe: (s) => [s.vaccination, s.medication].filter(Boolean).join(" · ") || "health record",
  sourceId: (s) => s.id ?? 0,
  sourceDate: (s) => s.recordDate,
}

// ------------------------------------------------------- Internal Use (poultry)
export interface InternalUseForm {
  usageDate: string
  category: InternalUseCategory
  recipientName: string
  reason: string
  notes: string
  poultryProductId: number
  entryUnit: string
  entryQuantity: number
  unitCost: number
  useStaffHelper: boolean
  staffCount: number
  quantityPerStaff: number
}

export const internalUsePolicy: CopyPolicy<PoultryInternalUsage, InternalUseForm> = {
  formType: "poultry.internal-use",
  noun: "internal use",
  dateField: "usageDate",
  fields: {
    category:         { mode: "copy", from: (s) => s.category },
    recipientName:    { mode: "copy", from: (s) => s.recipientName ?? null },
    reason:           { mode: "copy", from: (s) => s.reason ?? null },
    poultryProductId: { mode: "copy", from: (s) => s.items?.[0]?.poultryProductId ?? null,
                        stillValid: mustBeValid("product", "That product") },
    entryUnit:        { mode: "copy", from: (s) => s.items?.[0]?.entryUnit ?? null },
    useStaffHelper:   { mode: "copy", from: (s) => (s.staffCount ?? 0) > 0 },
    // With the per-staff helper the form computes the total itself, so the old
    // total is not carried (it would be a hidden "check" field).
    entryQuantity:    { mode: "review", from: (s) => ((s.staffCount ?? 0) > 0 ? null : s.items?.[0]?.entryQuantity ?? null),
                        reason: "Confirm how much was used this time." },
    staffCount:       { mode: "review", from: (s) => (s.staffCount ?? 0) > 0 ? s.staffCount : null,
                        reason: "Staff on duty changes — confirm the head count." },
    quantityPerStaff: { mode: "review", from: (s) => ((s.staffCount ?? 0) > 0 ? s.items?.[0]?.quantityPerStaff ?? null : null),
                        reason: "Confirm the amount per person." },
    // Re-suggested from TODAY's stock cost by the form, never last time's.
    unitCost:         { mode: "never", reason: "Cost is worked out from today's stock value." },
    notes:            { mode: "never", reason: "Notes belong to the entry they were written for." },
    usageDate:        { mode: "never", reason: "Today's business date is used." },
  },
  describe: (s) => `${s.items?.[0]?.productName ?? "product"} · ${s.items?.[0]?.entryQuantity ?? ""} ${s.items?.[0]?.entryUnit ?? ""}`.trim(),
  sourceId: (s) => s.poultryInternalUsageId,
  sourceDate: (s) => s.usageDate,
}

// ------------------------------------------------------------------ Expenses
export interface ExpenseForm {
  flockId: string
  expenseDate: string
  category: string
  description: string
  amount: string
  paymentMethod: string
  poultryCashAccountId: string
  supplierId: string
  paymentStatus: string
  amountPaid: string
  dueDate: string
}

/**
 * Two variants. The default copies only what describes the expense
 * (category, supplier, description, payment method, flock). "Including the
 * amount" is an explicit choice: amount, cash account and paid status then
 * come across as REVIEW. Amount paid, due date and any receipt never do.
 */
export function expensePolicy(opts: { includeAmount: boolean }): CopyPolicy<Expense, ExpenseForm> {
  const money = opts.includeAmount ? ("review" as const) : ("never" as const)
  return {
    formType: opts.includeAmount ? "poultry.expense+amount" : "poultry.expense",
    noun: "expense",
    dateField: "expenseDate",
    fields: {
      category:             { mode: "copy", from: (s) => s.category, stillValid: mustBeValid("category", "That category") },
      description:          { mode: "copy", from: (s) => s.description },
      paymentMethod:        { mode: "copy", from: (s) => s.paymentMethod },
      supplierId:           { mode: "copy", from: (s) => (s.supplierId ? String(s.supplierId) : null),
                              stillValid: mustBeValid("supplier", "That supplier") },
      // flockId 0 = farm-wide on the list; the form calls that "ALL".
      flockId:              { mode: "copy", from: (s) => (s.flockId ? String(s.flockId) : "ALL"),
                              stillValid: (v, ctx) => (v === "ALL" ? null : mustBeValid("flock", "That flock")(v, ctx)) },
      amount:               { mode: money, from: (s) => (s.amount ? String(s.amount) : null),
                              reason: opts.includeAmount ? "Confirm this period's amount." : "Amounts change — enter this one fresh." },
      poultryCashAccountId: { mode: money, from: (s) => (s.poultryCashAccountId ? String(s.poultryCashAccountId) : null),
                              stillValid: mustBeValid("cashAccount", "That cash account"),
                              reason: opts.includeAmount ? "Confirm which account paid it." : "Choose the account for this payment." },
      paymentStatus:        { mode: money, from: (s) => (s.paymentStatus === "Unpaid" || s.paymentStatus === "PartiallyPaid" ? s.paymentStatus : "Paid"),
                              reason: opts.includeAmount ? "Confirm whether this one is paid." : "Say whether this one is paid." },
      amountPaid:           { mode: "never", reason: "Part payments are specific to one bill." },
      dueDate:              { mode: "never", reason: "Each bill has its own due date." },
      expenseDate:          { mode: "never", reason: "Today's business date is used." },
    },
    describe: (s) => `${s.category} · ${s.description}`,
    sourceId: (s) => s.expenseId,
    sourceDate: (s) => s.expenseDate,
  }
}

/** Expenses a workflow created (feed consumption, payroll, internal use ...) are not repeatable by hand. */
export const isRepeatableExpense = (e: Pick<Expense, "sourceType">) => !e.sourceType

/** Labels for the banner. */
export const FIELD_LABELS = {
  feedUsage: { flockId: "Flock", feedType: "Feed type", quantityKg: "Quantity (kg)", usageDate: "Date" },
  treatment: { recordType: "Record type", flockId: "Flock", houseId: "House", itemId: "Item", vaccination: "Name",
               medication: "Treatment", waterConsumption: "Dosage", notes: "Notes", recordDate: "Date" },
  internalUse: { category: "Reason", recipientName: "Who received it", reason: "Detail", poultryProductId: "Product",
                 entryUnit: "Unit", entryQuantity: "Quantity", useStaffHelper: "Per-staff helper", staffCount: "Staff count",
                 quantityPerStaff: "Per person", unitCost: "Unit cost", notes: "Notes", usageDate: "Date" },
  expense: { category: "Category", description: "Description", paymentMethod: "Payment method", supplierId: "Supplier",
             flockId: "Flock", amount: "Amount", poultryCashAccountId: "Cash account", paymentStatus: "Payment status",
             amountPaid: "Amount paid", dueDate: "Due date", expenseDate: "Date" },
} as const

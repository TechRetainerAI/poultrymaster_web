/**
 * Smart Repeat / Copy Previous Entry — the shared framework.
 *
 * REPEAT PREVIOUS MEANS "PREFILL A NEW FORM". It never duplicates, re-posts or
 * submits the old transaction. A prefill is just initial form state: the
 * person reviews it and presses the form's normal Save, which calls the
 * form's normal create service and passes every normal validation.
 *
 * Each form declares an explicit POLICY. A field is copied ONLY if the policy
 * names it — there is no reflection and no "copy everything except":
 *
 *   copy     safe to carry over as-is (the feed, the flock, the category)
 *   review   carried over but visibly marked "check this" (quantities,
 *            amounts, doses) — the form must show it as unconfirmed
 *   never    documented as deliberately NOT carried (amounts nobody should
 *            assume, cash accounts, references, paid status ...)
 *
 * On top of every policy, IDENTITY_AND_AUDIT_FIELDS are stripped from the
 * result no matter what a policy says — ids, numbers, created/posted/approved
 * stamps, status, reversal links. A policy cannot opt them back in.
 *
 * The DATE is never copied: it defaults to the company's business date
 * (today in the company's time zone). Copying yesterday's date onto a new
 * entry is exactly how a record lands on the wrong day.
 *
 * A REFERENCED record (flock, item, supplier, cash account) is re-checked
 * against what is valid NOW. A flock that has since closed, an item made
 * inactive, a supplier deleted — the value is dropped and the person told,
 * rather than silently resubmitted.
 */

export type CopyMode = "copy" | "review" | "never"

export interface FieldRule<TSource, TForm, K extends keyof TForm = keyof TForm> {
  mode: CopyMode
  /** Reads the value from the previous entry. Ignored for "never". */
  from?: (src: TSource) => TForm[K] | null | undefined
  /** Why it needs review / is never copied — shown to the person. */
  reason?: string
  /**
   * A reference that must still be valid today. Return a message to DROP the
   * value (e.g. "Flock B3 has been closed"), or null to keep it.
   */
  stillValid?: (value: TForm[K], ctx: RepeatContext) => string | null
}

export interface CopyPolicy<TSource, TForm> {
  /** Stable id, e.g. "poultry.expense". */
  formType: string
  /** What the button and banner call one entry, e.g. "expense". */
  noun: string
  /** The form field that holds the business date; filled from ctx.businessDate. */
  dateField?: keyof TForm
  fields: { [K in keyof TForm]?: FieldRule<TSource, TForm, K> }
  /** How to describe the previous entry in the banner ("Layer Mash · 12 Sep"). */
  describe: (src: TSource) => string
  /** The previous entry's own id, for the banner only (never copied). */
  sourceId: (src: TSource) => number | string
  /** The previous entry's date, for the banner only (never copied). */
  sourceDate?: (src: TSource) => string | null | undefined
}

export interface RepeatContext {
  /** The company's business date, yyyy-mm-dd. */
  businessDate: string
  /** Ids that are valid to reference today, by kind ("flock", "item", "supplier", "cashAccount"...). */
  valid?: Record<string, ReadonlySet<number | string>>
}

export interface DroppedField { field: string; reason: string }

export interface RepeatPrefill<TForm> {
  /** Initial form state: only the allowed fields, plus the business date. */
  values: Partial<TForm>
  /** Copied but unconfirmed — the form highlights these until edited. */
  review: string[]
  /** Fields the policy copies but which were not copied this time, and why. */
  dropped: DroppedField[]
  /** Fields the policy says are never copied, with the reason — for the banner's "not copied" list. */
  neverCopied: DroppedField[]
  source: { id: number | string; date: string | null; label: string; formType: string; noun: string }
  /** The form field that received the business date, if the form has one. */
  dateField?: string
}

/**
 * Stripped from EVERY prefill regardless of policy. Matched case-insensitively
 * on the form field name.
 */
export const IDENTITY_AND_AUDIT_FIELDS: readonly string[] = [
  "id", "expenseId", "healthRecordId", "productionRecordId", "internalUsageId", "usageId",
  "poultryRawMaterialPurchaseId", "poultryPurchaseReceiptId", "feedUsageId", "occurrenceId",
  "transactionNumber", "receiptNumber", "paymentNumber", "invoiceNumber", "referenceNo", "reference",
  "createdAt", "createdBy", "createdDate", "dateCreated", "updatedAt", "updatedBy", "dateUpdated",
  "postedAt", "postedBy", "approvedAt", "approvedBy", "submittedAt", "submittedBy",
  // Approval/workflow status. (A form's own Paid/Unpaid CHOICE is not listed:
  // the expense policy copies it only on explicit request, as REVIEW.)
  "status", "approvalStatus", "workflowStatus",
  "reversedAt", "reversedBy", "reversalReason", "isReversed", "reversalId", "reversalAdjustmentId",
  "isDeleted", "deletedAt", "clientRequestId",
]
const IDENTITY = new Set(IDENTITY_AND_AUDIT_FIELDS.map((f) => f.toLowerCase()))

export const isIdentityField = (name: string) => IDENTITY.has(name.toLowerCase())

const isBlank = (v: unknown) => v === null || v === undefined || (typeof v === "string" && v.trim() === "")

/** Builds the prefill for a NEW entry from a previous one. Pure; posts nothing. */
export function buildRepeatPrefill<TSource, TForm>(
  policy: CopyPolicy<TSource, TForm>,
  previous: TSource,
  ctx: RepeatContext,
): RepeatPrefill<TForm> {
  const values: Partial<TForm> = {}
  const review: string[] = []
  const dropped: DroppedField[] = []
  const neverCopied: DroppedField[] = []

  for (const key of Object.keys(policy.fields) as (keyof TForm & string)[]) {
    const rule = policy.fields[key] as FieldRule<TSource, TForm> | undefined
    if (!rule) continue
    if (rule.mode === "never") {
      neverCopied.push({ field: key, reason: rule.reason ?? "Enter it fresh for each entry." })
      continue
    }
    if (isIdentityField(key)) {
      // A policy tried to copy an identity/audit field: refuse, loudly in dev.
      neverCopied.push({ field: key, reason: "Transaction identity and audit fields are never copied." })
      continue
    }
    if (policy.dateField && key === policy.dateField) continue   // the date is never copied
    const value = rule.from ? rule.from(previous) : undefined
    if (isBlank(value)) continue
    const invalid = rule.stillValid ? rule.stillValid(value as TForm[typeof key], ctx) : null
    if (invalid) { dropped.push({ field: key, reason: invalid }); continue }
    ;(values as Record<string, unknown>)[key] = value
    if (rule.mode === "review") review.push(key)
  }

  if (policy.dateField) (values as Record<string, unknown>)[policy.dateField as string] = ctx.businessDate

  return {
    values,
    review,
    dropped,
    neverCopied,
    dateField: policy.dateField as string | undefined,
    source: {
      id: policy.sourceId(previous),
      date: policy.sourceDate?.(previous)?.slice(0, 10) ?? null,
      label: policy.describe(previous),
      formType: policy.formType,
      noun: policy.noun,
    },
  }
}

/** A reference check against ctx.valid[kind]; the message names what changed. */
export function mustBeValid(kind: string, what: string) {
  return (value: unknown, ctx: RepeatContext): string | null => {
    const set = ctx.valid?.[kind]
    if (!set) return null   // the form did not supply a list: nothing to check against
    // Forms keep ids as strings ("7"), lists as numbers (7): compare as text.
    const wanted = String(value)
    for (const v of set) if (String(v) === wanted) return null
    return `${what} is no longer available (closed, inactive or deleted), so it was not copied.`
  }
}

/**
 * Picks the entry to repeat: the most recent by date, then by id. Callers pass
 * rows already scoped to the active company (every list API is farm-scoped).
 */
export function latestEntry<T>(rows: T[], date: (r: T) => string | null | undefined, id: (r: T) => number): T | null {
  let best: T | null = null
  for (const r of rows) {
    if (!best) { best = r; continue }
    const a = (date(r) ?? "").slice(0, 10), b = (date(best) ?? "").slice(0, 10)
    if (a > b || (a === b && id(r) > id(best))) best = r
  }
  return best
}

/** True while a review field still holds the value that was copied (not yet confirmed/edited). */
export function stillUnconfirmed<TForm>(prefill: RepeatPrefill<TForm> | null, current: Partial<TForm>, field: keyof TForm & string): boolean {
  if (!prefill || !prefill.review.includes(field)) return false
  return (prefill.values as Record<string, unknown>)[field] === (current as Record<string, unknown>)[field]
}

/** Review fields still holding their copied value. */
export function unconfirmedFields<TForm>(prefill: RepeatPrefill<TForm> | null, current: Partial<TForm>): string[] {
  if (!prefill) return []
  return prefill.review.filter((f) => stillUnconfirmed(prefill, current, f as keyof TForm & string))
}

/**
 * The submit guard every repeat-enabled form adds IN FRONT OF its normal
 * validation (never instead of it): copied review values must be confirmed —
 * by editing them, or by ticking "I've checked these". Returns a message to
 * block the save, or null.
 */
export function repeatSubmitBlocker<TForm>(
  prefill: RepeatPrefill<TForm> | null, current: Partial<TForm>, confirmed: boolean, labels: Record<string, string>,
): string | null {
  const left = unconfirmedFields(prefill, current)
  if (left.length === 0 || confirmed) return null
  return `Check the values copied from your last entry before saving: ${left.map((f) => labels[f] ?? f).join(", ")}. Change them, or tick "I've checked these".`
}

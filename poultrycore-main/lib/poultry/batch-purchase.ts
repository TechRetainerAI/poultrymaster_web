// What a bird purchase asks for, and what it derives — in ONE place.
//
// A batch can be created from two screens: Flock Purchases, and Initial Farm
// Setup. Before this module each had its own copy of the field list, the
// supplier-type options and the total/balance/status arithmetic, so a field
// added to one would quietly be missing from the other and "part payment" could
// come to mean two different things on two screens.
//
// Pure: no React, no API. The rendered inputs live in
// components/poultry/batch-purchase-fields.tsx and both screens use those; this
// is what those inputs mean.

/**
 * A batch purchase as a FORM holds it: text, because that is what an input
 * contains. A half-typed "12" and an empty field are different things, and a
 * number-typed draft cannot tell them apart — it turns a cleared field into 0.
 */
export interface BatchPurchaseDraft {
  batchName: string
  batchCode: string
  breed: string
  numberOfBirds: string
  startDate: string

  costPerChick: string
  totalCost: string
  amountPaid: string
  supplierType: string
  /** "" means no supplier chosen. */
  supplierId: string
  dollarConversionRate: string

  orderPlacementDate: string
  estimatedArrivalDate: string
  notes: string
}

export type BatchPurchasePatch = Partial<BatchPurchaseDraft>

export function emptyBatchPurchase(): BatchPurchaseDraft {
  return {
    batchName: "", batchCode: "", breed: "", numberOfBirds: "", startDate: "",
    costPerChick: "", totalCost: "", amountPaid: "", supplierType: "local",
    supplierId: "", dollarConversionRate: "",
    orderPlacementDate: "", estimatedArrivalDate: "", notes: "",
  }
}

/**
 * Local or foreign. A display and reporting tag that pairs with the dollar
 * conversion rate; it carries no financial meaning of its own and is not
 * validated anywhere. Hard-coded in four places before this constant existed.
 */
export const SUPPLIER_TYPES = [
  { value: "local", label: "Local" },
  { value: "foreign", label: "Foreign" },
] as const

/** Lenient on purpose: form text, not validated input. Junk reads as zero. */
export const num = (raw: string | number | null | undefined): number => {
  const n = Number(raw)
  return Number.isFinite(n) ? n : 0
}

/**
 * The total a cost-per-chick implies. Returned as TEXT because it lands back in
 * a form field, and empty stays empty — a farm that has not said what it paid
 * should not be shown a confident 0.
 */
export function deriveTotalCost(costPerChick: string | number, numberOfBirds: string | number): string {
  const total = num(costPerChick) * num(numberOfBirds)
  return total > 0 ? String(Number(total.toFixed(2))) : ""
}

/**
 * Typing either side of the multiplication recomputes the total. The total
 * itself stays editable and an explicit edit wins — a farm whose invoice
 * disagrees with cost × birds is telling us something.
 */
export function patchForCostChange(
  draft: Pick<BatchPurchaseDraft, "costPerChick" | "numberOfBirds" | "totalCost">,
  change: { costPerChick?: string; numberOfBirds?: string },
): BatchPurchasePatch {
  const costPerChick = change.costPerChick ?? draft.costPerChick
  const numberOfBirds = change.numberOfBirds ?? draft.numberOfBirds
  const derived = deriveTotalCost(costPerChick, numberOfBirds)
  return {
    ...change,
    // Only overwrite when there is something to say. Clearing the cost must not
    // wipe a total the farm typed by hand.
    ...(derived ? { totalCost: derived } : {}),
  }
}

/** What is still owed. Never negative: overpayment is not a negative debt. */
export function batchBalance(totalCost: string | number, amountPaid: string | number): number {
  return Math.max(0, num(totalCost) - num(amountPaid))
}

export interface PaymentStatus {
  label: string
  className: string
}

/**
 * How the purchase stands, as a badge. Wording and colours are shared so the
 * same batch never reads "Unpaid" on one screen and "Part payment" on another.
 */
export function paymentStatus(total: string | number, paid: string | number): PaymentStatus {
  const t = num(total)
  const p = num(paid)
  if (t <= 0) return { label: "No cost set", className: "bg-slate-100 text-slate-600 border-slate-200" }
  if (p >= t) return { label: "Paid in full", className: "bg-green-100 text-green-800 border-green-200" }
  if (p <= 0) return { label: "Unpaid", className: "bg-red-100 text-red-800 border-red-200" }
  return { label: "Part payment", className: "bg-amber-100 text-amber-900 border-amber-200" }
}

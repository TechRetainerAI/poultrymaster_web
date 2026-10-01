// Flock closeout — the wizard's arithmetic, kept out of the component so it can
// be tested and so the wizard and the server cannot quietly disagree.
//
// validateCloseoutDraft mirrors FlockCloseoutValidator.cs. The server re-checks
// everything (and spflock_closeout re-checks the bird balance inside its own
// transaction), so this is about telling the person BEFORE they press Close,
// not about trust.

import type {
  FlockBirdPosition,
  FlockCloseoutContext,
  FlockCloseoutCullLine,
  FlockCloseoutSaleLine,
  FlockCloseoutTransferLine,
  FlockLifetimeSummary,
  PaymentTerms,
} from "@/lib/api/flock-closeout"

export const PAYMENT_TERMS: { value: PaymentTerms; label: string }[] = [
  { value: "Paid", label: "Paid in full" },
  { value: "Credit", label: "On credit" },
  { value: "PartPaid", label: "Part paid" },
]

export interface CloseoutDraft {
  closedDate: string
  reason: string
  notes?: string
  sales: FlockCloseoutSaleLine[]
  culls: FlockCloseoutCullLine[]
  transfers: FlockCloseoutTransferLine[]
}

const qty = (n: unknown) => Math.max(0, Math.trunc(Number(n) || 0))
const round2 = (n: number) => Math.round(n * 100) / 100

/** Quantity x unit price unless a total was typed. The same default the server uses. */
export function saleTotal(line: Pick<FlockCloseoutSaleLine, "quantity" | "unitPrice" | "totalAmount">): number {
  if (line.totalAmount != null && Number.isFinite(Number(line.totalAmount))) return Number(line.totalAmount)
  return round2(qty(line.quantity) * (Number(line.unitPrice) || 0))
}

export interface DispositionTotals {
  sold: number
  culled: number
  transferred: number
  total: number
}

export function dispositionTotals(draft: Pick<CloseoutDraft, "sales" | "culls" | "transfers">): DispositionTotals {
  const sold = draft.sales.reduce((s, l) => s + qty(l.quantity), 0)
  const culled = draft.culls.reduce((s, l) => s + qty(l.quantity), 0)
  const transferred = draft.transfers.reduce((s, l) => s + qty(l.quantity), 0)
  return { sold, culled, transferred, total: sold + culled + transferred }
}

/** Birds still to account for. Negative means the dispositions overshoot. */
export function unresolvedBirds(position: Pick<FlockBirdPosition, "currentLiveBirds">, draft: Pick<CloseoutDraft, "sales" | "culls" | "transfers">): number {
  return position.currentLiveBirds - dispositionTotals(draft).total
}

export interface ReconciliationLine {
  key: string
  label: string
  value: number
  /** How the line moves the running figure: a subtotal has none. */
  sign: "+" | "-" | "±" | "="
  hint?: string
  muted?: boolean
}

/**
 * The flock's birds, top to bottom, in the order they happened. Every line is
 * a column of fnflock_birdposition; nothing is computed here that the server
 * did not already compute, so the wizard cannot show a different story.
 *
 * Opening history appears only when Initial Farm Setup recorded it -- a flock
 * the app saw from placement has none -- and it is kept visibly apart from the
 * mortality recorded since, so neither distorts the other.
 */
export function reconciliationLines(p: FlockBirdPosition): ReconciliationLine[] {
  const lines: ReconciliationLine[] = []
  lines.push({ key: "placed", label: "Originally placed", value: p.originallyPlaced, sign: "=" })

  if (p.hasOpeningPosition && p.originallyPlaced !== p.openingLiveBirds) {
    if (p.historyKnown) {
      const hist: [string, string, number][] = [
        ["openingMortality", "Opening historical mortality", p.openingMortality],
        ["openingSold", "Sold before tracking began", p.openingSold],
        ["openingCulled", "Culled before tracking began", p.openingCulled],
        ["openingTransferred", "Transferred before tracking began", p.openingTransferred],
        ["openingOther", "Other opening adjustment", p.openingOther],
      ]
      for (const [key, label, value] of hist) {
        if (value) lines.push({ key, label, value, sign: "-", muted: true })
      }
    } else {
      lines.push({
        key: "openingOther",
        label: "Opening reduction (history not recorded)",
        value: p.originallyPlaced - p.openingLiveBirds,
        sign: "-",
        muted: true,
        hint: "Not known to be deaths, so it is not counted as mortality.",
      })
    }
  }

  lines.push({
    key: "openingLive",
    label: p.hasOpeningPosition ? "Opening current position" : "Birds at start",
    value: p.openingLiveBirds,
    sign: "=",
  })
  lines.push({ key: "mortality", label: "Recorded mortality", value: p.recordedMortality, sign: "-" })
  if (p.correction !== 0) {
    lines.push({
      key: "correction",
      label: "Count corrections",
      value: p.correction,
      sign: "±",
      hint: "Changes in the production-record head count that recorded mortality does not explain.",
    })
  }
  lines.push({
    key: "lastCount",
    label: "Last counted",
    value: p.lastCountedBirds,
    sign: "=",
    hint: p.lastCountDate ? undefined : "No production records yet: the flock's starting number.",
  })
  lines.push({ key: "sold", label: "Birds sold", value: p.birdsSold, sign: "-" })
  if (p.birdsCulled) lines.push({ key: "culled", label: "Culled", value: p.birdsCulled, sign: "-" })
  if (p.birdsTransferred) lines.push({ key: "transferred", label: "Transferred", value: p.birdsTransferred, sign: "-" })
  lines.push({ key: "live", label: "Current live birds", value: p.currentLiveBirds, sign: "=" })
  return lines
}

/** Mirrors FlockCloseoutValidator.Validate. Empty means ready to close. */
export function validateCloseoutDraft(draft: CloseoutDraft, context: FlockCloseoutContext): string[] {
  const errors: string[] = []
  if (context.isClosed) return ["This flock is already closed."]
  if (context.ineligibleReason) return [context.ineligibleReason]

  if (!draft.reason.trim()) errors.push("A reason is required to close a flock.")

  const closed = (draft.closedDate || "").slice(0, 10)
  const today = (context.businessDate || "").slice(0, 10)
  const earliest = (context.earliestCloseDate || "").slice(0, 10)
  if (!closed) errors.push("Choose the closing date.")
  else {
    if (today && closed > today) errors.push("The closing date cannot be in the future.")
    if (earliest && closed < earliest) errors.push(`The closing date cannot be before ${earliest}.`)
  }

  draft.sales.forEach((s, i) => {
    const n = `Sale ${i + 1}`
    if (qty(s.quantity) <= 0) errors.push(`${n}: enter how many birds were sold.`)
    if ((Number(s.unitPrice) || 0) < 0 || (Number(s.totalAmount) || 0) < 0) errors.push(`${n}: the price cannot be negative.`)
    const total = saleTotal(s)
    const hasCustomer = s.customerId != null || !!(s.customerName ?? "").trim()
    if (s.paymentTerms !== "Credit" && s.poultryCashAccountId == null)
      errors.push(`${n}: choose the cash account the money was received into.`)
    if (s.paymentTerms !== "Paid" && !hasCustomer)
      errors.push(`${n}: a sale on credit needs a customer, so the balance has someone to belong to.`)
    if (s.paymentTerms === "PartPaid") {
      const paid = Number(s.amountPaid) || 0
      if (paid <= 0 || paid >= total)
        errors.push(`${n}: a part payment must be more than zero and less than the sale total (${total.toFixed(2)}).`)
    }
    if (s.paymentTerms !== "Credit" && !(s.paymentMethod ?? "").trim()) errors.push(`${n}: choose how the customer paid.`)
  })

  draft.culls.forEach((c, i) => {
    if (qty(c.quantity) <= 0) errors.push(`Cull ${i + 1}: enter how many birds were culled.`)
  })
  draft.transfers.forEach((t, i) => {
    if (qty(t.quantity) <= 0) errors.push(`Transfer ${i + 1}: enter how many birds were transferred.`)
    if (!(t.destination ?? "").trim()) errors.push(`Transfer ${i + 1}: say where the birds went.`)
  })

  const live = context.position.currentLiveBirds
  const left = unresolvedBirds(context.position, draft)
  if (live < 0) {
    errors.push(`The flock's records account for ${-live} more birds than it had. Check for a bird sale that was also deducted on a production record before closing.`)
  } else if (left > 0) {
    errors.push(`Unresolved bird balance: ${left} bird(s) are still unaccounted for. Sell, cull or transfer them, or record any unrecorded deaths as mortality on a production record, before closing.`)
  } else if (left < 0) {
    errors.push(`Unresolved bird balance: the dispositions account for ${-left} more bird(s) than the flock has (${live}).`)
  }
  return errors
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

export type LifetimeGroupBy = "flock" | "batch" | "breed" | "supplier" | "house"

export interface LifetimeGroup {
  key: string
  label: string
  flocks: number
  originallyPlaced: number
  totalEggs: number
  recordedMortality: number
  openingLiveBirds: number
  feedConsumedKg: number
  totalRevenue: number
  totalCost: number
  profit: number
  /** Re-derived from the sums, never an average of per-flock rates. */
  trackedMortalityRate: number | null
  profitPerOriginalBird: number | null
  revenuePerOriginalBird: number | null
  feedKgPerDozenEggs: number | null
}

function groupKey(row: FlockLifetimeSummary, by: LifetimeGroupBy): [string, string] {
  switch (by) {
    case "batch":
      return [`b${row.batchId ?? "none"}`, row.batchCode || row.batchName || "No batch"]
    case "breed": {
      const b = (row.breed ?? "").trim()
      return [`r${b.toLowerCase() || "none"}`, b || "Unknown breed"]
    }
    case "supplier":
      return row.supplierId != null
        ? [`s${row.supplierType ?? ""}:${row.supplierId}`, `${row.supplierType ?? "Supplier"} #${row.supplierId}`]
        : ["snone", "No supplier recorded"]
    case "house":
      return [`h${row.houseId ?? "none"}`, row.houseName || "No house"]
    default:
      return [`f${row.flockId}`, row.flockName]
  }
}

/**
 * Batch vs Batch, Breed vs Breed, Supplier vs Supplier, House vs House, Flock vs
 * Flock -- all the same operation over fnflock_lifetimesummary rows. Ratios are
 * recomputed from the summed figures: averaging per-flock rates would weight a
 * 50-bird flock the same as a 5,000-bird one.
 */
export function groupLifetimeSummaries(rows: FlockLifetimeSummary[], by: LifetimeGroupBy): LifetimeGroup[] {
  const map = new Map<string, LifetimeGroup>()
  for (const row of rows) {
    const [key, label] = groupKey(row, by)
    const g = map.get(key) ?? {
      key, label, flocks: 0, originallyPlaced: 0, totalEggs: 0, recordedMortality: 0, openingLiveBirds: 0,
      feedConsumedKg: 0, totalRevenue: 0, totalCost: 0, profit: 0,
      trackedMortalityRate: null, profitPerOriginalBird: null, revenuePerOriginalBird: null, feedKgPerDozenEggs: null,
    }
    g.flocks += 1
    g.originallyPlaced += row.originallyPlaced
    g.totalEggs += Number(row.totalEggs) || 0
    g.recordedMortality += row.recordedMortality
    g.openingLiveBirds += row.openingLiveBirds
    g.feedConsumedKg += Number(row.feedConsumedKg) || 0
    g.totalRevenue += Number(row.totalRevenue) || 0
    g.totalCost += Number(row.totalCost) || 0
    g.profit += Number(row.profit) || 0
    map.set(key, g)
  }
  return [...map.values()].map((g) => ({
    ...g,
    trackedMortalityRate: g.openingLiveBirds > 0 ? g.recordedMortality / g.openingLiveBirds : null,
    profitPerOriginalBird: g.originallyPlaced > 0 ? round2(g.profit / g.originallyPlaced) : null,
    revenuePerOriginalBird: g.originallyPlaced > 0 ? round2(g.totalRevenue / g.originallyPlaced) : null,
    feedKgPerDozenEggs: g.totalEggs > 0 ? Math.round((g.feedConsumedKg / (g.totalEggs / 12)) * 1000) / 1000 : null,
  }))
}

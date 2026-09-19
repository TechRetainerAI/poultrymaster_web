// The impact preview behind "Correct original cost" (migrations 313, 314).
//
// WHY THIS IS THE ONE THING THE CLIENT COMPUTES
// --------------------------------------------
// Everything else on the Capital Investments screens is the server's number,
// read and printed. This is the exception, and it is an exception for a reason
// there is no way around: §21 asks the user to see the impact BEFORE they
// confirm, and there is no way to ask the server what a figure would be if it
// were different without writing it.
//
// So it is confined to this file, it is pure, and it is tested -- because a
// preview that disagrees with what the save then does would be worse than no
// preview at all. Nothing it returns is ever persisted: the moment the save
// returns, the register reloads and every figure is the server's again.
//
// EVERY RULE HERE IS MIRRORED FROM THE SERVER, NOT INVENTED
// ---------------------------------------------------------
//   monthly        = (total - residual) / life          fn*capitalasset_monthly
//   depreciable    = GREATEST(total - residual, 0)      fn*capitalasset_financials
//   book value     = GREATEST(total - accumulated, residual)          "
//   remaining      = GREATEST(depreciable - accumulated, 0)           "
//   residual > total is REFUSED                        sp*_correctoriginalcost
//
// If one of those changes on the server, it has to change here too, and the
// tests beside this file are what will say so.

export interface CorrectionInput {
  /** The original acquisition as it stands, including any earlier correction. */
  acquisitionCost: number
  /** Everything capitalised since. A correction never touches it. */
  additionalCost: number
  residualValue: number
  usefulLifeMonths?: number | null
  /** The signed sum of the depreciation ledger. Never changed by a correction. */
  accumulatedDepreciation: number
  /** What the user typed. */
  newAcquisitionCost: number
}

export interface CorrectionPreview {
  /** The corrected acquisition, rounded to the money the server will store. */
  next: number
  /** Signed. Negative when the correction reduces what was recorded. */
  difference: number
  newTotal: number
  newDepreciable: number
  /** Null when no useful life has been set -- a Draft asset. */
  newMonthly: number | null
  newBookValue: number
  newRemaining: number
  /** The server refuses this outright; say so before Save, not after. */
  residualTooHigh: boolean
  /**
   * Legal, but worth naming: the months already charged stand, and there is
   * simply nothing left for future months to charge.
   */
  overDepreciated: boolean
  nothingLeft: boolean
}

export const round2 = (n: number) => Math.round(n * 100) / 100

/**
 * Null when there is nothing to preview -- a blank box, a non-number, a
 * non-positive amount, or an amount that is already what is recorded. All four
 * are cases the server refuses, and a preview of a refusal is noise.
 */
export function previewCorrection(input: CorrectionInput): CorrectionPreview | null {
  const {
    acquisitionCost, additionalCost, residualValue,
    usefulLifeMonths, accumulatedDepreciation, newAcquisitionCost,
  } = input

  if (!Number.isFinite(newAcquisitionCost) || newAcquisitionCost <= 0) return null

  const next = round2(newAcquisitionCost)
  const difference = round2(next - acquisitionCost)
  // The server's own tolerance: below half a pesewa it is the same number.
  if (Math.abs(difference) < 0.005) return null

  const newTotal = round2(next + additionalCost)
  const newDepreciable = Math.max(round2(newTotal - residualValue), 0)
  const life = usefulLifeMonths ?? 0
  const newMonthly = life > 0 ? round2(newDepreciable / life) : null
  const newBookValue = Math.max(round2(newTotal - accumulatedDepreciation), residualValue)
  const newRemaining = Math.max(round2(newDepreciable - accumulatedDepreciation), 0)

  return {
    next,
    difference,
    newTotal,
    newDepreciable,
    newMonthly,
    newBookValue,
    newRemaining,
    residualTooHigh: residualValue > newTotal,
    overDepreciated: newDepreciable > 0 && accumulatedDepreciation >= newDepreciable,
    nothingLeft: newDepreciable <= 0,
  }
}

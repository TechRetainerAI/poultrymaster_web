// Ratio / proportion logic for feed formulas.
//
// A formula is a recipe pattern, not a fixed shopping list: the batch decides
// how much finished feed to make, and the ingredients are distributed to match.
//
//   All-percentage formula   line = Q * percentage / 100
//   All-fixed formula        the fixed quantities are a base recipe — scale
//                            them by Q / sum(fixed). 50/30/20 (base 100) at
//                            Q = 500 gives 250/150/100.
//   Mixed formula            percentage lines take their share of Q; whatever
//                            share of the batch the percentages leave over is
//                            split across the fixed lines in proportion to
//                            their fixed quantities.
//
// On the happy path the ingredients sum to exactly Q — the check a farmer does
// by eye. When the formula can't cover the batch (percentages summing past
// 100, no fixed base, zero quantity) we fall back to the literal fixed
// quantity and let the caller surface the shortfall rather than emitting
// zeros or negatives.

import type { FeedFormulaLine } from "@/lib/api/poultry-feed-production"

export type FormulaShape = "percentage" | "fixed" | "mixed" | "empty"

export interface FormulaCoverage {
  pctTotal: number
  fixedBase: number
  shape: FormulaShape
}

// QuantityUsed is DECIMAL(14,3) — round to what the column can actually hold.
const QTY_DP = 3
export const roundQty = (n: number) => Number(n.toFixed(QTY_DP))

const isPct = (l: FeedFormulaLine) => l.quantityMode === "Percentage"
const pctOf = (l: FeedFormulaLine) => Number(l.percentage) || 0
const fixedOf = (l: FeedFormulaLine) => Number(l.fixedQuantity) || 0

export function formulaCoverage(lines: FeedFormulaLine[] | null | undefined): FormulaCoverage {
  const ls = lines ?? []
  const pctLines = ls.filter(isPct)
  const fixedLines = ls.filter((l) => !isPct(l))
  const pctTotal = pctLines.reduce((s, l) => s + pctOf(l), 0)
  const fixedBase = fixedLines.reduce((s, l) => s + fixedOf(l), 0)
  const shape: FormulaShape = !ls.length
    ? "empty"
    : pctLines.length && fixedLines.length
      ? "mixed"
      : pctLines.length
        ? "percentage"
        : "fixed"
  return { pctTotal, fixedBase, shape }
}

/**
 * How much of each ingredient one unit of output needs.
 * Returns poultryFeedFormulaLineId → quantity per unit produced.
 *
 * Only lines that scale linearly appear. A fixed line falls out of the map when
 * the formula can't scale it (no fixed base, or percentages already at/over
 * 100) — it is then a constant, so it can't be expressed per unit and can't
 * limit how much the batch can be. Callers use this to answer "how much can I
 * actually produce with the stock I have?".
 */
export function formulaUnitFactors(lines: FeedFormulaLine[] | null | undefined): Map<number, number> {
  const ls = lines ?? []
  const out = new Map<number, number>()
  const { pctTotal, fixedBase, shape } = formulaCoverage(ls)
  // Share of each unit produced that the fixed lines divide between them.
  const fixedShare = shape === "fixed" ? 1 : (100 - pctTotal) / 100

  for (const l of ls) {
    if (isPct(l)) {
      out.set(l.poultryFeedFormulaLineId, pctOf(l) / 100)
    } else if (fixedBase > 0 && fixedShare > 0) {
      out.set(l.poultryFeedFormulaLineId, (fixedShare * fixedOf(l)) / fixedBase)
    }
  }
  return out
}

/**
 * Distribute `quantityToProduce` across a formula's ingredient lines.
 * Returns poultryFeedFormulaLineId → required quantity.
 */
export function scaleFormulaLines(
  lines: FeedFormulaLine[] | null | undefined,
  quantityToProduce: number,
): Map<number, number> {
  const ls = lines ?? []
  const out = new Map<number, number>()
  const q = Number(quantityToProduce) || 0
  // Nothing to distribute yet — every line is blank, not its literal recipe amount.
  if (q <= 0) {
    for (const l of ls) out.set(l.poultryFeedFormulaLineId, 0)
    return out
  }
  const { pctTotal, fixedBase, shape } = formulaCoverage(ls)

  // Share of the batch left for the fixed lines once the percentages take theirs.
  // Pure-fixed formulas get the whole batch.
  const remainder = shape === "fixed" ? q : q * ((100 - pctTotal) / 100)
  // Scale fixed lines only when there is a real base and a real share to split.
  const canScaleFixed = q > 0 && fixedBase > 0 && remainder > 0
  const fixedScale = canScaleFixed ? remainder / fixedBase : 0

  for (const l of ls) {
    const required = isPct(l)
      ? (q * pctOf(l)) / 100
      : canScaleFixed
        ? fixedOf(l) * fixedScale
        : fixedOf(l) // fall back to the literal recipe amount
    out.set(l.poultryFeedFormulaLineId, roundQty(required))
  }
  return out
}

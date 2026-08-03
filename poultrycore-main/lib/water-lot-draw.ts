// Previewing which purchase lots a production batch will consume.
//
// Approving a water batch walks the item's open lots in its FIFO/LIFO/HIFO order
// and takes what it needs — see spWaterRawMaterialItem_ConsumeBatches (migration
// 188). This is the same walk, done client-side, so the form can show the split
// and the resulting price while the quantity is being typed:
//
//   Lot A   5 Jan    1,000 m @ 2.00/m    GHS 2,000
//   Lot B   20 Jan     500 m @ 2.50/m    GHS 1,250
//   ------------------------------------------------
//   1,500 m                              GHS 3,250   (2.1667/m)
//
// It is a PREVIEW, not the decision. The server re-runs the real draw at
// approval, and between the two another batch may have consumed the same lots.
// The numbers agree as long as this walk matches the SP: same order (the API
// returns the lots pre-sorted by policy, ties on purchase id), same arithmetic.
//
// UNITS. Lots hold their balance in PURCHASE units; a batch is typed in
// PRODUCTION units. Every lot carries both, so the walk compares production
// against production and reports the take in both.

import type { WaterRawMaterialLot } from "@/lib/api/water"

export interface LotTake {
  lot: WaterRawMaterialLot
  /** Taken from this lot, in the units the batch is typed in. */
  productionQuantity: number
  /** The same take in purchase units — what the lot's balance goes down by. */
  purchaseQuantity: number
  /** productionQuantity x the lot's production unit cost. */
  cost: number
}

export interface DrawPlan {
  takes: LotTake[]
  /** Everything the open lots can supply, in production units. */
  available: number
  /** What the takes add up to — equals the requested quantity unless short. */
  drawn: number
  /** Requested beyond what the lots hold. Above zero, approval will refuse. */
  shortfall: number
  totalCost: number
  /** Weighted average per production unit — what the line gets costed at. */
  unitCost: number
}

// The SP tolerates a rounding hair before calling a draw short; matching it here
// keeps the preview from crying shortfall on a quantity the server would accept.
const EPSILON = 0.0005

/**
 * Walk `lots` (already in the item's consumption order) taking `needed`
 * production units. Returns the split, the blended unit cost, and any shortfall.
 */
export function planDraw(lots: WaterRawMaterialLot[], needed: number): DrawPlan {
  const available = lots.reduce((s, l) => s + Number(l.remainingProductionQuantity ?? 0), 0)
  const want = Number(needed) || 0

  const empty: DrawPlan = { takes: [], available, drawn: 0, shortfall: 0, totalCost: 0, unitCost: 0 }
  if (want <= 0) return empty

  const takes: LotTake[] = []
  let remaining = want
  for (const lot of lots) {
    if (remaining <= EPSILON) break
    const lotProd = Number(lot.remainingProductionQuantity ?? 0)
    if (lotProd <= 0) continue

    const productionQuantity = Math.min(lotProd, remaining)
    // Guard the divisor: a lot with no conversion factor is 1:1.
    const mult = Number(lot.productionUnitsPerPurchaseUnit) || 1
    takes.push({
      lot,
      productionQuantity,
      purchaseQuantity: productionQuantity / mult,
      cost: productionQuantity * Number(lot.productionUnitCost ?? 0),
    })
    remaining -= productionQuantity
  }

  const drawn = takes.reduce((s, t) => s + t.productionQuantity, 0)
  const totalCost = takes.reduce((s, t) => s + t.cost, 0)
  return {
    takes,
    available,
    drawn,
    shortfall: Math.max(0, want - drawn),
    totalCost,
    // From the draw, not from any one lot's price — a line spanning two lots is
    // costed at the blend, which is what the server writes to the usage row.
    unitCost: drawn > 0 ? totalCost / drawn : 0,
  }
}

/** Open lots for one item, from a farm-wide list. Order is preserved. */
export function lotsForItem(lots: WaterRawMaterialLot[], itemId: number): WaterRawMaterialLot[] {
  return lots.filter((l) => l.waterRawMaterialItemId === itemId)
}

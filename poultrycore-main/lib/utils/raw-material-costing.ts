import type { PoultryRawMaterialItem, PoultryRawMaterialPurchase, RawMaterialUsageMethod } from "@/lib/api/poultry-inventory"

// Mirrors the server-side FIFO/LIFO/HIFO batch walk
// (spPoultryRawMaterialItem_ConsumeBatches in migration 146) so the "used from
// inventory" pickers can show a live cost preview before saving. The server
// recomputes and persists the authoritative cost/quantity at save time — this
// is a preview only and can be stale if purchases changed since the page loaded.

export interface BatchCostPreview {
  /** Quantity-weighted average unit cost across the batches that would be drawn, or null if none available. */
  unitCost: number | null
  /** unitCost * quantity requested (best-effort even if there's a shortfall). */
  totalCost: number | null
  /** How much of the requested quantity is actually covered by tracked batch stock. */
  quantityCovered: number
  /** requested - quantityCovered; > 0 means the server will reject the save (insufficient batch stock). */
  shortfall: number
}

const EMPTY_PREVIEW: BatchCostPreview = { unitCost: null, totalCost: null, quantityCovered: 0, shortfall: 0 }

export function previewBatchConsumption(
  item: Pick<PoultryRawMaterialItem, "poultryRawMaterialItemId" | "usageMethod"> | null | undefined,
  purchases: PoultryRawMaterialPurchase[],
  neededQty: number,
): BatchCostPreview {
  if (!item || !neededQty || neededQty <= 0) return EMPTY_PREVIEW

  const method: RawMaterialUsageMethod = item.usageMethod ?? "FIFO"
  const candidates = purchases.filter(
    (p) => p.poultryRawMaterialItemId === item.poultryRawMaterialItemId && p.remainingQuantity > 0,
  )

  const sorted = [...candidates].sort((a, b) => {
    if (method === "HIFO") {
      if (b.unitCost !== a.unitCost) return b.unitCost - a.unitCost
      return a.poultryRawMaterialPurchaseId - b.poultryRawMaterialPurchaseId
    }
    const ad = new Date(a.purchaseDate).getTime()
    const bd = new Date(b.purchaseDate).getTime()
    const direction = method === "LIFO" ? -1 : 1
    if (ad !== bd) return direction * (ad - bd)
    return a.poultryRawMaterialPurchaseId - b.poultryRawMaterialPurchaseId
  })

  // neededQty is in PRODUCTION units (the item's stock unit). A batch's
  // availability in production units = remainingQuantity (purchase units) x
  // units-per-purchase; its cost per production unit = unitCost / units-per-purchase.
  let remaining = neededQty
  let coveredQty = 0   // production units covered
  let coveredCost = 0  // money
  for (const p of sorted) {
    if (remaining <= 0) break
    const mult = p.productionUnitsPerPurchaseUnit && p.productionUnitsPerPurchaseUnit > 0 ? p.productionUnitsPerPurchaseUnit : 1
    const availProd = p.remainingQuantity * mult
    const take = Math.min(availProd, remaining)
    if (take <= 0) continue
    coveredQty += take
    coveredCost += (take / mult) * p.unitCost   // purchase-equivalent x per-purchase cost
    remaining -= take
  }

  const shortfall = Math.max(0, neededQty - coveredQty)
  const unitCost = coveredQty > 0 ? coveredCost / coveredQty : null   // per production unit
  const totalCost = unitCost !== null ? unitCost * neededQty : null

  return { unitCost, totalCost, quantityCovered: coveredQty, shortfall }
}

interface SequentialLine {
  item: Pick<PoultryRawMaterialItem, "poultryRawMaterialItemId" | "usageMethod"> | null | undefined
  qty: number
}

/**
 * Per-item quantity (and its cost) that the record being EDITED already consumed.
 * On save the server reverses these draws before re-applying, restoring that stock
 * to the lots — so the preview must credit it back, otherwise editing an existing
 * record shows a false shortfall (e.g. used 140 of 150; on edit the lot reads 10,
 * and re-entering 140 looks impossible even though the save would succeed).
 */
export type ConsumptionCredit = Record<number, { qty: number; unitCost: number }>

interface WorkingLot {
  unitCost: number
  purchaseDate: string
  id: number
  remaining: number   // in PURCHASE units (production units for the credit lot)
  mult: number        // production units per purchase unit (1 for credit)
  isCredit?: boolean
}

/**
 * Preview several consumption lines that all draw from the SAME purchase pool, in
 * order — mirroring the server, which applies each line one after another. Lines
 * sharing an item deplete a single running balance, so two lines that together
 * exceed stock are correctly flagged (a per-line preview would pass each one on
 * its own full-stock view). Feed and medication are separate pools here (their
 * categories are disjoint), so they can be previewed independently.
 *
 * `credit` adds back what the record being edited already consumed (see
 * ConsumptionCredit) so an edit doesn't falsely block on the record's own stock.
 */
export function previewLinesSequential(
  lines: SequentialLine[],
  purchases: PoultryRawMaterialPurchase[],
  credit?: ConsumptionCredit,
): BatchCostPreview[] {
  // Mutable working copy of each lot's remaining quantity, grouped by item. The
  // lot objects are shared across lines, so a draw by one line is visible to the
  // next.
  const lotsByItem = new Map<number, WorkingLot[]>()
  for (const p of purchases) {
    if (p.remainingQuantity <= 0) continue
    const arr = lotsByItem.get(p.poultryRawMaterialItemId) ?? []
    arr.push({ unitCost: p.unitCost, purchaseDate: p.purchaseDate, id: p.poultryRawMaterialPurchaseId, remaining: p.remainingQuantity, mult: p.productionUnitsPerPurchaseUnit && p.productionUnitsPerPurchaseUnit > 0 ? p.productionUnitsPerPurchaseUnit : 1 })
    lotsByItem.set(p.poultryRawMaterialItemId, arr)
  }
  // Add the record's own prior consumption back as a synthetic "credit" lot per
  // item, drawn first (it reproduces the cost this record was already charged).
  if (credit) {
    for (const [idStr, c] of Object.entries(credit)) {
      if (!c || c.qty <= 0) continue
      const id = Number(idStr)
      const arr = lotsByItem.get(id) ?? []
      arr.push({ unitCost: c.unitCost, purchaseDate: "1900-01-01", id: -1, remaining: c.qty, mult: 1, isCredit: true })
      lotsByItem.set(id, arr)
    }
  }

  return lines.map(({ item, qty }) => {
    if (!item || !qty || qty <= 0) return { ...EMPTY_PREVIEW }

    const method: RawMaterialUsageMethod = item.usageMethod ?? "FIFO"
    const lots = lotsByItem.get(item.poultryRawMaterialItemId) ?? []
    const sorted = [...lots].sort((a, b) => {
      // The credited stock is what will be reversed-and-redrawn, so draw it first.
      if (!!a.isCredit !== !!b.isCredit) return a.isCredit ? -1 : 1
      if (method === "HIFO") {
        if (b.unitCost !== a.unitCost) return b.unitCost - a.unitCost
        return a.id - b.id
      }
      const ad = new Date(a.purchaseDate).getTime()
      const bd = new Date(b.purchaseDate).getTime()
      const direction = method === "LIFO" ? -1 : 1
      if (ad !== bd) return direction * (ad - bd)
      return a.id - b.id
    })

    // Work in PRODUCTION units (the item's stock unit, what `qty` is entered in).
    // A lot's production availability = remaining (purchase units) x mult.
    let remaining = qty
    let coveredQty = 0
    let coveredCost = 0
    for (const lot of sorted) {
      if (remaining <= 0) break
      const availProd = lot.remaining * lot.mult
      const take = Math.min(availProd, remaining)
      if (take <= 0) continue
      coveredQty += take
      coveredCost += (take / lot.mult) * lot.unitCost   // purchase-equivalent x per-purchase cost
      remaining -= take
      lot.remaining -= take / lot.mult // deplete the shared lot (its own unit) so later lines see less
    }

    const shortfall = Math.max(0, qty - coveredQty)
    const unitCost = coveredQty > 0 ? coveredCost / coveredQty : null
    const totalCost = unitCost !== null ? unitCost * qty : null
    return { unitCost, totalCost, quantityCovered: coveredQty, shortfall }
  })
}

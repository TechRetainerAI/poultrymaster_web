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

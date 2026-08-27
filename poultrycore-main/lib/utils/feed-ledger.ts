import type {
  PoultryRawMaterialItem,
  PoultryRawMaterialPurchase,
  PoultryRawMaterialUsage,
  PoultryRawMaterialAdjustment,
} from "@/lib/api/poultry-inventory"

/**
 * Feed stock ledger — a view over the poultry RAW MATERIALS store.
 *
 * This used to read its incoming side from the legacy Supplies table
 * (`/supplies`), filtering for a type containing "feed". Feed is actually bought
 * on /poultry-raw-materials, which writes poultryrawmaterialpurchases. Those are
 * two unconnected inventory systems, and Supplies has never held a single feed
 * row on this database — so the IN side was permanently zero and every farm
 * showed a negative balance equal to its total usage. Measured before the
 * change: Prof Owusu -64,673 kg, Sky Farm -14,236 kg (holding 13,261),
 * Gyimah -212 kg (holding 940).
 *
 * The ledger now uses the same three movements that maintain
 * poultryrawmaterialitems.currentquantity, so the balance here and the stock on
 * /poultry-raw-materials are the same number by construction:
 *
 *     purchases  -  usage  +  adjustments  =  current quantity
 *
 * Usage rows are included even when a later reversal put the stock back: each
 * reversal is a matching 'ProductionReversal' / 'FeedProductionReversal'
 * adjustment, so both appear and net to zero. Showing them is the point of a
 * ledger — the movement happened and then it was undone.
 *
 * Verified against the live database: this identity reproduces currentquantity
 * for 22 of 27 feed items. The five that differ are on the two test farms and
 * predate this change (two of them already hold negative stock).
 *
 * Units: 23 of 27 feed items are stocked in Kilogram, 4 in Bag (all with a 1:1
 * conversion recorded). Quantities are summed as stored and each row states its
 * own unit, rather than pretending a bag is a kilogram.
 */

export interface FeedLedgerRow {
  sortKey: string
  date: string
  type: string
  description: string
  in: number
  out: number
  balance: number
}

type LineInput = {
  sortKey: string
  date: string
  type: string
  description: string
  in: number
  out: number
  order: number
}

/** Manual corrections from Feed tracker (API); kg — positive adds, negative removes. */
export interface FeedInventoryAdjustmentLedgerInput {
  adjustmentId: number
  adjustmentDate: string
  feedDeltaKg: number
  adjustmentType: string
  description?: string | null
}

function formatFeedAdjustmentType(t: string): string {
  switch (t) {
    case "OpeningBalance":
      return "Opening balance"
    case "Stocktake":
      return "Stocktake"
    case "Correction":
      return "Correction"
    default:
      return t || "Adjustment"
  }
}

/** The raw-material categories that count as feed. */
export const FEED_CATEGORIES = ["FinishedFeed", "FeedIngredient"] as const

export function isFeedItem(item: Pick<PoultryRawMaterialItem, "category">): boolean {
  const c = (item.category || "").trim().toLowerCase()
  return c === "finishedfeed" || c === "feedingredient"
}

function iso(dateRaw: string | null | undefined): string {
  const d = (dateRaw || "").trim()
  if (!d) return new Date(0).toISOString()
  const parsed = new Date(d)
  return Number.isNaN(parsed.getTime()) ? new Date(0).toISOString() : parsed.toISOString()
}

const unitBit = (unit: string | null | undefined) => {
  const u = (unit || "").trim()
  return u ? ` ${u}` : ""
}

export interface FeedStockLedgerInput {
  items: PoultryRawMaterialItem[]
  purchases: PoultryRawMaterialPurchase[]
  usages: PoultryRawMaterialUsage[]
  /** Stock movements from /poultry-raw-materials (reversals, manual corrections). */
  adjustments: PoultryRawMaterialAdjustment[]
  /** Corrections entered on this page itself. Unused on the live data so far. */
  manualAdjustments?: FeedInventoryAdjustmentLedgerInput[]
}

/**
 * Feed stock: IN from raw-material feed purchases, OUT from feed consumption,
 * plus the stock adjustments that accompany reversals.
 */
export function buildFeedStockLedger(
  input: FeedStockLedgerInput,
): { rows: FeedLedgerRow[]; feedKgAtHand: number; lastUpdatedIso: string; totalInKg: number; totalOutKg: number } {
  const { items, purchases, usages, adjustments, manualAdjustments = [] } = input

  // Which item ids are feed. The list endpoints already return itemName/category
  // on each row, but the item list is the authority — a row's own category can
  // be null on older records.
  const feedItemIds = new Set(items.filter(isFeedItem).map((i) => i.poultryRawMaterialItemId))
  const itemById = new Map(items.map((i) => [i.poultryRawMaterialItemId, i]))
  const isFeed = (id: number, rowCategory?: string | null) =>
    feedItemIds.has(id) ||
    ["finishedfeed", "feedingredient"].includes((rowCategory || "").trim().toLowerCase())

  const nameOf = (id: number, fallback?: string | null) =>
    itemById.get(id)?.itemName || fallback || `Item #${id}`
  const unitOf = (id: number, fallback?: string | null) =>
    itemById.get(id)?.unitOfMeasure || fallback || ""

  const lines: LineInput[] = []

  for (const p of purchases) {
    if (!isFeed(p.poultryRawMaterialItemId, p.category)) continue
    const qty = Number(p.quantity) || 0
    if (qty <= 0) continue
    const unit = unitOf(p.poultryRawMaterialItemId, p.unitOfMeasure)
    const from = (p.supplierName || "").trim()
    lines.push({
      sortKey: `purchase_${p.poultryRawMaterialPurchaseId}`,
      date: iso(p.purchaseDate),
      type: "Purchase IN",
      description: `${nameOf(p.poultryRawMaterialItemId, p.itemName)} — purchased (${qty}${unitBit(unit)})${from ? ` from ${from}` : ""}`,
      in: qty,
      out: 0,
      order: 0,
    })
  }

  for (const u of usages) {
    if (!isFeed(u.poultryRawMaterialItemId, null)) continue
    const qty = Number(u.quantityUsed) || 0
    if (qty <= 0) continue
    const unit = unitOf(u.poultryRawMaterialItemId, u.unitOfMeasure)
    // A feed-production batch consumes ingredients to make finished feed; that
    // is a genuine outflow of the ingredient and has no flock attached.
    const via = u.poultryFeedProductionBatchId
      ? ` — feed production ${u.feedProductionBatchNumber ?? `#${u.poultryFeedProductionBatchId}`}`
      : " — used in production"
    lines.push({
      sortKey: `usage_${u.poultryRawMaterialUsageId}`,
      date: iso(u.usedDate),
      type: "Usage OUT",
      description: `${nameOf(u.poultryRawMaterialItemId, u.itemName)}${via} (${qty}${unitBit(unit)})`,
      in: 0,
      out: qty,
      order: 1,
    })
  }

  for (const a of adjustments) {
    if (!isFeed(a.poultryRawMaterialItemId, a.category)) continue
    const qty = Number(a.quantity) || 0
    if (qty === 0) continue
    const unit = unitOf(a.poultryRawMaterialItemId, a.unitOfMeasure)
    const label = (a.movementType || "Adjustment").trim()
    const note = (a.note || "").trim()
    lines.push({
      sortKey: `stockadj_${a.poultryRawMaterialAdjustmentId}`,
      date: iso(a.adjustedDate),
      type: "Adjustment",
      description: `${nameOf(a.poultryRawMaterialItemId, a.itemName)} — ${label}${note ? `: ${note}` : ""} (${Math.abs(qty)}${unitBit(unit)})`,
      in: qty > 0 ? qty : 0,
      out: qty < 0 ? -qty : 0,
      order: 2,
    })
  }

  for (const a of manualAdjustments) {
    const d = Number(a.feedDeltaKg)
    if (!Number.isFinite(d) || d === 0) continue
    const typeLabel = formatFeedAdjustmentType(a.adjustmentType)
    const desc = (a.description || "").trim() || typeLabel
    lines.push({
      sortKey: `feedadj_${a.adjustmentId}`,
      date: iso(a.adjustmentDate),
      type: "Adjustment",
      description: `${typeLabel}: ${desc}`,
      in: d > 0 ? d : 0,
      out: d < 0 ? -d : 0,
      order: 3,
    })
  }

  lines.sort((a, b) => {
    const da = new Date(a.date).getTime()
    const db = new Date(b.date).getTime()
    if (da !== db) return da - db
    if (a.order !== b.order) return a.order - b.order
    return a.sortKey.localeCompare(b.sortKey)
  })

  let bal = 0
  let totalInKg = 0
  let totalOutKg = 0
  const rows: FeedLedgerRow[] = lines.map((line) => {
    bal += line.in - line.out
    totalInKg += line.in
    totalOutKg += line.out
    return {
      sortKey: line.sortKey,
      date: line.date,
      type: line.type,
      description: line.description,
      in: line.in,
      out: line.out,
      balance: bal,
    }
  })

  return {
    rows,
    feedKgAtHand: rows.length > 0 ? rows[rows.length - 1].balance : 0,
    lastUpdatedIso: rows.length > 0 ? rows[rows.length - 1].date : new Date().toISOString(),
    totalInKg,
    totalOutKg,
  }
}

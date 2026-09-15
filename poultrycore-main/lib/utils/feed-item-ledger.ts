import type {
  PoultryRawMaterialItem,
  PoultryRawMaterialPurchase,
  PoultryRawMaterialUsage,
  PoultryRawMaterialAdjustment,
} from "@/lib/api/poultry-inventory"

/**
 * Per-item feed stock ledger — the poultry counterpart to the water Inventory
 * tracker (/water-inventory-tracker, migration 221).
 *
 * WHAT THIS IS FOR
 * ----------------
 * /feed-tracker answers "how much feed does the farm hold", pooling every feed
 * item into one running figure. It cannot answer "this item says 4,300 — why?",
 * because the movements of a dozen different items are interleaved in one
 * balance. This module runs the ledger SEPARATELY per item, so an item's
 * opening + in - out lands exactly on its own closing.
 *
 * WHY IT IS BUILT ON THE CLIENT AND NOT IN SQL
 * --------------------------------------------
 * Water needed a stored function because waterstocktransactions mixes bags and
 * sachets and only the server could normalise them. Poultry has no such
 * problem: stock is maintained by ONE arithmetic identity, spelled out in
 * migration 175 (spPoultryRawMaterialItem_RecalculateStock):
 *
 *     currentquantity = SUM(purchase.quantity * productionUnitsPerPurchaseUnit)
 *                     - SUM(usage.quantityUsed)
 *                     + SUM(adjustment.quantity)        -- signed
 *
 * All three source lists are already exposed by endpoints this app calls, so the
 * tracker reproduces that identity here rather than adding a fourth read path
 * that could drift from it. Change this file only alongside 175.
 *
 * THE PURCHASE UNIT TRAP
 * ----------------------
 * A purchase is recorded in the unit it was BOUGHT in (a 50kg bag), while stock
 * is held in the unit it is USED in (kg). `productionUnitsPerPurchaseUnit` is
 * the bridge, and migration 157 is what made purchases post through it. Summing
 * `quantity` raw — as the pooled ledger in feed-ledger.ts still does —
 * undercounts every item whose two units differ. On the live database 7 of 59
 * feed purchases carry a factor other than 1 (up to 1000), so this is a real
 * difference, not a theoretical one. Use `productionQty()`; never `p.quantity`.
 */

/** Which half of the feed store an item belongs to. */
export type FeedItemKind = "Ingredient" | "FinishedFeed"

/**
 * Matched the same way the feed formula builder and the feed production batch
 * form match them (components/feed-production/batch-form.tsx), so an item that
 * can be picked as an ingredient there is trackable here. Category is free text
 * by convention — migration 167 added 'FinishedFeed' without a schema change —
 * hence a pattern rather than an equality test.
 */
export const isFinishedFeedCategory = (c?: string | null) => !!c && /finish/i.test(c)
export const isIngredientCategory = (c?: string | null) =>
  !!c && /feed/i.test(c) && !isFinishedFeedCategory(c)

export function feedItemKind(c?: string | null): FeedItemKind | null {
  if (isFinishedFeedCategory(c)) return "FinishedFeed"
  if (isIngredientCategory(c)) return "Ingredient"
  return null
}

/** Movement families. The In/Out split is carried by the quantities, not by this. */
export type FeedMovementKind = "Purchase" | "Usage" | "Adjustment"

export interface FeedItemMovement {
  /** Stable across reloads: source table + that row's own id. */
  key: string
  itemId: number
  /**
   * yyyy-mm-dd, sliced from the stored timestamp rather than parsed through
   * Date — a timestamp at midnight shifts a day in any negative-offset zone.
   */
  date: string
  /** Full timestamp, for ordering movements that share a day. */
  timestamp: string
  kind: FeedMovementKind
  /** Display wording. Defined here only, so the table and the type filter agree. */
  label: string
  description: string
  inQty: number
  outQty: number
  /** Running balance for THIS item, accumulated from its first movement ever. */
  balance: number
  /** Ascending position in this item's own ledger; `balance` follows it. */
  seq: number

  // Money, on usage rows only (migration 268). Two figures because either alone
  // misleads: `cost` is what the stock drawn was worth, `recognized` only the
  // part that reached Profit & Loss at this draw — zero on stock already
  // expensed at purchase, which does not make the feed free.
  cost?: number
  recognized?: number
  costLayers?: number
  /** A reversed draw keeps its row; its money must not be totalled twice. */
  reversed?: boolean
  /** 288. The record to ask for a cost breakdown. Null on feed-production draws. */
  productionRecordId?: number | null
}

export interface FeedItemPosition {
  itemId: number
  itemName: string
  category: string
  kind: FeedItemKind
  /** The unit stock is HELD in, which is the unit every figure here is in. */
  unit: string
  isActive: boolean
  minimumStockAlert: number

  // Period figures. opening + inQty - outQty === closing, by construction.
  opening: number
  inQty: number
  outQty: number
  closing: number
  movementCount: number

  /** Balance after every movement ever recorded, period ignored. */
  derivedNow: number
  /** poultryrawmaterialitems.currentquantity — what every other screen shows. */
  onRecord: number
  /**
   * derivedNow - onRecord. Non-zero means the stored running total and its own
   * source rows disagree; migration 175's Recalculate stock is the repair. The
   * tracker reports it rather than quietly picking one of the two figures.
   */
  drift: number
  /** Most recent movement of any kind, all-time. Null for an item never moved. */
  lastMovementDate: string | null
}

/**
 * One line of the "All feed ingredients" / "All finished feed" roll-up.
 *
 * Totals are grouped BY UNIT and never across them. Feed is stocked in
 * Kilogram, Bag and Sack on the live database, and one farm holds both
 * Kilogram and Bag items in each half — adding those together would produce a
 * number with no unit and no meaning. A farm whose feed is all in one unit sees
 * a single line, which is the common case and reads as one plain total.
 */
export interface FeedUnitTotals {
  /** The stocking unit these figures are in. Empty string when an item has none. */
  unit: string
  items: number
  opening: number
  inQty: number
  outQty: number
  closing: number
  /** Sum of the stored stock figures — what the Raw Materials page shows. */
  onRecord: number
  movementCount: number
  /** How many of these items disagree with their own movements (see `drift`). */
  driftItems: number
}

export interface FeedItemLedgerInput {
  items: PoultryRawMaterialItem[]
  purchases: PoultryRawMaterialPurchase[]
  usages: PoultryRawMaterialUsage[]
  adjustments: PoultryRawMaterialAdjustment[]
}

/** yyyy-mm-dd from a stored timestamp, without going through Date. */
export function dayOf(raw: string | null | undefined): string {
  const s = (raw || "").trim()
  return s ? s.slice(0, 10) : ""
}

/**
 * A purchase in STOCK units. See "The purchase unit trap" above.
 * A factor of 0 is treated as 1, exactly as migration 175's NULLIF(...,0) does —
 * a zero would otherwise erase the whole purchase.
 */
export function productionQty(p: PoultryRawMaterialPurchase): number {
  const qty = Number(p.quantity) || 0
  const factor = Number(p.productionUnitsPerPurchaseUnit) || 1
  return qty * factor
}

const num = (n: number) => n.toLocaleString(undefined, { maximumFractionDigits: 3 })

const humanMovementType = (t?: string | null): string => {
  const v = (t || "").trim()
  if (!v) return "Adjustment"
  switch (v) {
    case "ProductionReversal":     return "Production reversed"
    case "FeedProductionReversal": return "Feed production reversed"
    case "Correction":             return "Correction"
    case "Stocktake":              return "Stocktake"
    case "OpeningBalance":         return "Opening balance"
    // Anything else is shown as recorded rather than flattened to "Adjustment",
    // which would hide a movement type this list has not caught up with.
    default: return v.replace(/([a-z])([A-Z])/g, "$1 $2")
  }
}

type Draft = Omit<FeedItemMovement, "balance" | "seq"> & { order: number; id: number }

/**
 * Every feed movement, grouped by item and in ledger order, with a running
 * balance per item. Period-independent: the caller slices the window it wants,
 * which is what lets the opening balance be read straight off this.
 */
export function buildFeedItemMovements(input: FeedItemLedgerInput): Map<number, FeedItemMovement[]> {
  const { items, purchases, usages, adjustments } = input

  // The item list is the authority on category: a purchase or adjustment row
  // carries its own copy, which is null on older records.
  const feedItems = new Map<number, PoultryRawMaterialItem>()
  for (const i of items) {
    if (feedItemKind(i.category)) feedItems.set(i.poultryRawMaterialItemId, i)
  }

  const unitOf = (id: number, fallback?: string | null) =>
    (feedItems.get(id)?.unitOfMeasure || fallback || "").trim()

  const drafts = new Map<number, Draft[]>()
  const push = (id: number, d: Draft) => {
    const list = drafts.get(id)
    if (list) list.push(d)
    else drafts.set(id, [d])
  }

  for (const p of purchases) {
    const id = p.poultryRawMaterialItemId
    if (!feedItems.has(id)) continue
    const qty = productionQty(p)
    if (qty === 0) continue
    const unit = unitOf(id, p.unitOfMeasure)
    const batch = p.feedProductionBatchNumber ?? (p.sourceFeedProductionBatchId ? `#${p.sourceFeedProductionBatchId}` : null)
    const supplier = (p.supplierName || "").trim()

    // Three different events share the purchases table, and calling all three
    // "Purchase" would make a farm's own produced feed look bought.
    let label = "Purchase"
    let description = supplier ? `Purchased from ${supplier}` : "Purchased"
    if (p.feedProductionRole === "Produced") {
      label = "Produced"
      description = batch ? `Produced by feed batch ${batch}` : "Produced by feed production"
    } else if (p.feedProductionRole === "Purchased" || p.sourceFeedProductionBatchId) {
      label = "Bought for production"
      description = batch
        ? `Bought for feed batch ${batch}${supplier ? ` from ${supplier}` : ""}`
        : "Bought during feed production"
    }
    // A purchase entered in bags reads as a bag count on every other screen, so
    // show the conversion rather than silently printing a different number.
    const factor = Number(p.productionUnitsPerPurchaseUnit) || 1
    if (factor !== 1) {
      const bought = Number(p.quantity) || 0
      // The purchase row has no unit of its own; the item says what it is bought in.
      const boughtUnit = (feedItems.get(id)?.purchaseUnitOfMeasure || "").trim()
      description += ` — ${num(bought)}${boughtUnit ? ` ${boughtUnit}` : ""}` +
        ` × ${num(factor)} = ${num(qty)}${unit ? ` ${unit}` : ""}`
    }
    if ((p.notes || "").trim()) description += ` · ${(p.notes || "").trim()}`

    push(id, {
      key: `purchase_${p.poultryRawMaterialPurchaseId}`,
      id: p.poultryRawMaterialPurchaseId,
      itemId: id,
      date: dayOf(p.purchaseDate),
      timestamp: p.purchaseDate || "",
      kind: "Purchase",
      label,
      description,
      inQty: qty > 0 ? qty : 0,
      outQty: qty < 0 ? -qty : 0,
      order: 0,
    })
  }

  for (const u of usages) {
    const id = u.poultryRawMaterialItemId
    if (!feedItems.has(id)) continue
    const qty = Number(u.quantityUsed) || 0
    if (qty === 0) continue

    const batch = u.feedProductionBatchNumber ?? (u.poultryFeedProductionBatchId ? `#${u.poultryFeedProductionBatchId}` : null)
    let label = "Fed to flock"
    let description = "Consumed in production"
    if (u.poultryFeedProductionBatchId) {
      // An ingredient drawn into a feed batch genuinely leaves stock; it has no
      // flock behind it, and calling it "fed" would be wrong.
      label = "Used in feed production"
      description = batch ? `Drawn into feed batch ${batch}` : "Drawn into feed production"
      if ((u.feedProductionFeedName || "").trim()) description += ` → ${(u.feedProductionFeedName || "").trim()}`
    }
    if ((u.varianceReason || "").trim()) description += ` · ${(u.varianceReason || "").trim()}`
    if ((u.notes || "").trim()) description += ` · ${(u.notes || "").trim()}`
    if (u.isReversed) description += " · reversed"

    push(id, {
      key: `usage_${u.poultryRawMaterialUsageId}`,
      id: u.poultryRawMaterialUsageId,
      itemId: id,
      date: dayOf(u.usedDate),
      timestamp: u.usedDate || "",
      kind: "Usage",
      label,
      description,
      inQty: qty < 0 ? -qty : 0,
      outQty: qty > 0 ? qty : 0,
      order: 1,
      cost: u.operationalCost,
      recognized: u.recognizedCost,
      costLayers: u.costLayerCount,
      reversed: u.isReversed,
      productionRecordId: u.productionRecordId ?? null,
    })
  }

  for (const a of adjustments) {
    const id = a.poultryRawMaterialItemId
    if (!feedItems.has(id)) continue
    const qty = Number(a.quantity) || 0
    if (qty === 0) continue
    const note = (a.note || "").trim()

    push(id, {
      key: `adjustment_${a.poultryRawMaterialAdjustmentId}`,
      id: a.poultryRawMaterialAdjustmentId,
      itemId: id,
      date: dayOf(a.adjustedDate),
      timestamp: a.adjustedDate || "",
      kind: "Adjustment",
      label: humanMovementType(a.movementType),
      description: note || (qty > 0 ? "Stock increased" : "Stock decreased"),
      inQty: qty > 0 ? qty : 0,
      outQty: qty < 0 ? -qty : 0,
      order: 2,
    })
  }

  const out = new Map<number, FeedItemMovement[]>()
  for (const [id, list] of drafts) {
    // Within a day the three sources have to run in a fixed order or the running
    // balance depends on which endpoint answered first: stock arrives, is drawn,
    // and is corrected afterwards.
    list.sort((a, b) => {
      if (a.timestamp !== b.timestamp) return a.timestamp < b.timestamp ? -1 : 1
      if (a.order !== b.order) return a.order - b.order
      return a.id - b.id
    })
    let balance = 0
    out.set(id, list.map((d, index) => {
      balance += d.inQty - d.outQty
      const { order: _order, id: _id, ...rest } = d
      return { ...rest, balance, seq: index }
    }))
  }
  // Feed items that have never moved still belong in the tracker: "this item has
  // not moved all month" is an answer, and dropping it would make the picker
  // disagree with the Raw Materials page.
  for (const id of feedItems.keys()) if (!out.has(id)) out.set(id, [])
  return out
}

/**
 * Per-item opening / in / out / closing for [from, to] inclusive, plus the
 * all-time position used to report drift against the stored stock figure.
 * `from`/`to` are yyyy-mm-dd; an empty string on either side means "open-ended".
 */
export function buildFeedItemPositions(
  input: FeedItemLedgerInput,
  from: string,
  to: string,
  movementsByItem?: Map<number, FeedItemMovement[]>,
): FeedItemPosition[] {
  const moves = movementsByItem ?? buildFeedItemMovements(input)
  const positions: FeedItemPosition[] = []

  for (const item of input.items) {
    const kind = feedItemKind(item.category)
    if (!kind) continue
    const list = moves.get(item.poultryRawMaterialItemId) ?? []

    let opening = 0, inQty = 0, outQty = 0, movementCount = 0
    for (const m of list) {
      if (from && m.date < from) { opening += m.inQty - m.outQty; continue }
      if (to && m.date > to) continue
      inQty += m.inQty
      outQty += m.outQty
      movementCount++
    }

    const derivedNow = list.length > 0 ? list[list.length - 1].balance : 0
    const onRecord = Number(item.currentQuantity) || 0
    positions.push({
      itemId: item.poultryRawMaterialItemId,
      itemName: item.itemName,
      category: item.category,
      kind,
      unit: (item.unitOfMeasure || "").trim(),
      isActive: item.isActive,
      minimumStockAlert: Number(item.minimumStockAlert) || 0,
      opening,
      inQty,
      outQty,
      closing: opening + inQty - outQty,
      movementCount,
      derivedNow,
      onRecord,
      // Rounded to the 3dp quantities are stored at, so float noise does not
      // raise a drift warning on an item that reconciles exactly.
      drift: Math.round((derivedNow - onRecord) * 1000) / 1000,
      lastMovementDate: list.length > 0 ? list[list.length - 1].date : null,
    })
  }

  return positions.sort((a, b) => a.itemName.localeCompare(b.itemName))
}

/**
 * Roll up a set of positions into one line per stocking unit. Pass the
 * positions of a single kind to get the "All feed ingredients" / "All finished
 * feed" figures; the result is ordered with the unit holding the most items
 * first, so the line an owner means is the one they read.
 */
export function summariseFeedPositions(positions: FeedItemPosition[]): FeedUnitTotals[] {
  const byUnit = new Map<string, FeedUnitTotals>()
  for (const p of positions) {
    const unit = p.unit
    let t = byUnit.get(unit)
    if (!t) {
      t = { unit, items: 0, opening: 0, inQty: 0, outQty: 0, closing: 0, onRecord: 0, movementCount: 0, driftItems: 0 }
      byUnit.set(unit, t)
    }
    t.items++
    t.opening += p.opening
    t.inQty += p.inQty
    t.outQty += p.outQty
    t.closing += p.closing
    t.onRecord += p.onRecord
    t.movementCount += p.movementCount
    if (p.drift !== 0) t.driftItems++
  }
  return [...byUnit.values()].sort((a, b) => b.items - a.items || a.unit.localeCompare(b.unit))
}

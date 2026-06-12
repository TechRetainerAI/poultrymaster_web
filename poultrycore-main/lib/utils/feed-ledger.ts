import type { FeedUsage } from "@/lib/api/feed-usage"
import type { Supply } from "@/lib/api/supply"
import type { Flock } from "@/lib/api/flock"

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

export function isFeedSupply(s: Pick<Supply, "type">): boolean {
  const t = (s.type || "").trim().toLowerCase()
  return t === "feed" || t.includes("feed")
}

/** Best-effort kg for ledger math; non-kg units still use numeric quantity (see UI note). */
export function supplyQuantityToKg(quantity: number, unit: string | null | undefined): number {
  const q = Math.max(0, Number(quantity) || 0)
  const u = (unit || "").trim().toLowerCase()
  if (!u || u === "kg" || u.includes("kilogram")) return q
  if (u.includes("ton")) return q * 1000
  if (u === "g" || (u.includes("g") && !u.includes("kg"))) return q / 1000
  return q
}

function flockLabel(flocks: Flock[], flockId: number): string {
  const f = flocks.find((x) => x.flockId === flockId)
  return f?.name?.trim() || `Flock #${flockId}`
}

/**
 * Feed stock: IN from Inventory supplies (category Feed), OUT from feed usage (kg),
 * plus optional manual adjustments (kg). Optional flockId limits OUT rows only; IN and adjustments stay farm-wide.
 */
export function buildFeedStockLedger(
  supplies: Supply[],
  usages: FeedUsage[],
  flocks: Flock[],
  options?: { flockId?: number | null; adjustments?: FeedInventoryAdjustmentLedgerInput[] }
): { rows: FeedLedgerRow[]; feedKgAtHand: number; lastUpdatedIso: string; totalInKg: number; totalOutKg: number } {
  const lines: LineInput[] = []
  const flockId = options?.flockId
  const adjustments = options?.adjustments ?? []
  const usagesFiltered =
    flockId != null && Number.isFinite(flockId) ? usages.filter((u) => u.flockId === flockId) : usages

  for (const s of supplies) {
    if (!isFeedSupply(s)) continue
    const qtyKg = supplyQuantityToKg(s.quantity, s.unit)
    if (qtyKg <= 0) continue
    const dateRaw = s.purchaseDate?.trim() || ""
    const date = dateRaw ? new Date(dateRaw).toISOString() : new Date(0).toISOString()
    const unitBit = (s.unit || "").trim() ? ` (${s.quantity} ${s.unit})` : ""
    lines.push({
      sortKey: `supply_${s.id}`,
      date,
      type: "Inventory IN",
      description: `${(s.name || "Feed").trim()} — purchased${unitBit}`,
      in: qtyKg,
      out: 0,
      order: 0,
    })
  }

  for (const u of usagesFiltered) {
    const kg = Math.max(0, Number(u.quantityKg) || 0)
    if (kg <= 0) continue
    lines.push({
      sortKey: `usage_${u.feedUsageId}`,
      date: u.usageDate,
      type: "Usage OUT",
      description: `${flockLabel(flocks, u.flockId)} — ${(u.feedType || "Feed").trim()} (usage)`,
      in: 0,
      out: kg,
      order: 1,
    })
  }

  for (const a of adjustments) {
    const d = Number(a.feedDeltaKg)
    if (!Number.isFinite(d) || d === 0) continue
    const dateStr = a.adjustmentDate
      ? new Date(a.adjustmentDate).toISOString()
      : new Date(0).toISOString()
    const typeLabel = formatFeedAdjustmentType(a.adjustmentType)
    const desc = (a.description || "").trim() || typeLabel
    lines.push({
      sortKey: `feedadj_${a.adjustmentId}`,
      date: dateStr,
      type: "Adjustment",
      description: `${typeLabel}: ${desc}`,
      in: d > 0 ? d : 0,
      out: d < 0 ? -d : 0,
      order: 2,
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
  let totalIn = 0
  let totalOut = 0
  const rows: FeedLedgerRow[] = lines.map((line) => {
    bal += line.in - line.out
    totalIn += line.in
    totalOut += line.out
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

  const lastUpdatedIso = rows.length > 0 ? rows[rows.length - 1].date : new Date().toISOString()

  return {
    rows,
    feedKgAtHand: rows.length > 0 ? rows[rows.length - 1].balance : 0,
    lastUpdatedIso,
    totalInKg: totalIn,
    totalOutKg: totalOut,
  }
}

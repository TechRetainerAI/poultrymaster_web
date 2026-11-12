import type { Flock } from "@/lib/api/flock"
import type { ProductionRecord } from "@/lib/api/production-record"
import { isLiveBirdProduct } from "@/lib/poultry/bird-pricing"
import type { Sale } from "@/lib/api/sale"
import type { FlockPositionRow } from "@/lib/api/flock-positions"
import { flockLifetime } from "@/lib/flocks/bird-position"
import { getBirdsLeftForFlockFromRecords } from "@/lib/utils/production-records"

export type BirdsLeftLedgerRow = {
  id: string
  date: string
  type: "IN" | "OUT"
  category: "Placement" | "Mortality" | "Bird sale" | "Cull / transfer / other"
  flockId: number
  flockName: string
  quantity: number
  description: string
  sourceId?: string | number
}

export type FlockBirdsSummary = {
  flockId: number
  flockName: string
  placedIn: number
  totalMortalityOut: number
  totalBirdSalesOut: number
  /** Culled, transferred out or otherwise lost before tracking began (Initial Farm Setup). */
  totalOtherOut: number
  birdsLeftCalculated: number
  birdsLeftFromLatestLog: number | null
}

/** The flock's server-side bird position (migration 421), when the API has it. */
export type FlockPositionLookup = Map<number, FlockPositionRow>

/**
 * Sales that reduce the live bird count. Since 403 this IS the database's rule
 * (fnpoultrysale_isbirdsale, via isLiveBirdProduct), so the Birds tracker and
 * the flock's bird position can never disagree about a sale. The old local
 * pattern also matched "Broiler feed", "Layer mash" and "Poultry manure".
 * Dead Birds (374) left the live count when they died, not when sold.
 */
export function isBirdSaleProduct(product: string | null | undefined): boolean {
  return isLiveBirdProduct(product)
}

/**
 * Birds a flock went IN with. With its position (421) that is the birds it
 * STARTED with -- originally placed; the opening live count when the farm said
 * the history is not known. Without it, flock.quantity, which for a flock from
 * Initial Farm Setup is only the opening LIVE count.
 */
function placedFor(flock: Flock, positions?: FlockPositionLookup): number {
  const p = positions?.get(flock.flockId)
  if (p) return Math.max(0, flockLifetime(p).started)
  return Math.max(0, Number(flock.quantity) || 0)
}

export function buildBirdsLeftLedger(
  flocks: Flock[],
  productionRecords: ProductionRecord[],
  sales: Sale[],
  positions?: FlockPositionLookup,
): BirdsLeftLedgerRow[] {
  const rows: BirdsLeftLedgerRow[] = []
  const flockName = (id: number) => flocks.find((f) => f.flockId === id)?.name ?? `Flock #${id}`

  for (const flock of flocks) {
    const qty = placedFor(flock, positions)
    if (qty <= 0) continue
    const start = (flock.startDate ?? "").split("T")[0] || new Date().toISOString().split("T")[0]
    const name = flock.name ?? flockName(flock.flockId)
    const p = positions?.get(flock.flockId)
    const hasHistory = !!p && p.hasOpeningPosition
    rows.push({
      id: `in-flock-${flock.flockId}`,
      date: start,
      type: "IN",
      category: "Placement",
      flockId: flock.flockId,
      flockName: name,
      quantity: qty,
      description: hasHistory
        ? `Birds originally placed (${qty.toLocaleString()})`
        : `Birds placed when flock was created (${qty.toLocaleString()})`,
      sourceId: flock.flockId,
    })

    // The opening historical reduction from Initial Farm Setup: birds that left
    // the flock before tracking began. Only when the farm broke it down -- an
    // unknown history is an adjustment, not deaths, and the flock then went IN
    // with its opening live count instead (placedFor).
    if (p && p.hasOpeningPosition && p.historyKnown) {
      const before = (id: string, category: BirdsLeftLedgerRow["category"], quantity: number, description: string) => {
        if (quantity > 0) {
          rows.push({ id: `${id}-${flock.flockId}`, date: start, type: "OUT", category, flockId: flock.flockId,
            flockName: name, quantity, description, sourceId: flock.flockId })
        }
      }
      before("hist-mort", "Mortality", p.openingMortality, "Died before tracking began (Initial Farm Setup)")
      before("hist-sale", "Bird sale", p.openingSold, "Sold before tracking began (Initial Farm Setup)")
      before("hist-cull", "Cull / transfer / other", p.openingCulled, "Culled before tracking began (Initial Farm Setup)")
      before("hist-xfer", "Cull / transfer / other", p.openingTransferred, "Transferred out before tracking began (Initial Farm Setup)")
      before("hist-other", "Cull / transfer / other", p.openingOther, "Other loss before tracking began (Initial Farm Setup)")
    }
  }

  for (const r of productionRecords) {
    const fid = r.flockId
    if (fid == null) continue
    const mort = Number(r.mortality) || 0
    if (mort <= 0) continue
    const d = (r.date ?? "").split("T")[0] || ""
    rows.push({
      id: `mort-${r.id ?? `${fid}-${d}`}`,
      date: d,
      type: "OUT",
      category: "Mortality",
      flockId: fid,
      flockName: (r as { flockName?: string }).flockName ?? flockName(fid),
      quantity: mort,
      description: `Deaths on production record`,
      sourceId: r.id,
    })
  }

  for (const s of sales) {
    if (!isBirdSaleProduct(s.product)) continue
    const fid = s.flockId
    if (fid == null) continue
    const q = Number(s.quantity) || 0
    if (q <= 0) continue
    const d = (s.saleDate ?? "").split("T")[0] || ""
    rows.push({
      id: `sale-${s.saleId ?? `${fid}-${d}`}`,
      date: d,
      type: "OUT",
      category: "Bird sale",
      flockId: fid,
      flockName: flockName(fid),
      quantity: q,
      description: s.product ? `Sale: ${s.product}` : "Bird sale",
      sourceId: s.saleId,
    })
  }

  rows.sort((a, b) => {
    const da = a.date || ""
    const db = b.date || ""
    if (da !== db) return db.localeCompare(da)
    if (a.type !== b.type) return a.type === "IN" ? -1 : 1
    return a.flockId - b.flockId
  })

  return rows
}

export function summarizeBirdsLeftByFlock(
  flocks: Flock[],
  productionRecords: ProductionRecord[],
  sales: Sale[],
  positions?: FlockPositionLookup,
): FlockBirdsSummary[] {
  const ledger = buildBirdsLeftLedger(flocks, productionRecords, sales, positions)

  return flocks.map((flock) => {
    const placedIn = placedFor(flock, positions)
    const flockRows = ledger.filter((r) => r.flockId === flock.flockId)
    const sumOf = (category: BirdsLeftLedgerRow["category"]) =>
      flockRows.filter((r) => r.category === category).reduce((s, r) => s + r.quantity, 0)
    const totalMortalityOut = sumOf("Mortality")
    const totalBirdSalesOut = sumOf("Bird sale")
    const totalOtherOut = sumOf("Cull / transfer / other")
    const birdsLeftCalculated = Math.max(0, placedIn - totalMortalityOut - totalBirdSalesOut - totalOtherOut)
    const fromLog = getBirdsLeftForFlockFromRecords(productionRecords, flock.flockId)
    const birdsLeftFromLatestLog =
      productionRecords.some((r) => r.flockId === flock.flockId) ? fromLog : null

    return {
      flockId: flock.flockId,
      flockName: flock.name ?? `Flock #${flock.flockId}`,
      placedIn,
      totalMortalityOut,
      totalBirdSalesOut,
      totalOtherOut,
      birdsLeftCalculated,
      birdsLeftFromLatestLog,
    }
  })
}

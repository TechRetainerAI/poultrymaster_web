import type { Flock } from "@/lib/api/flock"
import type { ProductionRecord } from "@/lib/api/production-record"
import type { Sale } from "@/lib/api/sale"
import { getBirdsLeftForFlockFromRecords } from "@/lib/utils/production-records"

export type BirdsLeftLedgerRow = {
  id: string
  date: string
  type: "IN" | "OUT"
  category: "Placement" | "Mortality" | "Bird sale"
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
  birdsLeftCalculated: number
  birdsLeftFromLatestLog: number | null
}

/** Sales that reduce live bird count (not eggs). */
export function isBirdSaleProduct(product: string | null | undefined): boolean {
  const p = (product ?? "").trim().toLowerCase()
  if (!p) return false
  if (p.includes("egg")) return false
  return /bird|chicken|broiler|layer|cull|live|poultry|hen|rooster/.test(p)
}

export function buildBirdsLeftLedger(
  flocks: Flock[],
  productionRecords: ProductionRecord[],
  sales: Sale[],
): BirdsLeftLedgerRow[] {
  const rows: BirdsLeftLedgerRow[] = []
  const flockName = (id: number) => flocks.find((f) => f.flockId === id)?.name ?? `Flock #${id}`

  for (const flock of flocks) {
    const qty = Math.max(0, Number(flock.quantity) || 0)
    if (qty <= 0) continue
    const start = (flock.startDate ?? "").split("T")[0] || new Date().toISOString().split("T")[0]
    rows.push({
      id: `in-flock-${flock.flockId}`,
      date: start,
      type: "IN",
      category: "Placement",
      flockId: flock.flockId,
      flockName: flock.name ?? flockName(flock.flockId),
      quantity: qty,
      description: `Birds placed when flock was created (${qty.toLocaleString()})`,
      sourceId: flock.flockId,
    })
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
): FlockBirdsSummary[] {
  const ledger = buildBirdsLeftLedger(flocks, productionRecords, sales)

  return flocks.map((flock) => {
    const placedIn = Math.max(0, Number(flock.quantity) || 0)
    const flockRows = ledger.filter((r) => r.flockId === flock.flockId)
    const totalMortalityOut = flockRows
      .filter((r) => r.category === "Mortality")
      .reduce((s, r) => s + r.quantity, 0)
    const totalBirdSalesOut = flockRows
      .filter((r) => r.category === "Bird sale")
      .reduce((s, r) => s + r.quantity, 0)
    const birdsLeftCalculated = Math.max(0, placedIn - totalMortalityOut - totalBirdSalesOut)
    const fromLog = getBirdsLeftForFlockFromRecords(productionRecords, flock.flockId)
    const birdsLeftFromLatestLog =
      productionRecords.some((r) => r.flockId === flock.flockId) ? fromLog : null

    return {
      flockId: flock.flockId,
      flockName: flock.name ?? `Flock #${flock.flockId}`,
      placedIn,
      totalMortalityOut,
      totalBirdSalesOut,
      birdsLeftCalculated,
      birdsLeftFromLatestLog,
    }
  })
}

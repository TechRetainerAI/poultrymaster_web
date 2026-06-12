import type { EggProduction } from "@/lib/api/egg-production"
import type { Sale } from "@/lib/api/sale"
import type { Flock } from "@/lib/api/flock"
import { resolveEggProductionFlockName } from "@/lib/utils/resolve-egg-flock-name"
import { formatEggGradeLabel } from "@/lib/constants/egg-grade"

export interface EggLedgerRow {
  sortKey: string
  date: string
  type: string
  description: string
  in: number
  out: number
  balance: number
}

export function isEggSaleProduct(product: string | undefined | null): boolean {
  if (!product?.trim()) return false
  return product.trim().toLowerCase().includes("egg")
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

/** Manual corrections from Egg tracker (API); positive adds eggs, negative removes. */
export interface EggInventoryAdjustmentLedgerInput {
  adjustmentId: number
  adjustmentDate: string
  eggDelta: number
  adjustmentType: string
  description?: string | null
}

function formatEggAdjustmentType(t: string): string {
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

/** Running egg inventory: production (in) − broken (out) − egg sales (out) ± adjustments. Chronological balance on each row. */
export function buildEggStockLedger(
  productions: EggProduction[],
  sales: Sale[],
  flocks: Flock[] = [],
  adjustments: EggInventoryAdjustmentLedgerInput[] = []
): { rows: EggLedgerRow[]; currentEggsAtHand: number; lastUpdatedIso: string } {
  const lines: LineInput[] = []

  for (const p of productions) {
    const inCount = Math.max(0, Number(p.totalProduction) || 0)
    const broken = Math.max(0, Number(p.brokenEggs) || 0)
    const flock = resolveEggProductionFlockName(p, flocks)
    const date = p.productionDate
    const grade = p.eggGrade?.trim()
    const gradeBit = grade ? ` — ${formatEggGradeLabel(grade)}` : ""

    lines.push({
      sortKey: `prod_${p.productionId}`,
      date,
      type: "Production",
      description: `${flock}${gradeBit} — collected`,
      in: inCount,
      out: 0,
      order: 0,
    })

    if (broken > 0) {
      lines.push({
        sortKey: `broken_${p.productionId}`,
        date,
        type: "Broken eggs",
        description: `${flock} — non-saleable`,
        in: 0,
        out: broken,
        order: 1,
      })
    }
  }

  for (const s of sales) {
    if (!isEggSaleProduct(s.product)) continue
    const qty = Math.max(0, Number(s.quantity) || 0)
    if (qty <= 0) continue
    const who = s.customerName?.trim()
    lines.push({
      sortKey: `sale_${s.saleId}`,
      date: s.saleDate,
      type: "Sale",
      description: who ? `${who} — ${s.product}` : (s.product || "Egg sale"),
      in: 0,
      out: qty,
      order: 2,
    })
  }

  for (const a of adjustments) {
    const d = Math.round(Number(a.eggDelta) || 0)
    if (d === 0) continue
    const dateStr = a.adjustmentDate
      ? new Date(a.adjustmentDate).toISOString()
      : new Date(0).toISOString()
    const typeLabel = formatEggAdjustmentType(a.adjustmentType)
    const desc = (a.description || "").trim() || typeLabel
    lines.push({
      sortKey: `eggadj_${a.adjustmentId}`,
      date: dateStr,
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
  const rows: EggLedgerRow[] = lines.map((line) => {
    bal += line.in - line.out
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

  const lastUpdatedIso =
    rows.length > 0 ? rows[rows.length - 1].date : new Date().toISOString()

  return {
    rows,
    currentEggsAtHand: rows.length > 0 ? rows[rows.length - 1].balance : 0,
    lastUpdatedIso,
  }
}

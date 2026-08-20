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

/**
 * Non-production, non-sale movements posted to the poultry stock ledger for the
 * egg product — driver load-outs, deliveries, restocks and the Set stock /
 * Reconcile corrections made from /poultry-inventory.
 *
 * The Egg Tracker used to ignore these entirely, so a 2,000-egg driver load-out
 * never reduced "Eggs on hand" and this page disagreed with the inventory's
 * "In stock". Production and Sale rows are deliberately NOT taken from here:
 * they are already derived from the production records and the sales list, and
 * pulling them in as well would double-count them.
 */
export interface EggStockMoveLedgerInput {
  poultryStockTransactionId: number
  createdDate: string
  txnType: string
  quantity: number
  note?: string | null
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

/**
 * The non-saleable categories deducted from collected eggs, in ledger order.
 * An egg is on hand only if it is not broken, meaty, soft-shelled or lost — the
 * same rule as spPoultryReport_EggStockBalance and the weekly report's "Egg
 * loss" figure. Each is its own ledger line so the deduction is visible and the
 * page's type filter can isolate it.
 */
const EGG_LOSS_LINES: {
  key: "brokenEggs" | "meatyEggs" | "softEggs" | "lostEggs"
  type: string
  note: string
  order: number
}[] = [
  { key: "brokenEggs", type: "Broken eggs", note: "non-saleable", order: 1 },
  { key: "meatyEggs", type: "Meaty eggs", note: "non-saleable", order: 2 },
  { key: "softEggs", type: "Soft eggs", note: "non-saleable", order: 3 },
  { key: "lostEggs", type: "Lost eggs", note: "lost", order: 4 },
]

/** Running egg inventory: production (in) − broken/meaty/soft/lost (out) − egg sales (out) ± adjustments ± stock-ledger moves. Chronological balance on each row. */
export function buildEggStockLedger(
  productions: EggProduction[],
  sales: Sale[],
  flocks: Flock[] = [],
  adjustments: EggInventoryAdjustmentLedgerInput[] = [],
  stockMoves: EggStockMoveLedgerInput[] = []
): { rows: EggLedgerRow[]; currentEggsAtHand: number; lastUpdatedIso: string } {
  const lines: LineInput[] = []

  for (const p of productions) {
    const inCount = Math.max(0, Number(p.totalProduction) || 0)
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

    for (const loss of EGG_LOSS_LINES) {
      const qty = Math.max(0, Number(p[loss.key]) || 0)
      if (qty <= 0) continue
      lines.push({
        sortKey: `${loss.key}_${p.productionId}`,
        date,
        type: loss.type,
        description: `${flock} — ${loss.note}`,
        in: 0,
        out: qty,
        order: loss.order,
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
      order: 5,
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
      order: 6,
    })
  }

  for (const m of stockMoves) {
    const type = m.txnType?.trim()
    if (!type || type === "Production" || type === "Sale") continue
    const qty = Math.round(Number(m.quantity) || 0)
    if (qty === 0) continue
    const note = (m.note || "").trim()
    lines.push({
      sortKey: `stockmove_${m.poultryStockTransactionId}`,
      date: m.createdDate,
      type,
      description: note || type,
      in: qty > 0 ? qty : 0,
      out: qty < 0 ? -qty : 0,
      order: 7,
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

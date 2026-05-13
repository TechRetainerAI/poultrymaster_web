import type { HealthRecord } from "@/lib/api/health"
import type { ProductionRecord } from "@/lib/api/production-record"
import type { Flock } from "@/lib/api/flock"
import { stripReceiptSuffixFromDescription } from "@/lib/utils/expense-receipt"
import {
  isMedicationPhotoReferenceRecord,
  normalizeProductKey,
  primaryLabelFromText,
} from "@/lib/utils/medication-photo"

export { normalizeProductKey, primaryLabelFromText } from "@/lib/utils/medication-photo"

export interface MedicationLedgerRow {
  sortKey: string
  date: string
  type: string
  description: string
  in: number
  out: number
  balance: number
  /** Normalized key for grouping (lowercase trimmed). */
  productKey: string
  /** Human-readable product name for this row. */
  productLabel: string
}

export interface MedicationProductBalance {
  key: string
  label: string
  balance: number
  /** True when running balance for this product is zero or below (used / depleted on paper). */
  depleted: boolean
}

type LineInput = {
  sortKey: string
  date: string
  type: string
  description: string
  in: number
  out: number
  order: number
  productKey: string
  productLabel: string
}

export function isMedicationFocusedHealthRecord(r: HealthRecord): boolean {
  const med = (r.medication || "").trim()
  if (med.length > 0) return true
  const notes = r.notes || ""
  return /^\[Type:\s*Medication\]/i.test(notes)
}

function isNoneMedicationText(s: string | null | undefined): boolean {
  const t = (s || "").trim()
  return t.length === 0 || /^none$/i.test(t)
}

/** First numeric dose in text, else 1 (one administration) when text is non-empty. */
export function parseMedicationDoseUnits(text: string | null | undefined): number {
  const t = (text || "").trim()
  if (!t || /^none$/i.test(t)) return 0
  const m = t.match(/(\d+(?:\.\d+)?)/)
  if (m) return Math.max(0, parseFloat(m[1]))
  return 1
}

function flockLabel(flocks: Flock[], flockId: number | null | undefined): string {
  if (flockId == null) return "—"
  const f = flocks.find((x) => x.flockId === flockId)
  return f?.name?.trim() || `Flock #${flockId}`
}

function balancesByProductFromRows(rows: MedicationLedgerRow[]): MedicationProductBalance[] {
  const map = new Map<string, { label: string; balance: number }>()
  for (const r of rows) {
    if (!r.productKey) continue
    if (!map.has(r.productKey)) {
      map.set(r.productKey, { label: r.productLabel, balance: 0 })
    }
    const cur = map.get(r.productKey)!
    cur.balance += r.in - r.out
  }
  return [...map.entries()]
    .map(([key, v]) => ({
      key,
      label: v.label,
      balance: v.balance,
      depleted: v.balance <= 0,
    }))
    .sort((a, b) => a.label.localeCompare(b.label))
}

/**
 * Medication stock: IN from health (medication / medication-type notes), OUT from production records medication field.
 * Dose uses first number in text when present, otherwise 1 per row. Optional flockId filters both sides.
 */
export function buildMedicationStockLedger(
  healthRecords: HealthRecord[],
  productionRecords: ProductionRecord[],
  flocks: Flock[],
  options?: { flockId?: number | null }
): {
  rows: MedicationLedgerRow[]
  byProduct: MedicationProductBalance[]
  medicationUnitsAtHand: number
  lastUpdatedIso: string
  totalInUnits: number
  totalOutUnits: number
} {
  const lines: LineInput[] = []
  const flockId = options?.flockId

  const healthFiltered =
    flockId != null && Number.isFinite(flockId)
      ? healthRecords.filter((r) => r.flockId === flockId)
      : healthRecords

  let healthIdx = 0
  for (const r of healthFiltered) {
    if (isMedicationPhotoReferenceRecord(r)) continue
    if (!isMedicationFocusedHealthRecord(r)) continue
    const blob = [stripReceiptSuffixFromDescription(r.medication || ""), stripReceiptSuffixFromDescription(r.notes || "")]
      .filter(Boolean)
      .join(" ")
    const dose = parseMedicationDoseUnits(blob)
    if (dose <= 0) continue
    const date = r.recordDate ? new Date(r.recordDate).toISOString() : new Date(0).toISOString()
    const medLabel =
      stripReceiptSuffixFromDescription((r.medication || "").trim()) ||
      primaryLabelFromText(blob) ||
      "Medication (health)"
    const productLabel = primaryLabelFromText(medLabel)
    const productKey = normalizeProductKey(productLabel)
    healthIdx += 1
    lines.push({
      sortKey: `health_${r.id ?? "noid"}_${r.recordDate}_${r.flockId ?? "x"}_${healthIdx}`,
      date,
      type: "Health IN",
      description: `${flockLabel(flocks, r.flockId ?? null)} — ${medLabel}`,
      in: dose,
      out: 0,
      order: 0,
      productKey,
      productLabel,
    })
  }

  const prodFiltered =
    flockId != null && Number.isFinite(flockId)
      ? productionRecords.filter((p) => p.flockId === flockId)
      : productionRecords

  for (const p of prodFiltered) {
    if (isNoneMedicationText(p.medication)) continue
    const dose = parseMedicationDoseUnits(stripReceiptSuffixFromDescription(p.medication))
    if (dose <= 0) continue
    const date = p.date ? new Date(p.date).toISOString() : new Date(0).toISOString()
    const rawMed = stripReceiptSuffixFromDescription((p.medication || "").trim())
    const productLabel = primaryLabelFromText(rawMed)
    const productKey = normalizeProductKey(productLabel)
    lines.push({
      sortKey: `prod_${p.id}`,
      date,
      type: "Production OUT",
      description: `${flockLabel(flocks, p.flockId ?? null)} — ${rawMed}`,
      in: 0,
      out: dose,
      order: 1,
      productKey,
      productLabel,
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
  const rows: MedicationLedgerRow[] = lines.map((line) => {
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
      productKey: line.productKey,
      productLabel: line.productLabel,
    }
  })

  const lastUpdatedIso = rows.length > 0 ? rows[rows.length - 1].date : new Date().toISOString()
  const byProduct = balancesByProductFromRows(rows)

  return {
    rows,
    byProduct,
    medicationUnitsAtHand: rows.length > 0 ? rows[rows.length - 1].balance : 0,
    lastUpdatedIso,
    totalInUnits: totalIn,
    totalOutUnits: totalOut,
  }
}

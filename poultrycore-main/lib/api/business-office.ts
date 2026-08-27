import { farmApiUrl, getAuthHeaders } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import type { CompanyType } from "./companies"

// Today's numbers for the Business Office company cards.
//
// The four values are positional: what Metric1 MEANS depends on the company
// type, and the pairing of slot to label lives in one place —
// COMPANY_CARD_METRICS below. Nothing else should read metric1..4 directly.

export interface CompanySnapshot {
  farmId: string
  companyType: string
  /** null = not measured for this type; 0 = measured, and genuinely nothing. */
  metric1: number | null
  metric2: number | null
  metric3: number | null
  metric4: number | null
}

/** The caller's local day, YYYY-MM-DD — so "today" means the reader's today. */
function localToday(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export async function getCompanySnapshot(farmId: string, type: CompanyType | string): Promise<CompanySnapshot> {
  const qs = new URLSearchParams({ farmId, type: String(type), today: localToday() })
  const res = await fetch(farmApiUrl(`/BusinessOffice/company-snapshot?${qs.toString()}`), {
    headers: getAuthHeaders(),
  })
  if (!res.ok) {
    // The old message threw the body away, so a real reason from the API never
    // reached the caller — only the status code did.
    const text = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", "/BusinessOffice/company-snapshot", res.status, text))
  }
  const raw = await res.json()
  const num = (v: any) => (v === null || v === undefined || v === "" ? null : Number(v))
  return {
    farmId: raw.farmId ?? raw.FarmId ?? farmId,
    companyType: raw.companyType ?? raw.CompanyType ?? String(type),
    metric1: num(raw.metric1 ?? raw.Metric1),
    metric2: num(raw.metric2 ?? raw.Metric2),
    metric3: num(raw.metric3 ?? raw.Metric3),
    metric4: num(raw.metric4 ?? raw.Metric4),
  }
}

/** How a metric should read: a plain count, a weight, or money. */
export type MetricFormat = "count" | "kg" | "money"

export interface CardMetric {
  label: string
  /** Which positional slot of the snapshot this label describes. */
  slot: 1 | 2 | 3 | 4
  format: MetricFormat
  /** Money and debt figures are admin-only on the card. */
  adminOnly?: boolean
}

/**
 * Label ↔ slot ↔ format for each company type, in card order. This is the only
 * definition of what the four numbers mean — it has to stay in step with
 * spBusinessOffice_CompanySnapshot (migration 195), which fills the slots.
 */
export const COMPANY_CARD_METRICS: Record<string, CardMetric[]> = {
  Water: [
    { label: "Production today", slot: 1, format: "count" },
    { label: "Bags in stock", slot: 2, format: "count" },
    { label: "Driver returns", slot: 3, format: "count" },
    { label: "Today's sales", slot: 4, format: "money", adminOnly: true },
  ],
  Poultry: [
    { label: "Eggs today", slot: 1, format: "count" },
    { label: "Feed stock", slot: 2, format: "kg" },
    { label: "Mortality", slot: 3, format: "count" },
    { label: "Today's sales", slot: 4, format: "money", adminOnly: true },
  ],
  Generic: [
    { label: "Sales today", slot: 1, format: "money", adminOnly: true },
    { label: "Expenses today", slot: 2, format: "money", adminOnly: true },
    { label: "Low stock", slot: 3, format: "count" },
    { label: "Customer debt", slot: 4, format: "money", adminOnly: true },
  ],
}

/** Card metrics for a type, falling back to the money-free generic set. */
export function cardMetricsForType(type: string | null | undefined): CardMetric[] {
  return COMPANY_CARD_METRICS[String(type)] ?? COMPANY_CARD_METRICS.Generic
}

export function snapshotValue(snapshot: CompanySnapshot | undefined, slot: 1 | 2 | 3 | 4): number | null {
  if (!snapshot) return null
  return snapshot[`metric${slot}` as const]
}

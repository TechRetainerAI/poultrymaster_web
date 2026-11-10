// Broiler figures across several flocks (migration 402). Pure: no React.
//
// Each flock's figures come from the database (fnflock_broilerkpis). Adding
// flocks together is done by summing the quantities underneath, never by
// averaging ratios: three flocks' FCR is their total feed over their total kg,
// so a small flock cannot pull the farm's figure as hard as a big one.

import type { FlockBroilerKpis } from "@/lib/api/flock-closeout"

export interface BroilerTotals {
  flocks: number
  /** Flocks whose kg produced is known. Only these count towards FCR and cost per kg. */
  flocksWithKg: number
  birdsStarted: number
  deaths: number
  liveabilityPct: number | null
  kgProduced: number
  feedKgOfKnown: number
  fcr: number | null
  totalCostOfKnown: number
  costPerKg: number | null
  profit: number
  kgIsEstimated: boolean
}

const r = (n: number, dp: number) => Math.round((n + Number.EPSILON) * 10 ** dp) / 10 ** dp

export function broilerTotals(rows: readonly Pick<FlockBroilerKpis,
  "birdsStarted" | "deaths" | "kgProduced" | "feedKg" | "totalCost" | "profit" | "kgIsEstimated">[]): BroilerTotals {
  const known = rows.filter((x) => x.kgProduced != null && Number(x.kgProduced) > 0)
  const birdsStarted = rows.reduce((s, x) => s + (x.birdsStarted || 0), 0)
  const deaths = rows.reduce((s, x) => s + (x.deaths || 0), 0)
  const kg = known.reduce((s, x) => s + Number(x.kgProduced), 0)
  const feed = known.reduce((s, x) => s + Number(x.feedKg || 0), 0)
  const cost = known.reduce((s, x) => s + Number(x.totalCost || 0), 0)
  return {
    flocks: rows.length,
    flocksWithKg: known.length,
    birdsStarted,
    deaths,
    liveabilityPct: birdsStarted > 0 ? r((100 * (birdsStarted - deaths)) / birdsStarted, 2) : null,
    kgProduced: r(kg, 3),
    feedKgOfKnown: r(feed, 3),
    fcr: kg > 0 && feed > 0 ? r(feed / kg, 3) : null,
    totalCostOfKnown: r(cost, 2),
    costPerKg: kg > 0 ? r(cost / kg, 2) : null,
    profit: r(rows.reduce((s, x) => s + Number(x.profit || 0), 0), 2),
    kgIsEstimated: known.some((x) => x.kgIsEstimated),
  }
}

/** "1.826" -- FCR is read to three places on farms. */
export const fmtFcr = (v: number | null | undefined) => (v == null ? "—" : Number(v).toFixed(3))
/** "2.42 kg" */
export const fmtKgEach = (v: number | null | undefined) => (v == null ? "—" : `${Number(v).toFixed(2)} kg`)
/** "2,300 kg" */
export const fmtKgTotal = (v: number | null | undefined) => (v == null ? "—" : `${Math.round(Number(v)).toLocaleString()} kg`)

// Weigh-in arithmetic (migration 400). Pure: no React.
//
// The server recomputes every figure from the weights it receives
// (fnpoultryweighin_stats); this copy only previews them while typing. Both
// carry the same test cases -- see database/checks/flock-weigh-ins.test.sql.
//
//   uniformity = % of sampled birds within +/-10% of the sample average
//   CV         = sample standard deviation / average x 100 (needs 2+ birds)

export type WeightUnit = "g" | "kg"

export interface WeighInStats {
  sampleSize: number
  avgWeightG: number
  minWeightG: number
  maxWeightG: number
  uniformityPct: number
  /** Null for a single bird: a spread needs two. */
  cvPct: number | null
}

const round = (n: number, dp: number) => {
  const f = 10 ** dp
  return Math.round((n + Number.EPSILON) * f) / f
}

export function computeWeighInStats(weightsG: readonly number[]): WeighInStats | null {
  const w = weightsG.filter((x) => Number.isFinite(x))
  const n = w.length
  if (n === 0) return null
  const mean = w.reduce((a, b) => a + b, 0) / n
  const within = w.filter((x) => x >= mean * 0.9 && x <= mean * 1.1).length
  const sd = n < 2 ? null : Math.sqrt(w.reduce((a, x) => a + (x - mean) ** 2, 0) / (n - 1))
  return {
    sampleSize: n,
    avgWeightG: round(mean, 1),
    minWeightG: round(Math.min(...w), 1),
    maxWeightG: round(Math.max(...w), 1),
    uniformityPct: round((100 * within) / n, 1),
    cvPct: sd === null ? null : round((100 * sd) / mean, 2),
  }
}

export interface ParsedWeights {
  /** In grams, one per bird, rounded to 0.1 g. */
  weightsG: number[]
  /** Pieces of the text that are not a usable weight, as typed. */
  invalid: string[]
}

/**
 * Weights as a farm types them off a scale: separated by spaces, commas,
 * semicolons or new lines, in grams or kilograms. A decimal comma ("1,85") is
 * NOT supported -- commas separate birds -- so kg must use a point.
 */
export function parseWeights(text: string, unit: WeightUnit): ParsedWeights {
  const weightsG: number[] = []
  const invalid: string[] = []
  for (const token of text.split(/[\s,;]+/)) {
    if (!token) continue
    const n = Number(token)
    const g = unit === "kg" ? n * 1000 : n
    if (!Number.isFinite(n) || g <= 0 || g > 20000) invalid.push(token)
    else weightsG.push(round(g, 1))
  }
  return { weightsG, invalid }
}

/** "1,234 g" under 1 kg, else "1.85 kg". */
export function formatWeight(g: number | null | undefined): string {
  if (g === null || g === undefined || !Number.isFinite(g)) return "—"
  if (Math.abs(g) < 1000) return `${round(g, 0).toLocaleString()} g`
  return `${(g / 1000).toFixed(2)} kg`
}

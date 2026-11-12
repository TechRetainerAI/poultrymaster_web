import type { FlockPositionRow } from "@/lib/api/flock-positions"

/**
 * Lifetime bird figures for a flock, from its position (migration 419's rule,
 * the same one every report uses):
 *
 *   started     = originally placed; the opening live count when the farm said
 *                 the history is not known (its reduction is then an unknown
 *                 adjustment, not mortality)
 *   deaths      = opening historical mortality (history known) + recorded
 *   sold / culled / transferred = opening (history known) + since tracking
 *   other       = opening "other" (history known)
 *   live        = currentLiveBirds
 *   correction  = whatever the counts leave unexplained (signed), so
 *                 started = deaths + sold + culled + transferred + other + correction + live
 */
export interface FlockLifetimeFigures {
  started: number
  deaths: number
  sold: number
  culled: number
  transferred: number
  other: number
  correction: number
  live: number
}

type PositionLike = Pick<FlockPositionRow,
  "historyKnown" | "originallyPlaced" | "openingLiveBirds" | "openingMortality" | "openingSold" |
  "openingCulled" | "openingTransferred" | "openingOther" | "recordedMortality" | "birdsSold" |
  "birdsCulled" | "birdsTransferred" | "currentLiveBirds">

export function flockLifetime(p: PositionLike): FlockLifetimeFigures {
  const known = p.historyKnown
  const started = known ? p.originallyPlaced : p.openingLiveBirds
  const deaths = (known ? p.openingMortality : 0) + p.recordedMortality
  const sold = (known ? p.openingSold : 0) + p.birdsSold
  const culled = (known ? p.openingCulled : 0) + p.birdsCulled
  const transferred = (known ? p.openingTransferred : 0) + p.birdsTransferred
  const other = known ? p.openingOther : 0
  const live = p.currentLiveBirds
  return {
    started, deaths, sold, culled, transferred, other, live,
    correction: started - deaths - sold - culled - transferred - other - live,
  }
}

/** Sum of flockLifetime over many flocks. */
export function sumLifetime(rows: PositionLike[]): FlockLifetimeFigures {
  const t: FlockLifetimeFigures = { started: 0, deaths: 0, sold: 0, culled: 0, transferred: 0, other: 0, correction: 0, live: 0 }
  for (const r of rows) {
    const f = flockLifetime(r)
    t.started += f.started; t.deaths += f.deaths; t.sold += f.sold; t.culled += f.culled
    t.transferred += f.transferred; t.other += f.other; t.correction += f.correction; t.live += f.live
  }
  return t
}

/** Index positions by flock id. */
export function positionsById<T extends { flockId: number }>(rows: T[] | null | undefined): Map<number, T> {
  const m = new Map<number, T>()
  for (const r of rows ?? []) m.set(r.flockId, r)
  return m
}

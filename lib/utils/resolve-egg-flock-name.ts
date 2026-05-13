import type { EggProduction } from "@/lib/api/egg-production"
import type { Flock } from "@/lib/api/flock"

/** Matches placeholder from API when `spEggProduction_*` has no FlockName column. */
const API_UNKNOWN_FLOCK = /^unknown flock$/i

export function resolveEggProductionFlockName(prod: EggProduction, flocks: Flock[]): string {
  const fromApi = (prod.flockName ?? "").trim()
  if (fromApi && !API_UNKNOWN_FLOCK.test(fromApi)) return fromApi
  const flock = flocks.find((f) => f.flockId === prod.flockId)
  return flock?.name?.trim() || (prod.flockId ? `Flock #${prod.flockId}` : "—")
}

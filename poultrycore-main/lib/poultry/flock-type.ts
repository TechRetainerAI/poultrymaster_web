// Layer and Broiler flocks (migration 399).
//
// Every flock is one or the other. The company's business type (Layers |
// Broilers | Both, migration 212) is only the DEFAULT for a new flock: a farm
// may run both at once, so the flock is what decides whether its screens ask
// about eggs.
//
// Pure: no React. The database rule this mirrors is fnpoultry_defaultflocktype.

import { BREED_CATALOG, breedKey } from "@/lib/poultry/breeds"

export const FLOCK_TYPES = ["Layer", "Broiler"] as const
export type FlockType = (typeof FLOCK_TYPES)[number]

export const FLOCK_TYPE_LABELS: Record<FlockType, string> = {
  Layer: "Layers (eggs)",
  Broiler: "Broilers (meat)",
}

/** Anything the API did not send (a database before 399) is a Layer flock. */
export function flockTypeOf(flock: { flockType?: string | null } | null | undefined): FlockType {
  return flock?.flockType === "Broiler" ? "Broiler" : "Layer"
}

export const isBroilerFlock = (flock: { flockType?: string | null } | null | undefined): boolean =>
  flockTypeOf(flock) === "Broiler"

const BROILER_BREEDS = new Set(
  (BREED_CATALOG.find((g) => g.group === "Broilers")?.breeds ?? []).map(breedKey),
)

/**
 * A breed that only makes sense as a meat bird. The catalog's Broilers group,
 * plus the same name fragments the database matches, so "Cobb", "ross 308" and
 * the misspelt "Broiller" all count.
 */
export function isBroilerBreed(breed: string | null | undefined): boolean {
  const key = breedKey(breed)
  if (!key) return false
  return BROILER_BREEDS.has(key) || /(broil|cobb|ross|arbor|hubbard)/.test(key)
}

/**
 * The type a new flock starts with: a broiler breed, else the company's
 * business type, else Layer. Same order as fnpoultry_defaultflocktype.
 */
export function defaultFlockType(breed: string | null | undefined, businessType?: string | null): FlockType {
  if (isBroilerBreed(breed)) return "Broiler"
  if (businessType === "Broilers") return "Broiler"
  return "Layer"
}

interface FlockLike {
  flockType?: string | null
  closedDate?: string | null
  /** The flock list can carry soft-deleted rows on some readers. */
  isDeleted?: boolean | null
}

/**
 * Should the egg screens (sorting, egg tracker, broken eggs, egg settings, the
 * egg section of a production record) be offered at all?
 *
 * Yes while ANY open flock lays. Only when no open flock is a layer AND there
 * is a positive sign the farm is a broiler farm (an open broiler flock, or a
 * company set to Broilers) are they hidden. With nothing loaded yet, or an
 * empty farm with no business type, the answer is yes: hiding a screen a layer
 * farm needs is worse than showing one a broiler farm ignores.
 */
export function showEggFeatures(
  flocks: readonly FlockLike[] | null | undefined,
  businessType?: string | null,
): boolean {
  const open = (flocks ?? []).filter((f) => !f.closedDate && !f.isDeleted)
  if (open.some((f) => flockTypeOf(f) === "Layer")) return true
  if (open.some((f) => flockTypeOf(f) === "Broiler")) return false
  return businessType !== "Broilers"
}

/**
 * Should the broiler screens (Broiler performance) be offered? Yes once the
 * company has ever had a broiler flock, or is set to Broilers or Both. With
 * nothing known the answer is yes, as for eggs.
 */
export function showBroilerFeatures(
  flocks: readonly FlockLike[] | null | undefined,
  businessType?: string | null,
): boolean {
  if (flocks == null) return true
  if (flocks.some((f) => !f.isDeleted && flockTypeOf(f) === "Broiler")) return true
  return businessType === "Broilers" || businessType === "Both"
}

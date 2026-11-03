// Selling birds per bird or per kg of live weight (migration 401). Pure.
//
// The quantity of a bird line is ALWAYS the number of birds -- the flock's bird
// position subtracts it. Per kg, the amount is live weight x price per kg and
// the per-bird price is amount / birds, which is what the database stores as
// the line's unit price so every older report still multiplies correctly.

import { byproductRole } from "@/lib/poultry/byproducts"

export type BirdPricingBasis = "PerBird" | "PerKg"

export interface BirdPricing {
  basis: BirdPricingBasis
  /** Total live weight of the birds on the line; optional per bird. */
  liveWeightKg: number | null
  /** Per kg only. */
  pricePerKg: number | null
}

export const EMPTY_BIRD_PRICING: BirdPricing = { basis: "PerBird", liveWeightKg: null, pricePerKg: null }

/**
 * Is this product a sale of live birds? The database's rule
 * (fnpoultrysale_isbirdsale, 374 + 401) exactly: bird / chick / cockerel /
 * broiler -- but not "Broiler feed" -- never an egg, never a byproduct.
 */
export function isLiveBirdProduct(product: string | null | undefined): boolean {
  const p = (product ?? "").toLowerCase()
  if (!p || p.includes("egg") || byproductRole(product) != null) return false
  if (p === "birds" || p.includes("bird") || p.includes("chick") || p.includes("cockerel")) return true
  return p.includes("broiler") && !/(feed|mash|starter|grower|finisher|concentrate)/.test(p)
}

const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100

/** The line amount: per kg, kg x price per kg; per bird, birds x unit price. */
export function birdLineAmount(birds: number, unitPrice: number, pricing: BirdPricing): number {
  if (pricing.basis === "PerKg") return round2((pricing.liveWeightKg ?? 0) * (pricing.pricePerKg ?? 0))
  return round2((birds || 0) * (unitPrice || 0))
}

/** The per-bird price stored for a per-kg line. 0 with no birds. */
export function perBirdPrice(amount: number, birds: number): number {
  return birds > 0 ? round2(amount / birds) : 0
}

/** Average live weight per bird, or null when unknown. */
export function avgKgPerBird(birds: number, liveWeightKg: number | null | undefined): number | null {
  return birds > 0 && liveWeightKg != null && liveWeightKg > 0 ? liveWeightKg / birds : null
}

/** Does the line carry anything the database's bird branch should see? */
export function hasBirdPricing(p: BirdPricing | null | undefined): boolean {
  return !!p && (p.basis === "PerKg" || (p.liveWeightKg != null && p.liveWeightKg > 0))
}

/** What is wrong with the line, or null. Same limits as the database. */
export function birdPricingProblem(birds: number, p: BirdPricing): string | null {
  if (!hasBirdPricing(p)) return null
  if (!(birds > 0) || !Number.isInteger(birds)) return "Enter the number of birds as a whole number."
  if (p.liveWeightKg != null && !(p.liveWeightKg > 0)) return "The live weight must be above 0 kg."
  if (p.liveWeightKg != null && p.liveWeightKg / birds > 20) return `${p.liveWeightKg} kg for ${birds} birds is over 20 kg a bird. Check the weight.`
  if (p.basis === "PerKg") {
    if (p.liveWeightKg == null) return "A sale priced per kg needs the total live weight in kg."
    if (p.pricePerKg == null || !(p.pricePerKg > 0)) return "Enter the price per kg."
  }
  return null
}

/** The fields a sale line sends for the database's bird branch (empty when none). */
export function birdPricingPayload(p: BirdPricing | null | undefined, amountOverridden = false) {
  if (!p || !hasBirdPricing(p)) return {}
  return {
    pricingBasis: p.basis,
    liveWeightKg: p.liveWeightKg,
    pricePerKg: p.basis === "PerKg" ? p.pricePerKg : null,
    ...(amountOverridden ? { amountOverridden: true } : {}),
  }
}

/** A saved line back into the form's shape (Correct Sale). */
export function birdPricingFromLine(l: { pricingBasis?: string | null; liveWeightKg?: number | null; pricePerKg?: number | null } | null | undefined): BirdPricing {
  if (!l?.pricingBasis) return { ...EMPTY_BIRD_PRICING }
  return {
    basis: l.pricingBasis === "PerKg" ? "PerKg" : "PerBird",
    liveWeightKg: l.liveWeightKg != null ? Number(l.liveWeightKg) : null,
    pricePerKg: l.pricePerKg != null ? Number(l.pricePerKg) : null,
  }
}

/** One line of text for a saved bird line, e.g. "250 kg at 30.00 / kg · 2.50 kg a bird". */
export function birdLineNote(l: { quantity?: number | null; pricingBasis?: string | null; liveWeightKg?: number | null; pricePerKg?: number | null }): string | null {
  if (!l.pricingBasis || l.liveWeightKg == null) return null
  const kg = Number(l.liveWeightKg)
  const avg = avgKgPerBird(Number(l.quantity) || 0, kg)
  const parts = [
    l.pricingBasis === "PerKg" && l.pricePerKg != null
      ? `${kg.toLocaleString()} kg at ${Number(l.pricePerKg).toFixed(2)} / kg`
      : `${kg.toLocaleString()} kg live weight`,
    avg != null ? `${avg.toFixed(2)} kg a bird` : "",
  ]
  return parts.filter(Boolean).join(" · ")
}

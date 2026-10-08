// The public plan ladder — mirrors the live GH-2026 price book
// (pricebookentries, migration 329). Keep in step with the admin console:
// if a price changes there, change it here too. Prices are per company,
// per month, in GHS; poultry is priced by active bird count. Annual prices
// are not configured yet, so every surface shows monthly only.
//
// HONESTY RULE: plans differ by SCALE, not by features — nothing is
// feature-gated today (planentitlements is empty = unlimited). Don't add
// bullets that imply a lower plan lacks a feature, and don't invent
// support tiers or commercial promises that don't exist.

export interface PublicPlan {
  code: "starter" | "growth" | "business" | "enterprise"
  name: string
  blurb: string
  /** Monthly GHS price per company, or null = request a price. */
  monthlyGhs: number | null
  /** Configured annual price; null/undefined = annual not available (never 12x monthly). */
  annualGhs?: number | null
  scaleLine: string
  features: string[]
  highlight?: boolean
}

export const TRIAL_DAYS = 150

/** Every plan ships the complete platform; the ladder prices your scale. */
export const CORE_FEATURES = [
  "Production & flock records",
  "Feed, medication & inventory",
  "Sales, expenses & cash accounts",
  "Daily closing, reports & audit logs",
  "Team logins with roles",
  "Phone, tablet & desktop",
] as const

export const PUBLIC_PLANS: PublicPlan[] = [
  {
    code: "starter",
    name: "Starter",
    blurb: "For small farms getting their records off paper",
    monthlyGhs: 500,
    scaleLine: "Up to 2,000 birds",
    features: ["The complete platform — every feature included", ...CORE_FEATURES.slice(0, 4)],
  },
  {
    code: "growth",
    name: "Growth",
    blurb: "For growing farms that run on their numbers",
    monthlyGhs: 1000,
    scaleLine: "2,001 – 5,000 birds",
    highlight: true,
    features: [
      "Everything in Starter — same complete platform",
      "Sized for flocks up to 5,000 birds",
      ...CORE_FEATURES.slice(0, 3),
    ],
  },
  {
    code: "business",
    name: "Business",
    blurb: "For large operations with serious volume",
    monthlyGhs: 1500,
    scaleLine: "Above 5,000 birds",
    features: [
      "Everything in Growth — same complete platform",
      "No upper limit on flock size",
      ...CORE_FEATURES.slice(0, 3),
    ],
  },
  {
    code: "enterprise",
    name: "Enterprise",
    blurb: "For groups running many companies",
    monthlyGhs: null,
    scaleLine: "Custom contract",
    features: [
      "Everything in Business",
      "Many companies, one consolidated bill",
      "Business Office — your organization HQ",
      "Custom contract terms",
    ],
  },
]


// ---------- presentation-driven cards (admin-app spec 11-16) ----------
// When the backend serves presentation + prices, build the cards from DATA so
// admins change copy and prices without a deploy; the constants above remain
// the offline fallback only.

import type { PublicPricing } from "@/lib/api/platform-billing"

function scaleLine(min?: number | null, max?: number | null, plural?: string | null): string {
  const unit = plural || "units"
  if (min == null && max == null) return "Custom contract"
  if (max == null) return `Above ${((min ?? 1) - 1).toLocaleString()} ${unit}`
  if ((min ?? 0) <= 0) return `Up to ${max.toLocaleString()} ${unit}`
  return `${min!.toLocaleString()} – ${max.toLocaleString()} ${unit}`
}

export function plansFromApi(api: PublicPricing): PublicPlan[] {
  return api.plans.map((c) => ({
    code: c.tierCode as PublicPlan["code"],
    name: c.tierName,
    blurb: c.headline || "",
    monthlyGhs: c.monthlyPrice ?? null,
    annualGhs: c.annualPrice ?? null,
    scaleLine: c.tierCode === "enterprise" ? "Custom contract" : scaleLine(c.minValue, c.maxValue, api.metricPlural),
    features: c.featureBullets,
    highlight: c.isMostPopular,
  }))
}

// The business types an owner picks from when creating a company.
//
// What the owner sees is a business ("Gym / Fitness Centre"). What the system
// stores is a CompanyType plus, for the Generic-based ones, a business template
// and an industry template. Keeping the mapping here rather than in the dialog
// means the create form, the setup wizard and any future onboarding flow all
// agree on what "Gym" means.
//
// Deliberately NOT a sixth Farms.Type. A new type would need its own farm
// guard, IAM company type, controller tree and setup SP; a template needs none
// of that, and the LoginAPI's Farm.cs type regex already permits "Generic".

import type {
  BusinessTemplate,
  IndustryTemplate,
} from "@/lib/generic/template-labels"

export type CompanyType = "Poultry" | "Water" | "Generic" | "Hotel" | "Restaurant"

export interface BusinessType {
  /** Stable id used as the <SelectItem> value. */
  id: string
  label: string
  /** The one-liner under the label. */
  description: string
  companyType: CompanyType
  /** Set only for Generic-based types. */
  businessTemplate?: BusinessTemplate
  industryTemplate?: IndustryTemplate
}

export const BUSINESS_TYPES: BusinessType[] = [
  // ---- the four with their own module tree -------------------------------
  {
    id: "water",
    label: "Water production",
    description: "Sachet or bottled water — production, distribution, drivers",
    companyType: "Water",
  },
  {
    id: "poultry",
    label: "Poultry farm",
    description: "Flocks, houses, egg production, feed",
    companyType: "Poultry",
  },
  {
    id: "hotel",
    label: "Hotel",
    description: "Rooms, bookings, front desk",
    companyType: "Hotel",
  },
  {
    id: "restaurant",
    label: "Restaurant",
    description: "POS, menu, kitchen, delivery",
    companyType: "Restaurant",
  },

  // ---- subscription / recurring-billing businesses ------------------------
  {
    id: "saas",
    label: "SaaS / software company",
    description: "Customers on recurring plans",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "SaaS",
  },
  {
    id: "gym",
    label: "Gym / fitness centre",
    description: "Members on monthly or annual memberships",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "Gym",
  },
  {
    id: "school",
    label: "School",
    description: "Students, termly fees, fee notes",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "School",
  },
  {
    id: "cleaning",
    label: "Cleaning service",
    description: "Clients on service contracts",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "CleaningService",
  },
  {
    id: "security",
    label: "Security service",
    description: "Clients on service contracts",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "SecurityService",
  },
  {
    id: "agency",
    label: "Agency",
    description: "Clients on monthly retainers",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "Agency",
  },
  {
    id: "retainer",
    label: "Retainer business",
    description: "Any business billing a fixed amount each period",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "RetainerBusiness",
  },
  {
    id: "membership",
    label: "Membership organisation",
    description: "Members paying dues",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "MembershipBusiness",
  },

  // ---- everything else ----------------------------------------------------
  {
    id: "retail",
    label: "Shop / retail",
    description: "Stock, counter sales, suppliers",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Retail",
  },
  {
    id: "other",
    label: "Other small business",
    description: "Salon, pharmacy, workshop — sales, expenses and cash",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Other",
  },
]

export function findBusinessType(id: string): BusinessType | undefined {
  return BUSINESS_TYPES.find((t) => t.id === id)
}

/** True when creating this type should apply a template and open the wizard. */
export function needsTemplate(t: BusinessType | undefined): boolean {
  return Boolean(t?.businessTemplate && t?.industryTemplate)
}

// -----------------------------------------------------------------------------
// The legacy BusinessCategories list (migration 028) that predates templates.
// -----------------------------------------------------------------------------
// businessCategoryId is a classification label -- stored on the profile and read
// by nothing. The industry template is what actually drives labels, menus and
// seeds. The setup page therefore asks ONE question, the template one, and fills
// the legacy id in from this map so anything still reading it keeps working.
//
// Names, not ids: the ids are seeded per environment and a hardcoded number
// would silently point at the wrong row somewhere else. "Other" is the fallback
// and always exists.
const LEGACY_CATEGORY_BY_INDUSTRY: Record<IndustryTemplate, string> = {
  SaaS: "Services Business",
  Agency: "Services Business",
  RetainerBusiness: "Services Business",
  CleaningService: "Services Business",
  SecurityService: "Services Business",
  Gym: "Services Business",
  MembershipBusiness: "Services Business",
  School: "School",
  Retail: "Retail Shop",
  Other: "Other",
}

/**
 * The legacy category id for an industry template, given the categories the API
 * returned. Returns null when neither the mapped name nor "Other" is present,
 * which simply leaves the column null -- it drives nothing.
 */
export function legacyCategoryIdFor(
  industry: IndustryTemplate | undefined,
  categories: { businessCategoryId: number; name: string }[],
): number | null {
  if (!industry) return null
  const wanted = LEGACY_CATEGORY_BY_INDUSTRY[industry]
  const byName = (n: string) =>
    categories.find((c) => c.name.trim().toLowerCase() === n.toLowerCase())?.businessCategoryId ?? null
  return byName(wanted) ?? byName("Other")
}

/** The business types offered to a company that is already Generic. */
export const GENERIC_BUSINESS_TYPES: BusinessType[] =
  BUSINESS_TYPES.filter((t) => t.companyType === "Generic")

/** Find the business type carrying a given industry template. */
export function businessTypeForIndustry(industry?: string | null): BusinessType | undefined {
  if (!industry) return undefined
  return GENERIC_BUSINESS_TYPES.find((t) => t.industryTemplate === industry)
}

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

export type BusinessCategory = "retail" | "service" | "subscription" | "other"

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
  /** Wizard grouping category for searchable display. */
  category?: BusinessCategory
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
    category: "subscription",
  },
  {
    id: "gym",
    label: "Gym / fitness centre",
    description: "Members on monthly or annual memberships",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "Gym",
    category: "subscription",
  },
  {
    id: "school",
    label: "School / training centre",
    description: "Students, termly fees, fee notes",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "School",
    category: "subscription",
  },
  {
    id: "cleaning",
    label: "Cleaning service",
    description: "Clients on service contracts",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "CleaningService",
    category: "subscription",
  },
  {
    id: "security",
    label: "Security service",
    description: "Clients on service contracts",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "SecurityService",
    category: "subscription",
  },
  {
    id: "agency",
    label: "Agency",
    description: "Clients on monthly retainers",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "Agency",
    category: "subscription",
  },
  {
    id: "retainer",
    label: "Retainer business",
    description: "Any business billing a fixed amount each period",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "RetainerBusiness",
    category: "subscription",
  },
  {
    id: "membership",
    label: "Membership organisation",
    description: "Members paying dues",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "MembershipBusiness",
    category: "subscription",
  },

  // ---- retail / stock businesses --------------------------------------------
  {
    id: "produce",
    label: "Yam & produce seller",
    description: "Yams, tomatoes, vegetables — purchases, sales and spoilage",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "ProduceSeller",
    category: "retail",
  },
  {
    id: "grocery",
    label: "Grocery shop / mini-mart",
    description: "Packaged goods, stock alerts, daily cash closing",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Grocery",
    category: "retail",
  },
  {
    id: "clothing",
    label: "Clothing & shoe shop",
    description: "Fashion, accessories — stock by size and style",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Retail", // shares Retail template — no unique seeding yet
    category: "retail",
  },
  {
    id: "hardware",
    label: "Hardware & building materials",
    description: "Cement, iron rods, paint — bulk and unit sales",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "HardwareShop",
    category: "retail",
  },
  {
    id: "electronics",
    label: "Phone & electronics shop",
    description: "Phones, accessories, repairs — serial tracking",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "ElectronicsShop",
    category: "retail",
  },
  {
    id: "wholesaler",
    label: "Wholesaler / distributor",
    description: "Bulk buying and reselling — customer credit, supplier payments",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Wholesaler",
    category: "retail",
  },
  {
    id: "bakery",
    label: "Bakery",
    description: "Bread, pastries — daily production and sales",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Bakery",
    category: "retail",
  },
  {
    id: "pharmacy",
    label: "Pharmacy",
    description: "Medicines, health products — stock and expiry tracking",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Pharmacy",
    category: "retail",
  },
  {
    id: "car-dealership",
    label: "Car dealership",
    description: "Vehicle sales — purchases, deposits, customer balances",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "CarDealership",
    category: "retail",
  },
  {
    id: "retail",
    label: "Other shop / retail",
    description: "Any store selling physical goods",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Retail",
    category: "retail",
  },

  // ---- service businesses --------------------------------------------------
  {
    id: "barbershop",
    label: "Barbershop",
    description: "Haircuts, shaves — walk-in sales, staff commissions",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Barbershop",
    category: "service",
  },
  {
    id: "salon",
    label: "Hair salon & beauty",
    description: "Hair, nails, skincare — services, retail products, staff",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Salon",
    category: "service",
  },
  {
    id: "auto-repair",
    label: "Auto repair garage",
    description: "Car repairs — job tracking, parts, labour",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "AutoRepair",
    category: "service",
  },
  {
    id: "tailor",
    label: "Tailor / fashion designer",
    description: "Custom clothing — measurements, deposits, job tracking",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Tailor",
    category: "service",
  },
  {
    id: "laundry",
    label: "Laundry & dry cleaning",
    description: "Wash, iron, dry clean — customer items and pickup",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Laundry",
    category: "service",
  },
  {
    id: "freelancer",
    label: "Freelancer / consultant",
    description: "Client invoicing, project billing, expenses",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "Freelancer",
    category: "service",
  },

  // ---- catch-all -----------------------------------------------------------
  {
    id: "other",
    label: "Other business",
    description: "Any business not listed above",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Other",
    category: "other",
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
  // Phase B
  ProduceSeller: "Retail Shop",
  Grocery: "Retail Shop",
  HardwareShop: "Retail Shop",
  ElectronicsShop: "Retail Shop",
  Wholesaler: "Retail Shop",
  Bakery: "Retail Shop",
  CarDealership: "Retail Shop",
  Pharmacy: "Retail Shop",
  Barbershop: "Other",
  Salon: "Other",
  AutoRepair: "Other",
  Tailor: "Other",
  Laundry: "Other",
  Freelancer: "Services Business",
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

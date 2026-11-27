// The business types an owner picks from when creating a company.
//
// What the owner sees is a business ("Gym / Fitness Centre"). What the system
// stores is a CompanyType plus, for the Generic-based ones, a business template
// and an industry template. Keeping the mapping here rather than in the dialog
// means the create form, the setup wizard and any future onboarding flow all
// agree on what "Gym" means.
//
// Most businesses are Generic templates, not a Farms.Type of their own. A new
// type needs its own farm guard, IAM company type, controller tree and setup
// SP; a template needs none of that. Livestock is the exception: it clones the
// Poultry module tree for other animals, so it is a real sixth type.

import type {
  BusinessTemplate,
  IndustryTemplate,
} from "@/lib/generic/template-labels"

export type CompanyType = "Poultry" | "Water" | "Generic" | "Hotel" | "Restaurant" | "Livestock"

export type BusinessCategory = "retail" | "service" | "subscription" | "other"

// ---------------------------------------------------------------------------
// Discovery groups — customer-facing headings in the Create New Company
// selector. These are NOT backend company families; every Generic template
// stays Generic regardless of its group.
// ---------------------------------------------------------------------------

export interface BusinessTypeGroup {
  id: string
  label: string
  /** Display order in the selector. */
  order: number
}

export const BUSINESS_GROUPS: BusinessTypeGroup[] = [
  { id: "specialized",   label: "Specialized Business Systems",           order: 1 },
  { id: "retail",        label: "Retail, Trading & Distribution",         order: 2 },
  { id: "services",      label: "Services & Professional Businesses",     order: 3 },
  { id: "subscriptions", label: "Subscriptions, Memberships & Education", order: 4 },
  { id: "general",       label: "General & Flexible",                     order: 5 },
]

export type BusinessGroupId = typeof BUSINESS_GROUPS[number]["id"]

export function findBusinessGroup(id: string): BusinessTypeGroup | undefined {
  return BUSINESS_GROUPS.find((g) => g.id === id)
}

// ---------------------------------------------------------------------------

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
  /** Discovery group for the Create New Company selector. */
  group: BusinessGroupId
  /** Extra search terms that help the user find this type. */
  searchAliases?: string[]
}

export const BUSINESS_TYPES: BusinessType[] = [
  // ---- GROUP 1: SPECIALIZED BUSINESS SYSTEMS --------------------------------
  {
    id: "water",
    label: "Water production",
    description: "Sachet or bottled water — production, distribution, drivers",
    companyType: "Water",
    group: "specialized",
  },
  {
    id: "poultry",
    label: "Poultry farm",
    description: "Flocks, houses, egg production, feed",
    companyType: "Poultry",
    group: "specialized",
  },
  {
    id: "livestock",
    label: "Livestock farm",
    description: "Ducks, guinea fowl, rabbits, goats, sheep, pigs, cattle and more",
    companyType: "Livestock",
    group: "specialized",
  },
  {
    id: "hotel",
    label: "Hotel",
    description: "Rooms, bookings, front desk",
    companyType: "Hotel",
    group: "specialized",
  },
  {
    id: "restaurant",
    label: "Restaurant",
    description: "POS, menu, kitchen, delivery",
    companyType: "Restaurant",
    group: "specialized",
  },

  // ---- GROUP 2: RETAIL, TRADING & DISTRIBUTION ------------------------------
  {
    id: "produce",
    label: "Yam & produce seller",
    description: "Yams, tomatoes, vegetables — purchases, sales and spoilage",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "ProduceSeller",
    category: "retail",
    group: "retail",
  },
  {
    id: "grocery",
    label: "Grocery shop / mini-mart",
    description: "Packaged goods, stock alerts, daily cash closing",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Grocery",
    category: "retail",
    group: "retail",
  },
  {
    id: "clothing",
    label: "Clothing & shoe shop",
    description: "Fashion, accessories — stock by size and style",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Retail", // shares Retail template — no unique seeding yet
    category: "retail",
    group: "retail",
  },
  {
    id: "hardware",
    label: "Hardware & building materials",
    description: "Cement, iron rods, paint — bulk and unit sales",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "HardwareShop",
    category: "retail",
    group: "retail",
  },
  {
    id: "electronics",
    label: "Phone & electronics shop",
    description: "Phones, accessories, repairs — serial tracking",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "ElectronicsShop",
    category: "retail",
    group: "retail",
  },
  {
    id: "wholesaler",
    label: "Wholesaler / distributor",
    description: "Bulk buying and reselling — customer credit, supplier payments",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Wholesaler",
    category: "retail",
    group: "retail",
  },
  {
    id: "bakery",
    label: "Bakery",
    description: "Bread, pastries — daily production and sales",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Bakery",
    category: "retail",
    group: "retail",
  },
  {
    id: "pharmacy",
    label: "Pharmacy",
    description: "Medicines, health products — stock and expiry tracking",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Pharmacy",
    category: "retail",
    group: "retail",
  },
  {
    id: "car-dealership",
    label: "Car dealership",
    description: "Vehicle sales — purchases, deposits, customer balances",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "CarDealership",
    category: "retail",
    group: "retail",
  },
  {
    id: "retail",
    label: "Other shop / retail",
    description: "Any store selling physical goods",
    companyType: "Generic",
    businessTemplate: "RetailBusiness",
    industryTemplate: "Retail",
    category: "retail",
    group: "retail",
  },

  // ---- GROUP 3: SERVICES & PROFESSIONAL BUSINESSES --------------------------
  {
    id: "cleaning",
    label: "Cleaning service",
    description: "Clients on service contracts",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "CleaningService",
    category: "subscription",
    group: "services",
  },
  {
    id: "security",
    label: "Security service",
    description: "Clients on service contracts",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "SecurityService",
    category: "subscription",
    group: "services",
  },
  {
    id: "agency",
    label: "Agency",
    description: "Clients on monthly retainers",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "Agency",
    category: "subscription",
    group: "services",
  },
  {
    id: "barbershop",
    label: "Barbershop",
    description: "Haircuts, shaves — walk-in sales, staff commissions",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Barbershop",
    category: "service",
    group: "services",
  },
  {
    id: "salon",
    label: "Hair salon & beauty",
    description: "Hair, nails, skincare — services, retail products, staff",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Salon",
    category: "service",
    group: "services",
  },
  {
    id: "auto-repair",
    label: "Auto repair garage",
    description: "Car repairs — job tracking, parts, labour",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "AutoRepair",
    category: "service",
    group: "services",
  },
  {
    id: "tailor",
    label: "Tailor / fashion designer",
    description: "Custom clothing — measurements, deposits, job tracking",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Tailor",
    category: "service",
    group: "services",
  },
  {
    id: "laundry",
    label: "Laundry & dry cleaning",
    description: "Wash, iron, dry clean — customer items and pickup",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Laundry",
    category: "service",
    group: "services",
  },
  {
    id: "freelancer",
    label: "Freelancer / consultant",
    description: "Client invoicing, project billing, expenses",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "Freelancer",
    category: "service",
    group: "services",
  },

  // ---- GROUP 4: SUBSCRIPTIONS, MEMBERSHIPS & EDUCATION ----------------------
  {
    id: "saas",
    label: "SaaS / software company",
    description: "Customers on recurring plans",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "SaaS",
    category: "subscription",
    group: "subscriptions",
  },
  {
    id: "gym",
    label: "Gym / fitness centre",
    description: "Members on monthly or annual memberships",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "Gym",
    category: "subscription",
    group: "subscriptions",
  },
  {
    id: "school",
    label: "School / training centre",
    description: "Students, termly fees, fee notes",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "School",
    category: "subscription",
    group: "subscriptions",
  },
  {
    id: "retainer",
    label: "Retainer business",
    description: "Any business billing a fixed amount each period",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "RetainerBusiness",
    category: "subscription",
    group: "subscriptions",
  },
  {
    id: "membership",
    label: "Membership organisation",
    description: "Members paying dues",
    companyType: "Generic",
    businessTemplate: "SubscriptionServiceBusiness",
    industryTemplate: "MembershipBusiness",
    category: "subscription",
    group: "subscriptions",
  },

  // ---- GROUP 5: GENERAL & FLEXIBLE -----------------------------------------
  {
    id: "other",
    label: "General Business",
    description: "Flexible business management for products, services, purchases, sales, expenses and more.",
    companyType: "Generic",
    businessTemplate: "GeneralBusiness",
    industryTemplate: "Other",
    category: "other",
    group: "general",
    searchAliases: ["other business"],
  },
]

export function findBusinessType(id: string): BusinessType | undefined {
  return BUSINESS_TYPES.find((t) => t.id === id)
}

/** True when creating this type should apply a template and open the wizard. */
export function needsTemplate(t: BusinessType | undefined): boolean {
  return Boolean(t?.businessTemplate && t?.industryTemplate)
}

// ---------------------------------------------------------------------------
// Grouped business types — used by the Create New Company selector.
// ---------------------------------------------------------------------------

export interface BusinessTypeGroupWithItems extends BusinessTypeGroup {
  items: BusinessType[]
}

/** Business types grouped and ordered for the Create New Company selector. */
export function groupedBusinessTypes(
  types: BusinessType[] = BUSINESS_TYPES,
): BusinessTypeGroupWithItems[] {
  const map = new Map<string, BusinessType[]>()
  for (const t of types) {
    const list = map.get(t.group) ?? []
    list.push(t)
    map.set(t.group, list)
  }
  return BUSINESS_GROUPS
    .filter((g) => map.has(g.id))
    .map((g) => ({ ...g, items: map.get(g.id)! }))
}

/**
 * Search business types by query. Case-insensitive, matches label,
 * description, and searchAliases. Returns grouped results with empty
 * groups filtered out.
 */
export function searchBusinessTypes(
  query: string,
  types: BusinessType[] = BUSINESS_TYPES,
): BusinessTypeGroupWithItems[] {
  if (!query.trim()) return groupedBusinessTypes(types)
  const q = query.toLowerCase()
  const matched = types.filter(
    (t) =>
      t.label.toLowerCase().includes(q) ||
      t.description.toLowerCase().includes(q) ||
      t.searchAliases?.some((a) => a.toLowerCase().includes(q)),
  )
  return groupedBusinessTypes(matched)
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

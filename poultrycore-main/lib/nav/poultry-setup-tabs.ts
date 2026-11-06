// Farm Setup (/poultry-setup) navigation model: its two sections, their tabs,
// and how a URL resolves to one of them. Kept free of React so the rules can be
// unit-tested (poultry-setup-tabs.test.ts) and shared with the Setup menu.
//
// URL shape: /poultry-setup?section=production|business&tab=<tab key>
// The URL is the only state: the page renders whatever this resolves to.

export type SetupSection = "production" | "business"

export type SetupTabKey =
  | "farm-profile" | "houses" | "flock-purchases" | "flock-groups" | "products"
  | "feed-formulas" | "egg-settings" | "inventory"
  | "company-profile" | "customers" | "suppliers" | "financial-settings" | "cash-accounts"
  | "drivers" | "vehicles" | "routes" | "staff"

export type SetupTab = {
  key: SetupTabKey
  label: string
  /** The one line shown under the tab row. */
  description: string
  /** Tabs sharing a group show as ONE tab with a secondary selector. */
  group?: string
  groupLabel?: string
}

const DELIVERY = { group: "delivery", groupLabel: "Delivery" } as const

export const SETUP_SECTIONS: Record<SetupSection, { label: string; tabs: SetupTab[] }> = {
  production: {
    label: "Production Setup",
    tabs: [
      { key: "farm-profile", label: "Farm profile", description: "Set the bird type, housing, capacity and egg crate size your farm works with." },
      { key: "houses", label: "Houses & pens", description: "Manage the houses and pens where your birds are kept." },
      { key: "flock-purchases", label: "Flock purchases", description: "Record the birds you bought; each batch is later divided into flock groups." },
      { key: "flock-groups", label: "Flock groups", description: "Manage the groups of birds you record production against." },
      { key: "products", label: "Products", description: "Manage products used in production, purchasing and sales." },
      { key: "feed-formulas", label: "Feed formulas", description: "Configure ingredient formulas used to produce feed." },
      { key: "egg-settings", label: "Egg settings", description: "Configure the egg settings used when recording production." },
      { key: "inventory", label: "Supply items", description: "Set up the feed, medication and other supply items your farm uses. Record purchases on the Inventory page." },
    ],
  },
  business: {
    label: "Business Setup",
    tabs: [
      { key: "company-profile", label: "Company profile", description: "Manage your business name, contact details and currency." },
      { key: "customers", label: "Customers", description: "Manage customer details used in sales and payments." },
      { key: "suppliers", label: "Suppliers", description: "Manage supplier details used in purchases and payments." },
      { key: "financial-settings", label: "Financial settings", description: "Choose when inventory costs count towards profit and loss." },
      { key: "cash-accounts", label: "Cash accounts", description: "Manage the cash and bank accounts money is paid into and out of." },
      { key: "drivers", label: "Drivers", description: "Manage the drivers who deliver your eggs, linked to your employees.", ...DELIVERY },
      { key: "vehicles", label: "Vehicles", description: "Manage the vehicles your eggs are loaded onto for delivery.", ...DELIVERY },
      { key: "routes", label: "Routes", description: "Manage the delivery routes and the areas each one covers.", ...DELIVERY },
      { key: "staff", label: "Staff", description: "Manage the farm's staff records used for payroll and assignments." },
    ],
  },
}

export const SETUP_PATH = "/poultry-setup"

export function setupHref(section: SetupSection, tab: SetupTabKey): string {
  return `${SETUP_PATH}?section=${section}&tab=${tab}`
}

/** Which section owns a tab. */
export function sectionOfTab(tab: string): SetupSection | null {
  for (const s of Object.keys(SETUP_SECTIONS) as SetupSection[]) {
    if (SETUP_SECTIONS[s].tabs.some((t) => t.key === tab)) return s
  }
  return null
}

/**
 * Tab aliases: the old wizard's ?step= values, plus a few natural spellings.
 * A string value is a tab; { href } is a page outside Farm Setup.
 */
const ALIASES: Record<string, SetupTabKey | { href: string }> = {
  // old /poultry-setup?step= keys
  company: "company-profile",
  flocks: "flock-groups",
  "raw-materials": "inventory",
  employees: { href: "/employees" }, // Users & Permissions stays in Administration
  // friendly spellings
  delivery: "drivers",
  "houses-pens": "houses",
  "flock-batches": "flock-purchases",
  "egg-picks": "egg-settings",
  finance: "financial-settings",
}

export type SetupLocation =
  | { kind: "ok"; section: SetupSection; tab: SetupTabKey }
  | { kind: "redirect"; href: string }
  | { kind: "none" }

/**
 * Resolve URL params to what Farm Setup shows. Order of precedence:
 *   1. an explicit, allowed ?tab= (its own section wins over a mismatched ?section=)
 *   2. a legacy ?step=
 *   3. ?section= alone -> that section's first allowed tab
 *   4. nothing usable -> Production, else Business, first allowed tab
 * An unknown or forbidden tab falls through to the next rule, never to an error.
 */
export function resolveSetupLocation(
  params: { section?: string | null; tab?: string | null; step?: string | null },
  allowed: (tab: SetupTabKey) => boolean,
): SetupLocation {
  const firstAllowed = (s: SetupSection) => SETUP_SECTIONS[s].tabs.find((t) => allowed(t.key))?.key

  const tryTab = (raw: string | null | undefined): SetupLocation | null => {
    if (!raw) return null
    const alias = ALIASES[raw]
    if (alias && typeof alias === "object") return { kind: "redirect", href: alias.href }
    const key = (alias ?? raw) as SetupTabKey
    const section = sectionOfTab(key)
    if (!section || !allowed(key)) return null
    return { kind: "ok", section, tab: key }
  }

  const fromTab = tryTab(params.tab) ?? tryTab(params.step)
  if (fromTab) return fromTab

  const order: SetupSection[] = params.section === "business" ? ["business", "production"]
    : ["production", "business"]
  for (const s of order) {
    const t = firstAllowed(s)
    if (t) return { kind: "ok", section: s, tab: t }
  }
  return { kind: "none" }
}

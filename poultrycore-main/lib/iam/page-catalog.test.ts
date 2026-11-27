import { describe, expect, it } from "vitest"
import { readdirSync, statSync } from "node:fs"
import { join } from "node:path"
import {
  LEGACY_FLAGS, MEMBER_ROUTES, PAGE_CATALOG, PLATFORM_ROUTES, PUBLIC_ROUTES,
  defaultKeysFor, keysForPage, pageKey, pagesForCompanyType, type LegacyFlag, type PageDef,
} from "@/lib/iam/page-catalog"
import { canOpenPath, resolvePathAccess } from "@/lib/iam/page-registry"
import { evaluateLegacy } from "@/lib/iam/legacy"
import type { FeatureAccessPermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import { isWaterNavItemVisible } from "@/lib/utils/water-nav-access"
import { isHotelNavItemVisible } from "@/lib/utils/hotel-nav-access"
import { isRestaurantNavItemVisible } from "@/lib/utils/restaurant-nav-access"
import { isSetupAdminRoute } from "@/lib/nav/setup-admin-routes"
import { WATER_STAFF_FEATURE_KEYS, STAFF_FEATURE_PERMISSION_OPTIONS } from "@/lib/employees/permissions"

const APP_DIR = join(__dirname, "..", "..", "app")

/** Every routable page folder under app/ (route groups and api excluded). */
function appRoutes(dir = APP_DIR, prefix = ""): string[] {
  const out: string[] = []
  for (const name of readdirSync(dir)) {
    const full = join(dir, name)
    if (!statSync(full).isDirectory()) {
      if (name === "page.tsx") out.push(prefix || "/")
      continue
    }
    if (name === "api" || name.startsWith("_")) continue
    const seg = name.startsWith("(") ? "" : `/${name}`
    out.push(...appRoutes(full, prefix + seg))
  }
  return out
}

describe("page catalog", () => {
  it("has unique page keys", () => {
    const seen = new Map<string, number>()
    for (const p of PAGE_CATALOG) seen.set(pageKey(p), (seen.get(pageKey(p)) ?? 0) + 1)
    expect([...seen].filter(([, n]) => n > 1)).toEqual([])
  })

  it("lists each route once per module", () => {
    const seen = new Set<string>()
    const dupes: string[] = []
    for (const p of PAGE_CATALOG) for (const r of p.routes) {
      const k = `${p.module}|${r}`
      if (seen.has(k)) dupes.push(k)
      seen.add(k)
    }
    expect(dupes).toEqual([])
  })

  it("only points at routes that exist (test 29: no permission without a page)", () => {
    // An app route like /hotel-reports/[slug] serves /hotel-reports/guest-ledger,
    // and /generic-invoice-documents/[id] makes /generic-invoice-documents a real prefix.
    const patterns = appRoutes().map((r) => r.replace(/\[[^\]]+\]/g, "[^/]+"))
    const exists = (route: string) =>
      patterns.some((pat) => new RegExp(`^${pat}(/|$)`).test(route) || pat.startsWith(route + "/"))
    const missing = PAGE_CATALOG.flatMap((p) => p.routes.filter((r) => !exists(r)).map((r) => `${pageKey(p)} → ${r}`))
    expect(missing).toEqual([])
  })

  it("covers every app page (test 29: no page without a permission)", () => {
    const uncovered = appRoutes()
      .map((r) => r.replace(/\/\[[^\]]+\](?=\/|$)/g, "/x"))
      .filter((r) => resolvePathAccess(r, "Poultry").kind === "unregistered"
        && ["Water", "Generic", "Hotel", "Restaurant", "Livestock"].every((t) => resolvePathAccess(r, t).kind === "unregistered"))
    expect(uncovered).toEqual([])
  })

  it("declares dependsOn targets that exist", () => {
    const keys = new Set(PAGE_CATALOG.map(pageKey))
    expect(PAGE_CATALOG.filter((p) => p.dependsOn && !keys.has(p.dependsOn)).map(pageKey)).toEqual([])
  })

  it("never lists a route as both public/member and permission-controlled", () => {
    const special = [...PUBLIC_ROUTES, ...MEMBER_ROUTES, ...PLATFORM_ROUTES]
    expect(PAGE_CATALOG.flatMap((p) => p.routes.filter((r) => special.includes(r)))).toEqual([])
  })
})

describe("business-family filtering (test 9)", () => {
  it("shows a Poultry company no hotel, restaurant, water, generic or livestock pages", () => {
    const modules = new Set(pagesForCompanyType("Poultry").map((p) => p.module))
    expect([...modules].sort()).toEqual(["office", "poultry"])
  })
  it("gives Generic its own pages and the shared ones only", () => {
    const modules = new Set(pagesForCompanyType("Generic").map((p) => p.module))
    expect([...modules].sort()).toEqual(["generic", "office"])
  })
  it("resolves a shared route to the active company's module", () => {
    expect(resolvePathAccess("/recurring-expenses", "Generic")).toMatchObject({ key: "generic.recurring-expenses.view" })
    expect(resolvePathAccess("/recurring-expenses", "Poultry")).toMatchObject({ key: "poultry.recurring-expenses.view" })
  })
  it("lets detail pages inherit their parent", () => {
    expect(resolvePathAccess("/expenses/42/edit", "Poultry")).toMatchObject({ key: "poultry.expenses.view" })
    expect(resolvePathAccess("/poultry/reports/profit-loss", "Poultry")).toMatchObject({ key: "poultry.profit-loss.view" })
    expect(resolvePathAccess("/poultry/reports/cash-movement", "Poultry")).toMatchObject({ key: "poultry.reports-financial.view" })
  })
})

describe("default policy (tests 11, 26)", () => {
  const poultryDefaults = new Set(defaultKeysFor(pagesForCompanyType("Poultry")))
  it("pre-ticks ordinary operational pages", () => {
    for (const k of ["poultry.production-records.view", "poultry.batch-production.view", "poultry.inventory.view",
      "poultry.feed-usage.view", "poultry.health.view", "poultry.sales.view", "poultry.sales.create", "poultry.expenses.view"]) {
      expect(poultryDefaults.has(k), k).toBe(true)
    }
  })
  it("never pre-ticks payroll, owner money, cash, P&L, admin or privileged actions", () => {
    for (const k of ["poultry.payroll.view", "poultry.employee-loans.view", "poultry.employee-credit.view", "poultry.owner-money.view",
      "poultry.cash.view", "poultry.cash-reconciliation.view", "poultry.assets.view", "poultry.profit-loss.view",
      "poultry.reports-financial.view", "office.access.view", "office.employee-password.view", "office.employee-access.edit",
      "poultry.sales.approve", "poultry.sales.reverse", "poultry.expenses.approve", "poultry.sales.delete"]) {
      expect(poultryDefaults.has(k), k).toBe(false)
    }
  })
  it("only defaults keys a page actually defines", () => {
    const all = new Set(PAGE_CATALOG.flatMap(keysForPage))
    expect([...poultryDefaults].filter((k) => !all.has(k))).toEqual([])
  })
})

// ---------------------------------------------------------------------------
// Test 12 — the catalog's legacy rules reproduce what staff actually saw.
//
// Before this upgrade a plain staff member's menu was decided by the per-family
// nav-access files below, fed by the 12 flags that survived login (water flags
// grandfathered on, hotel/restaurant flags always off). For every route those
// files have an opinion on, the catalog's `legacy` rule must agree, for every
// single flag on its own and for none/all — the rules are all OR-of-flags, so
// that is exhaustive.
// ---------------------------------------------------------------------------
function staffAccess(on: readonly LegacyFlag[]): FeatureAccessPermissions {
  const f: Record<string, boolean> = {}
  for (const o of STAFF_FEATURE_PERMISSION_OPTIONS) f[o.key] = false
  for (const k of WATER_STAFF_FEATURE_KEYS) f[k] = true
  for (const k of on) f[k] = true
  return f as unknown as FeatureAccessPermissions
}

function oldVisible(module: PageDef["module"], route: string, f: FeatureAccessPermissions): boolean | undefined {
  switch (module) {
    case "water": return route.startsWith("/water-") ? isWaterNavItemVisible(route, f, false) : undefined
    case "hotel": return isHotelNavItemVisible(route, f, false)
    case "restaurant": return isRestaurantNavItemVisible(route, f, false)
    case "poultry":
    case "generic":
      if (isSetupAdminRoute(route)) return false
      // The allow-list answers `false` for routes it does not know; only
      // routes it knows (visible with every flag on) are its opinion.
      if (!isFinancialNavItemVisible(route, staffAccess([...LEGACY_FLAGS]), false)) return undefined
      return isFinancialNavItemVisible(route, f, false)
    default: return undefined
  }
}

/**
 * Routes where the old rule is knowingly not reproduced, with the reason.
 * Every entry is a page that is not in any menu, so no staff member saw it.
 */
const KNOWN_DIFFERENCES = new Set<string>([
  "hotel|/hotel-customer-payments", // orphan page (not in the menu); now follows Customer Payments
  "poultry|/cash",                   // hidden legacy page; follows Financial Activity
  // The P&L report now follows the Profit & Loss page (same statement). Someone
  // with View Financial but not View Reports already saw it at /water-profit-loss.
  "water|/water-reports/profit-loss",
])

describe("legacy access is preserved (test 12)", () => {
  const combos: LegacyFlag[][] = [[], [...LEGACY_FLAGS], ...LEGACY_FLAGS.map((f) => [f])]
  it("matches the old per-family visibility rules", () => {
    const mismatches: string[] = []
    for (const page of PAGE_CATALOG) for (const route of page.routes) {
      if (KNOWN_DIFFERENCES.has(`${page.module}|${route}`)) continue
      for (const on of combos) {
        const f = staffAccess(on)
        const old = oldVisible(page.module, route, f)
        if (old === undefined) continue
        const now = evaluateLegacy(page.legacy, new Set(on))
        if (old !== now) mismatches.push(`${pageKey(page)} ${route} flags=[${on.join(",")}] old=${old} new=${now}`)
      }
    }
    expect([...new Set(mismatches.map((m) => m.split(" flags=")[0]))]).toEqual([])
  })
})

describe("canOpenPath (tests 1, 3, 4, 5, 8, 30)", () => {
  const staff = (keys: string[]) => ({ companyType: "Poultry", isOwner: false, can: (k: string) => keys.includes(k) })
  it("denies Sales when View Sales is off", () => {
    expect(canOpenPath("/sales", staff(["poultry.expenses.view"]))).toBe(false)
    expect(canOpenPath("/sales/new", staff(["poultry.expenses.view"]))).toBe(false)
  })
  it("keeps Sales open while Customer Balances is off", () => {
    const s = staff(["poultry.sales.view"])
    expect(canOpenPath("/sales", s)).toBe(true)
    expect(canOpenPath("/customer-balances", s)).toBe(false)
  })
  it("denies Profit & Loss and its report twin", () => {
    const s = staff(["poultry.sales.view", "poultry.reports.view"])
    expect(canOpenPath("/poultry-profit-loss", s)).toBe(false)
    expect(canOpenPath("/poultry/reports/profit-loss", s)).toBe(false)
  })
  it("separates Expenses from Supplier Balances", () => {
    const s = staff(["poultry.expenses.view"])
    expect(canOpenPath("/expenses", s)).toBe(true)
    expect(canOpenPath("/supplier-balances", s)).toBe(false)
  })
  it("separates Production Records from Feed Production", () => {
    const s = staff(["poultry.production-records.view"])
    expect(canOpenPath("/production-records", s)).toBe(true)
    expect(canOpenPath("/poultry-feed-production", s)).toBe(false)
  })
  it("requires the Reports menu for a report category", () => {
    expect(canOpenPath("/poultry/reports/egg-sales", staff(["poultry.reports-sales.view"]))).toBe(false)
    expect(canOpenPath("/poultry/reports/egg-sales", staff(["poultry.reports-sales.view", "poultry.reports.view"]))).toBe(true)
  })
  it("opens dashboards and help to every member, and everything to owners", () => {
    expect(canOpenPath("/dashboard", staff([]))).toBe(true)
    expect(canOpenPath("/poultry-payroll", { companyType: "Poultry", isOwner: true, can: () => false })).toBe(true)
  })
  it("denies unregistered paths to staff", () => {
    expect(canOpenPath("/some-page-nobody-registered", staff(["poultry.sales.view"]))).toBe(false)
  })
})

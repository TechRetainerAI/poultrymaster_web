import { describe, it, expect } from "vitest"
import { existsSync } from "node:fs"
import { join } from "node:path"
import type { FeatureAccessPermissions, UserPermissions } from "@/hooks/use-permissions"
import type { GenericModulesResult } from "@/hooks/use-generic-modules"
import type { GenericModuleSettings } from "@/lib/api/generic-subscriptions"
import { templateLabels } from "@/lib/generic/template-labels"
import { buildGenericNavConfig } from "./generic-nav-config"
import type { MegaMenuGroup } from "./nav-model"

function modules(settings: Partial<GenericModuleSettings> | null): GenericModulesResult {
  const s = settings as GenericModuleSettings | null
  return {
    settings: s, industry: null, business: "RetailBusiness", isSubscriptionBusiness: false,
    businessSettings: null, labels: templateLabels(null), isLoading: false,
    showNew: (k) => Boolean(s?.[k]),
    showExisting: (k) => (s?.[k] === undefined || s?.[k] === null ? true : Boolean(s?.[k])),
    showCard: () => true,
  }
}

const perms = (isAdmin: boolean, f: Partial<FeatureAccessPermissions> = {}) =>
  ({ isAdmin, featureAccess: f as FeatureAccessPermissions, can: () => true }) as unknown as UserPermissions

function hrefs(nav: Record<string, MegaMenuGroup[]>): string[] {
  return Object.values(nav).flatMap((groups) => groups.flatMap((g) => g.items.filter((i) => i.visible !== false).map((i) => i.href!)))
}

const BASE: Partial<GenericModuleSettings> = {
  enableProducts: true, enableInventory: true, enablePurchases: true, enableCashAccounts: true,
}

describe("generic nav — Projects & Contracts", () => {
  it("is hidden for a company that has not switched it on, and while settings load", () => {
    expect(buildGenericNavConfig(modules(BASE)).catalog.map((g) => g.key)).not.toContain("catalog-projects")
    expect(buildGenericNavConfig(modules(null)).catalog.map((g) => g.key)).not.toContain("catalog-projects")
  })

  it("appears under Operations when switched on", () => {
    const nav = buildGenericNavConfig(modules({ ...BASE, enableProjects: true }))
    const g = nav.catalog.find((x) => x.key === "catalog-projects")
    expect(g?.label).toBe("Projects & Contracts")
    expect(g?.items.map((i) => i.href)).toEqual([
      "/generic-projects", "/generic-projects/new", "/generic-projects/compare", "/generic-projects/link",
    ])
  })

  it("links only to pages that exist", () => {
    const nav = buildGenericNavConfig(modules({ ...BASE, enableProjects: true }))
    const projectLinks = hrefs(nav as unknown as Record<string, MegaMenuGroup[]>)
      .map((h) => h.split("?")[0]).filter((h) => h.startsWith("/generic-projects"))
    expect(projectLinks.length).toBe(4)
    for (const h of projectLinks) {
      expect(existsSync(join(process.cwd(), "app", ...h.slice(1).split("/"), "page.tsx")), h).toBe(true)
    }
  })

  it("shows staff the register only with a financial or reports flag; never the setup rows without Financial", () => {
    const on = modules({ ...BASE, enableProjects: true })
    const none = hrefs(buildGenericNavConfig(on, perms(false)) as any)
    expect(none.filter((h) => h.startsWith("/generic-projects"))).toEqual([])
    const reports = hrefs(buildGenericNavConfig(on, perms(false, { canViewReports: true })) as any)
    expect(reports).toContain("/generic-projects")
    expect(reports).toContain("/generic-projects/compare")
    expect(reports).not.toContain("/generic-projects/new")
    expect(reports).not.toContain("/generic-projects/link")
  })
})

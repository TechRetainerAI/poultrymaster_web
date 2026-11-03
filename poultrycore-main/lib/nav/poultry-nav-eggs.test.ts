import { describe, it, expect } from "vitest"
import type { FeatureAccessPermissions, UserPermissions } from "@/hooks/use-permissions"
import type { MegaMenuGroup } from "./nav-model"
import { buildPoultryNavConfig, POULTRY_EGG_ONLY_HREFS } from "./poultry-nav-config"

// Migration 399: a broiler-only company sees no egg pages anywhere in the menus.

const admin = {
  isAdmin: true,
  featureAccess: {} as FeatureAccessPermissions,
  can: () => true,
} as unknown as UserPermissions

function visibleHrefs(showEggFeatures?: boolean): Set<string> {
  const nav = buildPoultryNavConfig({
    permissions: admin,
    onOpenAlerts: () => {},
    // A pinned egg page must disappear too.
    quickLinkHrefs: ["/egg-tracker", "/production-records"],
    showEggFeatures,
  })
  const out = new Set<string>()
  for (const section of Object.values(nav)) {
    if (Array.isArray(section)) {
      for (const g of section as MegaMenuGroup[]) for (const i of g.items) if (i.href && i.visible !== false) out.add(i.href)
    }
  }
  for (const i of nav.quickLinks.items) out.add(i.href)
  return out
}

describe("poultry nav egg pages", () => {
  it("shows them by default (callers that do not know)", () => {
    const hrefs = visibleHrefs(undefined)
    expect(hrefs.has("/egg-tracker")).toBe(true)
    expect(hrefs.has("/poultry-egg-sorting")).toBe(true)
  })

  it("hides every egg-only page, quick links included, for a broiler-only company", () => {
    const hrefs = visibleHrefs(false)
    for (const h of POULTRY_EGG_ONLY_HREFS) expect(hrefs.has(h), h).toBe(false)
    expect(hrefs.has("/production-records")).toBe(true)
    expect(hrefs.has("/flocks")).toBe(true)
  })
})

describe("poultry nav broiler pages (402)", () => {
  const hrefsWith = (showBroilerFeatures?: boolean) => {
    const nav = buildPoultryNavConfig({ permissions: admin, onOpenAlerts: () => {}, showBroilerFeatures })
    const out = new Set<string>()
    for (const section of Object.values(nav)) {
      if (Array.isArray(section)) for (const g of section as MegaMenuGroup[]) for (const i of g.items) if (i.href && i.visible !== false) out.add(i.href)
    }
    return out
  }
  it("shows Broiler performance by default and hides it on a layer-only farm", () => {
    expect(hrefsWith(undefined).has("/poultry-broiler-performance")).toBe(true)
    expect(hrefsWith(false).has("/poultry-broiler-performance")).toBe(false)
  })
})

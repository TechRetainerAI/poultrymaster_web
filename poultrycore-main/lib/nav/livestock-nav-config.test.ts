import { describe, it, expect } from "vitest"
import { existsSync } from "node:fs"
import { join } from "node:path"
import type { FeatureAccessPermissions, UserPermissions } from "@/hooks/use-permissions"
import type { MegaMenuGroup } from "./nav-model"
import { buildLivestockNavConfig, navSectionHasRows } from "./livestock-nav-config"
import { isSetupAdminRoute } from "./setup-admin-routes"

const perms = (isAdmin: boolean) => ({
  isAdmin,
  featureAccess: { canViewActivityLog: true } as FeatureAccessPermissions,
  can: () => true,
}) as unknown as UserPermissions

function rows(isAdmin: boolean, quickLinkHrefs?: string[] | null) {
  const nav = buildLivestockNavConfig({ permissions: perms(isAdmin), onOpenAlerts: () => {}, quickLinkHrefs })
  const visible: string[] = []
  for (const section of Object.values(nav)) {
    if (!Array.isArray(section)) continue
    for (const g of section as MegaMenuGroup[]) for (const i of g.items) if (i.href && i.visible !== false) visible.push(i.href)
  }
  return { nav, visible }
}

describe("livestock nav", () => {
  it("links only to pages that exist", () => {
    const { nav, visible } = rows(true)
    const hrefs = [...visible, ...nav.quickLinks.items.map((i) => i.href)]
      .map((h) => h.split("?")[0])
      .filter((h) => h.startsWith("/livestock"))
    expect(hrefs.length).toBeGreaterThan(0)
    for (const h of hrefs) {
      expect(existsSync(join(process.cwd(), "app", ...h.slice(1).split("/"), "page.tsx")), h).toBe(true)
    }
  })

  it("names its money groups so the sidebar shows every one of them", () => {
    // The sidebar's Sales / Expenses / Money menus pick groups by these keys only.
    const { nav } = rows(true)
    expect(nav.salesMoney.map((g) => g.key).sort()).toEqual(["expenses", "money", "sales"])
  })

  it("keeps every link inside the livestock routes or the shared ones", () => {
    const { visible } = rows(true)
    for (const h of visible) expect(h.startsWith("/livestock") || !/^\/(poultry|water|generic|hotel|restaurant)/.test(h), h).toBe(true)
  })

  it("hides setup pages from an ordinary employee", () => {
    const { nav, visible } = rows(false)
    expect(visible.some(isSetupAdminRoute)).toBe(false)
    expect(navSectionHasRows(nav.setup)).toBe(false)
  })

  it("shows the default quick links until the user customises them", () => {
    expect(rows(true, null).nav.quickLinks.items.map((i) => i.href)).toEqual(["/livestock-production-records", "/livestock-sales", "/livestock-customer-balances", "/livestock-daily-closing", "/livestock-groups", "/livestock-animals"])
    expect(rows(true, []).nav.quickLinks.items).toEqual([])
    // A pinned page from another company type cannot leak in.
    expect(rows(true, ["/flocks", "/livestock-animals"]).nav.quickLinks.items.map((i) => i.href)).toEqual(["/livestock-animals"])
  })
  it("hides breeding when no kept animal is bred on the farm", () => {
    const nav = buildLivestockNavConfig({ permissions: perms(true), onOpenAlerts: () => {}, showBreedingFeatures: false })
    const hrefs = nav.operations.flatMap((g) => g.items.filter((i) => i.visible !== false).map((i) => i.href))
    expect(hrefs).not.toContain("/livestock-breeding")
    const reports = nav.analytics.flatMap((g) => g.items.filter((i) => i.visible !== false).map((i) => i.href))
    expect(reports).not.toContain("/livestock/reports/breeding")
    expect(hrefs).toContain("/livestock-production-records")
  })
})

import { describe, expect, it } from "vitest"
import { pagesForCompanyType, viewKey, PAGE_CATALOG } from "@/lib/iam/page-catalog"
import {
  actionKey, defaultProfile, diffDrafts, groupForDisplay, setPageAction, setPageView, setSection, sensitiveTurnedOnBy,
} from "@/lib/iam/page-access-editor"
import { applyPageAccess, legacyGate } from "@/lib/iam/nav-access"
import { featureAccessFromKeys } from "@/lib/iam/feature-shim"
import { canOpenPath } from "@/lib/iam/page-registry"
import type { UserPermissions } from "@/hooks/use-permissions"

const poultry = pagesForCompanyType("Poultry")
const page = (resource: string) => poultry.find((p) => p.resource === resource && p.module === "poultry")!

describe("editor state (tests 24, 25)", () => {
  it("unticking a page removes everything it lets you do", () => {
    const sales = page("sales")
    let d = setPageView(new Set(), sales, true)
    d = setPageAction(d, sales, "approve", true)
    expect(d.has("poultry.sales.approve")).toBe(true)
    d = setPageView(d, sales, false)
    expect([...d].filter((k) => k.startsWith("poultry.sales."))).toEqual([])
  })

  it("ticking an action ticks the page too", () => {
    const d = setPageAction(new Set(), page("expenses"), "create", true)
    expect(d.has("poultry.expenses.view")).toBe(true)
  })

  it("search and the enabled/disabled filter never change the draft", () => {
    const draft = new Set(["poultry.sales.view", "poultry.payroll.view", "poultry.flocks.view"])
    const before = [...draft].sort()
    groupForDisplay(poultry, draft, "payroll", "all")
    groupForDisplay(poultry, draft, "", "disabled")
    groupForDisplay(poultry, draft, "", "enabled")
    expect([...draft].sort()).toEqual(before)
  })

  it("filters what is shown", () => {
    const draft = new Set(["poultry.sales.view"])
    const enabled = groupForDisplay(poultry, draft, "", "enabled").flatMap((s) => s.pages.map(viewKey))
    expect(enabled).toEqual(["poultry.sales.view"])
    const found = groupForDisplay(poultry, draft, "profit", "all").flatMap((s) => s.pages.map((p) => p.label))
    expect(found).toContain("Profit & Loss")
  })

  it("Select all skips sensitive pages unless confirmed, and never grants approve", () => {
    const money = poultry.filter((p) => p.section === "Money")
    expect(sensitiveTurnedOnBy(new Set(), money).length).toBeGreaterThan(0)
    const without = setSection(new Set(), money, true, false)
    expect(without.has("poultry.profit-loss.view")).toBe(false)
    const withSensitive = setSection(new Set(), money, true, true)
    expect(withSensitive.has("poultry.profit-loss.view")).toBe(true)
    expect([...withSensitive].some((k) => k.endsWith(".approve"))).toBe(false)
  })

  it("keeps hundreds of ticks through a round of edits (save payload is the whole draft)", () => {
    let d = defaultProfile(poultry)
    const n = d.size
    expect(n).toBeGreaterThan(50)
    d = setPageView(d, page("profit-loss"), true)
    d = setPageView(d, page("sales"), false)
    const diff = diffDrafts(defaultProfile(poultry), d)
    expect(diff.added).toEqual(["poultry.profit-loss.view"])
    expect(diff.removed.every((k) => k.startsWith("poultry.sales."))).toBe(true)
  })

  it("Reset to default keeps finer keys the person already had", () => {
    const d = defaultProfile(poultry, new Set(["poultry.customer-payments.create"]))
    expect(d.has("poultry.customer-payments.create")).toBe(true)
    expect(d.has("poultry.payroll.view")).toBe(false)
  })
})

describe("menus follow page access (test 21)", () => {
  const perms = (keys: string[], pageAccess = true): UserPermissions => {
    const can = (k: string) => keys.includes(k)
    return {
      pageAccess, isOwner: false, accessLoaded: true, can, permissionKeys: new Set(keys), isSuperuser: false,
      canOpen: (href: string) => canOpenPath(href, { companyType: "Poultry", isOwner: false, can }),
      featureAccess: featureAccessFromKeys(can, "Poultry"), isAdmin: false, isStaff: true, isSubscriber: false,
      roles: [], canDelete: false, canEdit: true, canCreate: true, canView: true, isLoading: false,
    } as UserPermissions
  }
  const config = {
    salesMoney: [
      { key: "sales", label: "Sales", items: [{ id: "s", title: "Sales", href: "/sales" }, { id: "cb", title: "Customer Balances", href: "/customer-balances" }] },
      { key: "money", label: "Money", items: [{ id: "pl", title: "Profit & Loss", href: "/poultry-profit-loss" }] },
    ],
  }

  it("drops rows the person cannot open and sections left empty", () => {
    const out = applyPageAccess(config, perms(["poultry.sales.view"]))
    expect(out.salesMoney.map((g) => g.key)).toEqual(["sales"])
    expect(out.salesMoney[0].items.map((i) => i.href)).toEqual(["/sales"])
  })

  it("does nothing before page access is live", () => {
    expect(applyPageAccess(config, perms([], false))).toBe(config)
    const p = perms([], false)
    expect(legacyGate(p)).toBe(p)
  })

  it("lets the old flag rules stand aside once page access is live", () => {
    const gated = legacyGate(perms([]))!
    expect(gated.featureAccess.canViewFinancial).toBe(true)
    expect(gated.isAdmin).toBe(true)
  })
})

describe("old flags derived from keys", () => {
  it("answers canEnterSales from the active company's Sales page", () => {
    const can = (k: string) => k === "water.sales.view"
    expect(featureAccessFromKeys(can, "Water").canEnterSales).toBe(true)
    expect(featureAccessFromKeys(can, "Poultry").canEnterSales).toBe(false)
  })
})

describe("multi-company (test 10)", () => {
  it("decides the same URL by the active company's grants", () => {
    const companyA = (k: string) => ["poultry.sales.view", "poultry.expenses.view"].includes(k)
    const companyB = (k: string) => ["water.sales.view", "water.profit-loss.view"].includes(k)
    expect(canOpenPath("/poultry-profit-loss", { companyType: "Poultry", isOwner: false, can: companyA })).toBe(false)
    expect(canOpenPath("/water-profit-loss", { companyType: "Water", isOwner: false, can: companyB })).toBe(true)
    expect(canOpenPath("/water-expenses", { companyType: "Water", isOwner: false, can: companyB })).toBe(false)
    // Company A's grants never open company B's pages.
    expect(canOpenPath("/water-sales", { companyType: "Water", isOwner: false, can: companyA })).toBe(false)
  })
})

it("every catalog action key the editor can tick is unique", () => {
  const keys = PAGE_CATALOG.flatMap((p) => (p.actions ?? []).map((a) => actionKey(p, a)))
  expect(new Set(keys).size).toBe(keys.length)
})

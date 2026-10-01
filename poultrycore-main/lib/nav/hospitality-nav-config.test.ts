import { describe, it, expect } from "vitest"
import type { FeatureAccessPermissions, UserPermissions } from "@/hooks/use-permissions"
import type { MegaMenuGroup } from "./nav-model"
import { buildPoultryNavConfig } from "./poultry-nav-config"
import { buildRestaurantNavConfig } from "./restaurant-nav-config"
import { buildHotelNavConfig } from "./hotel-nav-config"
import { isGatedHotelRoute } from "@/lib/utils/hotel-nav-access"

// Restaurant and Hotel copy Poultry's "Sales, Expenses & Money" menu word for
// word. These tests pin that: every Restaurant/Hotel row must be a Poultry row
// (same column, same label, same icon) and appear in Poultry's order. A row may
// be MISSING -- its page is not built yet -- but never renamed, reordered or
// invented. Adding a row later in the wrong place, or under a new name, fails
// here rather than in someone's screenshot.

const access = (over: Partial<FeatureAccessPermissions> = {}) =>
  ({
    canEnterSales: false,
    canEnterExpenses: false,
    canViewCashLedger: false,
    canViewFinancial: false,
    canViewCustomers: false,
    canViewReports: false,
    canSeeEmployees: false,
    canViewRestaurantPOS: false,
    canViewRestaurantStaff: false,
    canViewHotelBilling: false,
    canViewHotelPayroll: false,
    ...over,
  }) as unknown as FeatureAccessPermissions

const perms = (isAdmin: boolean, over: Partial<FeatureAccessPermissions> = {}) =>
  ({ isAdmin, featureAccess: access(over) }) as unknown as UserPermissions

const admin = perms(true)
const poultry = buildPoultryNavConfig({ permissions: admin, onOpenAlerts: () => {} }).salesMoney

const rows = (groups: MegaMenuGroup[]) =>
  groups.map((g) => ({ key: g.key, label: g.label, items: g.items.filter((i) => i.visible !== false) }))

describe.each([
  ["Restaurant", () => buildRestaurantNavConfig({}, admin).salesMoney],
  ["Hotel", () => buildHotelNavConfig({ permissions: admin }).salesMoney],
])("%s Sales, Expenses & Money", (_name, build) => {
  const menu = build()

  it("has Poultry's three columns, in Poultry's order, with Poultry's headings", () => {
    expect(menu.map((g) => [g.key, g.label])).toEqual(poultry.map((g) => [g.key, g.label]))
  })

  it("uses only Poultry's rows, word for word, with Poultry's icons, in Poultry's order", () => {
    rows(menu).forEach((col, c) => {
      const ref = poultry[c].items
      let last = -1
      for (const item of col.items) {
        const at = ref.findIndex((r) => r.title === item.title)
        expect(at, `"${item.title}" is not a Poultry ${col.label} row`).toBeGreaterThanOrEqual(0)
        expect(at, `"${item.title}" is out of Poultry's order`).toBeGreaterThan(last)
        expect(item.icon, `"${item.title}" icon`).toBe(ref[at].icon)
        last = at
      }
    })
  })

  it("points every row at a page of its own module", () => {
    const prefix = _name === "Restaurant" ? "/restaurant-" : "/hotel-"
    for (const col of menu) for (const item of col.items) {
      expect(item.href?.startsWith(prefix), `${item.title} -> ${item.href}`).toBe(true)
    }
  })
})

describe("permission gating", () => {
  it("Restaurant: a staff member with no money flags sees no money rows", () => {
    const menu = buildRestaurantNavConfig({}, perms(false)).salesMoney
    const visible = rows(menu).flatMap((g) => g.items.map((i) => i.href))
    // Expenses is deliberately ungated in restaurant-nav-access.ts (staff record
    // expenses there today); Internal Use follows Inventory, which staff use
    // (migration 330); everything else is behind a flag.
    expect(visible).toEqual(["/restaurant-expenses", "/restaurant-internal-use"])
  })

  it("Restaurant: Sales column has Poultry's three rows and gates (migration 333)", () => {
    const titles = (over: Partial<FeatureAccessPermissions>) =>
      rows(buildRestaurantNavConfig({}, perms(false, over)).salesMoney)
        .find((g) => g.key === "sales")!.items.map((i) => i.title)
    expect(rows(buildRestaurantNavConfig({}, admin).salesMoney)[0].items.map((i) => i.title))
      .toEqual(["Sales", "Payments", "Customer Balances"])
    expect(titles({ canEnterSales: true })).toEqual(expect.arrayContaining(["Payments", "Customer Balances"]))
    expect(titles({ canViewCustomers: true })).toContain("Customer Balances")
    expect(titles({ canViewCustomers: true })).not.toContain("Payments")
    expect(titles({ canViewCashLedger: true })).not.toContain("Payments")
  })

  it("Restaurant: Internal Use sits right after Expenses and follows the Inventory rule", () => {
    const items = buildRestaurantNavConfig({}, admin).salesMoney.find((g) => g.key === "expenses")!.items
    expect(items.slice(0, 2).map((i) => i.title)).toEqual(["Expenses", "Internal Use"])
    const staff = buildRestaurantNavConfig({}, perms(false))
    const iu = staff.salesMoney.find((g) => g.key === "expenses")!.items.find((i) => i.title === "Internal Use")!
    const inv = staff.inventoryReports.flatMap((g) => g.items).find((i) => i.href === "/restaurant-inventory")!
    expect(iu.visible).toBe(inv.visible)
  })

  it("Restaurant: the cash-ledger flag opens the Money column", () => {
    const menu = buildRestaurantNavConfig({}, perms(false, { canViewCashLedger: true })).salesMoney
    const money = rows(menu).find((g) => g.key === "money")!.items.map((i) => i.title)
    expect(money).toEqual([
      "Cash Flow", "Financial Activity", "Profit & Loss", "Owner Money", "Loans (Financing)",
      "Cash Account", "Cash Transfers", "Reconciliation",
    ])
  })

  it("Restaurant: Capital Investments/Assets follows Poultry's gate (expenses or financial)", () => {
    const titles = (over: Partial<FeatureAccessPermissions>) =>
      rows(buildRestaurantNavConfig({}, perms(false, over)).salesMoney)
        .find((g) => g.key === "expenses")!.items.map((i) => i.title)
    expect(titles({ canEnterExpenses: true })).toContain("Capital Investments/Assets")
    expect(titles({ canViewFinancial: true })).toContain("Capital Investments/Assets")
    expect(titles({ canViewCashLedger: true })).not.toContain("Capital Investments/Assets")
  })

  it("Restaurant: supplier rows follow Poultry's gates (migration 329)", () => {
    const titles = (over: Partial<FeatureAccessPermissions>) =>
      rows(buildRestaurantNavConfig({}, perms(false, over)).salesMoney)
        .find((g) => g.key === "expenses")!.items.map((i) => i.title)
    // Supplier Balances / Payments: financial, expenses or customers.
    for (const flag of ["canViewFinancial", "canEnterExpenses", "canViewCustomers"] as const) {
      expect(titles({ [flag]: true })).toEqual(expect.arrayContaining(["Supplier Payments", "Supplier Balances"]))
    }
    // Deferred inventory cost: expenses or financial, NOT customers.
    expect(titles({ canEnterExpenses: true })).toContain("Deferred inventory cost")
    expect(titles({ canViewCustomers: true })).not.toContain("Deferred inventory cost")
    expect(titles({ canViewCashLedger: true })).not.toContain("Supplier Balances")
  })

  it("Restaurant: Setup has Poultry's Finance group with Suppliers", () => {
    const finance = buildRestaurantNavConfig({}, admin).setup.find((g) => g.key === "finance")
    expect(finance?.label).toBe("Finance")
    expect(finance?.items.map((i) => [i.title, i.href])).toEqual([["Suppliers", "/restaurant-suppliers"]])
    const staff = buildRestaurantNavConfig({}, perms(false)).setup.find((g) => g.key === "finance")!
    expect(staff.items.every((i) => i.visible === false)).toBe(true)
  })

  it("Restaurant: with no permissions passed, rows stay visible as they always were", () => {
    const menu = buildRestaurantNavConfig().salesMoney
    expect(menu.every((g) => g.items.every((i) => i.visible === true))).toBe(true)
  })

  it("Hotel: every Sales, Expenses & Money row has its own rule", () => {
    // Without one, isHotelNavItemVisible falls through to `true` and the
    // sidebar -- which gates by each row's own href -- shows it to everyone.
    const menu = buildHotelNavConfig({ permissions: admin }).salesMoney
    for (const g of menu) for (const i of g.items) {
      expect(isGatedHotelRoute(i.href!), i.href).toBe(true)
    }
  })

  it("Hotel: a staff member with no flags sees no money rows", () => {
    const menu = buildHotelNavConfig({ permissions: perms(false) }).salesMoney
    expect(rows(menu).flatMap((g) => g.items)).toEqual([])
  })
})

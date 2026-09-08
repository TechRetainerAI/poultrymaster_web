import { describe, it, expect } from "vitest"
import { isWaterNavItemVisible, isGatedWaterRoute } from "./water-nav-access"
import type { FeatureAccessPermissions } from "@/hooks/use-permissions"

// The water gate is the OPPOSITE shape to the poultry one: unknown routes fail
// OPEN (`if (!rule) return true`), so a new water page cannot silently vanish
// the way Cash Transfers, Owner Money and Loans did on the poultry rail.
//
// That makes the failure mode here the mirror image, and it is what these tests
// watch for: a new money page that nobody classified stays VISIBLE to staff who
// should not see it. So the money routes are pinned by name, and the last test
// asserts the fail-open behaviour deliberately rather than by accident.

const access = (over: Partial<FeatureAccessPermissions> = {}) =>
  ({
    canEnterSales: false,
    canEnterExpenses: false,
    canViewCashLedger: false,
    canViewFinancial: false,
    canViewCustomers: false,
    canViewReports: false,
    canViewWaterProduction: false,
    canViewWaterInventory: false,
    canViewWaterDeliveries: false,
    canViewWaterPayroll: false,
    canViewWaterSetup: false,
    canViewWaterMaintenance: false,
    canViewInternalUse: false,
    canSeeEmployees: false,
    ...over,
  }) as unknown as FeatureAccessPermissions

// The Money group in the sidebar, the top nav and the mobile sheet. All three
// surfaces run through this gate, so one list covers them.
const MONEY_PAGES = [
  "/water-cash-flow",
  "/water-cash-accounts",
  "/water-cash-reconciliation",
  "/water-cash-transfers",
  "/water-owner-money",
  "/water-loans",
]

describe("isWaterNavItemVisible", () => {
  it("shows every Money page to someone who can see the cash ledger", () => {
    const f = access({ canViewCashLedger: true })
    for (const href of MONEY_PAGES) {
      expect(isWaterNavItemVisible(href, f, false), href).toBe(true)
    }
  })

  it("hides every Money page from someone who cannot", () => {
    // Staff are deny-by-default, which is exactly why migrations 257-259's
    // pages ride the existing cash-ledger flag rather than a new permission
    // nobody has been granted yet.
    const f = access()
    for (const href of MONEY_PAGES) {
      expect(isWaterNavItemVisible(href, f, false), href).toBe(false)
    }
  })

  it("classifies every Money page, so none of them fails open", () => {
    // The water-specific trap. An unclassified route is VISIBLE, so a money
    // page that nobody added here would show to staff with no cash access at
    // all -- and the test above would still pass, because it would return true
    // for the wrong reason. This is the line that catches that.
    for (const href of MONEY_PAGES) {
      expect(isGatedWaterRoute(href), href).toBe(true)
    }
  })

  it("shows everything to an admin", () => {
    const f = access()
    for (const href of MONEY_PAGES) {
      expect(isWaterNavItemVisible(href, f, true), href).toBe(true)
    }
  })

  it("fails OPEN on a route it has never heard of", () => {
    // Deliberate, and the reverse of the poultry gate: a new water page
    // appearing for everyone is a smaller problem than one silently vanishing.
    // Pinned so nobody "fixes" it into an allowlist without meaning to.
    const f = access()
    expect(isWaterNavItemVisible("/water-something-new", f, false)).toBe(true)
    expect(isGatedWaterRoute("/water-something-new")).toBe(false)
  })

  it("still gates the older water pages the way it always did", () => {
    expect(isWaterNavItemVisible("/water-sales", access({ canEnterSales: true }), false)).toBe(true)
    expect(isWaterNavItemVisible("/water-sales", access(), false)).toBe(false)
    expect(isWaterNavItemVisible("/water-expenses", access({ canEnterExpenses: true }), false)).toBe(true)
    expect(isWaterNavItemVisible("/water-payroll", access({ canViewWaterPayroll: true }), false)).toBe(true)
    expect(isWaterNavItemVisible("/water-reports", access({ canViewReports: true }), false)).toBe(true)
  })
})

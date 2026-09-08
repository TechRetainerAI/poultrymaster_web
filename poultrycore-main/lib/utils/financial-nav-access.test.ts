import { describe, it, expect } from "vitest"
import { isFinancialNavItemVisible } from "./financial-nav-access"
import type { FeatureAccessPermissions } from "@/hooks/use-permissions"

// This function is an ALLOWLIST: it ends in `return false`, so a Money nav item
// whose href is not named inside it is hidden from everyone — admins included.
//
// That is not a hypothetical. Cash Transfers, Owner Money and Loans (migrations
// 252-254) were added to the sidebar's Money group, which is wrapped in this
// gate, and were invisible on every screen until their hrefs were added here.
// These tests exist so the next Money page fails loudly in CI instead of
// silently not appearing.

const access = (over: Partial<FeatureAccessPermissions> = {}) =>
  ({
    canEnterSales: false,
    canEnterExpenses: false,
    canViewCashLedger: false,
    canViewFinancial: false,
    canViewCustomers: false,
    canViewReports: false,
    ...over,
  }) as unknown as FeatureAccessPermissions

const MONEY_PAGES = [
  "/cash-flow",
  "/cash",
  "/poultry-cash-accounts",
  "/poultry-cash-reconciliation",
  "/poultry-cash-transfers",
  "/poultry-owner-money",
  "/poultry-loans",
]

describe("isFinancialNavItemVisible", () => {
  it("shows every Money page to someone who can see the cash ledger", () => {
    const f = access({ canViewCashLedger: true })
    for (const href of MONEY_PAGES) {
      expect(isFinancialNavItemVisible(href, f, false), href).toBe(true)
    }
  })

  it("hides every Money page from someone who cannot", () => {
    // Staff are deny-by-default, which is exactly why these ride the existing
    // cash-ledger flag rather than a new permission nobody has been granted.
    const f = access()
    for (const href of MONEY_PAGES) {
      expect(isFinancialNavItemVisible(href, f, false), href).toBe(false)
    }
  })

  it("does NOT let admin alone reveal a Money page", () => {
    // The gate ignores isAdmin for these hrefs, so an admin without the cash
    // flag sees nothing here. Pinned because it surprises people.
    const f = access()
    expect(isFinancialNavItemVisible("/poultry-loans", f, true)).toBe(false)
  })

  it("hides an href it has never heard of", () => {
    // The trap: a new page added to a gated nav group but not to this list.
    const f = access({ canViewCashLedger: true, canViewFinancial: true })
    expect(isFinancialNavItemVisible("/poultry-something-new", f, true)).toBe(false)
  })

  it("still gates the older financial pages the way it always did", () => {
    expect(isFinancialNavItemVisible("/sales", access({ canEnterSales: true }), false)).toBe(true)
    expect(isFinancialNavItemVisible("/sales", access(), false)).toBe(false)
    expect(isFinancialNavItemVisible("/expenses", access({ canEnterExpenses: true }), false)).toBe(true)
    expect(isFinancialNavItemVisible("/customers", access({ canViewCustomers: true }), false)).toBe(true)
    expect(isFinancialNavItemVisible("/supplier-balances", access({ canEnterExpenses: true }), false)).toBe(true)
  })
})

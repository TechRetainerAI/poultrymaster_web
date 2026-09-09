import { describe, it, expect } from "vitest"
import {
  COST_TYPES,
  costTypeLabel,
  COST_TYPE_HELP,
  COST_TYPE_CLASS,
  isInProfit,
  plSectionLabel,
  assetStatusLabel,
  ASSET_STATUS_CLASS,
  legacyNote,
  recognitionSummaryLine,
  CASH_NOT_PROFIT_EXAMPLES,
  PROFIT_NOT_CASH_EXAMPLES,
} from "./financial-classification"

// These pin the frontend's vocabulary against the SQL one in
// database/checks/poultry-financial-cost-type.test.sql. The SQL file is the
// authority -- it tests the resolver that actually governs the report -- and
// this file exists so no screen can label a row differently from the way the
// P&L counted it.

describe("cost types", () => {
  it("knows exactly the five the database allows", () => {
    // A sixth value here would render a badge for a classification the CHECK
    // constraint on expense.financialcosttype would refuse to store.
    expect([...COST_TYPES]).toEqual([
      "OperatingExpense",
      "InventoryPurchase",
      "CapitalAsset",
      "NonCashExpense",
      "FinancingExpense",
    ])
  })

  it("has wording and a colour for every one of them", () => {
    for (const t of COST_TYPES) {
      expect(COST_TYPE_HELP[t], t).toBeTruthy()
      expect(COST_TYPE_CLASS[t], t).toBeTruthy()
      expect(costTypeLabel(t), t).not.toBe("")
    }
  })

  it("fails safe to Operating on an unknown or missing value", () => {
    // A legacy row arrives with no stated classification. Reading as "Operating"
    // is what it has always been treated as; reading as blank would look broken.
    expect(costTypeLabel(null)).toBe("Operating")
    expect(costTypeLabel(undefined)).toBe("Operating")
    expect(costTypeLabel("SOMETHING_NEW")).toBe("Operating")
  })

  it("explains every type in terms of BOTH profit and cash", () => {
    // The badges exist for one reason: money paid is not expense. Each sentence
    // has to say what happens to each, or it teaches nothing.
    for (const t of COST_TYPES) {
      const help = COST_TYPE_HELP[t].toLowerCase()
      expect(help, t).toMatch(/profit|cost/)
    }
    expect(COST_TYPE_HELP.CapitalAsset).toMatch(/depreciation/i)
    expect(COST_TYPE_HELP.InventoryPurchase).toMatch(/as the stock is used/i)
    expect(COST_TYPE_HELP.FinancingExpense).toMatch(/principal/i)
  })
})

describe("isInProfit", () => {
  it("is the guard against calling a capital purchase an expense", () => {
    // THE claim of the whole phase, in one function: a row can live in a table
    // called `expense` and not be one.
    expect(isInProfit("Excluded")).toBe(false)
    expect(isInProfit("DirectCost")).toBe(true)
    expect(isInProfit("OperatingExpense")).toBe(true)
    expect(isInProfit("OtherCost")).toBe(true)
  })

  it("treats an absent section as not classified rather than as in profit", () => {
    // An older API returns no section at all. Better to show nothing than to
    // assert a row IS in profit when the server never said so.
    expect(isInProfit(null)).toBe(false)
    expect(isInProfit(undefined)).toBe(false)
  })
})

describe("plSectionLabel", () => {
  it("names the four bands the report is built from", () => {
    expect(plSectionLabel("DirectCost")).toBe("Direct production cost")
    expect(plSectionLabel("OperatingExpense")).toBe("Operating expense")
    expect(plSectionLabel("OtherCost")).toBe("Depreciation & financing")
    expect(plSectionLabel("Excluded")).toBe("Not charged to profit")
  })
})

describe("asset status", () => {
  it("says what a status MEANS rather than repeating the enum", () => {
    // "Draft" tells an owner nothing. "Not in service" tells them why it is not
    // depreciating.
    expect(assetStatusLabel("Draft")).toBe("Not in service")
    expect(assetStatusLabel("Active")).toBe("In service")
    expect(assetStatusLabel("FullyDepreciated")).toBe("Fully depreciated")
  })

  it("has a colour for every status the database can store", () => {
    for (const s of ["Draft", "Active", "FullyDepreciated", "Disposed", "Reversed"]) {
      expect(ASSET_STATUS_CLASS[s], s).toBeTruthy()
    }
  })

  it("falls back to the raw value rather than to nothing", () => {
    expect(assetStatusLabel("Something")).toBe("Something")
    expect(assetStatusLabel(null)).toBe("—")
  })
})

describe("legacyNote", () => {
  it("says nothing when every record is classified", () => {
    // The old report warned about keyword mapping unconditionally. Saying it
    // when it is not true is how a warning gets ignored when it IS true.
    expect(legacyNote(0, 40)).toBeNull()
  })

  it("counts precisely rather than warning vaguely", () => {
    const note = legacyNote(3, 7)!
    expect(note).toContain("3 of 10")
    expect(note).toMatch(/placed by their category/i)
  })

  it("gets the singular right", () => {
    expect(legacyNote(1, 0)).toContain("1 of 1 cost record ")
  })
})

describe("recognitionSummaryLine", () => {
  it("states the farm setting in words", () => {
    expect(recognitionSummaryLine("EXPENSE_WHEN_CONSUMED", false)).toBe("Expense when consumed")
    expect(recognitionSummaryLine("EXPENSE_WHEN_PURCHASED", false)).toBe("Expense when purchased")
  })

  it("marks it as only the default when items override it", () => {
    // Otherwise the P&L would state a rule that some of its own numbers do not
    // follow.
    expect(recognitionSummaryLine("EXPENSE_WHEN_CONSUMED", true)).toBe("Expense when consumed (farm default)")
  })

  it("fails safe to today's behaviour on an unknown value", () => {
    expect(recognitionSummaryLine(null, false)).toBe("Expense when purchased")
  })
})

describe("the profit-versus-cash examples", () => {
  it("names the four cases a farm actually meets", () => {
    const all = CASH_NOT_PROFIT_EXAMPLES.join(" ").toLowerCase()
    expect(all).toMatch(/stock/)
    expect(all).toMatch(/building|machine/)
    expect(all).toMatch(/principal/)
    expect(all).toMatch(/owner/)
  })

  it("and the three that go the other way", () => {
    const all = PROFIT_NOT_CASH_EXAMPLES.join(" ").toLowerCase()
    expect(all).toMatch(/depreciation/)
    expect(all).toMatch(/bought earlier/)
    expect(all).toMatch(/not yet paid/)
  })
})

import { describe, it, expect } from "vitest"
import {
  EXPENSE_WHEN_PURCHASED,
  EXPENSE_WHEN_CONSUMED,
  costRecognitionGroup,
  farmDefaultFor,
  effectiveCostRecognition,
  methodShortLabel,
  recognitionTone,
  recognizedCostNote,
  deferredStatusTone,
  REMAINING_DEFERRED_TOOLTIP,
  NEWLY_RECOGNIZED_TOOLTIP,
  ALREADY_EXPENSED_TOOLTIP,
  NO_SECOND_PAYMENT_TOOLTIP,
  DEFERRED_EXCEPTION_TOOLTIP,
  type FarmCostRecognitionDefaults,
} from "./cost-recognition"

// These mirror, case for case, the claims in
// database/checks/poultry-cost-recognition-foundation.test.sql. The SQL file is
// the authority -- it tests the function that actually governs a purchase --
// and this file exists so the two forms cannot preview an answer the server
// would disagree with.
//
// If one of these ever fails while the SQL passes, the frontend is lying to the
// user about what saving will do.

const BOTH_PURCHASED: FarmCostRecognitionDefaults = {
  feed: EXPENSE_WHEN_PURCHASED,
  medication: EXPENSE_WHEN_PURCHASED,
}
const BOTH_DEFERRED: FarmCostRecognitionDefaults = {
  feed: EXPENSE_WHEN_CONSUMED,
  medication: EXPENSE_WHEN_CONSUMED,
}

describe("costRecognitionGroup", () => {
  it("groups the three feed categories together", () => {
    // Grain is Feed deliberately: the spec's own worked example is maize, and
    // farms file maize under either name. See migration 261's header.
    for (const c of ["FeedIngredient", "FinishedFeed", "Grain"]) {
      expect(costRecognitionGroup(c), c).toBe("Feed")
    }
  })

  it("groups medication on its own", () => {
    expect(costRecognitionGroup("Medication")).toBe("Medication")
  })

  it("leaves everything else unconfigured, Supplement included", () => {
    // Supplement is NOT medication. Guessing would move a real category into
    // deferred costing on a farm that only asked about drugs.
    for (const c of ["Supplement", "Packaging", "Equipment", "Other"]) {
      expect(costRecognitionGroup(c), c).toBe("Unconfigured")
    }
  })

  it("is case-insensitive and survives junk", () => {
    expect(costRecognitionGroup("feedingredient")).toBe("Feed")
    expect(costRecognitionGroup("  GRAIN  ")).toBe("Feed")
    expect(costRecognitionGroup(null)).toBe("Unconfigured")
    expect(costRecognitionGroup(undefined)).toBe("Unconfigured")
    expect(costRecognitionGroup("")).toBe("Unconfigured")
  })
})

describe("farmDefaultFor", () => {
  it("routes each group to its own setting, independently", () => {
    const feedOnly: FarmCostRecognitionDefaults = {
      feed: EXPENSE_WHEN_CONSUMED,
      medication: EXPENSE_WHEN_PURCHASED,
    }
    expect(farmDefaultFor("FeedIngredient", feedOnly)).toBe(EXPENSE_WHEN_CONSUMED)
    expect(farmDefaultFor("Grain", feedOnly)).toBe(EXPENSE_WHEN_CONSUMED)
    expect(farmDefaultFor("Medication", feedOnly)).toBe(EXPENSE_WHEN_PURCHASED)
  })

  it("keeps unconfigured categories out of reach of both settings", () => {
    // The important one. With BOTH settings deferred, a category nobody
    // configured must still expense on purchase -- otherwise turning the
    // feature on would silently defer a farm's packaging and equipment.
    for (const c of ["Packaging", "Supplement", "Equipment", "Other", "Invented"]) {
      expect(farmDefaultFor(c, BOTH_DEFERRED), c).toBe(EXPENSE_WHEN_PURCHASED)
    }
  })
})

describe("effectiveCostRecognition", () => {
  it("falls back to today's behaviour when nothing is configured", () => {
    const r = effectiveCostRecognition(null, "FeedIngredient", BOTH_PURCHASED)
    expect(r.method).toBe(EXPENSE_WHEN_PURCHASED)
    expect(r.source).toBe("FarmDefault")
  })

  it("follows the farm default when the item has no override", () => {
    const r = effectiveCostRecognition(null, "FeedIngredient", BOTH_DEFERRED)
    expect(r.method).toBe(EXPENSE_WHEN_CONSUMED)
    expect(r.source).toBe("FarmDefault")
  })

  it("lets an override win in both directions", () => {
    const optOut = effectiveCostRecognition(EXPENSE_WHEN_PURCHASED, "FeedIngredient", BOTH_DEFERRED)
    expect(optOut.method).toBe(EXPENSE_WHEN_PURCHASED)
    expect(optOut.source).toBe("ItemOverride")

    // And an unconfigured category can be deferred one item at a time, which is
    // the escape hatch for exceptions without opening the category up.
    const optIn = effectiveCostRecognition(EXPENSE_WHEN_CONSUMED, "Packaging", BOTH_PURCHASED)
    expect(optIn.method).toBe(EXPENSE_WHEN_CONSUMED)
    expect(optIn.source).toBe("ItemOverride")
  })

  it("still reports the farm default while overridden", () => {
    // This is what lets the form say "you are overriding X" instead of making
    // the user go and look the setting up.
    const r = effectiveCostRecognition(EXPENSE_WHEN_PURCHASED, "FeedIngredient", BOTH_DEFERRED)
    expect(r.farmDefault).toBe(EXPENSE_WHEN_CONSUMED)
  })

  it("returns to the farm default when the override is cleared", () => {
    expect(effectiveCostRecognition(null, "FeedIngredient", BOTH_DEFERRED).method)
      .toBe(EXPENSE_WHEN_CONSUMED)
  })

  it("re-reads the new category for an inherited item, but not an overridden one", () => {
    // Inherited: moving Grain -> Packaging drops it out of the feed setting.
    expect(effectiveCostRecognition(null, "Grain", BOTH_DEFERRED).method).toBe(EXPENSE_WHEN_CONSUMED)
    expect(effectiveCostRecognition(null, "Packaging", BOTH_DEFERRED).method).toBe(EXPENSE_WHEN_PURCHASED)

    // Overridden: the user chose a method, not a category's method, so the move
    // changes nothing.
    expect(effectiveCostRecognition(EXPENSE_WHEN_CONSUMED, "Medication", BOTH_PURCHASED).method)
      .toBe(EXPENSE_WHEN_CONSUMED)
    expect(effectiveCostRecognition(EXPENSE_WHEN_CONSUMED, "FeedIngredient", BOTH_PURCHASED).method)
      .toBe(EXPENSE_WHEN_CONSUMED)
  })

  it("never invents a third answer", () => {
    const cases: (string | null)[] = ["FeedIngredient", "Medication", "Packaging", "", null]
    for (const c of cases) {
      for (const o of [null, EXPENSE_WHEN_PURCHASED, EXPENSE_WHEN_CONSUMED] as const) {
        const r = effectiveCostRecognition(o, c, BOTH_DEFERRED)
        expect([EXPENSE_WHEN_PURCHASED, EXPENSE_WHEN_CONSUMED]).toContain(r.method)
      }
    }
  })
})

describe("methodShortLabel", () => {
  it("says what the table cell needs and fails safe", () => {
    expect(methodShortLabel(EXPENSE_WHEN_CONSUMED)).toBe("On use")
    expect(methodShortLabel(EXPENSE_WHEN_PURCHASED)).toBe("On purchase")
    // An unknown value reads as today's behaviour rather than as blank or as
    // the deferred one -- same failing-safe rule the SQL predicates use.
    expect(methodShortLabel(null)).toBe("On purchase")
    expect(methodShortLabel("WHENEVER")).toBe("On purchase")
  })
})

// ---------------------------------------------------------------------------
// The read side (migrations 264-268). These mirror the claims in
// database/checks/poultry-cost-recognition-reads.test.sql sections A, C and G.
// ---------------------------------------------------------------------------

describe("recognitionTone", () => {
  it("reads the number, not the server's wording", () => {
    // The database owns the status sentences and is free to reword them; the
    // palette must not break when it does.
    expect(recognitionTone(8000)).toBe("deferred")
    expect(recognitionTone(0)).toBe("expensed")
    expect(recognitionTone(null)).toBe("expensed")
    expect(recognitionTone(undefined)).toBe("expensed")
  })

  it("stays out of the way for rows where recognition does not apply", () => {
    expect(recognitionTone(1000, { reversed: true })).toBe("muted")
    expect(recognitionTone(0, { notApplicable: true })).toBe("muted")
  })
})

describe("recognizedCostNote", () => {
  it("says the one thing a zero must not be read as", () => {
    // Section C of the SQL check: 800 cedis of premix, expensed when it was
    // bought, recognises 0 here. "Free feed" is the misreading this prevents.
    expect(recognizedCostNote(0, 800)).toContain("Already charged")
    expect(recognizedCostNote(0, 800)).not.toContain("no cost")
  })

  it("credits a deferred usage to this moment", () => {
    expect(recognizedCostNote(2000, 2000)).toContain("when this usage was recorded")
  })

  it("distinguishes nothing recognised from nothing drawn", () => {
    expect(recognizedCostNote(0, 0)).toContain("No cost layers")
  })
})

// ---------------------------------------------------------------------------
// Migration 288: the Deferred Inventory Costs page's own vocabulary.
//
// These mirror the status strings produced by fnpoultrydeferredpurchase_rows
// and checked in database/checks/poultry-deferred-inventory-cost-reads.test.sql.
// The SQL is the authority for WHICH status a purchase gets; this file only
// guards how the page colours and explains it.
// ---------------------------------------------------------------------------
describe("deferredStatusTone", () => {
  it("treats cost still waiting as deferred", () => {
    expect(deferredStatusTone("Not yet expensed")).toBe("deferred")
    expect(deferredStatusTone("Partly expensed")).toBe("deferred")
  })

  it("treats settled cost as expensed, however it got there", () => {
    // Two different histories, one meaning: nothing more will hit the P&L.
    expect(deferredStatusTone("Fully expensed")).toBe("expensed")
    expect(deferredStatusTone("Expensed at purchase")).toBe("expensed")
  })

  it("does NOT dress an Exception as either", () => {
    // The one that matters: an Exception must never borrow the calm green of a
    // settled purchase or the ordinary amber of a waiting one. The page paints
    // it red from the status string itself.
    expect(deferredStatusTone("Exception")).toBe("muted")
  })

  it("falls back to muted on an unknown or missing status", () => {
    // A server that grows a new status must not crash the page or, worse,
    // colour the unknown one as though it were settled.
    expect(deferredStatusTone(null)).toBe("muted")
    expect(deferredStatusTone(undefined)).toBe("muted")
    expect(deferredStatusTone("Something New")).toBe("muted")
  })
})

describe("deferred-cost tooltips", () => {
  it("never uses accountant vocabulary", () => {
    // Section 29 of the brief: no "COGS", no "deferred recognition allocation
    // ledger". These are read by farm owners.
    const all = [
      REMAINING_DEFERRED_TOOLTIP, NEWLY_RECOGNIZED_TOOLTIP,
      ALREADY_EXPENSED_TOOLTIP, NO_SECOND_PAYMENT_TOOLTIP,
      DEFERRED_EXCEPTION_TOOLTIP,
    ]
    for (const t of all) {
      expect(t).not.toMatch(/COGS|amortis|accrual|ledger|allocation/i)
      expect(t.length).toBeGreaterThan(20)
    }
  })

  it("says plainly that recognising a cost moves no money", () => {
    // The single most expensive misreading on this page: an owner seeing a new
    // expense and believing they have been charged twice.
    expect(NO_SECOND_PAYMENT_TOOLTIP).toMatch(/moves no money|no money/i)
    expect(NO_SECOND_PAYMENT_TOOLTIP).toMatch(/bought/i)
  })

  it("warns that neither figure is safe on an Exception", () => {
    expect(DEFERRED_EXCEPTION_TOOLTIP).toMatch(/do not agree|until it is checked/i)
  })
})

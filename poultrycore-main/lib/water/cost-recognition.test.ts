import { describe, it, expect } from "vitest"
import {
  EXPENSE_WHEN_PURCHASED,
  EXPENSE_WHEN_CONSUMED,
  costRecognitionGroup,
  farmDefaultFor,
  effectiveCostRecognition,
  methodShortLabel,
  methodLabel,
  recognitionTone,
  GROUP_CATEGORIES,
  type FarmCostRecognitionDefaults,
} from "./cost-recognition"

// These mirror, case for case, the claims in
// database/checks/water-cost-recognition-foundation.test.sql. The SQL file is
// the authority -- it tests the function that actually governs a purchase -- and
// this file exists so the two forms cannot preview an answer the server would
// disagree with.
//
// If one of these ever fails while the SQL passes, the frontend is lying to the
// user about what saving will do.

const BOTH_PURCHASED: FarmCostRecognitionDefaults = {
  packaging: EXPENSE_WHEN_PURCHASED,
  treatment: EXPENSE_WHEN_PURCHASED,
}
const BOTH_DEFERRED: FarmCostRecognitionDefaults = {
  packaging: EXPENSE_WHEN_CONSUMED,
  treatment: EXPENSE_WHEN_CONSUMED,
}

describe("costRecognitionGroup", () => {
  it("groups the three packaging categories together", () => {
    for (const c of ["PackagingRoll", "SachetFilm", "OuterBag"]) {
      expect(costRecognitionGroup(c), c).toBe("Packaging")
    }
  })

  it("puts Chemical, and only Chemical, in Treatment", () => {
    expect(costRecognitionGroup("Chemical")).toBe("Treatment")
    // Filter and UVLamp are deliberately NOT Treatment: they are periodic
    // replacements, and with the asset register in the same workstream several
    // companies will file a UV lamp as capital or maintenance. Sweeping them in
    // because they sit near Chemical in a dropdown would move real money out of
    // a company's P&L that nobody asked to move. See migration 274's header.
    expect(costRecognitionGroup("Filter")).toBe("Unconfigured")
    expect(costRecognitionGroup("UVLamp")).toBe("Unconfigured")
  })

  it("leaves the operational categories unconfigured", () => {
    for (const c of ["SparePart", "Fuel", "CleaningSupply", "Other"]) {
      expect(costRecognitionGroup(c), c).toBe("Unconfigured")
    }
  })

  it("is case- and whitespace-insensitive, like the SQL", () => {
    expect(costRecognitionGroup("  sachetfilm  ")).toBe("Packaging")
    expect(costRecognitionGroup("CHEMICAL")).toBe("Treatment")
  })

  it("fails safe on a category nobody has invented yet", () => {
    // The one that matters: an unknown category must never be deferrable by a
    // company setting.
    expect(costRecognitionGroup("ZZ Invented")).toBe("Unconfigured")
    expect(costRecognitionGroup(null)).toBe("Unconfigured")
    expect(costRecognitionGroup(undefined)).toBe("Unconfigured")
    expect(costRecognitionGroup("")).toBe("Unconfigured")
  })

  it("covers every category the group table lists, and nothing twice", () => {
    // Guards against a category being added to GROUP_CATEGORIES for display
    // without the resolver agreeing -- which would show a company a setting that
    // does not govern what it says it governs.
    for (const [group, cats] of Object.entries(GROUP_CATEGORIES)) {
      for (const c of cats) expect(costRecognitionGroup(c), c).toBe(group)
    }
    const all = Object.values(GROUP_CATEGORIES).flat()
    expect(new Set(all).size).toBe(all.length)
  })
})

describe("farmDefaultFor", () => {
  it("is expense-when-purchased for everything when nothing is configured", () => {
    for (const c of ["PackagingRoll", "Chemical", "Fuel", "ZZ Invented"]) {
      expect(farmDefaultFor(c, BOTH_PURCHASED), c).toBe(EXPENSE_WHEN_PURCHASED)
    }
  })

  it("keeps the two settings independent", () => {
    const packagingOnly: FarmCostRecognitionDefaults = {
      packaging: EXPENSE_WHEN_CONSUMED,
      treatment: EXPENSE_WHEN_PURCHASED,
    }
    expect(farmDefaultFor("SachetFilm", packagingOnly)).toBe(EXPENSE_WHEN_CONSUMED)
    expect(farmDefaultFor("Chemical", packagingOnly)).toBe(EXPENSE_WHEN_PURCHASED)

    const treatmentOnly: FarmCostRecognitionDefaults = {
      packaging: EXPENSE_WHEN_PURCHASED,
      treatment: EXPENSE_WHEN_CONSUMED,
    }
    expect(farmDefaultFor("SachetFilm", treatmentOnly)).toBe(EXPENSE_WHEN_PURCHASED)
    expect(farmDefaultFor("Chemical", treatmentOnly)).toBe(EXPENSE_WHEN_CONSUMED)
  })

  it("never lets a company setting reach an unconfigured category", () => {
    // Both settings deferred: if a category leaked, this is where it shows.
    for (const c of ["Filter", "UVLamp", "SparePart", "Fuel", "CleaningSupply", "Other", "ZZ Invented"]) {
      expect(farmDefaultFor(c, BOTH_DEFERRED), c).toBe(EXPENSE_WHEN_PURCHASED)
    }
  })
})

describe("effectiveCostRecognition", () => {
  it("uses the company default when there is no override", () => {
    const r = effectiveCostRecognition(null, "SachetFilm", BOTH_DEFERRED)
    expect(r.method).toBe(EXPENSE_WHEN_CONSUMED)
    expect(r.source).toBe("FarmDefault")
  })

  it("lets an override win in both directions", () => {
    // Opting a single item OUT of a deferred company default...
    const out = effectiveCostRecognition(EXPENSE_WHEN_PURCHASED, "SachetFilm", BOTH_DEFERRED)
    expect(out.method).toBe(EXPENSE_WHEN_PURCHASED)
    expect(out.source).toBe("ItemOverride")

    // ...and deferring a single item in an unconfigured category, which is the
    // only way those categories can ever be deferred.
    const into = effectiveCostRecognition(EXPENSE_WHEN_CONSUMED, "Fuel", BOTH_PURCHASED)
    expect(into.method).toBe(EXPENSE_WHEN_CONSUMED)
    expect(into.source).toBe("ItemOverride")
  })

  it("still reports the company default it is overriding", () => {
    // So the form can say "you are overriding X" without a second round trip.
    const r = effectiveCostRecognition(EXPENSE_WHEN_PURCHASED, "SachetFilm", BOTH_DEFERRED)
    expect(r.farmDefault).toBe(EXPENSE_WHEN_CONSUMED)
  })

  it("treats undefined the same as null -- follow the default", () => {
    expect(effectiveCostRecognition(undefined, "Chemical", BOTH_DEFERRED).source).toBe("FarmDefault")
  })
})

describe("wording", () => {
  it("says on purchase for anything that is not the deferred method", () => {
    // Fails SAFE, exactly as fnwatercostrecognition_expenseatpurchase does: an
    // unrecognised value must never read as deferred.
    expect(methodShortLabel(EXPENSE_WHEN_PURCHASED)).toBe("On purchase")
    expect(methodShortLabel(null)).toBe("On purchase")
    expect(methodShortLabel("WHENEVER")).toBe("On purchase")
    expect(methodShortLabel(EXPENSE_WHEN_CONSUMED)).toBe("On use")
  })

  it("uses the same fail-safe rule in the long label", () => {
    expect(methodLabel("WHENEVER")).toBe("Expense when purchased")
    expect(methodLabel(EXPENSE_WHEN_CONSUMED)).toBe("Expense when consumed")
  })
})

describe("recognitionTone", () => {
  it("reads the number, not the wording", () => {
    expect(recognitionTone(500)).toBe("deferred")
    expect(recognitionTone(0)).toBe("expensed")
    expect(recognitionTone(null)).toBe("expensed")
  })

  it("mutes a reversed or inapplicable row whatever the number says", () => {
    expect(recognitionTone(500, { reversed: true })).toBe("muted")
    expect(recognitionTone(500, { notApplicable: true })).toBe("muted")
  })
})

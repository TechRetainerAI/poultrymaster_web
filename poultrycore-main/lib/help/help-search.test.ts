import { describe, expect, it } from "vitest"
import { highlightRuns, meaningfulWords, prepareHelpIndex, searchHelp } from "./help-search"
import type { HelpEntry } from "./help-types"

const entries: HelpEntry[] = [
  { id: "reverse-sale", kind: "faq", category: "Sales", title: "How do I reverse a sale?",
    body: "Open the sale and choose Reverse. Pick a reason.", keywords: ["undo sale", "cancel sale"] },
  { id: "cash-vs-profit", kind: "fix", category: "Money", title: "My cash doesn't match my profit",
    body: "Cash Flow counts money when it moves; Profit & Loss counts it when it is earned.", keywords: ["difference"] },
  { id: "eggs-per-crate", kind: "term", category: "Eggs", title: "Eggs per crate",
    body: "How many eggs make one crate on this farm. Set in Egg Sorting Settings." },
]
const index = prepareHelpIndex(entries)

describe("meaningfulWords", () => {
  it("drops question words", () => {
    expect(meaningfulWords("How do I reverse a sale?")).toEqual(["reverse", "sale"])
  })
  it("keeps something when the query is only question words", () => {
    expect(meaningfulWords("how do i")).toEqual(["how", "do", "i"])
  })
})

describe("searchHelp", () => {
  it("finds a question asked in other words", () => {
    expect(searchHelp("cancel a sale", index)[0].entry.id).toBe("reverse-sale")
    expect(searchHelp("why doesn't my cash match profit", index)[0].entry.id).toBe("cash-vs-profit")
  })
  it("tolerates typos", () => {
    expect(searchHelp("revers sael", index)[0].entry.id).toBe("reverse-sale")
  })
  it("matches the body when the title does not", () => {
    expect(searchHelp("crate settings", index)[0].entry.id).toBe("eggs-per-crate")
  })
  it("returns nothing for unrelated words", () => {
    expect(searchHelp("vaccination schedule", index)).toEqual([])
  })
})

describe("highlightRuns", () => {
  it("marks word starts only", () => {
    const runs = highlightRuns("Sales and wholesale", ["sale"])
    expect(runs.filter((r) => r.hit).map((r) => r.text)).toEqual(["Sales"])
  })
})

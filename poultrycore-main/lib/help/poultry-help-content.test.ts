import { existsSync } from "node:fs"
import { join } from "node:path"
import { describe, expect, it } from "vitest"
import { FEATURE_GUIDES, HELP_ENTRIES } from "./poultry-help-content"
import { prepareHelpIndex, searchHelp } from "./help-search"

// A help link to a page that no longer exists is a dead end for someone who is
// already stuck, so every link must resolve to an app route.
const routeExists = (href: string) => existsSync(join(process.cwd(), "app", href.split("?")[0], "page.tsx"))

describe("poultry help content", () => {
  it("has unique ids (they are shared #anchors)", () => {
    const ids = HELP_ENTRIES.map((e) => e.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it("links only to pages that exist", () => {
    const hrefs = [...HELP_ENTRIES.flatMap((e) => (e.links ?? []).map((l) => l.href)), ...FEATURE_GUIDES.map((g) => g.path)]
    expect(hrefs.filter((h) => !routeExists(h))).toEqual([])
  })

  it("answers the suggested questions", () => {
    const index = prepareHelpIndex(HELP_ENTRIES)
    const top = (q: string) => searchHelp(q, index)[0]?.entry.id
    expect(top("who owes me")).toBe("balance-wrong")
    expect(top("cash doesn't match profit")).toBe("cash-vs-profit")
    expect(top("reverse a sale")).toBe("reverse-sale")
    expect(["eggs-per-crate", "term-eggs-per-crate"]).toContain(top("eggs per crate"))
    expect(top("close the day")).toBe("daily-closing")
    expect(top("can't see a page")).toBe("cant-see-page")
    expect(top("change my pasword")).toBe("password")
  })
})

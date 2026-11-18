import { existsSync } from "node:fs"
import path from "node:path"
import { describe, expect, it } from "vitest"
import { HELP_ENTRIES } from "./poultry-help-content"
import { HELP_SHOTS } from "./help-shots"
// Plain JS config shared with the Playwright capture script.
import { SHOTS } from "../../scripts/help-screenshots/shots.mjs"

const ROOT = path.resolve(__dirname, "..", "..")
const ids = new Set(HELP_ENTRIES.map((e) => e.id))
const shotList = SHOTS as Record<string, Array<{ path?: string; menu?: { bar: string; href: string }; area?: string; caption: string }>>

describe("help screenshots", () => {
  it("only targets help entries that exist", () => {
    expect(Object.keys(shotList).filter((id) => !ids.has(id))).toEqual([])
    expect(Object.keys(HELP_SHOTS).filter((id) => !ids.has(id))).toEqual([])
  })

  it("starts every walkthrough on a page, and every page is a real route", () => {
    for (const [id, shots] of Object.entries(shotList)) {
      expect(shots[0].path, `${id} must open a page first`).toBeTruthy()
      for (const s of shots) {
        expect(s.caption.trim().length, `${id} has an empty caption`).toBeGreaterThan(0)
        for (const href of [s.path, s.menu?.href]) {
          if (!href) continue
          const route = href.split("?")[0].replace(/^\//, "")
          expect(existsSync(path.join(ROOT, "app", route, "page.tsx")), `${id}: no app/${route}/page.tsx`).toBe(true)
        }
      }
    }
  })

  it("has every captured picture on disk", () => {
    for (const shots of Object.values(HELP_SHOTS)) {
      for (const s of shots) {
        expect(existsSync(path.join(ROOT, "public", s.src)), s.src).toBe(true)
        expect(s.width).toBeGreaterThan(0)
      }
    }
  })
})

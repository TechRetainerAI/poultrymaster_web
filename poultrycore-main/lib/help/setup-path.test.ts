import { describe, expect, it } from "vitest"
import { SETUP_STEPS, setupProgress, stepStates } from "./setup-path"
import { HELP_ENTRIES } from "./poultry-help-content"

describe("setup path", () => {
  it("has unique ids, and every guide it names is a Help entry", () => {
    const ids = SETUP_STEPS.map((s) => s.id)
    expect(new Set(ids).size).toBe(ids.length)
    const entries = new Set(HELP_ENTRIES.map((e) => e.id))
    for (const s of SETUP_STEPS) if (s.guide) expect(entries.has(s.guide), s.guide).toBe(true)
  })

  it("every step is either counted from the data or ticked by hand, never both", () => {
    for (const s of SETUP_STEPS) expect(!!s.count !== !!s.manual, s.id).toBe(true)
  })

  it("puts what a step needs before it", () => {
    const at = (id: string) => SETUP_STEPS.findIndex((s) => s.id === id)
    expect(at("houses")).toBeLessThan(at("flocks"))
    expect(at("suppliers")).toBeLessThan(at("batches"))
    expect(at("batches")).toBeLessThan(at("flocks"))
    expect(at("flocks")).toBeLessThan(at("production"))
    expect(at("customers")).toBeLessThan(at("sales"))
    expect(at("cash-accounts")).toBeLessThan(at("batches"))
  })

  it("ticks counted steps from the data and manual ones from the ticks", () => {
    const s = stepStates(SETUP_STEPS, { houses: 2, flocks: 0, sales: undefined }, new Set(["company"]))
    expect(s.houses).toBe("done")
    expect(s.flocks).toBe("todo")
    expect(s.sales).toBe("unknown")
    expect(s.company).toBe("done")
    expect(s["egg-settings"]).toBe("todo")
  })

  it("counts only required steps, and points at the first one not done", () => {
    const none = setupProgress(SETUP_STEPS, stepStates(SETUP_STEPS, {}, new Set()))
    expect(none.done).toBe(0)
    expect(none.next).toBe("company")
    expect(none.total).toBe(SETUP_STEPS.filter((s) => !s.optional).length)

    const all = Object.fromEntries(SETUP_STEPS.map((s) => [s.id, s.optional ? "todo" : "done"])) as Record<string, "done" | "todo">
    const p = setupProgress(SETUP_STEPS, all)
    expect(p.complete).toBe(true)
    expect(p.next).toBeNull()
  })
})

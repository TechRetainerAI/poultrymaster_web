import { describe, it, expect } from "vitest"
import { explainHttpError, explainLoadFailure } from "./http-error"

// The rule this whole module exists to enforce: a raw payload is never an error
// message. These lock it in both directions -- the body must not leak, and what
// replaces it must actually say something.

describe("explainHttpError", () => {
  it("never returns the body when it is JSON with nothing usable", () => {
    const body = JSON.stringify({ success: false, sqlState: "23505", trace: "…" })
    const out = explainHttpError("POST", "/Poultry/products", 500, body)
    expect(out).not.toContain("sqlState")
    expect(out).not.toContain("{")
  })

  it("prefers a real message field when the backend supplies one", () => {
    const body = JSON.stringify({ message: "That supplier is already in use." })
    expect(explainHttpError("POST", "/x", 400, body)).toBe("That supplier is already in use.")
  })

  it("treats an HTML error page as noise", () => {
    const out = explainHttpError("GET", "/x", 500, "<!DOCTYPE html><html>…")
    expect(out).not.toContain("<")
  })
})

describe("explainLoadFailure", () => {
  // The case that prompted it. The server is telling the truth and the sentence
  // is still useless to the person reading it.
  const missingFn =
    "function sppoultrydeferredpurchase_summary(p_farmid => text, p_scope => text) does not exist"

  it("turns a missing database function into something actionable", () => {
    const { headline, hint } = explainLoadFailure(missingFn, "deferred inventory costs")
    expect(headline).toMatch(/aren't switched on yet/i)
    // The three things it must not do: leak the function name, leak the
    // signature, or sound like the company's records are damaged.
    expect(headline).not.toMatch(/sppoultry|=>|function/i)
    expect(hint).not.toMatch(/sppoultry|=>/)
    expect(hint).toMatch(/nothing is wrong with your data/i)
  })

  it("capitalises the subject it is handed without mangling it", () => {
    expect(explainLoadFailure(missingFn, "deferred inventory costs").headline)
      .toMatch(/^Deferred inventory costs/)
  })

  it("separates a permission problem from a broken one", () => {
    // These lead to different actions -- ask an admin vs. call support -- so
    // collapsing them into one message costs the reader a wasted step.
    const { headline, hint } = explainLoadFailure("GET /x failed (403).")
    expect(headline).toMatch(/permission/i)
    expect(hint).toMatch(/administrator/i)
  })

  it("separates an unreachable server, and promises nothing was changed", () => {
    const { headline, hint } = explainLoadFailure("TypeError: Failed to fetch")
    expect(headline).toMatch(/could not reach/i)
    expect(hint).toMatch(/nothing has been changed/i)
  })

  it("still says something useful about an error it has never seen", () => {
    const { headline, hint } = explainLoadFailure("kaboom", "deferred inventory costs")
    expect(headline).toBe("Could not load deferred inventory costs.")
    expect(hint).toBeTruthy()
  })

  it("survives an empty or missing message rather than throwing", () => {
    // A rejected promise with no message reaches this as "" — the fallback has
    // to hold, because this runs on the path where everything else failed.
    expect(() => explainLoadFailure("")).not.toThrow()
    expect(explainLoadFailure("").headline).toBe("Could not load this page.")
  })
})

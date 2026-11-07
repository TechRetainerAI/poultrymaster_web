import { describe, expect, it } from "vitest"
import {
  resolveSetupLocation, sectionOfTab, setupHref, SETUP_SECTIONS, type SetupTabKey,
} from "@/lib/nav/poultry-setup-tabs"

const all = () => true
const none = () => false
const except = (...blocked: SetupTabKey[]) => (k: SetupTabKey) => !blocked.includes(k)

describe("resolveSetupLocation", () => {
  it("defaults the bare route to Production's first tab", () => {
    expect(resolveSetupLocation({}, all)).toEqual({ kind: "ok", section: "production", tab: "company-settings" })
  })

  it("opens a section's first tab from ?section= alone", () => {
    expect(resolveSetupLocation({ section: "business" }, all)).toEqual({ kind: "ok", section: "business", tab: "customers" })
  })

  it("honours an explicit deep link", () => {
    expect(resolveSetupLocation({ section: "production", tab: "egg-settings" }, all))
      .toEqual({ kind: "ok", section: "production", tab: "egg-settings" })
  })

  it("takes the tab's own section when ?section= disagrees", () => {
    expect(resolveSetupLocation({ section: "production", tab: "customers" }, all))
      .toEqual({ kind: "ok", section: "business", tab: "customers" })
  })

  it("falls back safely from an unknown tab", () => {
    expect(resolveSetupLocation({ section: "business", tab: "nonsense" }, all))
      .toEqual({ kind: "ok", section: "business", tab: "customers" })
  })

  it("never opens a tab the user may not see", () => {
    expect(resolveSetupLocation({ tab: "financial-settings" }, except("financial-settings", "company-settings")))
      .toEqual({ kind: "ok", section: "production", tab: "houses" })
  })

  it("skips to Business when no Production tab is allowed", () => {
    const businessOnly = (k: SetupTabKey) => sectionOfTab(k) === "business"
    expect(resolveSetupLocation({ section: "production" }, businessOnly))
      .toEqual({ kind: "ok", section: "business", tab: "customers" })
  })

  it("reports no access when nothing is allowed", () => {
    expect(resolveSetupLocation({ tab: "houses" }, none)).toEqual({ kind: "none" })
  })

  it("maps the old ?step= links", () => {
    expect(resolveSetupLocation({ step: "company" }, all)).toEqual({ kind: "ok", section: "production", tab: "company-settings" })
    expect(resolveSetupLocation({ step: "flocks" }, all)).toEqual({ kind: "ok", section: "production", tab: "flock-groups" })
    expect(resolveSetupLocation({ step: "raw-materials" }, all)).toEqual({ kind: "ok", section: "production", tab: "inventory" })
    expect(resolveSetupLocation({ step: "vehicles" }, all)).toEqual({ kind: "ok", section: "business", tab: "vehicles" })
    expect(resolveSetupLocation({ step: "employees" }, all)).toEqual({ kind: "redirect", href: "/employees" })
  })

  it("prefers ?tab= over a legacy ?step=", () => {
    expect(resolveSetupLocation({ tab: "products", step: "customers" }, all))
      .toEqual({ kind: "ok", section: "production", tab: "products" })
  })

  it("sends the old profile tabs to Company settings", () => {
    for (const tab of ["farm-profile", "company-profile"])
      expect(resolveSetupLocation({ section: "business", tab }, all)).toEqual({ kind: "ok", section: "production", tab: "company-settings" })
  })

  it("opens Delivery on Drivers", () => {
    expect(resolveSetupLocation({ tab: "delivery" }, all)).toEqual({ kind: "ok", section: "business", tab: "drivers" })
  })
})

describe("setup tabs", () => {
  it("builds the canonical URL", () => {
    expect(setupHref("production", "flock-groups")).toBe("/poultry-setup?section=production&tab=flock-groups")
  })

  it("gives every tab one section and a description", () => {
    const keys = Object.values(SETUP_SECTIONS).flatMap((s) => s.tabs.map((t) => t.key))
    expect(new Set(keys).size).toBe(keys.length)
    for (const s of Object.values(SETUP_SECTIONS)) for (const t of s.tabs) expect(t.description.length).toBeGreaterThan(10)
  })
})

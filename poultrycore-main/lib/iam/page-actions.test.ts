import { describe, expect, it } from "vitest"
import { keyForAction } from "@/hooks/use-page-actions"

const page = (actions?: string[]) => ({ module: "generic" as const, resource: "purchases", actions: actions as any })

describe("keyForAction mirrors the API's FallbackActions", () => {
  it("uses the page's own key when it has one", () => {
    expect(keyForAction(page(["create", "edit", "approve", "reverse"]), "reverse")).toBe("generic.purchases.reverse")
  })
  it("reverse falls back to approve, then delete, then edit", () => {
    expect(keyForAction(page(["create", "edit", "approve"]), "reverse")).toBe("generic.purchases.approve")
    expect(keyForAction(page(["create", "edit", "delete"]), "reverse")).toBe("generic.purchases.delete")
    expect(keyForAction(page(["edit"]), "reverse")).toBe("generic.purchases.edit")
  })
  it("never falls back to a weaker action than the API would", () => {
    expect(keyForAction(page(["export"]), "approve")).toBeNull()
    expect(keyForAction(page(), "create")).toBeNull()
  })
  it("export falls back to view", () => {
    expect(keyForAction(page(), "export")).toBe("generic.purchases.view")
  })
})

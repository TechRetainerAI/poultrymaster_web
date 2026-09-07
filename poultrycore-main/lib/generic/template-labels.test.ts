import { describe, it, expect } from "vitest"
import {
  templateLabels,
  hasSubscriptions,
  DEFAULT_LABELS,
  type IndustryTemplate,
} from "./template-labels"

const ALL: IndustryTemplate[] = [
  "SaaS",
  "Gym",
  "School",
  "CleaningService",
  "SecurityService",
  "Agency",
  "RetainerBusiness",
  "MembershipBusiness",
  "Retail",
  "Other",
]

describe("templateLabels", () => {
  it("speaks each industry's own language", () => {
    expect(templateLabels("Gym").customer).toBe("Member")
    expect(templateLabels("School").customer).toBe("Student")
    expect(templateLabels("CleaningService").customer).toBe("Client")
    expect(templateLabels("SaaS").customer).toBe("Customer")
  })

  it("renames the documents where the industry renames them", () => {
    // A school does not send invoices, it sends fee notes.
    expect(templateLabels("School").invoice).toBe("Fee Note")
    expect(templateLabels("School").customerBalance).toBe("Outstanding Fees")
    expect(templateLabels("Gym").customerBalance).toBe("Member Balances")
    // Everyone else keeps the plain word.
    expect(templateLabels("SaaS").invoice).toBe("Invoice")
  })

  it("pluralises without producing 'Service Contracts s'", () => {
    expect(templateLabels("CleaningService").subscriptionPlural).toBe("Service Contracts")
    expect(templateLabels("School").invoicePlural).toBe("Fee Notes")
    expect(templateLabels("Gym").customerPlural).toBe("Members")
  })

  it("falls back to neutral labels for a company with no template", () => {
    // Every Generic company that predates templates lands here, and must keep
    // reading exactly as it does today.
    expect(templateLabels(null)).toEqual(DEFAULT_LABELS)
    expect(templateLabels(undefined)).toEqual(DEFAULT_LABELS)
    expect(templateLabels("")).toEqual(DEFAULT_LABELS)
    expect(DEFAULT_LABELS.customer).toBe("Customer")
  })

  it("falls back rather than throwing on a template it does not know", () => {
    // A template added in SQL before it is added here must not white-screen a page.
    expect(templateLabels("Bakery")).toEqual(DEFAULT_LABELS)
  })

  it("fills in every label for every industry", () => {
    for (const t of ALL) {
      const l = templateLabels(t)
      for (const [key, value] of Object.entries(l)) {
        expect(value, `${t}.${key}`).toBeTruthy()
        expect(String(value).trim(), `${t}.${key}`).toBe(value)
      }
    }
  })
})

describe("hasSubscriptions", () => {
  it("is true only for the subscription bundle", () => {
    expect(hasSubscriptions("SubscriptionServiceBusiness")).toBe(true)
    expect(hasSubscriptions("RetailBusiness")).toBe(false)
    expect(hasSubscriptions("GeneralBusiness")).toBe(false)
  })

  it("is false for a company with no template at all", () => {
    expect(hasSubscriptions(null)).toBe(false)
    expect(hasSubscriptions(undefined)).toBe(false)
  })
})

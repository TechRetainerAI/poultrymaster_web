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
    // Section 4 of the spec, verbatim: a school sends fee bills, a gym sends
    // membership bills, a cleaning firm sends service bills.
    expect(templateLabels("School").invoice).toBe("Fee Bill")
    expect(templateLabels("Gym").invoice).toBe("Membership Bill")
    expect(templateLabels("CleaningService").invoice).toBe("Service Bill")
    expect(templateLabels("SecurityService").invoice).toBe("Service Bill")
    expect(templateLabels("MembershipBusiness").invoice).toBe("Bill")
    expect(templateLabels("School").customerBalance).toBe("Outstanding Fees")
    expect(templateLabels("Gym").customerBalance).toBe("Member Balances")
    // Everyone else keeps the plain word.
    expect(templateLabels("SaaS").invoice).toBe("Invoice")
    expect(templateLabels("Agency").invoice).toBe("Invoice")
  })

  it("names the money coming in the way the industry names it", () => {
    expect(templateLabels("SaaS").payment).toBe("Subscription Payment")
    expect(templateLabels("Gym").payment).toBe("Membership Payment")
    expect(templateLabels("School").payment).toBe("Fee Payment")
    expect(templateLabels("CleaningService").payment).toBe("Client Payment")
    expect(templateLabels("MembershipBusiness").payment).toBe("Member Payment")
    expect(templateLabels("Other").payment).toBe("Payment")
  })

  it("names a late payer the way the industry names one", () => {
    expect(templateLabels("Gym").overdueCustomer).toBe("Overdue Member")
    // A school chases the parent, not the child, so the label names both.
    expect(templateLabels("School").overdueCustomer).toBe("Overdue Student / Parent")
    expect(templateLabels("Agency").overdueCustomer).toBe("Overdue Client")
    expect(templateLabels("SaaS").overdueCustomer).toBe("Overdue Customer")
  })

  it("calls a plan what the industry calls one", () => {
    expect(templateLabels("SaaS").plan).toBe("Subscription Plan")
    expect(templateLabels("Gym").plan).toBe("Membership Plan")
    expect(templateLabels("School").plan).toBe("Fee Plan")
    expect(templateLabels("CleaningService").plan).toBe("Service Package")
    expect(templateLabels("SecurityService").plan).toBe("Security Service Package")
    expect(templateLabels("Agency").plan).toBe("Retainer Package")
  })

  it("pluralises without producing 'Service Contracts s'", () => {
    expect(templateLabels("CleaningService").subscriptionPlural).toBe("Service Contracts")
    expect(templateLabels("SecurityService").subscriptionPlural).toBe("Security Contracts")
    expect(templateLabels("School").invoicePlural).toBe("Fee Bills")
    expect(templateLabels("Gym").customerPlural).toBe("Members")
    // The slash form pluralises correctly on the last word, which is the
    // wording the spec's own menu uses. Pinned so an edit cannot break it.
    expect(templateLabels("Other").planPlural).toBe("Service / Plans")
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

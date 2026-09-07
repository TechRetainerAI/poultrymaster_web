// What a Generic company calls things.
//
// A gym has members, a school has students, a cleaning firm has clients. They
// all run the SAME module bundle -- the difference is vocabulary, not
// behaviour, which is why this is a lookup table and not ten copies of a page.
//
// Deliberately a typed map rather than a database table. Labels never vary from
// one gym to the next, a map is unit-testable, and putting them in SQL would
// mean a round trip before the sidebar can render its own menu items.
//
// TODO: per-company label overrides. The shape below is what an override row
// would have to fill in, so adding them later is additive.

/** The MODULE BUNDLE: which workflows exist at all. */
export type BusinessTemplate =
  | "SubscriptionServiceBusiness"
  | "RetailBusiness"
  | "GeneralBusiness"

/** The VOCABULARY and the SEEDS. */
export type IndustryTemplate =
  | "SaaS"
  | "Gym"
  | "School"
  | "CleaningService"
  | "SecurityService"
  | "Agency"
  | "RetainerBusiness"
  | "MembershipBusiness"
  | "Retail"
  | "Other"

export interface TemplateLabels {
  /** "Customer", "Member", "Student"… */
  customer: string
  customerPlural: string
  /** What a recurring plan is called. */
  plan: string
  planPlural: string
  /** What a customer being on a plan is called. */
  subscription: string
  subscriptionPlural: string
  invoice: string
  invoicePlural: string
  payment: string
  /** The Customer Balances page title. */
  customerBalance: string
}

/**
 * Plural by adding "s" unless the label says otherwise. Every label below that
 * does not pluralise that way spells its plural out.
 */
function labels(
  customer: string,
  plan: string,
  subscription: string,
  overrides: Partial<TemplateLabels> = {},
): TemplateLabels {
  return {
    customer,
    customerPlural: `${customer}s`,
    plan,
    planPlural: `${plan}s`,
    subscription,
    subscriptionPlural: `${subscription}s`,
    invoice: "Invoice",
    invoicePlural: "Invoices",
    payment: "Payment",
    customerBalance: `${customer} Balances`,
    ...overrides,
  }
}

const LABELS: Record<IndustryTemplate, TemplateLabels> = {
  SaaS: labels("Customer", "Plan", "Subscription"),
  Gym: labels("Member", "Membership Plan", "Membership", {
    customerBalance: "Member Balances",
  }),
  School: labels("Student", "Fee Structure", "Enrolment", {
    // A school bills a term, and calls the bill a fee note.
    invoice: "Fee Note",
    invoicePlural: "Fee Notes",
    customerBalance: "Outstanding Fees",
  }),
  CleaningService: labels("Client", "Service Package", "Service Contract", {
    subscriptionPlural: "Service Contracts",
  }),
  SecurityService: labels("Client", "Service Package", "Service Contract", {
    subscriptionPlural: "Service Contracts",
  }),
  Agency: labels("Client", "Retainer Package", "Retainer"),
  RetainerBusiness: labels("Client", "Retainer Package", "Retainer"),
  MembershipBusiness: labels("Member", "Membership Plan", "Membership", {
    customerBalance: "Member Balances",
  }),
  Retail: labels("Customer", "Plan", "Subscription"),
  Other: labels("Customer", "Plan", "Subscription"),
}

/** The default every Generic company that predates templates keeps. */
export const DEFAULT_LABELS: TemplateLabels = LABELS.Other

/**
 * Labels for a template. An unknown or missing template gets the neutral
 * defaults rather than throwing -- an existing Generic company has no template
 * at all, and it must keep working exactly as it does today.
 */
export function templateLabels(template?: string | null): TemplateLabels {
  if (!template) return DEFAULT_LABELS
  return LABELS[template as IndustryTemplate] ?? DEFAULT_LABELS
}

/** True when this bundle bills on a schedule. */
export function hasSubscriptions(template?: string | null): boolean {
  return template === "SubscriptionServiceBusiness"
}

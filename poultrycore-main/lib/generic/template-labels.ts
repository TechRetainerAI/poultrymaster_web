// What a Generic company calls things.
//
// A gym has members, a school has students, a cleaning firm has clients. They
// all run the SAME module bundle -- the difference is vocabulary, not
// behaviour, which is why this is a lookup table and not ten copies of a page.
//
// The table below is section 4 of the spec, line for line. Where the spec names
// a label ("Membership Bill", "Fee Bill", "Subscription Payment") that name is
// used verbatim rather than a near-enough approximation, because the point of the feature
// is that the owner reads their own words.
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
  /** What the bill is called. A school sends fee bills, a gym membership bills. */
  invoice: string
  invoicePlural: string
  /** What money coming in is called. */
  payment: string
  paymentPlural: string
  /** The Customer Balances page title. */
  customerBalance: string
  /** How a late payer is described: "Overdue Member", "Overdue Student / Parent". */
  overdueCustomer: string
}

/**
 * Plural by adding "s" unless the label says otherwise. Every label below that
 * does not pluralise that way spells its plural out.
 *
 * Note "Service / Plan" + "s" is "Service / Plans", which is the wording the
 * spec's own menu uses -- the slash form pluralises correctly by accident, and
 * the test pins it so a future edit cannot quietly break it.
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
    paymentPlural: "Payments",
    customerBalance: `${customer} Balances`,
    overdueCustomer: `Overdue ${customer}`,
    ...overrides,
  }
}

const LABELS: Record<IndustryTemplate, TemplateLabels> = {
  // A SaaS company keeps the plain words, except that its plans are
  // subscription plans and the money coming in is a subscription payment.
  SaaS: labels("Customer", "Subscription Plan", "Subscription", {
    payment: "Subscription Payment",
    paymentPlural: "Subscription Payments",
  }),

  Gym: labels("Member", "Membership Plan", "Membership", {
    invoice: "Membership Bill",
    invoicePlural: "Membership Bills",
    payment: "Membership Payment",
    paymentPlural: "Membership Payments",
    customerBalance: "Member Balances",
  }),

  // A school bills a term, and the person who pays is usually not the person
  // enrolled -- which is why the overdue label names both.
  School: labels("Student", "Fee Plan", "Enrollment", {
    invoice: "Fee Bill",
    invoicePlural: "Fee Bills",
    payment: "Fee Payment",
    paymentPlural: "Fee Payments",
    customerBalance: "Outstanding Fees",
    overdueCustomer: "Overdue Student / Parent",
  }),

  CleaningService: labels("Client", "Service Package", "Service Contract", {
    subscriptionPlural: "Service Contracts",
    invoice: "Service Bill",
    invoicePlural: "Service Bills",
    payment: "Client Payment",
    paymentPlural: "Client Payments",
  }),

  SecurityService: labels("Client", "Security Service Package", "Security Contract", {
    subscriptionPlural: "Security Contracts",
    invoice: "Service Bill",
    invoicePlural: "Service Bills",
    payment: "Client Payment",
    paymentPlural: "Client Payments",
  }),

  Agency: labels("Client", "Retainer Package", "Support Retainer", {
    payment: "Client Payment",
    paymentPlural: "Client Payments",
  }),

  RetainerBusiness: labels("Client", "Retainer Package", "Retainer", {
    payment: "Client Payment",
    paymentPlural: "Client Payments",
  }),

  MembershipBusiness: labels("Member", "Membership Plan", "Membership", {
    invoice: "Bill",
    invoicePlural: "Bills",
    payment: "Member Payment",
    paymentPlural: "Member Payments",
    customerBalance: "Member Balances",
  }),

  // A shop and an unclassified business both keep the neutral words. "Service /
  // Plan" is the spec's own wording for a business that may have either.
  Retail: labels("Customer", "Service / Plan", "Subscription"),
  Other: labels("Customer", "Service / Plan", "Subscription / Contract"),
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

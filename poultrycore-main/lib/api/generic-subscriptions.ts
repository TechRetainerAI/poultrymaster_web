// Generic Company subscription API client.
//
// Business templates, module visibility, service plans, subscriptions and
// billing runs (migrations 242-243). Same fetch + buildApiUrl + getAuthHeaders
// pattern as lib/api/generic.ts, kept in its own file so the 1,000-line generic
// client does not grow another module.
//
// Customer Balances is NOT here: lib/api/balances.ts already speaks all three
// modules and the Generic page is a thin wrapper over it.

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import type { BusinessTemplate, IndustryTemplate } from "@/lib/generic/template-labels"
import type { BillingFrequency } from "@/lib/generic/billing-schedule"

// =============================================================================
// Types
// =============================================================================

/** Which modules this company's menus and pages show. Never null. */
export interface GenericModuleSettings {
  farmId: string
  enableProducts: boolean
  enableInventory: boolean
  enableStockAdjustments: boolean
  enableInternalUse: boolean
  enablePurchases: boolean
  enableSubscriptions: boolean
  enableInvoices: boolean
  enableCustomerBalances: boolean
  enableStaffPayments: boolean
  enableCashAccounts: boolean
}

export interface GenericServicePlan {
  genericServiceId: number
  farmId: string
  serviceName: string
  genericServiceCategoryId?: number | null
  categoryName?: string | null
  defaultPrice: number
  /** Recurring | OneOff. Null on a plain service that is not a plan. */
  planType?: string | null
  billingFrequency?: string | null
  notes?: string | null
  isActive: boolean
  activeSubscriptions: number
  monthlyValue: number
}

export type SubscriptionStatus =
  | "Draft"
  | "Active"
  | "Paused"
  | "Overdue"
  | "Suspended"
  | "Cancelled"
  | "Expired"

export interface GenericSubscription {
  genericSubscriptionId: number
  farmId: string
  genericCustomerId: number
  customerName?: string | null
  genericServiceId: number
  serviceName?: string | null
  subscriptionNumber?: string | null
  startDate: string
  endDate?: string | null
  billingFrequency: string
  billingAmount: number
  discountAmount: number
  taxAmount: number
  totalBillingAmount: number
  nextBillingDate?: string | null
  lastBillingDate?: string | null
  paymentDueDays: number
  autoGenerateInvoice: boolean
  defaultPaymentMethod?: string | null
  defaultCashAccountId?: number | null
  status: SubscriptionStatus | string
  notes?: string | null
  openInvoiceCount: number
  openBalance: number
  createdBy?: string | null
  createdAt?: string | null
}

export interface CreateSubscriptionInput {
  genericCustomerId: number
  genericServiceId: number
  startDate: string
  endDate?: string | null
  billingFrequency: BillingFrequency | string
  billingAmount: number
  discountAmount?: number
  taxAmount?: number
  paymentDueDays?: number
  autoGenerateInvoice?: boolean
  defaultPaymentMethod?: string | null
  defaultCashAccountId?: number | null
  notes?: string | null
  createdBy?: string | null
}

/** One line of "what generating now would raise". */
export interface BillingPreviewRow {
  genericSubscriptionId: number
  subscriptionNumber?: string | null
  genericCustomerId: number
  customerName?: string | null
  serviceName?: string | null
  billingFrequency: string
  billingPeriodStart: string
  billingPeriodEnd: string
  dueDate: string
  invoiceAmount: number
  /** True when this period is already invoiced, so generate will skip it. */
  alreadyBilled: boolean
}

export interface BillingRun {
  genericBillingRunId: number
  billingRunDate: string
  asOfDate: string
  totalSubscriptionsChecked: number
  totalInvoicesGenerated: number
  totalSkipped: number
  status: string
  notes?: string | null
  createdBy?: string | null
}

// =============================================================================
// Plumbing
// =============================================================================

function farmBase(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return `/generic-company/${encodeURIComponent(farmId)}`
}

function currentFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return farmId
}

async function getJson<T>(endpoint: string): Promise<T> {
  const r = await fetch(buildApiUrl(endpoint), { method: "GET", headers: getAuthHeaders() })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("GET", endpoint, r.status, text))
  }
  return (await r.json()) as T
}

async function sendJson<T>(
  method: "POST" | "PUT",
  endpoint: string,
  body: unknown,
): Promise<T | null> {
  const r = await fetch(buildApiUrl(endpoint), {
    method,
    headers: getAuthHeaders(),
    // Every body carries farmId: model validation runs before the action body,
    // so a request without it fails with 400 before the controller can copy it
    // off the route -- and the audit filter's farmId cascade reads the body,
    // not the {farmId} route segment.
    body: JSON.stringify({ ...(body as object), farmId: currentFarmId() }),
  })
  if (r.status === 204) return null
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError(method, endpoint, r.status, text))
  }
  const txt = await r.text()
  return txt ? (JSON.parse(txt) as T) : null
}

// =============================================================================
// Business template + module visibility
// =============================================================================

/** Both fields are null for a Generic company that predates templates. */
export interface GenericBusinessTemplateInfo {
  farmId: string
  genericBusinessTemplate?: string | null
  genericIndustryTemplate?: string | null
}

/**
 * Which template this company is on — what drives the labels ("Member",
 * "Student", "Fee Note"). Its own endpoint rather than a field on the profile:
 * the live profile proc selects a fixed column list and would silently keep
 * omitting the two new columns.
 */
export async function getBusinessTemplate(): Promise<GenericBusinessTemplateInfo> {
  return getJson<GenericBusinessTemplateInfo>(`${farmBase()}/business-template`)
}

export async function getModuleSettings(): Promise<GenericModuleSettings> {
  return getJson<GenericModuleSettings>(`${farmBase()}/module-settings`)
}

export async function saveModuleSettings(
  s: Omit<GenericModuleSettings, "farmId">,
): Promise<GenericModuleSettings | null> {
  return sendJson<GenericModuleSettings>("PUT", `${farmBase()}/module-settings`, s)
}

/**
 * Stamps the template on the company and seeds this industry's categories, cash
 * accounts and starter plans. Safe to call again — every seed is
 * ON CONFLICT DO NOTHING, so nothing the owner has since edited is overwritten.
 */
export async function applyBusinessTemplate(input: {
  businessTemplate: BusinessTemplate
  industryTemplate: IndustryTemplate
  createdBy?: string | null
}): Promise<GenericModuleSettings | null> {
  return sendJson<GenericModuleSettings>("POST", `${farmBase()}/business-template`, input)
}

// =============================================================================
// Service plans
// =============================================================================

export async function getServicePlans(activeOnly = false): Promise<GenericServicePlan[]> {
  const q = activeOnly ? "?activeOnly=true" : ""
  return getJson<GenericServicePlan[]>(`${farmBase()}/service-plans${q}`)
}

/**
 * Sets a service's plan type and billing frequency. Creating or renaming the
 * service itself still goes through the service-catalogue endpoints.
 */
export async function setServicePlan(
  serviceId: number,
  input: { planType?: string | null; billingFrequency?: string | null },
): Promise<void> {
  await sendJson("PUT", `${farmBase()}/service-plans/${serviceId}`, input)
}

export interface GenericServiceCategory {
  genericServiceCategoryId: number
  name: string
  description?: string | null
  isActive: boolean
}

export async function getServiceCategories(): Promise<GenericServiceCategory[]> {
  return getJson<GenericServiceCategory[]>(`${farmBase()}/service-categories`)
}

/**
 * Creates the plan in two steps because they are two different things: a plan
 * IS a service (the existing catalogue endpoint owns that), and the two plan
 * columns are set separately so this never has to rewrite a live proc whose
 * body is not in the repo.
 */
export async function createServicePlan(input: {
  serviceName: string
  defaultPrice: number
  genericServiceCategoryId?: number | null
  planType?: string | null
  billingFrequency?: string | null
  notes?: string | null
}): Promise<number | null> {
  const created = await sendJson<{ genericServiceId: number }>("POST", `${farmBase()}/services`, {
    serviceName: input.serviceName,
    defaultPrice: input.defaultPrice,
    genericServiceCategoryId: input.genericServiceCategoryId ?? null,
    notes: input.notes ?? null,
    isActive: true,
  })
  const id = created?.genericServiceId ?? null
  if (id && (input.planType || input.billingFrequency)) {
    await setServicePlan(id, {
      planType: input.planType ?? null,
      billingFrequency: input.billingFrequency ?? null,
    })
  }
  return id
}

// =============================================================================
// Subscriptions
// =============================================================================

export async function getSubscriptions(status?: string | null): Promise<GenericSubscription[]> {
  const q = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericSubscription[]>(`${farmBase()}/subscriptions${q}`)
}

export async function createSubscription(
  input: CreateSubscriptionInput,
): Promise<number | null> {
  const res = await sendJson<{ genericSubscriptionId: number }>(
    "POST",
    `${farmBase()}/subscriptions`,
    input,
  )
  return res?.genericSubscriptionId ?? null
}

/**
 * Pause, resume, suspend, cancel or expire. Cancelling needs a reason — the
 * server rejects a blank one rather than silently cancelling.
 */
export async function setSubscriptionStatus(
  subscriptionId: number,
  input: { status: SubscriptionStatus | string; reason?: string | null; by?: string | null },
): Promise<void> {
  await sendJson("POST", `${farmBase()}/subscriptions/${subscriptionId}/status`, input)
}

/**
 * A genericsales row read as an invoice. Same table the Sales page shows; this
 * shape adds the due date, the subscription it came from and whether it is
 * overdue.
 */
export interface GenericInvoiceRow {
  genericSaleId: number
  receiptNumber?: string | null
  saleDate: string
  dueDate?: string | null
  genericCustomerId?: number | null
  customerName?: string | null
  genericSubscriptionId?: number | null
  subscriptionNumber?: string | null
  billingPeriodStart?: string | null
  billingPeriodEnd?: string | null
  totalAmount: number
  amountPaid: number
  balance: number
  paymentStatus: string
  /** Draft | Approved | Cancelled | Refunded. */
  status: string
  /** Only an approved invoice with a balance can be overdue. */
  isOverdue: boolean
  ageDays: number
  notes?: string | null
  createdAt?: string | null
}

export async function getInvoices(opts: {
  status?: string | null
  subscriptionOnly?: boolean
  from?: string | null
  to?: string | null
} = {}): Promise<GenericInvoiceRow[]> {
  const params = new URLSearchParams()
  if (opts.status && opts.status !== "All") params.set("status", opts.status)
  if (opts.subscriptionOnly) params.set("subscriptionOnly", "true")
  if (opts.from) params.set("from", opts.from)
  if (opts.to) params.set("to", opts.to)
  const q = params.toString()
  return getJson<GenericInvoiceRow[]>(`${farmBase()}/invoices${q ? `?${q}` : ""}`)
}

// =============================================================================
// Billing runs
// =============================================================================

export async function getBillingRuns(): Promise<BillingRun[]> {
  return getJson<BillingRun[]>(`${farmBase()}/billing-runs`)
}

/** What generating right now would raise. Writes nothing. */
export async function previewBilling(asOf?: string | null): Promise<BillingPreviewRow[]> {
  const q = asOf ? `?asOf=${encodeURIComponent(asOf)}` : ""
  return getJson<BillingPreviewRow[]>(`${farmBase()}/billing-runs/preview${q}`)
}

/**
 * Raises one DRAFT invoice per unbilled period. Draft on purpose: approving an
 * invoice is what makes it a receivable, and that stays a human decision.
 * Running it twice bills nobody twice.
 */
export async function generateBilling(asOf?: string | null): Promise<BillingRun | null> {
  return sendJson<BillingRun>("POST", `${farmBase()}/billing-runs/generate`, {
    asOf: asOf ?? null,
  })
}

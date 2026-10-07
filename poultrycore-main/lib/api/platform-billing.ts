// Platform billing — the Business Office's consolidated VisibilityCore
// subscription (migration 329). Served by the farm API's PlatformBilling
// routes; amounts and currency are always computed server-side, this client
// only displays them and forwards references.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"

export interface BillingAccount {
  id: number
  marketCode: string
  currencyCode: string
  status: string
  billingCycle: string
  trialStartUtc?: string | null
  trialEndUtc?: string | null
  trialDaysLeft?: number | null
  billingEmail?: string | null
  verificationStatus: string
  cancelAtPeriodEnd: boolean
  currentPeriodEnd?: string | null
  pendingMarketCode?: string | null
  pendingMarketEffective?: string | null
}

export interface CompanyBillingRow {
  farmId: string
  companyName: string
  companyFamily: string
  businessType: string
  billingProfileCode: string
  billingProfileName: string
  metricType: string
  metricValue: number
  tierCode?: string | null
  tierName?: string | null
  monthlyAmount?: number | null
  currencyCode: string
  pricingStatus: string
  participationStatus: string
  evaluationUntilUtc?: string | null
}

export interface BillPreview {
  subtotal: number
  eligibleCompanyCount: number
  discountPercent: number
  discountAmount: number
  taxAmount: number
  total: number
  currencyCode: string
  hasUnpricedCompanies: boolean
  periodStart: string
  periodEnd: string
  discountBreakdown?: { id: number; name: string; amount: number }[]
  creditsAvailable?: number
  estimatedCreditApplied?: number
  estimatedAmountDue?: number
}

export interface SavingsDetail {
  kind: "MultiCompany" | "Discount" | "Promotion" | "Credit"
  name: string
  discountType?: string | null
  value?: number | null
  amountThisPeriod: number
  endDate?: string | null
  remainingPeriods?: number | null
  explanation?: string | null
}

export interface BillingSummary {
  pendingTierChanges: PendingTierChange[]
  account: BillingAccount
  companies: CompanyBillingRow[]
  preview: BillPreview
  enforcementEnabled: boolean
  savings?: SavingsDetail[]
}

export interface PlatformInvoiceLine {
  farmId?: string | null
  description: string
  tierCode?: string | null
  metricValue?: number | null
  unitPrice: number
  lineAmount: number
}

export interface PlatformInvoice {
  id: number
  invoiceNumber: string
  currencyCode: string
  periodStart: string
  periodEnd: string
  issueDate: string
  dueDate: string
  subtotal: number
  discountAmount: number
  taxAmount: number
  totalAmount: number
  amountPaid: number
  creditApplied?: number
  balance: number
  status: string
  discountBreakdown?: string | null
  lines: PlatformInvoiceLine[]
}

export interface PlatformPayment {
  id: number
  provider: string
  externalReference?: string | null
  amount: number
  currencyCode: string
  status: string
  paymentDateUtc?: string | null
  invoiceNumber?: string | null
  methodSummary?: string | null
}

export interface PricingExplain {
  companyName: string
  billingProfileName: string
  metricType: string
  metricValue: number
  tierName?: string | null
  marketName: string
  monthlyAmount?: number | null
  currencyCode: string
  pricingStatus: string
  evaluatedAtUtc: string
  nextTierName?: string | null
  nextTierAtValue?: number | null
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error((await res.text()) || `Request failed (${res.status})`)
  return (await res.json()) as T
}

export async function getBillingSummary(): Promise<BillingSummary> {
  const { userId } = getUserContext()
  return jget<BillingSummary>(`/PlatformBilling/summary?userId=${encodeURIComponent(userId)}`)
}

export async function getPlatformInvoices(): Promise<PlatformInvoice[]> {
  const { userId } = getUserContext()
  return jget<PlatformInvoice[]>(`/PlatformBilling/invoices?userId=${encodeURIComponent(userId)}`)
}

export async function getPlatformPayments(): Promise<PlatformPayment[]> {
  const { userId } = getUserContext()
  return jget<PlatformPayment[]>(`/PlatformBilling/payments?userId=${encodeURIComponent(userId)}`)
}

export async function explainCompanyPricing(farmId: string): Promise<PricingExplain> {
  const { userId } = getUserContext()
  return jget<PricingExplain>(
    `/PlatformBilling/explain?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
  )
}

export async function startPlatformCheckout(
  successUrl: string,
  failureUrl: string
): Promise<{ success: boolean; checkoutUrl?: string; reference?: string; message?: string }> {
  const { userId } = getUserContext()
  const res = await fetch(farmApiUrl(`/PlatformBilling/checkout`), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ userId, successUrl, failureUrl }),
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) return { success: false, message: body?.message || `Checkout failed (${res.status})` }
  return body
}

/**
 * Settlement truth comes from the provider, never from landing back on a
 * success URL — the return only tells us which reference to verify.
 */
export async function verifyPlatformPayment(reference: string): Promise<{ ok: boolean; message: string }> {
  const { userId } = getUserContext()
  const res = await fetch(
    farmApiUrl(
      `/PlatformBilling/verify?userId=${encodeURIComponent(userId)}&reference=${encodeURIComponent(reference)}`
    ),
    { headers: getAuthHeaders() }
  )
  const body = await res.json().catch(() => ({}))
  return { ok: res.ok && body?.ok === true, message: body?.message || "Verification failed." }
}

// ---------- Phase B ----------

export interface PendingTierChange {
  farmId: string
  companyName: string
  fromTierName: string
  toTierName: string
  effectiveDate: string
}

export interface MarketChangePreview {
  marketCode: string
  marketName: string
  currencyCode: string
  marketActive: boolean
  companies: CompanyBillingRow[]
  preview: BillPreview
}

export interface PlanUsage {
  farmId: string
  companyName: string
  billingProfileCode: string
  metricType: string
  metricValue: number
  tierCode?: string | null
  monthlyAmount?: number | null
  currencyCode: string
  pricingStatus: string
  evaluatedAtUtc: string
  managedBy: string
}

async function jpost(path: string, body: unknown): Promise<{ ok: boolean; message: string }> {
  const res = await fetch(farmApiUrl(path), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify(body),
  })
  const data = await res.json().catch(() => ({}))
  return { ok: res.ok && data?.ok !== false, message: data?.message || (res.ok ? "Done." : `Failed (${res.status})`) }
}

export async function previewMarket(marketCode: string): Promise<MarketChangePreview> {
  const { userId } = getUserContext()
  return jget<MarketChangePreview>(
    `/PlatformBilling/market-preview?userId=${encodeURIComponent(userId)}&marketCode=${encodeURIComponent(marketCode)}`
  )
}

export async function requestMarketChange(marketCode: string, reason: string) {
  const { userId } = getUserContext()
  return jpost(`/PlatformBilling/market-change`, { userId, marketCode, reason })
}

export async function cancelMarketChange(): Promise<{ ok: boolean; message: string }> {
  const { userId } = getUserContext()
  const res = await fetch(
    farmApiUrl(`/PlatformBilling/market-change?userId=${encodeURIComponent(userId)}`),
    { method: "DELETE", headers: getAuthHeaders() }
  )
  const data = await res.json().catch(() => ({}))
  return { ok: res.ok, message: data?.message || "" }
}

export async function setBillingCycle(cycle: "monthly" | "annual") {
  const { userId } = getUserContext()
  return jpost(`/PlatformBilling/billing-cycle`, { userId, cycle })
}

export async function cancelSubscription(reason?: string) {
  const { userId } = getUserContext()
  return jpost(`/PlatformBilling/cancel`, { userId, reason })
}

export async function reactivateSubscription() {
  const { userId } = getUserContext()
  return jpost(`/PlatformBilling/reactivate`, { userId })
}

export interface Entitlement {
  tierCode: string
  capability: string
  enabled: boolean
  limit?: number | null
  usage?: number | null
  limitReached: boolean
}

/** Configured tier capabilities for this company; an absent capability is unlimited (spec 17/24). */
export async function getEntitlements(farmId: string): Promise<Entitlement[]> {
  const { userId } = getUserContext()
  return jget<Entitlement[]>(
    `/PlatformBilling/entitlements?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
  )
}

/** The company-level "Plan & Usage" view — read-only, managed by the Business Office. */
export async function getPlanUsage(farmId: string): Promise<PlanUsage> {
  const { userId } = getUserContext()
  return jget<PlanUsage>(
    `/PlatformBilling/plan-usage?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
  )
}

// ---------- Platform admin (SystemAdmin / PlatformOwner only) ----------

export async function getAdminConfig(): Promise<Record<string, unknown[]>> {
  const { userId } = getUserContext()
  return jget<Record<string, unknown[]>>(
    `/PlatformBillingAdmin/config?userId=${encodeURIComponent(userId)}`
  )
}

export async function adminPutSetting(key: string, value: string) {
  const { userId } = getUserContext()
  const res = await fetch(farmApiUrl(`/PlatformBillingAdmin/setting`), {
    method: "PUT", headers: getAuthHeaders(), body: JSON.stringify({ userId, key, value }),
  })
  return { ok: res.ok }
}

export async function adminPostPrice(body: {
  marketCode: string; tierCode: string; profileCode?: string | null
  monthlyPrice: number; annualPrice?: number | null
}) {
  const { userId } = getUserContext()
  const res = await fetch(farmApiUrl(`/PlatformBillingAdmin/price`), {
    method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ userId, ...body }),
  })
  return { ok: res.ok, message: res.ok ? "Price configured." : await res.text() }
}

export async function adminPutDiscounts(rules: { minCompanies: number; percent: number }[]) {
  const { userId } = getUserContext()
  const res = await fetch(farmApiUrl(`/PlatformBillingAdmin/discounts`), {
    method: "PUT", headers: getAuthHeaders(), body: JSON.stringify({ userId, rules }),
  })
  return { ok: res.ok }
}

export async function adminPutCompanyState(body: Record<string, unknown>) {
  const { userId } = getUserContext()
  const res = await fetch(farmApiUrl(`/PlatformBillingAdmin/company-state`), {
    method: "PUT", headers: getAuthHeaders(), body: JSON.stringify({ userId, ...body }),
  })
  return { ok: res.ok, message: res.ok ? "Saved." : await res.text() }
}

export async function adminCreditNote(invoiceNumber: string, amount: number, reason: string) {
  const { userId } = getUserContext()
  const res = await fetch(farmApiUrl(`/PlatformBillingAdmin/credit-note`), {
    method: "POST", headers: getAuthHeaders(),
    body: JSON.stringify({ userId, invoiceNumber, amount, reason }),
  })
  return { ok: res.ok, message: res.ok ? "Credit applied." : await res.text() }
}

export async function adminRunMaintenance(): Promise<{ report?: string }> {
  const { userId } = getUserContext()
  const res = await fetch(farmApiUrl(`/PlatformBillingAdmin/run-maintenance`), {
    method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ userId, key: "run" }),
  })
  return res.ok ? res.json() : { report: `Failed (${res.status})` }
}

// ---------- Presentation-driven plan cards (admin-app spec 11-16) ----------

export interface PublicPlanCard {
  tierCode: string
  tierName: string
  headline?: string | null
  featureBullets: string[]
  badgeText?: string | null
  isMostPopular: boolean
  ctaText?: string | null
  monthlyPrice?: number | null
  annualPrice?: number | null
  minValue?: number | null
  maxValue?: number | null
}

export interface PublicPricing {
  marketCode: string
  currencyCode: string
  billingProfileCode: string
  usedFallback: boolean
  displayName: string
  shortDescription?: string | null
  metricDisplayName?: string | null
  metricSingular?: string | null
  metricPlural?: string | null
  plans: PublicPlanCard[]
}

export interface PricingContext {
  billingProfileCode: string
  businessTemplateCode?: string | null
  displayName: string
  sortOrder: number
}

/** The pricing-context selector's options, from presentation config (anonymous). */
export async function getPricingContexts(): Promise<PricingContext[]> {
  const res = await fetch(farmApiUrl(`/PlatformBilling/pricing-contexts`))
  if (!res.ok) throw new Error(`Contexts not available (${res.status})`)
  return (await res.json()) as PricingContext[]
}

export interface CyclePreview {
  currentCycle: string
  targetCycle: string
  current: BillPreview
  target: BillPreview
  missingPrices: string[]
  effectiveDate: string
}

/** Backend-computed monthly/annual comparison for the switch confirmation. */
export async function getCyclePreview(cycle: "monthly" | "annual"): Promise<CyclePreview> {
  const { userId } = getUserContext()
  return jget<CyclePreview>(
    `/PlatformBilling/cycle-preview?userId=${encodeURIComponent(userId)}&cycle=${cycle}`
  )
}

/** Anonymous — the public pricing page uses it before any login exists. */
export async function getPublicPricing(
  market = "GH", profile = "POULTRY_BIRDS", template?: string
): Promise<PublicPricing> {
  const qs = `market=${encodeURIComponent(market)}&profile=${encodeURIComponent(profile)}${template ? `&template=${encodeURIComponent(template)}` : ""}`
  const res = await fetch(farmApiUrl(`/PlatformBilling/public-pricing?${qs}`))
  if (!res.ok) throw new Error(`Pricing not available (${res.status})`)
  return (await res.json()) as PublicPricing
}

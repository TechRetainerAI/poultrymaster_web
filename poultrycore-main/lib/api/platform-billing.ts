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
}

export interface CompanyBillingRow {
  farmId: string
  companyName: string
  companyFamily: string
  businessType: string
  billingProfileName: string
  metricType: string
  metricValue: number
  tierName?: string | null
  monthlyAmount?: number | null
  currencyCode: string
  pricingStatus: string
  participationStatus: string
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
}

export interface BillingSummary {
  account: BillingAccount
  companies: CompanyBillingRow[]
  preview: BillPreview
  enforcementEnabled: boolean
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
  balance: number
  status: string
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

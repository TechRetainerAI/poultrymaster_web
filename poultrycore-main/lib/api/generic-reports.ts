// Generic Company subscription dashboard + reports API client (migration 250).
//
// Same fetch + buildApiUrl + getAuthHeaders pattern as lib/api/generic.ts and
// lib/api/generic-subscriptions.ts.
//
// Six of the spec's twelve reports are NOT here, on purpose:
//
//   Customer payments   listPayments("generic", "customer", …)   lib/api/balances
//   Unpaid customers    listBalances("generic", "customer", …)   lib/api/balances
//   Customer balances   listBalances("generic", "customer", …)   lib/api/balances
//   Supplier balances   listBalances("generic", "supplier", …)   lib/api/balances
//   Cash flow           getCashSummaryReport()                   lib/api/generic
//   Profit / loss       getPeriodPnL()                           lib/api/generic
//
// Their report pages call those. Wrapping them again here would have created a
// second way to ask the same question, and the two answers drifting apart is a
// matter of when, not whether.

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import type { GenericCashSummaryRow, GenericExpenseByCategoryRow } from "./generic"

// =============================================================================
// Types — one per result set in migration 250.
// =============================================================================

export interface GenericSubDashboardKpis {
  monthStart: string
  monthEnd: string
  monthlyRecurringRevenue: number
  activeSubscriptions: number
  activeCustomers: number
  paymentsCollected: number
  expensesPaid: number
  netCashFlow: number
  invoicedThisMonth: number
  customerBalances: number
  supplierBalances: number
  cashAtHand: number
  overdueCustomers: number
  overdueAmount: number
  monthlyBurnRate: number
  breakEvenCustomers: number
  newSubscriptions: number
  cancelledSubscriptions: number
}

export interface GenericSubRenewalRow {
  genericSubscriptionId: number
  subscriptionNumber?: string | null
  genericCustomerId: number
  customerName: string
  serviceName?: string | null
  billingFrequency: string
  nextBillingDate?: string | null
  totalBillingAmount: number
  /** Negative when the subscription is already late to bill. */
  daysUntil: number
  status: string
}

export interface GenericOverduePartyRow {
  partyId: number
  partyName: string
  contactPhone?: string | null
  totalBalance: number
  overdueAmount: number
  openDocumentCount: number
  oldestDocumentDate?: string | null
  lastPaymentDate?: string | null
}

export interface GenericExpenseSliceRow {
  genericExpenseCategoryId: number
  categoryName: string
  expenseCount: number
  totalAmount: number
  pctOfTotal: number
}

export interface GenericRecurringDueRow {
  genericRecurringExpenseId: number
  expenseName: string
  categoryName?: string | null
  supplierName?: string | null
  amount: number
  frequency: string
  nextDueDate?: string | null
  daysUntil: number
}

export interface GenericActivityRow {
  activityAt: string
  activityType: string
  reference?: string | null
  party?: string | null
  description?: string | null
  /** Signed: money out is negative. */
  amount: number
  status: string
}

export interface GenericSubAlerts {
  dueToBillCount: number
  dueToBillAmount: number
  draftInvoiceCount: number
  draftInvoiceAmount: number
  endingSoonCount: number
  recurringDueCount: number
  recurringDueAmount: number
  overdueCustomerCount: number
  overdueCustomerAmount: number
  negativeAccountCount: number
}

export interface GenericStaffPaySummary {
  peoplePaid: number
  staffPaymentTotal: number
  payrollTotal: number
  totalPaid: number
  topPersonName?: string | null
  topPersonAmount: number
}

export interface GenericSubDashboard {
  kpis: GenericSubDashboardKpis
  renewals: GenericSubRenewalRow[]
  overdueCustomers: GenericOverduePartyRow[]
  expenseBreakdown: GenericExpenseSliceRow[]
  recurringDue: GenericRecurringDueRow[]
  recentActivity: GenericActivityRow[]
  alerts: GenericSubAlerts
  staffSummary: GenericStaffPaySummary
  cashAccounts: GenericCashSummaryRow[]
}

export interface GenericMrrRow {
  monthStart: string
  activeMrr: number
  activeCount: number
  newMrr: number
  newCount: number
  lostMrr: number
  lostCount: number
  /** Always 0 — there is no subscription amount history to derive it from. */
  expansionMrr: number
  /** Always 0, for the same reason as expansionMrr. */
  contractionMrr: number
  netMrrChange: number
}

export interface GenericSubRevenueMonthRow {
  monthStart: string
  invoiceCount: number
  invoicedAmount: number
  /** Paid against THAT month's invoices as of now, not cash received that month. */
  collectedAmount: number
  outstanding: number
  activeMrr: number
  newCount: number
  lostCount: number
}

export interface GenericSubRevenuePlanRow {
  genericServiceId: number
  serviceName: string
  billingFrequency: string
  activeSubscriptions: number
  activeMrr: number
  invoiceCount: number
  invoicedAmount: number
  collectedAmount: number
  outstanding: number
}

export interface GenericSubRevenueCustomerRow {
  genericCustomerId: number
  customerName: string
  contactPhone?: string | null
  activeSubscriptions: number
  activeMrr: number
  invoiceCount: number
  invoicedAmount: number
  collectedAmount: number
  outstanding: number
  lastPaymentDate?: string | null
}

export interface GenericSubRevenueReport {
  byMonth: GenericSubRevenueMonthRow[]
  byPlan: GenericSubRevenuePlanRow[]
  byCustomer: GenericSubRevenueCustomerRow[]
}

export interface GenericIncomeSplit {
  subscriptionIncome: number
  subscriptionInvoiceCount: number
  otherIncome: number
  otherSalesCount: number
  totalIncome: number
}

export interface GenericExpenseBySupplierRow {
  /** Null on the "No supplier" row. */
  genericSupplierId?: number | null
  supplierName: string
  expenseCount: number
  totalAmount: number
  amountPaid: number
  outstanding: number
}

export interface GenericExpenseTrendRow {
  monthStart: string
  expenseCount: number
  totalAmount: number
  recurringAmount: number
  staffAmount: number
}

export interface GenericExpenseReport {
  byCategory: GenericExpenseByCategoryRow[]
  bySupplier: GenericExpenseBySupplierRow[]
  trend: GenericExpenseTrendRow[]
}

export interface GenericHostingCategoryRow {
  genericExpenseCategoryId: number
  categoryName: string
  /** Matched the hosting name pattern. A suggestion, not a decision. */
  isSuggested: boolean
  totalAmount: number
}

export interface GenericHostingCostRow {
  monthStart: string
  hostingCost: number
  expenseCount: number
  totalRevenue: number
  totalExpenses: number
  pctOfRevenue: number
  pctOfExpenses: number
}

export interface GenericHostingCostReport {
  categories: GenericHostingCategoryRow[]
  months: GenericHostingCostRow[]
}

export interface GenericStaffCostPersonRow {
  genericStaffId: number
  staffName: string
  staffRole?: string | null
  workerType?: string | null
  paymentCount: number
  staffPayments: number
  payrollPay: number
  totalPaid: number
  lastPaymentDate?: string | null
}

export interface GenericStaffCostMonthRow {
  monthStart: string
  peoplePaid: number
  staffPayments: number
  payrollPay: number
  totalPaid: number
}

export interface GenericStaffCostRoleRow {
  staffRole: string
  peopleCount: number
  totalPaid: number
  pctOfTotal: number
}

export interface GenericStaffCostReport {
  byPerson: GenericStaffCostPersonRow[]
  byMonth: GenericStaffCostMonthRow[]
  byRole: GenericStaffCostRoleRow[]
}

export interface GenericBreakEven {
  monthsAveraged: number
  periodStart: string
  periodEnd: string
  monthlyFixedCosts: number
  monthlyRecurringRevenue: number
  activeCustomers: number
  activeSubscriptions: number
  avgRevenuePerCustomer: number
  breakEvenCustomers: number
  /** Negative means that many customers short of covering the month. */
  customerSurplus: number
  monthlySurplus: number
}

// =============================================================================
// Plumbing
// =============================================================================

function reportsBase(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return `/generic-company/${encodeURIComponent(farmId)}/reports`
}

async function getJson<T>(endpoint: string): Promise<T> {
  const r = await fetch(buildApiUrl(endpoint), { method: "GET", headers: getAuthHeaders() })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("GET", endpoint, r.status, text))
  }
  return (await r.json()) as T
}

function range(fromDate?: string | null, toDate?: string | null): string {
  const p = new URLSearchParams()
  if (fromDate) p.set("fromDate", fromDate)
  if (toDate) p.set("toDate", toDate)
  const q = p.toString()
  return q ? `?${q}` : ""
}

// =============================================================================
// Calls
// =============================================================================

/** Every panel of the subscription dashboard, in one request. */
export async function getSubscriptionDashboard(asOf?: string | null): Promise<GenericSubDashboard> {
  const q = asOf ? `?asOf=${encodeURIComponent(asOf)}` : ""
  return getJson<GenericSubDashboard>(`${reportsBase()}/subscription-dashboard${q}`)
}

export async function getMrrReport(fromDate?: string, toDate?: string): Promise<GenericMrrRow[]> {
  return getJson<GenericMrrRow[]>(`${reportsBase()}/mrr${range(fromDate, toDate)}`)
}

export async function getSubscriptionRevenue(
  fromDate?: string,
  toDate?: string,
): Promise<GenericSubRevenueReport> {
  return getJson<GenericSubRevenueReport>(`${reportsBase()}/subscription-revenue${range(fromDate, toDate)}`)
}

export async function getIncomeSplit(fromDate?: string, toDate?: string): Promise<GenericIncomeSplit> {
  return getJson<GenericIncomeSplit>(`${reportsBase()}/income-split${range(fromDate, toDate)}`)
}

export async function getExpenseReport(fromDate?: string, toDate?: string): Promise<GenericExpenseReport> {
  return getJson<GenericExpenseReport>(`${reportsBase()}/expense-report${range(fromDate, toDate)}`)
}

/**
 * Hosting / cloud cost against revenue.
 *
 * OMIT categoryIds to use the suggested categories. An EMPTY array is a
 * different question — "the owner ticked nothing" — and correctly returns
 * zeros. A query string cannot carry an empty list, so that case travels as
 * useSuggested=false, which is what the endpoint expects.
 */
export async function getHostingCost(
  fromDate?: string,
  toDate?: string,
  categoryIds?: number[],
): Promise<GenericHostingCostReport> {
  const p = new URLSearchParams()
  if (fromDate) p.set("fromDate", fromDate)
  if (toDate) p.set("toDate", toDate)
  if (categoryIds) {
    if (categoryIds.length === 0) p.set("useSuggested", "false")
    else categoryIds.forEach((id) => p.append("categoryIds", String(id)))
  }
  const q = p.toString()
  return getJson<GenericHostingCostReport>(`${reportsBase()}/hosting-cost${q ? `?${q}` : ""}`)
}

export async function getStaffCostReport(fromDate?: string, toDate?: string): Promise<GenericStaffCostReport> {
  return getJson<GenericStaffCostReport>(`${reportsBase()}/staff-cost${range(fromDate, toDate)}`)
}

export async function getBreakEven(asOf?: string | null, months = 3): Promise<GenericBreakEven> {
  const p = new URLSearchParams({ months: String(months) })
  if (asOf) p.set("asOf", asOf)
  return getJson<GenericBreakEven>(`${reportsBase()}/break-even?${p.toString()}`)
}

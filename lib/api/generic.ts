// Generic Company API client.
// Wraps the entire /api/generic-company/{farmId}/... surface plus the
// platform-wide /api/business-categories lookup. Same fetch + buildApiUrl +
// getAuthHeaders pattern as the other lib/api/* modules in this project.

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"

// =============================================================================
// Types
// =============================================================================

export interface BusinessCategory {
  businessCategoryId: number
  name: string
  description?: string | null
  sortOrder: number
  isActive: boolean
}

export interface GenericCompanyProfile {
  genericCompanyProfileId: number
  farmId: string
  businessCategoryId?: number | null
  businessCategoryNameSnapshot?: string | null
  businessCategoryName?: string | null
  businessDescription?: string | null
  defaultCurrency: string
  openingCashBalance: number
  businessStartDate?: string | null
  mainLocation?: string | null
  ownerName?: string | null
  phoneNumber?: string | null
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface GenericCompanySetupInput {
  farmId: string
  businessCategoryId?: number | null
  businessDescription?: string | null
  defaultCurrency?: string
  openingCashBalance?: number
  businessStartDate?: string | null
  mainLocation?: string | null
  ownerName?: string | null
  phoneNumber?: string | null
  notes?: string | null
}

export interface GenericCashAccount {
  genericCashAccountId: number
  accountName: string
  accountType: string
  openingBalance: number
  currentBalance: number
  allowNegativeBalance: boolean
  isActive: boolean
  notes?: string | null
}

export interface GenericExpenseCategory {
  genericExpenseCategoryId: number
  name: string
  description?: string | null
  isActive: boolean
}

export interface GenericProduct {
  genericProductId: number
  genericProductCategoryId?: number | null
  categoryName?: string | null
  productName: string
  sku?: string | null
  barcode?: string | null
  unitOfMeasure?: string | null
  costPrice: number
  sellingPrice: number
  wholesalePrice?: number | null
  retailPrice?: number | null
  openingStock: number
  currentStock: number
  minimumStockAlert: number
  trackInventory: boolean
  supplierId?: number | null
  isActive: boolean
  notes?: string | null
}

export interface GenericCustomer {
  genericCustomerId: number
  customerName: string
  customerType: string
  phoneNumber?: string | null
  email?: string | null
  location?: string | null
  address?: string | null
  creditLimit: number
  paymentTermsDays: number
  openingBalance: number
  currentBalance: number
  isActive: boolean
  notes?: string | null
}

export interface GenericCustomerInput {
  customerName: string
  customerType: string
  phoneNumber?: string | null
  email?: string | null
  location?: string | null
  address?: string | null
  creditLimit: number
  paymentTermsDays: number
  openingBalance: number
  isActive: boolean
  notes?: string | null
}

export interface GenericSupplier {
  genericSupplierId: number
  supplierName: string
  supplierType: string
  phoneNumber?: string | null
  email?: string | null
  location?: string | null
  address?: string | null
  paymentTermsDays: number
  openingBalance: number
  currentBalance: number
  isActive: boolean
  notes?: string | null
}

export type GenericSupplierInput = Omit<
  GenericSupplier,
  "genericSupplierId" | "currentBalance"
>

export interface GenericSaleItem {
  genericSaleItemId?: number
  itemType: "Product" | "Service"
  genericProductId?: number | null
  genericServiceId?: number | null
  description?: string | null
  quantity: number
  unitPrice: number
  discountAmount: number
  lineTotal?: number
  costAmount?: number | null
  notes?: string | null
}

export interface GenericSale {
  genericSaleId: number
  saleDate: string
  genericCustomerId?: number | null
  customerName?: string | null
  salesType: string
  salesChannel?: string | null
  subtotalAmount: number
  discountAmount: number
  taxAmount: number
  totalAmount: number
  amountPaid: number
  balance: number
  paymentStatus: string
  paymentMethod?: string | null
  genericCashAccountId?: number | null
  receiptNumber?: string | null
  status: "Draft" | "Approved" | "Cancelled" | "Refunded" | string
  notes?: string | null
  createdAt: string
  items: GenericSaleItem[]
}

export interface GenericSaleCreateInput {
  saleDate?: string | null
  genericCustomerId?: number | null
  salesType: string
  salesChannel?: string | null
  headerDiscountAmount: number
  taxAmount: number
  amountPaid: number
  paymentMethod?: string | null
  genericCashAccountId?: number | null
  receiptNumber?: string | null
  notes?: string | null
  items: GenericSaleItem[]
}

export interface GenericPurchase {
  genericPurchaseId: number
  genericSupplierId?: number | null
  supplierName?: string | null
  purchaseDate: string
  totalAmount: number
  amountPaid: number
  balance: number
  paymentStatus: string
  paymentMethod?: string | null
  invoiceNumber?: string | null
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
  createdAt: string
}

export interface GenericExpense {
  genericExpenseId: number
  expenseDate: string
  genericExpenseCategoryId: number
  categoryName?: string | null
  genericSupplierId?: number | null
  supplierName?: string | null
  description?: string | null
  amount: number
  paidTo?: string | null
  paymentMethod: string
  status: "Draft" | "Submitted" | "Approved" | "Rejected" | "Cancelled" | string
  notes?: string | null
  createdAt: string
}

export interface GenericDailyClosing {
  genericDailyClosingId: number
  closingDate: string
  openingCash: number
  totalSales: number
  totalExpenses: number
  totalCustomerPayments: number
  totalSupplierPayments: number
  totalPurchasesPaid: number
  totalCashIn: number
  totalCashOut: number
  expectedCash: number
  actualCashCounted: number
  cashDifference: number
  creditSales: number
  customerDebtTotal: number
  supplierDebtTotal: number
  inventoryAdjustmentsCount: number
  managerNotes?: string | null
  differenceReason?: string | null
  status: "Draft" | "Submitted" | "Approved" | "Rejected" | string
  createdAt: string
}

export interface GenericDailyClosingCreateInput {
  closingDate: string
  openingCash?: number | null
  actualCashCounted: number
  managerNotes?: string | null
  differenceReason?: string | null
}

// Dashboard bundle
export interface GenericDashboard {
  today: {
    todaySales: number
    todayExpenses: number
    todayPurchasesPaid: number
    todayGrossProfit: number
    yesterdaySales: number
    cashAtHand: number
    inventoryValue: number
    customerDebt: number
    supplierDebt: number
  }
  week: {
    weekSales: number
    weekExpenses: number
    weekPurchasesPaid: number
    weekGrossProfit: number
    topSellingItem?: string | null
    topSellingQuantity: number
    topExpenseCategory?: string | null
    topExpenseAmount: number
  }
  cashAccounts: Array<{
    genericCashAccountId: number
    accountName: string
    accountType: string
    currentBalance: number
    isActive: boolean
  }>
  alerts: {
    lowStockCount: number
    draftSalesCount: number
    draftExpensesCount: number
    customersOwingCount: number
    suppliersOwedCount: number
    pendingClosingsCount: number
  }
}

// =============================================================================
// Helpers
// =============================================================================

function farmBase(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return `/generic-company/${encodeURIComponent(farmId)}`
}

// Backend models have `[Required] FarmId` even though the controller already
// gets farmId from the route. Model validation runs BEFORE the action body
// (where the controller could copy it from route), so requests without
// farmId in the body fail with 400 "Company ID is required" before the
// controller ever sees them. Wrap every POST body with farmId so this
// validation passes. Cleaner long-term fix would be removing [Required]
// from FarmId in models that get it from route, but that's a backend refactor.
function withFarmId<T extends object>(input: T): T & { farmId: string } {
  const { farmId } = getUserContext()
  return { ...input, farmId }
}

// Mirror of lib/api/water.ts → explainHttpError. We parse the Farm API's
// GlobalExceptionMiddleware JSON ({ message, hint, sqlNumber, ... }) and
// surface just the `.message` so toasts show "Customer payment cannot be
// approved from status Cancelled" instead of "POST /Generic/... -> 500".
function explainHttpError(method: string, endpoint: string, status: number, body: string): string {
  if (!body) return `${method} ${endpoint} → HTTP ${status}`
  let parsed: any = null
  try { parsed = JSON.parse(body) } catch { /* not JSON */ }
  if (parsed) {
    if (typeof parsed.message === "string" && parsed.message) return parsed.message
    if (typeof parsed.detail === "string"  && parsed.detail)  return parsed.detail
    if (typeof parsed.title === "string"   && parsed.title)   return parsed.title
    if (typeof parsed.error === "string"   && parsed.error)   return parsed.error
    if (parsed.errors && typeof parsed.errors === "object") {
      const lines: string[] = []
      for (const k of Object.keys(parsed.errors)) {
        const v = parsed.errors[k]
        lines.push(`${k}: ${Array.isArray(v) ? v.join(", ") : String(v)}`)
      }
      if (lines.length) return lines.join(" · ")
    }
  }
  const trimmed = body.trim().replace(/\s+/g, " ")
  return trimmed.length > 400 ? trimmed.slice(0, 400) + "…" : trimmed
}

async function getJson<T>(endpoint: string): Promise<T> {
  const url = buildApiUrl(endpoint)
  const r = await fetch(url, { method: "GET", headers: getAuthHeaders() })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("GET", endpoint, r.status, text))
  }
  return (await r.json()) as T
}

async function postJson<T>(endpoint: string, body: unknown): Promise<T | null> {
  const url = buildApiUrl(endpoint)
  const r = await fetch(url, {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify(body ?? {}),
  })
  if (r.status === 204) return null
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("POST", endpoint, r.status, text))
  }
  const txt = await r.text()
  return txt ? (JSON.parse(txt) as T) : null
}

async function putJson<T>(endpoint: string, body: unknown): Promise<T | null> {
  const url = buildApiUrl(endpoint)
  const r = await fetch(url, {
    method: "PUT",
    headers: getAuthHeaders(),
    body: JSON.stringify(body ?? {}),
  })
  if (r.status === 204) return null
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("PUT", endpoint, r.status, text))
  }
  const txt = await r.text()
  return txt ? (JSON.parse(txt) as T) : null
}

async function deleteResource(endpoint: string): Promise<void> {
  const url = buildApiUrl(endpoint)
  const r = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!r.ok && r.status !== 204) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("DELETE", endpoint, r.status, text))
  }
}

// =============================================================================
// Business categories (platform-wide lookup)
// =============================================================================

export async function getBusinessCategories(): Promise<BusinessCategory[]> {
  return getJson<BusinessCategory[]>("/business-categories")
}

// =============================================================================
// Company profile + setup
// =============================================================================

export async function getProfile(): Promise<GenericCompanyProfile | null> {
  try {
    return await getJson<GenericCompanyProfile>(farmBase())
  } catch (e) {
    // 404 means "not set up yet" — fine, caller treats as null.
    if (e instanceof Error && /404/.test(e.message)) return null
    throw e
  }
}

export async function setupProfile(
  input: Omit<GenericCompanySetupInput, "farmId">
): Promise<GenericCompanyProfile | null> {
  const { farmId } = getUserContext()
  return postJson<GenericCompanyProfile>("/generic-company/setup", {
    ...input,
    farmId,
  })
}

export async function updateProfile(
  input: Omit<GenericCompanySetupInput, "farmId">
): Promise<GenericCompanyProfile | null> {
  return putJson<GenericCompanyProfile>(farmBase(), input)
}

// =============================================================================
// Cash accounts
// =============================================================================

export async function getCashAccounts(): Promise<GenericCashAccount[]> {
  return getJson<GenericCashAccount[]>(`${farmBase()}/cash-accounts`)
}

// =============================================================================
// Products
// =============================================================================

export async function getProducts(): Promise<GenericProduct[]> {
  return getJson<GenericProduct[]>(`${farmBase()}/products`)
}

export interface GenericProductInput {
  productName: string
  sku?: string | null
  barcode?: string | null
  unitOfMeasure?: string | null
  costPrice: number
  sellingPrice: number
  wholesalePrice?: number | null
  retailPrice?: number | null
  openingStock: number
  minimumStockAlert: number
  trackInventory: boolean
  genericProductCategoryId?: number | null
  supplierId?: number | null
  isActive: boolean
  notes?: string | null
}

export async function createGenericProduct(input: GenericProductInput): Promise<GenericProduct | null> {
  return postJson<GenericProduct>(`${farmBase()}/products`, withFarmId(input))
}

export async function updateGenericProduct(id: number, input: GenericProductInput): Promise<void> {
  await putJson(`${farmBase()}/products/${id}`, input)
}

export async function deleteGenericProduct(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/products/${id}`)
}

// =============================================================================
// Customers + customer payments
// =============================================================================

export async function getCustomers(): Promise<GenericCustomer[]> {
  return getJson<GenericCustomer[]>(`${farmBase()}/customers`)
}

export async function getCustomer(id: number): Promise<GenericCustomer | null> {
  try {
    return await getJson<GenericCustomer>(`${farmBase()}/customers/${id}`)
  } catch (e) {
    if (e instanceof Error && /404/.test(e.message)) return null
    throw e
  }
}

export async function createCustomer(input: GenericCustomerInput): Promise<GenericCustomer | null> {
  return postJson<GenericCustomer>(`${farmBase()}/customers`, withFarmId(input))
}

export async function updateCustomer(id: number, input: GenericCustomerInput): Promise<void> {
  await putJson(`${farmBase()}/customers/${id}`, withFarmId(input))
}

export async function deleteCustomer(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/customers/${id}`)
}

// =============================================================================
// Suppliers
// =============================================================================

export async function getSuppliers(): Promise<GenericSupplier[]> {
  return getJson<GenericSupplier[]>(`${farmBase()}/suppliers`)
}

export async function getSupplier(id: number): Promise<GenericSupplier | null> {
  try {
    return await getJson<GenericSupplier>(`${farmBase()}/suppliers/${id}`)
  } catch (e) {
    if (e instanceof Error && /404/.test(e.message)) return null
    throw e
  }
}

export async function createSupplier(input: GenericSupplierInput): Promise<GenericSupplier | null> {
  return postJson<GenericSupplier>(`${farmBase()}/suppliers`, withFarmId(input))
}

export async function updateSupplier(id: number, input: GenericSupplierInput): Promise<void> {
  await putJson(`${farmBase()}/suppliers/${id}`, withFarmId(input))
}

export async function deleteSupplier(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/suppliers/${id}`)
}

// =============================================================================
// Sales
// =============================================================================

export async function getSales(status?: string | null): Promise<GenericSale[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericSale[]>(`${farmBase()}/sales${qs}`)
}

export async function getSale(id: number): Promise<GenericSale | null> {
  try {
    return await getJson<GenericSale>(`${farmBase()}/sales/${id}`)
  } catch (e) {
    if (e instanceof Error && /404/.test(e.message)) return null
    throw e
  }
}

export async function createSale(input: GenericSaleCreateInput): Promise<GenericSale | null> {
  return postJson<GenericSale>(`${farmBase()}/sales`, withFarmId(input))
}

export async function approveSale(id: number): Promise<void> {
  await postJson(`${farmBase()}/sales/${id}/approve`, {})
}

export async function cancelSale(id: number, reason?: string): Promise<void> {
  await postJson(`${farmBase()}/sales/${id}/cancel`, { reason })
}

export async function refundSale(id: number, reason?: string): Promise<void> {
  await postJson(`${farmBase()}/sales/${id}/refund`, { reason })
}

// =============================================================================
// Purchases
// =============================================================================

export async function getPurchases(status?: string | null): Promise<GenericPurchase[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericPurchase[]>(`${farmBase()}/purchases${qs}`)
}

export async function approvePurchase(id: number): Promise<void> {
  await postJson(`${farmBase()}/purchases/${id}/approve`, {})
}

export async function cancelPurchase(id: number, reason?: string): Promise<void> {
  await postJson(`${farmBase()}/purchases/${id}/cancel`, { reason })
}

// =============================================================================
// Expenses
// =============================================================================

export async function getExpenses(status?: string | null): Promise<GenericExpense[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericExpense[]>(`${farmBase()}/expenses${qs}`)
}

export async function approveExpense(id: number): Promise<void> {
  await postJson(`${farmBase()}/expenses/${id}/approve`, {})
}

// =============================================================================
// Daily Closings
// =============================================================================

export async function getDailyClosings(): Promise<GenericDailyClosing[]> {
  return getJson<GenericDailyClosing[]>(`${farmBase()}/daily-closings`)
}

export async function createDailyClosing(
  input: GenericDailyClosingCreateInput
): Promise<GenericDailyClosing | null> {
  return postJson<GenericDailyClosing>(`${farmBase()}/daily-closings`, withFarmId(input))
}

export async function submitDailyClosing(id: number): Promise<GenericDailyClosing | null> {
  return postJson<GenericDailyClosing>(`${farmBase()}/daily-closings/${id}/submit`, {})
}

export async function approveDailyClosing(id: number): Promise<void> {
  await postJson(`${farmBase()}/daily-closings/${id}/approve`, {})
}

// =============================================================================
// Dashboard + reports
// =============================================================================

export async function getDashboard(): Promise<GenericDashboard> {
  return getJson<GenericDashboard>(`${farmBase()}/reports/dashboard`)
}

// =============================================================================
// Part 2: extended types
// =============================================================================

export interface GenericExpenseCategory {
  genericExpenseCategoryId: number
  name: string
  description?: string | null
  isActive: boolean
}

export interface GenericPurchaseItem {
  genericProductId: number
  description?: string | null
  quantity: number
  unitCost: number
  discountAmount: number
  notes?: string | null
}

export interface GenericPurchaseCreateInput {
  purchaseDate?: string | null
  genericSupplierId?: number | null
  headerDiscountAmount: number
  taxAmount: number
  amountPaid: number
  paymentMethod?: string | null
  genericCashAccountId?: number | null
  invoiceNumber?: string | null
  notes?: string | null
  items: GenericPurchaseItem[]
}

export interface GenericExpenseCreateInput {
  expenseDate?: string | null
  genericExpenseCategoryId: number
  genericSupplierId?: number | null
  description?: string | null
  amount: number
  paidTo?: string | null
  paymentMethod: string
  genericCashAccountId?: number | null
  notes?: string | null
}

export interface GenericCustomerPayment {
  genericCustomerPaymentId: number
  genericCustomerId: number
  customerName?: string | null
  paymentDate: string
  amount: number
  paymentMethod: string
  genericCashAccountId?: number | null
  linkedSaleId?: number | null
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
  createdAt: string
}

export interface GenericCustomerPaymentCreateInput {
  genericCustomerId: number
  amount: number
  paymentMethod: string
  genericCashAccountId?: number | null
  linkedSaleId?: number | null
  paymentDate?: string | null
  notes?: string | null
}

export interface GenericSupplierPayment {
  genericSupplierPaymentId: number
  genericSupplierId: number
  supplierName?: string | null
  paymentDate: string
  amount: number
  paymentMethod: string
  genericCashAccountId?: number | null
  linkedPurchaseId?: number | null
  linkedExpenseId?: number | null
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
  createdAt: string
}

export interface GenericSupplierPaymentCreateInput {
  genericSupplierId: number
  amount: number
  paymentMethod: string
  genericCashAccountId?: number | null
  linkedPurchaseId?: number | null
  linkedExpenseId?: number | null
  paymentDate?: string | null
  notes?: string | null
}

export interface GenericCashTransfer {
  genericCashTransferId: number
  fromGenericCashAccountId: number
  fromAccountName?: string | null
  toGenericCashAccountId: number
  toAccountName?: string | null
  transferDate: string
  amount: number
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
  createdAt: string
}

export interface GenericCashTransferCreateInput {
  fromGenericCashAccountId: number
  toGenericCashAccountId: number
  amount: number
  transferDate?: string | null
  notes?: string | null
}

export interface GenericStockAdjustment {
  genericStockAdjustmentId: number
  genericProductId: number
  productName?: string | null
  adjustmentDate: string
  adjustmentType: "Increase" | "Decrease" | string
  quantity: number
  reason: string
  status: "Draft" | "Submitted" | "Approved" | "Rejected" | string
  rejectionReason?: string | null
  notes?: string | null
  createdAt: string
}

export interface GenericStockAdjustmentCreateInput {
  genericProductId: number
  adjustmentType: "Increase" | "Decrease"
  quantity: number
  reason: string
  adjustmentDate?: string | null
  notes?: string | null
}

export interface GenericCustomerLedgerEntry {
  genericCustomerLedgerId: number
  transactionDate: string
  transactionType: string
  saleId?: number | null
  paymentId?: number | null
  debitAmount: number
  creditAmount: number
  balanceAfterTransaction: number
  description?: string | null
  createdAt: string
}

export interface GenericSupplierLedgerEntry {
  genericSupplierLedgerId: number
  transactionDate: string
  transactionType: string
  purchaseId?: number | null
  expenseId?: number | null
  paymentId?: number | null
  debitAmount: number
  creditAmount: number
  balanceAfterTransaction: number
  description?: string | null
  createdAt: string
}

export interface GenericPeriodPnL {
  periodStart: string
  periodEnd: string
  totalIncome: number
  totalExpenses: number
  costOfGoodsSold: number
  grossProfit: number
  netProfit: number
  profitMarginPct: number
  totalPurchasesPaid: number
  salesCount: number
}

export interface GenericSalesByProductRow {
  genericProductId?: number | null
  productName: string
  sku?: string | null
  totalQuantity: number
  totalRevenue: number
  totalCost: number
  salesCount: number
}

export interface GenericSalesByCustomerRow {
  genericCustomerId?: number | null
  customerName: string
  phoneNumber?: string | null
  salesCount: number
  totalRevenue: number
  totalPaid: number
  totalOutstanding: number
}

export interface GenericExpenseByCategoryRow {
  genericExpenseCategoryId: number
  categoryName: string
  expenseCount: number
  totalAmount: number
}

export interface GenericInventoryValueRow {
  genericProductCategoryId?: number | null
  categoryName: string
  productCount: number
  totalUnits: number
  totalCostValue: number
  totalRetailValue: number
}

export interface GenericInventoryValueReport {
  byCategory: GenericInventoryValueRow[]
  totalCostValue: number
  totalRetailValue: number
  productCount: number
}

export interface GenericCashSummaryRow {
  genericCashAccountId: number
  accountName: string
  accountType: string
  currentBalance: number
  periodCashIn: number
  periodCashOut: number
  isActive: boolean
}

export interface GenericCashSummaryReport {
  accounts: GenericCashSummaryRow[]
  totalCashAtHand: number
}

// =============================================================================
// Part 2: expense categories
// =============================================================================

export async function getExpenseCategories(): Promise<GenericExpenseCategory[]> {
  return getJson<GenericExpenseCategory[]>(`${farmBase()}/expense-categories`)
}

// =============================================================================
// Part 2: purchase create
// =============================================================================

export async function createPurchase(
  input: GenericPurchaseCreateInput
): Promise<GenericPurchase | null> {
  return postJson<GenericPurchase>(`${farmBase()}/purchases`, withFarmId(input))
}

// =============================================================================
// Part 2: expense create
// =============================================================================

export async function createExpense(
  input: GenericExpenseCreateInput
): Promise<GenericExpense | null> {
  return postJson<GenericExpense>(`${farmBase()}/expenses`, withFarmId(input))
}

// =============================================================================
// Part 2: customer payments
// =============================================================================

export async function getCustomerPayments(status?: string | null): Promise<GenericCustomerPayment[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericCustomerPayment[]>(`${farmBase()}/customer-payments${qs}`)
}

export async function createCustomerPayment(
  input: GenericCustomerPaymentCreateInput
): Promise<GenericCustomerPayment | null> {
  return postJson<GenericCustomerPayment>(`${farmBase()}/customer-payments`, withFarmId(input))
}

export async function approveCustomerPayment(id: number): Promise<void> {
  await postJson(`${farmBase()}/customer-payments/${id}/approve`, {})
}

export async function cancelCustomerPayment(id: number): Promise<void> {
  await postJson(`${farmBase()}/customer-payments/${id}/cancel`, {})
}

// =============================================================================
// Part 2: supplier payments
// =============================================================================

export async function getSupplierPayments(status?: string | null): Promise<GenericSupplierPayment[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericSupplierPayment[]>(`${farmBase()}/supplier-payments${qs}`)
}

export async function createSupplierPayment(
  input: GenericSupplierPaymentCreateInput
): Promise<GenericSupplierPayment | null> {
  return postJson<GenericSupplierPayment>(`${farmBase()}/supplier-payments`, withFarmId(input))
}

export async function approveSupplierPayment(id: number): Promise<void> {
  await postJson(`${farmBase()}/supplier-payments/${id}/approve`, {})
}

export async function cancelSupplierPayment(id: number): Promise<void> {
  await postJson(`${farmBase()}/supplier-payments/${id}/cancel`, {})
}

// =============================================================================
// Part 2: cash transfers
// =============================================================================

export async function getCashTransfers(status?: string | null): Promise<GenericCashTransfer[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericCashTransfer[]>(`${farmBase()}/cash-transfers${qs}`)
}

export async function createCashTransfer(
  input: GenericCashTransferCreateInput
): Promise<GenericCashTransfer | null> {
  return postJson<GenericCashTransfer>(`${farmBase()}/cash-transfers`, withFarmId(input))
}

export async function approveCashTransfer(id: number): Promise<void> {
  await postJson(`${farmBase()}/cash-transfers/${id}/approve`, {})
}

export async function cancelCashTransfer(id: number): Promise<void> {
  await postJson(`${farmBase()}/cash-transfers/${id}/cancel`, {})
}

// =============================================================================
// Part 2: stock adjustments
// =============================================================================

export async function getStockAdjustments(status?: string | null): Promise<GenericStockAdjustment[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericStockAdjustment[]>(`${farmBase()}/inventory/adjustments${qs}`)
}

export async function createStockAdjustment(
  input: GenericStockAdjustmentCreateInput
): Promise<GenericStockAdjustment | null> {
  return postJson<GenericStockAdjustment>(`${farmBase()}/inventory/adjustments`, withFarmId(input))
}

export async function submitStockAdjustment(id: number): Promise<void> {
  await postJson(`${farmBase()}/inventory/adjustments/${id}/submit`, {})
}

export async function approveStockAdjustment(id: number): Promise<void> {
  await postJson(`${farmBase()}/inventory/adjustments/${id}/approve`, {})
}

export async function rejectStockAdjustment(id: number, rejectionReason: string): Promise<void> {
  await postJson(`${farmBase()}/inventory/adjustments/${id}/reject`, { rejectionReason })
}

// =============================================================================
// Part 2: ledgers
// =============================================================================

export async function getCustomerLedger(customerId: number): Promise<GenericCustomerLedgerEntry[]> {
  return getJson<GenericCustomerLedgerEntry[]>(`${farmBase()}/customers/${customerId}/ledger`)
}

export async function getSupplierLedger(supplierId: number): Promise<GenericSupplierLedgerEntry[]> {
  return getJson<GenericSupplierLedgerEntry[]>(`${farmBase()}/suppliers/${supplierId}/ledger`)
}

// =============================================================================
// Part 2: reports
// =============================================================================

export async function getPeriodPnL(fromDate: string, toDate: string): Promise<GenericPeriodPnL> {
  return getJson<GenericPeriodPnL>(
    `${farmBase()}/reports/period-pnl?fromDate=${encodeURIComponent(fromDate)}&toDate=${encodeURIComponent(toDate)}`
  )
}

export async function getSalesByProductReport(fromDate: string, toDate: string): Promise<GenericSalesByProductRow[]> {
  return getJson<GenericSalesByProductRow[]>(
    `${farmBase()}/reports/sales-by-product?fromDate=${encodeURIComponent(fromDate)}&toDate=${encodeURIComponent(toDate)}`
  )
}

export async function getSalesByCustomerReport(fromDate: string, toDate: string): Promise<GenericSalesByCustomerRow[]> {
  return getJson<GenericSalesByCustomerRow[]>(
    `${farmBase()}/reports/sales-by-customer?fromDate=${encodeURIComponent(fromDate)}&toDate=${encodeURIComponent(toDate)}`
  )
}

export async function getExpensesByCategoryReport(fromDate: string, toDate: string): Promise<GenericExpenseByCategoryRow[]> {
  return getJson<GenericExpenseByCategoryRow[]>(
    `${farmBase()}/reports/expenses-by-category?fromDate=${encodeURIComponent(fromDate)}&toDate=${encodeURIComponent(toDate)}`
  )
}

export async function getInventoryValueReport(): Promise<GenericInventoryValueReport> {
  return getJson<GenericInventoryValueReport>(`${farmBase()}/reports/inventory-value`)
}

export async function getCashSummaryReport(fromDate: string, toDate: string): Promise<GenericCashSummaryReport> {
  return getJson<GenericCashSummaryReport>(
    `${farmBase()}/reports/cash-summary?fromDate=${encodeURIComponent(fromDate)}&toDate=${encodeURIComponent(toDate)}`
  )
}

// =============================================================================
// Phase 6: Staff + Attendance + Payroll (spec §13, §14)
// =============================================================================

export type GenericStaffRole =
  | "Owner" | "Manager" | "Accountant" | "Cashier" | "Salesperson"
  | "InventoryOfficer" | "Cleaner" | "Security" | "Driver" | "ServiceProvider" | "Other"

export type GenericStaffSalaryType = "Daily" | "Weekly" | "Monthly" | "Commission" | "Mixed"

export type GenericAttendanceStatus = "Present" | "Absent" | "Late" | "HalfDay" | "OffDay"

export type GenericPayrollStatus = "Draft" | "Approved" | "Paid" | "Cancelled"

export interface GenericStaff {
  genericStaffId: number
  farmId: string
  firstName: string
  lastName: string
  phoneNumber?: string | null
  email?: string | null
  role: GenericStaffRole | string
  salaryType: GenericStaffSalaryType | string
  basePay: number
  commissionRate?: number | null
  branchId?: number | null
  isActive: boolean
  isDeleted: boolean
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface GenericStaffInput {
  firstName: string
  lastName: string
  phoneNumber?: string | null
  email?: string | null
  role: GenericStaffRole | string
  salaryType: GenericStaffSalaryType | string
  basePay: number
  commissionRate?: number | null
  branchId?: number | null
  isActive: boolean
  notes?: string | null
}

export interface GenericStaffAttendance {
  genericStaffAttendanceId: number
  farmId: string
  genericStaffId: number
  staffName?: string | null
  staffRole?: string | null
  attendanceDate: string
  clockIn?: string | null
  clockOut?: string | null
  shift?: string | null
  status: GenericAttendanceStatus | string
  notes?: string | null
  createdBy?: string | null
  createdAt: string
}

export interface GenericStaffAttendanceUpsertInput {
  genericStaffId: number
  attendanceDate: string  // ISO date (YYYY-MM-DD)
  clockIn?: string | null
  clockOut?: string | null
  shift?: string | null
  status: GenericAttendanceStatus | string
  notes?: string | null
}

export interface GenericPayrollItem {
  genericPayrollItemId: number
  genericPayrollRunId: number
  genericStaffId: number
  staffName?: string | null
  staffRole?: string | null
  basicPay: number
  dailyWage: number
  commission: number
  bonus: number
  deductions: number
  netPay: number
  paymentMethod?: string | null
  notes?: string | null
  createdAt: string
}

export interface GenericPayrollRun {
  genericPayrollRunId: number
  farmId: string
  periodStart: string
  periodEnd: string
  payDate?: string | null
  totalGrossPay: number
  totalDeductions: number
  totalNetPay: number
  status: GenericPayrollStatus | string
  genericCashAccountId?: number | null
  cashAccountName?: string | null
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  paidBy?: string | null
  paidAt?: string | null
  createdAt: string
  updatedAt?: string | null
  items: GenericPayrollItem[]
}

export interface GenericPayrollRunCreateInput {
  periodStart: string  // ISO date
  periodEnd: string    // ISO date
  payDate?: string | null
  genericCashAccountId?: number | null
  notes?: string | null
}

export interface GenericPayrollRunUpdateInput {
  periodStart: string
  periodEnd: string
  payDate?: string | null
  genericCashAccountId?: number | null
  notes?: string | null
}

export interface GenericPayrollItemUpsertInput {
  genericStaffId: number
  basicPay: number
  dailyWage: number
  commission: number
  bonus: number
  deductions: number
  paymentMethod?: string | null
  notes?: string | null
}

// --------- Staff CRUD

export async function getStaff(role?: string | null): Promise<GenericStaff[]> {
  const qs = role ? `?role=${encodeURIComponent(role)}` : ""
  return getJson<GenericStaff[]>(`${farmBase()}/staff${qs}`)
}

export async function getStaffMember(id: number): Promise<GenericStaff | null> {
  try {
    return await getJson<GenericStaff>(`${farmBase()}/staff/${id}`)
  } catch (e) {
    if (e instanceof Error && /404/.test(e.message)) return null
    throw e
  }
}

export async function createStaff(input: GenericStaffInput): Promise<GenericStaff | null> {
  return postJson<GenericStaff>(`${farmBase()}/staff`, withFarmId(input))
}

export async function updateStaff(id: number, input: GenericStaffInput): Promise<void> {
  await putJson(`${farmBase()}/staff/${id}`, input)
}

export async function deleteStaff(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/staff/${id}`)
}

// --------- Attendance

export async function getAttendance(params?: {
  staffId?: number
  fromDate?: string
  toDate?: string
}): Promise<GenericStaffAttendance[]> {
  const qs = new URLSearchParams()
  if (params?.staffId != null) qs.set("staffId", String(params.staffId))
  if (params?.fromDate) qs.set("fromDate", params.fromDate)
  if (params?.toDate)   qs.set("toDate",   params.toDate)
  const query = qs.toString() ? `?${qs.toString()}` : ""
  return getJson<GenericStaffAttendance[]>(`${farmBase()}/staff-attendance${query}`)
}

export async function upsertAttendance(input: GenericStaffAttendanceUpsertInput): Promise<GenericStaffAttendance | null> {
  return postJson<GenericStaffAttendance>(`${farmBase()}/staff-attendance`, withFarmId(input))
}

export async function deleteAttendance(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/staff-attendance/${id}`)
}

// --------- Payroll Runs + Items

export async function getPayrollRuns(status?: string | null): Promise<GenericPayrollRun[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericPayrollRun[]>(`${farmBase()}/payroll-runs${qs}`)
}

export async function getPayrollRun(id: number): Promise<GenericPayrollRun | null> {
  try {
    return await getJson<GenericPayrollRun>(`${farmBase()}/payroll-runs/${id}`)
  } catch (e) {
    if (e instanceof Error && /404/.test(e.message)) return null
    throw e
  }
}

export async function createPayrollRun(
  input: GenericPayrollRunCreateInput
): Promise<{ genericPayrollRunId: number } | null> {
  return postJson<{ genericPayrollRunId: number }>(`${farmBase()}/payroll-runs`, input)
}

export async function updatePayrollRun(id: number, input: GenericPayrollRunUpdateInput): Promise<void> {
  await putJson(`${farmBase()}/payroll-runs/${id}`, input)
}

export async function upsertPayrollItem(
  runId: number,
  input: GenericPayrollItemUpsertInput
): Promise<GenericPayrollItem | null> {
  return postJson<GenericPayrollItem>(`${farmBase()}/payroll-runs/${runId}/items`, input)
}

export async function deletePayrollItem(itemId: number): Promise<void> {
  await deleteResource(`${farmBase()}/payroll-runs/items/${itemId}`)
}

export async function approvePayrollRun(id: number): Promise<void> {
  await postJson(`${farmBase()}/payroll-runs/${id}/approve`, {})
}

export async function markPayrollRunPaid(id: number, payDate?: string): Promise<void> {
  await postJson(`${farmBase()}/payroll-runs/${id}/mark-paid`, payDate ? { payDate } : {})
}

export async function cancelPayrollRun(id: number, reason?: string): Promise<void> {
  await postJson(`${farmBase()}/payroll-runs/${id}/cancel`, reason ? { reason } : {})
}

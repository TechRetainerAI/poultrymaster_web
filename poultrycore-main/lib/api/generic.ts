// Generic Company API client.
// Wraps the entire /api/generic-company/{farmId}/... surface plus the
// platform-wide /api/business-categories lookup. Same fetch + buildApiUrl +
// getAuthHeaders pattern as the other lib/api/* modules in this project.

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

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
  /** Rich item description, separate from operational Notes (migration 441). */
  description?: string | null
  unitOfMeasure?: string | null
  /** Unit used when purchasing, e.g. "bag" (migration 441). */
  purchaseUnit?: string | null
  /** Unit used when selling, e.g. "piece" (migration 441). */
  salesUnit?: string | null
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
  /** Optional expiry/best-before date (migration 363). Null = no expiry. */
  expiryDate?: string | null
  /** Whether this product tracks expiry dates (migration 363). */
  trackExpiry?: boolean
  /** Product = things you sell, SupplyItem = things you use internally (migration 440). */
  itemType?: "Product" | "SupplyItem"
  /** Whether this item can be sold to customers (migration 441). */
  canSell?: boolean
  /** Whether this item can be consumed or produced in production workflows (migration 441). */
  canUseInProduction?: boolean
  /** Whether this item can be used for internal consumption (migration 441). */
  canUseInternally?: boolean
  /** User who last updated this item (migration 441). */
  updatedBy?: string | null
  createdBy?: string | null
  createdAt?: string | null
  updatedAt?: string | null
  /** Product image URL or base64 data URL (migration 492). */
  imageUrl?: string | null
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
  // Student extension fields (migration 365) — nullable, only for schools
  dateOfBirth?: string | null
  admissionNumber?: string | null
  classOrGrade?: string | null
  guardianName?: string | null
  guardianPhone?: string | null
  guardianEmail?: string | null
  enrollmentDate?: string | null
  gender?: string | null
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
  // Student extension fields (migration 365)
  dateOfBirth?: string | null
  admissionNumber?: string | null
  classOrGrade?: string | null
  guardianName?: string | null
  guardianPhone?: string | null
  guardianEmail?: string | null
  enrollmentDate?: string | null
  gender?: string | null
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
  saleUnit?: string | null
  unitFactor?: number
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
  /** 484: set when the sale was reversed (its status is then "Cancelled"). List only. */
  saleReversalId?: number | null
  /** 485: on a correcting sale, the reversed sale it replaces. List only. */
  correctsSaleId?: number | null
  /** 485: on a reversed sale, the live sale that corrects it; null = it can still be reposted. List only. */
  correctedBySaleId?: number | null
  items: GenericSaleItem[]
}

export interface GenericSaleCreateInput {
  /**
   * 483 Projects & Contracts: optional, saved in the same statement as this
   * transaction. Leave it out to keep the old behaviour exactly.
   */
  projects?: import("@/lib/api/generic-projects").ProjectAssignment
  /** 485: Correct sale / Edit & repost -- the reversed sale this one replaces. */
  correctsSaleId?: number | null
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
  applyCreditAmount?: number
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
  // 448: payment state, as on Poultry Expenses. amountPaid is what has been
  // paid so far (resolved); balance = amount - amountPaid.
  genericCashAccountId?: number | null
  receiptUrl?: string | null
  cashAccountName?: string | null
  amountPaid?: number | null
  dueDate?: string | null
  paymentStatus?: "Paid" | "PartiallyPaid" | "Unpaid" | "NonCash" | string | null
  sourceType?: string | null
  /** What supplier payments have applied; while > 0 the money is locked. */
  paymentsApplied?: number | null
  rejectionReason?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
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
    body: JSON.stringify(withFarmId((body ?? {}) as object)),
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
    body: JSON.stringify(withFarmId((body ?? {}) as object)),
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

/**
 * A manual adjustment on one cash account (signed amount, reason required).
 * Moves the account's balance -- the Generic twin of Poultry's
 * adjustPoultryCashAccount, used by Cash Flow's "Add adjustment" (Report 40).
 */
export async function adjustCashAccount(accountId: number, input: {
  amount: number; reason: string; transactionDate?: string | null
}): Promise<void> {
  await postJson(`${farmBase()}/cash/adjustments`, {
    genericCashAccountId: accountId, amount: input.amount, reason: input.reason,
    transactionDate: input.transactionDate ?? null,
  })
}

export async function createCashAccount(input: {
  accountName: string; accountType: string; openingBalance: number;
  allowNegativeBalance: boolean; notes?: string | null
}): Promise<GenericCashAccount | null> {
  // Report 40 Part 9: the policy is what the server reads; send it with the bit.
  return postJson<GenericCashAccount>(`${farmBase()}/cash-accounts`, withFarmId({
    ...input, negativeBalancePolicy: input.allowNegativeBalance ? "AlwaysAllow" : "DoNotAllow",
  }))
}

export async function updateCashAccount(id: number, input: {
  accountName: string; accountType: string;
  allowNegativeBalance: boolean; isActive: boolean; notes?: string | null
}): Promise<void> {
  await putJson(`${farmBase()}/cash-accounts/${id}`, withFarmId({
    ...input, negativeBalancePolicy: input.allowNegativeBalance ? "AlwaysAllow" : "DoNotAllow",
  }))
}

export async function deleteCashAccount(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/cash-accounts/${id}`)
}

export interface GenericCashTransaction {
  genericCashTransactionId: number
  genericCashAccountId: number
  accountName?: string | null
  transactionDate: string
  transactionType: string
  sourceType?: string | null
  amount: number
  description?: string | null
}

export async function listCashTransactions(params?: { cashAccountId?: number }): Promise<GenericCashTransaction[]> {
  const path = params?.cashAccountId
    ? `${farmBase()}/cash/accounts/${params.cashAccountId}/transactions`
    : `${farmBase()}/cash/transactions`
  return getJson<GenericCashTransaction[]>(path)
}

// =============================================================================
// Cash reconciliation
// =============================================================================

export interface GenericCashReconciliation {
  genericCashReconciliationId: number
  farmId: string
  genericCashAccountId: number
  accountName?: string | null
  reconciliationDate: string
  systemBalance: number
  /** Null while a draft has no figure; 0 is a real count. */
  actualBalance: number | null
  difference: number
  adjustmentTransactionId?: number | null
  reason?: string | null
  notes?: string | null
  /** Draft | Posted | Reversed (migration 456). */
  status: "Draft" | "Posted" | "Reversed" | string
  requestedBy?: string | null
  approvedBy?: string | null
  createdAt: string
  accountType?: string | null
  referenceNo?: string | null
  systemBalanceCached?: number | null
  reversalTransactionId?: number | null
  createdBy?: string | null
  updatedAt?: string | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

/** Per-account figures for the Reconciliation page (Poultry's account-status). */
export interface GenericCashAccountCountStatus {
  genericCashAccountId: number
  accountName: string
  accountType?: string | null
  isActive: boolean
  currentBalance: number
  /** Ledger truth: the sum of the account's transactions. */
  ledgerBalance: number
  cacheDrift: number
  lastReconciledAt?: string | null
  lastReconciledBalance?: number | null
  daysSinceReconciled?: number | null
  /** Entries dated after the last posted count (Generic has no per-entry clearing). */
  unclearedCount: number
  unclearedAmount: number
  openDraftId?: number | null
}

export interface GenericCashAccountDetails {
  genericCashAccountId: number
  farmId: string
  accountName: string
  accountType: string
  openingBalance: number
  currentBalance: number
  negativeBalancePolicy: string
  negativeBalanceLimit: number
  isActive: boolean
  lastReconciledAt?: string | null
  lastReconciledBalance?: number | null
  totalMoneyIn: number
  totalMoneyOut: number
  transferIn: number
  transferOut: number
  totalAdjustments: number
  ledgerBalance: number
  unreconciledCount: number
}

export async function getCashAccountDetails(accountId: number): Promise<GenericCashAccountDetails | null> {
  return getJson<GenericCashAccountDetails>(`${farmBase()}/cash/accounts/${accountId}/details`)
}

export async function getCashReconciliations(accountId: number): Promise<GenericCashReconciliation[]> {
  return getJson<GenericCashReconciliation[]>(`${farmBase()}/cash/accounts/${accountId}/reconciliations`)
}

export async function createCashReconciliation(input: {
  genericCashAccountId: number
  actualBalance: number
  reconciliationDate?: string | null
  reason?: string | null
  notes?: string | null
}): Promise<{ genericCashReconciliationId: number } | null> {
  const { userId } = getUserContext()
  const q = new URLSearchParams()
  if (userId) { q.set("requestedBy", userId); q.set("approvedBy", userId) }
  return postJson<{ genericCashReconciliationId: number }>(
    `${farmBase()}/cash/reconciliations?${q.toString()}`, input)
}

function byParam(name: string): string {
  const { userId } = getUserContext()
  return userId ? `?${name}=${encodeURIComponent(userId)}` : ""
}

export async function getCashAccountCountStatus(): Promise<GenericCashAccountCountStatus[]> {
  return getJson<GenericCashAccountCountStatus[]>(`${farmBase()}/cash/reconciliations/account-status`)
}

export interface GenericCashCountInput {
  reconciliationDate?: string | null
  actualBalance?: number | null
  reason?: string | null
  notes?: string | null
}

/** Save a DRAFT count. Moves no money; post it with postCashCount. */
export async function createCashCount(input: GenericCashCountInput & { genericCashAccountId: number }) {
  return postJson<{ genericCashReconciliationId: number }>(
    `${farmBase()}/cash/reconciliations/drafts${byParam("createdBy")}`, input)
}

export async function updateCashCount(id: number, input: GenericCashCountInput & { genericCashAccountId: number }) {
  await putJson(`${farmBase()}/cash/reconciliations/${id}${byParam("updatedBy")}`, input)
}

/** Discard a DRAFT count (nothing was posted, nothing moves). */
export async function deleteCashCount(id: number) {
  await deleteResource(`${farmBase()}/cash/reconciliations/${id}${byParam("userId")}`)
}

/** Post a draft: re-measures against the ledger now; returns the adjustment id, or null when it balanced. */
export async function postCashCount(id: number) {
  return postJson<{ adjustmentTransactionId: number | null }>(
    `${farmBase()}/cash/reconciliations/${id}/post${byParam("postedBy")}`, {})
}

/** Reverse a POSTED count: an opposite adjustment, the original kept. */
export async function reverseCashCount(id: number, reason: string) {
  await postJson(`${farmBase()}/cash/reconciliations/${id}/reverse${byParam("reversedBy")}`, { reason })
}

/**
 * Recalculate: rebuild every cash account's stored balance from its
 * transactions. Moves no money (Poultry's reconcilePoultryCashBalances).
 */
export async function recalculateCashBalances(): Promise<{ updated: number } | null> {
  return postJson<{ updated: number }>(`${farmBase()}/cash/accounts/reconcile-balances`, {})
}

// =============================================================================
// Products
// =============================================================================

// =============================================================================
// Product Categories
// =============================================================================

export interface GenericProductCategory {
  genericProductCategoryId: number
  farmId: string
  name: string
  description?: string | null
  isActive: boolean
}

export async function getProductCategories(): Promise<GenericProductCategory[]> {
  return getJson<GenericProductCategory[]>(`${farmBase()}/product-categories`)
}

export async function createProductCategory(input: { name: string; description?: string | null }): Promise<GenericProductCategory | null> {
  return postJson<GenericProductCategory>(`${farmBase()}/product-categories`, input)
}

export async function getProducts(): Promise<GenericProduct[]> {
  return getJson<GenericProduct[]>(`${farmBase()}/products`)
}

export interface GenericProductInput {
  productName: string
  sku?: string | null
  barcode?: string | null
  description?: string | null
  unitOfMeasure?: string | null
  purchaseUnit?: string | null
  salesUnit?: string | null
  /** Product = things you sell, SupplyItem = things you use internally (migration 440). */
  itemType?: "Product" | "SupplyItem"
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
  expiryDate?: string | null
  trackExpiry?: boolean
  /** Capability flags (migration 441) */
  canSell?: boolean
  canUseInProduction?: boolean
  canUseInternally?: boolean
  /** Product image URL or base64 data URL (migration 492). */
  imageUrl?: string | null
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
// UOM Conversions (migration 364)
// =============================================================================

export interface GenericUomConversion {
  genericUomConversionId: number
  farmId: string
  genericProductId?: number | null
  fromUnit: string
  toUnit: string
  conversionFactor: number
  isActive: boolean
}

export async function getUomConversions(productId?: number | null): Promise<GenericUomConversion[]> {
  const q = productId ? `?productId=${productId}` : ""
  return getJson(`${farmBase()}/uom-conversions${q}`)
}

export async function upsertUomConversion(input: {
  genericProductId?: number | null
  fromUnit: string
  toUnit: string
  conversionFactor: number
}): Promise<{ genericUomConversionId: number } | null> {
  return postJson(`${farmBase()}/uom-conversions`, input)
}

export async function deleteUomConversion(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/uom-conversions/${id}`)
}

// =============================================================================
// Units of Measure (migration 492)
// =============================================================================

export interface GenericUnitOfMeasure {
  genericUnitOfMeasureId: number
  farmId: string
  unitName: string
  unitAbbreviation?: string | null
  isActive: boolean
  createdAt: string
}

export async function getUnitsOfMeasure(): Promise<GenericUnitOfMeasure[]> {
  return getJson<GenericUnitOfMeasure[]>(`${farmBase()}/units`)
}

export async function upsertUnitOfMeasure(input: { unitName: string; unitAbbreviation?: string | null }): Promise<{ genericUnitOfMeasureId: number } | null> {
  return postJson(`${farmBase()}/units`, input)
}

export async function deleteUnitOfMeasure(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/units/${id}`)
}

// =============================================================================
// Classes & Academic Terms (migration 366 — school businesses)
// =============================================================================

export interface GenericClass {
  genericClassId: number
  farmId: string
  className: string
  classLevel?: number | null
  classTeacher?: string | null
  capacity?: number | null
  description?: string | null
  isActive: boolean
  studentCount: number
}

export interface GenericAcademicTerm {
  genericAcademicTermId: number
  farmId: string
  termName: string
  startDate: string
  endDate: string
  isCurrent: boolean
  isActive: boolean
}

export async function getClasses(): Promise<GenericClass[]> {
  return getJson(`${farmBase()}/classes`)
}

export async function upsertClass(input: Partial<GenericClass>): Promise<{ genericClassId: number } | null> {
  return postJson(`${farmBase()}/classes`, input)
}

export async function deleteClass(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/classes/${id}`)
}

export async function getAcademicTerms(): Promise<GenericAcademicTerm[]> {
  return getJson(`${farmBase()}/academic-terms`)
}

export async function upsertAcademicTerm(input: Partial<GenericAcademicTerm>): Promise<{ genericAcademicTermId: number } | null> {
  return postJson(`${farmBase()}/academic-terms`, input)
}

export async function deleteAcademicTerm(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/academic-terms/${id}`)
}

// =============================================================================
// Customer/Student Attendance (migration 367)
// =============================================================================

export interface GenericCustomerAttendance {
  genericCustomerAttendanceId: number
  farmId: string
  genericCustomerId: number
  customerName?: string | null
  classOrGrade?: string | null
  attendanceDate: string
  status: string
  genericClassId?: number | null
  genericAcademicTermId?: number | null
  notes?: string | null
  createdBy?: string | null
}

export async function getCustomerAttendance(date?: string, classId?: number): Promise<GenericCustomerAttendance[]> {
  const params = new URLSearchParams()
  if (date) params.set("date", date)
  if (classId) params.set("classId", String(classId))
  const q = params.toString()
  return getJson(`${farmBase()}/customer-attendance${q ? `?${q}` : ""}`)
}

export async function upsertCustomerAttendance(input: Partial<GenericCustomerAttendance>): Promise<{ genericCustomerAttendanceId: number } | null> {
  return postJson(`${farmBase()}/customer-attendance`, input)
}

export async function deleteCustomerAttendance(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/customer-attendance/${id}`)
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

/** One purchase with its lines and payment header (for editing a Draft). */
export interface GenericPurchaseDetail extends GenericPurchase {
  subtotalAmount?: number
  discountAmount?: number
  taxAmount?: number
  genericCashAccountId?: number | null
  items: (GenericPurchaseItem & { lineTotal?: number })[]
}

export async function getPurchase(id: number): Promise<GenericPurchaseDetail | null> {
  return getJson<GenericPurchaseDetail>(`${farmBase()}/purchases/${id}`)
}

/** Draft only: the server refuses an Approved or Cancelled purchase (migration 472). */
export async function updatePurchase(id: number, input: GenericPurchaseCreateInput): Promise<GenericPurchaseDetail | null> {
  return putJson<GenericPurchaseDetail>(`${farmBase()}/purchases/${id}`, withFarmId(input))
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

export async function rejectExpense(id: number, rejectionReason: string): Promise<void> {
  await postJson(`${farmBase()}/expenses/${id}/reject`, { rejectionReason })
}

/** 448: edit. An approved expense's money is re-posted; locked once a supplier payment is applied. */
export async function updateExpense(id: number, input: GenericExpenseCreateInput): Promise<GenericExpense | null> {
  return putJson<GenericExpense>(`${farmBase()}/expenses/${id}`, withFarmId(input))
}

/** 448: delete. An approved expense gives its cash back and comes off the supplier first. */
export async function deleteExpense(id: number, reason?: string | null): Promise<void> {
  await postJson(`${farmBase()}/expenses/${id}/delete`, { reason: reason ?? null })
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
  /** Present on a saved line (read back from the server). */
  genericPurchaseItemId?: number
  genericProductId: number
  description?: string | null
  quantity: number
  unitCost: number
  discountAmount: number
  notes?: string | null
  /** Unit the line was bought in, e.g. "bag" (migration 472). Empty = the product's base unit. */
  purchaseUnit?: string | null
  /** Base units in one purchaseUnit (1 bag = 50 kg → 50). Stock rises by quantity × unitFactor. */
  unitFactor?: number
}

export interface GenericPurchaseCreateInput {
  /**
   * 483 Projects & Contracts: optional, saved in the same statement as this
   * transaction. Leave it out to keep the old behaviour exactly.
   */
  projects?: import("@/lib/api/generic-projects").ProjectAssignment
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
  /**
   * 483 Projects & Contracts: optional, saved in the same statement as this
   * transaction. Leave it out to keep the old behaviour exactly.
   */
  projects?: import("@/lib/api/generic-projects").ProjectAssignment
  expenseDate?: string | null
  genericExpenseCategoryId: number
  genericSupplierId?: number | null
  description?: string | null
  amount: number
  paidTo?: string | null
  paymentMethod: string
  genericCashAccountId?: number | null
  notes?: string | null
  /** Receipt photo path from /api/receipt-upload (as on Poultry). */
  receiptUrl?: string | null
  /** 448: null = paid in full, 0 = not paid (owed to the supplier), between = partly paid. */
  amountPaid?: number | null
  dueDate?: string | null
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
  status: "Draft" | "Approved" | "Cancelled" | "Reversed" | string
  notes?: string | null
  createdAt: string
  /** TRF-2026-0001 (migration 456). */
  transferNumber?: string | null
  /** The bank's or wallet's own reference for the movement. */
  referenceNumber?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface GenericCashTransferCreateInput {
  fromGenericCashAccountId: number
  toGenericCashAccountId: number
  amount: number
  transferDate?: string | null
  referenceNumber?: string | null
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

/**
 * Create AND approve in one server call (Poultry's "Record transfer"). If the
 * approval is refused (not enough money) the whole call fails and no Draft is
 * left behind -- never create + approve separately from a page.
 */
export async function recordCashTransfer(
  input: GenericCashTransferCreateInput
): Promise<GenericCashTransfer | null> {
  const { userId } = getUserContext()
  const q = userId ? `?createdBy=${encodeURIComponent(userId)}` : ""
  return postJson<GenericCashTransfer>(`${farmBase()}/cash-transfers/record${q}`,
    withFarmId({ ...input, createdBy: userId || null }))
}

/** Undo an APPROVED transfer: two opposite ledger rows, originals kept, reason audited. */
export async function reverseCashTransfer(id: number, reason: string): Promise<void> {
  const { userId } = getUserContext()
  const q = userId ? `?reversedBy=${encodeURIComponent(userId)}` : ""
  await postJson(`${farmBase()}/cash-transfers/${id}/reverse${q}`, { reason })
}

// =============================================================================
// Customer Credits
// =============================================================================

export interface GenericCustomerCredit {
  genericCustomerCreditId: number; farmId: string; genericCustomerId: number
  customerName: string | null; creditType: string; amount: number
  remainingBalance: number; creditDate: string; notes: string | null
  status: string; createdAt: string
  /** What made it: "CustomerPayment" + the payment id; null when added by hand. */
  referenceType?: string | null; referenceId?: number | null
}

export async function getCustomerCredits(): Promise<GenericCustomerCredit[]> {
  return getJson<GenericCustomerCredit[]>(`${farmBase()}/customer-credits`)
}

export async function createCustomerCredit(input: {
  genericCustomerId: number; creditType: string; amount: number
  creditDate?: string; notes?: string
  /** 501: Projects & Contracts -- { projectId } or { splits }. */
  projects?: unknown
}): Promise<number | null> {
  return postJson<number>(`${farmBase()}/customer-credits`, withFarmId(input))
}

// =============================================================================
// Supplier Credits
// =============================================================================

export interface GenericSupplierCredit {
  genericSupplierCreditId: number; farmId: string; genericSupplierId: number
  supplierName: string | null; creditType: string; amount: number
  remainingBalance: number; creditDate: string; notes: string | null
  status: string; createdAt: string
}

export async function getSupplierCredits(): Promise<GenericSupplierCredit[]> {
  return getJson<GenericSupplierCredit[]>(`${farmBase()}/supplier-credits`)
}

export async function createSupplierCredit(input: {
  genericSupplierId: number; creditType: string; amount: number
  creditDate?: string; notes?: string
}): Promise<number | null> {
  return postJson<number>(`${farmBase()}/supplier-credits`, withFarmId(input))
}

// =============================================================================
// Deferred Inventory Cost
// =============================================================================

export interface GenericDeferredCost {
  genericProductId: number; productName: string
  totalPurchased: number; totalSoldCost: number
  deferredBalance: number; currentStock: number
}

export async function getDeferredCosts(): Promise<GenericDeferredCost[]> {
  return getJson<GenericDeferredCost[]>(`${farmBase()}/deferred-costs`)
}

// =============================================================================
// Loans (Financing)
// =============================================================================

// Migration 455 brought these up to Poultry's loans: real lender type / account
// number / interest type / term / frequency / next payment fields, loan and
// payment numbers, edit, cancel and reversal, and every cash move posted to the
// account ledger. Status reads 'Active' | 'PaidOff' | 'Cancelled'.
export interface GenericLoan {
  genericLoanId: number; farmId: string; loanNumber: string | null
  lenderName: string; lenderType: string | null; accountNumber: string | null
  originalPrincipal: number; amountReceived: number; interestRate: number
  interestType: string | null; termMonths: number | null; paymentFrequency: string | null
  totalInterestPaid: number; totalFeesPaid: number; totalPrincipalPaid: number
  outstandingBalance: number; loanDate: string; startDate: string | null
  dueDate: string | null; nextPaymentDate: string | null
  genericCashAccountId: number | null; accountName: string | null
  paymentCount: number; isOverdue: boolean; paidOffDate: string | null; cancelReason: string | null
  status: string; notes: string | null; createdAt: string
}

export interface GenericLoanPayment {
  genericLoanPaymentId: number; genericLoanId: number; loanNumber: string | null
  paymentNumber: string | null; paymentDate: string
  principalAmount: number; interestAmount: number; feeAmount: number; otherAmount: number
  totalPayment: number; genericCashAccountId: number | null; accountName: string | null
  paymentMethod: string | null; referenceNumber: string | null
  notes: string | null; isReversed: boolean; status: "Posted" | "Reversed" | string
  reversedAt: string | null; reversalReason: string | null; createdAt: string
}

export async function getLoans(): Promise<GenericLoan[]> {
  return getJson<GenericLoan[]>(`${farmBase()}/loans`)
}

/** A received amount needs an account: the server refuses one without. */
export async function createLoan(input: {
  lenderName: string; originalPrincipal: number; amountReceived: number; interestRate?: number | null
  loanDate: string; startDate?: string; dueDate?: string
  genericCashAccountId?: number | null; notes?: string | null
  lenderType?: string | null; accountNumber?: string | null; interestType?: string | null
  termMonths?: number | null; paymentFrequency?: string | null; nextPaymentDate?: string | null
  /** Projects & Contracts: saved with the loan (singleAssignment). */
  projects?: unknown
}): Promise<number | null> {
  const { userId } = getUserContext()
  return postJson<number>(`${farmBase()}/loans`, withFarmId({ ...input, createdBy: userId || null }))
}

/** Terms only. Blank fields keep their stored value; the money is never edited. */
export async function updateLoan(loanId: number, input: {
  lenderName?: string | null; lenderType?: string | null; accountNumber?: string | null
  interestRate?: number | null; interestType?: string | null; termMonths?: number | null
  paymentFrequency?: string | null; dueDate?: string | null; nextPaymentDate?: string | null
  notes?: string | null
  /** Projects & Contracts: only when the project was changed; leave out to keep it. */
  projects?: unknown
}): Promise<void> {
  const { userId } = getUserContext()
  await putJson(`${farmBase()}/loans/${loanId}`, withFarmId({ ...input, updatedBy: userId || null }))
}

/** Refused while the loan has posted repayments. Takes the received money back out. */
export async function cancelLoan(loanId: number, reason: string): Promise<void> {
  const { userId } = getUserContext()
  await postJson(`${farmBase()}/loans/${loanId}/cancel`, { reason, by: userId || null })
}

/** Every repayment of the company (reversed ones included), newest first. */
export async function getAllLoanPayments(): Promise<GenericLoanPayment[]> {
  return getJson<GenericLoanPayment[]>(`${farmBase()}/loans/payments`)
}

export async function getLoanPayments(loanId: number): Promise<GenericLoanPayment[]> {
  return getJson<GenericLoanPayment[]>(`${farmBase()}/loans/${loanId}/payments`)
}

/** Refuses principal above what is owed, and overdrawing the account. */
export async function repayLoan(loanId: number, input: {
  principalAmount: number; interestAmount: number; feeAmount: number; otherAmount?: number
  paymentDate?: string | null; genericCashAccountId?: number | null; notes?: string | null
  paymentMethod?: string | null; referenceNumber?: string | null; nextPaymentDate?: string | null
}): Promise<number | null> {
  const { userId } = getUserContext()
  return postJson<number>(`${farmBase()}/loans/${loanId}/repay`, withFarmId({ ...input, createdBy: userId || null }))
}

export async function reverseLoanPayment(paymentId: number, reason: string): Promise<void> {
  const { userId } = getUserContext()
  await postJson(`${farmBase()}/loans/payments/${paymentId}/reverse`, { reason, by: userId || null })
}

// =============================================================================
// Capital Assets
// =============================================================================

export interface GenericAsset {
  genericAssetId: number; farmId: string; assetName: string; category: string | null
  purchaseDate: string; purchaseCost: number; currentValue: number; totalDepreciation: number
  usefulLifeMonths: number | null; depreciationMethod: string | null; status: string
  disposalDate: string | null; disposalAmount: number | null
  location: string | null; serialNumber: string | null; notes: string | null; createdAt: string
}

export async function getAssets(): Promise<GenericAsset[]> {
  return getJson<GenericAsset[]>(`${farmBase()}/assets`)
}

export async function createAsset(input: {
  assetName: string; category?: string; purchaseDate: string; purchaseCost: number
  usefulLifeMonths?: number; depreciationMethod?: string
  location?: string; serialNumber?: string; notes?: string
}): Promise<number | null> {
  return postJson<number>(`${farmBase()}/assets`, withFarmId(input))
}

export async function disposeAsset(assetId: number, input: {
  disposalDate?: string; disposalAmount: number
}): Promise<void> {
  await postJson(`${farmBase()}/assets/${assetId}/dispose`, withFarmId(input))
}

export async function depreciateAsset(assetId: number, amount: number): Promise<void> {
  await postJson(`${farmBase()}/assets/${assetId}/depreciate`, amount)
}

// =============================================================================
// Deliveries
// =============================================================================

export interface GenericDelivery {
  genericDeliveryId: number
  farmId: string
  deliveryDate: string
  driverName: string | null
  vehicleName: string | null
  route: string | null
  customerName: string | null
  destination: string | null
  transportMode: string | null
  genericProductId: number
  productName: string | null
  quantityLoaded: number
  unit: string | null
  unitPrice: number
  quantitySold: number
  quantityReturned: number
  quantityDamaged: number
  quantityShort: number
  cashCollected: number
  creditSales: number
  deliveryExpenses: number
  totalSales: number
  status: string
  notes: string | null
  createdAt: string
  reconciledAt: string | null
  deliveredAt: string | null
  deliveredBy: string | null
}

export async function getDeliveries(status?: string | null): Promise<GenericDelivery[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  return getJson<GenericDelivery[]>(`${farmBase()}/deliveries${qs}`)
}

export async function loadDelivery(input: {
  genericProductId: number; quantityLoaded: number; unit: string; unitPrice: number
  driverName: string; vehicleName: string; route: string; deliveryDate: string; notes: string
  customerName?: string; destination?: string; transportMode?: string
}): Promise<number | null> {
  return postJson<number>(`${farmBase()}/deliveries/load`, withFarmId(input))
}

export async function reconcileDelivery(id: number, input: {
  quantitySold: number; quantityReturned: number; quantityDamaged: number; quantityShort: number
  cashCollected: number; creditSales: number; deliveryExpenses: number
}): Promise<void> {
  await postJson(`${farmBase()}/deliveries/${id}/reconcile`, withFarmId(input))
}

export async function reverseDelivery(id: number): Promise<void> {
  await postJson(`${farmBase()}/deliveries/${id}/reverse`, {})
}

export async function cancelDelivery(id: number): Promise<void> {
  await postJson(`${farmBase()}/deliveries/${id}/cancel`, {})
}

export async function dispatchDelivery(id: number): Promise<void> {
  await postJson(`${farmBase()}/deliveries/${id}/dispatch`, {})
}

export async function markDeliveryDelivered(id: number): Promise<void> {
  await postJson(`${farmBase()}/deliveries/${id}/mark-delivered`, {})
}

// Delivery reports
export interface GenericDriverReport {
  driverName: string; transportMode: string | null; totalDeliveries: number; totalLoaded: number; totalSold: number
  totalReturned: number; totalDamaged: number; totalShort: number; totalSales: number
  totalCashCollected: number; totalCreditSales: number; totalExpenses: number; deliveryRate: number
  loadedDeliveries: number; inTransitDeliveries: number; deliveredDeliveries: number
  reconciledDeliveries: number; cancelledDeliveries: number
}

export interface GenericProductDeliveryReport {
  productName: string; totalDeliveries: number; totalLoaded: number; totalSold: number
  totalReturned: number; totalDamaged: number; totalShort: number; totalSales: number
  sellThroughRate: number
}

export interface GenericRouteReport {
  route: string; totalDeliveries: number; totalLoaded: number; totalSold: number
  totalSales: number; totalExpenses: number; netRevenue: number
}

// =============================================================================
// Drivers
// =============================================================================

export interface GenericDriver {
  genericDriverId: number; farmId: string; driverName: string
  phoneNumber: string | null; licenseNumber: string | null
  vehicleName: string | null; vehicleRegistration: string | null
  transportMode: string | null
  isActive: boolean; notes: string | null; createdAt: string
}

export async function getDrivers(): Promise<GenericDriver[]> {
  return getJson<GenericDriver[]>(`${farmBase()}/drivers`)
}

export async function createDriver(input: {
  driverName: string; phoneNumber?: string; licenseNumber?: string
  vehicleName?: string; vehicleRegistration?: string; transportMode?: string; notes?: string
}): Promise<number | null> {
  return postJson<number>(`${farmBase()}/drivers`, withFarmId(input))
}

export async function updateDriver(id: number, input: {
  driverName: string; phoneNumber?: string; licenseNumber?: string
  vehicleName?: string; vehicleRegistration?: string; transportMode?: string; isActive?: boolean; notes?: string
}): Promise<void> {
  await putJson(`${farmBase()}/drivers/${id}`, withFarmId(input))
}

export async function deleteDriver(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/drivers/${id}`)
}

// =============================================================================
// Routes
// =============================================================================

export interface GenericRoute {
  genericRouteId: number; farmId: string; routeName: string
  description: string | null; startPoint: string | null; endPoint: string | null
  estimatedTime: string | null; isActive: boolean; notes: string | null; createdAt: string
}

export async function getRoutes(): Promise<GenericRoute[]> {
  return getJson<GenericRoute[]>(`${farmBase()}/routes`)
}

export async function createRoute(input: {
  routeName: string; description?: string; startPoint?: string
  endPoint?: string; estimatedTime?: string; notes?: string
}): Promise<number | null> {
  return postJson<number>(`${farmBase()}/routes`, withFarmId(input))
}

export async function updateRoute(id: number, input: {
  routeName: string; description?: string; startPoint?: string
  endPoint?: string; estimatedTime?: string; isActive?: boolean; notes?: string
}): Promise<void> {
  await putJson(`${farmBase()}/routes/${id}`, withFarmId(input))
}

export async function deleteRoute(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/routes/${id}`)
}

export async function getDriverReport(fromDate?: string, toDate?: string, driverName?: string): Promise<GenericDriverReport[]> {
  const qs = new URLSearchParams()
  if (fromDate) qs.append("fromDate", fromDate)
  if (toDate) qs.append("toDate", toDate)
  if (driverName) qs.append("driverName", driverName)
  const q = qs.toString()
  return getJson<GenericDriverReport[]>(`${farmBase()}/deliveries/reports/by-driver${q ? `?${q}` : ""}`)
}

export async function getProductDeliveryReport(fromDate?: string, toDate?: string): Promise<GenericProductDeliveryReport[]> {
  const qs = new URLSearchParams()
  if (fromDate) qs.append("fromDate", fromDate)
  if (toDate) qs.append("toDate", toDate)
  const q = qs.toString()
  return getJson<GenericProductDeliveryReport[]>(`${farmBase()}/deliveries/reports/by-product${q ? `?${q}` : ""}`)
}

export async function getRouteReport(fromDate?: string, toDate?: string): Promise<GenericRouteReport[]> {
  const qs = new URLSearchParams()
  if (fromDate) qs.append("fromDate", fromDate)
  if (toDate) qs.append("toDate", toDate)
  const q = qs.toString()
  return getJson<GenericRouteReport[]>(`${farmBase()}/deliveries/reports/by-route${q ? `?${q}` : ""}`)
}

// =============================================================================
// Part 2: stock movements
// =============================================================================

export interface GenericStockMovement {
  genericStockMovementId: number
  farmId: string
  genericProductId: number
  productName: string | null
  inventoryLocationId: number | null
  movementDate: string
  movementType: string
  quantity: number
  unitCost: number | null
  unitSellingPrice: number | null
  totalCostValue: number | null
  referenceType: string | null
  referenceId: number | null
  reason: string | null
  createdBy: string | null
  approvedBy: string | null
  approvedAt: string | null
  notes: string | null
  createdAt: string
}

export async function getStockMovementsForProduct(productId: number): Promise<GenericStockMovement[]> {
  return getJson<GenericStockMovement[]>(`${farmBase()}/inventory/products/${productId}/movements`)
}

export async function getStockMovements(fromDate?: string, toDate?: string): Promise<GenericStockMovement[]> {
  const qs = new URLSearchParams()
  if (fromDate) qs.append("fromDate", fromDate)
  if (toDate) qs.append("toDate", toDate)
  const q = qs.toString()
  return getJson<GenericStockMovement[]>(`${farmBase()}/inventory/movements${q ? `?${q}` : ""}`)
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

export interface GenericProfitLossEntry {
  section: "revenue" | "direct" | "operating" | "other" | "owner" | "borrowing" | "capital"
  line: string
  date: string
  reference: string
  description: string
  amount: number
}

/**
 * project (484): "all" / undefined = the whole company (unchanged), "general" =
 * only what is on no project, "12" or "12,15" = those projects' share.
 */
export async function getProfitLossEntries(farmId: string, fromDate: string, toDate: string, project?: string): Promise<GenericProfitLossEntry[]> {
  const params = new URLSearchParams({ fromDate, toDate })
  if (project && project !== "all") params.append("project", project)
  return getJson<GenericProfitLossEntry[]>(`/generic-company/${encodeURIComponent(farmId)}/reports/profit-loss?${params}`)
}

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

// =============================================================================
// Phase 4: Financial Impact Preview & Reports (migration 442)
// =============================================================================

export interface GenericFinancialPreview {
  productName: string
  transactionType: string
  quantity: number
  unitCost: number
  totalCost: number
  inventoryChange: number
  revenueEffect: number
  cogsEffect: number
  expenseEffect: number
  cashEffect: number
  supplierEffect: number
  currentStock: number
  stockAfter: number
  expenseCategory: string | null
  notes: string | null
}

export async function getFinancialPreview(
  productId: number, quantity: number, transactionType: string
): Promise<GenericFinancialPreview> {
  const qs = new URLSearchParams({
    productId: String(productId),
    quantity: String(quantity),
    transactionType,
  }).toString()
  return getJson<GenericFinancialPreview>(`${farmBase()}/reports/financial-preview?${qs}`)
}

export interface GenericPnLBreakdown {
  totalIncome: number
  costOfGoodsSold: number
  grossProfit: number
  internalUseExpenses: number
  operatingExpenses: number
  payrollExpenses: number
  totalExpenses: number
  netProfit: number
  profitMarginPct: number
  salesCount: number
  internalUseCount: number
}

export async function getPnLBreakdown(fromDate: string, toDate: string): Promise<GenericPnLBreakdown> {
  return getJson<GenericPnLBreakdown>(`${farmBase()}/reports/pnl-breakdown?fromDate=${fromDate}&toDate=${toDate}`)
}

export interface GenericItemCostReconciliation {
  productName: string
  totalPurchasedQty: number
  totalPurchasedCost: number
  totalProducedQty: number
  totalProducedCost: number
  soldQty: number
  soldCost: number
  internalUseQty: number
  internalUseCost: number
  productionConsumedQty: number
  productionConsumedCost: number
  adjustmentQty: number
  remainingQty: number
  remainingCostBasis: number
  costReconciled: boolean
}

export async function getItemCostReconciliation(productId: number): Promise<GenericItemCostReconciliation> {
  return getJson<GenericItemCostReconciliation>(`${farmBase()}/reports/item-cost-reconciliation?productId=${productId}`)
}

// =============================================================================
// Phase 5: Reports (migration 443)
// =============================================================================

export interface GenericInventoryBalanceRow {
  genericProductId: number
  productName: string
  categoryName: string | null
  purpose: string | null
  unitOfMeasure: string | null
  openingQty: number
  purchasesQty: number
  productionInQty: number
  returnsInQty: number
  salesQty: number
  internalUseQty: number
  productionOutQty: number
  damageQty: number
  adjustmentQty: number
  otherQty: number
  closingQty: number
  unitCost: number
  inventoryValue: number
}

export async function getInventoryBalance(fromDate: string, toDate: string): Promise<GenericInventoryBalanceRow[]> {
  return getJson<GenericInventoryBalanceRow[]>(`${farmBase()}/reports/inventory-balance?fromDate=${fromDate}&toDate=${toDate}`)
}

export interface GenericConsumptionRow {
  usageDate: string
  genericProductId: number
  productName: string
  categoryName: string | null
  quantityUsed: number
  unitOfMeasure: string | null
  unitCost: number
  totalCost: number
  expenseCategory: string | null
  reason: string | null
  referenceNumber: string | null
  recordedBy: string | null
  status: string | null
  genericInternalUsageId: number
}

export interface GenericConsumptionSummary {
  totalConsumptionCost: number
  totalItemsConsumed: number
  totalRecords: number
  topItemName: string | null
  topItemCost: number
  categoryBreakdown: string | null
}

export async function getInternalConsumption(fromDate?: string, toDate?: string, category?: string): Promise<GenericConsumptionRow[]> {
  const qs = new URLSearchParams()
  if (fromDate) qs.append("fromDate", fromDate)
  if (toDate) qs.append("toDate", toDate)
  if (category) qs.append("category", category)
  const q = qs.toString()
  return getJson<GenericConsumptionRow[]>(`${farmBase()}/reports/internal-consumption${q ? `?${q}` : ""}`)
}

export async function getConsumptionSummary(fromDate?: string, toDate?: string): Promise<GenericConsumptionSummary> {
  const qs = new URLSearchParams()
  if (fromDate) qs.append("fromDate", fromDate)
  if (toDate) qs.append("toDate", toDate)
  const q = qs.toString()
  return getJson<GenericConsumptionSummary>(`${farmBase()}/reports/consumption-summary${q ? `?${q}` : ""}`)
}

export interface GenericReconciliationRow {
  genericProductId: number
  productName: string
  ledgerTotal: number
  cachedStock: number
  drift: number
  isReconciled: boolean
}

export async function getInventoryReconciliation(): Promise<GenericReconciliationRow[]> {
  return getJson<GenericReconciliationRow[]>(`${farmBase()}/reports/inventory-reconciliation`)
}

export interface GenericRestockForecastRow {
  genericProductId: number
  productName: string
  currentStock: number
  minimumStockAlert: number
  unitOfMeasure: string | null
  avgDailySales: number
  avgDailyInternalUse: number
  avgDailyProduction: number
  avgDailyOtherOut: number
  avgDailyTotalOut: number
  daysUntilStockout: number
  daysUntilReorderPoint: number
  suggestedReorderQty: number
  urgencyLevel: string
}

export async function getRestockForecast(lookbackDays?: number): Promise<GenericRestockForecastRow[]> {
  const qs = lookbackDays ? `?lookbackDays=${lookbackDays}` : ""
  return getJson<GenericRestockForecastRow[]>(`${farmBase()}/reports/restock-forecast${qs}`)
}

// =============================================================================
// Service Catalog (migration 493)
// =============================================================================

export interface GenericServiceCategory {
  genericServiceCategoryId: number
  farmId: string
  name: string
  description?: string | null
  isActive: boolean
  isDeleted: boolean
  createdAt: string
  updatedAt?: string | null
}

export interface GenericService {
  genericServiceId: number
  farmId: string
  genericServiceCategoryId?: number | null
  categoryName?: string | null
  serviceName: string
  serviceCode?: string | null
  description?: string | null
  pricingUnit: string
  defaultPrice: number
  estimatedCost?: number | null
  durationMinutes?: number | null
  assignedStaffId?: number | null
  isActive: boolean
  isDeleted: boolean
  notes?: string | null
  archivedAt?: string | null
  createdBy?: string | null
  updatedBy?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface GenericServiceInput {
  serviceName: string
  serviceCode?: string | null
  description?: string | null
  pricingUnit?: string
  defaultPrice?: number
  estimatedCost?: number | null
  durationMinutes?: number | null
  assignedStaffId?: number | null
  genericServiceCategoryId?: number | null
  isActive?: boolean
  notes?: string | null
}

// --- Service categories ---

export async function getServiceCategories(): Promise<GenericServiceCategory[]> {
  return getJson<GenericServiceCategory[]>(`${farmBase()}/service-categories`)
}

export async function createServiceCategory(input: { name: string; description?: string | null }): Promise<GenericServiceCategory | null> {
  return postJson<GenericServiceCategory>(`${farmBase()}/service-categories`, { ...input, farmId: getUserContext().farmId })
}

export async function updateServiceCategory(id: number, input: { name: string; description?: string | null; isActive?: boolean }): Promise<void> {
  await putJson(`${farmBase()}/service-categories/${id}`, { ...input, farmId: getUserContext().farmId })
}

export async function deleteServiceCategory(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/service-categories/${id}`)
}

// --- Services ---

export async function getServices(): Promise<GenericService[]> {
  return getJson<GenericService[]>(`${farmBase()}/services`)
}

export async function getServiceById(id: number): Promise<GenericService | null> {
  return getJson<GenericService>(`${farmBase()}/services/${id}`)
}

export async function createService(input: GenericServiceInput): Promise<GenericService | null> {
  return postJson<GenericService>(`${farmBase()}/services`, withFarmId(input))
}

export async function updateService(id: number, input: GenericServiceInput): Promise<void> {
  await putJson(`${farmBase()}/services/${id}`, input)
}

export async function deleteService(id: number): Promise<void> {
  await deleteResource(`${farmBase()}/services/${id}`)
}

export async function archiveService(id: number): Promise<void> {
  await postJson(`${farmBase()}/services/${id}/archive`, {})
}

export async function activateService(id: number): Promise<void> {
  await postJson(`${farmBase()}/services/${id}/activate`, {})
}

export async function deactivateService(id: number): Promise<void> {
  await postJson(`${farmBase()}/services/${id}/deactivate`, {})
}

export async function serviceHasPostedSales(id: number): Promise<boolean> {
  return getJson<boolean>(`${farmBase()}/services/${id}/has-posted-sales`)
}

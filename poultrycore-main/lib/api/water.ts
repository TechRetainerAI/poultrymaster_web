import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// ----- Types -----
// Migration 063 introduces ProductType so finished goods are separated from
// raw/packaging materials in the Products list and Recipe pickers.
// #10: expanded product-type list (added Consumable, SparePart, Service).
export type WaterProductType = "FinishedGood" | "RawMaterial" | "PackagingMaterial" | "Consumable" | "SparePart" | "Service" | "Other"

export interface WaterProduct {
  waterProductId: number
  farmId: string
  name: string
  sku?: string | null
  sizeMl?: number | null
  unit?: string | null
  unitPrice: number
  isActive: boolean
  productType: WaterProductType
  notes?: string | null
  createdDate: string
  updatedDate?: string | null
  stockOnHand: number
  // Migration 084 — sachet-water support. Inventory page reads these to show
  // both bags + sachets when isSachetProduct=true. Sales modal uses sellingUnit
  // to pick between bagPrice and sachetPrice.
  baseUnit?: string | null
  sachetsPerBag?: number | null
  bagPrice?: number | null
  sachetPrice?: number | null
  isSachetProduct?: boolean
  // Migration 092 — Packaging & Pricing (#8/#9/#10). unit = Inventory Unit,
  // sizeMl = Size Per Unit, sachetsPerBag = Units Per Package, bagPrice/
  // sachetPrice = selling prices.
  sizeUnit?: string | null
  packagingUnit?: string | null
  defaultSalesUnit?: string | null
  productCategory?: string | null
}

export interface WaterProductInput {
  name: string
  sku?: string | null
  sizeMl?: number | null
  unit?: string | null
  unitPrice: number
  isActive?: boolean
  productType?: WaterProductType
  notes?: string | null
  // Migration 084 — sachet-water support (optional).
  baseUnit?: string | null
  sachetsPerBag?: number | null
  bagPrice?: number | null
  sachetPrice?: number | null
  isSachetProduct?: boolean
  // Migration 092 — Packaging & Pricing (#8/#9/#10).
  sizeUnit?: string | null
  packagingUnit?: string | null
  defaultSalesUnit?: string | null
  productCategory?: string | null
}

export interface WaterCustomer {
  waterCustomerId: number
  farmId: string
  name: string
  contactPhone?: string | null
  contactEmail?: string | null
  address?: string | null
  city?: string | null
  notes?: string | null
  createdDate: string
  updatedDate?: string | null
  outstandingBalance: number
  // Migration 082 — system-managed default customers (Summary delivery sales,
  // walk-in / unassigned-credit posting). Frontend pins these to the top of
  // the customer list and gates delete behind a strong warning.
  customerType?: string | null
  defaultCustomerType?: "GeneralSales" | "GeneralDelivery" | "GeneralCredit" | string | null
  isDefaultCustomer?: boolean
  isSystemGenerated?: boolean
  isActive?: boolean
}

export interface WaterCustomerInput {
  name: string
  contactPhone?: string | null
  contactEmail?: string | null
  address?: string | null
  city?: string | null
  notes?: string | null
}

// Migration 082 — one row per default-customer type returned by
// /Water/customers/create-defaults.
export interface WaterDefaultCustomerResult {
  waterCustomerId: number
  defaultCustomerType: "GeneralSales" | "GeneralDelivery" | "GeneralCredit" | string
  name: string
  wasCreated: boolean
}

export interface WaterStockTransaction {
  stockTxnId: number
  farmId: string
  waterProductId: number
  productName?: string | null
  txnType: "Restock" | "Adjust" | "Sale" | "Return" | string
  quantity: number
  unitCost?: number | null
  relatedSaleId?: number | null
  note?: string | null
  createdDate: string
  createdBy?: string | null
}

export interface WaterSaleItem {
  waterSaleItemId?: number
  waterSaleId?: number
  waterProductId: number
  productName?: string | null
  quantity: number
  unitPrice: number
  lineTotal?: number
  // Migration 084 — selling unit on the line (Bag | Sachet). BaseUnit /
  // BaseQuantity are server-computed and reflect the deducted stock in the
  // product's base unit.
  sellingUnit?: string | null
  baseUnit?: string | null
  baseQuantity?: number | null
}

export interface WaterSale {
  waterSaleId: number
  farmId: string
  waterCustomerId?: number | null
  customerName?: string | null
  saleDate: string
  totalAmount: number
  amountPaid: number
  balance: number
  status: "Pending" | "Paid" | "PartiallyPaid" | "Cancelled" | string
  notes?: string | null
  createdDate: string
  createdBy?: string | null
  updatedDate?: string | null
  // Where the sale came from: null/"" = direct sale; "DeliveryRun" = created by
  // a driver return (cannot be deleted on the Sales page).
  sourceType?: string | null
  sourceId?: number | null
  items: WaterSaleItem[]
}

export interface CreateWaterSaleInput {
  waterCustomerId?: number | null
  saleDate?: string | null
  notes?: string | null
  items: WaterSaleItem[]
}

export interface WaterPayment {
  waterPaymentId: number
  farmId: string
  waterSaleId: number
  amount: number
  paymentMethod?: string | null
  paymentDate: string
  reference?: string | null
  note?: string | null
  createdDate: string
  createdBy?: string | null
  customerName?: string | null
}

export interface WaterPaymentInput {
  waterSaleId: number
  amount: number
  paymentMethod?: string | null
  paymentDate?: string | null
  reference?: string | null
  note?: string | null
}

export interface WaterDashboardSummary {
  activeProducts: number
  totalCustomers: number
  totalStockOnHand: number
  salesToday: number
  salesThisMonth: number
  outstandingReceivables: number
}

// ----- Helpers -----
function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

function currentUserId(): string {
  const { userId } = getUserContext()
  return userId
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()   // Doc3-D: expired session -> login
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as T
}

async function jsend<T>(path: string, method: "POST" | "PUT" | "DELETE", body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()   // Doc3-D: expired session -> login
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError(method, path, res.status, t))
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

// ----- Products -----
export const listWaterProducts = () =>
  jget<WaterProduct[]>(`/Water/products?farmId=${encodeURIComponent(activeFarmId())}`)

export const getWaterProduct = (id: number) =>
  jget<WaterProduct>(`/Water/products/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterProduct = (input: WaterProductInput) =>
  jsend<WaterProduct>(`/Water/products`, "POST", { ...input, farmId: activeFarmId() })

export const updateWaterProduct = (id: number, input: WaterProductInput) =>
  jsend<void>(`/Water/products/${id}`, "PUT", { ...input, waterProductId: id, farmId: activeFarmId() })

export const deleteWaterProduct = (id: number) =>
  jsend<void>(`/Water/products/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Customers -----
export const listWaterCustomers = () =>
  jget<WaterCustomer[]>(`/Water/customers?farmId=${encodeURIComponent(activeFarmId())}`)

export const getWaterCustomer = (id: number) =>
  jget<WaterCustomer>(`/Water/customers/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterCustomer = (input: WaterCustomerInput) =>
  jsend<WaterCustomer>(`/Water/customers`, "POST", { ...input, farmId: activeFarmId() })

export const updateWaterCustomer = (id: number, input: WaterCustomerInput) =>
  jsend<void>(`/Water/customers/${id}`, "PUT", { ...input, waterCustomerId: id, farmId: activeFarmId() })

export const deleteWaterCustomer = (id: number) =>
  jsend<void>(`/Water/customers/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// Migration 082 — idempotently creates the 3 default system customers for the
// active farm. Returns one row per default type (wasCreated=false on rows
// that already existed).
export const createWaterDefaultCustomers = () =>
  jsend<WaterDefaultCustomerResult[]>(
    `/Water/customers/create-defaults?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
  )

// ----- Stock -----
export const listWaterStockTransactions = (productId?: number) => {
  const farmId = encodeURIComponent(activeFarmId())
  const url = productId
    ? `/Water/stock/transactions?farmId=${farmId}&productId=${productId}`
    : `/Water/stock/transactions?farmId=${farmId}`
  return jget<WaterStockTransaction[]>(url)
}

export interface AddStockTxnInput {
  waterProductId: number
  txnType: "Restock" | "Adjust" | "Return"
  quantity: number
  unitCost?: number | null
  note?: string | null
}

export const addWaterStockTransaction = (input: AddStockTxnInput) =>
  jsend<{ stockTxnId: number }>(`/Water/stock/transactions`, "POST", {
    ...input,
    farmId: activeFarmId(),
    createdBy: currentUserId() || null,
  })

// ----- Sales -----
export const listWaterSales = () =>
  jget<WaterSale[]>(`/Water/sales?farmId=${encodeURIComponent(activeFarmId())}`)

export const getWaterSale = (id: number) =>
  jget<WaterSale>(`/Water/sales/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterSale = (input: CreateWaterSaleInput) =>
  jsend<WaterSale>(`/Water/sales`, "POST", {
    ...input,
    farmId: activeFarmId(),
    createdBy: currentUserId() || null,
  })

export const cancelWaterSale = (id: number) =>
  jsend<void>(`/Water/sales/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
// Hard-delete a direct sale. The backend rejects delivery-sourced sales.
export const deleteWaterSale = (id: number) =>
  jsend<void>(`/Water/sales/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Payments -----
export const listWaterPayments = () =>
  jget<WaterPayment[]>(`/Water/payments?farmId=${encodeURIComponent(activeFarmId())}`)

export const listWaterPaymentsBySale = (saleId: number) =>
  jget<WaterPayment[]>(`/Water/payments/by-sale/${saleId}?farmId=${encodeURIComponent(activeFarmId())}`)

export const recordWaterPayment = (input: WaterPaymentInput) =>
  jsend<{ waterPaymentId: number }>(`/Water/payments`, "POST", {
    ...input,
    farmId: activeFarmId(),
    createdBy: currentUserId() || null,
  })

// ----- Dashboard -----
export const getWaterDashboardSummary = () =>
  jget<WaterDashboardSummary>(`/Water/dashboard/summary?farmId=${encodeURIComponent(activeFarmId())}`)

// =============================================================================
// W4: Finance (Expenses, Cash Accounts, Cash Transfers, Customer Ledger)
// =============================================================================

export interface WaterExpenseCategory {
  waterExpenseCategoryId: number
  farmId: string
  name: string
  description?: string | null
  isActive: boolean
  isDeleted: boolean
  createdAt: string
  updatedAt?: string | null
}

export interface WaterExpense {
  waterExpenseId: number
  farmId: string
  expenseDate: string
  waterExpenseCategoryId: number
  categoryName?: string | null
  description?: string | null
  amount: number
  paidTo?: string | null
  paymentMethod: string
  waterCashAccountId?: number | null
  cashAccountName?: string | null
  receiptUrl?: string | null
  linkedWaterVehicleId?: number | null
  linkedWaterMachineId?: number | null
  linkedWaterProductionBatchId?: number | null
  // Migration 077 — supplier link replaces freetext paidTo as the canonical Paid To.
  supplierId?: number | null
  supplierName?: string | null
  // Migration 075/078 — Source link for auto-generated expenses (Payroll,
  // RawMaterialPurchase, ProductionBatch). Powers the clickable Source column.
  sourceType?: "Payroll" | "RawMaterialPurchase" | "ProductionBatch" | string | null
  sourceId?: number | null
  status: "Draft" | "Submitted" | "Approved" | "Rejected" | "Cancelled" | string
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface WaterExpenseInput {
  expenseDate?: string | null
  waterExpenseCategoryId: number
  description?: string | null
  amount: number
  paidTo?: string | null
  paymentMethod: string
  waterCashAccountId?: number | null
  receiptUrl?: string | null
  linkedWaterVehicleId?: number | null
  linkedWaterMachineId?: number | null
  linkedWaterProductionBatchId?: number | null
  notes?: string | null
  supplierId?: number | null
}

// Migration 076 — Supplier master list (Paid To dropdown source).
export interface WaterSupplier {
  waterSupplierId: number
  farmId: string
  supplierName: string
  contactPerson?: string | null
  phone?: string | null
  email?: string | null
  address?: string | null
  supplierType?: string | null
  notes?: string | null
  isActive: boolean
  isDeleted: boolean
  createdBy?: string | null
  createdAt: string
  updatedBy?: string | null
  updatedAt?: string | null
}

export interface WaterSupplierInput {
  supplierName: string
  contactPerson?: string | null
  phone?: string | null
  email?: string | null
  address?: string | null
  supplierType?: string | null
  notes?: string | null
  isActive?: boolean
}

// The §1 SupplierType examples. Used to power the dropdown on the form.
// Plain string so users can still type "Other" or future categories freely.
export const WATER_SUPPLIER_TYPES = [
  "Raw Material Supplier",
  "Packaging Supplier",
  "Fuel Supplier",
  "Machine Parts Supplier",
  "Vehicle Repair Supplier",
  "Utility Provider",
  "Service Provider",
  "Other",
] as const

export interface WaterCashAccount {
  waterCashAccountId: number
  farmId: string
  accountName: string
  accountType: string
  openingBalance: number
  currentBalance: number
  allowNegativeBalance: boolean
  isActive: boolean
  notes?: string | null
}

export interface WaterCashTransaction {
  waterCashTransactionId: number
  farmId: string
  waterCashAccountId: number
  accountName?: string | null
  transactionDate: string
  transactionType: string
  sourceType?: string | null
  sourceId?: number | null
  amount: number
  description?: string | null
  createdAt: string
}

export interface WaterCashTransfer {
  waterCashTransferId: number
  farmId: string
  fromWaterCashAccountId: number
  fromAccountName?: string | null
  toWaterCashAccountId: number
  toAccountName?: string | null
  transferDate: string
  amount: number
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
}

// ----- Expense categories
export const listWaterExpenseCategories = () =>
  jget<WaterExpenseCategory[]>(`/Water/expense-categories?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterExpenseCategory = (input: { name: string; description?: string | null; isActive?: boolean }) =>
  jsend<{ waterExpenseCategoryId: number }>(`/Water/expense-categories`, "POST", { ...input, farmId: activeFarmId(), isActive: input.isActive ?? true })

export const updateWaterExpenseCategory = (id: number, input: { name: string; description?: string | null; isActive: boolean }) =>
  jsend<void>(`/Water/expense-categories/${id}`, "PUT", { ...input, waterExpenseCategoryId: id, farmId: activeFarmId() })

export const deleteWaterExpenseCategory = (id: number) =>
  jsend<void>(`/Water/expense-categories/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Expenses
export const listWaterExpenses = (opts?: { status?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterExpense[]>(`/Water/expenses?${qs.toString()}`)
}

export const getWaterExpense = (id: number) =>
  jget<WaterExpense>(`/Water/expenses/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterExpense = (input: WaterExpenseInput) =>
  jsend<WaterExpense>(`/Water/expenses`, "POST", { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })

export const submitWaterExpense = (id: number) =>
  jsend<void>(`/Water/expenses/${id}/submit?farmId=${encodeURIComponent(activeFarmId())}`, "POST")

export const approveWaterExpense = (id: number) =>
  jsend<void>(`/Water/expenses/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

export const rejectWaterExpense = (id: number, reason?: string) =>
  jsend<void>(`/Water/expenses/${id}/reject?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST", { reason })

export const cancelWaterExpense = (id: number, reason?: string) =>
  jsend<void>(`/Water/expenses/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}&cancelledBy=${encodeURIComponent(currentUserId() || "")}`, "POST", { reason })

export const deleteWaterExpense = (id: number) =>
  jsend<void>(`/Water/expenses/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

export const seedWaterFinanceDefaults = () =>
  jsend<{ expenseCategoryCount: number; cashAccountCount: number }>(`/Water/expenses/seed-defaults?farmId=${encodeURIComponent(activeFarmId())}`, "POST")

// ----- Suppliers (Migration 076)
export const listWaterSuppliers = (opts?: { includeInactive?: boolean; search?: string }) => {
  const q = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.includeInactive) q.set("includeInactive", "true")
  if (opts?.search) q.set("search", opts.search)
  return jget<WaterSupplier[]>(`/Water/suppliers?${q.toString()}`)
}

export const getWaterSupplier = (id: number) =>
  jget<WaterSupplier>(`/Water/suppliers/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterSupplier = (input: WaterSupplierInput) =>
  jsend<WaterSupplier>(`/Water/suppliers`, "POST", { ...input, farmId: activeFarmId(), createdBy: currentUserId() })

export const updateWaterSupplier = (id: number, input: WaterSupplierInput) =>
  jsend<WaterSupplier>(`/Water/suppliers/${id}`, "PUT", { ...input, waterSupplierId: id, farmId: activeFarmId(), updatedBy: currentUserId() })

export const deleteWaterSupplier = (id: number) =>
  jsend<void>(`/Water/suppliers/${id}?farmId=${encodeURIComponent(activeFarmId())}&deletedBy=${encodeURIComponent(currentUserId() || "")}`, "DELETE")

// ----- Cash accounts
export const listWaterCashAccounts = () =>
  jget<WaterCashAccount[]>(`/Water/cash-accounts?farmId=${encodeURIComponent(activeFarmId())}`)

export const getWaterCashAccount = (id: number) =>
  jget<WaterCashAccount>(`/Water/cash-accounts/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterCashAccount = (input: { accountName: string; accountType: string; openingBalance?: number; allowNegativeBalance?: boolean; notes?: string | null }) =>
  jsend<{ waterCashAccountId: number }>(`/Water/cash-accounts`, "POST", { ...input, farmId: activeFarmId(), openingBalance: input.openingBalance ?? 0, allowNegativeBalance: input.allowNegativeBalance ?? false })

export const updateWaterCashAccount = (id: number, input: { accountName: string; accountType: string; allowNegativeBalance: boolean; isActive: boolean; notes?: string | null }) =>
  jsend<void>(`/Water/cash-accounts/${id}`, "PUT", { ...input, waterCashAccountId: id, farmId: activeFarmId() })

export const deleteWaterCashAccount = (id: number) =>
  jsend<void>(`/Water/cash-accounts/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

export const reconcileWaterCashBalances = () =>
  jsend<void>(`/Water/cash-accounts/reconcile-balances?farmId=${encodeURIComponent(activeFarmId())}`, "POST")

// Manual balance adjustment. amount is signed: positive adds cash, negative removes it.
export const adjustWaterCashAccount = (id: number, input: { amount: number; reason: string }) =>
  jsend<void>(`/Water/cash-accounts/${id}/adjust?farmId=${encodeURIComponent(activeFarmId())}`, "POST",
    { amount: input.amount, reason: input.reason, createdBy: currentUserId() || null })

export const listWaterCashTransactions = (opts?: { cashAccountId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.cashAccountId) qs.append("cashAccountId", String(opts.cashAccountId))
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterCashTransaction[]>(`/Water/cash-accounts/transactions?${qs.toString()}`)
}

// ----- Cash transfers
export const listWaterCashTransfers = (status?: string) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (status) qs.append("status", status)
  return jget<WaterCashTransfer[]>(`/Water/cash-transfers?${qs.toString()}`)
}

export const createWaterCashTransfer = (input: { fromWaterCashAccountId: number; toWaterCashAccountId: number; amount: number; transferDate?: string; notes?: string | null }) =>
  jsend<{ waterCashTransferId: number }>(`/Water/cash-transfers`, "POST", { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })

export const approveWaterCashTransfer = (id: number) =>
  jsend<void>(`/Water/cash-transfers/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

export const cancelWaterCashTransfer = (id: number) =>
  jsend<void>(`/Water/cash-transfers/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")

// =============================================================================
// W5: Company profile + setup
// =============================================================================

export interface WaterCompanyProfile {
  waterCompanyProfileId: number
  farmId: string
  brandName?: string | null
  businessType: string
  productionSiteAddress?: string | null
  mainLocation?: string | null
  waterSourceType: string
  defaultCurrency: string
  defaultBagSachetCount: number
  ownerName?: string | null
  phoneNumber?: string | null
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface WaterCompanySetupInput {
  brandName?: string | null
  businessType?: string
  productionSiteAddress?: string | null
  mainLocation?: string | null
  waterSourceType?: string
  defaultCurrency?: string
  defaultBagSachetCount?: number
  ownerName?: string | null
  phoneNumber?: string | null
  notes?: string | null
}

// 404 from this endpoint = "no Water profile set up yet" (by design — backend
// returns NotFound() when profile row doesn't exist). Treat that as null so
// the dashboard can render and the user is steered to the setup page.
export const getWaterCompanyProfile = async (): Promise<WaterCompanyProfile | null> => {
  try {
    return await jget<WaterCompanyProfile>(`/Water/company?farmId=${encodeURIComponent(activeFarmId())}`)
  } catch (e) {
    if (e instanceof Error && /-> 404/.test(e.message)) return null
    throw e
  }
}

export const setupWaterCompany = (input: WaterCompanySetupInput) =>
  jsend<WaterCompanyProfile>(`/Water/company/setup`, "POST", { ...input, farmId: activeFarmId() })

export const updateWaterCompanyProfile = (input: WaterCompanySetupInput) =>
  jsend<WaterCompanyProfile>(`/Water/company?farmId=${encodeURIComponent(activeFarmId())}`, "PUT", input)

// =============================================================================
// W6: Staff, Attendance, Payroll
// =============================================================================

export interface WaterStaff {
  waterStaffId: number
  farmId: string
  firstName: string
  lastName: string
  phoneNumber?: string | null
  email?: string | null
  role: string
  salaryType: string
  basePay: number
  commissionRate?: number | null
  assignedWaterVehicleId?: number | null
  assignedWaterRouteId?: number | null
  isActive: boolean
  isDeleted: boolean
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface WaterStaffInput {
  firstName: string
  lastName: string
  phoneNumber?: string | null
  email?: string | null
  role: string
  salaryType: string
  basePay: number
  commissionRate?: number | null
  assignedWaterVehicleId?: number | null
  assignedWaterRouteId?: number | null
  isActive?: boolean
  notes?: string | null
}

export interface WaterStaffAttendance {
  waterStaffAttendanceId: number
  farmId: string
  waterStaffId: number
  staffName?: string | null
  attendanceDate: string
  clockIn?: string | null
  clockOut?: string | null
  shift?: string | null
  status: string
  notes?: string | null
  createdBy?: string | null
  createdAt: string
}

export interface WaterStaffAttendanceUpsert {
  waterStaffId: number
  attendanceDate: string
  clockIn?: string | null
  clockOut?: string | null
  shift?: string | null
  status: string
  notes?: string | null
}

export interface WaterPayrollItem {
  waterPayrollItemId: number
  waterPayrollRunId: number
  waterStaffId: number
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

export interface WaterPayrollRun {
  waterPayrollRunId: number
  farmId: string
  periodStart: string
  periodEnd: string
  payDate?: string | null
  totalGrossPay: number
  totalDeductions: number
  totalNetPay: number
  status: "Draft" | "Pending" | "Approved" | "Paid" | "Reopened" | "Cancelled" | string
  waterCashAccountId?: number | null
  cashAccountName?: string | null
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  paidBy?: string | null
  paidAt?: string | null
  // Migration 080 — audit trail for Unapprove/Reapprove cycle.
  reopenedBy?: string | null
  reopenedAt?: string | null
  reopenReason?: string | null
  reapprovedBy?: string | null
  reapprovedAt?: string | null
  createdAt: string
  updatedAt?: string | null
  items?: WaterPayrollItem[]
}

// ----- Staff
export const listWaterStaff = (role?: string) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (role) qs.append("role", role)
  return jget<WaterStaff[]>(`/Water/staff?${qs.toString()}`)
}

export const getWaterStaff = (id: number) =>
  jget<WaterStaff>(`/Water/staff/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterStaff = (input: WaterStaffInput) =>
  jsend<WaterStaff>(`/Water/staff`, "POST", { ...input, farmId: activeFarmId(), isActive: input.isActive ?? true })

export const updateWaterStaff = (id: number, input: WaterStaffInput) =>
  jsend<void>(`/Water/staff/${id}`, "PUT", { ...input, waterStaffId: id, farmId: activeFarmId() })

export const deleteWaterStaff = (id: number) =>
  jsend<void>(`/Water/staff/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Attendance
export const listWaterStaffAttendance = (opts?: { staffId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.staffId) qs.append("staffId", String(opts.staffId))
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterStaffAttendance[]>(`/Water/staff-attendance?${qs.toString()}`)
}

export const upsertWaterStaffAttendance = (input: WaterStaffAttendanceUpsert) =>
  jsend<WaterStaffAttendance>(`/Water/staff-attendance?farmId=${encodeURIComponent(activeFarmId())}&createdBy=${encodeURIComponent(currentUserId() || "")}`, "POST", input)

export const deleteWaterStaffAttendance = (id: number) =>
  jsend<void>(`/Water/staff-attendance/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Payroll
export const listWaterPayrollRuns = (status?: string) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (status) qs.append("status", status)
  return jget<WaterPayrollRun[]>(`/Water/payroll-runs?${qs.toString()}`)
}

export const getWaterPayrollRun = (id: number) =>
  jget<WaterPayrollRun>(`/Water/payroll-runs/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterPayrollRun = (input: { periodStart: string; periodEnd: string; payDate?: string | null; waterCashAccountId?: number | null; notes?: string | null }) =>
  jsend<{ waterPayrollRunId: number }>(`/Water/payroll-runs?createdBy=${encodeURIComponent(currentUserId() || "")}`, "POST", { ...input, farmId: activeFarmId() })

export const upsertWaterPayrollItem = (runId: number, input: { waterStaffId: number; basicPay: number; dailyWage: number; commission: number; bonus: number; deductions: number; paymentMethod?: string | null; notes?: string | null }) =>
  jsend<WaterPayrollItem>(`/Water/payroll-runs/${runId}/items?farmId=${encodeURIComponent(activeFarmId())}`, "POST", input)

export const deleteWaterPayrollItem = (itemId: number) =>
  jsend<void>(`/Water/payroll-runs/items/${itemId}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

export const approveWaterPayrollRun = (id: number) =>
  jsend<void>(`/Water/payroll-runs/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

export const markWaterPayrollRunPaid = (id: number, payDate?: string) =>
  jsend<void>(`/Water/payroll-runs/${id}/mark-paid?farmId=${encodeURIComponent(activeFarmId())}&paidBy=${encodeURIComponent(currentUserId() || "")}`, "POST", { payDate: payDate ?? null })

export const cancelWaterPayrollRun = (id: number, reason?: string) =>
  jsend<void>(`/Water/payroll-runs/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}&cancelledBy=${encodeURIComponent(currentUserId() || "")}`, "POST", { reason })

// Migration 080 — flip Approved/Paid back to Reopened so corrections can be made.
// Reverses the linked Expense (SourceType=Payroll) so books reconcile.
export const unapproveWaterPayrollRun = (id: number, reason: string) =>
  jsend<void>(`/Water/payroll-runs/${id}/unapprove?farmId=${encodeURIComponent(activeFarmId())}&reopenedBy=${encodeURIComponent(currentUserId() || "")}`, "POST", { reason })

// Migration 080 — hard delete a Draft / Pending / Reopened run.
// Backend rejects if active linked expense exists; call unapprove first if needed.
export const deleteWaterPayrollRun = (id: number) =>
  jsend<void>(`/Water/payroll-runs/${id}?farmId=${encodeURIComponent(activeFarmId())}&deletedBy=${encodeURIComponent(currentUserId() || "")}`, "DELETE")

// Migration 082 — Full Payroll Run Details with YTD totals + linked expense.
export interface WaterPayrollYtdTotals {
  year: number
  ytdGrossPaid: number
  ytdDeductions: number
  ytdNetPaid: number
  totalPayrollRuns: number
  totalStaffPaid: number
}
export interface WaterPayrollYtdStaffRow {
  waterStaffId: number
  staffName?: string | null
  staffRole?: string | null
  ytdBasic: number
  ytdDaily: number
  ytdCommission: number
  ytdBonus: number
  ytdDeductions: number
  ytdGross: number
  ytdNet: number
}
export interface WaterPayrollLinkedExpense {
  waterExpenseId: number
  farmId: string
  expenseDate: string
  waterExpenseCategoryId: number
  categoryName?: string | null
  description?: string | null
  amount: number
  paymentMethod?: string | null
  waterCashAccountId?: number | null
  cashAccountName?: string | null
  status?: string | null
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  sourceType?: string | null
  sourceId?: number | null
  createdAt: string
  updatedAt?: string | null
}
export interface WaterPayrollRunDetails {
  run: WaterPayrollRun | null
  ytdTotals: WaterPayrollYtdTotals | null
  ytdByStaff: WaterPayrollYtdStaffRow[]
  linkedExpense: WaterPayrollLinkedExpense | null
}

export const getWaterPayrollRunDetails = (id: number) =>
  jget<WaterPayrollRunDetails>(`/Water/payroll-runs/${id}/details?farmId=${encodeURIComponent(activeFarmId())}`)

// =============================================================================
// W7: Maintenance Logs
// =============================================================================

export interface WaterMaintenanceLog {
  waterMaintenanceLogId: number
  farmId: string
  assetType: string
  assetId?: number | null
  assetLabel?: string | null
  issueDate: string
  issueDescription: string
  reportedByWaterStaffId?: number | null
  technicianName?: string | null
  repairCost: number
  partsReplaced?: string | null
  downtimeHours?: number | null
  status: "Open" | "InProgress" | "Completed" | "Cancelled" | string
  completedDate?: string | null
  waterCashAccountId?: number | null
  cashAccountName?: string | null
  cashTransactionWritten: boolean
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface WaterMaintenanceLogInput {
  assetType: string
  assetId?: number | null
  assetLabel?: string | null
  issueDate?: string | null
  issueDescription: string
  reportedByWaterStaffId?: number | null
  technicianName?: string | null
  repairCost?: number
  partsReplaced?: string | null
  downtimeHours?: number | null
  notes?: string | null
}

export interface WaterMaintenanceAlert {
  assetType: string
  assetId: number
  assetLabel: string
  nextDueDate: string
  daysUntilDue: number
  severity: "Overdue" | "DueSoon" | "Upcoming" | string
}

export const listWaterMaintenanceLogs = (opts?: { status?: string; assetType?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.assetType) qs.append("assetType", opts.assetType)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterMaintenanceLog[]>(`/Water/maintenance-logs?${qs.toString()}`)
}

export const createWaterMaintenanceLog = (input: WaterMaintenanceLogInput) =>
  jsend<WaterMaintenanceLog>(`/Water/maintenance-logs`, "POST", { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null, repairCost: input.repairCost ?? 0 })

export const updateWaterMaintenanceLog = (id: number, input: WaterMaintenanceLogInput & { status: string }) =>
  jsend<void>(`/Water/maintenance-logs/${id}`, "PUT", { ...input, waterMaintenanceLogId: id, farmId: activeFarmId(), repairCost: input.repairCost ?? 0 })

export const completeWaterMaintenanceLog = (id: number, opts?: { completedDate?: string; waterCashAccountId?: number | null }) =>
  jsend<void>(`/Water/maintenance-logs/${id}/complete?farmId=${encodeURIComponent(activeFarmId())}&completedBy=${encodeURIComponent(currentUserId() || "")}`, "POST", opts ?? {})

export const deleteWaterMaintenanceLog = (id: number) =>
  jsend<void>(`/Water/maintenance-logs/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

export const listWaterMaintenanceDueAlerts = () =>
  jget<WaterMaintenanceAlert[]>(`/Water/maintenance-logs/due-alerts?farmId=${encodeURIComponent(activeFarmId())}`)

// =============================================================================
// W1: Production (boreholes, machines, production batches, quality tests)
// =============================================================================

export interface WaterBorehole {
  waterBoreholeId: number
  farmId: string
  boreholeName: string
  location?: string | null
  pumpType?: string | null
  pumpCapacity?: string | null
  tankCapacity?: string | null
  waterTreatmentMethod?: string | null
  filtrationSystem?: string | null
  uvSterilizationAvailable?: boolean
  maintenanceFrequencyDays?: number | null
  lastMaintenanceDate?: string | null
  nextMaintenanceDate?: string | null
  waterQualityTestDueDate?: string | null
  status: "Active" | "Inactive" | "UnderMaintenance" | string
  notes?: string | null
}

export interface WaterMachine {
  waterMachineId: number
  farmId: string
  machineName: string
  machineNumber?: string | null
  machineType?: string | null
  manufacturer?: string | null
  purchaseDate?: string | null
  capacityPerHour?: number | null
  assignedOperatorStaffId?: number | null
  maintenanceFrequencyDays?: number | null
  lastMaintenanceDate?: string | null
  nextMaintenanceDate?: string | null
  status: "Active" | "Down" | "UnderMaintenance" | string
  notes?: string | null
}

export interface WaterProductionBatch {
  waterProductionBatchId: number
  farmId: string
  batchNumber?: string | null
  productionDate: string
  shift?: string | null
  waterMachineId?: number | null
  machineName?: string | null
  waterBoreholeId?: number | null
  boreholeName?: string | null
  operatorStaffId?: number | null
  startTime?: string | null
  endTime?: string | null
  waterProductId?: number | null
  productName?: string | null
  bagsProduced: number
  sachetsPerBag: number
  totalSachetsProduced?: number
  looseSachetsProduced?: number
  rejectedSachets?: number
  damagedBags?: number
  packagingRollsUsed?: number | null
  estimatedWaterUsedLitres?: number | null
  electricityCost?: number
  fuelCost?: number
  laborCost?: number
  otherProductionCost?: number
  totalProductionCost?: number
  // Migration 063: roll-up of raw material cost. The all-in cost displayed in
  // the UI is totalProductionCost + rawMaterialCost.
  rawMaterialCost?: number
  // Migration 067 — server-side derived fields. The list page now binds the
  // Cost (=allInCost) and Cost/Bag columns directly to these so they match
  // the modal summary.
  goodBags?: number
  allInCost?: number
  costPerBag?: number
  productionEfficiencyPercent?: number
  // Migration 067 — 'SingleMachine' | 'AllMachines'.
  machineScope?: "SingleMachine" | "AllMachines" | string
  qualityStatus: "Pending" | "Passed" | "Failed" | string
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  createdAt: string
  updatedAt?: string | null
  // Migration 193 — set when this record was generated by a Batch Production
  // allocation (labelled "Daily Production" in the DB/API). Such a record must
  // be managed from its parent batch, never edited or reopened on its own.
  waterDailyProductionId?: number | null
  waterDailyProductionAllocationId?: number | null
  sourceType?: "ManualSingleBatch" | "DailyProductionAllocation" | string
  // Inbound only — sent on POST/PUT to /production-batches.
  materialsUsed?: WaterProductionMaterialUsageInput[]
}

/** True when the record belongs to a Batch Production parent (migration 193). */
export const isDailyProductionChild = (b: WaterProductionBatch): boolean =>
  b.sourceType === "DailyProductionAllocation" || !!b.waterDailyProductionId

// =============================================================================
// Production Recipes + Raw Material Usage (migration 063)
// =============================================================================

export interface WaterProductionRecipeItem {
  waterProductionRecipeItemId: number
  waterProductionRecipeId: number
  waterRawMaterialItemId: number
  rawMaterialName?: string | null
  rawMaterialUnit?: string | null
  rawMaterialStock?: number | null
  latestUnitCost?: number | null
  quantityPerOutputUnit: number
  outputUnit: string
  wasteAllowancePercent: number
  isOptional: boolean
  displayOrder: number
  notes?: string | null
  createdAt?: string
  updatedAt?: string | null
}

export interface WaterProductionRecipe {
  waterProductionRecipeId: number
  farmId: string
  waterProductId: number
  recipeName: string
  isDefault: boolean
  isActive: boolean
  notes?: string | null
  createdBy?: string | null
  createdAt: string
  updatedBy?: string | null
  updatedAt?: string | null
  items: WaterProductionRecipeItem[]
}

// Input for POST/PUT /production-batches — the per-batch "Raw Materials Used"
// table. Property names match the SP's OPENJSON contract.
export interface WaterProductionMaterialUsageInput {
  waterRawMaterialItemId: number
  quantityUsed: number
  expectedQuantityUsed?: number | null
  unitCost?: number | null
  varianceReason?: string | null
  notes?: string | null
}

export interface WaterProductionMaterialUsageRow {
  waterRawMaterialUsageId: number
  farmId: string
  waterRawMaterialItemId: number
  itemName?: string | null
  unitOfMeasure?: string | null
  currentStock?: number | null
  waterProductionBatchId?: number | null
  batchNumber?: string | null
  finishedProductName?: string | null
  usedDate: string
  quantityUsed: number
  expectedQuantityUsed?: number | null
  variance: number
  varianceReason?: string | null
  unitCost?: number | null
  totalCost?: number | null
  usedByStaffId?: number | null
  notes?: string | null
  createdAt: string
}

// Body for PUT /products/{id}/recipe.
export interface WaterProductionRecipeUpsertInput {
  recipeName?: string
  notes?: string | null
  items: Array<{
    waterRawMaterialItemId: number
    quantityPerOutputUnit: number
    outputUnit?: string
    wasteAllowancePercent?: number
    isOptional?: boolean
    displayOrder?: number
    notes?: string | null
  }>
}

export interface WaterQualityTest {
  waterQualityTestId: number
  farmId: string
  waterBoreholeId?: number | null
  waterProductionBatchId?: number | null
  testDate: string
  testType?: string | null
  phLevel?: number | null
  tds?: number | null
  turbidity?: number | null
  chlorineLevel?: number | null
  result: "Passed" | "Failed" | "Pending" | string
  testedBy?: string | null
  labName?: string | null
  attachmentUrl?: string | null
  nextTestDate?: string | null
  notes?: string | null
}

// ----- Boreholes
export const listWaterBoreholes = () =>
  jget<WaterBorehole[]>(`/Water/boreholes?farmId=${encodeURIComponent(activeFarmId())}`)
export const createWaterBorehole = (input: Omit<WaterBorehole, "waterBoreholeId" | "farmId">) =>
  jsend<WaterBorehole>(`/Water/boreholes`, "POST", { ...input, farmId: activeFarmId() })
export const updateWaterBorehole = (id: number, input: Omit<WaterBorehole, "waterBoreholeId" | "farmId">) =>
  jsend<void>(`/Water/boreholes/${id}`, "PUT", { ...input, waterBoreholeId: id, farmId: activeFarmId() })
export const deleteWaterBorehole = (id: number) =>
  jsend<void>(`/Water/boreholes/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Machines
export const listWaterMachines = () =>
  jget<WaterMachine[]>(`/Water/machines?farmId=${encodeURIComponent(activeFarmId())}`)
export const createWaterMachine = (input: Omit<WaterMachine, "waterMachineId" | "farmId">) =>
  jsend<WaterMachine>(`/Water/machines`, "POST", { ...input, farmId: activeFarmId() })
export const updateWaterMachine = (id: number, input: Omit<WaterMachine, "waterMachineId" | "farmId">) =>
  jsend<void>(`/Water/machines/${id}`, "PUT", { ...input, waterMachineId: id, farmId: activeFarmId() })
export const deleteWaterMachine = (id: number) =>
  jsend<void>(`/Water/machines/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Production batches
export const listWaterProductionBatches = (opts?: { status?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterProductionBatch[]>(`/Water/production-batches?${qs.toString()}`)
}
export const getWaterProductionBatch = (id: number) =>
  jget<WaterProductionBatch>(`/Water/production-batches/${id}?farmId=${encodeURIComponent(activeFarmId())}`)
export const updateWaterProductionBatch = (id: number, input: Partial<WaterProductionBatch> & { bagsProduced: number; sachetsPerBag: number; productionDate?: string }) =>
  jsend<void>(`/Water/production-batches/${id}`, "PUT", { ...input, waterProductionBatchId: id, farmId: activeFarmId() })
export const createWaterProductionBatch = (input: Partial<WaterProductionBatch> & { bagsProduced: number; sachetsPerBag: number; productionDate?: string }) =>
  jsend<WaterProductionBatch>(`/Water/production-batches`, "POST", { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })
/** Open purchase lots, for previewing what a production batch will draw. */
export const listWaterRawMaterialOpenLots = (itemId?: number) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (itemId) qs.append("itemId", String(itemId))
  return jget<WaterRawMaterialLot[]>(`/Water/raw-material-items/open-lots?${qs.toString()}`)
}

export const approveWaterProductionBatch = (id: number) =>
  jsend<void>(`/Water/production-batches/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")
export const cancelWaterProductionBatch = (id: number) =>
  jsend<void>(`/Water/production-batches/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const reopenWaterProductionBatch = (id: number) =>
  jsend<void>(`/Water/production-batches/${id}/reopen?farmId=${encodeURIComponent(activeFarmId())}&reopenedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

// Migration 063: read back the per-batch materials used so an edit dialog can
// preload the same rows. Returns [] when the batch never logged any.
export const listWaterProductionBatchMaterials = (batchId: number) =>
  jget<WaterProductionMaterialUsageRow[]>(`/Water/production-batches/${batchId}/materials?farmId=${encodeURIComponent(activeFarmId())}`)

// Migration 067 — Details view: linked loss, expense and stock-txn records.
export interface WaterProductionLoss {
  waterProductionLossId: number
  farmId: string
  lossDate: string
  lossType: string
  sourceType: string
  sourceId?: number | null
  waterProductId?: number | null
  productName?: string | null
  batchNumber?: string | null
  bagsLost: number
  sachetsLost: number
  sachetsPerBag: number
  costPerBag: number
  bagsLossValue: number
  sachetsLossValue: number
  totalValue: number
  reason?: string | null
  status: string
  notes?: string | null
  createdBy?: string | null
  createdAt: string
}

export interface WaterProductionLinkedExpense {
  waterExpenseId: number
  farmId: string
  expenseDate: string
  waterExpenseCategoryId: number
  categoryName?: string | null
  description?: string | null
  amount: number
  paidTo?: string | null
  paymentMethod?: string | null
  waterCashAccountId?: number | null
  cashAccountName?: string | null
  linkedWaterProductionBatchId?: number | null
  status?: string | null
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  createdAt: string
}

export interface WaterProductionLinkedStockTxn {
  waterStockTransactionId: number
  waterProductId: number
  productName?: string | null
  txnType?: string | null
  quantity: number
  unitCost?: number | null
  note?: string | null
  createdAt: string
}

export const listWaterProductionBatchLinkedLosses = (batchId: number) =>
  jget<WaterProductionLoss[]>(`/Water/production-batches/${batchId}/linked-losses?farmId=${encodeURIComponent(activeFarmId())}`)

export const listWaterProductionBatchLinkedExpenses = (batchId: number) =>
  jget<WaterProductionLinkedExpense[]>(`/Water/production-batches/${batchId}/linked-expenses?farmId=${encodeURIComponent(activeFarmId())}`)

export const listWaterProductionBatchLinkedStockTxns = (batchId: number) =>
  jget<WaterProductionLinkedStockTxn[]>(`/Water/production-batches/${batchId}/linked-stock-txns?farmId=${encodeURIComponent(activeFarmId())}`)

// Migration 067 — standalone Loss page.
export const listWaterProductionLosses = (opts?: { fromDate?: string; toDate?: string; status?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate)   qs.append("toDate",   opts.toDate)
  if (opts?.status)   qs.append("status",   opts.status)
  return jget<WaterProductionLoss[]>(`/Water/production-losses?${qs.toString()}`)
}

// ----- Production Recipes -----
// Returns null when the product has no recipe yet. The backend emits 200 with
// either a recipe payload or `null` body — distinguishing "no recipe" from a
// network error.
export const getWaterProductionRecipe = async (waterProductId: number): Promise<WaterProductionRecipe | null> => {
  const r = await jget<WaterProductionRecipe | null>(`/Water/products/${waterProductId}/recipe?farmId=${encodeURIComponent(activeFarmId())}`)
  return r ?? null
}

export const upsertWaterProductionRecipe = (waterProductId: number, input: WaterProductionRecipeUpsertInput) =>
  jsend<{ waterProductionRecipeId: number }>(
    `/Water/products/${waterProductId}/recipe?farmId=${encodeURIComponent(activeFarmId())}&updatedBy=${encodeURIComponent(currentUserId() || "")}`,
    "PUT",
    {
      recipeName: input.recipeName ?? "Default",
      notes: input.notes ?? null,
      items: input.items,
    },
  )

export const deleteWaterProductionRecipe = (waterProductId: number, recipeId: number) =>
  jsend<void>(`/Water/products/${waterProductId}/recipe/${recipeId}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Raw Material Usage history (for /water-raw-materials → Usage History tab) -----
export const listWaterRawMaterialUsageHistory = (opts?: { itemId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.itemId) qs.append("itemId", String(opts.itemId))
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterProductionMaterialUsageRow[]>(`/Water/raw-material-usage/history?${qs.toString()}`)
}

// ----- Quality tests
export const listWaterQualityTests = (opts?: { boreholeId?: number; batchId?: number }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.boreholeId) qs.append("boreholeId", String(opts.boreholeId))
  if (opts?.batchId) qs.append("batchId", String(opts.batchId))
  return jget<WaterQualityTest[]>(`/Water/quality-tests?${qs.toString()}`)
}
export const createWaterQualityTest = (input: Omit<WaterQualityTest, "waterQualityTestId" | "farmId">) =>
  jsend<WaterQualityTest>(`/Water/quality-tests`, "POST", { ...input, farmId: activeFarmId() })

// =============================================================================
// W2: Distribution (drivers, vehicles, routes, vehicle loadings, driver returns)
// =============================================================================

export interface WaterDriver {
  waterDriverId: number
  farmId: string
  driverName: string
  phoneNumber?: string | null
  licenseNumber?: string | null
  // Backend column name is DefaultVehicleId (NOT AssignedWaterVehicleId — that
  // belongs to WaterStaff). The previous mismatch was the reason the assigned
  // vehicle never persisted across save (Prompt 2 §6).
  defaultVehicleId?: number | null
  defaultRouteId?: number | null
  basePay?: number | null
  commissionPerBag?: number | null
  isActive: boolean
  notes?: string | null
  // Legacy alias — accepted by some older callers. New code should use
  // defaultVehicleId. Kept here to keep callers compiling during rollout.
  assignedWaterVehicleId?: number | null
  // #18 — links the driver to its AspNetUsers employee.
  employeeUserId?: string | null
}

export interface WaterVehicle {
  waterVehicleId: number
  farmId: string
  vehicleName: string
  vehicleType: string
  registrationNumber?: string | null
  defaultDriverStaffId?: number | null
  capacityBags?: number | null
  fuelType?: string | null
  status: "Active" | "Inactive" | "UnderMaintenance" | string
  notes?: string | null
}

export interface WaterRoute {
  waterRouteId: number
  farmId: string
  routeName: string
  areaCovered?: string | null
  defaultDriverStaffId?: number | null
  // Backend column is DefaultVehicleId (NOT DefaultWaterVehicleId — the name
  // mismatch was breaking persistence per Prompt 2 §7).
  defaultVehicleId?: number | null
  expectedCustomers?: number | null
  expectedBagsSold?: number | null
  notes?: string | null
}

export interface WaterVehicleLoading {
  waterVehicleLoadingId: number
  farmId: string
  loadDate: string
  waterVehicleId: number
  vehicleName?: string | null
  // Backend renamed driverStaffId -> waterDriverId in migration 040. Both
  // names are kept as optionals for older callers; new code should use
  // waterDriverId.
  driverStaffId?: number | null
  waterDriverId?: number | null
  driverName?: string | null
  assistantStaffId?: number | null
  waterRouteId?: number | null
  routeName?: string | null
  waterProductId?: number | null
  productName?: string | null
  bagsLoaded: number
  sachetsPerBag?: number
  expectedSellingPricePerBag?: number
  expectedCash?: number
  openingCashWithDriver?: number
  loadedByStaffId?: number | null
  status: "Loaded" | "Returned" | "Reconciled" | "Cancelled" | string
  notes?: string | null
  // Migration 064: multi-product items, sent on POST and returned via the
  // /items endpoint.
  items?: WaterVehicleLoadingItem[]
}

// Per-product line on a loading (migration 064).
export interface WaterVehicleLoadingItem {
  waterVehicleLoadingItemId?: number
  waterVehicleLoadingId?: number
  waterProductId: number
  productName?: string | null
  productUnit?: string | null
  bagsLoaded: number
  sachetsPerBag?: number
  unitPrice: number
  expectedAmount?: number
  notes?: string | null
  createdAt?: string
  updatedAt?: string | null
}

export interface WaterDriverReturn {
  waterDriverReturnId: number
  farmId: string
  waterVehicleLoadingId: number
  returnDate: string
  bagsSold: number
  bagsReturned: number
  bagsDamaged: number
  missingBags?: number
  cashCollected: number
  moMoCollected: number
  bankCollected: number
  creditSalesAmount: number
  // Migration 064: driver's cash float reconciliation.
  cashReturnedByDriver?: number
  approvedDeliveryExpenses?: number
  totalCollected?: number
  totalAccountedFor?: number
  expectedCash?: number
  shortageAmount?: number
  overageAmount?: number
  reconciledByStaffId?: number | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  status?: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
  // Joined for convenience (from spWaterDriverReturn_GetAll).
  waterVehicleId?: number | null
  waterDriverId?: number | null
  waterRouteId?: number | null
  vehicleName?: string | null
  driverName?: string | null
  routeName?: string | null
  loadingBagsLoaded?: number | null
  loadingExpectedCash?: number | null
  expectedSellingPricePerBag?: number | null
  // Migration 064: optional payloads on POST.
  items?: WaterDriverReturnItem[]
  customerSales?: WaterDriverReturnCustomerSaleInput[]
  expenses?: WaterDeliveryExpenseInput[]
  // Migration 083 — sales posting mode + primary customer.
  //   'Detailed'     → use customer breakdown rows (default; legacy).
  //   'OneCustomer'  → entire delivery sale posts to primaryCustomerId.
  //   'Summary'      → posts to the GeneralDelivery default customer.
  salesPostingMode?: "Detailed" | "OneCustomer" | "Summary" | string | null
  primaryCustomerId?: number | null
}

// Per-product reconciliation row (migration 064).
export interface WaterDriverReturnItem {
  waterDriverReturnItemId?: number
  waterDriverReturnId?: number
  waterProductId: number
  productName?: string | null
  bagsLoaded?: number
  bagsSold: number
  bagsReturned: number
  bagsDamaged: number
  unitPrice: number
  expectedSales?: number
  notes?: string | null
  createdAt?: string
  updatedAt?: string | null
}

// Customer breakdown row sent on POST.
export interface WaterDriverReturnCustomerSaleInput {
  waterCustomerId?: number | null
  customerLabel?: string | null
  cashPaid: number
  moMoPaid: number
  bankPaid: number
  creditAmount: number
  notes?: string | null
  items: Array<{
    waterProductId: number
    quantity: number
    unitPrice: number
  }>
}

// Customer breakdown row returned by GET — includes the generated WaterSale.
export interface WaterDriverReturnCustomerSaleRow {
  waterDriverReturnCustomerSaleId: number
  waterDriverReturnId: number
  waterCustomerId?: number | null
  customerName?: string | null
  customerLabel?: string | null
  totalAmount: number
  cashPaid: number
  moMoPaid: number
  bankPaid: number
  creditAmount: number
  generatedWaterSaleId?: number | null
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
  items: Array<{
    waterDriverReturnCustomerSaleItemId: number
    waterDriverReturnCustomerSaleId: number
    waterProductId: number
    productName?: string | null
    quantity: number
    unitPrice: number
    lineTotal: number
  }>
}

export interface WaterDeliveryExpenseInput {
  expenseCategory: string
  amount: number
  description?: string | null
  isApproved?: boolean
  notes?: string | null
}

export interface WaterDeliveryExpense {
  waterDeliveryExpenseId: number
  farmId: string
  waterDriverReturnId?: number | null
  waterVehicleLoadingId?: number | null
  expenseCategory: string
  amount: number
  description?: string | null
  isApproved: boolean
  notes?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
  // Migration 085 — populated by listWaterDeliveryExpenses(); null on the
  // per-return endpoint.
  returnDate?: string | null
  returnStatus?: string | null
  driverName?: string | null
  vehicleNumber?: string | null
}

// Migration 085 — list every delivery expense for the farm; powers the
// unified Expenses ledger on /water-expenses (alongside listWaterExpenses).
export const listWaterDeliveryExpenses = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate)   qs.append("toDate",   opts.toDate)
  return jget<WaterDeliveryExpense[]>(`/Water/delivery-expenses?${qs.toString()}`)
}

// ----- Vehicles
export const listWaterVehicles = () =>
  jget<WaterVehicle[]>(`/Water/vehicles?farmId=${encodeURIComponent(activeFarmId())}`)
export const createWaterVehicle = (input: Omit<WaterVehicle, "waterVehicleId" | "farmId">) =>
  jsend<WaterVehicle>(`/Water/vehicles`, "POST", { ...input, farmId: activeFarmId() })
export const updateWaterVehicle = (id: number, input: Omit<WaterVehicle, "waterVehicleId" | "farmId">) =>
  jsend<void>(`/Water/vehicles/${id}`, "PUT", { ...input, waterVehicleId: id, farmId: activeFarmId() })
export const deleteWaterVehicle = (id: number) =>
  jsend<void>(`/Water/vehicles/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Routes
export const listWaterRoutes = () =>
  jget<WaterRoute[]>(`/Water/routes?farmId=${encodeURIComponent(activeFarmId())}`)
export const createWaterRoute = (input: Omit<WaterRoute, "waterRouteId" | "farmId">) =>
  jsend<WaterRoute>(`/Water/routes`, "POST", { ...input, farmId: activeFarmId() })
export const updateWaterRoute = (id: number, input: Omit<WaterRoute, "waterRouteId" | "farmId">) =>
  jsend<void>(`/Water/routes/${id}`, "PUT", { ...input, waterRouteId: id, farmId: activeFarmId() })
export const deleteWaterRoute = (id: number) =>
  jsend<void>(`/Water/routes/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Drivers
export const listWaterDrivers = () =>
  jget<WaterDriver[]>(`/Water/drivers?farmId=${encodeURIComponent(activeFarmId())}`)
export const createWaterDriver = (input: Omit<WaterDriver, "waterDriverId" | "farmId">) =>
  jsend<WaterDriver>(`/Water/drivers`, "POST", { ...input, farmId: activeFarmId() })
export const updateWaterDriver = (id: number, input: Omit<WaterDriver, "waterDriverId" | "farmId">) =>
  jsend<void>(`/Water/drivers/${id}`, "PUT", { ...input, waterDriverId: id, farmId: activeFarmId() })
export const deleteWaterDriver = (id: number) =>
  jsend<void>(`/Water/drivers/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// #18 — drivers sourced from employees-with-driver-role (+ legacy standalone).
export const listWaterDriversForFarm = () =>
  jget<WaterDriver[]>(`/Water/drivers/list-for-farm?farmId=${encodeURIComponent(activeFarmId())}`)

// #18 — make an existing employee a driver (assigns role + upserts profile).
export const createWaterDriverFromEmployee = (input: {
  employeeUserId: string; role?: string; licenseNumber?: string | null;
  defaultVehicleId?: number | null; defaultRouteId?: number | null;
  basePay?: number | null; commissionPerBag?: number | null; notes?: string | null
}) =>
  jsend<WaterDriver>(`/Water/drivers/from-employee`, "POST", { ...input, farmId: activeFarmId() })

export const getEmployeeJobRoles = (employeeUserId: string) =>
  jget<string[]>(`/Water/drivers/job-roles?farmId=${encodeURIComponent(activeFarmId())}&employeeUserId=${encodeURIComponent(employeeUserId)}`)

export const setEmployeeJobRoles = (employeeUserId: string, rolesCsv: string) =>
  jsend<void>(`/Water/drivers/job-roles`, "POST", { farmId: activeFarmId(), employeeUserId, rolesCsv })

// ----- Vehicle loadings (Load Vehicle action)
export const listWaterVehicleLoadings = (opts?: { status?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterVehicleLoading[]>(`/Water/vehicle-loadings?${qs.toString()}`)
}
export const createWaterVehicleLoading = (input: Partial<WaterVehicleLoading> & { waterVehicleId: number; bagsLoaded: number }) =>
  jsend<WaterVehicleLoading>(`/Water/vehicle-loadings`, "POST", { ...input, farmId: activeFarmId() })
export const approveWaterVehicleLoading = (id: number) =>
  jsend<void>(`/Water/vehicle-loadings/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")
export const cancelWaterVehicleLoading = (id: number) =>
  jsend<void>(`/Water/vehicle-loadings/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")

// Migration 065: void a Draft or Loaded loading. Reverses LoadOut stock when
// the loading was already approved; blocks if a return references it.
export const voidWaterVehicleLoading = (id: number, reason?: string | null) =>
  jsend<void>(
    `/Water/vehicle-loadings/${id}/void?farmId=${encodeURIComponent(activeFarmId())}&voidedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST",
    { reason: reason ?? null },
  )

// ----- Driver returns (the reconciliation step after a vehicle returns)
export const listWaterDriverReturns = (opts?: { status?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterDriverReturn[]>(`/Water/driver-returns?${qs.toString()}`)
}
export const createWaterDriverReturn = (input: Partial<WaterDriverReturn> & { waterVehicleLoadingId: number; bagsSold: number; bagsReturned: number; bagsDamaged: number; cashCollected: number; moMoCollected: number; bankCollected: number; creditSalesAmount: number }) =>
  jsend<WaterDriverReturn>(`/Water/driver-returns`, "POST", { ...input, farmId: activeFarmId() })
export const approveWaterDriverReturn = (id: number) =>
  jsend<void>(`/Water/driver-returns/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")
export const cancelWaterDriverReturn = (id: number) =>
  jsend<void>(`/Water/driver-returns/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
// Migration 071: Uncancel — Cancelled → Draft. After uncancel the operator
// can Approve again to re-reconcile.
export const uncancelWaterDriverReturn = (id: number) =>
  jsend<void>(`/Water/driver-returns/${id}/uncancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
// Migration 072: admin-only hard delete of a Cancelled return + its items,
// customer-sales (and their items), and delivery expenses. The SP rejects
// non-Cancelled rows; the frontend gates the button behind permissions.isAdmin.
export const deleteWaterDriverReturn = (id: number) =>
  jsend<void>(`/Water/driver-returns/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// Migration 068: Reverse Reconciliation (Prompt 2 §3). Unwinds linked sales,
// payments and stock txns and flips the return back to Draft so the user can
// edit and re-reconcile.
export const reverseWaterDriverReturn = (id: number, reason: string) =>
  jsend<void>(
    `/Water/driver-returns/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}&reversedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST",
    { reason },
  )

// Migration 083 — Approve & Reconcile a Draft return in one shot.
// Validates bag accounting + posting-mode-specific rules, then materialises
// sales using the row's SalesPostingMode (Detailed | OneCustomer | Summary).
export const approveReconcileWaterDriverReturn = (id: number) =>
  jsend<void>(
    `/Water/driver-returns/${id}/approve-reconcile?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST",
  )

// Migration 083 — set the posting mode + primary customer on a Draft return.
export const updateWaterDriverReturnPostingMode = (
  id: number,
  body: { salesPostingMode: "Detailed" | "OneCustomer" | "Summary"; primaryCustomerId?: number | null },
) =>
  jsend<void>(
    `/Water/driver-returns/${id}/posting-mode?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    body,
  )

// Migration 068: Reload / Edit Load (Prompt 2 §4). Reverses LoadOut for the
// previous lines and applies the new ones. Header fields can be partially
// updated; Items === null leaves existing items alone.
export const reloadWaterVehicleLoading = (id: number, input: {
  waterDriverId?: number | null
  waterVehicleId?: number | null
  waterRouteId?: number | null
  loadDate?: string | null
  openingCashWithDriver?: number | null
  notes?: string | null
  items?: Array<{ waterProductId: number; bagsLoaded: number; unitPrice: number }> | null
}) =>
  jsend<void>(
    `/Water/vehicle-loadings/${id}/reload?farmId=${encodeURIComponent(activeFarmId())}&updatedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST",
    input,
  )

// Migration 064: detail GETs for a delivery run / return.
export const listWaterVehicleLoadingItems = (loadingId: number) =>
  jget<WaterVehicleLoadingItem[]>(`/Water/vehicle-loadings/${loadingId}/items?farmId=${encodeURIComponent(activeFarmId())}`)

export const listWaterDriverReturnItems = (returnId: number) =>
  jget<WaterDriverReturnItem[]>(`/Water/driver-returns/${returnId}/items?farmId=${encodeURIComponent(activeFarmId())}`)

export const listWaterDriverReturnCustomerSales = (returnId: number) =>
  jget<WaterDriverReturnCustomerSaleRow[]>(`/Water/driver-returns/${returnId}/customer-sales?farmId=${encodeURIComponent(activeFarmId())}`)

export const listWaterDriverReturnExpenses = (returnId: number) =>
  jget<WaterDeliveryExpense[]>(`/Water/driver-returns/${returnId}/expenses?farmId=${encodeURIComponent(activeFarmId())}`)

// =============================================================================
// W3: Raw materials, loss records, daily closing, reports
// =============================================================================

/** Which purchase lot a production batch draws from first. */
export type WaterRawMaterialUsageMethod = "FIFO" | "LIFO" | "HIFO"

/**
 * An open purchase lot — what's left of one purchase and what it cost. Returned
 * already ordered by the item's usage method, so walking the list top-down is
 * the same order production will consume in. See lib/water-lot-draw.ts.
 */
export interface WaterRawMaterialLot {
  waterRawMaterialPurchaseId: number
  waterRawMaterialItemId: number
  itemName?: string | null
  usageMethod?: WaterRawMaterialUsageMethod | null
  purchaseDate: string
  supplierName?: string | null
  /** Left in the lot, in PURCHASE units. */
  remainingQuantity: number
  productionUnitsPerPurchaseUnit: number
  /** The same balance in the PRODUCTION units a batch is typed in. */
  remainingProductionQuantity: number
  /** Cost per purchase unit, as bought. */
  unitCost: number
  /** Cost per production unit, as consumed. */
  productionUnitCost: number
}

export interface WaterRawMaterialItem {
  waterRawMaterialItemId: number
  farmId: string
  itemName: string
  category: string
  unitOfMeasure?: string | null
  /** How the item is BOUGHT (e.g. "bag"); production/stock uses unitOfMeasure. */
  purchaseUnitOfMeasure?: string | null
  minimumStockAlert?: number | null
  currentQuantity?: number
  isActive: boolean
  notes?: string | null
  /** Drives which lot an approved production batch consumes, and at what price. */
  usageMethod: WaterRawMaterialUsageMethod
}

export interface WaterRawMaterialPurchase {
  waterRawMaterialPurchaseId: number
  farmId: string
  waterRawMaterialItemId: number
  itemName?: string | null
  // Migration 078 — SupplierId FK; SupplierName preserved as freetext fallback.
  supplierId?: number | null
  supplierName?: string | null
  purchaseDate: string
  quantity: number
  unitCost: number
  totalCost?: number
  paymentMethod?: string | null
  amountPaid?: number
  balance?: number
  // Which cash account the payment leaves (mirrors WaterExpense). The Insert SP
  // honors it when set, else falls back to the first active account.
  waterCashAccountId?: number | null
  // Migration 116 — production-unit conversion. Buy in the item's unit
  // (purchase unit, e.g. Roll), consume in productionUnit (e.g. Sachet).
  // productionUnitsPerPurchaseUnit = production units yielded per purchase unit.
  // productionQuantity / productionUnitCost are derived server-side (read-only).
  productionUnit?: string | null
  productionUnitsPerPurchaseUnit?: number | null
  productionQuantity?: number | null
  productionUnitCost?: number | null
  receiptUrl?: string | null
  notes?: string | null
}

export interface WaterRawMaterialUsage {
  waterRawMaterialUsageId: number
  farmId: string
  waterProductionBatchId?: number | null
  waterRawMaterialItemId: number
  itemName?: string | null
  quantityUsed: number
  expectedQuantityUsed?: number | null
  variance?: number | null
  varianceReason?: string | null
  usedByStaffId?: number | null
  dateUsed: string
  notes?: string | null
}

export interface WaterLossRecord {
  waterLossRecordId: number
  farmId: string
  lossDate: string
  lossType: string
  waterProductId?: number | null
  quantityBags?: number | null
  quantitySachets?: number | null
  estimatedValue?: number | null
  responsibleStaffId?: number | null
  reason?: string | null
  status?: string
  approvedBy?: string | null
  notes?: string | null
}

export interface WaterDailyClosing {
  waterDailyClosingId: number
  farmId: string
  closingDate: string
  openingStock?: number
  bagsProduced?: number
  bagsSold?: number
  bagsReturned?: number
  bagsDamaged?: number
  closingStock?: number
  /** Backend column name (ClosingStockBags). Prefer this over closingStock. */
  closingStockBags?: number
  totalIncome?: number
  totalExpenses?: number
  cashAtHand?: number
  moMoBalance?: number
  bankBalance?: number
  creditSales?: number
  customerCollections?: number
  driverShortages?: number
  /** Backend column name (DriverShortagesTotal). Prefer this over driverShortages. */
  driverShortagesTotal?: number
  actualCashCounted?: number
  cashDifference?: number
  managerNotes?: string | null
  rejectionReason?: string | null
  status: "Draft" | "Submitted" | "Approved" | "Rejected" | string
  submittedBy?: string | null
  submittedAt?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
}

export interface WaterDailyClosingSubmit {
  actualCashCounted?: number
  managerNotes?: string | null
}

// ----- Raw material items
export const listWaterRawMaterialItems = () =>
  jget<WaterRawMaterialItem[]>(`/Water/raw-material-items?farmId=${encodeURIComponent(activeFarmId())}`)
export const createWaterRawMaterialItem = (input: Omit<WaterRawMaterialItem, "waterRawMaterialItemId" | "farmId" | "currentQuantity">) =>
  jsend<WaterRawMaterialItem>(`/Water/raw-material-items`, "POST", { ...input, farmId: activeFarmId() })
export const updateWaterRawMaterialItem = (id: number, input: Omit<WaterRawMaterialItem, "waterRawMaterialItemId" | "farmId" | "currentQuantity">) =>
  jsend<void>(`/Water/raw-material-items/${id}`, "PUT", { ...input, waterRawMaterialItemId: id, farmId: activeFarmId() })
export const deleteWaterRawMaterialItem = (id: number) =>
  jsend<void>(`/Water/raw-material-items/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// Recompute raw-material CurrentQuantity from purchases and usage. Omit itemId to
// recalculate every raw material / supply for the active company.
export interface WaterRawMaterialRecalcRow {
  waterRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  unitOfMeasure?: string | null
  oldQuantity: number
  newQuantity: number
  delta: number
}
export const recalculateWaterRawMaterialStock = (itemId?: number) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (itemId) qs.append("itemId", String(itemId))
  // Send an empty body so a Content-Length is always set — a bodyless POST can
  // 411 (Length Required) when relayed through the same-origin proxy's fetch.
  return jsend<WaterRawMaterialRecalcRow[]>(`/Water/raw-material-items/recalculate-stock?${qs.toString()}`, "POST", {})
}

// ----- Manual adjustments (increase/decrease a raw material / supply directly) -----
export interface WaterRawMaterialAdjustment {
  waterRawMaterialAdjustmentId: number
  farmId: string
  waterRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  unitOfMeasure?: string | null
  adjustedDate: string
  quantity: number            // signed: + increase, - decrease
  unitCost?: number | null
  movementType?: string | null
  note?: string | null
  createdBy?: string | null
  createdAt: string
}
export const listWaterRawMaterialAdjustments = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterRawMaterialAdjustment[]>(`/Water/raw-material-adjustments?${qs.toString()}`)
}
// quantity is a SIGNED delta (positive increases stock, negative decreases it).
export const adjustWaterRawMaterialItem = (
  itemId: number,
  input: { quantity: number; unitCost?: number | null; movementType?: string; note?: string | null },
) =>
  jsend<{ currentQuantity: number }>(`/Water/raw-material-items/${itemId}/adjust`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: currentUserId(),
  })

// Finished-product stock reconciliation (Sachet Water, Bottled, …) — in/out
// breakdown re-derived from the transaction ledger. Read-only.
export interface WaterProductReconcileRow {
  productId: number
  name?: string | null
  stockIn: number
  stockOut: number
  currentStock: number
}
export const reconcileWaterProductStock = (productId?: number) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (productId) qs.append("productId", String(productId))
  return jget<WaterProductReconcileRow[]>(`/Water/products/reconcile-stock?${qs.toString()}`)
}
// Set a finished product's stock to a physical count — writes a correcting
// Adjust transaction for (target − current). Returns the new stock.
export const setWaterProductStock = (productId: number, targetQuantity: number, note?: string) =>
  jsend<{ currentStock: number }>(`/Water/products/${productId}/set-stock`, "POST", {
    farmId: activeFarmId(), targetQuantity, note: note || "Stock-take correction", createdBy: currentUserId(),
  })
export const listWaterRawMaterialPurchases = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterRawMaterialPurchase[]>(`/Water/raw-material-purchases?${qs.toString()}`)
}
export const createWaterRawMaterialPurchase = (input: Omit<WaterRawMaterialPurchase, "waterRawMaterialPurchaseId" | "farmId" | "itemName" | "balance">) =>
  jsend<{ waterRawMaterialPurchaseId: number }>(`/Water/raw-material-purchases`, "POST", { ...input, farmId: activeFarmId() })
export const updateWaterRawMaterialPurchase = (id: number, input: Omit<WaterRawMaterialPurchase, "waterRawMaterialPurchaseId" | "farmId" | "itemName" | "balance" | "waterRawMaterialItemId">) =>
  jsend<void>(`/Water/raw-material-purchases/${id}`, "PUT", { ...input, waterRawMaterialPurchaseId: id, farmId: activeFarmId() })
export const deleteWaterRawMaterialPurchase = (id: number) =>
  jsend<void>(`/Water/raw-material-purchases/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// Record a follow-up payment against an outstanding purchase balance. Posts its
// own expense + cash-out on the backend; returns the new outstanding balance.
export const payWaterRawMaterialPurchaseBalance = (
  id: number,
  input: { amount: number; paymentMethod?: string; paymentDate?: string },
) =>
  jsend<{ balance: number }>(`/Water/raw-material-purchases/${id}/pay-balance`, "POST", {
    farmId: activeFarmId(),
    amount: input.amount,
    paymentMethod: input.paymentMethod ?? "Cash",
    paymentDate: input.paymentDate || null,
  })

// ----- Loss records
export const listWaterLossRecords = (opts?: { lossType?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.lossType) qs.append("lossType", opts.lossType)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterLossRecord[]>(`/Water/loss-records?${qs.toString()}`)
}
export const createWaterLossRecord = (input: Omit<WaterLossRecord, "waterLossRecordId" | "farmId">) =>
  jsend<{ waterLossRecordId: number }>(`/Water/loss-records`, "POST", { ...input, farmId: activeFarmId() })
export const approveWaterLossRecord = (id: number) =>
  jsend<void>(`/Water/loss-records/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")
// Migration 068: edit a Pending loss record inline. The backend rejects edits
// on Approved records — caller should Unapprove first.
export const updateWaterLossRecord = (id: number, input: Partial<WaterLossRecord>) =>
  jsend<void>(`/Water/loss-records/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "PUT",
    { ...input, waterLossRecordId: id, farmId: activeFarmId() })
// Migration 068: Approved → Reopened (Pending) with a reason. Cash impact is
// reversed automatically by the SP.
export const unapproveWaterLossRecord = (id: number, reason: string) =>
  jsend<void>(
    `/Water/loss-records/${id}/unapprove?farmId=${encodeURIComponent(activeFarmId())}&unapprovedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST",
    { reason },
  )

// ----- Daily closing
export const listWaterDailyClosings = (opts?: { status?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterDailyClosing[]>(`/Water/daily-closings?${qs.toString()}`)
}
export const getWaterDailyClosing = (id: number) =>
  jget<WaterDailyClosing>(`/Water/daily-closings/${id}?farmId=${encodeURIComponent(activeFarmId())}`)
export const createWaterDailyClosing = (input: { closingDate: string; managerNotes?: string | null }) =>
  jsend<WaterDailyClosing>(`/Water/daily-closings`, "POST", { ...input, farmId: activeFarmId() })
export const submitWaterDailyClosing = (id: number, body: WaterDailyClosingSubmit) =>
  jsend<WaterDailyClosing>(`/Water/daily-closings/${id}/submit?farmId=${encodeURIComponent(activeFarmId())}&submittedBy=${encodeURIComponent(currentUserId() || "")}`, "POST", body)
// Email the closing report (PDF) to `to` (the company email). Handled by the
// Farm API EmailController (POST /api/Email/daily-closing); it loads the closing
// and builds the PDF server-side. Returns 503 if SMTP isn't configured.
export const emailWaterDailyClosing = (id: number, to: string, companyName?: string) =>
  jsend<{ success: boolean; message: string }>(
    `/Email/daily-closing?id=${id}&farmId=${encodeURIComponent(activeFarmId())}&to=${encodeURIComponent(to)}${companyName ? `&companyName=${encodeURIComponent(companyName)}` : ""}`,
    "POST")
export const approveWaterDailyClosing = (id: number) =>
  jsend<void>(`/Water/daily-closings/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")
export const rejectWaterDailyClosing = (id: number, rejectionReason: string) =>
  jsend<void>(`/Water/daily-closings/${id}/reject?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST", { rejectionReason })
export const deleteWaterDailyClosing = (id: number) =>
  jsend<void>(`/Water/daily-closings/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")
export const updateWaterDailyClosingNotes = (id: number, managerNotes: string | null) =>
  jsend<void>(`/Water/daily-closings/${id}/notes?farmId=${encodeURIComponent(activeFarmId())}`, "PUT", { managerNotes })

// Migration 068 — Reopen an active closing (marks it Reopened + IsActive=0)
// so a new closing can be submitted for the same date. After the new closing
// is in the DB, call linkSuperseded(newId, previousId) to record the chain.
export const reopenWaterDailyClosing = (id: number, reason: string) =>
  jsend<void>(
    `/Water/daily-closings/${id}/reopen?farmId=${encodeURIComponent(activeFarmId())}&reopenedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST",
    { reason },
  )

export const linkSupersededWaterDailyClosing = (newClosingId: number, previousClosingId: number) =>
  jsend<void>(
    `/Water/daily-closings/${newClosingId}/link-superseded?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { previousClosingId },
  )

// Migration 081 — Supplier Report row.
export interface WaterSupplierActivityRow {
  waterSupplierId: number
  supplierName: string
  supplierType?: string | null
  contactPerson?: string | null
  phone?: string | null
  email?: string | null
  totalPurchaseAmount: number
  purchaseCount: number
  lastPurchaseDate?: string | null
  totalExpenseAmount: number
  expenseCount: number
  lastExpenseDate?: string | null
  outstandingBalance: number
}

export const getWaterSupplierActivity = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.set("fromDate", opts.fromDate)
  if (opts?.toDate)   qs.set("toDate",   opts.toDate)
  return jget<WaterSupplierActivityRow[]>(`/Water/reports/supplier-activity?${qs.toString()}`)
}

// ----- Inventory Tracker (migration 221) -----
/**
 * Per-product stock position for a period. Quantities ending `Base` are in BASE
 * units (sachets); the `Bags` pair is the same figure divided by sachetsPerBag,
 * for display only. Base is the only unit the ledger can be summed in without
 * mixing bags and sachets — see the migration header for why.
 */
export interface WaterInventoryTrackerRow {
  waterProductId: number
  productName: string
  sku?: string | null
  baseUnit?: string | null
  isSachetProduct: boolean
  sachetsPerBag: number
  openingBase: number
  stockInBase: number
  stockOutBase: number
  closingBase: number
  openingBags: number
  closingBags: number
  unitCost: number
  closingValue: number
  movementCount: number
}

/** One movement. `runningBase` is seeded from the row's opening, so the last
 *  entry lands exactly on that product's closing figure. */
export interface WaterInventoryTrackerMovement {
  stockTxnId: number
  createdDate: string
  txnType: string
  /** Server-supplied wording ("Production", "Loaded to vehicle", …). Don't
   *  re-map it client-side; the SP is the single source of that vocabulary. */
  movementLabel: string
  baseQuantity: number
  quantityBags: number
  runningBase: number
  unitCost?: number | null
  note?: string | null
  createdBy?: string | null
}

export const getWaterInventoryTracker = (fromDate: string, toDate: string) =>
  jget<WaterInventoryTrackerRow[]>(
    `/Water/reports/inventory-tracker?farmId=${encodeURIComponent(activeFarmId())}` +
    `&fromDate=${encodeURIComponent(fromDate)}&toDate=${encodeURIComponent(toDate)}`,
  )

export const getWaterInventoryTrackerMovements = (
  productId: number, fromDate: string, toDate: string,
) =>
  jget<WaterInventoryTrackerMovement[]>(
    `/Water/reports/inventory-tracker/movements?farmId=${encodeURIComponent(activeFarmId())}` +
    `&productId=${productId}&fromDate=${encodeURIComponent(fromDate)}&toDate=${encodeURIComponent(toDate)}`,
  )

// Migration 079 — single-shot Recreate after Reopen.
// Backend creates the new Draft using current data and links it to the predecessor.
export const recreateWaterDailyClosing = (input: {
  closingDate: string
  predecessorClosingId: number
  actualCashCounted?: number
  managerNotes?: string | null
  differenceReason?: string | null
}) =>
  jsend<{ waterDailyClosingId: number; closing: WaterDailyClosing }>(
    `/Water/daily-closings/recreate?farmId=${encodeURIComponent(activeFarmId())}&createdBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST",
    {
      closingDate: input.closingDate,
      predecessorClosingId: input.predecessorClosingId,
      actualCashCounted: input.actualCashCounted ?? 0,
      managerNotes: input.managerNotes ?? null,
      differenceReason: input.differenceReason ?? null,
    },
  )

// ----- Reports
// Shape matches dbo.spWaterReport_PeriodPnL exactly (migration 044). Older
// versions of this interface used totalSales / grossProfit / cashAtHand /
// customerDebt — those columns are not returned by the SP and would always
// arrive as undefined. The current shape is the authoritative one.
export interface WaterPeriodPnL {
  periodStart: string
  periodEnd: string
  totalIncome: number
  totalExpenses: number
  rawMaterialCost: number
  productionCost: number
  totalLosses: number
  netProfit: number
  profitMarginPct: number
  bagsProduced: number
  bagsSold: number
  avgProfitPerBag: number
}
// These three mirror the backend C# models exactly (camelCase of the
// PoultryFarmAPIWeb.Models.* report rows). The Farm API serializes camelCase.
export interface WaterRouteProfitabilityRow {
  waterRouteId: number
  routeName: string
  totalBagsLoaded: number
  totalBagsSold: number
  totalBagsReturned: number
  totalBagsLost: number
  totalRevenue: number
  totalShortages: number
  totalOverages: number
  netRouteIncome: number
}
export interface WaterDriverReconciliationRow {
  waterDriverId: number
  driverName: string
  phoneNumber: string | null
  totalBagsLoaded: number
  totalBagsSold: number
  totalBagsReturned: number
  totalBagsLost: number
  expectedRevenue: number
  actualAccountedFor: number
  totalShortages: number
  shortageOccurrences: number
}
export interface WaterRawMaterialVarianceRow {
  waterRawMaterialItemId: number
  itemName: string
  category: string
  unitOfMeasure: string | null
  totalExpected: number
  totalActual: number
  totalVariance: number
  usageCount: number
}

const period = (from: string, to: string) =>
  `farmId=${encodeURIComponent(activeFarmId())}&fromDate=${encodeURIComponent(from)}&toDate=${encodeURIComponent(to)}`

export const getWaterPeriodPnL = (fromDate: string, toDate: string) =>
  jget<WaterPeriodPnL>(`/Water/reports/period-pnl?${period(fromDate, toDate)}`)
export const getWaterRouteProfitability = (fromDate: string, toDate: string) =>
  jget<WaterRouteProfitabilityRow[]>(`/Water/reports/route-profitability?${period(fromDate, toDate)}`)
export const getWaterDriverReconciliation = (fromDate: string, toDate: string) =>
  jget<WaterDriverReconciliationRow[]>(`/Water/reports/driver-reconciliation?${period(fromDate, toDate)}`)
export const getWaterRawMaterialVariance = (fromDate: string, toDate: string) =>
  jget<WaterRawMaterialVarianceRow[]>(`/Water/reports/raw-material-variance?${period(fromDate, toDate)}`)

// Migration 057: dashboard intelligence (gap #7 — owner-intelligence cards)

export interface WaterExpenseByCategoryRow {
  waterExpenseCategoryId: number
  categoryName: string
  expenseCount: number
  totalAmount: number
}

export interface WaterTopCustomerRow {
  waterCustomerId: number
  customerName: string
  phoneNumber: string | null
  salesCount: number
  totalSales: number
  totalPaid: number
  outstandingBalance: number
}

export const getWaterExpenseByCategory = (fromDate: string, toDate: string) =>
  jget<WaterExpenseByCategoryRow[]>(`/Water/reports/expense-by-category?${period(fromDate, toDate)}`)

export const getWaterTopCustomers = (fromDate: string, toDate: string, topN = 5) =>
  jget<WaterTopCustomerRow[]>(`/Water/reports/top-customers?${period(fromDate, toDate)}&topN=${topN}`)

// Migration 066: Driver Collection Report (Prompt 2 #16). Two result sets:
// per-driver per-product detail rows + per-driver totals.
export interface WaterDriverCollectionDetailRow {
  waterDriverId?: number | null
  driverName?: string | null
  waterProductId: number
  productName?: string | null
  bagsLoaded: number
  bagsSold: number
  bagsReturned: number
  bagsDamaged: number
  expectedCash: number
  salesValue: number
}
export interface WaterDriverCollectionTotalsRow {
  waterDriverId?: number | null
  driverName?: string | null
  deliveryRuns: number
  reconciledRuns: number
  cashCollected: number
  moMoCollected: number
  bankCollected: number
  creditSales: number
  shortage: number
  overage: number
}
export interface WaterDriverCollectionReport {
  detail: WaterDriverCollectionDetailRow[]
  totals: WaterDriverCollectionTotalsRow[]
}

export const getWaterDriverCollection = (fromDate: string, toDate: string, waterDriverId?: number) => {
  const qs = `${period(fromDate, toDate)}${waterDriverId ? `&waterDriverId=${waterDriverId}` : ""}`
  return jget<WaterDriverCollectionReport>(`/Water/reports/driver-collection?${qs}`)
}

// ---------------------------------------------------------------------------
// Batch Production (migration 193 — "WaterDailyProduction" in the DB/API; the
// UI calls it Batch Production, mirroring the poultry side.)
// ---------------------------------------------------------------------------
// The day's combined output, allocated across machines. Posting creates one
// real WaterProductionBatch per machine and approves it, so lot costing,
// finished-goods stock, auto-expenses and loss rows are all inherited.
// ---------------------------------------------------------------------------
export type WaterDailyProductionStatus =
  | "Draft" | "PendingAllocation" | "Allocated" | "Posted" | "Reversed" | "Cancelled"

export type WaterMachineSelectionType = "AllMachines" | "CustomMachines" | "SingleMachine"

export type WaterAllocationMethod =
  | "Manual" | "ByMachineCapacity" | "ByPreviousProduction" | "EqualSplit"

export interface WaterDailyProductionMachine {
  waterDailyProductionMachineId?: number
  waterMachineId: number
  machineName?: string | null
  machineNumber?: string | null
  capacityPerHour?: number | null
  operatorStaffId?: number | null
}

export interface WaterDailyProductionMaterial {
  waterDailyProductionMaterialId?: number
  waterRawMaterialItemId: number
  itemName?: string | null
  unitOfMeasure?: string | null
  quantityUsed: number
  expectedQuantityUsed?: number | null
  unitCost?: number | null
  totalCost?: number
  varianceReason?: string | null
  notes?: string | null
}

export interface WaterDailyProductionAllocationMaterial {
  waterDailyProductionAllocationMaterialId?: number
  waterDailyProductionMaterialId?: number | null
  waterRawMaterialItemId: number
  itemName?: string | null
  quantityAllocated: number
  expectedQuantityAllocated?: number | null
  unitCost?: number | null
  totalCost?: number
}

export interface WaterDailyProductionAllocation {
  waterDailyProductionAllocationId?: number
  waterMachineId: number
  machineName?: string | null
  allocationMethod?: WaterAllocationMethod | null
  shift?: string | null
  operatorStaffId?: number | null
  startTime?: string | null
  endTime?: string | null
  bagsProduced: number
  looseSachetsProduced: number
  rejectedSachets: number
  damagedBags: number
  packagingRollsUsed: number
  estimatedWaterUsedLitres?: number | null
  electricityCost: number
  fuelCost: number
  laborCost: number
  otherProductionCost: number
  totalProductionCost?: number
  rawMaterialCost?: number | null
  notes?: string | null
  generatedWaterProductionBatchId?: number | null
  generatedBatchNumber?: string | null
  materials: WaterDailyProductionAllocationMaterial[]
}

export interface WaterDailyProductionPosting {
  waterDailyProductionPostingId: number
  waterDailyProductionAllocationId?: number | null
  postingVersion: number
  waterProductionBatchId: number
  batchNumber: string
  waterMachineId?: number | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
}

export interface WaterDailyProduction {
  waterDailyProductionId: number
  farmId: string
  userId?: string | null
  productionNumber?: string | null
  productionDate: string
  shift: string
  machineSelectionType: WaterMachineSelectionType
  waterProductId: number
  waterBoreholeId?: number | null
  operatorStaffId?: number | null
  startTime?: string | null
  endTime?: string | null
  bagsProduced: number
  sachetsPerBag: number
  looseSachetsProduced: number
  rejectedSachets: number
  damagedBags: number
  packagingRollsUsed: number
  estimatedWaterUsedLitres?: number | null
  electricityCost: number
  fuelCost: number
  laborCost: number
  otherProductionCost: number
  totalProductionCost: number
  rawMaterialCost: number
  qualityStatus: string
  qualityPHLevel?: number | null
  qualityChlorinePpm?: number | null
  qualityTurbidity?: number | null
  qualityTDS?: number | null
  qualityNotes?: string | null
  status: WaterDailyProductionStatus
  postingVersion: number
  notes?: string | null
  createdBy?: string | null
  createdAt?: string | null
  updatedBy?: string | null
  updatedAt?: string | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  // Read-only enrichments from the SP
  productName?: string | null
  boreholeName?: string | null
  goodBags: number
  allInCost: number
  costPerBag: number
  productionEfficiencyPercent?: number
  machineCount?: number
  allocationCount?: number
  machines: WaterDailyProductionMachine[]
  materials: WaterDailyProductionMaterial[]
  allocations: WaterDailyProductionAllocation[]
  postings: WaterDailyProductionPosting[]
}

export interface WaterDailyProductionInput
  extends Partial<Omit<WaterDailyProduction, "machines" | "materials" | "allocations" | "postings">> {
  productionDate: string
  waterProductId: number
  machines?: WaterDailyProductionMachine[]
  materials?: WaterDailyProductionMaterial[]
}

export const listWaterDailyProductions = (opts?: {
  status?: WaterDailyProductionStatus
  fromDate?: string
  toDate?: string
}) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterDailyProduction[]>(`/Water/daily-productions?${qs.toString()}`)
}

export const getWaterDailyProduction = (id: number) =>
  jget<WaterDailyProduction>(`/Water/daily-productions/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterDailyProduction = (input: WaterDailyProductionInput) =>
  jsend<WaterDailyProduction>(`/Water/daily-productions`, "POST", {
    ...input,
    farmId: activeFarmId(),
    userId: currentUserId(),
  })

export const updateWaterDailyProduction = (id: number, input: WaterDailyProductionInput) =>
  jsend<void>(`/Water/daily-productions/${id}`, "PUT", {
    ...input,
    waterDailyProductionId: id,
    farmId: activeFarmId(),
    userId: currentUserId(),
    updatedBy: currentUserId(),
  })

export const deleteWaterDailyProduction = (id: number) =>
  jsend<void>(
    `/Water/daily-productions/${id}?farmId=${encodeURIComponent(activeFarmId())}&userId=${encodeURIComponent(currentUserId())}`,
    "DELETE",
  )

export const saveWaterDailyProductionAllocation = (
  id: number,
  allocations: WaterDailyProductionAllocation[],
  status: WaterDailyProductionStatus = "Allocated",
) =>
  jsend<WaterDailyProduction>(
    `/Water/daily-productions/${id}/allocation?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { updatedBy: currentUserId(), status, allocations },
  )

export const deleteWaterDailyProductionAllocation = (id: number) =>
  jsend<WaterDailyProduction>(
    `/Water/daily-productions/${id}/allocation?farmId=${encodeURIComponent(activeFarmId())}&userId=${encodeURIComponent(currentUserId())}`,
    "DELETE",
  )

export const setWaterDailyProductionStatus = (id: number, status: WaterDailyProductionStatus) =>
  jsend<WaterDailyProduction>(
    `/Water/daily-productions/${id}/status?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { status, userId: currentUserId() },
  )

export const postWaterDailyProduction = (id: number) =>
  jsend<WaterDailyProduction>(
    `/Water/daily-productions/${id}/post?farmId=${encodeURIComponent(activeFarmId())}&postedBy=${encodeURIComponent(currentUserId())}`,
    "POST",
  )

export const reverseWaterDailyProduction = (id: number) =>
  jsend<WaterDailyProduction>(
    `/Water/daily-productions/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}&reversedBy=${encodeURIComponent(currentUserId())}`,
    "POST",
  )

export const WATER_DAILY_PRODUCTION_STATUS_LABELS: Record<WaterDailyProductionStatus, string> = {
  Draft: "Draft",
  PendingAllocation: "Pending Allocation",
  Allocated: "Allocated",
  Posted: "Posted",
  Reversed: "Reversed",
  Cancelled: "Cancelled",
}

// "All active machines" / "Machine A, Machine B +2 more" — the day's scope.
export const waterMachineScopeLabel = (d: WaterDailyProduction): string => {
  if (d.machineSelectionType === "AllMachines") return "All active machines"
  const names = (d.machines || []).map((m) => m.machineName).filter(Boolean) as string[]
  if (!names.length) return `${d.machineCount ?? 0} machine(s)`
  return names.length <= 2 ? names.join(", ") : `${names.slice(0, 2).join(", ")} +${names.length - 2} more`
}

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"

// ----- Types -----
export interface WaterProduct {
  waterProductId: number
  farmId: string
  name: string
  sku?: string | null
  sizeMl?: number | null
  unit?: string | null
  unitPrice: number
  isActive: boolean
  notes?: string | null
  createdDate: string
  updatedDate?: string | null
  stockOnHand: number
}

export interface WaterProductInput {
  name: string
  sku?: string | null
  sizeMl?: number | null
  unit?: string | null
  unitPrice: number
  isActive?: boolean
  notes?: string | null
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
}

export interface WaterCustomerInput {
  name: string
  contactPhone?: string | null
  contactEmail?: string | null
  address?: string | null
  city?: string | null
  notes?: string | null
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
  if (!res.ok) throw new Error(`GET ${path} -> ${res.status}`)
  return (await res.json()) as T
}

async function jsend<T>(path: string, method: "POST" | "PUT" | "DELETE", body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    const t = await res.text().catch(() => "")
    throw new Error(`${method} ${path} -> ${res.status} ${t}`)
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
}

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
  status: "Draft" | "Approved" | "Paid" | "Cancelled" | string
  waterCashAccountId?: number | null
  cashAccountName?: string | null
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  paidBy?: string | null
  paidAt?: string | null
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
  pumpCapacity?: number | null
  tankCapacity?: number | null
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
  costPerBag?: number
  productionEfficiencyPercent?: number
  qualityStatus: "Pending" | "Passed" | "Failed" | string
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  createdAt: string
  updatedAt?: string | null
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
export const approveWaterProductionBatch = (id: number) =>
  jsend<void>(`/Water/production-batches/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")
export const cancelWaterProductionBatch = (id: number) =>
  jsend<void>(`/Water/production-batches/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const reopenWaterProductionBatch = (id: number) =>
  jsend<void>(`/Water/production-batches/${id}/reopen?farmId=${encodeURIComponent(activeFarmId())}&reopenedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

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
  assignedWaterVehicleId?: number | null
  isActive: boolean
  notes?: string | null
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
  defaultWaterVehicleId?: number | null
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
  driverStaffId?: number | null
  driverName?: string | null
  assistantStaffId?: number | null
  waterRouteId?: number | null
  routeName?: string | null
  waterProductId?: number | null
  bagsLoaded: number
  sachetsPerBag?: number
  expectedSellingPricePerBag?: number
  expectedCash?: number
  openingCashWithDriver?: number
  loadedByStaffId?: number | null
  status: "Loaded" | "Returned" | "Reconciled" | "Cancelled" | string
  notes?: string | null
}

export interface WaterDriverReturn {
  waterDriverReturnId: number
  farmId: string
  waterVehicleLoadingId: number
  returnDate: string
  bagsSold: number
  bagsReturned: number
  bagsDamaged: number
  cashCollected: number
  moMoCollected: number
  bankCollected: number
  creditSalesAmount: number
  totalCollected?: number
  expectedCash?: number
  shortageAmount?: number
  overageAmount?: number
  reconciledByStaffId?: number | null
  approvedBy?: string | null
  approvedAt?: string | null
  status?: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
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

// =============================================================================
// W3: Raw materials, loss records, daily closing, reports
// =============================================================================

export interface WaterRawMaterialItem {
  waterRawMaterialItemId: number
  farmId: string
  itemName: string
  category: string
  unitOfMeasure?: string | null
  minimumStockAlert?: number | null
  currentQuantity?: number
  isActive: boolean
  notes?: string | null
}

export interface WaterRawMaterialPurchase {
  waterRawMaterialPurchaseId: number
  farmId: string
  waterRawMaterialItemId: number
  itemName?: string | null
  supplierId?: number | null
  purchaseDate: string
  quantity: number
  unitCost: number
  totalCost?: number
  paymentMethod?: string | null
  amountPaid?: number
  balance?: number
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
  totalIncome?: number
  totalExpenses?: number
  cashAtHand?: number
  moMoBalance?: number
  bankBalance?: number
  creditSales?: number
  customerCollections?: number
  driverShortages?: number
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
export const listWaterRawMaterialPurchases = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterRawMaterialPurchase[]>(`/Water/raw-material-purchases?${qs.toString()}`)
}
export const createWaterRawMaterialPurchase = (input: Omit<WaterRawMaterialPurchase, "waterRawMaterialPurchaseId" | "farmId" | "itemName" | "totalCost" | "balance">) =>
  jsend<{ waterRawMaterialPurchaseId: number }>(`/Water/raw-material-purchases`, "POST", { ...input, farmId: activeFarmId() })
export const updateWaterRawMaterialPurchase = (id: number, input: Omit<WaterRawMaterialPurchase, "waterRawMaterialPurchaseId" | "farmId" | "itemName" | "totalCost" | "balance" | "waterRawMaterialItemId">) =>
  jsend<void>(`/Water/raw-material-purchases/${id}`, "PUT", { ...input, waterRawMaterialPurchaseId: id, farmId: activeFarmId() })
export const deleteWaterRawMaterialPurchase = (id: number) =>
  jsend<void>(`/Water/raw-material-purchases/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

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
export const approveWaterDailyClosing = (id: number) =>
  jsend<void>(`/Water/daily-closings/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")
export const rejectWaterDailyClosing = (id: number, rejectionReason: string) =>
  jsend<void>(`/Water/daily-closings/${id}/reject?farmId=${encodeURIComponent(activeFarmId())}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST", { rejectionReason })
export const deleteWaterDailyClosing = (id: number) =>
  jsend<void>(`/Water/daily-closings/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")
export const updateWaterDailyClosingNotes = (id: number, managerNotes: string | null) =>
  jsend<void>(`/Water/daily-closings/${id}/notes?farmId=${encodeURIComponent(activeFarmId())}`, "PUT", { managerNotes })

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
  netProfit: number
  profitMarginPct: number
  bagsProduced: number
  bagsSold: number
  avgProfitPerBag: number
}
export interface WaterRouteProfitabilityRow {
  waterRouteId: number
  routeName: string
  bagsLoaded: number
  bagsSold: number
  revenue: number
  shortagesValue: number
  netProfit: number
}
export interface WaterDriverReconciliationRow {
  waterStaffId: number
  driverName: string
  trips: number
  bagsLoaded: number
  bagsSold: number
  cashCollected: number
  shortagesValue: number
}
export interface WaterRawMaterialVarianceRow {
  waterRawMaterialItemId: number
  itemName: string
  category: string
  expectedQuantity: number
  actualQuantity: number
  variance: number
  estimatedLossValue: number
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

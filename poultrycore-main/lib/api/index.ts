// Centralized API exports

// Configuration
export { API_BASE_URL, getApiUrl, getUserContext, getAuthHeaders, validateUserContext } from './config'

// Types
export type {
  ApiResponse,
  RegisterData,
  LoginData,
  ForgotPasswordData,
  ResetPasswordData,
  ReportRequest,
  Sale,
  SaleInput,
  Expense,
  ExpenseInput,
  Customer,
  CustomerInput,
  Flock,
  FlockInput,
  ProductionRecord,
  ProductionRecordInput,
  FeedUsage,
  FeedUsageInput,
  EggProduction,
  EggProductionInput,
  UserProfile,
  UserProfileInput,
  DashboardMetrics,
  ChartData
} from './types'

// Employee Types (from admin.ts)
export type {
  Employee,
  CreateEmployeeData,
  UpdateEmployeeData
} from './admin'

// Authentication API
export {
  register,
  login,
  forgotPassword,
  resetPassword
} from './auth'

// Report API
export {
  getReportContext
} from './report'

// Sales API
export {
  getSales,
  getSale,
  getSalesByFlock,
  createSale,
  updateSale,
  deleteSale
} from './sale'

// Expense API
export {
  getExpenses,
  getExpense,
  getExpensesByFlock,
  createExpense,
  updateExpense,
  deleteExpense
} from './expense'

// Customer API
export {
  getCustomers,
  getCustomer,
  createCustomer,
  updateCustomer,
  deleteCustomer
} from './customer'

// Supplier API
export type { Supplier, SupplierInput } from './supplier'
export {
  getSuppliers,
  getSupplier,
  createSupplier,
  updateSupplier,
  deleteSupplier
} from './supplier'

// Egg inventory adjustments
export type { EggInventoryAdjustment, EggInventoryAdjustmentInput } from './egg-inventory-adjustment'
export {
  getEggInventoryAdjustments,
  createEggInventoryAdjustment,
  updateEggInventoryAdjustment,
  deleteEggInventoryAdjustment
} from './egg-inventory-adjustment'

// Feed inventory adjustments
export type { FeedInventoryAdjustment, FeedInventoryAdjustmentInput } from './feed-inventory-adjustment'
export {
  getFeedInventoryAdjustments,
  createFeedInventoryAdjustment,
  updateFeedInventoryAdjustment,
  deleteFeedInventoryAdjustment
} from './feed-inventory-adjustment'

// Flock API
export {
  getFlocks,
  getFlock,
  createFlock,
  updateFlock,
  deleteFlock
} from './flock'

// Production Record API
export {
  getProductionRecords,
  getProductionRecord,
  createProductionRecord,
  updateProductionRecord,
  deleteProductionRecord
} from './production-record'

// Feed Usage API
export {
  getFeedUsages,
  getFeedUsage,
  createFeedUsage,
  updateFeedUsage,
  deleteFeedUsage
} from './feed-usage'

// Egg Production API
export {
  getEggProductions,
  getEggProduction,
  createEggProduction,
  updateEggProduction,
  deleteEggProduction
} from './egg-production'

// User Profile API
export {
  getUserProfile,
  updateUserProfile
} from './user-profile'

// Dashboard API
export {
  getDashboardSummary
} from './dashboard'

// Admin/Employee API
export {
  getEmployees,
  getEmployee,
  getEmployeeCount,
  createEmployee,
  updateEmployee,
  deleteEmployee,
  getTodayLogins
} from './admin'

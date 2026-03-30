// Centralized API types and interfaces

// Common API response structure
export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

// Authentication types
export interface RegisterData {
  farmName: string
  username: string
  email: string
  password: string
  firstName: string
  lastName: string
  roles: string[]
  phoneNumber: string
}

export interface LoginData {
  username: string
  password: string
  rememberMe: boolean
}

export interface ForgotPasswordData {
  email: string
}

export interface ResetPasswordData {
  email: string
  password: string
  confirmPassword: string
  token: string
}

// Report types
export interface ReportRequest {
  farmId: string
  userId: string
  reportType: string
  startDate: string
  endDate: string
  flockId?: number
  customerId?: number
}

export type ReportExportFormat = 'csv' | 'pdf' | 'excel'

// Sale types
export interface Sale {
  farmId: string
  userId: string
  saleId: number
  saleDate: string
  product: string
  quantity: number
  unitPrice: number
  totalAmount: number
  paymentMethod: string
  customerName: string
  flockId: number
  saleDescription: string
  createdDate: string
}

export interface SaleInput {
  farmId: string
  userId: string
  saleId?: number
  saleDate: string
  product: string
  quantity: number
  unitPrice: number
  totalAmount: number
  paymentMethod: string
  customerName: string
  flockId: number
  saleDescription: string
  createdDate?: string
}

// Expense types (already defined in expense.ts, but centralized here)
export interface Expense {
  farmId: string
  userId: string
  expenseId: number
  expenseDate: string
  category: string
  description: string
  amount: number
  paymentMethod: string
  flockId: number
  createdDate: string
}

export interface ExpenseInput {
  farmId: string
  userId: string
  expenseId?: number
  expenseDate: string
  category: string
  description: string
  amount: number
  paymentMethod: string
  flockId: number
  createdDate?: string
}

// Customer types
export interface Customer {
  farmId: string
  userId: string
  customerId: number
  customerName: string
  email: string
  phoneNumber: string
  address: string
  contactPerson: string
  customerType: string
  notes: string
  createdDate: string
}

export interface CustomerInput {
  farmId: string
  userId: string
  customerId?: number
  customerName: string
  email: string
  phoneNumber: string
  address: string
  contactPerson: string
  customerType: string
  notes: string
  createdDate?: string
}

// Flock types
export interface Flock {
  farmId: string
  userId: string
  flockId: number
  flockName: string
  breed: string
  flockSize: number
  startDate: string
  expectedEndDate: string
  currentAge: number
  status: string
  notes: string
  createdDate: string
}

export interface FlockInput {
  farmId: string
  userId: string
  flockId?: number
  flockName: string
  breed: string
  flockSize: number
  startDate: string
  expectedEndDate: string
  currentAge: number
  status: string
  notes: string
  createdDate?: string
}

// Production Record types
export interface ProductionRecord {
  farmId: string
  userId: string
  recordId: number
  recordDate: string
  flockId: number
  eggsCollected: number
  eggsSold: number
  eggsBroken: number
  mortality: number
  feedConsumed: number
  waterConsumed: number
  temperature: number
  humidity: number
  notes: string
  createdDate: string
}

export interface ProductionRecordInput {
  farmId: string
  userId: string
  recordId?: number
  recordDate: string
  flockId: number
  eggsCollected: number
  eggsSold: number
  eggsBroken: number
  mortality: number
  feedConsumed: number
  waterConsumed: number
  temperature: number
  humidity: number
  notes: string
  createdDate?: string
}

// Feed Usage types
export interface FeedUsage {
  farmId: string
  userId: string
  feedUsageId: number
  usageDate: string
  flockId: number
  feedType: string
  quantity: number
  unit: string
  cost: number
  supplier: string
  batchNumber: string
  notes: string
  createdDate: string
}

export interface FeedUsageInput {
  farmId: string
  userId: string
  feedUsageId?: number
  usageDate: string
  flockId: number
  feedType: string
  quantity: number
  unit: string
  cost: number
  supplier: string
  batchNumber: string
  notes: string
  createdDate?: string
}

// Egg Production types
export interface EggProduction {
  farmId: string
  userId: string
  productionId: number
  productionDate: string
  flockId: number
  totalEggs: number
  gradeA: number
  gradeB: number
  gradeC: number
  crackedEggs: number
  dirtyEggs: number
  notes: string
  createdDate: string
}

export interface EggProductionInput {
  farmId: string
  userId: string
  productionId?: number
  productionDate: string
  flockId: number
  totalEggs: number
  gradeA: number
  gradeB: number
  gradeC: number
  crackedEggs: number
  dirtyEggs: number
  notes: string
  createdDate?: string
}

// User Profile types
export interface UserProfile {
  farmId: string
  userId: string
  username: string
  email: string
  firstName: string
  lastName: string
  phoneNumber: string
  roles: string[]
  isStaff: boolean
  isSubscriber: boolean
  farmName: string
  lastLoginDate: string
  createdDate: string
}

export interface UserProfileInput {
  farmId: string
  userId: string
  username: string
  email: string
  firstName: string
  lastName: string
  phoneNumber: string
  roles: string[]
  isStaff: boolean
  isSubscriber: boolean
  farmName: string
  lastLoginDate?: string
  createdDate?: string
}

// Dashboard types
export interface DashboardMetrics {
  totalEggs: number
  totalSales: number
  totalExpenses: number
  netProfit: number
  activeFlocks: number
  mortalityRate: number
  feedConsumption: number
  eggProductionRate: number
}

export interface ChartData {
  labels: string[]
  datasets: {
    label: string
    data: number[]
    backgroundColor?: string
    borderColor?: string
  }[]
}

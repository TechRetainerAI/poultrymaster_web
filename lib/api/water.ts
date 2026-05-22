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

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { forceReauth } from "./session-expiry"

// Poultry inventory + raw materials API wrappers (mirror lib/api/water.ts).
// Additive: new module; existing poultry API wrappers untouched. Calls hit
// /Poultry/* on the Farm API via the same-origin proxy.

// ----- Types -----
export interface PoultryRawMaterialItem {
  poultryRawMaterialItemId: number
  farmId: string
  itemName: string
  category: string
  unitOfMeasure?: string | null
  minimumStockAlert: number
  currentQuantity: number
  isActive: boolean
  isLowStock?: boolean
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface PoultryRawMaterialItemInput {
  itemName: string
  category: string
  unitOfMeasure?: string | null
  minimumStockAlert?: number
  isActive?: boolean
  notes?: string | null
}

export interface PoultryRawMaterialPurchase {
  poultryRawMaterialPurchaseId: number
  farmId: string
  poultryRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  unitOfMeasure?: string | null
  supplierName?: string | null
  supplierId?: number | null
  purchaseDate: string
  quantity: number
  unitCost: number
  totalCost: number
  productionUnit?: string | null
  productionUnitsPerPurchaseUnit?: number | null
  productionQuantity?: number | null
  productionUnitCost?: number | null
  paymentMethod?: string | null
  amountPaid: number
  balance: number
  receiptUrl?: string | null
  notes?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface PoultryRawMaterialPurchaseInput {
  poultryRawMaterialItemId: number
  supplierName?: string | null
  supplierId?: number | null
  purchaseDate?: string
  quantity: number
  unitCost: number
  totalCost?: number
  productionUnit?: string | null
  productionUnitsPerPurchaseUnit?: number | null
  paymentMethod?: string | null
  amountPaid?: number
  receiptUrl?: string | null
  notes?: string | null
}

export interface PoultryRawMaterialUsage {
  poultryRawMaterialUsageId: number
  farmId: string
  poultryRawMaterialItemId: number
  itemName?: string | null
  unitOfMeasure?: string | null
  poultryProductionBatchId?: number | null
  usedDate: string
  quantityUsed: number
  expectedQuantityUsed?: number | null
  variance: number
  varianceReason?: string | null
  notes?: string | null
  createdAt: string
}

// ----- Helpers -----
function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(`GET ${path} failed (${res.status}): ${t || res.statusText}`)
  }
  return (await res.json()) as T
}

async function jsend<T>(path: string, method: "POST" | "PUT" | "DELETE", body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(`${method} ${path} failed (${res.status}): ${t || res.statusText}`)
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

// ----- Raw material items -----
export const listPoultryRawMaterialItems = () =>
  jget<PoultryRawMaterialItem[]>(`/Poultry/raw-material-items?farmId=${encodeURIComponent(activeFarmId())}`)

export const createPoultryRawMaterialItem = (input: PoultryRawMaterialItemInput) =>
  jsend<PoultryRawMaterialItem>(`/Poultry/raw-material-items`, "POST", { ...input, farmId: activeFarmId() })

export const updatePoultryRawMaterialItem = (id: number, input: PoultryRawMaterialItemInput) =>
  jsend<void>(`/Poultry/raw-material-items/${id}`, "PUT", { ...input, poultryRawMaterialItemId: id, farmId: activeFarmId() })

export const deletePoultryRawMaterialItem = (id: number) =>
  jsend<void>(`/Poultry/raw-material-items/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Raw material purchases -----
export const listPoultryRawMaterialPurchases = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryRawMaterialPurchase[]>(`/Poultry/raw-material-purchases?${qs.toString()}`)
}

export const createPoultryRawMaterialPurchase = (input: PoultryRawMaterialPurchaseInput) =>
  jsend<{ poultryRawMaterialPurchaseId: number }>(`/Poultry/raw-material-purchases`, "POST", { ...input, farmId: activeFarmId() })

export const updatePoultryRawMaterialPurchase = (id: number, input: PoultryRawMaterialPurchaseInput) =>
  jsend<void>(`/Poultry/raw-material-purchases/${id}`, "PUT", { ...input, poultryRawMaterialPurchaseId: id, farmId: activeFarmId() })

export const deletePoultryRawMaterialPurchase = (id: number) =>
  jsend<void>(`/Poultry/raw-material-purchases/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

export const payPoultryRawMaterialPurchaseBalance = (
  id: number,
  input: { amount: number; paymentMethod?: string; paymentDate?: string },
) =>
  jsend<{ balance: number }>(`/Poultry/raw-material-purchases/${id}/pay-balance`, "POST", {
    farmId: activeFarmId(),
    amount: input.amount,
    paymentMethod: input.paymentMethod ?? "Cash",
    paymentDate: input.paymentDate || null,
  })

// ----- Usage history -----
export const listPoultryRawMaterialUsageHistory = (opts?: { itemId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.itemId) qs.append("itemId", String(opts.itemId))
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryRawMaterialUsage[]>(`/Poultry/raw-material-usage/history?${qs.toString()}`)
}

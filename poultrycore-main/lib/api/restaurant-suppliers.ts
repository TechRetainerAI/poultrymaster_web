import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

// =============================================================================
// Restaurant supplier side — API module (migration 329)
//
// Suppliers (Setup > Finance), purchases that carry a cost, cost recognition per
// ingredient category, the read-only Deferred inventory cost page and the
// payment state of expenses. Supplier Balances / Supplier Payments go through the
// shared lib/api/balances.ts with module "restaurant" — the backend answers the
// same contract as Poultry under /api/Restaurant.
//
// A purchase adds its stock as a FIFO lot, moves only the amount PAID NOW out of
// a cash account and leaves the rest owed to the supplier. Refusals (a closed
// day, an overdrawn account, stock already used) come back as 400 with a plain
// sentence, thrown here as the Error message. The acting user comes from the
// login token on the server.
// =============================================================================

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

function url(path: string, query: Record<string, string | number | undefined | null> = {}): string {
  const q = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v))
  return farmApiUrl(`/Restaurant${path}?${q.toString()}`)
}

async function get<T>(path: string, query?: Record<string, string | number | undefined | null>): Promise<T> {
  const res = await fetch(url(path, query), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

async function send<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(url(path), { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

// ----- Suppliers ---------------------------------------------------------------

/** Rows come back with the database's lowercase column names. */
export interface RestaurantSupplierRow {
  restaurantsupplierid: number
  name: string
  contactname?: string | null
  phone?: string | null
  email?: string | null
  address?: string | null
  category?: string | null
  notes?: string | null
  isactive: boolean
  createdat?: string | null
}

export interface RestaurantSupplierInput {
  name: string
  contactName?: string | null
  phone?: string | null
  email?: string | null
  address?: string | null
  category?: string | null
  notes?: string | null
}

/** What restaurants buy, for the supplier's Category. "Other" is typed. */
export const SUPPLIER_CATEGORIES = [
  "Food ingredients", "Vegetables & fruit", "Meat & poultry", "Fish & seafood", "Drinks",
  "Cooking materials", "Packaging", "Tableware", "Cleaning & kitchen supplies",
] as const

export function listSuppliers(): Promise<RestaurantSupplierRow[]> {
  return get<RestaurantSupplierRow[]>("/setup/suppliers")
}

export function createSupplier(input: RestaurantSupplierInput): Promise<{ restaurantSupplierId: number }> {
  return send("POST", "/setup/suppliers", { ...input, farmId: farmId() })
}

export function updateSupplier(id: number, input: RestaurantSupplierInput): Promise<void> {
  return send("PUT", `/setup/suppliers/${id}`, { ...input, farmId: farmId(), isActive: true })
}

/** Deactivated rather than deleted once it has purchases or payments; refused while it is owed money. */
export async function deleteSupplier(id: number): Promise<void> {
  const res = await fetch(url(`/setup/suppliers/${id}`), { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- Purchases -----------------------------------------------------------------

export type CostMode = "EXPENSE_WHEN_PURCHASED" | "EXPENSE_WHEN_CONSUMED"

export const COST_MODE_LABELS: Record<CostMode, string> = {
  EXPENSE_WHEN_PURCHASED: "Expense when purchased",
  EXPENSE_WHEN_CONSUMED: "Expense when consumed",
}

export interface RestaurantPurchase {
  purchaseId: number
  purchaseDate: string
  ingredientId: number
  ingredientName?: string | null
  category?: string | null
  unit?: string | null
  supplierId?: number | null
  supplierName?: string | null
  quantity: number
  unitCost: number
  totalCost: number
  paymentMethod?: string | null
  /** Paid when the purchase was recorded. */
  amountPaid: number
  /** Applied by supplier payments since. */
  allocated: number
  balance: number
  paymentStatus?: string | null
  dueDate?: string | null
  cashAccountId?: number | null
  cashAccountName?: string | null
  costMode?: CostMode | null
  remainingQuantity: number
  deferredTotalCost: number
  deferredRemainingCost: number
  notes?: string | null
  status: "Posted" | "Reversed" | string
  createdBy?: string | null
  createdAt: string
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface RestaurantPurchaseInput {
  ingredientId: number
  quantity: number
  totalCost: number
  purchaseDate?: string | null
  supplierId?: number | null
  supplierName?: string | null
  paymentMethod?: string | null
  /** Null = paid in full (nothing, for Credit). */
  amountPaid?: number | null
  cashAccountId?: number | null
  dueDate?: string | null
  notes?: string | null
}

export function listPurchases(query: { from?: string; to?: string; supplierId?: number; ingredientId?: number; purchaseId?: number } = {}) {
  return get<RestaurantPurchase[]>("/purchases", query)
}

export function createPurchase(input: RestaurantPurchaseInput): Promise<{ purchaseId: number }> {
  return send("POST", "/purchases", input)
}

export function reversePurchase(id: number, reason: string): Promise<void> {
  return send("POST", `/purchases/${id}/reverse`, { reason })
}

export interface RestaurantCostModeRow {
  category: string
  costMode: CostMode
  ingredientCount: number
  isConfigured: boolean
  updatedBy?: string | null
  updatedAt?: string | null
}

export function listCostModes(): Promise<RestaurantCostModeRow[]> {
  return get<RestaurantCostModeRow[]>("/purchases/cost-recognition")
}

export function setCostMode(category: string, costMode: CostMode): Promise<void> {
  return send("PUT", "/purchases/cost-recognition", { category, costMode })
}

// ----- Deferred inventory cost ----------------------------------------------------

export type DeferredScope = "DEFERRED" | "RECOGNIZED" | "EXCEPTION" | "ALL"

export interface RestaurantDeferredSummary {
  remainingDeferredCost: number
  recognizedCost: number
  deferredBasis: number
  operationalCost: number
  purchaseCount: number
  deferredPurchases: number
  fullyRecognized: number
  notRecognized: number
  exceptions: number
  exceptionDrift: number
  recognitionPercent: number
  blockedPurchases: number
  blockedCost: number
}

export interface RestaurantDeferredPurchase {
  purchaseId: number
  purchaseDate: string
  ingredientId: number
  itemName: string
  category?: string | null
  unit?: string | null
  supplierId?: number | null
  supplierName?: string | null
  purchasedQuantity: number
  consumedQuantity: number
  remainingQuantity: number
  operationalCost: number
  deferredTotalCost: number
  recognizedCost: number
  deferredRemainingCost: number
  recognitionPercent: number
  allocatedRecognizedCost: number
  recognitionDrift: number
  costRecognitionMethod: CostMode
  recognitionMethodLabel: string
  status: string
  exceptionReason?: string | null
  recognitionEvents: number
  lastRecognitionDate?: string | null
  costingMethod: string
  queuePosition?: number | null
  quantityAheadInQueue: number
}

export interface RestaurantDeferredHistoryRow {
  drawId: number
  usedDate: string
  sourceType: string
  sourceLabel: string
  quantityDrawn: number
  unit?: string | null
  unitCostAtDraw: number
  operationalCost: number
  recognizedCost: number
  recognitionOutcome: string
  isReversed: boolean
}

export function getDeferredCosts(q: {
  scope?: DeferredScope; itemId?: number | null; category?: string | null
  fromDate?: string | null; toDate?: string | null; search?: string | null
}): Promise<{ summary: RestaurantDeferredSummary; purchases: RestaurantDeferredPurchase[] }> {
  return get("/deferred-inventory-costs", {
    scope: q.scope, itemId: q.itemId ?? undefined, category: q.category ?? undefined,
    fromDate: q.fromDate ?? undefined, toDate: q.toDate ?? undefined, search: q.search ?? undefined,
  })
}

export function getDeferredCostHistory(purchaseId: number): Promise<RestaurantDeferredHistoryRow[]> {
  return get(`/deferred-inventory-costs/${purchaseId}/history`)
}

// ----- Expenses ---------------------------------------------------------------------

export interface RestaurantExpensePayment {
  expenseId: number
  supplierId?: number | null
  supplierName?: string | null
  amountPaid: number
  balance: number
  paymentStatus: "Paid" | "PartiallyPaid" | "Unpaid" | string
  /** Migration 337: paid when recorded (what Edit changes), settled by supplier payments, and the account paid from. */
  paidAtEntry?: number
  allocated?: number
  cashAccountId?: number | null
  dueDate?: string | null
}

export function listExpensePayments(from?: string, to?: string): Promise<RestaurantExpensePayment[]> {
  return get<RestaurantExpensePayment[]>("/expenses/payments", { from, to })
}

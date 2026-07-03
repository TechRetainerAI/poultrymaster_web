import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { forceReauth } from "./session-expiry"

// Poultry Driver / Distribution API wrappers (full-fidelity port of the water
// driver module — lib/api/water.ts "W2: Distribution" section). Crate/eggs-per-
// crate vocabulary. Calls hit /Poultry/* on the Farm API via the same-origin
// proxy. Coexists with the simpler flat poultry-deliveries module.

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
function activeFarmId(): string {
  const { farmId } = getUserContext()
  return farmId || ""
}
function activeUserId(): string | null {
  const { userId } = getUserContext()
  return userId || null
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
function qs(params: Record<string, string | number | undefined | null>): string {
  const p = new URLSearchParams({ farmId: activeFarmId() })
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== null && v !== "") p.append(k, String(v))
  return p.toString()
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
export interface PoultryDriver {
  poultryDriverId: number
  farmId: string
  driverName: string
  phoneNumber?: string | null
  licenseNumber?: string | null
  defaultVehicleId?: number | null
  defaultRouteId?: number | null
  basePay?: number | null
  commissionPerCrate?: number | null
  isActive: boolean
  employeeUserId?: string | null
  employeeEmail?: string | null
  employeeUserName?: string | null
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}
export interface PoultryDriverInput {
  driverName: string
  phoneNumber?: string | null
  licenseNumber?: string | null
  defaultVehicleId?: number | null
  defaultRouteId?: number | null
  basePay?: number | null
  commissionPerCrate?: number | null
  isActive?: boolean
  notes?: string | null
}

export interface PoultryVehicle {
  poultryVehicleId: number
  farmId: string
  vehicleName: string
  vehicleType?: string | null
  registrationNumber?: string | null
  defaultDriverId?: number | null
  capacityCrates?: number | null
  fuelType?: string | null
  status: string
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}
export interface PoultryVehicleInput {
  vehicleName: string
  vehicleType?: string | null
  registrationNumber?: string | null
  defaultDriverId?: number | null
  capacityCrates?: number | null
  fuelType?: string | null
  status?: string
  notes?: string | null
}

export interface PoultryRoute {
  poultryRouteId: number
  farmId: string
  routeName: string
  areaCovered?: string | null
  defaultDriverId?: number | null
  defaultVehicleId?: number | null
  expectedCustomers?: number | null
  expectedCratesSold?: number | null
  isActive: boolean
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}
export interface PoultryRouteInput {
  routeName: string
  areaCovered?: string | null
  defaultDriverId?: number | null
  defaultVehicleId?: number | null
  expectedCustomers?: number | null
  expectedCratesSold?: number | null
  isActive?: boolean
  notes?: string | null
}

export interface PoultryVehicleLoading {
  poultryVehicleLoadingId: number
  farmId: string
  loadDate: string
  poultryVehicleId: number
  poultryDriverId?: number | null
  assistantStaffId?: number | null
  poultryRouteId?: number | null
  poultryProductId: number
  cratesLoaded: number
  eggsPerCrate: number
  expectedSellingPricePerCrate: number
  expectedCash: number
  openingCashWithDriver: number
  status: string
  notes?: string | null
  vehicleName?: string | null
  driverName?: string | null
  routeName?: string | null
  productName?: string | null
  registrationNumber?: string | null
  createdAt: string
}
export interface PoultryVehicleLoadingItem {
  poultryVehicleLoadingItemId: number
  poultryVehicleLoadingId: number
  poultryProductId: number
  productName?: string | null
  productUnit?: string | null
  cratesLoaded: number
  eggsPerCrate: number
  unitPrice: number
  expectedAmount: number
  notes?: string | null
}
export interface PoultryVehicleLoadingItemInput {
  poultryProductId: number
  cratesLoaded: number
  unitPrice: number
  eggsPerCrate?: number
  notes?: string | null
}
export interface PoultryVehicleLoadingInput {
  loadDate?: string
  poultryVehicleId: number
  poultryDriverId?: number | null
  assistantStaffId?: number | null
  poultryRouteId?: number | null
  openingCashWithDriver?: number
  notes?: string | null
  items: PoultryVehicleLoadingItemInput[]
}

export interface PoultryDriverReturn {
  poultryDriverReturnId: number
  farmId: string
  poultryVehicleLoadingId: number
  returnDate: string
  cratesSold: number
  cratesReturned: number
  cratesDamaged: number
  missingCrates: number
  cashCollected: number
  moMoCollected: number
  bankCollected: number
  creditSalesAmount: number
  totalAccountedFor: number
  cashReturnedByDriver: number
  approvedDeliveryExpenses: number
  shortageAmount: number
  overageAmount: number
  salesPostingMode: string
  primaryCustomerId?: number | null
  status: string
  notes?: string | null
  vehicleName?: string | null
  driverName?: string | null
  routeName?: string | null
  poultryDriverId?: number | null
  poultryVehicleId?: number | null
  poultryRouteId?: number | null
  loadingCratesLoaded?: number | null
  loadingExpectedCash?: number | null
  createdAt: string
}
export interface PoultryDriverReturnItem {
  poultryDriverReturnItemId: number
  poultryDriverReturnId: number
  poultryProductId: number
  productName?: string | null
  cratesLoaded: number
  cratesSold: number
  cratesReturned: number
  cratesDamaged: number
  unitPrice: number
  expectedSales: number
  notes?: string | null
}
export interface PoultryDriverReturnItemInput {
  poultryProductId: number
  cratesSold: number
  cratesReturned: number
  cratesDamaged: number
  unitPrice: number
  notes?: string | null
}
export interface PoultryDriverReturnCustomerSaleItemInput {
  poultryProductId: number
  quantity: number
  unitPrice: number
}
export interface PoultryDriverReturnCustomerSaleInput {
  customerId?: number | null
  customerLabel?: string | null
  cashPaid?: number
  moMoPaid?: number
  bankPaid?: number
  creditAmount?: number
  notes?: string | null
  items?: PoultryDriverReturnCustomerSaleItemInput[]
}
export interface PoultryDriverReturnCustomerSaleRow {
  poultryDriverReturnCustomerSaleId: number
  poultryDriverReturnId: number
  customerId?: number | null
  customerLabel?: string | null
  totalAmount: number
  cashPaid: number
  moMoPaid: number
  bankPaid: number
  creditAmount: number
  generatedSaleId?: number | null
  notes?: string | null
}
export interface PoultryDeliveryExpenseInput {
  expenseCategory: string
  amount: number
  description?: string | null
  isApproved?: boolean
  notes?: string | null
}
export interface PoultryDriverDeliveryExpense {
  poultryDriverDeliveryExpenseId: number
  farmId: string
  poultryDriverReturnId?: number | null
  poultryVehicleLoadingId?: number | null
  expenseCategory: string
  amount: number
  description?: string | null
  isApproved: boolean
  linkedExpenseId?: number | null
  notes?: string | null
  driverName?: string | null
  returnDate?: string | null
  createdAt: string
}
export interface PoultryDriverReturnInput {
  poultryVehicleLoadingId: number
  returnDate?: string
  cratesSold: number
  cratesReturned: number
  cratesDamaged?: number
  missingCrates?: number
  cashCollected?: number
  moMoCollected?: number
  bankCollected?: number
  creditSalesAmount?: number
  cashReturnedByDriver?: number
  approvedDeliveryExpenses?: number
  salesPostingMode?: string
  primaryCustomerId?: number | null
  notes?: string | null
  items?: PoultryDriverReturnItemInput[]
  customerSales?: PoultryDriverReturnCustomerSaleInput[]
  expenses?: PoultryDeliveryExpenseInput[]
}

export interface PoultryDriverShortage {
  poultryDriverShortageId: number
  farmId: string
  poultryDriverId?: number | null
  poultryVehicleLoadingId?: number | null
  poultryDriverReturnId: number
  shortageDate: string
  expectedAmount: number
  actualAmount: number
  shortageAmount: number
  reason?: string | null
  status: string
  approvedBy?: string | null
  notes?: string | null
  driverName?: string | null
}

export interface PoultryDriverReconciliationRow {
  poultryDriverId?: number | null
  driverName?: string | null
  deliveryRuns: number
  totalCratesLoaded: number
  totalCratesSold: number
  totalCratesReturned: number
  totalCratesLost: number
  expectedRevenue: number
  accountedRevenue: number
  totalShortage: number
  totalOverage: number
}
export interface PoultryDriverCollectionDetailRow {
  poultryDriverId?: number | null
  driverName?: string | null
  poultryDriverReturnId: number
  returnDate: string
  productName?: string | null
  cratesLoaded: number
  cratesSold: number
  cratesReturned: number
  cratesDamaged: number
  expectedAmount: number
}
export interface PoultryDriverCollectionTotalsRow {
  poultryDriverId?: number | null
  driverName?: string | null
  deliveryRuns: number
  totalCratesLoaded: number
  totalCratesSold: number
  totalCratesReturned: number
  totalCratesLost: number
  totalExpected: number
  totalCollected: number
  totalShortage: number
}
export interface PoultryDriverCollectionReport {
  detail: PoultryDriverCollectionDetailRow[]
  totals: PoultryDriverCollectionTotalsRow[]
}

// ---------------------------------------------------------------------------
// Drivers
// ---------------------------------------------------------------------------
export const listPoultryDrivers = () =>
  jget<PoultryDriver[]>(`/Poultry/drivers?farmId=${encodeURIComponent(activeFarmId())}`)
export const listPoultryDriversForFarm = () =>
  jget<PoultryDriver[]>(`/Poultry/drivers/list-for-farm?farmId=${encodeURIComponent(activeFarmId())}`)
export const createPoultryDriver = (input: PoultryDriverInput) =>
  jsend<PoultryDriver>(`/Poultry/drivers`, "POST", { ...input, farmId: activeFarmId() })
export const updatePoultryDriver = (id: number, input: PoultryDriverInput) =>
  jsend<void>(`/Poultry/drivers/${id}`, "PUT", { ...input, poultryDriverId: id, farmId: activeFarmId() })
export const deletePoultryDriver = (id: number) =>
  jsend<void>(`/Poultry/drivers/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")
export const createPoultryDriverFromEmployee = (input: {
  employeeUserId: string
  driverName?: string
  phoneNumber?: string | null
  licenseNumber?: string | null
  basePay?: number | null
  commissionPerCrate?: number | null
}) => jsend<PoultryDriver>(`/Poultry/drivers/from-employee`, "POST", { ...input, farmId: activeFarmId() })

// ---------------------------------------------------------------------------
// Vehicles
// ---------------------------------------------------------------------------
export const listPoultryVehicles = () =>
  jget<PoultryVehicle[]>(`/Poultry/vehicles?farmId=${encodeURIComponent(activeFarmId())}`)
export const createPoultryVehicle = (input: PoultryVehicleInput) =>
  jsend<PoultryVehicle>(`/Poultry/vehicles`, "POST", { ...input, farmId: activeFarmId() })
export const updatePoultryVehicle = (id: number, input: PoultryVehicleInput) =>
  jsend<void>(`/Poultry/vehicles/${id}`, "PUT", { ...input, poultryVehicleId: id, farmId: activeFarmId() })
export const deletePoultryVehicle = (id: number) =>
  jsend<void>(`/Poultry/vehicles/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
export const listPoultryRoutes = () =>
  jget<PoultryRoute[]>(`/Poultry/routes?farmId=${encodeURIComponent(activeFarmId())}`)
export const createPoultryRoute = (input: PoultryRouteInput) =>
  jsend<PoultryRoute>(`/Poultry/routes`, "POST", { ...input, farmId: activeFarmId() })
export const updatePoultryRoute = (id: number, input: PoultryRouteInput) =>
  jsend<void>(`/Poultry/routes/${id}`, "PUT", { ...input, poultryRouteId: id, farmId: activeFarmId() })
export const deletePoultryRoute = (id: number) =>
  jsend<void>(`/Poultry/routes/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ---------------------------------------------------------------------------
// Vehicle loadings
// ---------------------------------------------------------------------------
export const listPoultryVehicleLoadings = (opts?: { status?: string; fromDate?: string; toDate?: string }) =>
  jget<PoultryVehicleLoading[]>(`/Poultry/vehicle-loadings?${qs({ status: opts?.status, fromDate: opts?.fromDate, toDate: opts?.toDate })}`)
export const getPoultryVehicleLoading = (id: number) =>
  jget<PoultryVehicleLoading>(`/Poultry/vehicle-loadings/${id}?farmId=${encodeURIComponent(activeFarmId())}`)
export const listPoultryVehicleLoadingItems = (id: number) =>
  jget<PoultryVehicleLoadingItem[]>(`/Poultry/vehicle-loadings/${id}/items?farmId=${encodeURIComponent(activeFarmId())}`)
export const createPoultryVehicleLoading = (input: PoultryVehicleLoadingInput) =>
  jsend<{ poultryVehicleLoadingId: number }>(`/Poultry/vehicle-loadings`, "POST", { ...input, farmId: activeFarmId(), createdBy: activeUserId() })
export const approvePoultryVehicleLoading = (id: number) =>
  jsend<void>(`/Poultry/vehicle-loadings/${id}/approve?${qs({ approvedBy: activeUserId() })}`, "POST")
export const cancelPoultryVehicleLoading = (id: number) =>
  jsend<void>(`/Poultry/vehicle-loadings/${id}/cancel?${qs({})}`, "POST")
export const voidPoultryVehicleLoading = (id: number) =>
  jsend<void>(`/Poultry/vehicle-loadings/${id}/void?${qs({})}`, "POST")
export const reloadPoultryVehicleLoading = (id: number) =>
  jsend<{ poultryVehicleLoadingId: number }>(`/Poultry/vehicle-loadings/${id}/reload?${qs({ createdBy: activeUserId() })}`, "POST")

// ---------------------------------------------------------------------------
// Driver returns
// ---------------------------------------------------------------------------
export const listPoultryDriverReturns = (opts?: { status?: string; fromDate?: string; toDate?: string }) =>
  jget<PoultryDriverReturn[]>(`/Poultry/driver-returns?${qs({ status: opts?.status, fromDate: opts?.fromDate, toDate: opts?.toDate })}`)
export const getPoultryDriverReturn = (id: number) =>
  jget<PoultryDriverReturn>(`/Poultry/driver-returns/${id}?farmId=${encodeURIComponent(activeFarmId())}`)
export const listPoultryDriverReturnItems = (id: number) =>
  jget<PoultryDriverReturnItem[]>(`/Poultry/driver-returns/${id}/items?farmId=${encodeURIComponent(activeFarmId())}`)
export const listPoultryDriverReturnCustomerSales = (id: number) =>
  jget<PoultryDriverReturnCustomerSaleRow[]>(`/Poultry/driver-returns/${id}/customer-sales?farmId=${encodeURIComponent(activeFarmId())}`)
export const listPoultryDriverReturnExpenses = (id: number) =>
  jget<PoultryDriverDeliveryExpense[]>(`/Poultry/driver-returns/${id}/expenses?farmId=${encodeURIComponent(activeFarmId())}`)
export const createPoultryDriverReturn = (input: PoultryDriverReturnInput) =>
  jsend<{ poultryDriverReturnId: number }>(`/Poultry/driver-returns`, "POST", { ...input, farmId: activeFarmId(), createdBy: activeUserId() })
export const approvePoultryDriverReturn = (id: number) =>
  jsend<void>(`/Poultry/driver-returns/${id}/approve?${qs({ approvedBy: activeUserId() })}`, "POST")
export const approveReconcilePoultryDriverReturn = (input: PoultryDriverReturnInput) =>
  jsend<void>(`/Poultry/driver-returns/approve-reconcile`, "POST", { ...input, farmId: activeFarmId(), createdBy: activeUserId() })
export const cancelPoultryDriverReturn = (id: number) =>
  jsend<void>(`/Poultry/driver-returns/${id}/cancel?${qs({})}`, "POST")
export const uncancelPoultryDriverReturn = (id: number) =>
  jsend<void>(`/Poultry/driver-returns/${id}/uncancel?${qs({})}`, "POST")
export const reversePoultryDriverReturn = (id: number) =>
  jsend<void>(`/Poultry/driver-returns/${id}/reverse?${qs({})}`, "POST")
export const deletePoultryDriverReturn = (id: number) =>
  jsend<void>(`/Poultry/driver-returns/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")
export const updatePoultryDriverReturnPostingMode = (id: number, salesPostingMode: string) =>
  jsend<void>(`/Poultry/driver-returns/${id}/posting-mode`, "POST", { farmId: activeFarmId(), salesPostingMode })

// ---------------------------------------------------------------------------
// Delivery expenses (ledger listing)
// ---------------------------------------------------------------------------
export const listPoultryDeliveryExpenses = (opts?: { fromDate?: string; toDate?: string }) =>
  jget<PoultryDriverDeliveryExpense[]>(`/Poultry/driver-delivery-expenses?${qs({ fromDate: opts?.fromDate, toDate: opts?.toDate })}`)

// ---------------------------------------------------------------------------
// Shortages
// ---------------------------------------------------------------------------
export const listPoultryDriverShortages = (status?: string) =>
  jget<PoultryDriverShortage[]>(`/Poultry/driver-shortages?${qs({ status })}`)
export const resolvePoultryDriverShortage = (id: number, status: string, notes?: string) =>
  jsend<void>(`/Poultry/driver-shortages/${id}/resolve`, "POST", { farmId: activeFarmId(), status, approvedBy: activeUserId(), notes: notes ?? null })

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------
export const getPoultryDriverReconciliation = (fromDate?: string, toDate?: string) =>
  jget<PoultryDriverReconciliationRow[]>(`/Poultry/reports/driver-reconciliation?${qs({ fromDate, toDate })}`)
export const getPoultryDriverCollection = (opts?: { fromDate?: string; toDate?: string; poultryDriverId?: number }) =>
  jget<PoultryDriverCollectionReport>(`/Poultry/reports/driver-collection?${qs({ fromDate: opts?.fromDate, toDate: opts?.toDate, poultryDriverId: opts?.poultryDriverId })}`)

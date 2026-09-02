import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

// =============================================================================
// Restaurant Management System — API Module (Phase R1: Setup + Menu)
// =============================================================================

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function jget<T>(endpoint: string): Promise<T> {
  const farmId = activeFarmId()
  const sep = endpoint.includes("?") ? "&" : "?"
  const url = farmApiUrl(`${endpoint}${sep}farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

async function jsend<T>(endpoint: string, method: string, body?: unknown): Promise<T> {
  const url = farmApiUrl(endpoint)
  const res = await fetch(url, {
    method,
    headers: getAuthHeaders(),
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

async function jdelete(endpoint: string): Promise<void> {
  const farmId = activeFarmId()
  const sep = endpoint.includes("?") ? "&" : "?"
  const url = farmApiUrl(`${endpoint}${sep}farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// =============================================================================
// TYPES
// =============================================================================

// ----- Profile -----

export interface RestaurantProfile {
  restaurantProfileId: number
  farmId: string
  restaurantName: string
  address?: string | null
  city?: string | null
  country?: string | null
  phone?: string | null
  email?: string | null
  cuisineType?: string | null
  serviceTypes?: string | null
  openingTime: string
  closingTime: string
  defaultCurrency: string
  taxRate: number
  serviceChargeRate: number
  timeZone?: string | null
  logoUrl?: string | null
  description?: string | null
  seatingCapacity: number
  createdAt: string
  updatedAt?: string | null
}

export interface RestaurantProfileInput {
  restaurantName: string
  address?: string | null
  city?: string | null
  country?: string | null
  phone?: string | null
  email?: string | null
  cuisineType?: string | null
  serviceTypes?: string | null
  openingTime?: string
  closingTime?: string
  defaultCurrency?: string
  taxRate?: number
  serviceChargeRate?: number
  timeZone?: string | null
  logoUrl?: string | null
  description?: string | null
  seatingCapacity?: number
}

// ----- Menu Categories -----

export interface MenuCategory {
  menuCategoryId: number
  farmId: string
  parentCategoryId?: number | null
  name: string
  description?: string | null
  imageUrl?: string | null
  sortOrder: number
  isActive: boolean
  createdAt: string
  updatedAt?: string | null
}

export interface MenuCategoryInput {
  parentCategoryId?: number | null
  name: string
  description?: string | null
  imageUrl?: string | null
  sortOrder?: number
  isActive?: boolean
}

// ----- Menu Items -----

export interface MenuItem {
  menuItemId: number
  farmId: string
  menuCategoryId?: number | null
  categoryName?: string | null
  name: string
  description?: string | null
  price: number
  costPrice: number
  imageUrl?: string | null
  prepTime: number
  calories?: number | null
  allergens?: string | null
  spicyLevel: number
  isVegetarian: boolean
  isVegan: boolean
  isGlutenFree: boolean
  isHalal: boolean
  isKosher: boolean
  isAvailable: boolean
  isActive: boolean
  sortOrder: number
  sku?: string | null
  barcode?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface MenuItemInput {
  menuCategoryId?: number | null
  name: string
  description?: string | null
  price: number
  costPrice?: number
  imageUrl?: string | null
  prepTime?: number
  calories?: number | null
  allergens?: string | null
  spicyLevel?: number
  isVegetarian?: boolean
  isVegan?: boolean
  isGlutenFree?: boolean
  isHalal?: boolean
  isKosher?: boolean
  isAvailable?: boolean
  isActive?: boolean
  sortOrder?: number
  sku?: string | null
  barcode?: string | null
}

// ----- Modifier Groups -----

export interface ModifierGroup {
  modifierGroupId: number
  farmId: string
  name: string
  description?: string | null
  isRequired: boolean
  minSelections: number
  maxSelections: number
  sortOrder: number
  isActive: boolean
  createdAt: string
  updatedAt?: string | null
}

export interface ModifierGroupInput {
  name: string
  description?: string | null
  isRequired?: boolean
  minSelections?: number
  maxSelections?: number
  sortOrder?: number
  isActive?: boolean
}

// ----- Modifiers -----

export interface Modifier {
  modifierId: number
  farmId: string
  modifierGroupId: number
  groupName?: string | null
  name: string
  priceAdjustment: number
  isDefault: boolean
  isAvailable: boolean
  sortOrder: number
  createdAt: string
  updatedAt?: string | null
}

export interface ModifierInput {
  modifierGroupId: number
  name: string
  priceAdjustment?: number
  isDefault?: boolean
  isAvailable?: boolean
  sortOrder?: number
}

// ----- Menu Item Modifier Group (junction) -----

export interface MenuItemModifierGroup {
  menuItemModifierGroupId: number
  farmId: string
  menuItemId: number
  modifierGroupId: number
  groupName?: string | null
  isRequired: boolean
  minSelections: number
  maxSelections: number
  sortOrder: number
}

// ----- Combos -----

export interface Combo {
  comboId: number
  farmId: string
  name: string
  description?: string | null
  price: number
  imageUrl?: string | null
  isActive: boolean
  sortOrder: number
  createdAt: string
  updatedAt?: string | null
}

export interface ComboInput {
  name: string
  description?: string | null
  price: number
  imageUrl?: string | null
  isActive?: boolean
  sortOrder?: number
}

export interface ComboItem {
  comboItemId: number
  farmId: string
  comboId: number
  menuItemId?: number | null
  menuItemName?: string | null
  menuCategoryId?: number | null
  categoryName?: string | null
  quantity: number
  sortOrder: number
}

export interface ComboItemInput {
  menuItemId?: number | null
  menuCategoryId?: number | null
  quantity?: number
  sortOrder?: number
}

// ----- Menu Schedules -----

export interface MenuSchedule {
  menuScheduleId: number
  farmId: string
  name: string
  startTime: string
  endTime: string
  daysOfWeek?: string | null
  isActive: boolean
  createdAt: string
  updatedAt?: string | null
}

export interface MenuScheduleInput {
  name: string
  startTime: string
  endTime: string
  daysOfWeek?: string | null
  isActive?: boolean
}

export interface MenuScheduleItem {
  menuScheduleItemId: number
  farmId: string
  menuScheduleId: number
  menuItemId: number
  menuItemName?: string | null
  overridePrice?: number | null
}

// ----- Item Tags -----

export interface ItemTag {
  itemTagId: number
  farmId: string
  menuItemId: number
  tag: string
}

// =============================================================================
// API FUNCTIONS
// =============================================================================

// ----- Profile -----

export async function getRestaurantProfile(): Promise<RestaurantProfile> {
  return jget<RestaurantProfile>("/Restaurant/setup/profile")
}

export async function upsertRestaurantProfile(input: RestaurantProfileInput): Promise<RestaurantProfile> {
  const farmId = activeFarmId()
  return jsend<RestaurantProfile>("/Restaurant/setup/profile", "POST", { ...input, farmId })
}

// ----- Menu Categories -----

export async function listMenuCategories(): Promise<MenuCategory[]> {
  return jget<MenuCategory[]>("/Restaurant/menu/categories")
}

export async function getMenuCategory(id: number): Promise<MenuCategory> {
  return jget<MenuCategory>(`/Restaurant/menu/categories/${id}`)
}

export async function createMenuCategory(input: MenuCategoryInput): Promise<MenuCategory> {
  const farmId = activeFarmId()
  return jsend<MenuCategory>("/Restaurant/menu/categories", "POST", { ...input, farmId })
}

export async function updateMenuCategory(id: number, input: MenuCategoryInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/menu/categories/${id}`, "PUT", { ...input, farmId })
}

export async function deleteMenuCategory(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/categories/${id}`)
}

// ----- Menu Items -----

export async function listMenuItems(categoryId?: number): Promise<MenuItem[]> {
  const extra = categoryId ? `&categoryId=${categoryId}` : ""
  return jget<MenuItem[]>(`/Restaurant/menu/items?_=1${extra}`)
}

export async function getMenuItem(id: number): Promise<MenuItem> {
  return jget<MenuItem>(`/Restaurant/menu/items/${id}`)
}

export async function createMenuItem(input: MenuItemInput): Promise<MenuItem> {
  const farmId = activeFarmId()
  return jsend<MenuItem>("/Restaurant/menu/items", "POST", { ...input, farmId })
}

export async function updateMenuItem(id: number, input: MenuItemInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/menu/items/${id}`, "PUT", { ...input, farmId })
}

export async function deleteMenuItem(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/items/${id}`)
}

export async function toggleMenuItemAvailability(id: number, isAvailable: boolean): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/menu/items/${id}/availability?farmId=${encodeURIComponent(farmId)}&isAvailable=${isAvailable}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- Modifier Groups -----

export async function listModifierGroups(): Promise<ModifierGroup[]> {
  return jget<ModifierGroup[]>("/Restaurant/menu/modifier-groups")
}

export async function createModifierGroup(input: ModifierGroupInput): Promise<{ modifierGroupId: number }> {
  const farmId = activeFarmId()
  return jsend<{ modifierGroupId: number }>("/Restaurant/menu/modifier-groups", "POST", { ...input, farmId })
}

export async function updateModifierGroup(id: number, input: ModifierGroupInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/menu/modifier-groups/${id}`, "PUT", { ...input, farmId })
}

export async function deleteModifierGroup(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/modifier-groups/${id}`)
}

// ----- Modifiers -----

export async function listModifiers(groupId?: number): Promise<Modifier[]> {
  const extra = groupId ? `&groupId=${groupId}` : ""
  return jget<Modifier[]>(`/Restaurant/menu/modifiers?_=1${extra}`)
}

export async function createModifier(input: ModifierInput): Promise<{ modifierId: number }> {
  const farmId = activeFarmId()
  return jsend<{ modifierId: number }>("/Restaurant/menu/modifiers", "POST", { ...input, farmId })
}

export async function updateModifier(id: number, input: ModifierInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/menu/modifiers/${id}`, "PUT", { ...input, farmId })
}

export async function deleteModifier(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/modifiers/${id}`)
}

// ----- Menu Item <-> Modifier Group -----

export async function listItemModifierGroups(menuItemId: number): Promise<MenuItemModifierGroup[]> {
  return jget<MenuItemModifierGroup[]>(`/Restaurant/menu/items/${menuItemId}/modifier-groups`)
}

export async function assignModifierGroupToItem(
  menuItemId: number, modifierGroupId: number, sortOrder: number = 0
): Promise<{ menuItemModifierGroupId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/menu/items/${menuItemId}/modifier-groups?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ modifierGroupId, sortOrder }),
  })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

export async function unassignModifierGroupFromItem(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/items/modifier-groups/${id}`)
}

// ----- Combos -----

export async function listCombos(): Promise<Combo[]> {
  return jget<Combo[]>("/Restaurant/menu/combos")
}

export async function createCombo(input: ComboInput): Promise<{ comboId: number }> {
  const farmId = activeFarmId()
  return jsend<{ comboId: number }>("/Restaurant/menu/combos", "POST", { ...input, farmId })
}

export async function updateCombo(id: number, input: ComboInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/menu/combos/${id}`, "PUT", { ...input, farmId })
}

export async function deleteCombo(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/combos/${id}`)
}

// ---- Combo Items ----

export async function listComboItems(comboId: number): Promise<ComboItem[]> {
  return jget<ComboItem[]>(`/Restaurant/menu/combos/${comboId}/items`)
}

export async function addComboItem(comboId: number, input: ComboItemInput): Promise<{ comboItemId: number }> {
  const farmId = activeFarmId()
  return jsend<{ comboItemId: number }>(`/Restaurant/menu/combos/${comboId}/items`, "POST", { ...input, farmId })
}

export async function removeComboItem(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/combos/items/${id}`)
}

// ----- Menu Schedules -----

export async function listMenuSchedules(): Promise<MenuSchedule[]> {
  return jget<MenuSchedule[]>("/Restaurant/menu/schedules")
}

export async function createMenuSchedule(input: MenuScheduleInput): Promise<{ menuScheduleId: number }> {
  const farmId = activeFarmId()
  return jsend<{ menuScheduleId: number }>("/Restaurant/menu/schedules", "POST", { ...input, farmId })
}

export async function updateMenuSchedule(id: number, input: MenuScheduleInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/menu/schedules/${id}`, "PUT", { ...input, farmId })
}

export async function deleteMenuSchedule(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/schedules/${id}`)
}

// ---- Schedule Items ----

export async function listScheduleItems(scheduleId: number): Promise<MenuScheduleItem[]> {
  return jget<MenuScheduleItem[]>(`/Restaurant/menu/schedules/${scheduleId}/items`)
}

export async function assignItemToSchedule(
  scheduleId: number, menuItemId: number, overridePrice?: number | null
): Promise<{ menuScheduleItemId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/menu/schedules/${scheduleId}/items?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ menuItemId, overridePrice }),
  })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

export async function unassignItemFromSchedule(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/schedules/items/${id}`)
}

// ----- Item Tags -----

export async function listItemTags(menuItemId: number): Promise<ItemTag[]> {
  return jget<ItemTag[]>(`/Restaurant/menu/items/${menuItemId}/tags`)
}

export async function addItemTag(menuItemId: number, tag: string): Promise<{ itemTagId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/menu/items/${menuItemId}/tags?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ tag }),
  })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

export async function removeItemTag(id: number): Promise<void> {
  await jdelete(`/Restaurant/menu/items/tags/${id}`)
}

// =============================================================================
// PHASE R2: FLOOR PLAN + POS / ORDERS
// =============================================================================

// ----- Floors -----

export interface Floor {
  floorId: number; farmId: string; name: string; floorNumber: number
  description?: string | null; isActive: boolean; sortOrder: number
  createdAt: string; updatedAt?: string | null; tableCount: number
}
export interface FloorInput {
  name: string; floorNumber?: number; description?: string | null
  isActive?: boolean; sortOrder?: number
}

export async function listFloors(): Promise<Floor[]> {
  return jget<Floor[]>("/Restaurant/floor/floors")
}
export async function createFloor(input: FloorInput): Promise<{ floorId: number }> {
  const farmId = activeFarmId()
  return jsend<{ floorId: number }>("/Restaurant/floor/floors", "POST", { ...input, farmId })
}
export async function updateFloor(id: number, input: FloorInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/floor/floors/${id}`, "PUT", { ...input, farmId })
}
export async function deleteFloor(id: number): Promise<void> {
  await jdelete(`/Restaurant/floor/floors/${id}`)
}

// ----- Tables -----

export interface RestaurantTable {
  tableId: number; farmId: string; floorId?: number | null; floorName?: string | null
  tableNumber: string; tableName?: string | null; capacity: number
  shape: string; status: string
  positionX: number; positionY: number; width: number; height: number
  isActive: boolean; currentOrderId?: number | null
  createdAt: string; updatedAt?: string | null
}
export interface TableInput {
  floorId?: number | null; tableNumber: string; tableName?: string | null
  capacity?: number; shape?: string
  positionX?: number; positionY?: number; width?: number; height?: number
  isActive?: boolean
}

export async function listTables(floorId?: number, status?: string): Promise<RestaurantTable[]> {
  let extra = ""
  if (floorId) extra += `&floorId=${floorId}`
  if (status) extra += `&status=${encodeURIComponent(status)}`
  return jget<RestaurantTable[]>(`/Restaurant/floor/tables?_=1${extra}`)
}
export async function getTable(id: number): Promise<RestaurantTable> {
  return jget<RestaurantTable>(`/Restaurant/floor/tables/${id}`)
}
export async function createTable(input: TableInput): Promise<RestaurantTable> {
  const farmId = activeFarmId()
  return jsend<RestaurantTable>("/Restaurant/floor/tables", "POST", { ...input, farmId })
}
export async function updateTable(id: number, input: TableInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/floor/tables/${id}`, "PUT", { ...input, farmId })
}
export async function deleteTable(id: number): Promise<void> {
  await jdelete(`/Restaurant/floor/tables/${id}`)
}
export async function updateTableStatus(id: number, status: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/floor/tables/${id}/status?farmId=${encodeURIComponent(farmId)}&status=${encodeURIComponent(status)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function updateTablePosition(id: number, positionX: number, positionY: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/floor/tables/${id}/position?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ positionX, positionY }) })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- Orders -----

export interface Order {
  orderId: number; farmId: string; orderNumber: string; orderType: string; status: string
  tableId?: number | null; tableNumber?: string | null
  customerId?: number | null; customerName?: string | null; customerPhone?: string | null
  covers: number; subtotal: number; discountAmount: number; taxAmount: number
  serviceChargeAmount: number; totalAmount: number; paidAmount: number
  paymentStatus: string; notes?: string | null; createdBy?: string | null; servedBy?: string | null
  cancelReason?: string | null; refundReason?: string | null
  createdAt: string; updatedAt?: string | null; completedAt?: string | null
  itemCount: number
}
export interface OrderCreateInput {
  orderType?: string; tableId?: number | null; tableNumber?: string | null
  customerId?: number | null; customerName?: string | null; customerPhone?: string | null
  covers?: number; notes?: string | null; servedBy?: string | null
}

export async function listOrders(status?: string, orderType?: string, fromDate?: string, toDate?: string): Promise<Order[]> {
  let extra = ""
  if (status) extra += `&status=${encodeURIComponent(status)}`
  if (orderType) extra += `&orderType=${encodeURIComponent(orderType)}`
  if (fromDate) extra += `&fromDate=${encodeURIComponent(fromDate)}`
  if (toDate) extra += `&toDate=${encodeURIComponent(toDate)}`
  return jget<Order[]>(`/Restaurant/orders?_=1${extra}`)
}
export async function getOrder(id: number): Promise<Order> {
  return jget<Order>(`/Restaurant/orders/${id}`)
}
export async function createOrder(input: OrderCreateInput): Promise<{ orderId: number; orderNumber: string }> {
  const farmId = activeFarmId()
  return jsend<{ orderId: number; orderNumber: string }>("/Restaurant/orders", "POST", { ...input, farmId })
}
export async function updateOrderStatus(id: number, status: string, reason?: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/orders/${id}/status?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status, reason }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function recalcOrder(id: number, taxRate: number, serviceChargeRate: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/orders/${id}/recalc?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ taxRate, serviceChargeRate }) })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- Order Items -----

export interface OrderItem {
  orderItemId: number; farmId: string; orderId: number
  menuItemId?: number | null; comboId?: number | null
  itemName: string; quantity: number; unitPrice: number
  modifierTotal: number; lineTotal: number; notes?: string | null
  status: string; seatNumber?: number | null; kdsStation?: string | null
  sentToKitchenAt?: string | null; prepStartedAt?: string | null
  readyAt?: string | null; createdAt: string
}
export interface OrderItemInput {
  menuItemId?: number | null; comboId?: number | null
  itemName: string; quantity?: number; unitPrice: number
  notes?: string | null; seatNumber?: number | null; kdsStation?: string | null
  modifiers?: { modifierId?: number | null; modifierName: string; priceAdjustment: number; quantity?: number }[]
}

export async function listOrderItems(orderId: number): Promise<OrderItem[]> {
  return jget<OrderItem[]>(`/Restaurant/orders/${orderId}/items`)
}
export async function addOrderItem(orderId: number, input: OrderItemInput): Promise<{ orderItemId: number }> {
  const farmId = activeFarmId()
  return jsend<{ orderItemId: number }>(`/Restaurant/orders/${orderId}/items`, "POST", { ...input, farmId, orderId })
}
export async function updateOrderItemStatus(id: number, status: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/orders/items/${id}/status?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function cancelOrderItem(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/orders/items/${id}/cancel?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- Order Item Modifiers -----

export interface OrderItemModifier {
  orderItemModifierId: number; farmId: string; orderItemId: number
  modifierId?: number | null; modifierName: string; priceAdjustment: number; quantity: number
}
export async function listOrderItemModifiers(orderItemId: number): Promise<OrderItemModifier[]> {
  return jget<OrderItemModifier[]>(`/Restaurant/orders/items/${orderItemId}/modifiers`)
}

// ----- Order Payments -----

export interface OrderPayment {
  orderPaymentId: number; farmId: string; orderId: number
  paymentMethod: string; amount: number; tipAmount: number
  reference?: string | null; status: string; processedBy?: string | null; createdAt: string
}
export interface PaymentInput {
  paymentMethod: string; amount: number; tipAmount?: number; reference?: string | null
}

export async function listOrderPayments(orderId: number): Promise<OrderPayment[]> {
  return jget<OrderPayment[]>(`/Restaurant/orders/${orderId}/payments`)
}
export async function addOrderPayment(orderId: number, input: PaymentInput): Promise<{ orderPaymentId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/orders/${orderId}/payments?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify(input) })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

// ----- Discounts -----

export interface Discount {
  discountId: number; farmId: string; name: string; discountType: string; value: number
  couponCode?: string | null; isAutoApply: boolean; minOrderAmount: number
  maxDiscountAmount?: number | null; startDate?: string | null; endDate?: string | null
  isActive: boolean; createdAt: string; updatedAt?: string | null
}
export interface DiscountInput {
  name: string; discountType?: string; value: number; couponCode?: string | null
  isAutoApply?: boolean; minOrderAmount?: number; maxDiscountAmount?: number | null
  startDate?: string | null; endDate?: string | null; isActive?: boolean
}

export async function listDiscounts(): Promise<Discount[]> {
  return jget<Discount[]>("/Restaurant/orders/discounts")
}
export async function createDiscount(input: DiscountInput): Promise<{ discountId: number }> {
  const farmId = activeFarmId()
  return jsend<{ discountId: number }>("/Restaurant/orders/discounts", "POST", { ...input, farmId })
}
export async function updateDiscount(id: number, input: DiscountInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/orders/discounts/${id}`, "PUT", { ...input, farmId })
}
export async function deleteDiscount(id: number): Promise<void> {
  await jdelete(`/Restaurant/orders/discounts/${id}`)
}

// ----- Order Discounts -----

export interface OrderDiscount {
  orderDiscountId: number; farmId: string; orderId: number; discountId?: number | null
  discountName: string; discountType: string; value: number; appliedAmount: number; createdAt: string
}

export async function listOrderDiscounts(orderId: number): Promise<OrderDiscount[]> {
  return jget<OrderDiscount[]>(`/Restaurant/orders/${orderId}/discounts`)
}
export async function applyOrderDiscount(orderId: number, discountId: number | null, discountName: string, discountType: string, value: number, appliedAmount: number): Promise<{ orderDiscountId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/orders/${orderId}/discounts?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ discountId, discountName, discountType, value, appliedAmount }) })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function removeOrderDiscount(id: number): Promise<void> {
  await jdelete(`/Restaurant/orders/discounts/applied/${id}`)
}

// =============================================================================
// PHASE R3: KITCHEN DISPLAY SYSTEM (KDS)
// =============================================================================

// ----- KDS Stations -----

export interface KdsStation {
  kdsStationId: number; farmId: string; name: string; displayColor: string
  sortOrder: number; isExpo: boolean; isActive: boolean
  createdAt: string; updatedAt?: string | null; itemCount: number
}
export interface KdsStationInput {
  name: string; displayColor?: string; sortOrder?: number
  isExpo?: boolean; isActive?: boolean
}

export async function listKdsStations(): Promise<KdsStation[]> {
  return jget<KdsStation[]>("/Restaurant/kds/stations")
}
export async function createKdsStation(input: KdsStationInput): Promise<{ kdsStationId: number }> {
  const farmId = activeFarmId()
  return jsend<{ kdsStationId: number }>("/Restaurant/kds/stations", "POST", { ...input, farmId })
}
export async function updateKdsStation(id: number, input: KdsStationInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/kds/stations/${id}`, "PUT", { ...input, farmId })
}
export async function deleteKdsStation(id: number): Promise<void> {
  await jdelete(`/Restaurant/kds/stations/${id}`)
}

// ----- Station-Item Mappings -----

export interface KdsStationItem {
  kdsStationItemId: number; farmId: string; kdsStationId: number
  menuItemId: number; menuItemName?: string | null; categoryName?: string | null
}

export async function listKdsStationItems(stationId: number): Promise<KdsStationItem[]> {
  return jget<KdsStationItem[]>(`/Restaurant/kds/stations/${stationId}/items`)
}
export async function assignItemToKdsStation(stationId: number, menuItemId: number): Promise<{ kdsStationItemId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/kds/stations/${stationId}/items?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ menuItemId }) })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function unassignItemFromKdsStation(id: number): Promise<void> {
  await jdelete(`/Restaurant/kds/stations/items/${id}`)
}

// ----- KDS Queue -----

export interface KdsQueueItem {
  orderItemId: number; orderId: number; orderNumber: string; orderType: string
  tableNumber?: string | null; itemName: string; quantity: number; notes?: string | null
  status: string; seatNumber?: number | null; kdsStation?: string | null
  sentToKitchenAt?: string | null; prepStartedAt?: string | null; readyAt?: string | null
  createdAt: string; modifiers?: string | null; elapsedMinutes: number
}

export async function getKdsQueue(stationId?: number, isExpo?: boolean): Promise<KdsQueueItem[]> {
  let extra = ""
  if (stationId) extra += `&stationId=${stationId}`
  if (isExpo) extra += `&isExpo=true`
  return jget<KdsQueueItem[]>(`/Restaurant/kds/queue?_=1${extra}`)
}

export async function kdsBumpItem(orderItemId: number): Promise<{ newStatus: string }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/kds/bump/${orderItemId}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

export async function kdsRecallItem(orderItemId: number): Promise<{ newStatus: string }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/kds/recall/${orderItemId}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

export async function kdsBumpOrder(orderId: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/kds/bump-order/${orderId}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- KDS Stats -----

export interface KdsStats {
  pendingCount: number; preparingCount: number; readyCount: number
  avgPrepMinutes?: number | null; longestWaitMinutes?: number | null
}

export async function getKdsStats(): Promise<KdsStats> {
  return jget<KdsStats>("/Restaurant/kds/stats")
}

// =============================================================================
// PHASE R4: RESERVATIONS & WAITLIST
// =============================================================================

// ----- Reservation Settings -----

export interface ReservationSettings {
  reservationSettingId: number; farmId: string; defaultDurationMins: number
  maxPartySizeOnline: number; minAdvanceHours: number; maxAdvanceDays: number
  slotIntervalMins: number; overbookingBuffer: number; autoConfirm: boolean
  noShowThresholdMins: number; cancellationPolicy?: string | null
  confirmationMessage?: string | null; createdAt: string; updatedAt?: string | null
}

export async function getReservationSettings(): Promise<ReservationSettings> {
  return jget<ReservationSettings>("/Restaurant/reservations/settings")
}
export async function upsertReservationSettings(input: Partial<ReservationSettings>): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>("/Restaurant/reservations/settings", "POST", { ...input, farmId })
}

// ----- Reservations -----

export interface Reservation {
  reservationId: number; farmId: string; reservationNumber: string; status: string
  reservationDate: string; reservationTime: string; endTime?: string | null
  partySize: number; guestName: string; guestPhone?: string | null; guestEmail?: string | null
  tableId?: number | null; tableNumber?: string | null; specialRequests?: string | null
  occasion?: string | null; source: string; isVip: boolean; notes?: string | null
  cancelReason?: string | null; seatedAt?: string | null; completedAt?: string | null
  noShowMarkedAt?: string | null; reminderSent: boolean; createdBy?: string | null
  createdAt: string; updatedAt?: string | null
}
export interface ReservationInput {
  reservationDate: string; reservationTime: string; endTime?: string | null
  partySize: number; guestName: string; guestPhone?: string | null; guestEmail?: string | null
  tableId?: number | null; tableNumber?: string | null; specialRequests?: string | null
  occasion?: string | null; source?: string; isVip?: boolean; notes?: string | null
}

export async function listReservations(date?: string, status?: string, fromDate?: string, toDate?: string): Promise<Reservation[]> {
  let extra = ""
  if (date) extra += `&date=${encodeURIComponent(date)}`
  if (status) extra += `&status=${encodeURIComponent(status)}`
  if (fromDate) extra += `&fromDate=${encodeURIComponent(fromDate)}`
  if (toDate) extra += `&toDate=${encodeURIComponent(toDate)}`
  return jget<Reservation[]>(`/Restaurant/reservations?_=1${extra}`)
}
export async function getReservation(id: number): Promise<Reservation> {
  return jget<Reservation>(`/Restaurant/reservations/${id}`)
}
export async function createReservation(input: ReservationInput): Promise<{ reservationId: number; reservationNumber: string }> {
  const farmId = activeFarmId()
  return jsend<{ reservationId: number; reservationNumber: string }>("/Restaurant/reservations", "POST", { ...input, farmId })
}
export async function updateReservation(id: number, input: ReservationInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/reservations/${id}`, "PUT", { ...input, farmId })
}
export async function updateReservationStatus(id: number, status: string, reason?: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/reservations/${id}/status?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status, reason }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function deleteReservation(id: number): Promise<void> {
  await jdelete(`/Restaurant/reservations/${id}`)
}
export async function autoAssignTable(partySize: number, date: string, time: string): Promise<{ tableId: number; tableNumber: string; capacity: number }[]> {
  return jget<{ tableId: number; tableNumber: string; capacity: number }[]>(
    `/Restaurant/reservations/auto-assign-table?partySize=${partySize}&date=${encodeURIComponent(date)}&time=${encodeURIComponent(time)}`
  )
}

export interface ReservationStats {
  totalCount: number; confirmedCount: number; seatedCount: number
  completedCount: number; cancelledCount: number; noShowCount: number
  totalCovers: number; noShowRate: number
}
export async function getReservationStats(date: string): Promise<ReservationStats> {
  return jget<ReservationStats>(`/Restaurant/reservations/stats?date=${encodeURIComponent(date)}`)
}

// ----- Waitlist -----

export interface WaitlistEntry {
  waitlistId: number; farmId: string; guestName: string; guestPhone?: string | null
  partySize: number; estimatedWaitMins: number; status: string; notes?: string | null
  quotedWaitMins?: number | null; notifiedAt?: string | null; seatedAt?: string | null
  tableId?: number | null; tableNumber?: string | null
  createdAt: string; updatedAt?: string | null; actualWaitMins?: number | null
}
export interface WaitlistInput {
  guestName: string; guestPhone?: string | null; partySize: number
  estimatedWaitMins?: number; quotedWaitMins?: number | null; notes?: string | null
}

export async function listWaitlist(status?: string): Promise<WaitlistEntry[]> {
  const extra = status ? `&status=${encodeURIComponent(status)}` : ""
  return jget<WaitlistEntry[]>(`/Restaurant/reservations/waitlist?_=1${extra}`)
}
export async function addToWaitlist(input: WaitlistInput): Promise<{ waitlistId: number }> {
  const farmId = activeFarmId()
  return jsend<{ waitlistId: number }>("/Restaurant/reservations/waitlist", "POST", { ...input, farmId })
}
export async function updateWaitlistStatus(id: number, status: string, tableId?: number, tableNumber?: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/reservations/waitlist/${id}/status?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status, tableId, tableNumber }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function deleteFromWaitlist(id: number): Promise<void> {
  await jdelete(`/Restaurant/reservations/waitlist/${id}`)
}

export interface WaitlistStats {
  waitingCount: number; notifiedCount: number; avgWaitMins?: number | null
  longestWaitMins?: number | null; totalCovers: number
}
export async function getWaitlistStats(): Promise<WaitlistStats> {
  return jget<WaitlistStats>("/Restaurant/reservations/waitlist/stats")
}

// =============================================================================
// PHASE R5: ONLINE ORDERING
// =============================================================================

// ----- Online Ordering Settings -----

export interface OnlineOrderingSettings {
  onlineOrderingSettingId: number; farmId: string; isEnabled: boolean
  allowDineInQr: boolean; allowTakeaway: boolean; allowDelivery: boolean
  minOrderAmount: number; maxOrdersPerSlot: number; slotDurationMins: number
  estimatedPrepMinsDine: number; estimatedPrepMinsTake: number; estimatedPrepminsDeliv: number
  deliveryFeeType: string; deliveryFeeAmount: number; freeDeliveryAbove?: number | null
  maxDeliveryDistanceKm: number; acceptingOrders: boolean; pausedReason?: string | null
  welcomeMessage?: string | null; termsAndConditions?: string | null
  createdAt: string; updatedAt?: string | null
}

export async function getOnlineSettings(): Promise<OnlineOrderingSettings> {
  return jget<OnlineOrderingSettings>("/Restaurant/online/settings")
}
export async function upsertOnlineSettings(input: Partial<OnlineOrderingSettings>): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>("/Restaurant/online/settings", "POST", { ...input, farmId })
}
export async function toggleAcceptingOrders(accepting: boolean, reason?: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/online/settings/toggle?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ accepting, reason }) })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- QR Codes -----

export interface QrCode {
  qrCodeId: number; farmId: string; tableId?: number | null; tableNumber: string
  qrToken: string; isActive: boolean; scanCount: number; lastScannedAt?: string | null; createdAt: string
}

export async function listQrCodes(): Promise<QrCode[]> {
  return jget<QrCode[]>("/Restaurant/online/qr-codes")
}
export async function generateQrCode(tableId: number, tableNumber: string): Promise<{ qrCodeId: number; qrToken: string }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/online/qr-codes?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ tableId, tableNumber }) })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function deleteQrCode(id: number): Promise<void> {
  await jdelete(`/Restaurant/online/qr-codes/${id}`)
}

// ----- Promo Codes -----

export interface PromoCode {
  promoCodeId: number; farmId: string; code: string; description?: string | null
  discountType: string; discountValue: number; minOrderAmount: number
  maxDiscountAmount?: number | null; maxUses: number; currentUses: number
  validFrom?: string | null; validUntil?: string | null; isActive: boolean
  channelRestriction?: string | null; createdAt: string; updatedAt?: string | null
}
export interface PromoCodeInput {
  code: string; description?: string | null; discountType?: string; discountValue: number
  minOrderAmount?: number; maxDiscountAmount?: number | null; maxUses?: number
  validFrom?: string | null; validUntil?: string | null; isActive?: boolean
  channelRestriction?: string | null
}

export async function listPromoCodes(): Promise<PromoCode[]> {
  return jget<PromoCode[]>("/Restaurant/online/promo-codes")
}
export async function createPromoCode(input: PromoCodeInput): Promise<{ promoCodeId: number }> {
  const farmId = activeFarmId()
  return jsend<{ promoCodeId: number }>("/Restaurant/online/promo-codes", "POST", { ...input, farmId })
}
export async function updatePromoCode(id: number, input: PromoCodeInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/online/promo-codes/${id}`, "PUT", { ...input, farmId })
}
export async function deletePromoCode(id: number): Promise<void> {
  await jdelete(`/Restaurant/online/promo-codes/${id}`)
}

// ----- Public API (no auth) -----

export interface PublicMenuItem {
  menuItemId: number; name: string; description?: string | null; price: number
  imageUrl?: string | null; prepTime: number; calories?: number | null; allergens?: string | null
  spicyLevel: number; isVegetarian: boolean; isVegan: boolean; isGlutenFree: boolean
  isHalal: boolean; isKosher: boolean; categoryId: number; categoryName: string
}
export interface PublicCategory {
  menuCategoryId: number; name: string; description?: string | null
  imageUrl?: string | null; sortOrder: number
}
export interface OrderTracking {
  orderId: number; orderNumber: string; orderType: string; status: string
  tableNumber?: string | null; totalAmount: number; paymentStatus: string
  estimatedReadyTime?: string | null; createdAt: string; updatedAt?: string | null
}
export interface PromoValidation {
  valid: boolean; promoCodeId: number; discountType: string; discountValue: number
  maxDiscountAmount?: number | null; calculatedDiscount: number; message: string
}

export async function getPublicMenu(farmId: string): Promise<PublicMenuItem[]> {
  const url = farmApiUrl(`/Restaurant/public/${farmId}/menu`)
  const res = await fetch(url)
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function getPublicCategories(farmId: string): Promise<PublicCategory[]> {
  const url = farmApiUrl(`/Restaurant/public/${farmId}/categories`)
  const res = await fetch(url)
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function getPublicSettings(farmId: string): Promise<any> {
  const url = farmApiUrl(`/Restaurant/public/${farmId}/settings`)
  const res = await fetch(url)
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function scanQrCode(token: string): Promise<{ farmId: string; tableId: number; tableNumber: string }> {
  const url = farmApiUrl(`/Restaurant/public/qr/${token}`)
  const res = await fetch(url)
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function validatePromoCode(farmId: string, code: string, orderAmount: number, channel?: string): Promise<PromoValidation> {
  const url = farmApiUrl(`/Restaurant/public/${farmId}/validate-promo`)
  const res = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code, orderAmount, channel }) })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function placeOnlineOrder(farmId: string, input: any): Promise<{ orderId: number; orderNumber: string; trackingToken: string }> {
  const url = farmApiUrl(`/Restaurant/public/${farmId}/place-order`)
  const res = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(input) })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function trackOrder(token: string): Promise<OrderTracking> {
  const url = farmApiUrl(`/Restaurant/public/track/${token}`)
  const res = await fetch(url)
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

// =============================================================================
// PHASE R6: DELIVERY MANAGEMENT
// =============================================================================

export interface Driver {
  driverId: number; farmId: string; firstName: string; lastName: string; phone: string; email?: string | null
  vehicleType: string; vehiclePlate?: string | null; licenseNumber?: string | null; status: string
  currentLatitude?: number | null; currentLongitude?: number | null; lastLocationUpdate?: string | null
  isActive: boolean; notes?: string | null; createdAt: string; updatedAt?: string | null
  activeDeliveries: number; totalDeliveries: number; avgRating?: number | null
}
export interface DriverInput {
  firstName: string; lastName: string; phone: string; email?: string | null
  vehicleType?: string; vehiclePlate?: string | null; licenseNumber?: string | null
  isActive?: boolean; notes?: string | null
}

export async function listDrivers(status?: string): Promise<Driver[]> {
  const extra = status ? `&status=${encodeURIComponent(status)}` : ""
  return jget<Driver[]>(`/Restaurant/delivery/drivers?_=1${extra}`)
}
export async function createDriver(input: DriverInput): Promise<{ driverId: number }> {
  const farmId = activeFarmId()
  return jsend<{ driverId: number }>("/Restaurant/delivery/drivers", "POST", { ...input, farmId })
}
export async function updateDriver(id: number, input: DriverInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/delivery/drivers/${id}`, "PUT", { ...input, farmId })
}
export async function deleteDriver(id: number): Promise<void> {
  await jdelete(`/Restaurant/delivery/drivers/${id}`)
}
export async function updateDriverStatus(id: number, status: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/delivery/drivers/${id}/status?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status }) })
  if (!res.ok) throw new Error(await readApiError(res))
}

export interface DeliveryZone {
  deliveryZoneId: number; farmId: string; name: string; minDistanceKm: number
  maxDistanceKm: number; deliveryFee: number; estimatedMins: number
  isActive: boolean; sortOrder: number; createdAt: string; updatedAt?: string | null
}
export interface DeliveryZoneInput {
  name: string; minDistanceKm?: number; maxDistanceKm?: number; deliveryFee?: number
  estimatedMins?: number; isActive?: boolean; sortOrder?: number
}

export async function listDeliveryZones(): Promise<DeliveryZone[]> { return jget<DeliveryZone[]>("/Restaurant/delivery/zones") }
export async function createDeliveryZone(input: DeliveryZoneInput): Promise<{ deliveryZoneId: number }> {
  const farmId = activeFarmId(); return jsend<{ deliveryZoneId: number }>("/Restaurant/delivery/zones", "POST", { ...input, farmId })
}
export async function updateDeliveryZone(id: number, input: DeliveryZoneInput): Promise<void> {
  const farmId = activeFarmId(); await jsend<void>(`/Restaurant/delivery/zones/${id}`, "PUT", { ...input, farmId })
}
export async function deleteDeliveryZone(id: number): Promise<void> { await jdelete(`/Restaurant/delivery/zones/${id}`) }

export interface DeliveryAssignment {
  deliveryAssignmentId: number; farmId: string; orderId: number; orderNumber?: string | null
  driverId?: number | null; driverName?: string | null; driverPhone?: string | null; status: string
  assignedAt?: string | null; pickedUpAt?: string | null; deliveredAt?: string | null
  deliveryAddress?: string | null; deliveryNotes?: string | null; deliveryZoneId?: number | null
  deliveryFee: number; estimatedMins?: number | null; actualMins?: number | null
  distanceKm?: number | null; proofType?: string | null; proofData?: string | null
  rating?: number | null; failReason?: string | null; createdAt: string; updatedAt?: string | null
}

export async function listDeliveryAssignments(status?: string, driverId?: number): Promise<DeliveryAssignment[]> {
  let extra = ""; if (status) extra += `&status=${encodeURIComponent(status)}`; if (driverId) extra += `&driverId=${driverId}`
  return jget<DeliveryAssignment[]>(`/Restaurant/delivery/assignments?_=1${extra}`)
}
export async function createDeliveryAssignment(orderId: number, orderNumber: string, driverId: number,
  deliveryAddress?: string, deliveryNotes?: string, zoneId?: number, deliveryFee?: number, estimatedMins?: number
): Promise<{ deliveryAssignmentId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/delivery/assignments?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(),
    body: JSON.stringify({ orderId, orderNumber, driverId, deliveryAddress, deliveryNotes, deliveryZoneId: zoneId, deliveryFee: deliveryFee || 0, estimatedMins }) })
  if (!res.ok) throw new Error(await readApiError(res)); return res.json()
}
export async function updateAssignmentStatus(id: number, status: string, failReason?: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/delivery/assignments/${id}/status?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status, failReason }) })
  if (!res.ok) throw new Error(await readApiError(res))
}

export interface ThirdPartyPlatform {
  platformId: number; farmId: string; name: string; apiKey?: string | null; apiSecret?: string | null
  storeId?: string | null; commissionRate: number; autoAccept: boolean; isEnabled: boolean; isActive: boolean
  createdAt: string; updatedAt?: string | null; orderCount: number; totalRevenue: number
}
export interface ThirdPartyPlatformInput {
  name: string; apiKey?: string | null; apiSecret?: string | null; storeId?: string | null
  commissionRate?: number; autoAccept?: boolean; isEnabled?: boolean
}

export async function listPlatforms(): Promise<ThirdPartyPlatform[]> { return jget<ThirdPartyPlatform[]>("/Restaurant/delivery/platforms") }
export async function createPlatform(input: ThirdPartyPlatformInput): Promise<{ platformId: number }> {
  const farmId = activeFarmId(); return jsend<{ platformId: number }>("/Restaurant/delivery/platforms", "POST", { ...input, farmId })
}
export async function updatePlatform(id: number, input: ThirdPartyPlatformInput): Promise<void> {
  const farmId = activeFarmId(); await jsend<void>(`/Restaurant/delivery/platforms/${id}`, "PUT", { ...input, farmId })
}
export async function deletePlatform(id: number): Promise<void> { await jdelete(`/Restaurant/delivery/platforms/${id}`) }

export interface DeliveryStats {
  totalAssignments: number; pendingCount: number; activeCount: number
  deliveredCount: number; failedCount: number; avgDeliveryMins?: number | null
  totalFees: number; availableDrivers: number; onDeliveryDrivers: number
}
export async function getDeliveryStats(date?: string): Promise<DeliveryStats> {
  const extra = date ? `&date=${encodeURIComponent(date)}` : ""
  return jget<DeliveryStats>(`/Restaurant/delivery/stats?_=1${extra}`)
}

// =============================================================================
// PHASE R7: INVENTORY & RECIPES
// =============================================================================

export interface Ingredient {
  ingredientId: number; farmId: string; name: string; category?: string | null; unit: string
  costPerUnit: number; currentStock: number; parLevel: number; reorderPoint: number
  supplierName?: string | null; expiryDays?: number | null; storageArea?: string | null
  isActive: boolean; notes?: string | null; createdAt: string; updatedAt?: string | null; isLow: boolean
}
export interface IngredientInput {
  name: string; category?: string | null; unit?: string; costPerUnit?: number; currentStock?: number
  parLevel?: number; reorderPoint?: number; supplierName?: string | null; expiryDays?: number | null
  storageArea?: string | null; isActive?: boolean; notes?: string | null
}

export async function listIngredients(category?: string): Promise<Ingredient[]> {
  const extra = category ? `&category=${encodeURIComponent(category)}` : ""
  return jget<Ingredient[]>(`/Restaurant/inventory/ingredients?_=1${extra}`)
}
export async function createIngredient(input: IngredientInput): Promise<{ ingredientId: number }> {
  const farmId = activeFarmId(); return jsend<{ ingredientId: number }>("/Restaurant/inventory/ingredients", "POST", { ...input, farmId })
}
export async function updateIngredient(id: number, input: IngredientInput): Promise<void> {
  const farmId = activeFarmId(); await jsend<void>(`/Restaurant/inventory/ingredients/${id}`, "PUT", { ...input, farmId })
}
export async function deleteIngredient(id: number): Promise<void> { await jdelete(`/Restaurant/inventory/ingredients/${id}`) }
export async function adjustIngredientStock(id: number, quantity: number, movementType: string, reason: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/inventory/ingredients/${id}/adjust?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ quantity, movementType, reason }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function getLowStock(): Promise<Ingredient[]> { return jget<Ingredient[]>("/Restaurant/inventory/low-stock") }

export interface Recipe {
  recipeId: number; farmId: string; menuItemId: number; ingredientId: number
  ingredientName?: string | null; quantity: number; unit: string; wastePercent: number
  notes?: string | null; costPerUnit: number; lineCost: number
}
export async function listRecipe(menuItemId: number): Promise<Recipe[]> { return jget<Recipe[]>(`/Restaurant/inventory/recipes/${menuItemId}`) }
export async function upsertRecipe(menuItemId: number, ingredientId: number, quantity: number, unit: string, wastePercent: number, notes?: string): Promise<{ recipeId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/inventory/recipes?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ menuItemId, ingredientId, quantity, unit, wastePercent, notes }) })
  if (!res.ok) throw new Error(await readApiError(res)); return res.json()
}
export async function deleteRecipe(id: number): Promise<void> { await jdelete(`/Restaurant/inventory/recipes/${id}`) }

export interface FoodCost { totalCost: number; sellingPrice: number; foodCostPercent: number }
export async function getFoodCost(menuItemId: number): Promise<FoodCost> { return jget<FoodCost>(`/Restaurant/inventory/food-cost/${menuItemId}`) }
export async function deductOrderStock(orderId: number): Promise<{ itemsDeducted: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/inventory/deduct-order/${orderId}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res)); return res.json()
}

export interface WasteLog {
  wasteLogId: number; farmId: string; ingredientId?: number | null; menuItemId?: number | null
  ingredientName: string; quantity: number; unit: string; costAmount: number
  reason: string; notes?: string | null; loggedBy?: string | null; createdAt: string
}
export interface WasteInput {
  ingredientId?: number | null; menuItemId?: number | null; ingredientName: string
  quantity: number; unit: string; costAmount?: number; reason: string; notes?: string | null
}
export async function listWaste(fromDate?: string, toDate?: string): Promise<WasteLog[]> {
  let extra = ""; if (fromDate) extra += `&fromDate=${encodeURIComponent(fromDate)}`; if (toDate) extra += `&toDate=${encodeURIComponent(toDate)}`
  return jget<WasteLog[]>(`/Restaurant/inventory/waste?_=1${extra}`)
}
export async function logWaste(input: WasteInput): Promise<{ wasteLogId: number }> {
  const farmId = activeFarmId(); return jsend<{ wasteLogId: number }>("/Restaurant/inventory/waste", "POST", { ...input, farmId })
}
export interface WasteSummary { reason: string; totalQuantity: number; totalCost: number; count: number }
export async function getWasteSummary(fromDate?: string, toDate?: string): Promise<WasteSummary[]> {
  let extra = ""; if (fromDate) extra += `&fromDate=${encodeURIComponent(fromDate)}`; if (toDate) extra += `&toDate=${encodeURIComponent(toDate)}`
  return jget<WasteSummary[]>(`/Restaurant/inventory/waste/summary?_=1${extra}`)
}

export interface InventoryValue {
  ingredientId: number; name: string; category?: string | null; unit?: string | null
  currentStock: number; costPerUnit: number; totalValue: number; isLow: boolean
}
export async function getInventoryValue(): Promise<InventoryValue[]> { return jget<InventoryValue[]>("/Restaurant/inventory/value") }

// =============================================================================
// PHASE R8: REPORTING & BI ANALYTICS
// =============================================================================

export interface DailySalesReport {
  totalOrders: number; completedOrders: number; cancelledOrders: number
  totalRevenue: number; totalDiscount: number; totalTax: number
  totalServiceCharge: number; netRevenue: number; avgTicket: number; totalCovers: number
  dineInCount: number; dineInRevenue: number; takeawayCount: number; takeawayRevenue: number
  deliveryCount: number; deliveryRevenue: number
  cashAmount: number; cardAmount: number; mobileAmount: number; otherAmount: number
}
export async function getDailySalesReport(date: string): Promise<DailySalesReport> {
  return jget<DailySalesReport>(`/Restaurant/reports/daily-sales?date=${encodeURIComponent(date)}`)
}

export interface SalesByItemRow { menuItemId: number; itemName: string; quantitySold: number; totalRevenue: number; avgPrice: number; orderCount: number }
export async function getSalesByItem(from: string, to: string): Promise<SalesByItemRow[]> {
  return jget<SalesByItemRow[]>(`/Restaurant/reports/sales-by-item?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`)
}

export interface SalesByCategoryRow { categoryName: string; itemCount: number; quantitySold: number; totalRevenue: number }
export async function getSalesByCategory(from: string, to: string): Promise<SalesByCategoryRow[]> {
  return jget<SalesByCategoryRow[]>(`/Restaurant/reports/sales-by-category?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`)
}

export interface SalesByHourRow { hourOfDay: number; orderCount: number; totalRevenue: number; avgTicket: number }
export async function getSalesByHour(date: string): Promise<SalesByHourRow[]> {
  return jget<SalesByHourRow[]>(`/Restaurant/reports/sales-by-hour?date=${encodeURIComponent(date)}`)
}

export interface RevenueTrendRow { reportDate: string; orderCount: number; totalRevenue: number; avgTicket: number }
export async function getRevenueTrend(from: string, to: string): Promise<RevenueTrendRow[]> {
  return jget<RevenueTrendRow[]>(`/Restaurant/reports/revenue-trend?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`)
}

export interface FoodCostRow { menuItemId: number; itemName: string; sellingPrice: number; recipeCost: number; foodCostPercent: number; margin: number; categoryName: string }
export async function getFoodCostReport(): Promise<FoodCostRow[]> { return jget<FoodCostRow[]>("/Restaurant/reports/food-cost") }

export interface ServerPerformanceRow { servedBy: string; orderCount: number; totalRevenue: number; avgTicket: number; totalCovers: number }
export async function getServerPerformance(from: string, to: string): Promise<ServerPerformanceRow[]> {
  return jget<ServerPerformanceRow[]>(`/Restaurant/reports/server-performance?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`)
}

// =============================================================================
// PHASE R9: CRM
// =============================================================================

export interface Customer {
  customerId: number; farmId: string; name: string; phone?: string | null; email?: string | null
  dateOfBirth?: string | null; anniversary?: string | null; dietaryPreferences?: string | null
  allergies?: string | null; favouriteItems?: string | null; segment: string
  totalVisits: number; totalSpent: number; avgTicket: number; lastVisit?: string | null
  notes?: string | null; isActive: boolean; createdAt: string; updatedAt?: string | null
}
export interface CustomerInput {
  name: string; phone?: string | null; email?: string | null; dateOfBirth?: string | null
  anniversary?: string | null; dietaryPreferences?: string | null; allergies?: string | null
  favouriteItems?: string | null; segment?: string; notes?: string | null; isActive?: boolean
}
export async function listCustomers(segment?: string, search?: string): Promise<Customer[]> {
  let extra = ""; if (segment) extra += `&segment=${encodeURIComponent(segment)}`; if (search) extra += `&search=${encodeURIComponent(search)}`
  return jget<Customer[]>(`/Restaurant/crm/customers?_=1${extra}`)
}
export async function createCustomer(input: CustomerInput): Promise<{ customerId: number }> { const farmId = activeFarmId(); return jsend<{ customerId: number }>("/Restaurant/crm/customers", "POST", { ...input, farmId }) }
export async function updateCustomer(id: number, input: CustomerInput): Promise<void> { const farmId = activeFarmId(); await jsend<void>(`/Restaurant/crm/customers/${id}`, "PUT", { ...input, farmId }) }
export async function deleteCustomer(id: number): Promise<void> { await jdelete(`/Restaurant/crm/customers/${id}`) }

export interface CustomerStats { totalCustomers: number; newCount: number; regularCount: number; vipCount: number; lapsedCount: number; totalLifetimeValue: number }
export async function getCustomerStats(): Promise<CustomerStats> { return jget<CustomerStats>("/Restaurant/crm/customers/stats") }

export interface Feedback {
  feedbackId: number; farmId: string; customerId?: number | null; customerName?: string | null
  orderId?: number | null; rating: number; foodRating?: number | null; serviceRating?: number | null
  ambienceRating?: number | null; comment?: string | null; source: string; status: string
  response?: string | null; respondedBy?: string | null; createdAt: string; updatedAt?: string | null
}
export interface FeedbackInput {
  customerId?: number | null; customerName?: string | null; orderId?: number | null
  rating: number; foodRating?: number | null; serviceRating?: number | null
  ambienceRating?: number | null; comment?: string | null; source?: string
}
export async function listFeedback(status?: string): Promise<Feedback[]> {
  const extra = status ? `&status=${encodeURIComponent(status)}` : ""
  return jget<Feedback[]>(`/Restaurant/crm/feedback?_=1${extra}`)
}
export async function createFeedback(input: FeedbackInput): Promise<{ feedbackId: number }> { const farmId = activeFarmId(); return jsend<{ feedbackId: number }>("/Restaurant/crm/feedback", "POST", { ...input, farmId }) }
export async function respondToFeedback(id: number, response: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/crm/feedback/${id}/respond?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ response }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export interface FeedbackStats { totalFeedback: number; avgRating?: number | null; avgFood?: number | null; avgService?: number | null; avgAmbience?: number | null; newCount: number }
export async function getFeedbackStats(): Promise<FeedbackStats> { return jget<FeedbackStats>("/Restaurant/crm/feedback/stats") }

export interface Campaign {
  campaignId: number; farmId: string; name: string; campaignType: string; targetSegment?: string | null
  subject?: string | null; message?: string | null; channel: string; status: string
  scheduledAt?: string | null; sentAt?: string | null; recipientCount: number; openCount: number; createdAt: string
}
export interface CampaignInput { name: string; campaignType: string; targetSegment?: string | null; subject?: string | null; message?: string | null; channel?: string }
export async function listCampaigns(): Promise<Campaign[]> { return jget<Campaign[]>("/Restaurant/crm/campaigns") }
export async function createCampaign(input: CampaignInput): Promise<{ campaignId: number }> { const farmId = activeFarmId(); return jsend<{ campaignId: number }>("/Restaurant/crm/campaigns", "POST", { ...input, farmId }) }
export async function deleteCampaign(id: number): Promise<void> { await jdelete(`/Restaurant/crm/campaigns/${id}`) }

// =============================================================================
// R10: LOYALTY & REWARDS
// =============================================================================

export interface LoyaltySettings {
  loyaltySettingId: number; farmId: string; isEnabled: boolean
  pointsPerCurrencyUnit: number; pointsRedemptionRate: number; minimumRedeemPoints: number
  pointsExpiryDays: number; tiersEnabled: boolean
  bronzeThreshold: number; silverThreshold: number; goldThreshold: number; platinumThreshold: number
  bronzeMultiplier: number; silverMultiplier: number; goldMultiplier: number; platinumMultiplier: number
  referralBonus: number; createdAt: string; updatedAt?: string | null
}
export interface LoyaltyAccount {
  loyaltyAccountId: number; farmId: string; customerId?: number | null
  customerName: string; customerPhone?: string | null
  totalPoints: number; lifetimePoints: number; currentTier: string
  referralCode?: string | null; referredBy?: number | null
  createdAt: string; updatedAt?: string | null
}
export interface PointTransaction {
  pointTransactionId: number; transactionType: string; points: number
  description?: string | null; orderId?: number | null; createdAt: string
}
export interface LoyaltyStats {
  totalMembers: number; totalPointsOutstanding: number
  bronzeCount: number; silverCount: number; goldCount: number; platinumCount: number
}

export async function getLoyaltySettings(): Promise<LoyaltySettings> { return jget<LoyaltySettings>("/Restaurant/loyalty/settings") }
export async function upsertLoyaltySettings(input: Partial<LoyaltySettings>): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>("/Restaurant/loyalty/settings", "POST", { ...input, farmId })
}
export async function listLoyaltyAccounts(tier?: string): Promise<LoyaltyAccount[]> {
  const extra = tier ? `&tier=${encodeURIComponent(tier)}` : ""
  return jget<LoyaltyAccount[]>(`/Restaurant/loyalty/accounts?_=1${extra}`)
}
export async function createLoyaltyAccount(customerName: string, customerPhone?: string, customerId?: number): Promise<{ loyaltyAccountId: number }> {
  const farmId = activeFarmId()
  return jsend<{ loyaltyAccountId: number }>(`/Restaurant/loyalty/accounts?farmId=${encodeURIComponent(farmId)}`, "POST", { customerName, customerPhone, customerId })
}
export async function earnPoints(accountId: number, points: number, description: string, orderId?: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/loyalty/accounts/${accountId}/earn?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ points, description, orderId }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function redeemPoints(accountId: number, points: number, description: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/loyalty/accounts/${accountId}/redeem?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ points, description }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function getLoyaltyTransactions(accountId: number): Promise<PointTransaction[]> {
  return jget<PointTransaction[]>(`/Restaurant/loyalty/accounts/${accountId}/transactions`)
}
export async function getLoyaltyStats(): Promise<LoyaltyStats> { return jget<LoyaltyStats>("/Restaurant/loyalty/stats") }

// =============================================================================
// R11: NOTIFICATIONS
// =============================================================================

export interface RestaurantNotification {
  notificationId: number; farmId: string; type: string; title: string; message: string
  severity: string; isRead: boolean; targetUserId?: string | null; targetRole?: string | null
  relatedId?: number | null; relatedType?: string | null; createdAt: string
}
export interface NotificationSettings {
  notificationSettingId: number; farmId: string
  emailEnabled: boolean; smsEnabled: boolean; pushEnabled: boolean
  lowStockAlerts: boolean; newOrderAlerts: boolean; reservationAlerts: boolean
  kpiAlerts: boolean; shiftReminders: boolean
  createdAt: string; updatedAt?: string | null
}

export async function listNotifications(unreadOnly = false): Promise<RestaurantNotification[]> {
  const extra = unreadOnly ? "&unreadOnly=true" : ""
  return jget<RestaurantNotification[]>(`/Restaurant/notifications?_=1${extra}`)
}
export async function markNotificationRead(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/notifications/${id}/read?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function markAllNotificationsRead(): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/notifications/read-all?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function getNotificationSettings(): Promise<NotificationSettings> { return jget<NotificationSettings>("/Restaurant/notifications/settings") }
export async function upsertNotificationSettings(input: Partial<NotificationSettings>): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>("/Restaurant/notifications/settings", "POST", { ...input, farmId })
}

// =============================================================================
// R12: CATERING & EVENTS
// =============================================================================

export interface CateringEvent {
  eventId: number; farmId: string; eventNumber?: string | null; name: string
  eventType: string; eventDate: string; startTime?: string | null; endTime?: string | null
  guestCount: number; venue?: string | null; status: string
  contactName?: string | null; contactPhone?: string | null; contactEmail?: string | null
  packageName?: string | null; pricePerHead: number; totalAmount: number
  depositAmount: number; depositPaid: boolean; balanceDue: number
  specialRequests?: string | null; dietaryNotes?: string | null; notes?: string | null
  createdBy?: string | null; createdAt: string; updatedAt?: string | null
}
export interface CateringEventInput {
  name: string; eventType: string; eventDate: string; startTime?: string | null; endTime?: string | null
  guestCount: number; venue?: string | null; contactName?: string | null
  contactPhone?: string | null; contactEmail?: string | null; packageName?: string | null
  pricePerHead: number; depositAmount?: number; specialRequests?: string | null
  dietaryNotes?: string | null; notes?: string | null
}

export async function listEvents(status?: string): Promise<CateringEvent[]> {
  const extra = status ? `&status=${encodeURIComponent(status)}` : ""
  return jget<CateringEvent[]>(`/Restaurant/events?_=1${extra}`)
}
export async function createEvent(input: CateringEventInput): Promise<{ eventId: number }> {
  const farmId = activeFarmId()
  return jsend<{ eventId: number }>("/Restaurant/events", "POST", { ...input, farmId })
}
export async function updateEventStatus(id: number, status: string): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/events/${id}/status?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status }) })
  if (!res.ok) throw new Error(await readApiError(res))
}
export async function deleteEvent(id: number): Promise<void> { await jdelete(`/Restaurant/events/${id}`) }

// =============================================================================
// R13: GIFT CARDS
// =============================================================================

export interface GiftCard {
  giftCardId: number; farmId: string; cardNumber: string; cardType: string
  initialBalance: number; currentBalance: number
  purchaserName?: string | null; purchaserPhone?: string | null
  recipientName?: string | null; status: string; expiryDate?: string | null; createdAt: string
}
export interface GiftCardTx {
  giftCardTxId: number; transactionType: string; amount: number; balanceAfter: number
  orderId?: number | null; notes?: string | null; processedBy?: string | null; createdAt: string
}
export interface GiftCardStats {
  totalCards: number; activeCards: number; totalIssued: number; totalOutstanding: number; totalRedeemed: number
}
export interface GiftCardRedeemResult { success: boolean; newBalance: number; message: string }
export interface GiftCardCreateInput {
  cardType?: string; amount: number; purchaserName?: string | null; purchaserPhone?: string | null
  recipientName?: string | null; recipientEmail?: string | null; message?: string | null; expiryDate?: string | null
}

export async function listGiftCards(status?: string): Promise<GiftCard[]> {
  const extra = status ? `&status=${encodeURIComponent(status)}` : ""
  return jget<GiftCard[]>(`/Restaurant/gift-cards?_=1${extra}`)
}
export async function createGiftCard(input: GiftCardCreateInput): Promise<{ giftCardId: number; cardNumber: string }> {
  const farmId = activeFarmId()
  return jsend<{ giftCardId: number; cardNumber: string }>(`/Restaurant/gift-cards?farmId=${encodeURIComponent(farmId)}`, "POST", input)
}
export async function redeemGiftCard(cardNumber: string, amount: number, orderId?: number): Promise<GiftCardRedeemResult> {
  const farmId = activeFarmId()
  return jsend<GiftCardRedeemResult>(`/Restaurant/gift-cards/redeem?farmId=${encodeURIComponent(farmId)}`, "POST", { cardNumber, amount, orderId })
}
export async function reloadGiftCard(cardNumber: string, amount: number): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Restaurant/gift-cards/reload?farmId=${encodeURIComponent(farmId)}`, "POST", { cardNumber, amount })
}
export async function checkGiftCardBalance(cardNumber: string): Promise<GiftCard | null> {
  try {
    const farmId = activeFarmId()
    const url = farmApiUrl(`/Restaurant/gift-cards/balance/${encodeURIComponent(cardNumber)}?farmId=${encodeURIComponent(farmId)}`)
    const res = await fetch(url, { headers: getAuthHeaders() })
    if (res.status === 404) return null
    if (!res.ok) throw new Error(await readApiError(res))
    return res.json()
  } catch { return null }
}
export async function getGiftCardTransactions(id: number): Promise<GiftCardTx[]> {
  return jget<GiftCardTx[]>(`/Restaurant/gift-cards/${id}/transactions`)
}
export async function getGiftCardStats(): Promise<GiftCardStats> { return jget<GiftCardStats>("/Restaurant/gift-cards/stats") }

// =============================================================================
// R14: EXPENSES & ACCOUNTING
// =============================================================================

export interface ExpenseCategory {
  expenseCategoryId: number; farmId: string; name: string; isActive: boolean; sortOrder: number
}
export interface RestaurantExpense {
  expenseId: number; farmId: string; expenseDate: string; categoryId?: number | null
  categoryName?: string | null; description: string; amount: number
  paymentMethod: string; supplierName?: string | null; receiptRef?: string | null
  status: string; createdBy?: string | null; createdAt: string
}
export interface RestaurantExpenseInput {
  expenseDate: string; categoryId?: number | null; description: string
  amount: number; paymentMethod?: string; supplierName?: string | null; receiptRef?: string | null
}
export interface ReceiptTemplate {
  receiptTemplateId: number; farmId: string; headerText?: string | null; footerText?: string | null
  showLogo: boolean; showTaxDetails: boolean; createdAt: string; updatedAt?: string | null
}

export async function listExpenseCategories(): Promise<ExpenseCategory[]> { return jget<ExpenseCategory[]>("/Restaurant/expenses/categories") }
export async function createExpenseCategory(name: string): Promise<{ expenseCategoryId: number }> {
  const farmId = activeFarmId()
  return jsend<{ expenseCategoryId: number }>(`/Restaurant/expenses/categories?farmId=${encodeURIComponent(farmId)}`, "POST", { name })
}
export async function deleteExpenseCategory(id: number): Promise<void> { await jdelete(`/Restaurant/expenses/categories/${id}`) }
export async function listExpenses(from?: string, to?: string): Promise<RestaurantExpense[]> {
  let extra = ""
  if (from) extra += `&from=${encodeURIComponent(from)}`
  if (to) extra += `&to=${encodeURIComponent(to)}`
  return jget<RestaurantExpense[]>(`/Restaurant/expenses?_=1${extra}`)
}
export async function createExpense(input: RestaurantExpenseInput): Promise<{ expenseId: number }> {
  const farmId = activeFarmId()
  return jsend<{ expenseId: number }>("/Restaurant/expenses", "POST", { ...input, farmId })
}
export async function deleteExpense(id: number): Promise<void> { await jdelete(`/Restaurant/expenses/${id}`) }
export async function getReceiptTemplate(): Promise<ReceiptTemplate> { return jget<ReceiptTemplate>("/Restaurant/expenses/receipt-template") }
export async function upsertReceiptTemplate(input: Partial<ReceiptTemplate>): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>("/Restaurant/expenses/receipt-template", "POST", { ...input, farmId })
}

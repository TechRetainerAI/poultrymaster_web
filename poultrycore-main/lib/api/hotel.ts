import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

// =============================================================================
// Hotel Management System — API Module (Phase 1: Foundation + Rooms)
// =============================================================================

// ----- Helpers -----

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

// =============================================================================
// TYPES
// =============================================================================

// ----- Profile -----

export interface HotelProfile {
  hotelProfileId: number
  farmId: string
  hotelName: string
  address?: string | null
  city?: string | null
  country?: string | null
  phone?: string | null
  email?: string | null
  starRating?: number | null
  checkInTime: string
  checkOutTime: string
  defaultCurrency: string
  taxRate: number
  serviceChargeRate: number
  timeZone?: string | null
  logoUrl?: string | null
  description?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface HotelProfileInput {
  hotelName: string
  address?: string | null
  city?: string | null
  country?: string | null
  phone?: string | null
  email?: string | null
  starRating?: number | null
  checkInTime?: string
  checkOutTime?: string
  defaultCurrency?: string
  taxRate?: number
  serviceChargeRate?: number
  timeZone?: string | null
  logoUrl?: string | null
  description?: string | null
}

// ----- Room Categories (system-wide lookup) -----

export interface HotelRoomCategory {
  hotelRoomCategoryId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

// ----- Supply Categories & Items (system-wide lookup) -----

export interface HotelSupplyCategory {
  hotelSupplyCategoryId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

export interface HotelSupplyItem {
  hotelSupplyItemId: number
  code: string
  description: string
  category?: string | null
  sortOrder: number
  isActive: boolean
}

// ----- Maintenance Assets (system-wide lookup) -----

export interface HotelMaintenanceAsset {
  hotelMaintenanceAssetId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

// ----- Table Locations (system-wide lookup) -----

export interface HotelTableLocation {
  hotelTableLocationId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

// ----- HK Task Types (system-wide lookup) -----

export interface HotelHKTaskType {
  hotelHKTaskTypeId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

// ----- Guest Request Types (system-wide lookup) -----

export interface HotelRequestType {
  hotelRequestTypeId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

// ----- Communication Subjects (system-wide lookup) -----

export interface HotelCommSubject {
  hotelCommSubjectId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

// ----- ID Types (system-wide lookup) -----

export interface HotelIdType {
  hotelIdTypeId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

// ----- Bed Types (system-wide lookup) -----

export interface HotelBedType {
  hotelBedTypeId: number
  code: string
  description: string
  sortOrder: number
  isActive: boolean
}

// ----- Room Types -----

export interface HotelRoomType {
  hotelRoomTypeId: number
  farmId: string
  name: string
  description?: string | null
  baseRate: number
  maxOccupancy: number
  bedType?: string | null
  imageUrl?: string | null
  isActive: boolean
  sortOrder: number
  createdAt: string
  updatedAt?: string | null
  hotelRoomCategoryId?: number | null
  categoryCode?: string | null
  categoryName?: string | null
  hotelBedTypeId?: number | null
  bedTypeCode?: string | null
  bedTypeName?: string | null
}

export interface HotelRoomTypeInput {
  name: string
  description?: string | null
  baseRate: number
  maxOccupancy?: number
  bedType?: string | null
  imageUrl?: string | null
  isActive?: boolean
  sortOrder?: number
  hotelRoomCategoryId?: number | null
  hotelBedTypeId?: number | null
}

// ----- Floors -----

export interface HotelFloor {
  hotelFloorId: number
  farmId: string
  floorNumber: number
  name: string
  isActive: boolean
  sortOrder: number
  createdAt: string
  updatedAt?: string | null
}

export interface HotelFloorInput {
  floorNumber: number
  name: string
  isActive?: boolean
  sortOrder?: number
}

// ----- Rooms -----

export type HotelRoomStatusType = "Available" | "Occupied" | "Maintenance" | "Reserved" | "Cleaning"

export interface HotelRoom {
  hotelRoomId: number
  farmId: string
  roomNumber: string
  hotelRoomTypeId: number
  hotelFloorId?: number | null
  status: HotelRoomStatusType
  description?: string | null
  isActive: boolean
  createdAt: string
  updatedAt?: string | null
  // Joined
  roomTypeName?: string | null
  baseRate?: number | null
  maxOccupancy?: number | null
  bedType?: string | null
  floorNumber?: number | null
  floorName?: string | null
}

export interface HotelRoomInput {
  roomNumber: string
  hotelRoomTypeId: number
  hotelFloorId?: number | null
  status?: HotelRoomStatusType
  description?: string | null
  isActive?: boolean
}

// ----- Amenities -----

export interface HotelAmenity {
  hotelAmenityId: number
  farmId: string
  name: string
  category?: string | null
  icon?: string | null
  isActive: boolean
  createdAt: string
  updatedAt?: string | null
}

export interface HotelAmenityInput {
  name: string
  category?: string | null
  icon?: string | null
  isActive?: boolean
}

export interface HotelRoomAmenity {
  hotelRoomId: number
  hotelAmenityId: number
  farmId: string
  name?: string | null
  category?: string | null
  icon?: string | null
}

export interface HotelRoomStatusSummary {
  status: string
  roomCount: number
}

// =============================================================================
// API FUNCTIONS
// =============================================================================

// ----- Profile -----

export async function getHotelProfile(): Promise<HotelProfile> {
  return jget<HotelProfile>("/Hotel/setup/profile")
}

export async function upsertHotelProfile(input: HotelProfileInput): Promise<HotelProfile> {
  const farmId = activeFarmId()
  return jsend<HotelProfile>("/Hotel/setup/profile", "POST", { ...input, farmId })
}

// ----- Room Categories -----

export async function listHotelRoomCategories(): Promise<HotelRoomCategory[]> {
  return jget<HotelRoomCategory[]>("/Hotel/setup/room-categories")
}

// ----- Supply Categories & Items -----

export async function listHotelSupplyCategories(): Promise<HotelSupplyCategory[]> {
  return jget<HotelSupplyCategory[]>("/Hotel/setup/supply-categories")
}

export async function listHotelSupplyItems(): Promise<HotelSupplyItem[]> {
  return jget<HotelSupplyItem[]>("/Hotel/setup/supply-items")
}

// ----- Maintenance Assets -----

export async function listHotelMaintenanceAssets(): Promise<HotelMaintenanceAsset[]> {
  return jget<HotelMaintenanceAsset[]>("/Hotel/setup/maintenance-assets")
}

// ----- Table Locations -----

export async function listHotelTableLocations(): Promise<HotelTableLocation[]> {
  return jget<HotelTableLocation[]>("/Hotel/setup/table-locations")
}

// ----- HK Task Types -----

export async function listHotelHKTaskTypes(): Promise<HotelHKTaskType[]> {
  return jget<HotelHKTaskType[]>("/Hotel/setup/hk-task-types")
}

// ----- Guest Request Types -----

export async function listHotelRequestTypes(): Promise<HotelRequestType[]> {
  return jget<HotelRequestType[]>("/Hotel/setup/request-types")
}

// ----- Communication Subjects -----

export async function listHotelCommSubjects(): Promise<HotelCommSubject[]> {
  return jget<HotelCommSubject[]>("/Hotel/setup/comm-subjects")
}

// ----- Custom option lists ("Other", remembered) -----

/**
 * Which remembered list a dropdown draws from. Must match the allow-list in
 * HotelCustomOptionController — an unknown key is rejected with a 400.
 */
export type HotelCustomOptionListKey =
  | "CommSubject"        // hotel-communications        -> Log Guest Communication / Subject
  | "RequestType"        // hotel-guest-requests        -> New Guest Request / Type
  | "LostFoundCategory"  // hotel-lost-found            -> Log Lost Item / Category
  | "HKTaskType"         // hotel-housekeeping-schedule -> Add Schedule Entry / Task Type
  | "MenuCategory"       // hotel-menu                  -> Add Menu Item / Category
  | "SupplyCategory"     // hotel-inventory             -> Add Supply Item / Category
  | "SupplyItemName"     // hotel-inventory             -> Add Supply Item / Name
  | "MaintenanceAsset"   // hotel-maintenance           -> New Maintenance Request / Asset / Area
  | "TableLocation"      // hotel-restaurant-tables     -> Add Table / Location

export interface HotelCustomOption {
  customOptionId: number
  farmId: string
  listKey: string
  value: string
  sortOrder: number
  isActive: boolean
  createdAt?: string | null
  createdBy?: string | null
}

/**
 * Values this hotel has added to one dropdown.
 *
 * Returns [] rather than throwing when the endpoint is not there yet: the route
 * only exists once the Farm API has been redeployed with migration 300 applied,
 * and a dropdown that threw on mount would take the whole dialog down with it.
 * An empty list degrades to exactly today's behaviour — seed options only.
 * Same fallback the Restaurant side needed for migration 291.
 */
export async function listHotelCustomOptions(listKey: HotelCustomOptionListKey): Promise<HotelCustomOption[]> {
  try {
    return await jget<HotelCustomOption[]>(`/Hotel/custom-options?listKey=${encodeURIComponent(listKey)}`)
  } catch {
    return []
  }
}

/** Every list for this hotel, for a dialog with more than one "Other" dropdown. */
export async function listAllHotelCustomOptions(): Promise<HotelCustomOption[]> {
  try {
    return await jget<HotelCustomOption[]>("/Hotel/custom-options")
  } catch {
    return []
  }
}

/**
 * Remember a typed value. Idempotent server-side, so re-saving an existing value
 * returns that row instead of creating a duplicate — a double-submit is harmless.
 * Throws on a real failure so the caller can tell the operator it was not saved;
 * callers still apply the typed value to the record either way.
 */
export async function createHotelCustomOption(
  listKey: HotelCustomOptionListKey,
  value: string,
): Promise<HotelCustomOption> {
  const farmId = activeFarmId()
  return jsend<HotelCustomOption>("/Hotel/custom-options", "POST", { farmId, listKey, value })
}

/** Stop offering a value. Soft delete — records already using it are untouched. */
export async function deleteHotelCustomOption(customOptionId: number): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Hotel/custom-options/${customOptionId}?farmId=${encodeURIComponent(farmId)}`, "DELETE")
}

// ----- ID Types -----

export async function listHotelIdTypes(): Promise<HotelIdType[]> {
  return jget<HotelIdType[]>("/Hotel/setup/id-types")
}

// ----- Bed Types -----

export async function listHotelBedTypes(): Promise<HotelBedType[]> {
  return jget<HotelBedType[]>("/Hotel/setup/bed-types")
}

// ----- Room Types -----

export async function listHotelRoomTypes(): Promise<HotelRoomType[]> {
  return jget<HotelRoomType[]>("/Hotel/setup/room-types")
}

export async function getHotelRoomType(id: number): Promise<HotelRoomType> {
  return jget<HotelRoomType>(`/Hotel/setup/room-types/${id}`)
}

export async function createHotelRoomType(input: HotelRoomTypeInput): Promise<HotelRoomType> {
  const farmId = activeFarmId()
  return jsend<HotelRoomType>("/Hotel/setup/room-types", "POST", { ...input, farmId })
}

export async function updateHotelRoomType(id: number, input: HotelRoomTypeInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Hotel/setup/room-types/${id}`, "PUT", { ...input, farmId })
}

export async function deleteHotelRoomType(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/setup/room-types/${id}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- Floors -----

export async function listHotelFloors(): Promise<HotelFloor[]> {
  return jget<HotelFloor[]>("/Hotel/setup/floors")
}

export async function createHotelFloor(input: HotelFloorInput): Promise<{ hotelFloorId: number }> {
  const farmId = activeFarmId()
  return jsend<{ hotelFloorId: number }>("/Hotel/setup/floors", "POST", { ...input, farmId })
}

export async function updateHotelFloor(id: number, input: HotelFloorInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Hotel/setup/floors/${id}`, "PUT", { ...input, farmId })
}

export async function deleteHotelFloor(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/setup/floors/${id}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- Rooms -----

export async function listHotelRooms(): Promise<HotelRoom[]> {
  return jget<HotelRoom[]>("/Hotel/rooms")
}

export async function getHotelRoom(id: number): Promise<HotelRoom> {
  return jget<HotelRoom>(`/Hotel/rooms/${id}`)
}

export async function createHotelRoom(input: HotelRoomInput): Promise<HotelRoom> {
  const farmId = activeFarmId()
  return jsend<HotelRoom>("/Hotel/rooms", "POST", { ...input, farmId })
}

export async function updateHotelRoom(id: number, input: HotelRoomInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Hotel/rooms/${id}`, "PUT", { ...input, farmId })
}

export async function updateHotelRoomStatus(id: number, status: HotelRoomStatusType): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/rooms/${id}/status?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, {
    method: "PATCH",
    headers: getAuthHeaders(),
    body: JSON.stringify({ status }),
  })
  if (!res.ok) throw new Error(await readApiError(res))
}

export async function deleteHotelRoom(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/rooms/${id}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

export async function getHotelRoomStatusSummary(): Promise<HotelRoomStatusSummary[]> {
  return jget<HotelRoomStatusSummary[]>("/Hotel/rooms/status-summary")
}

// ----- Amenities -----

export async function listHotelAmenities(): Promise<HotelAmenity[]> {
  return jget<HotelAmenity[]>("/Hotel/setup/amenities")
}

export async function createHotelAmenity(input: HotelAmenityInput): Promise<{ hotelAmenityId: number }> {
  const farmId = activeFarmId()
  return jsend<{ hotelAmenityId: number }>("/Hotel/setup/amenities", "POST", { ...input, farmId })
}

export async function updateHotelAmenity(id: number, input: HotelAmenityInput): Promise<void> {
  const farmId = activeFarmId()
  await jsend<void>(`/Hotel/setup/amenities/${id}`, "PUT", { ...input, farmId })
}

export async function deleteHotelAmenity(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/setup/amenities/${id}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// ----- Room Amenities -----

export async function listRoomAmenities(roomId: number): Promise<HotelRoomAmenity[]> {
  return jget<HotelRoomAmenity[]>(`/Hotel/rooms/${roomId}/amenities`)
}

export async function addRoomAmenity(roomId: number, amenityId: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/rooms/${roomId}/amenities/${amenityId}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

export async function removeRoomAmenity(roomId: number, amenityId: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/rooms/${roomId}/amenities/${amenityId}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// =============================================================================
// PHASE 2: GUESTS & BOOKINGS
// =============================================================================

export interface HotelGuest {
  hotelGuestId: number; farmId: string; firstName: string; lastName: string
  email?: string | null; phone?: string | null; idType?: string | null; idNumber?: string | null
  nationality?: string | null; address?: string | null; dateOfBirth?: string | null
  notes?: string | null; isVIP: boolean; totalStays: number; lastStayDate?: string | null
  createdAt: string; updatedAt?: string | null
}

export interface HotelGuestInput {
  firstName: string; lastName: string; email?: string | null; phone?: string | null
  idType?: string | null; idNumber?: string | null; nationality?: string | null
  address?: string | null; dateOfBirth?: string | null; notes?: string | null; isVIP?: boolean
}

export type HotelBookingStatusType = "Confirmed" | "CheckedIn" | "CheckedOut" | "Cancelled" | "NoShow"
export type HotelBookingSourceType = "WalkIn" | "Phone" | "Online" | "Agent"

export interface HotelBooking {
  hotelBookingId: number; farmId: string; bookingRef: string; hotelGuestId: number
  hotelRoomId?: number | null; hotelRoomTypeId: number; checkInDate: string; checkOutDate: string
  numberOfGuests: number; adults: number; children: number; nightlyRate: number; totalAmount: number
  status: HotelBookingStatusType; source: HotelBookingSourceType
  specialRequests?: string | null; createdBy?: string | null
  createdAt: string; updatedAt?: string | null
  guestFirstName?: string | null; guestLastName?: string | null; guestPhone?: string | null; guestEmail?: string | null
  roomNumber?: string | null; roomTypeName?: string | null
}

export interface HotelBookingInput {
  hotelGuestId: number; hotelRoomTypeId: number; hotelRoomId?: number | null
  checkInDate: string; checkOutDate: string; numberOfGuests?: number; adults?: number; children?: number
  nightlyRate: number; totalAmount: number; source?: HotelBookingSourceType; specialRequests?: string | null
}

// Guest API
export async function listHotelGuests(): Promise<HotelGuest[]> { return jget<HotelGuest[]>("/Hotel/guests") }
export async function getHotelGuest(id: number): Promise<HotelGuest> { return jget<HotelGuest>(`/Hotel/guests/${id}`) }
export async function searchHotelGuests(q: string): Promise<HotelGuest[]> { return jget<HotelGuest[]>(`/Hotel/guests/search?q=${encodeURIComponent(q)}`) }
export async function createHotelGuest(input: HotelGuestInput): Promise<HotelGuest> { return jsend<HotelGuest>("/Hotel/guests", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateHotelGuest(id: number, input: HotelGuestInput): Promise<void> { await jsend<void>(`/Hotel/guests/${id}`, "PUT", { ...input, farmId: activeFarmId() }) }
export async function deleteHotelGuest(id: number): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/guests/${id}?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() }); if (!res.ok) throw new Error(await readApiError(res)) }

// Booking API
export async function listHotelBookings(): Promise<HotelBooking[]> { return jget<HotelBooking[]>("/Hotel/bookings") }
export async function getHotelBooking(id: number): Promise<HotelBooking> { return jget<HotelBooking>(`/Hotel/bookings/${id}`) }
export async function getTodayArrivals(): Promise<HotelBooking[]> { return jget<HotelBooking[]>("/Hotel/bookings/today-arrivals") }
export async function getTodayDepartures(): Promise<HotelBooking[]> { return jget<HotelBooking[]>("/Hotel/bookings/today-departures") }
export async function createHotelBooking(input: HotelBookingInput): Promise<HotelBooking> {
  const farmId = activeFarmId()
  const ref = `BK-${new Date().toISOString().slice(0,10).replace(/-/g,"")}-${String(Math.floor(Math.random()*999)+1).padStart(3,"0")}`
  return jsend<HotelBooking>("/Hotel/bookings", "POST", { ...input, farmId, bookingRef: ref, status: "Confirmed" })
}
export async function updateHotelBooking(id: number, input: HotelBookingInput): Promise<void> { await jsend<void>(`/Hotel/bookings/${id}`, "PUT", { ...input, farmId: activeFarmId() }) }
export async function cancelHotelBooking(id: number): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/bookings/${id}/cancel?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "POST", headers: getAuthHeaders() }); if (!res.ok) throw new Error(await readApiError(res)) }
export async function updateBookingStatus(id: number, status: HotelBookingStatusType): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/bookings/${id}/status?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status }) }); if (!res.ok) throw new Error(await readApiError(res)) }

// =============================================================================
// PHASE 3: CHECK-IN/OUT & HOUSEKEEPING
// =============================================================================

export interface HotelCheckIn { hotelCheckInId: number; farmId: string; hotelBookingId: number; hotelRoomId: number; hotelGuestId: number; checkInTime: string; keyCardNumber?: string | null; depositAmount: number; depositMethod?: string | null; notes?: string | null; checkedInBy?: string | null; createdAt: string }
export interface HotelCheckOut { hotelCheckOutId: number; farmId: string; hotelBookingId: number; hotelRoomId: number; checkOutTime: string; finalBillAmount: number; lateFee: number; damageCharges: number; keyReturned: boolean; notes?: string | null; checkedOutBy?: string | null; createdAt: string }
export type HotelHousekeepingTaskType = "Cleaning" | "DeepClean" | "Inspection" | "TurnDown" | "Laundry"
export type HotelHousekeepingPriority = "Low" | "Normal" | "High" | "Urgent"
export type HotelHousekeepingStatus = "Pending" | "InProgress" | "Completed" | "Inspected" | "Failed"
export interface HotelHousekeepingTask { hotelHousekeepingTaskId: number; farmId: string; hotelRoomId: number; taskType: HotelHousekeepingTaskType; priority: HotelHousekeepingPriority; status: HotelHousekeepingStatus; assignedTo?: string | null; scheduledDate: string; startedAt?: string | null; completedAt?: string | null; inspectedBy?: string | null; inspectionNotes?: string | null; notes?: string | null; createdAt: string; updatedAt?: string | null; roomNumber?: string | null }

export async function processCheckIn(input: { hotelBookingId: number; hotelRoomId: number; keyCardNumber?: string; depositAmount?: number; depositMethod?: string; notes?: string }): Promise<HotelCheckIn> { return jsend<HotelCheckIn>("/Hotel/front-desk/check-in", "POST", { ...input, farmId: activeFarmId() }) }
export async function processCheckOut(input: { hotelBookingId: number; hotelRoomId: number; lateFee?: number; damageCharges?: number; keyReturned?: boolean; notes?: string }): Promise<HotelCheckOut> { return jsend<HotelCheckOut>("/Hotel/front-desk/check-out", "POST", { ...input, farmId: activeFarmId() }) }
export async function listHousekeepingTasks(): Promise<HotelHousekeepingTask[]> { return jget<HotelHousekeepingTask[]>("/Hotel/housekeeping") }
export async function createHousekeepingTask(input: { hotelRoomId: number; taskType: HotelHousekeepingTaskType; priority?: HotelHousekeepingPriority; assignedTo?: string; scheduledDate?: string; notes?: string }): Promise<HotelHousekeepingTask> { return jsend<HotelHousekeepingTask>("/Hotel/housekeeping", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateHousekeepingStatus(id: number, status: HotelHousekeepingStatus): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/housekeeping/${id}/status?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status }) }); if (!res.ok) throw new Error(await readApiError(res)) }

// =============================================================================
// PHASE 4: FINANCE, BILLING, RESTAURANT
// =============================================================================

export interface HotelStayCharge { hotelStayChargeId: number; farmId: string; hotelBookingId: number; chargeType: string; description: string; quantity: number; unitPrice: number; totalAmount: number; chargeDate: string; postedBy?: string | null; createdAt: string }
export interface HotelInvoice { hotelInvoiceId: number; farmId: string; hotelBookingId: number; hotelGuestId: number; invoiceNumber: string; subTotal: number; taxAmount: number; taxRate: number; discountAmount: number; totalAmount: number; amountPaid: number; balance: number; status: string; issuedDate: string; dueDate?: string | null; notes?: string | null; createdAt: string; updatedAt?: string | null }
export interface HotelPayment { hotelPaymentId: number; farmId: string; hotelInvoiceId?: number | null; hotelBookingId: number; amount: number; paymentMethod: string; reference?: string | null; paymentDate: string; receivedBy?: string | null; notes?: string | null; createdAt: string }
export interface HotelExpense { hotelExpenseId: number; farmId: string; category: string; description: string; amount: number; expenseDate: string; vendor?: string | null; receiptRef?: string | null; status: string; approvedBy?: string | null; notes?: string | null; paymentMethod?: string | null; hotelCashAccountId?: number | null; paidTo?: string | null; hotelExpenseCategoryId?: number | null; createdAt: string; updatedAt?: string | null }
export interface HotelExpenseCategory { hotelExpenseCategoryId: number; farmId: string; name: string; isActive: boolean; createdAt: string }
export interface HotelCashAccount { hotelCashAccountId: number; farmId: string; accountName: string; accountType: string; openingBalance: number; currentBalance: number; isActive: boolean; notes?: string | null; createdAt: string; updatedAt?: string | null }
export interface HotelMenuItem { hotelMenuItemId: number; farmId: string; name: string; category: string; description?: string | null; price: number; isAvailable: boolean; isActive: boolean; createdAt: string; updatedAt?: string | null }
export interface HotelRestaurantTable { hotelRestaurantTableId: number; farmId: string; tableNumber: string; capacity: number; location?: string | null; status: string; createdAt: string }
export interface HotelRestaurantOrder { hotelRestaurantOrderId: number; farmId: string; hotelBookingId?: number | null; hotelRoomId?: number | null; tableNumber?: string | null; serverName?: string | null; status: string; subTotal: number; taxAmount: number; tipAmount: number; totalAmount: number; orderTime: string; deliveredTime?: string | null; notes?: string | null; createdAt: string; updatedAt?: string | null }

// Finance API stubs
export async function listStayCharges(bookingId: number): Promise<HotelStayCharge[]> { return jget<HotelStayCharge[]>(`/Hotel/billing/charges?bookingId=${bookingId}`) }
export async function addStayCharge(input: { hotelBookingId: number; chargeType: string; description: string; quantity: number; unitPrice: number }): Promise<HotelStayCharge> { return jsend<HotelStayCharge>("/Hotel/billing/charges", "POST", { ...input, farmId: activeFarmId(), totalAmount: input.quantity * input.unitPrice }) }
export async function listInvoices(): Promise<HotelInvoice[]> { return jget<HotelInvoice[]>("/Hotel/billing/invoices") }
export async function generateInvoice(bookingId: number): Promise<HotelInvoice> { return jsend<HotelInvoice>("/Hotel/billing/invoices/generate", "POST", { hotelBookingId: bookingId, farmId: activeFarmId() }) }
export async function listHotelPayments(): Promise<HotelPayment[]> { return jget<HotelPayment[]>("/Hotel/billing/payments") }
export async function recordPayment(input: { hotelBookingId: number; hotelInvoiceId?: number; amount: number; paymentMethod: string; reference?: string; notes?: string }): Promise<HotelPayment> { return jsend<HotelPayment>("/Hotel/billing/payments", "POST", { ...input, farmId: activeFarmId() }) }
export async function listHotelExpenses(): Promise<HotelExpense[]> { return jget<HotelExpense[]>("/Hotel/finance/expenses") }
export async function createHotelExpense(input: { category: string; description: string; amount: number; expenseDate: string; vendor?: string; notes?: string; paymentMethod?: string; hotelCashAccountId?: number | null; paidTo?: string; hotelExpenseCategoryId?: number | null }): Promise<HotelExpense> { return jsend<HotelExpense>("/Hotel/finance/expenses", "POST", { ...input, farmId: activeFarmId() }) }
export async function submitHotelExpense(id: number): Promise<void> { await jsend<void>(`/Hotel/finance/expenses/${id}/submit`, "POST", { farmId: activeFarmId() }) }
export async function approveHotelExpense(id: number): Promise<void> { await jsend<void>(`/Hotel/finance/expenses/${id}/approve`, "POST", { farmId: activeFarmId() }) }
export async function cancelHotelExpense(id: number, reason?: string): Promise<void> { await jsend<void>(`/Hotel/finance/expenses/${id}/cancel`, "POST", { farmId: activeFarmId(), reason }) }
export async function listHotelExpenseCategories(): Promise<HotelExpenseCategory[]> { return jget<HotelExpenseCategory[]>("/Hotel/finance/expense-categories") }
export async function createHotelExpenseCategory(input: { name: string }): Promise<HotelExpenseCategory> { return jsend<HotelExpenseCategory>("/Hotel/finance/expense-categories", "POST", { ...input, farmId: activeFarmId() }) }
// The endpoint returns raw Postgres column names (hotelcashaccountid, accountname, ...),
// not the camelCase this type declares. Add the camelCase fields and keep the originals,
// so pages reading either spelling work.
export async function listHotelCashAccounts(): Promise<HotelCashAccount[]> {
  const rows = await jget<any[]>("/Hotel/finance/cash-accounts")
  return (rows ?? []).map((r) => ({
    ...r,
    hotelCashAccountId: r.hotelCashAccountId ?? r.hotelcashaccountid,
    farmId: r.farmId ?? r.farmid,
    accountName: r.accountName ?? r.accountname,
    accountType: r.accountType ?? r.accounttype,
    openingBalance: r.openingBalance ?? r.openingbalance,
    currentBalance: r.currentBalance ?? r.currentbalance,
    isActive: r.isActive ?? r.isactive,
    createdAt: r.createdAt ?? r.createdat,
    updatedAt: r.updatedAt ?? r.updatedat,
  }))
}
export async function createHotelCashAccount(input: { accountName: string; accountType: string; openingBalance: number; purpose?: string | null }): Promise<HotelCashAccount> { return jsend<HotelCashAccount>("/Hotel/finance/cash-accounts", "POST", { ...input, farmId: activeFarmId() }) }
export async function deleteHotelCashAccount(id: number): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/finance/cash-accounts/${id}?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() }); if (!res.ok) throw new Error(await readApiError(res)) }
export async function updateCashAccountPurpose(id: number, purpose: string | null): Promise<void> { await jsend<void>(`/Hotel/finance/cash-accounts/${id}/purpose`, "PATCH", { farmId: activeFarmId(), purpose }) }

// Cash Transactions API
export interface HotelCashTransaction { hotelcashtxnid: number; farmid: string; hotelcashaccountid: number; txntype: string; amount: number; balanceafter: number; description?: string | null; reference?: string | null; sourcetype?: string | null; sourceid?: number | null; txndate: string; createdby?: string | null; createdat: string; accountname?: string | null }
export async function listCashTransactions(accountId?: number): Promise<HotelCashTransaction[]> {
  const farmId = activeFarmId()
  const acctParam = accountId ? `&accountId=${accountId}` : ""
  const url = farmApiUrl(`/Hotel/finance/cash-transactions?farmId=${encodeURIComponent(farmId)}${acctParam}`)
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

// Paginated API variants
export interface PaginatedResult<T> { data: T[]; total: number; page: number; pageSize: number }

async function jpaged<T>(endpoint: string, page: number, pageSize: number): Promise<PaginatedResult<T>> {
  const farmId = activeFarmId()
  const sep = endpoint.includes("?") ? "&" : "?"
  const url = farmApiUrl(`${endpoint}${sep}farmId=${encodeURIComponent(farmId)}&page=${page}&pageSize=${pageSize}`)
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

export async function listHotelBookingsPaged(page: number, pageSize: number): Promise<PaginatedResult<HotelBooking>> { return jpaged<HotelBooking>("/Hotel/bookings", page, pageSize) }
export async function listHotelPaymentsPaged(page: number, pageSize: number): Promise<PaginatedResult<HotelPayment>> { return jpaged<HotelPayment>("/Hotel/billing/payments", page, pageSize) }
export async function listHotelExpensesPaged(page: number, pageSize: number): Promise<PaginatedResult<HotelExpense>> { return jpaged<HotelExpense>("/Hotel/finance/expenses", page, pageSize) }

// Menu & Restaurant API
export async function listMenuItems(): Promise<HotelMenuItem[]> { return jget<HotelMenuItem[]>("/Hotel/restaurant/menu") }
export async function createMenuItem(input: { name: string; category: string; description?: string; price: number }): Promise<HotelMenuItem> { return jsend<HotelMenuItem>("/Hotel/restaurant/menu", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateMenuItem(id: number, input: { name: string; category: string; description?: string; price: number; isAvailable?: boolean }): Promise<void> { await jsend<void>(`/Hotel/restaurant/menu/${id}`, "PUT", { ...input, farmId: activeFarmId() }) }
export async function deleteMenuItem(id: number): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/restaurant/menu/${id}?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() }); if (!res.ok) throw new Error(await readApiError(res)) }
export async function listRestaurantTables(): Promise<HotelRestaurantTable[]> { return jget<HotelRestaurantTable[]>("/Hotel/restaurant/tables") }
export async function createRestaurantTable(input: { tableNumber: string; capacity: number; location?: string }): Promise<HotelRestaurantTable> { return jsend<HotelRestaurantTable>("/Hotel/restaurant/tables", "POST", { ...input, farmId: activeFarmId() }) }
export async function listRestaurantOrders(): Promise<HotelRestaurantOrder[]> { return jget<HotelRestaurantOrder[]>("/Hotel/restaurant/orders") }
export async function createRestaurantOrder(input: { tableNumber?: string; serverName?: string; hotelBookingId?: number; hotelRoomId?: number; items?: { menuItemId: number; quantity: number; unitPrice: number; notes?: string }[] }): Promise<HotelRestaurantOrder> { return jsend<HotelRestaurantOrder>("/Hotel/restaurant/orders", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateRestaurantOrderStatus(id: number, status: string): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/restaurant/orders/${id}/status?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status }) }); if (!res.ok) throw new Error(await readApiError(res)) }

// =============================================================================
// PHASE 5: STAFF, INVENTORY, MAINTENANCE, REPORTS, DASHBOARD
// =============================================================================

export interface HotelStaff { hotelStaffId: number; farmId: string; firstName: string; lastName: string; email?: string | null; phone?: string | null; role: string; department: string; hireDate: string; isActive: boolean; salaryAmount: number; notes?: string | null; createdAt: string; updatedAt?: string | null }
export interface HotelInventoryItem { hotelInventoryItemId: number; farmId: string; name: string; category: string; unit: string; stockOnHand: number; reorderLevel: number; unitCost: number; isActive: boolean; createdAt: string; updatedAt?: string | null }
export interface HotelMaintenanceRequest { hotelMaintenanceRequestId: number; farmId: string; hotelRoomId?: number | null; assetDescription: string; issueDescription: string; priority: string; status: string; assignedTo?: string | null; estimatedCost: number; actualCost: number; reportedBy?: string | null; reportedAt: string; completedAt?: string | null; notes?: string | null; createdAt: string; updatedAt?: string | null; roomNumber?: string | null }
export interface HotelDailyClosing { hotelDailyClosingId: number; farmId: string; closingDate: string; totalRevenue: number; roomRevenue: number; fnbRevenue: number; otherRevenue: number; totalExpenses: number; occupancyRate: number; roomsOccupied: number; totalRooms: number; adr: number; revPar: number; notes?: string | null; closedBy?: string | null; createdAt: string }
export interface HotelDashboardSummary { totalRooms: number; availableRooms: number; occupiedRooms: number; reservedRooms: number; cleaningRooms: number; maintenanceRooms: number; occupancyRate: number; todayArrivals: number; todayDepartures: number; todayRevenue: number; monthlyRevenue: number; adr: number; revPar: number }

// Staff API
export async function listHotelStaff(): Promise<HotelStaff[]> { return jget<HotelStaff[]>("/Hotel/staff") }
export async function createHotelStaff(input: { firstName: string; lastName: string; role: string; department: string; salaryAmount: number; email?: string; phone?: string; hireDate?: string }): Promise<HotelStaff> { return jsend<HotelStaff>("/Hotel/staff", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateHotelStaff(id: number, input: any): Promise<void> { await jsend<void>(`/Hotel/staff/${id}`, "PUT", { ...input, farmId: activeFarmId() }) }
export async function deleteHotelStaff(id: number): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/staff/${id}?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() }); if (!res.ok) throw new Error(await readApiError(res)) }

// Inventory API
export async function listHotelInventory(): Promise<HotelInventoryItem[]> { return jget<HotelInventoryItem[]>("/Hotel/inventory") }
export async function createHotelInventoryItem(input: { name: string; category: string; unit: string; stockOnHand: number; reorderLevel: number; unitCost: number }): Promise<HotelInventoryItem> { return jsend<HotelInventoryItem>("/Hotel/inventory", "POST", { ...input, farmId: activeFarmId() }) }

// Maintenance API
export async function listMaintenanceRequests(): Promise<HotelMaintenanceRequest[]> { return jget<HotelMaintenanceRequest[]>("/Hotel/maintenance") }
export async function createMaintenanceRequest(input: { hotelRoomId?: number; assetDescription: string; issueDescription: string; priority?: string; estimatedCost?: number }): Promise<HotelMaintenanceRequest> { return jsend<HotelMaintenanceRequest>("/Hotel/maintenance", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateMaintenanceStatus(id: number, status: string): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/maintenance/${id}/status?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "PATCH", headers: getAuthHeaders(), body: JSON.stringify({ status }) }); if (!res.ok) throw new Error(await readApiError(res)) }

// Reports & Dashboard API
export async function getHotelDashboardSummary(): Promise<HotelDashboardSummary> { return jget<HotelDashboardSummary>("/Hotel/dashboard/summary") }
export async function listDailyClosings(): Promise<HotelDailyClosing[]> { return jget<HotelDailyClosing[]>("/Hotel/reports/daily-closings") }
export async function createDailyClosing(input: { closingDate: string; notes?: string }): Promise<HotelDailyClosing> { return jsend<HotelDailyClosing>("/Hotel/reports/daily-closings", "POST", { ...input, farmId: activeFarmId() }) }

// Night Audit API
export interface HotelNightAudit { hotelnightauditid: number; farmid: string; auditdate: string; totalrooms: number; occupiedrooms: number; availablerooms: number; occupancyrate: number; totalrevenue: number; totalexpenses: number; outstandingbalances: number; checkincount: number; checkoutcount: number; noshowcount: number; pendinghousetasks: number; openmaintenance: number; issues?: string | null; status: string; roomchargesposted: number; createdat: string }
export async function runNightAudit(input: { closingDate?: string; notes?: string }): Promise<HotelNightAudit> { return jsend<HotelNightAudit>("/Hotel/night-audit", "POST", { ...input, farmId: activeFarmId() }) }
export async function listNightAudits(): Promise<HotelNightAudit[]> { return jget<HotelNightAudit[]>("/Hotel/night-audit") }

// Room Rate Calendar API
export interface HotelRoomRate { hotelroomrateid: number; farmid: string; hotelroomtypeid: number; ratename: string; rate: number; startdate: string; enddate: string; isweekend: boolean; isactive: boolean; roomtypename?: string; createdat: string }
export async function listRoomRates(): Promise<HotelRoomRate[]> { return jget<HotelRoomRate[]>("/Hotel/room-rates") }
export async function createRoomRate(input: { hotelRoomTypeId: number; rateName: string; rate: number; startDate: string; endDate: string; isWeekend?: boolean }): Promise<HotelRoomRate> { return jsend<HotelRoomRate>("/Hotel/room-rates", "POST", { ...input, farmId: activeFarmId() }) }
export async function deleteRoomRate(id: number): Promise<void> { const farmId = activeFarmId(); const url = farmApiUrl(`/Hotel/room-rates/${id}?farmId=${encodeURIComponent(farmId)}`); const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() }); if (!res.ok) throw new Error(await readApiError(res)) }

// Order Items API
export async function getOrderItems(orderId: number): Promise<any[]> { return jget<any[]>(`/Hotel/restaurant/orders/${orderId}/items`) }

// =============================================================================
// LOYALTY PROGRAM
// =============================================================================

export type LoyaltyTier = "Bronze" | "Silver" | "Gold" | "Platinum"

export interface HotelLoyaltyMember {
  hotelloyaltymemberid: number; farmid: string; hotelguestid: number
  membershipnumber: string; tier: LoyaltyTier; totalpoints: number; lifetimepoints: number
  joinedat: string; lasttierupdate?: string | null; notes?: string | null
  isactive: boolean; createdat: string; updatedat?: string | null
  // Joined guest fields
  firstname?: string; lastname?: string; email?: string | null; phone?: string | null; isvip?: boolean
}

export interface HotelLoyaltyTransaction {
  hotelloyaltytransactionid: number; farmid: string; hotelloyaltymemberid: number
  hotelbookingid?: number | null; transactiontype: string; points: number
  description?: string | null; createdat: string
}

export async function listLoyaltyMembers(): Promise<HotelLoyaltyMember[]> { return jget<HotelLoyaltyMember[]>("/Hotel/loyalty") }
export async function getLoyaltyMember(id: number): Promise<HotelLoyaltyMember> { return jget<HotelLoyaltyMember>(`/Hotel/loyalty/${id}`) }
export async function getLoyaltyByGuest(guestId: number): Promise<HotelLoyaltyMember | { enrolled: false }> { return jget<any>(`/Hotel/loyalty/guest/${guestId}`) }
export async function enrollLoyalty(guestId: number, notes?: string): Promise<HotelLoyaltyMember> { return jsend<HotelLoyaltyMember>("/Hotel/loyalty/enroll", "POST", { hotelGuestId: guestId, notes, farmId: activeFarmId() }) }
export async function addLoyaltyPoints(input: { hotelLoyaltyMemberId: number; hotelBookingId?: number; transactionType: string; points: number; description?: string }): Promise<{ success: boolean; tier: string }> { return jsend<{ success: boolean; tier: string }>("/Hotel/loyalty/points", "POST", { ...input, farmId: activeFarmId() }) }
export async function listLoyaltyTransactions(memberId: number): Promise<HotelLoyaltyTransaction[]> { return jget<HotelLoyaltyTransaction[]>(`/Hotel/loyalty/${memberId}/transactions`) }

// =============================================================================
// PAYROLL
// =============================================================================

export interface HotelPayrollRun {
  hotelpayrollrunid: number; farmid: string
  periodstart: string; periodend: string; paydate?: string | null
  totalgrosspay: number; totaldeductions: number; totalnetpay: number
  status: string; hotelcashaccountid?: number | null; cashaccountname?: string | null
  notes?: string | null; createdby?: string | null
  approvedby?: string | null; approvedat?: string | null
  paidby?: string | null; paidat?: string | null
  cancelledby?: string | null; cancelreason?: string | null
  createdat: string; updatedat?: string | null
}

export interface HotelPayrollItem {
  hotelpayrollitemid: number; hotelpayrollrunid: number
  hotelstaffid: number; staffname?: string | null; staffrole?: string | null
  basicpay: number; dailywage: number; commission: number; bonus: number
  /** Total deducted: otherdeductions plus the line's staff loan deductions. */
  deductions: number; netpay: number
  /** What the user typed as deductions (tax, penalties, ...), excluding loans. */
  otherdeductions?: number
  paymentmethod?: string | null; notes?: string | null; createdat: string
}

/** A staff loan deduction on a payroll line. Draft until the run is approved, then Posted as a loan repayment. */
export interface HotelPayrollDeduction {
  hotelPayrollDeductionId: number
  hotelPayrollItemId: number
  hotelStaffId: number
  hotelEmployeeLoanId: number
  loanNumber?: string | null
  loanType: string
  deductionType: string
  amount: number
  status: "Draft" | "Posted" | "Reversed" | string
  hotelEmployeeLoanRepaymentId?: number | null
  outstandingBalance: number
}

export interface HotelPayrollRunDetail {
  run: HotelPayrollRun; items: HotelPayrollItem[]; deductions: HotelPayrollDeduction[]
}

// Payroll API
export async function listHotelPayrollRuns(status?: string): Promise<HotelPayrollRun[]> {
  const qs = status ? `&status=${encodeURIComponent(status)}` : ""
  return jget<HotelPayrollRun[]>(`/Hotel/payroll-runs?${qs}`)
}

export async function getHotelPayrollRun(id: number): Promise<HotelPayrollRunDetail> {
  return jget<HotelPayrollRunDetail>(`/Hotel/payroll-runs/${id}`)
}

export async function createHotelPayrollRun(input: { periodStart: string; periodEnd: string; payDate?: string; hotelCashAccountId?: number; notes?: string }): Promise<HotelPayrollRun> {
  return jsend<HotelPayrollRun>("/Hotel/payroll-runs", "POST", { ...input, farmId: activeFarmId() })
}

/**
 * Save one payroll line. `deductions` is the OTHER deductions (not loans).
 * `loanDeductions`: omit to keep the line's loan deductions as they are; pass a
 * list to replace them (an empty list removes them all).
 */
export async function upsertHotelPayrollItem(runId: number, input: { hotelStaffId: number; staffName?: string; staffRole?: string; basicPay: number; dailyWage: number; commission: number; bonus: number; deductions: number; paymentMethod?: string; notes?: string; loanDeductions?: { loanId: number; amount: number }[] }): Promise<any> {
  return jsend<any>(`/Hotel/payroll-runs/${runId}/items`, "POST", { ...input, hotelPayrollRunId: runId, farmId: activeFarmId() })
}

export async function deleteHotelPayrollItem(itemId: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/payroll-runs/items/${itemId}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

export async function approveHotelPayrollRun(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/payroll-runs/${id}/approve?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// Mark paid, cancel and reopen take a JSON body: the API reads farmId from it.
// (Mark paid and cancel used to send query strings only, which the API rejected.)
export async function markHotelPayrollRunPaid(id: number, payDate?: string): Promise<void> {
  await jsend<void>(`/Hotel/payroll-runs/${id}/mark-paid`, "POST", { farmId: activeFarmId(), payDate: payDate || undefined })
}

export async function cancelHotelPayrollRun(id: number, reason?: string): Promise<void> {
  await jsend<void>(`/Hotel/payroll-runs/${id}/cancel`, "POST", { farmId: activeFarmId(), cancelReason: reason || undefined })
}

/** Approved -> Draft, to correct a run before it is paid. Its staff loan repayments are reversed. */
export async function reopenHotelPayrollRun(id: number, reason: string): Promise<void> {
  await jsend<void>(`/Hotel/payroll-runs/${id}/reopen`, "POST", { farmId: activeFarmId(), reason })
}

export async function deleteHotelPayrollRun(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Hotel/payroll-runs/${id}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

// =============================================================================
// PHASE 6: NEW FEATURES
// =============================================================================

// Room Availability
export async function checkRoomAvailability(checkIn: string, checkOut: string, roomTypeId?: number): Promise<any[]> {
  const farmId = activeFarmId()
  let url = farmApiUrl(`/Hotel/availability?farmId=${encodeURIComponent(farmId)}&checkIn=${checkIn}&checkOut=${checkOut}`)
  if (roomTypeId) url += `&roomTypeId=${roomTypeId}`
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

// Guest Stay History
export async function getGuestStayHistory(guestId: number): Promise<any[]> { return jget<any[]>(`/Hotel/stay-history/${guestId}`) }

// Check-in/out History
export async function listCheckInHistory(): Promise<any[]> { return jget<any[]>("/Hotel/checkin-history") }
export async function listCheckOutHistory(): Promise<any[]> { return jget<any[]>("/Hotel/checkout-history") }

// Guest Folio
export async function getGuestFolio(bookingId: number): Promise<any> { return jget<any>(`/Hotel/folio/${bookingId}`) }

// Deposits
export async function listDeposits(bookingId?: number): Promise<any[]> {
  const farmId = activeFarmId()
  let url = farmApiUrl(`/Hotel/deposits?farmId=${encodeURIComponent(farmId)}`)
  if (bookingId) url += `&bookingId=${bookingId}`
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function createDeposit(input: { hotelBookingId: number; hotelGuestId: number; depositType: string; amount: number; method?: string; reference?: string; notes?: string }): Promise<any> { return jsend<any>("/Hotel/deposits", "POST", { ...input, farmId: activeFarmId() }) }

// Guest Communications
export async function listCommunications(guestId?: number): Promise<any[]> {
  const farmId = activeFarmId()
  let url = farmApiUrl(`/Hotel/communications?farmId=${encodeURIComponent(farmId)}`)
  if (guestId) url += `&guestId=${guestId}`
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function createCommunication(input: { hotelGuestId: number; hotelBookingId?: number; commType: string; subject?: string; message: string; priority?: string; assignedTo?: string }): Promise<any> { return jsend<any>("/Hotel/communications", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateCommunicationStatus(id: number, status: string): Promise<any> { return jsend<any>(`/Hotel/communications/${id}/status`, "PATCH", { farmId: activeFarmId(), status }) }

// Guest Requests
export async function listGuestRequests(status?: string): Promise<any[]> {
  const farmId = activeFarmId()
  let url = farmApiUrl(`/Hotel/guest-requests?farmId=${encodeURIComponent(farmId)}`)
  if (status) url += `&status=${status}`
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function createGuestRequest(input: { hotelBookingId?: number; hotelRoomId?: number; requestType: string; description?: string; scheduledTime?: string; assignedTo?: string; notes?: string }): Promise<any> { return jsend<any>("/Hotel/guest-requests", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateGuestRequestStatus(id: number, status: string): Promise<any> { return jsend<any>(`/Hotel/guest-requests/${id}/status`, "PATCH", { farmId: activeFarmId(), status }) }

// Lost & Found
export async function listLostFound(): Promise<any[]> { return jget<any[]>("/Hotel/lost-and-found") }
export async function createLostFound(input: { hotelRoomId?: number; hotelBookingId?: number; hotelGuestId?: number; itemDescription: string; foundDate?: string; foundBy?: string; foundLocation?: string; category?: string; storageLocation?: string; notes?: string }): Promise<any> { return jsend<any>("/Hotel/lost-and-found", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateLostFoundStatus(id: number, status: string, claimedBy?: string): Promise<any> { return jsend<any>(`/Hotel/lost-and-found/${id}/status`, "PATCH", { farmId: activeFarmId(), status, claimedBy }) }

// Room Flags
export async function updateRoomFlags(roomId: number, flags: { dnd?: boolean; lateCheckout?: string; vipTreatment?: boolean; specialInstructions?: string }): Promise<any> { return jsend<any>(`/Hotel/rooms/${roomId}/flags`, "PATCH", { ...flags, farmId: activeFarmId() }) }

// Housekeeping Schedule
export async function listHKSchedule(date?: string): Promise<any[]> {
  const farmId = activeFarmId()
  let url = farmApiUrl(`/Hotel/housekeeping-schedule?farmId=${encodeURIComponent(farmId)}`)
  if (date) url += `&date=${date}`
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}
export async function createHKSchedule(input: { scheduleDate: string; hotelRoomId: number; assignedTo?: string; taskType?: string; priority?: string; notes?: string }): Promise<any> { return jsend<any>("/Hotel/housekeeping-schedule", "POST", { ...input, farmId: activeFarmId() }) }
export async function bulkCreateHKSchedule(input: { scheduleDate: string; taskType?: string; assignedTo?: string }): Promise<any> { return jsend<any>("/Hotel/housekeeping-schedule/bulk", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateHKScheduleStatus(id: number, status: string): Promise<any> { return jsend<any>(`/Hotel/housekeeping-schedule/${id}/status`, "PATCH", { farmId: activeFarmId(), status }) }

// Shift Handovers
export async function listShiftHandovers(): Promise<any[]> { return jget<any[]>("/Hotel/shift-handovers") }
export async function createShiftHandover(input: { shiftDate?: string; shiftType: string; handoverBy: string; handoverTo?: string; keyMessages?: string; pendingItems?: string; vipGuests?: string; incidents?: string; cashBalance?: number }): Promise<any> { return jsend<any>("/Hotel/shift-handovers", "POST", { ...input, farmId: activeFarmId() }) }
export async function acknowledgeShiftHandover(id: number, receivedBy: string): Promise<any> { return jsend<any>(`/Hotel/shift-handovers/${id}/acknowledge`, "POST", { farmId: activeFarmId(), receivedBy }) }

// =============================================================================
// SERVER-SIDE REPORTS — migration 299
// =============================================================================
// The first hotel reporting that aggregates in the DATABASE. Every existing
// hotel report page calls one of the unfiltered list functions above, pulls the
// whole table into the browser and sums it in JavaScript; these ten hand back
// rows that are already aggregated and already filtered to a date range.
//
// All are (from, to) except the guest ledger, which is a position rather than a
// period and so takes no dates at all.
function hrq(path: string, from: string, to: string): string {
  return `/Hotel/reports/${path}?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`
}

export interface SourceOfBusinessRow {
  sourceLabel: string; bookingCount: number; roomNights: number; guestCount: number
  revenueTotal: number; adr: number; sharePct: number; avgLeadDays: number
}
export async function getSourceOfBusiness(from: string, to: string): Promise<SourceOfBusinessRow[]> {
  return jget<SourceOfBusinessRow[]>(hrq("source-of-business", from, to))
}

export interface BookingPaceRow {
  leadBucket: string; bucketOrder: number; bookingCount: number; roomNights: number
  revenueTotal: number; adr: number; sharePct: number
}
export async function getBookingPace(from: string, to: string): Promise<BookingPaceRow[]> {
  return jget<BookingPaceRow[]>(hrq("booking-pace", from, to))
}

export interface RoomTypePerformanceRow {
  typeLabel: string; roomsInType: number; bookingCount: number; roomNights: number
  revenueTotal: number; adr: number; revpar: number; occupancyPct: number; sharePct: number
}
export async function getRoomTypePerformance(from: string, to: string): Promise<RoomTypePerformanceRow[]> {
  return jget<RoomTypePerformanceRow[]>(hrq("room-type-performance", from, to))
}

export interface HotelPerformanceKpis {
  daysCounted: number; availableRoomNights: number; occupiedRoomNights: number
  occupancyPct: number; roomRevenue: number; fnbRevenue: number; otherRevenue: number
  totalRevenue: number; totalExpenses: number; grossOperatingProfit: number
  adr: number; revpar: number; trevpar: number; goppar: number; noshowCount: number
}
export async function getHotelPerformanceKpis(from: string, to: string): Promise<HotelPerformanceKpis> {
  return jget<HotelPerformanceKpis>(hrq("performance-kpis", from, to))
}

export interface GuestLedgerRow {
  invoiceRef: string; guestLabel: string; issuedOn: string; dueOn?: string | null
  invoiceState: string; totalAmount: number; paidAmount: number; balanceDue: number
  daysOutstanding: number; ageBucket: string
}
// No date range: a ledger is what is owed right now.
export async function getGuestLedger(): Promise<GuestLedgerRow[]> {
  return jget<GuestLedgerRow[]>("/Hotel/reports/guest-ledger")
}

export interface AncillaryRevenueRow {
  chargeLabel: string; chargeCount: number; qtyTotal: number; revenueTotal: number
  avgCharge: number; sharePct: number; staysTouched: number
}
export async function getAncillaryRevenue(from: string, to: string): Promise<AncillaryRevenueRow[]> {
  return jget<AncillaryRevenueRow[]>(hrq("ancillary-revenue", from, to))
}

export interface HotelCancellationRow {
  sourceLabel: string; cancelledCount: number; nightsLost: number; valueLost: number
  sharePct: number; avgLeadDays: number; bookedCount: number; cancelRatePct: number
}
export async function getHotelCancellations(from: string, to: string): Promise<HotelCancellationRow[]> {
  return jget<HotelCancellationRow[]>(hrq("cancellations", from, to))
}

export interface LengthOfStayRow {
  losBucket: string; bucketOrder: number; bookingCount: number; roomNights: number
  revenueTotal: number; adr: number; sharePct: number
}
export async function getLengthOfStay(from: string, to: string): Promise<LengthOfStayRow[]> {
  return jget<LengthOfStayRow[]>(hrq("length-of-stay", from, to))
}

export interface HousekeepingProductivityRow {
  attendantLabel: string; tasksTotal: number; tasksCompleted: number; timedCount: number
  avgMinutes: number; fastestMinutes: number; slowestMinutes: number
  roomsPerShift: number; inspectedCount: number
}
export async function getHousekeepingProductivity(from: string, to: string): Promise<HousekeepingProductivityRow[]> {
  return jget<HousekeepingProductivityRow[]>(hrq("housekeeping-productivity", from, to))
}

export interface HotelLoyaltyRow {
  tierLabel: string; memberCount: number; activeMembers: number; pointsBalance: number
  lifetimePoints: number; earnedInPeriod: number; redeemedInPeriod: number; sharePct: number
}
export async function getHotelLoyaltyReport(from: string, to: string): Promise<HotelLoyaltyRow[]> {
  return jget<HotelLoyaltyRow[]>(hrq("loyalty", from, to))
}

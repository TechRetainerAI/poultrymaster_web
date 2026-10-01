// Hotel Sales (migration 332): what the hotel sold -- stays (room nights plus
// every folio charge) and walk-in restaurant orders -- with Total / Paid /
// Balance, and billing a checked-out stay to a corporate account.

import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

export interface HotelSaleRow {
  documentType: "Stay" | "Order" | string
  documentId: number
  partyId?: number | null
  partyName?: string | null
  docDate: string
  dueDate?: string | null
  reference?: string | null
  label?: string | null
  totalAmount: number
  amountPaid: number
  balance: number
  paymentStatus: "Paid" | "Partial" | "Pending" | string
  bookingStatus?: string | null
  nights?: number | null
  roomNumber?: string | null
  paymentMethod?: string | null
  billedToAccount: boolean
  isOwing: boolean
  isOverdue: boolean
}

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

export async function listHotelSales(range: { from?: string | null; to?: string | null } = {}): Promise<HotelSaleRow[]> {
  const q = new URLSearchParams({ farmId: activeFarmId() })
  if (range.from) q.set("from", range.from)
  if (range.to) q.set("to", range.to)
  const res = await fetch(farmApiUrl(`/Hotel/sales?${q}`), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return (await res.json()) as HotelSaleRow[]
}

export async function billStayToAccount(bookingId: number, hotelCustomerId: number): Promise<void> {
  const res = await fetch(farmApiUrl(`/Hotel/sales/${bookingId}/bill-to`), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ farmId: activeFarmId(), hotelCustomerId }),
  })
  if (!res.ok) throw new Error(await readApiError(res))
}

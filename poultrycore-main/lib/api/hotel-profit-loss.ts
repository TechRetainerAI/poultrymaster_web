import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

// ---- types ------------------------------------------------------------------

export interface HotelProfitLossLine {
  section: string
  lineKey: string
  lineLabel: string
  amount: number
  sortOrder: number
  isInformational: boolean
  entryCount: number
}

export interface HotelProfitLossReport {
  startDate: string
  endDate: string
  roomRevenue: number
  restaurantRevenue: number
  depositsNet: number
  totalRevenue: number
  staffWages: number
  totalExpenseCategory: number
  totalExpenses: number
  netProfit: number
  netMarginPercent: number | null
  status: string
  revenueEntries: number
  expenseEntries: number
  lines: HotelProfitLossLine[]
}

export interface HotelPlExpenseRow {
  hotelExpenseId: number
  expenseDate: string
  category: string | null
  description: string | null
  amount: number
  vendor: string | null
  paymentMethod: string | null
  status: string | null
  plLineKey: string | null
}

export interface HotelPlRevenueRow {
  sourceType: string | null
  sourceId: number
  entryDate: string
  description: string | null
  amount: number
  method: string | null
  plLineKey: string | null
}

// ---- API calls --------------------------------------------------------------

async function get<T>(path: string, qs: Record<string, string>): Promise<T> {
  const farmId = getUserContext().farmId ?? ""
  const params = new URLSearchParams({ farmId, ...qs })
  const url = farmApiUrl(`/Hotel/profit-loss${path}?${params}`)
  const res = await fetch(url, { method: "GET", headers: getAuthHeaders() })
  if (!res.ok) {
    const text = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", `/Hotel/profit-loss${path}`, res.status, text))
  }
  return res.json()
}

export async function getHotelProfitLoss(opts?: {
  startDate?: string; endDate?: string
}): Promise<HotelProfitLossReport> {
  const qs: Record<string, string> = {}
  if (opts?.startDate) qs.startDate = opts.startDate
  if (opts?.endDate) qs.endDate = opts.endDate
  return get<HotelProfitLossReport>("", qs)
}

export async function getHotelPlExpenses(opts: {
  startDate: string; endDate: string; lineKey?: string
}): Promise<HotelPlExpenseRow[]> {
  const qs: Record<string, string> = { startDate: opts.startDate, endDate: opts.endDate }
  if (opts.lineKey) qs.lineKey = opts.lineKey
  return get<HotelPlExpenseRow[]>("/expenses", qs)
}

export async function getHotelPlRevenue(opts: {
  startDate: string; endDate: string; lineKey?: string
}): Promise<HotelPlRevenueRow[]> {
  const qs: Record<string, string> = { startDate: opts.startDate, endDate: opts.endDate }
  if (opts.lineKey) qs.lineKey = opts.lineKey
  return get<HotelPlRevenueRow[]>("/revenue", qs)
}

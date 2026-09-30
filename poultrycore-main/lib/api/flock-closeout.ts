// Flock closeout — REST client for PoultryFarmAPI/FlockCloseoutController
// (migration 332).
//
// farmId goes in the QUERY STRING on every call, writes included: that is where
// the API's IAM filter reads the company from, so a body-only farmId would be
// checked against whatever company the token was issued for.

import { buildApiUrl, getAuthHeaders } from "./config"
import { DEFAULT_FARM_API_HOST } from "@/lib/api/default-api-hosts"
import type { Flock } from "@/lib/api/flock"

function normalizeApiBase(raw?: string, fallback = DEFAULT_FARM_API_HOST) {
  const val = raw || fallback
  return val.startsWith("http://") || val.startsWith("https://") ? val : `https://${val}`
}

const DIRECT_API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)
const IS_BROWSER = typeof window !== "undefined"

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
}

/** fnflock_birdposition: every figure derived, none typed. */
export interface FlockBirdPosition {
  flockId: number
  hasOpeningPosition: boolean
  historyKnown: boolean
  originallyPlaced: number
  openingMortality: number
  openingSold: number
  openingCulled: number
  openingTransferred: number
  openingOther: number
  openingLiveBirds: number
  recordedMortality: number
  productionRecordCount: number
  lastCountedBirds: number
  lastCountDate?: string | null
  correction: number
  birdsSold: number
  birdsCulled: number
  birdsTransferred: number
  currentLiveBirds: number
}

export interface FlockCloseoutContext {
  flock: Flock
  position: FlockBirdPosition
  isClosed: boolean
  ineligibleReason?: string | null
  houseName?: string | null
  businessDate: string
  earliestCloseDate: string
  birdProductName: string
}

export type PaymentTerms = "Paid" | "Credit" | "PartPaid"

export interface FlockCloseoutSaleLine {
  quantity: number
  unitPrice: number
  totalAmount?: number | null
  customerId?: number | null
  customerName?: string | null
  paymentTerms: PaymentTerms
  amountPaid?: number | null
  paymentMethod?: string | null
  poultryCashAccountId?: number | null
  description?: string | null
}

export interface FlockCloseoutCullLine {
  quantity: number
  notes?: string | null
}

export interface FlockCloseoutTransferLine {
  quantity: number
  destination: string
  notes?: string | null
}

export interface FlockCloseoutRequest {
  userId: string
  farmId: string
  closedDate: string
  reason: string
  notes?: string | null
  sales: FlockCloseoutSaleLine[]
  culls: FlockCloseoutCullLine[]
  transfers: FlockCloseoutTransferLine[]
}

export interface FlockCloseoutResult {
  success: boolean
  message: string
  closeoutId?: number | null
  saleIds: number[]
  releasedHouseId?: number | null
  releasedHouseName?: string | null
  warnings: string[]
  errors: string[]
}

export interface FlockReopenResult {
  success: boolean
  message: string
  closeoutId?: number | null
  warnings: string[]
}

export interface FlockCloseoutDisposition {
  dispositionId: number
  disposition: "Sale" | "Cull" | "Transfer"
  quantity: number
  saleId?: number | null
  destination?: string | null
  notes?: string | null
  reversedAt?: string | null
  /** 333: when a reopen reversed this sale. The sale row is then gone; amount and customer are a snapshot. */
  saleReversedAt?: string | null
  totalAmount?: number | null
  customerName?: string | null
  paid?: boolean | null
}

export interface FlockCloseoutRecord {
  closeoutId: number
  flockId: number
  closedDate: string
  reason: string
  notes?: string | null
  closedBy: string
  closedAt: string
  houseId?: number | null
  hasOpeningPosition: boolean
  historyKnown: boolean
  originallyPlaced: number
  openingMortality: number
  openingSold: number
  openingCulled: number
  openingTransferred: number
  openingOther: number
  openingLiveBirds: number
  recordedMortality: number
  correction: number
  lastCountedBirds: number
  lastCountDate?: string | null
  soldBeforeCloseout: number
  liveBirdsAtCloseout: number
  disposedSold: number
  disposedCulled: number
  disposedTransferred: number
  reopenedAt?: string | null
  reopenedBy?: string | null
  reopenReason?: string | null
  dispositions: FlockCloseoutDisposition[]
}

/**
 * fnflock_lifetimesummary. Batch, breed, supplier and house ride on the row so
 * a comparison is a grouping of these rows (see groupLifetimeSummaries), never
 * a second definition of profit.
 */
export interface FlockLifetimeSummary {
  flockId: number
  flockName: string
  breed?: string | null
  status: "Active" | "Inactive" | "Pending" | "Closed" | string
  batchId?: number | null
  batchCode?: string | null
  batchName?: string | null
  supplierId?: number | null
  supplierType?: string | null
  houseId?: number | null
  houseName?: string | null
  startDate: string
  closedDate?: string | null
  daysInProduction: number
  hasOpeningPosition: boolean
  historyKnown: boolean
  originallyPlaced: number
  openingLiveBirds: number
  openingMortality: number
  recordedMortality: number
  birdsSold: number
  birdsCulled: number
  birdsTransferred: number
  finalBirds: number
  trackedMortalityRate?: number | null
  lifetimeMortalityRate?: number | null
  totalEggs: number
  productionDays: number
  eggRevenue: number
  birdSaleRevenue: number
  otherRevenue: number
  totalRevenue: number
  feedConsumedKg: number
  feedCost: number
  medicationCost: number
  birdCost: number
  birdCostRecorded: boolean
  laborCost: number
  otherDirectCost: number
  totalCost: number
  profit: number
  profitPerOriginalBird?: number | null
  revenuePerOriginalBird?: number | null
  feedKgPerDozenEggs?: number | null
}

const lowerFirst = (k: string) => (k ? k.charAt(0).toLowerCase() + k.slice(1) : k)

/** The backend answers in PascalCase; every page here works in camelCase. */
function camel<T>(value: any): T {
  if (Array.isArray(value)) return value.map((v) => camel(v)) as unknown as T
  if (value && typeof value === "object" && !(value instanceof Date)) {
    const out: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(value)) out[lowerFirst(k)] = camel(v)
    return out as T
  }
  return value as T
}

async function call<T>(endpoint: string, init?: RequestInit): Promise<ApiResponse<T>> {
  try {
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    const response = await fetch(url, { ...init, headers: getAuthHeaders() })
    const text = await response.text()
    const body = text ? (() => { try { return JSON.parse(text) } catch { return null } })() : null

    if (!response.ok) {
      // A refused closeout still carries its list of errors.
      return {
        success: false,
        message: (body && (body.message || body.Message)) || (typeof body === "string" ? body : `Request failed (${response.status})`),
        data: body && typeof body === "object" ? camel<T>(body) : undefined,
      }
    }
    return { success: true, data: camel<T>(body), message: body?.message ?? body?.Message }
  } catch (error: any) {
    console.error("[flock-closeout] network error:", error)
    return { success: false, message: error?.message || "Could not reach the server." }
  }
}

export function getFlockCloseoutContext(flockId: number, userId: string, farmId: string) {
  const qs = new URLSearchParams({ userId, farmId }).toString()
  return call<FlockCloseoutContext>(`/flock-closeout/${flockId}/context?${qs}`)
}

export function getFlockCloseoutHistory(flockId: number, farmId: string) {
  const qs = new URLSearchParams({ farmId }).toString()
  return call<FlockCloseoutRecord[]>(`/flock-closeout/${flockId}/history?${qs}`)
}

export function getFlockLifetimeSummaries(farmId: string, opts: { flockId?: number; closedOnly?: boolean } = {}) {
  const qs = new URLSearchParams({ farmId })
  if (opts.flockId != null) qs.set("flockId", String(opts.flockId))
  if (opts.closedOnly) qs.set("closedOnly", "true")
  return call<FlockLifetimeSummary[]>(`/flock-closeout/lifetime?${qs.toString()}`)
}

export function closeFlock(flockId: number, request: FlockCloseoutRequest) {
  const qs = new URLSearchParams({ farmId: request.farmId }).toString()
  return call<FlockCloseoutResult>(`/flock-closeout/${flockId}?${qs}`, {
    method: "POST",
    body: JSON.stringify(request),
  })
}

/**
 * Reopen a closed flock. reverseSales (default true, migration 333) also undoes
 * the closeout's sales: their payments are reversed (kept, marked Reversed),
 * the money leaves the cash account, the sales are removed and the birds come
 * back. false keeps the sales and only unlocks them.
 */
export function reopenFlock(flockId: number, userId: string, farmId: string, reason: string, reverseSales = true) {
  const qs = new URLSearchParams({ farmId }).toString()
  return call<FlockReopenResult>(`/flock-closeout/${flockId}/reverse?${qs}`, {
    method: "POST",
    body: JSON.stringify({ userId, farmId, reason, reverseSales }),
  })
}

// Initial Farm Setup — REST client for PoultryFarmAPI/PoultryFarmSetupController.
//
// Three reads and two writes. The wizard's whole payload goes in ONE call so the
// server can create the farm inside one transaction: a farm half-created is
// worse than none, because nothing tells you which half.

import { buildApiUrl, getAuthHeaders } from "./config"
import { DEFAULT_FARM_API_HOST } from "@/lib/api/default-api-hosts"

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

export interface FarmSetupStatus {
  isComplete: boolean
  farmSetupId: number
  farmId: string
  setupMode: string
  completedBusinessDate?: string | null
  completedAt?: string | null
  completedBy?: string | null
  batchCount: number
  houseCount: number
  flockCount: number
  originallyPlaced: number
  openingLiveBirds: number
  historicalReduction: number
  notes?: string | null
  /** True when the company has no batches, houses or flocks at all. */
  looksEmpty: boolean
  existingBatches: number
  existingHouses: number
  existingFlocks: number
}

export interface OpeningFlockPosition {
  openingPositionId: number
  flockId: number
  flockName?: string | null
  batchId?: number | null
  houseId?: number | null
  effectiveBusinessDate: string
  originallyPlaced: number
  openingLiveBirds: number
  historicalMortality: number
  historicalSold: number
  historicalCulled: number
  historicalTransferred: number
  otherAdjustment: number
  historyKnown: boolean
  startDateEstimated: boolean
  source: string
  notes?: string | null
  createdAt?: string | null
  historicalReduction: number
}

export interface OpeningPositionSummary {
  flockCount: number
  originallyPlaced: number
  openingLiveBirds: number
  historicalReduction: number
  historicalMortality: number
  historicalSold: number
  historicalCulled: number
  historicalTransferred: number
  otherAdjustment: number
  flocksWithUnknownHistory: number
  positions: OpeningFlockPosition[]
}

export interface FarmSetupRowError {
  section: string
  index: number
  field: string
  message: string
}

export interface FarmSetupResult {
  success: boolean
  batchesCreated: number
  batchesReused: number
  housesCreated: number
  housesReused: number
  flocksCreated: number
  openingPositionsCreated: number
  originallyPlaced: number
  openingLiveBirds: number
  historicalReduction: number
  effectiveBusinessDate?: string | null
  errors: FarmSetupRowError[]
  warnings: FarmSetupRowError[]
  message?: string
}

/** A flock the farm already has — read-only context for the allocation step. */
export interface ExistingFlockRow {
  flockId: number
  name: string
  batchId?: number | null
  houseId?: number | null
  houseName?: string | null
  quantity: number
  active: boolean
}

export interface FarmSetupWizardContext {
  status: FarmSetupStatus
  businessDate: string
  batches: any[]
  houses: any[]
  /** What is already placed, so the wizard can show it without offering to edit it. */
  flocks: ExistingFlockRow[]
  existingFlockNames: string[]
  allocatedByBatchId: Record<number, number>
}

const lowerFirst = (s: string) => (s.length > 0 ? s[0].toLowerCase() + s.slice(1) : s)

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

async function read<T>(endpoint: string): Promise<ApiResponse<T>> {
  try {
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    const response = await fetch(url, { headers: getAuthHeaders() })
    const text = await response.text()
    const body = text ? (() => { try { return JSON.parse(text) } catch { return null } })() : null

    if (!response.ok) {
      return { success: false, message: (body && (body.message || body.Message)) || `Request failed (${response.status})` }
    }
    return { success: true, data: camel<T>(body) }
  } catch (error: any) {
    console.error("[v0] Farm setup API network error:", error)
    return { success: false, message: error?.message || "Network error" }
  }
}

async function write<T>(endpoint: string, payload: unknown): Promise<ApiResponse<T>> {
  try {
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    const response = await fetch(url, {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify(payload),
    })
    const text = await response.text()
    const body = text ? (() => { try { return JSON.parse(text) } catch { return null } })() : null

    if (!response.ok) {
      // A rejected setup still carries the per-row errors the grids need.
      return {
        success: false,
        message: (body && (body.message || body.Message)) || `Request failed (${response.status})`,
        data: body ? camel<T>(body) : undefined,
      }
    }
    return { success: true, data: camel<T>(body), message: body?.message ?? body?.Message }
  } catch (error: any) {
    console.error("[v0] Farm setup API network error:", error)
    return { success: false, message: error?.message || "Network error" }
  }
}

/** Has this company been set up, and what does it already have? */
export function getFarmSetupStatus(userId: string, farmId: string): Promise<ApiResponse<FarmSetupStatus>> {
  const qs = new URLSearchParams({ userId, farmId }).toString()
  return read<FarmSetupStatus>(`/PoultryFarmSetup/status?${qs}`)
}

/** Everything the wizard needs to open, including the company's business date. */
export function getFarmSetupContext(userId: string, farmId: string): Promise<ApiResponse<FarmSetupWizardContext>> {
  const qs = new URLSearchParams({ userId, farmId }).toString()
  return read<FarmSetupWizardContext>(`/PoultryFarmSetup/context?${qs}`)
}

/**
 * Opening historical mortality, and what has been recorded since, kept apart.
 * Known lifetime mortality is their sum — and never includes the unknown
 * adjustment, because "we don't know what happened to 30 birds" is not 30 deaths.
 */
export function getOpeningPositions(userId: string, farmId: string): Promise<ApiResponse<OpeningPositionSummary>> {
  const qs = new URLSearchParams({ userId, farmId }).toString()
  return read<OpeningPositionSummary>(`/PoultryFarmSetup/opening-positions?${qs}`)
}

/**
 * An unfinished setup, kept against the COMPANY (migration 328).
 *
 * `draft` is the wizard's own draft object as JSON text — the server stores it
 * without reading into it, so the shape can change without a migration.
 */
export interface FarmSetupDraft {
  farmId: string
  draft: string
  step: number
  phase?: string | null
  updatedBy?: string | null
  updatedAt?: string | null
}

export function getFarmSetupDraft(
  userId: string, farmId: string,
): Promise<ApiResponse<{ hasDraft: boolean; draft: FarmSetupDraft | null }>> {
  const qs = new URLSearchParams({ userId, farmId }).toString()
  return read<{ hasDraft: boolean; draft: FarmSetupDraft | null }>(`/PoultryFarmSetup/draft?${qs}`)
}

/** PUT rather than POST: there is one draft per company and this replaces it. */
export async function saveFarmSetupDraft(
  payload: FarmSetupDraft,
): Promise<ApiResponse<{ savedAt: string }>> {
  try {
    const url = IS_BROWSER
      ? buildApiUrl(`/PoultryFarmSetup/draft`)
      : `${DIRECT_API_BASE_URL}/api/PoultryFarmSetup/draft`
    const response = await fetch(url, {
      method: "PUT",
      headers: getAuthHeaders(),
      body: JSON.stringify({
        FarmId: payload.farmId,
        Draft: payload.draft,
        Step: payload.step,
        Phase: payload.phase ?? null,
        UpdatedBy: payload.updatedBy ?? null,
      }),
    })
    const text = await response.text()
    const body = text ? (() => { try { return JSON.parse(text) } catch { return null } })() : null
    if (!response.ok) {
      return { success: false, message: (body && (body.message || body.Message)) || `Request failed (${response.status})` }
    }
    return { success: true, data: camel(body) }
  } catch (error: any) {
    return { success: false, message: error?.message || "Could not reach the server." }
  }
}

export async function deleteFarmSetupDraft(
  userId: string, farmId: string,
): Promise<ApiResponse<{ discarded: boolean }>> {
  try {
    const qs = new URLSearchParams({ userId, farmId }).toString()
    const url = IS_BROWSER
      ? buildApiUrl(`/PoultryFarmSetup/draft?${qs}`)
      : `${DIRECT_API_BASE_URL}/api/PoultryFarmSetup/draft?${qs}`
    const response = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
    if (!response.ok) return { success: false, message: `Request failed (${response.status})` }
    return { success: true, data: { discarded: true } }
  } catch (error: any) {
    return { success: false, message: error?.message || "Could not reach the server." }
  }
}

/** Create the whole farm in one transaction. */
export function completeFarmSetup(payload: unknown): Promise<ApiResponse<FarmSetupResult>> {
  return write<FarmSetupResult>(`/PoultryFarmSetup/complete`, payload)
}

export interface OpeningPositionCorrection {
  userId: string
  farmId: string
  flockId: number
  originallyPlaced: number
  openingLiveBirds: number
  historyKnown: boolean
  historicalMortality: number
  historicalSold: number
  historicalCulled: number
  historicalTransferred: number
  notes?: string
}

/** Restate one flock's day-one numbers. Refused once it has production history. */
export function correctOpeningPosition(correction: OpeningPositionCorrection): Promise<ApiResponse<any>> {
  return write<any>(`/PoultryFarmSetup/opening-positions/correct`, {
    UserId: correction.userId,
    FarmId: correction.farmId,
    FlockId: correction.flockId,
    OriginallyPlaced: correction.originallyPlaced,
    OpeningLiveBirds: correction.openingLiveBirds,
    HistoryKnown: correction.historyKnown,
    HistoricalMortality: correction.historicalMortality,
    HistoricalSold: correction.historicalSold,
    HistoricalCulled: correction.historicalCulled,
    HistoricalTransferred: correction.historicalTransferred,
    Notes: correction.notes ?? null,
  })
}

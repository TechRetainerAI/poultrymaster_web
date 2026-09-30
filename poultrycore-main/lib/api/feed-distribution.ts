// Distribute Feed — client for api/Poultry/feed-distributions (migration 335).
// Posting adds feed lines to each flock's production record through the same
// update an individual edit uses; nothing is computed on this side.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import type { DistributionCandidate, SuggestionBasis } from "@/lib/production/feed-distribution"

export interface FeedAvailability {
  poultryRawMaterialItemId: number
  itemName: string
  category: string | null
  unitOfMeasure: string | null
  usageMethod: "FIFO" | "LIFO" | "HIFO" | string
  availableKg: number
  currentQuantity: number | null
  lotCount: number
  costRecognitionMethod: "EXPENSE_WHEN_PURCHASED" | "EXPENSE_WHEN_CONSUMED" | string | null
  gramsPerBirdPerDay: number | null
  /** The unit the saved rate was typed in (336). */
  rateUnit?: string | null
}

export interface FeedDistribution {
  poultryFeedDistributionId: number
  businessDate: string
  poultryRawMaterialItemId: number
  itemName: string | null
  basis: "Manual" | "Rate" | "RecentAverage"
  gramsPerBirdPerDay: number | null
  rateUnit?: string | null
  totalSuggestedKg: number | null
  totalActualKg: number
  totalCost: number | null
  flockCount: number
  status: "Posted" | "Reversed"
  notes: string | null
  postedBy: string | null
  postedAtUtc: string
  reversedBy: string | null
  reversedAtUtc: string | null
  reversalReason: string | null
}

export interface FeedDistributionLine {
  poultryFeedDistributionLineId: number
  flockId: number
  flockName: string | null
  productionRecordId: number
  birds: number | null
  suggestedKg: number | null
  actualKg: number
  unitCost: number | null
  totalCost: number | null
  notes: string | null
  reversalNote: string | null
}

export interface PostFeedDistributionInput {
  businessDate: string
  itemId: number
  basis: "Manual" | SuggestionBasis
  gramsPerBirdPerDay: number | null
  /** The unit the rate was typed in; gramsPerBirdPerDay is already converted. */
  rateUnit: string | null
  saveRate: boolean
  notes: string | null
  lines: { flockId: number; actualKg: number; suggestedKg: number | null; birds: number | null; notes: string | null }[]
}

/** The API refused because stock no longer covers the distribution. */
export class InsufficientFeedError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "InsufficientFeedError"
  }
}

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(farmApiUrl(path), {
    method,
    headers: getAuthHeaders(),
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const raw = await res.text().catch(() => "")
    let message: string | undefined
    try { message = JSON.parse(raw)?.message } catch { /* not JSON */ }
    if (res.status === 409) throw new InsufficientFeedError(message ?? "Not enough feed in stock.")
    if ((res.status === 400 || res.status === 403 || res.status === 404) && message) throw new Error(message)
    throw new Error(explainHttpError(method, path, res.status, raw))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

export const getFeedAvailability = async (itemId: number) =>
  call<FeedAvailability>("GET", `/Poultry/feed-distributions/availability?farmId=${encodeURIComponent(farmId())}&itemId=${itemId}`)

export const getFeedDistributionCandidates = async (businessDate: string, itemId: number, avgDays = 7) =>
  call<DistributionCandidate[]>(
    "GET",
    `/Poultry/feed-distributions/candidates?farmId=${encodeURIComponent(farmId())}&businessDate=${businessDate}&itemId=${itemId}&avgDays=${avgDays}`,
  )

export const postFeedDistribution = async (input: PostFeedDistributionInput) =>
  call<{ poultryFeedDistributionId: number }>("POST", `/Poultry/feed-distributions`, { ...input, farmId: farmId() })

export const reverseFeedDistribution = async (id: number, reason: string) =>
  call<void>("POST", `/Poultry/feed-distributions/${id}/reversal`, { farmId: farmId(), reason })

export const listFeedDistributions = async (fromDate?: string, toDate?: string) => {
  const qs = new URLSearchParams({ farmId: farmId() })
  if (fromDate) qs.set("fromDate", fromDate)
  if (toDate) qs.set("toDate", toDate)
  return call<FeedDistribution[]>("GET", `/Poultry/feed-distributions?${qs}`)
}

export const getFeedDistributionLines = async (id: number) =>
  call<FeedDistributionLine[]>("GET", `/Poultry/feed-distributions/${id}/lines?farmId=${encodeURIComponent(farmId())}`)

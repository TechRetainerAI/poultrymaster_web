// Feed Usage from stock — client for api/Poultry/feed-usage-entries (migration 389).
// An entry adds feed lines to each flock's production record for the day, the
// same update the production form uses, so stock leaves exactly once. A flock
// with no record yet gets a feed-only record that still counts as missing
// production. Nothing is computed on this side.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import { InsufficientFeedError } from "./feed-distribution"

export { InsufficientFeedError }

/** The flock's production record for the date. */
export type FeedRecordStatus = "None" | "FeedOnly" | "Recorded" | "Duplicate"

export interface FeedUsageCandidate {
  flockId: number
  flockName: string
  batchId: number | null
  batchName: string | null
  houseName: string | null
  recordStatus: FeedRecordStatus
  productionRecordId: number | null
  birds: number | null
  stockFeedKg: number
  /** The feed already on the record, e.g. "wheat brown 40 kg". */
  feedLines: string | null
}

export interface FeedUsageEntry {
  poultryFeedUsageEntryId: number
  businessDate: string
  scope: "Flock" | "Batch"
  batchId: number | null
  batchName: string | null
  splitBasis: "Birds" | "Equal" | "Manual" | null
  totalKg: number
  totalCost: number | null
  flockCount: number
  feedOnlyRecords: number
  status: "Posted" | "Reversed"
  notes: string | null
  postedBy: string | null
  postedAtUtc: string | null
  reversedBy: string | null
  reversedAtUtc: string | null
  reversalReason: string | null
}

export interface FeedUsageEntryLine {
  poultryFeedUsageLineId: number
  flockId: number
  flockName: string | null
  productionRecordId: number
  createdRecord: boolean
  itemId: number
  itemName: string | null
  quantityKg: number
  unitCost: number | null
  totalCost: number | null
  birds: number | null
  reversalNote: string | null
}

/** One feed line on a production record, or an old typed-in row (Legacy, no stock). */
export interface FeedUsageLogRow {
  usageDate: string
  flockId: number
  flockName: string | null
  productionRecordId: number | null
  recordSource: "ManualSingleFlock" | "BatchAllocation" | "FeedUsage" | "Legacy" | string | null
  feedOnly: boolean
  itemId: number | null
  itemName: string | null
  quantityKg: number
  unitCost: number | null
  totalCost: number | null
  entryId: number | null
  distributionId: number | null
  legacyFeedUsageId: number | null
}

export interface PostFeedUsageInput {
  businessDate: string
  scope: "Flock" | "Batch"
  batchId: number | null
  splitBasis: "Birds" | "Equal" | "Manual" | null
  notes: string | null
  lines: { flockId: number; itemId: number; qty: number; birds: number | null }[]
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

const range = (fromDate?: string, toDate?: string) => {
  const qs = new URLSearchParams({ farmId: farmId() })
  if (fromDate) qs.set("fromDate", fromDate)
  if (toDate) qs.set("toDate", toDate)
  return qs
}

export const getFeedUsageCandidates = async (businessDate: string) =>
  call<FeedUsageCandidate[]>(
    "GET",
    `/Poultry/feed-usage-entries/candidates?farmId=${encodeURIComponent(farmId())}&businessDate=${businessDate}`,
  )

export const postFeedUsage = async (input: PostFeedUsageInput) =>
  call<{ poultryFeedUsageEntryId: number }>("POST", `/Poultry/feed-usage-entries`, { ...input, farmId: farmId() })

export const reverseFeedUsage = async (id: number, reason: string) =>
  call<void>("POST", `/Poultry/feed-usage-entries/${id}/reversal`, { farmId: farmId(), reason })

export const listFeedUsageEntries = async (fromDate?: string, toDate?: string) =>
  call<FeedUsageEntry[]>("GET", `/Poultry/feed-usage-entries?${range(fromDate, toDate)}`)

export const getFeedUsageEntryLines = async (id: number) =>
  call<FeedUsageEntryLine[]>("GET", `/Poultry/feed-usage-entries/${id}/lines?farmId=${encodeURIComponent(farmId())}`)

export const getFeedUsageLog = async (fromDate?: string, toDate?: string) =>
  call<FeedUsageLogRow[]>("GET", `/Poultry/feed-usage-entries/log?${range(fromDate, toDate)}`)

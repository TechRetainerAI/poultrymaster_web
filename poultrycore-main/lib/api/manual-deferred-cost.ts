// Manual deferred inventory cost (migration 371, poultry).
//
// Cost for stock the farm already holds that no purchase covers -- e.g. opening
// stock -- recognised into Profit & Loss as the stock is used, exactly like a
// purchase expensed when consumed. No purchase, no supplier, no cash, no change
// to stock. Only the part not yet recognised can be reversed. Owner / admin.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"

export type ManualDeferredEntryType =
  | "OpeningDeferredCost" | "HistoricalDeferredCost" | "CostAdjustment" | "Migration" | "Other"

export const MANUAL_DEFERRED_ENTRY_LABEL: Record<ManualDeferredEntryType, string> = {
  OpeningDeferredCost: "Opening deferred cost",
  HistoricalDeferredCost: "Historical deferred cost",
  CostAdjustment: "Cost adjustment",
  Migration: "Migration",
  Other: "Other",
}

export interface ManualDeferredCostRow {
  entryId: number
  entryNumber: string
  poultryRawMaterialPurchaseId: number
  poultryRawMaterialItemId: number
  itemName: string | null
  unitOfMeasure: string | null
  entryType: ManualDeferredEntryType
  amount: number
  quantity: number
  effectiveDate: string | null
  /** Already on Profit & Loss through usage. */
  recognised: number
  /** Still waiting to be recognised. */
  remaining: number
  remainingQuantity: number
  reason: string
  reference: string | null
  notes: string | null
  status: string
  createdBy: string | null
  createdAt: string | null
  reversedBy: string | null
  reversedAt: string | null
  reversalReason: string | null
  reversedAmount: number | null
}

export interface UncoveredStockRow {
  poultryRawMaterialItemId: number
  itemName: string
  unitOfMeasure: string | null
  currentQuantity: number
  uncoveredQuantity: number
}

function farm(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function call<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders(), ...init })
  const text = await res.text().catch(() => "")
  let data: any = null
  try { data = text ? JSON.parse(text) : null } catch { data = text }
  if (!res.ok) throw new Error((data && data.message) || (typeof data === "string" && data) || `Request failed (${res.status})`)
  return data as T
}

const root = "Poultry/deferred-inventory-costs"

export const listManualDeferredCosts = () =>
  call<ManualDeferredCostRow[]>(`${root}/manual?farmId=${encodeURIComponent(farm())}`)

export const listUncoveredStock = () =>
  call<UncoveredStockRow[]>(`${root}/uncovered-stock?farmId=${encodeURIComponent(farm())}`)

export function createManualDeferredCost(input: {
  poultryRawMaterialItemId: number; amount: number; quantity: number; effectiveDate: string
  entryType: ManualDeferredEntryType; reason: string; reference?: string | null; notes?: string | null
}): Promise<{ entryId: number; entryNumber: string }> {
  const farmId = farm()
  return call(`${root}/manual?farmId=${encodeURIComponent(farmId)}`, { method: "POST", body: JSON.stringify({ ...input, farmId }) })
}

export function reverseManualDeferredCost(entryId: number, reason: string): Promise<{ reversedAmount: number }> {
  const farmId = farm()
  return call(`${root}/manual/${entryId}/reverse?farmId=${encodeURIComponent(farmId)}`, {
    method: "POST", body: JSON.stringify({ farmId, reason }),
  })
}

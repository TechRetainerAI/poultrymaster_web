// Generic Production Records API client.

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

export interface GenericProductionRecord {
  genericProductionRecordId: number
  farmId: string
  genericProductId: number
  productName: string | null
  quantityProduced: number
  productionDate: string
  unitCost: number
  totalCost: number
  batchNumber: string | null
  materialsUsed: string | null
  notes: string | null
  status: string
  reversalReason: string | null
  createdBy: string | null
  reversedBy: string | null
  reversedAt: string | null
  createdAt: string
}

export interface CreateProductionRecordInput {
  genericProductId: number
  quantityProduced: number
  productionDate?: string | null
  unitCost?: number
  batchNumber?: string | null
  materialsUsed?: string | null
  notes?: string | null
}

function farmBase(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return `/generic-company/${encodeURIComponent(farmId)}`
}

function currentFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return farmId
}

export async function getProductionRecords(status?: string | null): Promise<GenericProductionRecord[]> {
  const qs = status ? `?status=${encodeURIComponent(status)}` : ""
  const r = await fetch(buildApiUrl(`${farmBase()}/production-records${qs}`), {
    method: "GET", headers: getAuthHeaders(),
  })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("GET", `production-records`, r.status, text))
  }
  return (await r.json()) as GenericProductionRecord[]
}

export async function createProductionRecord(input: CreateProductionRecordInput): Promise<number> {
  const r = await fetch(buildApiUrl(`${farmBase()}/production-records`), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ ...input, farmId: currentFarmId() }),
  })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("POST", `production-records`, r.status, text))
  }
  const data = await r.json()
  return data?.genericProductionRecordId ?? 0
}

export async function reverseProductionRecord(id: number, reason: string): Promise<void> {
  const r = await fetch(buildApiUrl(`${farmBase()}/production-records/${id}/reverse`), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ farmId: currentFarmId(), reason }),
  })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("POST", `production-records/${id}/reverse`, r.status, text))
  }
}

import { getAuthHeaders } from './config'

// =============================================================================
// Batch-level production records + allocation workflow (migration 156).
// A batch record captures TOTAL production for a group of flocks and stays inert
// (Pending Allocation) until an allocation distributes those totals across the
// included flocks and is Posted into flock-level ProductionRecords.
// =============================================================================

export type BatchSelectionType = 'SpecificBatch' | 'AllBatches' | 'CustomBatch'

export type BatchStatus =
  | 'Draft'
  | 'PendingAllocation'
  | 'Allocated'
  | 'Posted'
  | 'Reversed'
  | 'Cancelled'

export type AllocationMethod = 'Manual' | 'ByBirdCount' | 'ByPreviousProduction' | 'EqualSplit'

/** A flock frozen into the batch's allocation scope. */
export interface ProductionBatchIncludedFlock {
  flockId: number
  flockName?: string | null
  birdBatchId?: number | null
}

/** A batch-level feed or medication usage line. */
export interface ProductionBatchUsageLine {
  id?: number | null
  itemId: number
  itemName?: string | null
  qty: number
  unitCost?: number | null
  totalCost?: number | null
  method?: string | null
}

/** A flattened feed/medication line inside one allocation row. */
export interface ProductionBatchAllocationUsageLine {
  /** Id of the parent batch-level usage line this maps to. */
  batchUsageId?: number | null
  itemId: number
  itemName?: string | null
  qty: number
  unitCost?: number | null
  totalCost?: number | null
}

/** One flock's allocation of the batch totals. */
export interface ProductionBatchAllocation {
  id?: number | null
  flockId: number
  flockName?: string | null
  allocationMethod?: AllocationMethod | string | null
  ageInWeeks?: number | null
  ageInDays?: number | null
  birdsBefore?: number | null
  deaths: number
  birdsAfter?: number | null
  firstPickEggs: number
  secondPickEggs: number
  thirdPickEggs: number
  fourthPickEggs: number
  brokenEggs?: number | null
  meatyEggs?: number | null
  softEggs?: number | null
  lostEggs?: number | null
  totalEggs: number
  eggPercentage?: number | null
  feedKg?: number | null
  totalFeedCost?: number | null
  totalMedicationCost?: number | null
  totalCostOfProduction?: number | null
  notes?: string | null
  generatedProductionRecordId?: number | null
  feeds?: ProductionBatchAllocationUsageLine[]
  medications?: ProductionBatchAllocationUsageLine[]
}

export interface ProductionBatchRecord {
  id: number
  farmId: string
  userId?: string | null
  createdBy?: string | null
  updatedBy?: string | null
  postedBy?: string | null
  batchSelectionType: BatchSelectionType
  selectedBirdBatchId?: number | null
  batchName?: string | null
  productionDate: string
  ageInWeeks?: number | null
  ageInDays?: number | null
  ageDisplay?: string | null
  firstPickCrates?: number | null
  firstPickLooseEggs?: number | null
  firstPickTotal: number
  secondPickCrates?: number | null
  secondPickLooseEggs?: number | null
  secondPickTotal: number
  thirdPickCrates?: number | null
  thirdPickLooseEggs?: number | null
  thirdPickTotal: number
  fourthPickCrates?: number | null
  fourthPickLooseEggs?: number | null
  fourthPickTotal: number
  brokenEggs?: number | null
  meatyEggs?: number | null
  softEggs?: number | null
  lostEggs?: number | null
  totalEggs: number
  feedKg?: number | null
  deaths: number
  birdsLeft?: number | null
  eggGrade?: string | null
  feedType?: string | null
  medication?: string | null
  totalFeedCost?: number | null
  totalMedicationCost?: number | null
  totalCostOfProduction?: number | null
  status: BatchStatus
  notes?: string | null
  createdDate: string
  updatedDate?: string | null
  postedDate?: string | null
  includedFlocks: ProductionBatchIncludedFlock[]
  feeds: ProductionBatchUsageLine[]
  medications: ProductionBatchUsageLine[]
  allocations: ProductionBatchAllocation[]
}

export interface ProductionBatchRecordInput {
  id?: number
  farmId: string
  userId: string
  createdBy?: string
  updatedBy?: string
  batchSelectionType: BatchSelectionType
  selectedBirdBatchId?: number | null
  batchName?: string | null
  productionDate: string
  ageInWeeks?: number | null
  ageInDays?: number | null
  ageDisplay?: string | null
  firstPickCrates?: number | null
  firstPickLooseEggs?: number | null
  firstPickTotal: number
  secondPickCrates?: number | null
  secondPickLooseEggs?: number | null
  secondPickTotal: number
  thirdPickCrates?: number | null
  thirdPickLooseEggs?: number | null
  thirdPickTotal: number
  fourthPickCrates?: number | null
  fourthPickLooseEggs?: number | null
  fourthPickTotal: number
  brokenEggs?: number | null
  meatyEggs?: number | null
  softEggs?: number | null
  lostEggs?: number | null
  totalEggs: number
  feedKg?: number | null
  deaths: number
  birdsLeft?: number | null
  eggGrade?: string | null
  feedType?: string | null
  medication?: string | null
  totalFeedCost?: number | null
  totalMedicationCost?: number | null
  totalCostOfProduction?: number | null
  status?: BatchStatus
  notes?: string | null
  includedFlocks: ProductionBatchIncludedFlock[]
  feeds: ProductionBatchUsageLine[]
  medications: ProductionBatchUsageLine[]
}

const BASE = '/api/proxy/ProductionBatchRecord'

async function readError(response: Response): Promise<string> {
  try {
    const text = await response.text()
    try {
      const j = JSON.parse(text)
      return j.message || j.error || j.title || text
    } catch {
      return text
    }
  } catch {
    return `Server error (${response.status})`
  }
}

export async function getBatchProductionRecords(userId: string, farmId: string) {
  try {
    const url = `${BASE}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    const response = await fetch(url, {
      method: 'GET',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    })
    if (!response.ok) {
      return { success: false, message: await readError(response), data: [] as ProductionBatchRecord[] }
    }
    const data = (await response.json()) as ProductionBatchRecord[]
    return { success: true, message: 'ok', data }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message: `Failed to load batch production records: ${message}`, data: [] as ProductionBatchRecord[] }
  }
}

export async function getBatchProductionRecord(id: number, farmId: string) {
  try {
    const url = `${BASE}/${id}?farmId=${encodeURIComponent(farmId)}`
    const response = await fetch(url, {
      method: 'GET',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    })
    if (!response.ok) {
      return { success: false, message: await readError(response), data: null as ProductionBatchRecord | null }
    }
    const data = (await response.json()) as ProductionBatchRecord
    return { success: true, message: 'ok', data }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message, data: null as ProductionBatchRecord | null }
  }
}

export async function createBatchProductionRecord(input: ProductionBatchRecordInput) {
  try {
    const payload = { ...input, createdBy: input.createdBy ?? input.userId, updatedBy: input.updatedBy ?? input.userId }
    const response = await fetch(BASE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...getAuthHeaders() },
      body: JSON.stringify(payload),
    })
    if (!response.ok) {
      return { success: false, message: await readError(response), data: null as ProductionBatchRecord | null }
    }
    const data = (await response.json().catch(() => null)) as ProductionBatchRecord | null
    return { success: true, message: 'Batch production record saved', data }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message, data: null as ProductionBatchRecord | null }
  }
}

export async function updateBatchProductionRecord(id: number, input: ProductionBatchRecordInput) {
  try {
    const payload = { ...input, id, createdBy: input.createdBy ?? input.userId, updatedBy: input.updatedBy ?? input.userId }
    const response = await fetch(`${BASE}/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...getAuthHeaders() },
      body: JSON.stringify(payload),
    })
    if (!response.ok) {
      return { success: false, message: await readError(response) }
    }
    return { success: true, message: 'Batch production record updated' }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message }
  }
}

export async function deleteBatchProductionRecord(id: number, userId: string, farmId: string) {
  try {
    const url = `${BASE}/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    const response = await fetch(url, {
      method: 'DELETE',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json', ...getAuthHeaders() },
    })
    if (!response.ok) {
      return { success: false, message: await readError(response) }
    }
    return { success: true, message: 'Batch production record deleted' }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message }
  }
}

/** Save (replace) allocation rows. `status` defaults to 'Allocated' server-side. */
export async function saveBatchAllocation(
  id: number,
  farmId: string,
  body: { updatedBy: string; status?: BatchStatus; allocations: ProductionBatchAllocation[] },
) {
  try {
    const url = `${BASE}/${id}/allocation?farmId=${encodeURIComponent(farmId)}`
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...getAuthHeaders() },
      body: JSON.stringify(body),
    })
    if (!response.ok) {
      return { success: false, message: await readError(response), data: null as ProductionBatchRecord | null }
    }
    const data = (await response.json().catch(() => null)) as ProductionBatchRecord | null
    return { success: true, message: 'Allocation saved', data }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message, data: null as ProductionBatchRecord | null }
  }
}

export async function setBatchStatus(id: number, farmId: string, status: BatchStatus, userId: string) {
  try {
    const url = `${BASE}/${id}/status?farmId=${encodeURIComponent(farmId)}`
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...getAuthHeaders() },
      body: JSON.stringify({ status, userId }),
    })
    if (!response.ok) {
      return { success: false, message: await readError(response) }
    }
    return { success: true, message: `Status set to ${status}` }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message }
  }
}

/** Post the allocation — creates flock records + inventory/bird side-effects (transactional). */
export async function postBatchAllocation(id: number, farmId: string, userId: string) {
  try {
    const url = `${BASE}/${id}/post?farmId=${encodeURIComponent(farmId)}`
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...getAuthHeaders() },
      body: JSON.stringify({ userId }),
    })
    if (!response.ok) {
      return { success: false, message: await readError(response), data: null as ProductionBatchRecord | null }
    }
    const data = (await response.json().catch(() => null)) as ProductionBatchRecord | null
    return { success: true, message: 'Batch allocation posted', data }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message, data: null as ProductionBatchRecord | null }
  }
}

/**
 * Delete the allocation only, keeping the parent batch record. When the batch is
 * Posted the server reverses the generated flock records (undoing inventory + bird
 * effects) before removing the rows; the batch returns to Pending Allocation.
 */
export async function deleteBatchAllocation(id: number, farmId: string, userId: string) {
  try {
    const url = `${BASE}/${id}/allocation?farmId=${encodeURIComponent(farmId)}&userId=${encodeURIComponent(userId)}`
    const response = await fetch(url, {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...getAuthHeaders() },
    })
    if (!response.ok) {
      return { success: false, message: await readError(response), data: null as ProductionBatchRecord | null }
    }
    const data = (await response.json().catch(() => null)) as ProductionBatchRecord | null
    return { success: true, message: 'Allocation deleted', data }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message, data: null as ProductionBatchRecord | null }
  }
}

/** Reverse a posted batch — deletes the generated flock records + their side-effects. */
export async function reverseBatchProduction(id: number, farmId: string, userId: string) {
  try {
    const url = `${BASE}/${id}/reverse?farmId=${encodeURIComponent(farmId)}`
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...getAuthHeaders() },
      body: JSON.stringify({ userId }),
    })
    if (!response.ok) {
      return { success: false, message: await readError(response), data: null as ProductionBatchRecord | null }
    }
    const data = (await response.json().catch(() => null)) as ProductionBatchRecord | null
    return { success: true, message: 'Batch reversed', data }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Network error'
    return { success: false, message, data: null as ProductionBatchRecord | null }
  }
}

// ---- Small display helpers shared by the list + allocation pages ----

export const BATCH_STATUS_LABELS: Record<BatchStatus, string> = {
  Draft: 'Draft',
  PendingAllocation: 'Pending Allocation',
  Allocated: 'Allocated',
  Posted: 'Posted',
  Reversed: 'Reversed',
  Cancelled: 'Cancelled',
}

export function batchNameLabel(r: Pick<ProductionBatchRecord, 'batchSelectionType' | 'batchName'>): string {
  if (r.batchName && r.batchName.trim()) return r.batchName.trim()
  if (r.batchSelectionType === 'AllBatches') return 'All Batches'
  if (r.batchSelectionType === 'CustomBatch') return 'Custom Batch'
  return 'Batch'
}

/** Secondary line under the batch name — the included flocks / scope. */
export function batchScopeLabel(r: ProductionBatchRecord): string {
  if (r.batchSelectionType === 'AllBatches') return 'All active flocks'
  const names = (r.includedFlocks || []).map((f) => f.flockName || `Flock ${f.flockId}`)
  if (names.length === 0) return '—'
  if (names.length <= 4) return names.join(', ')
  return `${names.slice(0, 4).join(', ')} +${names.length - 4} more`
}

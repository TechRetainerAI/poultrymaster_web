// Batch Bird Reconciliation (migration 413): where every bird a batch bought
// went, postings that explain birds never placed in a flock, flock-to-flock
// transfers and the repair of bird movements written before 413.
import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import type { ReconciliationLine } from "@/lib/flocks/bird-reconciliation"

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function call<T>(path: string, method: "GET" | "POST" = "GET", body?: unknown): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  const text = await res.text().catch(() => "")
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    // The API answers rule failures as { message } -- show that sentence as is.
    try {
      const j = JSON.parse(text)
      if (j?.message) throw new Error(j.message)
    } catch (e) {
      if (e instanceof Error && !(e instanceof SyntaxError)) throw e
    }
    throw new Error(explainHttpError(method, path, res.status, text))
  }
  return (text ? JSON.parse(text) : undefined) as T
}

export type BatchReconciliationStatus = "FullyAccountedFor" | "NeedsReconciliation" | "OverAllocated"

export interface BatchBirdReconciliationRow {
  batchId: number
  batchCode: string
  batchName: string
  startDate: string
  isHistorical: boolean
  originalBirds: number
  originallyAllocated: number
  flockCount: number
  batchSold: number
  /** Birds sold out of the batch's flocks (opening history + posted sales). Absent on an older API. */
  flockSold?: number
  batchMortality: number
  batchCulled: number
  batchTransferred: number
  batchOtherRemovals: number
  batchAdditions: number
  /** Birds of the batch in no flock (derived). */
  unallocatedPool: number
  /** Of those, the ones confirmed alive. */
  unallocatedLive: number
  /** Positive = not explained yet; negative = more placed than bought. */
  unexplained: number
  flockLiveBirds: number
  totalLiveBirds: number
  flockHistoricalReductions: number
  historicalSaleBirds: number
  historicalSaleValue: number
  historicalReceived: number
  historicalOwed: number
  status: BatchReconciliationStatus
  lastReconciledAt: string | null
  lastReconciliationNo: string | null
}

export interface BatchReconciliationFlock {
  flockId: number
  flockName: string
  isClosed: boolean
  isDeleted: boolean
  originallyPlaced: number
  hasOpeningPosition: boolean
  historicalMortality: number
  historicalSold: number
  historicalCulled: number
  historicalTransferred: number
  historicalOther: number
  openingLiveBirds: number
  recordedMortality: number
  birdsSold: number
  birdsCulled: number
  birdsTransferred: number
  productionRecordCount: number
  quantityAdjustments: number
  currentLiveBirds: number
}

export interface BatchReconciliationMovement {
  birdAdjustmentId: number
  date: string
  scope: "Flock" | "BatchUnallocated"
  appliedTo: string
  flockId: number | null
  flockName: string | null
  reason: string | null
  movementType: string
  quantity: number
  birdsBefore: number
  birdsAfter: number
  note: string | null
  sourceType: string | null
  sourceId: number | null
  reversesId: number | null
  reversedById: number | null
  createdBy: string | null
  createdAt: string
}

export interface HistoricalBirdSale {
  historicalSaleId: number
  saleDate: string
  scope: "Flock" | "BatchUnallocated"
  flockId: number | null
  flockName: string | null
  birds: number
  pricePerBird: number | null
  totalValue: number | null
  valueUnknown: boolean
  customerId: number | null
  customerName: string | null
  amountReceived: number
  amountOwed: number
  financialTreatment: "QuantityOnly" | "HistoricalPaid" | "HistoricalReceivable" | "HistoricalUnpaidNotTracked"
  debtId: number | null
  debtNumber: string | null
  debtCreated: boolean
  reference: string | null
  notes: string | null
  status: "Posted" | "Reversed"
  reconciliationId: number | null
}

export interface BatchReconciliationPosting {
  reconciliationid: number
  reconciliationno: string
  asofdate: string
  source: string
  unallocatedbefore: number
  removedbirds: number
  unallocatedafter: number
  stillunallocatedlive: number
  unexplainedbirds: number
  status: "Reconciled" | "Unexplained" | "Reversed"
  notes: string | null
  createdby: string | null
  createdat: string
  reversedat: string | null
  reversalreason: string | null
}

export interface BatchReconciliationDetail {
  /** The summary row (snake/lowercase keys as the database returns them). */
  summary: Record<string, unknown> | null
  flocks: BatchReconciliationFlock[]
  movements: BatchReconciliationMovement[]
  historicalSales: HistoricalBirdSale[]
  reconciliations: BatchReconciliationPosting[]
}

export interface BatchReconciliationResult {
  reconciliationId: number
  reconciliationNo: string
  repeated: boolean
  unallocatedBefore?: number
  removedBirds?: number
  unallocatedAfter?: number
  stillUnallocatedLive?: number
  unexplainedBirds?: number
  status?: "Reconciled" | "Unexplained"
  historicalSaleBirds?: number
  historicalSaleValue?: number
  historicalReceived?: number
  historicalOwed?: number
  debtsCreated?: number
  newCashMovement?: number
  currentPeriodRevenue?: number
  currentPeriodExpense?: number
}

export const getBatchBirdReconciliation = () =>
  call<BatchBirdReconciliationRow[]>(`/Poultry/bird-reconciliation/batches?farmId=${encodeURIComponent(farmId())}`)

export const getBatchBirdReconciliationDetail = (batchId: number) =>
  call<BatchReconciliationDetail>(`/Poultry/bird-reconciliation/batches/${batchId}?farmId=${encodeURIComponent(farmId())}`)

export interface PostBatchReconciliationInput {
  batchId: number
  asOfDate?: string | null
  lines: ReconciliationLine[]
  stillUnallocatedLive: number
  notes?: string | null
  source?: string | null
  requestKey: string
}

export const postBatchReconciliation = (input: PostBatchReconciliationInput) =>
  call<BatchReconciliationResult>(`/Poultry/bird-reconciliation/batches/${input.batchId}/reconcile`, "POST", {
    farmId: farmId(),
    batchId: input.batchId,
    asOfDate: input.asOfDate || null,
    lines: input.lines,
    stillUnallocatedLive: input.stillUnallocatedLive,
    notes: input.notes ?? null,
    source: input.source ?? "Batch",
    requestKey: input.requestKey,
  })

export const reverseBatchReconciliation = (reconciliationId: number, reason: string) =>
  call<{ reconciliationId: number; reconciliationNo: string; status: string; unallocatedNow: number }>(
    `/Poultry/bird-reconciliation/reconciliations/${reconciliationId}/reverse`, "POST", { farmId: farmId(), reason })

export const postBirdTransfer = (input: { fromFlockId: number; toFlockId: number; quantity: number; effectiveDate?: string | null; note?: string | null; requestKey: string }) =>
  call<{ outAdjustmentId: number; inAdjustmentId: number; farmLiveBirds: number }>(
    `/Poultry/bird-reconciliation/transfers`, "POST", { ...input, farmId: farmId() })

export interface BirdRepairDiagnosticRow {
  farmId: string
  checkCode: string
  severity: "Fix" | "Review" | "Info"
  ledgerRowId: number | null
  openingPositionId: number | null
  batchId: number | null
  flockId: number | null
  flockName: string | null
  currentValue: string | null
  expectedValue: string | null
  missingRelationship: string | null
  proposedCorrection: string | null
  doubleApplicationRisk: string | null
  confidence: "Verified" | "Unresolved" | "Review"
  evidence: string | null
  autoRepairable: boolean
}

export const diagnoseBirdMovements = () =>
  call<BirdRepairDiagnosticRow[]>(`/Poultry/bird-reconciliation/repair/diagnose?farmId=${encodeURIComponent(farmId())}`)

export const applyBirdMovementRepair = (dryRun: boolean) =>
  call<{ checkCode: string; ledgerRowId: number; batchId: number | null; flockId: number | null; applied: boolean; evidence: string | null }[]>(
    `/Poultry/bird-reconciliation/repair/apply`, "POST", { farmId: farmId(), dryRun })

// ---- Existing flock (Issue 5) ---------------------------------------------

export interface ExistingFlockHistoryInput {
  originallyPlaced: number
  currentLiveBirds: number
  historyKnown: boolean
  historicalMortality: number
  historicalSold: number
  historicalCulled: number
  historicalTransferred: number
  notes?: string | null
}

/** POST api/Flock/existing: the flock, what was placed, what stands now, and why. */
export const createExistingFlock = (flock: Record<string, unknown>, history: ExistingFlockHistoryInput, asOfDate: string, source: string) => {
  const { userId } = getUserContext()
  return call<{ flockId: number; name: string; quantity: number }>(`/Flock/existing`, "POST", {
    flock: { ...flock, farmId: farmId(), userId: (flock.userId as string) || userId },
    history,
    asOfDate,
    source,
  })
}

/** This company's customers, for the "who still owes" pick on a historical sale. */
export async function listReconciliationCustomers(): Promise<{ customerId: number; name: string }[]> {
  const { userId } = getUserContext()
  const rows = await call<any[]>(`/Customer?userId=${encodeURIComponent(userId || "")}&farmId=${encodeURIComponent(farmId())}`)
  return (rows ?? []).map((c) => ({ customerId: Number(c.customerId ?? c.CustomerId), name: String(c.name ?? c.Name ?? "") }))
    .filter((c) => c.customerId > 0)
}

// Egg Sorting Workspace — client for api/Poultry/egg-sorting (migrations 341-343).
// Sorting turns Unsorted egg stock into sized stock; it never creates eggs. All
// availability, locking and ledger work happens in the database.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export type SortingMode = "ByPick" | "Combined"
export type SortingStatus = "Draft" | "Posted" | "Reversed"
export type SortingLineType = "SizedOutput" | "Reject" | "Breakage" | "OtherLoss"
export type ClosingPolicy = "Off" | "Warning" | "Blocking"

export interface EggSortingSettings {
  farmId: string
  enableEggSorting: boolean
  closingPolicy: ClosingPolicy
  isCustomised: boolean
  updatedBy: string | null
  updatedAtUtc: string | null
  /** Eggs in one crate for this farm (344; 30 by default). */
  eggsPerCrate: number
  /** Default selling price per crate of Unsorted / General eggs (344). */
  unsortedPricePerCrate: number | null
}

/** Unsorted (eggSizeId null) or a size, with eggs on hand. */
export interface EggClass {
  poultryProductId: number
  eggSizeId: number | null
  name: string
  classKind: "Unsorted" | "Size"
  sortOrder: number
  isActive: boolean
  onHand: number
  /** Default selling price per crate (344); null = none set. */
  pricePerCrate?: number | null
}

export type AdjustmentKind = "Breakage" | "Loss" | "Stocktake" | "Correction"

export interface EggSortingAuditRow {
  auditId: number
  entity: "Sorting" | "EggSize" | "Settings" | "Sale" | "Adjustment" | string
  entityId: number | null
  action: string
  actor: string | null
  /** JSON object text; shape depends on the action. */
  details: string | null
  atUtc: string
}

export interface EggSortingPick {
  productionRecordId: number
  flockId: number
  flockName: string | null
  batchName: string | null
  houseName: string | null
  productionDate: string
  pickNumber: number
  pickGross: number
  pickSorted: number
  pickLeft: number
  /** What a by-pick sorting may take now: LEAST(pick left, record left). */
  available: number
  recordGross: number
  recordCollectionLoss: number
  recordSaleable: number
  recordSorted: number
  recordLeft: number
  byPickSorted: number
}

export interface EggSortingSummary {
  businessDate: string
  unsortedOnHand: number
  sizedOnHand: number
  sortedToday: number
  sizedCreatedToday: number
  lossToday: number
  sessionsToday: number
  productionLeft: number
  recordsWithLeft: number
  oldestLeftDate: string | null
}

export interface EggSortingLine {
  lineId?: number | null
  lineType: SortingLineType
  eggSizeId: number | null
  sizeName?: string | null
  quantity: number
  notes?: string | null
}

export interface EggSortingSource {
  productionRecordId: number
  pickNumber: number
  productionDate: string
  quantity: number
}

export interface EggSortingSession {
  sessionId: number
  sessionNo: string
  sortingMode: SortingMode
  flockId: number
  flockName: string | null
  productionRecordId: number | null
  pickNumber: number | null
  scopeRecordIds: number[]
  sortingDate: string
  status: SortingStatus
  inputQuantity: number
  outputQuantity: number
  lossQuantity: number
  notes: string | null
  createdBy: string | null
  createdAtUtc: string
  postedBy: string | null
  postedAtUtc: string | null
  reversedBy: string | null
  reversedAtUtc: string | null
  reversalReason: string | null
  firstProductionDate: string | null
  lastProductionDate: string | null
  lines: EggSortingLine[]
  sources: EggSortingSource[]
}

export interface SaveSortingInput {
  sortingMode: SortingMode
  sortingDate: string
  productionRecordIds: number[]
  pickNumber: number | null
  lines: EggSortingLine[]
  notes: string | null
  clientRequestId: string | null
  post: boolean
}

export interface EggCompositionRow {
  groupKey: string
  groupLabel: string
  groupSort: string
  /** The flock the row belongs to (migration 350); absent before it. */
  flockId?: number | null
  flockName?: string | null
  lineType: SortingLineType
  eggSizeId: number | null
  sizeName: string | null
  sizeSort: number
  quantity: number
  sessions: number
  combinedSessions: number
}

export interface EggCarryoverRow {
  productionDate: string
  /** The flock the row belongs to (migration 350); absent before it. */
  flockId?: number | null
  flockName?: string | null
  records: number
  gross: number
  collectionLoss: number
  saleable: number
  sorted: number
  leftUnsorted: number
}

export interface EggLedgerRow {
  transactionId: number
  createdAtUtc: string
  businessDate: string
  txnType: string
  poultryProductId: number
  className: string
  classKind: "Unsorted" | "Size"
  quantityIn: number
  quantityOut: number
  runningBalance: number
  relatedId: number | null
  note: string | null
  createdBy: string | null
  flockId: number | null
  flockName: string | null
  productionRecordId: number | null
  pickNumbers: string | null
  sortingSessionNo: string | null
  saleId: number | null
  customerName: string | null
  saleGroupNo: string | null
  reference: string | null
}

export interface ProductionDuplicateGroup {
  flockId: number
  flockName: string | null
  productionDate: string
  recordCount: number
  recordIds: number[]
  totalEggs: number
  grades: string | null
}

export type CompositionGroupBy = "productiondate" | "sortingdate" | "flock" | "batch" | "age" | "pick"

/** The database refused because the eggs are no longer there (or were sold). */
export class EggSortingConflictError extends Error {
  constructor(message: string, readonly code: string | null) {
    super(message)
    this.name = "EggSortingConflictError"
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
    let code: string | null = null
    try { const j = JSON.parse(raw); message = j?.message; code = j?.code ?? null } catch { /* not JSON */ }
    if (res.status === 409) throw new EggSortingConflictError(message ?? "The eggs are no longer available.", code)
    if ((res.status === 400 || res.status === 403 || res.status === 404) && message) throw new Error(message)
    throw new Error(explainHttpError(method, path, res.status, raw))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

const base = "/Poultry/egg-sorting"
const q = (extra: Record<string, string | number | boolean | null | undefined> = {}) => {
  const qs = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(extra)) if (v !== null && v !== undefined && v !== "") qs.set(k, String(v))
  return qs.toString()
}

export const getEggSortingSettings = () => call<EggSortingSettings>("GET", `${base}/settings?${q()}`)

export const saveEggSortingSettings = (input: {
  enableEggSorting: boolean
  closingPolicy: ClosingPolicy
  eggsPerCrate: number
  unsortedPricePerCrate: number | null
}) => call<void>("PUT", `${base}/settings`, { farmId: farmId(), ...input })

export const setEggSizePrice = (eggSizeId: number, pricePerCrate: number | null) =>
  call<void>("PUT", `${base}/sizes/${eggSizeId}/price`, { farmId: farmId(), pricePerCrate })

/** Breakage / loss (eggs out) or stock-take / correction (signed) against one class. */
export const adjustEggClass = (input: { poultryProductId: number; kind: AdjustmentKind; quantity: number; reason: string }) =>
  call<{ transactionId: number }>("POST", `${base}/adjustments`, { farmId: farmId(), ...input })

export const getEggSortingAudit = (opts: { entity?: string; entityId?: number; limit?: number } = {}) =>
  call<EggSortingAuditRow[]>("GET", `${base}/audit?${q({ entity: opts.entity, entityId: opts.entityId, limit: opts.limit ?? 200 })}`)

export const getEggClasses = (opts: { includeInactive?: boolean; ensure?: boolean } = {}) =>
  call<EggClass[]>("GET", `${base}/classes?${q({ includeInactive: opts.includeInactive ?? false, ensure: opts.ensure ?? false })}`)

export const saveEggSize = (input: { eggSizeId: number | null; name: string; sortOrder: number | null; isActive: boolean }) =>
  call<{ eggSizeId: number }>("PUT", `${base}/sizes`, { farmId: farmId(), ...input })

export const getEggSortingPicks = (opts: { fromDate?: string; toDate?: string; flockId?: number | null; recordIds?: number[] }) => {
  const qs = new URLSearchParams(q({ fromDate: opts.fromDate, toDate: opts.toDate, flockId: opts.flockId ?? undefined }))
  for (const id of opts.recordIds ?? []) qs.append("recordIds", String(id))
  return call<EggSortingPick[]>("GET", `${base}/picks?${qs}`)
}

export const getEggSortingSummary = (date?: string) => call<EggSortingSummary>("GET", `${base}/summary?${q({ date })}`)

export const listEggSortingSessions = (opts: { fromDate?: string; toDate?: string; status?: SortingStatus; recordId?: number } = {}) =>
  call<EggSortingSession[]>("GET", `${base}/sessions?${q(opts)}`)

export const getEggSortingSession = (id: number) => call<EggSortingSession>("GET", `${base}/sessions/${id}?${q()}`)

export const saveEggSorting = (input: SaveSortingInput, sessionId?: number | null) =>
  sessionId
    ? call<{ sessionId: number }>("PUT", `${base}/sessions/${sessionId}`, { ...input, farmId: farmId() })
    : call<{ sessionId: number }>("POST", `${base}/sessions`, { ...input, farmId: farmId() })

export const discardEggSorting = (id: number) => call<void>("DELETE", `${base}/sessions/${id}?${q()}`)

export const reverseEggSorting = (id: number, reason: string) =>
  call<void>("POST", `${base}/sessions/${id}/reversal`, { farmId: farmId(), reason })

export const getEggComposition = (fromDate: string, toDate: string, groupBy: CompositionGroupBy, flockId?: number | null) =>
  call<EggCompositionRow[]>("GET", `${base}/composition?${q({ fromDate, toDate, groupBy, flockId: flockId ?? undefined })}`)

export const getEggCarryover = (fromDate: string, toDate: string, flockId?: number | null) =>
  call<EggCarryoverRow[]>("GET", `${base}/carryover?${q({ fromDate, toDate, flockId: flockId ?? undefined })}`)

export const getEggLedger = (opts: { fromDate?: string; toDate?: string; productId?: number | null } = {}) =>
  call<EggLedgerRow[]>("GET", `${base}/ledger?${q({ fromDate: opts.fromDate, toDate: opts.toDate, productId: opts.productId ?? undefined })}`)

export const getProductionDuplicates = () => call<ProductionDuplicateGroup[]>("GET", `${base}/production-duplicates?${q()}`)

// Treatment Campaigns — client for api/Poultry/treatment-campaigns (migration
// 339). Recording a day adds medication lines to each flock's production record
// through the same update an individual edit uses; nothing is computed here.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import type { DoseBasis, TreatmentDayRow } from "@/lib/production/treatment-campaigns"

export interface MedicationProduct {
  poultryRawMaterialItemId: number
  itemName: string
  category: string | null
  unitOfMeasure: string | null
  usageMethod: string
  isActive: boolean
  availableQuantity: number
  lotCount: number
  costRecognitionMethod: "EXPENSE_WHEN_PURCHASED" | "EXPENSE_WHEN_CONSUMED" | string | null
  doseQuantity: number | null
  doseBasis: DoseBasis | null
  eggWithdrawalDays: number | null
  meatWithdrawalDays: number | null
  withdrawalNotes: string | null
}

export interface TreatmentFlockOption {
  flockId: number
  flockName: string
  batchName: string | null
  houseName: string | null
  birds: number | null
}

export interface TreatmentCampaign {
  poultryTreatmentCampaignId: number
  name: string
  poultryRawMaterialItemId: number
  itemName: string | null
  unitOfMeasure: string | null
  reason: string | null
  startDate: string
  endDate: string
  plannedDays: number
  doseInstructions: string | null
  doseQuantity: number | null
  doseBasis: DoseBasis | null
  doseSource: "User" | "Product" | "None"
  eggWithdrawalDays: number | null
  meatWithdrawalDays: number | null
  withdrawalNotes: string | null
  notes: string | null
  lifecycle: "Open" | "Completed" | "Cancelled"
  status: "Scheduled" | "InProgress" | "Completed" | "Cancelled"
  companyToday: string
  flockCount: number
  postedDays: number
  totalQuantity: number
  totalCost: number | null
  lastPostedDate: string | null
  eggWithdrawalUntil: string | null
  meatWithdrawalUntil: string | null
  createdBy: string | null
  createdAtUtc: string
  completedBy: string | null
  completedAtUtc: string | null
  cancelledBy: string | null
  cancelledAtUtc: string | null
  cancelReason: string | null
}

export interface TreatmentCampaignFlock {
  flockId: number
  flockName: string
  houseName: string | null
  birdsAtCreation: number | null
  doseQuantity: number | null
  notes: string | null
  isClosed: boolean
  postedDays: number
  totalQuantity: number
  lastPostedDate: string | null
}

export interface TreatmentDayPosting {
  poultryTreatmentCampaignPostId: number
  poultryTreatmentCampaignId: number
  businessDate: string
  flockCount: number
  totalQuantity: number
  totalCost: number | null
  status: "Posted" | "Reversed"
  notes: string | null
  postedBy: string | null
  postedAtUtc: string
  reversedBy: string | null
  reversedAtUtc: string | null
  reversalReason: string | null
}

export interface TreatmentDayLine {
  poultryTreatmentCampaignPostLineId: number
  flockId: number
  flockName: string | null
  productionRecordId: number
  birds: number | null
  doseQuantity: number | null
  doseBasis: string | null
  suggestedQuantity: number | null
  actualQuantity: number
  unitCost: number | null
  totalCost: number | null
  notes: string | null
  reversalNote: string | null
}

export interface FlockTreatmentHistoryRow {
  poultryTreatmentCampaignPostLineId: number
  poultryTreatmentCampaignPostId: number
  poultryTreatmentCampaignId: number
  campaignName: string
  reason: string | null
  itemName: string | null
  unitOfMeasure: string | null
  businessDate: string
  productionRecordId: number
  birds: number | null
  actualQuantity: number
  totalCost: number | null
  postStatus: "Posted" | "Reversed"
  eggWithdrawalUntil: string | null
  meatWithdrawalUntil: string | null
  notes: string | null
}

export interface CreateTreatmentCampaignInput {
  name: string
  itemId: number
  reason: string | null
  startDate: string
  endDate: string
  doseInstructions: string | null
  doseQuantity: number | null
  doseBasis: DoseBasis | null
  doseSource: "User" | "Product" | null
  eggWithdrawalDays: number | null
  meatWithdrawalDays: number | null
  withdrawalNotes: string | null
  notes: string | null
  saveAsProductDefault: boolean
  flocks: { flockId: number; doseQuantity: number | null; notes: string | null }[]
}

export interface PostTreatmentDayInput {
  businessDate: string
  notes: string | null
  lines: { flockId: number; actualQuantity: number; suggestedQuantity: number | null; notes: string | null }[]
}

/** The API refused because stock no longer covers the day. */
export class InsufficientMedicationError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "InsufficientMedicationError"
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
    let code: string | undefined
    try { const j = JSON.parse(raw); message = j?.message; code = j?.code } catch { /* not JSON */ }
    if (res.status === 409 && code === "InsufficientStock") throw new InsufficientMedicationError(message ?? "Not enough medication in stock.")
    if ((res.status === 400 || res.status === 403 || res.status === 404 || res.status === 409) && message) throw new Error(message)
    throw new Error(explainHttpError(method, path, res.status, raw))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

const base = "/Poultry/treatment-campaigns"
const q = () => `farmId=${encodeURIComponent(farmId())}`

export const listMedicationProducts = async () => call<MedicationProduct[]>("GET", `${base}/products?${q()}`)

export const saveMedicationProductSettings = async (
  itemId: number,
  s: { doseQuantity: number | null; doseBasis: DoseBasis | null; eggWithdrawalDays: number | null; meatWithdrawalDays: number | null; withdrawalNotes: string | null },
) => call<void>("PUT", `${base}/products/${itemId}/settings`, { ...s, farmId: farmId() })

export const listTreatmentFlockOptions = async () => call<TreatmentFlockOption[]>("GET", `${base}/flock-options?${q()}`)

export const listTreatmentCampaigns = async () => call<TreatmentCampaign[]>("GET", `${base}?${q()}`)

export const getTreatmentCampaign = async (id: number) => call<TreatmentCampaign>("GET", `${base}/${id}?${q()}`)

export const createTreatmentCampaign = async (input: CreateTreatmentCampaignInput) =>
  call<{ poultryTreatmentCampaignId: number }>("POST", base, { ...input, farmId: farmId() })

export const completeTreatmentCampaign = async (id: number) =>
  call<void>("PUT", `${base}/${id}/completion`, { farmId: farmId() })

export const cancelTreatmentCampaign = async (id: number, reason: string) =>
  call<void>("PUT", `${base}/${id}/cancellation`, { farmId: farmId(), reason })

export const listTreatmentCampaignFlocks = async (id: number) =>
  call<TreatmentCampaignFlock[]>("GET", `${base}/${id}/flocks?${q()}`)

export const getTreatmentDayGrid = async (id: number, date: string) =>
  call<TreatmentDayRow[]>("GET", `${base}/${id}/day-grid?${q()}&date=${date}`)

export const listTreatmentDays = async (id: number) => call<TreatmentDayPosting[]>("GET", `${base}/${id}/days?${q()}`)

export const getTreatmentDayLines = async (postId: number) =>
  call<TreatmentDayLine[]>("GET", `${base}/days/${postId}/lines?${q()}`)

export const postTreatmentDay = async (id: number, input: PostTreatmentDayInput) =>
  call<{ poultryTreatmentCampaignPostId: number }>("POST", `${base}/${id}/days`, { ...input, farmId: farmId() })

export const reverseTreatmentDay = async (postId: number, reason: string) =>
  call<void>("POST", `${base}/days/${postId}/reversal`, { farmId: farmId(), reason })

export const getFlockTreatmentHistory = async (flockId: number) =>
  call<FlockTreatmentHistoryRow[]>("GET", `${base}/flocks/${flockId}/history?${q()}`)

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// Flock Lifecycle Assistant (migration 347): /Poultry/lifecycle on the Farm API.
//
// Every call takes an optional farmId. Inside a company it defaults to the
// active one; Business Office "My Tasks" passes each company's id explicitly,
// because the BO shell has no active company and the server -- not the
// browser -- is what knows this user's permissions in each of them.

export type LifecycleStatus = "Scheduled" | "Upcoming" | "Due" | "Overdue" | "Completed" | "Skipped"
export type LifecycleView = "Open" | "All" | LifecycleStatus
export type LifecycleAgeUnit = "Day" | "Week"
export type LifecycleActionType = "FlockDetails" | "FlockTransfer" | "MedicationCampaign" | "Production" | "Closeout"

export interface LifecycleMilestone {
  milestoneId?: number | null
  ageUnit: LifecycleAgeUnit
  ageValue: number
  /** Read-only: the age in days. */
  ageDays?: number
  title: string
  description?: string | null
  category?: string | null
  leadTimeDays: number
  actionType?: LifecycleActionType | null
  sortOrder?: number
}

export interface LifecycleTemplate {
  templateId: number
  name: string
  breed?: string | null
  description?: string | null
  isActive: boolean
  milestoneCount: number
  assignedBatches: number
  assignedFlocks: number
  createdBy?: string | null
  createdAt: string
  updatedBy?: string | null
  updatedAt?: string | null
  milestones?: LifecycleMilestone[] | null
}

export interface LifecycleTemplateInput {
  name: string
  breed?: string | null
  description?: string | null
  isActive: boolean
  milestones: LifecycleMilestone[]
}

export interface LifecycleAssignment {
  assignmentId: number
  templateId: number
  templateName: string
  templateBreed?: string | null
  batchId?: number | null
  batchCode?: string | null
  batchName?: string | null
  flockId?: number | null
  flockName?: string | null
  targetBreed?: string | null
  ageAtStartDays: number
  flockCount: number
  /** The plan names a breed and this batch/flock is another. A warning only. */
  breedMismatch: boolean
  assignedBy?: string | null
  assignedAt: string
}

export interface LifecycleTask {
  flockId: number
  flockName: string
  batchId?: number | null
  batchCode?: string | null
  houseId?: number | null
  breed?: string | null
  flockStartDate: string
  flockActive: boolean
  /** Start date derived during onboarding: every date on this task is an estimate. */
  isEstimated: boolean
  assignmentId: number
  /** "Batch" (inherited) | "Flock" (its own plan). */
  assignedVia: "Batch" | "Flock" | string
  templateId: number
  templateName: string
  templateBreed?: string | null
  ageAtStartDays: number
  currentAgeDays: number
  milestoneId: number
  title: string
  description?: string | null
  category?: string | null
  ageUnit: LifecycleAgeUnit
  ageValue: number
  ageDays: number
  leadTimeDays: number
  actionType?: LifecycleActionType | null
  dueDate: string
  dueWindowEnd: string
  visibleFrom: string
  daysUntilDue: number
  taskId?: number | null
  status: LifecycleStatus
  note?: string | null
  actedBy?: string | null
  actedAt?: string | null
  /** The company's business date the statuses were worked out against. */
  today: string
}

export interface LifecycleSummary {
  upcoming: number
  due: number
  overdue: number
  completedLast30: number
  skippedLast30: number
  estimatedFlocks: number
  assignedFlocks: number
  today: string
}

export interface LifecycleTaskEvent {
  eventId: number
  flockId: number
  milestoneId: number
  title: string
  fromStatus: string
  toStatus: string
  note?: string | null
  actor?: string | null
  atUtc: string
}

function fid(farmId?: string): string {
  const id = farmId || getUserContext().farmId
  if (!id) throw new Error("No active company. Pick a company first.")
  return id
}

/** A failed call that carries its HTTP status, so My Tasks can tell "no access" from "broken". */
export class LifecycleHttpError extends Error {
  constructor(message: string, public status: number) { super(message) }
}

async function call<T>(path: string, method: "GET" | "POST" | "PUT" | "DELETE" = "GET", body?: unknown): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new LifecycleHttpError(explainHttpError(method, path, res.status, t), res.status)
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

const q = (farmId?: string, extra?: Record<string, string | number | null | undefined>) => {
  const p = new URLSearchParams({ farmId: fid(farmId) })
  for (const [k, v] of Object.entries(extra ?? {})) if (v !== undefined && v !== null && v !== "") p.append(k, String(v))
  return p.toString()
}

export const listLifecycleTasks = (opts?: { view?: LifecycleView; flockId?: number | null; farmId?: string }) =>
  call<LifecycleTask[]>(`/Poultry/lifecycle/tasks?${q(opts?.farmId, { view: opts?.view ?? "Open", flockId: opts?.flockId })}`)

export const getLifecycleSummary = (farmId?: string) =>
  call<LifecycleSummary>(`/Poultry/lifecycle/summary?${q(farmId)}`)

export const getLifecycleTaskHistory = (flockId: number, milestoneId?: number, farmId?: string) =>
  call<LifecycleTaskEvent[]>(`/Poultry/lifecycle/tasks/history?${q(farmId, { flockId, milestoneId })}`)

export const setLifecycleTaskStatus = (input: {
  flockId: number; milestoneId: number; status: "Completed" | "Skipped" | "Open"; note?: string | null; farmId?: string
}) => {
  const farmId = fid(input.farmId)
  return call<{ taskId: number }>(`/Poultry/lifecycle/tasks/status?farmId=${encodeURIComponent(farmId)}`, "PUT", { ...input, farmId })
}

export const listLifecycleTemplates = () => call<LifecycleTemplate[]>(`/Poultry/lifecycle/templates?${q()}`)

export const getLifecycleTemplate = (id: number) => call<LifecycleTemplate>(`/Poultry/lifecycle/templates/${id}?${q()}`)

export const createLifecycleTemplate = (input: LifecycleTemplateInput) => {
  const farmId = fid()
  return call<LifecycleTemplate>(`/Poultry/lifecycle/templates?farmId=${encodeURIComponent(farmId)}`, "POST", { ...input, farmId })
}

export const updateLifecycleTemplate = (id: number, input: LifecycleTemplateInput) => {
  const farmId = fid()
  return call<LifecycleTemplate>(`/Poultry/lifecycle/templates/${id}?farmId=${encodeURIComponent(farmId)}`, "PUT", { ...input, farmId })
}

export const deleteLifecycleTemplate = (id: number) =>
  call<{ outcome: "Deleted" | "Retired" }>(`/Poultry/lifecycle/templates/${id}?${q()}`, "DELETE")

export const listLifecycleAssignments = () => call<LifecycleAssignment[]>(`/Poultry/lifecycle/assignments?${q()}`)

export const assignLifecycleTemplate = (input: { templateId: number; batchId?: number | null; flockId?: number | null; ageAtStartDays: number }) => {
  const farmId = fid()
  return call<{ assignmentId: number }>(`/Poultry/lifecycle/assignments?farmId=${encodeURIComponent(farmId)}`, "POST", { ...input, farmId })
}

export const removeLifecycleAssignment = (id: number) =>
  call<void>(`/Poultry/lifecycle/assignments/${id}?${q()}`, "DELETE")

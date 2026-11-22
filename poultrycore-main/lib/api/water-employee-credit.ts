// Water Employee Credit (migration 460): the Poultry client (lib/api/poultry-finance.ts,
// 441) on api/Water/employee-credit, ported from the Generic one (450). Same shapes,
// water ids. The entry labels and manual types are Poultry's, re-exported.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// ----- shared helpers (mirror water.ts) --------------------------------------
function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}
function currentUserId(): string {
  const { userId } = getUserContext()
  return userId
}
async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as T
}
async function jsend<T>(path: string, method: "POST" | "PUT" | "DELETE", body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError(method, path, res.status, t))
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}
const fid = () => encodeURIComponent(activeFarmId())


export { EMPLOYEE_CREDIT_ENTRY_LABELS, EMPLOYEE_CREDIT_MANUAL_TYPES, type EmployeeCreditManualType } from "./poultry-finance"
import type { EmployeeCreditManualType } from "./poultry-finance"
import { listWaterCashAccounts, listWaterStaff, type WaterCashAccount, type WaterStaff } from "./water"

export type { WaterCashAccount }
export type WaterCreditStaff = WaterStaff & { isDeleted?: boolean }
export const listWaterCreditStaff = (): Promise<WaterCreditStaff[]> => listWaterStaff()
export const listWaterCreditCashAccounts = (): Promise<WaterCashAccount[]> => listWaterCashAccounts()

export interface WaterEmployeeCreditBalance {
  waterStaffId: number
  staffName?: string | null
  staffRole?: string | null
  isActive: boolean
  balance: number
  totalIn: number
  totalPaidOut: number
  lastEntryDate?: string | null
  entryCount: number
}

export interface WaterEmployeeCreditEntry {
  waterEmployeeCreditId: number
  waterStaffId: number
  staffName?: string | null
  entryType: string
  amount: number
  signedAmount: number
  runningBalance: number
  entryDate: string
  waterCashAccountId?: number | null
  accountName?: string | null
  paymentMethod?: string | null
  reference?: string | null
  description?: string | null
  waterPayrollRunId?: number | null
  payrollPeriod?: string | null
  waterExpenseId?: number | null
  status: string
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface WaterEmployeeCreditTotal {
  totalHeld: number
  staffCount: number
}

export const listWaterEmployeeCreditBalances = () =>
  jget<WaterEmployeeCreditBalance[]>(`/Water/employee-credit/balances?farmId=${fid()}`)

export const listWaterEmployeeCreditEntries = (staffId?: number | null) =>
  jget<WaterEmployeeCreditEntry[]>(
    `/Water/employee-credit/entries?farmId=${fid()}` + (staffId ? `&staffId=${staffId}` : ""))

export const getWaterEmployeeCreditTotal = () =>
  jget<WaterEmployeeCreditTotal>(`/Water/employee-credit/total?farmId=${fid()}`)

export interface WaterEmployeeCreditAddInput {
  waterStaffId: number
  entryType: EmployeeCreditManualType
  amount: number
  entryDate?: string | null
  waterCashAccountId?: number | null
  paymentMethod?: string | null
  reference?: string | null
  description?: string | null
}

export const addWaterEmployeeCredit = (input: WaterEmployeeCreditAddInput) =>
  jsend<{ waterEmployeeCreditId: number }>(`/Water/employee-credit`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: currentUserId() || null,
  })

export interface WaterEmployeeCreditPayoutInput {
  waterStaffId: number
  amount: number
  waterCashAccountId: number
  entryDate?: string | null
  paymentMethod?: string | null
  reference?: string | null
  description?: string | null
}

export const payoutWaterEmployeeCredit = (input: WaterEmployeeCreditPayoutInput) =>
  jsend<{ waterEmployeeCreditId: number }>(`/Water/employee-credit/payout`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: currentUserId() || null,
  })

export const reverseWaterEmployeeCredit = (id: number, reason: string) =>
  jsend<void>(`/Water/employee-credit/${id}/reverse`, "POST", {
    farmId: activeFarmId(), reason, actionBy: currentUserId() || null,
  })

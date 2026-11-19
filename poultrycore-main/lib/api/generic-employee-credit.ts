// Generic Employee Credit (migration 450, Report 40 Part 4): the Poultry client
// (lib/api/poultry-finance.ts, 441) on api/Generic/employee-credit. Same shapes,
// generic ids. The entry labels and manual types are Poultry's, re-exported.

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
import { getCashAccounts, getStaff, type GenericCashAccount, type GenericStaff } from "./generic"

export type { GenericCashAccount }
export type GenericCreditStaff = GenericStaff & { isDeleted?: boolean }
export const listGenericStaff = (): Promise<GenericCreditStaff[]> => getStaff()
export const listGenericCashAccounts = (): Promise<GenericCashAccount[]> => getCashAccounts()

export interface GenericEmployeeCreditBalance {
  genericStaffId: number
  staffName?: string | null
  staffRole?: string | null
  isActive: boolean
  balance: number
  totalIn: number
  totalPaidOut: number
  lastEntryDate?: string | null
  entryCount: number
}

export interface GenericEmployeeCreditEntry {
  genericEmployeeCreditId: number
  genericStaffId: number
  staffName?: string | null
  entryType: string
  amount: number
  signedAmount: number
  runningBalance: number
  entryDate: string
  genericCashAccountId?: number | null
  accountName?: string | null
  paymentMethod?: string | null
  reference?: string | null
  description?: string | null
  genericPayrollRunId?: number | null
  payrollPeriod?: string | null
  expenseId?: number | null
  status: string
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface GenericEmployeeCreditTotal {
  totalHeld: number
  staffCount: number
}

export const listGenericEmployeeCreditBalances = () =>
  jget<GenericEmployeeCreditBalance[]>(`/Generic/employee-credit/balances?farmId=${fid()}`)

export const listGenericEmployeeCreditEntries = (staffId?: number | null) =>
  jget<GenericEmployeeCreditEntry[]>(
    `/Generic/employee-credit/entries?farmId=${fid()}` + (staffId ? `&staffId=${staffId}` : ""))

export const getGenericEmployeeCreditTotal = () =>
  jget<GenericEmployeeCreditTotal>(`/Generic/employee-credit/total?farmId=${fid()}`)

export interface GenericEmployeeCreditAddInput {
  genericStaffId: number
  entryType: EmployeeCreditManualType
  amount: number
  entryDate?: string | null
  genericCashAccountId?: number | null
  paymentMethod?: string | null
  reference?: string | null
  description?: string | null
}

export const addGenericEmployeeCredit = (input: GenericEmployeeCreditAddInput) =>
  jsend<{ genericEmployeeCreditId: number }>(`/Generic/employee-credit`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: currentUserId() || null,
  })

export interface GenericEmployeeCreditPayoutInput {
  genericStaffId: number
  amount: number
  genericCashAccountId: number
  entryDate?: string | null
  paymentMethod?: string | null
  reference?: string | null
  description?: string | null
}

export const payoutGenericEmployeeCredit = (input: GenericEmployeeCreditPayoutInput) =>
  jsend<{ genericEmployeeCreditId: number }>(`/Generic/employee-credit/payout`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: currentUserId() || null,
  })

export const reverseGenericEmployeeCredit = (id: number, reason: string) =>
  jsend<void>(`/Generic/employee-credit/${id}/reverse`, "POST", {
    farmId: activeFarmId(), reason, actionBy: currentUserId() || null,
  })

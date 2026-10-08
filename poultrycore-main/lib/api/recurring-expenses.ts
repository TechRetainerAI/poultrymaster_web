import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import { listPoultryCashAccounts } from "@/lib/api/poultry-finance"
import { getSuppliers as getPoultrySuppliers } from "@/lib/api/supplier"
import { listWaterCashAccounts, listWaterExpenseCategories, listWaterSuppliers } from "@/lib/api/water"
import {
  getCashAccounts as getGenericCashAccounts, getExpenseCategories as getGenericCategories,
  getSuppliers as getGenericSuppliers,
} from "@/lib/api/generic"
import { listHotelCashAccounts, listHotelExpenseCategories } from "@/lib/api/hotel"
import { listHotelSuppliers } from "@/lib/api/hotel-suppliers"
import { listExpenseCategories as listRestaurantCategories, listRestaurantSuppliers } from "@/lib/api/restaurant"
import { listCashAccounts as listRestaurantCashAccounts } from "@/lib/api/restaurant-finance"

// Recurring Expense Engine (migration 348): /recurring-expenses on the Farm API,
// for EVERY company type. The module comes from the company itself; the ids
// below (category, supplier, cash account) are that module's own ids.

export type RecurringModule = "poultry" | "water" | "generic" | "hotel" | "restaurant"
export type RecurringFrequency = "Weekly" | "Biweekly" | "Monthly" | "Quarterly" | "SemiAnnual" | "Annual"
export type RecurringStatus = "Active" | "Paused" | "Ended"
export type OccurrenceStatus = "Draft" | "Posting" | "Posted" | "Skipped"

export interface RecurringTemplate {
  templateId: number
  module: RecurringModule
  name: string
  categoryId?: number | null
  categoryName?: string | null
  supplierId?: number | null
  payeeName?: string | null
  amount: number
  isVariable: boolean
  frequency: RecurringFrequency
  startDate: string
  endDate?: string | null
  generateFrom: string
  paymentMethod: string
  cashAccountId?: number | null
  description?: string | null
  approvalMode: "Draft" | "AutoPost"
  status: RecurringStatus
  nextDueDate?: string | null
  drafts: number
  posted: number
  skipped: number
  lastPostedAt?: string | null
  createdBy?: string | null
  createdAt: string
  endedAt?: string | null
  endReason?: string | null
}

export interface RecurringTemplateInput {
  name: string
  categoryId?: number | null
  categoryName?: string | null
  supplierId?: number | null
  payeeName?: string | null
  amount: number
  isVariable: boolean
  frequency: RecurringFrequency
  startDate: string
  endDate?: string | null
  paymentMethod: string
  cashAccountId?: number | null
  description?: string | null
  approvalMode: "Draft" | "AutoPost"
}

export interface RecurringOccurrence {
  occurrenceId: number
  templateId: number
  templateName: string
  module: RecurringModule
  occurrenceNo: number
  scheduledDate: string
  status: OccurrenceStatus
  amount: number
  templateAmount: number
  isVariable: boolean
  expenseDate: string
  paymentMethod: string
  cashAccountId?: number | null
  supplierId?: number | null
  categoryId?: number | null
  categoryName?: string | null
  payeeName?: string | null
  description?: string | null
  note?: string | null
  expenseId?: number | null
  postedBy?: string | null
  postedAt?: string | null
  skippedBy?: string | null
  skippedAt?: string | null
  skipReason?: string | null
  claimedBy?: string | null
  claimedAt?: string | null
  /** A post that started over 10 minutes ago and never finished. */
  isInterrupted: boolean
  createdAt: string
}

export interface RecurringUpcoming {
  templateId: number
  name: string
  categoryName?: string | null
  amount: number
  isVariable: boolean
  frequency: RecurringFrequency
  occurrenceNo: number
  scheduledDate: string
  daysAway: number
  today: string
}

export interface RecurringPostResult {
  occurrenceId: number
  expenseId: number
  module: RecurringModule
  awaitingModuleApproval: boolean
  message: string
}

export interface RecurringGenerateResult { generated: number; autoPosted: number; autoPostFailures: string[] }

function fid(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function call<T>(path: string, method: "GET" | "POST" | "PUT" | "DELETE" = "GET", body?: unknown): Promise<T> {
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

// farmId always rides the query string too: that is where the IAM filter reads it.
const withFarm = (path: string, extra: Record<string, string | number | null | undefined> = {}) => {
  const p = new URLSearchParams({ farmId: fid() })
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== null && v !== "") p.append(k, String(v))
  return `${path}${path.includes("?") ? "&" : "?"}${p.toString()}`
}
const body = <T extends object>(b: T) => ({ ...b, farmId: fid() })

export const listRecurringTemplates = () => call<RecurringTemplate[]>(withFarm("/recurring-expenses/templates"))
export const createRecurringTemplate = (i: RecurringTemplateInput) =>
  call<{ templateId: number }>(withFarm("/recurring-expenses/templates"), "POST", body(i))
export const updateRecurringTemplate = (id: number, i: RecurringTemplateInput) =>
  call<{ templateId: number }>(withFarm(`/recurring-expenses/templates/${id}`), "PUT", body(i))
export const setRecurringTemplateStatus = (id: number, action: "Pause" | "Resume" | "End", reason?: string | null) =>
  call<{ status: RecurringStatus }>(withFarm(`/recurring-expenses/templates/${id}/status`), "PUT", body({ action, reason: reason ?? null }))
export const deleteRecurringTemplate = (id: number) => call<void>(withFarm(`/recurring-expenses/templates/${id}`), "DELETE")

export const generateRecurringExpenses = () => call<RecurringGenerateResult>(withFarm("/recurring-expenses/generate"), "POST")
export const listUpcomingRecurring = (days: number) => call<RecurringUpcoming[]>(withFarm("/recurring-expenses/upcoming", { days }))
export const listRecurringOccurrences = (status?: string, templateId?: number) =>
  call<RecurringOccurrence[]>(withFarm("/recurring-expenses/occurrences", { status, templateId }))
export const editRecurringOccurrence = (id: number, i: {
  amount: number; expenseDate: string; paymentMethod: string; cashAccountId?: number | null
  supplierId?: number | null; description?: string | null; note?: string | null
}) => call<void>(withFarm(`/recurring-expenses/occurrences/${id}`), "PUT", body(i))
export const postRecurringOccurrence = (id: number) =>
  call<RecurringPostResult>(withFarm(`/recurring-expenses/occurrences/${id}/record`), "POST")
export const skipRecurringOccurrence = (id: number, reason: string) =>
  call<void>(withFarm(`/recurring-expenses/occurrences/${id}/skip`), "PUT", body({ reason }))
export const restoreRecurringOccurrence = (id: number) =>
  call<void>(withFarm(`/recurring-expenses/occurrences/${id}/restore`), "PUT", body({}))
export const releaseRecurringOccurrence = (id: number, reason?: string) =>
  call<void>(withFarm(`/recurring-expenses/occurrences/${id}/release`), "PUT", body({ reason: reason ?? null }))
export const linkRecurringOccurrence = (id: number, expenseId: number) =>
  call<void>(withFarm(`/recurring-expenses/occurrences/${id}/link`), "PUT", body({ expenseId }))

// ----------------------------------------------------------- module lookups --
export interface Option { id: number; name: string }
export interface ModuleLookups {
  /** Poultry categories are free text; every other module has a category table. */
  categoriesAreText: boolean
  textCategories: string[]
  categories: Option[]
  suppliers: Option[]
  cashAccounts: Option[]
  /** The module approves expenses after they are created (cash moves on approval). */
  moduleApproves: boolean
  expensesHref: string
}

/** The same list the poultry New Expense page offers. */
export const POULTRY_CATEGORIES = ["Feed", "Veterinary", "Equipment", "Labor", "Utilities", "Rent", "Security", "Internet", "Software", "Other"]

export function moduleForFarmType(type: string | null | undefined): RecurringModule {
  switch ((type ?? "").toLowerCase()) {
    case "water": return "water"
    case "generic": return "generic"
    case "hotel": return "hotel"
    case "restaurant": return "restaurant"
    default: return "poultry"
  }
}

const safe = async <T,>(p: Promise<T>, fallback: T): Promise<T> => { try { return await p } catch { return fallback } }

export async function loadModuleLookups(module: RecurringModule): Promise<ModuleLookups> {
  const base = { categoriesAreText: false, textCategories: [] as string[], categories: [] as Option[], suppliers: [] as Option[], cashAccounts: [] as Option[] }
  switch (module) {
    case "poultry": {
      const { farmId, userId } = getUserContext()
      const [cash, sup] = await Promise.all([
        safe(listPoultryCashAccounts(), []),
        farmId && userId ? safe(getPoultrySuppliers(userId, farmId), { success: false, data: [] }) : Promise.resolve({ success: false, data: [] }),
      ])
      return {
        ...base, categoriesAreText: true, textCategories: POULTRY_CATEGORIES,
        suppliers: ((sup as any).data ?? []).map((s: any) => ({ id: s.supplierId, name: s.name })),
        cashAccounts: cash.filter((a) => a.isActive).map((a) => ({ id: a.poultryCashAccountId, name: a.accountName })),
        moduleApproves: false, expensesHref: "/expenses",
      }
    }
    case "water": {
      const [cats, sups, cash] = await Promise.all([safe(listWaterExpenseCategories(), []), safe(listWaterSuppliers(), []), safe(listWaterCashAccounts(), [])])
      return {
        ...base,
        categories: (cats as any[]).filter((c) => c.isActive !== false).map((c) => ({ id: c.waterExpenseCategoryId, name: c.name })),
        suppliers: (sups as any[]).map((s) => ({ id: s.waterSupplierId, name: s.supplierName })),
        cashAccounts: (cash as any[]).filter((a) => a.isActive !== false).map((a) => ({ id: a.waterCashAccountId, name: a.accountName })),
        moduleApproves: true, expensesHref: "/water-expenses",
      }
    }
    case "generic": {
      const [cats, sups, cash] = await Promise.all([safe(getGenericCategories(), []), safe(getGenericSuppliers(), []), safe(getGenericCashAccounts(), [])])
      return {
        ...base,
        categories: (cats as any[]).filter((c) => c.isActive !== false).map((c) => ({ id: c.genericExpenseCategoryId, name: c.name })),
        suppliers: (sups as any[]).map((s) => ({ id: s.genericSupplierId, name: s.supplierName })),
        cashAccounts: (cash as any[]).filter((a) => a.isActive !== false).map((a) => ({ id: a.genericCashAccountId, name: a.accountName })),
        moduleApproves: true, expensesHref: "/generic-expenses",
      }
    }
    case "hotel": {
      const [cats, sups, cash] = await Promise.all([safe(listHotelExpenseCategories(), []), safe(listHotelSuppliers(), []), safe(listHotelCashAccounts(), [])])
      return {
        ...base,
        categories: (cats as any[]).filter((c) => c.isActive !== false).map((c) => ({ id: c.hotelExpenseCategoryId, name: c.name })),
        suppliers: (sups as any[]).filter((s) => s.isActive !== false).map((s) => ({ id: s.hotelSupplierId, name: s.supplierName })),
        cashAccounts: (cash as any[]).filter((a) => a.isActive !== false).map((a) => ({ id: a.hotelCashAccountId, name: a.accountName })),
        moduleApproves: true, expensesHref: "/hotel-expenses",
      }
    }
    case "restaurant": {
      const [cats, sups, cash] = await Promise.all([safe(listRestaurantCategories(), []), safe(listRestaurantSuppliers(), []), safe(listRestaurantCashAccounts(), [])])
      return {
        ...base,
        categories: (cats as any[]).filter((c) => c.isActive !== false).map((c) => ({ id: c.expenseCategoryId, name: c.name })),
        suppliers: (sups as any[]).map((s) => ({ id: s.restaurantsupplierid ?? s.restaurantSupplierId, name: s.name })),
        cashAccounts: (cash as any[]).filter((a) => a.isActive !== false).map((a) => ({ id: a.cashAccountId, name: a.name })),
        moduleApproves: false, expensesHref: "/restaurant-expenses",
      }
    }
  }
}

/**
 * Customer credit is one feature on two company types (poultry 351-371, water
 * 422). The API routes and DTOs are identical -- only the route prefix and a
 * few loaders differ -- so the credit pages and dialogs call these instead of
 * a module's own client.
 */
import { getCustomers } from "@/lib/api"
import { getUserContext } from "@/lib/api/config"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { listWaterCashAccounts, listWaterCustomers, listWaterSuppliers } from "@/lib/api/water"
import { getSuppliers } from "@/lib/api/supplier"

export type CreditModule = "Poultry" | "Water"

/** The active company's module, from what the company switcher stores. */
export function creditModule(): CreditModule {
  if (typeof window === "undefined") return "Poultry"
  try {
    return localStorage.getItem("farmType") === "Water" ? "Water" : "Poultry"
  } catch {
    return "Poultry"
  }
}

/** Cash accounts in the poultry shape (water ids mapped onto poultryCashAccountId). */
export async function listCreditCashAccounts(): Promise<PoultryCashAccount[]> {
  if (creditModule() === "Water") {
    const rows = await listWaterCashAccounts()
    return rows.map((a) => ({
      poultryCashAccountId: a.waterCashAccountId,
      farmId: a.farmId,
      accountName: a.accountName,
      accountType: a.accountType,
      openingBalance: a.openingBalance,
      currentBalance: a.currentBalance,
      allowNegativeBalance: a.allowNegativeBalance,
      isActive: a.isActive,
      notes: a.notes,
    }))
  }
  return listPoultryCashAccounts()
}

/** The company's customers as { id, name }, sorted by name. */
export async function listCreditCustomers(): Promise<{ id: number; name: string }[]> {
  let list: any[] = []
  if (creditModule() === "Water") {
    list = (await listWaterCustomers()).map((c) => ({ id: c.waterCustomerId, name: c.name }))
  } else {
    const { userId, farmId } = getUserContext()
    const r: any = await getCustomers(userId, farmId)
    const raw = (r?.success ? r.data : r) ?? []
    list = (Array.isArray(raw) ? raw : []).map((c: any) => ({
      id: Number(c.customerId ?? c.id), name: String(c.name ?? c.customerName ?? ""),
    }))
  }
  return list
    .filter((c) => c.id > 0 && c.name)
    .sort((a, b) => a.name.localeCompare(b.name))
}

/** Permission key for the active module, e.g. "customer-payments.create". */
export function creditPerm(key: string): string {
  return `${creditModule() === "Water" ? "water" : "poultry"}.${key}`
}

/** Where the credit pages link to, per module. */
export function creditRoutes() {
  const water = creditModule() === "Water"
  return {
    balances: water ? "/water-customer-balances" : "/customer-balances",
    credits: water ? "/water-customer-credits" : "/customer-credits",
    customer: (id: number) => (water ? "/water-customers" : `/customers/${id}`),
  }
}

/** The balances-client module name ("poultry" | "water"). */
export function creditBalanceModule(): "poultry" | "water" {
  return creditModule() === "Water" ? "water" : "poultry"
}

/** The company's suppliers as { id, name }, sorted by name (424). */
export async function listCreditSuppliers(): Promise<{ id: number; name: string }[]> {
  let list: { id: number; name: string }[] = []
  if (creditModule() === "Water") {
    list = (await listWaterSuppliers()).map((x) => ({ id: x.waterSupplierId, name: x.supplierName }))
  } else {
    const { userId, farmId } = getUserContext()
    const r = await getSuppliers(userId, farmId)
    list = (r?.data ?? []).map((x: any) => ({ id: Number(x.supplierId), name: String(x.name ?? "") }))
  }
  return list.filter((x) => x.id > 0 && x.name).sort((a, b) => a.name.localeCompare(b.name))
}

/** Supplier-side links, per module (424). */
export function supplierCreditRoutes() {
  const water = creditModule() === "Water"
  return {
    balances: water ? "/water-supplier-balances" : "/supplier-balances",
    credits: water ? "/water-supplier-credits" : "/supplier-credits",
  }
}

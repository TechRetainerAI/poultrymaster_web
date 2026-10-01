// Restaurant wiring for the shared Customer Balances / Payments pages
// (migration 333). A customer is a saved CRM customer (restaurantcustomers);
// the document it owes on is a pay-later order ("Order").

import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "@/lib/api/config"
import { listCashAccounts } from "@/lib/api/restaurant-finance"
import type { CashAccountOption } from "@/components/balances/record-payment-dialog"

/** Restaurant rose, for the shared pages' header icon. */
export const RESTAURANT_ICON_CLASS = "text-rose-600"

export const RESTAURANT_CUSTOMER_PERMISSIONS = {
  view: "restaurant.customer-balances.view",
  pay: "restaurant.customer-payments.create",
  reverse: "restaurant.customer-payments.reverse",
  statement: "restaurant.customer-statements.view",
}

export async function loadRestaurantCashAccounts(): Promise<CashAccountOption[]> {
  const accounts = await listCashAccounts()
  return accounts
    .filter((a) => a.isActive)
    .map((a) => ({ id: a.cashAccountId, name: a.name, currentBalance: a.currentBalance, allowNegativeBalance: a.allowNegative }))
}

/** The orders list; a single order has no page of its own. */
export const restaurantOrderHref = (_orderId: number) => "/restaurant-orders"

/**
 * Close an order as Pay later: marks it for its saved customer (optional due
 * date) and completes it, unpaid or part-paid. Only a customer-linked order can
 * do this; the server refuses walk-ins with a plain sentence.
 */
export async function markOrderPayLater(orderId: number, input: { dueDate?: string | null; notes?: string | null } = {}) {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  const res = await fetch(farmApiUrl(`/Restaurant/orders/${orderId}/pay-later?farmId=${encodeURIComponent(farmId)}`), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ farmId, dueDate: input.dueDate || null, notes: input.notes || null }),
  })
  if (!res.ok) throw new Error(await readApiError(res))
}

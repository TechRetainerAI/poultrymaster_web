// Hotel wiring for the shared balances / payments pages (migration 332).
//
// Customer party ids: a guest is its hotelguestid, a corporate account is MINUS
// its hotelcustomerid. Document types: Stay (a booking's bill), OpeningBalance,
// and on the supplier side Expense / AssetCost / OpeningBalance.

import { listHotelCashAccounts } from "@/lib/api/hotel"
import type { CashAccountOption } from "@/components/balances/record-payment-dialog"

/** Hotel violet, for the shared pages' header icon. */
export const HOTEL_ICON_CLASS = "text-violet-600"

export async function loadHotelCashAccounts(activeOnly = true): Promise<CashAccountOption[]> {
  const accounts = await listHotelCashAccounts()
  return accounts
    .filter((a) => !activeOnly || a.isActive !== false)
    .map((a: any) => ({
      id: a.hotelCashAccountId ?? a.hotelcashaccountid,
      name: a.accountName ?? a.accountname,
      currentBalance: Number(a.currentBalance ?? a.currentbalance ?? 0),
      allowNegativeBalance: Boolean(a.allowNegativeBalance ?? a.allownegativebalance ?? false),
    }))
}

export function hotelPartyHref(partyId: number): string {
  return partyId < 0 ? "/hotel-customers" : "/hotel-guests"
}

export function hotelCustomerDocumentHref(documentType: string, documentId: number): string | null {
  if (documentType === "OpeningBalance") return "/hotel-customers"
  return `/hotel-sales?bookingId=${documentId}`
}

export function hotelPayableHref(documentType: string, documentId: number): string | null {
  switch (documentType) {
    case "Purchase":
      return `/hotel-inventory?purchaseId=${documentId}`
    case "Expense":
      return `/hotel-expenses?expenseId=${documentId}`
    case "AssetCost":
      return "/hotel-assets"
    case "OpeningBalance":
      return "/hotel-suppliers"
    default:
      return null
  }
}

export const HOTEL_CUSTOMER_PERMISSIONS = {
  view: "hotel.customer-balances.view",
  pay: "hotel.customer-payments.create",
  reverse: "hotel.customer-payments.reverse",
  statement: "hotel.customer-statements.view",
}

export const HOTEL_SUPPLIER_PERMISSIONS = {
  view: "hotel.supplier-balances.view",
  pay: "hotel.supplier-payments.create",
  reverse: "hotel.supplier-payments.reverse",
  statement: "hotel.supplier-statements.view",
}

"use client"

// Restaurant Supplier Payments (Sales, Expenses & Money → Supplier Payments).
//
// The ledger of money actually paid out, as opposed to Supplier Balances, which
// is the ledger of money still owed. The Poultry page (app/supplier-payments) on
// the shared PaymentsLedgerPage; the same documentHref branching as the balances
// twin (migration 329).

import { PaymentsLedgerPage } from "@/components/balances/payments-ledger-page"
import { listCashAccounts } from "@/lib/api/restaurant-finance"
import { restaurantPayableHref } from "@/lib/restaurant/payables"

export default function RestaurantSupplierPaymentsPage() {
  return (
    <PaymentsLedgerPage
      module="restaurant"
      companyType="Restaurant"
      loadCashAccounts={async () => {
        const accounts = await listCashAccounts()
        return accounts.map((a) => ({ id: a.cashAccountId, name: a.name }))
      }}
      partyHref={() => "/restaurant-suppliers"}
      documentHref={(a) => restaurantPayableHref(a.documentType, a.documentId)}
      permissions={{
        view: "restaurant.supplier-balances.view",
        reverse: "restaurant.supplier-payments.reverse",
      }}
    />
  )
}

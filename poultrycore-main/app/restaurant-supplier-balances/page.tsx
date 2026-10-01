"use client"

// Restaurant Supplier Balances (Sales, Expenses & Money → Supplier Balances).
//
// The Poultry page (app/supplier-balances) on the shared BalancesPage. Restaurant
// payables span three document tables -- purchases, expenses owed to a supplier
// and capital investments not yet paid for (migration 329) -- so documentHref
// branches on documentType, exactly as the Poultry twin does.

import { BalancesPage } from "@/components/balances/balances-page"
import { listCashAccounts } from "@/lib/api/restaurant-finance"
import { restaurantPayableHref } from "@/lib/restaurant/payables"

export default function RestaurantSupplierBalancesPage() {
  return (
    <BalancesPage
      module="restaurant"
      side="supplier"
      companyType="Restaurant"
      loadCashAccounts={async () => {
        const accounts = await listCashAccounts()
        return accounts
          .filter((a) => a.isActive)
          .map((a) => ({
            id: a.cashAccountId,
            name: a.name,
            currentBalance: a.currentBalance,
            allowNegativeBalance: a.allowNegative,
          }))
      }}
      partyHref={() => "/restaurant-suppliers"}
      documentHref={(doc) => restaurantPayableHref(doc.documentType, doc.documentId)}
      permissions={{
        view: "restaurant.supplier-balances.view",
        pay: "restaurant.supplier-payments.create",
        reverse: "restaurant.supplier-payments.reverse",
        statement: "restaurant.supplier-statements.view",
      }}
    />
  )
}

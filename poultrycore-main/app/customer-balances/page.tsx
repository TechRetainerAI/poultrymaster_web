"use client"

// Poultry Customer Balances (Sales & Money → Customer Balances).
//
// Thin: everything lives in <BalancesPage>, which the water and generic routes
// will reuse once their migrations land. All this file decides is which module
// it is, where a customer and a sale live, and which permission keys apply.

import { BalancesPage } from "@/components/balances/balances-page"
import { listPoultryCashAccounts } from "@/lib/api/poultry-finance"

export default function CustomerBalancesPage() {
  return (
    <BalancesPage
      module="poultry"
      side="customer"
      companyType="Poultry"
      loadCashAccounts={async () => {
        const accounts = await listPoultryCashAccounts()
        return accounts
          .filter((a) => a.isActive)
          .map((a) => ({
            id: a.poultryCashAccountId,
            name: a.accountName,
            currentBalance: a.currentBalance,
            allowNegativeBalance: a.allowNegativeBalance,
          }))
      }}
      partyHref={(customerId) => `/customers/${customerId}`}
      // The Sales page is a list with its own filters rather than a per-sale
      // route, so deep-link into it with the sale highlighted.
      documentHref={(doc) => `/sales?saleId=${doc.documentId}`}
      permissions={{
        view: "poultry.customer-balances.view",
        pay: "poultry.customer-payments.create",
        reverse: "poultry.customer-payments.reverse",
        statement: "poultry.customer-statements.view",
      }}
    />
  )
}

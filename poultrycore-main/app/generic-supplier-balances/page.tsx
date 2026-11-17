"use client"

// Generic Supplier Balances (Purchases & Suppliers → Supplier Balances).
//
// Deep copy of the poultry version: uses the shared <BalancesPage> with
// supplier credit panel below the table. The only poultry feature NOT
// replicated is supplier debts (no backend support yet on the generic side).

import { BalancesPage } from "@/components/balances/balances-page"
import { GenericSupplierCreditPanel } from "@/components/generic/generic-supplier-credit-panel"
import { getCashAccounts } from "@/lib/api/generic"

export default function GenericSupplierBalancesPage() {
  return (
    <BalancesPage
      module="generic"
      side="supplier"
      companyType="Generic"
      loadCashAccounts={async () => {
        const accounts = await getCashAccounts()
        return accounts
          .filter((a) => a.isActive)
          .map((a) => ({
            id: a.genericCashAccountId,
            name: a.accountName,
            currentBalance: a.currentBalance,
            allowNegativeBalance: a.allowNegativeBalance,
          }))
      }}
      partyHref={(supplierId) => `/generic-suppliers/${supplierId}/ledger`}
      documentHref={(doc) =>
        doc.documentType === "Expense"
          ? `/generic-expenses?expenseId=${doc.documentId}`
          : `/generic-purchases?purchaseId=${doc.documentId}`
      }
      afterTable={(_reload, paymentsVersion) => <GenericSupplierCreditPanel refreshKey={paymentsVersion} />}
      permissions={{
        view: "generic.supplier-balances.view",
        pay: "generic.supplier-payments.create",
        reverse: "generic.supplier-payments.reverse",
        statement: "generic.supplier-statements.view",
      }}
    />
  )
}

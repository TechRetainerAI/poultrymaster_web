"use client"

// Generic Supplier Balances (Purchases & Suppliers → Supplier Balances).
//
// The Poultry page on the shared <BalancesPage>. 449 (Report 40): supplier debts
// (record in the header, reverse on the debt's row) and Poultry's supplier
// credit panel under the table, as on Poultry.

import { BalancesPage } from "@/components/balances/balances-page"
import { RecordSupplierDebtButton, ReverseSupplierDebtButton } from "@/components/balances/supplier-debts-panel"
import { SupplierCreditPanel } from "@/components/suppliers/supplier-credit-panel"
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
        doc.documentType === "SupplierDebt" ? null
          : doc.documentType === "Expense"
          ? `/generic-expenses?expenseId=${doc.documentId}`
          : `/generic-purchases?purchaseId=${doc.documentId}`
      }
      headerActions={(reload) => <RecordSupplierDebtButton onChanged={reload} />}
      documentActions={(doc, party, compact, reload) => (
        <ReverseSupplierDebtButton doc={doc} partyName={party.partyName} compact={compact} onChanged={reload} />
      )}
      afterTable={(_reload, paymentsVersion) => <SupplierCreditPanel refreshKey={paymentsVersion} />}
      permissions={{
        view: "generic.supplier-balances.view",
        pay: "generic.supplier-payments.create",
        reverse: "generic.supplier-payments.reverse",
        statement: "generic.supplier-statements.view",
      }}
    />
  )
}

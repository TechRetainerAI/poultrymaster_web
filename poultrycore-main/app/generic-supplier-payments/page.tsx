"use client"

// Generic Supplier Payments — deep copy of the poultry version.
//
// Uses the shared <PaymentsLedgerPage> for the full poultry-level experience:
// expandable allocations, sortable columns, summary cards, export, filters.
// The standalone Draft/Approve page this replaced had none of these.

import { PaymentsLedgerPage } from "@/components/balances/payments-ledger-page"
import { getCashAccounts } from "@/lib/api/generic"

export default function GenericSupplierPaymentsPage() {
  return (
    <PaymentsLedgerPage
      module="generic"
      companyType="Generic"
      loadCashAccounts={async () => {
        const accounts = await getCashAccounts()
        return accounts
          .filter((a) => a.isActive)
          .map((a) => ({ id: a.genericCashAccountId, name: a.accountName }))
      }}
      partyHref={(supplierId) => `/generic-suppliers/${supplierId}/ledger`}
      documentHref={(a) =>
        a.documentType === "Expense"
          ? `/generic-expenses?expenseId=${a.documentId}`
          : `/generic-purchases?purchaseId=${a.documentId}`
      }
      permissions={{
        view: "generic.supplier-balances.view",
        reverse: "generic.supplier-payments.reverse",
      }}
    />
  )
}

"use client"

// Generic Supplier Payments — the Poultry page on the shared <PaymentsLedgerPage>.
//
// 449 (Report 40): "Record payment" in the header, as on Poultry -- a payment
// spread over several bills, kept partly as credit, or an advance (applied to
// nothing). Supplier debts (SD-) link nowhere, as on Poultry.

import { PaymentsLedgerPage } from "@/components/balances/payments-ledger-page"
import { RecordPartyPaymentButton } from "@/components/payments/record-customer-payment-button"
import { usePermissions } from "@/hooks/use-permissions"
import { getCashAccounts } from "@/lib/api/generic"

export default function GenericSupplierPaymentsPage() {
  const { can } = usePermissions()
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
        a.documentType === "SupplierDebt" ? null
          : a.documentType === "Expense"
          ? `/generic-expenses?expenseId=${a.documentId}`
          : `/generic-purchases?purchaseId=${a.documentId}`
      }
      permissions={{
        view: "generic.supplier-balances.view",
        reverse: "generic.supplier-payments.reverse",
      }}
      headerActions={(reload) => can("generic.supplier-payments.create")
        ? <RecordPartyPaymentButton side="supplier" onPosted={reload} />
        : null}
    />
  )
}

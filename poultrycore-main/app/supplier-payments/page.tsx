"use client"

// Poultry Supplier Payments (Sales & Money → Supplier Payments).
//
// The ledger of money actually paid out, as opposed to Supplier Balances, which
// is the ledger of money still owed. Same documentHref branching as the balances
// twin, because poultry payables span three document tables now: raw-material
// purchases, flock batches and — since migration 238 — expenses.

import { PaymentsLedgerPage } from "@/components/balances/payments-ledger-page"
import { listPoultryCashAccounts } from "@/lib/api/poultry-finance"

export default function SupplierPaymentsPage() {
  return (
    <PaymentsLedgerPage
      module="poultry"
      companyType="Poultry"
      loadCashAccounts={async () => {
        const accounts = await listPoultryCashAccounts()
        return accounts.map((a) => ({ id: a.poultryCashAccountId, name: a.accountName }))
      }}
      partyHref={() => "/suppliers"}
      documentHref={(a) => {
        switch (a.documentType) {
          case "FlockBatch":
            return `/flock-batch/${a.documentId}`
          case "Expense":
            // The Expenses page filters to one row the same way the raw
            // materials tab does, so the link lands on the bill that was paid
            // rather than on the whole list.
            return `/expenses?expenseId=${a.documentId}`
          default:
            return `/poultry-raw-materials?tab=purchases&purchaseId=${a.documentId}`
        }
      }}
      permissions={{
        view: "poultry.supplier-balances.view",
        reverse: "poultry.supplier-payments.reverse",
      }}
    />
  )
}

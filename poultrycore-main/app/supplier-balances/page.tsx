"use client"

// Poultry Supplier Balances (Sales & Money → Supplier Balances).
//
// Poultry payables span two document tables -- raw-material purchases and flock
// batches -- so documentHref has to branch on documentType. That is the same
// reason the allocation rows carry a type alongside the id.

import { BalancesPage } from "@/components/balances/balances-page"
import { listPoultryCashAccounts } from "@/lib/api/poultry-finance"

export default function SupplierBalancesPage() {
  return (
    <BalancesPage
      module="poultry"
      side="supplier"
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
      partyHref={() => "/suppliers"}
      // Raw-material purchases live on a tab of the raw materials page rather
      // than at a route of their own, so this lands on that tab with the one
      // purchase in focus — ?purchaseId= narrows the list the same way
      // ?saleId= does on /sales for the customer side. Without it the link
      // dropped you into every supplier's purchases and left you to find the
      // row yourself. Flock batches do have a detail route.
      documentHref={(doc) =>
        doc.documentType === "FlockBatch"
          ? `/flock-batch/${doc.documentId}`
          : `/poultry-raw-materials?tab=purchases&purchaseId=${doc.documentId}`
      }
      permissions={{
        view: "poultry.supplier-balances.view",
        pay: "poultry.supplier-payments.create",
        reverse: "poultry.supplier-payments.reverse",
        statement: "poultry.supplier-statements.view",
      }}
    />
  )
}

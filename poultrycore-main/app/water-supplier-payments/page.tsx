"use client"

// Water Supplier Payments (Sales & Money → Supplier Payments).
//
// The water twin of /supplier-payments. Water payables are a single document
// table (waterrawmaterialpurchases), so documentHref has nothing to branch on —
// but allocations still carry a documentType, so a second payable table later
// changes this file and nothing else.

import { PaymentsLedgerPage } from "@/components/balances/payments-ledger-page"
import { listWaterCashAccounts } from "@/lib/api/water"

export default function WaterSupplierPaymentsPage() {
  return (
    <PaymentsLedgerPage
      module="water"
      companyType="Water"
      loadCashAccounts={async () => {
        const accounts = await listWaterCashAccounts()
        return accounts.map((a) => ({ id: a.waterCashAccountId, name: a.accountName }))
      }}
      partyHref={() => "/water-suppliers"}
      documentHref={(a) => `/water-raw-materials?tab=purchases&purchaseId=${a.documentId}`}
      permissions={{
        view: "water.supplier-balances.view",
        reverse: "water.supplier-payments.reverse",
      }}
    />
  )
}

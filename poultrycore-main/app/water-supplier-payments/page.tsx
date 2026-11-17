"use client"

// Water Supplier Payments (Sales & Money → Supplier Payments).
//
// The water twin of /supplier-payments. Water payables are a single document
// table (waterrawmaterialpurchases), so documentHref has nothing to branch on —
// but allocations still carry a documentType, so a second payable table later
// changes this file and nothing else.

import { PaymentsLedgerPage } from "@/components/balances/payments-ledger-page"
import { listWaterCashAccounts } from "@/lib/api/water"
import { RecordPartyPaymentButton } from "@/components/payments/record-customer-payment-button"
import { usePermissions } from "@/hooks/use-permissions"

export default function WaterSupplierPaymentsPage() {
  const { can } = usePermissions()
  return (
    <PaymentsLedgerPage
      module="water"
      companyType="Water"
      loadCashAccounts={async () => {
        const accounts = await listWaterCashAccounts()
        return accounts.map((a) => ({ id: a.waterCashAccountId, name: a.accountName }))
      }}
      partyHref={() => "/water-suppliers"}
      documentHref={(a) => a.documentType === "SupplierDebt" ? null
        : `/water-supply-purchases?tab=purchases&purchaseId=${a.documentId}`}
      // 426: a payment not tied to one purchase -- spread, or kept as an advance.
      headerActions={(reload) => can("water.supplier-payments.create")
        ? <RecordPartyPaymentButton side="supplier" onPosted={reload} />
        : null}
      permissions={{
        view: "water.supplier-balances.view",
        reverse: "water.supplier-payments.reverse",
      }}
    />
  )
}

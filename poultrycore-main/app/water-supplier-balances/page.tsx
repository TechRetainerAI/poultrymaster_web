"use client"

// Water Supplier Balances (Sales & Money → Supplier Balances).
//
// Water payables are a single document table (waterrawmaterialpurchases), so
// unlike the poultry twin documentHref has nothing to branch on -- but the
// allocation rows still carry a documentType, so a second payable table later
// changes this file and nothing else.

import { BalancesPage } from "@/components/balances/balances-page"
import { listWaterCashAccounts } from "@/lib/api/water"

export default function WaterSupplierBalancesPage() {
  return (
    <BalancesPage
      module="water"
      side="supplier"
      companyType="Water"
      // The supplier side DOES move cash: paying a purchase writes an approved
      // WaterExpenses row and a CashOut, which is what the Raw Materials
      // pay-balance button has always done (migration 091). So the account
      // picker is real here, unlike on the customer page.
      loadCashAccounts={async () => {
        const accounts = await listWaterCashAccounts()
        return accounts
          .filter((a) => a.isActive)
          .map((a) => ({
            id: a.waterCashAccountId,
            name: a.accountName,
            currentBalance: a.currentBalance,
            allowNegativeBalance: a.allowNegativeBalance,
          }))
      }}
      partyHref={() => "/water-suppliers"}
      // Raw-material purchases live on a tab of the raw materials page rather
      // than at a route of their own, so this lands on that tab with the one
      // purchase in focus.
      documentHref={(doc) =>
        `/water-raw-materials?tab=purchases&purchaseId=${doc.documentId}`
      }
      permissions={{
        view: "water.supplier-balances.view",
        pay: "water.supplier-payments.create",
        reverse: "water.supplier-payments.reverse",
        statement: "water.supplier-statements.view",
      }}
    />
  )
}

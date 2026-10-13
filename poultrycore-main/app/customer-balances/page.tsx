"use client"

// Poultry Customer Balances (Sales & Money → Customer Balances).
//
// Thin: everything lives in <BalancesPage>, which the water and generic routes
// will reuse once their migrations land. All this file decides is which module
// it is, where a customer and a sale live, and which permission keys apply.

import { useState } from "react"
import { useRouter } from "next/navigation"
import { BalancesPage } from "@/components/balances/balances-page"
import { SaleLinesDialog } from "@/components/sales/sale-lines-dialog"
import { listPoultryCashAccounts } from "@/lib/api/poultry-finance"
import { CustomerCreditPanel } from "@/components/sales/customer-credit-panel"

export default function CustomerBalancesPage() {
  const router = useRouter()
  // Click a sale row: what was sold on it (358 lines), without leaving the page.
  const [detailSaleId, setDetailSaleId] = useState<number | null>(null)
  return (
    <>
    <BalancesPage
      module="poultry"
      side="customer"
      companyType="Poultry"
      // 351: money held for customers, beside (never netted into) what they owe.
      afterSummary={<CustomerCreditPanel />}
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
      onDocumentDetails={(doc) => setDetailSaleId(doc.documentId)}
      permissions={{
        view: "poultry.customer-balances.view",
        pay: "poultry.customer-payments.create",
        reverse: "poultry.customer-payments.reverse",
        statement: "poultry.customer-statements.view",
      }}
    />
    <SaleLinesDialog
      saleIds={detailSaleId ? [detailSaleId] : null}
      onOpenChange={(o) => { if (!o) setDetailSaleId(null) }}
      onOpenSale={(id) => router.push(`/sales?saleId=${id}`)}
    />
    </>
  )
}

"use client"

// Generic Customer Balances (Sales & Money → Customer Balances).
//
// Deep copy of the poultry version: uses the shared <BalancesPage> with
// sale lines dialog, customer credit panel, and clickable document rows.
// The only poultry feature NOT replicated is customer debts (no backend
// support yet on the generic side).

import { useState } from "react"
import { useRouter } from "next/navigation"
import { BalancesPage } from "@/components/balances/balances-page"
import { GenericSaleLinesDialog } from "@/components/generic/generic-sale-lines-dialog"
import { GenericCustomerCreditPanel } from "@/components/generic/generic-customer-credit-panel"
import { getCashAccounts } from "@/lib/api/generic"
import { useGenericModules } from "@/hooks/use-generic-modules"

export default function GenericCustomerBalancesPage() {
  const router = useRouter()
  const { labels } = useGenericModules()

  // Click a sale row: show what was sold, without leaving the page.
  const [detailSaleId, setDetailSaleId] = useState<number | null>(null)

  return (
    <>
    <BalancesPage
      module="generic"
      side="customer"
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
      partyHref={(customerId) => `/generic-customers/${customerId}/ledger`}
      documentHref={(doc) => `/generic-sales?saleId=${doc.documentId}`}
      onDocumentDetails={(doc) => setDetailSaleId(doc.documentId)}
      afterTable={(_reload, paymentsVersion) => <GenericCustomerCreditPanel refreshKey={paymentsVersion} />}
      permissions={{
        view: "generic.customer-balances.view",
        pay: "generic.customer-payments.create",
        reverse: "generic.customer-payments.reverse",
        statement: "generic.customer-statements.view",
      }}
      wording={{
        party: labels.customer.toLowerCase(),
        partyPlural: labels.customerPlural.toLowerCase(),
        title: labels.customerBalance,
        document: labels.invoice.toLowerCase(),
      }}
    />
    <GenericSaleLinesDialog
      saleIds={detailSaleId ? [detailSaleId] : null}
      onOpenChange={(o) => { if (!o) setDetailSaleId(null) }}
      onOpenSale={(id) => router.push(`/generic-sales?saleId=${id}`)}
    />
    </>
  )
}

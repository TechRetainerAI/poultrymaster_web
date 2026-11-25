"use client"

// Generic Customer Balances (Sales & Money → Customer Balances).
//
// Deep copy of the poultry version: uses the shared <BalancesPage> with
// sale lines dialog, customer credit panel, and clickable document rows.
// 488: customer debts too (Poultry 369) -- "Record customer debt" in the header,
// Reverse on a debt's row; an open debt is listed among the customer's open
// items and is paid like a sale.

import { useState } from "react"
import { useRouter } from "next/navigation"
import { BalancesPage } from "@/components/balances/balances-page"
import { GenericSaleLinesDialog } from "@/components/generic/generic-sale-lines-dialog"
import { GenericCustomerCreditPanel } from "@/components/generic/generic-customer-credit-panel"
import { RecordCustomerDebtButton, ReverseCustomerDebtButton } from "@/components/balances/customer-debts-panel"
import { getCashAccounts } from "@/lib/api/generic"
import { useProjectBalanceScope } from "@/components/generic/projects/use-project-balance-scope"
import { useGenericModules } from "@/hooks/use-generic-modules"

export default function GenericCustomerBalancesPage() {
  const router = useRouter()
  const { labels } = useGenericModules()
  // 493: Project / Contract filter -- each customer's balance on that project.
  const projectScope = useProjectBalanceScope("customer")

  // Click a sale row: show what was sold, without leaving the page.
  const [detailSaleId, setDetailSaleId] = useState<number | null>(null)

  return (
    <>
    <BalancesPage
      module="generic"
      side="customer"
      companyType="Generic"
      scope={projectScope}
      // 488 (Poultry 369): debts recorded by hand (owed without a sale). Recording
      // is a header button, reversing is on the debt's row. Both reload the balances.
      headerActions={(reload) => <RecordCustomerDebtButton onChanged={reload} />}
      documentActions={(doc, party, compact, reload) => (
        <ReverseCustomerDebtButton doc={doc} partyName={party.partyName} compact={compact} onChanged={reload} />
      )}
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
      // 488: a customer debt is not a sale -- no sale page and no sale lines.
      documentHref={(doc) => doc.documentType === "CustomerDebt" ? null : `/generic-sales?saleId=${doc.documentId}`}
      onDocumentDetails={(doc) => { if (doc.documentType !== "CustomerDebt") setDetailSaleId(doc.documentId) }}
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

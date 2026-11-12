"use client"

// Water Customer Balances (Sales & Money → Customer Balances).
//
// Thin, like the poultry twin: everything lives in <BalancesPage>. All this
// file decides is which module it is, where a customer and a sale live, and
// which permission keys apply.

import { BalancesPage } from "@/components/balances/balances-page"
import { CustomerCreditPanel } from "@/components/sales/customer-credit-panel"
import { RecordCustomerDebtButton, ReverseCustomerDebtButton } from "@/components/balances/customer-debts-panel"

export default function WaterCustomerBalancesPage() {
  return (
    <BalancesPage
      module="water"
      side="customer"
      companyType="Water"
      // Deliberately empty. No water sale-payment path posts cash -- water cash
      // arrives through driver return reconciliation and daily closing -- so a
      // payment taken here must not either, or it double-counts against them
      // (see the CASH note in migration 227). With no accounts to offer, the
      // payment dialog simply doesn't show the picker, rather than showing a
      // control that silently does nothing.
      loadCashAccounts={async () => []}
      partyHref={() => "/water-customers"}
      // The water Sales page is a list with its own filters rather than a
      // per-sale route, so deep-link into it with the sale highlighted.
      documentHref={(doc) => `/water-sales?saleId=${doc.documentId}`}
      // 425: debts recorded by hand (owed without a sale). An open debt shows
      // among the customer's open items; recording is a header button,
      // reversing is on the debt's row (owner / admin).
      headerActions={(reload) => <RecordCustomerDebtButton onChanged={reload} />}
      documentActions={(doc, party, compact, reload) => (
        <ReverseCustomerDebtButton doc={doc} partyName={party.partyName} compact={compact} onChanged={reload} />
      )}
      // 424: customer credit (advances, left-over payments, opening credit,
      // credit notes) sits beside -- never netted into -- what is owed.
      afterTable={(_reload, paymentsVersion) => <CustomerCreditPanel refreshKey={paymentsVersion} />}
      permissions={{
        view: "water.customer-balances.view",
        pay: "water.customer-payments.create",
        reverse: "water.customer-payments.reverse",
        statement: "water.customer-statements.view",
      }}
    />
  )
}

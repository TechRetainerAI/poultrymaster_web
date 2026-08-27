"use client"

// Water Customer Balances (Sales & Money → Customer Balances).
//
// Thin, like the poultry twin: everything lives in <BalancesPage>. All this
// file decides is which module it is, where a customer and a sale live, and
// which permission keys apply.

import { BalancesPage } from "@/components/balances/balances-page"

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
      permissions={{
        view: "water.customer-balances.view",
        pay: "water.customer-payments.create",
        reverse: "water.customer-payments.reverse",
        statement: "water.customer-statements.view",
      }}
    />
  )
}

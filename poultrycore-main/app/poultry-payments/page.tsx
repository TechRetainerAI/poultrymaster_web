"use client"

// Poultry "Payments received".
//
// Thin: everything lives in <PaymentsReceivedPage>, which water and generic can
// reuse once they need it. All this file decides is which module it is, where a
// sale lives, and which permission keys apply.

import { PaymentsReceivedPage } from "@/components/payments/payments-received-page"

export default function PoultryPaymentsPage() {
  return (
    <PaymentsReceivedPage
      module="poultry"
      companyType="Poultry"
      // The Sales page is a list with its own filters rather than a per-sale
      // route, so deep-link into it with the sale highlighted.
      saleHref={(saleId) => `/sales?saleId=${saleId}`}
      permissions={{
        view: "poultry.customer-balances.view",
        reverse: "poultry.customer-payments.reverse",
      }}
    />
  )
}

"use client"

// Water "Payments received".
//
// Thin: everything lives in <PaymentsReceivedPage>, shared with poultry. All
// this file decides is which module it is, where a sale lives, and which
// permission keys apply.
//
// Water has the same grouped payment model poultry does (migration 227), so a
// bulk payment across several sales is ONE row here, expandable to show what
// each sale received — where this page used to list the underlying waterpayments
// rows, which are one per sale.

import { PaymentsReceivedPage } from "@/components/payments/payments-received-page"

export default function WaterPaymentsPage() {
  return (
    <PaymentsReceivedPage
      module="water"
      companyType="Water"
      // The water Sales page is a list with its own filters rather than a
      // per-sale route, so deep-link into it with the sale highlighted.
      saleHref={(saleId) => `/water-sales?saleId=${saleId}`}
      permissions={{
        view: "water.customer-balances.view",
        reverse: "water.customer-payments.reverse",
      }}
    />
  )
}

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
import { RecordCustomerPaymentButton } from "@/components/payments/record-customer-payment-button"
import { usePermissions } from "@/hooks/use-permissions"

export default function WaterPaymentsPage() {
  const { can } = usePermissions()
  return (
    <PaymentsReceivedPage
      module="water"
      companyType="Water"
      // The water Sales page is a list with its own filters rather than a
      // per-sale route, so deep-link into it with the sale highlighted.
      saleHref={(saleId) => `/water-sales?saleId=${saleId}`}
      // 424/425: a payment not tied to one sale -- spread over sales and debts,
      // kept as credit, or (ticked) an old debt from before the system on P&L.
      headerActions={(reload) => can("water.customer-payments.create")
        ? <RecordCustomerPaymentButton onPosted={reload} />
        : null}
      // 424: a hand-added credit is reversed or refunded on Customer Credits.
      manualCreditHref={(row) =>
        `/water-customer-credits?tab=manual&q=${encodeURIComponent(row.paymentNumber ?? row.partyName ?? "")}`}
      permissions={{
        view: "water.customer-balances.view",
        reverse: "water.customer-payments.reverse",
      }}
    />
  )
}

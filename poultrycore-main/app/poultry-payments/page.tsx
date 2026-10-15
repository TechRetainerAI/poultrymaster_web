"use client"

// Poultry "Payments received".
//
// Thin: everything lives in <PaymentsReceivedPage>, which water and generic can
// reuse once they need it. All this file decides is which module it is, where a
// sale lives, and which permission keys apply.

import { useState } from "react"
import { useRouter } from "next/navigation"
import { PaymentsReceivedPage } from "@/components/payments/payments-received-page"
import { SaleLinesDialog } from "@/components/sales/sale-lines-dialog"
import { RecordCustomerPaymentButton } from "@/components/payments/record-customer-payment-button"
import { usePermissions } from "@/hooks/use-permissions"

export default function PoultryPaymentsPage() {
  const router = useRouter()
  // Details on a payment: what was sold on the sale(s) it paid (358 lines).
  const [details, setDetails] = useState<{ saleIds: number[]; title: string } | null>(null)
  const { can } = usePermissions()
  return (
    <>
      <PaymentsReceivedPage
        module="poultry"
        companyType="Poultry"
        // The Sales page is a list with its own filters rather than a per-sale
        // route, so deep-link into it with the sale highlighted.
        saleHref={(saleId) => `/sales?saleId=${saleId}`}
        onSaleDetails={(saleIds, title) => setDetails({ saleIds, title })}
        // 367: a payment not tied to one sale -- spread over sales, kept as credit, or an advance.
        headerActions={(reload) => can("poultry.customer-payments.create")
          ? <RecordCustomerPaymentButton onPosted={reload} />
          : null}
        permissions={{
          view: "poultry.customer-balances.view",
          reverse: "poultry.customer-payments.reverse",
        }}
      />
      <SaleLinesDialog
        saleIds={details?.saleIds ?? null}
        title={details?.title}
        onOpenChange={(o) => { if (!o) setDetails(null) }}
        onOpenSale={(id) => router.push(`/sales?saleId=${id}`)}
      />
    </>
  )
}

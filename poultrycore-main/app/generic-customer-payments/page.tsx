"use client"

// Generic "Customer Payments" — deep copy of the poultry version.
//
// Uses the shared <PaymentsReceivedPage> for the full poultry-level experience:
// expandable allocations, sortable columns, summary cards, filters, details.
// The standalone Draft/Approve page this replaced had none of these.

import { useState } from "react"
import { useRouter } from "next/navigation"
import { PaymentsReceivedPage } from "@/components/payments/payments-received-page"
import { GenericSaleLinesDialog } from "@/components/generic/generic-sale-lines-dialog"
import { useProjectListFilter } from "@/components/generic/projects/use-project-list-filter"
import type { PaymentHistoryRow } from "@/lib/api/balances"

export default function GenericCustomerPaymentsPage() {
  const router = useRouter()
  const [details, setDetails] = useState<{ saleIds: number[]; title: string } | null>(null)
  // 493: a payment belongs to the projects of the sales it paid (and of its
  // designated advance). paymentId is the Generic customer payment id.
  const { extraFilter } = useProjectListFilter<PaymentHistoryRow>("CustomerPayment", (r) => Number(r.paymentId) || null)

  return (
    <>
      <PaymentsReceivedPage
        module="generic"
        companyType="Generic"
        title="Customer Payments"
        extraFilter={extraFilter}
        saleHref={(saleId) => `/generic-sales?saleId=${saleId}`}
        onSaleDetails={(saleIds, title) => setDetails({ saleIds, title })}
        manualCreditHref={(row) =>
          `/generic-customer-credits?q=${encodeURIComponent(row.paymentNumber ?? row.partyName ?? "")}`}
        permissions={{
          view: "generic.customer-balances.view",
          reverse: "generic.customer-payments.reverse",
        }}
      />
      <GenericSaleLinesDialog
        saleIds={details?.saleIds ?? null}
        onOpenChange={(o) => { if (!o) setDetails(null) }}
        onOpenSale={(id) => router.push(`/generic-sales?saleId=${id}`)}
      />
    </>
  )
}

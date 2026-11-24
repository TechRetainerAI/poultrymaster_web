"use client"

// Generic "Customer Payments" — deep copy of the poultry version.
//
// Uses the shared <PaymentsReceivedPage> for the full poultry-level experience:
// expandable allocations, sortable columns, summary cards, filters, details.
// The standalone Draft/Approve page this replaced had none of these.
//
// 488: "Record customer payment" in the header, as on Poultry (367): pick the
// customer, then the ordinary payment dialog opens on their open sales and
// customer debts. What is not applied is kept as their credit; a payment
// applied to nothing is an advance.

import { useState } from "react"
import { useRouter } from "next/navigation"
import { PaymentsReceivedPage } from "@/components/payments/payments-received-page"
import { RecordCustomerPaymentButton } from "@/components/payments/record-customer-payment-button"
import { GenericSaleLinesDialog } from "@/components/generic/generic-sale-lines-dialog"
import { usePermissions } from "@/hooks/use-permissions"

export default function GenericCustomerPaymentsPage() {
  const router = useRouter()
  const { can } = usePermissions()
  const [details, setDetails] = useState<{ saleIds: number[]; title: string } | null>(null)

  return (
    <>
      <PaymentsReceivedPage
        module="generic"
        companyType="Generic"
        title="Customer Payments"
        saleHref={(saleId) => `/generic-sales?saleId=${saleId}`}
        onSaleDetails={(saleIds, title) => setDetails({ saleIds, title })}
        // 488 (Poultry 367): a payment not tied to one sale -- spread over sales and
        // debts, kept as credit, or an advance.
        headerActions={(reload) => can("generic.customer-payments.create")
          ? <RecordCustomerPaymentButton onPosted={reload} />
          : null}
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

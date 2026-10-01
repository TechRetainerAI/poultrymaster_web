"use client"

// Hotel "Payments" (Sales, Expenses & Money → Payments).
//
// The Poultry page (app/poultry-payments) on the shared PaymentsReceivedPage:
// one row per payment actually received -- a guest paying at the desk, or a
// corporate account settling several stays at once -- with its allocation and
// Reverse ("Why is this being reversed?"). Migration 332. Payments are taken on
// Sales, Customer Balances or the Billing page.

import { PaymentsReceivedPage } from "@/components/payments/payments-received-page"
import { HOTEL_CUSTOMER_PERMISSIONS, HOTEL_ICON_CLASS } from "@/lib/hotel/balances"

export default function HotelPaymentsPage() {
  return (
    <PaymentsReceivedPage
      module="hotel"
      companyType="Hotel"
      iconClassName={HOTEL_ICON_CLASS}
      saleHref={(bookingId) => `/hotel-sales?bookingId=${bookingId}`}
      permissions={{ view: HOTEL_CUSTOMER_PERMISSIONS.view, reverse: HOTEL_CUSTOMER_PERMISSIONS.reverse }}
    />
  )
}

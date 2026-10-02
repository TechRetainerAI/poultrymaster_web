"use client"

// Restaurant "Payments" (Sales, Expenses & Money → Payments).
//
// The Poultry page (app/poultry-payments) on the shared PaymentsReceivedPage:
// one row per payment actually received -- a payment taken on an order at the
// till (OP-n) or a customer settling pay-later orders (CP-n) -- with its
// allocation and Reverse ("Why is this being reversed?"). Migration 333.
// The Income & Expenses view that used to live here is /restaurant-income-expenses.

import { PaymentsReceivedPage } from "@/components/payments/payments-received-page"
import { RESTAURANT_CUSTOMER_PERMISSIONS, RESTAURANT_ICON_CLASS, restaurantOrderHref } from "@/lib/restaurant/balances"

export default function RestaurantPaymentsPage() {
  return (
    <PaymentsReceivedPage
      module="restaurant"
      pagerVariant="records"
      companyType="Restaurant"
      iconClassName={RESTAURANT_ICON_CLASS}
      saleHref={restaurantOrderHref}
      permissions={{ view: RESTAURANT_CUSTOMER_PERMISSIONS.view, reverse: RESTAURANT_CUSTOMER_PERMISSIONS.reverse }}
    />
  )
}

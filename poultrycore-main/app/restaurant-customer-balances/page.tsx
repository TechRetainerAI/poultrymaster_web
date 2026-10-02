"use client"

// Restaurant Customer Balances (Sales, Expenses & Money → Customer Balances).
//
// The Poultry page (app/customer-balances) on the shared BalancesPage. Who owes
// the restaurant: saved customers with pay-later orders not yet fully paid
// (migration 333). Receiving a payment allocates it across that customer's
// open orders, oldest first, as one cash movement.

import { BalancesPage } from "@/components/balances/balances-page"
import {
  RESTAURANT_CUSTOMER_PERMISSIONS, RESTAURANT_ICON_CLASS, loadRestaurantCashAccounts, restaurantOrderHref,
} from "@/lib/restaurant/balances"

export default function RestaurantCustomerBalancesPage() {
  return (
    <BalancesPage
      module="restaurant"
      pagerVariant="records"
      side="customer"
      companyType="Restaurant"
      iconClassName={RESTAURANT_ICON_CLASS}
      loadCashAccounts={loadRestaurantCashAccounts}
      partyHref={() => "/restaurant-crm"}
      documentHref={(doc) => restaurantOrderHref(doc.documentId)}
      permissions={RESTAURANT_CUSTOMER_PERMISSIONS}
    />
  )
}

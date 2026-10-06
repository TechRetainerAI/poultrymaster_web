"use client"

// Hotel Customer Balances (Sales, Expenses & Money → Customer Balances).
//
// The Poultry page (app/customer-balances) on the shared BalancesPage. Who owes
// the hotel: guests with an open bill (in house or checked out) and corporate
// accounts with stays billed to them or an opening balance (migration 332).

import { BalancesPage } from "@/components/balances/balances-page"
import {
  HOTEL_CUSTOMER_PERMISSIONS, HOTEL_ICON_CLASS, hotelCustomerDocumentHref, hotelPartyHref, loadHotelCashAccounts,
} from "@/lib/hotel/balances"

export default function HotelCustomerBalancesPage() {
  return (
    <BalancesPage
      module="hotel"
      pagerVariant="records"
      side="customer"
      companyType="Hotel"
      iconClassName={HOTEL_ICON_CLASS}
      loadCashAccounts={() => loadHotelCashAccounts()}
      partyHref={hotelPartyHref}
      documentHref={(doc) => hotelCustomerDocumentHref(doc.documentType, doc.documentId)}
      permissions={HOTEL_CUSTOMER_PERMISSIONS}
    />
  )
}

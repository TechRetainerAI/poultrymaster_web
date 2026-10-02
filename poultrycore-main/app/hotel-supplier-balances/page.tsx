"use client"

// Hotel Supplier Balances (Sales, Expenses & Money → Supplier Balances).
//
// The Poultry page (app/supplier-balances) on the shared BalancesPage. What the
// hotel owes: approved Credit expenses naming a supplier, the unpaid part of
// capital asset costs, and suppliers' opening balances (migration 332).

import { BalancesPage } from "@/components/balances/balances-page"
import {
  HOTEL_ICON_CLASS, HOTEL_SUPPLIER_PERMISSIONS, hotelPayableHref, loadHotelCashAccounts,
} from "@/lib/hotel/balances"

export default function HotelSupplierBalancesPage() {
  return (
    <BalancesPage
      module="hotel"
      pagerVariant="records"
      side="supplier"
      companyType="Hotel"
      iconClassName={HOTEL_ICON_CLASS}
      loadCashAccounts={() => loadHotelCashAccounts()}
      partyHref={() => "/hotel-suppliers"}
      documentHref={(doc) => hotelPayableHref(doc.documentType, doc.documentId)}
      permissions={HOTEL_SUPPLIER_PERMISSIONS}
    />
  )
}

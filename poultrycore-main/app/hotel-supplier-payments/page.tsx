"use client"

// Hotel Supplier Payments (Sales, Expenses & Money → Supplier Payments).
//
// The Poultry page (app/supplier-payments) on the shared PaymentsLedgerPage:
// the ledger of money actually paid out, as opposed to Supplier Balances, which
// is what is still owed. Payments post when recorded, as Poultry's do; the old
// Draft -> Approve screen is gone (its API still works and now allocates the
// payment oldest-first through the same function -- migration 332).

import { PaymentsLedgerPage } from "@/components/balances/payments-ledger-page"
import {
  HOTEL_ICON_CLASS, HOTEL_SUPPLIER_PERMISSIONS, hotelPayableHref, loadHotelCashAccounts,
} from "@/lib/hotel/balances"

export default function HotelSupplierPaymentsPage() {
  return (
    <PaymentsLedgerPage
      module="hotel"
      pagerVariant="records"
      companyType="Hotel"
      iconClassName={HOTEL_ICON_CLASS}
      loadCashAccounts={async () => (await loadHotelCashAccounts(false)).map((a) => ({ id: a.id, name: a.name }))}
      partyHref={() => "/hotel-suppliers"}
      documentHref={(a) => hotelPayableHref(a.documentType, a.documentId)}
      permissions={{ view: HOTEL_SUPPLIER_PERMISSIONS.view, reverse: HOTEL_SUPPLIER_PERMISSIONS.reverse }}
    />
  )
}

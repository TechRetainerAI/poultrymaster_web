"use client"

// Supplier payments -- every payment made to suppliers, with the purchase or
// later. Like poultry's Supplier Payments page.

import { Receipt } from "lucide-react"
import { LivestockPage } from "@/components/livestock/livestock-page"
import { PaymentsList } from "@/components/livestock/payments-list"

export default function LivestockSupplierPaymentsPage() {
  return (
    <LivestockPage title="Supplier payments" description="Money paid to suppliers." icon={Receipt}>
      <PaymentsList direction="supplier" />
    </LivestockPage>
  )
}

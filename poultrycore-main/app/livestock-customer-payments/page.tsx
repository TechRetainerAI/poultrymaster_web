"use client"

// Customer payments -- every payment received from customers, with the sale
// or later. Like poultry's Customer Payments page.

import { HandCoins } from "lucide-react"
import { LivestockPage } from "@/components/livestock/livestock-page"
import { PaymentsList } from "@/components/livestock/payments-list"

export default function LivestockCustomerPaymentsPage() {
  return (
    <LivestockPage title="Customer payments" description="Money received from customers." icon={HandCoins}>
      <PaymentsList direction="customer" />
    </LivestockPage>
  )
}

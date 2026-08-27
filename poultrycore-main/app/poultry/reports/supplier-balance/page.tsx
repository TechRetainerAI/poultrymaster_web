"use client"

// Advanced Poultry Report route: /poultry/reports/supplier-balance
//
// The read/export/print view of the same payables the Supplier Balances page
// works from — both read sppoultrysupplierbalances, so they cannot disagree.
import { PoultryReportView } from "@/components/poultry-reports/poultry-report-view"

export default function PoultrySupplierBalanceReport() {
  return <PoultryReportView slug="supplier-balance" />
}

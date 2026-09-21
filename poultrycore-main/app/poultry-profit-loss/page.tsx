"use client"

// Profit & Loss as a MONEY PAGE: /poultry-profit-loss
//
// The same statement as /poultry/reports/profit-loss, in a different frame.
// This one sits in the Money group beside Cash Flow, Expenses and Financial
// Activity -- it is not a report, so it has a plain page header and NO back
// button. There is no catalogue behind it to go back to.
//
// The report skin, with the catalogue chrome and its back button, lives on the
// /poultry/reports/profit-loss route. Both render the same component, because
// the FIGURES must never differ between them.
import { PoultryProfitLossView } from "@/components/poultry-reports/poultry-profit-loss-view"

export default function PoultryProfitLossPage() {
  return <PoultryProfitLossView chrome="page" />
}

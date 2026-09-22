"use client"

// Profit & Loss as a MONEY PAGE: /water-profit-loss
//
// The same statement as /water-reports/profit-loss, in a different frame. This
// one sits in the Money group beside Cash Flow, Owner Money and Loans -- it is
// not a report, so it has a plain page header and NO back button. There is no
// catalogue behind it to go back to.
import { WaterProfitLossView } from "@/components/water-reports/water-profit-loss-view"

export default function WaterProfitLossPage() {
  return <WaterProfitLossView chrome="page" />
}

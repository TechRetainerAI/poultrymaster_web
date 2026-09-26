"use client"

// Profit & Loss as a REPORT: /water-reports/profit-loss
//
// The catalogue skin -- report chrome, and a back button to /water-reports.
// The Money-page skin is the same component on /water-profit-loss.
import { WaterProfitLossView } from "@/components/water-reports/water-profit-loss-view"

export default function WaterProfitLossReportPage() {
  return <WaterProfitLossView chrome="report" />
}

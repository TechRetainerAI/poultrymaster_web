"use client"

// Advanced Poultry Report route: /poultry/reports/profit-loss
// Company-wide Profit & Loss (all sales/expenses; not attributed per flock).
import { PoultryReportView } from "@/components/poultry-reports/poultry-report-view"

export default function PoultryProfitLossReport() {
  return <PoultryReportView slug="profit-loss" />
}

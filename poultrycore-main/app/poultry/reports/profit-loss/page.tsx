"use client"

// Advanced Poultry Report route: /poultry/reports/profit-loss
//
// Since migration 272 this is a STATEMENT, not a table -- Revenue, Gross
// Profit, Operating Profit, Net Profit, with Financing & Owner Activity and
// Capital Investments printed beside it and never inside it -- so it has its
// own view rather than riding the shared report engine.
import { PoultryProfitLossView } from "@/components/poultry-reports/poultry-profit-loss-view"

export default function PoultryProfitLossReport() {
  return <PoultryProfitLossView />
}

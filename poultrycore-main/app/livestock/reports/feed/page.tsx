"use client"

import { Wheat } from "lucide-react"
import { getFeedReport } from "@/lib/api/livestock"
import { UsageReportPage } from "@/components/livestock/usage-report"

export default function LivestockFeedReportPage() {
  return <UsageReportPage title="Feed used" description="Feed used by item and by group." icon={Wheat} fetcher={getFeedReport} />
}

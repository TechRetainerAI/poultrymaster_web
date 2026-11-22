"use client"

import { Pill } from "lucide-react"
import { getMedicineReport } from "@/lib/api/livestock"
import { UsageReportPage } from "@/components/livestock/usage-report"

export default function LivestockMedicineReportPage() {
  return <UsageReportPage title="Medicine used" description="Medicine and vaccines used, and illnesses seen." icon={Pill} fetcher={getMedicineReport} medicine />
}

"use client"

// Pens -- houses, hutches, sties, paddocks and kraals, with how many animals
// each holds. Owner/admin only for changes.

import { Warehouse } from "lucide-react"
import { LivestockPage } from "@/components/livestock/livestock-page"
import { PensView } from "@/components/livestock/pens-view"

export default function LivestockPensPage() {
  return (
    <LivestockPage title="Pens" description="Where your animals live, and how many each holds." icon={Warehouse}>
      <PensView />
    </LivestockPage>
  )
}

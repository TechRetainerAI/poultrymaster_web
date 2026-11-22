"use client"

// Animals kept -- which kinds of animal the farm keeps. Turns the egg, milk
// and breeding pages on or off. Owner/admin only for changes.

import { PawPrint } from "lucide-react"
import { LivestockPage } from "@/components/livestock/livestock-page"
import { SpeciesKept } from "@/components/livestock/species-kept"

export default function LivestockAnimalsKeptPage() {
  return (
    <LivestockPage title="Animals kept" description="The kinds of animal on this farm. Pages for eggs, milk and breeding follow what you tick." icon={PawPrint}>
      <SpeciesKept />
    </LivestockPage>
  )
}

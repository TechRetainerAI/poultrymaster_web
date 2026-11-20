"use client"

import { useEffect, useState } from "react"
import { ClipboardList } from "lucide-react"
import { LivestockPage } from "@/components/livestock/livestock-page"
import { ProductionRecordForm } from "@/components/livestock/production-record-form"

// ?groupId= and ?date= preselect, so "no record yet today" links land ready.
export default function NewLivestockProductionRecordPage() {
  const [preset, setPreset] = useState<{ groupId: number | null; date: string | null } | null>(null)
  useEffect(() => {
    const p = new URLSearchParams(window.location.search)
    setPreset({ groupId: p.get("groupId") ? Number(p.get("groupId")) : null, date: p.get("date") })
  }, [])
  return (
    <LivestockPage title="New daily record" icon={ClipboardList} back={{ href: "/livestock-production-records", label: "Daily records" }}>
      {preset && <ProductionRecordForm presetGroupId={preset.groupId} presetDate={preset.date} />}
    </LivestockPage>
  )
}

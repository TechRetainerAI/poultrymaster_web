"use client"

// Full-page ADD production record, like poultry's /production-records/new.
// The modal on the list is the default way in; this route is for people who
// want the room, for direct links, and for "no record yet today" links. It
// renders the SAME form the modal does.
//
// ?groupId= and ?date= preselect.

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { ClipboardList, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { LivestockPage } from "@/components/livestock/livestock-page"
import { ProductionRecordForm } from "@/components/livestock/production-record-form"

export default function NewLivestockProductionRecordPage() {
  const router = useRouter()
  const [preset, setPreset] = useState<{ groupId: number | null; date: string | null } | null>(null)
  useEffect(() => {
    const p = new URLSearchParams(window.location.search)
    setPreset({ groupId: p.get("groupId") ? Number(p.get("groupId")) : null, date: p.get("date") })
  }, [])
  const toList = () => router.push("/livestock-production-records")
  return (
    <LivestockPage
      title="Add Production Record"
      description="A group's day: produce, deaths and culls, and the feed and medicine used."
      icon={ClipboardList}
      actions={<Button size="sm" className="gap-1.5 bg-red-600 text-white hover:bg-red-700" onClick={toList}><X className="h-4 w-4" /> Close</Button>}
    >
      {preset && <ProductionRecordForm presetGroupId={preset.groupId} presetDate={preset.date} onSaved={toList} onCancel={toList} />}
    </LivestockPage>
  )
}

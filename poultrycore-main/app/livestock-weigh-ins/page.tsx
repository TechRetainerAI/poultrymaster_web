"use client"

// Weigh-ins & Growth -- the poultry weigh-ins / broiler performance page for
// livestock. Pick a group; see its weights, gain per day and feed per kg gained.

import { useEffect, useState } from "react"
import { Scale } from "lucide-react"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { listGroups, type LivestockGroup } from "@/lib/api/livestock"
import { GrowthPanel } from "@/components/livestock/growth-panel"
import { EmptyState, LivestockPage, Loading } from "@/components/livestock/livestock-page"

export default function LivestockWeighInsPage() {
  const [groups, setGroups] = useState<LivestockGroup[] | null>(null)
  const [groupId, setGroupId] = useState<number | null>(null)

  useEffect(() => {
    listGroups(true).then((gs) => {
      setGroups(gs)
      const fromUrl = Number(new URLSearchParams(window.location.search).get("groupId"))
      setGroupId(gs.find((g) => g.groupId === fromUrl)?.groupId ?? gs.find((g) => g.status === "Active")?.groupId ?? null)
    }).catch(() => setGroups([]))
  }, [])

  const group = groups?.find((g) => g.groupId === groupId)
  return (
    <LivestockPage title="Weigh-ins & growth" description="How fast each group grows, and how much feed each kg of growth takes." icon={Scale}>
      {!groups ? <Loading /> : groups.length === 0 ? <EmptyState title="No groups yet" /> : (
        <>
          <Select value={groupId ? String(groupId) : ""} onValueChange={(v) => setGroupId(Number(v))}>
            <SelectTrigger className="w-72"><SelectValue placeholder="Choose a group" /></SelectTrigger>
            <SelectContent>
              {groups.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.speciesName}{g.status === "Closed" ? " (closed)" : ""}</SelectItem>)}
            </SelectContent>
          </Select>
          {group && <GrowthPanel key={group.groupId} groupId={group.groupId} groupStart={group.startDate} canRecord={group.status === "Active"} />}
        </>
      )}
    </LivestockPage>
  )
}

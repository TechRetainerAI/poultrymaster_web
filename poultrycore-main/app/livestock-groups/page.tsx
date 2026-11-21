"use client"

// Animal Groups -- the poultry Flocks page for livestock. One row per group:
// its animal, pen, head now (from the head ledger), tagged animals and age.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Layers, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listGroups, type LivestockGroup } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { GroupFormDialog } from "@/components/livestock/group-form-dialog"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtAge, fmtDate, fmtNum,
} from "@/components/livestock/livestock-page"

const ALL = "__all"

export default function LivestockGroupsPage() {
  const router = useRouter()
  const { kept, loaded } = useLivestockSpecies()
  const [groups, setGroups] = useState<LivestockGroup[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [includeClosed, setIncludeClosed] = useState(false)
  const [species, setSpecies] = useState(ALL)
  const [creating, setCreating] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try { setGroups(await listGroups(includeClosed)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [includeClosed])
  useEffect(() => { load() }, [load])

  const shown = useMemo(() => (groups ?? []).filter((g) => species === ALL || g.speciesCode === species), [groups, species])
  const totals = useMemo(() => {
    const active = shown.filter((g) => g.status === "Active")
    return { groups: active.length, head: active.reduce((s, g) => s + g.head, 0), tagged: active.reduce((s, g) => s + g.tagged, 0) }
  }, [shown])

  return (
    <LivestockPage
      title="Animal groups"
      description="Animals kept and recorded together."
      icon={Layers}
      actions={
        <Button className={AMBER_BUTTON} disabled={loaded && kept.length === 0} onClick={() => setCreating(true)}>
          <Plus className="h-4 w-4 mr-1" /> New group
        </Button>
      }
    >
      {loaded && kept.length === 0 && (
        <EmptyState title="Choose the animals your farm keeps first"
          action={<Button asChild className={AMBER_BUTTON}><Link href="/livestock-animals-kept">Choose your animals</Link></Button>}>
          Groups are made for a kind of animal, so pick the kinds you keep in Farm setup.
        </EmptyState>
      )}

      <div className="grid grid-cols-3 gap-3">
        <StatCard label="Active groups" value={fmtNum(totals.groups)} tone="amber" />
        <StatCard label="Animals" value={fmtNum(totals.head)} />
        <StatCard label="Tagged" value={fmtNum(totals.tagged)} />
      </div>

      <div className="flex items-center gap-3 flex-wrap">
        <Select value={species} onValueChange={setSpecies}>
          <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All animals</SelectItem>
            {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
          </SelectContent>
        </Select>
        <label className="flex items-center gap-2 text-sm text-stone-600">
          <Switch checked={includeClosed} onCheckedChange={setIncludeClosed} /> Show closed groups
        </label>
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !groups ? <Loading /> : shown.length === 0 ? (
        <EmptyState title="No groups yet">Create a group for animals already on the farm, or divide an intake batch.</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Group</TableHead>
                <TableHead>Animal</TableHead>
                <TableHead>Pen</TableHead>
                <TableHead className="text-right">Animals now</TableHead>
                <TableHead className="text-right">Tagged</TableHead>
                <TableHead className="text-right">Deaths</TableHead>
                <TableHead>Started</TableHead>
                <TableHead>Age of group</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {shown.map((g) => (
                <TableRow key={g.groupId} className="cursor-pointer hover:bg-amber-50/60"
                  onClick={() => router.push(`/livestock-groups/${g.groupId}`)}>
                  <TableCell className="font-medium">
                    <Link href={`/livestock-groups/${g.groupId}`} className="hover:underline" onClick={(e) => e.stopPropagation()}>{g.name}</Link>
                    {g.status === "Closed" && <Badge variant="outline" className="ml-2">Closed</Badge>}
                    {g.batchCode && <div className="text-xs text-stone-500">Batch {g.batchCode}</div>}
                  </TableCell>
                  <TableCell>{g.speciesName}</TableCell>
                  <TableCell>{g.penName ?? "—"}</TableCell>
                  <TableCell className="text-right font-medium">
                    {fmtNum(g.head)} <span className="text-xs text-stone-400">of {fmtNum(g.placed)}</span>
                  </TableCell>
                  <TableCell className="text-right">{fmtNum(g.tagged)}</TableCell>
                  <TableCell className="text-right">{fmtNum(g.deaths)}</TableCell>
                  <TableCell>{fmtDate(g.startDate)}</TableCell>
                  <TableCell>{fmtAge(g.ageDays)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <GroupFormDialog open={creating} onOpenChange={setCreating} onSaved={(id) => router.push(`/livestock-groups/${id}`)} />
    </LivestockPage>
  )
}

"use client"

// Animal Groups -- the poultry Flocks page for livestock. One row per group:
// its animal, pen, head now (from the head ledger), tagged animals and age.
// Filters match the Animal register: search, kind, status, pen, breed,
// purpose, tagging and age.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Layers, Plus, Search, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listGroups, type GroupPurpose, type LivestockGroup } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { GroupFormDialog } from "@/components/livestock/group-form-dialog"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtAge, fmtDate, fmtNum,
} from "@/components/livestock/livestock-page"

const ALL = "__all"
const NONE = "__none"

const PURPOSES: GroupPurpose[] = ["Meat", "Eggs", "Milk", "Breeding", "Mixed"]
type TaggingFilter = typeof ALL | "all" | "some" | "none"
const AGES = [
  { key: "u6m", label: "Under 6 months", test: (d: number) => d < 183 },
  { key: "6to12m", label: "6 to 12 months", test: (d: number) => d >= 183 && d < 365 },
  { key: "1to2y", label: "1 to 2 years", test: (d: number) => d >= 365 && d < 730 },
  { key: "o2y", label: "Over 2 years", test: (d: number) => d >= 730 },
] as const

export default function LivestockGroupsPage() {
  const router = useRouter()
  const { kept, loaded } = useLivestockSpecies()
  const [groups, setGroups] = useState<LivestockGroup[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [status, setStatus] = useState<"Active" | "Closed" | "All">("Active")
  const includeClosed = status !== "Active"
  const [species, setSpecies] = useState(ALL)
  const [search, setSearch] = useState("")
  const [pen, setPen] = useState(ALL)
  const [breed, setBreed] = useState(ALL)
  const [purpose, setPurpose] = useState<GroupPurpose | typeof ALL>(ALL)
  const [tagging, setTagging] = useState<TaggingFilter>(ALL)
  const [age, setAge] = useState(ALL)
  const [creating, setCreating] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try { setGroups(await listGroups(includeClosed)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [includeClosed])
  useEffect(() => { load() }, [load])

  const ofKind = useMemo(() => (groups ?? []).filter((g) => species === ALL || g.speciesCode === species), [groups, species])
  const pens = useMemo(() => [...new Set(ofKind.map((g) => g.penName).filter((x): x is string => !!x))].sort(), [ofKind])
  const breeds = useMemo(() => [...new Set(ofKind.map((g) => g.breed).filter((x): x is string => !!x))].sort(), [ofKind])
  const shown = useMemo(() => {
    const q = search.trim().toLowerCase()
    return ofKind.filter((g) => {
      if (status !== "All" && g.status !== status) return false
      if (q && !`${g.name} ${g.batchCode ?? ""}`.toLowerCase().includes(q)) return false
      if (pen === NONE ? !!g.penName : pen !== ALL && g.penName !== pen) return false
      if (breed === NONE ? !!g.breed : breed !== ALL && g.breed !== breed) return false
      if (purpose !== ALL && g.purpose !== purpose) return false
      if (tagging === "all" && !(g.head > 0 && g.tagged >= g.head)) return false
      if (tagging === "some" && !(g.tagged > 0 && g.tagged < g.head)) return false
      if (tagging === "none" && g.tagged > 0) return false
      if (age !== ALL) {
        const band = AGES.find((x) => x.key === age)
        if (!band?.test(g.ageDays)) return false
      }
      return true
    })
  }, [ofKind, status, search, pen, breed, purpose, tagging, age])
  const pg = usePagination(shown, 10)
  const filtering = !!search || species !== ALL || status !== "Active" || pen !== ALL || breed !== ALL || purpose !== ALL || tagging !== ALL || age !== ALL
  const clear = () => {
    setSearch(""); setSpecies(ALL); setStatus("Active"); setPen(ALL); setBreed(ALL); setPurpose(ALL); setTagging(ALL); setAge(ALL)
  }
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
        <div className="relative">
          <Search className="h-4 w-4 absolute left-2.5 top-2.5 text-stone-400" />
          <Input className="pl-8 w-56" placeholder="Group name or batch" value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>
        <Select value={species} onValueChange={(v) => { setSpecies(v); setPen(ALL); setBreed(ALL) }}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All animals</SelectItem>
            {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={status} onValueChange={(v) => setStatus(v as typeof status)}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="Active">Active groups</SelectItem>
            <SelectItem value="Closed">Closed groups</SelectItem>
            <SelectItem value="All">All groups</SelectItem>
          </SelectContent>
        </Select>
        <Select value={pen} onValueChange={setPen}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any pen</SelectItem>
            {pens.map((x) => <SelectItem key={x} value={x}>{x}</SelectItem>)}
            <SelectItem value={NONE}>No pen</SelectItem>
          </SelectContent>
        </Select>
        <Select value={breed} onValueChange={setBreed}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any breed</SelectItem>
            {breeds.map((x) => <SelectItem key={x} value={x}>{x}</SelectItem>)}
            <SelectItem value={NONE}>Breed not given</SelectItem>
          </SelectContent>
        </Select>
        <Select value={purpose} onValueChange={(v) => setPurpose(v as GroupPurpose | typeof ALL)}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any purpose</SelectItem>
            {PURPOSES.map((x) => <SelectItem key={x} value={x}>{x}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={tagging} onValueChange={(v) => setTagging(v as TaggingFilter)}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any tagging</SelectItem>
            <SelectItem value="all">All animals tagged</SelectItem>
            <SelectItem value="some">Some tagged</SelectItem>
            <SelectItem value="none">None tagged</SelectItem>
          </SelectContent>
        </Select>
        <Select value={age} onValueChange={setAge}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any age</SelectItem>
            {AGES.map((x) => <SelectItem key={x.key} value={x.key}>{x.label}</SelectItem>)}
          </SelectContent>
        </Select>
        {filtering && (
          <Button variant="ghost" size="sm" className="text-amber-800" onClick={clear}><X className="h-4 w-4 mr-1" />Clear filters</Button>
        )}
        {groups && (
          <span className="ml-auto text-sm text-stone-500">
            {filtering ? `${shown.length} of ${groups.filter((g) => status === "All" || g.status === status).length} groups` : `${shown.length} groups`}
          </span>
        )}
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !groups ? <Loading /> : shown.length === 0 ? (
        filtering
          ? <EmptyState title="No group matches">Try other filters, or clear them.</EmptyState>
          : <EmptyState title="No groups yet">Create a group for animals already on the farm, or divide an intake batch.</EmptyState>
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
              {pg.pageItems.map((g) => (
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
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}

      <GroupFormDialog open={creating} onOpenChange={setCreating} onSaved={(id) => router.push(`/livestock-groups/${id}`)} />
    </LivestockPage>
  )
}

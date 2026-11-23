"use client"

// Animal Register -- every tagged animal, searchable by tag or name.
// Kind, status and group are asked of the server; sex, breed, parents and age
// narrow the loaded list here.

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { Search, Tag, Tags, Users, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listAnimals, listGroups, type AnimalSex, type AnimalStatus, type LivestockAnimal, type LivestockGroup } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { TagManyDialog } from "@/components/livestock/tag-many-dialog"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtAge } from "@/components/livestock/livestock-page"

const ALL = "__all"
const NONE = "__none"

type ParentsFilter = typeof ALL | "both" | "mother" | "father" | "none"
const AGES = [
  { key: "u6m", label: "Under 6 months", test: (d: number) => d < 183 },
  { key: "6to12m", label: "6 to 12 months", test: (d: number) => d >= 183 && d < 365 },
  { key: "1to2y", label: "1 to 2 years", test: (d: number) => d >= 365 && d < 730 },
  { key: "o2y", label: "Over 2 years", test: (d: number) => d >= 730 },
] as const

export default function LivestockAnimalsPage() {
  const router = useRouter()
  const { kept } = useLivestockSpecies()
  const [animals, setAnimals] = useState<LivestockAnimal[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [species, setSpecies] = useState(ALL)
  const [status, setStatus] = useState<AnimalStatus | "All">("Active")
  const [search, setSearch] = useState("")
  const [term, setTerm] = useState("")
  const [tagMany, setTagMany] = useState(false)
  const [tagParents, setTagParents] = useState(false)
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [groupId, setGroupId] = useState(ALL)
  const [sex, setSex] = useState<AnimalSex | typeof ALL>(ALL)
  const [breed, setBreed] = useState(ALL)
  const [parentsF, setParentsF] = useState<ParentsFilter>(ALL)
  const [age, setAge] = useState(ALL)

  useEffect(() => { listGroups().then(setGroups).catch(() => setGroups([])) }, [])
  // Groups of the chosen kind; a group of another kind is let go.
  const groupOptions = groups.filter((g) => species === ALL || g.speciesCode === species)
  useEffect(() => {
    if (groupId !== ALL && !groupOptions.some((g) => String(g.groupId) === groupId)) setGroupId(ALL)
  }, [species, groups]) // eslint-disable-line react-hooks/exhaustive-deps

  // Search waits for a pause in typing.
  useEffect(() => { const t = setTimeout(() => setTerm(search.trim()), 300); return () => clearTimeout(t) }, [search])

  const load = useCallback(async () => {
    setError(null)
    try {
      setAnimals(await listAnimals({
        speciesCode: species === ALL ? undefined : species, status, search: term || undefined,
        groupId: groupId === ALL ? undefined : Number(groupId),
      }))
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [species, status, term, groupId])
  useEffect(() => { load() }, [load])

  const breeds = useMemo(() => [...new Set((animals ?? []).map((a) => a.breed).filter((b): b is string => !!b))].sort(), [animals])
  const shown = useMemo(() => (animals ?? []).filter((a) => {
    if (sex !== ALL && a.sex !== sex) return false
    if (breed === NONE ? !!a.breed : breed !== ALL && a.breed !== breed) return false
    if (parentsF === "both" && !(a.damId && a.sireId)) return false
    if (parentsF === "mother" && !a.damId) return false
    if (parentsF === "father" && !a.sireId) return false
    if (parentsF === "none" && (a.damId || a.sireId)) return false
    if (age === NONE) return a.ageDays == null
    if (age !== ALL) {
      const band = AGES.find((x) => x.key === age)
      if (a.ageDays == null || !band?.test(a.ageDays)) return false
    }
    return true
  }), [animals, sex, breed, parentsF, age])
  const pg = usePagination(shown, 10)
  const filtering = !!search || species !== ALL || status !== "Active" || groupId !== ALL || sex !== ALL || breed !== ALL || parentsF !== ALL || age !== ALL
  const clear = () => {
    setSearch(""); setSpecies(ALL); setStatus("Active"); setGroupId(ALL); setSex(ALL); setBreed(ALL); setParentsF(ALL); setAge(ALL)
  }

  return (
    <LivestockPage
      title="Animal register"
      description="Tagged animals: who they are, where they are, and their parents."
      icon={Tag}
      actions={
        <div className="flex gap-2">
          <Button variant="outline" className="border-amber-300 bg-amber-50 text-amber-900 hover:bg-amber-100" onClick={() => setTagParents(true)}><Users className="h-4 w-4 mr-1" /> Tag parents</Button>
          <Button className={AMBER_BUTTON} onClick={() => setTagMany(true)}><Tags className="h-4 w-4 mr-1" /> Tag several</Button>
        </div>
      }
    >
      <div className="flex items-center gap-3 flex-wrap">
        <div className="relative">
          <Search className="h-4 w-4 absolute left-2.5 top-2.5 text-stone-400" />
          <Input className="pl-8 w-56" placeholder="Tag or name" value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>
        <Select value={species} onValueChange={setSpecies}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All animals</SelectItem>
            {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={status} onValueChange={(v) => setStatus(v as AnimalStatus | "All")}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="Active">Alive on farm</SelectItem>
            <SelectItem value="Sold">Sold</SelectItem>
            <SelectItem value="Dead">Died</SelectItem>
            <SelectItem value="Culled">Culled</SelectItem>
            <SelectItem value="All">All</SelectItem>
          </SelectContent>
        </Select>
        <Select value={groupId} onValueChange={setGroupId}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All groups</SelectItem>
            {groupOptions.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={sex} onValueChange={(v) => setSex(v as AnimalSex | typeof ALL)}>
          <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any sex</SelectItem>
            <SelectItem value="Female">Female</SelectItem>
            <SelectItem value="Male">Male</SelectItem>
            <SelectItem value="Unknown">Sex not known</SelectItem>
          </SelectContent>
        </Select>
        <Select value={breed} onValueChange={setBreed}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any breed</SelectItem>
            {breeds.map((b) => <SelectItem key={b} value={b}>{b}</SelectItem>)}
            <SelectItem value={NONE}>Breed not given</SelectItem>
          </SelectContent>
        </Select>
        <Select value={parentsF} onValueChange={(v) => setParentsF(v as ParentsFilter)}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any parents</SelectItem>
            <SelectItem value="both">Both parents known</SelectItem>
            <SelectItem value="mother">Mother known</SelectItem>
            <SelectItem value="father">Father known</SelectItem>
            <SelectItem value="none">No parent known</SelectItem>
          </SelectContent>
        </Select>
        <Select value={age} onValueChange={setAge}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any age</SelectItem>
            {AGES.map((x) => <SelectItem key={x.key} value={x.key}>{x.label}</SelectItem>)}
            <SelectItem value={NONE}>Age not known</SelectItem>
          </SelectContent>
        </Select>
        {filtering && (
          <Button variant="ghost" size="sm" className="text-amber-800" onClick={clear}><X className="h-4 w-4 mr-1" />Clear filters</Button>
        )}
        {animals && (
          <span className="ml-auto text-sm text-stone-500">
            {shown.length === animals.length ? `${animals.length} animals` : `${shown.length} of ${animals.length} animals`}
          </span>
        )}
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !animals ? <Loading /> : shown.length === 0 ? (
        <EmptyState title={filtering ? "No animal matches" : "No tagged animals yet"}>
          {filtering ? "Try other filters, or clear them." : "Register animals you follow one by one: breeding stock, goats, pigs, cattle."}
        </EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tag</TableHead>
                <TableHead>Animal</TableHead>
                <TableHead>Sex</TableHead>
                <TableHead>Age</TableHead>
                <TableHead>Group</TableHead>
                <TableHead>Mother</TableHead>
                <TableHead>Father</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((a) => (
                <TableRow key={a.animalId} className="cursor-pointer hover:bg-amber-50/60" onClick={() => router.push(`/livestock-animals/${a.animalId}`)}>
                  <TableCell className="font-medium">{a.tagNumber}{a.name && <div className="text-xs text-stone-500">{a.name}</div>}</TableCell>
                  <TableCell>{a.speciesName}{a.breed && <div className="text-xs text-stone-500">{a.breed}</div>}</TableCell>
                  <TableCell>{a.sex === "Unknown" ? "—" : a.sex}</TableCell>
                  <TableCell>{fmtAge(a.ageDays)}</TableCell>
                  <TableCell>{a.groupName}</TableCell>
                  <TableCell>{a.damTag ?? "—"}</TableCell>
                  <TableCell>{a.sireTag ?? "—"}</TableCell>
                  <TableCell>{a.status === "Active" ? "Alive" : a.status}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}

      <TagManyDialog open={tagMany} onOpenChange={setTagMany} onSaved={load} />
      <TagManyDialog mode="parents" open={tagParents} onOpenChange={setTagParents} onSaved={load} />
    </LivestockPage>
  )
}

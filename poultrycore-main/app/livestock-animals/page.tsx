"use client"

// Animal Register -- every tagged animal, searchable by tag or name.

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Plus, Search, Tag, Tags } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listAnimals, type AnimalStatus, type LivestockAnimal } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AnimalFormDialog } from "@/components/livestock/animal-form-dialog"
import { TagManyDialog } from "@/components/livestock/tag-many-dialog"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtAge } from "@/components/livestock/livestock-page"

const ALL = "__all"

export default function LivestockAnimalsPage() {
  const router = useRouter()
  const { kept } = useLivestockSpecies()
  const [animals, setAnimals] = useState<LivestockAnimal[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [species, setSpecies] = useState(ALL)
  const [status, setStatus] = useState<AnimalStatus | "All">("Active")
  const [search, setSearch] = useState("")
  const [term, setTerm] = useState("")
  const [creating, setCreating] = useState(false)
  const [tagMany, setTagMany] = useState(false)

  // Search waits for a pause in typing.
  useEffect(() => { const t = setTimeout(() => setTerm(search.trim()), 300); return () => clearTimeout(t) }, [search])

  const load = useCallback(async () => {
    setError(null)
    try {
      setAnimals(await listAnimals({ speciesCode: species === ALL ? undefined : species, status, search: term || undefined }))
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [species, status, term])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage
      title="Animal register"
      description="Tagged animals: who they are, where they are, and their parents."
      icon={Tag}
      actions={
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setTagMany(true)}><Tags className="h-4 w-4 mr-1" /> Tag several</Button>
          <Button className={AMBER_BUTTON} onClick={() => setCreating(true)}><Plus className="h-4 w-4 mr-1" /> Register animal</Button>
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
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !animals ? <Loading /> : animals.length === 0 ? (
        <EmptyState title={term ? "No animal matches" : "No tagged animals yet"}>
          {term ? "Try another tag or name." : "Register animals you follow one by one: breeding stock, goats, pigs, cattle."}
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
              {animals.map((a) => (
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
        </div>
      )}

      <TagManyDialog open={tagMany} onOpenChange={setTagMany} onSaved={load} />
      <AnimalFormDialog open={creating} onOpenChange={setCreating} onSaved={(id) => router.push(`/livestock-animals/${id}`)} />
    </LivestockPage>
  )
}

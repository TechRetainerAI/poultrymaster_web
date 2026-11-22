"use client"

// Tag several animals into one group at once (468).
//
// One row per animal in hand. The farmer clips the tag, then writes on that
// row whatever tells the animal apart (colour, markings, sex) so the tag in
// the register points to a real, recognisable animal. All rows save together
// or none do.

import { useEffect, useMemo, useRef, useState } from "react"
import { Plus, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { useToast } from "@/hooks/use-toast"
import {
  listAnimals, listBatches, listGroups, saveAnimals,
  type AnimalSex, type AnimalSource, type LivestockAnimal, type LivestockBatch, type LivestockGroup, type TagManyRow,
} from "@/lib/api/livestock"
import { ageToDays, parseAgeText } from "@/lib/livestock/breeds"
import { BreedSelect } from "@/components/livestock/breed-age-inputs"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, todayIso } from "./livestock-page"

const NONE = "__none"
type RowDefaults = Pick<TagManyRow, "sex" | "breed" | "birthDate" | "damId" | "sireId">
const blankRow = (d: Partial<RowDefaults> = {}): TagManyRow => ({
  tagNumber: "", name: null, sex: "Female", breed: null, birthDate: null, damId: null, sireId: null, notes: null, ...d,
})

/** "RB-009" + 1 -> "RB-010": the last number in the tag counts up, keeping its zeros. */
export function nextTags(first: string, count: number): string[] {
  const m = first.trim().match(/^(.*?)(\d+)(\D*)$/)
  if (!m) return []
  const [, pre, digits, post] = m
  const start = Number(digits)
  return Array.from({ length: count }, (_, i) => `${pre}${String(start + i).padStart(digits.length, "0")}${post}`)
}

/**
 * When the group's animals were born: the group's start date minus how old
 * they were then, or, when the group has no age, the intake batch's date minus
 * the age they came in at ("3 months"). Null when neither recorded an age.
 */
export function groupBirthDate(g: LivestockGroup | undefined, batches: LivestockBatch[] = []): string | null {
  if (!g) return null
  if (g.ageAtStartDays != null && g.startDate) return daysBefore(g.startDate, g.ageAtStartDays)
  const b = g.batchId != null ? batches.find((x) => x.batchId === g.batchId) : undefined
  const age = parseAgeText(b?.ageAtIntake)
  return b && age ? daysBefore(b.intakeDate, ageToDays(age.n, age.unit)) : null
}

function daysBefore(date: string, days: number): string | null {
  const d = new Date(`${date.slice(0, 10)}T00:00:00Z`)
  if (Number.isNaN(d.getTime())) return null
  d.setUTCDate(d.getUTCDate() - days)
  return d.toISOString().slice(0, 10)
}

export function TagManyDialog({ open, onOpenChange, presetGroupId, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  presetGroupId?: number | null
  onSaved: () => void
}) {
  const { toast } = useToast()
  const { byCode } = useLivestockSpecies()
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [batches, setBatches] = useState<LivestockBatch[]>([])
  const [groupId, setGroupId] = useState<number | undefined>(undefined)
  const [isNew, setIsNew] = useState<"yes" | "no">("no")
  const [source, setSource] = useState<AnimalSource>("Purchased")
  const [acquiredDate, setAcquiredDate] = useState<string>(todayIso())
  const [cost, setCost] = useState<number | null>(null)
  const [parents, setParents] = useState<LivestockAnimal[]>([])
  const [firstTag, setFirstTag] = useState("")
  const [howMany, setHowMany] = useState<number | "">(10)
  const [fillSex, setFillSex] = useState<AnimalSex>("Female")
  const [fillBreed, setFillBreed] = useState<string | null>(null)
  const [fillDam, setFillDam] = useState<number | null>(null)
  const [fillSire, setFillSire] = useState<number | null>(null)
  const [rows, setRows] = useState<TagManyRow[]>([blankRow()])
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open) return
    listGroups().then(setGroups).catch(() => setGroups([]))
    listBatches().then(setBatches).catch(() => setBatches([]))
    setGroupId(presetGroupId ?? undefined)
    setIsNew("no"); setSource("Purchased"); setAcquiredDate(todayIso()); setCost(null)
    setFirstTag(""); setHowMany(10); setFillSex("Female"); setFillBreed(null); setFillDam(null); setFillSire(null); setRows([blankRow()])
    auto.current = { breed: null, birth: null }
  }, [open, presetGroupId])

  const group = groups.find((g) => g.groupId === groupId)
  const speciesCode = group?.speciesCode
  const species = speciesCode ? byCode.get(speciesCode) : undefined
  const showParents = species?.breedsOnFarm !== false

  // Possible parents: same kind, any status (a dead dam is still the mother).
  useEffect(() => {
    if (!open || !speciesCode) { setParents([]); return }
    listAnimals({ speciesCode, status: "All" }).then(setParents).catch(() => setParents([]))
  }, [open, speciesCode])
  const dams = useMemo(() => parents.filter((p) => p.sex !== "Male"), [parents])
  const sires = useMemo(() => parents.filter((p) => p.sex !== "Female"), [parents])

  // Another group can mean another kind of animal: chosen parents no longer fit.
  useEffect(() => {
    setFillDam(null); setFillSire(null)
    setRows((rs) => rs.map((r) => ({ ...r, damId: null, sireId: null })))
  }, [speciesCode])

  // Already counted in the group: their breed and birth date are the group's,
  // so fill them in. Only blanks and earlier fill-ins are replaced, never what
  // the farmer typed.
  const counted = isNew === "no" && !!group
  const birthDefault = counted ? groupBirthDate(group, batches) : null
  const auto = useRef<{ breed: string | null; birth: string | null }>({ breed: null, birth: null })
  useEffect(() => {
    if (!open || !counted) return
    const prev = auto.current
    const next = { breed: group!.breed, birth: birthDefault }
    setFillBreed((b) => (b == null || b === prev.breed ? next.breed : b))
    setRows((rs) => rs.map((r) => ({
      ...r,
      breed: r.breed == null || r.breed === prev.breed ? next.breed : r.breed,
      birthDate: r.birthDate == null || r.birthDate === prev.birth ? next.birth : r.birthDate,
    })))
    auto.current = next
  }, [open, counted, group?.groupId, group?.breed, birthDefault]) // eslint-disable-line react-hooks/exhaustive-deps
  const untagged = group ? Math.max(group.head - group.tagged, 0) : 0
  const filled = rows.filter((r) => r.tagNumber.trim())
  const tooMany = isNew === "no" && !!group && filled.length > untagged
  const fillTags = nextTags(firstTag, typeof howMany === "number" ? Math.min(howMany, 500) : 0)

  const setRow = <K extends keyof TagManyRow>(i: number, k: K, v: TagManyRow[K]) =>
    setRows((rs) => rs.map((r, j) => (j === i ? { ...r, [k]: v } : r)))

  const rowDefaults = (): Partial<RowDefaults> => ({
    sex: fillSex, breed: fillBreed, birthDate: birthDefault, damId: fillDam, sireId: fillSire,
  })

  const fill = () => {
    if (fillTags.length === 0) return
    // Keep rows already typed in; replace an empty starting row.
    setRows((rs) => [...rs.filter((r) => r.tagNumber.trim()), ...fillTags.map((t) => ({ ...blankRow(rowDefaults()), tagNumber: t }))])
  }

  const save = async () => {
    if (!groupId) return
    setSaving(true)
    try {
      const res = await saveAnimals({
        groupId,
        addsToHead: isNew === "yes",
        source: isNew === "yes" ? source : "OnFarm",
        acquiredDate: isNew === "yes" ? acquiredDate || null : null,
        purchaseCost: isNew === "yes" && source === "Purchased" ? cost : null,
        animals: filled.map((r) => ({ ...r, tagNumber: r.tagNumber.trim() })),
      })
      toast({ title: `${res.animalIds.length} animal${res.animalIds.length === 1 ? "" : "s"} tagged` })
      onOpenChange(false)
      onSaved()
    } catch (e: any) {
      toast({ title: "Nothing saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const activeGroups = groups.filter((g) => g.status === "Active")
  const canSave = !!groupId && filled.length > 0 && !tooMany

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-6xl">
        <DialogHeader><DialogTitle>Tag several animals</DialogTitle></DialogHeader>
        <div className="space-y-4 max-h-[75vh] overflow-y-auto pr-1">
          <div>
            <Label>Group</Label>
            <Select value={groupId ? String(groupId) : ""} disabled={!!presetGroupId} onValueChange={(v) => setGroupId(Number(v))}>
              <SelectTrigger><SelectValue placeholder="Choose a group" /></SelectTrigger>
              <SelectContent>
                {activeGroups.map((g) => (
                  <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.speciesName} · {g.head} head</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {group && (
              <p className="text-xs text-stone-500 mt-1">
                {group.head} head · {group.tagged} tagged · <span className="font-medium text-stone-700">{untagged} still without a tag</span>
              </p>
            )}
            {counted && (group!.breed || birthDefault) && (
              <p className="text-xs text-amber-800 mt-1">
                Breed{birthDefault ? " and birth date" : ""} filled in from {group!.name}. Change any animal that differs.
              </p>
            )}
          </div>

          <div>
            <Label>Are these animals new to the group?</Label>
            <RadioGroup value={isNew} onValueChange={(v) => setIsNew(v as "yes" | "no")} className="mt-1 space-y-1">
              <label className="flex items-center gap-2 text-sm">
                <RadioGroupItem value="no" /> No, they are already counted in {group?.name ?? "the group"} and are only getting tags
              </label>
              <label className="flex items-center gap-2 text-sm">
                <RadioGroupItem value="yes" /> Yes, they were just bought, born or brought in (each adds one to the group)
              </label>
            </RadioGroup>
          </div>

          {isNew === "yes" && (
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <Label>Came from</Label>
                  <Select value={source} onValueChange={(v) => setSource(v as AnimalSource)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Purchased">Bought</SelectItem>
                      <SelectItem value="BornOnFarm">Born on the farm</SelectItem>
                      <SelectItem value="Other">Other</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label htmlFor="tm-acq">{source === "BornOnFarm" ? "Date (birth)" : "Date they arrived"}</Label>
                  <Input id="tm-acq" type="date" max={todayIso()} value={acquiredDate} onChange={(e) => setAcquiredDate(e.target.value)} />
                </div>
                {source === "Purchased" && (
                  <div>
                    <Label htmlFor="tm-cost">Price paid for each</Label>
                    <Input id="tm-cost" type="number" min={0} step="0.01" value={cost ?? ""}
                      onChange={(e) => setCost(e.target.value === "" ? null : Number(e.target.value))} />
                  </div>
                )}
            </div>
          )}

          <div className="rounded-md border bg-amber-50/50 p-3 space-y-2">
            <div className="text-sm font-medium">Fill in tag numbers</div>
            <p className="text-xs text-stone-500">Every row added here starts with the sex, breed and parents chosen below. Change any row after.</p>
            <div className="flex flex-wrap items-end gap-3">
              <div>
                <Label htmlFor="tm-first" className="text-xs">First tag</Label>
                <Input id="tm-first" className="w-36" placeholder="e.g. RB-001" value={firstTag} onChange={(e) => setFirstTag(e.target.value)} />
              </div>
              <div>
                <Label htmlFor="tm-count" className="text-xs">How many</Label>
                <Input id="tm-count" className="w-24" type="number" min={1} max={500} value={howMany}
                  onChange={(e) => setHowMany(e.target.value === "" ? "" : Math.max(1, Number(e.target.value)))} />
              </div>
              <div>
                <Label className="text-xs">Sex</Label>
                <Select value={fillSex} onValueChange={(v) => setFillSex(v as AnimalSex)}>
                  <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Female">Female</SelectItem>
                    <SelectItem value="Male">Male</SelectItem>
                    <SelectItem value="Unknown">Not known</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label htmlFor="tm-fbreed" className="text-xs">Breed</Label>
                <BreedSelect id="tm-fbreed" className="w-48" speciesCode={speciesCode} value={fillBreed} onChange={setFillBreed} />
              </div>
              {showParents && (
                <>
                  <ParentSelect label="Mother" options={dams} value={fillDam} onChange={setFillDam} />
                  <ParentSelect label="Father" options={sires} value={fillSire} onChange={setFillSire} />
                </>
              )}
              <Button type="button" variant="outline" disabled={fillTags.length === 0} onClick={fill}>Add rows</Button>
            </div>
            <p className="text-xs text-stone-500">
              {firstTag.trim() && fillTags.length === 0
                ? "The first tag needs a number in it, e.g. RB-001."
                : fillTags.length > 0
                  ? `Adds ${fillTags[0]} to ${fillTags[fillTags.length - 1]}.`
                  : "Type the first tag and how many; the number counts up."}
            </p>
          </div>

          <p className="text-sm text-stone-600">
            Tag each animal as you go, then use its row to note what tells it apart, such as colour, markings or a notched ear.
            After that, the tag number on the animal is how you find it in the register.
          </p>

          <div className="rounded-md border overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-stone-50 text-left">
                <tr>
                  <th className="px-2 py-2 w-8">#</th>
                  <th className="px-2 py-2">Tag number</th>
                  <th className="px-2 py-2">Sex</th>
                  <th className="px-2 py-2">Birth date</th>
                  <th className="px-2 py-2">Breed</th>
                  {showParents && <th className="px-2 py-2">Mother</th>}
                  {showParents && <th className="px-2 py-2">Father</th>}
                  <th className="px-2 py-2">Name</th>
                  <th className="px-2 py-2">Notes: how to tell it apart</th>
                  <th className="px-2 py-2 w-10" />
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={i} className="border-t">
                    <td className="px-2 py-1 text-stone-500">{i + 1}</td>
                    <td className="px-2 py-1"><Input className="min-w-28" value={r.tagNumber} onChange={(e) => setRow(i, "tagNumber", e.target.value)} /></td>
                    <td className="px-2 py-1">
                      <Select value={r.sex} onValueChange={(v) => setRow(i, "sex", v as AnimalSex)}>
                        <SelectTrigger className="min-w-28"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="Female">Female</SelectItem>
                          <SelectItem value="Male">Male</SelectItem>
                          <SelectItem value="Unknown">Not known</SelectItem>
                        </SelectContent>
                      </Select>
                    </td>
                    <td className="px-2 py-1"><Input type="date" max={todayIso()} value={r.birthDate ?? ""} onChange={(e) => setRow(i, "birthDate", e.target.value || null)} /></td>
                    <td className="px-2 py-1"><BreedSelect className="min-w-44" speciesCode={speciesCode} value={r.breed} onChange={(v) => setRow(i, "breed", v)} /></td>
                    {showParents && <td className="px-2 py-1"><ParentSelect options={dams} value={r.damId} onChange={(v) => setRow(i, "damId", v)} /></td>}
                    {showParents && <td className="px-2 py-1"><ParentSelect options={sires} value={r.sireId} onChange={(v) => setRow(i, "sireId", v)} /></td>}
                    <td className="px-2 py-1"><Input className="min-w-28" placeholder="Optional" value={r.name ?? ""} onChange={(e) => setRow(i, "name", e.target.value || null)} /></td>
                    <td className="px-2 py-1"><Input className="min-w-48" placeholder="e.g. white with black ears" value={r.notes ?? ""} onChange={(e) => setRow(i, "notes", e.target.value || null)} /></td>
                    <td className="px-2 py-1">
                      <Button type="button" variant="ghost" size="icon" aria-label="Remove row" disabled={rows.length === 1}
                        onClick={() => setRows((rs) => rs.filter((_, j) => j !== i))}><Trash2 className="h-4 w-4" /></Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Button type="button" variant="outline" size="sm" onClick={() => setRows((rs) => [...rs, blankRow(rowDefaults())])}>
            <Plus className="h-4 w-4 mr-1" /> Add a row
          </Button>

          {tooMany && (
            <p className="text-sm text-red-600">
              {group!.name} has only {untagged} animal{untagged === 1 ? "" : "s"} without a tag, but you have {filled.length} tags.
              Remove rows, or choose "Yes" above if these animals are new to the group.
            </p>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>
            {saving ? "Saving…" : `Save ${filled.length} tag${filled.length === 1 ? "" : "s"}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ParentSelect({ label, options, value, onChange }: {
  label?: string
  options: LivestockAnimal[]
  value: number | null
  onChange: (id: number | null) => void
}) {
  const select = (
    <Select value={value ? String(value) : NONE} onValueChange={(v) => onChange(v === NONE ? null : Number(v))}>
      <SelectTrigger className="min-w-36"><SelectValue /></SelectTrigger>
      <SelectContent>
        <SelectItem value={NONE}>Not known</SelectItem>
        {options.map((p) => <SelectItem key={p.animalId} value={String(p.animalId)}>{p.tagNumber}{p.name ? ` · ${p.name}` : ""}</SelectItem>)}
      </SelectContent>
    </Select>
  )
  return label ? <div><Label className="text-xs">{label}</Label>{select}</div> : select
}

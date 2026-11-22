"use client"

// Tag several animals into one group at once (468).
//
// One row per animal in hand. The farmer clips the tag, then writes on that
// row whatever tells the animal apart (colour, markings, sex) so the tag in
// the register points to a real, recognisable animal. All rows save together
// or none do.

import { useEffect, useMemo, useRef, useState } from "react"
import { Plus, Tags, Trash2, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import {
  listAnimals, listBatches, listBreeding, listGroups, saveAnimals,
  type AnimalSex, type AnimalSource, type BreedingEvent, type LivestockAnimal, type LivestockBatch, type LivestockGroup, type TagManyRow,
} from "@/lib/api/livestock"
import { ageToDays, parseAgeText } from "@/lib/livestock/breeds"
import { BreedSelect } from "@/components/livestock/breed-age-inputs"
import { ParentPicker, type PendingParent } from "@/components/livestock/parent-picker"
import { parentProblem } from "@/lib/livestock/parents"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, fmtDate, todayIso } from "./livestock-page"

const NONE = "__none"
type FillSet = { id: number; tags: string[]; sex: AnimalSex; breed: string | null }
const SEX_LABEL: Record<AnimalSex, string> = { Female: "female", Male: "male", Unknown: "sex not known" }
type RowDefaults = Pick<TagManyRow, "sex" | "breed" | "birthDate" | "damId" | "sireId" | "damTag" | "sireTag">
const blankRow = (d: Partial<RowDefaults> = {}): TagManyRow => ({
  tagNumber: "", name: null, sex: "Female", breed: null, birthDate: null, damId: null, sireId: null, damTag: null, sireTag: null, notes: null, ...d,
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

export function TagManyDialog({ open, onOpenChange, presetGroupId, onSaved, mode = "any" }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  presetGroupId?: number | null
  /** "parents": tag the mothers and fathers on their own, before their young. No parent columns. */
  mode?: "any" | "parents"
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
  // A parent being tagged in this same list, by tag (472).
  const [fillDamTag, setFillDamTag] = useState<string | null>(null)
  const [fillSireTag, setFillSireTag] = useState<string | null>(null)
  // Births recorded into this group: picking one fills mother, father and birth date.
  const [births, setBirths] = useState<BreedingEvent[]>([])
  const [fromBirth, setFromBirth] = useState<number | null>(null)
  // A birth date typed for the next rows; wins over the group's.
  const [fillBirthTyped, setFillBirthTyped] = useState<string | null>(null)
  const [rows, setRows] = useState<TagManyRow[]>([])
  // Each "Add rows" is a set (e.g. 5 females, then 5 males), shown so one can
  // be taken out again without touching the others.
  const [sets, setSets] = useState<FillSet[]>([])
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open) return
    listGroups().then(setGroups).catch(() => setGroups([]))
    listBatches().then(setBatches).catch(() => setBatches([]))
    setGroupId(presetGroupId ?? undefined)
    setIsNew("no"); setSource("Purchased"); setAcquiredDate(todayIso()); setCost(null)
    setFirstTag(""); setHowMany(10); setFillSex("Female"); setFillBreed(null); setFillDam(null); setFillSire(null); setRows([])
    setFillDamTag(null); setFillSireTag(null); setFromBirth(null); setFillBirthTyped(null)
    auto.current = { breed: null, birth: null }
    setSets([])
  }, [open, presetGroupId])

  const group = groups.find((g) => g.groupId === groupId)
  const speciesCode = group?.speciesCode
  const species = speciesCode ? byCode.get(speciesCode) : undefined
  const showParents = mode !== "parents" && species?.breedsOnFarm !== false

  // Possible parents: same kind, any status (a dead dam is still the mother).
  useEffect(() => {
    if (!open || !speciesCode) { setParents([]); return }
    listAnimals({ speciesCode, status: "All" }).then(setParents).catch(() => setParents([]))
  }, [open, speciesCode])
  useEffect(() => {
    if (!open || !groupId) { setBirths([]); return }
    listBreeding({ groupId, eventType: "Birth" })
      .then((b) => setBirths(b.filter((e) => e.groupId === groupId && (e.bornAlive ?? 0) > 0)))
      .catch(() => setBirths([]))
  }, [open, groupId])

  const gestation = species?.gestationDays ?? null
  const byId = useMemo(() => new Map(parents.map((p) => [p.animalId, p])), [parents])
  const sameTag = (a: string | null | undefined, b: string | null | undefined) =>
    !!a && !!b && a.trim().toLowerCase() === b.trim().toLowerCase()
  const pendingAll: PendingParent[] = rows.filter((r) => r.tagNumber.trim())
    .map((r) => ({ tag: r.tagNumber.trim(), sex: r.sex, birthDate: r.birthDate }))
  const pendingFor = (r: TagManyRow) => pendingAll.filter((p) => !sameTag(p.tag, r.tagNumber))
  // A row whose chosen mother or father cannot be its parent.
  const badParent = (r: TagManyRow) => {
    const check = (id: number | null, tag: string | null | undefined, role: "mother" | "father") => {
      if (tag) {
        const p = pendingFor(r).find((x) => sameTag(x.tag, tag))
        return !p || !!parentProblem(p, role, r.birthDate, gestation)
      }
      const a = id != null ? byId.get(id) : undefined
      return !!a && !!parentProblem(a, role, r.birthDate, gestation)
    }
    return check(r.damId, r.damTag, "mother") || check(r.sireId, r.sireTag, "father")
  }
  // Tags gone from the list: rows that named them as a parent go back to "Not known".
  const dropParentRefs = (rs: TagManyRow[], gone: (tag: string) => boolean) =>
    rs.map((x) => ({ ...x, damTag: x.damTag && gone(x.damTag) ? null : x.damTag, sireTag: x.sireTag && gone(x.sireTag) ? null : x.sireTag }))

  // How many young of a birth already have a tag, on the farm or in this list.
  const taggedFromBirth = (e: BreedingEvent) => {
    const d = e.date.slice(0, 10)
    const born = (x: { damId: number | null; birthDate: string | null }) => x.damId === e.damId && x.birthDate?.slice(0, 10) === d
    return parents.filter(born).length + rows.filter((x) => x.tagNumber.trim() && !x.damTag && born(x)).length
  }
  const birth = births.find((e) => e.eventId === fromBirth)
  const fillBirth = birth ? birth.date.slice(0, 10) : fillBirthTyped
  const pickBirth = (id: number | null) => {
    setFromBirth(id)
    const e = births.find((x) => x.eventId === id)
    setFillDamTag(null); setFillSireTag(null)
    if (!e) { setFillDam(null); setFillSire(null); return }
    setFillDam(e.damId); setFillSire(e.sireId)
    const left = (e.bornAlive ?? 0) - taggedFromBirth(e)
    setHowMany(left > 0 ? left : "")
  }

  // Another group can mean another kind of animal: chosen parents no longer fit.
  useEffect(() => {
    setFillDam(null); setFillSire(null); setFillDamTag(null); setFillSireTag(null); setFromBirth(null)
    setRows((rs) => rs.map((r) => ({ ...r, damId: null, sireId: null, damTag: null, sireTag: null })))
  }, [speciesCode])

  // Already counted in the group: their breed and birth date are the group's,
  // so fill them in. Only blanks and earlier fill-ins are replaced, never what
  // the farmer typed.
  const counted = isNew === "no" && !!group
  // Not for parents: the group's birth date is its young's, and parents are older.
  const birthDefault = counted && mode !== "parents" ? groupBirthDate(group, batches) : null
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
  // A new tag number keeps the rows that named the old one as their parent.
  const renameTag = (i: number, next: string) => {
    const old = rows[i]?.tagNumber
    setRows((rs) => rs.map((r, j) => j === i ? { ...r, tagNumber: next } : {
      ...r,
      damTag: sameTag(r.damTag, old) ? next : r.damTag,
      sireTag: sameTag(r.sireTag, old) ? next : r.sireTag,
    }))
    if (sameTag(fillDamTag, old)) setFillDamTag(next || null)
    if (sameTag(fillSireTag, old)) setFillSireTag(next || null)
  }
  const removeRow = (i: number) => {
    const gone = rows[i]?.tagNumber
    setRows((rs) => dropParentRefs(rs.filter((_, j) => j !== i), (t) => sameTag(t, gone)))
    if (sameTag(fillDamTag, gone)) setFillDamTag(null)
    if (sameTag(fillSireTag, gone)) setFillSireTag(null)
  }

  const rowDefaults = (): Partial<RowDefaults> => ({
    sex: fillSex, breed: fillBreed, birthDate: fillBirth ?? birthDefault,
    damId: fillDamTag ? null : fillDam, sireId: fillSireTag ? null : fillSire, damTag: fillDamTag, sireTag: fillSireTag,
  })

  const fill = () => {
    if (fillTags.length === 0) return
    // Adds a set. A tag already in the list is replaced, never doubled; blank
    // rows go.
    const fresh = new Set(fillTags)
    const kept = rows.filter((r) => r.tagNumber.trim() && !fresh.has(r.tagNumber.trim()))
    setRows([...kept, ...fillTags.map((t) => ({ ...blankRow(rowDefaults()), tagNumber: t }))])
    setSets((ss) => [
      ...ss.map((x) => ({ ...x, tags: x.tags.filter((t) => !fresh.has(t)) })).filter((x) => x.tags.length > 0),
      { id: Date.now(), tags: fillTags, sex: fillSex, breed: fillBreed },
    ])
    // Ready for the next set: the tag after this one, and the animals left.
    setFirstTag(nextTags(fillTags[fillTags.length - 1], 2)[1] ?? "")
    if (counted) {
      const left = untagged - (kept.length + fillTags.length)
      setHowMany(left > 0 ? left : "")
    }
  }

  const removeSet = (id: number) => {
    const set = sets.find((x) => x.id === id)
    if (!set) return
    const gone = new Set(set.tags.map((t) => t.toLowerCase()))
    const isGone = (t: string) => gone.has(t.trim().toLowerCase())
    setRows((rs) => dropParentRefs(rs.filter((r) => !isGone(r.tagNumber)), isGone))
    if (fillDamTag && isGone(fillDamTag)) setFillDamTag(null)
    if (fillSireTag && isGone(fillSireTag)) setFillSireTag(null)
    setSets((ss) => ss.filter((x) => x.id !== id))
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
        animals: filled.map((r) => ({
          ...r, tagNumber: r.tagNumber.trim(),
          damTag: r.damTag?.trim() || null, sireTag: r.sireTag?.trim() || null,
          damId: r.damTag ? null : r.damId, sireId: r.sireTag ? null : r.sireId,
        })),
      })
      const n = res.animalIds.length
      toast(mode === "parents"
        ? { title: `${n} parent${n === 1 ? "" : "s"} tagged`, description: "Now use Tag several for their young and pick these as Mother and Father." }
        : { title: `${n} animal${n === 1 ? "" : "s"} tagged` })
      onOpenChange(false)
      onSaved()
    } catch (e: any) {
      toast({ title: "Nothing saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const activeGroups = groups.filter((g) => g.status === "Active")
  const parentErrors = showParents ? filled.filter(badParent).length : 0
  const canSave = !!groupId && filled.length > 0 && !tooMany && parentErrors === 0

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[min(96vw,84rem)] p-0 gap-0 overflow-hidden">
        <DialogHeader className="px-6 py-4 border-b bg-gradient-to-r from-amber-50 to-white">
          <DialogTitle className="flex items-center gap-3 text-amber-900">
            <span className="flex h-9 w-9 items-center justify-center rounded-full bg-amber-100 text-amber-700"><Tags className="h-5 w-5" /></span>
            <span>
              {mode === "parents" ? "Tag parents" : "Tag several animals"}
              <span className="block text-xs font-normal text-stone-500">
                {mode === "parents"
                  ? "Tag your mothers and fathers first. Their young can then pick them as Mother and Father."
                  : "Give each animal a tag number, then save them all at once."}
              </span>
            </span>
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4 max-h-[72vh] overflow-y-auto px-6 py-4">
          {/* 1. Group */}
          <section className="rounded-lg border p-4 space-y-3">
            <StepTitle n={1}>Which group are they in?</StepTitle>
            <Select value={groupId ? String(groupId) : ""} disabled={!!presetGroupId} onValueChange={(v) => setGroupId(Number(v))}>
              <SelectTrigger><SelectValue placeholder="Choose a group" /></SelectTrigger>
              <SelectContent>
                {activeGroups.map((g) => (
                  <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.speciesName} · {g.head} head</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {group && (
              <div className="flex flex-wrap gap-2 text-xs">
                <span className="rounded-full bg-stone-100 px-2.5 py-1 text-stone-700">{group.head} head</span>
                <span className="rounded-full bg-emerald-100 px-2.5 py-1 text-emerald-800">{group.tagged} tagged</span>
                <span className="rounded-full bg-amber-100 px-2.5 py-1 font-medium text-amber-900">{untagged} still without a tag</span>
              </div>
            )}

            <div className="grid grid-cols-1 md:grid-cols-2 gap-2 pt-1">
              {([
                ["no", "Only getting tags", `They are already counted in ${group?.name ?? "the group"}.`],
                ["yes", "New to the group", "Just bought, born or brought in. Each adds one to the group."],
              ] as const).map(([v, title, text]) => (
                <button key={v} type="button" onClick={() => setIsNew(v)}
                  className={`rounded-lg border-2 p-3 text-left transition-colors ${isNew === v ? "border-amber-500 bg-amber-50" : "border-stone-200 hover:border-amber-300"}`}>
                  <span className="flex items-center gap-2 text-sm font-medium text-stone-900">
                    <span className={`h-4 w-4 rounded-full border-2 ${isNew === v ? "border-amber-600 bg-amber-600 ring-2 ring-inset ring-white" : "border-stone-300"}`} />
                    {title}
                  </span>
                  <span className="mt-1 block pl-6 text-xs text-stone-600">{text}</span>
                </button>
              ))}
            </div>

            {isNew === "yes" && (
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 rounded-md bg-stone-50 p-3">
                <div>
                  <Label>Came from</Label>
                  <Select value={source} onValueChange={(v) => setSource(v as AnimalSource)}>
                    <SelectTrigger className="bg-white"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Purchased">Bought</SelectItem>
                      <SelectItem value="BornOnFarm">Born on the farm</SelectItem>
                      <SelectItem value="Other">Other</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label htmlFor="tm-acq">{source === "BornOnFarm" ? "Date (birth)" : "Date they arrived"}</Label>
                  <Input id="tm-acq" className="bg-white" type="date" max={todayIso()} value={acquiredDate} onChange={(e) => setAcquiredDate(e.target.value)} />
                </div>
                {source === "Purchased" && (
                  <div>
                    <Label htmlFor="tm-cost">Price paid for each</Label>
                    <Input id="tm-cost" className="bg-white" type="number" min={0} step="0.01" value={cost ?? ""}
                      onChange={(e) => setCost(e.target.value === "" ? null : Number(e.target.value))} />
                  </div>
                )}
              </div>
            )}
          </section>

          {/* 2. Fill in */}
          <section className="rounded-lg border border-amber-200 bg-amber-50/60 p-4 space-y-3">
            <div>
              <StepTitle n={2}>Fill in tag numbers <span className="font-normal text-stone-500">(quick way)</span></StepTitle>
              <p className="mt-1 pl-8 text-xs text-stone-600">
                Type the first tag and how many; the number counts up. Each row starts with the sex, breed{showParents ? " and parents" : ""} chosen here.
                You can do it in parts, e.g. 5 females, then change the sex and add the other 5.
                {showParents && <> Tagging mothers and their young together? Add the mothers first; they then show under <strong>Being tagged now</strong> in Mother and Father.</>}
                {counted && (group!.breed || birthDefault) && <> Breed{birthDefault ? " and birth date" : ""} come from {group!.name}.</>}
              </p>
            </div>
            {showParents && births.length > 0 && (
              <div className="rounded-md border border-amber-200 bg-white p-3">
                <Label className="text-xs">Young from a birth you recorded (fills mother, father and birth date)</Label>
                <Select value={fromBirth ? String(fromBirth) : "none"} onValueChange={(v) => pickBirth(v === "none" ? null : Number(v))}>
                  <SelectTrigger className="bg-white"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">Not from a birth record</SelectItem>
                    {births.map((e) => {
                      const done = taggedFromBirth(e)
                      return (
                        <SelectItem key={e.eventId} value={String(e.eventId)}>
                          {fmtDate(e.date)} · mother {e.damTag ?? "?"}{e.sireTag ? ` × father ${e.sireTag}` : ""} · {e.bornAlive} born alive · {done} tagged
                        </SelectItem>
                      )
                    })}
                  </SelectContent>
                </Select>
                {birth && (
                  <p className="mt-1 text-xs text-amber-900">
                    Rows added now get mother <strong>{birth.damTag ?? "not known"}</strong>, father <strong>{birth.sireTag ?? "not known"}</strong> and birth date <strong>{fmtDate(birth.date)}</strong>.
                    {Math.max((birth.bornAlive ?? 0) - taggedFromBirth(birth), 0)} of {birth.bornAlive} still without a tag.
                  </p>
                )}
              </div>
            )}
            <div className={`grid grid-cols-2 gap-3 items-end ${showParents ? "lg:grid-cols-[1.1fr_0.6fr_0.9fr_1.2fr_1.1fr_1.1fr_1.1fr_auto]" : "lg:grid-cols-[1.2fr_0.7fr_1fr_1.3fr_1.1fr_auto]"}`}>
              <div>
                <Label htmlFor="tm-first" className="text-xs">First tag</Label>
                <Input id="tm-first" className="bg-white" placeholder="e.g. RB-001" value={firstTag} onChange={(e) => setFirstTag(e.target.value)} />
              </div>
              <div>
                <Label htmlFor="tm-count" className="text-xs">How many</Label>
                <Input id="tm-count" className="bg-white" type="number" min={1} max={500} value={howMany}
                  onChange={(e) => setHowMany(e.target.value === "" ? "" : Math.max(1, Number(e.target.value)))} />
              </div>
              <div>
                <Label className="text-xs">Sex</Label>
                <Select value={fillSex} onValueChange={(v) => setFillSex(v as AnimalSex)}>
                  <SelectTrigger className="bg-white"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Female">Female</SelectItem>
                    <SelectItem value="Male">Male</SelectItem>
                    <SelectItem value="Unknown">Not known</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label htmlFor="tm-fbreed" className="text-xs">Breed</Label>
                <BreedSelect id="tm-fbreed" className="bg-white" speciesCode={speciesCode} value={fillBreed} onChange={setFillBreed} />
              </div>
              <div>
                <Label htmlFor="tm-fbirth" className="text-xs">Birth date</Label>
                <Input id="tm-fbirth" type="date" className="bg-white" max={todayIso()} value={fillBirth ?? birthDefault ?? ""}
                  onChange={(e) => { setFromBirth(null); setFillBirthTyped(e.target.value || null) }} />
              </div>
              {showParents && (
                <>
                  <div>
                    <Label className="text-xs">Mother</Label>
                    <ParentPicker role="mother" animals={parents} value={fillDam} pending={pendingAll} pendingValue={fillDamTag}
                      onChange={(v, t) => { setFillDam(v); setFillDamTag(t ?? null); setFromBirth(null) }}
                      childBirthDate={fillBirth ?? birthDefault} groupId={groupId} gestationDays={gestation} />
                  </div>
                  <div>
                    <Label className="text-xs">Father</Label>
                    <ParentPicker role="father" animals={parents} value={fillSire} pending={pendingAll} pendingValue={fillSireTag}
                      onChange={(v, t) => { setFillSire(v); setFillSireTag(t ?? null); setFromBirth(null) }}
                      childBirthDate={fillBirth ?? birthDefault} groupId={groupId} gestationDays={gestation} />
                  </div>
                </>
              )}
              <Button type="button" className={`${AMBER_BUTTON} col-span-2 lg:col-span-1`} disabled={fillTags.length === 0} onClick={fill}>
                <Plus className="h-4 w-4 mr-1" />
                {fillTags.length > 0 ? `Add ${fillTags.length} row${fillTags.length === 1 ? "" : "s"}` : "Add rows"}
              </Button>
            </div>
            {(firstTag.trim() || fillTags.length > 0) && (
              <p className={`text-xs ${fillTags.length === 0 ? "text-rose-700" : "text-amber-900"}`}>
                {fillTags.length === 0
                  ? "The first tag needs a number in it, e.g. RB-001."
                  : <>Adds <strong>{fillTags[0]}</strong> to <strong>{fillTags[fillTags.length - 1]}</strong>.</>}
              </p>
            )}
            {sets.length > 0 && (
              <div className="flex flex-wrap items-center gap-2 border-t border-amber-200 pt-3">
                <span className="text-xs font-medium text-stone-600">Added:</span>
                {sets.map((x) => (
                  <span key={x.id} className="inline-flex items-center gap-1 rounded-full border border-amber-300 bg-white py-0.5 pl-2.5 pr-1 text-xs text-amber-900">
                    <strong>{x.tags.length}</strong> {SEX_LABEL[x.sex]}{x.breed ? ` ${x.breed}` : ""} · {x.tags[0]}{x.tags.length > 1 ? ` to ${x.tags[x.tags.length - 1]}` : ""}
                    <button type="button" aria-label={`Remove ${x.tags[0]} set`} onClick={() => removeSet(x.id)}
                      className="rounded-full p-0.5 text-stone-400 hover:bg-rose-50 hover:text-rose-600"><X className="h-3.5 w-3.5" /></button>
                  </span>
                ))}
              </div>
            )}
          </section>

          {/* 3. The tags */}
          <section className="rounded-lg border overflow-hidden">
            <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-b">
              <div>
                <StepTitle n={3}>
                  Check each animal
                  <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-900">{filled.length} tag{filled.length === 1 ? "" : "s"}</span>
                </StepTitle>
                <p className="mt-1 pl-8 text-xs text-stone-600">Note what tells it apart (colour, markings, a notched ear) so the tag points to an animal you can find.</p>
              </div>
              <Button type="button" variant="outline" size="sm" className="border-amber-300 text-amber-800 hover:bg-amber-50"
                onClick={() => setRows((rs) => [...rs, blankRow(rowDefaults())])}>
                <Plus className="h-4 w-4 mr-1" /> Add a row
              </Button>
            </div>
            <div className="overflow-x-auto max-h-[45vh]">
              <table className="w-full text-sm">
                <thead className="sticky top-0 z-10 bg-amber-600 text-left text-xs font-semibold text-white">
                  <tr>
                    <th className="px-2 py-2 w-8">#</th>
                    <th className="px-2 py-2">Tag number</th>
                    <th className="px-2 py-2">Sex</th>
                    <th className="px-2 py-2">Birth date</th>
                    <th className="px-2 py-2">Breed</th>
                    {showParents && <th className="px-2 py-2">Mother</th>}
                    {showParents && <th className="px-2 py-2">Father</th>}
                    <th className="px-2 py-2">Name</th>
                    <th className="px-2 py-2">How to tell it apart</th>
                    <th className="px-2 py-2 w-10" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-amber-100">
                  {rows.length === 0 && (
                    <tr>
                      <td colSpan={showParents ? 10 : 8} className="px-3 py-10 text-center">
                        <Tags className="mx-auto mb-2 h-8 w-8 text-amber-300" />
                        <p className="text-sm font-medium text-stone-700">No tags yet</p>
                        <p className="text-xs text-stone-500">Use step 2 above, or <span className="font-medium">Add a row</span> to type tags one at a time.</p>
                      </td>
                    </tr>
                  )}
                  {rows.map((r, i) => (
                    <tr key={i} className="odd:bg-white even:bg-amber-50/40">
                      <td className="px-2 py-1.5 text-xs text-stone-500">{i + 1}</td>
                      <td className="px-2 py-1.5"><Input className="min-w-28 font-medium" placeholder="Tag" value={r.tagNumber} onChange={(e) => renameTag(i, e.target.value)} /></td>
                      <td className="px-2 py-1.5">
                        <Select value={r.sex} onValueChange={(v) => setRow(i, "sex", v as AnimalSex)}>
                          <SelectTrigger className="min-w-28"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="Female">Female</SelectItem>
                            <SelectItem value="Male">Male</SelectItem>
                            <SelectItem value="Unknown">Not known</SelectItem>
                          </SelectContent>
                        </Select>
                      </td>
                      <td className="px-2 py-1.5"><Input type="date" max={todayIso()} value={r.birthDate ?? ""} onChange={(e) => setRow(i, "birthDate", e.target.value || null)} /></td>
                      <td className="px-2 py-1.5"><BreedSelect className="min-w-40" speciesCode={speciesCode} value={r.breed} onChange={(v) => setRow(i, "breed", v)} /></td>
                      {showParents && <td className="px-2 py-1.5"><ParentPicker role="mother" animals={parents} value={r.damId} pending={pendingFor(r)} pendingValue={r.damTag ?? null}
                        onChange={(v, t) => setRows((rs) => rs.map((x, j) => (j === i ? { ...x, damId: v, damTag: t ?? null } : x)))}
                        childBirthDate={r.birthDate} groupId={groupId} gestationDays={gestation} /></td>}
                      {showParents && <td className="px-2 py-1.5"><ParentPicker role="father" animals={parents} value={r.sireId} pending={pendingFor(r)} pendingValue={r.sireTag ?? null}
                        onChange={(v, t) => setRows((rs) => rs.map((x, j) => (j === i ? { ...x, sireId: v, sireTag: t ?? null } : x)))}
                        childBirthDate={r.birthDate} groupId={groupId} gestationDays={gestation} /></td>}
                      <td className="px-2 py-1.5"><Input className="min-w-28" placeholder="Optional" value={r.name ?? ""} onChange={(e) => setRow(i, "name", e.target.value || null)} /></td>
                      <td className="px-2 py-1.5"><Input className="min-w-48" placeholder="e.g. white with black ears" value={r.notes ?? ""} onChange={(e) => setRow(i, "notes", e.target.value || null)} /></td>
                      <td className="px-2 py-1.5">
                        <Button type="button" variant="ghost" size="icon" aria-label="Remove row"
                          onClick={() => removeRow(i)}><Trash2 className="h-4 w-4 text-rose-600" /></Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          {parentErrors > 0 && (
            <p className="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700">
              {parentErrors} row{parentErrors === 1 ? " has a" : "s have a"} mother or father that cannot be its parent (marked in red). Pick another, or set it to Not known.
            </p>
          )}

          {tooMany && (
            <p className="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700">
              {group!.name} has only {untagged} animal{untagged === 1 ? "" : "s"} without a tag, but you have {filled.length} tags.
              Remove rows, or choose "New to the group" above if these animals are new.
            </p>
          )}
        </div>
        <DialogFooter className="px-6 py-3 border-t bg-stone-50 sm:items-center">
          {group && filled.length > 0 && (
            <p className="mr-auto text-xs text-stone-600">
              {filled.length} tag{filled.length === 1 ? "" : "s"} into <span className="font-medium text-stone-800">{group.name}</span>
              {isNew === "yes" ? ` · adds ${filled.length} to the group` : ` · ${Math.max(untagged - filled.length, 0)} left without a tag`}
            </p>
          )}
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>
            {saving ? "Saving…" : `Save ${filled.length} tag${filled.length === 1 ? "" : "s"}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function StepTitle({ n, children }: { n: number; children: React.ReactNode }) {
  return (
    <h3 className="flex items-center gap-2 text-sm font-semibold text-stone-900">
      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-amber-600 text-xs font-bold text-white">{n}</span>
      {children}
    </h3>
  )
}

"use client"

// Register / edit a tagged animal.
//
// Registering asks the one question that decides the head count: is this
// animal NEW to the group (bought, born, brought in -- the group gains one) or
// one already counted there that is only now getting a tag (nothing moves)?

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { useToast } from "@/hooks/use-toast"
import {
  listAnimals, listGroups, saveAnimal,
  type AnimalInput, type AnimalSex, type AnimalSource, type LivestockAnimal, type LivestockGroup,
} from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { BreedSelect } from "@/components/livestock/breed-age-inputs"
import { AMBER_BUTTON, todayIso } from "./livestock-page"

const NONE = "__none"

export function AnimalFormDialog({ open, onOpenChange, animal, presetGroupId, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  animal?: LivestockAnimal | null
  presetGroupId?: number | null
  onSaved: (animalId: number) => void
}) {
  const { toast } = useToast()
  const { byCode } = useLivestockSpecies()
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [parents, setParents] = useState<LivestockAnimal[]>([])
  const [form, setForm] = useState<AnimalInput>(blank())
  const [isNew, setIsNew] = useState<"yes" | "no">("no")
  const [saving, setSaving] = useState(false)
  const isEdit = !!animal

  useEffect(() => {
    if (!open) return
    listGroups().then(setGroups).catch(() => setGroups([]))
    if (animal) {
      setForm({
        tagNumber: animal.tagNumber, name: animal.name, sex: animal.sex, breed: animal.breed, birthDate: animal.birthDate,
        damId: animal.damId, sireId: animal.sireId, source: animal.source, acquiredDate: animal.acquiredDate,
        purchaseCost: animal.purchaseCost, notes: animal.notes,
      })
    } else {
      setForm({ ...blank(), groupId: presetGroupId ?? undefined })
      setIsNew("no")
    }
  }, [open, animal, presetGroupId])

  const group = groups.find((g) => g.groupId === (animal?.groupId ?? form.groupId))
  const speciesCode = animal?.speciesCode ?? group?.speciesCode
  const species = speciesCode ? byCode.get(speciesCode) : undefined

  // Possible parents: same kind, any status (a dead dam is still the mother).
  useEffect(() => {
    if (!open || !speciesCode) { setParents([]); return }
    listAnimals({ speciesCode, status: "All" }).then((a) => setParents(a.filter((x) => x.animalId !== animal?.animalId)))
      .catch(() => setParents([]))
  }, [open, speciesCode, animal?.animalId])
  const dams = useMemo(() => parents.filter((p) => p.sex !== "Male"), [parents])
  const sires = useMemo(() => parents.filter((p) => p.sex !== "Female"), [parents])

  const set = <K extends keyof AnimalInput>(k: K, v: AnimalInput[K]) => setForm((f) => ({ ...f, [k]: v }))

  const save = async () => {
    setSaving(true)
    try {
      const body: AnimalInput = isEdit ? form : {
        ...form, addsToHead: isNew === "yes",
        source: isNew === "yes" ? form.source : "OnFarm",
      }
      const res = await saveAnimal(body, animal?.animalId)
      toast({ title: isEdit ? "Animal updated" : `Tag ${form.tagNumber} registered` })
      onOpenChange(false)
      onSaved(res.animalId)
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const activeGroups = groups.filter((g) => g.status === "Active")
  const canSave = form.tagNumber.trim() && (isEdit || form.groupId)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>{isEdit ? `Edit tag ${animal!.tagNumber}` : "Register a tagged animal"}</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          {!isEdit && (
            <div>
              <Label>Group</Label>
              <Select value={form.groupId ? String(form.groupId) : ""} disabled={!!presetGroupId}
                onValueChange={(v) => setForm((f) => ({ ...f, groupId: Number(v), damId: null, sireId: null }))}>
                <SelectTrigger><SelectValue placeholder="Choose a group" /></SelectTrigger>
                <SelectContent>
                  {activeGroups.map((g) => (
                    <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.speciesName} · {g.head} head</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="a-tag">Tag number</Label>
              <Input id="a-tag" value={form.tagNumber} onChange={(e) => set("tagNumber", e.target.value)} />
            </div>
            <div>
              <Label htmlFor="a-name">Name (optional)</Label>
              <Input id="a-name" value={form.name ?? ""} onChange={(e) => set("name", e.target.value || null)} />
            </div>
          </div>

          {!isEdit && (
            <div>
              <Label>Is this animal new to the group?</Label>
              <RadioGroup value={isNew} onValueChange={(v) => setIsNew(v as "yes" | "no")} className="mt-1 space-y-1">
                <label className="flex items-center gap-2 text-sm">
                  <RadioGroupItem value="no" /> No, it is already counted in {group?.name ?? "the group"} and is only getting a tag
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <RadioGroupItem value="yes" /> Yes, it was just bought, born or brought in (adds one to the group)
                </label>
              </RadioGroup>
            </div>
          )}

          {(isEdit || isNew === "yes") && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Came from</Label>
                <Select value={form.source} onValueChange={(v) => set("source", v as AnimalSource)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Purchased">Bought</SelectItem>
                    <SelectItem value="BornOnFarm">Born on the farm</SelectItem>
                    <SelectItem value="OnFarm">Already on the farm</SelectItem>
                    <SelectItem value="Other">Other</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label htmlFor="a-acq">{form.source === "BornOnFarm" ? "Date (birth)" : "Date it arrived"}</Label>
                <Input id="a-acq" type="date" max={todayIso()} value={form.acquiredDate ?? ""}
                  onChange={(e) => set("acquiredDate", e.target.value || null)} />
              </div>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Sex</Label>
              <Select value={form.sex} onValueChange={(v) => set("sex", v as AnimalSex)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Female">Female</SelectItem>
                  <SelectItem value="Male">Male</SelectItem>
                  <SelectItem value="Unknown">Not known</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="a-birth">Birth date</Label>
              <Input id="a-birth" type="date" max={todayIso()} value={form.birthDate ?? ""}
                onChange={(e) => set("birthDate", e.target.value || null)} />
            </div>
          </div>

          {species?.breedsOnFarm !== false && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Mother</Label>
                <Select value={form.damId ? String(form.damId) : NONE} onValueChange={(v) => set("damId", v === NONE ? null : Number(v))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NONE}>Not known</SelectItem>
                    {dams.map((p) => <SelectItem key={p.animalId} value={String(p.animalId)}>{p.tagNumber}{p.name ? ` · ${p.name}` : ""}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label>Father</Label>
                <Select value={form.sireId ? String(form.sireId) : NONE} onValueChange={(v) => set("sireId", v === NONE ? null : Number(v))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NONE}>Not known</SelectItem>
                    {sires.map((p) => <SelectItem key={p.animalId} value={String(p.animalId)}>{p.tagNumber}{p.name ? ` · ${p.name}` : ""}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="a-breed">Breed</Label>
              <BreedSelect id="a-breed" speciesCode={speciesCode} value={form.breed} onChange={(v) => set("breed", v)}
                placeholder={group?.breed ? `Same as group: ${group.breed}` : "Choose a breed"} />
            </div>
            {form.source === "Purchased" && (
              <div>
                <Label htmlFor="a-cost">Price paid</Label>
                <Input id="a-cost" type="number" min={0} step="0.01" value={form.purchaseCost ?? ""}
                  onChange={(e) => set("purchaseCost", e.target.value === "" ? null : Number(e.target.value))} />
              </div>
            )}
          </div>
          <div>
            <Label htmlFor="a-notes">Notes</Label>
            <Textarea id="a-notes" rows={2} value={form.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function blank(): AnimalInput {
  return { tagNumber: "", name: null, sex: "Female", breed: null, birthDate: null, damId: null, sireId: null,
    source: "Purchased", acquiredDate: todayIso(), purchaseCost: null, notes: null }
}

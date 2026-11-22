"use client"

// New / edit animal group -- the poultry flock form for livestock.
//
// Creating asks where the animals come from:
//   From a batch      -- part of an intake batch not yet in a group.
//   Already on farm   -- animals alive on the start date, before recording
//                        began (poultry's Opening Farm Position, inline).
//   Empty for now     -- head arrives later through tags, births or moves.
// Editing changes the description only; head changes are recorded on the
// group page.

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
  listBatches, listPens, saveGroup,
  type GroupInput, type GroupPurpose, type LivestockBatch, type LivestockGroup, type LivestockPen,
} from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AgeDaysInput, AgeTextInput, BreedSelect } from "@/components/livestock/breed-age-inputs"
import { AMBER_BUTTON, todayIso } from "./livestock-page"

const NONE = "__none"
const PURPOSES: { value: GroupPurpose; label: string }[] = [
  { value: "Meat", label: "Meat / growing" },
  { value: "Eggs", label: "Eggs" },
  { value: "Milk", label: "Milk" },
  { value: "Breeding", label: "Breeding" },
  { value: "Mixed", label: "Mixed" },
]

export function GroupFormDialog({ open, onOpenChange, group, presetBatchId, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  /** Edit when given. */
  group?: LivestockGroup | null
  presetBatchId?: number | null
  onSaved: (groupId: number) => void
}) {
  const { toast } = useToast()
  const { kept, byCode } = useLivestockSpecies()
  const [pens, setPens] = useState<LivestockPen[]>([])
  const [batches, setBatches] = useState<LivestockBatch[]>([])
  const [form, setForm] = useState<GroupInput>(() => emptyForm())
  const [saving, setSaving] = useState(false)
  const isEdit = !!group

  useEffect(() => {
    if (!open) return
    listPens().then(setPens).catch(() => setPens([]))
    listBatches().then(setBatches).catch(() => setBatches([]))
    if (group) {
      setForm({
        name: group.name, speciesCode: group.speciesCode, penId: group.penId, breed: group.breed,
        purpose: group.purpose, startDate: group.startDate, ageAtStartDays: group.ageAtStartDays, notes: group.notes,
      })
    } else {
      setForm({ ...emptyForm(), speciesCode: kept[0]?.speciesCode ?? "",
        source: presetBatchId ? "Batch" : "Opening", batchId: presetBatchId ?? null })
    }
  }, [open, group, presetBatchId, kept])

  // A preset batch fixes the species and the earliest start.
  useEffect(() => {
    if (!form.batchId || isEdit) return
    const b = batches.find((x) => x.batchId === form.batchId)
    if (b && b.speciesCode !== form.speciesCode) setForm((f) => ({ ...f, speciesCode: b.speciesCode, startDate: b.intakeDate }))
  }, [form.batchId, batches, isEdit, form.speciesCode])

  const species = byCode.get(form.speciesCode)
  const groupTerm = species?.groupTerm ?? "group"
  const openBatches = batches.filter((b) => b.speciesCode === form.speciesCode && b.unallocated > 0)
  const pickedBatch = batches.find((b) => b.batchId === form.batchId)
  const penChoices = pens.filter((p) => p.isActive && (!p.speciesCode || p.speciesCode === form.speciesCode))
  const pen = pens.find((p) => p.penId === form.penId)
  const overCapacity = useMemo(() => {
    if (!pen?.capacity || isEdit) return false
    return pen.head + (Number(form.quantity) || 0) > pen.capacity
  }, [pen, form.quantity, isEdit])

  const set = <K extends keyof GroupInput>(k: K, v: GroupInput[K]) => setForm((f) => ({ ...f, [k]: v }))

  const save = async () => {
    setSaving(true)
    try {
      const res = await saveGroup(form, group?.groupId)
      toast({ title: isEdit ? `${groupTerm} updated` : `${groupTerm} created` })
      onOpenChange(false)
      onSaved(res.groupId)
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const canSave = form.name.trim() && form.speciesCode && form.startDate &&
    (isEdit || form.source === "Empty" || (Number(form.quantity) > 0 && (form.source !== "Batch" || form.batchId)))

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>{isEdit ? `Edit ${group!.name}` : "New animal group"}</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Animal</Label>
              <Select value={form.speciesCode} disabled={isEdit || !!presetBatchId}
                onValueChange={(v) => setForm((f) => ({ ...f, speciesCode: v, penId: null, batchId: null, breed: null }))}>
                <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                <SelectContent>
                  {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="g-name">Name</Label>
              <Input id="g-name" value={form.name} onChange={(e) => set("name", e.target.value)}
                placeholder={species ? `${species.name} ${groupTerm} 1` : ""} />
            </div>
          </div>

          {!isEdit && (
            <div>
              <Label>Where do the animals come from?</Label>
              <RadioGroup value={form.source} onValueChange={(v) => set("source", v as GroupInput["source"])} className="mt-1 space-y-1">
                <label className="flex items-center gap-2 text-sm"><RadioGroupItem value="Batch" /> From an intake batch</label>
                <label className="flex items-center gap-2 text-sm"><RadioGroupItem value="Opening" /> Already on the farm</label>
                <label className="flex items-center gap-2 text-sm"><RadioGroupItem value="Empty" /> Empty for now (add tagged animals or births later)</label>
              </RadioGroup>
            </div>
          )}

          {!isEdit && form.source === "Batch" && (
            <div>
              <Label>Batch</Label>
              <Select value={form.batchId ? String(form.batchId) : ""} disabled={!!presetBatchId}
                onValueChange={(v) => setForm((f) => ({ ...f, batchId: Number(v), startDate:
                  batches.find((b) => b.batchId === Number(v))?.intakeDate ?? f.startDate }))}>
                <SelectTrigger><SelectValue placeholder={openBatches.length ? "Choose a batch" : "No batch with animals left"} /></SelectTrigger>
                <SelectContent>
                  {openBatches.map((b) => (
                    <SelectItem key={b.batchId} value={String(b.batchId)}>
                      {b.batchCode} · {b.unallocated} of {b.quantity} not in a group
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="g-start">{!isEdit && form.source === "Opening" ? "Count date" : "Start date"}</Label>
              <Input id="g-start" type="date" max={todayIso()} value={form.startDate} onChange={(e) => set("startDate", e.target.value)} />
            </div>
            {!isEdit && form.source !== "Empty" && (
              <div>
                <Label htmlFor="g-qty">How many animals</Label>
                <Input id="g-qty" type="number" min={1} inputMode="numeric" value={form.quantity ?? ""}
                  onChange={(e) => set("quantity", e.target.value === "" ? null : Number(e.target.value))} />
                {pickedBatch && <p className="text-xs text-stone-500 mt-1">Up to {pickedBatch.unallocated}</p>}
              </div>
            )}
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>{species?.penTerm ?? "Pen"}</Label>
              <Select value={form.penId ? String(form.penId) : NONE} onValueChange={(v) => set("penId", v === NONE ? null : Number(v))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={NONE}>Not in a pen</SelectItem>
                  {penChoices.map((p) => <SelectItem key={p.penId} value={String(p.penId)}>{p.name}</SelectItem>)}
                </SelectContent>
              </Select>
              {overCapacity && (
                <p className="text-xs text-amber-800 mt-1">
                  {pen!.name} holds {pen!.capacity}; it would have {pen!.head + Number(form.quantity)}.
                </p>
              )}
            </div>
            <div>
              <Label>Kept for</Label>
              <Select value={form.purpose} onValueChange={(v) => set("purpose", v as GroupPurpose)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {PURPOSES
                    .filter((p) => p.value !== "Eggs" || species?.producesEggs)
                    .filter((p) => p.value !== "Milk" || species?.producesMilk)
                    .map((p) => <SelectItem key={p.value} value={p.value}>{p.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="g-age">Age on the start date</Label>
              <AgeDaysInput key={`${open}-${group?.groupId ?? "new"}`} id="g-age" value={form.ageAtStartDays ?? null} onChange={(d) => set("ageAtStartDays", d)} />
              <p className="text-xs text-stone-500 mt-1">Times the vaccination plan. Leave empty if they were just born.</p>
            </div>
            <div>
            <Label htmlFor="g-breed">Breed</Label>
            <BreedSelect id="g-breed" speciesCode={form.speciesCode} value={form.breed} onChange={(v) => set("breed", v)}
              placeholder={pickedBatch?.breed ? `Same as batch: ${pickedBatch.breed}` : "Choose a breed"} />
            </div>
          </div>
          <div>
            <Label htmlFor="g-notes">Notes</Label>
            <Textarea id="g-notes" rows={2} value={form.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} />
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

function emptyForm(): GroupInput {
  return { name: "", speciesCode: "", penId: null, breed: null, purpose: "Meat", startDate: todayIso(), ageAtStartDays: null, notes: null,
    source: "Opening", batchId: null, quantity: null }
}

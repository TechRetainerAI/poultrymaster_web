"use client"

// Record a breeding event: mating, pregnancy check, birth, weaning, loss.
// A birth adds its live young to a group; a weaning can move them to another.
// Words follow the species (Kidding / Kids, Farrowing / Piglets...).

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import {
  listAnimals, listGroups, saveBreeding,
  type BreedingEvent, type BreedingEventType, type BreedingInput, type LivestockAnimal, type LivestockGroup,
} from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, todayIso } from "./livestock-page"

const NONE = "__none"

export function BreedingDialog({ open, onOpenChange, event, preset, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  /** Edit when given. */
  event?: BreedingEvent | null
  preset?: Partial<BreedingInput>
  onSaved: () => void
}) {
  const { toast } = useToast()
  const { byCode, kept } = useLivestockSpecies()
  const [animals, setAnimals] = useState<LivestockAnimal[]>([])
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [f, setF] = useState<BreedingInput>(blank())
  const [saving, setSaving] = useState(false)
  const isEdit = !!event

  useEffect(() => {
    if (!open) return
    listAnimals({ status: "Active" }).then(setAnimals).catch(() => setAnimals([]))
    listGroups().then(setGroups).catch(() => setGroups([]))
    setF(event ? {
      eventType: event.eventType, date: event.date, damId: event.damId, sireId: event.sireId, groupId: event.groupId,
      toGroupId: event.toGroupId, method: event.method, result: event.result, bornAlive: event.bornAlive,
      bornDead: event.bornDead, weanedCount: event.weanedCount, notes: event.notes,
    } : { ...blank(), ...preset })
    // Keyed on the preset's contents: callers pass it inline, and a new object
    // each render must not wipe what is being typed.
  }, [open, event, JSON.stringify(preset ?? {})]) // eslint-disable-line react-hooks/exhaustive-deps

  const breeders = new Set(kept.filter((s) => s.breedsOnFarm).map((s) => s.speciesCode))
  const dam = animals.find((a) => a.animalId === f.damId)
  const speciesCode = dam?.speciesCode ?? groups.find((g) => g.groupId === f.groupId)?.speciesCode
  const sp = speciesCode ? byCode.get(speciesCode) : undefined
  const females = animals.filter((a) => a.sex !== "Male" && breeders.has(a.speciesCode))
  const males = animals.filter((a) => a.sex !== "Female" && (!speciesCode || a.speciesCode === speciesCode))
  const groupChoices = groups.filter((g) => breeders.has(g.speciesCode) && (!speciesCode || g.speciesCode === speciesCode))
  const set = <K extends keyof BreedingInput>(k: K, v: BreedingInput[K]) => setF((s) => ({ ...s, [k]: v }))
  const t = f.eventType
  const young = (sp?.youngTerm ?? "young").toLowerCase()

  const save = async () => {
    setSaving(true)
    try {
      await saveBreeding(f, event?.eventId)
      toast({ title: "Recorded" })
      onOpenChange(false)
      onSaved()
    } catch (e: any) {
      toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const needsDam = t === "Mating" || t === "PregnancyCheck" || t === "Loss"
  const canSave = f.date && (!needsDam || f.damId) &&
    (t !== "PregnancyCheck" || f.result) &&
    (t !== "Birth" || (f.groupId && ((f.bornAlive ?? 0) + (f.bornDead ?? 0)) > 0)) &&
    (t !== "Weaning" || (f.groupId && (f.weanedCount ?? 0) > 0))

  // Default the young's group to the mother's own group.
  useEffect(() => {
    if (!isEdit && t === "Birth" && dam && !f.groupId) setF((s) => ({ ...s, groupId: dam.groupId }))
  }, [t, dam, isEdit, f.groupId])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>{isEdit ? "Edit breeding record" : "Record breeding"}</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>What happened</Label>
              <Select value={t} disabled={isEdit} onValueChange={(v) => set("eventType", v as BreedingEventType)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Mating">Mated / served</SelectItem>
                  <SelectItem value="PregnancyCheck">Pregnancy check</SelectItem>
                  <SelectItem value="Birth">{sp?.birthTerm ? `${sp.birthTerm} (birth)` : "Birth"}</SelectItem>
                  <SelectItem value="Weaning">Weaning</SelectItem>
                  <SelectItem value="Loss">Lost the pregnancy</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="br-date">Date</Label>
              <Input id="br-date" type="date" max={todayIso()} value={f.date} onChange={(e) => set("date", e.target.value)} />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Female{needsDam ? "" : " (if known)"}</Label>
              <Select value={f.damId ? String(f.damId) : NONE} onValueChange={(v) => set("damId", v === NONE ? null : Number(v))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {!needsDam && <SelectItem value={NONE}>Not known / untagged</SelectItem>}
                  {females.map((a) => <SelectItem key={a.animalId} value={String(a.animalId)}>{a.tagNumber} · {a.speciesName}{a.name ? ` · ${a.name}` : ""}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            {(t === "Mating" || t === "Birth") && (
              <div>
                <Label>Male (if known)</Label>
                <Select value={f.sireId ? String(f.sireId) : NONE} onValueChange={(v) => set("sireId", v === NONE ? null : Number(v))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NONE}>Not known</SelectItem>
                    {males.map((a) => <SelectItem key={a.animalId} value={String(a.animalId)}>{a.tagNumber}{a.name ? ` · ${a.name}` : ""}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            )}
          </div>

          {t === "Mating" && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>How</Label>
                <Select value={f.method ?? "Natural"} onValueChange={(v) => set("method", v as "Natural" | "AI")}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Natural">Natural</SelectItem>
                    <SelectItem value="AI">Artificial insemination</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              {sp?.gestationDays && f.date && (
                <p className="text-sm text-stone-600 self-end pb-2">
                  Due about {new Date(new Date(f.date + "T00:00:00").getTime() + sp.gestationDays * 86400000).toLocaleDateString()}
                </p>
              )}
            </div>
          )}

          {t === "PregnancyCheck" && (
            <div>
              <Label>Result</Label>
              <Select value={f.result ?? ""} onValueChange={(v) => set("result", v as "Pregnant" | "NotPregnant")}>
                <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Pregnant">Pregnant</SelectItem>
                  <SelectItem value="NotPregnant">Not pregnant</SelectItem>
                </SelectContent>
              </Select>
            </div>
          )}

          {(t === "Birth" || t === "Weaning") && (
            <div>
              <Label>{t === "Birth" ? `Group the ${young} go into` : `Group the ${young} are in`}</Label>
              <Select value={f.groupId ? String(f.groupId) : ""} onValueChange={(v) => set("groupId", Number(v))}>
                <SelectTrigger><SelectValue placeholder="Choose a group" /></SelectTrigger>
                <SelectContent>
                  {groupChoices.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.head} head</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          )}

          {t === "Birth" && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label htmlFor="br-alive">Born alive</Label>
                <Input id="br-alive" type="number" min={0} inputMode="numeric" value={f.bornAlive ?? ""}
                  onChange={(e) => set("bornAlive", e.target.value === "" ? null : Number(e.target.value))} />
              </div>
              <div>
                <Label htmlFor="br-dead">Born dead</Label>
                <Input id="br-dead" type="number" min={0} inputMode="numeric" value={f.bornDead ?? ""}
                  onChange={(e) => set("bornDead", e.target.value === "" ? null : Number(e.target.value))} />
              </div>
              <p className="col-span-2 text-xs text-stone-500">
                The live {young} are added to the group's count. Tag any you want to follow one by one as already counted.
              </p>
            </div>
          )}

          {t === "Weaning" && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label htmlFor="br-weaned">How many weaned</Label>
                <Input id="br-weaned" type="number" min={1} inputMode="numeric" value={f.weanedCount ?? ""}
                  onChange={(e) => set("weanedCount", e.target.value === "" ? null : Number(e.target.value))} />
              </div>
              <div>
                <Label>Move them to</Label>
                <Select value={f.toGroupId ? String(f.toGroupId) : NONE} onValueChange={(v) => set("toGroupId", v === NONE ? null : Number(v))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NONE}>Stay in the same group</SelectItem>
                    {groupChoices.filter((g) => g.groupId !== f.groupId).map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
          )}

          <div>
            <Label htmlFor="br-notes">Notes</Label>
            <Textarea id="br-notes" rows={2} value={f.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} />
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

function blank(): BreedingInput {
  return { eventType: "Mating", date: todayIso(), damId: null, sireId: null, groupId: null, toGroupId: null,
    method: "Natural", result: null, bornAlive: null, bornDead: null, weanedCount: null, notes: null }
}

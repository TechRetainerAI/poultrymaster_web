"use client"

// Add / edit a health record: an observation, illness, treatment, vaccination,
// deworming or vet visit, on a group or one tagged animal. A medicine or
// vaccine used is taken out of stock. Opened pre-filled from a due
// vaccination step to mark it given.

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import {
  listAnimals, listGroups, listItems, saveHealth,
  type HealthInput, type HealthKind, type HealthRecord, type LivestockAnimal, type LivestockGroup, type LivestockItem,
} from "@/lib/api/livestock"
import { AMBER_BUTTON, fmtNum, todayIso } from "./livestock-page"

const NONE = "__none"
export const HEALTH_KIND_LABEL: Record<HealthKind, string> = {
  Observation: "Observation", Illness: "Illness", Treatment: "Treatment", Vaccination: "Vaccination",
  Deworming: "Deworming", VetVisit: "Vet visit",
}

export function HealthDialog({ open, onOpenChange, record, preset, title, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  record?: HealthRecord | null
  preset?: Partial<HealthInput>
  title?: string
  onSaved: () => void
}) {
  const { toast } = useToast()
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [animals, setAnimals] = useState<LivestockAnimal[]>([])
  const [items, setItems] = useState<LivestockItem[]>([])
  const [f, setF] = useState<HealthInput>(blank())
  const [saving, setSaving] = useState(false)
  const isEdit = !!record

  useEffect(() => {
    if (!open) return
    listGroups().then(setGroups).catch(() => setGroups([]))
    listItems().then((xs) => setItems(xs.filter((i) => ["Medication", "Vaccine", "Supply", "Other"].includes(i.category)))).catch(() => setItems([]))
    setF(record ? {
      groupId: record.groupId, animalId: record.animalId, date: record.date, kind: record.kind, affected: record.affected,
      signs: record.signs, diagnosis: record.diagnosis, action: record.action, vetName: record.vetName, itemId: record.itemId,
      quantity: record.quantity, stepId: record.stepId, status: record.status, resolvedDate: record.resolvedDate, notes: record.notes,
    } : { ...blank(), ...preset })
    // Keyed on the preset's contents: callers pass it inline.
  }, [open, record, JSON.stringify(preset ?? {})]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!open || !f.groupId) { setAnimals([]); return }
    listAnimals({ groupId: f.groupId }).then(setAnimals).catch(() => setAnimals([]))
  }, [open, f.groupId])

  const group = groups.find((g) => g.groupId === f.groupId)
  const usable = items.filter((i) => !i.speciesCode || i.speciesCode === group?.speciesCode)
  const item = items.find((i) => i.itemId === f.itemId)
  const set = <K extends keyof HealthInput>(k: K, v: HealthInput[K]) => setF((s) => ({ ...s, [k]: v }))

  const save = async () => {
    setSaving(true)
    try {
      await saveHealth(f, record?.healthId)
      toast({ title: isEdit ? "Health record updated" : "Health record saved" })
      onOpenChange(false)
      onSaved()
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }
  const canSave = f.groupId && f.date && (f.itemId == null) === (f.quantity == null)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>{title ?? (isEdit ? "Edit health record" : "New health record")}</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Group</Label>
              <Select value={f.groupId ? String(f.groupId) : ""} disabled={isEdit || !!preset?.groupId}
                onValueChange={(v) => setF((s) => ({ ...s, groupId: Number(v), animalId: null, itemId: null, quantity: null }))}>
                <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                <SelectContent>{groups.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.speciesName}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div>
              <Label>What</Label>
              <Select value={f.kind} disabled={!!preset?.stepId} onValueChange={(v) => setF((s) => ({ ...s, kind: v as HealthKind,
                status: v === "Illness" ? "Open" : "Resolved" }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(Object.keys(HEALTH_KIND_LABEL) as HealthKind[]).map((k) => <SelectItem key={k} value={k}>{HEALTH_KIND_LABEL[k]}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="h-date">Date</Label>
              <Input id="h-date" type="date" max={todayIso()} min={group?.startDate} value={f.date} onChange={(e) => set("date", e.target.value)} />
            </div>
            {animals.length > 0 ? (
              <div>
                <Label>One animal (optional)</Label>
                <Select value={f.animalId ? String(f.animalId) : NONE} onValueChange={(v) => set("animalId", v === NONE ? null : Number(v))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NONE}>The whole group</SelectItem>
                    {animals.map((a) => <SelectItem key={a.animalId} value={String(a.animalId)}>{a.tagNumber}{a.name ? ` · ${a.name}` : ""}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            ) : <div />}
          </div>
          {!f.animalId && (f.kind === "Illness" || f.kind === "Observation" || f.kind === "Treatment") && (
            <div className="w-1/2 pr-1.5">
              <Label htmlFor="h-aff">Animals affected</Label>
              <Input id="h-aff" type="number" min={1} inputMode="numeric" value={f.affected ?? ""}
                onChange={(e) => set("affected", e.target.value === "" ? null : Number(e.target.value))} />
            </div>
          )}
          {(f.kind === "Illness" || f.kind === "Observation" || f.kind === "VetVisit") && (
            <>
              <div>
                <Label htmlFor="h-signs">What you saw</Label>
                <Textarea id="h-signs" rows={2} value={f.signs ?? ""} onChange={(e) => set("signs", e.target.value || null)} placeholder="Coughing, not eating, diarrhoea…" />
              </div>
              <div>
                <Label htmlFor="h-diag">Diagnosis</Label>
                <Input id="h-diag" value={f.diagnosis ?? ""} onChange={(e) => set("diagnosis", e.target.value || null)} />
              </div>
            </>
          )}
          <div>
            <Label htmlFor="h-action">What was done</Label>
            <Input id="h-action" value={f.action ?? ""} onChange={(e) => set("action", e.target.value || null)} />
          </div>
          <div className="grid grid-cols-[1fr_8rem] gap-3">
            <div>
              <Label>Medicine or vaccine used (optional)</Label>
              <Select value={f.itemId ? String(f.itemId) : NONE} onValueChange={(v) => setF((s) => ({ ...s, itemId: v === NONE ? null : Number(v), quantity: v === NONE ? null : s.quantity }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={NONE}>None from stock</SelectItem>
                  {usable.map((i) => <SelectItem key={i.itemId} value={String(i.itemId)}>{i.name} · {fmtNum(i.stock)} {i.unit} left</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="h-qty">How much{item ? ` (${item.unit})` : ""}</Label>
              <Input id="h-qty" type="number" min={0} step="any" disabled={!f.itemId} value={f.quantity ?? ""}
                onChange={(e) => set("quantity", e.target.value === "" ? null : Number(e.target.value))} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="h-vet">Vet (optional)</Label>
              <Input id="h-vet" value={f.vetName ?? ""} onChange={(e) => set("vetName", e.target.value || null)} />
            </div>
            {f.kind === "Illness" && (
              <div>
                <Label>Status</Label>
                <Select value={f.status} onValueChange={(v) => set("status", v as "Open" | "Resolved")}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Open">Still sick</SelectItem>
                    <SelectItem value="Resolved">Recovered</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            )}
          </div>
          <div>
            <Label htmlFor="h-notes">Notes</Label>
            <Textarea id="h-notes" rows={2} value={f.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} />
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

function blank(): HealthInput {
  return { groupId: null, animalId: null, date: todayIso(), kind: "Observation", affected: null, signs: null, diagnosis: null,
    action: null, vetName: null, itemId: null, quantity: null, stepId: null, status: "Resolved", notes: null }
}

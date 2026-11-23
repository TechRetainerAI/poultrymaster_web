"use client"

// Record a change to a group's head that has no record of its own: deaths or
// culls outside a production record, a count correction, or moving animals to
// another group of the same kind. Tagged animals are changed on the animal
// itself (the database refuses an untagged loss that would eat into them).

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { changeHead, listGroups, type HeadChangeType, type LivestockGroup } from "@/lib/api/livestock"
import { AMBER_BUTTON, todayIso } from "./livestock-page"

export function HeadChangeDialog({ open, onOpenChange, group, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  group: LivestockGroup
  onSaved: () => void
}) {
  const { toast } = useToast()
  const [type, setType] = useState<HeadChangeType>("Death")
  const [date, setDate] = useState(todayIso())
  const [qty, setQty] = useState("")
  const [direction, setDirection] = useState<"up" | "down">("down")
  const [notes, setNotes] = useState("")
  const [toGroupId, setToGroupId] = useState<string>("")
  const [others, setOthers] = useState<LivestockGroup[]>([])
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open) return
    setType("Death"); setDate(todayIso()); setQty(""); setNotes(""); setToGroupId(""); setDirection("down")
    listGroups().then((gs) => setOthers(gs.filter((g) => g.groupId !== group.groupId && g.speciesCode === group.speciesCode)))
      .catch(() => setOthers([]))
  }, [open, group.groupId, group.speciesCode])

  const n = Number(qty)
  const delta = type === "Correction" ? (direction === "up" ? n : -n) : -n
  const after = Number.isFinite(n) && n > 0 ? group.head + delta : null

  const save = async () => {
    setSaving(true)
    try {
      await changeHead(group.groupId, {
        date, type, quantity: type === "Correction" ? delta : n, notes: notes.trim() || null,
        toGroupId: type === "Transfer" ? Number(toGroupId) : null,
      })
      toast({ title: "Recorded", description: `${group.name} now has ${after} animal(s).` })
      onOpenChange(false)
      onSaved()
    } catch (e: any) {
      toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const canSave = n > 0 && date && (type !== "Transfer" || toGroupId) && (type !== "Correction" || notes.trim())

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Change the count of {group.name}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>What happened</Label>
              <Select value={type} onValueChange={(v) => setType(v as HeadChangeType)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Death">Died</SelectItem>
                  <SelectItem value="Cull">Culled / removed</SelectItem>
                  <SelectItem value="Transfer">Moved to another group</SelectItem>
                  <SelectItem value="Correction">Count correction</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="hc-date">Date</Label>
              <Input id="hc-date" type="date" min={group.startDate} max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>

          {type === "Correction" && (
            <div>
              <Label>The real count is</Label>
              <Select value={direction} onValueChange={(v) => setDirection(v as "up" | "down")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="down">Lower than recorded</SelectItem>
                  <SelectItem value="up">Higher than recorded</SelectItem>
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="hc-qty">{type === "Correction" ? "By how many" : "How many"}</Label>
              <Input id="hc-qty" type="number" min={1} inputMode="numeric" value={qty} onChange={(e) => setQty(e.target.value)} />
            </div>
            {type === "Transfer" && (
              <div>
                <Label>To group</Label>
                <Select value={toGroupId} onValueChange={setToGroupId}>
                  <SelectTrigger><SelectValue placeholder={others.length ? "Choose" : "No other group"} /></SelectTrigger>
                  <SelectContent>
                    {others.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            )}
          </div>

          <div>
            <Label htmlFor="hc-notes">{type === "Correction" ? "Why (required)" : "Notes"}</Label>
            <Textarea id="hc-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>

          {after != null && (
            <p className={`text-sm ${after < 0 ? "text-rose-700" : "text-stone-600"}`}>
              {group.head} now → <strong>{after}</strong> after this.
              {group.tagged > 0 && type !== "Transfer" && " Tagged animals that died or were sold are recorded on the animal itself."}
            </p>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>{saving ? "Saving…" : "Record"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

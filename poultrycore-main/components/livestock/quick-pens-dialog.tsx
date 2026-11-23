"use client"

// Quickly add pens -- the poultry "Quickly Add Houses/Pens" for livestock,
// opened from Divide into groups so pens can be made without leaving it.
// Names are made from a prefix and a number ("Hutch 1", "Hutch 2"…) and can
// be edited before saving. Pens are setup, so only an owner/admin can add them.

import { useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useToast } from "@/hooks/use-toast"
import { savePen, type LivestockPen } from "@/lib/api/livestock"
import { AMBER_BUTTON } from "./livestock-page"

export function QuickPensDialog({ speciesCode, speciesName, penTerm, existing, onClose, onCreated }: {
  speciesCode: string
  speciesName: string
  /** What a pen is called for this animal: Hutch, Sty, Paddock… */
  penTerm: string
  /** Pens already on the farm, so new names do not repeat them. */
  existing: LivestockPen[]
  onClose: () => void
  /** The new pens' ids, in the order shown. */
  onCreated: (penIds: number[]) => void
}) {
  const { toast } = useToast()
  const [prefix, setPrefix] = useState(penTerm)
  const [count, setCount] = useState(2)
  const [capacity, setCapacity] = useState("")
  // The same entries as a pen on Setup → Pens. "For" is this animal or any
  // animal -- the only pens Divide into groups can offer for this batch.
  const [forSpecies, setForSpecies] = useState<"this" | "any">("this")
  const [location, setLocation] = useState("")
  const [notes, setNotes] = useState("")
  const [edited, setEdited] = useState<Record<number, string>>({})
  const [saving, setSaving] = useState(false)

  // Number on from the highest "<prefix> N" already on the farm.
  const names = useMemo(() => {
    const p = prefix.trim()
    const taken = new Set(existing.map((x) => x.name.trim().toLowerCase()))
    const out: string[] = []
    for (let n = 1; out.length < Math.min(Math.max(count, 0), 50); n++) {
      const name = `${p} ${n}`
      if (!taken.has(name.toLowerCase())) out.push(name)
    }
    return out.map((n, i) => edited[i] ?? n)
  }, [prefix, count, existing, edited])

  const save = async () => {
    setSaving(true)
    const ids: number[] = []
    try {
      for (const name of names) {
        const { penId } = await savePen({ name: name.trim(), speciesCode: forSpecies === "this" ? speciesCode : null,
          capacity: capacity ? Number(capacity) : null,
          location: location.trim() || null, notes: notes.trim() || null, isActive: true })
        ids.push(penId)
      }
      toast({ title: `${ids.length} ${penTerm.toLowerCase()}(s) added` })
      onCreated(ids)
    } catch (e: any) {
      toast({ title: ids.length ? `Only ${ids.length} added` : "Not added", description: e?.message ?? String(e), variant: "destructive" })
      if (ids.length) onCreated(ids)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>Quickly add {penTerm.toLowerCase()}s</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-stone-600">For {speciesName.toLowerCase()}. You can change any of them later on Setup → Pens.</p>
          <div className="grid grid-cols-3 gap-2">
            <div className="col-span-3 sm:col-span-1">
              <Label htmlFor="qp-prefix">Name</Label>
              <Input id="qp-prefix" value={prefix} onChange={(e) => { setPrefix(e.target.value); setEdited({}) }} />
            </div>
            <div>
              <Label htmlFor="qp-count">How many</Label>
              <Input id="qp-count" type="number" min={1} max={50} inputMode="numeric" value={count || ""}
                onChange={(e) => { setCount(Number(e.target.value)); setEdited({}) }} />
            </div>
            <div>
              <Label htmlFor="qp-cap">Capacity (animals, each)</Label>
              <Input id="qp-cap" type="number" min={1} inputMode="numeric" placeholder="Optional" value={capacity}
                onChange={(e) => setCapacity(e.target.value)} />
            </div>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <div>
              <Label>For</Label>
              <Select value={forSpecies} onValueChange={(v) => setForSpecies(v as "this" | "any")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="this">{speciesName}</SelectItem>
                  <SelectItem value="any">Any animal</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="qp-loc">Location</Label>
              <Input id="qp-loc" placeholder="Optional" value={location} onChange={(e) => setLocation(e.target.value)} />
            </div>
          </div>
          <div>
            <Label htmlFor="qp-notes">Notes</Label>
            <Textarea id="qp-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
          {names.length > 0 && (
            <div className="space-y-1.5 max-h-60 overflow-y-auto pr-1">
              {names.map((n, i) => (
                <Input key={i} aria-label={`Pen ${i + 1} name`} value={n} onChange={(e) => setEdited((x) => ({ ...x, [i]: e.target.value }))} />
              ))}
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !prefix.trim() || names.length === 0 || names.some((n) => !n.trim())} onClick={save}>
            {saving ? "Adding…" : `Add ${names.length}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

"use client"

// Stock item form and the "correct the count" dialog. A new item starts
// with no stock: stock comes in through a purchase (Record purchase), which
// also takes the money out of a cash account. Shared by the Feed & Stock list and an item's own page.

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { changeStock, saveItem, type ItemCategory, type ItemInput, type LivestockItem } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, fmtMoney, todayIso } from "./livestock-page"

const ANY = "__any"
const OTHER_UNIT = "__other"

/**
 * Units a stock item can be counted in. The value is what is saved; keep "kg"
 * exactly, since the database reads it as 1 kg per unit (459).
 */
export const ITEM_UNITS: { value: string; label: string }[] = [
  { value: "kg", label: "kg (kilogram)" }, { value: "g", label: "g (gram)" }, { value: "tonne", label: "Tonne" },
  { value: "bag", label: "Bag" }, { value: "sack", label: "Sack" }, { value: "bale", label: "Bale" },
  { value: "litre", label: "Litre" }, { value: "ml", label: "ml (millilitre)" }, { value: "bottle", label: "Bottle" },
  { value: "sachet", label: "Sachet" }, { value: "dose", label: "Dose" }, { value: "vial", label: "Vial" },
  { value: "tablet", label: "Tablet" }, { value: "piece", label: "Piece" }, { value: "pack", label: "Pack" },
  { value: "box", label: "Box" }, { value: "carton", label: "Carton" }, { value: "crate", label: "Crate" },
  { value: "tray", label: "Tray" }, { value: "dozen", label: "Dozen" }, { value: "unit", label: "Unit" },
]
const isListedUnit = (u: string) => ITEM_UNITS.some((x) => x.value === u.trim().toLowerCase())
export const CATEGORY_LABEL: Record<ItemCategory, string> = {
  Feed: "Feed", Ingredient: "Feed ingredient", Medication: "Medication", Vaccine: "Vaccine", Supply: "Supply", Produce: "Produce (eggs, milk, meat)", Other: "Other",
}

export function ItemFormDialog({ open, onOpenChange, item, defaultCategory = "Feed", onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  item?: LivestockItem | null
  defaultCategory?: ItemCategory
  onSaved: (itemId: number) => void
}) {
  const { toast } = useToast()
  const { kept } = useLivestockSpecies()
  const [f, setF] = useState<ItemInput>(blank(defaultCategory))
  const [saving, setSaving] = useState(false)
  const [otherUnit, setOtherUnit] = useState(false)
  const isEdit = !!item

  useEffect(() => {
    if (!open) return
    setF(item ? {
      name: item.name, category: item.category, unit: item.unit, kgPerUnit: item.kgPerUnit, minimumStock: item.minimumStock,
      speciesCode: item.speciesCode, notes: item.notes, isActive: item.isActive,
    } : blank(defaultCategory))
    // A unit typed before the list existed opens as "Other" with its text kept.
    setOtherUnit(!!item && !!item.unit && !isListedUnit(item.unit))
  }, [open, item, defaultCategory])

  const set = <K extends keyof ItemInput>(k: K, v: ItemInput[K]) => setF((s) => ({ ...s, [k]: v }))
  const isKg = f.unit.trim().toLowerCase() === "kg"

  const save = async () => {
    setSaving(true)
    try {
      const res = await saveItem(f, item?.itemId)
      toast({ title: isEdit ? "Item updated" : "Item added" })
      onOpenChange(false)
      onSaved(res.itemId)
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>{isEdit ? `Edit ${item!.name}` : "Add a stock item"}</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div>
            <Label htmlFor="i-name">Name</Label>
            <Input id="i-name" value={f.name} onChange={(e) => set("name", e.target.value)} placeholder="Goat pellets" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Kind</Label>
              <Select value={f.category} disabled={isEdit && item!.stock !== 0} onValueChange={(v) => set("category", v as ItemCategory)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(Object.keys(CATEGORY_LABEL) as ItemCategory[]).map((c) => <SelectItem key={c} value={c}>{CATEGORY_LABEL[c]}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>For</Label>
              <Select value={f.speciesCode ?? ANY} onValueChange={(v) => set("speciesCode", v === ANY ? null : v)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={ANY}>Any animal</SelectItem>
                  {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="i-unit">Counted in</Label>
              <Select value={otherUnit ? OTHER_UNIT : isListedUnit(f.unit) ? f.unit.trim().toLowerCase() : ""} disabled={isEdit && item!.stock !== 0}
                onValueChange={(v) => {
                  if (v === OTHER_UNIT) { setOtherUnit(true); set("unit", "") }
                  else { setOtherUnit(false); set("unit", v) }
                }}>
                <SelectTrigger id="i-unit"><SelectValue placeholder="Choose a unit" /></SelectTrigger>
                <SelectContent>
                  {ITEM_UNITS.map((u) => <SelectItem key={u.value} value={u.value}>{u.label}</SelectItem>)}
                  <SelectItem value={OTHER_UNIT}>Other (type it)</SelectItem>
                </SelectContent>
              </Select>
              {otherUnit && (
                <Input className="mt-2" aria-label="Unit" value={f.unit} disabled={isEdit && item!.stock !== 0}
                  onChange={(e) => set("unit", e.target.value)} placeholder="e.g. jerrycan" />
              )}
              {isEdit && item!.stock !== 0 && <p className="text-xs text-stone-500 mt-1">Fixed while there is stock.</p>}
            </div>
            {(f.category === "Feed" || f.category === "Ingredient") && !isKg && (
              <div>
                <Label htmlFor="i-kg">kg in one {f.unit || "unit"}</Label>
                <Input id="i-kg" type="number" min={0} step="0.001" value={f.kgPerUnit ?? ""}
                  onChange={(e) => set("kgPerUnit", e.target.value === "" ? null : Number(e.target.value))} />
                <p className="text-xs text-stone-500 mt-1">Needed for feed per kg gained.</p>
              </div>
            )}
          </div>
          <div>
            <Label htmlFor="i-min">Warn me when stock falls to</Label>
            <Input id="i-min" type="number" min={0} value={f.minimumStock ?? ""} placeholder="No warning"
              onChange={(e) => set("minimumStock", e.target.value === "" ? null : Number(e.target.value))} />
          </div>
          {!isEdit && (
            <p className="text-xs text-stone-500">The item starts with no stock. Use Record purchase to bring it in and pay for it.</p>
          )}
          <div>
            <Label htmlFor="i-notes">Notes</Label>
            <Textarea id="i-notes" rows={2} value={f.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} />
          </div>
          {isEdit && (
            <label className="flex items-center gap-2 text-sm"><Switch checked={f.isActive !== false} onCheckedChange={(v) => set("isActive", v)} /> In use</label>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !f.name.trim() || !f.unit.trim()} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function blank(category: ItemCategory): ItemInput {
  return { name: "", category, unit: category === "Feed" || category === "Ingredient" ? "kg" : "", kgPerUnit: null, minimumStock: null, speciesCode: null,
    notes: null }
}

/**
 * A count correction, with a reason. Stock no longer comes in here: it comes
 * in through a purchase, which also pays for it from a cash account.
 */
export function StockChangeDialog({ item, onClose, onDone }: { item: LivestockItem; onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const type = "Adjustment" as const
  const [qty, setQty] = useState("")
  const [direction, setDirection] = useState<"up" | "down">("down")
  const [cost, setCost] = useState(item.avgCost != null ? String(Math.round(item.avgCost * 100) / 100) : "")
  const [date, setDate] = useState(todayIso())
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)

  const n = Number(qty)
  const signed = direction === "down" ? -n : n
  const needsCost = signed > 0
  const save = async () => {
    setSaving(true)
    try {
      await changeStock({ itemId: item.itemId, date, type, quantity: signed, unitCost: needsCost ? Number(cost) : null, notes: notes.trim() || null })
      toast({ title: "Stock corrected" })
      onDone()
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }
  const canSave = n > 0 && date && (!needsCost || cost !== "") && notes.trim()

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Correct the count: {item.name} ({item.stock.toLocaleString()} {item.unit} recorded)</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-stone-600">Only for fixing the count after you check what is really there. To bring in new stock, use Record purchase.</p>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>The real stock is</Label>
              <Select value={direction} onValueChange={(v) => setDirection(v as "up" | "down")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="down">Less than recorded</SelectItem>
                  <SelectItem value="up">More than recorded</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="sc-date">Date</Label>
              <Input id="sc-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="sc-qty">By how much ({item.unit})</Label>
              <Input id="sc-qty" type="number" min={0} value={qty} onChange={(e) => setQty(e.target.value)} />
            </div>
            {needsCost && (
              <div>
                <Label htmlFor="sc-cost">Cost per {item.unit}</Label>
                <Input id="sc-cost" type="number" min={0} step="0.01" value={cost} onChange={(e) => setCost(e.target.value)} />
                {n > 0 && cost !== "" && <p className="text-xs text-stone-500 mt-1">Total {fmtMoney(n * Number(cost))}</p>}
              </div>
            )}
          </div>
          <div>
            <Label htmlFor="sc-notes">Why (required)</Label>
            <Textarea id="sc-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

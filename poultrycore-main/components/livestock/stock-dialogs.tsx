"use client"

// Stock item form (with opening stock on create) and the "add / correct
// stock" dialog. Shared by the Feed & Stock list and an item's own page.

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
  const isEdit = !!item

  useEffect(() => {
    if (!open) return
    setF(item ? {
      name: item.name, category: item.category, unit: item.unit, kgPerUnit: item.kgPerUnit, minimumStock: item.minimumStock,
      speciesCode: item.speciesCode, notes: item.notes, isActive: item.isActive,
    } : blank(defaultCategory))
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
              <Input id="i-unit" value={f.unit} disabled={isEdit && item!.stock !== 0} onChange={(e) => set("unit", e.target.value)} placeholder="kg, bag, bottle, dose" />
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
            <div className="rounded-md border border-amber-200 bg-amber-50/50 p-3 space-y-2">
              <div className="text-sm font-medium text-stone-800">Stock you have now (optional)</div>
              <div className="grid grid-cols-3 gap-2">
                <div>
                  <Label htmlFor="i-oq" className="text-xs">Quantity ({f.unit || "units"})</Label>
                  <Input id="i-oq" type="number" min={0} value={f.openingQuantity ?? ""}
                    onChange={(e) => set("openingQuantity", e.target.value === "" ? null : Number(e.target.value))} />
                </div>
                <div>
                  <Label htmlFor="i-oc" className="text-xs">Cost each</Label>
                  <Input id="i-oc" type="number" min={0} step="0.01" value={f.openingUnitCost ?? ""}
                    onChange={(e) => set("openingUnitCost", e.target.value === "" ? null : Number(e.target.value))} />
                </div>
                <div>
                  <Label htmlFor="i-od" className="text-xs">As of</Label>
                  <Input id="i-od" type="date" max={todayIso()} value={f.openingDate ?? todayIso()} onChange={(e) => set("openingDate", e.target.value)} />
                </div>
              </div>
            </div>
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
    notes: null, openingQuantity: null, openingUnitCost: null, openingDate: todayIso() }
}

/** Stock in (with its cost) or a count correction (with a reason). */
export function StockChangeDialog({ item, onClose, onDone }: { item: LivestockItem; onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const [type, setType] = useState<"StockIn" | "Adjustment">("StockIn")
  const [qty, setQty] = useState("")
  const [direction, setDirection] = useState<"up" | "down">("down")
  const [cost, setCost] = useState(item.avgCost != null ? String(Math.round(item.avgCost * 100) / 100) : "")
  const [date, setDate] = useState(todayIso())
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)

  const n = Number(qty)
  const signed = type === "Adjustment" && direction === "down" ? -n : n
  const needsCost = signed > 0
  const save = async () => {
    setSaving(true)
    try {
      await changeStock({ itemId: item.itemId, date, type, quantity: signed, unitCost: needsCost ? Number(cost) : null, notes: notes.trim() || null })
      toast({ title: type === "StockIn" ? "Stock added" : "Stock corrected" })
      onDone()
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }
  const canSave = n > 0 && date && (!needsCost || cost !== "") && (type !== "Adjustment" || notes.trim())

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{item.name}: {item.stock.toLocaleString()} {item.unit} in stock</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>What</Label>
              <Select value={type} onValueChange={(v) => setType(v as "StockIn" | "Adjustment")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="StockIn">Add stock</SelectItem>
                  <SelectItem value="Adjustment">Correct the count</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="sc-date">Date</Label>
              <Input id="sc-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>
          {type === "Adjustment" && (
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
          )}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="sc-qty">{type === "Adjustment" ? "By how much" : "How much"} ({item.unit})</Label>
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
            <Label htmlFor="sc-notes">{type === "Adjustment" ? "Why (required)" : "Notes"}</Label>
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

"use client"

// Egg classes on the Sales page (migrations 341-343).
//
// A sale deducts the class it sells: a Large sale comes out of Large, never
// out of Unsorted, and deleting it puts the eggs back into Large. A farm that
// does not sort has only Unsorted / General, and this whole block stays out of
// the way. Several classes on one sale are entered as extra lines and saved
// as one sale number with one payment.

import { Plus, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import type { EggClass } from "@/lib/api/egg-sorting"
import { EGGS_PER_CRATE } from "@/lib/production/production-record-calc"

/** Select value for Unsorted / General (sent to the API as 0). */
export const UNSORTED_VALUE = "unsorted"

export const classValue = (eggProductId: number | null | undefined) =>
  eggProductId ? String(eggProductId) : UNSORTED_VALUE

export const classIdFrom = (value: string): number | null =>
  value === UNSORTED_VALUE ? null : Number(value) || null

/** The class a sale draws from: its size, or the Unsorted product. */
export function classFor(classes: EggClass[], eggProductId: number | null | undefined): EggClass | undefined {
  return eggProductId
    ? classes.find((c) => c.poultryProductId === eggProductId)
    : classes.find((c) => c.classKind === "Unsorted")
}

export function EggClassSelect({
  classes, value, onChange, id, addBack = 0, addBackClass = null,
}: {
  classes: EggClass[]
  value: number | null | undefined
  onChange: (eggProductId: number | null) => void
  id?: string
  /** Editing: the sale's own eggs are back on the shelf for its own class. */
  addBack?: number
  addBackClass?: number | null
}) {
  const shown = classes.filter((c) => c.classKind === "Unsorted" || c.isActive || c.poultryProductId === value)
  const onHand = (c: EggClass) =>
    Math.max(0, Math.trunc(c.onHand + (((c.classKind === "Unsorted" ? null : c.poultryProductId) ?? null) === (addBackClass ?? null) ? addBack : 0)))
  return (
    <div className="space-y-2">
      <Label htmlFor={id} className="text-sm">Egg class *</Label>
      <Select value={classValue(value)} onValueChange={(v) => onChange(classIdFrom(v))}>
        <SelectTrigger id={id} className="bg-white"><SelectValue /></SelectTrigger>
        <SelectContent>
          {shown.map((c) => (
            <SelectItem key={c.poultryProductId} value={c.classKind === "Unsorted" ? UNSORTED_VALUE : String(c.poultryProductId)}>
              {c.classKind === "Unsorted" ? "Unsorted / General" : c.name} — {onHand(c).toLocaleString()} in stock
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <p className="text-xs text-slate-500">Stock comes out of this class only. Sizes come from the Egg Sorting Workspace.</p>
    </div>
  )
}

export interface ExtraEggLine {
  key: string
  eggProductId: number | null
  crates: number
  loose: number
  unitPrice: number
}

export const extraLineEggs = (l: ExtraEggLine) => l.crates * EGGS_PER_CRATE + l.loose

/** Same pricing as the main line: per crate, loose eggs pro rata. */
export const extraLineTotal = (l: ExtraEggLine) =>
  Math.round(((extraLineEggs(l) / EGGS_PER_CRATE) * l.unitPrice) * 100) / 100

export function ExtraEggLines({
  classes, lines, onChange, mainEggs, mainClass,
}: {
  classes: EggClass[]
  lines: ExtraEggLine[]
  onChange: (lines: ExtraEggLine[]) => void
  /** The main line's eggs and class, so a class's stock is not counted twice. */
  mainEggs: number
  mainClass: number | null
}) {
  const update = (key: string, patch: Partial<ExtraEggLine>) =>
    onChange(lines.map((l) => (l.key === key ? { ...l, ...patch } : l)))
  const priceOf = (id: number | null) => Number(classFor(classes, id)?.pricePerCrate) || 0
  const add = () => {
    const cls = classes.find((c) => c.classKind === "Size" && c.isActive && c.poultryProductId !== mainClass)?.poultryProductId ?? null
    onChange([...lines, { key: `${Date.now()}-${lines.length}`, eggProductId: cls, crates: 0, loose: 0, unitPrice: priceOf(cls) }])
  }

  // Eggs already asked of each class by the lines above this one.
  const usedBefore = (idx: number, cls: number | null) =>
    (mainClass === cls ? mainEggs : 0) + lines.slice(0, idx).filter((l) => l.eggProductId === cls).reduce((s, l) => s + extraLineEggs(l), 0)

  return (
    <div className="space-y-3 px-4 pb-4 bg-amber-50">
      {lines.map((l, idx) => {
        const cls = classFor(classes, l.eggProductId)
        const left = Math.max(0, Math.trunc((cls?.onHand ?? 0) - usedBefore(idx, l.eggProductId)))
        const short = extraLineEggs(l) > left
        return (
          <div key={l.key} className="rounded-lg border border-amber-200 bg-white p-3">
            <div className="grid grid-cols-2 items-end gap-3 sm:grid-cols-[minmax(10rem,1.5fr)_repeat(3,minmax(0,1fr))_auto]">
              <div className="col-span-2 sm:col-span-1">
                <EggClassSelect classes={classes} value={l.eggProductId}
                  onChange={(v) => update(l.key, { eggProductId: v, unitPrice: priceOf(v) || l.unitPrice })} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm">Crates</Label>
                <NumberInput min="0" value={l.crates} onChange={(e) => update(l.key, { crates: parseInt(e.target.value) || 0 })} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm">Loose</Label>
                <NumberInput min="0" max={String(EGGS_PER_CRATE - 1)} value={l.loose} onChange={(e) => update(l.key, { loose: parseInt(e.target.value) || 0 })} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm">Price / crate</Label>
                <NumberInput min="0" step="0.01" value={l.unitPrice} onChange={(e) => update(l.key, { unitPrice: Number(e.target.value) || 0 })} />
              </div>
              <Button type="button" variant="ghost" size="icon" className="text-rose-600" onClick={() => onChange(lines.filter((x) => x.key !== l.key))} aria-label="Remove line">
                <X className="h-4 w-4" />
              </Button>
            </div>
            <div className="mt-2 flex flex-wrap justify-between gap-2 text-xs">
              <span className={short ? "text-rose-700" : "text-slate-500"}>
                {extraLineEggs(l).toLocaleString()} eggs · {left.toLocaleString()} left in this class{short ? " — not enough" : ""}
              </span>
              <span className="font-semibold text-slate-800">Line total {extraLineTotal(l).toFixed(2)}</span>
            </div>
          </div>
        )
      })}
      <Button type="button" variant="outline" size="sm" onClick={add} className="bg-white">
        <Plus className="mr-1.5 h-4 w-4" /> Add another egg size to this sale
      </Button>
    </div>
  )
}

/** Any extra line asking for more than its class holds (after the lines above it). */
export function extraLinesShort(classes: EggClass[], lines: ExtraEggLine[], mainEggs: number, mainClass: number | null): boolean {
  return lines.some((l, idx) => {
    const cls = classFor(classes, l.eggProductId)
    const used = (mainClass === l.eggProductId ? mainEggs : 0)
      + lines.slice(0, idx).filter((x) => x.eggProductId === l.eggProductId).reduce((s, x) => s + extraLineEggs(x), 0)
    return extraLineEggs(l) > Math.max(0, (cls?.onHand ?? 0) - used)
  })
}

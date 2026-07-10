"use client"

import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Trash2 } from "lucide-react"
import { previewBatchConsumption, type BatchCostPreview } from "@/lib/utils/raw-material-costing"
import type { PoultryRawMaterialItem, PoultryRawMaterialPurchase } from "@/lib/api/poultry-inventory"
import type { ProductionMedicationLine } from "@/lib/api/production-record"

// Multiple medication lines on a production record (migration 147). Mirrors the
// water-sales "Add line" pattern: each line picks a medication from raw-material
// inventory and a quantity consumed; unit/total cost preview the server-side
// FIFO/LIFO/HIFO batch draw. The server recomputes the authoritative cost on save.

/** One editable medication line's raw form state. */
export interface MedLineDraft {
  specificMedicationUsedId: string
  totalMedicationConsumed: string
}

export const emptyMedLine = (): MedLineDraft => ({ specificMedicationUsedId: "", totalMedicationConsumed: "" })

export interface MedLineRow {
  item: PoultryRawMaterialItem | null
  qty: number
  preview: BatchCostPreview
}

export interface MedLinesComputed {
  rows: MedLineRow[]
  /** Sum of every line's previewed total cost. */
  totalCost: number
  /** Sum of every line's consumed quantity. */
  totalConsumed: number
  /** True if any line's requested quantity exceeds tracked batch stock. */
  hasShortfall: boolean
  /** The first line with a shortfall (for the blocking error message), if any. */
  firstShortfall: MedLineRow | null
  /** Payload lines (only rows with an item + quantity), ready for ProductionRecordInput.medications. */
  medications: ProductionMedicationLine[]
}

/** Pure helper: resolve each draft line to its item + batch-cost preview + payload. */
export function computeMedLines(
  lines: MedLineDraft[],
  medItems: PoultryRawMaterialItem[],
  purchases: PoultryRawMaterialPurchase[],
): MedLinesComputed {
  const rows: MedLineRow[] = lines.map((l) => {
    const item = medItems.find((i) => String(i.poultryRawMaterialItemId) === l.specificMedicationUsedId) ?? null
    const qty = parseFloat(l.totalMedicationConsumed) || 0
    return { item, qty, preview: previewBatchConsumption(item, purchases, qty) }
  })
  const totalCost = rows.reduce((a, r) => a + (r.preview.totalCost ?? 0), 0)
  const totalConsumed = rows.reduce((a, r) => a + r.qty, 0)
  const firstShortfall = rows.find((r) => r.item && r.preview.shortfall > 0) ?? null
  const medications: ProductionMedicationLine[] = rows
    .filter((r) => r.item && r.qty > 0)
    .map((r) => ({
      specificMedicationUsedId: r.item!.poultryRawMaterialItemId,
      specificMedicationUsedName: r.item!.itemName,
      totalMedicationConsumed: r.qty,
      medicationUnitCost: r.preview.unitCost,
      totalMedicationCost: Number((r.preview.totalCost ?? 0).toFixed(2)),
    }))
  return { rows, totalCost, totalConsumed, hasShortfall: firstShortfall !== null, firstShortfall, medications }
}

interface MedicationLinesProps {
  lines: MedLineDraft[]
  rows: MedLineRow[]
  medItems: PoultryRawMaterialItem[]
  onAdd: () => void
  onRemove: (index: number) => void
  onChange: (index: number, patch: Partial<MedLineDraft>) => void
  disabled?: boolean
}

/** Repeatable medication-line editor. Costs are read-only server-mirrored previews. */
export function MedicationLines({ lines, rows, medItems, onAdd, onRemove, onChange, disabled }: MedicationLinesProps) {
  return (
    <div className="col-span-12 space-y-3">
      {lines.length === 0 && (
        <div className="text-xs text-slate-400">
          No medication lines. Click <span className="font-medium">Add line</span> to draw a medication from inventory.
        </div>
      )}

      {lines.map((line, idx) => {
        const row = rows[idx]
        const preview = row?.preview
        const selectedMed = row?.item ?? null
        return (
          <div key={idx} className="grid grid-cols-12 gap-3 items-start rounded-lg border border-slate-200 bg-white px-3 py-3">
            <div className="col-span-12 md:col-span-4 space-y-1">
              {idx === 0 && <Label className="text-xs">Specific Medication Used</Label>}
              <Select
                value={line.specificMedicationUsedId || "none"}
                onValueChange={(v) => onChange(idx, { specificMedicationUsedId: v === "none" ? "" : v })}
                disabled={disabled}
              >
                <SelectTrigger><SelectValue placeholder="Select medication from inventory" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">None</SelectItem>
                  {medItems.map((i) => (
                    <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>
                      {i.itemName}{i.unitOfMeasure ? ` (${i.unitOfMeasure})` : ""} · {i.currentQuantity} in stock · {i.usageMethod}
                    </SelectItem>
                  ))}
                  {medItems.length === 0 && <div className="px-2 py-1.5 text-xs text-slate-400">No medication items in Raw Materials yet.</div>}
                </SelectContent>
              </Select>
            </div>

            <div className="col-span-6 md:col-span-2 space-y-1">
              {idx === 0 && <Label className="text-xs">Consumed</Label>}
              <Input
                type="number"
                step="0.001"
                min="0"
                value={line.totalMedicationConsumed}
                onChange={(e) => onChange(idx, { totalMedicationConsumed: e.target.value })}
                disabled={disabled}
              />
            </div>

            <div className="col-span-6 md:col-span-2 space-y-1">
              {idx === 0 && (
                <Label className="text-xs">
                  Unit Cost <span className="text-slate-400 font-normal">({selectedMed?.usageMethod ?? "FIFO"})</span>
                </Label>
              )}
              <div className="h-10 flex items-center px-3 rounded-md border border-slate-200 bg-slate-100 text-slate-700">
                {preview && preview.unitCost !== null ? preview.unitCost.toFixed(4) : "—"}
              </div>
            </div>

            <div className="col-span-9 md:col-span-3 space-y-1">
              {idx === 0 && <Label className="text-xs">Total Cost</Label>}
              <div className="h-10 flex items-center px-3 rounded-md border border-slate-200 bg-white font-semibold text-slate-700">
                {preview && preview.totalCost !== null ? preview.totalCost.toFixed(2) : "0.00"}
              </div>
            </div>

            <div className="col-span-3 md:col-span-1 flex md:justify-end">
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className={idx === 0 ? "mt-5 text-red-600 hover:text-red-700 hover:bg-red-50" : "text-red-600 hover:text-red-700 hover:bg-red-50"}
                onClick={() => onRemove(idx)}
                disabled={disabled}
                aria-label="Remove medication line"
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>

            {selectedMed && preview && preview.shortfall > 0 && (
              <div className="col-span-12 text-xs text-red-600">
                Not enough purchased stock tracked to cover {line.totalMedicationConsumed} — only {preview.quantityCovered} available across recorded purchases. Record a new purchase before saving.
              </div>
            )}
          </div>
        )
      })}

      <Button type="button" variant="outline" size="sm" onClick={onAdd} disabled={disabled}>
        <Plus className="h-3.5 w-3.5 mr-1" /> Add line
      </Button>
    </div>
  )
}

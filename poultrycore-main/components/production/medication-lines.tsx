"use client"

import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Trash2 } from "lucide-react"
import { previewLinesSequential, type BatchCostPreview, type ConsumptionCredit } from "@/lib/utils/raw-material-costing"
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
  /**
   * Projected on-hand per item AFTER this record saves: current stock + what this
   * record gives back (credit) − what the current lines consume. Drives the live
   * "in stock" badge in the picker.
   */
  pendingStockByItemId: Record<number, number>
}

/**
 * Build the "already consumed by this record" credit from a saved record's
 * medication lines, so editing doesn't falsely block on the record's own stock.
 * Pass the ProductionRecord.medications loaded from the API (undefined on a new record).
 */
export function buildMedCredit(
  medications?: { specificMedicationUsedId?: number | null; totalMedicationConsumed?: number | null; medicationUnitCost?: number | null }[] | null,
): ConsumptionCredit {
  const credit: ConsumptionCredit = {}
  for (const m of medications ?? []) {
    if (m.specificMedicationUsedId == null || !m.totalMedicationConsumed) continue
    const prev = credit[m.specificMedicationUsedId]
    credit[m.specificMedicationUsedId] = {
      qty: (prev?.qty ?? 0) + (m.totalMedicationConsumed ?? 0),
      unitCost: m.medicationUnitCost ?? prev?.unitCost ?? 0,
    }
  }
  return credit
}

/** Pure helper: resolve each draft line to its item + batch-cost preview + payload. */
export function computeMedLines(
  lines: MedLineDraft[],
  medItems: PoultryRawMaterialItem[],
  purchases: PoultryRawMaterialPurchase[],
  credit?: ConsumptionCredit,
): MedLinesComputed {
  const resolved = lines.map((l) => ({
    item: medItems.find((i) => String(i.poultryRawMaterialItemId) === l.specificMedicationUsedId) ?? null,
    qty: parseFloat(l.totalMedicationConsumed) || 0,
  }))
  // Sequential draw across lines so two lines of the SAME medication share one
  // running balance (a per-line check would let 50 + 10 through on a 50 stock).
  // `credit` adds back this record's own prior consumption when editing.
  const previews = previewLinesSequential(resolved, purchases, credit)
  const rows: MedLineRow[] = resolved.map((r, i) => ({ item: r.item, qty: r.qty, preview: previews[i] }))
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

  // Projected on-hand per item after save: current + credit (reversed) − consumed.
  const consumedByItem: Record<number, number> = {}
  for (const r of rows) {
    if (r.item && r.qty > 0) {
      const id = r.item.poultryRawMaterialItemId
      consumedByItem[id] = (consumedByItem[id] ?? 0) + r.qty
    }
  }
  const pendingStockByItemId: Record<number, number> = {}
  for (const it of medItems) {
    const id = it.poultryRawMaterialItemId
    pendingStockByItemId[id] = it.currentQuantity + (credit?.[id]?.qty ?? 0) - (consumedByItem[id] ?? 0)
  }

  return { rows, totalCost, totalConsumed, hasShortfall: firstShortfall !== null, firstShortfall, medications, pendingStockByItemId }
}

interface MedicationLinesProps {
  lines: MedLineDraft[]
  rows: MedLineRow[]
  medItems: PoultryRawMaterialItem[]
  /** Projected on-hand per item (computeMedLines().pendingStockByItemId) for the live badge. */
  stockByItemId?: Record<number, number>
  onAdd: () => void
  onRemove: (index: number) => void
  onChange: (index: number, patch: Partial<MedLineDraft>) => void
  disabled?: boolean
}

// Trim float noise (e.g. 129.99999999) without forcing trailing zeros.
const fmtStock = (n: number) => (Math.round(n * 1000) / 1000).toLocaleString()

/** Repeatable medication-line editor. Costs are read-only server-mirrored previews. */
export function MedicationLines({ lines, rows, medItems, stockByItemId, onAdd, onRemove, onChange, disabled }: MedicationLinesProps) {
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
        // Hide inactive items, but keep the one this line already uses so an edit
        // doesn't silently drop a now-inactive selection.
        const visibleItems = medItems.filter(
          (i) => i.isActive || String(i.poultryRawMaterialItemId) === line.specificMedicationUsedId,
        )
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
                  {visibleItems.map((i) => {
                    const stock = stockByItemId?.[i.poultryRawMaterialItemId] ?? i.currentQuantity
                    return (
                      <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>
                        {i.itemName}{i.unitOfMeasure ? ` (${i.unitOfMeasure})` : ""} · {fmtStock(stock)} in stock · {i.usageMethod}{i.isActive ? "" : " · (inactive)"}
                      </SelectItem>
                    )
                  })}
                  {visibleItems.length === 0 && <div className="px-2 py-1.5 text-xs text-slate-400">No active medication items in Raw Materials.</div>}
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

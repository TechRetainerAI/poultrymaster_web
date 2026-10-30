"use client"

// One line of the New sale "Items" table, laid out like the Water sale form:
// Product | Egg size | Quantity | Price | Line total | remove.
//
// Eggs are counted as crates + loose eggs and priced per crate; every other
// product is a plain quantity at a unit price. The parent owns the numbers --
// this only draws them -- so the first line can stay bound to the page's form
// state while added lines live in a list.

import type { ReactNode } from "react"
import { X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import type { EggClass } from "@/lib/api/egg-sorting"
import { EGGS_PER_CRATE } from "@/lib/production/production-record-calc"
import { UNSORTED_VALUE, classIdFrom, classValue } from "@/components/sales/egg-class-fields"
import { byproductRole } from "@/lib/poultry/byproducts"

/** Every product the list can show. Broken Eggs / Dead Birds only when the company offers them (374). */
export const SALE_PRODUCT_OPTIONS = ["Fresh Eggs", "Chicken", "Broken Eggs", "Dead Birds", "Manure", "Other"]

/** The list for this company: Broken Eggs on by default, Dead Birds off until turned on. */
export function saleProductOptions(settings: { brokenEggsInSales?: boolean; deadBirdsInSales?: boolean } | null | undefined): string[] {
  return SALE_PRODUCT_OPTIONS.filter((o) =>
    o === "Broken Eggs" ? settings?.brokenEggsInSales !== false
    : o === "Dead Birds" ? settings?.deadBirdsInSales === true
    : true)
}

/** Eggs sold by size and crate. Broken Eggs are NOT: they are their own stock, sold by the egg. */
export const isEggProduct = (product: string | null | undefined) =>
  (product ?? "").toLowerCase().includes("egg") && byproductRole(product) == null

/** Header and row share one grid so the columns line up. */
export const SALE_ITEM_GRID =
  "md:grid-cols-[minmax(0,5fr)_minmax(0,5fr)_minmax(0,5fr)_minmax(0,3fr)_minmax(0,3fr)_32px]"

export function SaleItemsHeader() {
  return (
    <div className={`hidden md:grid ${SALE_ITEM_GRID} gap-2 pl-[18px] pr-3 text-[11px] font-semibold uppercase tracking-wide text-amber-800`}>
      <div>Product</div>
      <div>Egg size</div>
      <div>Quantity</div>
      <div className="text-right">Unit price</div>
      <div className="text-right">Line total</div>
      <div />
    </div>
  )
}

export function SaleItemRow({
  index,
  product, onProductChange,
  classes, eggProductId, onClassChange,
  size, onSizeChange,
  crates, loose, onCratesChange, onLooseChange,
  quantity, onQuantityChange,
  unitPrice, onUnitPriceChange,
  lineTotal, onRemove, note, options = SALE_PRODUCT_OPTIONS,
}: {
  /** 1-based line number, shown on the card. */
  index?: number
  product: string
  onProductChange: (product: string) => void
  classes: EggClass[]
  eggProductId: number | null
  onClassChange: (eggProductId: number | null) => void
  /** Free-text size for farms without egg sizes; omit to show "Unsorted". */
  size?: string
  onSizeChange?: (size: string) => void
  crates: number
  loose: number
  onCratesChange: (n: number) => void
  onLooseChange: (n: number) => void
  quantity: number
  onQuantityChange: (n: number) => void
  unitPrice: number
  onUnitPriceChange: (n: number) => void
  lineTotal: number
  /** Absent: the line cannot be removed (the only line). */
  onRemove?: () => void
  /** Stock and the like, under the row. */
  note?: ReactNode
  /** The products offered (saleProductOptions). */
  options?: string[]
}) {
  const egg = isEggProduct(product)
  const hasSizes = classes.some((c) => c.classKind === "Size")
  const selectValue = options.includes(product) ? product : "Other"
  const shownClasses = classes.filter((c) => c.classKind === "Unsorted" || c.isActive || c.poultryProductId === eggProductId)

  return (
    // A card per line: amber edge for eggs, sky for anything else, so a mixed
    // sale reads at a glance.
    <div className={`relative space-y-1 rounded-lg border border-l-4 bg-white p-3 shadow-sm ${egg ? "border-amber-200 border-l-amber-500" : "border-sky-200 border-l-sky-500"}`}>
      {index != null && (
        <span className={`absolute -left-2.5 -top-2.5 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold text-white shadow ${egg ? "bg-amber-500" : "bg-sky-500"}`}>
          {index}
        </span>
      )}
      <div className={`grid grid-cols-12 ${SALE_ITEM_GRID} items-start gap-2`}>
        {/* Product */}
        <div className="col-span-12 min-w-0 space-y-1 md:col-auto">
          <Label className="text-xs text-slate-500 md:hidden">Product</Label>
          <Select value={selectValue} onValueChange={(v) => onProductChange(v === "Other" ? "" : v)}>
            <SelectTrigger className="min-w-0"><SelectValue /></SelectTrigger>
            <SelectContent>
              {options.map((o) => <SelectItem key={o} value={o}>{o}</SelectItem>)}
            </SelectContent>
          </Select>
          {selectValue === "Other" && (
            <Input value={product} onChange={(e) => onProductChange(e.target.value)} placeholder="Product name" />
          )}
        </div>

        {/* Egg size */}
        <div className="col-span-12 min-w-0 md:col-auto">
          <Label className="text-xs text-slate-500 md:hidden">Egg size</Label>
          {!egg ? (
            <div className="flex h-10 items-center px-1 text-sm text-slate-400">—</div>
          ) : hasSizes ? (
            <Select value={classValue(eggProductId)} onValueChange={(v) => onClassChange(classIdFrom(v))}>
              <SelectTrigger className="min-w-0"><SelectValue /></SelectTrigger>
              <SelectContent>
                {shownClasses.map((c) => (
                  <SelectItem key={c.poultryProductId} value={c.classKind === "Unsorted" ? UNSORTED_VALUE : String(c.poultryProductId)}>
                    <span className="flex flex-col leading-tight">
                      <span className="truncate">{c.classKind === "Unsorted" ? "Unsorted / General" : c.name}</span>
                      <span className="text-[11px] text-slate-400">stock {Math.max(0, Math.trunc(c.onHand)).toLocaleString()}</span>
                    </span>
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          ) : onSizeChange ? (
            <Input list="egg-size-suggestions" value={size ?? ""} onChange={(e) => onSizeChange(e.target.value)} placeholder="Optional, e.g. Large" />
          ) : (
            <div className="flex h-10 items-center px-1 text-sm text-slate-500">Unsorted</div>
          )}
        </div>

        {/* Quantity */}
        <div className="col-span-12 min-w-0 sm:col-span-6 md:col-auto">
          <Label className="text-xs text-slate-500 md:hidden">Quantity</Label>
          {egg ? (
            <div className="grid grid-cols-2 gap-1.5">
              <div>
                <NumberInput className="text-right tabular-nums" min="0" value={crates}
                  onChange={(e) => onCratesChange(parseInt(e.target.value) || 0)} aria-label="Crates" />
                <span className="text-[11px] text-slate-500">crates ({EGGS_PER_CRATE})</span>
              </div>
              <div>
                <NumberInput className="text-right tabular-nums" min="0" max={String(EGGS_PER_CRATE - 1)} value={loose}
                  onChange={(e) => onLooseChange(parseInt(e.target.value) || 0)} aria-label="Loose eggs" />
                <span className="text-[11px] text-slate-500">loose eggs</span>
              </div>
            </div>
          ) : (
            <NumberInput className="text-right tabular-nums" min="0" value={quantity}
              onChange={(e) => onQuantityChange(Number(e.target.value) || 0)} aria-label="Quantity" />
          )}
        </div>

        {/* Unit price */}
        <div className="col-span-6 min-w-0 sm:col-span-3 md:col-auto">
          <Label className="text-xs text-slate-500 md:hidden">Unit price</Label>
          <NumberInput className="text-right tabular-nums" min="0" step="0.01" value={unitPrice}
            onChange={(e) => onUnitPriceChange(Number(e.target.value) || 0)} placeholder="0.00" aria-label="Unit price" />
          {egg && <span className="block text-right text-[11px] text-slate-500">per crate</span>}
        </div>

        {/* Line total */}
        <div className="col-span-4 min-w-0 self-center text-right font-semibold tabular-nums text-emerald-700 sm:col-span-2 md:col-auto md:pt-2.5 md:self-start">
          <Label className="block text-xs font-normal text-slate-500 md:hidden">Line total</Label>
          {lineTotal.toFixed(2)}
        </div>

        {/* Remove */}
        <div className="col-span-2 text-right sm:col-span-1 md:col-auto">
          {onRemove && (
            <Button type="button" size="icon" variant="ghost" onClick={onRemove} title="Remove line" aria-label="Remove line">
              <X className="h-4 w-4 text-red-500" />
            </Button>
          )}
        </div>
      </div>
      {(egg || note) && (
        <div className="space-y-1 px-1 text-xs text-slate-500">
          {egg && crates + loose > 0 && (
            <p>
              {crates} crate{crates === 1 ? "" : "s"}{loose > 0 ? ` + ${loose} loose` : ""} = {(crates * EGGS_PER_CRATE + loose).toLocaleString()} eggs
              {loose > 0 ? " — loose eggs charged pro rata" : ""}
            </p>
          )}
          {note}
        </div>
      )}
    </div>
  )
}

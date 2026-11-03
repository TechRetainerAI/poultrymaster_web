"use client"

// One line of the New sale "Items" table:
// Product | Egg size | Boxes | Crates | Pieces | Unit price | Price unit | Line total | remove.
//
// Eggs are counted as crates + loose eggs and priced per crate; every other
// product is a plain quantity at a unit price. A farm with Boxes on (393/394)
// also gets a Boxes column, and the price can be typed per box, per crate or
// per egg (the Price unit); the other two follow from it. Stock is still taken
// in eggs. The parent owns the numbers -- this only draws them -- so the first
// line can stay bound to the page's form state while added lines live in a list.

import { useState, type ReactNode } from "react"
import { Package, Scale, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import type { EggClass } from "@/lib/api/egg-sorting"
import { EGGS_PER_CRATE } from "@/lib/production/production-record-calc"
import { UNSORTED_VALUE, classIdFrom, classValue } from "@/components/sales/egg-class-fields"
import { byproductRole } from "@/lib/poultry/byproducts"
import {
  boxSize, effectiveBoxPrice, effectivePiecePrice, toEggPieces, type EggPackaging,
} from "@/lib/poultry/egg-packaging"
import {
  EMPTY_BIRD_PRICING, avgKgPerBird, isLiveBirdProduct, perBirdPrice, type BirdPricing, type BirdPricingBasis,
} from "@/lib/poultry/bird-pricing"

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

/**
 * Header and row share one grid so the columns line up. The quantity columns
 * have a floor wide enough for five-digit counts.
 */
const GRID_BOXES =
  "md:grid-cols-[minmax(0,4fr)_minmax(0,4fr)_minmax(4.75rem,2fr)_minmax(4.75rem,2fr)_minmax(4.75rem,2fr)_minmax(6rem,3fr)_minmax(6.5rem,3fr)_minmax(5.5rem,3fr)_32px]"
const GRID_CRATES =
  "md:grid-cols-[minmax(0,5fr)_minmax(0,5fr)_minmax(5rem,2fr)_minmax(5rem,2fr)_minmax(6rem,3fr)_minmax(6.5rem,3fr)_minmax(5.5rem,3fr)_32px]"

const farmHasBoxes = (packaging: EggPackaging | undefined) => !!packaging && boxSize(packaging) != null

// Big, centred, no spinner arrows: the arrows ate half of a narrow box.
const QTY_INPUT =
  "h-10 px-2 text-center text-base font-semibold tabular-nums [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"

const money = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100
const plural = (n: number, one: string, many: string) => (n === 1 ? one : many)

export function SaleItemsHeader({
  packaging, eggs = true, quantityLabel = "Quantity",
}: {
  packaging?: EggPackaging
  /**
   * False when no line on the sale is eggs: a chicken (or manure) sale has no
   * egg size, boxes, crates or pieces, so the header shows one quantity column
   * over them. A sale with any egg line keeps the egg columns.
   */
  eggs?: boolean
  /** The single column's name when eggs is false, e.g. "Birds". */
  quantityLabel?: string
}) {
  const boxes = farmHasBoxes(packaging)
  return (
    <div className={`hidden md:grid ${boxes ? GRID_BOXES : GRID_CRATES} gap-2 pl-[18px] pr-3 text-[11px] font-semibold uppercase tracking-wide text-amber-800`}>
      <div>Product</div>
      {eggs ? (
        <>
          <div>Egg size</div>
          {boxes && <div className="text-center">Boxes</div>}
          <div className="text-center">Crates</div>
          <div className="text-center">Pieces</div>
        </>
      ) : (
        <>
          <div />
          {/* Same span as a non-egg row's quantity box (see the row below). */}
          <div className={`${boxes ? "col-span-3" : "col-span-2"} text-center`}>{quantityLabel}</div>
        </>
      )}
      <div className="text-right">Unit price</div>
      <div>Price unit</div>
      <div className="text-right">Line total</div>
      <div />
    </div>
  )
}

type PriceUnit = "Box" | "Crate" | "Egg"

export function SaleItemRow({
  index,
  product, onProductChange,
  classes, eggProductId, onClassChange,
  size, onSizeChange,
  crates, loose, onCratesChange, onLooseChange,
  quantity, onQuantityChange,
  unitPrice, onUnitPriceChange,
  lineTotal, onRemove, note, options = SALE_PRODUCT_OPTIONS,
  packaging, boxes = 0, onBoxesChange, pricePerBox = null, onPricePerBoxChange, pricePerPiece = null, onPricePerPieceChange,
  birdPricing, onBirdPricingChange,
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
  /** 393: the farm's packaging. With boxes on, the line takes Boxes too. */
  packaging?: EggPackaging
  boxes?: number
  onBoxesChange?: (n: number) => void
  /** 394: null = crates per box x the crate price. */
  pricePerBox?: number | null
  onPricePerBoxChange?: (n: number | null) => void
  /** 394: null = the crate price shared over the crate. */
  pricePerPiece?: number | null
  onPricePerPieceChange?: (n: number | null) => void
  /**
   * 401: a live-bird line priced per bird or per kg, with its live weight.
   * Omit the handler and a bird line stays the plain quantity x price row.
   */
  birdPricing?: BirdPricing
  onBirdPricingChange?: (p: BirdPricing) => void
}) {
  const egg = isEggProduct(product)
  // 401: live birds -- quantity is the bird count; the price is per bird or per kg.
  const bird = !egg && !!onBirdPricingChange && isLiveBirdProduct(product)
  const bp = birdPricing ?? EMPTY_BIRD_PRICING
  const perKg = bird && bp.basis === "PerKg"
  const setBird = (patch: Partial<BirdPricing>) => onBirdPricingChange?.({ ...bp, ...patch })
  const hasSizes = classes.some((c) => c.classKind === "Size")
  const selectValue = options.includes(product) ? product : "Other"
  const shownClasses = classes.filter((c) => c.classKind === "Unsorted" || c.isActive || c.poultryProductId === eggProductId)
  const farmBoxes = farmHasBoxes(packaging) && !!onBoxesChange
  const boxesOn = egg && farmBoxes
  const perCrate = packaging?.eggsPerCrate ?? EGGS_PER_CRATE
  const cratesPerBox = boxesOn ? boxSize(packaging!)! : 0

  // Which price the Unit price box edits. Display only: the line always keeps
  // a crate price, plus a box / egg price when one was typed or set per size.
  const [priceUnit, setPriceUnit] = useState<PriceUnit>("Crate")
  const unit: PriceUnit = !boxesOn && priceUnit === "Box" ? "Crate" : priceUnit
  const prices = { pricePerCrate: unitPrice, pricePerBox, pricePerPiece }
  const boxPrice = boxesOn ? effectiveBoxPrice(prices, packaging!) : 0
  const eggPrice = packaging ? effectivePiecePrice(prices, packaging) : unitPrice / Math.max(1, perCrate)
  const shownPrice = perKg ? bp.pricePerKg ?? 0
    : !egg ? unitPrice : unit === "Box" ? boxPrice : unit === "Egg" ? round2(eggPrice) : unitPrice

  // The typed price sets the other two, so a box, a crate and an egg are
  // always priced from the same figure (crate price kept to the cent, as saved).
  const setPrice = (v: number) => {
    if (perKg) { setBird({ pricePerKg: v }); return }
    if (!egg || unit === "Crate") {
      onUnitPriceChange(v)
      if (egg) { onPricePerBoxChange?.(null); onPricePerPieceChange?.(null) }
    } else if (unit === "Box") {
      onPricePerBoxChange?.(v)
      onUnitPriceChange(round2(v / Math.max(1, cratesPerBox)))
      onPricePerPieceChange?.(null)
    } else {
      onPricePerPieceChange?.(v)
      onUnitPriceChange(round2(v * perCrate))
      onPricePerBoxChange?.(null)
    }
  }

  const qtyField = (key: string, label: string, value: number, onChange: (n: number) => void, max?: number) => (
    <div key={key} className={`min-w-0 ${boxesOn ? "col-span-4" : "col-span-6"} md:col-auto`}>
      <Label className="text-xs text-slate-500 md:hidden">{label}</Label>
      <NumberInput className={QTY_INPUT} min="0" max={max != null ? String(max) : undefined} value={value}
        onChange={(e) => onChange(Math.max(0, parseInt(e.target.value) || 0))} aria-label={label} placeholder="0" />
    </div>
  )
  const eggs = boxesOn ? toEggPieces({ boxes, crates, pieces: loose }, packaging!) : crates * perCrate + loose

  const amountParts = [
    boxesOn && boxes ? `${boxes.toLocaleString()} ${plural(boxes, "Box", "Boxes")}` : "",
    crates ? `${crates.toLocaleString()} ${plural(crates, "Crate", "Crates")}` : "",
    loose ? `${loose.toLocaleString()} ${plural(loose, "Egg", "Eggs")}` : "",
  ].filter(Boolean)

  return (
    // A card per line: amber edge for eggs, sky for anything else, so a mixed
    // sale reads at a glance.
    <div className={`relative space-y-2 rounded-lg border border-l-4 bg-white p-3 shadow-sm ${egg ? "border-amber-200 border-l-amber-500" : "border-sky-200 border-l-sky-500"}`}>
      {index != null && (
        <span className={`absolute -left-2.5 -top-2.5 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold text-white shadow ${egg ? "bg-amber-500" : "bg-sky-500"}`}>
          {index}
        </span>
      )}
      <div className={`grid grid-cols-12 ${farmBoxes ? GRID_BOXES : GRID_CRATES} items-start gap-2`}>
        {/* Product */}
        <div className="col-span-12 min-w-0 space-y-1 sm:col-span-6 md:col-auto">
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
        <div className="col-span-12 min-w-0 sm:col-span-6 md:col-auto">
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

        {/* Boxes | Crates | Pieces -- or one Quantity across them for anything but eggs */}
        {egg ? (
          <>
            {boxesOn && qtyField("boxes", "Boxes", boxes, onBoxesChange!)}
            {qtyField("crates", "Crates", crates, onCratesChange)}
            {qtyField("pieces", "Pieces", loose, onLooseChange, perCrate - 1)}
          </>
        ) : (
          <div className={`col-span-12 min-w-0 ${farmBoxes ? "md:col-span-3" : "md:col-span-2"}`}>
            <Label className="text-xs text-slate-500 md:hidden">{isLiveBirdProduct(product) ? "Birds" : "Quantity"}</Label>
            <NumberInput className={QTY_INPUT} min="0" value={quantity}
              onChange={(e) => onQuantityChange(Number(e.target.value) || 0)}
              aria-label={isLiveBirdProduct(product) ? "Number of birds" : "Quantity"} placeholder="0" />
            {/* Desktop: the header may be the egg columns (a mixed sale), so the
                box says what it counts. */}
            <div className="mt-0.5 hidden text-center text-[10px] text-slate-500 md:block">
              {isLiveBirdProduct(product) ? "birds" : "units"}
            </div>
          </div>
        )}

        {/* Unit price */}
        <div className="col-span-6 min-w-0 md:col-auto">
          <Label className="text-xs text-slate-500 md:hidden">Unit price</Label>
          <NumberInput key={unit} className="h-10 text-right tabular-nums" min="0" step="0.01" value={shownPrice}
            onChange={(e) => setPrice(Math.max(0, Number(e.target.value) || 0))} placeholder="0.00" aria-label="Unit price" />
        </div>

        {/* Price unit */}
        <div className="col-span-6 min-w-0 md:col-auto">
          <Label className="text-xs text-slate-500 md:hidden">Price unit</Label>
          {bird ? (
            <Select value={bp.basis} onValueChange={(v) => setBird({ basis: v as BirdPricingBasis })}>
              <SelectTrigger className="min-w-0" aria-label="Price unit"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="PerBird">Per bird</SelectItem>
                <SelectItem value="PerKg">Per kg</SelectItem>
              </SelectContent>
            </Select>
          ) : egg ? (
            <Select value={unit} onValueChange={(v) => setPriceUnit(v as PriceUnit)}>
              <SelectTrigger className="min-w-0" aria-label="Price unit"><SelectValue /></SelectTrigger>
              <SelectContent>
                {boxesOn && <SelectItem value="Box">Per Box</SelectItem>}
                <SelectItem value="Crate">Per Crate</SelectItem>
                <SelectItem value="Egg">Per Egg</SelectItem>
              </SelectContent>
            </Select>
          ) : (
            <div className="flex h-10 items-center px-1 text-sm text-slate-500">Per unit</div>
          )}
        </div>

        {/* Line total */}
        <div className="col-span-10 min-w-0 self-center text-right text-base font-bold tabular-nums text-emerald-700 md:col-auto">
          <Label className="block text-xs font-normal text-slate-500 md:hidden">Line total</Label>
          {money(lineTotal)}
        </div>

        {/* Remove */}
        <div className="col-span-2 self-center text-right md:col-auto">
          {onRemove && (
            <Button type="button" size="icon" variant="ghost" onClick={onRemove} title="Remove line" aria-label="Remove line">
              <X className="h-4 w-4 text-red-500" />
            </Button>
          )}
        </div>
      </div>

      {egg && eggs > 0 && (
        // What the quantity comes to, and the conversion and prices behind the total.
        <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-2 rounded-md border border-amber-100 bg-amber-50/70 px-3 py-2">
          <div className="flex items-center gap-2.5">
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-amber-100 text-amber-700">
              <Package className="h-4 w-4" />
            </span>
            <span className="text-sm font-semibold text-slate-800">
              {amountParts.join(" + ")} = {eggs.toLocaleString()} {plural(eggs, "Egg", "Eggs")}
            </span>
          </div>
          <div className="text-xs leading-relaxed text-slate-500">
            {boxesOn ? (
              <>
                <div>Box conversion: 1 Box = {cratesPerBox} Crates = {(cratesPerBox * perCrate).toLocaleString()} Eggs</div>
                <div>Box {money(boxPrice)} · Crate {money(unitPrice)} · Egg {money(eggPrice)}</div>
              </>
            ) : (
              <>
                <div>1 Crate = {perCrate} Eggs</div>
                {loose > 0 && <div>Pieces charged pro rata from the crate price</div>}
              </>
            )}
          </div>
        </div>
      )}
      {bird && (
        // 401: the live weight. Required per kg; per bird it is optional and
        // feeds the flock's kg-sold and feed-conversion figures.
        <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-2 rounded-md border border-sky-100 bg-sky-50/70 px-3 py-2">
          <div className="flex items-end gap-2.5">
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-sky-100 text-sky-700">
              <Scale className="h-4 w-4" />
            </span>
            <div className="w-36 space-y-1">
              <Label className="text-xs text-slate-600">Live weight (kg){perKg ? " *" : ""}</Label>
              <NumberInput className="h-9 text-right tabular-nums" min="0" step="0.1"
                value={bp.liveWeightKg ?? ""} placeholder={perKg ? "0.0" : "Optional"}
                onChange={(e) => setBird({ liveWeightKg: e.target.value === "" ? null : Math.max(0, Number(e.target.value) || 0) })}
                aria-label="Total live weight in kg" />
            </div>
          </div>
          <div className="text-xs leading-relaxed text-slate-600">
            {(() => {
              const avg = avgKgPerBird(quantity, bp.liveWeightKg)
              return (
                <>
                  {avg != null && <div>Average {avg.toFixed(2)} kg a bird</div>}
                  {perKg
                    ? <div>{(bp.liveWeightKg ?? 0).toLocaleString()} kg × {money(bp.pricePerKg ?? 0)} = <b>{money(lineTotal)}</b>{quantity > 0 ? ` · ${money(perBirdPrice(lineTotal, quantity))} a bird` : ""}</div>
                    : <div>{bp.liveWeightKg ? "Weight kept for the flock's kg sold and feed conversion." : "Add the weight to track kg sold and feed conversion."}</div>}
                </>
              )
            })()}
          </div>
        </div>
      )}
      {note && <div className="rounded-md bg-slate-50 px-3 py-1.5 text-xs text-slate-600">{note}</div>}
    </div>
  )
}

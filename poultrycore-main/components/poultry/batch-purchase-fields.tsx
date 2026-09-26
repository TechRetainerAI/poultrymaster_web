"use client"

// The bird-purchase form, written once.
//
// Both Flock Purchases and Initial Farm Setup render THESE, so the two cannot
// drift: a field added here appears on both, and a label changed here changes on
// both. What they mean lives in lib/poultry/batch-purchase.ts.
//
// The fieldsets own their inputs but NOT their surroundings: each screen passes
// its own grid class and keeps its own section chrome, because a dialog and a
// card in a list genuinely want different layouts. Sharing the chrome as well
// would have meant one of them looking wrong.

import type React from "react"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { BreedSelect } from "@/components/poultry/breed-select"
import {
  SUPPLIER_TYPES, batchBalance, patchForCostChange,
  type BatchPurchaseDraft, type BatchPurchasePatch,
} from "@/lib/poultry/batch-purchase"

export interface BatchFieldsProps {
  value: BatchPurchaseDraft
  onPatch: (patch: BatchPurchasePatch) => void
  disabled?: boolean
  /** Breeds already used on this farm — offered first in the breed picker. */
  knownBreeds?: readonly string[]
  /** The grid the fields lay out in. Each screen chooses its own. */
  className?: string
  /** Per-field message, keyed by field name, shown under the input. */
  errors?: Partial<Record<keyof BatchPurchaseDraft, string | undefined>>
}

/** One labelled control. Local so both screens get identical spacing. */
function Cell({ label, error, hint, children, className }: {
  label: string; error?: string; hint?: string
  children: React.ReactNode; className?: string
}) {
  return (
    <div className={`space-y-2 ${className ?? ""}`}>
      <Label className="text-sm font-medium text-slate-700">{label}</Label>
      {children}
      {hint && !error && <p className="text-xs text-slate-500">{hint}</p>}
      {error && <p className="text-xs text-red-600">{error}</p>}
    </div>
  )
}

const GRID = "grid grid-cols-1 md:grid-cols-2 gap-4"

/** Name, code, breed, birds, date — what a batch IS, before any money. */
export function BatchIdentityFields({
  value, onPatch, disabled, className, errors, knownBreeds = [],
}: BatchFieldsProps) {
  return (
    <div className={className ?? GRID}>
      <Cell label="Batch Name *" error={errors?.batchName}>
        <Input placeholder="e.g., Batch A - Rhode Island Reds" value={value.batchName}
          onChange={(e) => onPatch({ batchName: e.target.value })} required disabled={disabled} />
      </Cell>
      <Cell label="Batch Code *" error={errors?.batchCode}>
        <Input placeholder="e.g., B-001" value={value.batchCode}
          onChange={(e) => onPatch({ batchCode: e.target.value })} required disabled={disabled} />
      </Cell>
      <Cell label="Breed" error={errors?.breed}>
        <BreedSelect value={value.breed} onChange={(breed) => onPatch({ breed })}
          known={knownBreeds} disabled={disabled} />
      </Cell>
      <Cell label="Start Date *" error={errors?.startDate}>
        <Input type="date" value={value.startDate}
          onChange={(e) => onPatch({ startDate: e.target.value })} required disabled={disabled} />
      </Cell>
      <Cell label="Number of Birds *" error={errors?.numberOfBirds}>
        {/* Changing the bird count recomputes the total, the same way changing
            the cost per chick does — patchForCostChange owns that rule. */}
        <NumberInput min="1" placeholder="e.g., 100" value={value.numberOfBirds}
          onChange={(e) => onPatch(patchForCostChange(value, { numberOfBirds: e.target.value }))}
          required disabled={disabled} />
      </Cell>
    </div>
  )
}

export interface BatchPurchaseDetailProps extends BatchFieldsProps {
  suppliers: { supplierId: number; name: string }[]
  currencySymbol?: string
  /** Rendered under Amount Paid — e.g. that a historical purchase posts nothing. */
  amountPaidHint?: string
  /**
   * False where the screen shows the balance somewhere better. Flock Purchases
   * has a Total / Paid / Balance strip with a status badge; repeating it in the
   * grid would be saying the same number twice.
   */
  showBalance?: boolean
}

/** Cost, payment and who it was bought from. */
export function BatchPurchaseDetailFields({
  value, onPatch, disabled, className, errors, suppliers, currencySymbol = "",
  amountPaidHint, showBalance = true,
}: BatchPurchaseDetailProps) {
  const balance = batchBalance(value.totalCost, value.amountPaid)
  return (
    <div className={className ?? GRID}>
      <Cell label="Cost Per Chick" error={errors?.costPerChick}>
        <NumberInput min="0" step="0.01" value={value.costPerChick}
          onChange={(e) => onPatch(patchForCostChange(value, { costPerChick: e.target.value }))}
          disabled={disabled} />
      </Cell>
      <Cell label="Total Cost" error={errors?.totalCost}>
        <NumberInput min="0" step="0.01" placeholder="Auto-calculated" value={value.totalCost}
          onChange={(e) => onPatch({ totalCost: e.target.value })} disabled={disabled} />
      </Cell>
      <Cell label={`Amount Paid Now ${currencySymbol ? `(${currencySymbol})` : ""}`.trim()}
        hint={amountPaidHint ?? "Part payment is fine — pay the balance later by editing the batch."}
        error={errors?.amountPaid}>
        <NumberInput min="0" step="0.01" value={value.amountPaid}
          onChange={(e) => onPatch({ amountPaid: e.target.value })} disabled={disabled} />
      </Cell>
      {showBalance && (
        <Cell label="Balance">
          <div className="flex h-9 items-center rounded-md border border-slate-200 bg-slate-50 px-3 text-sm tabular-nums text-slate-700">
            {balance.toLocaleString()}
          </div>
        </Cell>
      )}
      <Cell label="Type">
        <Select value={value.supplierType || "local"} onValueChange={(v) => onPatch({ supplierType: v })} disabled={disabled}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            {SUPPLIER_TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
          </SelectContent>
        </Select>
      </Cell>
      <Cell label="Supplier">
        <Select value={value.supplierId || "none"}
          onValueChange={(v) => onPatch({ supplierId: v === "none" ? "" : v })} disabled={disabled}>
          <SelectTrigger>
            <SelectValue placeholder={suppliers.length === 0 ? "No suppliers found" : "No supplier"} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="none">No supplier</SelectItem>
            {suppliers.map((s) => (
              <SelectItem key={s.supplierId} value={String(s.supplierId)}>{s.name}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Cell>
      {/* Only means anything for a foreign purchase, so it stays out of the way
          for the common case -- but never hides a rate that is already set, or
          editing a batch could make its own data unreachable. */}
      {(value.supplierType === "foreign" || value.dollarConversionRate.trim() !== "") && (
        <Cell label="Dollar Conversion Rate" error={errors?.dollarConversionRate}>
          <NumberInput min="0" step="0.0001" value={value.dollarConversionRate}
            onChange={(e) => onPatch({ dollarConversionRate: e.target.value })} disabled={disabled} />
        </Cell>
      )}
    </div>
  )
}

/** When it was ordered, when it is due, and anything worth remembering. */
export function BatchOrderFields({ value, onPatch, disabled, className, errors }: BatchFieldsProps) {
  return (
    <div className={className ?? GRID}>
      <Cell label="Order Placement Date" hint="When you placed the order with the supplier."
        error={errors?.orderPlacementDate}>
        <Input type="date" value={value.orderPlacementDate}
          onChange={(e) => onPatch({ orderPlacementDate: e.target.value })} disabled={disabled} />
      </Cell>
      <Cell label="Estimated Arrival Date" hint="When the birds are expected to arrive."
        error={errors?.estimatedArrivalDate}>
        <Input type="date" value={value.estimatedArrivalDate}
          onChange={(e) => onPatch({ estimatedArrivalDate: e.target.value })} disabled={disabled} />
      </Cell>
    </div>
  )
}

/**
 * Notes, on its own, because the two screens file it differently: Flock
 * Purchases keeps it with the status toggles, the wizard keeps it with the
 * order details. Shared as a field rather than forced into one section.
 */
export function BatchNotesField({ value, onPatch, disabled, className }: BatchFieldsProps) {
  return (
    <Cell label="Notes (Optional)" className={className}>
      <textarea
        className="w-full min-h-[72px] rounded-md border border-slate-200 bg-white px-3 py-2 text-sm"
        placeholder="Anything worth remembering about this batch"
        value={value.notes} onChange={(e) => onPatch({ notes: e.target.value })} disabled={disabled} />
    </Cell>
  )
}

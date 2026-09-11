"use client"

// =============================================================================
// PoultryReportFilter — shared filter bar for the Advanced Poultry Reports.
// Date presets + From/To + optional flock / customer / supplier filters and an
// "include closed flocks" toggle. Controlled via props.
// =============================================================================

import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from "@/components/ui/select"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod } from "@/lib/date-ranges"
import { cn } from "@/lib/utils"
import type { Flock } from "@/lib/api/flock"

export interface PoultryReportFilterValue {
  fromDate: string
  toDate: string
  flockId?: number | null
  customerName?: string | null
  supplierName?: string | null
  category?: string | null
  includeClosedFlocks?: boolean
}

export interface PoultryReportFilterProps {
  value: PoultryReportFilterValue
  onChange: (next: PoultryReportFilterValue) => void
  onReset: () => void
  show: { flock?: boolean; customer?: boolean; supplier?: boolean; category?: boolean; includeClosedFlocks?: boolean }
  flocks: Flock[]
  /** Category options for the category filter — gathered from the report's own rows. */
  categories?: string[]
  customers: string[]
}

const ALL = "__ALL__"

export function PoultryReportFilter({ value, onChange, onReset, show, flocks, customers, categories = [] }: PoultryReportFilterProps) {
  const set = (patch: Partial<PoultryReportFilterValue>) => onChange({ ...value, ...patch })

  return (
    // Labels sit ABOVE their control rather than beside it. Beside it, every
    // field started at a different x — "Period", "From" and "To" are different
    // widths — so the boxes came out ragged on a phone and cramped on a
    // desktop. Stacked, one field per row, they share a left edge and a width;
    // from sm: up the same fields lay out as an inline bar, and on a desktop
    // (lg:) that bar is a SINGLE row — nowrap, with the fields shrinking off
    // their preferred widths rather than dropping to a second line. Between the
    // two it still wraps: a 700px laptop window with five filters would squeeze
    // every box to nothing if it could not.
    <div className="print:hidden mb-4 grid grid-cols-1 items-end gap-2 sm:flex sm:flex-wrap sm:gap-3 lg:flex-nowrap">
      <FilterField label="Period" className="sm:w-44">
        <PeriodSelect
          label={null}
          className="w-full"
          value={rangeToPeriod(value.fromDate, value.toDate)}
          onChange={(_p, range) => { if (range) set({ fromDate: range.from, toDate: range.to }) }}
        />
      </FilterField>

      <FilterField label="From" className="sm:w-40">
        <Input type="date" value={value.fromDate} onChange={(e) => set({ fromDate: e.target.value })} className="w-full" />
      </FilterField>
      <FilterField label="To" className="sm:w-40">
        <Input type="date" value={value.toDate} onChange={(e) => set({ toDate: e.target.value })} className="w-full" />
      </FilterField>

      {show.flock && (
        <FilterField label="Flock" className="sm:w-48">
          <Select
            value={value.flockId != null ? String(value.flockId) : ALL}
            onValueChange={(v) => set({ flockId: v === ALL ? null : Number(v) })}
          >
            <SelectTrigger className="w-full"><SelectValue placeholder="All flocks" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All flocks</SelectItem>
              {flocks.map((f) => <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name}</SelectItem>)}
            </SelectContent>
          </Select>
        </FilterField>
      )}

      {show.customer && (
        <FilterField label="Customer" className="sm:w-48">
          <Select
            value={value.customerName || ALL}
            onValueChange={(v) => set({ customerName: v === ALL ? null : v })}
          >
            <SelectTrigger className="w-full"><SelectValue placeholder="All customers" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All customers</SelectItem>
              {customers.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
            </SelectContent>
          </Select>
        </FilterField>
      )}

      {show.supplier && (
        <FilterField label="Supplier / payee" className="sm:w-44">
          <Input
            value={value.supplierName ?? ""}
            onChange={(e) => set({ supplierName: e.target.value || null })}
            placeholder="Any supplier"
            className="w-full"
          />
        </FilterField>
      )}

      {show.category && (
        <FilterField label="Category" className="sm:w-56">
          <Select
            value={value.category ?? ALL}
            onValueChange={(v) => set({ category: v === ALL ? null : v })}
          >
            <SelectTrigger className="w-full"><SelectValue placeholder="All categories" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All categories</SelectItem>
              {categories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
            </SelectContent>
          </Select>
        </FilterField>
      )}

      {show.includeClosedFlocks && (
        // No label of its own, so it aligns on the control line rather than
        // riding up level with the labels above it.
        <label className="flex h-9 shrink-0 cursor-pointer select-none items-center gap-2 whitespace-nowrap text-sm text-slate-600">
          <input
            type="checkbox"
            className="h-4 w-4 rounded border-slate-300"
            checked={!!value.includeClosedFlocks}
            onChange={(e) => set({ includeClosedFlocks: e.target.checked })}
          />
          Include closed flocks
        </label>
      )}

      <Button variant="outline" size="sm" onClick={onReset} className="h-9 w-full shrink-0 sm:w-auto">Clear</Button>
    </div>
  )
}

/** One labelled control: label on top, control filling the width below it. */
function FilterField({ label, className, children }: {
  label: string; className?: string; children: React.ReactNode
}) {
  return (
    <div className={cn("flex min-w-0 flex-col gap-1", className)}>
      <Label className="text-xs text-slate-600">{label}</Label>
      {children}
    </div>
  )
}

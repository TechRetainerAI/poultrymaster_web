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
    <div className="print:hidden mb-4 flex items-center gap-2 flex-wrap">
      <div className="flex items-center gap-1.5 w-full sm:w-auto">
        <Label className="text-xs text-slate-600 whitespace-nowrap">Period</Label>
        <div className="flex-1 sm:flex-none">
          <PeriodSelect
            label={null}
            className="w-full sm:w-44"
            value={rangeToPeriod(value.fromDate, value.toDate)}
            onChange={(_p, range) => { if (range) set({ fromDate: range.from, toDate: range.to }) }}
          />
        </div>
      </div>

      <div className="flex items-center gap-1.5 w-full sm:w-auto">
        <Label className="text-xs text-slate-600 whitespace-nowrap">From</Label>
        <Input type="date" value={value.fromDate} onChange={(e) => set({ fromDate: e.target.value })} className="flex-1 sm:w-40 sm:flex-none" />
      </div>
      <div className="flex items-center gap-1.5 w-full sm:w-auto">
        <Label className="text-xs text-slate-600 whitespace-nowrap">To</Label>
        <Input type="date" value={value.toDate} onChange={(e) => set({ toDate: e.target.value })} className="flex-1 sm:w-40 sm:flex-none" />
      </div>

      {show.flock && (
        <div className="flex items-center gap-1.5 w-full sm:w-auto">
          <Label className="text-xs text-slate-600 whitespace-nowrap">Flock</Label>
          <Select
            value={value.flockId != null ? String(value.flockId) : ALL}
            onValueChange={(v) => set({ flockId: v === ALL ? null : Number(v) })}
          >
            <SelectTrigger className="w-full sm:w-48"><SelectValue placeholder="All flocks" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All flocks</SelectItem>
              {flocks.map((f) => <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      )}

      {show.customer && (
        <div className="flex items-center gap-1.5 w-full sm:w-auto">
          <Label className="text-xs text-slate-600 whitespace-nowrap">Customer</Label>
          <Select
            value={value.customerName || ALL}
            onValueChange={(v) => set({ customerName: v === ALL ? null : v })}
          >
            <SelectTrigger className="w-full sm:w-48"><SelectValue placeholder="All customers" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All customers</SelectItem>
              {customers.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      )}

      {show.supplier && (
        <div className="flex items-center gap-1.5 w-full sm:w-auto">
          <Label className="text-xs text-slate-600 whitespace-nowrap">Supplier / payee</Label>
          <Input
            value={value.supplierName ?? ""}
            onChange={(e) => set({ supplierName: e.target.value || null })}
            placeholder="Any supplier"
            className="flex-1 sm:w-44 sm:flex-none"
          />
        </div>
      )}

      {show.category && (
        <div className="flex items-center gap-1.5 w-full sm:w-auto">
          <Label className="text-xs text-slate-600 whitespace-nowrap">Category</Label>
          <Select
            value={value.category ?? ALL}
            onValueChange={(v) => set({ category: v === ALL ? null : v })}
          >
            <SelectTrigger className="flex-1 sm:w-56 sm:flex-none"><SelectValue placeholder="All categories" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All categories</SelectItem>
              {categories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      )}

      {show.includeClosedFlocks && (
        <label className="flex items-center gap-2 text-sm text-slate-600 h-9 cursor-pointer select-none">
          <input
            type="checkbox"
            className="h-4 w-4 rounded border-slate-300"
            checked={!!value.includeClosedFlocks}
            onChange={(e) => set({ includeClosedFlocks: e.target.checked })}
          />
          Include closed flocks
        </label>
      )}

      <Button variant="outline" size="sm" onClick={onReset} className="h-9 w-full sm:w-auto">Clear</Button>
    </div>
  )
}

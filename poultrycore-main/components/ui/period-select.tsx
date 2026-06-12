"use client"

/**
 * PeriodSelect — a grouped "period" dropdown to sit next to From/To date
 * filters on reports (James 2026-06-10). Picking a preset (Today, This Month,
 * Last Quarter, …) sets From/To for the caller; "Custom Date Range" hands
 * control back to the manual inputs.
 *
 *   <PeriodSelect
 *     value={period}
 *     onChange={(p, range) => {
 *       setPeriod(p)
 *       if (range) { setFrom(range.from); setTo(range.to) }
 *     }}
 *   />
 */

import { Label } from "@/components/ui/label"
import {
  Select, SelectContent, SelectGroup, SelectItem,
  SelectSeparator, SelectTrigger, SelectValue,
} from "@/components/ui/select"
import { PERIOD_GROUPS, periodToRange, type DateRange, type PeriodKey } from "@/lib/date-ranges"

export function PeriodSelect({
  value,
  onChange,
  label = "Period",
  className = "w-44",
}: {
  value: PeriodKey
  onChange: (period: PeriodKey, range: DateRange | null) => void
  label?: string | null
  className?: string
}) {
  return (
    <div>
      {label ? <Label className="text-xs">{label}</Label> : null}
      <Select
        value={value}
        onValueChange={(v) => {
          const p = v as PeriodKey
          onChange(p, periodToRange(p))
        }}
      >
        <SelectTrigger className={className}><SelectValue placeholder="Select period" /></SelectTrigger>
        <SelectContent>
          {/* Visually grouped (matching James's "Best display order" mockup):
              separators between groups, no category headings. */}
          {PERIOD_GROUPS.map((g, gi) => (
            <SelectGroup key={g.label}>
              {gi > 0 && <SelectSeparator />}
              {g.options.map((o) => (
                <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
              ))}
            </SelectGroup>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}

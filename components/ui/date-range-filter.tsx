"use client"

/**
 * DateRangeFilter — a Period dropdown + From + To inputs in one row, kept in
 * sync (James 2026-06-10: "add the Period dropdown on all the main pages with
 * date from / date to"). Picking a preset (Today, This Month, Last Quarter, …)
 * fills From/To; editing From/To by hand flips the dropdown to "Custom Date
 * Range". Drop-in replacement for an inline pair of <input type="date"> filters.
 *
 *   <DateRangeFilter
 *     from={dateFrom}
 *     to={dateTo}
 *     onChange={(from, to) => { setDateFrom(from); setDateTo(to) }}
 *   />
 */

import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select, SelectContent, SelectGroup, SelectItem,
  SelectSeparator, SelectTrigger, SelectValue,
} from "@/components/ui/select"
import { PERIOD_GROUPS, periodToRange, rangeToPeriod } from "@/lib/date-ranges"

export function DateRangeFilter({
  from,
  to,
  onChange,
  showLabels = true,
  className = "",
}: {
  from: string
  to: string
  onChange: (from: string, to: string) => void
  /** Show the small "Period / From / To" captions above each control. */
  showLabels?: boolean
  className?: string
}) {
  // Reflect the current From/To in the dropdown (a matching preset, else Custom).
  const period = from && to ? rangeToPeriod(from, to) : "custom"

  return (
    <div className={`flex flex-wrap items-end gap-2 ${className}`}>
      <div>
        {showLabels ? <Label className="text-xs">Period</Label> : null}
        <Select
          value={period}
          onValueChange={(v) => {
            const r = periodToRange(v as never)
            if (r) onChange(r.from, r.to) // preset → fill From/To; "custom" → keep current
          }}
        >
          <SelectTrigger className="w-40"><SelectValue placeholder="Select period" /></SelectTrigger>
          <SelectContent>
            {/* Visually grouped (James's "Best display order" mockup): separators, no headings. */}
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
      <div>
        {showLabels ? <Label className="text-xs">From</Label> : null}
        <Input
          type="date"
          value={from}
          onChange={(e) => onChange(e.target.value, to)}
          className="w-40"
        />
      </div>
      <div>
        {showLabels ? <Label className="text-xs">To</Label> : null}
        <Input
          type="date"
          value={to}
          onChange={(e) => onChange(from, e.target.value)}
          className="w-40"
        />
      </div>
    </div>
  )
}

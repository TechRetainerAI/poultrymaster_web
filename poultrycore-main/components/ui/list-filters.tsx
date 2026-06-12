"use client"

/**
 * ListFilters — the search + date-range filter strip from the poultry list
 * pages (see app/sales/page.tsx around lines 1192-1215). Sits above the
 * list and feeds its `search` / `dateFrom` / `dateTo` state back to the
 * page so the underlying `items` array can be filtered client-side.
 *
 * Usage:
 *
 *   const [search, setSearch] = useState("")
 *   const [dateFrom, setDateFrom] = useState("")
 *   const [dateTo, setDateTo] = useState("")
 *
 *   <ListFilters
 *     search={search} setSearch={setSearch}
 *     dateFrom={dateFrom} setDateFrom={setDateFrom}
 *     dateTo={dateTo} setDateTo={setDateTo}
 *     searchPlaceholder="Search customer or product"
 *   />
 *
 *   const filtered = useMemo(
 *     () => filterByDateAndSearch(items, {
 *       search, dateFrom, dateTo,
 *       searchKeys: ["customerName", "productName"],
 *       dateKey: "saleDate",
 *     }),
 *     [items, search, dateFrom, dateTo],
 *   )
 *
 * Pass `searchOnly` when the entity has no date field. `extras` slot accepts
 * extra controls (status select, currency dropdown, export buttons) that
 * sit to the right of the date range.
 */

import { type ReactNode } from "react"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"
import {
  Select, SelectContent, SelectGroup, SelectItem,
  SelectSeparator, SelectTrigger, SelectValue,
} from "@/components/ui/select"
import { PERIOD_GROUPS, periodToRange, rangeToPeriod } from "@/lib/date-ranges"
import { Search, X } from "lucide-react"

export interface ListFiltersProps {
  search: string
  setSearch: (v: string) => void
  searchPlaceholder?: string
  dateFrom?: string
  setDateFrom?: (v: string) => void
  dateTo?: string
  setDateTo?: (v: string) => void
  /** When true, hide the From/To inputs even if setters are passed. */
  searchOnly?: boolean
  /** Slot for extra controls (status select, currency dropdown, etc.). */
  extras?: ReactNode
  /** Slot for action buttons (Export PDF, etc.). Rendered on the right. */
  actions?: ReactNode
}

export function ListFilters({
  search, setSearch,
  searchPlaceholder = "Search…",
  dateFrom, setDateFrom,
  dateTo, setDateTo,
  searchOnly,
  extras,
  actions,
}: ListFiltersProps) {
  const showDates = !searchOnly && setDateFrom && setDateTo
  const activeCount =
    (search ? 1 : 0) + (dateFrom ? 1 : 0) + (dateTo ? 1 : 0)

  // Period dropdown reflects the current From/To (a matching preset, else
  // Custom). Picking a preset fills both dates at once.
  const period = dateFrom && dateTo ? rangeToPeriod(dateFrom, dateTo) : "custom"

  function clearAll() {
    setSearch("")
    setDateFrom?.("")
    setDateTo?.("")
  }

  return (
    <div className="p-3 bg-white rounded-lg border flex flex-wrap gap-3 items-end mb-4">
      <div className="w-full sm:w-[260px]">
        <Label className="text-xs text-slate-500">Search</Label>
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
          <Input
            placeholder={searchPlaceholder}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
      </div>

      {showDates && (
        <>
          {/* Period preset — picking one fills From/To; editing From/To by hand
              flips this back to "Custom Date Range". */}
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <Label className="text-xs text-slate-500 shrink-0 w-10">Period</Label>
            <Select
              value={period}
              onValueChange={(v) => {
                const r = periodToRange(v as never)
                if (r) { setDateFrom!(r.from); setDateTo!(r.to) }
              }}
            >
              <SelectTrigger className="flex-1 sm:w-[160px] sm:flex-none">
                <SelectValue placeholder="Select period" />
              </SelectTrigger>
              <SelectContent>
                {/* Grouped by spacing (James's "Best display order" mockup). */}
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
          {/* #19: label + picker inline on one row each, so the From/To filter
              takes 2 rows on mobile instead of 4. */}
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <Label className="text-xs text-slate-500 shrink-0 w-10">From</Label>
            <Input
              type="date"
              value={dateFrom ?? ""}
              onChange={(e) => setDateFrom!(e.target.value)}
              className="flex-1 sm:w-[160px] sm:flex-none"
            />
          </div>
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <Label className="text-xs text-slate-500 shrink-0 w-10">To</Label>
            <Input
              type="date"
              value={dateTo ?? ""}
              onChange={(e) => setDateTo!(e.target.value)}
              className="flex-1 sm:w-[160px] sm:flex-none"
            />
          </div>
        </>
      )}

      {extras}

      {activeCount > 0 && (
        <Button variant="ghost" size="sm" onClick={clearAll} className="gap-1 text-slate-500 hover:text-slate-800">
          <X className="h-3 w-3" /> Clear ({activeCount})
        </Button>
      )}

      {actions && <div className="ml-auto flex items-center gap-2 flex-wrap">{actions}</div>}
    </div>
  )
}

/**
 * Filter helper used alongside ListFilters. Returns the subset of `items`
 * whose `dateKey` falls inside [dateFrom, dateTo] AND whose `searchKeys`
 * contain `search` (case-insensitive substring). Empty filters are no-ops.
 */
export function filterByDateAndSearch<T extends Record<string, any>>(
  items: T[],
  opts: {
    search: string
    dateFrom?: string
    dateTo?: string
    searchKeys: (keyof T | string)[]
    dateKey?: keyof T | string
  },
): T[] {
  const s = (opts.search ?? "").trim().toLowerCase()
  const from = opts.dateFrom ? new Date(opts.dateFrom) : null
  const to = opts.dateTo ? new Date(opts.dateTo) : null
  if (to) {
    // Make the comparison inclusive of the entire 'to' day.
    to.setHours(23, 59, 59, 999)
  }

  return items.filter((row) => {
    // Date check
    if ((from || to) && opts.dateKey) {
      const raw = row[opts.dateKey as keyof T]
      if (raw) {
        const d = new Date(raw as any)
        if (!Number.isNaN(d.getTime())) {
          if (from && d < from) return false
          if (to && d > to) return false
        }
      }
    }
    // Search check
    if (s) {
      const hit = opts.searchKeys.some((k) => {
        const v = row[k as keyof T]
        return v != null && String(v).toLowerCase().includes(s)
      })
      if (!hit) return false
    }
    return true
  })
}

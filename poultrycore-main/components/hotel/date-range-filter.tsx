"use client"

import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Calendar } from "lucide-react"

interface DateRangeFilterProps {
  startDate: string
  endDate: string
  onStartChange: (date: string) => void
  onEndChange: (date: string) => void
  onClear?: () => void
}

export function DateRangeFilter({ startDate, endDate, onStartChange, onEndChange, onClear }: DateRangeFilterProps) {
  return (
    <div className="flex items-center gap-2">
      <Calendar className="h-4 w-4 text-slate-400" />
      <Input type="date" className="w-[140px] h-8 text-xs" value={startDate} onChange={(e) => onStartChange(e.target.value)} />
      <span className="text-xs text-slate-400">to</span>
      <Input type="date" className="w-[140px] h-8 text-xs" value={endDate} onChange={(e) => onEndChange(e.target.value)} />
      {onClear && (startDate || endDate) && (
        <Button variant="ghost" size="sm" className="text-xs h-8" onClick={onClear}>Clear</Button>
      )}
    </div>
  )
}

export function filterByDateRange<T>(items: T[], dateField: string, startDate: string, endDate: string): T[] {
  return items.filter((item: any) => {
    const val = item[dateField]?.slice?.(0, 10) ?? ""
    if (!val) return true
    if (startDate && val < startDate) return false
    if (endDate && val > endDate) return false
    return true
  })
}

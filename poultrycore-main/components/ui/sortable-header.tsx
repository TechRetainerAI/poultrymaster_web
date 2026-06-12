"use client"

import { ArrowUpDown, ArrowUp, ArrowDown } from "lucide-react"
import { TableHead } from "@/components/ui/table"
import { cn } from "@/lib/utils"

export type SortDirection = "asc" | "desc" | null

interface SortableHeaderProps {
  label: string
  sortKey: string
  currentSort: string | null
  currentDirection: SortDirection
  onSort: (key: string) => void
  className?: string
}

export function SortableHeader({
  label,
  sortKey,
  currentSort,
  currentDirection,
  onSort,
  className,
}: SortableHeaderProps) {
  const isActive = currentSort === sortKey

  return (
    <TableHead
      className={cn(
        "cursor-pointer select-none hover:bg-slate-100 transition-colors",
        className
      )}
      onClick={() => onSort(sortKey)}
    >
      <div className="flex items-center gap-1">
        <span>{label}</span>
        {isActive ? (
          currentDirection === "asc" ? (
            <ArrowUp className="w-3 h-3 text-blue-600" />
          ) : (
            <ArrowDown className="w-3 h-3 text-blue-600" />
          )
        ) : (
          <ArrowUpDown className="w-3 h-3 text-slate-400" />
        )}
      </div>
    </TableHead>
  )
}

/**
 * Toggle sort: first click = asc, second = desc, third = clear
 */
export function toggleSort(
  key: string,
  currentKey: string | null,
  currentDirection: SortDirection
): { key: string | null; direction: SortDirection } {
  if (currentKey !== key) {
    return { key, direction: "asc" }
  }
  if (currentDirection === "asc") {
    return { key, direction: "desc" }
  }
  // was desc → clear
  return { key: null, direction: null }
}

/**
 * Generic sort function for arrays.
 * Supports string, number, and date values.
 */
export function sortData<T>(
  data: T[],
  key: string | null,
  direction: SortDirection,
  getValueFn?: (item: T, key: string) => any
): T[] {
  if (!key || !direction) return data

  return [...data].sort((a, b) => {
    const aVal = getValueFn ? getValueFn(a, key) : (a as any)[key]
    const bVal = getValueFn ? getValueFn(b, key) : (b as any)[key]

    // Handle null/undefined
    if (aVal == null && bVal == null) return 0
    if (aVal == null) return direction === "asc" ? -1 : 1
    if (bVal == null) return direction === "asc" ? 1 : -1

    // Date comparison
    if (aVal instanceof Date && bVal instanceof Date) {
      return direction === "asc"
        ? aVal.getTime() - bVal.getTime()
        : bVal.getTime() - aVal.getTime()
    }

    // Try as dates if they look like date strings
    if (typeof aVal === "string" && typeof bVal === "string") {
      const dateA = new Date(aVal)
      const dateB = new Date(bVal)
      if (!isNaN(dateA.getTime()) && !isNaN(dateB.getTime()) && aVal.includes("-")) {
        return direction === "asc"
          ? dateA.getTime() - dateB.getTime()
          : dateB.getTime() - dateA.getTime()
      }
    }

    // Number comparison
    if (typeof aVal === "number" && typeof bVal === "number") {
      return direction === "asc" ? aVal - bVal : bVal - aVal
    }

    // String comparison
    const strA = String(aVal).toLowerCase()
    const strB = String(bVal).toLowerCase()
    if (strA < strB) return direction === "asc" ? -1 : 1
    if (strA > strB) return direction === "asc" ? 1 : -1
    return 0
  })
}


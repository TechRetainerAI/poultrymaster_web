"use client"

// =============================================================================
// ReportDataTable — a single, reusable table with click-to-sort headers and
// pagination (page numbers + prev/next + items-per-page), mirroring the
// production-records page UX. Used by every poultry report (the 20 advanced
// reports and the 4 farm dashboards) so they all behave consistently.
//
// Each row carries two parallel arrays:
//   • `display` — the React nodes shown in the cells (may be styled).
//   • `sort`    — primitive values used purely for column sorting.
// Keeping them separate lets cells stay pretty while sorting stays correct.
// =============================================================================

import { useEffect, useMemo, useState, type ReactNode } from "react"
import {
  Table, TableHeader, TableBody, TableFooter, TableRow, TableHead, TableCell,
} from "@/components/ui/table"
import {
  Pagination, PaginationContent, PaginationItem, PaginationLink,
  PaginationNext, PaginationPrevious, PaginationEllipsis,
} from "@/components/ui/pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Button } from "@/components/ui/button"
import { SortableHeader, type SortDirection, toggleSort } from "@/components/ui/sortable-header"
import { ArrowUp, ArrowDown } from "lucide-react"
import { useIsMobile } from "@/hooks/use-mobile"
import { cn } from "@/lib/utils"

export interface ReportTableColumn {
  header: string
  align?: "left" | "right"
}

export interface ReportTableRow {
  display: ReactNode[]
  sort: (string | number | null | undefined)[]
}

type SortVal = string | number | null | undefined

// Loose numeric parse — strips currency symbols / thousands separators.
function looseNumber(v: string): number | null {
  const cleaned = v.replace(/[^0-9.\-]/g, "")
  if (cleaned === "" || cleaned === "-" || cleaned === ".") return null
  const n = Number(cleaned)
  return Number.isNaN(n) ? null : n
}

// Compare two cell sort-values intelligently: real numbers first, then date
// strings, then currency / "1,234" style numbers, finally case-insensitive text.
function smartCompare(a: SortVal, b: SortVal): number {
  if (a == null && b == null) return 0
  if (a == null) return -1
  if (b == null) return 1
  if (typeof a === "number" && typeof b === "number") return a - b

  const as = String(a)
  const bs = String(b)

  const looksDate = (s: string) => /[a-zA-Z]/.test(s) || /[-/]/.test(s)
  const ad = Date.parse(as)
  const bd = Date.parse(bs)
  if (looksDate(as) && looksDate(bs) && !Number.isNaN(ad) && !Number.isNaN(bd)) return ad - bd

  const an = looseNumber(as)
  const bn = looseNumber(bs)
  if (an != null && bn != null) return an - bn

  return as.toLowerCase().localeCompare(bs.toLowerCase())
}

const PAGE_SIZE_OPTIONS = [10, 25, 50, 100]

export function ReportDataTable({
  columns,
  rows,
  empty = "No data for the selected filters.",
  initialPageSize = 10,
  minWidth,
  footer,
}: {
  columns: ReportTableColumn[]
  rows: ReportTableRow[]
  empty?: string
  initialPageSize?: number
  minWidth?: number
  /** Optional pinned totals row (parallel to columns). Not sorted or paginated. */
  footer?: ReactNode[]
}) {
  const isMobile = useIsMobile()
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(initialPageSize)

  const handleSort = (key: string) => {
    const r = toggleSort(key, sortKey, sortDir)
    setSortKey(r.key)
    setSortDir(r.direction)
  }

  const sorted = useMemo(() => {
    if (sortKey == null || sortDir == null) return rows
    const ci = Number(sortKey)
    const dir = sortDir === "asc" ? 1 : -1
    return [...rows].sort((a, b) => dir * smartCompare(a.sort[ci], b.sort[ci]))
  }, [rows, sortKey, sortDir])

  const total = sorted.length
  const totalPages = Math.max(1, Math.ceil(total / pageSize))
  const safePage = Math.min(page, totalPages)
  const start = (safePage - 1) * pageSize
  const end = start + pageSize
  const pageRows = sorted.slice(start, end)

  // Reset to page 1 when the data set or sort changes.
  useEffect(() => { setPage(1) }, [rows, sortKey, sortDir, pageSize])

  if (rows.length === 0) {
    return <p className="text-sm text-slate-500">{empty}</p>
  }

  const getPageNumbers = (): (number | "ellipsis")[] => {
    const pages: (number | "ellipsis")[] = []
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) pages.push(i)
    } else if (safePage <= 3) {
      pages.push(1, 2, 3, 4, "ellipsis", totalPages)
    } else if (safePage >= totalPages - 2) {
      pages.push(1, "ellipsis", totalPages - 3, totalPages - 2, totalPages - 1, totalPages)
    } else {
      pages.push(1, "ellipsis", safePage - 1, safePage, safePage + 1, "ellipsis", totalPages)
    }
    return pages
  }

  // Toggle the sort direction (mobile control), defaulting to ascending.
  const flipDir = () => setSortDir((d) => (d === "asc" ? "desc" : "asc"))

  return (
    <div className="space-y-3">
      {isMobile ? (
        <>
          {/* Mobile sort control — headers aren't tappable in the card view. */}
          <div className="flex items-center gap-2">
            <Select
              value={sortKey ?? "none"}
              onValueChange={(v) => {
                if (v === "none") { setSortKey(null); setSortDir(null) }
                else { setSortKey(v); setSortDir((d) => (sortKey === v && d ? d : "asc")) }
              }}
            >
              <SelectTrigger className="h-9 flex-1">
                <SelectValue placeholder="Sort by…" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">No sorting</SelectItem>
                {columns.map((c, i) => (
                  <SelectItem key={c.header} value={String(i)}>{c.header}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button
              variant="outline"
              size="sm"
              className="h-9 gap-1 shrink-0"
              disabled={sortKey == null}
              onClick={flipDir}
            >
              {sortDir === "desc" ? <ArrowDown className="h-4 w-4" /> : <ArrowUp className="h-4 w-4" />}
              {sortDir === "desc" ? "Desc" : "Asc"}
            </Button>
          </div>

          {/* Card list — one card per row. Each record gets a coloured header
              strip (primary value + record number) so it's clear on mobile
              where one record ends and the next begins. */}
          <div className="space-y-3">
            {pageRows.map((row, ri) => (
              <div key={start + ri} className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
                <div className="flex items-center justify-between gap-2 border-b border-amber-200 bg-amber-50 px-3 py-2">
                  <span className="min-w-0 break-words text-sm font-semibold text-slate-800">{row.display[0]}</span>
                  <span className="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-amber-700">
                    #{start + ri + 1}
                  </span>
                </div>
                <dl className="divide-y divide-slate-100 px-3 py-2">
                  {row.display.slice(1).map((cell, i) => {
                    const ci = i + 1
                    return (
                      <div key={ci} className="flex items-start justify-between gap-3 py-1.5 first:pt-0 last:pb-0">
                        <dt className="text-xs text-slate-500 shrink-0">{columns[ci]?.header}</dt>
                        <dd className={cn("text-sm text-slate-800 text-right min-w-0 break-words", columns[ci]?.align === "right" && "tabular-nums")}>
                          {cell}
                        </dd>
                      </div>
                    )
                  })}
                </dl>
              </div>
            ))}
            {footer && (
              <div className="rounded-lg border-2 border-slate-300 bg-slate-100 p-3 shadow-sm font-semibold">
                <dl className="divide-y divide-slate-200">
                  {footer.map((cell, ci) => (
                    <div key={ci} className="flex items-start justify-between gap-3 py-1.5 first:pt-0 last:pb-0">
                      <dt className="text-xs text-slate-500 shrink-0">{columns[ci]?.header}</dt>
                      <dd className={cn("text-sm text-slate-900 text-right min-w-0 break-words", columns[ci]?.align === "right" && "tabular-nums")}>
                        {cell}
                      </dd>
                    </div>
                  ))}
                </dl>
              </div>
            )}
          </div>
        </>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-slate-200">
          <Table style={minWidth ? { minWidth } : undefined}>
            <TableHeader>
              <TableRow>
                {columns.map((col, i) => (
                  <SortableHeader
                    key={col.header}
                    label={col.header}
                    sortKey={String(i)}
                    currentSort={sortKey}
                    currentDirection={sortDir}
                    onSort={handleSort}
                    className={cn(col.align === "right" && "text-right [&>div]:justify-end")}
                  />
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {pageRows.map((row, ri) => (
                <TableRow key={start + ri} className="even:bg-slate-50/60">
                  {row.display.map((cell, ci) => (
                    <TableCell
                      key={ci}
                      className={cn(
                        "py-2.5",
                        columns[ci]?.align === "right"
                          ? "text-right tabular-nums"
                          // The shared TableCell is whitespace-nowrap (ui/table.tsx:86),
                          // which is right for dates and money but turns a long
                          // Description into one endless line and pushes every
                          // column after it off the screen. Text columns wrap;
                          // right-aligned ones stay on one line, because a wrapped
                          // amount is unreadable.
                          : "whitespace-normal break-words align-top max-w-[28rem]",
                      )}
                    >
                      {cell}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
            {footer && (
              <TableFooter className="bg-slate-100">
                <TableRow className="border-t-2 border-slate-300 hover:bg-slate-100">
                  {footer.map((cell, ci) => (
                    <TableCell
                      key={ci}
                      className={cn("py-2.5 font-semibold text-slate-900", columns[ci]?.align === "right" && "text-right tabular-nums")}
                    >
                      {cell}
                    </TableCell>
                  ))}
                </TableRow>
              </TableFooter>
            )}
          </Table>
        </div>
      )}

      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div className="flex items-center gap-3">
          <span className="text-sm text-slate-600">
            Showing {total === 0 ? 0 : start + 1}–{Math.min(end, total)} of {total.toLocaleString()}
          </span>
          <Select value={String(pageSize)} onValueChange={(v) => { setPageSize(Number(v)); setPage(1) }}>
            <SelectTrigger className="w-[110px] h-8">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {PAGE_SIZE_OPTIONS.map((n) => (
                <SelectItem key={n} value={String(n)}>{n} / page</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {totalPages > 1 && (
          <Pagination className="mx-0 w-auto justify-end">
            <PaginationContent>
              <PaginationItem>
                <PaginationPrevious
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  className={safePage === 1 ? "pointer-events-none opacity-50" : "cursor-pointer"}
                />
              </PaginationItem>
              {getPageNumbers().map((p, i) => (
                <PaginationItem key={i}>
                  {p === "ellipsis" ? (
                    <PaginationEllipsis />
                  ) : (
                    <PaginationLink
                      onClick={() => setPage(p)}
                      isActive={safePage === p}
                      className="cursor-pointer"
                    >
                      {p}
                    </PaginationLink>
                  )}
                </PaginationItem>
              ))}
              <PaginationItem>
                <PaginationNext
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  className={safePage === totalPages ? "pointer-events-none opacity-50" : "cursor-pointer"}
                />
              </PaginationItem>
            </PaginationContent>
          </Pagination>
        )}
      </div>
    </div>
  )
}

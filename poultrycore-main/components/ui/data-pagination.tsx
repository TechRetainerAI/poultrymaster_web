"use client"

// =============================================================================
// DataPagination — the standard list footer: an items-per-page select and page
// numbers with prev/next.
//
// Lifted out of components/poultry-reports/report-data-table.tsx so every list
// page (poultry, water and generic) shows the same control in the same place.
// Pair it with usePagination() (hooks/use-pagination.ts):
//
//   const pg = usePagination(filteredRows)
//   ...
//   <DataPagination {...pg.paginationProps} />
//
// Renders nothing at all for a list shorter than the smallest page size — a
// 3-row table gets no footer. There is deliberately no "Showing 1–5 of 25"
// count line; the page links carry that information.
// =============================================================================

import {
  Pagination, PaginationContent, PaginationItem, PaginationLink,
  PaginationNext, PaginationPrevious, PaginationEllipsis,
} from "@/components/ui/pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"

// 5 first because it is the default: the Select renders blank if the current
// pageSize is not one of the options.
export const PAGE_SIZE_OPTIONS = [5, 10, 25, 50, 100]

export interface DataPaginationProps {
  /** 1-based, already clamped. */
  page: number
  pageSize: number
  /** Total rows across all pages. */
  total: number
  onPageChange: (page: number) => void
  onPageSizeChange: (size: number) => void
  pageSizeOptions?: number[]
  className?: string
}

/** 1 … 4 [ellipsis] N — never more than seven slots wide. */
function getPageNumbers(page: number, totalPages: number): (number | "ellipsis")[] {
  const pages: (number | "ellipsis")[] = []
  if (totalPages <= 7) {
    for (let i = 1; i <= totalPages; i++) pages.push(i)
  } else if (page <= 3) {
    pages.push(1, 2, 3, 4, "ellipsis", totalPages)
  } else if (page >= totalPages - 2) {
    pages.push(1, "ellipsis", totalPages - 3, totalPages - 2, totalPages - 1, totalPages)
  } else {
    pages.push(1, "ellipsis", page - 1, page, page + 1, "ellipsis", totalPages)
  }
  return pages
}

export function DataPagination({
  page, pageSize, total, onPageChange, onPageSizeChange,
  pageSizeOptions = PAGE_SIZE_OPTIONS,
  className,
}: DataPaginationProps) {
  const totalPages = Math.max(1, Math.ceil(total / pageSize))

  // A list shorter than the smallest page size can't be paged and doesn't need
  // a size control either — render nothing rather than a stub footer.
  if (total < pageSizeOptions[0]) return null

  return (
    <div className={cn("flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mt-4", className)}>
      <div className="flex items-center gap-3">
        <Select value={String(pageSize)} onValueChange={(v) => onPageSizeChange(Number(v))}>
          <SelectTrigger className="w-[110px] h-8">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {pageSizeOptions.map((n) => (
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
                onClick={() => onPageChange(Math.max(1, page - 1))}
                className={page === 1 ? "pointer-events-none opacity-50" : "cursor-pointer"}
              />
            </PaginationItem>
            {getPageNumbers(page, totalPages).map((p, i) => (
              <PaginationItem key={i}>
                {p === "ellipsis" ? (
                  <PaginationEllipsis />
                ) : (
                  <PaginationLink
                    onClick={() => onPageChange(p)}
                    isActive={page === p}
                    className="cursor-pointer"
                  >
                    {p}
                  </PaginationLink>
                )}
              </PaginationItem>
            ))}
            <PaginationItem>
              <PaginationNext
                onClick={() => onPageChange(Math.min(totalPages, page + 1))}
                className={page === totalPages ? "pointer-events-none opacity-50" : "cursor-pointer"}
              />
            </PaginationItem>
          </PaginationContent>
        </Pagination>
      )}
    </div>
  )
}

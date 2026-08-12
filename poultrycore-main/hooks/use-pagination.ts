"use client"

// =============================================================================
// usePagination — client-side paging for a list that is already fully loaded.
//
// Every list page in this app fetches the whole collection and filters/sorts it
// in memory, so paging is a slice, not a query. This hook is the one place that
// slice lives; pair it with <DataPagination> (components/ui/data-pagination.tsx)
// for the footer UI:
//
//   const pg = usePagination(filteredRows)
//   ...
//   {pg.pageItems.map(...)}
//   <DataPagination {...pg.paginationProps} />
//
// Behaviour matches components/poultry-reports/report-data-table.tsx, which is
// what the poultry pages have always used.
// =============================================================================

import { useEffect, useMemo, useState } from "react"

export interface PaginationResult<T> {
  /** Current page, 1-based and already clamped to [1, totalPages]. */
  page: number
  setPage: (page: number) => void
  pageSize: number
  setPageSize: (size: number) => void
  /** The slice to render. */
  pageItems: T[]
  /** Total items across all pages (post-filter). */
  total: number
  totalPages: number
  /** 0-based index of the first item on this page — handy for row numbering. */
  start: number
  /** Exclusive end index. */
  end: number
  /** Spread straight onto <DataPagination />. */
  paginationProps: {
    page: number
    pageSize: number
    total: number
    onPageChange: (page: number) => void
    onPageSizeChange: (size: number) => void
  }
}

export function usePagination<T>(items: T[], initialPageSize = 5): PaginationResult<T> {
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(initialPageSize)

  const total = items.length
  const totalPages = Math.max(1, Math.ceil(total / pageSize))
  // Clamp rather than store the clamped value: deleting the last row of the
  // last page would otherwise leave the caller rendering an empty slice.
  const safePage = Math.min(Math.max(1, page), totalPages)
  const start = (safePage - 1) * pageSize
  const end = start + pageSize

  const pageItems = useMemo(() => items.slice(start, end), [items, start, end])

  // Snap back to page 1 when the result set resizes (a filter or search was
  // applied, a record was added). Keyed on the LENGTH, not the array identity:
  // most callers rebuild their filtered array on every render, and depending on
  // identity would pin every list to page 1 forever.
  useEffect(() => { setPage(1) }, [total, pageSize])

  return {
    page: safePage,
    setPage,
    pageSize,
    setPageSize,
    pageItems,
    total,
    totalPages,
    start,
    end,
    paginationProps: {
      page: safePage,
      pageSize,
      total,
      onPageChange: setPage,
      onPageSizeChange: (size: number) => { setPageSize(size); setPage(1) },
    },
  }
}

"use client"

/**
 * MobileCardList — the responsive list pattern from the poultry pages
 * (see app/customers/page.tsx for the original). On mobile, render each item
 * as a collapsible card with primary + secondary fields visible, full detail
 * grid + action buttons revealed on tap. On desktop, fall through to the
 * existing table.
 *
 * Usage:
 *
 *   <MobileCardList
 *     items={customers}
 *     getKey={(c) => c.id}
 *     primary={(c) => c.name}
 *     secondary={(c) => <>{c.email} · {c.city}</>}
 *     details={(c) => [
 *       { label: "Phone", value: c.phone ?? "—" },
 *       { label: "Outstanding", value: gh(c.outstandingBalance) },
 *     ]}
 *     actions={(c) => (
 *       <>
 *         <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(c)}>Edit</Button>
 *         <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(c)}>Delete</Button>
 *       </>
 *     )}
 *     desktopTable={<Table>…</Table>}
 *   />
 *
 * The component renders desktopTable on screens ≥ lg. On smaller screens it
 * shows the card list. A "View table format" toggle lets mobile users
 * temporarily reveal the table (horizontal scroll) when they need columns
 * that didn't make it into the card detail grid.
 */

import { useState, type ReactNode } from "react"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { Button } from "@/components/ui/button"
import { DataPagination, type DataPaginationProps } from "@/components/ui/data-pagination"
import { ChevronDown, ChevronUp } from "lucide-react"
import { cn } from "@/lib/utils"

type DetailField = { label: string; value: ReactNode }

/**
 * Tinted headline tiles, the look the /poultry-daily-closing cards use: the
 * one or two numbers that matter sit above the fold in their own coloured
 * panel, so a collapsed card still answers "how much?" at a glance.
 */
type HighlightAccent = "emerald" | "blue" | "violet" | "amber" | "rose" | "slate"
type HighlightField = { label: string; value: ReactNode; accent?: HighlightAccent; /** Span both columns. */ wide?: boolean }

const HIGHLIGHT_TONES: Record<HighlightAccent, { tile: string; label: string; value: string }> = {
  emerald: { tile: "bg-emerald-100 border-emerald-300", label: "text-emerald-900", value: "text-emerald-800" },
  blue: { tile: "bg-blue-100 border-blue-300", label: "text-blue-900", value: "text-blue-800" },
  violet: { tile: "bg-violet-100 border-violet-300", label: "text-violet-900", value: "text-violet-900" },
  amber: { tile: "bg-amber-100 border-amber-300", label: "text-amber-900", value: "text-amber-800" },
  rose: { tile: "bg-rose-100 border-rose-300", label: "text-rose-900", value: "text-rose-700" },
  slate: { tile: "bg-slate-100 border-slate-300", label: "text-slate-600", value: "text-slate-900" },
}

export interface MobileCardListProps<T> {
  items: T[]
  getKey: (item: T) => string | number
  primary: (item: T) => ReactNode
  secondary?: (item: T) => ReactNode
  details?: (item: T) => DetailField[]
  /**
   * Coloured headline tiles rendered under `secondary`, visible whether the
   * card is open or shut. Use for the item's money / count figures; leave the
   * descriptive fields to `details`.
   */
  highlights?: (item: T) => HighlightField[]
  actions?: (item: T) => ReactNode
  desktopTable: ReactNode
  emptyState?: ReactNode
  /** Optional badge / status pill rendered to the right of the chevron. */
  trailing?: (item: T) => ReactNode
  /** Detail pages (#N4): start cards expanded and hide the "view table" toggle. */
  alwaysExpanded?: boolean
  /** Start cards expanded but KEEP the "view table format" toggle available. */
  defaultOpen?: boolean
  /**
   * Tint alternate cards amber, the way the /poultry-daily-closing list does.
   * On a phone the stripe is what separates one record from the next once the
   * cards carry coloured tiles of their own.
   */
  striped?: boolean
  /**
   * Spread usePagination()'s `paginationProps` here and pass the PAGE SLICE
   * (`pg.pageItems`) as both `items` and the array the `desktopTable` maps
   * over — the footer then sits below the cards and the table alike.
   */
  pagination?: DataPaginationProps
}

export function MobileCardList<T>({
  items, getKey, primary, secondary, details, highlights, actions, desktopTable, emptyState, trailing, alwaysExpanded = false, defaultOpen = false, striped = false, pagination,
}: MobileCardListProps<T>) {
  const [showTable, setShowTable] = useState(false)

  // `items` is the current page, so this only fires when the whole (filtered)
  // list is empty — usePagination snaps back to page 1 whenever it resizes.
  if (items.length === 0) {
    return <>{emptyState ?? null}</>
  }

  const pager = pagination ? <DataPagination {...pagination} className="px-3 pb-3" /> : null

  return (
    <>
      {/* Desktop: always the existing table */}
      <div className="hidden lg:block">
        {desktopTable}
        {pager}
      </div>

      {/* Mobile + tablet: collapsible cards by default; user can toggle into
          the table for the column-rich view. Uniform white cards with a
          subtle slate border + shadow — matches the look of the per-product
          / per-material cards inside the data-entry dialogs so the whole
          app reads as one design language. */}
      <div className="lg:hidden">
        {!showTable ? (
          <div className="space-y-2 p-3">
            {items.map((item, idx) => {
              const stripe = striped && idx % 2 === 0
              return (
              <Collapsible
                key={getKey(item)}
                defaultOpen={alwaysExpanded || defaultOpen}
                className={cn("group rounded-lg border shadow-sm overflow-hidden",
                  stripe ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}
              >
                <div className={cn("p-3 transition-colors", stripe ? "active:bg-black/10" : "active:bg-slate-50/80")}>
                  <CollapsibleTrigger asChild>
                    <div className="cursor-pointer">
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0 flex-1">
                          <div className="font-semibold text-slate-900 break-words">{primary(item)}</div>
                          {secondary && (
                            <div className="mt-1 flex items-center gap-2 text-sm text-slate-600 break-words">
                              {secondary(item)}
                            </div>
                          )}
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          {trailing?.(item)}
                          <ChevronDown className="h-5 w-5 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
                        </div>
                      </div>
                      {/* Full card width — the tiles sit below the header row
                          rather than beside the chevron, so they line up edge
                          to edge like the daily-closing cards. */}
                      {highlights && (
                        <div className="mt-3 grid grid-cols-2 gap-2">
                          {highlights(item).map((h, i) => {
                            const tone = HIGHLIGHT_TONES[h.accent ?? "slate"]
                            return (
                              <div key={i} className={cn("rounded-lg border px-3 py-2 shadow-sm", tone.tile, h.wide && "col-span-2")}>
                                <p className={cn("text-[11px] font-semibold uppercase tracking-wide", tone.label)}>{h.label}</p>
                                <p className={cn("text-xl font-extrabold leading-tight tabular-nums break-words", tone.value)}>{h.value}</p>
                              </div>
                            )
                          })}
                        </div>
                      )}
                    </div>
                  </CollapsibleTrigger>
                  <CollapsibleContent>
                    <div className={cn("mt-4 pt-4 border-t space-y-2 text-sm", stripe ? "border-slate-200/70" : "border-slate-100")}>
                      {details && (
                        <div className="grid grid-cols-2 gap-2">
                          {details(item).map((d, i) => (
                            <div key={i} className="min-w-0">
                              <div className="text-xs text-slate-500">{d.label}</div>
                              <div className="font-medium break-words">{d.value ?? "—"}</div>
                            </div>
                          ))}
                        </div>
                      )}
                      {actions && (
                        <div className="flex gap-2 pt-2">
                          {actions(item)}
                        </div>
                      )}
                    </div>
                  </CollapsibleContent>
                </div>
              </Collapsible>
              )
            })}

            {!alwaysExpanded && (
            <div className="px-1 pt-2">
              <Button
                variant="ghost"
                size="sm"
                className="w-full text-slate-600"
                onClick={() => setShowTable(true)}
              >
                View table format <ChevronDown className="h-4 w-4 ml-1" />
              </Button>
            </div>
            )}
            {pager}
          </div>
        ) : (
          <>
            <div className="px-3 py-2 border-b bg-slate-50 flex items-center justify-between gap-2 sticky top-0 z-10">
              <span className="text-xs text-slate-600">Table • Scroll → for more</span>
              <Button variant="ghost" size="sm" onClick={() => setShowTable(false)}>
                <ChevronUp className="h-4 w-4 mr-1" /> Cards
              </Button>
            </div>
            <div className="overflow-x-auto" style={{ WebkitOverflowScrolling: "touch" }}>
              {desktopTable}
            </div>
            {pager}
          </>
        )}
      </div>
    </>
  )
}

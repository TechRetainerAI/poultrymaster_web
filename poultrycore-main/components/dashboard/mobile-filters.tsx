"use client"

import * as React from "react"
import { SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { cn } from "@/lib/utils"

export const MOBILE_FILTER_SHEET_CONTENT_CLASS =
  "z-[60] flex h-[85vh] max-h-[90dvh] flex-col rounded-t-2xl p-0"

export const MOBILE_FILTER_SELECT_CONTENT_CLASS = "z-[200] max-h-[min(70vh,24rem)]"

/**
 * For a select whose list is GROUPED — option groups with headings and
 * separators between them.
 *
 * 24rem above is right for a flat list of a dozen-ish options. A grouped list
 * spends height on things that are not options: six headings and five
 * separators cost roughly 150px before a single choice is drawn, so the same
 * ceiling leaves the Period picker scrolling with only half its presets
 * visible. 44rem contains all sixteen.
 *
 * Still bounded by 85vh, so a short screen scrolls rather than the panel
 * running off the bottom — the point is to stop cramping a list that FITS, not
 * to let a panel grow without limit.
 */
export const GROUPED_SELECT_CONTENT_CLASS = "z-[200] max-h-[min(85vh,44rem)]"

/** Wrap filter trigger + export actions; flex-wrap avoids cramped grids on narrow phones. */
export const MOBILE_FILTERS_TOOLBAR_ROW_CLASS =
  "flex flex-wrap items-center gap-2 min-w-0 w-full"

/** Compact pill — no fixed vw width so it stays short and responsive. */
export const MOBILE_FILTERS_TRIGGER_BUTTON_CLASS =
  "inline-flex h-10 shrink-0 items-center gap-1.5 rounded-full border border-slate-200 bg-white px-3 text-sm font-medium shadow-sm"

export function MobileFilterSheetHeader({ title = "Filters" }: { title?: string }) {
  return (
    <SheetHeader className="border-b border-slate-100 px-4 pb-2 pt-2 text-left">
      <SheetTitle>{title}</SheetTitle>
    </SheetHeader>
  )
}

export function MobileFilterSheetBody({
  children,
  className,
}: {
  children: React.ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        "min-h-0 flex-1 space-y-5 overflow-y-auto overscroll-contain px-4 py-4 pb-28",
        className
      )}
    >
      {children}
    </div>
  )
}

export function MobileFilterSheetFooter({ children }: { children: React.ReactNode }) {
  return (
    <div className="border-t border-slate-100 bg-background px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
      {children}
    </div>
  )
}

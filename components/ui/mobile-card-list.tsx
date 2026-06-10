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
import { ChevronDown, ChevronUp } from "lucide-react"
import { cn } from "@/lib/utils"

type DetailField = { label: string; value: ReactNode }

export interface MobileCardListProps<T> {
  items: T[]
  getKey: (item: T) => string | number
  primary: (item: T) => ReactNode
  secondary?: (item: T) => ReactNode
  details?: (item: T) => DetailField[]
  actions?: (item: T) => ReactNode
  desktopTable: ReactNode
  emptyState?: ReactNode
  /** Optional badge / status pill rendered to the right of the chevron. */
  trailing?: (item: T) => ReactNode
  /** Detail pages (#N4): start cards expanded and hide the "view table" toggle. */
  alwaysExpanded?: boolean
}

export function MobileCardList<T>({
  items, getKey, primary, secondary, details, actions, desktopTable, emptyState, trailing, alwaysExpanded = false,
}: MobileCardListProps<T>) {
  const [showTable, setShowTable] = useState(false)

  if (items.length === 0) {
    return <>{emptyState ?? null}</>
  }

  return (
    <>
      {/* Desktop: always the existing table */}
      <div className="hidden lg:block">{desktopTable}</div>

      {/* Mobile + tablet: collapsible cards by default; user can toggle into
          the table for the column-rich view. Uniform white cards with a
          subtle slate border + shadow — matches the look of the per-product
          / per-material cards inside the data-entry dialogs so the whole
          app reads as one design language. */}
      <div className="lg:hidden">
        {!showTable ? (
          <div className="space-y-2 p-3">
            {items.map((item) => (
              <Collapsible
                key={getKey(item)}
                defaultOpen={alwaysExpanded}
                className="group rounded-lg border border-slate-200 bg-white shadow-sm overflow-hidden"
              >
                <div className="p-3 active:bg-slate-50/80 transition-colors">
                  <CollapsibleTrigger asChild>
                    <div className="flex items-start justify-between gap-3 cursor-pointer">
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
                  </CollapsibleTrigger>
                  <CollapsibleContent>
                    <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
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
            ))}

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
          </>
        )}
      </div>
    </>
  )
}

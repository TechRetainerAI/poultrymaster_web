"use client"

// =============================================================================
// The shared pieces of a sectioned Profit & Loss statement.
//
// A P&L is not a list of numbers, it is a statement with parts: where money
// came IN, and the distinct places it goes OUT. These pieces give every P&L in
// the app the same vocabulary for saying so — one colour per section, carried
// by the heading, the lines and the section's own total — so the poultry
// statement and the water one read as the same document about two businesses.
//
// The desktop layout stands the sections side by side (see StatementPanel);
// the stacked layout each report builds for itself, because what belongs
// between the sections — the running Gross / Operating / Net results — differs
// from report to report.
// =============================================================================

import { ChevronRight } from "lucide-react"
import { cn } from "@/lib/utils"

export type SectionTone = "emerald" | "rose" | "amber" | "violet"

/**
 * Money in is emerald; the ways money goes out are rose (what it cost to
 * produce), amber (what it cost to run the place) and violet (what the assets,
 * the borrowing, or the losses cost).
 */
export const SECTION_TONES: Record<SectionTone, { head: string; rail: string; total: string }> = {
  emerald: { head: "bg-emerald-50 text-emerald-800", rail: "border-emerald-200", total: "bg-emerald-50/70" },
  rose:    { head: "bg-rose-50 text-rose-800",       rail: "border-rose-200",    total: "bg-rose-50/70" },
  amber:   { head: "bg-amber-50 text-amber-800",     rail: "border-amber-200",   total: "bg-amber-50/70" },
  violet:  { head: "bg-violet-50 text-violet-800",   rail: "border-violet-200",  total: "bg-violet-50/70" },
}

/**
 * Cost lines are shown in accounting parentheses — but only when there is
 * something to subtract. An empty section printing "(0.00)" reads as a
 * negative figure when it means nothing happened.
 */
export function stated(amount: number, gh: (n: number) => string, negative?: boolean) {
  return negative && amount !== 0 ? `(${gh(amount)})` : gh(amount)
}

export type StatementLine = {
  /** Unique within its section. */
  id: string
  label: string
  amount: number
  /** How many records are behind the figure, when the report knows. */
  entryCount?: number
  /** Opens the drilldown, where the report has one. Without it the line is inert. */
  onOpen?: () => void
}

/**
 * One section of the statement as a self-contained panel: heading, its lines,
 * its total. Put several in a grid row and the whole statement sits on one line
 * of the page; put them in a single column and it stacks.
 */
export function StatementPanel({ title, totalLabel, total, lines, gh, negative, tone, emptyText = "None this period" }: {
  title: string
  totalLabel: string
  total: number
  lines: StatementLine[]
  gh: (n: number) => string
  negative?: boolean
  tone: SectionTone
  emptyText?: string
}) {
  const t = SECTION_TONES[tone]
  return (
    <div className="flex flex-col overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
      <div className={cn("px-3 py-2 text-[11px] font-semibold uppercase tracking-wide", t.head)}>
        {title}
      </div>
      {/* flex-1 so panels sharing a row square off at the bottom however many
          lines each of them happens to have. */}
      <div className="flex-1 divide-y divide-slate-100">
        {lines.length === 0 ? (
          <p className="px-3 py-3 text-sm text-slate-400">{emptyText}</p>
        ) : lines.map((l) => {
          const body = (
            <>
              <span className="min-w-0">
                <span className="inline-flex items-center gap-1">
                  <span className="break-words">{l.label}</span>
                  {l.onOpen && <ChevronRight className="h-3.5 w-3.5 shrink-0 text-slate-400" />}
                </span>
                {l.entryCount != null && (
                  <span className="ml-1 inline-block rounded-full bg-slate-100 px-1.5 py-px align-middle text-[10px] font-medium text-slate-500">
                    {l.entryCount} {l.entryCount === 1 ? "entry" : "entries"}
                  </span>
                )}
              </span>
              <span className="shrink-0 tabular-nums">{stated(l.amount, gh, negative)}</span>
            </>
          )
          // A line only becomes a button where there is something behind it to
          // open: a control that does nothing on click is worse than a plain row.
          return l.onOpen ? (
            <button key={l.id} type="button" onClick={l.onOpen}
                    className="flex w-full items-start justify-between gap-2 px-3 py-2 text-left text-sm hover:bg-slate-50">
              {body}
            </button>
          ) : (
            <div key={l.id} className="flex items-start justify-between gap-2 px-3 py-2 text-sm">
              {body}
            </div>
          )
        })}
      </div>
      <div className={cn("flex items-center justify-between gap-2 border-t px-3 py-2 text-sm font-semibold", t.total)}>
        <span className="min-w-0 break-words">{totalLabel}</span>
        <span className="shrink-0 tabular-nums">{stated(total, gh, negative)}</span>
      </div>
    </div>
  )
}

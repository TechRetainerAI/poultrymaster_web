"use client"

/**
 * An INFORMATIONAL panel on a Profit & Loss statement: money that moved without
 * being revenue or expense — owner contributions, borrowing, capital purchases.
 *
 * WHY IT LOOKS DIFFERENT FROM THE STATEMENT PANELS
 * ------------------------------------------------
 * Dashed border, a subtitle that says "Excluded from profit", and a plain note
 * explaining the rule. None of that is decoration: these figures sit on a page
 * whose entire subject is profit, and an owner who sees "Loans received 50,000"
 * beside "Revenue 208,000" will add them together unless the page is emphatic
 * that they are different kinds of thing.
 *
 * WHY IT CARRIES LINKS
 * --------------------
 * Because the next question after "we took a 50,000 loan this period" is always
 * "show me the loans", and the answer is a module that already exists. A
 * drilldown says what made the figure; the links say where the thing lives.
 *
 * SHARED BY BOTH P&Ls ON PURPOSE
 * ------------------------------
 * It began as a local component inside the poultry P&L. The water P&L needed the
 * same panel, and the choice was to copy thirty lines or to move them here.
 * Copying would have meant two panels that start identical and drift — which is
 * the failure this codebase keeps designing around. Each module passes its OWN
 * hrefs; nothing about poultry or water is baked in.
 */

import type { ReactNode } from "react"
import Link from "next/link"
import { ChevronRight } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"

/**
 * The minimum a line needs to be shown and opened. Both PoultryProfitLossLine
 * and WaterPlLine satisfy it structurally, so neither module has to adapt its
 * own type to use this.
 */
export type PlInfoLine = {
  lineKey: string
  lineLabel: string
  amount: number
}

export function PlInfoSection<T extends PlInfoLine>({
  icon, title, subtitle, note, lines, onOpen, gh, footer, links,
}: {
  icon: ReactNode
  title: string
  /** The rule, in three or four words: "Excluded from profit". */
  subtitle: string
  note: ReactNode
  lines: T[]
  /** Opens the drilldown behind one line. */
  onOpen: (l: T) => void
  gh: (n: number) => string
  footer?: ReactNode
  /** Where the underlying module lives. Each P&L supplies its own. */
  links: { href: string; label: string }[]
}) {
  return (
    <Card className="border-dashed"><CardContent className="p-4 space-y-3">
      <div className="flex items-start gap-2">
        <span className="text-slate-500 mt-0.5">{icon}</span>
        <div>
          <div className="text-sm font-semibold text-slate-900">{title}</div>
          <div className="text-[11px] uppercase tracking-wide text-amber-700">{subtitle}</div>
        </div>
      </div>
      <p className="text-xs text-slate-600">{note}</p>
      {lines.length === 0 ? (
        <p className="text-sm text-slate-400">None this period.</p>
      ) : (
        <div className="space-y-1">
          {lines.map((l) => (
            <button key={l.lineKey} type="button" onClick={() => onOpen(l)}
                    className="flex w-full items-center justify-between text-sm hover:underline">
              <span className="inline-flex items-center gap-1">
                {l.lineLabel}<ChevronRight className="w-3.5 h-3.5 text-slate-400" />
              </span>
              <span className="tabular-nums">{gh(l.amount)}</span>
            </button>
          ))}
        </div>
      )}
      {footer}
      <div className="flex flex-wrap gap-3 pt-1">
        {links.map((l) => (
          <Link key={l.href} href={l.href} className="text-xs text-sky-700 underline">{l.label}</Link>
        ))}
      </div>
    </CardContent></Card>
  )
}

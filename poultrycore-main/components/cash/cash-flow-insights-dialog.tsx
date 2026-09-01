"use client"

/**
 * Cash Flow Insights — plain-language answers to the questions an owner
 * actually asks: did we keep money, where did it come from, where did it go,
 * and is anything wrong with the numbers.
 *
 * This is where the diagnostics live. The page behind it is for the figures and
 * the history; warnings and breakdowns were pushed down here so the page reads
 * as a statement rather than a list of problems. Nothing is hidden — the button
 * that opens this is the first action in the header.
 *
 * Still a dumb renderer. Every sentence comes from buildCashFlowInsights() in
 * lib/cash/cash-flow, and every number is pre-computed; nothing here decides any
 * wording or does any arithmetic, so the two cannot drift.
 */

import type { ReactNode } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Lightbulb, TrendingUp, TrendingDown, AlertTriangle, Info } from "lucide-react"
import { cn } from "@/lib/utils"
import { FlowBreakdownCard } from "./flow-breakdown-card"
import type { CashFlowInsight, CashFlowTotals, FlowBucket } from "@/lib/cash/cash-flow"

const TONE: Record<CashFlowInsight["tone"], { row: string; icon: string; Icon: typeof Info }> = {
  good:    { row: "border-emerald-200 bg-emerald-50", icon: "text-emerald-700", Icon: TrendingUp },
  bad:     { row: "border-rose-200 bg-rose-50",       icon: "text-rose-700",    Icon: TrendingDown },
  warn:    { row: "border-amber-200 bg-amber-50",     icon: "text-amber-700",   Icon: AlertTriangle },
  neutral: { row: "border-slate-200 bg-slate-50",     icon: "text-slate-600",   Icon: Info },
}

export function CashFlowInsightsDialog({
  open,
  onOpenChange,
  periodLabel,
  totals,
  insights,
  inBuckets,
  outBuckets,
  breakdownTotals,
  breakdownScope = "period",
  warnings,
  notes,
  fmtMoney,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  periodLabel: string
  totals: CashFlowTotals
  insights: CashFlowInsight[]
  /**
   * Full breakdowns, not a top-N slice — this dialog is where they live now.
   * ALL TIME, unlike the period figures above them: where the money has come
   * from and gone is a question about the business, not about the range someone
   * has selected. The cards are labelled so the two scopes cannot be confused.
   */
  inBuckets: FlowBucket[]
  outBuckets: FlowBucket[]
  /** Totals matching the buckets. Falls back to the period totals. */
  breakdownTotals?: CashFlowTotals
  /**
   * What the buckets actually cover. Poultry builds them over all time; Water
   * fetches its ledger already filtered by the date range, so its buckets are
   * the period. The wording follows this rather than being hardcoded — a card
   * that says "all time" over period data is worse than no label at all.
   */
  breakdownScope?: "period" | "all-time"
  /**
   * Composed by the page, because the links inside are rail-specific
   * (/poultry-cash-accounts vs /water-cash-accounts). Rendered verbatim; pass
   * nothing when there is nothing wrong and the section disappears.
   */
  warnings?: ReactNode
  /**
   * Neutral facts about the figures — not problems. Rendered under their own
   * heading so nothing here reads as something to go and fix.
   */
  notes?: ReactNode
  fmtMoney: (n: number) => string
}) {
  const allTime = breakdownScope === "all-time"
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Lightbulb className="h-5 w-5 text-sky-600" />
            Cash Flow Insights
          </DialogTitle>
          <DialogDescription>{periodLabel} — in plain language.</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {/* The three numbers everything else is derived from, stated once. */}
          <div className="grid grid-cols-3 gap-2">
            <Figure label="Money in" value={fmtMoney(totals.moneyIn)} tone="text-emerald-700" />
            <Figure label="Money out" value={fmtMoney(totals.moneyOut)} tone="text-rose-700" />
            <Figure
              label="Net"
              value={`${totals.net > 0 ? "+" : ""}${fmtMoney(totals.net)}`}
              tone={totals.net >= 0 ? "text-emerald-700" : "text-rose-700"}
            />
          </div>

          {/* Anything that makes the figures above less trustworthy goes first.
              Reading "you kept money" before "some spending is missing" would be
              the wrong order to learn it in. */}
          {warnings && (
            <section>
              <SectionLabel>Worth checking first</SectionLabel>
              <div className="space-y-2">{warnings}</div>
            </section>
          )}

          {notes && (
            <section>
              <SectionLabel>About these figures</SectionLabel>
              <div className="space-y-2">{notes}</div>
            </section>
          )}

          <section>
            <SectionLabel>What happened</SectionLabel>
            <div className="space-y-2">
              {insights.map((i) => {
                const tone = TONE[i.tone]
                const Icon = tone.Icon
                return (
                  <div key={i.id} className={cn("rounded-md border p-3", tone.row)}>
                    <div className="flex items-start gap-2">
                      <Icon className={cn("mt-0.5 h-4 w-4 shrink-0", tone.icon)} />
                      <div className="min-w-0">
                        <p className="text-sm font-medium text-slate-900">{i.headline}</p>
                        <p className="mt-0.5 text-xs leading-snug text-slate-600">{i.detail}</p>
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>
          </section>

          <section>
            <SectionLabel>
              Where the money moved{allTime ? " — all time" : ""}
            </SectionLabel>
            {/* Stacked, not side by side. Money out reads UNDER money in so the
                two are compared down the page in the order they net off, and
                each card gets the full width for its labels — side by side, a
                long bucket name truncated at half the dialog. */}
            <div className="grid gap-3">
              <FlowBreakdownCard
                title="Money In by Source" direction="in" buckets={inBuckets}
                total={(breakdownTotals ?? totals).moneyIn} fmtMoney={fmtMoney}
                description={allTime
                  ? "Every payment ever received, whatever the date range above. Transfers between your own accounts are not counted."
                  : "Everything that came in this period. Transfers between your own accounts are not counted."}
                emptyText={allTime ? "No money has come in yet." : "No money came in during this period."}
              />
              <FlowBreakdownCard
                title="Money Out by Use" direction="out" buckets={outBuckets}
                total={(breakdownTotals ?? totals).moneyOut} fmtMoney={fmtMoney}
                description={allTime
                  ? "Everything ever paid out, whatever the date range above. Transfers between your own accounts are not counted."
                  : "Everything that went out this period. Transfers between your own accounts are not counted."}
                emptyText={allTime ? "No money has gone out yet." : "No money went out during this period."}
              />
            </div>
          </section>
        </div>

        <div className="flex justify-end pt-2">
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Close</Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <h3 className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
      {children}
    </h3>
  )
}

function Figure({ label, value, tone }: { label: string; value: string; tone: string }) {
  return (
    <div className="rounded-md border border-slate-200 bg-white p-2.5">
      <div className="text-[11px] leading-tight text-slate-500">{label}</div>
      <div className={cn("text-base font-semibold tabular-nums leading-snug", tone)}>{value}</div>
    </div>
  )
}

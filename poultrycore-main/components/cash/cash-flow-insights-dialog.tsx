"use client"

/**
 * Cash Flow Insights — plain-language answers to the questions an owner
 * actually asks: did we keep money, where did it come from, where did it go.
 *
 * A dumb renderer on purpose. Every sentence comes from buildCashFlowInsights()
 * in lib/cash/cash-flow, which is unit-tested; nothing here computes anything or
 * decides any wording, so the two can never drift.
 */

import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Lightbulb, TrendingUp, TrendingDown, AlertTriangle, Info } from "lucide-react"
import { cn } from "@/lib/utils"
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
  topIn,
  topOut,
  fmtMoney,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  periodLabel: string
  totals: CashFlowTotals
  insights: CashFlowInsight[]
  topIn: FlowBucket[]
  topOut: FlowBucket[]
  fmtMoney: (n: number) => string
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
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

          <div className="grid gap-4 sm:grid-cols-2">
            <SourceList title="Where money came from" buckets={topIn} fmtMoney={fmtMoney}
                        empty="Nothing came in this period." />
            <SourceList title="Where money went" buckets={topOut} fmtMoney={fmtMoney}
                        empty="Nothing went out this period." />
          </div>
        </div>

        <div className="flex justify-end pt-2">
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Close</Button>
        </div>
      </DialogContent>
    </Dialog>
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

function SourceList({
  title, buckets, fmtMoney, empty,
}: { title: string; buckets: FlowBucket[]; fmtMoney: (n: number) => string; empty: string }) {
  return (
    <div>
      <h3 className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">{title}</h3>
      {buckets.length === 0 ? (
        <p className="text-xs text-slate-500">{empty}</p>
      ) : (
        <ul className="space-y-1">
          {buckets.map((b) => (
            <li key={b.key} className="flex items-baseline justify-between gap-2 text-xs">
              <span className="min-w-0 truncate text-slate-700" title={b.label}>{b.label}</span>
              <span className="whitespace-nowrap tabular-nums text-slate-900">{fmtMoney(b.amount)}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

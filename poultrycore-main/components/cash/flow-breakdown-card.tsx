"use client"

/**
 * "Money In by Source" / "Money Out by Use" — one component, two instances.
 *
 * Renders a FlowBucket[] straight from lib/cash/cash-flow. All the arithmetic,
 * including the percentages, is already done: this only decides what it looks
 * like. Keeping it dumb is what lets the numbers be unit-tested.
 */

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { cn } from "@/lib/utils"
import type { FlowBucket } from "@/lib/cash/cash-flow"

export function FlowBreakdownCard({
  title,
  description,
  buckets,
  total,
  direction,
  fmtMoney,
  emptyText,
}: {
  title: string
  description?: string
  buckets: FlowBucket[]
  total: number
  direction: "in" | "out"
  fmtMoney: (n: number) => string
  emptyText: string
}) {
  const positive = direction === "in"

  return (
    <Card className="min-w-0">
      <CardHeader className="pb-2">
        <div className="flex items-baseline justify-between gap-2">
          <CardTitle className="text-base">{title}</CardTitle>
          <span className={cn("text-base font-semibold tabular-nums",
                              positive ? "text-emerald-700" : "text-rose-700")}>
            {fmtMoney(total)}
          </span>
        </div>
        {description && <CardDescription className="text-xs">{description}</CardDescription>}
      </CardHeader>
      <CardContent>
        {buckets.length === 0 ? (
          <p className="py-6 text-center text-sm text-slate-500">{emptyText}</p>
        ) : (
          <ul className="space-y-2.5">
            {buckets.map((b) => (
              <li key={b.key}>
                <div className="flex items-baseline justify-between gap-3">
                  <span className="min-w-0 truncate text-sm text-slate-700" title={b.label}>
                    {b.label}
                    {/* The count used to sit beside the percentage as a bare
                        "· 3", which named nothing. Said here instead, in words. */}
                    <span className="ml-1.5 text-xs text-slate-400">
                      {b.count} {b.count === 1 ? "entry" : "entries"}
                    </span>
                  </span>
                  <span className="whitespace-nowrap text-sm font-medium tabular-nums text-slate-900">
                    {fmtMoney(b.amount)}
                  </span>
                </div>
                <div className="mt-1 flex items-center gap-2">
                  {/* The bar is scaled to the share of the total, so the eye and
                      the number say the same thing. */}
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-100">
                    <div
                      className={cn("h-full rounded-full", positive ? "bg-emerald-500" : "bg-rose-500")}
                      style={{ width: `${Math.max(b.percent, 1)}%` }}
                    />
                  </div>
                  {/* Share of this card's total — stated, because a bare
                      percentage next to a bar invites "percent of what?". */}
                  <span
                    className="w-24 shrink-0 text-right text-[11px] tabular-nums text-slate-500"
                    title={`${b.percent}% of ${positive ? "money in" : "money out"}`}
                  >
                    {b.percent}% of total
                  </span>
                </div>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}

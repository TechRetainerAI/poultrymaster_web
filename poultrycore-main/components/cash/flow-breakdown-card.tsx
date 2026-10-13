"use client"

/**
 * "Money In by Source" / "Money Out by Use" — one component, two instances.
 *
 * Renders a FlowBucket[] straight from lib/cash/cash-flow. All the arithmetic,
 * including the percentages, is already done: this only decides what it looks
 * like. Keeping it dumb is what lets the numbers be unit-tested.
 */

import type { ReactNode } from "react"
import { ChevronRight } from "lucide-react"
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
  className,
  onSelect,
}: {
  title: string
  description?: string
  buckets: FlowBucket[]
  total: number
  direction: "in" | "out"
  fmtMoney: (n: number) => string
  emptyText: string
  /** For the caller's grid, not for restyling the card. The Feed tracker lays
   *  five of these out as one uniform block and passes `h-full` so each fills
   *  its stretched cell; a card with fewer buckets than its neighbour would
   *  otherwise sit short inside a full-height cell. */
  className?: string
  /** Makes each row a button that opens what is behind it (Egg tracker). */
  onSelect?: (bucket: FlowBucket) => void
}) {
  const positive = direction === "in"
  // One bucket is 100% of itself. The bar fills end to end and the percentage
  // repeats the total in the header, so both are dropped and the row is left to
  // say the one thing there is to say: what it was, and how much.
  const single = buckets.length === 1

  return (
    <Card className={cn("min-w-0", className)}>
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
                <BucketRow onSelect={onSelect ? () => onSelect(b) : undefined} positive={positive}>
                <div className="flex items-baseline justify-between gap-3">
                  <span className="min-w-0 truncate text-sm text-slate-700" title={b.label}>
                    {b.label}
                    {/* The count used to sit beside the percentage as a bare
                        "· 3", which named nothing. Said here instead, in words. */}
                    <span className="ml-1.5 text-xs text-slate-400">
                      {b.count} {b.count === 1 ? "entry" : "entries"}
                    </span>
                  </span>
                  <span className="flex items-center gap-1 whitespace-nowrap text-sm font-medium tabular-nums text-slate-900">
                    {fmtMoney(b.amount)}
                    {onSelect && <ChevronRight className="h-4 w-4 text-slate-400" />}
                  </span>
                </div>
                {!single && (
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
                      percentage next to a bar invites "percent of what?". The
                      hover names the card rather than saying "money": the Egg
                      tracker shows the same card counting eggs. */}
                  <span
                    className="w-24 shrink-0 text-right text-[11px] tabular-nums text-slate-500"
                    title={`${b.percent}% of ${title}`}
                  >
                    {b.percent}% of total
                  </span>
                </div>
                )}
                </BucketRow>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}

/** A plain block, or -- when the card can drill in -- a full-width button. */
function BucketRow({ onSelect, positive, children }: { onSelect?: () => void; positive: boolean; children: ReactNode }) {
  if (!onSelect) return <>{children}</>
  return (
    <button
      type="button"
      onClick={onSelect}
      className={cn(
        "-mx-2 block w-[calc(100%+1rem)] rounded-md px-2 py-1 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-1",
        positive ? "hover:bg-emerald-50 focus-visible:outline-emerald-400" : "hover:bg-rose-50 focus-visible:outline-rose-400",
      )}
    >
      {children}
    </button>
  )
}

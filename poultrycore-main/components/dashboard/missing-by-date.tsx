"use client"

// Farm Completeness, "By date": every day in the recent window on which some
// flock has no production record, newest first. When nobody entered anything
// on the 12th, the fix is ONE Batch Production Entry for the 12th with those
// flocks pre-selected -- which is what "Record batch" opens. Clicking a date
// opens its flocks, each with its own single-form Record.
//
// Data: GET /ActivityChecks/production/missing-by-date (migration 334), which
// uses the same eligibility and expected-from rules as every other view.

import { Fragment, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { ChevronDown, ChevronUp, CornerDownRight, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { cn } from "@/lib/utils"
import { getMissingProductionByDate, type MissingProductionByDate } from "@/lib/api/activity-checks"
import {
  batchEntryHref,
  daysAgoLabel,
  formatWeekdayDate,
  groupMissingByDate,
  missingDateHref,
} from "@/lib/activity/completeness"

const WINDOWS = [30, 90] as const
const COLS = 4

export function MissingByDateTable({ businessDate }: { businessDate: string }) {
  const [days, setDays] = useState<number>(WINDOWS[0])
  const [data, setData] = useState<MissingProductionByDate | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState<Set<string>>(() => new Set())

  useEffect(() => {
    let cancelled = false
    setError(null)
    getMissingProductionByDate(businessDate || undefined, days)
      .then((d) => { if (!cancelled) setData(d) })
      .catch((e) => { if (!cancelled) setError(e instanceof Error ? e.message : "Could not load missing days.") })
    return () => { cancelled = true }
  }, [businessDate, days])

  const groups = useMemo(() => groupMissingByDate(data?.entries ?? []), [data])
  const groupsPg = usePagination(groups, 10)
  const toggle = (date: string) =>
    setOpen((prev) => {
      const next = new Set(prev)
      if (next.has(date)) next.delete(date)
      else next.add(date)
      return next
    })

  if (error) return <p className="text-sm text-rose-700">{error}</p>
  if (!data) {
    return <p className="flex items-center gap-1.5 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>
  }

  const maxWindow = WINDOWS[WINDOWS.length - 1]

  return (
    <div className="overflow-x-auto rounded-lg border border-slate-200">
      {/* Phone: Date, Flocks and Action; the unposted batches move under the date. */}
      <table className="w-full text-sm sm:min-w-[36rem]">
        <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
          <tr>
            <th className="px-3 py-2 font-medium">Date</th>
            <th className="px-3 py-2 font-medium"><span className="sm:hidden">Flocks</span><span className="hidden sm:inline">Flocks missing</span></th>
            <th className="hidden px-3 py-2 font-medium sm:table-cell">In an unposted batch</th>
            <th className="px-3 py-2 text-right font-medium">Action</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {groups.length === 0 && (
            <tr><td colSpan={COLS} className="px-3 py-4 text-slate-500">No missing production in the last {data.windowDays} days.</td></tr>
          )}
          {groupsPg.pageItems.map((g) => {
            const isOpen = open.has(g.date)
            const href = batchEntryHref(g.date, g.missing.map((m) => m.flockId))
            const inBatch = g.pendingBatches.reduce((a, b) => a + b.flocks.length, 0)
            return (
              <Fragment key={g.date}>
                <tr
                  className={cn("cursor-pointer hover:bg-slate-50", isOpen && "bg-slate-50")}
                  role="button"
                  tabIndex={0}
                  aria-expanded={isOpen}
                  aria-label={`${isOpen ? "Hide" : "Show"} flocks missing on ${formatWeekdayDate(g.date)}`}
                  onClick={() => toggle(g.date)}
                  onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(g.date) } }}
                >
                  <td className="px-3 py-2 font-medium text-slate-900">
                    <span className="mr-1.5 inline-flex h-5 w-5 items-center justify-center align-middle text-slate-500">
                      {isOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                    </span>
                    {formatWeekdayDate(g.date)}
                    <span className="ml-2 text-xs font-normal text-slate-400">{daysAgoLabel(g.date, data.businessDate)}</span>
                    {g.pendingBatches.length > 0 && (
                      <span className="flex flex-wrap gap-x-2 pl-[1.625rem] text-xs font-normal sm:hidden">
                        {g.pendingBatches.map((b) => (
                          <Link key={b.id} className="text-sky-700 underline" onClick={(e) => e.stopPropagation()}
                            href={missingDateHref(b.flocks[0].flockId, g.date, b.id, b.status)}>
                            batch #{b.id} ({b.flocks.length})
                          </Link>
                        ))}
                      </span>
                    )}
                  </td>
                  <td className="px-3 py-2 tabular-nums text-slate-700">{g.missing.length || "—"}</td>
                  <td className="hidden px-3 py-2 text-slate-600 sm:table-cell">
                    {g.pendingBatches.length === 0 ? "—" : (
                      <span className="flex flex-wrap gap-x-2">
                        {g.pendingBatches.map((b) => (
                          <Link key={b.id} className="text-sky-700 underline" onClick={(e) => e.stopPropagation()}
                            href={missingDateHref(b.flocks[0].flockId, g.date, b.id, b.status)}>
                            batch #{b.id} ({b.flocks.length})
                          </Link>
                        ))}
                      </span>
                    )}
                    {inBatch > 0 && <span className="sr-only">{inBatch} flocks in unposted batches</span>}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2 text-right">
                    {href && (
                      <Button asChild size="sm" variant="outline" className="h-7 px-2.5 text-xs">
                        <Link href={href} onClick={(e) => e.stopPropagation()}>
                          Record batch ({g.missing.length})
                        </Link>
                      </Button>
                    )}
                  </td>
                </tr>
                {isOpen && g.missing.map((m) => (
                  <tr key={`${g.date}-${m.flockId}`} className="bg-slate-50/80">
                    <td className="px-3 py-2 pl-6 text-slate-800 sm:pl-8">
                      <span className="inline-flex items-center gap-1.5">
                        <CornerDownRight className="h-3.5 w-3.5 text-slate-400" /> {m.flockName}
                      </span>
                      <span className="block pl-5 text-xs text-slate-500 sm:hidden">
                        {[m.batchName, m.houseName].filter(Boolean).join(" · ") || "—"}
                      </span>
                    </td>
                    {/* Phone: an empty cell keeps Record under the Action column. */}
                    <td className="px-3 py-2 sm:hidden" />
                    <td colSpan={2} className="hidden px-3 py-2 text-slate-600 sm:table-cell">
                      {[m.batchName, m.houseName].filter(Boolean).join(" · ") || "—"}
                    </td>
                    <td className="px-3 py-2 text-right">
                      <Button asChild size="sm" variant="outline" className="h-7 px-2.5 text-xs">
                        <Link href={missingDateHref(m.flockId, g.date)}>Record</Link>
                      </Button>
                    </td>
                  </tr>
                ))}
              </Fragment>
            )
          })}
          <tr>
            <td colSpan={COLS} className="px-3 py-1.5 text-xs text-slate-500">
              <span className="inline-flex flex-wrap items-center gap-2">
                Last {data.windowDays} days.
                {data.windowDays < maxWindow && (
                  <Button variant="link" size="sm" className="h-auto p-0 text-xs" onClick={() => setDays(maxWindow)}>
                    Look back {maxWindow} days
                  </Button>
                )}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
      {groups.length > 0 && (
        <div className="border-t border-slate-100 px-3 py-2">
          <DataPagination {...groupsPg.paginationProps} />
        </div>
      )}
    </div>
  )
}

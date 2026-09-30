"use client"

// The dropdown under a flock on Farm Completeness: one table row per day this
// flock has no production record in the recent window, newest first, lined up
// under the flock's own columns, each with its own Record button.
//
// The flock row's "Days Missing" is only the CURRENT run (days since the last
// record). These rows also show older gaps -- a flock that missed the 10th,
// recorded the 11th to the 27th and missed today shows both -- because those
// are what someone clearing a backlog needs. Loaded when the flock is opened,
// not with the page.
//
// Renders <tr>s, so it must sit inside the card's <tbody>. COLS must match the
// card's column count.

import { useEffect, useState } from "react"
import Link from "next/link"
import { CornerDownRight, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  getFlockMissingProductionDates,
  type FlockMissingProductionDates,
} from "@/lib/api/activity-checks"
import { daysAgoLabel, formatWeekdayDate, missingDateHref } from "@/lib/activity/completeness"

const COLS = 6
const WINDOWS = [30, 90] as const
const ROW = "bg-slate-50/80"

export function FlockMissingDateRows({ flockId, businessDate }: { flockId: number; businessDate: string }) {
  const [days, setDays] = useState<number>(WINDOWS[0])
  const [data, setData] = useState<FlockMissingProductionDates | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    setError(null)
    getFlockMissingProductionDates(flockId, businessDate || undefined, days)
      .then((d) => { if (!cancelled) setData(d) })
      .catch((e) => { if (!cancelled) setError(e instanceof Error ? e.message : "Could not load the missing days.") })
    return () => { cancelled = true }
  }, [flockId, businessDate, days])

  if (error) {
    return (
      <tr className={ROW}>
        <td colSpan={COLS} className="px-3 py-2 pl-10 text-xs text-rose-700">{error}</td>
      </tr>
    )
  }
  if (!data) {
    return (
      <tr className={ROW}>
        <td colSpan={COLS} className="px-3 py-2 pl-10 text-xs text-slate-500">
          <span className="inline-flex items-center gap-1.5"><Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading missing days…</span>
        </td>
      </tr>
    )
  }

  const n = data.dates.length
  const maxWindow = WINDOWS[WINDOWS.length - 1]

  return (
    <>
      {data.dates.map((d) => {
        const inBatch = d.pendingBatchRecordId != null
        return (
          <tr key={d.date} className={ROW}>
            <td className="px-3 py-2 pl-8 font-medium text-slate-800">
              <span className="inline-flex items-center gap-1.5">
                <CornerDownRight className="h-3.5 w-3.5 text-slate-400" />
                {formatWeekdayDate(d.date)}
              </span>
            </td>
            <td colSpan={3} className="px-3 py-2">
              {inBatch ? (
                <span className="text-sky-800">
                  In batch entry #{d.pendingBatchRecordId} — not posted yet
                </span>
              ) : (
                <span className="text-amber-800">No production record</span>
              )}
            </td>
            <td className="px-3 py-2 text-slate-500">{daysAgoLabel(d.date, data.businessDate)}</td>
            <td className="px-3 py-2 text-right">
              <Button asChild size="sm" variant="outline" className="h-7 px-2.5 text-xs">
                <Link href={missingDateHref(flockId, d.date, d.pendingBatchRecordId, d.pendingBatchStatus)}>
                  {inBatch ? (d.pendingBatchStatus === "Draft" ? "Finish batch" : "Post batch") : "Record"}
                </Link>
              </Button>
            </td>
          </tr>
        )
      })}
      <tr className={ROW}>
        <td colSpan={COLS} className="px-3 py-1.5 pl-8 text-xs text-slate-500">
          <span className="inline-flex flex-wrap items-center gap-2">
            {n === 0
              ? `No missing days in the last ${data.windowDays} days.`
              : `${n} missing day${n === 1 ? "" : "s"} in the last ${data.windowDays} days.`}
            {data.windowDays < maxWindow && (
              <Button variant="link" size="sm" className="h-auto p-0 text-xs" onClick={() => setDays(maxWindow)}>
                Look back {maxWindow} days
              </Button>
            )}
          </span>
        </td>
      </tr>
    </>
  )
}

"use client"

// A date column that shows the entry time without widening the column.
//
// WHY THIS EXISTS
// ---------------
// "17 Sep 2026, 11:56" is about 140px on one line. Most of these tables give the
// date column 100px, so the single-line form overflows into whatever sits next
// to it -- on Expenses that is the description, and the row reads as broken.
//
// Widening the column is the wrong trade: the space would come out of the
// description, which is the column people actually read.
//
// So the two facts are stacked. The date keeps the visual weight it had; the
// time sits under it, smaller and muted, because it IS secondary -- you scan a
// table by day and only look at the time to separate entries within that day.
//
// When there is no real time (a back-dated row with no creation timestamp) the
// second line is not rendered at all, rather than showing a dash. A column of
// dashes draws the eye to the absence of something that was never promised.

import { fmtDateTimeParts } from "@/lib/utils/company-datetime"
import { cn } from "@/lib/utils"

export function DateTimeCell({
  value,
  row,
  className,
}: {
  /** The row's business date column (expenseDate, saleDate, …). */
  value: string | Date | null | undefined
  /** The whole row — the clock time is read off its creation timestamp. */
  row?: string | Date | null | object
  className?: string
}) {
  const { date, time } = fmtDateTimeParts(value, row)
  if (!date) return null

  return (
    <div className={cn("leading-tight", className)}>
      <div className="whitespace-nowrap">{date}</div>
      {time ? (
        <div className="text-[11px] font-normal text-slate-500 whitespace-nowrap">{time}</div>
      ) : null}
    </div>
  )
}

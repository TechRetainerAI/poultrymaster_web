"use client"

// The formatter tables use to render a row's date and time.
//
// Usage in a table cell:
//
//     const { fmt } = useCompanyDateTime()
//     ...
//     <td>{fmt(e.expenseDate, e)}</td>   // "17 Sep 2026, 11:56"
//
// The second argument is the row's creation timestamp and is where the clock
// time comes from — see lib/utils/company-datetime.ts for why the date and the
// time are read from two different columns.
//
// Pass `undefined` for the second argument on a table whose endpoint does not
// return a creation timestamp yet. The cell degrades to the date alone (or to
// the business date's own time, where one was genuinely recorded), and starts
// showing the entry time by itself once the API exposes the column — no change
// needed at the call site.

import { useCallback } from "react"
import { useBusinessDate } from "@/hooks/use-business-date"
import {
  formatCompanyDateTime,
  formatInstant,
} from "@/lib/utils/company-datetime"

export function useCompanyDateTime() {
  // useBusinessDate already caches the company's zone in localStorage and
  // re-fetches when the active company changes, so the first render formats in
  // the right zone rather than flashing UTC.
  const { timeZoneId, isAuthoritative } = useBusinessDate()

  const fmt = useCallback(
    (
      businessDate: string | Date | null | undefined,
      // The row itself is the easiest thing to pass: the formatter finds
      // createdDate / createdAt / dateCreated on it.
      createdAtOrRow?: string | Date | null | object,
    ) => formatCompanyDateTime(businessDate, createdAtOrRow, timeZoneId),
    [timeZoneId],
  )

  /** For an "Entered" / "Recorded at" column: the whole value is one instant. */
  const fmtInstant = useCallback(
    (value: string | Date | null | undefined) => formatInstant(value, timeZoneId),
    [timeZoneId],
  )

  return {
    fmt,
    fmtInstant,
    timeZoneId,
    /** False until the company's zone has been confirmed by the server. */
    isAuthoritative,
  }
}

// Rendering a record's date and time in the COMPANY's timezone.
//
// WHAT THE TABLES SHOW, AND WHY IT COMES FROM TWO COLUMNS
// ======================================================
// The business date and the clock time are two different facts here, stored
// separately, and the tables show both:
//
//   DATE  comes from the business date column (expenseDate, saleDate, ...)
//   TIME  comes from the record's creation timestamp (createdDate / createdAt)
//
// That looks odd until you see the data. `entryTimestamp` (lib/utils/date-key.ts)
// only stamps a real clock time when you record something dated TODAY; anything
// back-dated is stored at midnight, deliberately, because nobody knows what time
// last Tuesday's payment happened. On the live Expenses table that means 184 of
// 185 rows have a business date of exactly 00:00:00.
//
// So appending the business date's own time would print "12:00 AM" on virtually
// every expense. The creation timestamp is the one that always holds a real
// clock reading, and it is what makes two records entered on the same day
// orderable and auditable.
//
// THE TRADE-OFF, STATED PLAINLY
// -----------------------------
// For a back-dated entry the date and the time describe different events: a
// purchase dated last Tuesday, keyed in this morning, reads "Tue 9 Sep, 11:56".
// That is the agreed behaviour, not an oversight. Where the distinction matters,
// show `formatEnteredAt()` in its own column instead.
//
// WHY THE DATE IS NEVER TIMEZONE-CONVERTED
// ========================================
// The business date is a LABEL for a business day, not an instant. It is stored
// as midnight, so converting it through any zone west of UTC rolls it back a
// day: 2026-09-17T00:00:00Z shown in America/New_York is 16 Sep, 8pm -- the
// off-by-one that has bitten every date filter in this codebase. The date part
// is therefore taken from the string directly, with no Date object involved.
//
// The TIME is the opposite: a real instant, so it IS converted to the company's
// zone. Those two rules pulling in opposite directions is the whole point of the
// business-date-vs-event-time distinction.

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

/**
 * Parse a timestamp the API sent us.
 *
 * The Farm API has no JSON date converter configured, and the underlying columns
 * are `timestamp without time zone`, so .NET serialises them with NO offset:
 * "2026-09-17T11:56:00.295985". JavaScript parses a date-time string without an
 * offset as LOCAL time -- but the stored value is UTC (the database session runs
 * in UTC, so every now() on this platform wrote a UTC instant).
 *
 * Left alone, that means the time is read as local and then converted again for
 * display: correct in Ghana by coincidence, an hour or five out anywhere else.
 * So a bare timestamp gets an explicit 'Z'.
 *
 * A value that already carries an offset (or a trailing Z) is left exactly as
 * it is -- those are already unambiguous.
 */
export function parseServerTimestamp(value: string | Date | null | undefined): Date | null {
  if (!value) return null
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value

  const s = value.trim()
  if (!s) return null

  // Already zoned: ...Z, ...+01:00, ...-0500
  const hasZone = /[Zz]$/.test(s) || /[+-]\d{2}:?\d{2}$/.test(s)
  const iso = hasZone ? s : `${s.replace(" ", "T")}Z`

  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? null : d
}

/**
 * The date part of a business date, as stored, with no timezone conversion.
 * Returns "" for anything unparseable so a table cell degrades to empty rather
 * than to "Invalid Date".
 */
export function businessDatePart(value: string | Date | null | undefined): string {
  if (!value) return ""
  if (value instanceof Date) {
    // A Date has already lost the distinction, so read it back in the zone it
    // was built in. Callers should pass the raw string wherever possible.
    const y = value.getFullYear()
    const m = String(value.getMonth() + 1).padStart(2, "0")
    const d = String(value.getDate()).padStart(2, "0")
    return `${y}-${m}-${d}`
  }
  // "2026-09-17T00:00:00" / "2026-09-17 00:00:00" / "2026-09-17"
  const m = value.trim().match(/^(\d{4})-(\d{2})-(\d{2})/)
  return m ? `${m[1]}-${m[2]}-${m[3]}` : ""
}

/** "2026-09-17" -> "17 Sep 2026". Returns "" for an empty key. */
export function formatDateKey(key: string): string {
  const m = key.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return ""
  return `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}`
}

/** The clock time of a real instant, in the company's zone. "" if unavailable. */
export function formatTimeInZone(
  instant: Date | null,
  timeZoneId: string,
  opts?: { seconds?: boolean },
): string {
  if (!instant) return ""
  try {
    return new Intl.DateTimeFormat("en-GB", {
      timeZone: timeZoneId || "UTC",
      hour: "2-digit",
      minute: "2-digit",
      ...(opts?.seconds ? { second: "2-digit" } : {}),
      hour12: false,
    }).format(instant)
  } catch {
    // An unknown zone id throws. Fall back to UTC rather than dropping the time.
    return new Intl.DateTimeFormat("en-GB", {
      timeZone: "UTC",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(instant)
  }
}

/**
 * Pull the creation timestamp off a row, whatever it happens to be called.
 *
 * The column naming is not consistent across this schema -- `createdDate`,
 * `createdAt` and `dateCreated` all appear, and the `sale` table has BOTH
 * `createddate` and `datecreated`. Rather than making every one of the ~57 table
 * call sites know which name its own endpoint uses, they pass the row and this
 * finds it.
 *
 * Order matters: createdDate first, because that is the name the majority of the
 * financial tables use.
 */
export function createdTimestampOf(row: unknown): string | null {
  if (!row || typeof row !== "object") return null
  const r = row as Record<string, unknown>

  // Exact match first -- the common case, and cheap.
  for (const key of CREATED_KEYS) {
    const v = r[key]
    if (typeof v === "string" && v.trim()) return v
  }

  // Then case-insensitively. ASP.NET Core serialises camelCase by default, but
  // not every endpoint on this platform goes through the same pipeline, and a
  // PascalCase "CreatedAt" would otherwise be invisible here -- the table would
  // silently drop back to showing the date alone, which is exactly the bug that
  // is hard to notice.
  const lowered = new Map<string, unknown>()
  for (const k of Object.keys(r)) lowered.set(k.toLowerCase(), r[k])
  for (const key of CREATED_KEYS) {
    const v = lowered.get(key.toLowerCase())
    if (typeof v === "string" && v.trim()) return v
  }
  return null
}

const CREATED_KEYS = ["createdDate", "createdAt", "dateCreated", "createdOn"] as const

/**
 * What a table cell shows: "17 Sep 2026, 11:56".
 *
 * @param businessDate the row's business date column (expenseDate, saleDate, …)
 * @param createdAt    the row's creation timestamp, if the API returns one
 * @param timeZoneId   the company's IANA zone
 *
 * Falls back in this order, so it can be adopted everywhere immediately and
 * improves on its own as endpoints start returning a creation timestamp:
 *
 *   1. creation timestamp        -- a real clock reading, always present once exposed
 *   2. the business date's OWN time, when it is not midnight
 *      (Water Sales stores a genuine time on all 47 rows, so those need no
 *      creation column to show something true)
 *   3. date only                 -- nothing truthful to add
 *
 * It never invents "00:00": a midnight business date with no creation timestamp
 * prints the date alone.
 */
export function formatCompanyDateTime(
  businessDate: string | Date | null | undefined,
  // Either the creation timestamp itself, or the whole row to read it from --
  // see createdTimestampOf for why passing the row is usually easier.
  createdAtOrRow: string | Date | null | undefined | object,
  timeZoneId: string,
): string {
  const datePart = formatDateKey(businessDatePart(businessDate))
  if (!datePart) return ""

  const createdAt =
    createdAtOrRow && typeof createdAtOrRow === "object" && !(createdAtOrRow instanceof Date)
      ? createdTimestampOf(createdAtOrRow)
      : (createdAtOrRow as string | Date | null | undefined)

  const created = parseServerTimestamp(createdAt)
  if (created) {
    const t = formatTimeInZone(created, timeZoneId)
    return t ? `${datePart}, ${t}` : datePart
  }

  // No creation timestamp. Use the business date's own time, but only if it is
  // a real one -- midnight here means "no time was recorded", not "00:00".
  if (typeof businessDate === "string" && !/T?00:00:00(\.0+)?$/.test(businessDate.trim())) {
    const own = parseServerTimestamp(businessDate)
    if (own) {
      const t = formatTimeInZone(own, timeZoneId)
      if (t && t !== "00:00") return `${datePart}, ${t}`
    }
  }

  return datePart
}

/**
 * "17 Sep 2026, 11:56" for a pure instant — use this for an "Entered" or
 * "Recorded at" column, where the whole value is the creation event and there is
 * no business date involved.
 */
export function formatInstant(
  value: string | Date | null | undefined,
  timeZoneId: string,
): string {
  const d = parseServerTimestamp(value)
  if (!d) return ""
  const key = new Intl.DateTimeFormat("en-CA", {
    timeZone: timeZoneId || "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d)
  return `${formatDateKey(key)}, ${formatTimeInZone(d, timeZoneId)}`
}

// ---------------------------------------------------------------------------
// The call-site-friendly entry point.
// ---------------------------------------------------------------------------

/**
 * The active company's timezone, read from the cache that useBusinessDate keeps
 * in localStorage.
 *
 * WHY A CACHE READ RATHER THAN A HOOK
 * -----------------------------------
 * Table cells are not the only place dates are rendered: CSV and PDF export
 * helpers format them too, and those are plain functions where a React hook
 * cannot be called. Requiring a hook would also mean threading
 * `useCompanyDateTime()` into ~57 components by hand, with a real chance of
 * putting one inside a loop or a nested helper.
 *
 * A company's timezone changes approximately never, so caching it is safe in a
 * way that caching a business DATE would not be. useBusinessDate refreshes the
 * cache on every mount and whenever the active company changes.
 *
 * Before the first fetch completes the answer is UTC — identical to the stored
 * values, and identical to the company's own zone for 83 of the 84 companies on
 * this database. Components that need it to be reactive should use
 * useCompanyDateTime() instead.
 */
export const COMPANY_TZ_CACHE_PREFIX = "company_tz:"

/** Read one company's cached zone. Null when nothing is cached yet. */
export function cachedCompanyTimeZone(farmId: string): string | null {
  try {
    return localStorage.getItem(COMPANY_TZ_CACHE_PREFIX + farmId)
  } catch {
    // Private browsing or blocked storage. Not worth failing a table over.
    return null
  }
}

/** Record a company's zone so plain (non-React) formatters can read it. */
export function cacheCompanyTimeZone(farmId: string, timeZoneId: string): void {
  try {
    localStorage.setItem(COMPANY_TZ_CACHE_PREFIX + farmId, timeZoneId)
  } catch {
    /* ignore */
  }
}

export function currentCompanyTimeZone(): string {
  if (typeof window === "undefined") return "UTC"
  try {
    const farmId = localStorage.getItem("farmId")
    if (!farmId) return "UTC"
    return cachedCompanyTimeZone(farmId) || "UTC"
  } catch {
    return "UTC"
  }
}

/**
 * What table cells call: `fmtDateTime(e.expenseDate, e)` -> "17 Sep 2026, 11:56".
 *
 * Pass the whole row as the second argument; the creation timestamp is found on
 * it regardless of whether the endpoint calls it createdDate, createdAt or
 * dateCreated. A row with no creation timestamp degrades to the date alone
 * rather than printing a midnight that was never recorded.
 */
export function fmtDateTime(
  businessDate: string | Date | null | undefined,
  row?: string | Date | null | object,
): string {
  return formatCompanyDateTime(businessDate, row, currentCompanyTimeZone())
}

/** An "Entered" / "Recorded at" value, where the whole thing is one instant. */
export function fmtInstant(value: string | Date | null | undefined): string {
  return formatInstant(value, currentCompanyTimeZone())
}

/**
 * The value a table should sort a date column by.
 *
 * THE PROBLEM
 * -----------
 * Sorting on the business date alone leaves every row recorded on the same day
 * tied -- and most business dates are stored at midnight, so on a busy day that
 * is the whole table. The tie then resolves in whatever order the rows happened
 * to arrive, which is why a sale entered a minute ago did not appear at the top.
 *
 * THE RULE
 * --------
 * Business date first, entry time second. A back-dated entry stays in its own
 * day rather than jumping to the top because it was typed today -- the day is
 * what the row is ABOUT, the time is only how rows within that day are ordered.
 *
 * The tiebreaker is the entry's TIME OF DAY, not its full instant. That keeps
 * the business date strictly dominant (a single number cannot hold both a day
 * index and a millisecond instant without losing precision). The one case it
 * orders differently from absolute time is two rows for the SAME business date
 * created either side of midnight -- rare, and the day they belong to is still
 * right.
 */
export function businessSortValue(
  businessDate: string | Date | null | undefined,
  row?: string | Date | null | object,
): number {
  const key = businessDatePart(businessDate)
  const dayMs = key ? Date.parse(key + "T00:00:00Z") : 0
  if (Number.isNaN(dayMs)) return 0

  const createdAt =
    row && typeof row === "object" && !(row instanceof Date)
      ? createdTimestampOf(row)
      : (row as string | Date | null | undefined)

  // Fall back to the business date's own time when there is no creation
  // timestamp -- for the tables that genuinely record one (Water Sales), that is
  // still a real ordering.
  const instant = parseServerTimestamp(createdAt) ?? parseServerTimestamp(businessDate)
  const timeOfDay = instant ? ((instant.getTime() % 86400000) + 86400000) % 86400000 : 0
  return dayMs + timeOfDay
}

/**
 * The same value as fmtDateTime, split so a narrow column can stack the two
 * lines instead of overflowing.
 *
 * "17 Sep 2026, 11:56" needs roughly 140px on one line. Several tables give the
 * date column 100px, so on those the single-line form pushes into the next
 * column and the row looks broken. Stacking keeps the column at its original
 * width and puts the time where it reads as secondary information, which is
 * what it is.
 *
 * `time` is "" when there is no real one -- render nothing rather than a
 * placeholder, so a table of back-dated rows does not grow a column of dashes.
 */
export function fmtDateTimeParts(
  businessDate: string | Date | null | undefined,
  row?: string | Date | null | object,
): { date: string; time: string } {
  const full = fmtDateTime(businessDate, row)
  if (!full) return { date: "", time: "" }
  const at = full.lastIndexOf(", ")
  return at === -1
    ? { date: full, time: "" }
    : { date: full.slice(0, at), time: full.slice(at + 2) }
}


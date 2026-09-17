"use client"

// The active company's business date — what a date field should default to.
//
// Use this instead of `new Date()`, `Date.now()`, or `toISOString().slice(0,10)`
// anywhere you are choosing which business DAY a new record belongs to. Those
// all answer with the BROWSER's day, which is a different question: an owner in
// New York at 8pm gets yesterday's date for a farm in Ghana, records a sale
// against the wrong day, and nothing complains until a daily closing disagrees
// with what someone remembers.
//
// THE LOADING PROBLEM, AND WHY THE FALLBACK IS WHAT IT IS
// ======================================================
// The authoritative date comes from the server, so there is a moment before it
// arrives when a form still has to render something. Three options:
//
//   1. Render the browser's date.       Reintroduces the exact bug, silently.
//   2. Render nothing until loaded.     Every date field in the platform blinks.
//   3. Render the browser's CLOCK read  <- this
//      through the company's ZONE.
//
// (3) is right whenever the browser's clock is roughly correct, which is almost
// always, and it is right ACROSS THE ZONE BOUNDARY, which is the actual bug.
// It is only wrong if the device clock is itself wrong by hours. The server
// value replaces it as soon as it lands, and `isAuthoritative` says which one
// you are looking at, so a form that must not guess can wait.
//
// The zone is cached in localStorage per company because a company's timezone
// changes approximately never, while its business date changes daily -- so the
// zone is safe to cache and the date is not. Caching the date would be how a
// form ends up defaulting to yesterday.

import { useEffect, useState } from "react"
import { getCompanyTimeContext, type CompanyTimeContext } from "@/lib/api/company-time"
import { getUserContext } from "@/lib/api/config"

// The cache is owned by lib/utils/company-datetime.ts, because the plain
// (non-React) table formatters read from it too. Two copies of the key would be
// two chances to change one and not the other.
import {
  cachedCompanyTimeZone as cachedZone,
  cacheCompanyTimeZone as cacheZone,
} from "@/lib/utils/company-datetime"

/**
 * Today in `timeZone`, as "yyyy-MM-dd", from the browser's clock.
 *
 * en-CA is used because it formats as yyyy-MM-dd natively — building the string
 * from getFullYear/getMonth on a Date would read the BROWSER's zone back out
 * and undo the conversion.
 */
export function todayInZone(timeZone: string): string {
  try {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date())
  } catch {
    // An unknown zone id would throw. UTC is the honest fallback and matches
    // what the server does for a company with no timezone set.
    return new Date().toISOString().slice(0, 10)
  }
}

export interface UseBusinessDate {
  /** "yyyy-MM-dd". Always usable — see the note on isAuthoritative. */
  businessDate: string
  /**
   * True once the value came from the server. While false the date was computed
   * from the browser's clock read through the company's zone: right unless the
   * device clock is itself wrong. Gate a submit on this only where being a day
   * out would be unrecoverable.
   */
  isAuthoritative: boolean
  /** The company's IANA zone, e.g. "Africa/Accra". */
  timeZoneId: string
  /**
   * False means the zone was guessed from the company's currency by migration
   * 298 and nobody has confirmed it. Somewhere in Setup should ask.
   */
  timeZoneConfirmed: boolean
  isLoading: boolean
  context: CompanyTimeContext | null
}

export function useBusinessDate(): UseBusinessDate {
  const { farmId } = getUserContext()
  const [context, setContext] = useState<CompanyTimeContext | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  // Keyed on farmId so switching company re-fetches rather than showing the
  // previous company's day.
  useEffect(() => {
    if (!farmId) {
      setIsLoading(false)
      return
    }
    let cancelled = false
    setIsLoading(true)
    setContext(null)
    getCompanyTimeContext()
      .then((c) => {
        if (cancelled) return
        setContext(c)
        cacheZone(farmId, c.timeZoneId)
      })
      .catch(() => {
        /* keep the zone-aware fallback below */
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [farmId])

  const fallbackZone = (farmId && cachedZone(farmId)) || "UTC"

  return {
    businessDate: context?.businessDate ?? todayInZone(fallbackZone),
    isAuthoritative: context != null,
    timeZoneId: context?.timeZoneId ?? fallbackZone,
    timeZoneConfirmed: context?.timeZoneConfirmed ?? false,
    isLoading,
    context,
  }
}

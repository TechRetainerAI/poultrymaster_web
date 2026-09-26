// Company time — what day is it, for THIS company?
//
// THE PROBLEM THIS SOLVES
// ----------------------
// Every date field in the platform currently defaults to the BROWSER's idea of
// today. An owner in New York opening the app at 8pm sees a date input filled
// with a day that, for their farm in Ghana, is already over. They record a sale
// against the wrong business day and nothing complains -- the number is right,
// the day is wrong, and it only surfaces when a daily closing or a period
// report disagrees with what someone remembers happening.
//
// So the business date comes from the SERVER, derived from the company's own
// timezone, and the browser's clock is never consulted for it.
//
// WHY NOT JUST USE Intl / toLocaleDateString WITH THE ZONE?
// ---------------------------------------------------------
// Because that still starts from the browser's clock, which can be wrong, and
// because the answer would then be computed in three places (browser, API, SQL)
// using three tz database versions. `fncompany_businessdate` in migration 298
// is the single definition; this module is a client for it.
//
// WHAT THIS IS *NOT* FOR
// ----------------------
// Displaying a timestamp that already happened. A stored OccurredAtUtc renders
// in whatever zone the reader wants; that is a formatting question. This module
// answers the different question of which business DAY a new record belongs to.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// ----- Types -----

export interface CompanyTimeContext {
  farmId: string
  /** IANA id, e.g. "Africa/Accra". Never a fixed offset. */
  timeZoneId: string
  /**
   * False means migration 298 guessed this from the company's currency and
   * nobody has confirmed it. Nothing behaves differently either way — it exists
   * so Setup can prompt.
   */
  timeZoneConfirmed: boolean
  /** Today, for this company, as "yyyy-MM-dd". What a date input should default to. */
  businessDate: string
  /** The company's wall clock right now. */
  companyLocalDateTime: string
  /** The same instant in UTC. */
  utcNow: string
}

export interface CompanyTimeZoneOption {
  timeZoneId: string
  /** Signed, e.g. "+00:00". Today's offset — for a DST zone it changes twice a year. */
  utcOffset: string
  isDst: boolean
}

export interface CompanyTimeZoneUpdateResult {
  timeZoneId: string
  timeZoneConfirmed: boolean
  businessDate: string
}

// ----- Helpers -----

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as T
}

/**
 * The API returns businessDate as "yyyy-MM-dd", but companyLocalDateTime and
 * utcNow are full timestamps. Trim to the date part without going through
 * `new Date()`, which would reinterpret the string in the BROWSER's zone and
 * re-introduce the exact bug this module exists to remove.
 */
export function toDateOnly(isoish: string): string {
  return (isoish ?? "").slice(0, 10)
}

// ----- Calls -----

/**
 * The company's clock. Cheap and safe to call on boot — a company with no
 * timezone answers UTC with timeZoneConfirmed = false rather than failing,
 * because "not set" is a state to render, not an error.
 */
/*
 * `async` is load-bearing, not decoration. activeFarmId() throws, and it is
 * evaluated while the template literal is BUILT -- before jget() is called and
 * before any promise exists. Without `async` that throw is synchronous at the
 * call site, so a caller's `.catch()` is never attached and the error escapes
 * into React's render, blanking the whole app with "Application error: a
 * client-side exception".
 *
 * That is reachable in normal use because the callers guard on the auth STORE's
 * activeFarmId while activeFarmId() here reads localStorage's farmId. The two
 * can disagree -- store set, localStorage cleared -- and then the guard passes
 * and this throws anyway. `async` turns it into a rejected promise, which the
 * existing .catch() handles by keeping the UTC fallback this module documents.
 */
export const getCompanyTimeContext = async () =>
  jget<CompanyTimeContext>(`/CompanyTime/context?farmId=${encodeURIComponent(activeFarmId())}`)

/** Just today's date, for callers that need nothing else. */
export const getCompanyBusinessDate = async () =>
  jget<{ farmId: string; businessDate: string }>(
    `/CompanyTime/business-date?farmId=${encodeURIComponent(activeFarmId())}`,
  ).then((r) => r.businessDate)

/**
 * The zones a company may choose. Sourced from the same tz catalogue the server
 * validates against, so anything listed here is guaranteed to be accepted.
 */
export const getCompanyTimeZones = (search?: string) => {
  const qs = new URLSearchParams()
  if (search?.trim()) qs.append("search", search.trim())
  const q = qs.toString()
  return jget<CompanyTimeZoneOption[]>(`/CompanyTime/zones${q ? `?${q}` : ""}`)
}

/**
 * Set the company's business timezone and mark it confirmed.
 *
 * Changing it does NOT rewrite any historical business date — only how future
 * defaults, "today", and report boundaries are decided. Say so wherever this is
 * called from, because the opposite is the natural assumption.
 */
export async function setCompanyTimeZone(
  timeZoneId: string,
  updatedBy?: string,
): Promise<CompanyTimeZoneUpdateResult> {
  const farmId = activeFarmId()
  const path = `/CompanyTime/timezone?farmId=${encodeURIComponent(farmId)}`
  const res = await fetch(farmApiUrl(path), {
    method: "PUT",
    headers: { ...getAuthHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ farmId, timeZoneId, updatedBy }),
  })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    // A 400 here carries the stored procedure's own wording, which already
    // explains what to send instead ("Use a region id such as Africa/Accra, not
    // a fixed offset"). Surfacing it beats replacing it with a generic message.
    throw new Error(explainHttpError("PUT", path, res.status, t))
  }
  return (await res.json()) as CompanyTimeZoneUpdateResult
}

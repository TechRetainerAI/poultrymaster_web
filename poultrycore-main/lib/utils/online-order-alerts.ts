/**
 * "A new online order has come in" — the unread count on All Orders.
 *
 * An order placed from the QR page arrives without anybody touching a till, so
 * unless a member of staff happens to be looking at the Orders screen at that
 * moment, nothing tells them it exists. This puts a count on the All Orders row
 * in both the sidebar and the Orders & Kitchen menu, and tints that row while
 * the count is above zero.
 *
 * ## What "unseen" means
 *
 * Online orders whose id is higher than the highest one this device has already
 * had on screen. Opening All Orders marks everything currently listed as seen,
 * which clears the badge.
 *
 * ## Why an order id rather than a timestamp
 *
 * The obvious design is a "last looked at" time, and it is wrong here. Order
 * timestamps come back from the API without a timezone marker, so comparing them
 * against an instant we recorded in the browser silently drifts by the offset
 * between the server's clock and the viewer's — the badge would either never
 * appear or never clear, depending on which side of UTC you sit. Order ids are a
 * database sequence: monotonic, timezone-free, and directly comparable.
 *
 * A date range is still passed to the API, but only to keep the response small.
 * It never decides what counts as unseen.
 *
 * ## Why one shared poller
 *
 * The sidebar and the top nav both display this count and are both on screen at
 * once. Two independent hooks would mean two timers and two requests a minute
 * for one number. This is a module-level store with a single timer that runs
 * only while something is subscribed to it.
 *
 * Nothing here is a security boundary, and nothing is authoritative — it is a
 * hint that there is something to look at. Every failure degrades to "no badge".
 */

import { useEffect, useSyncExternalStore } from "react"
import { listOrders, listPendingOnlineOrders, type Order } from "@/lib/api/restaurant"

const SEEN_KEY = "pm.restaurant.onlineorders.seen.v1"

/** Slow on purpose. This is a nudge, not a live feed. */
const POLL_MS = 60_000

/**
 * How far back to ask for orders. Only bounds the payload. Two days rather than
 * one so an order placed just before midnight is still counted by the morning
 * shift.
 */
const WINDOW_DAYS = 2

/** An order is "online" when it carries a source; a walk-in has none. */
const isOnline = (o: Order) => Boolean(o.onlineSource)

/* ── the watermark, per restaurant ────────────────────────────────────────── */

type SeenByFarm = Record<string, number>

function readSeen(): SeenByFarm {
  try {
    if (typeof window === "undefined") return {}
    const raw = window.localStorage.getItem(SEEN_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === "object" ? (parsed as SeenByFarm) : {}
  } catch {
    // Blocked, unavailable, or corrupt. See lib/utils/guest-profile.ts for why
    // this is guarded rather than trusted: the accessor itself can throw.
    return {}
  }
}

function writeSeen(next: SeenByFarm): void {
  try {
    if (typeof window === "undefined") return
    window.localStorage.setItem(SEEN_KEY, JSON.stringify(next))
  } catch {
    /* Losing the badge is acceptable; breaking the sidebar is not. */
  }
}

function lastSeenId(farmId: string): number {
  if (!farmId) return 0
  const v = readSeen()[farmId]
  return typeof v === "number" && Number.isFinite(v) ? v : 0
}

/**
 * Mark every online order in `orders` as seen. Called by the All Orders page
 * once its list has loaded, so the badge clears from the act of looking.
 *
 * Takes the orders actually on screen rather than "now": marking a moment would
 * also dismiss an order that arrived while the page was loading and is not in
 * the list the user is looking at.
 */
export function markOnlineOrdersSeen(farmId: string, orders: Order[]): void {
  if (!farmId) return
  const highest = orders.reduce((max, o) => (isOnline(o) && o.orderId > max ? o.orderId : max), 0)
  if (highest <= lastSeenId(farmId)) return
  writeSeen({ ...readSeen(), [farmId]: highest })
  void refresh()
}

/* ── the shared count ─────────────────────────────────────────────────────── */

/**
 * Two different numbers, because they answer two different questions.
 *
 * `unseen`  — online orders nobody has had on screen. A notification: it clears
 *             by looking, and belongs on All Orders.
 * `pending` — online orders still waiting to be accepted or rejected. A workload:
 *             looking at it changes nothing, only acting on it does, so it
 *             belongs on New Guest Orders and must NOT clear on view.
 *
 * Getting these the same way round would be the obvious mistake — a to-do count
 * that silently empties because somebody glanced at the screen.
 */
export interface OnlineOrderCounts {
  unseen: number
  pending: number
}

const NONE: OnlineOrderCounts = { unseen: 0, pending: 0 }

/**
 * Cached, and only replaced when a value actually changes. useSyncExternalStore
 * compares snapshots by identity: returning a fresh object each call would spin
 * React in an infinite re-render.
 */
let counts: OnlineOrderCounts = NONE
let farm = ""
let enabled = false
let timer: ReturnType<typeof setInterval> | null = null
let inFlight = false
const subscribers = new Set<() => void>()

function emit(next: OnlineOrderCounts): void {
  if (next.unseen === counts.unseen && next.pending === counts.pending) return
  counts = next
  subscribers.forEach(fn => { try { fn() } catch { /* a bad subscriber must not stop the rest */ } })
}

function windowStart(): string {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() - (WINDOW_DAYS - 1))
  return d.toISOString()
}

async function refresh(): Promise<void> {
  if (!enabled || !farm || inFlight) return
  // Nothing to show a badge on while the tab is in the background, and polling
  // there is pure waste.
  if (typeof document !== "undefined" && document.hidden) return
  inFlight = true
  try {
    const seen = lastSeenId(farm)
    // Two calls rather than deriving both from one list: the pending tray is not
    // date-bounded, and an order left unaccepted over a weekend would fall out
    // of the window the unseen count uses and silently stop being counted.
    // Settled together so one slow response does not stall the other.
    const [recent, pending] = await Promise.all([
      listOrders(undefined, undefined, windowStart()),
      listPendingOnlineOrders(),
    ])
    emit({
      unseen: recent.filter(o => isOnline(o) && o.orderId > seen).length,
      pending: pending.length,
    })
  } catch {
    // Signed out, no active company, or the API is down. A nav badge is not
    // worth an error in the console on every page, and the previous counts are
    // left alone rather than being wrongly cleared to zero.
  } finally {
    inFlight = false
  }
}

/**
 * The pending tray already fetches this list every 10 seconds. Let it hand the
 * number straight over rather than making us fetch it again a minute later: the
 * badge then drops as the card leaves the screen, and a stale to-do count never
 * sends staff back to an empty tray.
 *
 * Ignored unless a Restaurant is active, so it cannot be used to force a count
 * onto a company that should not have one.
 */
export function reportPendingCount(n: number): void {
  if (!enabled || !farm) return
  emit({ ...counts, pending: Math.max(0, n) })
}

function stopTimer(): void {
  if (timer !== null) { clearInterval(timer); timer = null }
}

function startTimer(): void {
  stopTimer()
  if (!enabled || !farm || subscribers.size === 0) return
  timer = setInterval(() => { void refresh() }, POLL_MS)
}

/**
 * Switching company must not carry the previous restaurant's count over.
 *
 * Called from an effect, which runs *after* the first subscribe — so this is
 * also where the wake listeners get attached for a Restaurant, and torn down
 * again the moment the user switches to any other company type.
 */
function configure(nextFarm: string, nextEnabled: boolean): void {
  if (nextFarm === farm && nextEnabled === enabled) return
  const farmChanged = nextFarm !== farm
  farm = nextFarm
  enabled = nextEnabled
  if (farmChanged || !enabled) emit(NONE)
  if (enabled && subscribers.size > 0) attachWakeListeners()
  else detachWakeListeners()
  startTimer()
  void refresh()
}

/**
 * Staff leave the tab open all day and come back to it, so re-check on return
 * rather than making them wait out the rest of the minute.
 *
 * Attached lazily on first subscribe and removed on the last unsubscribe, rather
 * than at import time. This module is imported by the sidebar, which every
 * company type renders — Poultry, Water, Generic and Hotel must not acquire two
 * window listeners because a Restaurant feature happens to live in the bundle.
 */
const onWake = () => { void refresh() }

function attachWakeListeners(): void {
  if (typeof window === "undefined") return
  window.addEventListener("focus", onWake)
  document.addEventListener("visibilitychange", onWake)
}

function detachWakeListeners(): void {
  if (typeof window === "undefined") return
  window.removeEventListener("focus", onWake)
  document.removeEventListener("visibilitychange", onWake)
}

function subscribe(fn: () => void): () => void {
  // A non-Restaurant company never reaches the network, the timer, or the
  // listeners: it subscribes for the snapshot and nothing else runs.
  subscribers.add(fn)
  if (subscribers.size === 1 && enabled) attachWakeListeners()
  startTimer()
  void refresh()
  return () => {
    subscribers.delete(fn)
    if (subscribers.size === 0) { stopTimer(); detachWakeListeners() }
  }
}

/* ── the hook ─────────────────────────────────────────────────────────────── */

/**
 * Both counts: online orders not yet seen, and online orders still waiting to be
 * accepted.
 *
 * Returns zeroes for every non-Restaurant company, so the callers — which are
 * shared across all five company types — can call it unconditionally.
 */
export function useOnlineOrderCounts(farmId: string | null, isRestaurant: boolean): OnlineOrderCounts {
  const active = Boolean(isRestaurant && farmId)

  useEffect(() => { configure(active ? (farmId as string) : "", active) }, [farmId, active])

  return useSyncExternalStore(
    subscribe,
    () => (active ? counts : NONE),
    () => NONE,   // server render: no localStorage, no badge
  )
}

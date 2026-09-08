/**
 * Remembering a guest between orders, without a login system.
 *
 * A customer who scans the QR code has no account. Making them retype their
 * name, phone and email on every visit is the single most tedious thing about
 * the flow, and without somewhere to keep a tracking token they also lose the
 * ability to check "is my food ready?" the moment they close the tab.
 *
 * This stores both in `localStorage`, on the customer's own device:
 *
 *   - a **profile**  - name, phone, email, shared across restaurants, because a
 *     person's own contact details do not change per venue;
 *   - an **order history** - keyed per restaurant, because the tracking tokens,
 *     order numbers and prices belong to one venue and showing another
 *     restaurant's orders would be nonsense.
 *
 * ## What this deliberately is not
 *
 * It is **not** a login. It is bound to one browser on one device: clearing site
 * data, switching browser, or using private mode loses it. That is understood and
 * accepted for now - the alternative that survives a browser switch requires the
 * customer to identify themselves on the new device (an emailed link), which is a
 * later phase.
 *
 * Nothing here is a security boundary. The tracking token is already the only
 * credential needed to view an order, exactly as it was before; this just saves
 * the customer from having to keep the tab open.
 *
 * ## Why every call is wrapped
 *
 * `localStorage` is not merely "sometimes empty" - the accessor itself **throws**
 * in some contexts (Safari private mode historically, browsers configured to
 * block site data, and inside embedded webviews). A page whose menu fails to
 * render because a convenience feature could not read a cache would be a far
 * worse bug than the one this solves, so every read and write is guarded and
 * every failure degrades to "no saved details".
 */

const PROFILE_KEY = "pm.restaurant.guest.profile.v1"
const ORDERS_KEY = "pm.restaurant.guest.orders.v1"

/** Keep the list useful, not archival. Old tokens resolve to nothing anyway. */
const MAX_ORDERS_PER_FARM = 8
const MAX_AGE_DAYS = 30

export interface GuestProfile {
  name?: string
  phone?: string
  email?: string
  /** When these details were last confirmed by placing an order. */
  savedAt?: string
}

export interface GuestOrderRef {
  orderNumber: string
  trackingToken: string
  total: number
  orderType: string
  placedAt: string
}

/* ── storage plumbing ─────────────────────────────────────────────────────── */

function readJson<T>(key: string, fallback: T): T {
  try {
    if (typeof window === "undefined") return fallback
    const raw = window.localStorage.getItem(key)
    if (!raw) return fallback
    const parsed = JSON.parse(raw)
    return (parsed ?? fallback) as T
  } catch {
    // Unavailable, blocked, or corrupt. Corrupt is worth surviving too: a bad
    // value should never be able to permanently break the page for a customer.
    return fallback
  }
}

function writeJson(key: string, value: unknown): void {
  try {
    if (typeof window === "undefined") return
    window.localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // Full, blocked or unavailable. Losing the convenience is acceptable;
    // failing the order is not.
  }
}

/* ── profile ──────────────────────────────────────────────────────────────── */

export function loadGuestProfile(): GuestProfile {
  const p = readJson<GuestProfile>(PROFILE_KEY, {})
  // Guard against a hand-edited or partially-written value: only keep strings.
  return {
    name: typeof p.name === "string" ? p.name : undefined,
    phone: typeof p.phone === "string" ? p.phone : undefined,
    email: typeof p.email === "string" ? p.email : undefined,
    savedAt: typeof p.savedAt === "string" ? p.savedAt : undefined,
  }
}

/** Merges, so clearing the optional email does not wipe a saved phone number. */
export function saveGuestProfile(next: GuestProfile): void {
  const merged: GuestProfile = {
    ...loadGuestProfile(),
    ...Object.fromEntries(Object.entries(next).filter(([, v]) => v !== undefined && v !== "")),
    savedAt: new Date().toISOString(),
  }
  writeJson(PROFILE_KEY, merged)
}

export function hasGuestProfile(p: GuestProfile): boolean {
  return Boolean(p.name?.trim() || p.phone?.trim() || p.email?.trim())
}

/* ── order history, per restaurant ────────────────────────────────────────── */

type OrdersByFarm = Record<string, GuestOrderRef[]>

function isFresh(o: GuestOrderRef): boolean {
  const t = Date.parse(o.placedAt)
  if (Number.isNaN(t)) return false
  return Date.now() - t < MAX_AGE_DAYS * 24 * 60 * 60 * 1000
}

export function loadGuestOrders(farmId: string): GuestOrderRef[] {
  if (!farmId) return []
  const all = readJson<OrdersByFarm>(ORDERS_KEY, {})
  const list = Array.isArray(all[farmId]) ? all[farmId] : []
  return list
    .filter(o => o && typeof o.trackingToken === "string" && typeof o.orderNumber === "string")
    .filter(isFresh)
    .slice(0, MAX_ORDERS_PER_FARM)
}

export function rememberGuestOrder(farmId: string, order: GuestOrderRef): void {
  if (!farmId || !order?.trackingToken) return
  const all = readJson<OrdersByFarm>(ORDERS_KEY, {})
  const existing = Array.isArray(all[farmId]) ? all[farmId] : []
  // Newest first, de-duplicated by token so a double submit cannot list twice.
  const next = [order, ...existing.filter(o => o?.trackingToken !== order.trackingToken)]
    .filter(isFresh)
    .slice(0, MAX_ORDERS_PER_FARM)
  writeJson(ORDERS_KEY, { ...all, [farmId]: next })
}

/**
 * Wipes everything this module stores, for every restaurant. Offered to the
 * customer as "Forget my details": someone ordering on a shared or borrowed
 * phone needs a way out, and a store with no way to clear it is a trap.
 */
export function forgetGuest(): void {
  try {
    if (typeof window === "undefined") return
    window.localStorage.removeItem(PROFILE_KEY)
    window.localStorage.removeItem(ORDERS_KEY)
  } catch {
    /* nothing to do - if we cannot write, there is likely nothing stored */
  }
}

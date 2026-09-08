"use client"

/**
 * The page a guest lands on after scanning the restaurant's QR code.
 *
 * This is the only screen in the product seen by someone who is not a user: no
 * login, no sidebar, no company context. It is also overwhelmingly a phone
 * screen — someone standing in a queue holding their food in the other hand — so
 * it is built mobile-first and the desktop layout is the adaptation, not the
 * other way round.
 *
 * Layout: one column on phones with a fixed cart bar and a bottom sheet; on
 * `lg` the same cart becomes a sticky right-hand rail so a wide screen stops
 * being a narrow phone column stranded in the middle of a monitor.
 *
 * Colour: rose, matching the rest of the restaurant module (rose-600 is the
 * module's primary in ~110 places). This page previously used orange, which
 * belonged to nothing.
 *
 * Everything price- or identity-related is still resolved server-side: the cart
 * sends ids and quantities only, and the QR token is what binds an order to a
 * real scanned code. Nothing in this redesign relaxes that — see migration 248.
 */

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import {
  Loader2, Plus, Minus, ShoppingBag, X, Check, Search, Tag, UtensilsCrossed,
  Clock, Truck, ChevronLeft, Banknote, CreditCard, Smartphone, MapPin, Phone,
  CheckCircle2, AlertCircle, ChefHat, Store, History, UserCheck, Trash2,
} from "lucide-react"
import {
  loadGuestProfile, saveGuestProfile, hasGuestProfile,
  loadGuestOrders, rememberGuestOrder, forgetGuest,
  type GuestOrderRef,
} from "@/lib/utils/guest-profile"
import {
  getPublicMenu, getPublicCategories, getPublicSettings, getPublicProfile, scanQrCode,
  validatePromoCode, placeOnlineOrder, trackOrder,
  type PublicMenuItem, type PublicCategory, type OrderTracking, type PublicRestaurantProfile,
} from "@/lib/api/restaurant"

interface CartItem {
  menuItemId: number; name: string; price: number; quantity: number; notes: string
}

/* ══════════════════════════════════════════════════════════════════════════
   Formatting helpers
   ══════════════════════════════════════════════════════════════════════════ */

/**
 * Prices were previously printed as bare numbers ("20.00"), which tells a guest
 * nothing about what they are about to pay. The currency lives on the restaurant
 * profile; when it is missing or not a valid ISO code we fall back to the plain
 * number rather than guessing a symbol and being wrong.
 */
function makeMoney(currency?: string | null) {
  const code = (currency || "").trim().toUpperCase()
  const valid = /^[A-Z]{3}$/.test(code)
  return (n: number) => {
    const v = Number.isFinite(n) ? n : 0
    if (valid) {
      try {
        return new Intl.NumberFormat(undefined, {
          style: "currency", currency: code, minimumFractionDigits: 2, maximumFractionDigits: 2,
        }).format(v)
      } catch { /* unknown code on this runtime; fall through */ }
    }
    return v.toFixed(2)
  }
}

/**
 * Opening hours are stored as plain "HH:mm" strings with no timezone, so this is
 * a presentational hint only — never a gate. Returns null when the hours are
 * missing or unparseable, and the caller then shows nothing at all rather than
 * claiming a restaurant is closed when it is not.
 */
function openState(opening?: string | null, closing?: string | null): { open: boolean; label: string } | null {
  const parse = (s?: string | null) => {
    const m = /^(\d{1,2}):(\d{2})/.exec((s || "").trim())
    if (!m) return null
    const h = Number(m[1]), min = Number(m[2])
    if (h > 23 || min > 59) return null
    return h * 60 + min
  }
  const from = parse(opening), to = parse(closing)
  if (from === null || to === null) return null
  const now = new Date()
  const mins = now.getHours() * 60 + now.getMinutes()
  // A closing time earlier than the opening time means the kitchen runs past
  // midnight, so the open window wraps around the end of the day.
  const open = from <= to ? mins >= from && mins < to : mins >= from || mins < to
  return { open, label: `${opening}–${closing}` }
}

/* ══════════════════════════════════════════════════════════════════════════
   Full-screen states (loading / not found / closed)
   ══════════════════════════════════════════════════════════════════════════ */

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-[100dvh] items-center justify-center bg-[#faf7f6] p-5">
      <div className="w-full max-w-sm rounded-3xl border border-stone-200/80 bg-white p-7 text-center shadow-[0_1px_3px_rgba(0,0,0,0.04),0_12px_32px_-12px_rgba(0,0,0,0.12)]">
        {children}
      </div>
    </div>
  )
}

function StateIcon({ children, tone = "rose" }: { children: React.ReactNode; tone?: "rose" | "amber" | "stone" }) {
  const tones = {
    rose: "bg-rose-50 text-rose-600 ring-rose-100",
    amber: "bg-amber-50 text-amber-600 ring-amber-100",
    stone: "bg-stone-100 text-stone-500 ring-stone-200",
  }
  return (
    <div className={`mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-2xl ring-8 ${tones[tone]}`}>
      {children}
    </div>
  )
}

/** A skeleton rather than a spinner: the shape of what is coming reads as fast. */
function MenuSkeleton() {
  return (
    <div className="min-h-[100dvh] bg-[#faf7f6]">
      <div className="h-44 bg-gradient-to-br from-rose-600 to-rose-700 sm:h-52" />
      <div className="mx-auto max-w-6xl px-4 pt-5">
        <div className="mb-5 flex gap-2">
          {[64, 88, 72, 80].map((w, i) => <Skeleton key={i} className="h-9 rounded-full" style={{ width: w }} />)}
        </div>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-3 xl:grid-cols-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="overflow-hidden rounded-2xl border border-stone-200/80 bg-white">
              <Skeleton className="aspect-[4/3] w-full rounded-none" />
              <div className="space-y-2 p-3">
                <Skeleton className="h-4 w-4/5" />
                <Skeleton className="h-4 w-1/3" />
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

/* ══════════════════════════════════════════════════════════════════════════
   Menu card
   ══════════════════════════════════════════════════════════════════════════ */

function MenuCard({
  item, qty, money, onAdd, onDec,
}: {
  item: PublicMenuItem
  qty: number
  money: (n: number) => string
  onAdd: () => void
  onDec: () => void
}) {
  const [broken, setBroken] = useState(false)
  const hasPhoto = Boolean(item.imageUrl) && !broken

  return (
    <div
      className={`group relative flex flex-col overflow-hidden rounded-2xl border bg-white transition-all duration-200 ${
        qty > 0
          ? "border-rose-300 shadow-[0_0_0_1px_rgb(253,164,175),0_8px_24px_-12px_rgba(225,29,72,0.35)]"
          : "border-stone-200/80 shadow-[0_1px_2px_rgba(0,0,0,0.04)] hover:border-stone-300 hover:shadow-[0_8px_24px_-14px_rgba(0,0,0,0.25)]"
      }`}
    >
      {/* Tapping the photo adds — the whole tile is the primary action on a phone. */}
      <button
        type="button"
        onClick={onAdd}
        aria-label={`Add ${item.name} to your order`}
        className="relative block aspect-[4/3] w-full overflow-hidden bg-gradient-to-br from-rose-50 to-stone-100 text-left"
      >
        {hasPhoto ? (
          <img
            src={item.imageUrl as string}
            alt=""
            loading="lazy"
            onError={() => setBroken(true)}
            className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-[1.06]"
          />
        ) : (
          <span className="flex h-full w-full items-center justify-center">
            <UtensilsCrossed className="h-8 w-8 text-rose-200" />
          </span>
        )}

        {/* Dietary marks sit on the photo so the text block below stays calm. */}
        <span className="pointer-events-none absolute left-2 top-2 flex flex-wrap gap-1">
          {item.isVegan ? (
            <span className="rounded-full bg-emerald-600/95 px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wide text-white shadow-sm">Vegan</span>
          ) : item.isVegetarian ? (
            <span className="rounded-full bg-emerald-600/95 px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wide text-white shadow-sm">Veg</span>
          ) : null}
          {item.spicyLevel > 0 && (
            <span className="rounded-full bg-black/55 px-1.5 py-0.5 text-[9px] leading-tight text-white shadow-sm backdrop-blur-sm">
              {"🌶️".repeat(Math.min(item.spicyLevel, 3))}
            </span>
          )}
        </span>

        {qty > 0 && (
          <span className="absolute right-2 top-2 flex h-6 min-w-[24px] items-center justify-center rounded-full bg-rose-600 px-1.5 text-xs font-bold text-white shadow-md">
            {qty}
          </span>
        )}
      </button>

      <div className="flex flex-1 flex-col p-3">
        <h3 className="line-clamp-2 text-sm font-semibold leading-snug text-stone-900">{item.name}</h3>
        {item.description && (
          <p className="mt-0.5 line-clamp-1 text-xs text-stone-500">{item.description}</p>
        )}

        {/* Price and the add control share a row only while the control is a
            single round button. A stepper is ~95px wide, which on a 2-column
            phone grid left the price with ~50px and truncated it to "GH…", so
            once an item is in the cart the stepper takes a full row of its own. */}
        <div className="mt-2 flex items-end justify-between gap-2 pt-1">
          <div className="min-w-0">
            <div className="whitespace-nowrap text-[15px] font-bold text-stone-900">{money(item.price)}</div>
            {item.prepTime > 0 && (
              <div className="mt-0.5 flex items-center gap-1 text-[11px] text-stone-400">
                <Clock className="h-3 w-3" /> {item.prepTime} min
              </div>
            )}
          </div>

          {qty === 0 && (
            <button type="button" onClick={onAdd} aria-label={`Add ${item.name} to your order`}
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-rose-600 text-white shadow-sm transition-all hover:bg-rose-700 hover:shadow-md active:scale-95">
              <Plus className="h-4 w-4" />
            </button>
          )}
        </div>

        {qty > 0 && (
          <div className="mt-2 flex items-center justify-between rounded-full bg-rose-50 p-0.5 ring-1 ring-rose-200">
            <button type="button" onClick={onDec} aria-label={`Remove one ${item.name}`}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-rose-700 transition-colors hover:bg-white active:scale-95">
              <Minus className="h-4 w-4" />
            </button>
            <span className="text-sm font-bold tabular-nums text-rose-700">{qty}</span>
            <button type="button" onClick={onAdd} aria-label={`Add another ${item.name}`}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-rose-600 text-white shadow-sm transition-colors hover:bg-rose-700 active:scale-95">
              <Plus className="h-4 w-4" />
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

/* ══════════════════════════════════════════════════════════════════════════
   Page
   ══════════════════════════════════════════════════════════════════════════ */

function RestaurantOrderOnlineContent() {
  const searchParams = useSearchParams()
  const qrToken = searchParams.get("qr")
  const farmIdParam = searchParams.get("farmId") || searchParams.get("r")
  const trackToken = searchParams.get("track")

  const [loading, setLoading] = useState(true)
  const [farmId, setFarmId] = useState("")
  const [tableId, setTableId] = useState<number | null>(null)
  const [tableNumber, setTableNumber] = useState("")
  const [settings, setSettings] = useState<any>(null)
  const [profile, setProfile] = useState<PublicRestaurantProfile | null>(null)
  const [categories, setCategories] = useState<PublicCategory[]>([])
  const [items, setItems] = useState<PublicMenuItem[]>([])
  const [selectedCat, setSelectedCat] = useState<number | null>(null)
  const [search, setSearch] = useState("")
  const [cart, setCart] = useState<CartItem[]>([])
  const [orderType, setOrderType] = useState<string>("")
  const [scrolled, setScrolled] = useState(false)
  const searchRef = useRef<HTMLInputElement>(null)

  /**
   * Saved on this device only - see lib/utils/guest-profile.ts. Read once on
   * mount rather than on every render, because localStorage is synchronous and
   * a page this size re-renders on every keystroke.
   */
  const [recalled, setRecalled] = useState(false)
  const [pastOrders, setPastOrders] = useState<GuestOrderRef[]>([])
  const [pastStatuses, setPastStatuses] = useState<Record<string, string>>({})
  const [historyOpen, setHistoryOpen] = useState(false)

  // Customer info
  const [customerName, setCustomerName] = useState("")
  const [customerPhone, setCustomerPhone] = useState("")
  const [customerEmail, setCustomerEmail] = useState("")
  const [deliveryAddress, setDeliveryAddress] = useState("")

  // Promo
  const [promoCode, setPromoCode] = useState("")
  const [promoResult, setPromoResult] = useState<any>(null)

  // Checkout
  const [cartOpen, setCartOpen] = useState(false)
  const [step, setStep] = useState<"cart" | "details">("cart")
  const [placing, setPlacing] = useState(false)
  const [orderError, setOrderError] = useState<string | null>(null)
  /** How the guest intends to settle. No gateway yet - the choice is only recorded. */
  const [paymentIntent, setPaymentIntent] = useState("Cash")
  const [paymentAmount, setPaymentAmount] = useState("")

  // Tracking
  const [tracking, setTracking] = useState<OrderTracking | null>(null)
  const [trackingToken, setTrackingToken] = useState("")

  useEffect(() => { init() }, [])

  // Prefill from this device. Runs once, before the menu finishes loading, so the
  // checkout is already filled in by the time the guest reaches it.
  useEffect(() => {
    const saved = loadGuestProfile()
    if (!hasGuestProfile(saved)) return
    setCustomerName(saved.name ?? "")
    setCustomerPhone(saved.phone ?? "")
    setCustomerEmail(saved.email ?? "")
    setRecalled(true)
  }, [])

  // Drives the compact sticky header. Passive so it never blocks scrolling.
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 72)
    onScroll()
    window.addEventListener("scroll", onScroll, { passive: true })
    return () => window.removeEventListener("scroll", onScroll)
  }, [])

  async function init() {
    setLoading(true)
    try {
      if (trackToken) {
        const t = await trackOrder(trackToken)
        setTracking(t)
        setTrackingToken(trackToken)
        setLoading(false)
        return
      }

      let fId = farmIdParam || ""
      let venue = true

      if (qrToken) {
        const qr = await scanQrCode(qrToken)
        fId = qr.farmId
        // A restaurant-wide code identifies the venue only - the guest is at the
        // counter, not a table - so it must not claim DineIn.
        venue = qr.codeType === "Restaurant" || !qr.tableId
        setTableId(venue ? null : qr.tableId)
        setTableNumber(venue ? "" : qr.tableNumber)
        setOrderType(venue ? "Takeaway" : "DineIn")
      }

      if (!fId) { setLoading(false); return }

      setFarmId(fId)
      const [s, cats, menu, prof] = await Promise.all([
        getPublicSettings(fId),
        getPublicCategories(fId),
        getPublicMenu(fId),
        // The profile endpoint is newer than the rest of the public API. An older
        // Farm API returns 404 here, and a restaurant mid-setup has no profile
        // row at all - neither is a reason to deny someone their lunch.
        getPublicProfile(fId).catch(() => null),
      ])
      setSettings(s)
      setCategories(cats)
      setItems(menu)
      setProfile(prof)

      if (!qrToken) {
        if (s.allowTakeaway) setOrderType("Takeaway")
        else if (s.allowDelivery) setOrderType("Delivery")
      }
    } catch (e: any) {
      console.error(e)
    } finally { setLoading(false) }
  }

  // Past orders are per restaurant, so they can only be read once the scan has
  // resolved which farm this is.
  useEffect(() => {
    if (!farmId) return
    setPastOrders(loadGuestOrders(farmId))
  }, [farmId])

  /**
   * "Is my food ready?" is the whole point of keeping the history, so the stored
   * orders are resolved to their live status. Only the ones that can still change
   * are re-checked; a completed order is asked about exactly once.
   */
  const refreshPastStatuses = useCallback(async () => {
    if (pastOrders.length === 0) return
    const DONE = ["Completed", "Cancelled", "Refunded", "Served"]
    const open = pastOrders.filter(o => !DONE.includes(pastStatuses[o.trackingToken] ?? ""))
    if (open.length === 0) return
    const results = await Promise.all(open.map(o =>
      trackOrder(o.trackingToken)
        .then(t => [o.trackingToken, t.status] as const)
        .catch(() => null)))   // a token the server no longer knows just stays blank
    const found = results.filter(Boolean) as (readonly [string, string])[]
    if (found.length > 0) setPastStatuses(prev => ({ ...prev, ...Object.fromEntries(found) }))
  }, [pastOrders, pastStatuses])

  useEffect(() => { refreshPastStatuses().catch(() => {}) }, [pastOrders])

  useEffect(() => {
    if (pastOrders.length === 0) return
    const id = setInterval(() => { refreshPastStatuses().catch(() => {}) }, 30_000)
    return () => clearInterval(id)
  }, [pastOrders, refreshPastStatuses])

  const money = useMemo(() => makeMoney(profile?.defaultCurrency), [profile?.defaultCurrency])
  const hours = useMemo(() => openState(profile?.openingTime, profile?.closingTime), [profile?.openingTime, profile?.closingTime])
  const isVenueCode = Boolean(qrToken) && !tableId

  const filteredItems = items.filter(i => {
    if (selectedCat && i.categoryId !== selectedCat) return false
    if (search && !i.name.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })

  const qtyOf = useCallback(
    (id: number) => cart.filter(c => c.menuItemId === id).reduce((n, c) => n + c.quantity, 0),
    [cart],
  )

  function addToCart(item: PublicMenuItem) {
    setCart(prev => {
      const existing = prev.find(c => c.menuItemId === item.menuItemId)
      if (existing) return prev.map(c => c === existing ? { ...c, quantity: c.quantity + 1 } : c)
      return [...prev, { menuItemId: item.menuItemId, name: item.name, price: item.price, quantity: 1, notes: "" }]
    })
  }

  /** Stepping the last one off the card removes the line entirely. */
  function decFromCart(menuItemId: number) {
    setCart(prev => prev.flatMap(c =>
      c.menuItemId === menuItemId
        ? (c.quantity > 1 ? [{ ...c, quantity: c.quantity - 1 }] : [])
        : [c],
    ))
  }

  function updateQty(idx: number, delta: number) {
    setCart(cart.map((c, i) => i === idx ? { ...c, quantity: Math.max(1, c.quantity + delta) } : c))
  }
  function removeItem(idx: number) { setCart(cart.filter((_, i) => i !== idx)) }

  const cartCount = cart.reduce((s, c) => s + c.quantity, 0)
  const subtotal = cart.reduce((s, c) => s + c.price * c.quantity, 0)
  const deliveryFee = orderType === "Delivery" ? (settings?.deliveryFeeAmount || 0) : 0
  const freeDelivery = settings?.freeDeliveryAbove && subtotal >= settings.freeDeliveryAbove
  const actualDeliveryFee = freeDelivery ? 0 : deliveryFee
  const promoDiscount = promoResult?.valid ? promoResult.calculatedDiscount : 0
  const total = subtotal + actualDeliveryFee - promoDiscount
  const belowMinimum = Boolean(settings?.minOrderAmount) && subtotal < settings.minOrderAmount

  async function applyPromo() {
    if (!promoCode.trim()) return
    try {
      const result = await validatePromoCode(farmId, promoCode, subtotal, orderType === "DineIn" ? "QR" : "Online")
      setPromoResult(result)
    } catch (e: any) { setPromoResult({ valid: false, message: e?.message }) }
  }

  async function handlePlaceOrder() {
    if (cart.length === 0) return
    setOrderError(null)
    setPlacing(true)
    try {
      const result = await placeOnlineOrder(farmId, {
        // The token is what ties this order to a real, scanned code. The server
        // re-resolves it and overrides farm/table from the database, so these
        // fields are a convenience for older clients, not the source of truth.
        qrToken: qrToken || undefined,
        orderType,
        tableId: tableId || undefined,
        tableNumber: tableNumber || undefined,
        customerName: customerName.trim(),
        customerPhone: customerPhone.trim(),
        // Optional. Sent as undefined rather than "" so the column stays NULL
        // instead of holding an empty string that reads as "has an email".
        customerEmail: customerEmail.trim() || undefined,
        covers: 1,
        notes: orderType === "Delivery" ? `Delivery: ${deliveryAddress}` : undefined,
        onlineSource: qrToken ? "QR" : "Web",
        deliveryAddress: orderType === "Delivery" ? deliveryAddress : undefined,
        deliveryFee: actualDeliveryFee,
        promoCode: promoResult?.valid ? promoCode : undefined,
        guestPaymentIntent: paymentIntent,
        guestPaymentAmount: paymentAmount.trim() === "" ? total : Number(paymentAmount),
        // Only ids, quantities and notes travel. Names and prices are read from
        // the menu server-side; sending them let a guest set their own prices.
        items: cart.map(c => ({ menuItemId: c.menuItemId, quantity: c.quantity, notes: c.notes || undefined })),
      })
      // Only ever saved after the server has accepted the order, so a device
      // never remembers details from an attempt that failed.
      saveGuestProfile({
        name: customerName.trim(),
        phone: customerPhone.trim(),
        email: customerEmail.trim() || undefined,
      })
      rememberGuestOrder(farmId, {
        orderNumber: result.orderNumber,
        trackingToken: result.trackingToken,
        total,
        orderType,
        placedAt: new Date().toISOString(),
      })
      setPastOrders(loadGuestOrders(farmId))

      setTrackingToken(result.trackingToken)
      setTracking(await trackOrder(result.trackingToken))
      setCartOpen(false)
      setCart([])
    } catch (e: any) {
      setOrderError(e?.message || "We could not send your order. Please try again or ask a member of staff.")
    } finally { setPlacing(false) }
  }

  const refreshTracking = useCallback(async () => {
    if (trackingToken) setTracking(await trackOrder(trackingToken))
  }, [trackingToken])

  // Keep the guest's screen live without them having to do anything. Terminal
  // states cannot change again, so stop rather than poll a forgotten tab forever.
  useEffect(() => {
    if (!trackingToken) return
    const done = ["Completed", "Cancelled", "Refunded", "Served"]
    if (tracking && done.includes(tracking.status)) return
    const id = setInterval(() => { refreshTracking().catch(() => {}) }, 10_000)
    return () => clearInterval(id)
  }, [trackingToken, tracking?.status, refreshTracking])

  /* -- Loading ---------------------------------------------------------- */
  if (loading) return <MenuSkeleton />

  /* -- Tracking --------------------------------------------------------- */
  // A guest order sits at 'Placed' until staff accept it, so "Placed" means
  // "sent, waiting to be confirmed" rather than "the kitchen has it".
  if (tracking) {
    const TRACKING_STEPS = ["Placed", "Confirmed", "Preparing", "Ready"]
    const trackingStep = tracking.status === "Served" || tracking.status === "Completed"
      ? TRACKING_STEPS.length - 1
      : TRACKING_STEPS.indexOf(tracking.status)
    const awaitingConfirmation = tracking.status === "Placed"
    const wasRejected = tracking.status === "Cancelled"

    return (
      <div className="min-h-[100dvh] bg-[#faf7f6] px-4 py-8">
        <div className="mx-auto w-full max-w-md">
          <div className="overflow-hidden rounded-3xl border border-stone-200/80 bg-white shadow-[0_1px_3px_rgba(0,0,0,0.04),0_18px_44px_-20px_rgba(0,0,0,0.18)]">
            <div className={`px-6 py-7 text-center text-white ${
              wasRejected ? "bg-gradient-to-br from-stone-600 to-stone-700" : "bg-gradient-to-br from-rose-600 to-rose-700"
            }`}>
              <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-white/15 ring-8 ring-white/10 backdrop-blur-sm">
                {wasRejected ? <AlertCircle className="h-7 w-7" /> : <CheckCircle2 className="h-7 w-7" />}
              </div>
              <p className="text-xs font-medium uppercase tracking-[0.14em] text-white/70">
                {wasRejected ? "Not accepted" : awaitingConfirmation ? "Order sent" : "Your order"}
              </p>
              <h1 className="mt-1 text-2xl font-bold tracking-tight">{tracking.orderNumber}</h1>
              {profile?.restaurantName && (
                <p className="mt-1 text-sm text-white/80">{profile.restaurantName}</p>
              )}
            </div>

            <div className="space-y-5 p-6">
              {wasRejected ? (
                <div className="rounded-2xl bg-stone-50 p-4 text-left ring-1 ring-stone-200">
                  <div className="font-semibold text-stone-900">This order was not accepted</div>
                  <p className="mt-1 text-sm text-stone-600">
                    {tracking.cancelReason || "The restaurant could not take this order."}
                  </p>
                  <p className="mt-2 text-sm text-stone-600">
                    Please speak to a member of staff{tracking.tableNumber ? ` - you are at table ${tracking.tableNumber}` : ""}.
                  </p>
                </div>
              ) : (
                <>
                  {awaitingConfirmation && (
                    <div className="flex gap-3 rounded-2xl bg-amber-50 p-4 text-left ring-1 ring-amber-200/70">
                      <Loader2 className="mt-0.5 h-4 w-4 shrink-0 animate-spin text-amber-600" />
                      <p className="text-sm text-amber-900">
                        <span className="font-semibold">Sent to the restaurant.</span> A member of staff is
                        confirming your order - it will start being prepared once they accept it.
                      </p>
                    </div>
                  )}

                  <div className="flex items-start justify-between px-1">
                    {TRACKING_STEPS.map((label, i) => {
                      const done = i <= trackingStep
                      return (
                        <div key={label} className="flex flex-1 items-start">
                          <div className="flex w-full flex-col items-center gap-1.5">
                            <div className={`flex h-9 w-9 items-center justify-center rounded-full text-xs font-bold transition-all duration-300 ${
                              done ? "bg-rose-600 text-white shadow-[0_0_0_4px_rgba(225,29,72,0.12)]" : "bg-stone-100 text-stone-400"
                            }`}>
                              {done ? <Check className="h-4 w-4" /> : i + 1}
                            </div>
                            <span className={`text-[10px] font-medium ${done ? "text-rose-700" : "text-stone-400"}`}>{label}</span>
                          </div>
                          {i < TRACKING_STEPS.length - 1 && (
                            <div className={`mt-4 h-0.5 flex-1 rounded-full transition-colors duration-300 ${
                              i < trackingStep ? "bg-rose-600" : "bg-stone-200"
                            }`} />
                          )}
                        </div>
                      )
                    })}
                  </div>
                </>
              )}

              <dl className="space-y-2 rounded-2xl bg-stone-50 p-4 text-sm">
                <div className="flex justify-between">
                  <dt className="text-stone-500">Type</dt>
                  <dd className="font-medium text-stone-900">
                    {tracking.orderType}{tracking.tableNumber ? ` · Table ${tracking.tableNumber}` : ""}
                  </dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-stone-500">Total</dt>
                  <dd className="font-bold text-stone-900">{money(tracking.totalAmount)}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-stone-500">Placed</dt>
                  <dd className="font-medium text-stone-900">{new Date(tracking.createdAt).toLocaleTimeString()}</dd>
                </div>
                {tracking.estimatedReadyTime && (
                  <div className="flex justify-between">
                    <dt className="text-stone-500">Est. ready</dt>
                    <dd className="font-medium text-stone-900">{new Date(tracking.estimatedReadyTime).toLocaleTimeString()}</dd>
                  </div>
                )}
              </dl>

              <p className="text-center text-xs text-stone-400">This page updates automatically.</p>
            </div>
          </div>
        </div>
      </div>
    )
  }

  /* -- No restaurant ---------------------------------------------------- */
  if (!farmId || !settings) return (
    <Shell>
      <StateIcon tone="stone"><Search className="h-7 w-7" /></StateIcon>
      <h1 className="text-lg font-bold text-stone-900">Restaurant not found</h1>
      <p className="mt-2 text-sm text-stone-500">
        That code didn&apos;t match a restaurant. Please scan the QR code again, or ask a member of staff for help.
      </p>
    </Shell>
  )

  /* -- Closed ----------------------------------------------------------- */
  // Two different situations were both showing "currently unavailable", which told
  // nobody anything: the restaurant has never switched online ordering on, versus it
  // is on but paused right now. Separate them, and say what to do.
  if (!settings.isEnabled || !settings.acceptingOrders) return (
    <Shell>
      {!settings.isEnabled ? (
        <>
          <StateIcon tone="stone"><Store className="h-7 w-7" /></StateIcon>
          <h1 className="text-lg font-bold text-stone-900">
            {profile?.restaurantName
              ? `${profile.restaurantName} isn't taking phone orders yet`
              : "This restaurant isn't taking phone orders yet"}
          </h1>
          <p className="mt-2 text-sm text-stone-500">Please order at the counter.</p>
          <p className="mt-5 rounded-xl bg-stone-50 px-3 py-2.5 text-xs text-stone-400">
            Staff: switch on <span className="font-medium text-stone-600">Online Settings &rarr; Enable online ordering</span> and save.
          </p>
        </>
      ) : (
        <>
          <StateIcon tone="amber"><Clock className="h-7 w-7" /></StateIcon>
          <h1 className="text-lg font-bold text-stone-900">Orders are paused right now</h1>
          <p className="mt-2 text-sm text-stone-500">
            {settings.pausedReason || "The kitchen has stopped taking new orders for the moment. Please ask a member of staff."}
          </p>
          {hours && <p className="mt-4 text-xs text-stone-400">Usual hours {hours.label}</p>}
        </>
      )}
    </Shell>
  )

  /* -- Cart / checkout panel (shared by the mobile sheet and desktop rail) -- */
  const PAYMENT_METHODS = [
    { value: "MobileMoney", label: "Mobile Money", icon: Smartphone },
    { value: "CreditCard", label: "Card", icon: CreditCard },
    { value: "Cash", label: "Cash", icon: Banknote },
  ]

  /**
   * Only ever blocks a NON-EMPTY address that is clearly malformed. Blank stays
   * perfectly valid - the field is optional, and the server drops empty strings
   * to NULL. The check is deliberately loose: exhaustive email regexes reject
   * real addresses, and the API applies [EmailAddress] anyway.
   */
  const emailLooksWrong = customerEmail.trim() !== "" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail.trim())

  const canSubmit = cart.length > 0 && customerName.trim() !== "" && customerPhone.trim() !== ""
    && !emailLooksWrong
    && (orderType !== "Delivery" || deliveryAddress.trim() !== "")

  const totalsBlock = (
    <div className="space-y-1.5 text-sm">
      <div className="flex justify-between text-stone-500">
        <span>Subtotal</span><span className="tabular-nums text-stone-700">{money(subtotal)}</span>
      </div>
      {orderType === "Delivery" && (
        <div className="flex justify-between text-stone-500">
          <span>Delivery</span>
          <span className="tabular-nums text-stone-700">
            {freeDelivery ? <span className="text-emerald-600">Free</span> : money(actualDeliveryFee)}
          </span>
        </div>
      )}
      {promoDiscount > 0 && (
        <div className="flex justify-between text-emerald-600">
          <span>Promo · {promoCode}</span><span className="tabular-nums">-{money(promoDiscount)}</span>
        </div>
      )}
      <div className="flex items-baseline justify-between border-t border-stone-200 pt-2 text-base">
        <span className="font-semibold text-stone-900">Total</span>
        <span className="text-lg font-bold tabular-nums text-stone-900">{money(total)}</span>
      </div>
    </div>
  )

  const cartLines = (
    <div className="space-y-2.5">
      {cart.map((line, idx) => (
        <div key={line.menuItemId} className="flex items-center gap-3 rounded-2xl bg-stone-50/80 p-2.5">
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold text-stone-900">{line.name}</div>
            <div className="text-xs text-stone-500">{money(line.price)} each</div>
          </div>
          <div className="flex items-center gap-0.5 rounded-full bg-white p-0.5 ring-1 ring-stone-200">
            <button type="button" onClick={() => updateQty(idx, -1)} aria-label="Decrease quantity"
              className="flex h-7 w-7 items-center justify-center rounded-full text-stone-600 hover:bg-stone-100 active:scale-95">
              <Minus className="h-3.5 w-3.5" />
            </button>
            <span className="min-w-[16px] text-center text-sm font-bold tabular-nums">{line.quantity}</span>
            <button type="button" onClick={() => updateQty(idx, 1)} aria-label="Increase quantity"
              className="flex h-7 w-7 items-center justify-center rounded-full text-stone-600 hover:bg-stone-100 active:scale-95">
              <Plus className="h-3.5 w-3.5" />
            </button>
          </div>
          <div className="w-16 shrink-0 text-right text-sm font-bold tabular-nums text-stone-900">
            {money(line.price * line.quantity)}
          </div>
          <button type="button" onClick={() => removeItem(idx)} aria-label={`Remove ${line.name}`}
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-stone-300 hover:bg-rose-50 hover:text-rose-600">
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      ))}
    </div>
  )

  const detailsForm = (
    <div className="space-y-4">
      <div className="flex gap-2">
        <Input placeholder="Promo code" value={promoCode}
          onChange={e => setPromoCode(e.target.value.toUpperCase())}
          className="h-11 rounded-xl border-stone-200 bg-stone-50" />
        <Button type="button" variant="outline" onClick={applyPromo}
          className="h-11 shrink-0 rounded-xl border-stone-200 px-4">
          <Tag className="h-4 w-4" />
        </Button>
      </div>
      {promoResult && (
        <div className={`rounded-xl px-3 py-2 text-sm ${
          promoResult.valid ? "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200"
                            : "bg-rose-50 text-rose-700 ring-1 ring-rose-200"}`}>
          {promoResult.message}
        </div>
      )}

      {recalled && (
        <div className="flex items-start gap-2.5 rounded-2xl bg-emerald-50 p-3 ring-1 ring-emerald-200/70">
          <UserCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
          <div className="min-w-0 flex-1 text-xs text-emerald-900">
            <span className="font-semibold">Filled in from last time.</span> Change anything
            that is out of date.
            {/* Someone on a borrowed or shared phone needs a way out. */}
            <button type="button"
              onClick={() => {
                forgetGuest()
                setCustomerName(""); setCustomerPhone(""); setCustomerEmail("")
                setPastOrders([]); setRecalled(false)
              }}
              className="ml-1 whitespace-nowrap font-semibold underline underline-offset-2 hover:text-emerald-700">
              Not you?
            </button>
          </div>
        </div>
      )}

      {/* Both are required: for a guest with no account this is the only way the
          restaurant can reach them about the order. */}
      <div className="space-y-3">
        <div>
          <Label className="text-xs font-medium text-stone-600">Your name <span className="text-rose-600">*</span></Label>
          <Input value={customerName} onChange={e => setCustomerName(e.target.value)}
            placeholder="So we know whose order this is" autoComplete="name"
            className="mt-1.5 h-11 rounded-xl border-stone-200 bg-stone-50" />
        </div>
        <div>
          <Label className="text-xs font-medium text-stone-600">Phone number <span className="text-rose-600">*</span></Label>
          <Input type="tel" inputMode="tel" autoComplete="tel" value={customerPhone}
            onChange={e => setCustomerPhone(e.target.value)}
            placeholder="In case we need to check something"
            className="mt-1.5 h-11 rounded-xl border-stone-200 bg-stone-50" />
        </div>
        {/* Optional on purpose: a guest at a counter often has no email to hand,
            and the phone number is already the contact of record. Marked
            "Optional" in the label rather than left ambiguous, so nobody stalls
            wondering whether it is required. */}
        <div>
          <Label className="text-xs font-medium text-stone-600">
            Email address <span className="font-normal text-stone-400">(optional)</span>
          </Label>
          <Input type="email" inputMode="email" autoComplete="email" value={customerEmail}
            onChange={e => setCustomerEmail(e.target.value)}
            aria-invalid={emailLooksWrong || undefined}
            placeholder="For your receipt"
            className={`mt-1.5 h-11 rounded-xl bg-stone-50 ${
              emailLooksWrong ? "border-rose-400 focus-visible:ring-rose-500/30" : "border-stone-200"}`} />
          {emailLooksWrong && (
            <p className="mt-1.5 text-xs text-rose-600">
              That email address does not look right. Leave it blank if you would rather not give one.
            </p>
          )}
        </div>
        {orderType === "Delivery" && (
          <div>
            <Label className="text-xs font-medium text-stone-600">Delivery address <span className="text-rose-600">*</span></Label>
            <Input value={deliveryAddress} onChange={e => setDeliveryAddress(e.target.value)}
              placeholder="Where should we bring it?" autoComplete="street-address"
              className="mt-1.5 h-11 rounded-xl border-stone-200 bg-stone-50" />
          </div>
        )}
      </div>

      {/* Tappable cards rather than a dropdown: three options, and a select on a
          phone costs an extra tap and a native picker for no benefit. */}
      <div>
        <Label className="text-xs font-medium text-stone-600">How will you pay? <span className="text-rose-600">*</span></Label>
        <div className="mt-1.5 grid grid-cols-3 gap-2">
          {PAYMENT_METHODS.map(m => {
            const active = paymentIntent === m.value
            const Icon = m.icon
            return (
              <button key={m.value} type="button" onClick={() => setPaymentIntent(m.value)}
                aria-pressed={active}
                className={`flex flex-col items-center gap-1.5 rounded-2xl border p-3 text-center transition-all active:scale-[0.98] ${
                  active ? "border-rose-500 bg-rose-50 text-rose-700 shadow-[0_0_0_3px_rgba(225,29,72,0.08)]"
                         : "border-stone-200 bg-white text-stone-500 hover:border-stone-300"}`}>
                <Icon className="h-5 w-5" />
                <span className="text-[11px] font-semibold leading-tight">{m.label}</span>
              </button>
            )
          })}
        </div>
      </div>

      <div>
        <Label className="text-xs font-medium text-stone-600">Amount</Label>
        <Input type="number" inputMode="decimal" min={0} step="0.01" value={paymentAmount}
          onChange={e => setPaymentAmount(e.target.value)} placeholder={total.toFixed(2)}
          className="mt-1.5 h-11 rounded-xl border-stone-200 bg-stone-50" />
        {/* Deliberately explicit: nothing is charged here. The gateway is not
            built yet, so this is a record of what the guest intends to hand over,
            and staff still settle the order through the POS. */}
        <p className="mt-1.5 text-xs text-stone-400">
          Nothing is charged now - you settle with the staff. Leave blank to use the order total.
        </p>
      </div>
    </div>
  )

  /**
   * One cart surface, rendered into the mobile sheet and the desktop rail.
   *
   * Deliberately a function that RETURNS JSX, not a component that gets rendered
   * as an element. It was the latter, and because it was declared inside this
   * component its function identity changed on every render - so React saw a new
   * element type on each keystroke, tore the whole subtree down and rebuilt it.
   * The symptom was that every text box lost focus after a single character: you
   * typed one letter, the caret vanished, and you had to click back in for the
   * next one. Calling it inlines the JSX, which reconciles by position and keeps
   * the inputs mounted. Do not "tidy" this back into a component.
   */
  function cartBody(compact = false) {
    return (
      <div className="flex h-full flex-col">
        <div className={`flex-1 space-y-4 overflow-y-auto pb-4 ${compact ? "px-0" : "px-4"}`}>
          {step === "cart" ? (
            <>
              {cartLines}
              {belowMinimum && (
                <div className="rounded-xl bg-amber-50 px-3 py-2 text-sm text-amber-800 ring-1 ring-amber-200/70">
                  Minimum order is {money(settings.minOrderAmount)}. Add {money(settings.minOrderAmount - subtotal)} more.
                </div>
              )}
              {totalsBlock}
            </>
          ) : (
            <>
              {detailsForm}
              {totalsBlock}
            </>
          )}
        </div>

        <div className={`space-y-2 border-t border-stone-200 bg-white pt-3 ${compact ? "px-0" : "px-4"}`}
             style={{ paddingBottom: "max(0.75rem, env(safe-area-inset-bottom))" }}>
          {orderError && (
            <div className="rounded-xl bg-rose-50 px-3 py-2.5 text-sm text-rose-700 ring-1 ring-rose-200">{orderError}</div>
          )}
          {step === "cart" ? (
            <Button onClick={() => setStep("details")} disabled={cart.length === 0 || belowMinimum}
              className="h-12 w-full rounded-2xl bg-rose-600 text-base font-semibold hover:bg-rose-700">
              Continue · {money(total)}
            </Button>
          ) : (
            <>
              <Button onClick={handlePlaceOrder} disabled={placing || !canSubmit || belowMinimum}
                className="h-12 w-full rounded-2xl bg-rose-600 text-base font-semibold hover:bg-rose-700">
                {placing ? <Loader2 className="mr-2 h-5 w-5 animate-spin" /> : <Check className="mr-2 h-5 w-5" />}
                Place order · {money(total)}
              </Button>
              <Button variant="ghost" onClick={() => setStep("cart")}
                className="h-9 w-full rounded-xl text-sm text-stone-500 hover:text-stone-800">
                <ChevronLeft className="mr-1 h-4 w-4" /> Back to order
              </Button>
            </>
          )}
        </div>
      </div>
    )
  }

  /**
   * Rendered twice - once under the search box, once inside the bar that appears
   * on scroll - so the two can never drift apart.
   */
  function categoryRail(extraClass = "") {
    if (categories.length === 0) return null
    const chip = (active: boolean) =>
      `shrink-0 rounded-full px-3.5 py-1.5 text-sm font-medium transition-all ${
        active ? "bg-rose-600 text-white shadow-sm" : "bg-white text-stone-600 ring-1 ring-stone-200 hover:ring-stone-300"}`
    return (
      <div className={`-mx-4 flex gap-2 overflow-x-auto px-4 pb-0.5 [scrollbar-width:none] sm:-mx-6 sm:px-6 [&::-webkit-scrollbar]:hidden ${extraClass}`}>
        <button type="button" onClick={() => setSelectedCat(null)} className={chip(selectedCat === null)}>All</button>
        {categories.map(c => (
          <button key={c.menuCategoryId} type="button" onClick={() => setSelectedCat(c.menuCategoryId)}
            className={chip(selectedCat === c.menuCategoryId)}>
            {c.name}
          </button>
        ))}
      </div>
    )
  }

  /** Send the guest back to the search box rather than duplicating an input. */
  function focusSearch() {
    window.scrollTo({ top: 0, behavior: "smooth" })
    window.setTimeout(() => searchRef.current?.focus(), 350)
  }

  /** Reopen a stored order in the tracking view. */
  async function openPastOrder(o: GuestOrderRef) {
    setHistoryOpen(false)
    try {
      setTrackingToken(o.trackingToken)
      setTracking(await trackOrder(o.trackingToken))
    } catch {
      // The token is older than the server's record, or the order was purged.
      setTrackingToken("")
    }
  }

  const STATUS_TONE: Record<string, string> = {
    Placed: "bg-amber-100 text-amber-800",
    Confirmed: "bg-blue-100 text-blue-800",
    Preparing: "bg-indigo-100 text-indigo-800",
    Ready: "bg-emerald-100 text-emerald-800",
    Served: "bg-emerald-100 text-emerald-800",
    Completed: "bg-stone-100 text-stone-600",
    Cancelled: "bg-rose-100 text-rose-700",
    Refunded: "bg-rose-100 text-rose-700",
  }
  const STATUS_WORDS: Record<string, string> = {
    Placed: "Waiting for the restaurant",
    Confirmed: "Confirmed",
    Preparing: "Being prepared",
    Ready: "Ready for you",
    Served: "Served",
    Completed: "Completed",
    Cancelled: "Not accepted",
  }

  const emptyCart = (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-stone-200 px-4 py-10 text-center">
      <ShoppingBag className="mb-2 h-8 w-8 text-stone-300" />
      <p className="text-sm font-medium text-stone-600">Your order is empty</p>
      <p className="mt-0.5 text-xs text-stone-400">Tap a dish to add it.</p>
    </div>
  )

  /* -- Menu ------------------------------------------------------------- */
  return (
    <div className="min-h-[100dvh] bg-[#faf7f6]">
      {/* Compact bar, revealed once the hero scrolls away. */}
      <div className={`fixed inset-x-0 top-0 z-40 border-b border-stone-200/70 bg-white/85 backdrop-blur-md transition-all duration-300 ${
        scrolled ? "translate-y-0 opacity-100" : "-translate-y-full opacity-0"
      }`}>
        <div className="mx-auto max-w-6xl px-4 pb-2 pt-2.5 sm:px-6">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-rose-600 text-white">
              {profile?.logoUrl ? (
                <img src={profile.logoUrl} alt="" className="h-full w-full object-cover" />
              ) : (
                <UtensilsCrossed className="h-4 w-4" />
              )}
            </div>
            <span className="min-w-0 flex-1 truncate text-sm font-bold text-stone-900">
              {profile?.restaurantName || "Order online"}
            </span>
            <button type="button" onClick={focusSearch} aria-label="Search the menu"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-stone-500 transition-colors hover:bg-stone-100 hover:text-stone-800">
              <Search className="h-4 w-4" />
            </button>
            {cartCount > 0 && (
              <Button size="sm" onClick={() => { setStep("cart"); setCartOpen(true) }}
                className="h-8 shrink-0 rounded-full bg-rose-600 px-3 text-xs font-semibold hover:bg-rose-700 lg:hidden">
                <ShoppingBag className="mr-1.5 h-3.5 w-3.5" /> {cartCount}
              </Button>
            )}
          </div>
          {/* Jumping between courses is the one control worth keeping within
              reach halfway down a long menu. */}
          {categoryRail("mt-2")}
        </div>
      </div>

      {/* Hero.
          Kept deliberately short. At the original size this band ate ~43% of a
          390x844 phone before a single dish was visible, which is the wrong
          trade for a screen whose entire job is the menu. Same information, one
          compact block: identity on the left, everything else as one meta line. */}
      <header className="relative overflow-hidden bg-gradient-to-br from-rose-600 via-rose-600 to-rose-700">
        {/* Soft light bloom - keeps a flat colour field from looking like a solid
            block on a big screen. Decorative only. */}
        <div aria-hidden className="pointer-events-none absolute -right-12 -top-20 h-56 w-56 rounded-full bg-white/10 blur-3xl" />
        <div aria-hidden className="pointer-events-none absolute -bottom-24 -left-8 h-48 w-48 rounded-full bg-rose-400/25 blur-3xl" />

        <div className="relative mx-auto max-w-6xl px-4 py-4 sm:px-6 sm:py-5">
          <div className="flex items-center gap-3">
            <div className="flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-white/15 ring-1 ring-white/25 backdrop-blur-sm sm:h-12 sm:w-12">
              {profile?.logoUrl ? (
                <img src={profile.logoUrl} alt="" className="h-full w-full object-cover"
                  onError={e => { e.currentTarget.style.display = "none" }} />
              ) : (
                <UtensilsCrossed className="h-5 w-5 text-white sm:h-6 sm:w-6" />
              )}
            </div>

            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                <h1 className="truncate text-lg font-bold leading-tight tracking-tight text-white sm:text-2xl">
                  {profile?.restaurantName || "Order online"}
                </h1>
                {isVenueCode ? (
                  <Badge className="shrink-0 border-0 bg-white/20 px-1.5 py-0 text-[9px] font-semibold uppercase tracking-wider text-white backdrop-blur-sm hover:bg-white/20">
                    Skip the queue
                  </Badge>
                ) : tableNumber ? (
                  <Badge className="shrink-0 border-0 bg-white px-1.5 py-0 text-[9px] font-bold uppercase tracking-wider text-rose-700 hover:bg-white">
                    Table {tableNumber}
                  </Badge>
                ) : null}
                {hours && (
                  <span className={`inline-flex shrink-0 items-center gap-1 rounded-full px-1.5 py-0 text-[9px] font-semibold backdrop-blur-sm ${
                    hours.open ? "bg-emerald-400/20 text-emerald-50" : "bg-black/20 text-white/80"
                  }`}>
                    <span className={`h-1 w-1 rounded-full ${hours.open ? "bg-emerald-300" : "bg-white/50"}`} />
                    {hours.open ? "Open" : "Closed"} · {hours.label}
                  </span>
                )}
              </div>

              {/* Cuisine, city and phone collapse onto one line with separators
                  rather than a stacked icon row - three short facts do not need
                  three lines of a phone screen. */}
              <div className="mt-0.5 flex flex-wrap items-center gap-x-1.5 text-[11px] text-white/75 sm:text-xs">
                {[profile?.cuisineType, profile?.city, profile?.phone]
                  .filter(Boolean)
                  .map((v, i, arr) => (
                    <span key={i} className="flex items-center gap-1.5">
                      {v}
                      {i < arr.length - 1 && <span aria-hidden className="text-white/40">·</span>}
                    </span>
                  ))}
              </div>
            </div>
          </div>

          {(settings.welcomeMessage || profile?.description) && (
            <p className="mt-2 line-clamp-1 text-xs leading-snug text-white/80 sm:text-sm">
              {settings.welcomeMessage || profile?.description}
            </p>
          )}

          {/* Only appears once this device has actually ordered here before, so the
              compact hero keeps its height for a first-time guest. */}
          {pastOrders.length > 0 && (
            <button type="button" onClick={() => setHistoryOpen(true)}
              className="mt-2.5 inline-flex items-center gap-1.5 rounded-full bg-white/15 px-3 py-1.5 text-xs font-semibold text-white ring-1 ring-white/25 backdrop-blur-sm transition-colors hover:bg-white/25">
              <History className="h-3.5 w-3.5" />
              My orders ({pastOrders.length})
              {pastOrders.some(o => {
                const st = pastStatuses[o.trackingToken]
                return st && !["Completed", "Cancelled", "Refunded", "Served"].includes(st)
              }) && <span className="ml-0.5 h-2 w-2 rounded-full bg-emerald-300 ring-2 ring-emerald-300/40" />}
            </button>
          )}
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-4 sm:px-6 lg:grid lg:grid-cols-[minmax(0,1fr)_360px] lg:items-start lg:gap-8">
        {/* Menu column */}
        <main className="pb-40 lg:pb-16">
          {/* Order type. A table code is fixed to DineIn by the backend, so the
              choice only appears where there genuinely is one. */}
          {(!qrToken || isVenueCode) && (settings.allowTakeaway || settings.allowDelivery) && (
            <div className="flex gap-2 pt-3">
              {settings.allowTakeaway && (
                <button type="button" onClick={() => setOrderType("Takeaway")}
                  className={`flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold transition-all active:scale-[0.98] ${
                    orderType === "Takeaway" ? "bg-stone-900 text-white shadow-sm" : "bg-white text-stone-600 ring-1 ring-stone-200 hover:ring-stone-300"}`}>
                  <ShoppingBag className="h-4 w-4" /> Takeaway
                </button>
              )}
              {settings.allowDelivery && (
                <button type="button" onClick={() => setOrderType("Delivery")}
                  className={`flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold transition-all active:scale-[0.98] ${
                    orderType === "Delivery" ? "bg-stone-900 text-white shadow-sm" : "bg-white text-stone-600 ring-1 ring-stone-200 hover:ring-stone-300"}`}>
                  <Truck className="h-4 w-4" /> Delivery
                </button>
              )}
            </div>
          )}

          {/* Search + categories, sticky under the compact bar so filtering is
              always one thumb-reach away however far down the menu you are. */}
          {/* Not sticky. `html, body { overflow-x: hidden }` in globals.css (lines
              132-141) makes the body a scroll container, and a sticky descendant of
              a scroll container that is itself the scrolled element never engages -
              this bar scrolled away with the page. That rule is app-wide, so rather
              than change scrolling for poultry/water/hotel to fix one page, the
              category rail is repeated in the fixed bar below and search is one tap
              away from it. */}
          <div className="-mx-4 mt-3 px-4 pb-1 sm:-mx-6 sm:px-6">
            <div className="relative">
              <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-stone-400" />
              <Input ref={searchRef} value={search} onChange={e => setSearch(e.target.value)}
                placeholder="Search the menu..." aria-label="Search the menu"
                className="h-11 rounded-2xl border-stone-200 bg-white pl-10 shadow-sm placeholder:text-stone-400 focus-visible:ring-rose-500/30" />
              {search && (
                <button type="button" onClick={() => setSearch("")} aria-label="Clear search"
                  className="absolute right-3 top-1/2 flex h-6 w-6 -translate-y-1/2 items-center justify-center rounded-full bg-stone-100 text-stone-500 hover:bg-stone-200">
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </div>

            {categoryRail("mt-2.5")}
          </div>

          {filteredItems.length === 0 ? (
            <div className="flex flex-col items-center justify-center rounded-3xl border border-dashed border-stone-200 bg-white/60 px-6 py-20 text-center">
              <UtensilsCrossed className="mb-3 h-10 w-10 text-stone-300" />
              <p className="font-semibold text-stone-700">
                {search || selectedCat ? "Nothing matches that" : "Nothing on the menu yet"}
              </p>
              <p className="mt-1 text-sm text-stone-500">
                {search || selectedCat ? "Try a different search or category." : "Please ask a member of staff."}
              </p>
              {(search || selectedCat) && (
                <Button variant="outline" onClick={() => { setSearch(""); setSelectedCat(null) }}
                  className="mt-4 rounded-full border-stone-200">Clear filters</Button>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3 pt-1 sm:grid-cols-3 sm:gap-4 lg:grid-cols-3 xl:grid-cols-4">
              {filteredItems.map(item => (
                <MenuCard key={item.menuItemId} item={item} qty={qtyOf(item.menuItemId)} money={money}
                  onAdd={() => addToCart(item)} onDec={() => decFromCart(item.menuItemId)} />
              ))}
            </div>
          )}
        </main>

        {/* Desktop cart rail */}
        <aside className="hidden lg:sticky lg:top-20 lg:block lg:pt-5">
          <div className="flex max-h-[calc(100dvh-6rem)] flex-col overflow-hidden rounded-3xl border border-stone-200/80 bg-white shadow-[0_1px_3px_rgba(0,0,0,0.04),0_16px_40px_-24px_rgba(0,0,0,0.2)]">
            <div className="flex items-center justify-between border-b border-stone-200 px-5 py-4">
              <h2 className="text-base font-bold text-stone-900">
                {step === "cart" ? "Your order" : "Your details"}
              </h2>
              {cartCount > 0 && (
                <span className="rounded-full bg-rose-50 px-2 py-0.5 text-xs font-bold text-rose-700">
                  {cartCount} {cartCount === 1 ? "item" : "items"}
                </span>
              )}
            </div>
            <div className="flex-1 overflow-y-auto p-5">
              {cart.length === 0 ? emptyCart : cartBody(true)}
            </div>
          </div>
        </aside>
      </div>

      {/* Mobile cart bar */}
      {cartCount > 0 && (
        <div className="fixed inset-x-0 bottom-0 z-40 lg:hidden">
          <div className="pointer-events-none h-8 bg-gradient-to-t from-[#faf7f6] to-transparent" />
          <div className="border-t border-stone-200 bg-white px-4 pt-3 shadow-[0_-8px_32px_-16px_rgba(0,0,0,0.25)]"
               style={{ paddingBottom: "max(0.75rem, env(safe-area-inset-bottom))" }}>
            <Button onClick={() => { setStep("cart"); setCartOpen(true) }}
              className="flex h-13 w-full items-center justify-between rounded-2xl bg-rose-600 px-4 py-3.5 text-base font-semibold hover:bg-rose-700">
              <span className="flex items-center gap-2">
                <span className="flex h-6 min-w-[24px] items-center justify-center rounded-full bg-white/25 px-1.5 text-xs font-bold">
                  {cartCount}
                </span>
                View order
              </span>
              <span className="tabular-nums">{money(total)}</span>
            </Button>
          </div>
        </div>
      )}

      {/* Recent orders on this device. A sheet at every size, not just mobile:
          it is a short list and a dialog would be more chrome than content. */}
      <Sheet open={historyOpen} onOpenChange={setHistoryOpen}>
        <SheetContent side="bottom" className="flex max-h-[85dvh] flex-col rounded-t-3xl border-stone-200 p-0">
          <SheetHeader className="shrink-0 border-b border-stone-200 px-4 py-3.5">
            <SheetTitle className="flex items-center gap-2 text-left text-base font-bold text-stone-900">
              <History className="h-4 w-4 text-rose-600" /> Your recent orders
            </SheetTitle>
          </SheetHeader>

          <div className="flex-1 space-y-2.5 overflow-y-auto p-4">
            {pastOrders.map(o => {
              const status = pastStatuses[o.trackingToken]
              return (
                <button key={o.trackingToken} type="button" onClick={() => openPastOrder(o)}
                  className="flex w-full items-center gap-3 rounded-2xl border border-stone-200 bg-white p-3 text-left transition-all hover:border-rose-300 hover:shadow-sm active:scale-[0.99]">
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-mono text-sm font-bold text-stone-900">{o.orderNumber}</div>
                    <div className="mt-0.5 text-xs text-stone-500">
                      {o.orderType} &middot; {new Date(o.placedAt).toLocaleDateString()} &middot;{" "}
                      {new Date(o.placedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                    </div>
                    <div className="mt-1.5">
                      {status ? (
                        <span className={`inline-block rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                          STATUS_TONE[status] ?? "bg-stone-100 text-stone-600"}`}>
                          {STATUS_WORDS[status] ?? status}
                        </span>
                      ) : (
                        <span className="inline-block rounded-full bg-stone-100 px-2 py-0.5 text-[11px] text-stone-400">
                          Checking...
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="shrink-0 text-right">
                    <div className="text-sm font-bold tabular-nums text-stone-900">{money(o.total)}</div>
                    <div className="mt-0.5 text-[11px] font-medium text-rose-600">Track</div>
                  </div>
                </button>
              )
            })}
          </div>

          <div className="shrink-0 border-t border-stone-200 px-4 pt-3"
               style={{ paddingBottom: "max(0.75rem, env(safe-area-inset-bottom))" }}>
            <p className="mb-2 text-[11px] leading-snug text-stone-400">
              Saved on this device only, so you don&apos;t have to type your details again.
              They are not shared with anyone.
            </p>
            <Button variant="ghost" onClick={() => {
                forgetGuest()
                setCustomerName(""); setCustomerPhone(""); setCustomerEmail("")
                setPastOrders([]); setPastStatuses({}); setRecalled(false); setHistoryOpen(false)
              }}
              className="h-9 w-full rounded-xl text-sm text-stone-500 hover:text-rose-600">
              <Trash2 className="mr-1.5 h-4 w-4" /> Forget my details on this device
            </Button>
          </div>
        </SheetContent>
      </Sheet>

      {/* Mobile cart sheet */}
      <Sheet open={cartOpen} onOpenChange={o => { setCartOpen(o); if (!o) setStep("cart") }}>
        <SheetContent side="bottom"
          className="flex h-[92dvh] flex-col rounded-t-3xl border-stone-200 p-0 lg:hidden">
          <SheetHeader className="shrink-0 border-b border-stone-200 px-4 py-3.5">
            <SheetTitle className="flex items-center gap-2 text-left text-base font-bold text-stone-900">
              {step === "details" && (
                <button type="button" onClick={() => setStep("cart")} aria-label="Back to order"
                  className="-ml-1 flex h-7 w-7 items-center justify-center rounded-full text-stone-500 hover:bg-stone-100">
                  <ChevronLeft className="h-4 w-4" />
                </button>
              )}
              {step === "cart" ? "Your order" : "Your details"}
              {cartCount > 0 && step === "cart" && (
                <span className="rounded-full bg-rose-50 px-2 py-0.5 text-xs font-bold text-rose-700">{cartCount}</span>
              )}
            </SheetTitle>
          </SheetHeader>
          <div className="flex-1 overflow-hidden pt-4">
            {cart.length === 0 ? <div className="px-4">{emptyCart}</div> : cartBody()}
          </div>
        </SheetContent>
      </Sheet>
    </div>
  )
}

export default function RestaurantOrderOnlinePage() {
  return (
    <Suspense fallback={<MenuSkeleton />}>
      <RestaurantOrderOnlineContent />
    </Suspense>
  )
}

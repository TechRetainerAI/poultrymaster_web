"use client"

import { Suspense, useEffect, useState } from "react"
import { useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, Plus, Minus, ShoppingCart, X, Check, Search, Tag, UtensilsCrossed, Clock, MapPin, Truck } from "lucide-react"
import {
  getPublicMenu, getPublicCategories, getPublicSettings, scanQrCode,
  validatePromoCode, placeOnlineOrder, trackOrder,
  type PublicMenuItem, type PublicCategory, type OrderTracking,
} from "@/lib/api/restaurant"

interface CartItem {
  menuItemId: number; name: string; price: number; quantity: number; notes: string
}

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
  const [categories, setCategories] = useState<PublicCategory[]>([])
  const [items, setItems] = useState<PublicMenuItem[]>([])
  const [selectedCat, setSelectedCat] = useState<number | null>(null)
  const [search, setSearch] = useState("")
  const [cart, setCart] = useState<CartItem[]>([])
  const [orderType, setOrderType] = useState<string>("")

  // Customer info
  const [customerName, setCustomerName] = useState("")
  const [customerPhone, setCustomerPhone] = useState("")
  const [deliveryAddress, setDeliveryAddress] = useState("")

  // Promo
  const [promoCode, setPromoCode] = useState("")
  const [promoResult, setPromoResult] = useState<any>(null)

  // Checkout
  const [checkoutOpen, setCheckoutOpen] = useState(false)
  const [placing, setPlacing] = useState(false)
  const [orderError, setOrderError] = useState<string | null>(null)
  /** How the guest intends to settle. No gateway yet - the choice is only recorded. */
  const [paymentIntent, setPaymentIntent] = useState("Cash")
  const [paymentAmount, setPaymentAmount] = useState("")

  // Tracking
  const [tracking, setTracking] = useState<OrderTracking | null>(null)
  const [trackingToken, setTrackingToken] = useState("")

  useEffect(() => {
    init()
  }, [])

  async function init() {
    setLoading(true)
    try {
      // If tracking
      if (trackToken) {
        const t = await trackOrder(trackToken)
        setTracking(t)
        setTrackingToken(trackToken)
        setLoading(false)
        return
      }

      let fId = farmIdParam || ""

      // If QR scan
      if (qrToken) {
        const qr = await scanQrCode(qrToken)
        fId = qr.farmId
        // A restaurant-wide code identifies the venue only - the guest is at the
        // counter, not a table - so it must not claim DineIn.
        const isVenueCode = qr.codeType === "Restaurant" || !qr.tableId
        setTableId(isVenueCode ? null : qr.tableId)
        setTableNumber(isVenueCode ? "" : qr.tableNumber)
        setOrderType(isVenueCode ? "Takeaway" : "DineIn")
      }

      if (!fId) { setLoading(false); return }

      setFarmId(fId)
      const [s, cats, menu] = await Promise.all([
        getPublicSettings(fId),
        getPublicCategories(fId),
        getPublicMenu(fId),
      ])
      setSettings(s)
      setCategories(cats)
      setItems(menu)

      if (!orderType) {
        if (s.allowTakeaway) setOrderType("Takeaway")
        else if (s.allowDelivery) setOrderType("Delivery")
      }
    } catch (e: any) {
      console.error(e)
    } finally { setLoading(false) }
  }

  const filteredItems = items.filter(i => {
    if (selectedCat && i.categoryId !== selectedCat) return false
    if (search && !i.name.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })

  function addToCart(item: PublicMenuItem) {
    const existing = cart.find(c => c.menuItemId === item.menuItemId)
    if (existing) setCart(cart.map(c => c === existing ? { ...c, quantity: c.quantity + 1 } : c))
    else setCart([...cart, { menuItemId: item.menuItemId, name: item.name, price: item.price, quantity: 1, notes: "" }])
  }

  function updateQty(idx: number, delta: number) {
    setCart(cart.map((c, i) => i === idx ? { ...c, quantity: Math.max(1, c.quantity + delta) } : c))
  }

  function removeItem(idx: number) { setCart(cart.filter((_, i) => i !== idx)) }

  const subtotal = cart.reduce((s, c) => s + c.price * c.quantity, 0)
  const deliveryFee = orderType === "Delivery" ? (settings?.deliveryFeeAmount || 0) : 0
  const freeDelivery = settings?.freeDeliveryAbove && subtotal >= settings.freeDeliveryAbove
  const actualDeliveryFee = freeDelivery ? 0 : deliveryFee
  const promoDiscount = promoResult?.valid ? promoResult.calculatedDiscount : 0
  const total = subtotal + actualDeliveryFee - promoDiscount

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
        // The token is what ties this order to a real, scanned table. The server
        // re-resolves it and overrides farm/table from the database, so these
        // fields are a convenience for older clients, not the source of truth.
        qrToken: qrToken || undefined,
        orderType,
        tableId: tableId || undefined,
        tableNumber: tableNumber || undefined,
        customerName: customerName.trim(),
        customerPhone: customerPhone.trim(),
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
      setTrackingToken(result.trackingToken)
      setTracking(await trackOrder(result.trackingToken))
      setCheckoutOpen(false)
      setCart([])
    } catch (e: any) {
      setOrderError(e?.message || "We could not send your order. Please try again or ask a member of staff.")
    } finally { setPlacing(false) }
  }

  async function refreshTracking() {
    if (trackingToken) setTracking(await trackOrder(trackingToken))
  }

  // Keep the guest's screen live without them having to do anything. Terminal
  // states cannot change again, so stop rather than poll a forgotten tab forever.
  useEffect(() => {
    if (!trackingToken) return
    const done = ["Completed", "Cancelled", "Refunded", "Served"]
    if (tracking && done.includes(tracking.status)) return
    const id = setInterval(() => { refreshTracking().catch(() => {}) }, 10_000)
    return () => clearInterval(id)
  }, [trackingToken, tracking?.status])

  // A guest order sits at 'Placed' until staff accept it, so "Placed" means
  // "sent, waiting to be confirmed" rather than "the kitchen has it".
  const TRACKING_STEPS = ["Placed", "Confirmed", "Preparing", "Ready"]
  const trackingStep = tracking
    ? (tracking.status === "Served" || tracking.status === "Completed"
        ? TRACKING_STEPS.length - 1
        : TRACKING_STEPS.indexOf(tracking.status))
    : -1
  const awaitingConfirmation = tracking?.status === "Placed"
  const wasRejected = tracking?.status === "Cancelled"

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center bg-orange-50">
      <div className="text-center space-y-3">
        <Loader2 className="h-8 w-8 animate-spin text-orange-600 mx-auto" />
        <p className="text-sm text-muted-foreground">Loading menu...</p>
      </div>
    </div>
  )

  // Tracking view
  if (tracking) return (
    <div className="min-h-screen bg-orange-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardContent className="pt-6 space-y-6 text-center">
          <UtensilsCrossed className={`h-12 w-12 mx-auto ${wasRejected ? "text-red-500" : "text-orange-600"}`} />
          <h2 className="text-xl font-bold">Order {tracking.orderNumber}</h2>

          {wasRejected ? (
            <div className="rounded-lg bg-red-50 p-4 text-left">
              <div className="font-semibold text-red-800">This order was not accepted</div>
              <p className="mt-1 text-sm text-red-700">
                {tracking.cancelReason || "The restaurant could not take this order."}
              </p>
              <p className="mt-2 text-sm text-red-700">
                Please speak to a member of staff{tracking.tableNumber ? ` — you are at table ${tracking.tableNumber}` : ""}.
              </p>
            </div>
          ) : awaitingConfirmation && (
            <div className="rounded-lg bg-amber-50 p-3 text-sm text-amber-800">
              <span className="font-medium">Sent to the restaurant.</span> A member of staff is
              confirming your order — it will start being prepared once they accept it.
            </div>
          )}

          {/* Step indicators */}
          {!wasRejected && (
          <div className="flex items-center justify-between px-4">
            {TRACKING_STEPS.map((step, i) => (
              <div key={step} className="flex items-center flex-1">
                <div className="flex flex-col items-center">
                  <div className={`h-8 w-8 rounded-full flex items-center justify-center text-xs font-bold transition-all ${
                    i <= trackingStep ? "bg-orange-600 text-white" : "bg-gray-200 text-gray-500"
                  }`}>{i + 1}</div>
                  <span className={`text-[10px] mt-1 ${i <= trackingStep ? "text-orange-600 font-medium" : "text-gray-400"}`}>{step}</span>
                </div>
                {i < TRACKING_STEPS.length - 1 && (
                  <div className={`flex-1 h-0.5 mx-1 mt-[-12px] ${i < trackingStep ? "bg-orange-600" : "bg-gray-200"}`} />
                )}
              </div>
            ))}
          </div>
          )}

          <div className="text-sm text-muted-foreground space-y-1">
            <div>Type: {tracking.orderType} {tracking.tableNumber && `| Table ${tracking.tableNumber}`}</div>
            <div>Total: {tracking.totalAmount.toFixed(2)}</div>
            <div>Placed: {new Date(tracking.createdAt).toLocaleTimeString()}</div>
            {tracking.estimatedReadyTime && <div>Est. Ready: {new Date(tracking.estimatedReadyTime).toLocaleTimeString()}</div>}
          </div>
          <p className="text-xs text-muted-foreground">This updates automatically.</p>
        </CardContent>
      </Card>
    </div>
  )

  // No restaurant
  if (!farmId || !settings) return (
    <div className="min-h-screen flex items-center justify-center bg-orange-50">
      <Card className="w-full max-w-md"><CardContent className="pt-6 text-center"><p>Restaurant not found. Please scan a valid QR code.</p></CardContent></Card>
    </div>
  )

  // Two different situations were both showing "currently unavailable", which told
  // nobody anything: the restaurant has never switched online ordering on, versus it
  // is on but paused right now. Separate them, and say what to do.
  if (!settings.isEnabled || !settings.acceptingOrders) return (
    <div className="min-h-screen flex items-center justify-center bg-orange-50 p-4">
      <Card className="w-full max-w-md"><CardContent className="pt-6 text-center">
        <UtensilsCrossed className="h-12 w-12 text-orange-600 mx-auto mb-4" />
        {!settings.isEnabled ? (
          <>
            <h2 className="text-xl font-bold mb-2">This restaurant isn&apos;t taking phone orders yet</h2>
            <p className="text-muted-foreground">Please order at the counter.</p>
            <p className="mt-3 text-xs text-muted-foreground">
              Staff: switch on <span className="font-medium">Online Settings → Enable online ordering</span> and save.
            </p>
          </>
        ) : (
          <>
            <h2 className="text-xl font-bold mb-2">Orders are paused right now</h2>
            <p className="text-muted-foreground">
              {settings.pausedReason || "The kitchen has stopped taking new orders for the moment. Please ask a member of staff."}
            </p>
          </>
        )}
      </CardContent></Card>
    </div>
  )

  return (
    <div className="min-h-screen bg-orange-50">
      {/* Header */}
      <div className="bg-orange-600 text-white px-4 py-3 sticky top-0 z-10">
        <div className="max-w-2xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-2">
            <UtensilsCrossed className="h-5 w-5" />
            <span className="font-bold">Order Online</span>
            {tableNumber && <Badge className="bg-white text-orange-600">Table {tableNumber}</Badge>}
          </div>
          {cart.length > 0 && (
            <Button variant="ghost" className="text-white relative" onClick={() => setCheckoutOpen(true)}>
              <ShoppingCart className="h-5 w-5" />
              <span className="absolute -top-1 -right-1 bg-white text-orange-600 rounded-full w-5 h-5 text-xs flex items-center justify-center font-bold">
                {cart.reduce((s, c) => s + c.quantity, 0)}
              </span>
            </Button>
          )}
        </div>
      </div>

      {/* Order type selector (if not QR) */}
      {!qrToken && (
        <div className="max-w-2xl mx-auto px-4 py-3 flex gap-2">
          {settings.allowTakeaway && (
            <Button variant={orderType === "Takeaway" ? "default" : "outline"} size="sm" onClick={() => setOrderType("Takeaway")} className="gap-1"><Clock className="h-3 w-3" /> Takeaway</Button>
          )}
          {settings.allowDelivery && (
            <Button variant={orderType === "Delivery" ? "default" : "outline"} size="sm" onClick={() => setOrderType("Delivery")} className="gap-1"><Truck className="h-3 w-3" /> Delivery</Button>
          )}
        </div>
      )}

      {/* Category filter */}
      <div className="max-w-2xl mx-auto px-4 py-2 flex gap-2 overflow-x-auto">
        <Button variant={selectedCat === null ? "default" : "outline"} size="sm" onClick={() => setSelectedCat(null)}>All</Button>
        {categories.map(c => (
          <Button key={c.menuCategoryId} variant={selectedCat === c.menuCategoryId ? "default" : "outline"} size="sm" onClick={() => setSelectedCat(c.menuCategoryId)}>
            {c.name}
          </Button>
        ))}
      </div>

      {/* Search */}
      <div className="max-w-2xl mx-auto px-4 py-2">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input className="pl-9" placeholder="Search menu..." value={search} onChange={e => setSearch(e.target.value)} />
        </div>
      </div>

      {/* Menu items.
          Laid out as a photo grid rather than a text list, to match the staff POS:
          a guest choosing food on their phone picks by sight, and the photos are
          already on the items. Two columns fits a phone; wider screens get more. */}
      <div className="max-w-2xl mx-auto px-4 py-2 pb-28">
        {filteredItems.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center text-muted-foreground">
            <UtensilsCrossed className="mb-3 h-10 w-10 text-orange-200" />
            <p className="font-medium text-gray-700">Nothing on the menu yet</p>
            <p className="text-sm">{search ? "Try a different search." : "Please ask a member of staff."}</p>
          </div>
        ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {filteredItems.map(item => {
          const inCart = cart.filter(c => c.menuItemId === item.menuItemId).reduce((n, c) => n + c.quantity, 0)
          return (
          <button key={item.menuItemId} type="button" onClick={() => addToCart(item)}
            className="group relative overflow-hidden rounded-xl border bg-white text-left transition-all hover:border-orange-300 hover:shadow-md active:scale-[0.98]">
            {/* Photo, with the icon as a permanent backdrop so items without one
                (and images that fail to load) keep the grid rows even. */}
            <div className="relative aspect-[4/3] w-full overflow-hidden bg-orange-50">
              <div className="absolute inset-0 flex items-center justify-center">
                <UtensilsCrossed className="h-8 w-8 text-orange-200" />
              </div>
              {item.imageUrl && (
                <img src={item.imageUrl} alt="" loading="lazy"
                  className="relative h-full w-full object-cover transition-transform duration-200 group-hover:scale-105"
                  onError={e => (e.currentTarget.style.display = "none")} />
              )}
              {inCart > 0 && (
                <span className="absolute right-1.5 top-1.5 flex h-6 min-w-6 items-center justify-center rounded-full bg-orange-600 px-1.5 text-xs font-bold text-white shadow">
                  {inCart}
                </span>
              )}
            </div>

            <div className="p-2.5">
              <div className="flex items-start gap-1.5">
                <span className="line-clamp-2 flex-1 text-sm font-medium leading-snug text-gray-900">{item.name}</span>
              </div>
              <div className="mt-1 flex flex-wrap items-center gap-1">
                {item.isVegetarian && <Badge variant="secondary" className="h-4 bg-green-100 px-1 text-[9px]">Veg</Badge>}
                {item.isVegan && <Badge variant="secondary" className="h-4 bg-green-200 px-1 text-[9px]">Vegan</Badge>}
                {item.spicyLevel > 0 && <span className="text-[10px]">{"🌶️".repeat(Math.min(item.spicyLevel, 3))}</span>}
              </div>
              <div className="mt-1.5 flex items-center justify-between">
                <span className="font-bold text-orange-600">{item.price.toFixed(2)}</span>
                {item.prepTime > 0 && <span className="text-[10px] text-muted-foreground">{item.prepTime} min</span>}
              </div>
            </div>
          </button>
          )
        })}
        </div>
        )}
      </div>

      {/* Cart bottom bar */}
      {cart.length > 0 && (
        <div className="fixed bottom-0 left-0 right-0 z-10">
          <div className="h-6 bg-gradient-to-t from-white to-transparent" />
          <div className="bg-white border-t shadow-2xl p-4">
            <div className="max-w-2xl mx-auto">
              <Button className="w-full bg-orange-600 hover:bg-orange-700 h-12 text-lg" onClick={() => setCheckoutOpen(true)}>
                <ShoppingCart className="h-5 w-5 mr-2" />
                View Cart ({cart.reduce((s, c) => s + c.quantity, 0)} items) — {subtotal.toFixed(2)}
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Checkout Dialog */}
      <Dialog open={checkoutOpen} onOpenChange={setCheckoutOpen}>
        <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>Your Order</DialogTitle></DialogHeader>
          <div className="space-y-4">
            {/* Cart items */}
            <div className="space-y-2">
              {cart.map((item, idx) => (
                <div key={idx} className="flex items-center justify-between py-2 border-b">
                  <div className="flex-1">
                    <div className="font-medium text-sm">{item.name}</div>
                    <div className="text-xs text-muted-foreground">{item.price.toFixed(2)} each</div>
                  </div>
                  <div className="flex items-center gap-1">
                    <Button variant="outline" size="icon" className="h-6 w-6" onClick={() => updateQty(idx, -1)}><Minus className="h-3 w-3" /></Button>
                    <span className="w-6 text-center text-sm">{item.quantity}</span>
                    <Button variant="outline" size="icon" className="h-6 w-6" onClick={() => updateQty(idx, 1)}><Plus className="h-3 w-3" /></Button>
                    <span className="w-14 text-right text-sm font-medium">{(item.price * item.quantity).toFixed(2)}</span>
                    <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => removeItem(idx)}><X className="h-3 w-3 text-red-500" /></Button>
                  </div>
                </div>
              ))}
            </div>

            {/* Promo code */}
            <div className="flex gap-2">
              <Input placeholder="Promo code" value={promoCode} onChange={e => setPromoCode(e.target.value.toUpperCase())} />
              <Button variant="outline" onClick={applyPromo}><Tag className="h-4 w-4" /></Button>
            </div>
            {promoResult && (
              <div className={`text-sm p-2 rounded ${promoResult.valid ? "bg-green-50 text-green-700" : "bg-red-50 text-red-700"}`}>
                {promoResult.message}
              </div>
            )}

            {/* Customer info. Both are required: for a guest at a table this is
                the only way the restaurant can reach them about the order. */}
            <div className="space-y-2">
              <div>
                <Label>Your name <span className="text-orange-600">*</span></Label>
                <Input value={customerName} onChange={e => setCustomerName(e.target.value)} placeholder="So we know whose order this is" />
              </div>
              <div>
                <Label>Phone number <span className="text-orange-600">*</span></Label>
                <Input type="tel" inputMode="tel" value={customerPhone} onChange={e => setCustomerPhone(e.target.value)} placeholder="In case we need to check something" />
              </div>

              <div className="pt-1">
                <Label>Payment method <span className="text-orange-600">*</span></Label>
                <Select value={paymentIntent} onValueChange={v => setPaymentIntent(v)}>
                  <SelectTrigger className="mt-1"><SelectValue placeholder="Choose how you will pay" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="MobileMoney">Mobile Money</SelectItem>
                    <SelectItem value="CreditCard">Credit Card</SelectItem>
                    <SelectItem value="Cash">Physical Cash</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div>
                <Label>Amount</Label>
                <Input
                  type="number"
                  inputMode="decimal"
                  min={0}
                  step="0.01"
                  value={paymentAmount}
                  onChange={e => setPaymentAmount(e.target.value)}
                  placeholder={total.toFixed(2)}
                />
                {/* Deliberately explicit: nothing is charged here. The gateway is not
                    built yet, so this is a record of what the guest intends to hand
                    over, and staff still settle the order through the POS. */}
                <p className="mt-1.5 text-xs text-muted-foreground">
                  Nothing is charged now — you settle with the staff. Leave blank to use the order total.
                </p>
              </div>
              {orderType === "Delivery" && (
                <div><Label>Delivery Address *</Label><Input value={deliveryAddress} onChange={e => setDeliveryAddress(e.target.value)} placeholder="Full delivery address" /></div>
              )}
            </div>

            {/* Totals */}
            <div className="border-t pt-2 space-y-1 text-sm">
              <div className="flex justify-between"><span>Subtotal</span><span>{subtotal.toFixed(2)}</span></div>
              {orderType === "Delivery" && <div className="flex justify-between"><span>Delivery Fee</span><span>{freeDelivery ? <span className="line-through text-muted-foreground">{deliveryFee.toFixed(2)}</span> : actualDeliveryFee.toFixed(2)}</span></div>}
              {freeDelivery && <div className="text-green-600 text-xs">Free delivery on orders above {settings.freeDeliveryAbove}</div>}
              {promoDiscount > 0 && <div className="flex justify-between text-green-600"><span>Promo ({promoCode})</span><span>-{promoDiscount.toFixed(2)}</span></div>}
              <div className="flex justify-between font-bold text-lg border-t pt-1"><span>Total</span><span>{total.toFixed(2)}</span></div>
            </div>
          </div>
          <DialogFooter>
            {orderError && (
              <div className="mb-2 rounded-lg bg-red-50 p-2.5 text-sm text-red-700">{orderError}</div>
            )}
            <Button
              className="w-full bg-orange-600 hover:bg-orange-700 h-12"
              onClick={handlePlaceOrder}
              disabled={placing || cart.length === 0 || !customerName.trim() || !customerPhone.trim()}
            >
              {placing ? <Loader2 className="h-5 w-5 animate-spin mr-2" /> : <Check className="h-5 w-5 mr-2" />}
              Place Order — {total.toFixed(2)}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

export default function RestaurantOrderOnlinePage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      }
    >
      <RestaurantOrderOnlineContent />
    </Suspense>
  )
}

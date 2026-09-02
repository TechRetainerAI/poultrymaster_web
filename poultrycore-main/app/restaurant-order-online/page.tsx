"use client"

import { useEffect, useState } from "react"
import { useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
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

export default function RestaurantOrderOnlinePage() {
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
        setTableId(qr.tableId)
        setTableNumber(qr.tableNumber)
        setOrderType("DineIn")
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
        if (qrToken) setOrderType("DineIn")
        else if (s.allowTakeaway) setOrderType("Takeaway")
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
    setPlacing(true)
    try {
      const result = await placeOnlineOrder(farmId, {
        orderType,
        tableId: tableId || undefined,
        tableNumber: tableNumber || undefined,
        customerName: customerName || undefined,
        customerPhone: customerPhone || undefined,
        covers: 1,
        notes: orderType === "Delivery" ? `Delivery: ${deliveryAddress}` : undefined,
        onlineSource: qrToken ? "QR" : "Web",
        deliveryAddress: orderType === "Delivery" ? deliveryAddress : undefined,
        deliveryFee: actualDeliveryFee,
        promoCodeId: promoResult?.valid ? promoResult.promoCodeId : undefined,
        promoCode: promoResult?.valid ? promoCode : undefined,
        promoDiscount,
        items: cart.map(c => ({ menuItemId: c.menuItemId, itemName: c.name, quantity: c.quantity, unitPrice: c.price, notes: c.notes || undefined })),
      })
      setTrackingToken(result.trackingToken)
      setTracking(await trackOrder(result.trackingToken))
      setCheckoutOpen(false)
      setCart([])
    } catch (e: any) {
      alert(e?.message || "Order failed")
    } finally { setPlacing(false) }
  }

  async function refreshTracking() {
    if (trackingToken) setTracking(await trackOrder(trackingToken))
  }

  const TRACKING_STEPS = ["Placed", "Preparing", "Ready", "Delivered"]
  const trackingStep = tracking ? TRACKING_STEPS.indexOf(tracking.status) : -1

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
          <UtensilsCrossed className="h-12 w-12 text-orange-600 mx-auto" />
          <h2 className="text-xl font-bold">Order {tracking.orderNumber}</h2>

          {/* Step indicators */}
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

          <div className="text-sm text-muted-foreground space-y-1">
            <div>Type: {tracking.orderType} {tracking.tableNumber && `| Table ${tracking.tableNumber}`}</div>
            <div>Total: {tracking.totalAmount.toFixed(2)}</div>
            <div>Placed: {new Date(tracking.createdAt).toLocaleTimeString()}</div>
            {tracking.estimatedReadyTime && <div>Est. Ready: {new Date(tracking.estimatedReadyTime).toLocaleTimeString()}</div>}
          </div>
          <Button onClick={refreshTracking} variant="outline" className="w-full">Refresh Status</Button>
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

  if (!settings.isEnabled || !settings.acceptingOrders) return (
    <div className="min-h-screen flex items-center justify-center bg-orange-50">
      <Card className="w-full max-w-md"><CardContent className="pt-6 text-center">
        <UtensilsCrossed className="h-12 w-12 text-orange-600 mx-auto mb-4" />
        <h2 className="text-xl font-bold mb-2">Online ordering is currently unavailable</h2>
        {settings.pausedReason && <p className="text-muted-foreground">{settings.pausedReason}</p>}
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

      {/* Menu items */}
      <div className="max-w-2xl mx-auto px-4 py-2 space-y-2 pb-24">
        {filteredItems.map(item => (
          <Card key={item.menuItemId} className="cursor-pointer hover:shadow-md hover:border-orange-200 transition-all" onClick={() => addToCart(item)}>
            <CardContent className="py-3 px-4 flex items-center gap-3">
              <div className="h-12 w-12 rounded-lg bg-orange-50 flex items-center justify-center flex-shrink-0">
                <UtensilsCrossed className="h-5 w-5 text-orange-400" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-medium truncate">{item.name}</span>
                  {item.isVegetarian && <Badge variant="secondary" className="text-[10px] bg-green-100">Veg</Badge>}
                  {item.isVegan && <Badge variant="secondary" className="text-[10px] bg-green-200">Vegan</Badge>}
                  {item.spicyLevel > 0 && <span className="text-xs">{"🌶️".repeat(Math.min(item.spicyLevel, 3))}</span>}
                </div>
                {item.description && <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{item.description}</p>}
                <div className="text-xs text-muted-foreground mt-1">
                  {item.prepTime > 0 && <span>{item.prepTime} min</span>}
                  {item.calories && <span> | {item.calories} cal</span>}
                </div>
              </div>
              <div className="text-right ml-4">
                <div className="font-bold text-orange-600">{item.price.toFixed(2)}</div>
                <Button variant="outline" size="sm" className="mt-1 h-7 text-xs"><Plus className="h-3 w-3" /></Button>
              </div>
            </CardContent>
          </Card>
        ))}
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

            {/* Customer info */}
            <div className="space-y-2">
              <div><Label>Name</Label><Input value={customerName} onChange={e => setCustomerName(e.target.value)} /></div>
              <div><Label>Phone</Label><Input value={customerPhone} onChange={e => setCustomerPhone(e.target.value)} /></div>
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
            <Button className="w-full bg-orange-600 hover:bg-orange-700 h-12" onClick={handlePlaceOrder} disabled={placing || cart.length === 0}>
              {placing ? <Loader2 className="h-5 w-5 animate-spin mr-2" /> : <Check className="h-5 w-5 mr-2" />}
              Place Order — {total.toFixed(2)}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

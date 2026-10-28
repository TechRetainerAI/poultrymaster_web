"use client"

// Quick Sale / POS — a fast checkout screen for retail businesses.
//
// The existing /generic-sales/new page creates a full invoice with line items,
// header discounts, tax, etc. That is too slow for a yam seller doing 50+ sales
// a day. This page is the fast path: search product → add to cart → pay → done.
//
// On "Complete Sale" we create + approve the sale in one click (two API calls).
// The sale is immediately committed — no Draft step.

import { useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Loader2, Search, Plus, Minus, X, ShoppingCart, Check, Trash2, Zap,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  approveSale,
  createSale,
  getCashAccounts,
  getCustomers,
  getProducts,
  type GenericCashAccount,
  type GenericCustomer,
  type GenericProduct,
  type GenericSaleItem,
} from "@/lib/api/generic"

const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card"]

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, {
    style: "currency", currency: "GHS", maximumFractionDigits: 2,
  }).format(n)
}

interface CartItem {
  product: GenericProduct
  quantity: number
  unitPrice: number
}

export default function GenericPosPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const modules = useGenericModules()
  const logout = useLogout()
  const { toast } = useToast()
  const searchRef = useRef<HTMLInputElement>(null)

  const [loading, setLoading] = useState(true)
  const [completing, setCompleting] = useState(false)
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])

  // Cart state
  const [cart, setCart] = useState<CartItem[]>([])
  const [search, setSearch] = useState("")
  const [customerId, setCustomerId] = useState<string>("")
  const [paymentMethod, setPaymentMethod] = useState("Cash")
  const [cashAccountId, setCashAccountId] = useState("")
  const [amountReceived, setAmountReceived] = useState("")

  // Load data
  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard"); return
    }
    Promise.all([getProducts(), getCustomers(), getCashAccounts()])
      .then(([ps, cs, as]) => {
        setProducts(ps.filter((p) => p.isActive))
        setCustomers(cs.filter((c) => c.isActive))
        setCashAccounts(as.filter((a) => a.isActive))
        // Default cash account from business settings
        const defaultId = modules.businessSettings?.defaultCashAccountForPayments
        const defaultAccount = defaultId
          ? as.find((a) => a.genericCashAccountId === defaultId && a.isActive)
          : null
        const first = defaultAccount ?? as.find((a) => a.isActive)
        if (first) setCashAccountId(String(first.genericCashAccountId))
      })
      .catch((e) => toast({
        title: "Could not load", description: e?.message ?? String(e), variant: "destructive",
      }))
      .finally(() => setLoading(false))
  }, [activeFarmType, router, toast, modules.businessSettings?.defaultCashAccountForPayments])

  // Filter products by search
  const filtered = useMemo(() => {
    if (!search.trim()) return products.slice(0, 20) // Show first 20 by default
    const q = search.trim().toLowerCase()
    return products.filter(
      (p) =>
        p.productName.toLowerCase().includes(q) ||
        (p.sku && p.sku.toLowerCase().includes(q)) ||
        (p.barcode && p.barcode.toLowerCase().includes(q))
    )
  }, [products, search])

  // Cart totals
  const subtotal = cart.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0)
  const total = subtotal // No tax/discount in quick sale — keep it fast
  const received = Number(amountReceived) || 0
  const change = received - total
  const isPaid = received >= total || paymentMethod === "Credit"

  // Cart operations
  const addToCart = (product: GenericProduct) => {
    setCart((prev) => {
      const existing = prev.find((c) => c.product.genericProductId === product.genericProductId)
      if (existing) {
        return prev.map((c) =>
          c.product.genericProductId === product.genericProductId
            ? { ...c, quantity: c.quantity + 1 }
            : c
        )
      }
      return [...prev, { product, quantity: 1, unitPrice: product.sellingPrice }]
    })
    setSearch("")
    searchRef.current?.focus()
  }

  const updateQuantity = (productId: number, delta: number) => {
    setCart((prev) =>
      prev
        .map((c) =>
          c.product.genericProductId === productId
            ? { ...c, quantity: Math.max(0, c.quantity + delta) }
            : c
        )
        .filter((c) => c.quantity > 0)
    )
  }

  const removeFromCart = (productId: number) => {
    setCart((prev) => prev.filter((c) => c.product.genericProductId !== productId))
  }

  const clearCart = () => {
    setCart([])
    setAmountReceived("")
    setCustomerId("")
    setSearch("")
    searchRef.current?.focus()
  }

  // Complete sale: create + approve in one action
  const completeSale = async () => {
    if (cart.length === 0) {
      toast({ title: "Cart is empty", variant: "destructive" }); return
    }
    if (!isPaid && paymentMethod !== "Credit") {
      toast({ title: "Amount received is less than total", variant: "destructive" }); return
    }

    setCompleting(true)
    try {
      const items: GenericSaleItem[] = cart.map((c) => ({
        itemType: "Product" as const,
        genericProductId: c.product.genericProductId,
        genericServiceId: null,
        description: c.product.productName,
        quantity: c.quantity,
        unitPrice: c.unitPrice,
        discountAmount: 0,
      }))

      const sale = await createSale({
        saleDate: new Date().toISOString().slice(0, 10),
        genericCustomerId: customerId ? Number(customerId) : null,
        salesType: "WalkInSale",
        headerDiscountAmount: 0,
        taxAmount: 0,
        amountPaid: paymentMethod === "Credit" ? 0 : total,
        paymentMethod,
        genericCashAccountId: cashAccountId ? Number(cashAccountId) : null,
        items,
      })

      if (sale) {
        // Auto-approve — no Draft step for POS
        await approveSale(sale.genericSaleId)

        toast({
          title: `Sale #${sale.genericSaleId} completed`,
          description: change > 0 ? `Change: ${fmt(change)}` : "Paid in full",
        })

        // Refresh product stock (quick — re-fetch in background)
        getProducts().then((ps) => setProducts(ps.filter((p) => p.isActive))).catch(() => {})

        clearCart()
      }
    } catch (e: any) {
      toast({
        title: "Sale failed",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setCompleting(false)
    }
  }

  // Keyboard shortcut: Enter on search with single result adds it
  const onSearchKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && filtered.length === 1) {
      addToCart(filtered[0])
    }
  }

  if (loading) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 flex items-center justify-center">
            <Loader2 className="h-6 w-6 animate-spin text-slate-400" />
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">
          <div className="max-w-7xl mx-auto">
            {/* Header */}
            <div className="flex items-center justify-between mb-3">
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Zap className="h-5 w-5 text-amber-500" /> Quick Sale
              </h1>
              <Badge variant="outline" className="text-xs">
                {cart.length} item{cart.length !== 1 ? "s" : ""} in cart
              </Badge>
            </div>

            <div className="grid gap-3 lg:grid-cols-5">
              {/* ================================================
                  LEFT: Product search + results (3 cols)
                  ================================================ */}
              <div className="lg:col-span-3 space-y-3">
                {/* Search bar */}
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input
                    ref={searchRef}
                    placeholder="Search products by name, SKU or barcode…"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    onKeyDown={onSearchKeyDown}
                    className="pl-9 h-11 text-base"
                    autoFocus
                  />
                </div>

                {/* Product grid */}
                <div className="grid gap-2 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 max-h-[calc(100vh-220px)] overflow-y-auto">
                  {filtered.length === 0 ? (
                    <p className="col-span-full text-center text-sm text-slate-500 py-8">
                      No products match &ldquo;{search}&rdquo;
                    </p>
                  ) : (
                    filtered.map((p) => {
                      const inCart = cart.find((c) => c.product.genericProductId === p.genericProductId)
                      return (
                        <button
                          key={p.genericProductId}
                          type="button"
                          onClick={() => addToCart(p)}
                          className={`text-left rounded-lg border p-2.5 transition hover:shadow-sm ${
                            inCart
                              ? "border-indigo-400 bg-indigo-50"
                              : "border-slate-200 bg-white hover:border-slate-300"
                          }`}
                        >
                          <p className="font-medium text-slate-900 text-sm truncate">
                            {p.productName}
                          </p>
                          <p className="text-xs text-slate-500 mt-0.5">
                            {fmt(p.sellingPrice)}
                            {p.unitOfMeasure ? ` / ${p.unitOfMeasure}` : ""}
                          </p>
                          <div className="flex items-center justify-between mt-1">
                            <span className={`text-xs ${
                              p.currentStock <= p.minimumStockAlert
                                ? "text-red-600 font-medium"
                                : "text-slate-400"
                            }`}>
                              {p.trackInventory ? `${p.currentStock} in stock` : ""}
                            </span>
                            {inCart && (
                              <Badge className="text-xs bg-indigo-600">{inCart.quantity}</Badge>
                            )}
                          </div>
                        </button>
                      )
                    })
                  )}
                </div>
              </div>

              {/* ================================================
                  RIGHT: Cart + Payment (2 cols)
                  ================================================ */}
              <div className="lg:col-span-2 space-y-3">
                {/* Cart */}
                <Card>
                  <CardHeader className="py-2 px-3">
                    <div className="flex items-center justify-between">
                      <CardTitle className="text-sm flex items-center gap-1.5">
                        <ShoppingCart className="h-4 w-4" /> Cart
                      </CardTitle>
                      {cart.length > 0 && (
                        <Button variant="ghost" size="sm" onClick={clearCart} className="h-7 text-xs text-slate-500">
                          <Trash2 className="h-3 w-3 mr-1" /> Clear
                        </Button>
                      )}
                    </div>
                  </CardHeader>
                  <CardContent className="px-3 pb-3">
                    {cart.length === 0 ? (
                      <p className="text-sm text-slate-400 text-center py-6">
                        Search and tap products to add them here
                      </p>
                    ) : (
                      <div className="space-y-2 max-h-[280px] overflow-y-auto">
                        {cart.map((item) => (
                          <div
                            key={item.product.genericProductId}
                            className="flex items-center gap-2 rounded-md border border-slate-100 p-2"
                          >
                            <div className="flex-1 min-w-0">
                              <p className="text-sm font-medium text-slate-900 truncate">
                                {item.product.productName}
                              </p>
                              <p className="text-xs text-slate-500">
                                {fmt(item.unitPrice)} x {item.quantity} = {fmt(item.unitPrice * item.quantity)}
                              </p>
                            </div>
                            <div className="flex items-center gap-1">
                              <button
                                type="button"
                                onClick={() => updateQuantity(item.product.genericProductId, -1)}
                                className="flex h-7 w-7 items-center justify-center rounded-md border bg-white hover:bg-slate-50"
                              >
                                <Minus className="h-3 w-3" />
                              </button>
                              <span className="w-8 text-center text-sm font-medium">
                                {item.quantity}
                              </span>
                              <button
                                type="button"
                                onClick={() => updateQuantity(item.product.genericProductId, 1)}
                                className="flex h-7 w-7 items-center justify-center rounded-md border bg-white hover:bg-slate-50"
                              >
                                <Plus className="h-3 w-3" />
                              </button>
                              <button
                                type="button"
                                onClick={() => removeFromCart(item.product.genericProductId)}
                                className="flex h-7 w-7 items-center justify-center rounded-md text-slate-400 hover:text-red-500"
                              >
                                <X className="h-3.5 w-3.5" />
                              </button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}

                    {/* Total */}
                    {cart.length > 0 && (
                      <div className="mt-3 pt-3 border-t space-y-1">
                        <div className="flex justify-between text-lg font-bold text-slate-900">
                          <span>Total</span>
                          <span>{fmt(total)}</span>
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>

                {/* Payment */}
                <Card>
                  <CardHeader className="py-2 px-3">
                    <CardTitle className="text-sm">Payment</CardTitle>
                  </CardHeader>
                  <CardContent className="px-3 pb-3 space-y-3">
                    {/* Customer (optional) */}
                    <div>
                      <Label className="text-xs text-slate-500">Customer (optional)</Label>
                      <Select value={customerId} onValueChange={setCustomerId}>
                        <SelectTrigger className="h-9">
                          <SelectValue placeholder="Walk-in customer" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="walk-in">Walk-in customer</SelectItem>
                          {customers.map((c) => (
                            <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>
                              {c.customerName}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    {/* Payment method */}
                    <div>
                      <Label className="text-xs text-slate-500">Payment method</Label>
                      <div className="grid grid-cols-4 gap-1.5 mt-1">
                        {PAY_METHODS.map((m) => (
                          <button
                            key={m}
                            type="button"
                            onClick={() => setPaymentMethod(m)}
                            className={`rounded-md px-2 py-1.5 text-xs font-medium transition ${
                              paymentMethod === m
                                ? "bg-indigo-600 text-white"
                                : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                            }`}
                          >
                            {m}
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Cash account */}
                    <div>
                      <Label className="text-xs text-slate-500">Cash account</Label>
                      <Select value={cashAccountId} onValueChange={setCashAccountId}>
                        <SelectTrigger className="h-9">
                          <SelectValue placeholder="Select account" />
                        </SelectTrigger>
                        <SelectContent>
                          {cashAccounts.map((a) => (
                            <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                              {a.accountName}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    {/* Amount received */}
                    {paymentMethod !== "Credit" && (
                      <div>
                        <Label className="text-xs text-slate-500">Amount received</Label>
                        <NumberInput
                          step="0.01"
                          min="0"
                          value={amountReceived}
                          onChange={(e) => setAmountReceived(e.target.value)}
                          className="h-9"
                          placeholder={total > 0 ? String(total.toFixed(2)) : "0.00"}
                        />
                        {received > 0 && total > 0 && (
                          <div className="flex justify-between text-xs mt-1">
                            <span className="text-slate-500">Change</span>
                            <span className={change >= 0 ? "text-emerald-600 font-medium" : "text-red-600 font-medium"}>
                              {change >= 0 ? fmt(change) : `Short ${fmt(Math.abs(change))}`}
                            </span>
                          </div>
                        )}
                      </div>
                    )}

                    {/* Quick amount buttons */}
                    {paymentMethod !== "Credit" && total > 0 && (
                      <div className="flex gap-1.5">
                        <Button
                          variant="outline" size="sm"
                          className="flex-1 h-8 text-xs"
                          onClick={() => setAmountReceived(total.toFixed(2))}
                        >
                          Exact ({fmt(total)})
                        </Button>
                        {total <= 500 && (
                          <>
                            <Button
                              variant="outline" size="sm"
                              className="flex-1 h-8 text-xs"
                              onClick={() => setAmountReceived(String(Math.ceil(total / 5) * 5))}
                            >
                              {fmt(Math.ceil(total / 5) * 5)}
                            </Button>
                            <Button
                              variant="outline" size="sm"
                              className="flex-1 h-8 text-xs"
                              onClick={() => setAmountReceived(String(Math.ceil(total / 10) * 10))}
                            >
                              {fmt(Math.ceil(total / 10) * 10)}
                            </Button>
                          </>
                        )}
                      </div>
                    )}

                    {/* Complete sale button */}
                    <Button
                      className="w-full h-12 text-base font-semibold"
                      disabled={cart.length === 0 || completing || (!isPaid && paymentMethod !== "Credit")}
                      onClick={completeSale}
                    >
                      {completing ? (
                        <>
                          <Loader2 className="h-5 w-5 mr-2 animate-spin" /> Processing…
                        </>
                      ) : (
                        <>
                          <Check className="h-5 w-5 mr-2" />
                          Complete Sale {total > 0 ? `— ${fmt(total)}` : ""}
                        </>
                      )}
                    </Button>
                  </CardContent>
                </Card>
              </div>
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}

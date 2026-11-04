"use client"

// Quick Sale / POS + Sales History — combines the fast checkout screen with the
// sales history list, mirroring how generic-inventory combines Items/Purchases/Adjustments.

import { Suspense, useEffect, useMemo, useRef, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Loader2, Search, Plus, Minus, X, ShoppingCart, Check, Trash2, Zap,
  History, DollarSign, Printer,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import {
  approveSale,
  createSale,
  getCashAccounts,
  getCustomers,
  getProducts,
  getSales,
  type GenericCashAccount,
  type GenericCustomer,
  type GenericProduct,
  type GenericSale,
  type GenericSaleItem,
} from "@/lib/api/generic"

const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card"]

/** Extract a walk-in customer name stored in the notes field as "Customer: Name". */
function displayCustomer(sale: GenericSale): string {
  if (sale.customerName) return sale.customerName
  if (sale.notes?.startsWith("Customer: ")) return sale.notes.slice(10)
  return "Walk-in"
}
const TABS = ["pos", "new-sale", "sales"] as const
type TabKey = (typeof TABS)[number]

const SALES_TYPES = [
  "WalkInSale", "CustomerSale", "ProductSale", "ServiceSale", "MixedSale",
  "CreditSale", "OnlineSale", "DeliverySale", "WholesaleSale", "RetailSale",
]

type InvoiceRow = {
  itemType: "Product" | "Service"
  genericProductId?: number
  description: string
  quantity: number
  unitPrice: number
  discountAmount: number
}
const blankInvoiceRow = (): InvoiceRow => ({ itemType: "Product", genericProductId: undefined, description: "", quantity: 1, unitPrice: 0, discountAmount: 0 })

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, {
    style: "currency", currency: "GHS", maximumFractionDigits: 2,
  }).format(n)
}

function statusBadgeClass(s: string) {
  switch (s) {
    case "Approved": return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Refunded": return "bg-amber-100 text-amber-800 hover:bg-amber-100"
    default: return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

interface CartItem {
  product: GenericProduct
  quantity: number
  unitPrice: number
}

// KPI card matching inventory page style
function Kpi({ icon, label, value, sub, tone }: {
  icon: React.ReactNode; label: string; value: React.ReactNode; sub?: React.ReactNode
  tone?: "warn" | "bad" | "good"
}) {
  return (
    <div className={cn("min-w-0 rounded-xl border bg-white p-3 text-left shadow-sm sm:p-4",
      tone === "warn" ? "border-amber-200" : tone === "bad" ? "border-red-200" : "border-slate-200")}>
      <div className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-slate-500">{icon} {label}</div>
      <div className={cn("mt-1 text-xl font-bold tabular-nums sm:text-2xl",
        tone === "warn" ? "text-amber-700" : tone === "bad" ? "text-red-600" : tone === "good" ? "text-emerald-700" : "text-slate-900")}>{value}</div>
      {sub && <div className="mt-0.5 truncate text-xs text-slate-500">{sub}</div>}
    </div>
  )
}

function GenericPosPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const modules = useGenericModules()
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()
  const searchRef = useRef<HTMLInputElement>(null)

  // ---- Tab ----
  const tabParam = searchParams.get("tab")
  const tab: TabKey = (TABS as readonly string[]).includes(tabParam ?? "") ? (tabParam as TabKey) : "pos"
  const selectTab = (v: string) => {
    router.replace(v === "pos" ? "/generic-pos" : `/generic-pos?tab=${v}`, { scroll: false })
  }

  // ---- POS state ----
  const [loading, setLoading] = useState(true)
  const [completing, setCompleting] = useState(false)
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])
  const [cart, setCart] = useState<CartItem[]>([])
  const [search, setSearch] = useState("")
  const [customerId, setCustomerId] = useState<string>("")
  const [walkInName, setWalkInName] = useState("")
  const [paymentMethod, setPaymentMethod] = useState("Cash")
  const [cashAccountId, setCashAccountId] = useState("")
  const [amountReceived, setAmountReceived] = useState("")

  // ---- New Sale (invoice) state ----
  const [invoiceRows, setInvoiceRows] = useState<InvoiceRow[]>([blankInvoiceRow()])
  const [invoiceHeader, setInvoiceHeader] = useState(() => {
    const now = new Date()
    const date = now.toISOString().slice(0, 10)
    const pad = String(now.getHours()).padStart(2, "0") + String(now.getMinutes()).padStart(2, "0")
    const rand = String(Math.floor(Math.random() * 10000)).padStart(4, "0")
    return { saleDate: date, genericCustomerId: "", salesType: "WalkInSale", receiptNumber: `SAL-${date.replace(/-/g, "")}-${pad}${rand}`, headerDiscountAmount: "0", taxAmount: "0", amountPaid: "0", paymentMethod: "Cash", genericCashAccountId: "", notes: "" }
  })
  const [invoiceSaving, setInvoiceSaving] = useState(false)
  const [invoiceWalkInName, setInvoiceWalkInName] = useState("")

  const invoiceTotals = useMemo(() => {
    const subtotal = invoiceRows.reduce((s, r) => s + (r.quantity * r.unitPrice - r.discountAmount), 0)
    const disc = Number(invoiceHeader.headerDiscountAmount) || 0
    const tax = Number(invoiceHeader.taxAmount) || 0
    const total = subtotal - disc + tax
    const paid = Number(invoiceHeader.amountPaid) || 0
    return { subtotal, disc, tax, total, paid, balance: total - paid }
  }, [invoiceRows, invoiceHeader.headerDiscountAmount, invoiceHeader.taxAmount, invoiceHeader.amountPaid])

  const updateInvoiceRow = (idx: number, patch: Partial<InvoiceRow>) =>
    setInvoiceRows((rs) => rs.map((r, i) => (i === idx ? { ...r, ...patch } : r)))

  const onPickInvoiceProduct = (idx: number, productId: string) => {
    const p = products.find((x) => x.genericProductId === Number(productId))
    if (!p) { updateInvoiceRow(idx, { genericProductId: undefined, description: "" }); return }
    updateInvoiceRow(idx, { genericProductId: p.genericProductId, description: p.productName, unitPrice: p.sellingPrice > 0 ? p.sellingPrice : invoiceRows[idx].unitPrice })
  }

  async function onSaveInvoice() {
    const items: GenericSaleItem[] = invoiceRows
      .filter((r) => r.quantity > 0 && (r.itemType === "Service" || r.genericProductId))
      .map((r) => ({ itemType: r.itemType, genericProductId: r.itemType === "Product" ? r.genericProductId ?? null : null, genericServiceId: null, description: r.description || null, quantity: r.quantity, unitPrice: r.unitPrice, discountAmount: r.discountAmount }))
    if (items.length === 0) { toast({ title: "Add at least one item", variant: "destructive" }); return }
    setInvoiceSaving(true)
    try {
      const created = await createSale({
        saleDate: invoiceHeader.saleDate,
        genericCustomerId: invoiceHeader.genericCustomerId ? Number(invoiceHeader.genericCustomerId) : null,
        salesType: invoiceHeader.salesType,
        headerDiscountAmount: Number(invoiceHeader.headerDiscountAmount) || 0,
        taxAmount: Number(invoiceHeader.taxAmount) || 0,
        amountPaid: Number(invoiceHeader.amountPaid) || 0,
        paymentMethod: invoiceHeader.paymentMethod,
        genericCashAccountId: invoiceHeader.genericCashAccountId ? Number(invoiceHeader.genericCashAccountId) : null,
        receiptNumber: invoiceHeader.receiptNumber || null,
        notes: !invoiceHeader.genericCustomerId && invoiceWalkInName.trim()
          ? (invoiceHeader.notes ? `Customer: ${invoiceWalkInName.trim()} | ${invoiceHeader.notes}` : `Customer: ${invoiceWalkInName.trim()}`)
          : (invoiceHeader.notes || null),
        items,
      })
      if (created) {
        toast({ title: `Sale #${created.genericSaleId} created as Draft` })
        setInvoiceRows([blankInvoiceRow()])
        const now = new Date(); const date = now.toISOString().slice(0, 10)
        const pad2 = String(now.getHours()).padStart(2, "0") + String(now.getMinutes()).padStart(2, "0")
        const rand2 = String(Math.floor(Math.random() * 10000)).padStart(4, "0")
        setInvoiceHeader({ saleDate: date, genericCustomerId: "", salesType: "WalkInSale", receiptNumber: `SAL-${date.replace(/-/g, "")}-${pad2}${rand2}`, headerDiscountAmount: "0", taxAmount: "0", amountPaid: "0", paymentMethod: "Cash", genericCashAccountId: invoiceHeader.genericCashAccountId, notes: "" })
        setInvoiceWalkInName("")
        setSalesLoaded(false)
        getProducts().then((ps) => setProducts(ps.filter((p) => p.isActive))).catch(() => {})
      }
    } catch (e: any) { toast({ title: "Could not create sale", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setInvoiceSaving(false) }
  }

  // ---- Sales history state ----
  const [sales, setSales] = useState<GenericSale[]>([])
  const [salesLoaded, setSalesLoaded] = useState(false)
  const [salesSearch, setSalesSearch] = useState("")
  const [salesDateFrom, setSalesDateFrom] = useState("")
  const [salesDateTo, setSalesDateTo] = useState("")
  const [salesSort, setSalesSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })

  // ---- Load data ----
  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard"); return
    }
    Promise.all([getProducts(), getCustomers(), getCashAccounts()])
      .then(([ps, cs, as]) => {
        setProducts(ps.filter((p) => p.isActive))
        setCustomers(cs.filter((c) => c.isActive))
        setCashAccounts(as.filter((a) => a.isActive))
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

  // Lazy-load sales on first tab visit
  useEffect(() => {
    if (tab === "sales") void loadSales()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab])

  async function loadSales() {
    if (salesLoaded) return
    try {
      const data = await getSales(null)
      setSales(data)
      setSalesLoaded(true)
    } catch (e: any) {
      toast({ title: "Could not load sales", description: e?.message, variant: "destructive" })
    }
  }

  // ---- Receipt state ----
  const [receipt, setReceipt] = useState<{
    saleId: number; receiptNumber: string; date: string; customerName: string
    items: { name: string; qty: number; price: number; total: number }[]
    total: number; paid: number; change: number; paymentMethod: string
  } | null>(null)

  // ---- Selected customer (for balance display) ----
  const selectedCustomer = useMemo(
    () => customerId && customerId !== "walk-in" ? customers.find((c) => String(c.genericCustomerId) === customerId) ?? null : null,
    [customerId, customers],
  )

  // ---- POS logic ----
  const filtered = useMemo(() => {
    if (!search.trim()) return products.slice(0, 20)
    const q = search.trim().toLowerCase()
    return products.filter(
      (p) =>
        p.productName.toLowerCase().includes(q) ||
        (p.sku && p.sku.toLowerCase().includes(q)) ||
        (p.barcode && p.barcode.toLowerCase().includes(q))
    )
  }, [products, search])

  const subtotal = cart.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0)
  const total = subtotal
  const received = Number(amountReceived) || 0
  const change = received - total
  const isPaid = received >= total || paymentMethod === "Credit"

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
    setWalkInName("")
    setSearch("")
    searchRef.current?.focus()
  }

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

      const now = new Date()
      const pad = String(now.getHours()).padStart(2, "0") + String(now.getMinutes()).padStart(2, "0")
      const rand = String(Math.floor(Math.random() * 10000)).padStart(4, "0")
      const receiptNumber = `SAL-${now.toISOString().slice(0, 10).replace(/-/g, "")}-${pad}${rand}`

      const sale = await createSale({
        saleDate: now.toISOString().slice(0, 10),
        genericCustomerId: customerId ? Number(customerId) : null,
        salesType: "WalkInSale",
        headerDiscountAmount: 0,
        taxAmount: 0,
        amountPaid: paymentMethod === "Credit" ? 0 : total,
        paymentMethod,
        genericCashAccountId: cashAccountId ? Number(cashAccountId) : null,
        receiptNumber,
        notes: !customerId && walkInName.trim() ? `Customer: ${walkInName.trim()}` : null,
        items,
      })

      if (sale) {
        await approveSale(sale.genericSaleId)

        // Build receipt before clearing the cart
        const custName = selectedCustomer?.customerName ?? (walkInName.trim() || "Walk-in")
        setReceipt({
          saleId: sale.genericSaleId,
          receiptNumber,
          date: now.toLocaleString(),
          customerName: custName,
          items: cart.map((c) => ({ name: c.product.productName, qty: c.quantity, price: c.unitPrice, total: c.quantity * c.unitPrice })),
          total,
          paid: paymentMethod === "Credit" ? 0 : total,
          change: change > 0 ? change : 0,
          paymentMethod,
        })

        toast({
          title: `Sale #${sale.genericSaleId} completed`,
          description: change > 0 ? `Change: ${fmt(change)}` : "Paid in full",
        })
        getProducts().then((ps) => setProducts(ps.filter((p) => p.isActive))).catch(() => {})
        setSalesLoaded(false)
        clearCart()
      }
    } catch (e: any) {
      toast({ title: "Sale failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setCompleting(false)
    }
  }

  const onSearchKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && filtered.length === 1) {
      addToCart(filtered[0])
    }
  }

  // ---- Sales history derived data ----
  const salesStats = useMemo(() => {
    const approved = sales.filter((s) => s.status === "Approved")
    const totalSales = approved.reduce((sum, s) => sum + (s.totalAmount ?? 0), 0)
    const totalPaid = approved.reduce((sum, s) => sum + (s.amountPaid ?? 0), 0)
    const totalOutstanding = approved.reduce((sum, s) => sum + (s.balance ?? 0), 0)
    return { count: sales.length, totalSales, totalPaid, totalOutstanding }
  }, [sales])

  const filteredSales = useMemo(() => {
    return filterByDateAndSearch(sales, {
      search: salesSearch, dateFrom: salesDateFrom, dateTo: salesDateTo,
      searchKeys: ["customerName", "status", "receiptNumber", "notes"],
      dateKey: "saleDate",
    })
  }, [sales, salesSearch, salesDateFrom, salesDateTo])

  const sortedSales = useMemo(() => sortData(filteredSales, salesSort.key, salesSort.direction), [filteredSales, salesSort])
  const pgSales = usePagination(sortedSales)

  // ---- Tab styling (same as inventory page) ----
  const tabTriggerCls =
    "h-auto flex-none shrink-0 gap-1.5 rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 sm:px-4 " +
    "transition-all hover:bg-slate-100 hover:text-slate-900 " +
    "data-[state=active]:bg-blue-600 data-[state=active]:text-white data-[state=active]:shadow-md " +
    "data-[state=active]:shadow-blue-600/25 data-[state=active]:hover:bg-blue-600 data-[state=active]:hover:text-white"
  const tabCountCls =
    "ml-0.5 rounded-full bg-slate-100 px-1.5 py-0.5 text-[11px] font-bold tabular-nums text-slate-600 " +
    "group-data-[state=active]:bg-white/20 group-data-[state=active]:text-white"

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
          <div className="max-w-7xl mx-auto space-y-3">
            {/* Header */}
            <div className="flex items-center justify-between">
              <div>
                <h1 className="text-xl font-bold text-slate-900 sm:text-2xl">Sales &amp; Quick Sale</h1>
                <p className="text-sm text-slate-500">Sell products quickly, and view your sales history.</p>
              </div>
              <div className="flex items-center gap-2">
                <Button variant="outline" asChild>
                  <Link href="/generic-sales/new"><Plus className="w-4 h-4 mr-1" /> New Invoice Sale</Link>
                </Button>
              </div>
            </div>

            <Tabs value={tab} onValueChange={selectTab} className="gap-3">
              {/* KPI cards - show when on sales tab */}
              {tab === "sales" && salesLoaded && (
                <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                  <Kpi icon={<ShoppingCart className="w-4 h-4 text-blue-600" />} label="Total sales"
                    value={gh(salesStats.totalSales)} sub={`${salesStats.count} sale(s)`} />
                  <Kpi icon={<DollarSign className="w-4 h-4 text-emerald-600" />} label="Collected"
                    value={gh(salesStats.totalPaid)} tone="good" sub="amount received" />
                  <Kpi icon={<DollarSign className={cn("w-4 h-4", salesStats.totalOutstanding > 0 ? "text-red-600" : "text-slate-400")} />} label="Outstanding"
                    value={gh(salesStats.totalOutstanding)} tone={salesStats.totalOutstanding > 0 ? "bad" : undefined}
                    sub={salesStats.totalOutstanding > 0 ? "owed by customers" : "nothing owed"} />
                  <Kpi icon={<Zap className="w-4 h-4 text-amber-500" />} label="Cart"
                    value={cart.length > 0 ? `${cart.length} item${cart.length !== 1 ? "s" : ""}` : "Empty"}
                    sub={cart.length > 0 ? fmt(total) : "Switch to Quick Sale to sell"} />
                </div>
              )}

              <TabsList className="h-auto w-full max-w-full justify-start gap-1 overflow-x-auto rounded-xl border border-slate-200 bg-white p-1 shadow-sm sm:w-fit">
                <TabsTrigger value="pos" className={cn("group", tabTriggerCls)}>
                  <Zap className="w-4 h-4" /> Quick Sale
                </TabsTrigger>
                <TabsTrigger value="new-sale" className={cn("group", tabTriggerCls)}>
                  <Plus className="w-4 h-4" /> New Sale
                </TabsTrigger>
                <TabsTrigger value="sales" className={cn("group", tabTriggerCls)}>
                  <History className="w-4 h-4" /> Sales History
                  {salesLoaded && <span className={tabCountCls}>{sales.length.toLocaleString()}</span>}
                </TabsTrigger>
              </TabsList>

              {/* ===== QUICK SALE TAB ===== */}
              <TabsContent value="pos">
                <div className="grid gap-3 lg:grid-cols-5">
                  {/* LEFT: Product search + results (3 cols) */}
                  <div className="lg:col-span-3 space-y-3">
                    <div className="relative">
                      <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                      <Input
                        ref={searchRef}
                        placeholder="Search products by name, SKU or barcode..."
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        onKeyDown={onSearchKeyDown}
                        className="pl-9 h-11 text-base"
                        autoFocus
                      />
                    </div>
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
                              <p className="font-medium text-slate-900 text-sm truncate">{p.productName}</p>
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

                  {/* RIGHT: Cart + Payment (2 cols) */}
                  <div className="lg:col-span-2 space-y-3">
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
                              <div key={item.product.genericProductId} className="flex items-center gap-2 rounded-md border border-slate-100 p-2">
                                <div className="flex-1 min-w-0">
                                  <p className="text-sm font-medium text-slate-900 truncate">{item.product.productName}</p>
                                  <p className="text-xs text-slate-500">
                                    {fmt(item.unitPrice)} x {item.quantity} = {fmt(item.unitPrice * item.quantity)}
                                  </p>
                                </div>
                                <div className="flex items-center gap-1">
                                  <button type="button" onClick={() => updateQuantity(item.product.genericProductId, -1)}
                                    className="flex h-7 w-7 items-center justify-center rounded-md border bg-white hover:bg-slate-50">
                                    <Minus className="h-3 w-3" />
                                  </button>
                                  <span className="w-8 text-center text-sm font-medium">{item.quantity}</span>
                                  <button type="button" onClick={() => updateQuantity(item.product.genericProductId, 1)}
                                    className="flex h-7 w-7 items-center justify-center rounded-md border bg-white hover:bg-slate-50">
                                    <Plus className="h-3 w-3" />
                                  </button>
                                  <button type="button" onClick={() => removeFromCart(item.product.genericProductId)}
                                    className="flex h-7 w-7 items-center justify-center rounded-md text-slate-400 hover:text-red-500">
                                    <X className="h-3.5 w-3.5" />
                                  </button>
                                </div>
                              </div>
                            ))}
                          </div>
                        )}
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

                    <Card>
                      <CardHeader className="py-2 px-3">
                        <CardTitle className="text-sm">Payment</CardTitle>
                      </CardHeader>
                      <CardContent className="px-3 pb-3 space-y-3">
                        <div>
                          <Label className="text-xs text-slate-500">Customer (optional)</Label>
                          <Select value={customerId} onValueChange={(v) => { setCustomerId(v); if (v) setWalkInName("") }}>
                            <SelectTrigger className="h-9"><SelectValue placeholder="Walk-in customer" /></SelectTrigger>
                            <SelectContent>
                              <SelectItem value="walk-in">Walk-in customer</SelectItem>
                              {customers.map((c) => (
                                <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>
                                  <span className="flex items-center gap-2">
                                    <span>{c.customerName}</span>
                                    {c.currentBalance > 0 && (
                                      <span className="text-[10px] font-medium text-red-600 bg-red-50 px-1.5 py-0.5 rounded">owes {fmt(c.currentBalance)}</span>
                                    )}
                                  </span>
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                          {(!customerId || customerId === "walk-in") && (
                            <Input
                              className="mt-1.5 h-9"
                              placeholder="Walk-in customer name (optional)"
                              value={walkInName}
                              onChange={(e) => setWalkInName(e.target.value)}
                            />
                          )}
                          {selectedCustomer && selectedCustomer.currentBalance > 0 && (
                            <div className="mt-1.5 rounded-md border border-red-200 bg-red-50 px-2.5 py-1.5">
                              <span className="text-xs text-red-800">
                                <strong>{selectedCustomer.customerName}</strong> owes <strong className="text-red-700">{fmt(selectedCustomer.currentBalance)}</strong>
                              </span>
                            </div>
                          )}
                        </div>
                        <div>
                          <Label className="text-xs text-slate-500">Payment method</Label>
                          <div className="grid grid-cols-4 gap-1.5 mt-1">
                            {PAY_METHODS.map((m) => (
                              <button key={m} type="button" onClick={() => setPaymentMethod(m)}
                                className={`rounded-md px-2 py-1.5 text-xs font-medium transition ${
                                  paymentMethod === m
                                    ? "bg-indigo-600 text-white"
                                    : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                                }`}>{m}</button>
                            ))}
                          </div>
                        </div>
                        <div>
                          <Label className="text-xs text-slate-500">Cash account</Label>
                          <Select value={cashAccountId} onValueChange={setCashAccountId}>
                            <SelectTrigger className="h-9"><SelectValue placeholder="Select account" /></SelectTrigger>
                            <SelectContent>
                              {cashAccounts.map((a) => (
                                <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName}</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        {paymentMethod !== "Credit" && (
                          <div>
                            <Label className="text-xs text-slate-500">Amount received</Label>
                            <NumberInput step="0.01" min="0" value={amountReceived}
                              onChange={(e) => setAmountReceived(e.target.value)} className="h-9"
                              placeholder={total > 0 ? String(total.toFixed(2)) : "0.00"} />
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
                        {paymentMethod !== "Credit" && total > 0 && (
                          <div className="flex gap-1.5">
                            <Button variant="outline" size="sm" className="flex-1 h-8 text-xs"
                              onClick={() => setAmountReceived(total.toFixed(2))}>
                              Exact ({fmt(total)})
                            </Button>
                            {total <= 500 && (
                              <>
                                <Button variant="outline" size="sm" className="flex-1 h-8 text-xs"
                                  onClick={() => setAmountReceived(String(Math.ceil(total / 5) * 5))}>
                                  {fmt(Math.ceil(total / 5) * 5)}
                                </Button>
                                <Button variant="outline" size="sm" className="flex-1 h-8 text-xs"
                                  onClick={() => setAmountReceived(String(Math.ceil(total / 10) * 10))}>
                                  {fmt(Math.ceil(total / 10) * 10)}
                                </Button>
                              </>
                            )}
                          </div>
                        )}
                        <Button className="w-full h-12 text-base font-semibold"
                          disabled={cart.length === 0 || completing || (!isPaid && paymentMethod !== "Credit")}
                          onClick={completeSale}>
                          {completing ? (
                            <><Loader2 className="h-5 w-5 mr-2 animate-spin" /> Processing...</>
                          ) : (
                            <><Check className="h-5 w-5 mr-2" /> Complete Sale {total > 0 ? `— ${fmt(total)}` : ""}</>
                          )}
                        </Button>
                      </CardContent>
                    </Card>
                  </div>
                </div>
              </TabsContent>

              {/* ===== NEW SALE (INVOICE) TAB ===== */}
              <TabsContent value="new-sale">
                <div className="space-y-4">
                  {/* Header */}
                  <Card>
                    <CardContent className="grid grid-cols-1 md:grid-cols-4 gap-3 pt-6">
                      <div>
                        <Label className="text-xs text-slate-500">Sale date</Label>
                        <Input type="date" value={invoiceHeader.saleDate} onChange={(e) => setInvoiceHeader((h) => ({ ...h, saleDate: e.target.value }))} />
                      </div>
                      <div>
                        <Label className="text-xs text-slate-500">Sales type</Label>
                        <Select value={invoiceHeader.salesType} onValueChange={(v) => setInvoiceHeader((h) => ({ ...h, salesType: v }))}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>{SALES_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                        </Select>
                      </div>
                      <div>
                        <Label className="text-xs text-slate-500">Customer</Label>
                        <Select value={invoiceHeader.genericCustomerId || "__walk_in__"} onValueChange={(v) => { setInvoiceHeader((h) => ({ ...h, genericCustomerId: v === "__walk_in__" ? "" : v })); if (v !== "__walk_in__") setInvoiceWalkInName("") }}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="__walk_in__">-- Walk-in --</SelectItem>
                            {customers.map((c) => (
                              <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>
                                <span className="flex items-center gap-2">
                                  {c.customerName}
                                  {c.currentBalance > 0 && <span className="text-[10px] text-red-600 bg-red-50 px-1.5 py-0.5 rounded">owes {fmt(c.currentBalance)}</span>}
                                </span>
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        {!invoiceHeader.genericCustomerId && (
                          <Input className="mt-1.5" placeholder="Walk-in customer name (optional)" value={invoiceWalkInName} onChange={(e) => setInvoiceWalkInName(e.target.value)} />
                        )}
                      </div>
                      <div>
                        <Label className="text-xs text-slate-500">Receipt no.</Label>
                        <Input value={invoiceHeader.receiptNumber} onChange={(e) => setInvoiceHeader((h) => ({ ...h, receiptNumber: e.target.value }))} maxLength={60} />
                      </div>
                    </CardContent>
                  </Card>

                  {/* Line items */}
                  <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                      <CardTitle className="text-base">Items</CardTitle>
                      <Button size="sm" variant="outline" onClick={() => setInvoiceRows((rs) => [...rs, blankInvoiceRow()])}>
                        <Plus className="h-4 w-4 mr-1" /> Add row
                      </Button>
                    </CardHeader>
                    <CardContent className="p-0">
                      <div className="hidden lg:block">
                        <Table>
                          <TableHeader><TableRow>
                            <TableHead className="w-[110px]">Type</TableHead>
                            <TableHead>Product</TableHead>
                            <TableHead className="w-[110px] text-right">Qty</TableHead>
                            <TableHead className="w-[130px] text-right">Unit price</TableHead>
                            <TableHead className="w-[130px] text-right">Discount</TableHead>
                            <TableHead className="w-[130px] text-right">Line total</TableHead>
                            <TableHead className="w-[40px]"></TableHead>
                          </TableRow></TableHeader>
                          <TableBody>
                            {invoiceRows.map((r, idx) => {
                              const line = r.quantity * r.unitPrice - r.discountAmount
                              return (
                                <TableRow key={idx}>
                                  <TableCell>
                                    <Select value={r.itemType} onValueChange={(v) => updateInvoiceRow(idx, { itemType: v as "Product" | "Service" })}>
                                      <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
                                      <SelectContent><SelectItem value="Product">Product</SelectItem><SelectItem value="Service">Service</SelectItem></SelectContent>
                                    </Select>
                                  </TableCell>
                                  <TableCell>
                                    {r.itemType === "Product" ? (
                                      <Select value={r.genericProductId ? String(r.genericProductId) : ""} onValueChange={(v) => onPickInvoiceProduct(idx, v)}>
                                        <SelectTrigger className="h-8"><SelectValue placeholder="-- select --" /></SelectTrigger>
                                        <SelectContent>{products.map((p) => <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>{p.productName}{p.sku ? ` (${p.sku})` : ""}</SelectItem>)}</SelectContent>
                                      </Select>
                                    ) : (
                                      <Input className="h-8" value={r.description} onChange={(e) => updateInvoiceRow(idx, { description: e.target.value })} placeholder="Service description" />
                                    )}
                                  </TableCell>
                                  <TableCell><NumberInput className="h-8 text-right" step="0.001" min="0" value={r.quantity} onChange={(e) => updateInvoiceRow(idx, { quantity: Number(e.target.value) || 0 })} /></TableCell>
                                  <TableCell><NumberInput className="h-8 text-right" step="0.01" min="0" value={r.unitPrice} onChange={(e) => updateInvoiceRow(idx, { unitPrice: Number(e.target.value) || 0 })} /></TableCell>
                                  <TableCell><NumberInput className="h-8 text-right" step="0.01" min="0" value={r.discountAmount} onChange={(e) => updateInvoiceRow(idx, { discountAmount: Number(e.target.value) || 0 })} /></TableCell>
                                  <TableCell className="text-right font-semibold">{fmt(line)}</TableCell>
                                  <TableCell><Button size="icon" variant="ghost" onClick={() => setInvoiceRows((rs) => rs.filter((_, i) => i !== idx))}><X className="h-4 w-4 text-rose-600" /></Button></TableCell>
                                </TableRow>
                              )
                            })}
                          </TableBody>
                        </Table>
                      </div>
                      {/* Mobile card stack */}
                      <div className="lg:hidden p-3 space-y-3">
                        {invoiceRows.map((r, idx) => {
                          const line = r.quantity * r.unitPrice - r.discountAmount
                          return (
                            <div key={idx} className="rounded-lg border p-3 space-y-3">
                              <div className="flex items-center gap-2">
                                <Select value={r.itemType} onValueChange={(v) => updateInvoiceRow(idx, { itemType: v as "Product" | "Service" })}>
                                  <SelectTrigger className="h-9 w-28 shrink-0"><SelectValue /></SelectTrigger>
                                  <SelectContent><SelectItem value="Product">Product</SelectItem><SelectItem value="Service">Service</SelectItem></SelectContent>
                                </Select>
                                <div className="flex-1 min-w-0">
                                  {r.itemType === "Product" ? (
                                    <Select value={r.genericProductId ? String(r.genericProductId) : ""} onValueChange={(v) => onPickInvoiceProduct(idx, v)}>
                                      <SelectTrigger className="h-9"><SelectValue placeholder="-- select --" /></SelectTrigger>
                                      <SelectContent>{products.map((p) => <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>{p.productName}</SelectItem>)}</SelectContent>
                                    </Select>
                                  ) : (
                                    <Input className="h-9" value={r.description} onChange={(e) => updateInvoiceRow(idx, { description: e.target.value })} placeholder="Service description" />
                                  )}
                                </div>
                                <Button size="icon" variant="ghost" className="shrink-0" onClick={() => setInvoiceRows((rs) => rs.filter((_, i) => i !== idx))}><X className="h-4 w-4 text-rose-600" /></Button>
                              </div>
                              <div className="grid grid-cols-2 gap-2">
                                <div><label className="text-xs text-slate-500">Qty</label><NumberInput className="h-9 text-right" step="0.001" min="0" value={r.quantity} onChange={(e) => updateInvoiceRow(idx, { quantity: Number(e.target.value) || 0 })} /></div>
                                <div><label className="text-xs text-slate-500">Unit price</label><NumberInput className="h-9 text-right" step="0.01" min="0" value={r.unitPrice} onChange={(e) => updateInvoiceRow(idx, { unitPrice: Number(e.target.value) || 0 })} /></div>
                                <div><label className="text-xs text-slate-500">Discount</label><NumberInput className="h-9 text-right" step="0.01" min="0" value={r.discountAmount} onChange={(e) => updateInvoiceRow(idx, { discountAmount: Number(e.target.value) || 0 })} /></div>
                                <div><label className="text-xs text-slate-500">Line total</label><div className="h-9 flex items-center justify-end font-semibold tabular-nums pr-2">{fmt(line)}</div></div>
                              </div>
                            </div>
                          )
                        })}
                      </div>
                    </CardContent>
                  </Card>

                  {/* Payment + Totals */}
                  <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    <Card>
                      <CardHeader className="pb-2"><CardTitle className="text-base">Payment</CardTitle></CardHeader>
                      <CardContent className="grid grid-cols-2 gap-3">
                        <div><Label className="text-xs text-slate-500">Discount (header)</Label><NumberInput step="0.01" min="0" value={invoiceHeader.headerDiscountAmount} onChange={(e) => setInvoiceHeader((h) => ({ ...h, headerDiscountAmount: e.target.value }))} /></div>
                        <div><Label className="text-xs text-slate-500">Tax</Label><NumberInput step="0.01" min="0" value={invoiceHeader.taxAmount} onChange={(e) => setInvoiceHeader((h) => ({ ...h, taxAmount: e.target.value }))} /></div>
                        <div><Label className="text-xs text-slate-500">Amount paid</Label><NumberInput step="0.01" min="0" value={invoiceHeader.amountPaid} onChange={(e) => setInvoiceHeader((h) => ({ ...h, amountPaid: e.target.value }))} /></div>
                        <div>
                          <Label className="text-xs text-slate-500">Method</Label>
                          <Select value={invoiceHeader.paymentMethod} onValueChange={(v) => setInvoiceHeader((h) => ({ ...h, paymentMethod: v }))}>
                            <SelectTrigger><SelectValue /></SelectTrigger>
                            <SelectContent>{PAY_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                          </Select>
                        </div>
                        <div className="col-span-2">
                          <Label className="text-xs text-slate-500">Cash account</Label>
                          <Select value={invoiceHeader.genericCashAccountId || "__none__"} onValueChange={(v) => setInvoiceHeader((h) => ({ ...h, genericCashAccountId: v === "__none__" ? "" : v }))}>
                            <SelectTrigger><SelectValue /></SelectTrigger>
                            <SelectContent>
                              <SelectItem value="__none__">-- none / credit sale --</SelectItem>
                              {cashAccounts.map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName}</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="col-span-2"><Label className="text-xs text-slate-500">Notes</Label><Input value={invoiceHeader.notes} onChange={(e) => setInvoiceHeader((h) => ({ ...h, notes: e.target.value }))} /></div>
                      </CardContent>
                    </Card>
                    <Card>
                      <CardHeader className="pb-2"><CardTitle className="text-base">Totals</CardTitle></CardHeader>
                      <CardContent>
                        <dl className="space-y-1 text-sm">
                          <div className="flex justify-between"><dt className="text-slate-600">Subtotal</dt><dd className="tabular-nums">{fmt(invoiceTotals.subtotal)}</dd></div>
                          <div className="flex justify-between"><dt className="text-slate-600">Discount</dt><dd className="tabular-nums">{fmt(invoiceTotals.disc)}</dd></div>
                          <div className="flex justify-between"><dt className="text-slate-600">Tax</dt><dd className="tabular-nums">{fmt(invoiceTotals.tax)}</dd></div>
                          <div className="flex justify-between font-semibold"><dt>Total</dt><dd className="tabular-nums">{fmt(invoiceTotals.total)}</dd></div>
                          <div className="flex justify-between"><dt className="text-slate-600">Paid</dt><dd className="tabular-nums text-emerald-700">{fmt(invoiceTotals.paid)}</dd></div>
                          <div className="flex justify-between"><dt className="text-slate-600">Balance</dt><dd className={cn("tabular-nums", invoiceTotals.balance > 0 ? "text-red-600 font-bold" : "")}>{fmt(invoiceTotals.balance)}</dd></div>
                        </dl>
                        <div className="flex justify-end gap-2 mt-4">
                          <Button onClick={onSaveInvoice} disabled={invoiceSaving}>
                            {invoiceSaving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
                            Create as Draft
                          </Button>
                        </div>
                      </CardContent>
                    </Card>
                  </div>
                </div>
              </TabsContent>

              {/* ===== SALES HISTORY TAB ===== */}
              <TabsContent value="sales">
                <Card><CardContent className="space-y-3 p-3 sm:p-4">
                  <ListFilters search={salesSearch} setSearch={setSalesSearch}
                    dateFrom={salesDateFrom} setDateFrom={setSalesDateFrom}
                    dateTo={salesDateTo} setDateTo={setSalesDateTo}
                    searchPlaceholder="Search customer, receipt or notes" />

                  {!salesLoaded ? (
                    <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading sales...</div>
                  ) : filteredSales.length === 0 ? (
                    <div className="py-8 text-center text-slate-500">
                      {sales.length === 0
                        ? <>No sales yet. Use Quick Sale to record your first one.</>
                        : "No sales match these filters."}
                    </div>
                  ) : (
                    <>
                      {/* Desktop table */}
                      <div className="hidden md:block overflow-x-auto"><Table>
                        <TableHeader><TableRow>
                          {(() => { const onSort = (k: string) => setSalesSort((s) => toggleSort(k, s.key, s.direction)); const cs = salesSort.key, cd = salesSort.direction; return (<>
                          <TableHead>#</TableHead>
                          <SortableHeader label="Date" sortKey="saleDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                          <SortableHeader label="Customer" sortKey="customerName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                          <TableHead className="text-xs">Type</TableHead>
                          <SortableHeader label="Total" sortKey="totalAmount" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                          <SortableHeader label="Paid" sortKey="amountPaid" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                          <SortableHeader label="Balance" sortKey="balance" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                          <TableHead>Status</TableHead>
                          <TableHead></TableHead>
                          </>) })()}
                        </TableRow></TableHeader>
                        <TableBody>
                          {pgSales.pageItems.map((s) => (
                            <TableRow key={s.genericSaleId}>
                              <TableCell><Link href={`/generic-sales/${s.genericSaleId}`} className="text-emerald-700 underline">#{s.genericSaleId}</Link></TableCell>
                              <TableCell className="whitespace-nowrap text-sm">{fmtDateTime(s.saleDate, s)}</TableCell>
                              <TableCell>{s.customerName ?? <span className="text-slate-500">{displayCustomer(s)}</span>}</TableCell>
                              <TableCell className="text-xs text-slate-500">{s.salesType}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(s.totalAmount)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(s.amountPaid)}</TableCell>
                              <TableCell className={cn("text-right tabular-nums", s.balance > 0 && "text-red-600 font-semibold")}>{gh(s.balance)}</TableCell>
                              <TableCell><Badge className={statusBadgeClass(s.status)}>{s.status}</Badge></TableCell>
                              <TableCell><Button asChild size="sm" variant="ghost"><Link href={`/generic-sales/${s.genericSaleId}`}>Details</Link></Button></TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table></div>

                      {/* Mobile cards */}
                      <div className="md:hidden space-y-2">
                        {pgSales.pageItems.map((s) => (
                          <div key={s.genericSaleId} className="rounded-lg border border-slate-200 p-3">
                            <div className="flex items-center justify-between gap-2">
                              <Link href={`/generic-sales/${s.genericSaleId}`} className="font-medium text-emerald-700 underline">
                                #{s.genericSaleId} · {displayCustomer(s)}
                              </Link>
                              <Badge className={statusBadgeClass(s.status)}>{s.status}</Badge>
                            </div>
                            <div className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-sm">
                              <div><span className="text-slate-500">Date: </span>{fmtDateTime(s.saleDate, s)}</div>
                              <div><span className="text-slate-500">Type: </span>{s.salesType}</div>
                              <div><span className="text-slate-500">Total: </span><span className="tabular-nums">{gh(s.totalAmount)}</span></div>
                              <div><span className="text-slate-500">Paid: </span><span className="tabular-nums">{gh(s.amountPaid)}</span></div>
                              {s.balance > 0 && (
                                <div className="col-span-2"><span className="text-slate-500">Balance: </span><span className="text-red-600 font-semibold tabular-nums">{gh(s.balance)}</span></div>
                              )}
                            </div>
                            <div className="mt-2 flex justify-end border-t pt-2">
                              <Button asChild size="sm" variant="outline"><Link href={`/generic-sales/${s.genericSaleId}`}>Details</Link></Button>
                            </div>
                          </div>
                        ))}
                      </div>
                      <DataPagination {...pgSales.paginationProps} />
                    </>
                  )}
                </CardContent></Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      {/* ===== RECEIPT DIALOG ===== */}
      <Dialog open={!!receipt} onOpenChange={(o) => !o && setReceipt(null)}>
        <DialogContent className="max-w-md print:max-w-none print:shadow-none print:border-0">
          <DialogHeader className="print:hidden">
            <DialogTitle>Sale Receipt</DialogTitle>
          </DialogHeader>
          {receipt && (
            <div id="pos-receipt" className="space-y-3 text-sm">
              {/* Receipt header */}
              <div className="text-center border-b pb-3">
                <h2 className="text-lg font-bold text-slate-900">SALES RECEIPT</h2>
                <p className="text-xs text-slate-500 mt-1">Receipt: {receipt.receiptNumber}</p>
                <p className="text-xs text-slate-500">Date: {receipt.date}</p>
                <p className="text-xs text-slate-500">Customer: {receipt.customerName}</p>
              </div>

              {/* Items */}
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-xs text-slate-500">
                    <th className="text-left py-1">Item</th>
                    <th className="text-right py-1">Qty</th>
                    <th className="text-right py-1">Price</th>
                    <th className="text-right py-1">Total</th>
                  </tr>
                </thead>
                <tbody>
                  {receipt.items.map((item, i) => (
                    <tr key={i} className="border-b border-dashed">
                      <td className="py-1.5">{item.name}</td>
                      <td className="text-right tabular-nums">{item.qty}</td>
                      <td className="text-right tabular-nums">{fmt(item.price)}</td>
                      <td className="text-right tabular-nums font-medium">{fmt(item.total)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>

              {/* Totals */}
              <div className="border-t pt-2 space-y-1">
                <div className="flex justify-between font-bold text-base">
                  <span>Total</span>
                  <span className="tabular-nums">{fmt(receipt.total)}</span>
                </div>
                <div className="flex justify-between text-slate-600">
                  <span>Paid ({receipt.paymentMethod})</span>
                  <span className="tabular-nums">{fmt(receipt.paid)}</span>
                </div>
                {receipt.change > 0 && (
                  <div className="flex justify-between text-emerald-700 font-medium">
                    <span>Change</span>
                    <span className="tabular-nums">{fmt(receipt.change)}</span>
                  </div>
                )}
              </div>

              {/* Footer */}
              <div className="text-center border-t pt-3">
                <p className="text-xs text-slate-400">Sale #{receipt.saleId}</p>
                <p className="text-xs text-slate-400">Thank you for your purchase!</p>
              </div>
            </div>
          )}
          <div className="flex justify-end gap-2 print:hidden">
            <Button variant="outline" onClick={() => setReceipt(null)}>Close</Button>
            <Button onClick={() => window.print()}>
              <Printer className="w-4 h-4 mr-1" /> Print Receipt
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

export default function GenericPosPage() {
  return (
    <Suspense fallback={<div className="flex items-center gap-2 p-8 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>}>
      <GenericPosPageInner />
    </Suspense>
  )
}

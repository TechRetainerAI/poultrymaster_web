"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Minus, Trash2, Search, ShoppingCart, CreditCard, Banknote, X, Check, UtensilsCrossed, Smartphone, Users, Printer, Download, Mail } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { TakePaymentDialog, type PaymentResult } from "@/components/restaurant/order-money-dialogs"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listMenuCategories, listMenuItems, listTables, listCustomers,
  createOrder, addOrderItem, recalcOrder,
  updateOrderStatus, listOrderItems, getOrder, getReceiptTemplate,
  createLoyaltyAccount,
  type MenuCategory, type MenuItem, type RestaurantTable,
  type OrderItem, type Order, type Customer, type ReceiptTemplate,
} from "@/lib/api/restaurant"
import jsPDF from "jspdf"
import autoTable from "jspdf-autotable"

interface CartItem {
  menuItemId: number; name: string; price: number; quantity: number
  notes: string; modifiers: { modifierId: number; name: string; price: number }[]
}

export default function RestaurantPOSPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [categories, setCategories] = useState<MenuCategory[]>([])
  const [items, setItems] = useState<MenuItem[]>([])
  const [tables, setTables] = useState<RestaurantTable[]>([])
  const [selectedCat, setSelectedCat] = useState<number | null>(null)
  const [search, setSearch] = useState("")
  const [cart, setCart] = useState<CartItem[]>([])
  const [orderType, setOrderType] = useState("DineIn")
  const [selectedTable, setSelectedTable] = useState<number | null>(null)
  const [customers, setCustomers] = useState<Customer[]>([])
  const [selectedCustomerId, setSelectedCustomerId] = useState<number | null>(null)
  const [customerName, setCustomerName] = useState("")
  const [covers, setCovers] = useState(1)
  const [activeOrder, setActiveOrder] = useState<Order | null>(null)
  const [activeOrderItems, setActiveOrderItems] = useState<OrderItem[]>([])
  const [payDialogOpen, setPayDialogOpen] = useState(false)
  const [receiptTemplate, setReceiptTemplate] = useState<ReceiptTemplate | null>(null)
  const [receiptDialogOpen, setReceiptDialogOpen] = useState(false)
  // `amount` is what the customer handed over; `change` what went back. Only the
  // part applied to the bill is recorded as a payment (migration 323).
  const [receiptOrder, setReceiptOrder] = useState<{order: Order, items: OrderItem[], payment: {method: string, amount: number, tip: number, change: number}} | null>(null)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadData()
  }, [activeFarmType, router])

  async function loadData() {
    setLoading(true)
    try {
      const [cats, itms, tbls, custs, tmpl] = await Promise.all([listMenuCategories(), listMenuItems(), listTables(undefined, "Available"), listCustomers().catch(() => []), getReceiptTemplate().catch(() => null)])
      setCategories(cats); setItems(itms.filter(i => i.isAvailable && i.isActive)); setTables(tbls); setCustomers(custs); setReceiptTemplate(tmpl)
    } catch (e: any) { toast({ title: "Failed to load", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const filteredItems = items.filter(i => {
    if (selectedCat && i.menuCategoryId !== selectedCat) return false
    if (search && !i.name.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })

  function addToCart(item: MenuItem) {
    const existing = cart.find(c => c.menuItemId === item.menuItemId && c.modifiers.length === 0)
    if (existing) setCart(cart.map(c => c === existing ? { ...c, quantity: c.quantity + 1 } : c))
    else setCart([...cart, { menuItemId: item.menuItemId, name: item.name, price: item.price, quantity: 1, notes: "", modifiers: [] }])
  }
  function updateCartQty(index: number, delta: number) { setCart(cart.map((c, i) => i === index ? { ...c, quantity: Math.max(1, c.quantity + delta) } : c)) }
  function removeFromCart(index: number) { setCart(cart.filter((_, i) => i !== index)) }
  const cartSubtotal = cart.reduce((sum, c) => sum + (c.price + c.modifiers.reduce((ms, m) => ms + m.price, 0)) * c.quantity, 0)

  async function placeOrder() {
    if (cart.length === 0) { toast({ title: "Cart is empty", variant: "destructive" }); return }
    try {
      const tableNum = selectedTable ? tables.find(t => t.tableId === selectedTable)?.tableNumber : undefined
      const { orderId, orderNumber } = await createOrder({ orderType, tableId: selectedTable, tableNumber: tableNum, customerId: selectedCustomerId || undefined, customerName: customerName || undefined, covers })
      for (const item of cart) {
        await addOrderItem(orderId, { menuItemId: item.menuItemId, itemName: item.name, quantity: item.quantity, unitPrice: item.price, notes: item.notes || undefined,
          modifiers: item.modifiers.map(m => ({ modifierId: m.modifierId, modifierName: m.name, priceAdjustment: m.price, quantity: 1 })) })
      }
      // No rates: the server applies the tax and service-charge rates saved in
      // Restaurant Setup. Passing 0/0 here is what kept them from ever applying.
      await recalcOrder(orderId)
      // Auto-enrol customer in loyalty if they have a name
      if (selectedCustomerId || customerName) {
        try { await createLoyaltyAccount(customerName || "Guest", undefined, selectedCustomerId || undefined) } catch { /* already enrolled or loyalty disabled */ }
      }
      toast({ title: `Order ${orderNumber} placed!` })
      const [order, orderItems] = await Promise.all([getOrder(orderId), listOrderItems(orderId)])
      setActiveOrder(order); setActiveOrderItems(orderItems); setCart([]); setTables(await listTables(undefined, "Available"))
    } catch (e: any) { toast({ title: "Order failed", description: e?.message, variant: "destructive" }) }
  }

  /**
   * The payment is already recorded when this runs. The order is completed only
   * once it is fully paid -- the server refuses to complete an unpaid order -- so
   * a part payment keeps the order on screen with the balance still due.
   */
  async function handlePaid({ order, payment }: PaymentResult) {
    setPayDialogOpen(false)
    if (order.paymentStatus !== "Paid") {
      setActiveOrder(order)
      toast({ title: `${payment.applied.toFixed(2)} received`, description: `${(order.totalAmount - order.paidAmount).toFixed(2)} still due on ${order.orderNumber}.` })
      return
    }
    try {
      await updateOrderStatus(order.orderId, "Completed")
      toast({ title: "Payment recorded & order completed" })
      setReceiptOrder({ order, items: [...activeOrderItems], payment: { method: payment.method, amount: payment.tendered, tip: payment.tip, change: payment.change } })
      setReceiptDialogOpen(true)
      setActiveOrder(null); setActiveOrderItems([]); setTables(await listTables(undefined, "Available"))
    } catch (e: any) { toast({ title: "Paid, but the order could not be completed", description: e?.message, variant: "destructive" }) }
  }

  const activeFarmName = useAuthStore((s) => s.activeFarmName) || "Restaurant"

  function printReceipt() {
    const content = document.getElementById("receipt-content")
    if (!content) return
    const win = window.open("", "_blank", "width=300,height=600")
    if (!win) return
    win.document.write(`<html><head><title>Receipt</title><style>
      body { font-family: 'Courier New', monospace; font-size: 12px; width: 280px; margin: 0 auto; padding: 10px; }
      .center { text-align: center; }
      .bold { font-weight: bold; }
      .line { border-top: 1px dashed #000; margin: 8px 0; }
      .row { display: flex; justify-content: space-between; }
      .total-row { display: flex; justify-content: space-between; font-weight: bold; font-size: 14px; }
      h2 { margin: 0; font-size: 16px; }
      p { margin: 2px 0; }
    </style></head><body>`)
    win.document.write(content.innerHTML)
    win.document.write("</body></html>")
    win.document.close()
    win.print()
  }

  function downloadInvoice() {
    if (!receiptOrder) return
    const { order, items, payment } = receiptOrder
    const doc = new jsPDF({ format: "a5", unit: "mm" })
    const pageW = doc.internal.pageSize.getWidth()
    let y = 15

    // Header
    doc.setFontSize(16)
    doc.setFont("helvetica", "bold")
    doc.text(activeFarmName, pageW / 2, y, { align: "center" }); y += 7
    if (receiptTemplate?.headerText) {
      doc.setFontSize(9); doc.setFont("helvetica", "normal")
      doc.text(receiptTemplate.headerText, pageW / 2, y, { align: "center" }); y += 5
    }
    doc.setFontSize(10); doc.setFont("helvetica", "normal")
    doc.text("INVOICE / RECEIPT", pageW / 2, y, { align: "center" }); y += 8

    // Order info
    doc.setFontSize(9)
    const orderDate = order.createdAt ? new Date(order.createdAt).toLocaleString() : new Date().toLocaleString()
    doc.text(`Date: ${orderDate}`, 10, y); y += 5
    doc.text(`Order: ${order.orderNumber}`, 10, y); y += 5
    doc.text(`Type: ${order.orderType}${order.tableNumber ? ` | Table ${order.tableNumber}` : ""}`, 10, y); y += 5
    if (order.customerName) { doc.text(`Customer: ${order.customerName}`, 10, y); y += 5 }
    y += 3

    // Items table
    autoTable(doc, {
      startY: y,
      head: [["Qty", "Item", "Price"]],
      body: items.map(i => [String(i.quantity), i.itemName, i.lineTotal.toFixed(2)]),
      theme: "plain",
      styles: { fontSize: 9, cellPadding: 1.5 },
      headStyles: { fontStyle: "bold", fillColor: [240, 240, 240] },
      columnStyles: { 0: { cellWidth: 12, halign: "center" }, 2: { cellWidth: 22, halign: "right" } },
      margin: { left: 10, right: 10 },
    })
    y = (doc as any).lastAutoTable.finalY + 5

    // Totals
    const rightX = pageW - 10
    doc.text(`Subtotal:`, rightX - 40, y); doc.text(order.subtotal.toFixed(2), rightX, y, { align: "right" }); y += 5
    if (order.discountAmount > 0) { doc.text(`Discount:`, rightX - 40, y); doc.text(`-${order.discountAmount.toFixed(2)}`, rightX, y, { align: "right" }); y += 5 }
    if (order.serviceChargeAmount > 0) { doc.text(`Service:`, rightX - 40, y); doc.text(order.serviceChargeAmount.toFixed(2), rightX, y, { align: "right" }); y += 5 }
    if (order.taxAmount > 0) { doc.text(`Tax:`, rightX - 40, y); doc.text(order.taxAmount.toFixed(2), rightX, y, { align: "right" }); y += 5 }
    doc.setFont("helvetica", "bold"); doc.setFontSize(11)
    doc.text(`Total:`, rightX - 40, y); doc.text(order.totalAmount.toFixed(2), rightX, y, { align: "right" }); y += 7
    doc.setFont("helvetica", "normal"); doc.setFontSize(9)

    // Payment info
    doc.text(`Payment: ${payment.method}`, 10, y); y += 5
    doc.text(`Amount Paid: ${payment.amount.toFixed(2)}`, 10, y); y += 5
    if (payment.change > 0) {
      doc.text(`Change: ${payment.change.toFixed(2)}`, 10, y); y += 5
    }
    if (payment.tip > 0) { doc.text(`Tip: ${payment.tip.toFixed(2)}`, 10, y); y += 5 }
    y += 5

    // Footer
    doc.setFontSize(9)
    doc.text("Thank you for dining with us!", pageW / 2, y, { align: "center" }); y += 5
    if (receiptTemplate?.footerText) { doc.text(receiptTemplate.footerText, pageW / 2, y, { align: "center" }); y += 5 }
    doc.setFontSize(7); doc.setTextColor(150)
    doc.text("Powered by PoultryMaster", pageW / 2, y, { align: "center" })

    doc.save(`Receipt_${order.orderNumber}.pdf`)
  }

  async function emailReceipt() {
    if (!receiptOrder) return
    const { order } = receiptOrder
    // Find customer email
    const cust = customers.find(c => c.customerId === order.customerId)
    const email = cust?.email
    if (!email) { toast({ title: "No email", description: "This customer has no email address on file.", variant: "destructive" }); return }
    try {
      // Generate PDF blob
      const doc = new jsPDF({ format: "a5", unit: "mm" })
      const pageW = doc.internal.pageSize.getWidth()
      let y = 15
      doc.setFontSize(16); doc.setFont("helvetica", "bold")
      // Same header the PRINTED receipt builds above: the active company name, then
      // the configured header line. `receiptTemplate.restaurantName` used to be read
      // here, but that field does not exist — restaurantreceipttemplates has no such
      // column (migration 229) — so every emailed receipt was headed with the literal
      // word "Restaurant" instead of the venue name.
      doc.text(activeFarmName, pageW / 2, y, { align: "center" }); y += 7
      if (receiptTemplate?.headerText) {
        doc.setFontSize(8)
        doc.text(receiptTemplate.headerText, pageW / 2, y, { align: "center" }); y += 5
        doc.setFontSize(9)
      }
      doc.setFontSize(9); doc.setFont("helvetica", "normal")
      doc.text(`Order: ${order.orderNumber} | ${order.orderType}${order.tableNumber ? ` | Table ${order.tableNumber}` : ""}`, pageW / 2, y, { align: "center" }); y += 5
      doc.text(new Date(order.createdAt).toLocaleString(), pageW / 2, y, { align: "center" }); y += 8
      autoTable(doc, { startY: y, head: [["Item", "Qty", "Price", "Total"]], body: receiptOrder.items.map(oi => [oi.itemName, oi.quantity, oi.unitPrice.toFixed(2), oi.lineTotal.toFixed(2)]), theme: "grid", headStyles: { fillColor: [190, 18, 60] }, margin: { left: 10, right: 10 }, styles: { fontSize: 8 } })
      y = (doc as any).lastAutoTable.finalY + 5
      doc.setFontSize(10)
      doc.text(`Total: ${order.totalAmount.toFixed(2)}`, pageW - 10, y, { align: "right" }); y += 8
      doc.setFontSize(9)
      doc.text("Thank you for dining with us!", pageW / 2, y, { align: "center" })
      const blob = doc.output("blob") as Blob

      // sendReportEmail takes `blob` + `filename`. This used to pass a `file:` property
      // that does not exist on SendReportEmailInput, which left input.blob undefined —
      // and FormData.append(name, undefined, filename) THROWS, so emailing a receipt
      // failed 100% of the time and surfaced as a misleading "Email failed" toast.
      // Shape and extra fields now match lib/utils/pdf-export.ts (the Poultry/Water path).
      const { sendReportEmail } = await import("@/lib/api/email")
      const res = await sendReportEmail({
        blob,
        filename: `Receipt_${order.orderNumber}.pdf`,
        to: email,
        subject: `Your Receipt — Order ${order.orderNumber}`,
        body: `<p>Dear ${cust.name},</p><p>Please find your receipt attached for Order ${order.orderNumber}.</p><p>Thank you for dining with us!</p>`,
        farmName: activeFarmName || undefined,
        reportTitle: `Receipt ${order.orderNumber}`,
        senderName: activeFarmName || undefined,
      })

      // /api/Email/Report answers 400/500/503 on failure, so success is real and not assumed.
      if (!res.success) {
        toast({ title: "Email failed", description: res.message || "The receipt could not be sent.", variant: "destructive" })
        return
      }
      toast({ title: "Receipt emailed", description: `Sent to ${email}` })
    } catch (e: any) { toast({ title: "Email failed", description: e?.message, variant: "destructive" }) }
  }

  if (loading) return <PageSkeleton />

  return (
    <div className="flex min-h-screen lg:h-screen bg-gray-100">
      <DashboardSidebar />
      <div className="flex-1 min-w-0 flex flex-col lg:overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 lg:overflow-hidden pb-20 lg:pb-0">
          <div className="lg:h-full flex flex-col lg:flex-row">
            {/* LEFT: Menu items */}
            <div className="flex-1 min-h-0 flex flex-col lg:overflow-hidden bg-white">
              {/* Category pills */}
              <div className="p-3 border-b flex gap-2 overflow-x-auto flex-shrink-0 bg-gray-50">
                <Button variant={selectedCat === null ? "default" : "outline"} size="sm" onClick={() => setSelectedCat(null)} className={selectedCat === null ? "bg-rose-600 hover:bg-rose-700" : ""}>All</Button>
                {categories.filter(c => c.isActive).map(c => (
                  <Button key={c.menuCategoryId} variant={selectedCat === c.menuCategoryId ? "default" : "outline"} size="sm" onClick={() => setSelectedCat(c.menuCategoryId)}
                    className={selectedCat === c.menuCategoryId ? "bg-rose-600 hover:bg-rose-700" : ""}>{c.name}</Button>
                ))}
              </div>
              {/* Search */}
              <div className="p-3 border-b flex-shrink-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input className="pl-9 h-10 bg-gray-50" placeholder="Search menu items..." value={search} onChange={e => setSearch(e.target.value)} />
                </div>
              </div>
              {/* Item grid */}
              <div className="flex-1 lg:overflow-y-auto p-3">
                {filteredItems.length === 0 ? (
                  <div className="flex flex-col items-center justify-center h-full text-gray-400">
                    <UtensilsCrossed className="h-12 w-12 mb-3" />
                    <p className="font-medium">No items found</p>
                    <p className="text-sm">{search ? "Try a different search" : "Add items to your menu first"}</p>
                  </div>
                ) : (
                  <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
                    {filteredItems.map(item => (
                      <button key={item.menuItemId} onClick={() => addToCart(item)}
                        className="text-left border rounded-xl overflow-hidden hover:border-rose-300 hover:bg-rose-50/50 hover:shadow-sm transition-all group">
                        {/* Photo. On a POS the picture is what staff scan for, so it gets
                            the top of the tile. The icon sits underneath as a permanent
                            backdrop, so items with no photo -- and images that fail to
                            decode -- land on the same placeholder and every row in the
                            grid keeps the same height. */}
                        <div className="relative aspect-[4/3] w-full bg-gray-100 overflow-hidden">
                          <div className="absolute inset-0 flex items-center justify-center text-gray-300">
                            <UtensilsCrossed className="h-7 w-7" />
                          </div>
                          {item.imageUrl && (
                            <img src={item.imageUrl} alt="" loading="lazy"
                              className="relative w-full h-full object-cover transition-transform duration-200 group-hover:scale-105"
                              onError={e => (e.currentTarget.style.display = "none")} />
                          )}
                        </div>
                        <div className="p-3">
                          <div className="font-medium text-sm text-gray-900 truncate group-hover:text-rose-700">{item.name}</div>
                          <div className="text-xs text-muted-foreground truncate mt-0.5">{item.categoryName || "Uncategorized"}</div>
                          <div className="flex items-center justify-between mt-2">
                            <span className="font-bold text-rose-600">{item.price.toFixed(2)}</span>
                            {item.prepTime > 0 && <span className="text-[10px] text-muted-foreground">{item.prepTime}m</span>}
                          </div>
                        </div>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>

            {/* RIGHT: Cart / Active Order */}
            <div className="w-full lg:w-[400px] shrink-0 flex flex-col bg-white border-t lg:border-t-0 lg:border-l shadow-lg">
              {activeOrder ? (
                <div className="flex-1 flex flex-col">
                  <div className="p-4 border-b bg-green-50">
                    <div className="flex items-center justify-between">
                      <div>
                        <h3 className="font-bold text-lg text-green-900">{activeOrder.orderNumber}</h3>
                        <div className="text-sm text-green-700">{activeOrder.orderType} {activeOrder.tableNumber && `| Table ${activeOrder.tableNumber}`}</div>
                      </div>
                      <Badge className="bg-green-600 text-white">{activeOrder.status}</Badge>
                    </div>
                  </div>
                  <div className="flex-1 overflow-y-auto p-4 space-y-2">
                    {activeOrderItems.map(oi => (
                      <div key={oi.orderItemId} className="flex justify-between text-sm py-2 border-b border-dashed">
                        <div><span className="font-semibold text-rose-600">{oi.quantity}x</span> <span className="text-gray-700">{oi.itemName}</span>
                          {oi.notes && <div className="text-xs text-muted-foreground italic">{oi.notes}</div>}
                        </div>
                        <span className="font-medium">{oi.lineTotal.toFixed(2)}</span>
                      </div>
                    ))}
                  </div>
                  <div className="border-t p-4 space-y-3 bg-gray-50">
                    <div className="flex justify-between text-sm"><span className="text-muted-foreground">Subtotal</span><span className="font-medium">{activeOrder.subtotal.toFixed(2)}</span></div>
                    {activeOrder.discountAmount > 0 && <div className="flex justify-between text-sm text-red-600"><span>Discount</span><span>-{activeOrder.discountAmount.toFixed(2)}</span></div>}
                    {activeOrder.serviceChargeAmount > 0 && <div className="flex justify-between text-sm"><span className="text-muted-foreground">Service charge</span><span>{activeOrder.serviceChargeAmount.toFixed(2)}</span></div>}
                    {activeOrder.taxAmount > 0 && <div className="flex justify-between text-sm"><span className="text-muted-foreground">Tax</span><span>{activeOrder.taxAmount.toFixed(2)}</span></div>}
                    <div className="flex justify-between font-bold text-xl border-t pt-3"><span>Total</span><span className="text-rose-700">{activeOrder.totalAmount.toFixed(2)}</span></div>
                    {activeOrder.paidAmount > 0 && <div className="flex justify-between text-sm text-green-700"><span>Paid so far</span><span>{activeOrder.paidAmount.toFixed(2)}</span></div>}
                    <Button className="w-full bg-green-600 hover:bg-green-700 h-12 text-base" onClick={() => setPayDialogOpen(true)}>
                      <CreditCard className="h-5 w-5 mr-2" /> Pay {(activeOrder.totalAmount - activeOrder.paidAmount).toFixed(2)}
                    </Button>
                    <Button variant="outline" className="w-full" onClick={() => { setActiveOrder(null); setActiveOrderItems([]) }}>New Order</Button>
                  </div>
                </div>
              ) : (
                <div className="flex-1 flex flex-col">
                  {/* Order config */}
                  <div className="p-4 border-b space-y-3 bg-gray-50">
                    <div className="flex items-center gap-2">
                      <div className="h-8 w-8 rounded-lg bg-rose-100 flex items-center justify-center"><ShoppingCart className="h-4 w-4 text-rose-600" /></div>
                      <h3 className="font-bold text-gray-900">New Order</h3>
                    </div>
                    <div className="grid grid-cols-2 gap-2">
                      <Select value={orderType} onValueChange={setOrderType}>
                        <SelectTrigger className="h-9 text-xs bg-white"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="DineIn">Dine In</SelectItem>
                          <SelectItem value="Takeaway">Takeaway</SelectItem>
                          <SelectItem value="Delivery">Delivery</SelectItem>
                          <SelectItem value="DriveThrough">Drive Through</SelectItem>
                        </SelectContent>
                      </Select>
                      {orderType === "DineIn" && (
                        <Select value={selectedTable ? String(selectedTable) : "none"} onValueChange={v => setSelectedTable(v === "none" ? null : parseInt(v))}>
                          <SelectTrigger className="h-9 text-xs bg-white"><SelectValue placeholder="Select table" /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="none">No table</SelectItem>
                            {tables.map(t => <SelectItem key={t.tableId} value={String(t.tableId)}>Table {t.tableNumber} ({t.capacity})</SelectItem>)}
                          </SelectContent>
                        </Select>
                      )}
                    </div>
                    <Select value={selectedCustomerId ? String(selectedCustomerId) : "walk-in"} onValueChange={v => {
                      if (v === "walk-in") { setSelectedCustomerId(null); setCustomerName("") }
                      else { const c = customers.find(cu => cu.customerId === parseInt(v)); if (c) { setSelectedCustomerId(c.customerId); setCustomerName(c.name) } }
                    }}>
                      <SelectTrigger className="h-9 text-xs bg-white"><SelectValue placeholder="Walk-in customer" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="walk-in">Walk-in (Guest)</SelectItem>
                        {customers.map(c => <SelectItem key={c.customerId} value={String(c.customerId)}>{c.name} {c.phone ? `(${c.phone})` : ""}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                  {/* Cart items */}
                  <div className="flex-1 overflow-y-auto p-4">
                    {cart.length === 0 ? (
                      <div className="flex flex-col items-center justify-center h-full text-gray-400">
                        <ShoppingCart className="h-10 w-10 mb-2" />
                        <p className="font-medium text-sm">Cart is empty</p>
                        <p className="text-xs">Tap items on the left to add them</p>
                      </div>
                    ) : (
                      <div className="space-y-3">
                        {cart.map((item, idx) => (
                          <div key={idx} className="flex items-start gap-2 pb-3 border-b border-dashed">
                            <div className="flex-1 min-w-0">
                              <div className="font-medium text-sm text-gray-900">{item.name}</div>
                              <div className="text-xs text-muted-foreground mt-0.5">{item.price.toFixed(2)} each</div>
                            </div>
                            <div className="flex items-center gap-1">
                              <Button variant="outline" size="icon" className="h-7 w-7 rounded-full" onClick={() => updateCartQty(idx, -1)}><Minus className="h-3 w-3" /></Button>
                              <span className="w-8 text-center font-bold text-sm">{item.quantity}</span>
                              <Button variant="outline" size="icon" className="h-7 w-7 rounded-full" onClick={() => updateCartQty(idx, 1)}><Plus className="h-3 w-3" /></Button>
                            </div>
                            <div className="text-right min-w-[55px]">
                              <div className="font-bold text-sm">{(item.price * item.quantity).toFixed(2)}</div>
                              <button onClick={() => removeFromCart(idx)} className="text-red-400 hover:text-red-600 transition-colors"><X className="h-4 w-4" /></button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                  {/* Cart footer */}
                  {cart.length > 0 && (
                    <div className="border-t p-4 space-y-3 bg-gray-50">
                      <div className="flex justify-between font-bold text-xl">
                        <span>Total</span>
                        <span className="text-rose-700">{cartSubtotal.toFixed(2)}</span>
                      </div>
                      <Button className="w-full bg-rose-600 hover:bg-rose-700 h-12 text-base font-semibold" onClick={placeOrder}>
                        <Check className="h-5 w-5 mr-2" /> Place Order
                      </Button>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        </main>
      </div>

      {/* Payment: shared with the Orders screen. Records the amount applied to the
          bill (never the cash tendered) and routes cash to the open till. */}
      <TakePaymentDialog open={payDialogOpen} onOpenChange={setPayDialogOpen} order={activeOrder} onPaid={handlePaid} />

      {/* Receipt Dialog */}
      <Dialog open={receiptDialogOpen} onOpenChange={setReceiptDialogOpen}>
        <DialogContent className="sm:max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Receipt</DialogTitle>
            <DialogDescription>Print or download the receipt for this order.</DialogDescription>
          </DialogHeader>
          {receiptOrder && (
            <>
              <div id="receipt-content" className="font-mono text-xs p-4 bg-white border rounded-lg">
                <div className="center" style={{textAlign:"center"}}>
                  <h2 style={{margin:0,fontSize:"16px",fontWeight:"bold"}}>{activeFarmName}</h2>
                  {receiptTemplate?.headerText && <p style={{margin:"2px 0",fontSize:"10px"}}>{receiptTemplate.headerText}</p>}
                  <p style={{margin:"4px 0",fontSize:"10px"}}>{receiptOrder.order.createdAt ? new Date(receiptOrder.order.createdAt).toLocaleString() : new Date().toLocaleString()}</p>
                  <p style={{margin:"2px 0",fontWeight:"bold"}}>Order: {receiptOrder.order.orderNumber}</p>
                  <p style={{margin:"2px 0"}}>{receiptOrder.order.orderType}{receiptOrder.order.tableNumber ? ` | Table ${receiptOrder.order.tableNumber}` : ""}</p>
                  {receiptOrder.order.customerName && <p style={{margin:"2px 0"}}>Customer: {receiptOrder.order.customerName}</p>}
                </div>
                <div className="line" style={{borderTop:"1px dashed #000",margin:"8px 0"}} />
                {receiptOrder.items.map((oi, idx) => (
                  <div key={idx} className="row" style={{display:"flex",justifyContent:"space-between",margin:"3px 0"}}>
                    <span>{oi.quantity} x {oi.itemName}</span>
                    <span>{oi.lineTotal.toFixed(2)}</span>
                  </div>
                ))}
                <div className="line" style={{borderTop:"1px dashed #000",margin:"8px 0"}} />
                <div className="row" style={{display:"flex",justifyContent:"space-between"}}>
                  <span>Subtotal</span><span>{receiptOrder.order.subtotal.toFixed(2)}</span>
                </div>
                {receiptOrder.order.discountAmount > 0 && (
                  <div className="row" style={{display:"flex",justifyContent:"space-between"}}>
                    <span>Discount</span><span>-{receiptOrder.order.discountAmount.toFixed(2)}</span>
                  </div>
                )}
                {receiptOrder.order.serviceChargeAmount > 0 && (
                  <div className="row" style={{display:"flex",justifyContent:"space-between"}}>
                    <span>Service charge</span><span>{receiptOrder.order.serviceChargeAmount.toFixed(2)}</span>
                  </div>
                )}
                {receiptOrder.order.taxAmount > 0 && (
                  <div className="row" style={{display:"flex",justifyContent:"space-between"}}>
                    <span>Tax</span><span>{receiptOrder.order.taxAmount.toFixed(2)}</span>
                  </div>
                )}
                <div className="total-row" style={{display:"flex",justifyContent:"space-between",fontWeight:"bold",fontSize:"14px",margin:"4px 0"}}>
                  <span>TOTAL</span><span>{receiptOrder.order.totalAmount.toFixed(2)}</span>
                </div>
                <div className="line" style={{borderTop:"1px dashed #000",margin:"8px 0"}} />
                <div className="row" style={{display:"flex",justifyContent:"space-between"}}>
                  <span>Paid ({receiptOrder.payment.method})</span><span>{receiptOrder.payment.amount.toFixed(2)}</span>
                </div>
                {receiptOrder.payment.change > 0 && (
                  <div className="row" style={{display:"flex",justifyContent:"space-between"}}>
                    <span>Change</span><span>{receiptOrder.payment.change.toFixed(2)}</span>
                  </div>
                )}
                {receiptOrder.payment.tip > 0 && (
                  <div className="row" style={{display:"flex",justifyContent:"space-between"}}>
                    <span>Tip</span><span>{receiptOrder.payment.tip.toFixed(2)}</span>
                  </div>
                )}
                <div className="line" style={{borderTop:"1px dashed #000",margin:"8px 0"}} />
                <div className="center" style={{textAlign:"center"}}>
                  <p style={{margin:"4px 0"}}>Thank you for dining with us!</p>
                  {receiptTemplate?.footerText && <p style={{margin:"2px 0",fontSize:"10px"}}>{receiptTemplate.footerText}</p>}
                  <p style={{margin:"6px 0",fontSize:"9px",color:"#999"}}>Powered by PoultryMaster</p>
                </div>
              </div>
              <DialogFooter className="flex gap-2 sm:gap-2">
                <Button variant="outline" onClick={() => setReceiptDialogOpen(false)}>Close</Button>
                <Button variant="outline" onClick={emailReceipt}>
                  <Mail className="h-4 w-4 mr-2" /> Email
                </Button>
                <Button variant="outline" onClick={downloadInvoice}>
                  <Download className="h-4 w-4 mr-2" /> Download PDF
                </Button>
                <Button className="bg-rose-600 hover:bg-rose-700" onClick={printReceipt}>
                  <Printer className="h-4 w-4 mr-2" /> Print Receipt
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

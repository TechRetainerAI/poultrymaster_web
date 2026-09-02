"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { ClipboardList, ChevronRight, RefreshCw, Users, DollarSign, Clock, MapPin } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { listOrders, getOrder, updateOrderStatus, listOrderItems, type Order, type OrderItem } from "@/lib/api/restaurant"

const STATUS_BADGES: Record<string, string> = {
  Placed: "bg-blue-500", Confirmed: "bg-indigo-500", Preparing: "bg-amber-500",
  Ready: "bg-green-500", Served: "bg-teal-500", Completed: "bg-gray-500",
  Cancelled: "bg-red-500", Refunded: "bg-pink-500",
}
const STATUS_FLOW: Record<string, string[]> = {
  Placed: ["Confirmed", "Cancelled"], Confirmed: ["Preparing", "Cancelled"],
  Preparing: ["Ready"], Ready: ["Served"], Served: ["Completed"],
}

export default function RestaurantOrdersPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [orders, setOrders] = useState<Order[]>([])
  const [filterStatus, setFilterStatus] = useState<string>("active")
  const [filterType, setFilterType] = useState<string>("all")
  const [detailOrder, setDetailOrder] = useState<Order | null>(null)
  const [detailItems, setDetailItems] = useState<OrderItem[]>([])
  const [detailOpen, setDetailOpen] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadOrders()
  }, [activeFarmType, router])

  async function loadOrders() {
    setLoading(true)
    try {
      const statusParam = filterStatus === "active" || filterStatus === "all" ? undefined : filterStatus
      const typeParam = filterType === "all" ? undefined : filterType
      const list = await listOrders(statusParam, typeParam)
      setOrders(filterStatus === "active" ? list.filter(o => !["Completed", "Cancelled", "Refunded"].includes(o.status)) : list)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => { if (!loading) loadOrders() }, [filterStatus, filterType])

  async function openDetail(o: Order) {
    try {
      const [order, items] = await Promise.all([getOrder(o.orderId), listOrderItems(o.orderId)])
      setDetailOrder(order); setDetailItems(items); setDetailOpen(true)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function changeStatus(orderId: number, status: string) {
    try {
      await updateOrderStatus(orderId, status); toast({ title: `Order ${status}` }); loadOrders()
      if (detailOrder?.orderId === orderId) setDetailOrder(await getOrder(orderId))
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const todayOrders = orders.filter(o => new Date(o.createdAt).toDateString() === new Date().toDateString())
  const todayRevenue = todayOrders.filter(o => o.paymentStatus === "Paid").reduce((s, o) => s + o.totalAmount, 0)

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-5xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center">
                  <ClipboardList className="h-5 w-5 text-rose-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
                  <p className="text-sm text-muted-foreground">{orders.length} orders shown</p>
                </div>
              </div>
              <div className="flex gap-2">
                <Select value={filterStatus} onValueChange={setFilterStatus}>
                  <SelectTrigger className="w-[130px] h-9"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="active">Active</SelectItem>
                    <SelectItem value="all">All</SelectItem>
                    <SelectItem value="Placed">Placed</SelectItem>
                    <SelectItem value="Preparing">Preparing</SelectItem>
                    <SelectItem value="Ready">Ready</SelectItem>
                    <SelectItem value="Completed">Completed</SelectItem>
                    <SelectItem value="Cancelled">Cancelled</SelectItem>
                  </SelectContent>
                </Select>
                <Select value={filterType} onValueChange={setFilterType}>
                  <SelectTrigger className="w-[130px] h-9"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All Types</SelectItem>
                    <SelectItem value="DineIn">Dine In</SelectItem>
                    <SelectItem value="Takeaway">Takeaway</SelectItem>
                    <SelectItem value="Delivery">Delivery</SelectItem>
                  </SelectContent>
                </Select>
                <Button variant="outline" size="icon" className="h-9 w-9" onClick={loadOrders}><RefreshCw className="h-4 w-4" /></Button>
              </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-3 gap-3">
              <Card><CardContent className="py-3 px-4 flex items-center gap-3">
                <div className="h-9 w-9 rounded-lg bg-blue-100 flex items-center justify-center"><ClipboardList className="h-4 w-4 text-blue-600" /></div>
                <div><div className="text-xl font-bold">{orders.length}</div><div className="text-xs text-muted-foreground">Total Orders</div></div>
              </CardContent></Card>
              <Card><CardContent className="py-3 px-4 flex items-center gap-3">
                <div className="h-9 w-9 rounded-lg bg-green-100 flex items-center justify-center"><DollarSign className="h-4 w-4 text-green-600" /></div>
                <div><div className="text-xl font-bold">{todayRevenue.toFixed(0)}</div><div className="text-xs text-muted-foreground">Today's Revenue</div></div>
              </CardContent></Card>
              <Card><CardContent className="py-3 px-4 flex items-center gap-3">
                <div className="h-9 w-9 rounded-lg bg-amber-100 flex items-center justify-center"><Clock className="h-4 w-4 text-amber-600" /></div>
                <div><div className="text-xl font-bold">{todayOrders.length}</div><div className="text-xs text-muted-foreground">Today's Orders</div></div>
              </CardContent></Card>
            </div>

            {/* Orders list */}
            <Card>
              <CardContent className="pt-4">
                {orders.length === 0 ? (
                  <div className="text-center py-16 border-2 border-dashed rounded-xl">
                    <ClipboardList className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                    <h3 className="font-medium text-gray-900 mb-1">No orders found</h3>
                    <p className="text-sm text-muted-foreground">Orders will appear here once placed via POS or online</p>
                  </div>
                ) : (
                  <div className="space-y-2">
                    {orders.map(o => (
                      <div key={o.orderId} className="group flex items-center gap-4 p-4 border rounded-xl cursor-pointer hover:border-rose-200 hover:bg-rose-50/30 transition-all" onClick={() => openDetail(o)}>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="font-mono font-bold text-gray-900">{o.orderNumber}</span>
                            <Badge variant="outline" className="text-[10px] h-5">{o.orderType}</Badge>
                            <Badge className={`text-[10px] h-5 text-white ${STATUS_BADGES[o.status] || "bg-gray-500"}`}>{o.status}</Badge>
                            {o.paymentStatus === "Paid" && <Badge className="text-[10px] h-5 bg-green-100 text-green-700 hover:bg-green-100">Paid</Badge>}
                          </div>
                          <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground">
                            <span className="flex items-center gap-1"><Clock className="h-3 w-3" />{new Date(o.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span>
                            {o.tableNumber && <span className="flex items-center gap-1"><MapPin className="h-3 w-3" />Table {o.tableNumber}</span>}
                            {o.customerName && <span className="flex items-center gap-1"><Users className="h-3 w-3" />{o.customerName}</span>}
                            <span>{o.itemCount} items</span>
                          </div>
                        </div>
                        <div className="text-right flex-shrink-0">
                          <div className="font-bold text-lg text-gray-900">{o.totalAmount.toFixed(2)}</div>
                        </div>
                        {STATUS_FLOW[o.status] && (
                          <div className="flex gap-1 flex-shrink-0" onClick={e => e.stopPropagation()}>
                            {STATUS_FLOW[o.status].map(next => (
                              <Button key={next} size="sm" className={`h-8 text-xs ${next === "Cancelled" ? "bg-red-500 hover:bg-red-600" : "bg-rose-600 hover:bg-rose-700"}`}
                                onClick={() => changeStatus(o.orderId, next)}>{next}</Button>
                            ))}
                          </div>
                        )}
                        <ChevronRight className="h-4 w-4 text-gray-300 group-hover:text-rose-400 flex-shrink-0" />
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>

      {/* Order Detail */}
      <Dialog open={detailOpen} onOpenChange={setDetailOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-3">
              {detailOrder?.orderNumber}
              <Badge className={`text-white ${STATUS_BADGES[detailOrder?.status || ""]}`}>{detailOrder?.status}</Badge>
            </DialogTitle>
            <DialogDescription>Order details and line items</DialogDescription>
          </DialogHeader>
          {detailOrder && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-3 text-sm">
                {[
                  ["Type", detailOrder.orderType], ["Table", detailOrder.tableNumber || "—"],
                  ["Customer", detailOrder.customerName || "Walk-in"], ["Covers", String(detailOrder.covers)],
                  ["Server", detailOrder.servedBy || "—"], ["Created", new Date(detailOrder.createdAt).toLocaleString()],
                ].map(([label, val]) => (
                  <div key={label} className="flex justify-between p-2 bg-gray-50 rounded-lg">
                    <span className="text-muted-foreground">{label}</span>
                    <span className="font-medium">{val}</span>
                  </div>
                ))}
              </div>
              <div className="border rounded-xl overflow-hidden">
                <div className="px-4 py-2 bg-gray-50 text-xs font-medium text-muted-foreground uppercase tracking-wide">Items</div>
                <div className="divide-y">
                  {detailItems.map(item => (
                    <div key={item.orderItemId} className="flex justify-between p-3">
                      <div>
                        <span className="font-semibold text-rose-600 text-sm">{item.quantity}x</span>{" "}
                        <span className="text-sm font-medium">{item.itemName}</span>
                        <Badge variant="outline" className="ml-2 text-[10px] h-4">{item.status}</Badge>
                        {item.notes && <div className="text-xs text-muted-foreground italic mt-0.5">{item.notes}</div>}
                      </div>
                      <span className="font-medium text-sm">{item.lineTotal.toFixed(2)}</span>
                    </div>
                  ))}
                </div>
              </div>
              <div className="space-y-1.5 text-sm">
                <div className="flex justify-between"><span className="text-muted-foreground">Subtotal</span><span>{detailOrder.subtotal.toFixed(2)}</span></div>
                {detailOrder.discountAmount > 0 && <div className="flex justify-between text-red-600"><span>Discount</span><span>-{detailOrder.discountAmount.toFixed(2)}</span></div>}
                {detailOrder.taxAmount > 0 && <div className="flex justify-between"><span className="text-muted-foreground">Tax</span><span>{detailOrder.taxAmount.toFixed(2)}</span></div>}
                <div className="flex justify-between font-bold text-lg border-t pt-2"><span>Total</span><span className="text-rose-700">{detailOrder.totalAmount.toFixed(2)}</span></div>
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Paid</span>
                  <span className={detailOrder.paymentStatus === "Paid" ? "text-green-600 font-medium" : "text-amber-600"}>{detailOrder.paidAmount.toFixed(2)} ({detailOrder.paymentStatus})</span>
                </div>
              </div>
              {STATUS_FLOW[detailOrder.status] && (
                <div className="flex gap-2 pt-2">
                  {STATUS_FLOW[detailOrder.status].map(next => (
                    <Button key={next} className={`flex-1 ${next === "Cancelled" ? "bg-red-500 hover:bg-red-600" : "bg-rose-600 hover:bg-rose-700"}`}
                      onClick={() => changeStatus(detailOrder.orderId, next)}>Move to {next}</Button>
                  ))}
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

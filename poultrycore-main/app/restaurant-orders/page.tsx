"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { ClipboardList, ChevronRight, RefreshCw, Users, DollarSign, Clock, MapPin, QrCode, Globe, Store, Mail, Phone, UserPlus, UserCheck, Loader2, Star } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { listOrders, getOrder, updateOrderStatus, listOrderItems, linkOrderToCustomer, type Order, type OrderItem } from "@/lib/api/restaurant"
import { markOnlineOrdersSeen } from "@/lib/utils/online-order-alerts"

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
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const [loading, setLoading] = useState(true)
  const [orders, setOrders] = useState<Order[]>([])
  const [filterStatus, setFilterStatus] = useState<string>("active")
  const [filterType, setFilterType] = useState<string>("all")
  /**
   * Where the order came from. Filtered in the browser rather than server-side:
   * `listOrders` only accepts status and type, and adding a third parameter would
   * mean touching sprestaurant_order_list, which the KDS and reports also use.
   * The list is a single day's orders, so filtering client-side is free.
   */
  const [filterSource, setFilterSource] = useState<string>("all")
  const [detailOrder, setDetailOrder] = useState<Order | null>(null)
  const [detailItems, setDetailItems] = useState<OrderItem[]>([])
  const [detailOpen, setDetailOpen] = useState(false)
  const [linking, setLinking] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadOrders()
  }, [activeFarmType, router])

  /**
   * This screen is where the nav badge is cleared. Marking is done with the
   * orders that actually reach the page rather than with "now", so an order that
   * arrived while the list was loading still counts as unseen. A new online
   * order is always at 'Placed', which the default 'active' filter keeps, so it
   * can never be marked seen while hidden behind a filter.
   */
  function applyOrders(list: Order[]) {
    const next = filterStatus === "active"
      ? list.filter(o => !["Completed", "Cancelled", "Refunded"].includes(o.status))
      : list
    setOrders(next)
    if (activeFarmId) markOnlineOrdersSeen(activeFarmId, next)
  }

  async function loadOrders() {
    setLoading(true)
    try {
      const statusParam = filterStatus === "active" || filterStatus === "all" ? undefined : filterStatus
      const typeParam = filterType === "all" ? undefined : filterType
      applyOrders(await listOrders(statusParam, typeParam))
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => { if (!loading) loadOrders() }, [filterStatus, filterType])

  // Refresh in the background so orders arriving from table QR codes show up on
  // their own. Deliberately silent - no spinner, no toast on failure - because
  // this fires every 10s and must never interrupt someone mid-task.
  useEffect(() => {
    if (activeFarmType !== "Restaurant") return
    const id = setInterval(() => {
      const statusParam = filterStatus === "active" || filterStatus === "all" ? undefined : filterStatus
      const typeParam = filterType === "all" ? undefined : filterType
      // Same path as the manual load, so an order that arrives while staff are
      // sitting on this screen is marked seen too and never badges the nav.
      listOrders(statusParam, typeParam).then(applyOrders).catch(() => {})
    }, 10_000)
    return () => clearInterval(id)
  }, [activeFarmType, filterStatus, filterType])

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

  /**
   * An order is "online" when it carries a source ('QR' | 'Web' | 'App').
   * A walk-in rung up on the POS has no source at all - see migration 248, which
   * relies on exactly this distinction to keep unconfirmed guest orders out of
   * the kitchen.
   */
  const isOnline = (o: Order) => Boolean(o.onlineSource)

  const visibleOrders = orders.filter(o =>
    filterSource === "all" ? true : filterSource === "online" ? isOnline(o) : !isOnline(o))

  /**
   * Save the guest on this order into the CRM. The server reads the name, phone
   * and email from the order itself and matches an existing customer by phone,
   * so pressing this twice - or on a second order from the same person - links
   * rather than duplicating.
   */
  async function addAsCustomer(order: Order) {
    setLinking(true)
    try {
      const r = await linkOrderToCustomer(order.orderId)
      toast({
        title: r.created ? `${r.name} saved as a customer` : `Matched ${r.name}`,
        description: r.created
          ? r.message
          : `${r.message} Now ${r.totalVisits ?? 0} visit${r.totalVisits === 1 ? "" : "s"} — ${r.segment}.`,
      })
      // Re-read so the row and the dialog both show the link straight away.
      const fresh = await getOrder(order.orderId)
      setDetailOrder(fresh)
      setOrders(prev => prev.map(o => o.orderId === fresh.orderId ? { ...o, customerId: fresh.customerId } : o))
    } catch (e: any) {
      toast({ title: "Could not save the customer", description: e?.message, variant: "destructive" })
    } finally { setLinking(false) }
  }

  const todayOrders = orders.filter(o => new Date(o.createdAt).toDateString() === new Date().toDateString())
  const todayRevenue = todayOrders.filter(o => o.paymentStatus === "Paid").reduce((s, o) => s + o.totalAmount, 0)
  const todayOnline = todayOrders.filter(isOnline)

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
                  <p className="text-sm text-muted-foreground">
                    {visibleOrders.length} orders shown
                    {filterSource !== "all" && ` · ${filterSource === "online" ? "online" : "walk-in"} only`}
                  </p>
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
                <Select value={filterSource} onValueChange={setFilterSource}>
                  <SelectTrigger className="w-[140px] h-9"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All Sources</SelectItem>
                    <SelectItem value="online">Online only</SelectItem>
                    <SelectItem value="pos">Walk-in only</SelectItem>
                  </SelectContent>
                </Select>
                <Button variant="outline" size="icon" className="h-9 w-9" onClick={loadOrders}><RefreshCw className="h-4 w-4" /></Button>
              </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
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
              {/* Online orders deserve their own count: they are the ones that
                  arrived without a member of staff touching a till. */}
              <Card className={todayOnline.length > 0 ? "border-rose-200 bg-rose-50/40" : undefined}>
                <CardContent className="py-3 px-4 flex items-center gap-3">
                <div className="h-9 w-9 rounded-lg bg-rose-100 flex items-center justify-center"><Globe className="h-4 w-4 text-rose-600" /></div>
                <div>
                  <div className="text-xl font-bold">{todayOnline.length}</div>
                  <div className="text-xs text-muted-foreground">Online Today</div>
                </div>
              </CardContent></Card>
            </div>

            {/* Orders list */}
            <Card>
              <CardContent className="pt-4">
                {visibleOrders.length === 0 ? (
                  <div className="text-center py-16 border-2 border-dashed rounded-xl">
                    <ClipboardList className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                    <h3 className="font-medium text-gray-900 mb-1">No orders found</h3>
                    <p className="text-sm text-muted-foreground">Orders will appear here once placed via POS or online</p>
                  </div>
                ) : (
                  <div className="space-y-2">
                    {visibleOrders.map(o => (
                      <div key={o.orderId}
                        className={`group relative flex items-center gap-4 overflow-hidden rounded-xl border p-4 pl-5 cursor-pointer transition-all hover:border-rose-200 hover:bg-rose-50/30 ${
                          isOnline(o) ? "border-rose-200 bg-rose-50/40" : ""}`}
                        onClick={() => openDetail(o)}>
                        {/* A colour bar down the edge of the row: the marker has to be
                            readable at a glance while scanning a list, not something you
                            have to stop and read. */}
                        {isOnline(o) && <span aria-hidden className="absolute inset-y-0 left-0 w-1.5 bg-rose-500" />}
                        <div className="flex-1 min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="font-mono font-bold text-gray-900">{o.orderNumber}</span>
                            {/* Promoted out of the muted metadata line below, where it was a
                                grey chip reading just "QR" and easy to miss entirely. */}
                            {isOnline(o) ? (
                              <Badge className="h-5 gap-1 bg-rose-600 px-1.5 text-[10px] text-white hover:bg-rose-600">
                                <Globe className="h-3 w-3" />
                                ONLINE{o.onlineSource === "QR" ? " · QR" : o.onlineSource === "Web" ? " · WEB" : ""}
                              </Badge>
                            ) : (
                              <Badge variant="outline" className="h-5 gap-1 px-1.5 text-[10px] text-gray-500">
                                <Store className="h-3 w-3" /> WALK-IN
                              </Badge>
                            )}
                            <Badge variant="outline" className="text-[10px] h-5">{o.orderType}</Badge>
                            <Badge className={`text-[10px] h-5 text-white ${STATUS_BADGES[o.status] || "bg-gray-500"}`}>{o.status}</Badge>
                            {o.paymentStatus === "Paid" && <Badge className="text-[10px] h-5 bg-green-100 text-green-700 hover:bg-green-100">Paid</Badge>}
                            {/* An online order still at 'Placed' has not been accepted in the
                                New Guest Orders tray, so the kitchen cannot see it yet. */}
                            {isOnline(o) && o.status === "Placed" && (
                              <Badge className="h-5 bg-amber-100 px-1.5 text-[10px] text-amber-800 hover:bg-amber-100">
                                Awaiting confirmation
                              </Badge>
                            )}
                            {/* Already in the CRM. The point of the whole feature is
                                knowing a face is a returning one, so it belongs on
                                the row rather than hidden inside the dialog. */}
                            {o.customerId && (
                              <Badge className="h-5 gap-1 bg-emerald-100 px-1.5 text-[10px] text-emerald-800 hover:bg-emerald-100">
                                <UserCheck className="h-3 w-3" /> Customer
                              </Badge>
                            )}
                          </div>
                          <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground">
                            <span className="flex items-center gap-1"><Clock className="h-3 w-3" />{new Date(o.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span>
                            {o.tableNumber && <span className="flex items-center gap-1"><MapPin className="h-3 w-3" />Table {o.tableNumber}</span>}
                            {o.customerName && <span className="flex items-center gap-1"><Users className="h-3 w-3" />{o.customerName}</span>}
                            <span>{o.itemCount} items</span>
                            {o.customerPhone && <span className="flex items-center gap-1"><Phone className="h-3 w-3" />{o.customerPhone}</span>}
                            {o.guestPaymentIntent && (
                              <span className="flex items-center gap-1 text-rose-600">
                                Plans to pay by {o.guestPaymentIntent}
                              </span>
                            )}
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
            <DialogTitle className="flex flex-wrap items-center gap-2">
              {detailOrder?.orderNumber}
              {detailOrder && (isOnline(detailOrder) ? (
                <Badge className="gap-1 bg-rose-600 text-[10px] text-white hover:bg-rose-600">
                  <Globe className="h-3 w-3" />
                  ONLINE{detailOrder.onlineSource === "QR" ? " · QR" : detailOrder.onlineSource === "Web" ? " · WEB" : ""}
                </Badge>
              ) : (
                <Badge variant="outline" className="gap-1 text-[10px] text-gray-500">
                  <Store className="h-3 w-3" /> WALK-IN
                </Badge>
              ))}
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
              {/* Everything a walk-in order simply does not have: who the guest is,
                  how to reach them, and how they said they would pay. */}
              {isOnline(detailOrder) && (
                <div className="rounded-xl border border-rose-200 bg-rose-50/60 p-3">
                  <div className="mb-2 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-rose-700">
                    <Globe className="h-3.5 w-3.5" /> Online order
                  </div>
                  <div className="space-y-1.5 text-sm">
                    {detailOrder.customerPhone && (
                      <a href={`tel:${detailOrder.customerPhone}`} className="flex items-center gap-2 text-gray-700 hover:text-rose-700">
                        <Phone className="h-3.5 w-3.5 text-gray-400" />{detailOrder.customerPhone}
                      </a>
                    )}
                    {detailOrder.customerEmail && (
                      <a href={`mailto:${detailOrder.customerEmail}`} className="flex items-center gap-2 break-all text-gray-700 hover:text-rose-700">
                        <Mail className="h-3.5 w-3.5 shrink-0 text-gray-400" />{detailOrder.customerEmail}
                      </a>
                    )}
                    {detailOrder.guestPaymentIntent && (
                      <div className="flex items-center gap-2 text-gray-700">
                        <DollarSign className="h-3.5 w-3.5 text-gray-400" />
                        Plans to pay by {detailOrder.guestPaymentIntent}
                        {detailOrder.guestPaymentAmount ? ` (${detailOrder.guestPaymentAmount.toFixed(2)})` : ""}
                      </div>
                    )}
                    {detailOrder.deliveryAddress && (
                      <div className="flex items-center gap-2 text-gray-700">
                        <MapPin className="h-3.5 w-3.5 shrink-0 text-gray-400" />{detailOrder.deliveryAddress}
                      </div>
                    )}
                    {detailOrder.status === "Placed" && (
                      <p className="pt-1 text-xs text-amber-800">
                        Not yet confirmed — the kitchen cannot see this order. Accept it under
                        <span className="font-medium"> New Guest Orders</span>.
                      </p>
                    )}
                  </div>
                </div>
              )}

              {/* Save this guest into the CRM. Shown for any order that carries a
                  name or phone - a phone order taken at the counter is just as
                  worth keeping as an online one. */}
              {(detailOrder.customerName || detailOrder.customerPhone) && (
                detailOrder.customerId ? (
                  <div className="flex items-center gap-2 rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2.5 text-sm text-emerald-800">
                    <UserCheck className="h-4 w-4 shrink-0" />
                    <span className="flex-1">Saved as a customer.</span>
                    <Button variant="ghost" size="sm" className="h-7 text-xs text-emerald-800 hover:bg-emerald-100"
                      onClick={() => router.push("/restaurant-crm")}>
                      View <ChevronRight className="ml-0.5 h-3 w-3" />
                    </Button>
                  </div>
                ) : (
                  <div className="rounded-xl border border-dashed border-rose-200 bg-rose-50/50 p-3">
                    <div className="flex items-start gap-2.5">
                      <Star className="mt-0.5 h-4 w-4 shrink-0 text-rose-500" />
                      <div className="min-w-0 flex-1">
                        <div className="text-sm font-medium text-gray-900">Not a saved customer yet</div>
                        <p className="mt-0.5 text-xs text-muted-foreground">
                          Save {detailOrder.customerName || "this guest"}
                          {detailOrder.customerPhone ? ` (${detailOrder.customerPhone})` : ""} so repeat visits
                          are recognised and count towards Regular and VIP.
                        </p>
                        <Button size="sm" disabled={linking}
                          onClick={() => addAsCustomer(detailOrder)}
                          className="mt-2.5 h-8 bg-rose-600 text-xs hover:bg-rose-700">
                          {linking
                            ? <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                            : <UserPlus className="mr-1.5 h-3.5 w-3.5" />}
                          Add this person as a customer
                        </Button>
                      </div>
                    </div>
                  </div>
                )
              )}

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

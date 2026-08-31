"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ShoppingCart, ClipboardList, UtensilsCrossed, MapPin, CalendarDays, Truck, Globe, ChefHat, Users, DollarSign, TrendingUp, Clock, AlertTriangle, ArrowRight } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listOrders, listMenuItems, listTables, listDrivers,
  listReservations, getKdsStats, getDeliveryStats, getWaitlistStats,
  type Order, type MenuItem, type RestaurantTable, type KdsStats, type DeliveryStats, type WaitlistStats,
} from "@/lib/api/restaurant"

export default function RestaurantDashboardPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)

  const [loading, setLoading] = useState(true)
  const [orders, setOrders] = useState<Order[]>([])
  const [menuItems, setMenuItems] = useState<MenuItem[]>([])
  const [tables, setTables] = useState<RestaurantTable[]>([])
  const [kdsStats, setKdsStats] = useState<KdsStats | null>(null)
  const [deliveryStats, setDeliveryStats] = useState<DeliveryStats | null>(null)
  const [waitlistStats, setWaitlistStats] = useState<WaitlistStats | null>(null)
  const [todayReservations, setTodayReservations] = useState(0)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const today = new Date().toISOString().split("T")[0]
      const [ord, mi, tbl, kds, del, wl, res] = await Promise.all([
        listOrders().catch(() => []),
        listMenuItems().catch(() => []),
        listTables().catch(() => []),
        getKdsStats().catch(() => null),
        getDeliveryStats().catch(() => null),
        getWaitlistStats().catch(() => null),
        listReservations(today).catch(() => []),
      ])
      setOrders(ord)
      setMenuItems(mi)
      setTables(tbl)
      setKdsStats(kds)
      setDeliveryStats(del)
      setWaitlistStats(wl)
      setTodayReservations(res.length)
    } catch (e: any) {
      toast({ title: "Failed to load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  const activeOrders = orders.filter(o => !["Completed", "Cancelled", "Refunded"].includes(o.status))
  const todayOrders = orders.filter(o => new Date(o.createdAt).toDateString() === new Date().toDateString())
  const todayRevenue = todayOrders.filter(o => o.paymentStatus === "Paid").reduce((s, o) => s + o.totalAmount, 0)
  const occupiedTables = tables.filter(t => t.status === "Occupied").length
  const availableTables = tables.filter(t => t.status === "Available").length
  const unavailableItems = menuItems.filter(i => !i.isAvailable).length

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
              <div>
                <h1 className="text-2xl font-bold text-gray-900">Welcome back</h1>
                <p className="text-muted-foreground">{activeFarmName || "Restaurant"} — {new Date().toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}</p>
              </div>
              <Link href="/restaurant-pos">
                <Button className="bg-rose-600 hover:bg-rose-700 h-11 px-6">
                  <ShoppingCart className="h-4 w-4 mr-2" /> Open POS
                </Button>
              </Link>
            </div>

            {/* KPI Cards */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <Card className="border-l-4 border-l-rose-500">
                <CardContent className="pt-4 pb-3">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-xs text-muted-foreground font-medium uppercase tracking-wide">Active Orders</p>
                      <p className="text-3xl font-bold text-gray-900 mt-1">{activeOrders.length}</p>
                    </div>
                    <div className="h-12 w-12 rounded-xl bg-rose-100 flex items-center justify-center">
                      <ClipboardList className="h-6 w-6 text-rose-600" />
                    </div>
                  </div>
                </CardContent>
              </Card>

              <Card className="border-l-4 border-l-green-500">
                <CardContent className="pt-4 pb-3">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-xs text-muted-foreground font-medium uppercase tracking-wide">Today's Revenue</p>
                      <p className="text-3xl font-bold text-gray-900 mt-1">{todayRevenue.toFixed(0)}</p>
                    </div>
                    <div className="h-12 w-12 rounded-xl bg-green-100 flex items-center justify-center">
                      <DollarSign className="h-6 w-6 text-green-600" />
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground mt-2">{todayOrders.length} orders today</p>
                </CardContent>
              </Card>

              <Card className="border-l-4 border-l-blue-500">
                <CardContent className="pt-4 pb-3">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-xs text-muted-foreground font-medium uppercase tracking-wide">Tables</p>
                      <p className="text-3xl font-bold text-gray-900 mt-1">{occupiedTables}/{tables.length}</p>
                    </div>
                    <div className="h-12 w-12 rounded-xl bg-blue-100 flex items-center justify-center">
                      <MapPin className="h-6 w-6 text-blue-600" />
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground mt-2">{availableTables} available</p>
                </CardContent>
              </Card>

              <Card className="border-l-4 border-l-purple-500">
                <CardContent className="pt-4 pb-3">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-xs text-muted-foreground font-medium uppercase tracking-wide">Reservations</p>
                      <p className="text-3xl font-bold text-gray-900 mt-1">{todayReservations}</p>
                    </div>
                    <div className="h-12 w-12 rounded-xl bg-purple-100 flex items-center justify-center">
                      <CalendarDays className="h-6 w-6 text-purple-600" />
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground mt-2">Today</p>
                </CardContent>
              </Card>
            </div>

            {/* Kitchen & Delivery row */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Kitchen Status */}
              <Card>
                <CardHeader className="pb-3">
                  <div className="flex items-center justify-between">
                    <CardTitle className="text-base flex items-center gap-2">
                      <div className="h-8 w-8 rounded-lg bg-amber-100 flex items-center justify-center"><ChefHat className="h-4 w-4 text-amber-600" /></div>
                      Kitchen Status
                    </CardTitle>
                    <Link href="/restaurant-kds"><Button variant="ghost" size="sm" className="text-xs text-rose-600">Open KDS <ArrowRight className="h-3 w-3 ml-1" /></Button></Link>
                  </div>
                </CardHeader>
                <CardContent>
                  {kdsStats ? (
                    <div className="grid grid-cols-3 gap-3">
                      <div className="text-center p-3 rounded-lg bg-blue-50">
                        <div className="text-2xl font-bold text-blue-700">{kdsStats.pendingCount}</div>
                        <div className="text-xs text-blue-600 font-medium">Pending</div>
                      </div>
                      <div className="text-center p-3 rounded-lg bg-amber-50">
                        <div className="text-2xl font-bold text-amber-700">{kdsStats.preparingCount}</div>
                        <div className="text-xs text-amber-600 font-medium">Preparing</div>
                      </div>
                      <div className="text-center p-3 rounded-lg bg-green-50">
                        <div className="text-2xl font-bold text-green-700">{kdsStats.readyCount}</div>
                        <div className="text-xs text-green-600 font-medium">Ready</div>
                      </div>
                    </div>
                  ) : (
                    <p className="text-sm text-muted-foreground text-center py-4">No kitchen data</p>
                  )}
                  {kdsStats?.longestWaitMinutes != null && kdsStats.longestWaitMinutes > 10 && (
                    <div className="mt-3 flex items-center gap-2 text-sm text-amber-700 bg-amber-50 rounded-lg px-3 py-2">
                      <AlertTriangle className="h-4 w-4" />
                      Longest wait: {Math.floor(kdsStats.longestWaitMinutes)}min
                    </div>
                  )}
                </CardContent>
              </Card>

              {/* Delivery Status */}
              <Card>
                <CardHeader className="pb-3">
                  <div className="flex items-center justify-between">
                    <CardTitle className="text-base flex items-center gap-2">
                      <div className="h-8 w-8 rounded-lg bg-indigo-100 flex items-center justify-center"><Truck className="h-4 w-4 text-indigo-600" /></div>
                      Delivery Status
                    </CardTitle>
                    <Link href="/restaurant-delivery"><Button variant="ghost" size="sm" className="text-xs text-rose-600">Manage <ArrowRight className="h-3 w-3 ml-1" /></Button></Link>
                  </div>
                </CardHeader>
                <CardContent>
                  {deliveryStats ? (
                    <div className="grid grid-cols-3 gap-3">
                      <div className="text-center p-3 rounded-lg bg-green-50">
                        <div className="text-2xl font-bold text-green-700">{deliveryStats.availableDrivers}</div>
                        <div className="text-xs text-green-600 font-medium">Drivers Free</div>
                      </div>
                      <div className="text-center p-3 rounded-lg bg-blue-50">
                        <div className="text-2xl font-bold text-blue-700">{deliveryStats.activeCount}</div>
                        <div className="text-xs text-blue-600 font-medium">Active</div>
                      </div>
                      <div className="text-center p-3 rounded-lg bg-gray-50">
                        <div className="text-2xl font-bold text-gray-700">{deliveryStats.deliveredCount}</div>
                        <div className="text-xs text-gray-600 font-medium">Delivered</div>
                      </div>
                    </div>
                  ) : (
                    <p className="text-sm text-muted-foreground text-center py-4">No delivery data</p>
                  )}
                </CardContent>
              </Card>
            </div>

            {/* Waitlist & Quick Actions row */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {/* Waitlist */}
              <Card>
                <CardHeader className="pb-3">
                  <CardTitle className="text-base flex items-center gap-2">
                    <div className="h-8 w-8 rounded-lg bg-orange-100 flex items-center justify-center"><Users className="h-4 w-4 text-orange-600" /></div>
                    Waitlist
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {waitlistStats && waitlistStats.waitingCount > 0 ? (
                    <div className="space-y-2">
                      <div className="flex justify-between text-sm"><span className="text-muted-foreground">Waiting</span><span className="font-bold">{waitlistStats.waitingCount}</span></div>
                      <div className="flex justify-between text-sm"><span className="text-muted-foreground">Notified</span><span className="font-bold">{waitlistStats.notifiedCount}</span></div>
                      {waitlistStats.avgWaitMins != null && <div className="flex justify-between text-sm"><span className="text-muted-foreground">Avg Wait</span><span className="font-bold">{Math.floor(waitlistStats.avgWaitMins)}min</span></div>}
                      <div className="flex justify-between text-sm"><span className="text-muted-foreground">Covers</span><span className="font-bold">{waitlistStats.totalCovers}</span></div>
                    </div>
                  ) : (
                    <p className="text-sm text-muted-foreground text-center py-4">No guests waiting</p>
                  )}
                </CardContent>
              </Card>

              {/* Quick Actions */}
              <Card className="md:col-span-2">
                <CardHeader className="pb-3">
                  <CardTitle className="text-base">Quick Actions</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                    {[
                      { href: "/restaurant-pos", label: "New Order", icon: ShoppingCart, color: "bg-rose-100 text-rose-600" },
                      { href: "/restaurant-orders", label: "View Orders", icon: ClipboardList, color: "bg-blue-100 text-blue-600" },
                      { href: "/restaurant-kds", label: "Kitchen", icon: ChefHat, color: "bg-amber-100 text-amber-600" },
                      { href: "/restaurant-reservations", label: "Reservations", icon: CalendarDays, color: "bg-purple-100 text-purple-600" },
                      { href: "/restaurant-floor-plan", label: "Floor Plan", icon: MapPin, color: "bg-teal-100 text-teal-600" },
                      { href: "/restaurant-menu", label: "Menu Items", icon: UtensilsCrossed, color: "bg-green-100 text-green-600" },
                      { href: "/restaurant-online-orders", label: "Online Orders", icon: Globe, color: "bg-indigo-100 text-indigo-600" },
                      { href: "/restaurant-delivery", label: "Delivery", icon: Truck, color: "bg-orange-100 text-orange-600" },
                    ].map(a => (
                      <Link key={a.href} href={a.href}>
                        <div className="flex items-center gap-3 p-3 rounded-xl border hover:border-rose-200 hover:bg-rose-50/30 transition-all cursor-pointer">
                          <div className={`h-9 w-9 rounded-lg flex items-center justify-center ${a.color}`}>
                            <a.icon className="h-4 w-4" />
                          </div>
                          <span className="text-sm font-medium text-gray-700">{a.label}</span>
                        </div>
                      </Link>
                    ))}
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Alerts */}
            {unavailableItems > 0 && (
              <Card className="border-amber-200 bg-amber-50">
                <CardContent className="py-3 flex items-center gap-3">
                  <AlertTriangle className="h-5 w-5 text-amber-600 flex-shrink-0" />
                  <span className="text-sm text-amber-800"><strong>{unavailableItems}</strong> menu item{unavailableItems !== 1 ? "s are" : " is"} currently 86'd (unavailable)</span>
                  <Link href="/restaurant-menu" className="ml-auto"><Button variant="outline" size="sm" className="text-xs border-amber-300 text-amber-700 hover:bg-amber-100">View Menu</Button></Link>
                </CardContent>
              </Card>
            )}

            {/* Recent Orders */}
            <Card>
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">Recent Orders</CardTitle>
                  <Link href="/restaurant-orders"><Button variant="ghost" size="sm" className="text-xs text-rose-600">View All <ArrowRight className="h-3 w-3 ml-1" /></Button></Link>
                </div>
              </CardHeader>
              <CardContent>
                {activeOrders.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-4">No active orders</p>
                ) : (
                  <div className="space-y-2">
                    {activeOrders.slice(0, 8).map(o => (
                      <div key={o.orderId} className="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-gray-50 transition-colors">
                        <div className="flex items-center gap-3">
                          <span className="font-mono font-bold text-sm text-gray-900">{o.orderNumber}</span>
                          <Badge variant="outline" className="text-[10px] h-5">{o.orderType}</Badge>
                          <Badge className={`text-[10px] h-5 text-white ${
                            o.status === "Placed" ? "bg-blue-500" : o.status === "Preparing" ? "bg-amber-500" : o.status === "Ready" ? "bg-green-500" : "bg-gray-500"
                          }`}>{o.status}</Badge>
                        </div>
                        <div className="flex items-center gap-4">
                          {o.tableNumber && <span className="text-xs text-muted-foreground">Table {o.tableNumber}</span>}
                          <span className="font-medium text-sm">{o.totalAmount.toFixed(2)}</span>
                          <span className="text-xs text-muted-foreground">{new Date(o.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
    </div>
  )
}

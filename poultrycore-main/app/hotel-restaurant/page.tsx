"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, ShoppingCart, Plus, Minus, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listRestaurantOrders, listRestaurantTables, listMenuItems, createRestaurantOrder,
  updateRestaurantOrderStatus, listHotelBookings,
  type HotelRestaurantOrder, type HotelRestaurantTable, type HotelMenuItem, type HotelBooking,
} from "@/lib/api/hotel"

const STATUS_COLOR: Record<string, string> = { Available: "bg-emerald-100 text-emerald-700", Occupied: "bg-violet-100 text-violet-700", Reserved: "bg-blue-100 text-blue-700" }
const ORDER_STATUS_COLOR: Record<string, string> = { Placed: "bg-red-100 text-red-700", Preparing: "bg-amber-100 text-amber-700", Ready: "bg-emerald-100 text-emerald-700", Served: "bg-slate-100 text-slate-700" }

interface CartItem { menuItem: any; quantity: number }

export default function HotelRestaurantPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [tables, setTables] = useState<HotelRestaurantTable[]>([]); const [orders, setOrders] = useState<HotelRestaurantOrder[]>([])
  const [menuItems, setMenuItems] = useState<HotelMenuItem[]>([]); const [bookings, setBookings] = useState<HotelBooking[]>([])
  const [loading, setLoading] = useState(true)
  const [filterOrderStatus, setFilterOrderStatus] = useState("active")

  // POS dialog
  const [posOpen, setPosOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [posForm, setPosForm] = useState({ tableNumber: "", serverName: "", hotelBookingId: null as number | null })
  const [cart, setCart] = useState<CartItem[]>([])
  const [menuFilter, setMenuFilter] = useState("all")

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() {
    setLoading(true)
    try {
      const [t, o, m, b] = await Promise.all([listRestaurantTables(), listRestaurantOrders(), listMenuItems(), listHotelBookings()])
      setTables(t); setOrders(o); setMenuItems(m); setBookings(b.filter(x => x.status === "CheckedIn"))
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function addToCart(item: any) {
    const id = item.hotelMenuItemId ?? item.hotelmenuitemid
    const existing = cart.find(c => (c.menuItem.hotelMenuItemId ?? c.menuItem.hotelmenuitemid) === id)
    if (existing) { setCart(cart.map(c => (c.menuItem.hotelMenuItemId ?? c.menuItem.hotelmenuitemid) === id ? { ...c, quantity: c.quantity + 1 } : c)) }
    else { setCart([...cart, { menuItem: item, quantity: 1 }]) }
  }

  function updateCartQty(idx: number, delta: number) {
    const updated = [...cart]
    updated[idx].quantity = Math.max(0, updated[idx].quantity + delta)
    setCart(updated.filter(c => c.quantity > 0))
  }

  const cartTotal = cart.reduce((s, c) => s + Number(c.menuItem.price) * c.quantity, 0)

  async function handleCreateOrder() {
    setSaving(true)
    try {
      const tbl = posForm.tableNumber === "__none__" ? undefined : posForm.tableNumber || undefined
      await createRestaurantOrder({
        tableNumber: tbl,
        serverName: posForm.serverName || undefined,
        hotelBookingId: posForm.hotelBookingId ?? undefined,
        items: cart.map(c => ({ menuItemId: c.menuItem.hotelMenuItemId ?? c.menuItem.hotelmenuitemid, quantity: c.quantity, unitPrice: Number(c.menuItem.price) }))
      })
      toast({ title: `Order created — ${cartTotal.toFixed(2)}` })
      setPosOpen(false); setCart([]); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const filteredOrders = orders.filter((o: any) => {
    if (filterOrderStatus === "active") return o.status === "Placed" || o.status === "Preparing" || o.status === "Ready"
    return true
  })

  const menuCategories = [...new Set(menuItems.map((m: any) => m.category))]
  const filteredMenu = menuFilter === "all" ? menuItems : menuItems.filter((m: any) => m.category === menuFilter)

  const activeOrderCount = orders.filter((o: any) => o.status === "Placed" || o.status === "Preparing").length
  const todayRevenue = orders.filter((o: any) => o.status === "Served").reduce((s: number, o: any) => s + Number(o.totalAmount ?? o.totalamount ?? 0), 0)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3"><ShoppingCart className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Restaurant & Bar</h1></div>
          <Button onClick={() => { setPosForm({ tableNumber: "", serverName: "", hotelBookingId: null }); setCart([]); setMenuFilter("all"); setPosOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> New Order (POS)</Button>
        </div>

        {/* Summary */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
          <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-violet-700">{tables.length}</div><div className="text-xs text-slate-500">Tables</div></CardContent></Card>
          <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-red-700">{activeOrderCount}</div><div className="text-xs text-slate-500">Active Orders</div></CardContent></Card>
          <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-emerald-700">{todayRevenue.toFixed(2)}</div><div className="text-xs text-slate-500">Served Revenue</div></CardContent></Card>
          <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-violet-700">{menuItems.length}</div><div className="text-xs text-slate-500">Menu Items</div></CardContent></Card>
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <>
            {/* Tables */}
            <h2 className="text-sm font-semibold text-slate-400 uppercase mb-2">Tables</h2>
            <div className="grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10 gap-2 mb-6">
              {tables.map((t: any, idx: number) => (
                <div key={t.hotelRestaurantTableId ?? t.hotelrestauranttableid ?? `t-${idx}`} className={`p-2 rounded-lg border text-center ${STATUS_COLOR[t.status] ?? "bg-slate-50"}`}>
                  <div className="font-bold text-sm">{t.tableNumber ?? t.tablenumber}</div>
                  <div className="text-[10px]">{t.capacity} seats</div>
                </div>
              ))}
              {tables.length === 0 && <div className="col-span-full text-sm text-slate-400">No tables. Add from Restaurant Tables page.</div>}
            </div>

            {/* Orders */}
            <div className="flex items-center justify-between mb-2">
              <h2 className="text-sm font-semibold text-slate-400 uppercase">Orders</h2>
              <div className="flex gap-2">
                <Button variant={filterOrderStatus === "active" ? "default" : "outline"} size="sm" onClick={() => setFilterOrderStatus("active")} className={filterOrderStatus === "active" ? "bg-violet-600" : ""}>Active</Button>
                <Button variant={filterOrderStatus === "all" ? "default" : "outline"} size="sm" onClick={() => setFilterOrderStatus("all")} className={filterOrderStatus === "all" ? "bg-violet-600" : ""}>All ({orders.length})</Button>
              </div>
            </div>
            <Card><CardContent className="p-0">
              <table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">#</th><th className="text-left p-3">Table</th><th className="text-left p-3">Server</th><th className="text-left p-3">Status</th><th className="text-right p-3">Total</th><th className="text-left p-3">Time</th><th className="text-right p-3">Action</th></tr></thead>
                <tbody>{filteredOrders.map((o: any, idx: number) => {
                  const id = o.hotelRestaurantOrderId ?? o.hotelrestaurantorderid
                  const next: Record<string, string> = { Placed: "Preparing", Preparing: "Ready", Ready: "Served" }
                  return (
                    <tr key={id ?? `o-${idx}`} className="border-b hover:bg-slate-50">
                      <td className="p-3 font-mono text-xs">{id}</td>
                      <td className="p-3 font-semibold">{o.tableNumber ?? o.tablenumber ?? "Takeaway"}</td>
                      <td className="p-3">{o.serverName ?? o.servername ?? "—"}</td>
                      <td className="p-3"><Badge variant="outline" className={ORDER_STATUS_COLOR[o.status] ?? ""}>{o.status}</Badge></td>
                      <td className="p-3 text-right font-semibold">{Number(o.totalAmount ?? o.totalamount ?? 0).toFixed(2)}</td>
                      <td className="p-3 text-xs text-slate-500">{(o.orderTime ?? o.ordertime) ? new Date(o.orderTime ?? o.ordertime).toLocaleString() : "—"}</td>
                      <td className="p-3 text-right">
                        {next[o.status] && <Button size="sm" variant="outline" onClick={async () => { await updateRestaurantOrderStatus(id, next[o.status]); toast({ title: `→ ${next[o.status]}` }); await load() }}>{next[o.status]}</Button>}
                      </td>
                    </tr>
                  )
                })}
                  {filteredOrders.length === 0 && <tr><td colSpan={7} className="p-8 text-center text-slate-400">No orders.</td></tr>}
                </tbody></table>
            </CardContent></Card>
          </>
        )}

        {/* POS Dialog */}
        <Dialog open={posOpen} onOpenChange={setPosOpen}>
          <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
            <DialogHeader><DialogTitle>New Order — Point of Sale</DialogTitle></DialogHeader>
            <div className="grid md:grid-cols-2 gap-4">
              {/* Left: Menu */}
              <div>
                <div className="flex gap-1 flex-wrap mb-3">
                  <Button variant={menuFilter === "all" ? "default" : "outline"} size="sm" onClick={() => setMenuFilter("all")} className={menuFilter === "all" ? "bg-violet-600 text-xs" : "text-xs"}>All</Button>
                  {menuCategories.map(c => <Button key={c} variant={menuFilter === c ? "default" : "outline"} size="sm" onClick={() => setMenuFilter(c)} className={menuFilter === c ? "bg-violet-600 text-xs" : "text-xs"}>{c}</Button>)}
                </div>
                <div className="space-y-1 max-h-[350px] overflow-y-auto">
                  {filteredMenu.map((m: any, idx: number) => (
                    <button key={m.hotelMenuItemId ?? m.hotelmenuitemid ?? `mi-${idx}`} onClick={() => addToCart(m)} className="w-full flex items-center justify-between p-2 rounded-lg hover:bg-violet-50 border border-transparent hover:border-violet-200 transition-colors text-left">
                      <div><div className="font-medium text-sm">{m.name}</div><div className="text-xs text-slate-400">{m.category}</div></div>
                      <span className="font-semibold text-violet-700 text-sm">{Number(m.price).toFixed(2)}</span>
                    </button>
                  ))}
                  {filteredMenu.length === 0 && <div className="text-center py-4 text-slate-400 text-sm">No menu items. Add from Menu page.</div>}
                </div>
              </div>

              {/* Right: Cart + Order info */}
              <div>
                <div className="space-y-3 mb-4">
                  <div><Label className="text-xs">Table</Label>
                    <Select value={posForm.tableNumber || "__none__"} onValueChange={(v) => setPosForm({...posForm, tableNumber: v})}>
                      <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__none__">Takeaway / No table</SelectItem>
                        {tables.map((t: any, i: number) => <SelectItem key={t.hotelRestaurantTableId ?? t.hotelrestauranttableid ?? `ts-${i}`} value={t.tableNumber ?? t.tablenumber}>{t.tableNumber ?? t.tablenumber} ({t.capacity} seats)</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    <div><Label className="text-xs">Server</Label><Input className="h-9" value={posForm.serverName} onChange={(e) => setPosForm({...posForm, serverName: e.target.value})} placeholder="Server name" /></div>
                    <div><Label className="text-xs">Room Guest (optional)</Label>
                      <Select value={posForm.hotelBookingId ? String(posForm.hotelBookingId) : "__none__"} onValueChange={(v) => setPosForm({...posForm, hotelBookingId: v === "__none__" ? null : Number(v)})}>
                        <SelectTrigger className="h-9"><SelectValue placeholder="Not linked" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="__none__">Not linked to room</SelectItem>
                          {bookings.map(b => <SelectItem key={b.hotelBookingId} value={String(b.hotelBookingId)}>Room {b.roomNumber} — {b.guestFirstName} {b.guestLastName}</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                </div>

                {/* Cart */}
                <div className="border rounded-lg p-3">
                  <h4 className="font-semibold text-sm mb-2">Order Items ({cart.length})</h4>
                  {cart.length === 0 ? <div className="text-center py-4 text-slate-400 text-xs">Tap menu items to add</div> : (
                    <div className="space-y-2">
                      {cart.map((c, idx) => (
                        <div key={idx} className="flex items-center justify-between text-sm">
                          <div className="flex-1"><div className="font-medium">{c.menuItem.name}</div><div className="text-xs text-slate-400">{Number(c.menuItem.price).toFixed(2)} each</div></div>
                          <div className="flex items-center gap-1">
                            <Button variant="outline" size="icon" className="h-6 w-6" onClick={() => updateCartQty(idx, -1)}><Minus className="h-3 w-3" /></Button>
                            <span className="w-6 text-center font-semibold">{c.quantity}</span>
                            <Button variant="outline" size="icon" className="h-6 w-6" onClick={() => updateCartQty(idx, 1)}><Plus className="h-3 w-3" /></Button>
                            <span className="w-16 text-right font-semibold">{(Number(c.menuItem.price) * c.quantity).toFixed(2)}</span>
                            <Button variant="ghost" size="icon" className="h-6 w-6 text-red-500" onClick={() => setCart(cart.filter((_, i) => i !== idx))}><Trash2 className="h-3 w-3" /></Button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                  <div className="border-t mt-3 pt-3 flex justify-between font-bold text-lg">
                    <span>Total</span>
                    <span className="text-violet-700">{cartTotal.toFixed(2)}</span>
                  </div>
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setPosOpen(false)}>Cancel</Button>
              <Button onClick={handleCreateOrder} disabled={saving || cart.length === 0} className="bg-violet-600 hover:bg-violet-700">
                {saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
                Place Order — {cartTotal.toFixed(2)}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </main>
    </div></div>
  )
}

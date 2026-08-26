"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Loader2, Activity, ArrowRight } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listRestaurantOrders, updateRestaurantOrderStatus, type HotelRestaurantOrder } from "@/lib/api/hotel"

const STATUSES = ["Placed", "Preparing", "Ready", "Served"] as const
const STATUS_COLOR: Record<string, string> = { Placed: "bg-red-500", Preparing: "bg-amber-500", Ready: "bg-emerald-500", Served: "bg-slate-400" }
const STATUS_BG: Record<string, string> = { Placed: "border-red-300 bg-red-50", Preparing: "border-amber-300 bg-amber-50", Ready: "border-emerald-300 bg-emerald-50", Served: "border-slate-200 bg-slate-50" }
const NEXT_STATUS: Record<string, string> = { Placed: "Preparing", Preparing: "Ready", Ready: "Served" }

export default function HotelKitchenPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [orders, setOrders] = useState<HotelRestaurantOrder[]>([]); const [loading, setLoading] = useState(true)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setOrders(await listRestaurantOrders()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function moveToNext(order: any) {
    const next = NEXT_STATUS[order.status]
    if (!next) return
    try {
      await updateRestaurantOrderStatus(order.hotelRestaurantOrderId ?? order.hotelrestaurantorderid, next)
      toast({ title: `Order moved to ${next}` }); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const [filterView, setFilterView] = useState<"active" | "all">("active")
  const activeCount = orders.filter((o: any) => o.status === "Placed" || o.status === "Preparing").length
  const readyCount = orders.filter((o: any) => o.status === "Ready").length
  const servedCount = orders.filter((o: any) => o.status === "Served").length
  const displayStatuses = filterView === "active" ? ["Placed", "Preparing", "Ready"] as const : STATUSES

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3"><Activity className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Kitchen Display</h1></div>
          <div className="flex items-center gap-2">
            {activeCount > 0 && <Badge className="bg-red-100 text-red-700">{activeCount} active</Badge>}
            {readyCount > 0 && <Badge className="bg-emerald-100 text-emerald-700">{readyCount} ready to serve</Badge>}
            <Badge className="bg-slate-100 text-slate-700">{servedCount} served today</Badge>
          </div>
        </div>
        <div className="flex gap-2 mb-4">
          <Button variant={filterView === "active" ? "default" : "outline"} size="sm" onClick={() => setFilterView("active")} className={filterView === "active" ? "bg-violet-600" : ""}>Active Orders</Button>
          <Button variant={filterView === "all" ? "default" : "outline"} size="sm" onClick={() => setFilterView("all")} className={filterView === "all" ? "bg-violet-600" : ""}>All Orders ({orders.length})</Button>
        </div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <div className={`grid gap-4 ${filterView === "active" ? "md:grid-cols-3" : "md:grid-cols-4"}`}>
            {displayStatuses.map(status => {
              const col = orders.filter((o: any) => o.status === status)
              return (
                <div key={status}>
                  <div className="flex items-center gap-2 mb-3">
                    <div className={`w-3 h-3 rounded-full ${STATUS_COLOR[status]}`} />
                    <h3 className="font-semibold text-sm uppercase">{status}</h3>
                    <span className="text-xs text-slate-400">({col.length})</span>
                  </div>
                  <div className="space-y-3">
                    {col.map((o: any, idx: number) => {
                      const next = NEXT_STATUS[status]
                      const time = o.orderTime ?? o.ordertime
                      const elapsed = time ? Math.round((Date.now() - new Date(time).getTime()) / 60000) : 0
                      return (
                        <Card key={o.hotelRestaurantOrderId ?? o.hotelrestaurantorderid ?? `ko-${idx}`} className={`border-l-4 ${STATUS_BG[status]}`}>
                          <CardContent className="p-3 space-y-2">
                            <div className="flex items-center justify-between">
                              <span className="font-bold">Table {o.tableNumber ?? o.tablenumber ?? "Takeaway"}</span>
                              <span className="text-xs text-slate-400">{elapsed}m ago</span>
                            </div>
                            {(o.serverName ?? o.servername) && <div className="text-xs text-slate-500">Server: {o.serverName ?? o.servername}</div>}
                            {Number(o.totalAmount ?? o.totalamount ?? 0) > 0 && <div className="text-sm font-semibold">GH₵{Number(o.totalAmount ?? o.totalamount ?? 0).toFixed(2)}</div>}
                            {(o.notes) && <div className="text-xs text-slate-500 italic">{o.notes}</div>}
                            {status === "Served" && <div className="text-xs text-emerald-600 font-semibold">✓ Served {(o.deliveredTime ?? o.deliveredtime) ? new Date(o.deliveredTime ?? o.deliveredtime).toLocaleTimeString() : ""}</div>}
                            {next && (
                              <Button size="sm" className="w-full mt-1" variant={status === "Placed" ? "destructive" : status === "Preparing" ? "default" : "outline"} onClick={() => moveToNext(o)}>
                                Move to {next} <ArrowRight className="h-3 w-3 ml-1" />
                              </Button>
                            )}
                          </CardContent>
                        </Card>
                      )
                    })}
                    {col.length === 0 && <div className="text-center py-6 text-xs text-slate-300 border border-dashed rounded-lg">Empty</div>}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </main></div></div>
  )
}

"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Loader2, ShoppingCart } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listRestaurantOrders, type HotelRestaurantOrder } from "@/lib/api/hotel"

const STATUS_COLOR: Record<string, string> = { Placed: "bg-blue-100 text-blue-700", Preparing: "bg-amber-100 text-amber-700", Ready: "bg-emerald-100 text-emerald-700", Delivered: "bg-slate-100 text-slate-700", Served: "bg-slate-100 text-slate-700", Cancelled: "bg-red-100 text-red-700" }

export default function HotelRoomServicePage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [orders, setOrders] = useState<HotelRestaurantOrder[]>([]); const [loading, setLoading] = useState(true)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setOrders(await listRestaurantOrders()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><ShoppingCart className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Room Service Orders</h1><span className="text-sm text-slate-500">({orders.length})</span></div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Time</th><th className="text-left p-3">Table/Room</th><th className="text-left p-3">Server</th><th className="text-left p-3">Status</th><th className="text-right p-3">Amount</th></tr></thead>
            <tbody>{orders.map((o: any) => (<tr key={o.hotelRestaurantOrderId ?? o.hotelrestaurantorderid} className="border-b hover:bg-slate-50"><td className="p-3">{new Date(o.orderTime ?? o.ordertime).toLocaleString()}</td><td className="p-3">{o.tableNumber ?? o.tablenumber ?? "Room"}</td><td className="p-3">{o.serverName ?? o.servername ?? "-"}</td><td className="p-3"><Badge variant="outline" className={STATUS_COLOR[o.status] ?? ""}>{o.status}</Badge></td><td className="p-3 text-right font-semibold">{Number(o.totalAmount ?? o.totalamount ?? 0).toFixed(2)}</td></tr>))}
              {orders.length === 0 && <tr><td colSpan={5} className="p-8 text-center text-slate-400">No room service orders yet.</td></tr>}
            </tbody></table></CardContent></Card>
        )}
      </main></div></div>
  )
}

"use client"
import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Loader2, History, Search } from "lucide-react"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listCheckInHistory, listCheckOutHistory } from "@/lib/api/hotel"

export default function HotelStayHistoryPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [checkins, setCheckins] = useState<any[]>([]); const [checkouts, setCheckouts] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState(""); const [page, setPage] = useState(1); const pageSize = 10

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { const [ci, co] = await Promise.all([listCheckInHistory(), listCheckOutHistory()]); setCheckins(ci); setCheckouts(co) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  const filterFn = (item: any) => {
    if (!search) return true
    const q = search.toLowerCase()
    return `${item.firstname ?? ""} ${item.lastname ?? ""}`.toLowerCase().includes(q) || (item.bookingref ?? "").toLowerCase().includes(q) || (item.roomnumber ?? "").toLowerCase().includes(q)
  }
  const filteredCI = useMemo(() => checkins.filter(filterFn), [checkins, search])
  const filteredCO = useMemo(() => checkouts.filter(filterFn), [checkouts, search])
  const pagedCI = filteredCI.slice((page - 1) * pageSize, page * pageSize)
  const pagedCO = filteredCO.slice((page - 1) * pageSize, page * pageSize)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><History className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Stay History</h1></div>
        <div className="mb-4 relative max-w-sm"><Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search guest, ref, room..." className="pl-9" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} /></div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Tabs defaultValue="checkins">
            <TabsList className="mb-4"><TabsTrigger value="checkins">Check-ins ({filteredCI.length})</TabsTrigger><TabsTrigger value="checkouts">Check-outs ({filteredCO.length})</TabsTrigger></TabsList>
            <TabsContent value="checkins"><Card><CardContent className="p-0">
              <table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Guest</th><th className="text-left p-3">Room</th><th className="text-left p-3">Booking Ref</th><th className="text-left p-3">Check-in Time</th><th className="text-left p-3">Key Card</th><th className="text-right p-3">Deposit</th></tr></thead>
                <tbody>{pagedCI.map((ci: any, i) => (
                  <tr key={ci.hotelcheckinid ?? i} className="border-b hover:bg-slate-50">
                    <td className="p-3 font-semibold">{ci.firstname} {ci.lastname}</td>
                    <td className="p-3"><Badge variant="outline">{ci.roomnumber ?? "—"}</Badge></td>
                    <td className="p-3 font-mono text-xs">{ci.bookingref}</td>
                    <td className="p-3 text-xs">{ci.checkintime ? new Date(ci.checkintime).toLocaleString() : "—"}</td>
                    <td className="p-3">{ci.keycardnumber ?? "—"}</td>
                    <td className="p-3 text-right">{Number(ci.depositamount ?? 0).toFixed(2)}</td>
                  </tr>
                ))}{filteredCI.length === 0 && <tr><td colSpan={6} className="p-8 text-center text-slate-400">No check-in history.</td></tr>}</tbody>
              </table>
              <PaginationControls page={page} pageSize={pageSize} total={filteredCI.length} onPageChange={setPage} />
            </CardContent></Card></TabsContent>
            <TabsContent value="checkouts"><Card><CardContent className="p-0">
              <table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Guest</th><th className="text-left p-3">Room</th><th className="text-left p-3">Booking Ref</th><th className="text-left p-3">Check-out Time</th><th className="text-right p-3">Final Bill</th><th className="text-right p-3">Late Fee</th></tr></thead>
                <tbody>{pagedCO.map((co: any, i) => (
                  <tr key={co.hotelcheckoutid ?? i} className="border-b hover:bg-slate-50">
                    <td className="p-3 font-semibold">{co.firstname} {co.lastname}</td>
                    <td className="p-3"><Badge variant="outline">{co.roomnumber ?? "—"}</Badge></td>
                    <td className="p-3 font-mono text-xs">{co.bookingref}</td>
                    <td className="p-3 text-xs">{co.checkouttime ? new Date(co.checkouttime).toLocaleString() : "—"}</td>
                    <td className="p-3 text-right font-semibold">{Number(co.finalbillamount ?? 0).toFixed(2)}</td>
                    <td className="p-3 text-right">{Number(co.latefee ?? 0).toFixed(2)}</td>
                  </tr>
                ))}{filteredCO.length === 0 && <tr><td colSpan={6} className="p-8 text-center text-slate-400">No check-out history.</td></tr>}</tbody>
              </table>
              <PaginationControls page={page} pageSize={pageSize} total={filteredCO.length} onPageChange={setPage} />
            </CardContent></Card></TabsContent>
          </Tabs>
        )}
      </main></div></div>
  )
}

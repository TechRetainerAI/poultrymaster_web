"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Search, Bed, BedDouble } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { checkRoomAvailability, listHotelRoomTypes, type HotelRoomType } from "@/lib/api/hotel"

export default function HotelAvailabilityPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [roomTypes, setRoomTypes] = useState<HotelRoomType[]>([])
  const [results, setResults] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [searched, setSearched] = useState(false)

  const today = new Date().toISOString().slice(0, 10)
  const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10)
  const [checkIn, setCheckIn] = useState(today)
  const [checkOut, setCheckOut] = useState(tomorrow)
  const [roomTypeFilter, setRoomTypeFilter] = useState("all")

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; loadTypes() }, [activeFarmType, router])
  async function loadTypes() { try { setRoomTypes(await listHotelRoomTypes()) } catch {} }

  async function handleSearch() {
    if (!checkIn || !checkOut) { toast({ title: "Select dates", variant: "destructive" }); return }
    if (checkOut <= checkIn) { toast({ title: "Check-out must be after check-in", variant: "destructive" }); return }
    setLoading(true); setSearched(true)
    try {
      const rtId = roomTypeFilter !== "all" ? Number(roomTypeFilter) : undefined
      setResults(await checkRoomAvailability(checkIn, checkOut, rtId))
    } catch (e: any) { toast({ title: "Search failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // Group by floor
  const floors = new Map<string, any[]>()
  results.forEach((r) => { const f = r.floorname ?? "Unassigned"; if (!floors.has(f)) floors.set(f, []); floors.get(f)!.push(r) })

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><Search className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Room Availability</h1></div>

        <Card className="mb-6"><CardContent className="p-4">
          <div className="flex gap-4 flex-wrap items-end">
            <div><Label>Check-in *</Label><Input type="date" value={checkIn} onChange={(e) => setCheckIn(e.target.value)} className="w-44" /></div>
            <div><Label>Check-out *</Label><Input type="date" value={checkOut} min={checkIn} onChange={(e) => setCheckOut(e.target.value)} className="w-44" /></div>
            <div><Label>Room Type</Label>
              <Select value={roomTypeFilter} onValueChange={setRoomTypeFilter}>
                <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Types</SelectItem>
                  {roomTypes.map((rt: any) => <SelectItem key={rt.hotelRoomTypeId ?? rt.hotelroomtypeid} value={String(rt.hotelRoomTypeId ?? rt.hotelroomtypeid)}>{rt.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <Button onClick={handleSearch} disabled={loading} className="bg-violet-600 hover:bg-violet-700">
              {loading ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Search className="h-4 w-4 mr-1" />} Search
            </Button>
          </div>
        </CardContent></Card>

        {searched && !loading && (
          <>
            <div className="mb-4 flex items-center gap-2">
              <BedDouble className="h-5 w-5 text-violet-600" />
              <span className="text-lg font-semibold">{results.length} room(s) available</span>
              <span className="text-sm text-slate-500">for {checkIn} to {checkOut}</span>
            </div>
            {results.length === 0 ? (
              <div className="text-center py-12 text-slate-400">No rooms available for the selected dates and type.</div>
            ) : (
              Array.from(floors.entries()).map(([floorName, rooms]) => (
                <div key={floorName} className="mb-4">
                  <Badge variant="outline" className="mb-2 bg-violet-50 text-violet-700">{floorName}</Badge>
                  <div className="grid gap-3 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
                    {rooms.map((r: any) => (
                      <Card key={r.hotelroomid} className="hover:shadow-md transition-shadow">
                        <CardContent className="p-4">
                          <div className="flex items-center justify-between mb-2">
                            <span className="text-lg font-bold">Room {r.roomnumber}</span>
                            <Badge variant="outline" className="bg-emerald-50 text-emerald-700">{r.status}</Badge>
                          </div>
                          <div className="text-sm text-slate-600">{r.roomtypename}</div>
                          <div className="text-lg font-bold text-violet-700 mt-1">{Number(r.baserate ?? 0).toFixed(2)} /night</div>
                          <Button size="sm" className="w-full mt-3 bg-violet-600 hover:bg-violet-700" onClick={() => router.push("/hotel-bookings")}>
                            <Bed className="h-4 w-4 mr-1" /> Book Now
                          </Button>
                        </CardContent>
                      </Card>
                    ))}
                  </div>
                </div>
              ))
            )}
          </>
        )}
        {loading && <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>}
      </main></div></div>
  )
}

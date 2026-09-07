"use client"
import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Loader2, History, Search, User, Phone, Mail, MapPin, Globe, CreditCard, Star, Calendar, Bed } from "lucide-react"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listCheckInHistory, listCheckOutHistory, listHotelGuests, listHotelBookings, type HotelGuest, type HotelBooking } from "@/lib/api/hotel"

export default function HotelStayHistoryPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [checkins, setCheckins] = useState<any[]>([]); const [checkouts, setCheckouts] = useState<any[]>([])
  const [guests, setGuests] = useState<HotelGuest[]>([]); const [bookings, setBookings] = useState<HotelBooking[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState(""); const [page, setPage] = useState(1); const pageSize = 10

  // Guest detail dialog
  const [selectedGuest, setSelectedGuest] = useState<HotelGuest | null>(null)
  const [guestBookings, setGuestBookings] = useState<HotelBooking[]>([])
  const [guestCheckins, setGuestCheckins] = useState<any[]>([])
  const [guestCheckouts, setGuestCheckouts] = useState<any[]>([])

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() {
    setLoading(true)
    try {
      const [ci, co, g, b] = await Promise.all([listCheckInHistory(), listCheckOutHistory(), listHotelGuests().catch(() => []), listHotelBookings().catch(() => [])])
      setCheckins(ci); setCheckouts(co); setGuests(g); setBookings(b)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openGuestDetail(item: any) {
    const guestId = item.hotelguestid ?? item.hotelGuestId
    const guest = guests.find(g => g.hotelGuestId === guestId)
    if (!guest) {
      // Fallback: build a partial guest from the row data
      setSelectedGuest({
        hotelGuestId: guestId ?? 0, farmId: "", firstName: item.firstname ?? "", lastName: item.lastname ?? "",
        email: item.email ?? item.guestemail ?? null, phone: item.phone ?? item.guestphone ?? null,
        idType: item.idtype ?? null, idNumber: item.idnumber ?? null, nationality: item.nationality ?? null,
        address: item.address ?? null, isVIP: item.isvip ?? false, totalStays: 0, createdAt: "",
      } as HotelGuest)
    } else {
      setSelectedGuest(guest)
    }
    // Filter bookings/checkins/checkouts for this guest
    if (guestId) {
      setGuestBookings(bookings.filter(b => b.hotelGuestId === guestId))
      setGuestCheckins(checkins.filter((ci: any) => (ci.hotelguestid ?? ci.hotelGuestId) === guestId))
      setGuestCheckouts(checkouts.filter((co: any) => (co.hotelguestid ?? co.hotelGuestId) === guestId))
    }
  }

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
                  <tr key={ci.hotelcheckinid ?? i} className="border-b hover:bg-violet-50 cursor-pointer transition-colors" onClick={() => openGuestDetail(ci)}>
                    <td className="p-3 font-semibold text-violet-700">{ci.firstname} {ci.lastname}</td>
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
                  <tr key={co.hotelcheckoutid ?? i} className="border-b hover:bg-violet-50 cursor-pointer transition-colors" onClick={() => openGuestDetail(co)}>
                    <td className="p-3 font-semibold text-violet-700">{co.firstname} {co.lastname}</td>
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

        {/* Guest Detail Dialog */}
        <Dialog open={!!selectedGuest} onOpenChange={() => setSelectedGuest(null)}>
          <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
            {selectedGuest && (
              <>
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <div className="h-10 w-10 bg-violet-100 rounded-full flex items-center justify-center">
                      <User className="h-5 w-5 text-violet-700" />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        {selectedGuest.firstName} {selectedGuest.lastName}
                        {selectedGuest.isVIP && <Star className="h-4 w-4 text-amber-500 fill-amber-500" />}
                      </div>
                      <div className="text-xs text-slate-500 font-normal">{selectedGuest.totalStays} stay(s)</div>
                    </div>
                  </DialogTitle>
                </DialogHeader>

                {/* Contact Info */}
                <Card className="border-violet-100">
                  <CardHeader className="pb-2"><CardTitle className="text-xs uppercase text-slate-500">Contact Information</CardTitle></CardHeader>
                  <CardContent className="space-y-2 text-sm">
                    <div className="grid grid-cols-2 gap-3">
                      {selectedGuest.phone && <div className="flex items-center gap-2"><Phone className="h-4 w-4 text-slate-400" /><span>{selectedGuest.phone}</span></div>}
                      {selectedGuest.email && <div className="flex items-center gap-2"><Mail className="h-4 w-4 text-slate-400" /><span>{selectedGuest.email}</span></div>}
                      {selectedGuest.nationality && <div className="flex items-center gap-2"><Globe className="h-4 w-4 text-slate-400" /><span>{selectedGuest.nationality}</span></div>}
                      {selectedGuest.address && <div className="flex items-center gap-2 col-span-2"><MapPin className="h-4 w-4 text-slate-400 shrink-0" /><span>{selectedGuest.address}</span></div>}
                    </div>
                  </CardContent>
                </Card>

                {/* ID Info */}
                {selectedGuest.idType && (
                  <Card>
                    <CardHeader className="pb-2"><CardTitle className="text-xs uppercase text-slate-500">Identification</CardTitle></CardHeader>
                    <CardContent className="text-sm">
                      <div className="flex items-center gap-2">
                        <CreditCard className="h-4 w-4 text-slate-400" />
                        <span className="font-medium">{selectedGuest.idType}</span>
                        {selectedGuest.idNumber && <span className="font-mono text-slate-600">— {selectedGuest.idNumber}</span>}
                      </div>
                    </CardContent>
                  </Card>
                )}

                {/* Booking History */}
                {guestBookings.length > 0 && (
                  <Card>
                    <CardHeader className="pb-2"><CardTitle className="text-xs uppercase text-slate-500">Booking History ({guestBookings.length})</CardTitle></CardHeader>
                    <CardContent className="p-0">
                      <table className="w-full text-xs">
                        <thead className="bg-slate-50 border-b"><tr><th className="text-left p-2">Ref</th><th className="text-left p-2">Room</th><th className="text-left p-2">Dates</th><th className="text-left p-2">Status</th><th className="text-right p-2">Amount</th></tr></thead>
                        <tbody>
                          {guestBookings.map((b) => (
                            <tr key={b.hotelBookingId} className="border-b">
                              <td className="p-2 font-mono">{b.bookingRef}</td>
                              <td className="p-2">{b.roomNumber ?? "—"}</td>
                              <td className="p-2">{b.checkInDate?.slice(0, 10)} → {b.checkOutDate?.slice(0, 10)}</td>
                              <td className="p-2">
                                <Badge variant="outline" className={
                                  b.status === "CheckedIn" ? "bg-emerald-50 text-emerald-700" :
                                  b.status === "CheckedOut" ? "bg-slate-100 text-slate-600" :
                                  b.status === "Confirmed" ? "bg-blue-50 text-blue-700" :
                                  b.status === "Cancelled" ? "bg-red-50 text-red-700" :
                                  "bg-slate-50"
                                }>{b.status}</Badge>
                              </td>
                              <td className="p-2 text-right font-semibold">{Number(b.totalAmount ?? 0).toFixed(2)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                )}

                {/* Check-in History */}
                {guestCheckins.length > 0 && (
                  <Card>
                    <CardHeader className="pb-2"><CardTitle className="text-xs uppercase text-slate-500">Check-in History ({guestCheckins.length})</CardTitle></CardHeader>
                    <CardContent className="p-0">
                      <table className="w-full text-xs">
                        <thead className="bg-slate-50 border-b"><tr><th className="text-left p-2">Date</th><th className="text-left p-2">Room</th><th className="text-left p-2">Key Card</th><th className="text-right p-2">Deposit</th></tr></thead>
                        <tbody>
                          {guestCheckins.map((ci: any, i: number) => (
                            <tr key={ci.hotelcheckinid ?? i} className="border-b">
                              <td className="p-2">{ci.checkintime ? new Date(ci.checkintime).toLocaleDateString() : "—"}</td>
                              <td className="p-2">{ci.roomnumber ?? "—"}</td>
                              <td className="p-2">{ci.keycardnumber ?? "—"}</td>
                              <td className="p-2 text-right">{Number(ci.depositamount ?? 0).toFixed(2)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                )}

                {/* Check-out History */}
                {guestCheckouts.length > 0 && (
                  <Card>
                    <CardHeader className="pb-2"><CardTitle className="text-xs uppercase text-slate-500">Check-out History ({guestCheckouts.length})</CardTitle></CardHeader>
                    <CardContent className="p-0">
                      <table className="w-full text-xs">
                        <thead className="bg-slate-50 border-b"><tr><th className="text-left p-2">Date</th><th className="text-left p-2">Room</th><th className="text-right p-2">Final Bill</th><th className="text-right p-2">Late Fee</th></tr></thead>
                        <tbody>
                          {guestCheckouts.map((co: any, i: number) => (
                            <tr key={co.hotelcheckoutid ?? i} className="border-b">
                              <td className="p-2">{co.checkouttime ? new Date(co.checkouttime).toLocaleDateString() : "—"}</td>
                              <td className="p-2">{co.roomnumber ?? "—"}</td>
                              <td className="p-2 text-right font-semibold">{Number(co.finalbillamount ?? 0).toFixed(2)}</td>
                              <td className="p-2 text-right">{Number(co.latefee ?? 0).toFixed(2)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                )}

                {/* Dates */}
                <div className="text-xs text-slate-400 flex justify-between pt-2 border-t">
                  <span>First registered: {selectedGuest.createdAt ? new Date(selectedGuest.createdAt).toLocaleDateString() : "—"}</span>
                  {selectedGuest.lastStayDate && <span>Last stay: {new Date(selectedGuest.lastStayDate).toLocaleDateString()}</span>}
                </div>
              </>
            )}
          </DialogContent>
        </Dialog>
      </main></div></div>
  )
}

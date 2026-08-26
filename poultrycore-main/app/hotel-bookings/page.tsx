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
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Loader2, Plus, Calendar, Edit2, X, Printer, List } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelBookings, createHotelBooking, updateHotelBooking, cancelHotelBooking,
  listHotelGuests, listHotelRoomTypes, listHotelRooms, getHotelProfile,
  type HotelBooking, type HotelBookingInput, type HotelGuest, type HotelRoomType, type HotelRoom, type HotelProfile,
} from "@/lib/api/hotel"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { BookingCalendar } from "@/components/hotel/booking-calendar"

const STATUS_COLORS: Record<string, string> = {
  Confirmed: "bg-blue-100 text-blue-700", CheckedIn: "bg-emerald-100 text-emerald-700",
  CheckedOut: "bg-slate-100 text-slate-700", Cancelled: "bg-red-100 text-red-700", NoShow: "bg-amber-100 text-amber-700",
}

export default function HotelBookingsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [bookings, setBookings] = useState<HotelBooking[]>([])
  const [guests, setGuests] = useState<HotelGuest[]>([])
  const [roomTypes, setRoomTypes] = useState<HotelRoomType[]>([])
  const [rooms, setRooms] = useState<HotelRoom[]>([])
  const [loading, setLoading] = useState(true)
  const [filterStatus, setFilterStatus] = useState("all")
  const [searchQuery, setSearchQuery] = useState("")
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)

  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<HotelBooking | null>(null)
  const [saving, setSaving] = useState(false)
  const [receiptBooking, setReceiptBooking] = useState<HotelBooking | null>(null)
  const [hotelProfile, setHotelProfile] = useState<HotelProfile | null>(null)
  const [form, setForm] = useState<HotelBookingInput>({
    hotelGuestId: 0, hotelRoomTypeId: 0, hotelRoomId: null,
    checkInDate: "", checkOutDate: "", nightlyRate: 0, totalAmount: 0,
    numberOfGuests: 1, adults: 1, children: 0, source: "WalkIn", specialRequests: "",
  })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    loadData()
  }, [activeFarmType, router])

  async function loadData() {
    setLoading(true)
    try {
      const [b, g, rt, r, hp] = await Promise.all([listHotelBookings(), listHotelGuests(), listHotelRoomTypes(), listHotelRooms(), getHotelProfile().catch(() => null)])
      setBookings(b); setGuests(g); setRoomTypes(rt); setRooms(r); if (hp) setHotelProfile(hp)
    } catch (e: any) {
      toast({ title: "Failed to load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  function openCreate() {
    setEditing(null)
    const today = new Date().toISOString().slice(0, 10)
    const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10)
    setForm({ hotelGuestId: guests[0]?.hotelGuestId ?? 0, hotelRoomTypeId: roomTypes[0]?.hotelRoomTypeId ?? 0, hotelRoomId: null, checkInDate: today, checkOutDate: tomorrow, nightlyRate: roomTypes[0]?.baseRate ?? 0, totalAmount: roomTypes[0]?.baseRate ?? 0, numberOfGuests: 1, adults: 1, children: 0, source: "WalkIn" })
    setDialogOpen(true)
  }

  function openEdit(b: HotelBooking) {
    setEditing(b)
    setForm({ hotelGuestId: b.hotelGuestId, hotelRoomTypeId: b.hotelRoomTypeId, hotelRoomId: b.hotelRoomId, checkInDate: b.checkInDate.slice(0, 10), checkOutDate: b.checkOutDate.slice(0, 10), nightlyRate: b.nightlyRate, totalAmount: b.totalAmount, numberOfGuests: b.numberOfGuests, adults: b.adults, children: b.children, source: b.source, specialRequests: b.specialRequests })
    setDialogOpen(true)
  }

  // Auto-calculate total when dates or rate change
  function calcTotal(checkIn: string, checkOut: string, rate: number) {
    const d1 = new Date(checkIn); const d2 = new Date(checkOut)
    const nights = Math.max(1, Math.ceil((d2.getTime() - d1.getTime()) / 86400000))
    return nights * rate
  }

  async function handleSave() {
    setSaving(true)
    try {
      if (editing) { await updateHotelBooking(editing.hotelBookingId, form); toast({ title: "Booking updated" }) }
      else { await createHotelBooking(form); toast({ title: "Booking created" }) }
      setDialogOpen(false); await loadData()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  async function handleCancel(b: HotelBooking) {
    if (!confirm(`Cancel booking ${b.bookingRef}?`)) return
    try { await cancelHotelBooking(b.hotelBookingId); toast({ title: "Booking cancelled" }); await loadData() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }

  const filtered = bookings.filter((b) => {
    if (filterStatus !== "all" && b.status !== filterStatus) return false
    if (searchQuery) {
      const q = searchQuery.toLowerCase()
      const name = `${b.guestFirstName ?? ""} ${b.guestLastName ?? ""}`.toLowerCase()
      if (!name.includes(q) && !(b.bookingRef ?? "").toLowerCase().includes(q) && !(b.roomNumber ?? "").toLowerCase().includes(q)) return false
    }
    return true
  })
  const paginatedBookings = filtered.slice((page - 1) * pageSize, page * pageSize)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-3"><Calendar className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold text-slate-900">Bookings</h1></div>
            <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> New Booking</Button>
          </div>

          {/* Summary badges */}
          <div className="flex gap-2 flex-wrap mb-4">
            {[{s:"all",l:"All",c:bookings.length},{s:"Confirmed",l:"Confirmed",c:bookings.filter(b=>b.status==="Confirmed").length},{s:"CheckedIn",l:"Checked In",c:bookings.filter(b=>b.status==="CheckedIn").length},{s:"CheckedOut",l:"Checked Out",c:bookings.filter(b=>b.status==="CheckedOut").length},{s:"Cancelled",l:"Cancelled",c:bookings.filter(b=>b.status==="Cancelled").length},{s:"NoShow",l:"No Show",c:bookings.filter(b=>b.status==="NoShow").length}].map(f => (
              <Button key={f.s} variant={filterStatus === f.s ? "default" : "outline"} size="sm" onClick={() => setFilterStatus(f.s)} className={filterStatus === f.s ? "bg-violet-600" : ""}>
                {f.l} ({f.c})
              </Button>
            ))}
          </div>

          {/* Search and date filters */}
          <div className="flex gap-3 mb-4">
            <Input placeholder="Search guest name or ref..." className="max-w-xs" value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
            <Select value={filterStatus} onValueChange={setFilterStatus}>
              <SelectTrigger className="w-[160px]"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All statuses</SelectItem>
                <SelectItem value="Confirmed">Confirmed</SelectItem>
                <SelectItem value="CheckedIn">Checked In</SelectItem>
                <SelectItem value="CheckedOut">Checked Out</SelectItem>
                <SelectItem value="Cancelled">Cancelled</SelectItem>
                <SelectItem value="NoShow">No Show</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
            <Tabs defaultValue="table">
              <TabsList className="mb-4">
                <TabsTrigger value="table" className="gap-1"><List className="h-4 w-4" /> Table View</TabsTrigger>
                <TabsTrigger value="calendar" className="gap-1"><Calendar className="h-4 w-4" /> Calendar View</TabsTrigger>
              </TabsList>

              <TabsContent value="table">
                <Card>
                  <CardContent className="p-0">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Ref</th><th className="text-left p-3">Guest</th><th className="text-left p-3">Room</th><th className="text-left p-3">Booked On</th><th className="text-left p-3">Check-in</th><th className="text-left p-3">Check-out</th><th className="text-left p-3">Nights</th><th className="text-right p-3">Amount</th><th className="text-left p-3">Status</th><th className="text-right p-3">Actions</th></tr></thead>
                      <tbody>
                        {paginatedBookings.map((b) => {
                          const nights = Math.max(1, Math.ceil((new Date(b.checkOutDate).getTime() - new Date(b.checkInDate).getTime()) / 86400000))
                          return (
                          <tr key={b.hotelBookingId} className="border-b hover:bg-slate-50">
                            <td className="p-3 font-mono font-semibold text-xs">{b.bookingRef}</td>
                            <td className="p-3">{b.guestFirstName} {b.guestLastName}</td>
                            <td className="p-3">{b.roomNumber ?? b.roomTypeName}</td>
                            <td className="p-3 text-xs text-slate-500">{b.createdAt ? new Date(b.createdAt).toLocaleString() : "—"}</td>
                            <td className="p-3">{b.checkInDate?.slice(0, 10)}</td>
                            <td className="p-3">{b.checkOutDate?.slice(0, 10)}</td>
                            <td className="p-3 text-center">{nights}</td>
                            <td className="p-3 text-right font-semibold">{Number(b.totalAmount ?? 0).toFixed(2)}</td>
                            <td className="p-3"><Badge variant="outline" className={STATUS_COLORS[b.status] ?? ""}>{b.status}</Badge></td>
                            <td className="p-3 text-right space-x-1">
                              <Button variant="ghost" size="icon" title="Print Receipt" onClick={() => setReceiptBooking(b)}><Printer className="h-4 w-4" /></Button>
                              <Button variant="ghost" size="icon" onClick={() => openEdit(b)}><Edit2 className="h-4 w-4" /></Button>
                              {b.status === "Confirmed" && <Button variant="ghost" size="icon" className="text-red-600" onClick={() => handleCancel(b)}><X className="h-4 w-4" /></Button>}
                            </td>
                          </tr>
                        )})}
                        {filtered.length === 0 && <tr><td colSpan={10} className="p-8 text-center text-slate-400">No bookings found.</td></tr>}
                      </tbody>
                    </table>
                    <PaginationControls page={page} pageSize={pageSize} total={filtered.length} onPageChange={(p) => setPage(p)} onPageSizeChange={(ps) => { setPageSize(ps); setPage(1) }} />
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="calendar">
                <BookingCalendar bookings={bookings} rooms={rooms} onBookingClick={openEdit} />
              </TabsContent>
            </Tabs>
          )}

          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <DialogContent className="max-w-lg">
              <DialogHeader><DialogTitle>{editing ? `Edit Booking ${editing.bookingRef}` : "New Booking"}</DialogTitle></DialogHeader>
              <div className="space-y-4">
                <div><Label>Guest</Label>
                  <Select value={String(form.hotelGuestId)} onValueChange={(v) => setForm({ ...form, hotelGuestId: Number(v) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{guests.map((g) => <SelectItem key={g.hotelGuestId} value={String(g.hotelGuestId)}>{g.firstName} {g.lastName}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>Room Type</Label>
                    <Select value={String(form.hotelRoomTypeId)} onValueChange={(v) => { const rt = roomTypes.find((r) => r.hotelRoomTypeId === Number(v)); setForm({ ...form, hotelRoomTypeId: Number(v), nightlyRate: rt?.baseRate ?? form.nightlyRate, totalAmount: calcTotal(form.checkInDate, form.checkOutDate, rt?.baseRate ?? form.nightlyRate) }) }}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{roomTypes.map((rt) => <SelectItem key={rt.hotelRoomTypeId} value={String(rt.hotelRoomTypeId)}>{rt.name}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div><Label>Room (optional)</Label>
                    <Select value={String(form.hotelRoomId ?? "")} onValueChange={(v) => setForm({ ...form, hotelRoomId: v ? Number(v) : null })}>
                      <SelectTrigger><SelectValue placeholder="Assign later" /></SelectTrigger>
                      <SelectContent>{rooms.filter((r) => r.status === "Available" && r.hotelRoomTypeId === form.hotelRoomTypeId).map((r) => <SelectItem key={r.hotelRoomId} value={String(r.hotelRoomId)}>{r.roomNumber}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>Check-in</Label><Input type="date" value={form.checkInDate} onChange={(e) => setForm({ ...form, checkInDate: e.target.value, totalAmount: calcTotal(e.target.value, form.checkOutDate, form.nightlyRate) })} /></div>
                  <div><Label>Check-out</Label><Input type="date" value={form.checkOutDate} onChange={(e) => setForm({ ...form, checkOutDate: e.target.value, totalAmount: calcTotal(form.checkInDate, e.target.value, form.nightlyRate) })} /></div>
                </div>
                <div className="grid grid-cols-3 gap-4">
                  <div><Label>Nightly Rate</Label><Input type="number" step="0.01" value={form.nightlyRate} onChange={(e) => { const r = Number(e.target.value); setForm({ ...form, nightlyRate: r, totalAmount: calcTotal(form.checkInDate, form.checkOutDate, r) }) }} /></div>
                  <div><Label>Total</Label><Input type="number" step="0.01" value={form.totalAmount} readOnly className="bg-slate-50" /></div>
                  <div><Label>Source</Label>
                    <Select value={form.source ?? "WalkIn"} onValueChange={(v) => setForm({ ...form, source: v as any })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent><SelectItem value="WalkIn">Walk-in</SelectItem><SelectItem value="Phone">Phone</SelectItem><SelectItem value="Online">Online</SelectItem><SelectItem value="Agent">Agent</SelectItem></SelectContent>
                    </Select>
                  </div>
                </div>
                <div className="grid grid-cols-3 gap-4">
                  <div><Label>Adults</Label><Input type="number" min={1} value={form.adults ?? 1} onChange={(e) => setForm({ ...form, adults: Number(e.target.value), numberOfGuests: Number(e.target.value) + (form.children ?? 0) })} /></div>
                  <div><Label>Children</Label><Input type="number" min={0} value={form.children ?? 0} onChange={(e) => setForm({ ...form, children: Number(e.target.value), numberOfGuests: (form.adults ?? 1) + Number(e.target.value) })} /></div>
                  <div><Label>Total Guests</Label><Input type="number" value={form.numberOfGuests ?? 1} readOnly className="bg-slate-50" /></div>
                </div>
                <div><Label>Special Requests</Label><Input value={form.specialRequests ?? ""} onChange={(e) => setForm({ ...form, specialRequests: e.target.value })} placeholder="Any special requirements..." /></div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
                <Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{editing ? "Update" : "Create"}</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Booking Confirmation Receipt Dialog */}
          <Dialog open={!!receiptBooking} onOpenChange={() => setReceiptBooking(null)}>
            <DialogContent className="max-w-md">
              <DialogHeader><DialogTitle className="flex items-center gap-2"><Printer className="h-5 w-5 text-violet-600" />Booking Confirmation</DialogTitle></DialogHeader>
              {receiptBooking && (() => {
                const b = receiptBooking
                const guest = guests.find(g => g.hotelGuestId === b.hotelGuestId)
                const rt = roomTypes.find(r => r.hotelRoomTypeId === b.hotelRoomTypeId)
                const nights = Math.max(1, Math.ceil((new Date(b.checkOutDate).getTime() - new Date(b.checkInDate).getTime()) / 86400000))
                return (
                  <div id="booking-receipt">
                    <div className="space-y-4 text-sm">
                      {/* Hotel Header */}
                      <div className="text-center border-b pb-3">
                        <h2 className="text-lg font-bold text-violet-700">{hotelProfile?.hotelName ?? "Hotel"}</h2>
                        {hotelProfile?.address && <p className="text-xs text-slate-500">{hotelProfile.address}{hotelProfile.city ? `, ${hotelProfile.city}` : ""}{hotelProfile.country ? `, ${hotelProfile.country}` : ""}</p>}
                        {hotelProfile?.phone && <p className="text-xs text-slate-500">Tel: {hotelProfile.phone}{hotelProfile.email ? ` | ${hotelProfile.email}` : ""}</p>}
                        <p className="text-xs font-semibold mt-2 text-violet-600">BOOKING CONFIRMATION</p>
                      </div>

                      {/* Booking Reference */}
                      <div className="flex justify-between items-center bg-violet-50 p-2 rounded">
                        <span className="text-slate-600">Booking Ref:</span>
                        <span className="font-mono font-bold text-violet-700">{b.bookingRef}</span>
                      </div>

                      {/* Guest Details */}
                      <div>
                        <h4 className="font-semibold text-slate-700 mb-1">Guest Details</h4>
                        <div className="grid grid-cols-2 gap-1 text-xs">
                          <div><span className="text-slate-500">Name:</span> <strong>{guest?.firstName ?? b.guestFirstName} {guest?.lastName ?? b.guestLastName}</strong></div>
                          <div><span className="text-slate-500">Phone:</span> <strong>{guest?.phone ?? b.guestPhone ?? "—"}</strong></div>
                          <div><span className="text-slate-500">Email:</span> <strong>{guest?.email ?? b.guestEmail ?? "—"}</strong></div>
                          {guest?.idType && <div><span className="text-slate-500">ID:</span> <strong>{guest.idType}: {guest.idNumber}</strong></div>}
                        </div>
                      </div>

                      {/* Reservation Details */}
                      <div>
                        <h4 className="font-semibold text-slate-700 mb-1">Reservation Details</h4>
                        <div className="grid grid-cols-2 gap-1 text-xs">
                          <div><span className="text-slate-500">Room Type:</span> <strong>{rt?.name ?? b.roomTypeName}</strong></div>
                          <div><span className="text-slate-500">Room:</span> <strong>{b.roomNumber ?? "To be assigned"}</strong></div>
                          <div><span className="text-slate-500">Check-in:</span> <strong>{b.checkInDate?.slice(0, 10)}</strong></div>
                          <div><span className="text-slate-500">Check-out:</span> <strong>{b.checkOutDate?.slice(0, 10)}</strong></div>
                          <div><span className="text-slate-500">Nights:</span> <strong>{nights}</strong></div>
                          <div><span className="text-slate-500">Guests:</span> <strong>{b.adults ?? 1} Adult{(b.adults ?? 1) > 1 ? "s" : ""}{(b.children ?? 0) > 0 ? `, ${b.children} Child${b.children! > 1 ? "ren" : ""}` : ""}</strong></div>
                          <div><span className="text-slate-500">Source:</span> <strong>{b.source}</strong></div>
                          <div><span className="text-slate-500">Status:</span> <Badge variant="outline" className={`text-[10px] ${STATUS_COLORS[b.status] ?? ""}`}>{b.status}</Badge></div>
                        </div>
                      </div>

                      {/* Pricing */}
                      <div className="border-t pt-2">
                        <h4 className="font-semibold text-slate-700 mb-1">Pricing</h4>
                        <div className="space-y-1 text-xs">
                          <div className="flex justify-between"><span>Nightly Rate:</span><span>{Number(b.nightlyRate ?? 0).toFixed(2)}</span></div>
                          <div className="flex justify-between"><span>Number of Nights:</span><span>{nights}</span></div>
                          <div className="flex justify-between font-bold text-base border-t pt-1 mt-1">
                            <span>Total Amount:</span><span className="text-violet-700">{Number(b.totalAmount ?? 0).toFixed(2)}</span>
                          </div>
                        </div>
                      </div>

                      {/* Special Requests */}
                      {b.specialRequests && (
                        <div className="border-t pt-2">
                          <h4 className="font-semibold text-slate-700 mb-1">Special Requests</h4>
                          <p className="text-xs text-slate-600 italic">{b.specialRequests}</p>
                        </div>
                      )}

                      {/* Footer */}
                      <div className="text-center border-t pt-3 text-[10px] text-slate-400 space-y-1">
                        <p>Check-in time: {hotelProfile?.checkInTime ?? "14:00"} | Check-out time: {hotelProfile?.checkOutTime ?? "12:00"}</p>
                        <p>Booked on: {b.createdAt ? new Date(b.createdAt).toLocaleString() : "—"}</p>
                        <p>Thank you for choosing {hotelProfile?.hotelName ?? "our hotel"}!</p>
                      </div>
                    </div>
                  </div>
                )
              })()}
              <DialogFooter>
                <Button variant="outline" onClick={() => setReceiptBooking(null)}>Close</Button>
                <Button className="bg-violet-600 hover:bg-violet-700" onClick={() => {
                  const el = document.getElementById("booking-receipt")
                  if (!el) return
                  const win = window.open("", "_blank", "width=400,height=700")
                  if (!win) return
                  win.document.write(`<!DOCTYPE html><html><head><title>Booking Confirmation - ${receiptBooking?.bookingRef}</title><style>body{font-family:system-ui,sans-serif;padding:20px;font-size:12px;color:#333}h2{color:#7c3aed;margin:0}h4{margin:8px 0 4px;font-size:13px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:4px}.center{text-align:center}.border-b{border-bottom:1px solid #e5e7eb;padding-bottom:8px;margin-bottom:8px}.border-t{border-top:1px solid #e5e7eb;padding-top:8px;margin-top:8px}.bold{font-weight:700}.violet{color:#7c3aed}.ref{background:#f5f3ff;padding:8px;border-radius:6px;display:flex;justify-content:space-between;font-family:monospace}.price-row{display:flex;justify-content:space-between}.total{font-size:16px;font-weight:700;border-top:1px solid #e5e7eb;padding-top:4px;margin-top:4px}.small{font-size:10px;color:#94a3b8}@media print{body{padding:10px}}</style></head><body>`)
                  win.document.write(el.innerHTML.replace(/class="[^"]*"/g, "").replace(/<svg[^>]*>.*?<\/svg>/g, ""))
                  win.document.write("</body></html>")
                  win.document.close()
                  setTimeout(() => { win.print() }, 300)
                }}>
                  <Printer className="h-4 w-4 mr-1" /> Print
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

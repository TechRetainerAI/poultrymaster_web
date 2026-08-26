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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, LogIn, Key, Users, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelBookings, listHotelRooms, processCheckIn, listStayCharges, listHotelPayments,
  type HotelBooking, type HotelRoom, type HotelStayCharge, type HotelPayment,
} from "@/lib/api/hotel"

interface GuestBalance {
  booking: HotelBooking
  charges: number
  payments: number
  grandTotal: number
  balance: number
}

export default function HotelCheckInPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [confirmed, setConfirmed] = useState<HotelBooking[]>([])
  const [checkedIn, setCheckedIn] = useState<GuestBalance[]>([])
  const [rooms, setRooms] = useState<HotelRoom[]>([])
  const [allPayments, setAllPayments] = useState<HotelPayment[]>([])
  const [loading, setLoading] = useState(true); const [tab, setTab] = useState("awaiting")

  // Check-in dialog
  const [dialogOpen, setDialogOpen] = useState(false); const [selected, setSelected] = useState<HotelBooking | null>(null)
  const [selectedRoom, setSelectedRoom] = useState<number | null>(null)
  const [keyCard, setKeyCard] = useState(""); const [deposit, setDeposit] = useState(0); const [depositMethod, setDepositMethod] = useState("Cash")
  const [saving, setSaving] = useState(false)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [bookings, r, payments] = await Promise.all([listHotelBookings(), listHotelRooms(), listHotelPayments()])
      setRooms(r.filter((x) => x.status === "Available"))
      setConfirmed(bookings.filter((b) => b.status === "Confirmed"))
      setAllPayments(payments)

      // Build balance info for checked-in guests
      const inHouse = bookings.filter((b) => b.status === "CheckedIn")
      const balances: GuestBalance[] = []
      for (const b of inHouse) {
        let charges = 0
        try { const c = await listStayCharges(b.hotelBookingId); charges = c.reduce((s: number, x: any) => s + Number(x.totalAmount ?? x.totalamount ?? 0), 0) } catch {}
        const paid = payments.filter((p: any) => (p.hotelBookingId ?? p.hotelbookingid) === b.hotelBookingId).reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
        const grandTotal = Number(b.totalAmount ?? 0) + charges
        balances.push({ booking: b, charges, payments: paid, grandTotal, balance: grandTotal - paid })
      }
      setCheckedIn(balances)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openCheckIn(b: HotelBooking) { setSelected(b); setSelectedRoom(b.hotelRoomId ?? null); setKeyCard(""); setDeposit(0); setDepositMethod("Cash"); setDialogOpen(true) }

  async function handleCheckIn() {
    const roomId = selectedRoom ?? selected?.hotelRoomId
    if (!roomId) { toast({ title: "Please select a room", variant: "destructive" }); return }
    setSaving(true)
    try {
      await processCheckIn({ hotelBookingId: selected!.hotelBookingId, hotelRoomId: roomId, keyCardNumber: keyCard || undefined, depositAmount: deposit, depositMethod })
      toast({ title: `${selected!.guestFirstName} ${selected!.guestLastName} checked in` })
      setDialogOpen(false); await load()
    } catch (e: any) { toast({ title: "Check-in failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const totalOutstanding = checkedIn.reduce((s, g) => s + Math.max(0, g.balance), 0)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><LogIn className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Front Desk</h1></div>

        {/* Summary cards */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Awaiting Check-in</div><div className="text-2xl font-bold text-blue-700">{confirmed.length}</div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Currently Checked In</div><div className="text-2xl font-bold text-emerald-700">{checkedIn.length}</div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Total Outstanding</div><div className="text-2xl font-bold text-red-700">{totalOutstanding.toFixed(2)}</div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Available Rooms</div><div className="text-2xl font-bold text-violet-700">{rooms.length}</div></CardContent></Card>
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Tabs value={tab} onValueChange={setTab}>
            <TabsList className="mb-4">
              <TabsTrigger value="awaiting">Awaiting Check-in ({confirmed.length})</TabsTrigger>
              <TabsTrigger value="inhouse">In-House Guests ({checkedIn.length})</TabsTrigger>
            </TabsList>

            {/* TAB 1: Awaiting check-in */}
            <TabsContent value="awaiting">
              <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                {confirmed.map((b) => (
                  <Card key={b.hotelBookingId} className="hover:shadow-md transition-shadow">
                    <CardHeader className="pb-2"><CardTitle className="text-lg">{b.guestFirstName} {b.guestLastName}</CardTitle></CardHeader>
                    <CardContent className="space-y-2">
                      <div className="text-sm text-slate-500">Ref: <span className="font-mono">{b.bookingRef}</span></div>
                      <div className="text-sm">Room Type: {b.roomTypeName}</div>
                      <div className="text-sm">Guests: {b.adults} adults{b.children > 0 ? `, ${b.children} children` : ""}</div>
                      <div className="text-sm">Stay: {b.checkInDate?.slice(0,10)} to {b.checkOutDate?.slice(0,10)}</div>
                      <div className="text-sm font-semibold">Total: {Number(b.totalAmount ?? 0).toFixed(2)}</div>
                      <Button onClick={() => openCheckIn(b)} className="w-full mt-2 bg-violet-600 hover:bg-violet-700"><Key className="h-4 w-4 mr-1" /> Check In</Button>
                    </CardContent>
                  </Card>
                ))}
                {confirmed.length === 0 && <div className="col-span-full text-center py-12 text-slate-400">No confirmed bookings awaiting check-in.</div>}
              </div>
            </TabsContent>

            {/* TAB 2: In-House Guests with balance tracking */}
            <TabsContent value="inhouse">
              <Card><CardContent className="p-0">
                <table className="w-full text-sm">
                  <thead className="bg-slate-50 border-b"><tr>
                    <th className="text-left p-3">Guest</th>
                    <th className="text-left p-3">Room</th>
                    <th className="text-left p-3">Ref</th>
                    <th className="text-left p-3">Check-in</th>
                    <th className="text-left p-3">Check-out</th>
                    <th className="text-right p-3">Room Bill</th>
                    <th className="text-right p-3">Extras</th>
                    <th className="text-right p-3">Total</th>
                    <th className="text-right p-3">Paid</th>
                    <th className="text-right p-3">Balance</th>
                    <th className="text-left p-3">Status</th>
                  </tr></thead>
                  <tbody>
                    {checkedIn.map((g) => {
                      const b = g.booking
                      const isPaid = g.balance <= 0
                      return (
                        <tr key={b.hotelBookingId} className="border-b hover:bg-slate-50">
                          <td className="p-3 font-semibold">{b.guestFirstName} {b.guestLastName}</td>
                          <td className="p-3"><Badge variant="outline" className="bg-emerald-50 text-emerald-700">{b.roomNumber ?? "—"}</Badge></td>
                          <td className="p-3 font-mono text-xs">{b.bookingRef}</td>
                          <td className="p-3">{b.checkInDate?.slice(0,10)}</td>
                          <td className="p-3">{b.checkOutDate?.slice(0,10)}</td>
                          <td className="p-3 text-right">{Number(b.totalAmount ?? 0).toFixed(2)}</td>
                          <td className="p-3 text-right">{g.charges > 0 ? g.charges.toFixed(2) : "—"}</td>
                          <td className="p-3 text-right font-semibold">{g.grandTotal.toFixed(2)}</td>
                          <td className="p-3 text-right text-emerald-700">{g.payments > 0 ? g.payments.toFixed(2) : "—"}</td>
                          <td className={`p-3 text-right font-bold ${isPaid ? "text-emerald-700" : "text-red-700"}`}>{isPaid ? "0.00" : g.balance.toFixed(2)}</td>
                          <td className="p-3">
                            {isPaid
                              ? <Badge className="bg-emerald-100 text-emerald-700">Paid</Badge>
                              : <Badge className="bg-red-100 text-red-700">Owes {g.balance.toFixed(2)}</Badge>
                            }
                          </td>
                        </tr>
                      )
                    })}
                    {checkedIn.length === 0 && <tr><td colSpan={11} className="p-8 text-center text-slate-400">No guests currently checked in.</td></tr>}
                  </tbody>
                </table>
              </CardContent></Card>
            </TabsContent>
          </Tabs>
        )}

        {/* Check-in dialog */}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent>
            <DialogHeader><DialogTitle>Check In: {selected?.guestFirstName} {selected?.guestLastName}</DialogTitle></DialogHeader>
            <div className="space-y-4">
              <div className="text-sm text-slate-500">{selected?.roomTypeName} | {selected?.checkInDate?.slice(0,10)} to {selected?.checkOutDate?.slice(0,10)} | Total: {Number(selected?.totalAmount ?? 0).toFixed(2)}</div>
              <div><Label>Assign Room *</Label>
                <Select value={String(selectedRoom ?? "")} onValueChange={(v) => setSelectedRoom(Number(v))}>
                  <SelectTrigger><SelectValue placeholder="Select available room" /></SelectTrigger>
                  <SelectContent>{rooms.map((r) => <SelectItem key={r.hotelRoomId} value={String(r.hotelRoomId)}>Room {r.roomNumber} — {r.roomTypeName}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div><Label>Key Card Number</Label><Input value={keyCard} onChange={(e) => setKeyCard(e.target.value)} placeholder="Optional" /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><Label>Deposit Amount</Label><Input type="number" step="0.01" value={deposit} onChange={(e) => setDeposit(Number(e.target.value))} /></div>
                <div><Label>Deposit Method</Label>
                  <Select value={depositMethod} onValueChange={setDepositMethod}><SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent><SelectItem value="Cash">Cash</SelectItem><SelectItem value="Card">Card</SelectItem><SelectItem value="MobileMoney">Mobile Money</SelectItem><SelectItem value="BankTransfer">Bank Transfer</SelectItem></SelectContent>
                  </Select></div>
              </div>
              {deposit > 0 && <div className="p-2 bg-violet-50 rounded text-sm text-violet-700">A payment of <strong>{deposit.toFixed(2)}</strong> via {depositMethod} will be recorded automatically.</div>}
            </div>
            <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
              <Button onClick={handleCheckIn} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Confirm Check-in</Button></DialogFooter>
          </DialogContent>
        </Dialog>
      </main>
    </div></div>
  )
}

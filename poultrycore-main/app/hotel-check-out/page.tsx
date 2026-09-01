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
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, LogOut, Receipt, AlertTriangle, CheckCircle, Wallet, Search } from "lucide-react"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelBookings, listStayCharges, listHotelPayments, processCheckOut, recordPayment,
  type HotelBooking, type HotelStayCharge, type HotelPayment,
} from "@/lib/api/hotel"

interface GuestBill {
  booking: HotelBooking
  charges: HotelStayCharge[]
  payments: HotelPayment[]
  roomBill: number
  extraCharges: number
  grandTotal: number
  totalPaid: number
  balance: number
}

export default function HotelCheckOutPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [guests, setGuests] = useState<GuestBill[]>([]); const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [balanceFilter, setBalanceFilter] = useState("all")
  const [page, setPage] = useState(1); const [pageSize, setPageSize] = useState(10)

  // Checkout dialog
  const [dialogOpen, setDialogOpen] = useState(false); const [selected, setSelected] = useState<GuestBill | null>(null)
  const [lateFee, setLateFee] = useState(0); const [damageCharges, setDamageCharges] = useState(0)
  const [keyReturned, setKeyReturned] = useState(true); const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)

  // Payment dialog (for settling balance before checkout)
  const [payDialogOpen, setPayDialogOpen] = useState(false); const [payGuest, setPayGuest] = useState<GuestBill | null>(null)
  const [payAmount, setPayAmount] = useState(0); const [payMethod, setPayMethod] = useState("Cash")
  const [payingSaving, setPayingSaving] = useState(false)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [bookings, allPayments] = await Promise.all([listHotelBookings(), listHotelPayments()])
      const inHouse = bookings.filter((b) => b.status === "CheckedIn")

      const bills: GuestBill[] = []
      for (const b of inHouse) {
        let charges: any[] = []
        try { charges = await listStayCharges(b.hotelBookingId) } catch {}
        const guestPayments = allPayments.filter((p: any) => (p.hotelBookingId ?? p.hotelbookingid) === b.hotelBookingId)

        const roomBill = Number(b.totalAmount ?? 0)
        const extraCharges = charges.reduce((s: number, c: any) => s + Number(c.totalAmount ?? c.totalamount ?? 0), 0)
        const grandTotal = roomBill + extraCharges
        const totalPaid = guestPayments.reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)

        bills.push({ booking: b, charges, payments: guestPayments, roomBill, extraCharges, grandTotal, totalPaid, balance: grandTotal - totalPaid })
      }
      setGuests(bills)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openCheckOut(g: GuestBill) {
    setSelected(g); setLateFee(0); setDamageCharges(0); setKeyReturned(true); setNotes(""); setDialogOpen(true)
  }

  function openPayment(g: GuestBill) {
    setPayGuest(g); setPayAmount(Math.max(0, g.balance)); setPayMethod("Cash"); setPayDialogOpen(true)
  }

  async function handlePayment() {
    if (!payGuest || payAmount <= 0) return
    setPayingSaving(true)
    try {
      await recordPayment({ hotelBookingId: payGuest.booking.hotelBookingId, amount: payAmount, paymentMethod: payMethod })
      toast({ title: `Payment of ${payAmount.toFixed(2)} recorded` })
      setPayDialogOpen(false); await load()
    } catch (e: any) { toast({ title: "Payment failed", description: e?.message, variant: "destructive" }) }
    finally { setPayingSaving(false) }
  }

  async function handleCheckOut() {
    if (!selected) return
    const finalBalance = selected.balance + lateFee + damageCharges
    if (finalBalance > 0) {
      toast({ title: "Guest has an outstanding balance", description: `Balance of ${finalBalance.toFixed(2)} must be settled before checkout. Record a payment first.`, variant: "destructive" })
      return
    }
    if (!selected.booking.hotelRoomId) { toast({ title: "No room assigned", variant: "destructive" }); return }
    setSaving(true)
    try {
      await processCheckOut({ hotelBookingId: selected.booking.hotelBookingId, hotelRoomId: selected.booking.hotelRoomId, lateFee, damageCharges, keyReturned, notes: notes || undefined })
      toast({ title: `${selected.booking.guestFirstName} ${selected.booking.guestLastName} checked out successfully` })
      setDialogOpen(false); await load()
    } catch (e: any) { toast({ title: "Check-out failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const totalGuests = guests.length
  const totalOwed = guests.reduce((s, g) => s + Math.max(0, g.balance), 0)
  const fullyPaid = guests.filter((g) => g.balance <= 0).length

  // Filter guests
  const filtered = guests.filter((g) => {
    const b = g.booking
    if (balanceFilter === "paid" && g.balance > 0) return false
    if (balanceFilter === "owes" && g.balance <= 0) return false
    if (search) {
      const q = search.toLowerCase()
      const name = `${b.guestFirstName ?? ""} ${b.guestLastName ?? ""}`.toLowerCase()
      if (!name.includes(q) && !(b.bookingRef ?? "").toLowerCase().includes(q) && !(b.roomNumber ?? "").toLowerCase().includes(q)) return false
    }
    return true
  })
  const paginatedGuests = filtered.slice((page - 1) * pageSize, page * pageSize)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><LogOut className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Check-out</h1></div>

        {/* Summary */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Checked-in Guests</div><div className="text-2xl font-bold text-violet-700">{totalGuests}</div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Ready to Check-out</div><div className="text-2xl font-bold text-emerald-700">{fullyPaid}</div><div className="text-xs text-slate-400">Balance settled</div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">With Outstanding Balance</div><div className="text-2xl font-bold text-red-700">{totalGuests - fullyPaid}</div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Total Outstanding</div><div className="text-2xl font-bold text-red-700">{totalOwed.toFixed(2)}</div></CardContent></Card>
        </div>

        {/* Search & Filter */}
        <div className="flex gap-3 flex-wrap mb-4">
          <div className="relative max-w-sm flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
            <Input placeholder="Search guest name, ref, room..." className="pl-9" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} />
          </div>
          <div className="flex gap-2">
            {[{ v: "all", l: "All", c: totalGuests }, { v: "paid", l: "Paid", c: fullyPaid }, { v: "owes", l: "Owes", c: totalGuests - fullyPaid }].map(f => (
              <Button key={f.v} variant={balanceFilter === f.v ? "default" : "outline"} size="sm" onClick={() => { setBalanceFilter(f.v); setPage(1) }} className={balanceFilter === f.v ? "bg-violet-600" : ""}>
                {f.l} ({f.c})
              </Button>
            ))}
          </div>
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <div className="space-y-4">
            {paginatedGuests.map((g) => {
              const b = g.booking
              const isPaid = g.balance <= 0
              return (
                <Card key={b.hotelBookingId} className={`border-l-4 ${isPaid ? "border-l-emerald-500" : "border-l-red-500"}`}>
                  <CardContent className="p-4">
                    <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                      {/* Guest info */}
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="text-lg font-bold">{b.guestFirstName} {b.guestLastName}</span>
                          <Badge variant="outline" className="bg-emerald-50 text-emerald-700">Room {b.roomNumber}</Badge>
                          <span className="text-xs text-slate-400 font-mono">{b.bookingRef}</span>
                        </div>
                        <div className="text-sm text-slate-500">
                          Check-in: {b.checkInDate?.slice(0,10)} | Check-out due: {b.checkOutDate?.slice(0,10)} | {b.roomTypeName}
                        </div>
                      </div>

                      {/* Bill summary */}
                      <div className="flex items-center gap-6 text-sm">
                        <div className="text-center"><div className="text-slate-400">Room</div><div className="font-semibold">{g.roomBill.toFixed(2)}</div></div>
                        {g.extraCharges > 0 && <div className="text-center"><div className="text-slate-400">Extras</div><div className="font-semibold">{g.extraCharges.toFixed(2)}</div></div>}
                        <div className="text-center"><div className="text-slate-400">Total</div><div className="font-bold text-lg">{g.grandTotal.toFixed(2)}</div></div>
                        <div className="text-center"><div className="text-slate-400">Paid</div><div className="font-semibold text-emerald-700">{g.totalPaid.toFixed(2)}</div></div>
                        <div className="text-center">
                          <div className="text-slate-400">Balance</div>
                          <div className={`font-bold text-lg ${isPaid ? "text-emerald-700" : "text-red-700"}`}>{isPaid ? "0.00" : g.balance.toFixed(2)}</div>
                        </div>
                      </div>

                      {/* Actions */}
                      <div className="flex gap-2">
                        {!isPaid && (
                          <Button variant="outline" size="sm" className="text-red-700 border-red-300" onClick={() => openPayment(g)}>
                            <Wallet className="h-4 w-4 mr-1" /> Pay {g.balance.toFixed(2)}
                          </Button>
                        )}
                        <Button size="sm" onClick={() => openCheckOut(g)} className={isPaid ? "bg-violet-600 hover:bg-violet-700" : "bg-slate-400"}>
                          <Receipt className="h-4 w-4 mr-1" /> Check Out
                        </Button>
                      </div>
                    </div>

                    {/* Payment history (collapsed) */}
                    {g.payments.length > 0 && (
                      <div className="mt-3 pt-3 border-t">
                        <div className="text-xs font-semibold text-slate-400 mb-1">Payment History</div>
                        <div className="flex gap-3 flex-wrap">
                          {g.payments.map((p: any, idx: number) => (
                            <div key={p.hotelPaymentId ?? p.hotelpaymentid ?? `pay-${idx}`} className="text-xs bg-emerald-50 rounded px-2 py-1">
                              <span className="font-semibold">{Number(p.amount ?? 0).toFixed(2)}</span> via {p.paymentMethod ?? p.paymentmethod} — <span className="font-mono">{p.reference ?? p.reference ?? "N/A"}</span>
                              <span className="text-slate-400 ml-1">{(p.paymentDate ?? p.paymentdate)?.slice?.(0,10)}</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              )
            })}
            {filtered.length === 0 && <div className="text-center py-12 text-slate-400">{search || balanceFilter !== "all" ? "No matching guests found." : "No guests currently checked in."}</div>}
            {filtered.length > 0 && (
              <PaginationControls page={page} pageSize={pageSize} total={filtered.length} onPageChange={setPage} onPageSizeChange={(ps) => { setPageSize(ps); setPage(1) }} />
            )}
          </div>
        )}

        {/* Check-out dialog */}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent className="max-w-lg">
            <DialogHeader><DialogTitle>Check Out: {selected?.booking.guestFirstName} {selected?.booking.guestLastName}</DialogTitle></DialogHeader>
            <div className="space-y-4">
              {/* Bill summary */}
              <div className="p-4 bg-slate-50 rounded-lg space-y-2">
                <div className="flex justify-between text-sm"><span>Room ({selected?.booking.roomTypeName})</span><span>{selected?.roomBill.toFixed(2)}</span></div>
                {(selected?.extraCharges ?? 0) > 0 && <div className="flex justify-between text-sm"><span>Additional Charges</span><span>{selected?.extraCharges.toFixed(2)}</span></div>}
                <div className="flex justify-between font-semibold border-t pt-1"><span>Subtotal</span><span>{selected?.grandTotal.toFixed(2)}</span></div>
                <div className="flex justify-between text-sm text-emerald-700"><span>Paid</span><span>-{selected?.totalPaid.toFixed(2)}</span></div>
              </div>

              {/* Late fee / damage */}
              <div className="grid grid-cols-2 gap-4">
                <div><Label>Late Fee</Label><Input type="number" step="0.01" value={lateFee} onChange={(e) => setLateFee(Number(e.target.value))} /></div>
                <div><Label>Damage Charges</Label><Input type="number" step="0.01" value={damageCharges} onChange={(e) => setDamageCharges(Number(e.target.value))} /></div>
              </div>

              {/* Final balance */}
              {(() => {
                const finalBalance = (selected?.balance ?? 0) + lateFee + damageCharges
                const isPaid = finalBalance <= 0
                return (
                  <div className={`p-3 rounded-lg flex items-center gap-2 ${isPaid ? "bg-emerald-50" : "bg-red-50"}`}>
                    {isPaid ? <CheckCircle className="h-5 w-5 text-emerald-600" /> : <AlertTriangle className="h-5 w-5 text-red-600" />}
                    <div>
                      <div className={`font-bold ${isPaid ? "text-emerald-700" : "text-red-700"}`}>
                        Final Balance: {finalBalance.toFixed(2)}
                      </div>
                      {!isPaid && <div className="text-xs text-red-600">Guest must settle this balance before checkout. Use the "Pay" button on the guest card.</div>}
                      {isPaid && <div className="text-xs text-emerald-600">Balance settled. Ready for checkout.</div>}
                    </div>
                  </div>
                )
              })()}

              <label className="flex items-center gap-2"><input type="checkbox" checked={keyReturned} onChange={(e) => setKeyReturned(e.target.checked)} className="rounded" /><span className="text-sm">Key card returned</span></label>
              <div><Label>Notes</Label><Input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional checkout notes" /></div>
            </div>
            <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
              <Button onClick={handleCheckOut} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Confirm Check-out</Button></DialogFooter>
          </DialogContent>
        </Dialog>

        {/* Payment dialog */}
        <Dialog open={payDialogOpen} onOpenChange={setPayDialogOpen}>
          <DialogContent>
            <DialogHeader><DialogTitle>Record Payment: {payGuest?.booking.guestFirstName} {payGuest?.booking.guestLastName}</DialogTitle></DialogHeader>
            <div className="space-y-4">
              <div className="p-3 bg-red-50 rounded-lg">
                <div className="text-sm">Outstanding Balance: <span className="font-bold text-red-700">{payGuest?.balance.toFixed(2)}</span></div>
                <div className="text-xs text-slate-500">Room {payGuest?.booking.roomNumber} | {payGuest?.booking.bookingRef}</div>
              </div>
              <div><Label>Payment Amount *</Label><Input type="number" step="0.01" value={payAmount} onChange={(e) => setPayAmount(Number(e.target.value))} /></div>
              <div><Label>Payment Method</Label>
                <select className="w-full border rounded-md p-2 text-sm" value={payMethod} onChange={(e) => setPayMethod(e.target.value)}>
                  <option value="Cash">Cash</option>
                  <option value="Card">Card</option>
                  <option value="MobileMoney">Mobile Money</option>
                  <option value="BankTransfer">Bank Transfer</option>
                </select>
              </div>
              <div className="text-xs text-slate-500">A payment reference code will be generated automatically.</div>
            </div>
            <DialogFooter><Button variant="outline" onClick={() => setPayDialogOpen(false)}>Cancel</Button>
              <Button onClick={handlePayment} disabled={payingSaving} className="bg-emerald-600 hover:bg-emerald-700">{payingSaving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Record Payment</Button></DialogFooter>
          </DialogContent>
        </Dialog>
      </main>
    </div></div>
  )
}

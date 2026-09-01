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
import { Loader2, Receipt, Plus, FileText, CreditCard, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelBookings, listStayCharges, listHotelPayments,
  addStayCharge, generateInvoice, recordPayment,
  type HotelBooking, type HotelStayCharge, type HotelPayment,
} from "@/lib/api/hotel"

const CHARGE_TYPES = ["Room", "RoomService", "Minibar", "Laundry", "Damage", "Restaurant", "Spa", "Transport", "Telephone", "Other"]

interface BookingBill {
  booking: HotelBooking
  charges: any[]
  payments: any[]
  roomBill: number
  extraCharges: number
  grandTotal: number
  totalPaid: number
  balance: number
}

export default function HotelBillingPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [bills, setBills] = useState<BookingBill[]>([]); const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<BookingBill | null>(null)

  // Add charge dialog
  const [chargeOpen, setChargeOpen] = useState(false); const [chargeSaving, setChargeSaving] = useState(false)
  const [chargeForm, setChargeForm] = useState({ chargeType: "Room", description: "", quantity: 1, unitPrice: 0 })

  // Record payment dialog
  const [payOpen, setPayOpen] = useState(false); const [paySaving, setPaySaving] = useState(false)
  const [payForm, setPayForm] = useState({ amount: 0, paymentMethod: "Cash", reference: "", notes: "" })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [bookings, allPayments] = await Promise.all([listHotelBookings(), listHotelPayments()])
      const active = bookings.filter((b) => b.status === "CheckedIn" || b.status === "Confirmed")

      const results: BookingBill[] = []
      for (const b of active) {
        let charges: any[] = []
        try { charges = await listStayCharges(b.hotelBookingId) } catch {}
        const bPayments = allPayments.filter((p: any) => (p.hotelBookingId ?? p.hotelbookingid) === b.hotelBookingId)
        const roomBill = Number(b.totalAmount ?? 0)
        const extraCharges = charges.reduce((s: number, c: any) => s + Number(c.totalAmount ?? c.totalamount ?? 0), 0)
        const grandTotal = roomBill + extraCharges
        const totalPaid = bPayments.reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
        results.push({ booking: b, charges, payments: bPayments, roomBill, extraCharges, grandTotal, totalPaid, balance: grandTotal - totalPaid })
      }
      setBills(results)

      // Keep selected in sync
      if (selected) {
        const updated = results.find((r) => r.booking.hotelBookingId === selected.booking.hotelBookingId)
        setSelected(updated ?? null)
      }
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function handleAddCharge() {
    if (!selected) return
    if (!chargeForm.description.trim()) { toast({ title: "Description required", variant: "destructive" }); return }
    setChargeSaving(true)
    try {
      await addStayCharge({ hotelBookingId: selected.booking.hotelBookingId, chargeType: chargeForm.chargeType, description: chargeForm.description, quantity: chargeForm.quantity, unitPrice: chargeForm.unitPrice })
      toast({ title: "Charge added" }); setChargeOpen(false); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setChargeSaving(false) }
  }

  async function handleRecordPayment() {
    if (!selected || payForm.amount <= 0) return
    setPaySaving(true)
    try {
      await recordPayment({ hotelBookingId: selected.booking.hotelBookingId, amount: payForm.amount, paymentMethod: payForm.paymentMethod, reference: payForm.reference || undefined, notes: payForm.notes || undefined })
      toast({ title: `Payment of ${payForm.amount.toFixed(2)} recorded` }); setPayOpen(false); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setPaySaving(false) }
  }

  async function handleGenerateInvoice() {
    if (!selected) return
    try { await generateInvoice(selected.booking.hotelBookingId); toast({ title: "Invoice generated" }) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const totalRevenue = bills.reduce((s, b) => s + b.totalPaid, 0)
  const totalOutstanding = bills.reduce((s, b) => s + Math.max(0, b.balance), 0)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><Receipt className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Billing</h1></div>

        {/* Summary */}
        <div className="grid grid-cols-3 gap-4 mb-6">
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Active Stays</div><div className="text-2xl font-bold text-violet-700">{bills.length}</div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Total Collected</div><div className="text-2xl font-bold text-emerald-700">{totalRevenue.toFixed(2)}</div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="text-sm text-slate-500">Outstanding</div><div className={`text-2xl font-bold ${totalOutstanding > 0 ? "text-red-700" : "text-emerald-700"}`}>{totalOutstanding.toFixed(2)}</div></CardContent></Card>
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <div className="grid md:grid-cols-3 gap-6">
            {/* Left: Guest list */}
            <div className="md:col-span-1 space-y-2">
              <h3 className="font-semibold text-sm text-slate-500 uppercase mb-2">Select a Guest</h3>
              {bills.map((bill) => {
                const b = bill.booking
                const isSelected = selected?.booking.hotelBookingId === b.hotelBookingId
                const isPaid = bill.balance <= 0
                return (
                  <button key={b.hotelBookingId} onClick={() => setSelected(bill)} className={`w-full text-left p-3 rounded-lg border transition-colors ${isSelected ? "border-violet-400 bg-violet-50 shadow-sm" : "border-slate-200 hover:bg-slate-50"}`}>
                    <div className="flex items-center justify-between">
                      <span className="font-semibold text-sm">{b.guestFirstName} {b.guestLastName}</span>
                      {isPaid ? <Badge className="bg-emerald-100 text-emerald-700 text-[10px]">Paid</Badge> : <Badge className="bg-red-100 text-red-700 text-[10px]">Owes {bill.balance.toFixed(2)}</Badge>}
                    </div>
                    <div className="text-xs text-slate-500 mt-1">Room {b.roomNumber ?? "TBD"} | {b.bookingRef} | {b.status}</div>
                    <div className="text-xs text-slate-400 mt-0.5">Total: {bill.grandTotal.toFixed(2)} | Paid: {bill.totalPaid.toFixed(2)}</div>
                  </button>
                )
              })}
              {bills.length === 0 && <div className="text-center py-8 text-slate-400 text-sm">No active stays</div>}
            </div>

            {/* Right: Bill detail */}
            <div className="md:col-span-2">
              {!selected ? (
                <Card><CardContent className="p-12 text-center text-slate-400">Select a guest to view their bill</CardContent></Card>
              ) : (
                <Card>
                  <CardHeader className="pb-2">
                    <div className="flex items-center justify-between">
                      <div>
                        <CardTitle className="text-lg">{selected.booking.guestFirstName} {selected.booking.guestLastName}</CardTitle>
                        <div className="text-sm text-slate-500">Room {selected.booking.roomNumber ?? "TBD"} | {selected.booking.bookingRef} | {selected.booking.checkInDate?.slice(0,10)} to {selected.booking.checkOutDate?.slice(0,10)}</div>
                      </div>
                      <Badge variant="outline" className={selected.booking.status === "CheckedIn" ? "bg-emerald-50 text-emerald-700" : "bg-blue-50 text-blue-700"}>{selected.booking.status}</Badge>
                    </div>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    {/* Action buttons */}
                    <div className="flex gap-2 flex-wrap">
                      <Button size="sm" onClick={() => { setChargeForm({ chargeType: "Room", description: "", quantity: 1, unitPrice: 0 }); setChargeOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" />Add Charge</Button>
                      <Button size="sm" variant="outline" onClick={() => { setPayForm({ amount: Math.max(0, selected.balance), paymentMethod: "Cash", reference: "", notes: "" }); setPayOpen(true) }} className="text-emerald-700 border-emerald-300"><CreditCard className="h-4 w-4 mr-1" />Record Payment</Button>
                      <Button size="sm" variant="outline" onClick={handleGenerateInvoice}><FileText className="h-4 w-4 mr-1" />Generate Invoice</Button>
                    </div>

                    {/* Room charge */}
                    <div className="p-3 bg-slate-50 rounded-lg flex justify-between items-center">
                      <div><span className="font-medium">Room Charge</span><span className="text-sm text-slate-500 ml-2">({selected.booking.roomTypeName})</span></div>
                      <span className="font-semibold">{selected.roomBill.toFixed(2)}</span>
                    </div>

                    {/* Extra charges */}
                    {selected.charges.length > 0 && (
                      <div>
                        <h4 className="text-sm font-semibold text-slate-500 mb-2">Additional Charges</h4>
                        <table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-2">Type</th><th className="text-left p-2">Description</th><th className="text-right p-2">Qty</th><th className="text-right p-2">Price</th><th className="text-right p-2">Total</th></tr></thead>
                          <tbody>{selected.charges.map((c: any, idx: number) => (
                            <tr key={c.hotelStayChargeId ?? c.hotelstaychargeid ?? `ch-${idx}`} className="border-b">
                              <td className="p-2"><Badge variant="outline" className="text-xs">{c.chargeType ?? c.chargetype}</Badge></td>
                              <td className="p-2">{c.description}</td>
                              <td className="p-2 text-right">{c.quantity}</td>
                              <td className="p-2 text-right">{Number(c.unitPrice ?? c.unitprice ?? 0).toFixed(2)}</td>
                              <td className="p-2 text-right font-semibold">{Number(c.totalAmount ?? c.totalamount ?? 0).toFixed(2)}</td>
                            </tr>
                          ))}</tbody>
                        </table>
                      </div>
                    )}

                    {/* Payments */}
                    {selected.payments.length > 0 && (
                      <div>
                        <h4 className="text-sm font-semibold text-slate-500 mb-2">Payments Received</h4>
                        <div className="space-y-1">
                          {selected.payments.map((p: any, idx: number) => (
                            <div key={p.hotelPaymentId ?? p.hotelpaymentid ?? `py-${idx}`} className="flex items-center justify-between p-2 bg-emerald-50 rounded">
                              <div className="flex items-center gap-2">
                                <Badge className="bg-emerald-100 text-emerald-700 text-xs">{p.paymentMethod ?? p.paymentmethod}</Badge>
                                <span className="text-xs font-mono text-slate-400">{p.reference ?? "—"}</span>
                                <span className="text-xs text-slate-400">{(p.paymentDate ?? p.paymentdate)?.slice?.(0, 10)}</span>
                              </div>
                              <span className="font-semibold text-emerald-700">{Number(p.amount ?? 0).toFixed(2)}</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Bill summary */}
                    <div className="border-t pt-3 space-y-1">
                      <div className="flex justify-between text-sm"><span>Room Total</span><span>{selected.roomBill.toFixed(2)}</span></div>
                      {selected.extraCharges > 0 && <div className="flex justify-between text-sm"><span>Additional Charges</span><span>{selected.extraCharges.toFixed(2)}</span></div>}
                      <div className="flex justify-between text-sm font-semibold border-t pt-1"><span>Grand Total</span><span>{selected.grandTotal.toFixed(2)}</span></div>
                      {selected.totalPaid > 0 && <div className="flex justify-between text-sm text-emerald-700"><span>Total Paid</span><span>-{selected.totalPaid.toFixed(2)}</span></div>}
                      <div className={`flex justify-between text-lg font-bold pt-1 border-t ${selected.balance <= 0 ? "text-emerald-700" : "text-red-700"}`}>
                        <span>Balance Due</span>
                        <span>{selected.balance <= 0 ? "0.00 (Paid)" : selected.balance.toFixed(2)}</span>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              )}
            </div>
          </div>
        )}

        {/* Add Charge Dialog */}
        <Dialog open={chargeOpen} onOpenChange={setChargeOpen}><DialogContent><DialogHeader><DialogTitle>Add Charge — {selected?.booking.guestFirstName} {selected?.booking.guestLastName}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Charge Type</Label><Select value={chargeForm.chargeType} onValueChange={(v) => setChargeForm({...chargeForm, chargeType: v})}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{CHARGE_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent></Select></div>
            <div><Label>Description *</Label><Input value={chargeForm.description} onChange={(e) => setChargeForm({...chargeForm, description: e.target.value})} placeholder="e.g. Minibar drinks, Room service dinner" /></div>
            <div className="grid grid-cols-2 gap-4">
              <div><Label>Quantity</Label><Input type="number" min={1} value={chargeForm.quantity} onChange={(e) => setChargeForm({...chargeForm, quantity: Number(e.target.value)})} /></div>
              <div><Label>Unit Price</Label><Input type="number" step="0.01" value={chargeForm.unitPrice} onChange={(e) => setChargeForm({...chargeForm, unitPrice: Number(e.target.value)})} /></div>
            </div>
            <div className="p-2 bg-violet-50 rounded text-sm font-semibold text-violet-700">Charge Total: {(chargeForm.quantity * chargeForm.unitPrice).toFixed(2)}</div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setChargeOpen(false)}>Cancel</Button><Button onClick={handleAddCharge} disabled={chargeSaving} className="bg-violet-600 hover:bg-violet-700">{chargeSaving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Add Charge</Button></DialogFooter>
        </DialogContent></Dialog>

        {/* Record Payment Dialog */}
        <Dialog open={payOpen} onOpenChange={setPayOpen}><DialogContent><DialogHeader><DialogTitle>Record Payment — {selected?.booking.guestFirstName} {selected?.booking.guestLastName}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="p-3 bg-slate-50 rounded-lg">
              <div className="flex justify-between text-sm"><span>Grand Total</span><span className="font-semibold">{selected?.grandTotal.toFixed(2)}</span></div>
              <div className="flex justify-between text-sm text-emerald-700"><span>Already Paid</span><span>{selected?.totalPaid.toFixed(2)}</span></div>
              <div className={`flex justify-between font-bold border-t mt-1 pt-1 ${(selected?.balance ?? 0) <= 0 ? "text-emerald-700" : "text-red-700"}`}><span>Balance</span><span>{(selected?.balance ?? 0).toFixed(2)}</span></div>
            </div>
            <div><Label>Payment Amount *</Label><Input type="number" step="0.01" value={payForm.amount} onChange={(e) => setPayForm({...payForm, amount: Number(e.target.value)})} /></div>
            <div><Label>Payment Method</Label>
              <Select value={payForm.paymentMethod} onValueChange={(v) => setPayForm({...payForm, paymentMethod: v})}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="Cash">Cash</SelectItem><SelectItem value="Card">Card</SelectItem><SelectItem value="MobileMoney">Mobile Money</SelectItem><SelectItem value="BankTransfer">Bank Transfer</SelectItem></SelectContent>
              </Select>
            </div>
            <div><Label>Reference (optional)</Label><Input value={payForm.reference} onChange={(e) => setPayForm({...payForm, reference: e.target.value})} placeholder="Auto-generated if empty" /></div>
            <div><Label>Notes</Label><Input value={payForm.notes} onChange={(e) => setPayForm({...payForm, notes: e.target.value})} /></div>
            <div className="text-xs text-slate-500">A payment reference code will be generated automatically if not provided.</div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setPayOpen(false)}>Cancel</Button><Button onClick={handleRecordPayment} disabled={paySaving} className="bg-emerald-600 hover:bg-emerald-700">{paySaving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Record Payment</Button></DialogFooter>
        </DialogContent></Dialog>
      </main>
    </div></div>
  )
}

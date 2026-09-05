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
import { Loader2, CreditCard, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelPaymentsPaged, recordPayment, listHotelBookings, type HotelPayment, type HotelBooking } from "@/lib/api/hotel"
import { PaginationControls } from "@/components/ui/pagination-controls"

const METHOD_COLOR: Record<string, string> = { Cash: "bg-emerald-100 text-emerald-700", Card: "bg-blue-100 text-blue-700", MobileMoney: "bg-amber-100 text-amber-700", BankTransfer: "bg-violet-100 text-violet-700" }

export default function HotelPaymentsPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelPayment[]>([]); const [bookings, setBookings] = useState<HotelBooking[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ hotelBookingId: 0, amount: 0, paymentMethod: "Cash", reference: "", notes: "" })
  const [page, setPage] = useState(1); const [pageSize, setPageSize] = useState(20); const [totalItems, setTotalItems] = useState(0)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router, page, pageSize])
  async function load() { setLoading(true); try { const [pr, b] = await Promise.all([listHotelPaymentsPaged(page, pageSize), listHotelBookings()]); setItems(pr.data); setTotalItems(pr.total); setBookings(b.filter((x) => x.status === "CheckedIn" || x.status === "Confirmed")) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.hotelBookingId) { toast({ title: "Select a booking", variant: "destructive" }); return }
    setSaving(true)
    try { await recordPayment(form); toast({ title: "Payment recorded" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  const total = items.reduce((s, p: any) => s + Number(p.amount ?? 0), 0)
  function handlePageChange(p: number) { setPage(p) }
  function handlePageSizeChange(ps: number) { setPageSize(ps); setPage(1) }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><CreditCard className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Payments</h1><span className="text-sm text-slate-500">({totalItems}) — Page total: {total.toFixed(2)}</span></div>
          <Button onClick={() => { setForm({ hotelBookingId: bookings[0]?.hotelBookingId ?? 0, amount: 0, paymentMethod: "Cash", reference: "", notes: "" }); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Record Payment</Button>
        </div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Date</th><th className="text-left p-3">Guest (Payer)</th><th className="text-left p-3">Received By</th><th className="text-right p-3">Amount</th><th className="text-left p-3">Method</th><th className="text-left p-3">Reference</th><th className="text-left p-3">Notes</th></tr></thead>
            <tbody>{items.map((p: any, idx: number) => {
              const bk = bookings.find((b) => b.hotelBookingId === (p.hotelBookingId ?? p.hotelbookingid))
              return (<tr key={p.hotelPaymentId ?? p.hotelpaymentid ?? `pay-${idx}`} className="border-b hover:bg-slate-50"><td className="p-3">{(p.paymentDate ?? p.paymentdate)?.slice?.(0,10)}</td><td className="p-3 font-medium">{bk ? `${bk.guestFirstName} ${bk.guestLastName}` : "—"}<div className="text-xs text-slate-400">{bk?.bookingRef ?? ""}</div></td><td className="p-3 text-xs text-slate-500">{p.receivedBy ?? p.receivedby ?? "System"}</td><td className="p-3 text-right font-semibold">{Number(p.amount).toFixed(2)}</td><td className="p-3"><Badge variant="outline" className={METHOD_COLOR[p.paymentMethod ?? p.paymentmethod] ?? ""}>{p.paymentMethod ?? p.paymentmethod}</Badge></td><td className="p-3 font-mono text-xs">{p.reference ?? "—"}</td><td className="p-3 text-xs">{p.notes ?? ""}</td></tr>)
            })}
              {items.length === 0 && <tr><td colSpan={7} className="p-8 text-center text-slate-400">No payments recorded yet.</td></tr>}
            </tbody></table>
            <PaginationControls page={page} pageSize={pageSize} total={totalItems} onPageChange={handlePageChange} onPageSizeChange={handlePageSizeChange} />
          </CardContent></Card>
        )}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>Record Payment</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Booking *</Label><Select value={String(form.hotelBookingId)} onValueChange={(v) => setForm({...form, hotelBookingId: Number(v)})}><SelectTrigger><SelectValue placeholder="Select booking" /></SelectTrigger><SelectContent>{bookings.map(b => <SelectItem key={b.hotelBookingId} value={String(b.hotelBookingId)}>{b.bookingRef} — {b.guestFirstName} {b.guestLastName}</SelectItem>)}</SelectContent></Select></div>

            {/* Guest details auto-populated from selected booking */}
            {form.hotelBookingId > 0 && (() => {
              const bk = bookings.find(b => b.hotelBookingId === form.hotelBookingId)
              if (!bk) return null
              const nights = Math.max(1, Math.ceil((new Date(bk.checkOutDate).getTime() - new Date(bk.checkInDate).getTime()) / 86400000))
              return (
                <Card className="border-violet-100 bg-violet-50/30">
                  <CardContent className="p-3 text-sm">
                    <div className="grid grid-cols-2 gap-2">
                      <div><span className="text-slate-500">Guest</span><div className="font-semibold">{bk.guestFirstName} {bk.guestLastName}</div></div>
                      <div><span className="text-slate-500">Booking Ref</span><div className="font-mono font-semibold">{bk.bookingRef}</div></div>
                      <div><span className="text-slate-500">Room</span><div className="font-semibold">{bk.roomNumber ?? "—"} ({bk.roomTypeName ?? "—"})</div></div>
                      <div><span className="text-slate-500">Status</span><div><Badge variant="outline" className={bk.status === "CheckedIn" ? "bg-emerald-100 text-emerald-700" : "bg-blue-100 text-blue-700"}>{bk.status}</Badge></div></div>
                      <div><span className="text-slate-500">Dates</span><div>{bk.checkInDate?.slice(0, 10)} → {bk.checkOutDate?.slice(0, 10)} ({nights} night{nights > 1 ? "s" : ""})</div></div>
                      <div><span className="text-slate-500">Total Amount</span><div className="font-bold text-violet-700">{Number(bk.totalAmount ?? 0).toFixed(2)}</div></div>
                    </div>
                  </CardContent>
                </Card>
              )
            })()}

            <div className="grid grid-cols-2 gap-4"><div><Label>Amount *</Label><Input type="number" step="0.01" value={form.amount} onChange={(e) => setForm({...form, amount: Number(e.target.value)})} /></div><div><Label>Method</Label><Select value={form.paymentMethod} onValueChange={(v) => setForm({...form, paymentMethod: v})}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="Cash">Cash</SelectItem><SelectItem value="Card">Card</SelectItem><SelectItem value="MobileMoney">Mobile Money</SelectItem><SelectItem value="BankTransfer">Bank Transfer</SelectItem></SelectContent></Select></div></div>
            <div><Label>Reference</Label><Input value={form.reference} onChange={(e) => setForm({...form, reference: e.target.value})} placeholder="Transaction ID" /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Record</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}

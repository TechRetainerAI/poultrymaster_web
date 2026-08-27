"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, ScrollText, Printer } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelBookings, getGuestFolio, type HotelBooking } from "@/lib/api/hotel"

export default function HotelGuestFolioPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [bookings, setBookings] = useState<HotelBooking[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [folio, setFolio] = useState<any>(null)
  const [loading, setLoading] = useState(true); const [folioLoading, setFolioLoading] = useState(false)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; loadBookings() }, [activeFarmType, router])
  async function loadBookings() { setLoading(true); try { const b = await listHotelBookings(); setBookings(b.filter(x => x.status === "CheckedIn" || x.status === "CheckedOut")) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function loadFolio(id: number) {
    setSelectedId(id); setFolioLoading(true); setFolio(null)
    try { setFolio(await getGuestFolio(id)) } catch (e: any) { toast({ title: "Failed to load folio", description: e?.message, variant: "destructive" }) }
    finally { setFolioLoading(false) }
  }

  function printFolio() {
    if (!folio) return
    const b = folio.booking; const h = folio.hotel; const s = folio.summary
    const chargeRows = folio.charges.map((c: any) => `<tr><td>${(c.chargedate ?? "").slice(0,10)}</td><td>${c.chargetype}</td><td>${c.description ?? ""}</td><td style="text-align:right">${Number(c.quantity ?? 1)}</td><td style="text-align:right">${Number(c.unitprice ?? 0).toFixed(2)}</td><td style="text-align:right;font-weight:600">${Number(c.totalamount ?? 0).toFixed(2)}</td></tr>`).join("")
    const payRows = folio.payments.map((p: any) => `<tr><td>${(p.paymentdate ?? "").slice(0,10)}</td><td>${p.paymentmethod}</td><td>${p.reference ?? ""}</td><td style="text-align:right;font-weight:600;color:#059669">${Number(p.amount ?? 0).toFixed(2)}</td></tr>`).join("")
    const w = window.open("", "_blank")
    if (!w) return
    w.document.write(`<!DOCTYPE html><html><head><style>body{font-family:sans-serif;margin:40px;color:#1e293b}table{width:100%;border-collapse:collapse;margin:12px 0}th,td{padding:8px;border-bottom:1px solid #e2e8f0;text-align:left}th{background:#f8fafc;font-size:12px}h1{color:#7c3aed;margin:0}h2{font-size:14px;color:#64748b;margin:16px 0 8px}.summary{background:#f8fafc;padding:16px;border-radius:8px;margin:16px 0}.header{text-align:center;border-bottom:2px solid #7c3aed;padding-bottom:16px;margin-bottom:24px}@media print{body{margin:20px}}</style></head><body>
      <div class="header"><h1>${h.name}</h1><p style="color:#64748b">${h.address}<br>${h.phone} | ${h.email}</p></div>
      <h2 style="font-size:18px;color:#1e293b">Guest Folio / Statement</h2>
      <table><tr><td><strong>Guest:</strong> ${b.firstname} ${b.lastname}</td><td><strong>Ref:</strong> ${b.bookingref}</td></tr><tr><td><strong>Room:</strong> ${b.roomnumber ?? "—"} (${b.roomtypename})</td><td><strong>Status:</strong> ${b.status}</td></tr><tr><td><strong>Check-in:</strong> ${(b.checkindate ?? "").slice(0,10)}</td><td><strong>Check-out:</strong> ${(b.checkoutdate ?? "").slice(0,10)}</td></tr></table>
      <h2>Charges</h2><table><thead><tr><th>Date</th><th>Type</th><th>Description</th><th style="text-align:right">Qty</th><th style="text-align:right">Rate</th><th style="text-align:right">Total</th></tr></thead><tbody><tr><td>${(b.checkindate ?? "").slice(0,10)}</td><td>Room</td><td>${b.roomtypename} (${Math.max(1, Math.ceil((new Date(b.checkoutdate).getTime() - new Date(b.checkindate).getTime()) / 86400000))} nights)</td><td style="text-align:right">1</td><td style="text-align:right">${Number(b.nightlyrate ?? 0).toFixed(2)}</td><td style="text-align:right;font-weight:600">${Number(b.totalamount ?? 0).toFixed(2)}</td></tr>${chargeRows}</tbody></table>
      <h2>Payments</h2><table><thead><tr><th>Date</th><th>Method</th><th>Reference</th><th style="text-align:right">Amount</th></tr></thead><tbody>${payRows || '<tr><td colspan="4" style="text-align:center;color:#94a3b8">No payments</td></tr>'}</tbody></table>
      <div class="summary"><table style="margin:0"><tr><td>Room Total</td><td style="text-align:right">${s.roomTotal.toFixed(2)}</td></tr><tr><td>Additional Charges</td><td style="text-align:right">${s.chargesTotal.toFixed(2)}</td></tr><tr style="font-weight:700;font-size:16px"><td>Grand Total</td><td style="text-align:right">${s.grandTotal.toFixed(2)}</td></tr><tr><td>Total Paid</td><td style="text-align:right;color:#059669">${s.paymentsTotal.toFixed(2)}</td></tr><tr style="font-weight:700;font-size:18px"><td>Balance Due</td><td style="text-align:right;color:${s.balance <= 0 ? '#059669' : '#dc2626'}">${s.balance.toFixed(2)}</td></tr></table></div>
      <p style="text-align:center;color:#94a3b8;font-size:12px;margin-top:24px">Thank you for staying at ${h.name}</p>
    </body></html>`)
    w.document.close(); w.print()
  }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><ScrollText className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Guest Folio</h1></div>
          {folio && <Button onClick={printFolio} variant="outline"><Printer className="h-4 w-4 mr-1" /> Print Folio</Button>}
        </div>

        <Card className="mb-6"><CardContent className="p-4">
          <div className="flex gap-4 items-end">
            <div className="flex-1"><label className="text-sm font-medium">Select Booking</label>
              <Select value={selectedId ? String(selectedId) : undefined} onValueChange={(v) => loadFolio(Number(v))}>
                <SelectTrigger><SelectValue placeholder="Pick a booking..." /></SelectTrigger>
                <SelectContent>{bookings.map((b) => <SelectItem key={b.hotelBookingId} value={String(b.hotelBookingId)}>{b.bookingRef} — {b.guestFirstName} {b.guestLastName} ({b.status})</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
        </CardContent></Card>

        {folioLoading && <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>}
        {folio && !folioLoading && (() => {
          const b = folio.booking; const h = folio.hotel; const s = folio.summary
          return (
            <div className="space-y-4">
              {/* Hotel header */}
              <Card className="border-violet-200"><CardContent className="p-4 text-center">
                <h2 className="text-xl font-bold text-violet-700">{h.name}</h2>
                <p className="text-sm text-slate-500">{h.address}</p>
                <p className="text-sm text-slate-500">{h.phone} | {h.email}</p>
              </CardContent></Card>

              {/* Guest & Booking */}
              <Card><CardContent className="p-4 grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                <div><span className="text-slate-500">Guest</span><div className="font-semibold">{b.firstname} {b.lastname}</div></div>
                <div><span className="text-slate-500">Ref</span><div className="font-mono font-semibold">{b.bookingref}</div></div>
                <div><span className="text-slate-500">Room</span><div className="font-semibold">{b.roomnumber ?? "—"} ({b.roomtypename})</div></div>
                <div><span className="text-slate-500">Status</span><div><Badge variant="outline" className={b.status === "CheckedIn" ? "bg-emerald-100 text-emerald-700" : "bg-slate-100"}>{b.status}</Badge></div></div>
                <div><span className="text-slate-500">Check-in</span><div>{(b.checkindate ?? "").slice(0, 10)}</div></div>
                <div><span className="text-slate-500">Check-out</span><div>{(b.checkoutdate ?? "").slice(0, 10)}</div></div>
                <div><span className="text-slate-500">Guests</span><div>{b.adults} adults{b.children > 0 ? `, ${b.children} children` : ""}</div></div>
                <div><span className="text-slate-500">Nightly Rate</span><div className="font-semibold">{Number(b.nightlyrate ?? 0).toFixed(2)}</div></div>
              </CardContent></Card>

              {/* Charges */}
              <Card><CardHeader className="pb-2"><CardTitle className="text-sm">Charges</CardTitle></CardHeader><CardContent className="p-0">
                <table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Date</th><th className="text-left p-3">Type</th><th className="text-left p-3">Description</th><th className="text-right p-3">Qty</th><th className="text-right p-3">Rate</th><th className="text-right p-3">Total</th></tr></thead>
                <tbody>
                  <tr className="border-b"><td className="p-3">{(b.checkindate ?? "").slice(0,10)}</td><td className="p-3">Room</td><td className="p-3">{b.roomtypename}</td><td className="p-3 text-right">1</td><td className="p-3 text-right">{Number(b.nightlyrate ?? 0).toFixed(2)}</td><td className="p-3 text-right font-semibold">{Number(b.totalamount ?? 0).toFixed(2)}</td></tr>
                  {folio.charges.map((c: any, i: number) => <tr key={i} className="border-b"><td className="p-3">{(c.chargedate ?? "").slice(0,10)}</td><td className="p-3">{c.chargetype}</td><td className="p-3">{c.description ?? ""}</td><td className="p-3 text-right">{c.quantity ?? 1}</td><td className="p-3 text-right">{Number(c.unitprice ?? 0).toFixed(2)}</td><td className="p-3 text-right font-semibold">{Number(c.totalamount ?? 0).toFixed(2)}</td></tr>)}
                </tbody></table>
              </CardContent></Card>

              {/* Payments */}
              <Card><CardHeader className="pb-2"><CardTitle className="text-sm">Payments</CardTitle></CardHeader><CardContent className="p-0">
                <table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Date</th><th className="text-left p-3">Method</th><th className="text-left p-3">Reference</th><th className="text-right p-3">Amount</th></tr></thead>
                <tbody>
                  {folio.payments.map((p: any, i: number) => <tr key={i} className="border-b"><td className="p-3">{(p.paymentdate ?? "").slice(0,10)}</td><td className="p-3">{p.paymentmethod}</td><td className="p-3 font-mono text-xs">{p.reference ?? "—"}</td><td className="p-3 text-right font-semibold text-emerald-700">{Number(p.amount ?? 0).toFixed(2)}</td></tr>)}
                  {folio.payments.length === 0 && <tr><td colSpan={4} className="p-4 text-center text-slate-400">No payments</td></tr>}
                </tbody></table>
              </CardContent></Card>

              {/* Summary */}
              <Card className="border-violet-200"><CardContent className="p-4">
                <div className="grid grid-cols-2 gap-2 text-sm max-w-md mx-auto">
                  <div className="text-slate-500">Room Total</div><div className="text-right">{s.roomTotal.toFixed(2)}</div>
                  <div className="text-slate-500">Additional Charges</div><div className="text-right">{s.chargesTotal.toFixed(2)}</div>
                  <div className="font-bold text-lg border-t pt-2">Grand Total</div><div className="text-right font-bold text-lg border-t pt-2">{s.grandTotal.toFixed(2)}</div>
                  <div className="text-emerald-700">Total Paid</div><div className="text-right text-emerald-700">{s.paymentsTotal.toFixed(2)}</div>
                  <div className={`font-bold text-xl ${s.balance <= 0 ? "text-emerald-700" : "text-red-700"}`}>Balance Due</div>
                  <div className={`text-right font-bold text-xl ${s.balance <= 0 ? "text-emerald-700" : "text-red-700"}`}>{s.balance.toFixed(2)}</div>
                </div>
              </CardContent></Card>
            </div>
          )
        })()}
        {!folio && !folioLoading && !loading && <div className="text-center py-12 text-slate-400">Select a booking above to view the guest folio.</div>}
      </main></div></div>
  )
}

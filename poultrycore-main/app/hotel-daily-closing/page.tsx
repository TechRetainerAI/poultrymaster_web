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
import { Loader2, FileText, Plus, TrendingUp, TrendingDown, Users, DoorOpen } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listDailyClosings, createDailyClosing, getHotelRoomStatusSummary, listHotelBookings, listHotelPayments, listHotelExpenses, type HotelDailyClosing } from "@/lib/api/hotel"

export default function HotelDailyClosingPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelDailyClosing[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ closingDate: new Date().toISOString().slice(0,10), notes: "" })

  // Live stats for the "Close Today" preview
  const [liveStats, setLiveStats] = useState({ totalRooms: 0, occupied: 0, available: 0, revenue: 0, expenses: 0, arrivals: 0, departures: 0, checkedIn: 0 })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      setItems(await listDailyClosings())
      // Load live stats
      const [roomStatus, bookings, payments, expenses] = await Promise.all([
        getHotelRoomStatusSummary().catch(() => []),
        listHotelBookings().catch(() => []),
        listHotelPayments().catch(() => []),
        listHotelExpenses().catch(() => []),
      ])
      const today = new Date().toISOString().slice(0, 10)
      const totalRooms = roomStatus.reduce((s: number, r: any) => s + (r.roomCount ?? r.RoomCount ?? 0), 0)
      const occupied = roomStatus.find((r: any) => (r.status ?? r.Status) === "Occupied")?.roomCount ?? roomStatus.find((r: any) => (r.status ?? r.Status) === "Occupied")?.RoomCount ?? 0
      const available = roomStatus.find((r: any) => (r.status ?? r.Status) === "Available")?.roomCount ?? roomStatus.find((r: any) => (r.status ?? r.Status) === "Available")?.RoomCount ?? 0
      const todayPayments = payments.filter((p: any) => (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10) === today)
      const todayExpenses = expenses.filter((e: any) => (e.expenseDate ?? e.expensedate ?? "").slice(0, 10) === today)
      const revenue = todayPayments.reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
      const expenseTotal = todayExpenses.reduce((s: number, e: any) => s + Number(e.amount ?? 0), 0)
      const arrivals = bookings.filter((b) => b.checkInDate?.slice(0, 10) === today && b.status === "Confirmed").length
      const departures = bookings.filter((b) => b.checkOutDate?.slice(0, 10) === today && b.status === "CheckedIn").length
      const checkedIn = bookings.filter((b) => b.status === "CheckedIn").length
      setLiveStats({ totalRooms, occupied, available, revenue, expenses: expenseTotal, arrivals, departures, checkedIn })
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function handleClose() {
    setSaving(true)
    try { await createDailyClosing(form); toast({ title: "Day closed successfully" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  const occRate = liveStats.totalRooms > 0 ? Math.round((liveStats.occupied / liveStats.totalRooms) * 100) : 0
  const netProfit = liveStats.revenue - liveStats.expenses

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><FileText className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Daily Closing</h1></div>
          <Button onClick={() => { setForm({ closingDate: new Date().toISOString().slice(0,10), notes: "" }); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Close Today</Button>
        </div>

        {/* Live Today's Stats */}
        <Card className="mb-6 border-violet-200">
          <CardHeader className="pb-2"><CardTitle className="text-base flex items-center gap-2"><TrendingUp className="h-5 w-5 text-violet-600" />Today&apos;s Live Snapshot</CardTitle></CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-8 gap-4 text-center">
              <div><div className="text-2xl font-bold text-violet-700">{liveStats.totalRooms}</div><div className="text-xs text-slate-500">Total Rooms</div></div>
              <div><div className="text-2xl font-bold text-emerald-700">{liveStats.available}</div><div className="text-xs text-slate-500">Available</div></div>
              <div><div className="text-2xl font-bold text-violet-700">{liveStats.occupied}</div><div className="text-xs text-slate-500">Occupied</div></div>
              <div><div className="text-2xl font-bold text-violet-700">{occRate}%</div><div className="text-xs text-slate-500">Occupancy</div></div>
              <div><div className="text-2xl font-bold text-emerald-700">GH₵{liveStats.revenue.toFixed(0)}</div><div className="text-xs text-slate-500">Revenue</div></div>
              <div><div className="text-2xl font-bold text-red-700">GH₵{liveStats.expenses.toFixed(0)}</div><div className="text-xs text-slate-500">Expenses</div></div>
              <div><div className={`text-2xl font-bold ${netProfit >= 0 ? "text-emerald-700" : "text-red-700"}`}>GH₵{netProfit.toFixed(0)}</div><div className="text-xs text-slate-500">Net</div></div>
              <div><div className="text-2xl font-bold text-blue-700">{liveStats.checkedIn}</div><div className="text-xs text-slate-500">In-House</div></div>
            </div>
          </CardContent>
        </Card>

        {/* Closing History */}
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr>
            <th className="text-left p-3">Date</th><th className="text-right p-3">Revenue</th><th className="text-right p-3">Expenses</th><th className="text-right p-3">Net</th><th className="text-right p-3">Occupancy</th><th className="text-right p-3">Rooms</th><th className="text-right p-3">ADR</th><th className="text-right p-3">RevPAR</th><th className="text-left p-3">Notes</th>
          </tr></thead>
            <tbody>{items.map((i: any, idx: number) => {
              const rev = Number(i.totalRevenue ?? i.totalrevenue ?? 0)
              const exp = Number(i.totalExpenses ?? i.totalexpenses ?? 0)
              const net = rev - exp
              return (<tr key={i.hotelDailyClosingId ?? i.hoteldailyclosingid ?? `dc-${idx}`} className="border-b hover:bg-slate-50">
                <td className="p-3 font-medium">{(i.closingDate ?? i.closingdate)?.slice?.(0,10)}</td>
                <td className="p-3 text-right text-emerald-700 font-semibold">GH₵{rev.toFixed(2)}</td>
                <td className="p-3 text-right text-red-600">GH₵{exp.toFixed(2)}</td>
                <td className={`p-3 text-right font-bold ${net >= 0 ? "text-emerald-700" : "text-red-700"}`}>GH₵{net.toFixed(2)}</td>
                <td className="p-3 text-right">{Number(i.occupancyRate ?? i.occupancyrate ?? 0).toFixed(1)}%</td>
                <td className="p-3 text-right">{i.roomsOccupied ?? i.roomsoccupied ?? 0}/{i.totalRooms ?? i.totalrooms ?? 0}</td>
                <td className="p-3 text-right">GH₵{Number(i.adr ?? 0).toFixed(2)}</td>
                <td className="p-3 text-right">GH₵{Number(i.revPar ?? i.revpar ?? 0).toFixed(2)}</td>
                <td className="p-3 text-xs text-slate-500">{i.notes ?? ""}</td>
              </tr>)
            })}
              {items.length === 0 && <tr><td colSpan={9} className="p-8 text-center text-slate-400">No closings yet. Click "Close Today" to record today&apos;s snapshot.</td></tr>}
            </tbody></table></CardContent></Card>
        )}

        {/* Close Day Dialog */}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent className="max-w-lg"><DialogHeader><DialogTitle>Close Day</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="p-4 bg-violet-50 rounded-lg space-y-2">
              <p className="text-sm font-semibold text-violet-700">This will auto-calculate and save today&apos;s snapshot:</p>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div>Occupancy: <strong>{occRate}%</strong> ({liveStats.occupied}/{liveStats.totalRooms})</div>
                <div>Revenue: <strong className="text-emerald-700">GH₵{liveStats.revenue.toFixed(2)}</strong></div>
                <div>Expenses: <strong className="text-red-700">GH₵{liveStats.expenses.toFixed(2)}</strong></div>
                <div>Net: <strong className={netProfit >= 0 ? "text-emerald-700" : "text-red-700"}>GH₵{netProfit.toFixed(2)}</strong></div>
                <div>In-house guests: <strong>{liveStats.checkedIn}</strong></div>
                <div>ADR: <strong>GH₵{liveStats.occupied > 0 ? (liveStats.revenue / liveStats.occupied).toFixed(2) : "0.00"}</strong></div>
              </div>
            </div>
            <div><Label>Date</Label><Input type="date" value={form.closingDate} onChange={(e) => setForm({...form, closingDate: e.target.value})} /></div>
            <div><Label>Notes</Label><Input value={form.notes} onChange={(e) => setForm({...form, notes: e.target.value})} placeholder="Optional notes about today" /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleClose} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Close Day</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}

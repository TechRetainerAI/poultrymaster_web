"use client"
import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, Bell, Plus, Play, CheckCircle2, XCircle, Search } from "lucide-react"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listGuestRequests, createGuestRequest, updateGuestRequestStatus, listHotelBookings, listHotelRooms, type HotelBooking, type HotelRoom } from "@/lib/api/hotel"

const REQUEST_TYPES = ["WakeUpCall", "ExtraTowels", "RoomService", "Maintenance", "Transport", "Other"]
const STATUS_COLORS: Record<string, string> = { Pending: "bg-amber-100 text-amber-700", InProgress: "bg-blue-100 text-blue-700", Completed: "bg-emerald-100 text-emerald-700", Cancelled: "bg-red-100 text-red-700" }

export default function HotelGuestRequestsPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<any[]>([]); const [bookings, setBookings] = useState<HotelBooking[]>([]); const [rooms, setRooms] = useState<HotelRoom[]>([])
  const [loading, setLoading] = useState(true); const [statusFilter, setStatusFilter] = useState("ALL")
  const [search, setSearch] = useState(""); const [page, setPage] = useState(1); const pageSize = 10
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ hotelBookingId: null as number | null, hotelRoomId: null as number | null, requestType: "Other", description: "", scheduledTime: "", assignedTo: "", notes: "" })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { const [r, b, rm] = await Promise.all([listGuestRequests(), listHotelBookings(), listHotelRooms()]); setItems(r); setBookings(b.filter(x => x.status === "CheckedIn")); setRooms(rm) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() { setSaving(true); try { await createGuestRequest(form); toast({ title: "Request created" }); setOpen(false); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) } }
  async function doAction(id: number, status: string) { try { await updateGuestRequestStatus(id, status); toast({ title: `Request ${status.toLowerCase()}` }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  const filtered = useMemo(() => items.filter((r: any) => {
    if (statusFilter !== "ALL" && (r.status ?? "") !== statusFilter) return false
    if (search) { const q = search.toLowerCase(); if (!`${r.firstname ?? ""} ${r.lastname ?? ""} ${r.roomnumber ?? ""} ${r.requesttype ?? ""} ${r.description ?? ""}`.toLowerCase().includes(q)) return false }
    return true
  }), [items, statusFilter, search])
  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)
  const counts = { Pending: items.filter((r: any) => r.status === "Pending").length, InProgress: items.filter((r: any) => r.status === "InProgress").length, Completed: items.filter((r: any) => r.status === "Completed").length }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-4"><div className="flex items-center gap-3"><Bell className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Guest Requests</h1></div>
          <Button onClick={() => { setForm({ hotelBookingId: null, hotelRoomId: null, requestType: "Other", description: "", scheduledTime: "", assignedTo: "", notes: "" }); setOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> New Request</Button></div>
        <div className="flex gap-2 flex-wrap mb-3">{[{ s: "ALL", l: "All", c: items.length }, { s: "Pending", l: "Pending", c: counts.Pending }, { s: "InProgress", l: "In Progress", c: counts.InProgress }, { s: "Completed", l: "Completed", c: counts.Completed }].map(f => <Button key={f.s} variant={statusFilter === f.s ? "default" : "outline"} size="sm" onClick={() => { setStatusFilter(f.s); setPage(1) }} className={statusFilter === f.s ? "bg-violet-600" : ""}>{f.l} ({f.c})</Button>)}</div>
        <div className="mb-4 relative max-w-sm"><Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search..." className="pl-9" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} /></div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Date</th><th className="text-left p-3">Room</th><th className="text-left p-3">Guest</th><th className="text-left p-3">Type</th><th className="text-left p-3">Description</th><th className="text-left p-3">Scheduled</th><th className="text-left p-3">Assigned</th><th className="text-left p-3">Status</th><th className="text-right p-3">Actions</th></tr></thead>
            <tbody>{paged.map((r: any, i: number) => (<tr key={r.hotelguestrequestid ?? i} className="border-b hover:bg-slate-50"><td className="p-3 text-xs">{(r.createdat ?? "").slice(0, 10)}</td><td className="p-3">{r.roomnumber ?? "—"}</td><td className="p-3">{r.firstname ? `${r.firstname} ${r.lastname}` : "—"}</td><td className="p-3"><Badge variant="outline">{r.requesttype}</Badge></td><td className="p-3 max-w-[200px] truncate">{r.description ?? "—"}</td><td className="p-3 text-xs">{r.scheduledtime ? new Date(r.scheduledtime).toLocaleString() : "—"}</td><td className="p-3 text-xs">{r.assignedto ?? "—"}</td><td className="p-3"><Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge></td>
              <td className="p-3 text-right whitespace-nowrap">{r.status === "Pending" && <Button size="sm" variant="ghost" onClick={() => doAction(r.hotelguestrequestid, "InProgress")} title="Start"><Play className="h-4 w-4 text-blue-600" /></Button>}{(r.status === "Pending" || r.status === "InProgress") && <Button size="sm" variant="ghost" onClick={() => doAction(r.hotelguestrequestid, "Completed")} title="Complete"><CheckCircle2 className="h-4 w-4 text-emerald-600" /></Button>}{r.status !== "Completed" && r.status !== "Cancelled" && <Button size="sm" variant="ghost" onClick={() => doAction(r.hotelguestrequestid, "Cancelled")} title="Cancel"><XCircle className="h-4 w-4 text-red-500" /></Button>}</td></tr>))}
              {filtered.length === 0 && <tr><td colSpan={9} className="p-8 text-center text-slate-400">No requests found.</td></tr>}</tbody></table>
            <PaginationControls page={page} pageSize={pageSize} total={filtered.length} onPageChange={setPage} /></CardContent></Card>)}

        <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-w-lg"><DialogHeader><DialogTitle>New Guest Request</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3"><div><Label>Booking (optional)</Label><Select value={form.hotelBookingId ? String(form.hotelBookingId) : "__none__"} onValueChange={(v) => setForm({ ...form, hotelBookingId: v === "__none__" ? null : Number(v) })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="__none__">None</SelectItem>{bookings.map(b => <SelectItem key={b.hotelBookingId} value={String(b.hotelBookingId)}>{b.guestFirstName} {b.guestLastName} - {b.roomNumber ?? b.bookingRef}</SelectItem>)}</SelectContent></Select></div>
              <div><Label>Room</Label><Select value={form.hotelRoomId ? String(form.hotelRoomId) : "__none__"} onValueChange={(v) => setForm({ ...form, hotelRoomId: v === "__none__" ? null : Number(v) })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="__none__">None</SelectItem>{rooms.map((r: any) => <SelectItem key={r.hotelRoomId} value={String(r.hotelRoomId)}>Room {r.roomNumber}</SelectItem>)}</SelectContent></Select></div></div>
            <div className="grid grid-cols-2 gap-3"><div><Label>Type *</Label><Select value={form.requestType} onValueChange={(v) => setForm({ ...form, requestType: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{REQUEST_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent></Select></div>
              <div><Label>Scheduled Time</Label><Input type="datetime-local" value={form.scheduledTime} onChange={(e) => setForm({ ...form, scheduledTime: e.target.value })} /></div></div>
            <div><Label>Description</Label><Textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} /></div>
            <div><Label>Assigned To</Label><Input value={form.assignedTo} onChange={(e) => setForm({ ...form, assignedTo: e.target.value })} placeholder="Staff name" /></div>
          </div><DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Create</Button></DialogFooter></DialogContent></Dialog>
      </main></div></div>
  )
}

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
import { Loader2, MessageSquare, Plus, Play, CheckCircle2, XCircle, Search } from "lucide-react"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listCommunications, createCommunication, updateCommunicationStatus, listHotelGuests, listHotelBookings, listHotelCommSubjects, listHotelStaff, type HotelGuest, type HotelBooking, type HotelCommSubject, type HotelStaff } from "@/lib/api/hotel"

const COMM_TYPES = ["Note", "Complaint", "Request", "Compliment", "Incident"]
const PRIORITIES = ["Low", "Normal", "High", "Urgent"]
const PRIORITY_COLORS: Record<string, string> = { Low: "bg-slate-100 text-slate-600", Normal: "bg-blue-100 text-blue-700", High: "bg-amber-100 text-amber-700", Urgent: "bg-red-100 text-red-700" }
const STATUS_COLORS: Record<string, string> = { Open: "bg-amber-100 text-amber-700", InProgress: "bg-blue-100 text-blue-700", Resolved: "bg-emerald-100 text-emerald-700", Closed: "bg-slate-100 text-slate-700" }

export default function HotelCommunicationsPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<any[]>([]); const [guests, setGuests] = useState<HotelGuest[]>([]); const [bookings, setBookings] = useState<HotelBooking[]>([])
  const [commSubjects, setCommSubjects] = useState<HotelCommSubject[]>([])
  const [staff, setStaff] = useState<HotelStaff[]>([])
  const [loading, setLoading] = useState(true); const [statusFilter, setStatusFilter] = useState("ALL")
  const [search, setSearch] = useState(""); const [page, setPage] = useState(1); const pageSize = 10
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ hotelGuestId: 0, hotelBookingId: null as number | null, commType: "Note", subject: "", message: "", priority: "Normal", assignedTo: "" })
  const [subjectSelection, setSubjectSelection] = useState("")
  const [customSubject, setCustomSubject] = useState("")

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { const [c, g, b, cs, st] = await Promise.all([listCommunications(), listHotelGuests(), listHotelBookings(), listHotelCommSubjects().catch(() => []), listHotelStaff().catch(() => [])]); setItems(c); setGuests(g); setBookings(b); setCommSubjects(cs); setStaff(st.filter((s: any) => s.isActive ?? s.isactive)) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() { if (!form.hotelGuestId) { toast({ title: "Select a guest", variant: "destructive" }); return }; if (!form.message.trim()) { toast({ title: "Message required", variant: "destructive" }); return }; setSaving(true); try { await createCommunication(form); toast({ title: "Communication logged" }); setOpen(false); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) } }
  async function doStatus(id: number, status: string) { try { await updateCommunicationStatus(id, status); toast({ title: `Status → ${status}` }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  const filtered = useMemo(() => items.filter((r: any) => {
    if (statusFilter !== "ALL" && (r.status ?? "") !== statusFilter) return false
    if (search) { const q = search.toLowerCase(); if (!`${r.firstname ?? ""} ${r.lastname ?? ""} ${r.subject ?? ""} ${r.message ?? ""} ${r.roomnumber ?? ""}`.toLowerCase().includes(q)) return false }
    return true
  }), [items, statusFilter, search])
  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)
  const counts = { Open: items.filter((r: any) => r.status === "Open").length, InProgress: items.filter((r: any) => r.status === "InProgress").length, Resolved: items.filter((r: any) => r.status === "Resolved").length }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-4"><div className="flex items-center gap-3"><MessageSquare className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Guest Communication Log</h1></div>
          <Button onClick={() => { setForm({ hotelGuestId: guests[0]?.hotelGuestId ?? 0, hotelBookingId: null, commType: "Note", subject: "", message: "", priority: "Normal", assignedTo: "" }); setSubjectSelection(""); setCustomSubject(""); setOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Log Entry</Button></div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
          <Card><CardContent className="p-3"><div className="text-xs text-slate-500">Open</div><div className="text-xl font-bold text-amber-700">{counts.Open}</div></CardContent></Card>
          <Card><CardContent className="p-3"><div className="text-xs text-slate-500">In Progress</div><div className="text-xl font-bold text-blue-700">{counts.InProgress}</div></CardContent></Card>
          <Card><CardContent className="p-3"><div className="text-xs text-slate-500">Resolved</div><div className="text-xl font-bold text-emerald-700">{counts.Resolved}</div></CardContent></Card>
          <Card><CardContent className="p-3"><div className="text-xs text-slate-500">Total</div><div className="text-xl font-bold">{items.length}</div></CardContent></Card>
        </div>
        <div className="flex gap-2 flex-wrap mb-3">{[{ s: "ALL", l: "All" }, { s: "Open", l: "Open" }, { s: "InProgress", l: "In Progress" }, { s: "Resolved", l: "Resolved" }, { s: "Closed", l: "Closed" }].map(f => <Button key={f.s} variant={statusFilter === f.s ? "default" : "outline"} size="sm" onClick={() => { setStatusFilter(f.s); setPage(1) }} className={statusFilter === f.s ? "bg-violet-600" : ""}>{f.l}</Button>)}</div>
        <div className="mb-4 relative max-w-sm"><Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search guest, subject, message..." className="pl-9" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} /></div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Date</th><th className="text-left p-3">Guest</th><th className="text-left p-3">Room</th><th className="text-left p-3">Type</th><th className="text-left p-3">Subject</th><th className="text-left p-3">Priority</th><th className="text-left p-3">Status</th><th className="text-left p-3">Assigned</th><th className="text-right p-3">Actions</th></tr></thead>
            <tbody>{paged.map((r: any, i: number) => (<tr key={r.hotelguestcommid ?? i} className="border-b hover:bg-slate-50"><td className="p-3 text-xs">{(r.createdat ?? "").slice(0, 10)}</td><td className="p-3 font-semibold">{r.firstname ?? ""} {r.lastname ?? ""}</td><td className="p-3">{r.roomnumber ?? "—"}</td><td className="p-3"><Badge variant="outline">{r.commtype}</Badge></td><td className="p-3 max-w-[180px] truncate">{r.subject ?? r.message?.slice(0, 50) ?? "—"}</td><td className="p-3"><Badge className={PRIORITY_COLORS[r.priority] ?? ""}>{r.priority}</Badge></td><td className="p-3"><Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge></td><td className="p-3 text-xs">{r.assignedto ?? "—"}</td>
              <td className="p-3 text-right whitespace-nowrap">{r.status === "Open" && <Button size="sm" variant="ghost" onClick={() => doStatus(r.hotelguestcommid, "InProgress")}><Play className="h-4 w-4 text-blue-600" /></Button>}{(r.status === "Open" || r.status === "InProgress") && <Button size="sm" variant="ghost" onClick={() => doStatus(r.hotelguestcommid, "Resolved")}><CheckCircle2 className="h-4 w-4 text-emerald-600" /></Button>}{r.status === "Resolved" && <Button size="sm" variant="ghost" onClick={() => doStatus(r.hotelguestcommid, "Closed")}><XCircle className="h-4 w-4 text-slate-500" /></Button>}</td></tr>))}
              {filtered.length === 0 && <tr><td colSpan={9} className="p-8 text-center text-slate-400">No communications logged.</td></tr>}</tbody></table>
            <PaginationControls page={page} pageSize={pageSize} total={filtered.length} onPageChange={setPage} /></CardContent></Card>)}

        <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-w-lg"><DialogHeader><DialogTitle>Log Guest Communication</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Guest *</Label><Select value={form.hotelGuestId ? String(form.hotelGuestId) : undefined} onValueChange={(v) => setForm({ ...form, hotelGuestId: Number(v) })}><SelectTrigger><SelectValue placeholder="Select guest" /></SelectTrigger><SelectContent>{guests.map((g: any) => <SelectItem key={g.hotelGuestId} value={String(g.hotelGuestId)}>{g.firstName} {g.lastName}</SelectItem>)}</SelectContent></Select></div>
            <div className="grid grid-cols-2 gap-3"><div><Label>Type</Label><Select value={form.commType} onValueChange={(v) => setForm({ ...form, commType: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{COMM_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent></Select></div>
              <div><Label>Priority</Label><Select value={form.priority} onValueChange={(v) => setForm({ ...form, priority: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{PRIORITIES.map(p => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent></Select></div></div>
            <div><Label>Subject</Label>
              <Select value={subjectSelection || "__none__"} onValueChange={(v) => {
                const sel = v === "__none__" ? "" : v
                setSubjectSelection(sel)
                if (sel !== "Other") { setCustomSubject(""); setForm({ ...form, subject: sel }) }
                else { setForm({ ...form, subject: customSubject || "" }) }
              }}>
                <SelectTrigger><SelectValue placeholder="Select subject" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">None</SelectItem>
                  {commSubjects.map((s) => <SelectItem key={s.hotelCommSubjectId} value={s.description}>{s.description}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            {subjectSelection === "Other" && (
              <div><Label>Specify Subject</Label><Input value={customSubject} onChange={(e) => { setCustomSubject(e.target.value); setForm({ ...form, subject: e.target.value }) }} placeholder="Type custom subject..." /></div>
            )}
            <div><Label>Message *</Label><Textarea value={form.message} onChange={(e) => setForm({ ...form, message: e.target.value })} rows={3} /></div>
            <div><Label>Assigned To</Label>
              <Select value={form.assignedTo || "__none__"} onValueChange={(v) => setForm({ ...form, assignedTo: v === "__none__" ? "" : v })}>
                <SelectTrigger><SelectValue placeholder="Select staff" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">Unassigned</SelectItem>
                  {staff.map((s: any) => { const fn = s.firstName ?? s.firstname ?? ""; const ln = s.lastName ?? s.lastname ?? ""; const role = s.role ?? ""; const id = s.hotelStaffId ?? s.hotelstaffid; return <SelectItem key={id} value={`${fn} ${ln}`}>{fn} {ln} — {role}</SelectItem> })}
                </SelectContent>
              </Select>
            </div>
          </div><DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Log</Button></DialogFooter></DialogContent></Dialog>
      </main></div></div>
  )
}

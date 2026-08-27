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
import { Loader2, CalendarCheck, Plus, Play, CheckCircle2, SkipForward, Users } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHKSchedule, createHKSchedule, bulkCreateHKSchedule, updateHKScheduleStatus, listHotelRooms, type HotelRoom } from "@/lib/api/hotel"

const TASK_TYPES = ["Daily", "DeepClean", "Turndown", "Checkout"]
const STATUS_COLORS: Record<string, string> = { Scheduled: "bg-blue-100 text-blue-700", InProgress: "bg-amber-100 text-amber-700", Completed: "bg-emerald-100 text-emerald-700", Skipped: "bg-slate-100 text-slate-700" }

export default function HotelHKSchedulePage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<any[]>([]); const [rooms, setRooms] = useState<HotelRoom[]>([])
  const [loading, setLoading] = useState(true); const [bulking, setBulking] = useState(false)
  const [schedDate, setSchedDate] = useState(new Date().toISOString().slice(0, 10))
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ scheduleDate: "", hotelRoomId: 0, assignedTo: "", taskType: "Daily", priority: "Normal", notes: "" })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  useEffect(() => { if (activeFarmType === "Hotel") load() }, [schedDate])

  async function load() { setLoading(true); try { const [s, r] = await Promise.all([listHKSchedule(schedDate), listHotelRooms()]); setItems(s); setRooms(r) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleBulk() { setBulking(true); try { const r = await bulkCreateHKSchedule({ scheduleDate: schedDate, taskType: "Daily" }); toast({ title: `${r.created} room(s) scheduled out of ${r.totalRooms} occupied` }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setBulking(false) } }

  async function handleSave() { if (!form.hotelRoomId) { toast({ title: "Select a room", variant: "destructive" }); return }; setSaving(true); try { await createHKSchedule({ ...form, scheduleDate: schedDate }); toast({ title: "Scheduled" }); setOpen(false); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) } }

  async function doStatus(id: number, status: string) { try { await updateHKScheduleStatus(id, status); toast({ title: `Status → ${status}` }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  const scheduled = items.filter((i: any) => i.status === "Scheduled").length
  const inProgress = items.filter((i: any) => i.status === "InProgress").length
  const completed = items.filter((i: any) => i.status === "Completed").length
  const skipped = items.filter((i: any) => i.status === "Skipped").length

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-4"><div className="flex items-center gap-3"><CalendarCheck className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Housekeeping Schedule</h1></div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={handleBulk} disabled={bulking}>{bulking ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Users className="h-4 w-4 mr-1" />} Schedule All Occupied</Button>
            <Button onClick={() => { setForm({ scheduleDate: schedDate, hotelRoomId: 0, assignedTo: "", taskType: "Daily", priority: "Normal", notes: "" }); setOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add</Button>
          </div></div>

        <div className="flex items-center gap-4 mb-4"><Label>Date:</Label><Input type="date" value={schedDate} onChange={(e) => setSchedDate(e.target.value)} className="w-44" /></div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
          <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-blue-700">{scheduled}</div><div className="text-xs text-slate-500">Scheduled</div></CardContent></Card>
          <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-amber-700">{inProgress}</div><div className="text-xs text-slate-500">In Progress</div></CardContent></Card>
          <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-emerald-700">{completed}</div><div className="text-xs text-slate-500">Completed</div></CardContent></Card>
          <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-slate-500">{skipped}</div><div className="text-xs text-slate-500">Skipped</div></CardContent></Card>
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Room</th><th className="text-left p-3">Floor</th><th className="text-left p-3">Type</th><th className="text-left p-3">Task</th><th className="text-left p-3">Assigned</th><th className="text-left p-3">Priority</th><th className="text-left p-3">Status</th><th className="text-left p-3">Time</th><th className="text-right p-3">Actions</th></tr></thead>
            <tbody>{items.map((s: any, i: number) => {
              const elapsed = s.starttime && s.endtime ? `${Math.round((new Date(s.endtime).getTime() - new Date(s.starttime).getTime()) / 60000)} min` : s.starttime ? "In progress..." : "—"
              return (<tr key={s.hotelschedid ?? i} className="border-b hover:bg-slate-50"><td className="p-3 font-semibold">{s.roomnumber}</td><td className="p-3">{s.floorname ?? "—"}</td><td className="p-3 text-xs">{s.roomtypename ?? "—"}</td><td className="p-3"><Badge variant="outline">{s.tasktype}</Badge></td><td className="p-3">{s.assignedto ?? "—"}</td><td className="p-3">{s.priority}</td><td className="p-3"><Badge className={STATUS_COLORS[s.status] ?? ""}>{s.status}</Badge></td><td className="p-3 text-xs">{elapsed}</td>
                <td className="p-3 text-right whitespace-nowrap">{s.status === "Scheduled" && <><Button size="sm" variant="ghost" onClick={() => doStatus(s.hotelschedid, "InProgress")} title="Start"><Play className="h-4 w-4 text-blue-600" /></Button><Button size="sm" variant="ghost" onClick={() => doStatus(s.hotelschedid, "Skipped")} title="Skip"><SkipForward className="h-4 w-4 text-slate-500" /></Button></>}{s.status === "InProgress" && <Button size="sm" variant="ghost" onClick={() => doStatus(s.hotelschedid, "Completed")} title="Complete"><CheckCircle2 className="h-4 w-4 text-emerald-600" /></Button>}</td></tr>)})}
              {items.length === 0 && <tr><td colSpan={9} className="p-8 text-center text-slate-400">No schedule for this date. Click &quot;Schedule All Occupied&quot; to create today&apos;s roster.</td></tr>}</tbody></table></CardContent></Card>)}

        <Dialog open={open} onOpenChange={setOpen}><DialogContent><DialogHeader><DialogTitle>Add Schedule Entry</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Room *</Label><Select value={form.hotelRoomId ? String(form.hotelRoomId) : "__none__"} onValueChange={(v) => setForm({ ...form, hotelRoomId: v === "__none__" ? 0 : Number(v) })}><SelectTrigger><SelectValue placeholder="Select room" /></SelectTrigger><SelectContent><SelectItem value="__none__">-- Select --</SelectItem>{rooms.map((r: any) => <SelectItem key={r.hotelRoomId} value={String(r.hotelRoomId)}>Room {r.roomNumber} ({r.status})</SelectItem>)}</SelectContent></Select></div>
            <div className="grid grid-cols-2 gap-3"><div><Label>Task Type</Label><Select value={form.taskType} onValueChange={(v) => setForm({ ...form, taskType: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{TASK_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent></Select></div>
              <div><Label>Priority</Label><Select value={form.priority} onValueChange={(v) => setForm({ ...form, priority: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="Low">Low</SelectItem><SelectItem value="Normal">Normal</SelectItem><SelectItem value="High">High</SelectItem></SelectContent></Select></div></div>
            <div><Label>Assigned To</Label><Input value={form.assignedTo} onChange={(e) => setForm({ ...form, assignedTo: e.target.value })} placeholder="Housekeeper name" /></div>
          </div><DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Schedule</Button></DialogFooter></DialogContent></Dialog>
      </main></div></div>
  )
}

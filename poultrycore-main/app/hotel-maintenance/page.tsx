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
import { Loader2, Wrench, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listMaintenanceRequests, createMaintenanceRequest, updateMaintenanceStatus, listHotelRooms, type HotelMaintenanceRequest, type HotelRoom } from "@/lib/api/hotel"

const PRIORITY_COLOR: Record<string, string> = { Low: "bg-slate-100 text-slate-700", Normal: "bg-blue-100 text-blue-700", High: "bg-amber-100 text-amber-700", Critical: "bg-red-100 text-red-700" }
const STATUS_COLOR: Record<string, string> = { Open: "bg-blue-100 text-blue-700", Assigned: "bg-amber-100 text-amber-700", InProgress: "bg-violet-100 text-violet-700", Completed: "bg-emerald-100 text-emerald-700", Cancelled: "bg-slate-100 text-slate-700" }
const STATUSES = ["Open", "Assigned", "InProgress", "Completed", "Cancelled"]

export default function HotelMaintenancePage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelMaintenanceRequest[]>([]); const [rooms, setRooms] = useState<HotelRoom[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [filterStatus, setFilterStatus] = useState("all"); const [filterPriority, setFilterPriority] = useState("all")
  const [form, setForm] = useState({ hotelRoomId: null as number | null, assetDescription: "", issueDescription: "", priority: "Normal", estimatedCost: 0 })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { const [m, r] = await Promise.all([listMaintenanceRequests(), listHotelRooms()]); setItems(m); setRooms(r) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.issueDescription.trim()) { toast({ title: "Issue description required", variant: "destructive" }); return }
    setSaving(true)
    try { await createMaintenanceRequest({ ...form, hotelRoomId: form.hotelRoomId ?? undefined }); toast({ title: "Request created" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  async function changeStatus(id: number, status: string) {
    try { await updateMaintenanceStatus(id, status); toast({ title: `Status → ${status}` }); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const filtered = items.filter((m: any) => {
    if (filterStatus !== "all" && (m.status) !== filterStatus) return false
    if (filterPriority !== "all" && (m.priority) !== filterPriority) return false
    return true
  })

  const openCount = items.filter((m: any) => m.status === "Open" || m.status === "Assigned" || m.status === "InProgress").length

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><Wrench className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Maintenance</h1>{openCount > 0 && <Badge className="bg-red-100 text-red-700">{openCount} open</Badge>}</div>
          <Button onClick={() => { setForm({ hotelRoomId: null, assetDescription: "", issueDescription: "", priority: "Normal", estimatedCost: 0 }); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> New Request</Button>
        </div>

        {/* Filters */}
        <div className="flex gap-2 flex-wrap mb-4">
          {["all", ...STATUSES].map(s => (
            <Button key={s} variant={filterStatus === s ? "default" : "outline"} size="sm" onClick={() => setFilterStatus(s)} className={filterStatus === s ? "bg-violet-600" : ""}>
              {s === "all" ? `All (${items.length})` : `${s} (${items.filter((m: any) => m.status === s).length})`}
            </Button>
          ))}
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Room</th><th className="text-left p-3">Asset</th><th className="text-left p-3">Issue</th><th className="text-left p-3">Priority</th><th className="text-left p-3">Status</th><th className="text-right p-3">Est. Cost</th><th className="text-left p-3">Reported</th><th className="text-right p-3">Actions</th></tr></thead>
            <tbody>{filtered.map((m: any, idx: number) => (
              <tr key={m.hotelMaintenanceRequestId ?? m.hotelmaintenancerequestid ?? `mt-${idx}`} className="border-b hover:bg-slate-50">
                <td className="p-3 font-semibold">{m.roomNumber ?? m.roomnumber ?? "General"}</td>
                <td className="p-3">{m.assetDescription ?? m.assetdescription}</td>
                <td className="p-3 max-w-[250px]">{m.issueDescription ?? m.issuedescription}</td>
                <td className="p-3"><Badge variant="outline" className={PRIORITY_COLOR[m.priority] ?? ""}>{m.priority}</Badge></td>
                <td className="p-3"><Badge variant="outline" className={STATUS_COLOR[m.status] ?? ""}>{m.status}</Badge></td>
                <td className="p-3 text-right">GH₵{Number(m.estimatedCost ?? m.estimatedcost ?? 0).toFixed(2)}</td>
                <td className="p-3 text-xs text-slate-500">{(m.reportedAt ?? m.reportedat ?? m.createdat)?.slice?.(0, 10)}</td>
                <td className="p-3 text-right">
                  <Select onValueChange={(v) => changeStatus(m.hotelMaintenanceRequestId ?? m.hotelmaintenancerequestid, v)}>
                    <SelectTrigger className="w-[110px] h-8 text-xs"><SelectValue placeholder="Change..." /></SelectTrigger>
                    <SelectContent>{STATUSES.filter(s => s !== m.status).map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                  </Select>
                </td>
              </tr>
            ))}
              {filtered.length === 0 && <tr><td colSpan={8} className="p-8 text-center text-slate-400">No maintenance requests.</td></tr>}
            </tbody></table></CardContent></Card>
        )}

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>New Maintenance Request</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Room (optional)</Label>
              <Select value={form.hotelRoomId ? String(form.hotelRoomId) : "__general__"} onValueChange={(v) => setForm({...form, hotelRoomId: v === "__general__" ? null : Number(v)})}>
                <SelectTrigger><SelectValue placeholder="Select room" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__general__">General / Common Area</SelectItem>
                  {rooms.map((r) => <SelectItem key={r.hotelRoomId} value={String(r.hotelRoomId)}>Room {r.roomNumber} — {r.floorName ?? ""} ({r.roomTypeName})</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div><Label>Asset / Area *</Label><Input value={form.assetDescription} onChange={(e) => setForm({...form, assetDescription: e.target.value})} placeholder="e.g. Air Conditioner, Bathroom pipe, Elevator" /></div>
            <div><Label>Issue Description *</Label><Input value={form.issueDescription} onChange={(e) => setForm({...form, issueDescription: e.target.value})} placeholder="Describe the problem in detail" /></div>
            <div className="grid grid-cols-2 gap-4">
              <div><Label>Priority</Label><Select value={form.priority} onValueChange={(v) => setForm({...form, priority: v})}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="Low">Low</SelectItem><SelectItem value="Normal">Normal</SelectItem><SelectItem value="High">High</SelectItem><SelectItem value="Critical">Critical</SelectItem></SelectContent></Select></div>
              <div><Label>Estimated Cost (GH₵)</Label><Input type="number" step="0.01" value={form.estimatedCost} onChange={(e) => setForm({...form, estimatedCost: Number(e.target.value)})} /></div>
            </div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Submit Request</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}

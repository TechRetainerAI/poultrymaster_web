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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Loader2, Plus, LayoutGrid, List, Building2, DoorOpen, Users, Sparkles, Wrench, Calendar } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { RoomGrid } from "@/components/hotel/room-grid"
import { RoomStatusBadge } from "@/components/hotel/room-status-badge"
import {
  listHotelRooms, listHotelRoomTypes, listHotelFloors, getHotelRoomStatusSummary,
  createHotelRoom, updateHotelRoom, deleteHotelRoom, updateHotelRoomStatus,
  type HotelRoom, type HotelRoomType, type HotelFloor, type HotelRoomInput, type HotelRoomStatusType, type HotelRoomStatusSummary,
} from "@/lib/api/hotel"

export default function HotelRoomsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [rooms, setRooms] = useState<HotelRoom[]>([])
  const [roomTypes, setRoomTypes] = useState<HotelRoomType[]>([])
  const [floors, setFloors] = useState<HotelFloor[]>([])
  const [statusSummary, setStatusSummary] = useState<HotelRoomStatusSummary[]>([])
  const [loading, setLoading] = useState(true)
  const [view, setView] = useState<"grid" | "list">("grid")
  const [filterStatus, setFilterStatus] = useState<string>("all")
  const [filterFloor, setFilterFloor] = useState<string>("all")
  const [filterType, setFilterType] = useState<string>("all")
  const [searchQuery, setSearchQuery] = useState("")

  // Dialog state
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<HotelRoom | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<HotelRoomInput>({
    roomNumber: "", hotelRoomTypeId: 0, hotelFloorId: null, description: "", isActive: true,
  })

  // Detail dialog
  const [detailRoom, setDetailRoom] = useState<HotelRoom | null>(null)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    loadData()
  }, [activeFarmType, router])

  async function loadData() {
    setLoading(true)
    try {
      const [r, rt, fl, ss] = await Promise.all([listHotelRooms(), listHotelRoomTypes(), listHotelFloors(), getHotelRoomStatusSummary()])
      setRooms(r); setRoomTypes(rt); setFloors(fl); setStatusSummary(ss)
    } catch (e: any) {
      toast({ title: "Failed to load rooms", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  function openCreate() {
    setEditing(null)
    setForm({ roomNumber: "", hotelRoomTypeId: roomTypes[0]?.hotelRoomTypeId ?? 0, hotelFloorId: floors[0]?.hotelFloorId ?? null, description: "", isActive: true })
    setDialogOpen(true)
  }

  function openEdit(room: HotelRoom) {
    setEditing(room)
    setForm({ roomNumber: room.roomNumber, hotelRoomTypeId: room.hotelRoomTypeId, hotelFloorId: room.hotelFloorId, description: room.description ?? "", isActive: room.isActive })
    setDialogOpen(true)
  }

  async function handleSave() {
    if (!form.roomNumber.trim()) { toast({ title: "Room number is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) { await updateHotelRoom(editing.hotelRoomId, form); toast({ title: "Room updated" }) }
      else { await createHotelRoom(form); toast({ title: "Room created" }) }
      setDialogOpen(false); await loadData()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function handleDelete(room: HotelRoom) {
    if (!confirm(`Delete room ${room.roomNumber}?`)) return
    try { await deleteHotelRoom(room.hotelRoomId); toast({ title: "Room deleted" }); await loadData() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  async function handleStatusChange(room: HotelRoom, status: HotelRoomStatusType) {
    try { await updateHotelRoomStatus(room.hotelRoomId, status); toast({ title: `Room ${room.roomNumber} → ${status}` }); await loadData() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const sc = (s: string) => statusSummary.find((x) => (x.status ?? (x as any).Status) === s)?.roomCount ?? (statusSummary.find((x) => (x as any).Status === s) as any)?.RoomCount ?? 0
  const totalRooms = rooms.length
  const occupancyRate = totalRooms > 0 ? Math.round((sc("Occupied") / totalRooms) * 100) : 0

  const filtered = rooms.filter((r) => {
    if (filterStatus !== "all" && r.status !== filterStatus) return false
    if (filterFloor !== "all" && String(r.floorNumber ?? 0) !== filterFloor) return false
    if (filterType !== "all" && String(r.hotelRoomTypeId) !== filterType) return false
    if (searchQuery) {
      const q = searchQuery.toLowerCase()
      if (!r.roomNumber.toLowerCase().includes(q) && !(r.roomTypeName ?? "").toLowerCase().includes(q)) return false
    }
    return true
  })

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Header */}
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-3">
              <Building2 className="h-6 w-6 text-violet-600" />
              <h1 className="text-2xl font-bold text-slate-900">Room Inventory</h1>
            </div>
            <div className="flex items-center gap-2">
              <Button variant={view === "grid" ? "default" : "outline"} size="icon" onClick={() => setView("grid")} className={view === "grid" ? "bg-violet-600" : ""}><LayoutGrid className="h-4 w-4" /></Button>
              <Button variant={view === "list" ? "default" : "outline"} size="icon" onClick={() => setView("list")} className={view === "list" ? "bg-violet-600" : ""}><List className="h-4 w-4" /></Button>
              <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Room</Button>
            </div>
          </div>

          {/* Status Summary Cards */}
          <div className="grid grid-cols-3 md:grid-cols-6 gap-3 mb-4">
            <Card className="cursor-pointer hover:shadow-md" onClick={() => setFilterStatus("all")}><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-violet-700">{totalRooms}</div><div className="text-xs text-slate-500">Total</div></CardContent></Card>
            <Card className="cursor-pointer hover:shadow-md border-emerald-200" onClick={() => setFilterStatus("Available")}><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-emerald-700">{sc("Available")}</div><div className="text-xs text-slate-500">Available</div></CardContent></Card>
            <Card className="cursor-pointer hover:shadow-md border-violet-200" onClick={() => setFilterStatus("Occupied")}><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-violet-700">{sc("Occupied")}</div><div className="text-xs text-slate-500">Occupied</div></CardContent></Card>
            <Card className="cursor-pointer hover:shadow-md border-blue-200" onClick={() => setFilterStatus("Reserved")}><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-blue-700">{sc("Reserved")}</div><div className="text-xs text-slate-500">Reserved</div></CardContent></Card>
            <Card className="cursor-pointer hover:shadow-md border-orange-200" onClick={() => setFilterStatus("Cleaning")}><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-orange-700">{sc("Cleaning")}</div><div className="text-xs text-slate-500">Cleaning</div></CardContent></Card>
            <Card className="cursor-pointer hover:shadow-md border-amber-200" onClick={() => setFilterStatus("Maintenance")}><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-amber-700">{sc("Maintenance")}</div><div className="text-xs text-slate-500">Maintenance</div></CardContent></Card>
          </div>

          {/* Occupancy bar */}
          <div className="mb-4 p-3 bg-white rounded-lg border">
            <div className="flex items-center justify-between mb-1">
              <span className="text-sm font-medium text-slate-700">Occupancy Rate</span>
              <span className="text-sm font-bold text-violet-700">{occupancyRate}%</span>
            </div>
            <div className="w-full bg-slate-200 rounded-full h-3">
              <div className="bg-violet-600 h-3 rounded-full transition-all" style={{ width: `${occupancyRate}%` }} />
            </div>
          </div>

          {/* Filters */}
          <div className="flex gap-3 mb-4 flex-wrap">
            <Input placeholder="Search room number..." className="max-w-[180px]" value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
            <Select value={filterStatus} onValueChange={setFilterStatus}>
              <SelectTrigger className="w-[140px]"><SelectValue placeholder="All statuses" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All statuses</SelectItem>
                <SelectItem value="Available">Available</SelectItem>
                <SelectItem value="Occupied">Occupied</SelectItem>
                <SelectItem value="Reserved">Reserved</SelectItem>
                <SelectItem value="Cleaning">Cleaning</SelectItem>
                <SelectItem value="Maintenance">Maintenance</SelectItem>
              </SelectContent>
            </Select>
            <Select value={filterFloor} onValueChange={setFilterFloor}>
              <SelectTrigger className="w-[140px]"><SelectValue placeholder="All floors" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All floors</SelectItem>
                {floors.map((f) => <SelectItem key={f.hotelFloorId} value={String(f.floorNumber)}>{f.name}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={filterType} onValueChange={setFilterType}>
              <SelectTrigger className="w-[140px]"><SelectValue placeholder="All types" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All types</SelectItem>
                {roomTypes.map((rt) => <SelectItem key={rt.hotelRoomTypeId} value={String(rt.hotelRoomTypeId)}>{rt.name}</SelectItem>)}
              </SelectContent>
            </Select>
            <span className="text-sm text-slate-400 self-center">{filtered.length} room(s)</span>
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : view === "grid" ? (
            <RoomGrid rooms={filtered} onRoomClick={(r) => setDetailRoom(r)} />
          ) : (
            <Card>
              <CardContent className="p-0">
                <table className="w-full text-sm">
                  <thead className="bg-slate-50 border-b">
                    <tr>
                      <th className="text-left p-3">Room</th>
                      <th className="text-left p-3">Type</th>
                      <th className="text-left p-3">Floor</th>
                      <th className="text-left p-3">Bed</th>
                      <th className="text-left p-3">Max Guests</th>
                      <th className="text-right p-3">Rate (GH₵)</th>
                      <th className="text-left p-3">Status</th>
                      <th className="text-right p-3">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.map((room) => (
                      <tr key={room.hotelRoomId} className="border-b hover:bg-slate-50 cursor-pointer" onClick={() => setDetailRoom(room)}>
                        <td className="p-3 font-bold text-violet-700">{room.roomNumber}</td>
                        <td className="p-3">{room.roomTypeName}</td>
                        <td className="p-3">{room.floorName ?? "—"}</td>
                        <td className="p-3">{room.bedType ?? "—"}</td>
                        <td className="p-3 text-center">{room.maxOccupancy ?? "—"}</td>
                        <td className="p-3 text-right font-semibold">GH₵{Number(room.baseRate ?? 0).toFixed(2)}</td>
                        <td className="p-3"><RoomStatusBadge status={room.status} /></td>
                        <td className="p-3 text-right space-x-1" onClick={(e) => e.stopPropagation()}>
                          <Button variant="ghost" size="sm" onClick={() => openEdit(room)}>Edit</Button>
                          <Button variant="ghost" size="sm" className="text-red-600" onClick={() => handleDelete(room)}>Delete</Button>
                        </td>
                      </tr>
                    ))}
                    {filtered.length === 0 && (
                      <tr><td colSpan={8} className="p-8 text-center text-slate-400">No rooms match the filters.</td></tr>
                    )}
                  </tbody>
                </table>
              </CardContent>
            </Card>
          )}

          {/* Room Detail Dialog */}
          <Dialog open={!!detailRoom} onOpenChange={() => setDetailRoom(null)}>
            <DialogContent className="max-w-md">
              <DialogHeader><DialogTitle>Room {detailRoom?.roomNumber}</DialogTitle></DialogHeader>
              {detailRoom && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <RoomStatusBadge status={detailRoom.status} />
                    <span className="text-lg font-bold text-violet-700">GH₵{Number(detailRoom.baseRate ?? 0).toFixed(2)}/night</span>
                  </div>
                  <div className="grid grid-cols-2 gap-3 text-sm">
                    <div><span className="text-slate-500">Type:</span> <strong>{detailRoom.roomTypeName}</strong></div>
                    <div><span className="text-slate-500">Floor:</span> <strong>{detailRoom.floorName ?? "—"}</strong></div>
                    <div><span className="text-slate-500">Bed:</span> <strong>{detailRoom.bedType ?? "—"}</strong></div>
                    <div><span className="text-slate-500">Max Guests:</span> <strong>{detailRoom.maxOccupancy ?? "—"}</strong></div>
                  </div>
                  {detailRoom.description && <div className="text-sm text-slate-500">{detailRoom.description}</div>}

                  <div className="border-t pt-3">
                    <Label className="text-xs text-slate-500 uppercase">Change Status</Label>
                    <div className="flex gap-2 flex-wrap mt-2">
                      {(["Available", "Occupied", "Reserved", "Cleaning", "Maintenance"] as HotelRoomStatusType[]).filter(s => s !== detailRoom.status).map(s => (
                        <Button key={s} variant="outline" size="sm" onClick={async () => { await handleStatusChange(detailRoom, s); setDetailRoom(null) }}>{s}</Button>
                      ))}
                    </div>
                  </div>

                  <div className="flex gap-2 border-t pt-3">
                    <Button variant="outline" className="flex-1" onClick={() => { setDetailRoom(null); openEdit(detailRoom) }}>Edit Room</Button>
                    <Button variant="outline" className="flex-1 text-red-600" onClick={() => { setDetailRoom(null); handleDelete(detailRoom) }}>Delete</Button>
                  </div>
                </div>
              )}
            </DialogContent>
          </Dialog>

          {/* Create/Edit Dialog */}
          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>{editing ? `Edit Room ${editing.roomNumber}` : "Add Room"}</DialogTitle>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label>Room Number *</Label>
                  <Input value={form.roomNumber} onChange={(e) => setForm({ ...form, roomNumber: e.target.value })} placeholder="e.g. 101, A1" />
                </div>
                <div>
                  <Label>Room Type *</Label>
                  <Select value={String(form.hotelRoomTypeId)} onValueChange={(v) => setForm({ ...form, hotelRoomTypeId: Number(v) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {roomTypes.map((rt) => <SelectItem key={rt.hotelRoomTypeId} value={String(rt.hotelRoomTypeId)}>{rt.name} — GH₵{rt.baseRate} ({rt.bedType ?? "Standard"})</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Floor</Label>
                  <Select value={String(form.hotelFloorId ?? "")} onValueChange={(v) => setForm({ ...form, hotelFloorId: v ? Number(v) : null })}>
                    <SelectTrigger><SelectValue placeholder="Select floor" /></SelectTrigger>
                    <SelectContent>
                      {floors.map((f) => <SelectItem key={f.hotelFloorId} value={String(f.hotelFloorId)}>{f.name} (Floor {f.floorNumber})</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Description</Label>
                  <Input value={form.description ?? ""} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="Corner room, ocean view, etc." />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
                <Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                  {saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
                  {editing ? "Update" : "Create"}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

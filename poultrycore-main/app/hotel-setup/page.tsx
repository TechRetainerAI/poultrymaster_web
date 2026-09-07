"use client"

import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Plus, Settings, Trash2, Edit2, CalendarDays, DoorOpen, Search } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getHotelProfile, upsertHotelProfile,
  listHotelRoomCategories, listHotelBedTypes,
  listHotelRoomTypes, createHotelRoomType, updateHotelRoomType, deleteHotelRoomType,
  listHotelFloors, createHotelFloor, updateHotelFloor, deleteHotelFloor,
  listHotelAmenities, createHotelAmenity, updateHotelAmenity, deleteHotelAmenity,
  listRoomRates, createRoomRate, deleteRoomRate,
  listHotelRooms, createHotelRoom, updateHotelRoom, deleteHotelRoom,
  type HotelProfile, type HotelProfileInput, type HotelRoomCategory, type HotelBedType,
  type HotelRoomType, type HotelRoomTypeInput,
  type HotelFloor, type HotelFloorInput, type HotelAmenity, type HotelAmenityInput,
  type HotelRoomRate, type HotelRoom, type HotelRoomInput,
} from "@/lib/api/hotel"

export default function HotelSetupPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [profile, setProfile] = useState<HotelProfileInput>({ hotelName: "" })
  const [roomCategories, setRoomCategories] = useState<HotelRoomCategory[]>([])
  const [bedTypes, setBedTypes] = useState<HotelBedType[]>([])
  const [roomTypes, setRoomTypes] = useState<HotelRoomType[]>([])
  const [floors, setFloors] = useState<HotelFloor[]>([])
  const [amenities, setAmenities] = useState<HotelAmenity[]>([])
  const [rooms, setRooms] = useState<HotelRoom[]>([])

  // Room Type dialog
  const [rtDialogOpen, setRtDialogOpen] = useState(false)
  const [rtEditing, setRtEditing] = useState<HotelRoomType | null>(null)
  const [rtForm, setRtForm] = useState<HotelRoomTypeInput>({ name: "", baseRate: 0, maxOccupancy: 2, hotelRoomCategoryId: null, hotelBedTypeId: null })

  // Floor dialog
  const [flDialogOpen, setFlDialogOpen] = useState(false)
  const [flEditing, setFlEditing] = useState<HotelFloor | null>(null)
  const [flForm, setFlForm] = useState<HotelFloorInput>({ floorNumber: 1, name: "" })

  // Amenity dialog
  const [amDialogOpen, setAmDialogOpen] = useState(false)
  const [amEditing, setAmEditing] = useState<HotelAmenity | null>(null)
  const [amForm, setAmForm] = useState<HotelAmenityInput>({ name: "", category: "" })

  // Room Rates
  const [rates, setRates] = useState<HotelRoomRate[]>([])
  const [rateDialogOpen, setRateDialogOpen] = useState(false)
  const [rateForm, setRateForm] = useState({ hotelRoomTypeId: 0, rateName: "", rate: 0, startDate: "", endDate: "", isWeekend: false })

  // Filters
  const [rtSearch, setRtSearch] = useState("")
  const [rtCatFilter, setRtCatFilter] = useState("all")
  const [rtBedFilter, setRtBedFilter] = useState("all")
  const [rmSearch, setRmSearch] = useState("")
  const [rmTypeFilter, setRmTypeFilter] = useState("all")
  const [rmFloorFilter, setRmFloorFilter] = useState("all")
  const [rmStatusFilter, setRmStatusFilter] = useState("all")
  const [flSearch, setFlSearch] = useState("")
  const [amSearch, setAmSearch] = useState("")
  const [amCatFilter, setAmCatFilter] = useState("all")
  const [rateSearch, setRateSearch] = useState("")
  const [rateTypeFilter, setRateTypeFilter] = useState("all")
  const [rateStatusFilter, setRateStatusFilter] = useState("all")
  const [rateWeekendFilter, setRateWeekendFilter] = useState("all")

  // Filtered lists
  const filteredRoomTypes = useMemo(() => roomTypes.filter(rt => {
    if (rtSearch && !rt.name.toLowerCase().includes(rtSearch.toLowerCase()) && !(rt.description ?? "").toLowerCase().includes(rtSearch.toLowerCase())) return false
    if (rtCatFilter !== "all" && String(rt.hotelRoomCategoryId ?? "") !== rtCatFilter) return false
    if (rtBedFilter !== "all" && String(rt.hotelBedTypeId ?? "") !== rtBedFilter) return false
    return true
  }), [roomTypes, rtSearch, rtCatFilter, rtBedFilter])

  const filteredRooms = useMemo(() => rooms.filter(rm => {
    if (rmSearch && !rm.roomNumber.toLowerCase().includes(rmSearch.toLowerCase()) && !(rm.roomTypeName ?? "").toLowerCase().includes(rmSearch.toLowerCase())) return false
    if (rmTypeFilter !== "all" && String(rm.hotelRoomTypeId) !== rmTypeFilter) return false
    if (rmFloorFilter !== "all" && String(rm.hotelFloorId ?? "") !== rmFloorFilter) return false
    if (rmStatusFilter !== "all" && rm.status !== rmStatusFilter) return false
    return true
  }), [rooms, rmSearch, rmTypeFilter, rmFloorFilter, rmStatusFilter])

  const filteredFloors = useMemo(() => floors.filter(f => {
    if (flSearch && !f.name.toLowerCase().includes(flSearch.toLowerCase()) && !String(f.floorNumber).includes(flSearch)) return false
    return true
  }), [floors, flSearch])

  const amenityCategories = useMemo(() => [...new Set(amenities.map(a => a.category).filter(Boolean))], [amenities])
  const filteredAmenities = useMemo(() => amenities.filter(a => {
    if (amSearch && !a.name.toLowerCase().includes(amSearch.toLowerCase())) return false
    if (amCatFilter !== "all" && (a.category ?? "") !== amCatFilter) return false
    return true
  }), [amenities, amSearch, amCatFilter])

  const filteredRates = useMemo(() => {
    const now = new Date().toISOString().slice(0, 10)
    return rates.filter((r: any) => {
      const name = (r.ratename ?? r.rateName ?? "").toLowerCase()
      const rtName = r.roomtypename ?? r.roomTypeName ?? ""
      if (rateSearch && !name.includes(rateSearch.toLowerCase()) && !rtName.toLowerCase().includes(rateSearch.toLowerCase())) return false
      if (rateTypeFilter !== "all") {
        const rtId = String(r.hotelroomtypeid ?? r.hotelRoomTypeId ?? "")
        if (rtId !== rateTypeFilter) return false
      }
      if (rateWeekendFilter !== "all") {
        const isW = r.isweekend ?? r.isWeekend ?? false
        if (rateWeekendFilter === "weekend" && !isW) return false
        if (rateWeekendFilter === "weekday" && isW) return false
      }
      if (rateStatusFilter !== "all") {
        const start = (r.startdate ?? r.startDate ?? "").slice(0, 10)
        const end = (r.enddate ?? r.endDate ?? "").slice(0, 10)
        const isCurrent = start <= now && end >= now
        const isExpired = end < now
        if (rateStatusFilter === "active" && !isCurrent) return false
        if (rateStatusFilter === "expired" && !isExpired) return false
        if (rateStatusFilter === "upcoming" && (isCurrent || isExpired)) return false
      }
      return true
    })
  }, [rates, rateSearch, rateTypeFilter, rateStatusFilter, rateWeekendFilter])

  // Rooms dialog
  const [rmDialogOpen, setRmDialogOpen] = useState(false)
  const [rmEditing, setRmEditing] = useState<HotelRoom | null>(null)
  const [rmForm, setRmForm] = useState<HotelRoomInput>({ roomNumber: "", hotelRoomTypeId: 0, hotelFloorId: null, description: "", isActive: true })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [p, rc, bt, rt, fl, am, rr, rm] = await Promise.all([
        getHotelProfile().catch(() => null),
        listHotelRoomCategories().catch(() => []),
        listHotelBedTypes().catch(() => []),
        listHotelRoomTypes(),
        listHotelFloors(),
        listHotelAmenities(),
        listRoomRates().catch(() => []),
        listHotelRooms().catch(() => []),
      ])
      if (p) setProfile(p)
      setRoomCategories(rc)
      setBedTypes(bt)
      setRoomTypes(rt)
      setFloors(fl)
      setAmenities(am)
      setRates(rr)
      setRooms(rm)
    } catch (e: any) {
      toast({ title: "Failed to load setup", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  // ----- Profile -----
  async function saveProfile() {
    if (!profile.hotelName?.trim()) { toast({ title: "Hotel name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await upsertHotelProfile(profile)
      toast({ title: "Profile saved" })
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  // ----- Room Types -----
  async function saveRoomType() {
    setSaving(true)
    try {
      if (rtEditing) await updateHotelRoomType(rtEditing.hotelRoomTypeId, rtForm)
      else await createHotelRoomType(rtForm)
      setRtDialogOpen(false)
      toast({ title: rtEditing ? "Room type updated" : "Room type created" })
      const rt = await listHotelRoomTypes(); setRoomTypes(rt)
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  // ----- Floors -----
  async function saveFloor() {
    setSaving(true)
    try {
      if (flEditing) await updateHotelFloor(flEditing.hotelFloorId, flForm)
      else await createHotelFloor(flForm)
      setFlDialogOpen(false)
      toast({ title: flEditing ? "Floor updated" : "Floor created" })
      const fl = await listHotelFloors(); setFloors(fl)
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  // ----- Amenities -----
  async function saveAmenity() {
    setSaving(true)
    try {
      if (amEditing) await updateHotelAmenity(amEditing.hotelAmenityId, amForm)
      else await createHotelAmenity(amForm)
      setAmDialogOpen(false)
      toast({ title: amEditing ? "Amenity updated" : "Amenity created" })
      const am = await listHotelAmenities(); setAmenities(am)
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  // ----- Room Rates -----
  async function saveRate() {
    if (!rateForm.rateName?.trim() || !rateForm.startDate || !rateForm.endDate || !rateForm.hotelRoomTypeId) {
      toast({ title: "Please fill all required fields", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      await createRoomRate(rateForm)
      setRateDialogOpen(false)
      toast({ title: "Rate created" })
      setRates(await listRoomRates())
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  async function handleDeleteRate(id: number) {
    if (!confirm("Delete this rate?")) return
    try {
      await deleteRoomRate(id)
      toast({ title: "Rate deleted" })
      setRates(await listRoomRates())
    } catch (e: any) {
      toast({ title: "Delete failed", description: e?.message, variant: "destructive" })
    }
  }

  // ----- Rooms -----
  async function saveRoom() {
    if (!rmForm.roomNumber.trim()) { toast({ title: "Room number is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (rmEditing) { await updateHotelRoom(rmEditing.hotelRoomId, rmForm); toast({ title: "Room updated" }) }
      else { await createHotelRoom(rmForm); toast({ title: "Room created" }) }
      setRmDialogOpen(false)
      setRooms(await listHotelRooms())
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  if (loading) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Settings className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold text-slate-900">Hotel Setup</h1>
          </div>

          <Tabs defaultValue="profile" className="space-y-4">
            <TabsList className="flex-wrap">
              <TabsTrigger value="profile">Profile</TabsTrigger>
              <TabsTrigger value="room-types">Room Types ({roomTypes.length})</TabsTrigger>
              <TabsTrigger value="rooms">Rooms ({rooms.length})</TabsTrigger>
              <TabsTrigger value="floors">Floors ({floors.length})</TabsTrigger>
              <TabsTrigger value="amenities">Amenities ({amenities.length})</TabsTrigger>
              <TabsTrigger value="rates">Rates ({rates.length})</TabsTrigger>
            </TabsList>

            {/* PROFILE TAB */}
            <TabsContent value="profile">
              <Card>
                <CardHeader><CardTitle>Hotel Profile</CardTitle></CardHeader>
                <CardContent className="space-y-4 max-w-xl">
                  <div><Label>Hotel Name</Label><Input value={profile.hotelName ?? ""} onChange={(e) => setProfile({ ...profile, hotelName: e.target.value })} /></div>
                  <div className="grid grid-cols-2 gap-4">
                    <div><Label>Phone</Label><Input value={profile.phone ?? ""} onChange={(e) => setProfile({ ...profile, phone: e.target.value })} /></div>
                    <div><Label>Email</Label><Input value={profile.email ?? ""} onChange={(e) => setProfile({ ...profile, email: e.target.value })} /></div>
                  </div>
                  <div><Label>Address</Label><Input value={profile.address ?? ""} onChange={(e) => setProfile({ ...profile, address: e.target.value })} /></div>
                  <div className="grid grid-cols-2 gap-4">
                    <div><Label>City</Label><Input value={profile.city ?? ""} onChange={(e) => setProfile({ ...profile, city: e.target.value })} /></div>
                    <div><Label>Country</Label><Input value={profile.country ?? ""} onChange={(e) => setProfile({ ...profile, country: e.target.value })} /></div>
                  </div>
                  <div className="grid grid-cols-3 gap-4">
                    <div><Label>Star Rating</Label><Input type="number" min={1} max={5} value={profile.starRating ?? ""} onChange={(e) => setProfile({ ...profile, starRating: e.target.value ? Number(e.target.value) : null })} /></div>
                    <div><Label>Check-in Time</Label><Input value={profile.checkInTime ?? "14:00"} onChange={(e) => setProfile({ ...profile, checkInTime: e.target.value })} /></div>
                    <div><Label>Check-out Time</Label><Input value={profile.checkOutTime ?? "12:00"} onChange={(e) => setProfile({ ...profile, checkOutTime: e.target.value })} /></div>
                  </div>
                  <div className="grid grid-cols-3 gap-4">
                    <div><Label>Currency</Label><Input value={profile.defaultCurrency ?? "GHS"} onChange={(e) => setProfile({ ...profile, defaultCurrency: e.target.value })} /></div>
                    <div><Label>Tax Rate (%)</Label><Input type="number" step="0.01" value={profile.taxRate ?? 0} onChange={(e) => setProfile({ ...profile, taxRate: Number(e.target.value) })} /></div>
                    <div><Label>Service Charge (%)</Label><Input type="number" step="0.01" value={profile.serviceChargeRate ?? 0} onChange={(e) => setProfile({ ...profile, serviceChargeRate: Number(e.target.value) })} /></div>
                  </div>
                  <Button onClick={saveProfile} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                    {saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Save Profile
                  </Button>
                </CardContent>
              </Card>
            </TabsContent>

            {/* ROOM TYPES TAB */}
            <TabsContent value="room-types">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between">
                  <CardTitle>Room Types</CardTitle>
                  <Button size="sm" onClick={() => { setRtEditing(null); setRtForm({ name: "", baseRate: 0, maxOccupancy: 2, hotelRoomCategoryId: null, hotelBedTypeId: null }); setRtDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add</Button>
                </CardHeader>
                <CardContent>
                  <div className="flex gap-2 flex-wrap mb-4">
                    <div className="relative"><Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search..." className="pl-8 w-[160px]" value={rtSearch} onChange={(e) => setRtSearch(e.target.value)} /></div>
                    <Select value={rtCatFilter} onValueChange={setRtCatFilter}><SelectTrigger className="w-[160px]"><SelectValue placeholder="All categories" /></SelectTrigger><SelectContent><SelectItem value="all">All categories</SelectItem>{roomCategories.map(c => <SelectItem key={c.hotelRoomCategoryId} value={String(c.hotelRoomCategoryId)}>{c.description}</SelectItem>)}</SelectContent></Select>
                    <Select value={rtBedFilter} onValueChange={setRtBedFilter}><SelectTrigger className="w-[150px]"><SelectValue placeholder="All bed types" /></SelectTrigger><SelectContent><SelectItem value="all">All bed types</SelectItem>{bedTypes.map(b => <SelectItem key={b.hotelBedTypeId} value={String(b.hotelBedTypeId)}>{b.description}</SelectItem>)}</SelectContent></Select>
                    <span className="text-sm text-slate-400 self-center">{filteredRoomTypes.length} of {roomTypes.length}</span>
                  </div>
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Category</th><th className="text-left p-3">Name</th><th className="text-left p-3">Base Rate</th><th className="text-left p-3">Max Guests</th><th className="text-left p-3">Bed Type</th><th className="text-right p-3">Actions</th></tr></thead>
                    <tbody>
                      {filteredRoomTypes.map((rt) => (
                        <tr key={rt.hotelRoomTypeId} className="border-b">
                          <td className="p-3"><Badge variant="outline" className="bg-violet-50 text-violet-700">{rt.categoryName ?? "—"}</Badge></td>
                          <td className="p-3 font-medium">{rt.name}</td>
                          <td className="p-3">{rt.baseRate.toFixed(2)}</td>
                          <td className="p-3">{rt.maxOccupancy}</td>
                          <td className="p-3">{rt.bedTypeName ?? rt.bedType ?? "-"}</td>
                          <td className="p-3 text-right space-x-1">
                            <Button variant="ghost" size="icon" onClick={() => { setRtEditing(rt); setRtForm({ ...rt }); setRtDialogOpen(true) }}><Edit2 className="h-4 w-4" /></Button>
                            <Button variant="ghost" size="icon" className="text-red-600" onClick={async () => { if (confirm(`Delete ${rt.name}?`)) { await deleteHotelRoomType(rt.hotelRoomTypeId); setRoomTypes(await listHotelRoomTypes()); toast({ title: "Deleted" }) } }}><Trash2 className="h-4 w-4" /></Button>
                          </td>
                        </tr>
                      ))}
                      {filteredRoomTypes.length === 0 && <tr><td colSpan={6} className="p-8 text-center text-slate-400">{roomTypes.length === 0 ? "No room types yet." : "No room types match filters."}</td></tr>}
                    </tbody>
                  </table>
                </CardContent>
              </Card>
            </TabsContent>

            {/* ROOMS TAB */}
            <TabsContent value="rooms">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between">
                  <div>
                    <CardTitle>Rooms</CardTitle>
                    <p className="text-xs text-slate-500 mt-1">Add individual rooms and assign them to a room type and floor.</p>
                  </div>
                  <Button size="sm" onClick={() => { setRmEditing(null); setRmForm({ roomNumber: "", hotelRoomTypeId: roomTypes[0]?.hotelRoomTypeId ?? 0, hotelFloorId: floors[0]?.hotelFloorId ?? null, description: "", isActive: true }); setRmDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Room</Button>
                </CardHeader>
                <CardContent>
                  <div className="flex gap-2 flex-wrap mb-4">
                    <div className="relative"><Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search room..." className="pl-8 w-[160px]" value={rmSearch} onChange={(e) => setRmSearch(e.target.value)} /></div>
                    <Select value={rmTypeFilter} onValueChange={setRmTypeFilter}><SelectTrigger className="w-[150px]"><SelectValue placeholder="All types" /></SelectTrigger><SelectContent><SelectItem value="all">All types</SelectItem>{roomTypes.map(rt => <SelectItem key={rt.hotelRoomTypeId} value={String(rt.hotelRoomTypeId)}>{rt.name}</SelectItem>)}</SelectContent></Select>
                    <Select value={rmFloorFilter} onValueChange={setRmFloorFilter}><SelectTrigger className="w-[140px]"><SelectValue placeholder="All floors" /></SelectTrigger><SelectContent><SelectItem value="all">All floors</SelectItem>{floors.map(f => <SelectItem key={f.hotelFloorId} value={String(f.hotelFloorId)}>{f.name}</SelectItem>)}</SelectContent></Select>
                    <Select value={rmStatusFilter} onValueChange={setRmStatusFilter}><SelectTrigger className="w-[140px]"><SelectValue placeholder="All statuses" /></SelectTrigger><SelectContent><SelectItem value="all">All statuses</SelectItem><SelectItem value="Available">Available</SelectItem><SelectItem value="Occupied">Occupied</SelectItem><SelectItem value="Reserved">Reserved</SelectItem><SelectItem value="Cleaning">Cleaning</SelectItem><SelectItem value="Maintenance">Maintenance</SelectItem></SelectContent></Select>
                    <span className="text-sm text-slate-400 self-center">{filteredRooms.length} of {rooms.length}</span>
                  </div>
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b">
                      <tr>
                        <th className="text-left p-3">Room #</th>
                        <th className="text-left p-3">Type</th>
                        <th className="text-left p-3">Floor</th>
                        <th className="text-left p-3">Status</th>
                        <th className="text-right p-3">Rate</th>
                        <th className="text-right p-3">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredRooms.map((rm) => (
                        <tr key={rm.hotelRoomId} className="border-b hover:bg-slate-50">
                          <td className="p-3 font-bold text-violet-700">{rm.roomNumber}</td>
                          <td className="p-3">{rm.roomTypeName ?? "—"}</td>
                          <td className="p-3">{rm.floorName ?? "—"}</td>
                          <td className="p-3">
                            <Badge variant="outline" className={
                              rm.status === "Available" ? "bg-emerald-50 text-emerald-700" :
                              rm.status === "Occupied" ? "bg-violet-50 text-violet-700" :
                              rm.status === "Reserved" ? "bg-blue-50 text-blue-700" :
                              rm.status === "Cleaning" ? "bg-orange-50 text-orange-700" :
                              "bg-amber-50 text-amber-700"
                            }>{rm.status}</Badge>
                          </td>
                          <td className="p-3 text-right font-semibold">{Number(rm.baseRate ?? 0).toFixed(2)}</td>
                          <td className="p-3 text-right space-x-1">
                            <Button variant="ghost" size="icon" onClick={() => { setRmEditing(rm); setRmForm({ roomNumber: rm.roomNumber, hotelRoomTypeId: rm.hotelRoomTypeId, hotelFloorId: rm.hotelFloorId ?? null, description: rm.description ?? "", isActive: rm.isActive }); setRmDialogOpen(true) }}><Edit2 className="h-4 w-4" /></Button>
                            <Button variant="ghost" size="icon" className="text-red-600" onClick={async () => { if (confirm(`Delete room ${rm.roomNumber}?`)) { await deleteHotelRoom(rm.hotelRoomId); setRooms(await listHotelRooms()); toast({ title: "Deleted" }) } }}><Trash2 className="h-4 w-4" /></Button>
                          </td>
                        </tr>
                      ))}
                      {filteredRooms.length === 0 && <tr><td colSpan={6} className="p-8 text-center text-slate-400"><DoorOpen className="h-8 w-8 mx-auto mb-2 text-slate-300" />{rooms.length === 0 ? "No rooms yet. Add room types and floors first, then create rooms." : "No rooms match filters."}</td></tr>}
                    </tbody>
                  </table>
                </CardContent>
              </Card>
            </TabsContent>

            {/* FLOORS TAB */}
            <TabsContent value="floors">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between">
                  <CardTitle>Floors</CardTitle>
                  <Button size="sm" onClick={() => { setFlEditing(null); setFlForm({ floorNumber: floors.length + 1, name: `Floor ${floors.length + 1}` }); setFlDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add</Button>
                </CardHeader>
                <CardContent>
                  <div className="flex gap-2 mb-4">
                    <div className="relative"><Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search floor..." className="pl-8 w-[200px]" value={flSearch} onChange={(e) => setFlSearch(e.target.value)} /></div>
                    <span className="text-sm text-slate-400 self-center">{filteredFloors.length} of {floors.length}</span>
                  </div>
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">#</th><th className="text-left p-3">Name</th><th className="text-right p-3">Actions</th></tr></thead>
                    <tbody>
                      {filteredFloors.map((f) => (
                        <tr key={f.hotelFloorId} className="border-b">
                          <td className="p-3">{f.floorNumber}</td>
                          <td className="p-3 font-medium">{f.name}</td>
                          <td className="p-3 text-right space-x-1">
                            <Button variant="ghost" size="icon" onClick={() => { setFlEditing(f); setFlForm(f); setFlDialogOpen(true) }}><Edit2 className="h-4 w-4" /></Button>
                            <Button variant="ghost" size="icon" className="text-red-600" onClick={async () => { if (confirm(`Delete ${f.name}?`)) { await deleteHotelFloor(f.hotelFloorId); setFloors(await listHotelFloors()); toast({ title: "Deleted" }) } }}><Trash2 className="h-4 w-4" /></Button>
                          </td>
                        </tr>
                      ))}
                      {filteredFloors.length === 0 && <tr><td colSpan={3} className="p-8 text-center text-slate-400">{floors.length === 0 ? "No floors yet." : "No floors match search."}</td></tr>}
                    </tbody>
                  </table>
                </CardContent>
              </Card>
            </TabsContent>

            {/* AMENITIES TAB */}
            <TabsContent value="amenities">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between">
                  <CardTitle>Amenities</CardTitle>
                  <Button size="sm" onClick={() => { setAmEditing(null); setAmForm({ name: "", category: "" }); setAmDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add</Button>
                </CardHeader>
                <CardContent>
                  <div className="flex gap-2 flex-wrap mb-4">
                    <div className="relative"><Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search amenity..." className="pl-8 w-[180px]" value={amSearch} onChange={(e) => setAmSearch(e.target.value)} /></div>
                    <Select value={amCatFilter} onValueChange={setAmCatFilter}><SelectTrigger className="w-[160px]"><SelectValue placeholder="All categories" /></SelectTrigger><SelectContent><SelectItem value="all">All categories</SelectItem>{amenityCategories.map(c => <SelectItem key={c} value={c!}>{c}</SelectItem>)}</SelectContent></Select>
                    <span className="text-sm text-slate-400 self-center">{filteredAmenities.length} of {amenities.length}</span>
                  </div>
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Name</th><th className="text-left p-3">Category</th><th className="text-right p-3">Actions</th></tr></thead>
                    <tbody>
                      {filteredAmenities.map((a) => (
                        <tr key={a.hotelAmenityId} className="border-b">
                          <td className="p-3 font-medium">{a.name}</td>
                          <td className="p-3">{a.category ?? "-"}</td>
                          <td className="p-3 text-right space-x-1">
                            <Button variant="ghost" size="icon" onClick={() => { setAmEditing(a); setAmForm(a); setAmDialogOpen(true) }}><Edit2 className="h-4 w-4" /></Button>
                            <Button variant="ghost" size="icon" className="text-red-600" onClick={async () => { if (confirm(`Delete ${a.name}?`)) { await deleteHotelAmenity(a.hotelAmenityId); setAmenities(await listHotelAmenities()); toast({ title: "Deleted" }) } }}><Trash2 className="h-4 w-4" /></Button>
                          </td>
                        </tr>
                      ))}
                      {filteredAmenities.length === 0 && <tr><td colSpan={3} className="p-8 text-center text-slate-400">{amenities.length === 0 ? "No amenities yet." : "No amenities match filters."}</td></tr>}
                    </tbody>
                  </table>
                </CardContent>
              </Card>
            </TabsContent>

            {/* RATES TAB */}
            <TabsContent value="rates">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between">
                  <div>
                    <CardTitle>Room Rate Management</CardTitle>
                    <p className="text-xs text-slate-500 mt-1">Define seasonal rates, weekend rates, and special pricing for each room type.</p>
                  </div>
                  <Button size="sm" onClick={() => { setRateForm({ hotelRoomTypeId: roomTypes[0]?.hotelRoomTypeId ?? 0, rateName: "", rate: 0, startDate: "", endDate: "", isWeekend: false }); setRateDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Rate</Button>
                </CardHeader>
                <CardContent>
                  <div className="flex gap-2 flex-wrap mb-4">
                    <div className="relative"><Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search rate..." className="pl-8 w-[160px]" value={rateSearch} onChange={(e) => setRateSearch(e.target.value)} /></div>
                    <Select value={rateTypeFilter} onValueChange={setRateTypeFilter}><SelectTrigger className="w-[150px]"><SelectValue placeholder="All types" /></SelectTrigger><SelectContent><SelectItem value="all">All types</SelectItem>{roomTypes.map(rt => <SelectItem key={rt.hotelRoomTypeId} value={String(rt.hotelRoomTypeId)}>{rt.name}</SelectItem>)}</SelectContent></Select>
                    <Select value={rateStatusFilter} onValueChange={setRateStatusFilter}><SelectTrigger className="w-[130px]"><SelectValue placeholder="All statuses" /></SelectTrigger><SelectContent><SelectItem value="all">All statuses</SelectItem><SelectItem value="active">Active</SelectItem><SelectItem value="expired">Expired</SelectItem><SelectItem value="upcoming">Upcoming</SelectItem></SelectContent></Select>
                    <Select value={rateWeekendFilter} onValueChange={setRateWeekendFilter}><SelectTrigger className="w-[130px]"><SelectValue placeholder="All days" /></SelectTrigger><SelectContent><SelectItem value="all">All days</SelectItem><SelectItem value="weekday">Weekday</SelectItem><SelectItem value="weekend">Weekend</SelectItem></SelectContent></Select>
                    <span className="text-sm text-slate-400 self-center">{filteredRates.length} of {rates.length}</span>
                  </div>
                  {filteredRates.length > 0 ? (
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Rate Name</th>
                          <th className="text-left p-3">Room Type</th>
                          <th className="text-right p-3">Rate</th>
                          <th className="text-left p-3">Start Date</th>
                          <th className="text-left p-3">End Date</th>
                          <th className="text-center p-3">Type</th>
                          <th className="text-center p-3">Status</th>
                          <th className="text-right p-3">Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filteredRates.map((r: any) => {
                          const start = (r.startdate ?? r.startDate ?? "").slice(0, 10)
                          const end = (r.enddate ?? r.endDate ?? "").slice(0, 10)
                          const isWeekend = r.isweekend ?? r.isWeekend ?? false
                          const now = new Date().toISOString().slice(0, 10)
                          const isCurrent = start <= now && end >= now
                          const rtName = r.roomtypename ?? r.roomTypeName ?? roomTypes.find(rt => rt.hotelRoomTypeId === (r.hotelroomtypeid ?? r.hotelRoomTypeId))?.name ?? "—"
                          return (
                            <tr key={r.hotelroomrateid ?? r.hotelRoomRateId} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">{r.ratename ?? r.rateName}</td>
                              <td className="p-3">{rtName}</td>
                              <td className="p-3 text-right font-semibold text-violet-700">{Number(r.rate ?? 0).toFixed(2)}</td>
                              <td className="p-3">{start}</td>
                              <td className="p-3">{end}</td>
                              <td className="p-3 text-center">
                                <Badge variant="outline" className={isWeekend ? "bg-amber-100 text-amber-700" : "bg-blue-100 text-blue-700"}>
                                  {isWeekend ? "Weekend" : "Weekday"}
                                </Badge>
                              </td>
                              <td className="p-3 text-center">
                                <Badge variant="outline" className={isCurrent ? "bg-emerald-100 text-emerald-700" : end < now ? "bg-slate-100 text-slate-500" : "bg-blue-100 text-blue-700"}>
                                  {isCurrent ? "Active" : end < now ? "Expired" : "Upcoming"}
                                </Badge>
                              </td>
                              <td className="p-3 text-right">
                                <Button variant="ghost" size="icon" className="text-red-600" onClick={() => handleDeleteRate(r.hotelroomrateid ?? r.hotelRoomRateId)}>
                                  <Trash2 className="h-4 w-4" />
                                </Button>
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  ) : (
                    <div className="text-center py-8 text-slate-400">
                      <CalendarDays className="h-8 w-8 mx-auto mb-2 text-slate-300" />
                      {rates.length === 0 ? (
                        <><p>No custom rates defined. Room types will use their base rate.</p><p className="text-xs mt-1">Add seasonal rates, weekend rates, or special pricing to override base rates.</p></>
                      ) : (
                        <p>No rates match the current filters.</p>
                      )}
                    </div>
                  )}
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>

          {/* Room Type Dialog */}
          <Dialog open={rtDialogOpen} onOpenChange={setRtDialogOpen}>
            <DialogContent>
              <DialogHeader><DialogTitle>{rtEditing ? "Edit Room Type" : "Add Room Type"}</DialogTitle></DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label>Category *</Label>
                  <Select value={String(rtForm.hotelRoomCategoryId ?? "")} onValueChange={(v) => setRtForm({ ...rtForm, hotelRoomCategoryId: v ? Number(v) : null })}>
                    <SelectTrigger><SelectValue placeholder="Select a room category" /></SelectTrigger>
                    <SelectContent>
                      {roomCategories.map((cat) => (
                        <SelectItem key={cat.hotelRoomCategoryId} value={String(cat.hotelRoomCategoryId)}>
                          {cat.description} ({cat.code})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div><Label>Name</Label><Input value={rtForm.name} onChange={(e) => setRtForm({ ...rtForm, name: e.target.value })} placeholder="e.g. Deluxe Double" /></div>
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>Base Rate</Label><Input type="number" step="0.01" value={rtForm.baseRate} onChange={(e) => setRtForm({ ...rtForm, baseRate: Number(e.target.value) })} /></div>
                  <div><Label>Max Occupancy</Label><Input type="number" min={1} value={rtForm.maxOccupancy ?? 2} onChange={(e) => setRtForm({ ...rtForm, maxOccupancy: Number(e.target.value) })} /></div>
                </div>
                <div>
                  <Label>Bed Type</Label>
                  <Select value={String(rtForm.hotelBedTypeId ?? "")} onValueChange={(v) => setRtForm({ ...rtForm, hotelBedTypeId: v ? Number(v) : null })}>
                    <SelectTrigger><SelectValue placeholder="Select a bed type" /></SelectTrigger>
                    <SelectContent>
                      {bedTypes.map((bt) => (
                        <SelectItem key={bt.hotelBedTypeId} value={String(bt.hotelBedTypeId)}>
                          {bt.description}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div><Label>Description</Label><Input value={rtForm.description ?? ""} onChange={(e) => setRtForm({ ...rtForm, description: e.target.value })} /></div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setRtDialogOpen(false)}>Cancel</Button>
                <Button onClick={saveRoomType} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{rtEditing ? "Update" : "Create"}</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Room Dialog */}
          <Dialog open={rmDialogOpen} onOpenChange={setRmDialogOpen}>
            <DialogContent>
              <DialogHeader><DialogTitle>{rmEditing ? `Edit Room ${rmEditing.roomNumber}` : "Add Room"}</DialogTitle></DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label>Room Number *</Label>
                  <Input value={rmForm.roomNumber} onChange={(e) => setRmForm({ ...rmForm, roomNumber: e.target.value })} placeholder="e.g. 101, A1" />
                </div>
                <div>
                  <Label>Room Type *</Label>
                  <Select value={String(rmForm.hotelRoomTypeId)} onValueChange={(v) => setRmForm({ ...rmForm, hotelRoomTypeId: Number(v) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {roomTypes.map((rt) => <SelectItem key={rt.hotelRoomTypeId} value={String(rt.hotelRoomTypeId)}>{rt.name} — {rt.baseRate.toFixed(2)}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Floor</Label>
                  <Select value={String(rmForm.hotelFloorId ?? "")} onValueChange={(v) => setRmForm({ ...rmForm, hotelFloorId: v ? Number(v) : null })}>
                    <SelectTrigger><SelectValue placeholder="Select floor" /></SelectTrigger>
                    <SelectContent>
                      {floors.map((f) => <SelectItem key={f.hotelFloorId} value={String(f.hotelFloorId)}>{f.name} (Floor {f.floorNumber})</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Description</Label>
                  <Input value={rmForm.description ?? ""} onChange={(e) => setRmForm({ ...rmForm, description: e.target.value })} placeholder="Corner room, ocean view, etc." />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setRmDialogOpen(false)}>Cancel</Button>
                <Button onClick={saveRoom} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                  {saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
                  {rmEditing ? "Update" : "Create"}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Floor Dialog */}
          <Dialog open={flDialogOpen} onOpenChange={setFlDialogOpen}>
            <DialogContent>
              <DialogHeader><DialogTitle>{flEditing ? "Edit Floor" : "Add Floor"}</DialogTitle></DialogHeader>
              <div className="space-y-4">
                <div><Label>Floor Number</Label><Input type="number" value={flForm.floorNumber} onChange={(e) => setFlForm({ ...flForm, floorNumber: Number(e.target.value) })} /></div>
                <div><Label>Name</Label><Input value={flForm.name} onChange={(e) => setFlForm({ ...flForm, name: e.target.value })} placeholder="e.g. Ground Floor" /></div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setFlDialogOpen(false)}>Cancel</Button>
                <Button onClick={saveFloor} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{flEditing ? "Update" : "Create"}</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Amenity Dialog */}
          <Dialog open={amDialogOpen} onOpenChange={setAmDialogOpen}>
            <DialogContent>
              <DialogHeader><DialogTitle>{amEditing ? "Edit Amenity" : "Add Amenity"}</DialogTitle></DialogHeader>
              <div className="space-y-4">
                <div><Label>Name</Label><Input value={amForm.name} onChange={(e) => setAmForm({ ...amForm, name: e.target.value })} placeholder="e.g. WiFi, Air Conditioning" /></div>
                <div><Label>Category</Label><Input value={amForm.category ?? ""} onChange={(e) => setAmForm({ ...amForm, category: e.target.value })} placeholder="e.g. Technology, Comfort" /></div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setAmDialogOpen(false)}>Cancel</Button>
                <Button onClick={saveAmenity} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{amEditing ? "Update" : "Create"}</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Rate Dialog */}
          <Dialog open={rateDialogOpen} onOpenChange={setRateDialogOpen}>
            <DialogContent>
              <DialogHeader><DialogTitle>Add Rate</DialogTitle></DialogHeader>
              <div className="space-y-4">
                <div><Label>Rate Name *</Label><Input value={rateForm.rateName} onChange={(e) => setRateForm({ ...rateForm, rateName: e.target.value })} placeholder="e.g. Peak Season, Holiday Rate, Weekend Special" /></div>
                <div><Label>Room Type *</Label>
                  <Select value={String(rateForm.hotelRoomTypeId)} onValueChange={(v) => setRateForm({ ...rateForm, hotelRoomTypeId: Number(v) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{roomTypes.map((rt) => <SelectItem key={rt.hotelRoomTypeId} value={String(rt.hotelRoomTypeId)}>{rt.name} (Base: {rt.baseRate.toFixed(2)})</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                <div><Label>Rate *</Label><Input type="number" step="0.01" value={rateForm.rate} onChange={(e) => setRateForm({ ...rateForm, rate: Number(e.target.value) })} /></div>
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>Start Date *</Label><Input type="date" value={rateForm.startDate} onChange={(e) => setRateForm({ ...rateForm, startDate: e.target.value })} /></div>
                  <div><Label>End Date *</Label><Input type="date" value={rateForm.endDate} onChange={(e) => setRateForm({ ...rateForm, endDate: e.target.value })} /></div>
                </div>
                <div className="flex items-center gap-2">
                  <input type="checkbox" id="isWeekend" checked={rateForm.isWeekend} onChange={(e) => setRateForm({ ...rateForm, isWeekend: e.target.checked })} className="rounded" />
                  <label htmlFor="isWeekend" className="text-sm cursor-pointer">Weekend rate (applies Fri-Sun only)</label>
                </div>
                {rateForm.hotelRoomTypeId > 0 && rateForm.rate > 0 && (() => {
                  const baseRate = roomTypes.find(rt => rt.hotelRoomTypeId === rateForm.hotelRoomTypeId)?.baseRate ?? 0
                  const diff = rateForm.rate - baseRate
                  const pct = baseRate > 0 ? ((diff / baseRate) * 100).toFixed(1) : "0"
                  return (
                    <div className={`p-2 rounded text-xs ${diff >= 0 ? "bg-amber-50 text-amber-700" : "bg-emerald-50 text-emerald-700"}`}>
                      {diff >= 0 ? `+${pct}%` : `${pct}%`} vs base rate ({baseRate.toFixed(2)}) — {diff >= 0 ? "premium" : "discount"} of {Math.abs(diff).toFixed(2)}/night
                    </div>
                  )
                })()}
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setRateDialogOpen(false)}>Cancel</Button>
                <Button onClick={saveRate} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Create</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

"use client"

import { useEffect, useState } from "react"
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
import { Loader2, Plus, Settings, Trash2, Edit2, CalendarDays } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getHotelProfile, upsertHotelProfile,
  listHotelRoomTypes, createHotelRoomType, updateHotelRoomType, deleteHotelRoomType,
  listHotelFloors, createHotelFloor, updateHotelFloor, deleteHotelFloor,
  listHotelAmenities, createHotelAmenity, updateHotelAmenity, deleteHotelAmenity,
  listRoomRates, createRoomRate, deleteRoomRate,
  type HotelProfile, type HotelProfileInput, type HotelRoomType, type HotelRoomTypeInput,
  type HotelFloor, type HotelFloorInput, type HotelAmenity, type HotelAmenityInput,
  type HotelRoomRate,
} from "@/lib/api/hotel"

export default function HotelSetupPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [profile, setProfile] = useState<HotelProfileInput>({ hotelName: "" })
  const [roomTypes, setRoomTypes] = useState<HotelRoomType[]>([])
  const [floors, setFloors] = useState<HotelFloor[]>([])
  const [amenities, setAmenities] = useState<HotelAmenity[]>([])

  // Room Type dialog
  const [rtDialogOpen, setRtDialogOpen] = useState(false)
  const [rtEditing, setRtEditing] = useState<HotelRoomType | null>(null)
  const [rtForm, setRtForm] = useState<HotelRoomTypeInput>({ name: "", baseRate: 0, maxOccupancy: 2 })

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

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [p, rt, fl, am, rr] = await Promise.all([
        getHotelProfile().catch(() => null),
        listHotelRoomTypes(),
        listHotelFloors(),
        listHotelAmenities(),
        listRoomRates().catch(() => []),
      ])
      if (p) setProfile(p)
      setRoomTypes(rt)
      setFloors(fl)
      setAmenities(am)
      setRates(rr)
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
            <TabsList>
              <TabsTrigger value="profile">Profile</TabsTrigger>
              <TabsTrigger value="room-types">Room Types ({roomTypes.length})</TabsTrigger>
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
                  <Button size="sm" onClick={() => { setRtEditing(null); setRtForm({ name: "", baseRate: 0, maxOccupancy: 2 }); setRtDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add</Button>
                </CardHeader>
                <CardContent>
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Name</th><th className="text-left p-3">Base Rate</th><th className="text-left p-3">Max Guests</th><th className="text-left p-3">Bed Type</th><th className="text-right p-3">Actions</th></tr></thead>
                    <tbody>
                      {roomTypes.map((rt) => (
                        <tr key={rt.hotelRoomTypeId} className="border-b">
                          <td className="p-3 font-medium">{rt.name}</td>
                          <td className="p-3">{rt.baseRate.toFixed(2)}</td>
                          <td className="p-3">{rt.maxOccupancy}</td>
                          <td className="p-3">{rt.bedType ?? "-"}</td>
                          <td className="p-3 text-right space-x-1">
                            <Button variant="ghost" size="icon" onClick={() => { setRtEditing(rt); setRtForm(rt); setRtDialogOpen(true) }}><Edit2 className="h-4 w-4" /></Button>
                            <Button variant="ghost" size="icon" className="text-red-600" onClick={async () => { if (confirm(`Delete ${rt.name}?`)) { await deleteHotelRoomType(rt.hotelRoomTypeId); setRoomTypes(await listHotelRoomTypes()); toast({ title: "Deleted" }) } }}><Trash2 className="h-4 w-4" /></Button>
                          </td>
                        </tr>
                      ))}
                      {roomTypes.length === 0 && <tr><td colSpan={5} className="p-8 text-center text-slate-400">No room types yet.</td></tr>}
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
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">#</th><th className="text-left p-3">Name</th><th className="text-right p-3">Actions</th></tr></thead>
                    <tbody>
                      {floors.map((f) => (
                        <tr key={f.hotelFloorId} className="border-b">
                          <td className="p-3">{f.floorNumber}</td>
                          <td className="p-3 font-medium">{f.name}</td>
                          <td className="p-3 text-right space-x-1">
                            <Button variant="ghost" size="icon" onClick={() => { setFlEditing(f); setFlForm(f); setFlDialogOpen(true) }}><Edit2 className="h-4 w-4" /></Button>
                            <Button variant="ghost" size="icon" className="text-red-600" onClick={async () => { if (confirm(`Delete ${f.name}?`)) { await deleteHotelFloor(f.hotelFloorId); setFloors(await listHotelFloors()); toast({ title: "Deleted" }) } }}><Trash2 className="h-4 w-4" /></Button>
                          </td>
                        </tr>
                      ))}
                      {floors.length === 0 && <tr><td colSpan={3} className="p-8 text-center text-slate-400">No floors yet.</td></tr>}
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
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Name</th><th className="text-left p-3">Category</th><th className="text-right p-3">Actions</th></tr></thead>
                    <tbody>
                      {amenities.map((a) => (
                        <tr key={a.hotelAmenityId} className="border-b">
                          <td className="p-3 font-medium">{a.name}</td>
                          <td className="p-3">{a.category ?? "-"}</td>
                          <td className="p-3 text-right space-x-1">
                            <Button variant="ghost" size="icon" onClick={() => { setAmEditing(a); setAmForm(a); setAmDialogOpen(true) }}><Edit2 className="h-4 w-4" /></Button>
                            <Button variant="ghost" size="icon" className="text-red-600" onClick={async () => { if (confirm(`Delete ${a.name}?`)) { await deleteHotelAmenity(a.hotelAmenityId); setAmenities(await listHotelAmenities()); toast({ title: "Deleted" }) } }}><Trash2 className="h-4 w-4" /></Button>
                          </td>
                        </tr>
                      ))}
                      {amenities.length === 0 && <tr><td colSpan={3} className="p-8 text-center text-slate-400">No amenities yet.</td></tr>}
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
                  {rates.length > 0 ? (
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Rate Name</th>
                          <th className="text-left p-3">Room Type</th>
                          <th className="text-right p-3">Rate (GH₵)</th>
                          <th className="text-left p-3">Start Date</th>
                          <th className="text-left p-3">End Date</th>
                          <th className="text-center p-3">Type</th>
                          <th className="text-center p-3">Status</th>
                          <th className="text-right p-3">Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        {rates.map((r: any) => {
                          const start = (r.startdate ?? r.startDate ?? "").slice(0, 10)
                          const end = (r.enddate ?? r.endDate ?? "").slice(0, 10)
                          const isActive = r.isactive ?? r.isActive ?? true
                          const isWeekend = r.isweekend ?? r.isWeekend ?? false
                          const now = new Date().toISOString().slice(0, 10)
                          const isCurrent = start <= now && end >= now
                          const rtName = r.roomtypename ?? r.roomTypeName ?? roomTypes.find(rt => rt.hotelRoomTypeId === (r.hotelroomtypeid ?? r.hotelRoomTypeId))?.name ?? "—"
                          return (
                            <tr key={r.hotelroomrateid ?? r.hotelRoomRateId} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">{r.ratename ?? r.rateName}</td>
                              <td className="p-3">{rtName}</td>
                              <td className="p-3 text-right font-semibold text-violet-700">GH₵{Number(r.rate ?? 0).toFixed(2)}</td>
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
                      <p>No custom rates defined. Room types will use their base rate.</p>
                      <p className="text-xs mt-1">Add seasonal rates, weekend rates, or special pricing to override base rates.</p>
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
                <div><Label>Name</Label><Input value={rtForm.name} onChange={(e) => setRtForm({ ...rtForm, name: e.target.value })} placeholder="e.g. Deluxe Double" /></div>
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>Base Rate</Label><Input type="number" step="0.01" value={rtForm.baseRate} onChange={(e) => setRtForm({ ...rtForm, baseRate: Number(e.target.value) })} /></div>
                  <div><Label>Max Occupancy</Label><Input type="number" min={1} value={rtForm.maxOccupancy ?? 2} onChange={(e) => setRtForm({ ...rtForm, maxOccupancy: Number(e.target.value) })} /></div>
                </div>
                <div><Label>Bed Type</Label><Input value={rtForm.bedType ?? ""} onChange={(e) => setRtForm({ ...rtForm, bedType: e.target.value })} placeholder="e.g. King, Twin, Queen" /></div>
                <div><Label>Description</Label><Input value={rtForm.description ?? ""} onChange={(e) => setRtForm({ ...rtForm, description: e.target.value })} /></div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setRtDialogOpen(false)}>Cancel</Button>
                <Button onClick={saveRoomType} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{rtEditing ? "Update" : "Create"}</Button>
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
                    <SelectContent>{roomTypes.map((rt) => <SelectItem key={rt.hotelRoomTypeId} value={String(rt.hotelRoomTypeId)}>{rt.name} (Base: GH₵{rt.baseRate.toFixed(2)})</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                <div><Label>Rate (GH₵) *</Label><Input type="number" step="0.01" value={rateForm.rate} onChange={(e) => setRateForm({ ...rateForm, rate: Number(e.target.value) })} /></div>
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
                      {diff >= 0 ? `+${pct}%` : `${pct}%`} vs base rate (GH₵{baseRate.toFixed(2)}) — {diff >= 0 ? "premium" : "discount"} of GH₵{Math.abs(diff).toFixed(2)}/night
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

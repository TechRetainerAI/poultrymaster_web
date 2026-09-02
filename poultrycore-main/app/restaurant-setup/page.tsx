"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Plus, Trash2, Edit2, Settings, Clock, Utensils, Store, MapPin, Phone, Mail, Globe, DollarSign, Users, CheckCircle2, XCircle } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  getRestaurantProfile, upsertRestaurantProfile,
  listMenuSchedules, createMenuSchedule, updateMenuSchedule, deleteMenuSchedule,
  listModifierGroups, createModifierGroup, updateModifierGroup, deleteModifierGroup,
  listModifiers, createModifier, updateModifier, deleteModifier,
  type RestaurantProfile, type RestaurantProfileInput,
  type MenuSchedule, type MenuScheduleInput,
  type ModifierGroup, type ModifierGroupInput,
  type Modifier, type ModifierInput,
} from "@/lib/api/restaurant"

const SERVICE_TYPES = ["DineIn", "Takeaway", "Delivery", "DriveThrough"] as const
const SERVICE_LABELS: Record<string, string> = { DineIn: "Dine-In", Takeaway: "Takeaway", Delivery: "Delivery", DriveThrough: "Drive-Through" }
const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

export default function RestaurantSetupPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [profile, setProfile] = useState<RestaurantProfileInput>({ restaurantName: "" })
  const [activeServices, setActiveServices] = useState<Set<string>>(new Set())

  // Schedules
  const [schedules, setSchedules] = useState<MenuSchedule[]>([])
  const [schedDialogOpen, setSchedDialogOpen] = useState(false)
  const [schedEditing, setSchedEditing] = useState<MenuSchedule | null>(null)
  const [schedForm, setSchedForm] = useState<MenuScheduleInput>({ name: "", startTime: "06:00", endTime: "11:00" })
  const [schedDays, setSchedDays] = useState<Set<string>>(new Set(DAYS))

  // Modifier Groups
  const [modGroups, setModGroups] = useState<ModifierGroup[]>([])
  const [mgDialogOpen, setMgDialogOpen] = useState(false)
  const [mgEditing, setMgEditing] = useState<ModifierGroup | null>(null)
  const [mgForm, setMgForm] = useState<ModifierGroupInput>({ name: "", isRequired: false, minSelections: 0, maxSelections: 1 })

  // Modifiers
  const [modifiers, setModifiers] = useState<Modifier[]>([])
  const [modDialogOpen, setModDialogOpen] = useState(false)
  const [modEditing, setModEditing] = useState<Modifier | null>(null)
  const [modForm, setModForm] = useState<ModifierInput>({ modifierGroupId: 0, name: "", priceAdjustment: 0 })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [p, sc, mg, mo] = await Promise.all([
        getRestaurantProfile().catch(() => null),
        listMenuSchedules(),
        listModifierGroups(),
        listModifiers(),
      ])
      if (p) {
        setProfile(p)
        setActiveServices(new Set((p.serviceTypes || "").split(",").filter(Boolean)))
      }
      setSchedules(sc)
      setModGroups(mg)
      setModifiers(mo)
    } catch (e: any) {
      toast({ title: "Failed to load", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  function toggleService(svc: string) {
    const next = new Set(activeServices)
    next.has(svc) ? next.delete(svc) : next.add(svc)
    setActiveServices(next)
    setProfile({ ...profile, serviceTypes: Array.from(next).join(",") })
  }

  async function saveProfile() {
    if (!profile.restaurantName?.trim()) { toast({ title: "Restaurant name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await upsertRestaurantProfile(profile)
      toast({ title: "Profile saved successfully" })
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  // ---- Schedules ----
  function openSchedDialog(s?: MenuSchedule) {
    if (s) {
      setSchedEditing(s)
      setSchedForm({ name: s.name, startTime: s.startTime, endTime: s.endTime, daysOfWeek: s.daysOfWeek, isActive: s.isActive })
      setSchedDays(new Set((s.daysOfWeek || "").split(",").filter(Boolean)))
    } else {
      setSchedEditing(null)
      setSchedForm({ name: "", startTime: "06:00", endTime: "11:00", isActive: true })
      setSchedDays(new Set(DAYS))
    }
    setSchedDialogOpen(true)
  }

  function toggleSchedDay(day: string) {
    const next = new Set(schedDays)
    next.has(day) ? next.delete(day) : next.add(day)
    setSchedDays(next)
    setSchedForm({ ...schedForm, daysOfWeek: Array.from(next).join(",") })
  }

  async function saveSched() {
    if (!schedForm.name.trim()) { toast({ title: "Schedule name required", variant: "destructive" }); return }
    try {
      if (schedEditing) await updateMenuSchedule(schedEditing.menuScheduleId, schedForm)
      else await createMenuSchedule(schedForm)
      toast({ title: schedEditing ? "Schedule updated" : "Schedule created" })
      setSchedDialogOpen(false)
      setSchedules(await listMenuSchedules())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function deleteSched(id: number) {
    try { await deleteMenuSchedule(id); toast({ title: "Schedule deleted" }); setSchedules(await listMenuSchedules()) }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  // ---- Modifier Groups ----
  function openMgDialog(g?: ModifierGroup) {
    if (g) { setMgEditing(g); setMgForm({ name: g.name, description: g.description, isRequired: g.isRequired, minSelections: g.minSelections, maxSelections: g.maxSelections, isActive: g.isActive }) }
    else { setMgEditing(null); setMgForm({ name: "", isRequired: false, minSelections: 0, maxSelections: 1, isActive: true }) }
    setMgDialogOpen(true)
  }
  async function saveMg() {
    if (!mgForm.name.trim()) { toast({ title: "Group name required", variant: "destructive" }); return }
    try {
      if (mgEditing) await updateModifierGroup(mgEditing.modifierGroupId, mgForm)
      else await createModifierGroup(mgForm)
      toast({ title: mgEditing ? "Group updated" : "Group created" }); setMgDialogOpen(false); setModGroups(await listModifierGroups())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function deleteMg(id: number) {
    try { await deleteModifierGroup(id); toast({ title: "Group deleted" }); setModGroups(await listModifierGroups()); setModifiers(await listModifiers()) }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  // ---- Modifiers ----
  function openModDialog(m?: Modifier) {
    if (m) { setModEditing(m); setModForm({ modifierGroupId: m.modifierGroupId, name: m.name, priceAdjustment: m.priceAdjustment, isDefault: m.isDefault, isAvailable: m.isAvailable }) }
    else { setModEditing(null); setModForm({ modifierGroupId: modGroups[0]?.modifierGroupId || 0, name: "", priceAdjustment: 0, isDefault: false, isAvailable: true }) }
    setModDialogOpen(true)
  }
  async function saveMod() {
    if (!modForm.name.trim()) { toast({ title: "Modifier name required", variant: "destructive" }); return }
    try {
      if (modEditing) await updateModifier(modEditing.modifierId, modForm)
      else await createModifier(modForm)
      toast({ title: modEditing ? "Modifier updated" : "Modifier created" }); setModDialogOpen(false); setModifiers(await listModifiers())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function deleteMod(id: number) {
    try { await deleteModifier(id); toast({ title: "Modifier deleted" }); setModifiers(await listModifiers()) }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-5xl mx-auto space-y-6">
            {/* Page Header */}
            <div className="flex items-center justify-between">
              <div>
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center">
                    <Settings className="h-5 w-5 text-rose-600" />
                  </div>
                  <div>
                    <h1 className="text-2xl font-bold text-gray-900">Restaurant Setup</h1>
                    <p className="text-sm text-muted-foreground">Configure your restaurant profile, menu schedules and modifiers</p>
                  </div>
                </div>
              </div>
              <Button onClick={saveProfile} disabled={saving} className="bg-rose-600 hover:bg-rose-700">
                {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <CheckCircle2 className="mr-2 h-4 w-4" />}
                Save Changes
              </Button>
            </div>

            <Tabs defaultValue="profile" className="space-y-6">
              <TabsList className="bg-white border shadow-sm">
                <TabsTrigger value="profile" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <Store className="h-4 w-4 mr-2" /> Profile
                </TabsTrigger>
                <TabsTrigger value="schedules" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <Clock className="h-4 w-4 mr-2" /> Menu Schedules
                  {schedules.length > 0 && <Badge variant="secondary" className="ml-2 h-5 px-1.5">{schedules.length}</Badge>}
                </TabsTrigger>
                <TabsTrigger value="modifiers" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <Utensils className="h-4 w-4 mr-2" /> Modifiers
                  {modGroups.length > 0 && <Badge variant="secondary" className="ml-2 h-5 px-1.5">{modGroups.length}</Badge>}
                </TabsTrigger>
              </TabsList>

              {/* ===== PROFILE TAB ===== */}
              <TabsContent value="profile" className="space-y-6">
                {/* Basic Info */}
                <Card>
                  <CardHeader className="pb-4">
                    <div className="flex items-center gap-2">
                      <Store className="h-5 w-5 text-rose-500" />
                      <div>
                        <CardTitle className="text-lg">Basic Information</CardTitle>
                        <CardDescription>Your restaurant's name, cuisine and description</CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium">Restaurant Name <span className="text-rose-500">*</span></Label>
                        <Input value={profile.restaurantName || ""} onChange={e => setProfile({ ...profile, restaurantName: e.target.value })} placeholder="Enter restaurant name" className="h-10" />
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium">Cuisine Type</Label>
                        <Select value={profile.cuisineType || ""} onValueChange={v => setProfile({ ...profile, cuisineType: v })}>
                          <SelectTrigger className="h-10"><SelectValue placeholder="Select cuisine type" /></SelectTrigger>
                          <SelectContent>
                            {["Multi-Cuisine", "Italian", "Chinese", "Japanese", "Indian", "Mexican", "Thai", "French", "Mediterranean", "American", "African", "Korean", "Middle Eastern", "Seafood", "Steakhouse", "Vegetarian", "Vegan", "Fusion", "Other"].map(c => (
                              <SelectItem key={c} value={c}>{c}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    </div>
                    <div className="space-y-1.5">
                      <Label className="text-sm font-medium">Description</Label>
                      <textarea className="w-full min-h-[80px] rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-500 focus-visible:ring-offset-2" value={profile.description || ""} onChange={e => setProfile({ ...profile, description: e.target.value })} placeholder="Describe your restaurant — this appears on your online ordering page" />
                    </div>
                  </CardContent>
                </Card>

                {/* Service Types */}
                <Card>
                  <CardHeader className="pb-4">
                    <div className="flex items-center gap-2">
                      <Globe className="h-5 w-5 text-rose-500" />
                      <div>
                        <CardTitle className="text-lg">Service Types</CardTitle>
                        <CardDescription>Choose how customers can order from your restaurant</CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                      {SERVICE_TYPES.map(svc => {
                        const active = activeServices.has(svc)
                        return (
                          <button key={svc} type="button" onClick={() => toggleService(svc)}
                            className={`relative flex flex-col items-center gap-2 p-4 rounded-xl border-2 transition-all ${
                              active ? "border-rose-500 bg-rose-50 shadow-sm" : "border-gray-200 bg-white hover:border-gray-300"
                            }`}>
                            {active && <CheckCircle2 className="absolute top-2 right-2 h-4 w-4 text-rose-500" />}
                            <span className="text-2xl">{svc === "DineIn" ? "🍽️" : svc === "Takeaway" ? "🥡" : svc === "Delivery" ? "🛵" : "🚗"}</span>
                            <span className={`text-sm font-medium ${active ? "text-rose-700" : "text-gray-600"}`}>{SERVICE_LABELS[svc]}</span>
                          </button>
                        )
                      })}
                    </div>
                  </CardContent>
                </Card>

                {/* Contact & Location */}
                <Card>
                  <CardHeader className="pb-4">
                    <div className="flex items-center gap-2">
                      <MapPin className="h-5 w-5 text-rose-500" />
                      <div>
                        <CardTitle className="text-lg">Contact & Location</CardTitle>
                        <CardDescription>How customers find and reach your restaurant</CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium flex items-center gap-1.5"><Phone className="h-3.5 w-3.5 text-muted-foreground" /> Phone</Label>
                        <Input value={profile.phone || ""} onChange={e => setProfile({ ...profile, phone: e.target.value })} placeholder="+233 XX XXX XXXX" className="h-10" />
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium flex items-center gap-1.5"><Mail className="h-3.5 w-3.5 text-muted-foreground" /> Email</Label>
                        <Input type="email" value={profile.email || ""} onChange={e => setProfile({ ...profile, email: e.target.value })} placeholder="info@restaurant.com" className="h-10" />
                      </div>
                      <div className="space-y-1.5 md:col-span-2">
                        <Label className="text-sm font-medium">Address</Label>
                        <Input value={profile.address || ""} onChange={e => setProfile({ ...profile, address: e.target.value })} placeholder="Street address" className="h-10" />
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium">City</Label>
                        <Input value={profile.city || ""} onChange={e => setProfile({ ...profile, city: e.target.value })} placeholder="City" className="h-10" />
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium">Country</Label>
                        <Input value={profile.country || ""} onChange={e => setProfile({ ...profile, country: e.target.value })} placeholder="Country" className="h-10" />
                      </div>
                    </div>
                  </CardContent>
                </Card>

                {/* Operations */}
                <Card>
                  <CardHeader className="pb-4">
                    <div className="flex items-center gap-2">
                      <Clock className="h-5 w-5 text-rose-500" />
                      <div>
                        <CardTitle className="text-lg">Operations</CardTitle>
                        <CardDescription>Operating hours, capacity, and financial settings</CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium">Opening Time</Label>
                        <Input type="time" value={profile.openingTime || "08:00"} onChange={e => setProfile({ ...profile, openingTime: e.target.value })} className="h-10" />
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium">Closing Time</Label>
                        <Input type="time" value={profile.closingTime || "22:00"} onChange={e => setProfile({ ...profile, closingTime: e.target.value })} className="h-10" />
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium flex items-center gap-1.5"><Users className="h-3.5 w-3.5 text-muted-foreground" /> Seating Capacity</Label>
                        <Input type="number" min={0} value={profile.seatingCapacity || 0} onChange={e => setProfile({ ...profile, seatingCapacity: parseInt(e.target.value) || 0 })} className="h-10" />
                      </div>
                    </div>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mt-4 pt-4 border-t">
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium flex items-center gap-1.5"><DollarSign className="h-3.5 w-3.5 text-muted-foreground" /> Currency</Label>
                        <Select value={profile.defaultCurrency || "GHS"} onValueChange={v => setProfile({ ...profile, defaultCurrency: v })}>
                          <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {["GHS", "USD", "EUR", "GBP", "NGN", "KES", "ZAR", "XOF"].map(c => (
                              <SelectItem key={c} value={c}>{c}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium">Tax Rate (%)</Label>
                        <Input type="number" step="0.01" min={0} value={profile.taxRate || 0} onChange={e => setProfile({ ...profile, taxRate: parseFloat(e.target.value) || 0 })} className="h-10" />
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-sm font-medium">Service Charge (%)</Label>
                        <Input type="number" step="0.01" min={0} value={profile.serviceChargeRate || 0} onChange={e => setProfile({ ...profile, serviceChargeRate: parseFloat(e.target.value) || 0 })} className="h-10" />
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </TabsContent>

              {/* ===== SCHEDULES TAB ===== */}
              <TabsContent value="schedules" className="space-y-4">
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="h-9 w-9 rounded-lg bg-blue-100 flex items-center justify-center">
                          <Clock className="h-5 w-5 text-blue-600" />
                        </div>
                        <div>
                          <CardTitle className="text-lg">Menu Schedules</CardTitle>
                          <CardDescription>Define when different menus are available (breakfast, lunch, dinner, happy hour)</CardDescription>
                        </div>
                      </div>
                      <Button onClick={() => openSchedDialog()} className="bg-rose-600 hover:bg-rose-700">
                        <Plus className="h-4 w-4 mr-2" /> Add Schedule
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {schedules.length === 0 ? (
                      <div className="text-center py-12 border-2 border-dashed rounded-xl">
                        <Clock className="h-10 w-10 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No menu schedules yet</h3>
                        <p className="text-sm text-muted-foreground mb-4">Create schedules like Breakfast (6am-11am), Lunch (11am-3pm), Dinner (5pm-10pm)</p>
                        <Button variant="outline" onClick={() => openSchedDialog()}><Plus className="h-4 w-4 mr-2" /> Create your first schedule</Button>
                      </div>
                    ) : (
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                        {schedules.map(s => (
                          <div key={s.menuScheduleId} className="group relative flex items-start gap-4 p-4 border rounded-xl hover:border-rose-200 hover:bg-rose-50/30 transition-all">
                            <div className={`h-10 w-10 rounded-lg flex items-center justify-center flex-shrink-0 ${s.isActive ? "bg-green-100" : "bg-gray-100"}`}>
                              <Clock className={`h-5 w-5 ${s.isActive ? "text-green-600" : "text-gray-400"}`} />
                            </div>
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2">
                                <h4 className="font-semibold text-gray-900">{s.name}</h4>
                                <Badge variant={s.isActive ? "default" : "secondary"} className={`text-xs ${s.isActive ? "bg-green-100 text-green-700 hover:bg-green-100" : ""}`}>
                                  {s.isActive ? "Active" : "Inactive"}
                                </Badge>
                              </div>
                              <p className="text-sm text-muted-foreground mt-0.5">
                                {s.startTime} — {s.endTime}
                              </p>
                              {s.daysOfWeek && (
                                <div className="flex gap-1 mt-2">
                                  {DAYS.map(d => (
                                    <span key={d} className={`text-[10px] font-medium w-7 h-5 flex items-center justify-center rounded ${
                                      s.daysOfWeek?.includes(d) ? "bg-rose-100 text-rose-700" : "bg-gray-100 text-gray-400"
                                    }`}>{d}</span>
                                  ))}
                                </div>
                              )}
                            </div>
                            <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                              <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openSchedDialog(s)}><Edit2 className="h-3.5 w-3.5" /></Button>
                              <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => deleteSched(s.menuScheduleId)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* ===== MODIFIERS TAB ===== */}
              <TabsContent value="modifiers" className="space-y-4">
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="h-9 w-9 rounded-lg bg-purple-100 flex items-center justify-center">
                          <Utensils className="h-5 w-5 text-purple-600" />
                        </div>
                        <div>
                          <CardTitle className="text-lg">Modifier Groups</CardTitle>
                          <CardDescription>Create groups of options customers can choose when ordering (sizes, toppings, sauces)</CardDescription>
                        </div>
                      </div>
                      <Button onClick={() => openMgDialog()} className="bg-rose-600 hover:bg-rose-700">
                        <Plus className="h-4 w-4 mr-2" /> Add Group
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {modGroups.length === 0 ? (
                      <div className="text-center py-12 border-2 border-dashed rounded-xl">
                        <Utensils className="h-10 w-10 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No modifier groups yet</h3>
                        <p className="text-sm text-muted-foreground mb-4">Create groups like "Choose Size" (Small, Medium, Large) or "Extra Toppings" (Cheese, Mushrooms)</p>
                        <Button variant="outline" onClick={() => openMgDialog()}><Plus className="h-4 w-4 mr-2" /> Create your first group</Button>
                      </div>
                    ) : (
                      <div className="space-y-4">
                        {modGroups.map(g => {
                          const groupMods = modifiers.filter(m => m.modifierGroupId === g.modifierGroupId)
                          return (
                            <div key={g.modifierGroupId} className="border rounded-xl overflow-hidden">
                              {/* Group header */}
                              <div className="flex items-center justify-between p-4 bg-gray-50/80">
                                <div className="flex items-center gap-3">
                                  <div className={`h-8 w-8 rounded-lg flex items-center justify-center ${g.isActive ? "bg-purple-100" : "bg-gray-200"}`}>
                                    <Utensils className={`h-4 w-4 ${g.isActive ? "text-purple-600" : "text-gray-400"}`} />
                                  </div>
                                  <div>
                                    <div className="flex items-center gap-2">
                                      <h4 className="font-semibold text-gray-900">{g.name}</h4>
                                      <Badge variant={g.isRequired ? "default" : "outline"} className={`text-xs ${g.isRequired ? "bg-rose-100 text-rose-700 hover:bg-rose-100" : ""}`}>
                                        {g.isRequired ? "Required" : "Optional"}
                                      </Badge>
                                      {!g.isActive && <Badge variant="secondary" className="text-xs">Inactive</Badge>}
                                    </div>
                                    <p className="text-xs text-muted-foreground mt-0.5">
                                      Select {g.minSelections === g.maxSelections ? g.maxSelections : `${g.minSelections}–${g.maxSelections}`} option{g.maxSelections !== 1 ? "s" : ""}
                                      {g.description && ` · ${g.description}`}
                                    </p>
                                  </div>
                                </div>
                                <div className="flex gap-1">
                                  <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openMgDialog(g)}><Edit2 className="h-3.5 w-3.5" /></Button>
                                  <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => deleteMg(g.modifierGroupId)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
                                </div>
                              </div>
                              {/* Modifiers list */}
                              <div className="divide-y">
                                {groupMods.map(m => (
                                  <div key={m.modifierId} className="flex items-center justify-between px-4 py-2.5 hover:bg-gray-50 transition-colors">
                                    <div className="flex items-center gap-3">
                                      <div className={`h-2 w-2 rounded-full ${m.isAvailable ? "bg-green-500" : "bg-gray-300"}`} />
                                      <span className="text-sm font-medium text-gray-700">{m.name}</span>
                                      {m.isDefault && <Badge variant="outline" className="text-[10px] h-4 px-1.5 bg-blue-50 text-blue-600 border-blue-200">Default</Badge>}
                                    </div>
                                    <div className="flex items-center gap-2">
                                      {m.priceAdjustment > 0 && <span className="text-sm font-medium text-green-600">+{m.priceAdjustment.toFixed(2)}</span>}
                                      {m.priceAdjustment < 0 && <span className="text-sm font-medium text-red-600">{m.priceAdjustment.toFixed(2)}</span>}
                                      <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openModDialog(m)}><Edit2 className="h-3 w-3" /></Button>
                                      <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => deleteMod(m.modifierId)}><Trash2 className="h-3 w-3 text-red-500" /></Button>
                                    </div>
                                  </div>
                                ))}
                                <div className="px-4 py-2">
                                  <Button variant="ghost" size="sm" className="text-xs text-rose-600 hover:text-rose-700 hover:bg-rose-50 -ml-2"
                                    onClick={() => { setModForm({ modifierGroupId: g.modifierGroupId, name: "", priceAdjustment: 0, isDefault: false, isAvailable: true }); setModEditing(null); setModDialogOpen(true) }}>
                                    <Plus className="h-3 w-3 mr-1" /> Add option
                                  </Button>
                                </div>
                              </div>
                            </div>
                          )
                        })}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      {/* Schedule Dialog */}
      <Dialog open={schedDialogOpen} onOpenChange={setSchedDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{schedEditing ? "Edit Schedule" : "Add Menu Schedule"}</DialogTitle>
            <DialogDescription>Define when this menu period is available</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Schedule Name <span className="text-rose-500">*</span></Label>
              <Select value={schedForm.name || ""} onValueChange={v => setSchedForm({ ...schedForm, name: v })}>
                <SelectTrigger className="h-10"><SelectValue placeholder="Select a schedule" /></SelectTrigger>
                <SelectContent>
                  {["Breakfast", "Brunch", "Lunch", "Afternoon Tea", "Happy Hour", "Dinner", "Late Night", "Weekend Special", "Holiday Menu", "All Day"].map(s => (
                    <SelectItem key={s} value={s}>{s}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Start Time</Label>
                <Input type="time" value={schedForm.startTime} onChange={e => setSchedForm({ ...schedForm, startTime: e.target.value })} className="h-10" />
              </div>
              <div className="space-y-1.5">
                <Label>End Time</Label>
                <Input type="time" value={schedForm.endTime} onChange={e => setSchedForm({ ...schedForm, endTime: e.target.value })} className="h-10" />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Available Days</Label>
              <div className="flex gap-1.5">
                {DAYS.map(d => (
                  <button key={d} type="button" onClick={() => toggleSchedDay(d)}
                    className={`h-9 w-10 rounded-lg text-xs font-medium transition-all ${
                      schedDays.has(d) ? "bg-rose-500 text-white shadow-sm" : "bg-gray-100 text-gray-500 hover:bg-gray-200"
                    }`}>{d}</button>
                ))}
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSchedDialogOpen(false)}>Cancel</Button>
            <Button onClick={saveSched} className="bg-rose-600 hover:bg-rose-700">{schedEditing ? "Update" : "Create Schedule"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Modifier Group Dialog */}
      <Dialog open={mgDialogOpen} onOpenChange={setMgDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{mgEditing ? "Edit Modifier Group" : "Add Modifier Group"}</DialogTitle>
            <DialogDescription>A group of options customers can choose from when ordering</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Group Name <span className="text-rose-500">*</span></Label>
              <Select value={mgForm.name || ""} onValueChange={v => setMgForm({ ...mgForm, name: v })}>
                <SelectTrigger className="h-10"><SelectValue placeholder="Select a modifier group" /></SelectTrigger>
                <SelectContent>
                  {["Choose Size", "Extra Toppings", "Choose Sauce", "Choose Side", "Choose Drink", "Cooking Level", "Spice Level", "Choose Protein", "Choose Bread", "Dressing", "Add-Ons", "Remove Ingredients", "Choose Flavor", "Portion Size", "Temperature"].map(g => (
                    <SelectItem key={g} value={g}>{g}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Description</Label>
              <Input value={mgForm.description || ""} onChange={e => setMgForm({ ...mgForm, description: e.target.value })} placeholder="Brief description (optional)" className="h-10" />
            </div>
            <div className="p-3 bg-gray-50 rounded-lg space-y-3">
              <div className="flex items-center justify-between">
                <Label className="text-sm">Customer must select</Label>
                <button type="button" onClick={() => setMgForm({ ...mgForm, isRequired: !mgForm.isRequired })}
                  className={`relative inline-flex h-6 w-11 rounded-full transition-colors ${mgForm.isRequired ? "bg-rose-500" : "bg-gray-300"}`}>
                  <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform mt-0.5 ${mgForm.isRequired ? "translate-x-5 ml-0.5" : "translate-x-0.5"}`} />
                </button>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Min selections</Label>
                  <Input type="number" min={0} value={mgForm.minSelections || 0} onChange={e => setMgForm({ ...mgForm, minSelections: parseInt(e.target.value) || 0 })} className="h-9" />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Max selections</Label>
                  <Input type="number" min={1} value={mgForm.maxSelections || 1} onChange={e => setMgForm({ ...mgForm, maxSelections: parseInt(e.target.value) || 1 })} className="h-9" />
                </div>
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setMgDialogOpen(false)}>Cancel</Button>
            <Button onClick={saveMg} className="bg-rose-600 hover:bg-rose-700">{mgEditing ? "Update" : "Create Group"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Modifier Dialog */}
      <Dialog open={modDialogOpen} onOpenChange={setModDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{modEditing ? "Edit Modifier" : "Add Modifier Option"}</DialogTitle>
            <DialogDescription>An individual option within a modifier group</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Group</Label>
              <Select value={String(modForm.modifierGroupId)} onValueChange={v => setModForm({ ...modForm, modifierGroupId: parseInt(v) })}>
                <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                <SelectContent>{modGroups.map(g => <SelectItem key={g.modifierGroupId} value={String(g.modifierGroupId)}>{g.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Option Name <span className="text-rose-500">*</span></Label>
              <Input value={modForm.name} onChange={e => setModForm({ ...modForm, name: e.target.value })} placeholder="e.g. Large, Extra Cheese, Spicy" className="h-10" />
            </div>
            <div className="space-y-1.5">
              <Label>Price Adjustment</Label>
              <div className="relative">
                <DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input type="number" step="0.01" value={modForm.priceAdjustment || 0} onChange={e => setModForm({ ...modForm, priceAdjustment: parseFloat(e.target.value) || 0 })} className="h-10 pl-9" placeholder="0.00" />
              </div>
              <p className="text-xs text-muted-foreground">Use positive for extra charge, negative for discount, 0 for no change</p>
            </div>
            <div className="flex items-center gap-6 pt-1">
              <label className="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" checked={modForm.isDefault || false} onChange={e => setModForm({ ...modForm, isDefault: e.target.checked })} className="h-4 w-4 rounded border-gray-300 text-rose-600 focus:ring-rose-500" />
                <span className="text-sm">Pre-selected by default</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" checked={modForm.isAvailable !== false} onChange={e => setModForm({ ...modForm, isAvailable: e.target.checked })} className="h-4 w-4 rounded border-gray-300 text-rose-600 focus:ring-rose-500" />
                <span className="text-sm">Available</span>
              </label>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setModDialogOpen(false)}>Cancel</Button>
            <Button onClick={saveMod} className="bg-rose-600 hover:bg-rose-700">{modEditing ? "Update" : "Add Option"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

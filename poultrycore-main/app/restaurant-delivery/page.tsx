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
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Trash2, Edit2, Truck, MapPin, Users, Star, Package, RefreshCw } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listDrivers, createDriver, updateDriver, deleteDriver, updateDriverStatus,
  listDeliveryZones, createDeliveryZone, updateDeliveryZone, deleteDeliveryZone,
  listDeliveryAssignments, createDeliveryAssignment, updateAssignmentStatus, getDeliveryStats,
  listPlatforms, createPlatform, updatePlatform, deletePlatform,
  listOrders,
  type Driver, type DriverInput, type DeliveryZone, type DeliveryZoneInput,
  type DeliveryAssignment, type DeliveryStats, type Order,
  type ThirdPartyPlatform, type ThirdPartyPlatformInput,
} from "@/lib/api/restaurant"

const DRIVER_STATUS_COLORS: Record<string, string> = { Available: "bg-green-500", OnDelivery: "bg-blue-500", OffDuty: "bg-gray-500", Suspended: "bg-red-500" }
const ASSIGNMENT_STATUS_COLORS: Record<string, string> = { Pending: "bg-yellow-500", Assigned: "bg-blue-500", PickedUp: "bg-indigo-500", EnRoute: "bg-purple-500", Delivered: "bg-green-500", Failed: "bg-red-500", Cancelled: "bg-gray-500" }
const VEHICLES = ["Motorcycle", "Car", "Bicycle", "Van"]

export default function RestaurantDeliveryPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [drivers, setDrivers] = useState<Driver[]>([])
  const [zones, setZones] = useState<DeliveryZone[]>([])
  const [assignments, setAssignments] = useState<DeliveryAssignment[]>([])
  const [stats, setStats] = useState<DeliveryStats | null>(null)
  const [platforms, setPlatforms] = useState<ThirdPartyPlatform[]>([])
  const [filterAssignStatus, setFilterAssignStatus] = useState("active")

  // Driver dialog
  const [driverDialogOpen, setDriverDialogOpen] = useState(false)
  const [driverEditing, setDriverEditing] = useState<Driver | null>(null)
  const [driverForm, setDriverForm] = useState<DriverInput>({ firstName: "", lastName: "", phone: "", vehicleType: "Motorcycle" })

  // Zone dialog
  const [zoneDialogOpen, setZoneDialogOpen] = useState(false)
  const [zoneEditing, setZoneEditing] = useState<DeliveryZone | null>(null)
  const [zoneForm, setZoneForm] = useState<DeliveryZoneInput>({ name: "", minDistanceKm: 0, maxDistanceKm: 5, deliveryFee: 0, estimatedMins: 30 })

  // Platform dialog
  const [platDialogOpen, setPlatDialogOpen] = useState(false)
  const [platEditing, setPlatEditing] = useState<ThirdPartyPlatform | null>(null)
  const [platForm, setPlatForm] = useState<ThirdPartyPlatformInput>({ name: "", commissionRate: 0 })

  // Unassigned delivery orders (show automatically)
  const [pendingDeliveries, setPendingDeliveries] = useState<Order[]>([])

  // Dispatch dialog
  const [dispatchOpen, setDispatchOpen] = useState(false)
  const [deliveryOrders, setDeliveryOrders] = useState<Order[]>([])
  const [selectedOrderId, setSelectedOrderId] = useState<number | null>(null)
  const [selectedDriverId, setSelectedDriverId] = useState<number | null>(null)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [d, z, a, s, p, allOrd] = await Promise.all([
        listDrivers().catch(() => []),
        listDeliveryZones().catch(() => []),
        listDeliveryAssignments().catch(() => []),
        getDeliveryStats().catch(() => null),
        listPlatforms().catch(() => []),
        listOrders().catch(() => []),
      ])
      setDrivers(d); setZones(z); setAssignments(a); setStats(s); setPlatforms(p)
      // Find delivery orders not yet assigned to a driver
      const assignedOrderIds = new Set(a.map((x: DeliveryAssignment) => x.orderId))
      setPendingDeliveries(allOrd.filter((o: Order) => o.orderType === "Delivery" && !["Completed","Cancelled","Refunded"].includes(o.status) && !assignedOrderIds.has(o.orderId)))
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function loadAssignments() {
    const status = filterAssignStatus === "active" ? undefined : filterAssignStatus === "all" ? undefined : filterAssignStatus
    const [list, allOrd] = await Promise.all([listDeliveryAssignments(status).catch(() => []), listOrders().catch(() => [])])
    setAssignments(filterAssignStatus === "active" ? list.filter(a => !["Delivered","Failed","Cancelled"].includes(a.status)) : list)
    const assignedOrderIds = new Set(list.map((x: DeliveryAssignment) => x.orderId))
    setPendingDeliveries(allOrd.filter((o: Order) => o.orderType === "Delivery" && !["Completed","Cancelled","Refunded"].includes(o.status) && !assignedOrderIds.has(o.orderId)))
  }
  useEffect(() => { if (!loading) loadAssignments() }, [filterAssignStatus])

  // Drivers
  function openDriverDialog(d?: Driver) {
    if (d) { setDriverEditing(d); setDriverForm({ firstName: d.firstName, lastName: d.lastName, phone: d.phone, email: d.email, vehicleType: d.vehicleType, vehiclePlate: d.vehiclePlate, licenseNumber: d.licenseNumber, isActive: d.isActive, notes: d.notes }) }
    else { setDriverEditing(null); setDriverForm({ firstName: "", lastName: "", phone: "", vehicleType: "Motorcycle" }) }
    setDriverDialogOpen(true)
  }
  async function saveDriver() {
    if (!driverForm.firstName.trim() || !driverForm.phone.trim()) { toast({ title: "Name and phone required", variant: "destructive" }); return }
    try {
      if (driverEditing) await updateDriver(driverEditing.driverId, driverForm)
      else await createDriver(driverForm)
      toast({ title: driverEditing ? "Driver updated" : "Driver added" })
      setDriverDialogOpen(false); setDrivers(await listDrivers()); setStats(await getDeliveryStats())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function changeDriverStatus(id: number, status: string) {
    try { await updateDriverStatus(id, status); setDrivers(await listDrivers()); setStats(await getDeliveryStats()); toast({ title: `Driver ${status}` }) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function delDriver(id: number) {
    try { await deleteDriver(id); setDrivers(await listDrivers()); setStats(await getDeliveryStats()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  // Zones
  function openZoneDialog(z?: DeliveryZone) {
    if (z) { setZoneEditing(z); setZoneForm({ name: z.name, minDistanceKm: z.minDistanceKm, maxDistanceKm: z.maxDistanceKm, deliveryFee: z.deliveryFee, estimatedMins: z.estimatedMins, isActive: z.isActive }) }
    else { setZoneEditing(null); setZoneForm({ name: "", minDistanceKm: 0, maxDistanceKm: 5, deliveryFee: 0, estimatedMins: 30, isActive: true }) }
    setZoneDialogOpen(true)
  }
  async function saveZone() {
    if (!zoneForm.name.trim()) { toast({ title: "Zone name required", variant: "destructive" }); return }
    try {
      if (zoneEditing) await updateDeliveryZone(zoneEditing.deliveryZoneId, zoneForm)
      else await createDeliveryZone(zoneForm)
      toast({ title: zoneEditing ? "Zone updated" : "Zone created" }); setZoneDialogOpen(false); setZones(await listDeliveryZones())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function delZone(id: number) { try { await deleteDeliveryZone(id); setZones(await listDeliveryZones()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  // Platforms
  function openPlatDialog(p?: ThirdPartyPlatform) {
    if (p) { setPlatEditing(p); setPlatForm({ name: p.name, apiKey: p.apiKey, apiSecret: p.apiSecret, storeId: p.storeId, commissionRate: p.commissionRate, autoAccept: p.autoAccept, isEnabled: p.isEnabled }) }
    else { setPlatEditing(null); setPlatForm({ name: "", commissionRate: 0, isEnabled: false }) }
    setPlatDialogOpen(true)
  }
  async function savePlat() {
    if (!platForm.name.trim()) { toast({ title: "Platform name required", variant: "destructive" }); return }
    try {
      if (platEditing) await updatePlatform(platEditing.platformId, platForm)
      else await createPlatform(platForm)
      toast({ title: platEditing ? "Platform updated" : "Platform added" }); setPlatDialogOpen(false); setPlatforms(await listPlatforms())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function delPlat(id: number) { try { await deletePlatform(id); setPlatforms(await listPlatforms()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  // Assignment status
  async function changeAssignStatus(id: number, status: string) {
    try { await updateAssignmentStatus(id, status); loadAssignments(); setStats(await getDeliveryStats()); setDrivers(await listDrivers()); toast({ title: `Delivery ${status}` }) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  // Dispatch — assign driver to delivery order
  async function openDispatch(preselectedOrder?: Order) {
    if (preselectedOrder) {
      setDeliveryOrders([preselectedOrder])
      setSelectedOrderId(preselectedOrder.orderId)
    } else {
      setDeliveryOrders([...pendingDeliveries])
      setSelectedOrderId(null)
    }
    setSelectedDriverId(null); setDispatchOpen(true)
  }
  async function handleDispatch() {
    if (!selectedOrderId || !selectedDriverId) { toast({ title: "Select both order and driver", variant: "destructive" }); return }
    const order = [...pendingDeliveries, ...deliveryOrders].find(o => o.orderId === selectedOrderId)
    const driver = drivers.find(d => d.driverId === selectedDriverId)
    if (!order || !driver) return
    try {
      await createDeliveryAssignment(order.orderId, order.orderNumber, driver.driverId, order.notes || undefined)
      toast({ title: "Driver assigned", description: `${driver.firstName} assigned to ${order.orderNumber}` })
      setDispatchOpen(false); loadAssignments(); setStats(await getDeliveryStats()); setDrivers(await listDrivers())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center">
                <Truck className="h-5 w-5 text-rose-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-gray-900">Delivery Management</h1>
                <p className="text-sm text-muted-foreground">Drivers, zones, dispatch and third-party platforms</p>
              </div>
            </div>

            {/* Stats */}
            {stats && (
              <div className="grid grid-cols-5 gap-3">
                {[["Available Drivers", stats.availableDrivers, "text-green-600"], ["On Delivery", stats.onDeliveryDrivers, "text-blue-600"],
                  ["Active", stats.activeCount, "text-purple-600"], ["Delivered Today", stats.deliveredCount, "text-gray-600"],
                  ["Avg Time", stats.avgDeliveryMins ? `${stats.avgDeliveryMins.toFixed(0)}m` : "—", "text-orange-600"]
                ].map(([label, val, color]) => (
                  <Card key={String(label)}><CardContent className="py-3 text-center">
                    <div className={`text-2xl font-bold ${color}`}>{val}</div><div className="text-xs text-muted-foreground">{label}</div>
                  </CardContent></Card>
                ))}
              </div>
            )}

            <Tabs defaultValue="deliveries">
              <TabsList>
                <TabsTrigger value="deliveries">Deliveries {pendingDeliveries.length > 0 && <Badge className="ml-1 bg-amber-500 text-white h-5 px-1.5">{pendingDeliveries.length}</Badge>}</TabsTrigger>
                <TabsTrigger value="drivers">Drivers ({drivers.length})</TabsTrigger>
                <TabsTrigger value="zones">Zones ({zones.length})</TabsTrigger>
                <TabsTrigger value="platforms">Third-Party ({platforms.length})</TabsTrigger>
              </TabsList>

              {/* Deliveries */}
              <TabsContent value="deliveries" className="space-y-4">
                {/* Pending delivery orders awaiting driver assignment */}
                {pendingDeliveries.length > 0 && (
                  <Card className="border-amber-200 bg-amber-50">
                    <CardHeader className="pb-2">
                      <CardTitle className="text-base flex items-center gap-2">
                        <Package className="h-5 w-5 text-amber-600" />
                        Awaiting Driver Assignment ({pendingDeliveries.length})
                      </CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-2">
                        {pendingDeliveries.map(o => (
                          <div key={o.orderId} className="flex items-center justify-between p-3 bg-white border border-amber-200 rounded-lg">
                            <div>
                              <div className="flex items-center gap-2">
                                <span className="font-bold">{o.orderNumber}</span>
                                <Badge className="bg-amber-500 text-white text-xs">Needs Driver</Badge>
                              </div>
                              <div className="text-sm text-muted-foreground">
                                {o.customerName || "Guest"} | {o.totalAmount.toFixed(2)} | {new Date(o.createdAt).toLocaleTimeString()}
                              </div>
                              {o.notes && <div className="text-xs text-muted-foreground"><MapPin className="h-3 w-3 inline" /> {o.notes}</div>}
                            </div>
                            <Button size="sm" className="bg-rose-600 hover:bg-rose-700" onClick={() => openDispatch(o)}>
                              <Truck className="h-4 w-4 mr-1" /> Assign Driver
                            </Button>
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                )}

                <Card>
                  <CardHeader className="flex flex-row items-center justify-between">
                    <CardTitle>Delivery Assignments</CardTitle>
                    <div className="flex gap-2">
                      <Select value={filterAssignStatus} onValueChange={setFilterAssignStatus}>
                        <SelectTrigger className="w-[130px]"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="active">Active</SelectItem>
                          <SelectItem value="all">All</SelectItem>
                          <SelectItem value="Pending">Pending</SelectItem>
                          <SelectItem value="Delivered">Delivered</SelectItem>
                        </SelectContent>
                      </Select>
                      <Button variant="outline" size="icon" onClick={async () => { await loadAssignments(); setStats(await getDeliveryStats()) }}><RefreshCw className="h-4 w-4" /></Button>
                      <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openDispatch()}><Truck className="h-4 w-4 mr-2" /> Dispatch Driver</Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {assignments.length === 0 && pendingDeliveries.length === 0 ? <p className="text-muted-foreground text-sm text-center py-4">No deliveries.</p> :
                    assignments.length === 0 ? <p className="text-muted-foreground text-sm text-center py-4">No assigned deliveries yet. Assign drivers to the orders above.</p> : (
                      <div className="space-y-2">
                        {assignments.map(a => (
                          <div key={a.deliveryAssignmentId} className="flex items-center justify-between p-3 border rounded-lg">
                            <div>
                              <div className="flex items-center gap-2">
                                <span className="font-bold">{a.orderNumber}</span>
                                <Badge className={`text-white text-xs ${ASSIGNMENT_STATUS_COLORS[a.status] || "bg-gray-500"}`}>{a.status}</Badge>
                              </div>
                              <div className="text-sm text-muted-foreground">
                                Driver: {a.driverName || "Unassigned"} {a.driverPhone && `(${a.driverPhone})`}
                                {a.estimatedMins && ` | Est: ${a.estimatedMins}m`}
                                {a.actualMins && ` | Actual: ${a.actualMins}m`}
                                {a.rating && <span> | <Star className="h-3 w-3 inline text-yellow-500" />{a.rating}/5</span>}
                              </div>
                              {a.deliveryAddress && <div className="text-xs text-muted-foreground"><MapPin className="h-3 w-3 inline" /> {a.deliveryAddress}</div>}
                            </div>
                            <div className="flex gap-1">
                              {a.status === "Assigned" && <Button size="sm" onClick={() => changeAssignStatus(a.deliveryAssignmentId, "PickedUp")}>Picked Up</Button>}
                              {a.status === "PickedUp" && <Button size="sm" onClick={() => changeAssignStatus(a.deliveryAssignmentId, "EnRoute")}>En Route</Button>}
                              {a.status === "EnRoute" && <Button size="sm" className="bg-green-600" onClick={() => changeAssignStatus(a.deliveryAssignmentId, "Delivered")}>Delivered</Button>}
                              {["Assigned","PickedUp","EnRoute"].includes(a.status) && <Button size="sm" variant="destructive" onClick={() => changeAssignStatus(a.deliveryAssignmentId, "Failed")}>Failed</Button>}
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Drivers */}
              <TabsContent value="drivers">
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between">
                    <CardTitle className="flex items-center gap-2"><Users className="h-5 w-5" /> Drivers</CardTitle>
                    <Button size="sm" onClick={() => openDriverDialog()}><Plus className="h-4 w-4 mr-1" /> Add Driver</Button>
                  </CardHeader>
                  <CardContent>
                    {drivers.length === 0 ? <p className="text-muted-foreground text-sm">No drivers.</p> : (
                      <div className="space-y-2">
                        {drivers.map(d => (
                          <div key={d.driverId} className="flex items-center justify-between p-3 border rounded-lg">
                            <div>
                              <div className="flex items-center gap-2">
                                <span className="font-medium">{d.firstName} {d.lastName}</span>
                                <Badge className={`text-white text-xs ${DRIVER_STATUS_COLORS[d.status]}`}>{d.status}</Badge>
                                <Badge variant="outline" className="text-xs">{d.vehicleType}</Badge>
                              </div>
                              <div className="text-sm text-muted-foreground">
                                {d.phone} {d.vehiclePlate && `| ${d.vehiclePlate}`}
                                | Deliveries: {d.totalDeliveries} {d.activeDeliveries > 0 && `(${d.activeDeliveries} active)`}
                                {d.avgRating && <span> | <Star className="h-3 w-3 inline text-yellow-500" />{d.avgRating.toFixed(1)}</span>}
                              </div>
                            </div>
                            <div className="flex gap-1">
                              {d.status === "OffDuty" && <Button size="sm" variant="outline" onClick={() => changeDriverStatus(d.driverId, "Available")}>Clock In</Button>}
                              {d.status === "Available" && <Button size="sm" variant="outline" onClick={() => changeDriverStatus(d.driverId, "OffDuty")}>Clock Out</Button>}
                              <Button variant="ghost" size="icon" onClick={() => openDriverDialog(d)}><Edit2 className="h-4 w-4" /></Button>
                              <Button variant="ghost" size="icon" onClick={() => delDriver(d.driverId)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Zones */}
              <TabsContent value="zones">
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between">
                    <CardTitle className="flex items-center gap-2"><MapPin className="h-5 w-5" /> Delivery Zones</CardTitle>
                    <Button size="sm" onClick={() => openZoneDialog()}><Plus className="h-4 w-4 mr-1" /> Add Zone</Button>
                  </CardHeader>
                  <CardContent>
                    {zones.length === 0 ? <p className="text-muted-foreground text-sm">No zones configured.</p> : (
                      <div className="space-y-2">
                        {zones.map(z => (
                          <div key={z.deliveryZoneId} className="flex items-center justify-between p-3 border rounded-lg">
                            <div>
                              <span className="font-medium">{z.name}</span>
                              <div className="text-sm text-muted-foreground">
                                {z.minDistanceKm}-{z.maxDistanceKm} km | Fee: {z.deliveryFee.toFixed(2)} | Est: {z.estimatedMins}min
                              </div>
                            </div>
                            <div className="flex gap-1">
                              <Badge variant={z.isActive ? "default" : "secondary"}>{z.isActive ? "Active" : "Inactive"}</Badge>
                              <Button variant="ghost" size="icon" onClick={() => openZoneDialog(z)}><Edit2 className="h-4 w-4" /></Button>
                              <Button variant="ghost" size="icon" onClick={() => delZone(z.deliveryZoneId)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Third-Party Platforms */}
              <TabsContent value="platforms">
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between">
                    <CardTitle className="flex items-center gap-2"><Package className="h-5 w-5" /> Third-Party Platforms</CardTitle>
                    <Button size="sm" onClick={() => openPlatDialog()}><Plus className="h-4 w-4 mr-1" /> Add Platform</Button>
                  </CardHeader>
                  <CardContent>
                    {platforms.length === 0 ? <p className="text-muted-foreground text-sm">No platforms configured. Add Uber Eats, Glovo, etc.</p> : (
                      <div className="space-y-2">
                        {platforms.map(p => (
                          <div key={p.platformId} className="flex items-center justify-between p-3 border rounded-lg">
                            <div>
                              <div className="flex items-center gap-2">
                                <span className="font-medium">{p.name}</span>
                                <Badge variant={p.isEnabled ? "default" : "secondary"}>{p.isEnabled ? "Enabled" : "Disabled"}</Badge>
                              </div>
                              <div className="text-sm text-muted-foreground">
                                Commission: {p.commissionRate}% | Orders: {p.orderCount} | Revenue: {p.totalRevenue.toFixed(2)}
                                {p.autoAccept && " | Auto-accept"}
                              </div>
                            </div>
                            <div className="flex gap-1">
                              <Button variant="ghost" size="icon" onClick={() => openPlatDialog(p)}><Edit2 className="h-4 w-4" /></Button>
                              <Button variant="ghost" size="icon" onClick={() => delPlat(p.platformId)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      {/* Driver Dialog */}
      <Dialog open={driverDialogOpen} onOpenChange={setDriverDialogOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>{driverEditing ? "Edit Driver" : "Add Driver"}</DialogTitle><DialogDescription>Manage delivery driver details</DialogDescription></DialogHeader>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div><Label>First Name *</Label><Input value={driverForm.firstName} onChange={e => setDriverForm({ ...driverForm, firstName: e.target.value })} /></div>
              <div><Label>Last Name *</Label><Input value={driverForm.lastName} onChange={e => setDriverForm({ ...driverForm, lastName: e.target.value })} /></div>
              <div><Label>Phone *</Label><Input value={driverForm.phone} onChange={e => setDriverForm({ ...driverForm, phone: e.target.value })} /></div>
              <div><Label>Email</Label><Input value={driverForm.email || ""} onChange={e => setDriverForm({ ...driverForm, email: e.target.value })} /></div>
            </div>
            <div className="grid grid-cols-3 gap-3">
              <div><Label>Vehicle</Label>
                <Select value={driverForm.vehicleType || "Motorcycle"} onValueChange={v => setDriverForm({ ...driverForm, vehicleType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{VEHICLES.map(v => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent>
                </Select></div>
              <div><Label>Plate</Label><Input value={driverForm.vehiclePlate || ""} onChange={e => setDriverForm({ ...driverForm, vehiclePlate: e.target.value })} /></div>
              <div><Label>License</Label><Input value={driverForm.licenseNumber || ""} onChange={e => setDriverForm({ ...driverForm, licenseNumber: e.target.value })} /></div>
            </div>
          </div>
          <DialogFooter><Button onClick={saveDriver}>{driverEditing ? "Update" : "Add Driver"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Zone Dialog */}
      <Dialog open={zoneDialogOpen} onOpenChange={setZoneDialogOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>{zoneEditing ? "Edit Zone" : "Add Zone"}</DialogTitle><DialogDescription>Configure delivery zone</DialogDescription></DialogHeader>
          <div className="space-y-3">
            <div><Label>Name *</Label><Input value={zoneForm.name} onChange={e => setZoneForm({ ...zoneForm, name: e.target.value })} placeholder="e.g. Zone A - 0-3km" /></div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Min Distance (km)</Label><Input type="number" step="0.1" value={zoneForm.minDistanceKm || 0} onChange={e => setZoneForm({ ...zoneForm, minDistanceKm: parseFloat(e.target.value) || 0 })} /></div>
              <div><Label>Max Distance (km)</Label><Input type="number" step="0.1" value={zoneForm.maxDistanceKm || 5} onChange={e => setZoneForm({ ...zoneForm, maxDistanceKm: parseFloat(e.target.value) || 5 })} /></div>
              <div><Label>Delivery Fee</Label><Input type="number" step="0.01" value={zoneForm.deliveryFee || 0} onChange={e => setZoneForm({ ...zoneForm, deliveryFee: parseFloat(e.target.value) || 0 })} /></div>
              <div><Label>Est. Minutes</Label><Input type="number" value={zoneForm.estimatedMins || 30} onChange={e => setZoneForm({ ...zoneForm, estimatedMins: parseInt(e.target.value) || 30 })} /></div>
            </div>
          </div>
          <DialogFooter><Button onClick={saveZone}>{zoneEditing ? "Update" : "Create"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Platform Dialog */}
      <Dialog open={platDialogOpen} onOpenChange={setPlatDialogOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>{platEditing ? "Edit Platform" : "Add Platform"}</DialogTitle><DialogDescription>Third-party delivery platform</DialogDescription></DialogHeader>
          <div className="space-y-3">
            <div><Label>Platform Name *</Label><Input value={platForm.name} onChange={e => setPlatForm({ ...platForm, name: e.target.value })} placeholder="e.g. Uber Eats, Glovo" /></div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Store ID</Label><Input value={platForm.storeId || ""} onChange={e => setPlatForm({ ...platForm, storeId: e.target.value })} /></div>
              <div><Label>Commission %</Label><Input type="number" step="0.1" value={platForm.commissionRate || 0} onChange={e => setPlatForm({ ...platForm, commissionRate: parseFloat(e.target.value) || 0 })} /></div>
            </div>
            <div className="flex gap-4">
              <label className="flex items-center gap-2"><input type="checkbox" checked={platForm.isEnabled || false} onChange={e => setPlatForm({ ...platForm, isEnabled: e.target.checked })} />Enabled</label>
              <label className="flex items-center gap-2"><input type="checkbox" checked={platForm.autoAccept || false} onChange={e => setPlatForm({ ...platForm, autoAccept: e.target.checked })} />Auto-Accept Orders</label>
            </div>
          </div>
          <DialogFooter><Button onClick={savePlat}>{platEditing ? "Update" : "Add Platform"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dispatch Dialog */}
      <Dialog open={dispatchOpen} onOpenChange={setDispatchOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>Dispatch Driver</DialogTitle><DialogDescription>Assign a driver to a delivery order</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Select Delivery Order</Label>
              {deliveryOrders.length === 0 ? (
                <p className="text-sm text-muted-foreground py-2">No pending delivery orders to assign.</p>
              ) : (
                <Select onValueChange={v => setSelectedOrderId(parseInt(v))}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="Choose an order..." /></SelectTrigger>
                  <SelectContent>
                    {deliveryOrders.map(o => (
                      <SelectItem key={o.orderId} value={String(o.orderId)}>
                        {o.orderNumber} — {o.customerName || "Guest"} ({o.totalAmount.toFixed(2)})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
            <div className="space-y-1.5">
              <Label>Select Driver</Label>
              <Select onValueChange={v => setSelectedDriverId(parseInt(v))}>
                <SelectTrigger className="h-10"><SelectValue placeholder="Choose a driver..." /></SelectTrigger>
                <SelectContent>
                  {drivers.filter(d => d.status === "Available").map(d => (
                    <SelectItem key={d.driverId} value={String(d.driverId)}>
                      {d.firstName} {d.lastName} ({d.vehicleType})
                    </SelectItem>
                  ))}
                  {drivers.filter(d => d.status === "Available").length === 0 && (
                    <div className="px-2 py-3 text-sm text-muted-foreground">No available drivers</div>
                  )}
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDispatchOpen(false)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleDispatch} disabled={!selectedOrderId || !selectedDriverId}>
              <Truck className="h-4 w-4 mr-2" /> Assign Driver
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

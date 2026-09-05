"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Trash2, Edit2, MapPin, Users, CheckCircle2 } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listFloors, createFloor, updateFloor, deleteFloor,
  listTables, createTable, updateTable, deleteTable, updateTableStatus,
  type Floor, type FloorInput, type RestaurantTable, type TableInput,
} from "@/lib/api/restaurant"

const STATUS_CONFIG: Record<string, { color: string; bg: string; border: string; label: string }> = {
  Available: { color: "text-green-700", bg: "bg-green-50", border: "border-green-300", label: "Available" },
  Occupied: { color: "text-red-700", bg: "bg-red-50", border: "border-red-300", label: "Occupied" },
  Reserved: { color: "text-blue-700", bg: "bg-blue-50", border: "border-blue-300", label: "Reserved" },
  NeedsCleaning: { color: "text-amber-700", bg: "bg-amber-50", border: "border-amber-300", label: "Needs Cleaning" },
  OutOfService: { color: "text-gray-700", bg: "bg-gray-100", border: "border-gray-300", label: "Out of Service" },
}
const SHAPES = ["Square", "Round", "Booth", "Bar", "Long"]

export default function RestaurantFloorPlanPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [floors, setFloors] = useState<Floor[]>([])
  const [tables, setTables] = useState<RestaurantTable[]>([])
  const [activeFloor, setActiveFloor] = useState<number | null>(null)
  const [floorDialogOpen, setFloorDialogOpen] = useState(false)
  const [floorEditing, setFloorEditing] = useState<Floor | null>(null)
  const [floorForm, setFloorForm] = useState<FloorInput>({ name: "", floorNumber: 0 })
  const [tableDialogOpen, setTableDialogOpen] = useState(false)
  const [tableEditing, setTableEditing] = useState<RestaurantTable | null>(null)
  const [tableForm, setTableForm] = useState<TableInput>({ tableNumber: "", capacity: 4, shape: "Square" })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [fl, tb] = await Promise.all([listFloors(), listTables()])
      setFloors(fl); setTables(tb)
      if (fl.length > 0 && !activeFloor) setActiveFloor(fl[0].floorId)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openFloorDialog(f?: Floor) {
    if (f) { setFloorEditing(f); setFloorForm({ name: f.name, floorNumber: f.floorNumber, description: f.description, isActive: f.isActive }) }
    else { setFloorEditing(null); setFloorForm({ name: "", floorNumber: floors.length, isActive: true }) }
    setFloorDialogOpen(true)
  }
  async function saveFloor() {
    if (!floorForm.name.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    const duplicate = floors.find(f => f.name.toLowerCase() === floorForm.name.trim().toLowerCase() && (!floorEditing || f.floorId !== floorEditing.floorId))
    if (duplicate) { toast({ title: "Duplicate name", description: `An area named "${floorForm.name}" already exists.`, variant: "destructive" }); return }
    try {
      if (floorEditing) await updateFloor(floorEditing.floorId, floorForm); else await createFloor(floorForm)
      toast({ title: floorEditing ? "Updated" : "Created" }); setFloorDialogOpen(false)
      const fl = await listFloors(); setFloors(fl); if (!activeFloor && fl.length > 0) setActiveFloor(fl[0].floorId)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function removeFloor(id: number) { try { await deleteFloor(id); toast({ title: "Deleted" }); setFloors(await listFloors()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  function openTableDialog(t?: RestaurantTable) {
    if (t) { setTableEditing(t); setTableForm({ floorId: t.floorId, tableNumber: t.tableNumber, tableName: t.tableName, capacity: t.capacity, shape: t.shape, isActive: t.isActive }) }
    else { setTableEditing(null); setTableForm({ floorId: activeFloor, tableNumber: "", capacity: 4, shape: "Square", isActive: true }) }
    setTableDialogOpen(true)
  }
  async function saveTable() {
    if (!tableForm.tableNumber.trim()) { toast({ title: "Number required", variant: "destructive" }); return }
    try {
      if (tableEditing) await updateTable(tableEditing.tableId, tableForm); else await createTable(tableForm)
      toast({ title: tableEditing ? "Updated" : "Created" }); setTableDialogOpen(false); setTables(await listTables())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function removeTable(id: number) { try { await deleteTable(id); toast({ title: "Deleted" }); setTables(await listTables()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function changeTableStatus(id: number, status: string) {
    try { await updateTableStatus(id, status); setTables(await listTables()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const floorTables = tables.filter(t => activeFloor ? t.floorId === activeFloor : true)
  const statusCounts = Object.fromEntries(Object.keys(STATUS_CONFIG).map(s => [s, tables.filter(t => t.status === s).length]))

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center"><MapPin className="h-5 w-5 text-rose-600" /></div>
                <div>
                  <h1 className="text-2xl font-bold text-gray-900">Restaurant Areas</h1>
                  <p className="text-sm text-muted-foreground">Manage your dining areas and table layout. {tables.length} tables across {floors.length} areas.</p>
                </div>
              </div>
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => openFloorDialog()}><Plus className="h-4 w-4 mr-2" /> Add Area</Button>
                <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openTableDialog()}><Plus className="h-4 w-4 mr-2" /> Add Table</Button>
              </div>
            </div>

            {/* Status legend */}
            <div className="flex gap-4 flex-wrap">
              {Object.entries(STATUS_CONFIG).map(([status, cfg]) => (
                <div key={status} className="flex items-center gap-2">
                  <div className={`w-3 h-3 rounded-full ${cfg.bg} border ${cfg.border}`} />
                  <span className="text-sm text-muted-foreground">{cfg.label}: <strong>{statusCounts[status] || 0}</strong></span>
                </div>
              ))}
            </div>

            {/* Floor tabs */}
            {floors.length > 0 && (
              <div className="flex items-center gap-2">
                <Tabs value={String(activeFloor || floors[0]?.floorId)} onValueChange={v => setActiveFloor(parseInt(v))}>
                  <TabsList className="bg-white border shadow-sm">
                    {floors.map(f => (
                      <TabsTrigger key={f.floorId} value={String(f.floorId)} className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                        {f.name} <Badge variant="secondary" className="ml-1.5 h-5 px-1.5 text-[10px]">{f.tableCount}</Badge>
                      </TabsTrigger>
                    ))}
                  </TabsList>
                </Tabs>
                {floors.map(f => f.floorId === activeFloor && (
                  <div key={f.floorId} className="flex gap-1">
                    <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openFloorDialog(f)}><Edit2 className="h-3 w-3" /></Button>
                    <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => removeFloor(f.floorId)}><Trash2 className="h-3 w-3 text-red-500" /></Button>
                  </div>
                ))}
              </div>
            )}

            {/* Table grid */}
            <Card>
              <CardContent className="pt-6">
                {floorTables.length === 0 ? (
                  <div className="text-center py-16 border-2 border-dashed rounded-xl">
                    <MapPin className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                    <h3 className="font-medium text-gray-900 mb-1">{floors.length === 0 ? "No areas created yet" : "No tables on this floor"}</h3>
                    <p className="text-sm text-muted-foreground mb-4">{floors.length === 0 ? "Create areas like Ground Floor, Patio, Rooftop first" : "Add tables to this area"}</p>
                    <Button variant="outline" onClick={() => floors.length === 0 ? openFloorDialog() : openTableDialog()}>
                      <Plus className="h-4 w-4 mr-2" /> {floors.length === 0 ? "Create first area" : "Add first table"}
                    </Button>
                  </div>
                ) : (
                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                    {floorTables.map(t => {
                      const cfg = STATUS_CONFIG[t.status] || STATUS_CONFIG.Available
                      return (
                        <div key={t.tableId} className={`group relative border-2 rounded-2xl p-4 text-center transition-all hover:shadow-md ${cfg.border} ${cfg.bg}`}>
                          <div className="font-bold text-2xl text-gray-900">{t.tableNumber}</div>
                          {t.tableName && <div className="text-xs text-muted-foreground mt-0.5">{t.tableName}</div>}
                          <div className="flex items-center justify-center gap-1 mt-2">
                            <Users className="h-3.5 w-3.5 text-muted-foreground" />
                            <span className="text-sm text-muted-foreground">{t.capacity}</span>
                          </div>
                          <Badge variant="outline" className="mt-2 text-[10px]">{t.shape}</Badge>
                          <div className="mt-2">
                            <Badge className={`text-[10px] ${cfg.bg} ${cfg.color} border ${cfg.border} hover:${cfg.bg}`}>{cfg.label}</Badge>
                          </div>
                          {/* Quick actions */}
                          <div className="mt-3 flex gap-1 justify-center flex-wrap">
                            {t.status !== "Available" && <Button variant="ghost" size="sm" className="h-6 text-[10px] px-2 text-green-700 hover:bg-green-100" onClick={() => changeTableStatus(t.tableId, "Available")}>Free</Button>}
                            {t.status !== "Reserved" && t.status !== "Occupied" && <Button variant="ghost" size="sm" className="h-6 text-[10px] px-2 text-blue-700 hover:bg-blue-100" onClick={() => changeTableStatus(t.tableId, "Reserved")}>Reserve</Button>}
                            {t.status === "NeedsCleaning" && <Button variant="ghost" size="sm" className="h-6 text-[10px] px-2 text-green-700 hover:bg-green-100" onClick={() => changeTableStatus(t.tableId, "Available")}><CheckCircle2 className="h-3 w-3 mr-0.5" />Clean</Button>}
                          </div>
                          {/* Edit/delete */}
                          <div className="absolute top-1 right-1 flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                            <Button variant="ghost" size="icon" className="h-6 w-6 bg-white/80" onClick={() => openTableDialog(t)}><Edit2 className="h-3 w-3" /></Button>
                            <Button variant="ghost" size="icon" className="h-6 w-6 bg-white/80" onClick={() => removeTable(t.tableId)}><Trash2 className="h-3 w-3 text-red-500" /></Button>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>

      {/* Floor Dialog */}
      <Dialog open={floorDialogOpen} onOpenChange={setFloorDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>{floorEditing ? "Edit Area" : "Add Area"}</DialogTitle><DialogDescription>Create a section of your restaurant (e.g. Ground Floor, Patio)</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5"><Label>Area Name <span className="text-rose-500">*</span></Label><Input value={floorForm.name} onChange={e => setFloorForm({ ...floorForm, name: e.target.value })} placeholder="e.g. Ground Floor, Rooftop" className="h-10" /></div>
            <div className="space-y-1.5"><Label>Description</Label><Input value={floorForm.description || ""} onChange={e => setFloorForm({ ...floorForm, description: e.target.value })} placeholder="Optional description" className="h-10" /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setFloorDialogOpen(false)}>Cancel</Button><Button onClick={saveFloor} className="bg-rose-600 hover:bg-rose-700">{floorEditing ? "Update" : "Create Area"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Table Dialog */}
      <Dialog open={tableDialogOpen} onOpenChange={setTableDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>{tableEditing ? "Edit Table" : "Add Table"}</DialogTitle><DialogDescription>Configure table number, capacity and type</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Table Number <span className="text-rose-500">*</span></Label><Input value={tableForm.tableNumber} onChange={e => setTableForm({ ...tableForm, tableNumber: e.target.value })} placeholder="e.g. 1, A1" className="h-10" /></div>
              <div className="space-y-1.5"><Label>Display Name</Label><Input value={tableForm.tableName || ""} onChange={e => setTableForm({ ...tableForm, tableName: e.target.value })} placeholder="e.g. Window Seat" className="h-10" /></div>
            </div>
            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-1.5"><Label>Capacity</Label><Input type="number" min={1} value={tableForm.capacity || 4} onChange={e => setTableForm({ ...tableForm, capacity: parseInt(e.target.value) || 4 })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Shape</Label>
                <Select value={tableForm.shape || "Square"} onValueChange={v => setTableForm({ ...tableForm, shape: v })}>
                  <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                  <SelectContent>{SHAPES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select></div>
              <div className="space-y-1.5"><Label>Area</Label>
                <Select value={tableForm.floorId ? String(tableForm.floorId) : "none"} onValueChange={v => setTableForm({ ...tableForm, floorId: v === "none" ? null : parseInt(v) })}>
                  <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                  <SelectContent><SelectItem value="none">Unassigned</SelectItem>{floors.map(f => <SelectItem key={f.floorId} value={String(f.floorId)}>{f.name}</SelectItem>)}</SelectContent>
                </Select></div>
            </div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setTableDialogOpen(false)}>Cancel</Button><Button onClick={saveTable} className="bg-rose-600 hover:bg-rose-700">{tableEditing ? "Update" : "Add Table"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

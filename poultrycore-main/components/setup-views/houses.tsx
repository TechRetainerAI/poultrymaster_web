"use client"

import { useSetupEmbedded, shellClass, SetupTaskBar, SetupTabTools } from "@/components/setup/setup-embed"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Home, Plus, Pencil, Trash2, Loader2, Layers, LayoutGrid, List, Search, MapPin } from "lucide-react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { houseOccupancy, type HouseOccupancy } from "@/components/poultry/house-picker"
import { cn } from "@/lib/utils"
import { usePagination } from "@/hooks/use-pagination"
import { DataPagination } from "@/components/ui/data-pagination"
import { getHouses, createHouse, updateHouse, deleteHouse } from "@/lib/api/house"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { BulkHouseDialog } from "@/components/poultry/bulk-house-dialog"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"

export function HousesPage() {
  const embedded = useSetupEmbedded()
  const router = useRouter()
  const { toast } = useToast()
  const [houses, setHouses] = useState<any[]>([])
  // Birds per house, so an occupied pen can say why it cannot be deleted rather
  // than offering a button that will be refused. The server refuses it too
  // (sphouse_delete, migration 327) — this is so nobody has to find out that way.
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [loading, setLoading] = useState(true)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingHouse, setDeletingHouse] = useState<any | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)

  const [dialogOpen, setDialogOpen] = useState(false)
  const [bulkDialogOpen, setBulkDialogOpen] = useState(false)
  const [editing, setEditing] = useState<any | null>(null)
  const [name, setName] = useState("")
  const [capacity, setCapacity] = useState<string>("")
  const [location, setLocation] = useState<string>("")
  const [saving, setSaving] = useState(false)
  // Cards or table; remembered per browser.
  const [view, setView] = useState<"cards" | "table">("cards")
  const [search, setSearch] = useState("")
  useEffect(() => {
    try { const v = localStorage.getItem("houses-view"); if (v === "table" || v === "cards") setView(v) } catch {}
  }, [])
  const changeView = (v: "cards" | "table") => {
    setView(v)
    try { localStorage.setItem("houses-view", v) } catch {}
  }

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    router.push("/login")
  }

  const load = async () => {
    try {
      setLoading(true)
      const { userId, farmId } = getUserContext()
      if (!userId) throw new Error("User not found")
      if (!farmId) throw new Error("Farm not selected")
      const [res, flockRes] = await Promise.all([
        getHouses(userId, farmId),
        getFlocks(userId, farmId),
      ])
      if (res.success && res.data) setHouses(res.data as any[])
      else toast({ title: "Could not load houses", description: res.message || "Failed to load houses", variant: "destructive" })
      if (flockRes.success && flockRes.data) setFlocks(flockRes.data)
    } catch (e: any) {
      toast({ title: "Could not load houses", description: e?.message || "Failed to load houses", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const openCreate = () => {
    setEditing(null)
    setName("")
    setCapacity("")
    setLocation("")
    setDialogOpen(true)
  }

  const openEdit = (h: any) => {
    setEditing(h)
    setName(h.name || h.houseName || "")
    setCapacity(h.capacity != null ? String(h.capacity) : "")
    setLocation(h.location || "")
    setDialogOpen(true)
  }

  const submit = async () => {
    try {
      setSaving(true)
      if (!name.trim()) {
        toastFormGuide(toast, "Give this house a name so you can find it later in lists and reports.")
        setSaving(false)
        return
      }
      const { userId, farmId } = getUserContext()
      if (!userId) throw new Error("User not found")
      if (!farmId) throw new Error("Farm not selected")
      const payload = { userId, farmId, name, capacity: capacity ? parseInt(capacity) : null, location: location || null }
      const res = editing ? await updateHouse(editing.houseId, payload) : await createHouse(payload)
      if (!res.success) throw new Error(res.message || "Request failed")
      setDialogOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message || "Save failed", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const openDeleteDialog = (h: any) => {
    setDeletingHouse(h)
    setDeleteDialogOpen(true)
  }

  // Occupancy, on the one definition the rest of the module uses: ACTIVE flocks.
  const occupancy = useMemo(() => {
    const map = new Map<number, { flocks: number; birds: number }>()
    for (const f of flocks) {
      if (f.houseId == null || !f.active) continue
      const at = map.get(f.houseId) ?? { flocks: 0, birds: 0 }
      map.set(f.houseId, { flocks: at.flocks + 1, birds: at.birds + (Number(f.quantity) || 0) })
    }
    return map
  }, [flocks])

  const shown = useMemo(() => {
    const term = search.trim().toLowerCase()
    return houses.filter((h) => !term
      || String(h.name || h.houseName || "").toLowerCase().includes(term)
      || String(h.location || "").toLowerCase().includes(term))
  }, [houses, search])

  // One pager for both views; it snaps back to page 1 when the search changes.
  const pg = usePagination(shown, 10)

  const totals = useMemo(() => {
    let capacity = 0, birds = 0, full = 0
    for (const h of shown) {
      const o = houseOccupancy(h, flocks)
      capacity += o.capacity; birds += o.occupied
      if (o.state === "full") full += 1
    }
    return { capacity, birds, free: Math.max(0, capacity - birds), full }
  }, [shown, flocks])

  // A house holding birds is not deletable: flock.houseid has no foreign key, so
  // the delete would succeed and leave every flock in it pointing at nothing.
  const deleteButton = (h: any, cls: string, iconCls: string) => {
    const held = occupancy.get(h.houseId)
    const blocked = (held?.flocks ?? 0) > 0
    return (
      <Button size="icon" variant="ghost" disabled={blocked}
        onClick={() => openDeleteDialog(h)}
        title={blocked
          ? `Holds ${held!.birds.toLocaleString()} bird${held!.birds === 1 ? "" : "s"} in ${held!.flocks} flock${held!.flocks === 1 ? "" : "s"}. Move or close them before deleting this house.`
          : "Delete this house"}
        className={cn(cls, "text-red-600 disabled:text-slate-300")}>
        <Trash2 className={iconCls} />
      </Button>
    )
  }

  const remove = async () => {
    if (!deletingHouse) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }
    setIsDeleting(true)
    const res = await deleteHouse(deletingHouse.houseId, userId, farmId)
    if (res.success) {
      toast({ title: "House deleted", description: `"${deletingHouse.houseName ?? deletingHouse.name}" has been successfully deleted.` })
      await load()
    } else {
      toast({ title: "Delete failed", description: res.message || "Something went wrong. Please try again.", variant: "destructive" })
    }
    setIsDeleting(false)
    setDeleteDialogOpen(false)
    setDeletingHouse(null)
  }

  return (
    <div className={shellClass(embedded, "flex h-screen bg-slate-50")}>
      {!embedded && <DashboardSidebar onLogout={handleLogout} />}
      <div className={shellClass(embedded, "flex-1 flex flex-col min-w-0")}>
        {!embedded && <DashboardHeader />}
        <main className={embedded ? "min-w-0" : "flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0"}>
          <div className={embedded ? "space-y-3" : "space-y-6"}>
            <div className={embedded ? "hidden" : "flex items-center justify-between"}>
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                  <Home className="w-5 h-5 text-blue-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Houses</h1>
                  <p className="text-slate-600">Manage poultry houses</p>
                </div>
              </div>
              <SetupTaskBar tasks={[
                { id: "add", label: "Add House", icon: Plus, primary: true, onClick: openCreate },
                { id: "bulk", label: "Add Multiple Houses/Pens", icon: Layers, onClick: () => setBulkDialogOpen(true) },
              ]} />
            </div>

            {!loading && houses.length > 0 && (
              <SetupTabTools standaloneClassName="flex flex-wrap items-center gap-2">
                <div className={cn("relative", embedded ? "w-full sm:w-64" : "min-w-[220px] flex-1 sm:max-w-sm")}>
                  <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                  <Input className="h-9 bg-white pl-9" placeholder="Search by name or location" value={search} onChange={(e) => setSearch(e.target.value)} />
                </div>
                <span className="whitespace-nowrap text-sm text-slate-500">{shown.length} of {houses.length} houses</span>
                <div className={cn("inline-flex rounded-lg border border-slate-200 bg-white p-0.5", !embedded && "ml-auto")}>
                  {([["cards", LayoutGrid, "Cards"], ["table", List, "Table"]] as const).map(([v, Icon, label]) => (
                    <button key={v} type="button" onClick={() => changeView(v)}
                      className={cn("flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
                        view === v ? "bg-blue-600 text-white shadow-sm" : "text-slate-600 hover:bg-slate-100")}>
                      <Icon className="h-4 w-4" />{label}
                    </button>
                  ))}
                </div>
              </SetupTabTools>
            )}

            {loading ? (
              <div className="text-center py-12 text-slate-600">Loading houses...</div>
            ) : houses.length === 0 ? (
              <Card>
                <CardContent className="text-center py-12">
                  <Home className="h-12 w-12 text-slate-400 mx-auto mb-3" />
                  <p className="text-slate-600">No houses yet.</p>
                </CardContent>
              </Card>
            ) : shown.length === 0 ? (
              <div className="rounded-lg border border-dashed border-slate-300 bg-white py-10 text-center text-sm text-slate-500">
                No house matches &quot;{search}&quot;.
              </div>
            ) : view === "table" ? (
              <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white">
                <Table>
                  <TableHeader>
                    <TableRow className="bg-slate-50">
                      <TableHead className="font-semibold text-slate-900">House</TableHead>
                      <TableHead className="font-semibold text-slate-900">Location</TableHead>
                      <TableHead className="text-right font-semibold text-slate-900">Capacity</TableHead>
                      <TableHead className="text-right font-semibold text-slate-900">Active flocks</TableHead>
                      <TableHead className="text-right font-semibold text-slate-900">Birds in house</TableHead>
                      <TableHead className="min-w-[160px] font-semibold text-slate-900">Used</TableHead>
                      <TableHead className="text-right font-semibold text-slate-900">Free</TableHead>
                      <TableHead className="font-semibold text-slate-900">Status</TableHead>
                      <TableHead className="text-center font-semibold text-slate-900">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {pg.pageItems.map((h) => {
                      const o = houseOccupancy(h, flocks)
                      const pct = o.capacity > 0 ? Math.min(100, Math.round((o.occupied / o.capacity) * 100)) : null
                      return (
                        <TableRow key={h.houseId} className="hover:bg-slate-50">
                          <TableCell className="font-medium text-slate-900">
                            <span className="flex items-center gap-2"><Home className="h-4 w-4 shrink-0 text-blue-600" />{h.name || h.houseName}</span>
                          </TableCell>
                          <TableCell className="text-slate-600">
                            {h.location ? <span className="flex items-center gap-1"><MapPin className="h-3.5 w-3.5 text-slate-400" />{h.location}</span> : <span className="text-slate-400">—</span>}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">{o.capacity > 0 ? o.capacity.toLocaleString() : <span className="text-slate-400">Not set</span>}</TableCell>
                          <TableCell className="text-right tabular-nums">{o.flockCount}</TableCell>
                          <TableCell className="text-right tabular-nums">{o.occupied.toLocaleString()}</TableCell>
                          <TableCell>
                            {pct == null ? <span className="text-xs text-slate-400">—</span> : (
                              <div className="flex items-center gap-2">
                                <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-100">
                                  <div className={cn("h-full rounded-full", pct >= 100 ? "bg-red-500" : pct >= 80 ? "bg-amber-500" : "bg-emerald-500")} style={{ width: `${pct}%` }} />
                                </div>
                                <span className="w-9 text-right text-xs tabular-nums text-slate-600">{pct}%</span>
                              </div>
                            )}
                          </TableCell>
                          <TableCell className={cn("text-right font-semibold tabular-nums", o.state === "full" ? "text-red-600" : "text-emerald-700")}>
                            {o.free != null ? o.free.toLocaleString() : <span className="font-normal text-slate-400">—</span>}
                          </TableCell>
                          <TableCell><StatusPill state={o.state} /></TableCell>
                          <TableCell>
                            <div className="flex items-center justify-center gap-1">
                              <Button size="icon" variant="ghost" onClick={() => openEdit(h)} className="h-8 w-8 hover:bg-blue-50 hover:text-blue-600" title="Edit">
                                <Pencil className="h-4 w-4" />
                              </Button>
                              {deleteButton(h, "h-8 w-8 hover:bg-red-50", "h-4 w-4")}
                            </div>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                    <TableRow className="bg-slate-50 font-semibold">
                      <TableCell colSpan={2} className="text-slate-700">Total, all {shown.length} houses{totals.full > 0 ? ` (${totals.full} full)` : ""}</TableCell>
                      <TableCell className="text-right tabular-nums">{totals.capacity.toLocaleString()}</TableCell>
                      <TableCell />
                      <TableCell className="text-right tabular-nums">{totals.birds.toLocaleString()}</TableCell>
                      <TableCell />
                      <TableCell className="text-right tabular-nums text-emerald-700">{totals.free.toLocaleString()}</TableCell>
                      <TableCell colSpan={2} />
                    </TableRow>
                  </TableBody>
                </Table>
              </div>
            ) : (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {pg.pageItems.map((h) => {
                  const o = houseOccupancy(h, flocks)
                  const pct = o.capacity > 0 ? Math.min(100, Math.round((o.occupied / o.capacity) * 100)) : null
                  return (
                    <Card key={h.houseId} className="gap-0 overflow-hidden p-0 transition-shadow hover:shadow-md">
                      {/* Header: name + location, with the row actions */}
                      <div className="flex items-start justify-between gap-2 border-b border-slate-100 px-4 py-3">
                        <div className="flex min-w-0 items-center gap-2.5">
                          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-blue-50 text-blue-600"><Home className="h-4 w-4" /></span>
                          <div className="min-w-0">
                            <p className="truncate text-sm font-semibold text-slate-900">{h.name || h.houseName}</p>
                            {h.location
                              ? <p className="flex items-center gap-1 truncate text-xs text-slate-500" title={h.location}><MapPin className="h-3 w-3 shrink-0" />{h.location}</p>
                              : <p className="text-xs text-slate-400">No location set</p>}
                          </div>
                        </div>
                        <div className="flex shrink-0 gap-0.5">
                          <Button size="icon" variant="ghost" onClick={() => openEdit(h)} className="h-7 w-7 hover:bg-blue-50 hover:text-blue-600" title="Edit">
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                          {deleteButton(h, "h-7 w-7", "h-3.5 w-3.5")}
                        </div>
                      </div>
                      {/* Body: occupancy at a glance */}
                      <div className="space-y-3 px-4 py-3">
                        <div className="flex items-center justify-between">
                          <StatusPill state={o.state} />
                          <span className="text-xs text-slate-500">{o.flockCount} active {o.flockCount === 1 ? "flock" : "flocks"}</span>
                        </div>
                        {o.capacity > 0 && pct != null ? (
                          <div className="space-y-1.5">
                            <div className="h-1.5 overflow-hidden rounded-full bg-slate-100">
                              <div className={cn("h-full rounded-full", pct >= 100 ? "bg-red-500" : pct >= 80 ? "bg-amber-500" : "bg-emerald-500")} style={{ width: `${pct}%` }} />
                            </div>
                            <div className="flex items-center justify-between text-xs">
                              <span className="tabular-nums text-slate-500">{o.occupied.toLocaleString()} / {o.capacity.toLocaleString()} birds</span>
                              <span className="font-medium text-slate-700">{o.free != null ? `${o.free.toLocaleString()} free` : `${pct}%`}</span>
                            </div>
                          </div>
                        ) : (
                          <p className="text-xs text-slate-400">Capacity not set</p>
                        )}
                      </div>
                    </Card>
                  )
                })}
              </div>
            )}

            {!loading && shown.length > 0 && (
              <DataPagination {...pg.paginationProps} variant="records" />
            )}
          </div>
        </main>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>{editing ? "Edit House" : "Create New House"}</DialogTitle>
            <DialogDescription>
              {editing ? "Update the house information below." : "Add a new poultry house to your farm records."}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-5 py-4 overflow-y-auto pr-1">
            <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
              <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">House Details</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4">
                <div className="space-y-2">
                  <Label htmlFor="name">House Name *</Label>
                  <Input
                    id="name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    required
                    placeholder="House A"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="capacity">Capacity (birds)</Label>
                  <NumberInput
                    id="capacity"
                    
                    min="0"
                    value={capacity}
                    onChange={(e) => setCapacity(e.target.value)}
                    placeholder="1000"
                  />
                </div>
              </div>
            </div>

            <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
              <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Additional Information</div>
              <div className="grid grid-cols-1 gap-4 p-4">
                <div className="space-y-2">
                  <Label htmlFor="location">Location</Label>
                  <Input
                    id="location"
                    value={location}
                    onChange={(e) => setLocation(e.target.value)}
                    placeholder="North Wing"
                  />
                </div>
              </div>
            </div>
          </div>

          <div className="flex justify-end space-x-2 pt-2 border-t">
            <Button onClick={() => setDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
              Cancel
            </Button>
            <Button onClick={submit} disabled={saving} className="bg-blue-600 hover:bg-blue-700">
              {saving ? (
                <span className="flex items-center gap-2">
                  <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
                  Saving...
                </span>
              ) : editing ? (
                "Update House"
              ) : (
                "Create House"
              )}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Bulk creation. Same permission, same endpoint family, same audit
          resource as Add House -- it just does it N times in one transaction. */}
      <BulkHouseDialog
        open={bulkDialogOpen}
        onOpenChange={setBulkDialogOpen}
        existingNames={houses.map((h) => h.name || h.houseName || "")}
        source="Houses page"
        onCreated={load}
      />

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete House</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete &quot;{deletingHouse?.houseName ?? deletingHouse?.name}&quot;? This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={remove} disabled={isDeleting} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              {isDeleting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Deleting...</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

const STATUS: Record<HouseOccupancy["state"], [string, string]> = {
  empty: ["Empty", "bg-emerald-50 text-emerald-700 border-emerald-200"],
  free: ["Has space", "bg-sky-50 text-sky-700 border-sky-200"],
  full: ["Full", "bg-red-50 text-red-700 border-red-200"],
  unknown: ["In use", "bg-slate-50 text-slate-600 border-slate-200"],
}

function StatusPill({ state }: { state: HouseOccupancy["state"] }) {
  const [text, cls] = STATUS[state]
  return <span className={cn("inline-flex rounded-full border px-2 py-0.5 text-xs font-medium", cls)}>{text}</span>
}

"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Plus, Pencil, Trash2, Loader2, Route as RouteIcon, AlertCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterRoutes, createWaterRoute, updateWaterRoute, deleteWaterRoute,
  listWaterVehicles, type WaterRoute, type WaterVehicle,
} from "@/lib/api/water"

type FormState = Omit<WaterRoute, "waterRouteId" | "farmId">
const EMPTY: FormState = { routeName: "", areaCovered: null, defaultDriverStaffId: null, defaultWaterVehicleId: null, expectedCustomers: null, expectedBagsSold: null, notes: null }

export default function WaterRoutesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<WaterRoute[]>([])
  const [vehicles, setVehicles] = useState<WaterVehicle[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterRoute | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try { const [rs, vs] = await Promise.all([listWaterRoutes(), listWaterVehicles()]); setItems(rs); setVehicles(vs) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(r: WaterRoute) {
    setEditId(r.waterRouteId)
    setForm({
      routeName: r.routeName, areaCovered: r.areaCovered, defaultDriverStaffId: r.defaultDriverStaffId,
      defaultWaterVehicleId: r.defaultWaterVehicleId, expectedCustomers: r.expectedCustomers,
      expectedBagsSold: r.expectedBagsSold, notes: r.notes,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.routeName.trim()) return toast({ title: "Route name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterRoute(editId, form); toast({ title: "Route updated" }) }
      else        { await createWaterRoute(form);          toast({ title: "Route added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(r: WaterRoute) {
    await deleteWaterRoute(r.waterRouteId)
    await load()
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <RouteIcon className="h-6 w-6 text-sky-600" /> Routes
            </h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New route</Button>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700"><AlertCircle className="h-4 w-4" /> {error}</CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No routes yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Name</TableHead><TableHead>Area</TableHead><TableHead>Default vehicle</TableHead><TableHead className="text-right">Expected customers</TableHead><TableHead className="text-right">Expected bags</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {items.map((r) => (
                      <TableRow key={r.waterRouteId}>
                        <TableCell className="font-medium">{r.routeName}</TableCell>
                        <TableCell>{r.areaCovered ?? "—"}</TableCell>
                        <TableCell>{vehicles.find(v => v.waterVehicleId === r.defaultWaterVehicleId)?.vehicleName ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.expectedCustomers ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.expectedBagsSold ?? "—"}</TableCell>
                        <TableCell className="text-right">
                          <Button size="sm" variant="ghost" onClick={() => openEdit(r)}><Pencil className="h-4 w-4" /></Button>
                          <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(r)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>{editId ? "Edit route" : "New route"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Route name *</Label>
              <Input value={form.routeName} onChange={(e) => setForm({ ...form, routeName: e.target.value })} placeholder="e.g. Kumasi East" /></div>
            <div className="col-span-2"><Label>Area covered</Label>
              <Input value={form.areaCovered ?? ""} onChange={(e) => setForm({ ...form, areaCovered: e.target.value || null })} /></div>
            <div className="col-span-2"><Label>Default vehicle</Label>
              <Select value={String(form.defaultWaterVehicleId ?? "")} onValueChange={(v) => setForm({ ...form, defaultWaterVehicleId: v ? Number(v) : null })}>
                <SelectTrigger><SelectValue placeholder="(none)" /></SelectTrigger>
                <SelectContent>
                  {vehicles.length === 0 && (
                    <div className="px-2 py-1.5 text-sm text-slate-500">No vehicles. Add one on the Vehicles page first.</div>
                  )}
                  {vehicles.map(v => (
                    <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>
                      {v.vehicleName} ({v.vehicleType}){v.status !== "Active" ? ` — ${v.status}` : ""}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select></div>
            <div><Label>Expected customers</Label>
              <Input type="number" min={0} value={form.expectedCustomers ?? ""} onChange={(e) => setForm({ ...form, expectedCustomers: e.target.value ? Number(e.target.value) : null })} /></div>
            <div><Label>Expected bags/day</Label>
              <Input type="number" min={0} value={form.expectedBagsSold ?? ""} onChange={(e) => setForm({ ...form, expectedBagsSold: e.target.value ? Number(e.target.value) : null })} /></div>
            <div className="col-span-2"><Label>Notes</Label>
              <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value || null })} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? "Saving…" : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Remove route?"
        itemLabel={deleteTarget?.routeName}
        confirmLabel="Remove"
        successTitle="Route removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

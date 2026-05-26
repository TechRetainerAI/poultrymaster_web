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
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Trash2, Loader2, Users2, AlertCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterDrivers, createWaterDriver, updateWaterDriver, deleteWaterDriver,
  listWaterVehicles,
  type WaterDriver, type WaterVehicle,
} from "@/lib/api/water"

type FormState = Omit<WaterDriver, "waterDriverId" | "farmId">
const EMPTY: FormState = {
  driverName: "", phoneNumber: null, licenseNumber: null,
  assignedWaterVehicleId: null, isActive: true, notes: null,
}

export default function WaterDriversPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [drivers, setDrivers] = useState<WaterDriver[]>([])
  const [vehicles, setVehicles] = useState<WaterVehicle[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterDriver | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try {
      const [ds, vs] = await Promise.all([listWaterDrivers(), listWaterVehicles()])
      setDrivers(ds); setVehicles(vs)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(d: WaterDriver) {
    setEditId(d.waterDriverId)
    setForm({
      driverName: d.driverName,
      phoneNumber: d.phoneNumber ?? null,
      licenseNumber: d.licenseNumber ?? null,
      assignedWaterVehicleId: d.assignedWaterVehicleId ?? null,
      isActive: d.isActive,
      notes: d.notes ?? null,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.driverName.trim()) return toast({ title: "Driver name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterDriver(editId, form); toast({ title: "Driver updated" }) }
      else        { await createWaterDriver(form);        toast({ title: "Driver added" }) }
      setOpen(false); setEditId(null); setForm(EMPTY); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(d: WaterDriver) {
    await deleteWaterDriver(d.waterDriverId)
    await load()
  }

  function vehicleLabel(id: number | null | undefined): string {
    if (!id) return "—"
    const v = vehicles.find((x) => x.waterVehicleId === id)
    return v ? `${v.vehicleName} (${v.vehicleType})` : `#${id}`
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Users2 className="h-6 w-6 text-sky-600" /> Drivers
            </h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New driver</Button>
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
              ) : drivers.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No drivers yet. Add one to assign a vehicle.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
                      <TableHead>Phone</TableHead>
                      <TableHead>License</TableHead>
                      <TableHead>Assigned vehicle</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {drivers.map((d) => (
                      <TableRow key={d.waterDriverId}>
                        <TableCell className="font-medium">{d.driverName}</TableCell>
                        <TableCell>{d.phoneNumber ?? "—"}</TableCell>
                        <TableCell>{d.licenseNumber ?? "—"}</TableCell>
                        <TableCell>{vehicleLabel(d.assignedWaterVehicleId)}</TableCell>
                        <TableCell>{d.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                        <TableCell className="text-right">
                          <Button size="sm" variant="ghost" onClick={() => openEdit(d)}><Pencil className="h-4 w-4" /></Button>
                          <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(d)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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

      <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) setEditId(null) }}>
        <DialogContent>
          <DialogHeader><DialogTitle>{editId ? "Edit driver" : "New driver"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Driver name *</Label>
              <Input value={form.driverName} onChange={(e) => setForm({ ...form, driverName: e.target.value })} /></div>
            <div><Label>Phone</Label>
              <Input value={form.phoneNumber ?? ""} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value || null })} /></div>
            <div><Label>License number</Label>
              <Input value={form.licenseNumber ?? ""} onChange={(e) => setForm({ ...form, licenseNumber: e.target.value || null })} /></div>
            <div className="col-span-2"><Label>Assigned vehicle</Label>
              <Select
                value={String(form.assignedWaterVehicleId ?? "")}
                onValueChange={(v) => setForm({ ...form, assignedWaterVehicleId: v ? Number(v) : null })}
              >
                <SelectTrigger><SelectValue placeholder="(none)" /></SelectTrigger>
                <SelectContent>
                  {vehicles.length === 0 && (
                    <div className="px-2 py-1.5 text-sm text-slate-500">No vehicles. Add one on the Vehicles page first.</div>
                  )}
                  {vehicles.map((v) => (
                    <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>
                      {v.vehicleName} ({v.vehicleType}){v.status !== "Active" ? ` — ${v.status}` : ""}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select></div>
            <div className="col-span-2 flex items-center justify-between rounded border p-2">
              <Label>Active</Label>
              <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
            </div>
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
        title="Remove driver?"
        itemLabel={deleteTarget?.driverName}
        confirmLabel="Remove"
        successTitle="Driver removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

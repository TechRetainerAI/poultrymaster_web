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
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Trash2, Loader2, Truck, AlertCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterVehicles, createWaterVehicle, updateWaterVehicle, deleteWaterVehicle,
  type WaterVehicle,
} from "@/lib/api/water"

const TYPES = ["Truck", "MotorKing", "Tricycle", "Van", "Motorbike", "Other"]
const STATUSES = ["Active", "Inactive", "UnderMaintenance"]
const STATUS_COLOR: Record<string, string> = {
  Active: "bg-green-100 text-green-700",
  Inactive: "bg-slate-100 text-slate-700",
  UnderMaintenance: "bg-amber-100 text-amber-700",
}

type FormState = Omit<WaterVehicle, "waterVehicleId" | "farmId">
const EMPTY: FormState = { vehicleName: "", vehicleType: "Truck", registrationNumber: null, defaultDriverStaffId: null, capacityBags: null, fuelType: null, status: "Active", notes: null }

export default function WaterVehiclesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<WaterVehicle[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterVehicle | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try { setItems(await listWaterVehicles()) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(v: WaterVehicle) {
    setEditId(v.waterVehicleId)
    setForm({
      vehicleName: v.vehicleName, vehicleType: v.vehicleType, registrationNumber: v.registrationNumber,
      defaultDriverStaffId: v.defaultDriverStaffId, capacityBags: v.capacityBags, fuelType: v.fuelType,
      status: v.status, notes: v.notes,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.vehicleName.trim()) return toast({ title: "Vehicle name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterVehicle(editId, form); toast({ title: "Vehicle updated" }) }
      else        { await createWaterVehicle(form);         toast({ title: "Vehicle added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(v: WaterVehicle) {
    await deleteWaterVehicle(v.waterVehicleId)
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
              <Truck className="h-6 w-6 text-sky-600" /> Vehicles
            </h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New vehicle</Button>
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
                <div className="p-8 text-center text-slate-500">No vehicles yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Name</TableHead><TableHead>Type</TableHead><TableHead>Reg #</TableHead><TableHead className="text-right">Capacity</TableHead><TableHead>Fuel</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {items.map((v) => (
                      <TableRow key={v.waterVehicleId}>
                        <TableCell className="font-medium">{v.vehicleName}</TableCell>
                        <TableCell><Badge variant="outline">{v.vehicleType}</Badge></TableCell>
                        <TableCell>{v.registrationNumber ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{v.capacityBags ?? "—"}</TableCell>
                        <TableCell>{v.fuelType ?? "—"}</TableCell>
                        <TableCell><Badge className={STATUS_COLOR[v.status] ?? ""}>{v.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          <Button size="sm" variant="ghost" onClick={() => openEdit(v)}><Pencil className="h-4 w-4" /></Button>
                          <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(v)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
          <DialogHeader><DialogTitle>{editId ? "Edit vehicle" : "New vehicle"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Vehicle name *</Label>
              <Input value={form.vehicleName} onChange={(e) => setForm({ ...form, vehicleName: e.target.value })} placeholder="e.g. Truck 1" /></div>
            <div><Label>Type</Label>
              <Select value={form.vehicleType} onValueChange={(v) => setForm({ ...form, vehicleType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Registration #</Label>
              <Input value={form.registrationNumber ?? ""} onChange={(e) => setForm({ ...form, registrationNumber: e.target.value || null })} /></div>
            <div><Label>Capacity (bags)</Label>
              <Input type="number" min={0} value={form.capacityBags ?? ""} onChange={(e) => setForm({ ...form, capacityBags: e.target.value ? Number(e.target.value) : null })} /></div>
            <div><Label>Fuel type</Label>
              <Input value={form.fuelType ?? ""} onChange={(e) => setForm({ ...form, fuelType: e.target.value || null })} placeholder="Petrol / Diesel" /></div>
            <div className="col-span-2"><Label>Status</Label>
              <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{STATUSES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
              </Select></div>
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
        title="Remove vehicle?"
        itemLabel={deleteTarget?.vehicleName}
        confirmLabel="Remove"
        successTitle="Vehicle removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

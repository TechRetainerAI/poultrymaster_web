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
import { Plus, Pencil, Trash2, Loader2, Cog, AlertCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterMachines, createWaterMachine, updateWaterMachine, deleteWaterMachine,
  type WaterMachine,
} from "@/lib/api/water"

const STATUSES = ["Active", "Down", "UnderMaintenance"]
const STATUS_COLOR: Record<string, string> = {
  Active: "bg-green-100 text-green-700",
  Down: "bg-rose-100 text-rose-700",
  UnderMaintenance: "bg-amber-100 text-amber-700",
}

type FormState = Omit<WaterMachine, "waterMachineId" | "farmId">
const EMPTY: FormState = {
  machineName: "", machineNumber: null, machineType: null, manufacturer: null,
  purchaseDate: null, capacityPerHour: null, assignedOperatorStaffId: null,
  maintenanceFrequencyDays: null, lastMaintenanceDate: null, nextMaintenanceDate: null,
  status: "Active", notes: null,
}

export default function WaterMachinesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<WaterMachine[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterMachine | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try { setItems(await listWaterMachines()) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(m: WaterMachine) {
    setEditId(m.waterMachineId)
    setForm({
      machineName: m.machineName, machineNumber: m.machineNumber, machineType: m.machineType, manufacturer: m.manufacturer,
      purchaseDate: m.purchaseDate?.split("T")[0] ?? null,
      capacityPerHour: m.capacityPerHour, assignedOperatorStaffId: m.assignedOperatorStaffId,
      maintenanceFrequencyDays: m.maintenanceFrequencyDays,
      lastMaintenanceDate: m.lastMaintenanceDate?.split("T")[0] ?? null,
      nextMaintenanceDate: m.nextMaintenanceDate?.split("T")[0] ?? null,
      status: m.status, notes: m.notes,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.machineName.trim()) return toast({ title: "Machine name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterMachine(editId, form); toast({ title: "Machine updated" }) }
      else        { await createWaterMachine(form);         toast({ title: "Machine added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(m: WaterMachine) {
    await deleteWaterMachine(m.waterMachineId)
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
              <Cog className="h-6 w-6 text-sky-600" /> Machines
            </h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New machine</Button>
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
                <div className="p-8 text-center text-slate-500">No machines yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Name</TableHead><TableHead>Number</TableHead><TableHead>Type</TableHead><TableHead className="text-right">Capacity/hr</TableHead><TableHead>Next maint.</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {items.map((m) => (
                      <TableRow key={m.waterMachineId}>
                        <TableCell className="font-medium">{m.machineName}</TableCell>
                        <TableCell>{m.machineNumber ?? "—"}</TableCell>
                        <TableCell>{m.machineType ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{m.capacityPerHour ?? "—"}</TableCell>
                        <TableCell>{m.nextMaintenanceDate ? m.nextMaintenanceDate.split("T")[0] : "—"}</TableCell>
                        <TableCell><Badge className={STATUS_COLOR[m.status] ?? ""}>{m.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          <Button size="sm" variant="ghost" onClick={() => openEdit(m)}><Pencil className="h-4 w-4" /></Button>
                          <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(m)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>{editId ? "Edit machine" : "New machine"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Machine name *</Label>
              <Input value={form.machineName} onChange={(e) => setForm({ ...form, machineName: e.target.value })} /></div>
            <div><Label>Machine number</Label>
              <Input value={form.machineNumber ?? ""} onChange={(e) => setForm({ ...form, machineNumber: e.target.value || null })} /></div>
            <div><Label>Type</Label>
              <Input value={form.machineType ?? ""} onChange={(e) => setForm({ ...form, machineType: e.target.value || null })} placeholder="e.g. Sachet filling, Bottling" /></div>
            <div><Label>Manufacturer</Label>
              <Input value={form.manufacturer ?? ""} onChange={(e) => setForm({ ...form, manufacturer: e.target.value || null })} /></div>
            <div><Label>Capacity / hour (bags)</Label>
              <Input type="number" min={0} value={form.capacityPerHour ?? ""} onChange={(e) => setForm({ ...form, capacityPerHour: e.target.value ? Number(e.target.value) : null })} /></div>
            <div><Label>Purchase date</Label>
              <Input type="date" value={form.purchaseDate ?? ""} onChange={(e) => setForm({ ...form, purchaseDate: e.target.value || null })} /></div>
            <div><Label>Status</Label>
              <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{STATUSES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Maintenance frequency (days)</Label>
              <Input type="number" min={0} value={form.maintenanceFrequencyDays ?? ""} onChange={(e) => setForm({ ...form, maintenanceFrequencyDays: e.target.value ? Number(e.target.value) : null })} /></div>
            <div><Label>Last maintenance</Label>
              <Input type="date" value={form.lastMaintenanceDate ?? ""} onChange={(e) => setForm({ ...form, lastMaintenanceDate: e.target.value || null })} /></div>
            <div><Label>Next maintenance</Label>
              <Input type="date" value={form.nextMaintenanceDate ?? ""} onChange={(e) => setForm({ ...form, nextMaintenanceDate: e.target.value || null })} /></div>
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
        title="Remove machine?"
        itemLabel={deleteTarget?.machineName}
        confirmLabel="Remove"
        successTitle="Machine removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

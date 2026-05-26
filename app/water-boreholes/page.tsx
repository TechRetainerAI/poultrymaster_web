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
import { Switch } from "@/components/ui/switch"
import { Plus, Pencil, Trash2, Loader2, Droplets, AlertCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterBoreholes, createWaterBorehole, updateWaterBorehole, deleteWaterBorehole,
  type WaterBorehole,
} from "@/lib/api/water"

const STATUSES = ["Active", "Inactive", "UnderMaintenance"]
const STATUS_COLOR: Record<string, string> = {
  Active: "bg-green-100 text-green-700",
  Inactive: "bg-slate-100 text-slate-700",
  UnderMaintenance: "bg-amber-100 text-amber-700",
}

type FormState = Omit<WaterBorehole, "waterBoreholeId" | "farmId">
const EMPTY: FormState = {
  boreholeName: "", location: null, pumpType: null, pumpCapacity: null, tankCapacity: null,
  waterTreatmentMethod: null, filtrationSystem: null, uvSterilizationAvailable: false,
  maintenanceFrequencyDays: null, lastMaintenanceDate: null, nextMaintenanceDate: null,
  waterQualityTestDueDate: null, status: "Active", notes: null,
}

export default function WaterBoreholesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<WaterBorehole[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterBorehole | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try { setItems(await listWaterBoreholes()) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(b: WaterBorehole) {
    setEditId(b.waterBoreholeId)
    setForm({
      boreholeName: b.boreholeName, location: b.location, pumpType: b.pumpType,
      pumpCapacity: b.pumpCapacity, tankCapacity: b.tankCapacity,
      waterTreatmentMethod: b.waterTreatmentMethod, filtrationSystem: b.filtrationSystem,
      uvSterilizationAvailable: b.uvSterilizationAvailable ?? false,
      maintenanceFrequencyDays: b.maintenanceFrequencyDays,
      lastMaintenanceDate: b.lastMaintenanceDate?.split("T")[0] ?? null,
      nextMaintenanceDate: b.nextMaintenanceDate?.split("T")[0] ?? null,
      waterQualityTestDueDate: b.waterQualityTestDueDate?.split("T")[0] ?? null,
      status: b.status, notes: b.notes,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.boreholeName.trim()) return toast({ title: "Borehole name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterBorehole(editId, form); toast({ title: "Borehole updated" }) }
      else        { await createWaterBorehole(form);          toast({ title: "Borehole added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(b: WaterBorehole) {
    await deleteWaterBorehole(b.waterBoreholeId)
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
              <Droplets className="h-6 w-6 text-sky-600" /> Boreholes
            </h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New borehole</Button>
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
                <div className="p-8 text-center text-slate-500">No boreholes yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Name</TableHead><TableHead>Location</TableHead><TableHead>Treatment</TableHead><TableHead>Next maint.</TableHead><TableHead>Quality test due</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {items.map((b) => (
                      <TableRow key={b.waterBoreholeId}>
                        <TableCell className="font-medium">{b.boreholeName}</TableCell>
                        <TableCell>{b.location ?? "—"}</TableCell>
                        <TableCell>{b.waterTreatmentMethod ?? "—"}</TableCell>
                        <TableCell>{b.nextMaintenanceDate ? b.nextMaintenanceDate.split("T")[0] : "—"}</TableCell>
                        <TableCell>{b.waterQualityTestDueDate ? b.waterQualityTestDueDate.split("T")[0] : "—"}</TableCell>
                        <TableCell><Badge className={STATUS_COLOR[b.status] ?? ""}>{b.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          <Button size="sm" variant="ghost" onClick={() => openEdit(b)}><Pencil className="h-4 w-4" /></Button>
                          <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(b)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
          <DialogHeader><DialogTitle>{editId ? "Edit borehole" : "New borehole"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Borehole name *</Label>
              <Input value={form.boreholeName} onChange={(e) => setForm({ ...form, boreholeName: e.target.value })} /></div>
            <div><Label>Location</Label>
              <Input value={form.location ?? ""} onChange={(e) => setForm({ ...form, location: e.target.value || null })} /></div>
            <div><Label>Pump type</Label>
              <Input value={form.pumpType ?? ""} onChange={(e) => setForm({ ...form, pumpType: e.target.value || null })} /></div>
            <div><Label>Pump capacity</Label>
              <Input type="number" min={0} value={form.pumpCapacity ?? ""} onChange={(e) => setForm({ ...form, pumpCapacity: e.target.value ? Number(e.target.value) : null })} /></div>
            <div><Label>Tank capacity (L)</Label>
              <Input type="number" min={0} value={form.tankCapacity ?? ""} onChange={(e) => setForm({ ...form, tankCapacity: e.target.value ? Number(e.target.value) : null })} /></div>
            <div><Label>Treatment method</Label>
              <Input value={form.waterTreatmentMethod ?? ""} onChange={(e) => setForm({ ...form, waterTreatmentMethod: e.target.value || null })} /></div>
            <div><Label>Filtration</Label>
              <Input value={form.filtrationSystem ?? ""} onChange={(e) => setForm({ ...form, filtrationSystem: e.target.value || null })} /></div>
            <div className="col-span-2 flex items-center justify-between rounded border p-2">
              <Label>UV sterilization available</Label>
              <Switch checked={form.uvSterilizationAvailable ?? false} onCheckedChange={(v) => setForm({ ...form, uvSterilizationAvailable: v })} />
            </div>
            <div><Label>Status</Label>
              <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{STATUSES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Maint. frequency (days)</Label>
              <Input type="number" min={0} value={form.maintenanceFrequencyDays ?? ""} onChange={(e) => setForm({ ...form, maintenanceFrequencyDays: e.target.value ? Number(e.target.value) : null })} /></div>
            <div><Label>Last maintenance</Label>
              <Input type="date" value={form.lastMaintenanceDate ?? ""} onChange={(e) => setForm({ ...form, lastMaintenanceDate: e.target.value || null })} /></div>
            <div><Label>Next maintenance</Label>
              <Input type="date" value={form.nextMaintenanceDate ?? ""} onChange={(e) => setForm({ ...form, nextMaintenanceDate: e.target.value || null })} /></div>
            <div className="col-span-2"><Label>Water quality test due date</Label>
              <Input type="date" value={form.waterQualityTestDueDate ?? ""} onChange={(e) => setForm({ ...form, waterQualityTestDueDate: e.target.value || null })} /></div>
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
        title="Remove borehole?"
        itemLabel={deleteTarget?.boreholeName}
        confirmLabel="Remove"
        successTitle="Borehole removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

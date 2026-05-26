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
import { Plus, Pencil, Trash2, Loader2, Users2, AlertCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterStaff, createWaterStaff, updateWaterStaff, deleteWaterStaff,
  type WaterStaff, type WaterStaffInput,
} from "@/lib/api/water"

const ROLES = ["MachineOperator","PackagingWorker","Loader","Driver","MotorKingRider","Salesperson","FactoryManager","Accountant","Cleaner","Security","Other"]
const SALARY_TYPES = ["Daily","Weekly","Monthly","Commission","Mixed"]

const EMPTY: WaterStaffInput = {
  firstName: "", lastName: "", phoneNumber: "", email: "",
  role: "MachineOperator", salaryType: "Monthly", basePay: 0,
  commissionRate: null, assignedWaterVehicleId: null, assignedWaterRouteId: null,
  isActive: true, notes: "",
}

export default function WaterStaffPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [staff, setStaff] = useState<WaterStaff[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [roleFilter, setRoleFilter] = useState<string>("ALL")

  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<WaterStaffInput>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterStaff | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, roleFilter])

  async function load() {
    setLoading(true); setError(null)
    try { setStaff(await listWaterStaff(roleFilter === "ALL" ? undefined : roleFilter)) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(s: WaterStaff) {
    setEditId(s.waterStaffId)
    setForm({
      firstName: s.firstName, lastName: s.lastName,
      phoneNumber: s.phoneNumber ?? "", email: s.email ?? "",
      role: s.role, salaryType: s.salaryType, basePay: s.basePay,
      commissionRate: s.commissionRate, assignedWaterVehicleId: s.assignedWaterVehicleId, assignedWaterRouteId: s.assignedWaterRouteId,
      isActive: s.isActive, notes: s.notes ?? "",
    })
    setOpen(true)
  }

  async function save() {
    if (!form.firstName.trim() || !form.lastName.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterStaff(editId, form); toast({ title: "Staff updated" }) }
      else        { await createWaterStaff(form);        toast({ title: "Staff added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(s: WaterStaff) {
    await deleteWaterStaff(s.waterStaffId)
    await load()
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Users2 className="h-6 w-6 text-sky-600" /> Water staff
            </h1>
            <div className="flex items-center gap-2">
              <Select value={roleFilter} onValueChange={setRoleFilter}>
                <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All roles</SelectItem>
                  {ROLES.map(r => <SelectItem key={r} value={r}>{r}</SelectItem>)}
                </SelectContent>
              </Select>
              <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New staff</Button>
            </div>
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
              ) : staff.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No staff yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead><TableHead>Role</TableHead><TableHead>Salary type</TableHead>
                      <TableHead className="text-right">Base pay</TableHead>
                      <TableHead>Phone</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {staff.map((s) => (
                      <TableRow key={s.waterStaffId}>
                        <TableCell className="font-medium">{s.firstName} {s.lastName}</TableCell>
                        <TableCell><Badge variant="outline">{s.role}</Badge></TableCell>
                        <TableCell>{s.salaryType}</TableCell>
                        <TableCell className="text-right tabular-nums">{s.basePay.toFixed(2)}</TableCell>
                        <TableCell>{s.phoneNumber ?? "—"}</TableCell>
                        <TableCell>{s.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                        <TableCell className="text-right">
                          <Button size="sm" variant="ghost" onClick={() => openEdit(s)}><Pencil className="h-4 w-4" /></Button>
                          <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(s)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
          <DialogHeader><DialogTitle>{editId ? "Edit staff" : "New staff"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>First name *</Label>
              <Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} /></div>
            <div><Label>Last name *</Label>
              <Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} /></div>
            <div><Label>Phone</Label>
              <Input value={form.phoneNumber ?? ""} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
            <div><Label>Email</Label>
              <Input type="email" value={form.email ?? ""} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
            <div><Label>Role</Label>
              <Select value={form.role} onValueChange={(v) => setForm({ ...form, role: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{ROLES.map(r => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Salary type</Label>
              <Select value={form.salaryType} onValueChange={(v) => setForm({ ...form, salaryType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{SALARY_TYPES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Base pay (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={form.basePay} onChange={(e) => setForm({ ...form, basePay: Number(e.target.value) || 0 })} /></div>
            <div><Label>Commission rate (per bag / %)</Label>
              <Input type="number" step="0.01" value={form.commissionRate ?? ""} onChange={(e) => setForm({ ...form, commissionRate: e.target.value ? Number(e.target.value) : null })} /></div>
            <div className="col-span-2 flex items-center justify-between rounded border p-2">
              <Label>Active</Label>
              <Switch checked={form.isActive ?? true} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
            </div>
            <div className="col-span-2"><Label>Notes</Label>
              <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>
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
        title="Remove staff member?"
        itemLabel={deleteTarget ? `${deleteTarget.firstName} ${deleteTarget.lastName}` : undefined}
        confirmLabel="Remove"
        successTitle="Staff removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

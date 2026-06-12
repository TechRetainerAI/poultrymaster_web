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
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Trash2, Loader2, Users2, AlertCircle, UserPlus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterDrivers, createWaterDriver, updateWaterDriver, deleteWaterDriver,
  listWaterVehicles, listWaterRoutes, listWaterDriversForFarm, createWaterDriverFromEmployee,
  type WaterDriver, type WaterVehicle, type WaterRoute,
} from "@/lib/api/water"
import { getEmployees, createEmployee, type Employee, type CreateEmployeeData } from "@/lib/api/admin"

type FormState = Omit<WaterDriver, "waterDriverId" | "farmId">
const EMPTY: FormState = {
  driverName: "", phoneNumber: null, licenseNumber: null,
  assignedWaterVehicleId: null, isActive: true, notes: null,
}

export default function WaterDriversPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const logout = useLogout()

  const [drivers, setDrivers] = useState<WaterDriver[]>([])
  const [vehicles, setVehicles] = useState<WaterVehicle[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [routes, setRoutes] = useState<WaterRoute[]>([])
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterDriver | null>(null)

  // #18 — "Add existing employee as driver" flow.
  const [employees, setEmployees] = useState<Employee[]>([])
  const [empOpen, setEmpOpen] = useState(false)
  const [empSaving, setEmpSaving] = useState(false)
  // #18 Phase 2: "existing" picks an employee; "new" creates the employee then makes them a driver.
  const [empMode, setEmpMode] = useState<"existing" | "new">("existing")
  const [empForm, setEmpForm] = useState({
    employeeUserId: "", role: "Driver", licenseNumber: "",
    defaultVehicleId: null as number | null, defaultRouteId: null as number | null,
    basePay: 0, commissionPerBag: 0, notes: "",
    // new-employee fields
    firstName: "", lastName: "", phoneNumber: "", email: "", userName: "", password: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try {
      // #18 — list drivers as employees-with-driver-role (+ legacy standalone).
      const [ds, vs, rs] = await Promise.all([listWaterDriversForFarm(), listWaterVehicles(), listWaterRoutes()])
      setDrivers(ds); setVehicles(vs); setRoutes(rs)
      // Employees for the "add existing employee" picker (best-effort).
      try { const er = await getEmployees(); if (er.success && er.data) setEmployees(er.data) } catch {}
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openAddEmployee(mode: "existing" | "new" = "existing") {
    setEmpMode(mode)
    setEmpForm({
      employeeUserId: "", role: "Driver", licenseNumber: "", defaultVehicleId: null, defaultRouteId: null,
      basePay: 0, commissionPerBag: 0, notes: "",
      firstName: "", lastName: "", phoneNumber: "", email: "", userName: "", password: "",
    })
    setEmpOpen(true)
  }

  async function saveEmployeeDriver() {
    setEmpSaving(true)
    try {
      let employeeUserId = empForm.employeeUserId

      // #18 Phase 2: create the employee first, then make them a driver.
      if (empMode === "new") {
        const fn = empForm.firstName.trim(), ln = empForm.lastName.trim()
        if (!fn || !ln) { toast({ title: "First and last name are required", variant: "destructive" }); return }
        if (!empForm.userName.trim() || !/^[a-zA-Z0-9_]+$/.test(empForm.userName)) { toast({ title: "Username required (letters, digits, underscore)", variant: "destructive" }); return }
        if (empForm.password.length < 4) { toast({ title: "Password must be at least 4 characters", variant: "destructive" }); return }
        // Dedup: warn if an employee already matches by name / phone / email / username.
        const dup = employees.find(e =>
          (empForm.phoneNumber && e.phoneNumber && e.phoneNumber.trim() === empForm.phoneNumber.trim()) ||
          (empForm.email && e.email && e.email.trim().toLowerCase() === empForm.email.trim().toLowerCase()) ||
          (e.userName && e.userName.trim().toLowerCase() === empForm.userName.trim().toLowerCase()) ||
          (`${e.firstName} ${e.lastName}`.trim().toLowerCase() === `${fn} ${ln}`.toLowerCase()))
        if (dup && !window.confirm(`An employee that looks like this already exists (${dup.firstName} ${dup.lastName} · ${dup.phoneNumber || dup.email}). Create a new one anyway?`)) return
        const payload: CreateEmployeeData = {
          firstName: fn, lastName: ln, phoneNumber: empForm.phoneNumber.trim(),
          email: empForm.email.trim() || `${empForm.userName.trim()}@noemail.local`,
          userName: empForm.userName.trim(), password: empForm.password,
          farmId: activeFarmId ?? "", farmName: activeFarmName ?? "",
        }
        const res = await createEmployee(payload)
        if (!res.success || !res.data?.id) { toast({ title: "Could not create employee", description: res.message, variant: "destructive" }); return }
        employeeUserId = res.data.id
      } else {
        if (!empForm.employeeUserId) { toast({ title: "Pick an employee", variant: "destructive" }); return }
      }

      await createWaterDriverFromEmployee({
        employeeUserId,
        role: empForm.role,
        licenseNumber: empForm.licenseNumber || null,
        defaultVehicleId: empForm.defaultVehicleId,
        defaultRouteId: empForm.defaultRouteId,
        basePay: empForm.basePay || null,
        commissionPerBag: empForm.commissionPerBag || null,
        notes: empForm.notes || null,
      })
      toast({ title: empMode === "new" ? "Employee created & made a driver" : "Employee assigned as driver" })
      setEmpOpen(false); await load()
    } catch (e: any) { toast({ title: "Could not save driver", description: e?.message, variant: "destructive" }) }
    finally { setEmpSaving(false) }
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
          <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Users2 className="h-6 w-6 text-sky-600" /> Drivers
            </h1>
            <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
              <Button variant="outline" className="w-full sm:w-auto" onClick={() => openAddEmployee("existing")}><UserPlus className="h-4 w-4 mr-1" /> Existing employee</Button>
              <Button className="w-full sm:w-auto" onClick={() => openAddEmployee("new")}><Plus className="h-4 w-4 mr-1" /> New employee &amp; driver</Button>
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
              ) : drivers.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No drivers yet. Add one to assign a vehicle.</div>
              ) : (
                <MobileCardList
                  items={drivers}
                  getKey={(d) => d.waterDriverId}
                  primary={(d) => d.driverName}
                  secondary={(d) => (
                    d.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>
                  )}
                  details={(d) => [
                    { label: "Phone", value: d.phoneNumber ?? "—" },
                    { label: "License", value: d.licenseNumber ?? "—" },
                    { label: "Assigned vehicle", value: vehicleLabel(d.assignedWaterVehicleId) },
                    { label: "Status", value: d.isActive ? "Active" : "Inactive" },
                  ]}
                  actions={(d) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(d)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(d)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
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
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) setEditId(null) }}>
        <DialogContent className="w-[95vw] max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Users2 className="w-5 h-5 text-sky-600" /> {editId ? "Edit driver" : "New driver"}
            </DialogTitle>
            <DialogDescription>Enter the driver's details and assign a vehicle.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Driver details" color="indigo">
              <FormField label="Driver name *" full>
                <Input value={form.driverName} onChange={(e) => setForm({ ...form, driverName: e.target.value })} />
              </FormField>
              <FormField label="Phone">
                <Input value={form.phoneNumber ?? ""} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value || null })} />
              </FormField>
              <FormField label="License number">
                <Input value={form.licenseNumber ?? ""} onChange={(e) => setForm({ ...form, licenseNumber: e.target.value || null })} />
              </FormField>
              <FormField label="Assigned vehicle" full>
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
                </Select>
              </FormField>
              <FormField label="Active" full>
                <div className="flex items-center justify-between rounded border p-2">
                  <span className="text-sm text-slate-700">Active</span>
                  <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
                </div>
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value || null })} />
              </FormField>
            </FormSection>

            <div className="flex justify-end gap-3 pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={save} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* #18 — assign an existing employee as a driver. */}
      <Dialog open={empOpen} onOpenChange={setEmpOpen}>
        <DialogContent className="w-[95vw] max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><UserPlus className="w-5 h-5 text-sky-600" /> {empMode === "new" ? "New employee & driver" : "Add existing employee as driver"}</DialogTitle>
            <DialogDescription>A driver always belongs to an employee record — pick an existing one or create a new employee here.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            {/* #18 Phase 2: choose existing vs new employee. */}
            <div className="inline-flex rounded-lg border border-slate-200 p-0.5 text-sm">
              <button type="button" onClick={() => setEmpMode("existing")} className={`px-3 py-1.5 rounded-md ${empMode === "existing" ? "bg-sky-600 text-white" : "text-slate-600"}`}>Existing employee</button>
              <button type="button" onClick={() => setEmpMode("new")} className={`px-3 py-1.5 rounded-md ${empMode === "new" ? "bg-sky-600 text-white" : "text-slate-600"}`}>New employee</button>
            </div>

            {empMode === "new" ? (
              <FormSection title="New employee details" color="indigo">
                <FormField label="First name *"><Input value={empForm.firstName} onChange={(e) => setEmpForm({ ...empForm, firstName: e.target.value })} /></FormField>
                <FormField label="Last name *"><Input value={empForm.lastName} onChange={(e) => setEmpForm({ ...empForm, lastName: e.target.value })} /></FormField>
                <FormField label="Phone"><Input value={empForm.phoneNumber} onChange={(e) => setEmpForm({ ...empForm, phoneNumber: e.target.value })} /></FormField>
                <FormField label="Email"><Input value={empForm.email} onChange={(e) => setEmpForm({ ...empForm, email: e.target.value })} placeholder="optional" /></FormField>
                <FormField label="Username *"><Input value={empForm.userName} onChange={(e) => setEmpForm({ ...empForm, userName: e.target.value })} /></FormField>
                <FormField label="Password *"><Input type="password" value={empForm.password} onChange={(e) => setEmpForm({ ...empForm, password: e.target.value })} /></FormField>
              </FormSection>
            ) : null}

            <FormSection title={empMode === "new" ? "Driver role" : "Employee & role"} color="indigo">
              {empMode === "existing" && (
              <FormField label="Employee *" full>
                <Select value={empForm.employeeUserId} onValueChange={(v) => setEmpForm({ ...empForm, employeeUserId: v })}>
                  <SelectTrigger><SelectValue placeholder="Select an employee" /></SelectTrigger>
                  <SelectContent>
                    {employees.length === 0
                      ? <div className="px-2 py-1.5 text-sm text-slate-500">No employees found — use “New employee”.</div>
                      : employees.map((e) => (
                          <SelectItem key={e.id} value={e.id}>{e.firstName} {e.lastName} — {e.phoneNumber || e.email}</SelectItem>
                        ))}
                  </SelectContent>
                </Select>
              </FormField>
              )}
              <FormField label="Role">
                <Select value={empForm.role} onValueChange={(v) => setEmpForm({ ...empForm, role: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Driver">Driver</SelectItem>
                    <SelectItem value="MotorKingRider">Motor King Rider</SelectItem>
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="License number">
                <Input value={empForm.licenseNumber} onChange={(e) => setEmpForm({ ...empForm, licenseNumber: e.target.value })} />
              </FormField>
            </FormSection>

            <FormSection title="Assignment & pay" color="amber">
              <FormField label="Default vehicle">
                <Select value={String(empForm.defaultVehicleId ?? "")} onValueChange={(v) => setEmpForm({ ...empForm, defaultVehicleId: v ? Number(v) : null })}>
                  <SelectTrigger><SelectValue placeholder="(none)" /></SelectTrigger>
                  <SelectContent>
                    {vehicles.map((v) => <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>{v.vehicleName}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Default route">
                <Select value={String(empForm.defaultRouteId ?? "")} onValueChange={(v) => setEmpForm({ ...empForm, defaultRouteId: v ? Number(v) : null })}>
                  <SelectTrigger><SelectValue placeholder="(none)" /></SelectTrigger>
                  <SelectContent>
                    {routes.map((r) => <SelectItem key={r.waterRouteId} value={String(r.waterRouteId)}>{r.routeName}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <div className="flex justify-end gap-3 pt-2">
              <Button type="button" variant="outline" onClick={() => setEmpOpen(false)}>Cancel</Button>
              <Button onClick={saveEmployeeDriver} disabled={empSaving}>
                {empSaving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : (empMode === "new" ? "Create & make driver" : "Assign as driver")}
              </Button>
            </div>
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

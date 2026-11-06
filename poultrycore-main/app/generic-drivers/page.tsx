"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { usePagination } from "@/hooks/use-pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Users2, Plus, Loader2, Pencil, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getDrivers, createDriver, updateDriver, deleteDriver, type GenericDriver } from "@/lib/api/generic"

const TRANSPORT_MODES = ["Car", "Motorcycle", "Bicycle", "Truck", "Van", "Tricycle", "On Foot", "Other"]
const empty = () => ({ driverName: "", phoneNumber: "", licenseNumber: "", vehicleName: "", vehicleRegistration: "", transportMode: "Car", notes: "" })

export default function GenericDriversPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [rows, setRows] = useState<GenericDriver[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<GenericDriver | null>(null)
  const [deleting, setDeleting] = useState<GenericDriver | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(empty())

  const pg = usePagination(rows)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try { setRows(await getDrivers()) }
    catch (e: any) { toast({ title: "Could not load drivers", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openCreate() { setEditing(null); setForm(empty()); setDialogOpen(true) }
  function openEdit(d: GenericDriver) {
    setEditing(d)
    setForm({ driverName: d.driverName, phoneNumber: d.phoneNumber ?? "", licenseNumber: d.licenseNumber ?? "", vehicleName: d.vehicleName ?? "", vehicleRegistration: d.vehicleRegistration ?? "", transportMode: d.transportMode ?? "Car", notes: d.notes ?? "" })
    setDialogOpen(true)
  }

  async function doSave() {
    if (!form.driverName.trim()) { toast({ title: "Driver name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) {
        await updateDriver(editing.genericDriverId, { ...form, isActive: editing.isActive })
        toast({ title: "Driver updated" })
      } else {
        await createDriver(form)
        toast({ title: "Driver added" })
      }
      setDialogOpen(false); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Users2 className="h-5 w-5 text-emerald-600" /> Drivers
              </h1>
              <p className="text-xs text-slate-500">Manage delivery drivers and their vehicles.</p>
            </div>
            <Button onClick={openCreate}><Plus className="h-4 w-4 mr-1" /> Add Driver</Button>
          </div>

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600"><Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading…</CardContent></Card>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-slate-500">No drivers yet. Click &ldquo;Add Driver&rdquo; to get started.</CardContent></Card>
          ) : (
            <Card><CardContent className="p-0 md:p-2">
              <MobileCardList defaultOpen striped stripeAccent="blue"
                items={pg.pageItems} pagination={pg.paginationProps}
                getKey={(d: any) => d.genericDriverId}
                primary={(d: any) => d.driverName}
                secondary={(d: any) => d.phoneNumber ?? "No phone"}
                trailing={(d: any) => <Badge className={d.isActive ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600"}>{d.isActive ? "Active" : "Inactive"}</Badge>}
                highlights={(d: any) => [
                  ...(d.vehicleName ? [{ label: "Vehicle", value: d.vehicleName, accent: "blue" as const }] : []),
                  ...(d.licenseNumber ? [{ label: "License", value: d.licenseNumber, accent: "slate" as const }] : []),
                ]}
                details={(d: any) => [
                  { label: "Phone", value: d.phoneNumber ?? "—" },
                  { label: "License", value: d.licenseNumber ?? "—" },
                  { label: "Vehicle", value: d.vehicleName ?? "—" },
                  { label: "Registration", value: d.vehicleRegistration ?? "—" },
                  { label: "Notes", value: d.notes ?? "—" },
                ]}
                actions={(d: any) => (
                  <>
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(d)}>
                      <Pencil className="h-4 w-4 mr-1" /> Edit
                    </Button>
                    <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleting(d)}>
                      <Trash2 className="h-4 w-4 mr-1" /> Delete
                    </Button>
                  </>
                )}
                desktopTable={
                  <div className="overflow-x-auto"><Table>
                    <TableHeader><TableRow>
                      <TableHead>Name</TableHead><TableHead>Phone</TableHead>
                      <TableHead>License</TableHead><TableHead>Vehicle</TableHead>
                      <TableHead>Registration</TableHead><TableHead>Transport</TableHead><TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {rows.length === 0 ? <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-6">No drivers. Add one to get started.</TableCell></TableRow>
                      : pg.pageItems.map((d: any) => (
                        <TableRow key={d.genericDriverId}>
                          <TableCell className="font-medium">{d.driverName}</TableCell>
                          <TableCell>{d.phoneNumber ?? "—"}</TableCell>
                          <TableCell>{d.licenseNumber ?? "—"}</TableCell>
                          <TableCell>{d.vehicleName ?? "—"}</TableCell>
                          <TableCell>{d.vehicleRegistration ?? "—"}</TableCell>
                          <TableCell><Badge className="bg-blue-100 text-blue-700">{d.transportMode ?? "Car"}</Badge></TableCell>
                          <TableCell><Badge className={d.isActive ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600"}>{d.isActive ? "Active" : "Inactive"}</Badge></TableCell>
                          <TableCell className="text-right whitespace-nowrap">
                            <Button variant="ghost" size="sm" onClick={() => openEdit(d)}><Pencil className="h-4 w-4 text-slate-600" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDeleting(d)}><Trash2 className="h-4 w-4 text-red-600" /></Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                }
              />
            </CardContent></Card>
          )}
        </main>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-lg"><DialogHeader><DialogTitle>{editing ? "Edit Driver" : "Add Driver"}</DialogTitle></DialogHeader>
          <FormSection title="Driver details" color="indigo">
            <FormField label="Name *"><Input value={form.driverName} onChange={(e) => setForm({ ...form, driverName: e.target.value })} /></FormField>
            <FormField label="Phone"><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></FormField>
            <FormField label="License number"><Input value={form.licenseNumber} onChange={(e) => setForm({ ...form, licenseNumber: e.target.value })} /></FormField>
            <FormField label="Vehicle"><Input value={form.vehicleName} onChange={(e) => setForm({ ...form, vehicleName: e.target.value })} /></FormField>
            <FormField label="Vehicle registration"><Input value={form.vehicleRegistration} onChange={(e) => setForm({ ...form, vehicleRegistration: e.target.value })} /></FormField>
            <FormField label="Transport mode">
              <Select value={form.transportMode} onValueChange={(v) => setForm({ ...form, transportMode: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{TRANSPORT_MODES.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Notes"><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
            <Button onClick={doSave} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : editing ? "Save" : "Add Driver"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleting} onOpenChange={(o) => { if (!o) setDeleting(null) }}
        title={`Delete ${deleting?.driverName}?`}
        description="This driver will be permanently removed."
        onConfirm={async () => { if (deleting) { await deleteDriver(deleting.genericDriverId); setDeleting(null); await load() } }}
      />
    </div>
  )
}

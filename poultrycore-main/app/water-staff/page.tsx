"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Plus, Pencil, Trash2, Loader2, Users2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterStaff, createWaterStaff, updateWaterStaff, deleteWaterStaff,
  // Issue 1 (test-report): Staff is now the single source of truth for
  // drivers. We surface License + Assigned vehicle in this form when
  // role=Driver and quietly upsert the matching WaterDrivers row on save so
  // the delivery flows (Vehicle Loading, Driver Returns, reports) that still
  // read from /Water/drivers keep working.
  listWaterVehicles, listWaterDrivers, createWaterDriver, updateWaterDriver,
  type WaterStaff, type WaterStaffInput, type WaterVehicle, type WaterDriver,
} from "@/lib/api/water"
import { useCurrency } from "@/lib/currency"

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
  // Column-header / Stat-card unit suffix. Hardcoding " (GHC)" leaked the
  // currency symbol even when the user toggled "Show currency symbol" off in
  // setup (and was always wrong when the currency wasn't GHC). Drive it from
  // the same store fmtMoney reads so labels and values flip together.
  const { symbol, showSymbol } = useCurrency()
  // James (2026-05-30): currency symbols belong on the *values* (driven by
  // fmtMoney + the showCurrencySymbol toggle), never duplicated into the
  // column header. Force empty so headers stay clean regardless of toggle.
  const cur = ""

  const [staff, setStaff] = useState<WaterStaff[]>([])
  // Loaded only so the Driver-specific fields in the form have a vehicle
  // picker and so we can locate / upsert the matching WaterDriver record.
  const [vehicles, setVehicles] = useState<WaterVehicle[]>([])
  const [drivers, setDrivers] = useState<WaterDriver[]>([])
  // Local-only — the WaterStaff backend has no LicenseNumber column. On open
  // we prefill from the matched WaterDriver row; on save we push back into
  // the WaterDriver row.
  const [licenseNumber, setLicenseNumber] = useState<string>("")
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [roleFilter, setRoleFilter] = useState<string>("ALL")

  const visibleStaff = useMemo(
    () => filterByDateAndSearch(staff, {
      search, dateFrom, dateTo,
      searchKeys: ["firstName", "lastName", "phoneNumber", "email", "role"],
    }),
    [staff, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleStaff)

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
    setLoading(true)
    // Run vehicles + drivers in parallel — staff page only blocks on staff
    // itself, so a slow vehicle/driver fetch never delays the table render.
    try {
      const [s, v, d] = await Promise.allSettled([
        listWaterStaff(roleFilter === "ALL" ? undefined : roleFilter),
        listWaterVehicles(),
        listWaterDrivers(),
      ])
      if (s.status === "fulfilled") setStaff(s.value)
      else toast({ title: "Could not load staff", description: (s.reason as any)?.message ?? String(s.reason), variant: "destructive" })
      if (v.status === "fulfilled") setVehicles(v.value)
      if (d.status === "fulfilled") setDrivers(d.value)
    }
    finally { setLoading(false) }
  }

  // Find the WaterDriver row that mirrors a given staff member. Matched by
  // exact name + (phone if both have one). Phone-only fallback keeps the
  // mapping when a driver was added before the merge with no name match.
  function findMatchingDriver(firstName: string, lastName: string, phone: string | null | undefined): WaterDriver | undefined {
    const fullName = `${firstName} ${lastName}`.trim().toLowerCase()
    const phoneTrim = (phone ?? "").trim()
    return drivers.find((d) => {
      const dn = (d.driverName ?? "").trim().toLowerCase()
      const dp = (d.phoneNumber ?? "").trim()
      if (dn === fullName && (phoneTrim === "" || dp === "" || dp === phoneTrim)) return true
      if (phoneTrim !== "" && dp === phoneTrim) return true
      return false
    })
  }

  function openNew() { setEditId(null); setForm(EMPTY); setLicenseNumber(""); setOpen(true) }
  function openEdit(s: WaterStaff) {
    setEditId(s.waterStaffId)
    setForm({
      firstName: s.firstName, lastName: s.lastName,
      phoneNumber: s.phoneNumber ?? "", email: s.email ?? "",
      role: s.role, salaryType: s.salaryType, basePay: s.basePay,
      commissionRate: s.commissionRate, assignedWaterVehicleId: s.assignedWaterVehicleId, assignedWaterRouteId: s.assignedWaterRouteId,
      isActive: s.isActive, notes: s.notes ?? "",
    })
    // Prefill license from the mirrored WaterDriver row, if any. Empty
    // otherwise — only meaningful for role=Driver staff.
    const match = findMatchingDriver(s.firstName, s.lastName, s.phoneNumber ?? null)
    setLicenseNumber(match?.licenseNumber ?? "")
    setOpen(true)
  }

  async function save() {
    if (!form.firstName.trim() || !form.lastName.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterStaff(editId, form); toast({ title: "Staff updated" }) }
      else        { await createWaterStaff(form);        toast({ title: "Staff added" }) }

      // Issue 1 (test-report): when the saved staff member is a Driver,
      // mirror the License + Assigned vehicle to the WaterDrivers table so
      // the Delivery flows (Vehicle Loading, Driver Returns, reports) can
      // keep picking from /Water/drivers. The pairing is by name+phone —
      // see findMatchingDriver above. We swallow failures here because the
      // staff record is already saved; a follow-up edit can retry.
      if (form.role === "Driver") {
        try {
          const match = findMatchingDriver(form.firstName, form.lastName, form.phoneNumber ?? null)
          const driverPayload = {
            driverName: `${form.firstName} ${form.lastName}`.trim(),
            phoneNumber: form.phoneNumber || null,
            licenseNumber: licenseNumber.trim() || null,
            defaultVehicleId: form.assignedWaterVehicleId ?? null,
            isActive: form.isActive ?? true,
            notes: form.notes ?? null,
          }
          if (match) {
            await updateWaterDriver(match.waterDriverId, driverPayload)
          } else {
            await createWaterDriver(driverPayload)
          }
        } catch (driverErr: any) {
          toast({
            title: "Staff saved, but driver sync failed",
            description: driverErr?.message ?? "Open the staff member again and Save to retry.",
            variant: "destructive",
          })
        }
      }

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
              <Users2 className="h-6 w-6 text-sky-600" /> Employees
            </h1>
            <div className="flex flex-wrap items-center gap-2">
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

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search name, phone, email or role"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : staff.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No staff yet.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(s) => s.waterStaffId}
                  primary={(s) => `${s.firstName} ${s.lastName}`}
                  secondary={(s) => (
                    <>
                      <Badge variant="outline">{s.role}</Badge>
                      {s.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}
                    </>
                  )}
                  details={(s) => [
                    { label: "Role", value: s.role },
                    { label: "Salary type", value: s.salaryType },
                    { label: "Base pay", value: s.basePay.toFixed(2) },
                    { label: "Phone", value: s.phoneNumber ?? "—" },
                    { label: "Status", value: s.isActive ? "Active" : "Inactive" },
                  ]}
                  actions={(s) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(s)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(s)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Name</TableHead><TableHead>Role</TableHead><TableHead>Salary type</TableHead>
                          <TableHead className="text-right">Base pay</TableHead>
                          <TableHead>Phone</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((s) => (
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
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <Users2 className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit staff" : "New staff"}
            </DialogTitle>
            <DialogDescription>Enter the staff member's personal and pay details</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Identity" color="indigo">
              <FormField label="First name *">
                <Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} />
              </FormField>
              <FormField label="Last name *">
                <Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} />
              </FormField>
              <FormField label="Phone">
                <Input value={form.phoneNumber ?? ""} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} />
              </FormField>
              <FormField label="Email">
                <Input type="email" value={form.email ?? ""} onChange={(e) => setForm({ ...form, email: e.target.value })} />
              </FormField>
            </FormSection>

            <FormSection title="Role & Pay" color="amber">
              <FormField label="Role">
                <Select value={form.role} onValueChange={(v) => setForm({ ...form, role: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{ROLES.map(r => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Salary type">
                <Select value={form.salaryType} onValueChange={(v) => setForm({ ...form, salaryType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{SALARY_TYPES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label={`Base pay${cur}`}>
                <NumberInput min={0} step="0.01" value={form.basePay} onChange={(e) => setForm({ ...form, basePay: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Commission rate (per bag / %)">
                <NumberInput step="0.01" value={form.commissionRate ?? ""} onChange={(e) => setForm({ ...form, commissionRate: e.target.value ? Number(e.target.value) : null })} />
              </FormField>
              <FormField label="Active" full>
                <div className="flex items-center justify-between rounded border p-2">
                  <span className="text-sm text-slate-700">Active</span>
                  <Switch checked={form.isActive ?? true} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
                </div>
              </FormField>
            </FormSection>

            {/* Issue 1 (test-report): driver-only fields. These two fields
                show only when the role is Driver. Saving syncs the matching
                WaterDriver row (see save() above) so Delivery flows that
                pick from /Water/drivers continue to work. */}
            {form.role === "Driver" && (
              <FormSection title="Driver details" color="blue">
                <FormField label="License number">
                  <Input
                    value={licenseNumber}
                    onChange={(e) => setLicenseNumber(e.target.value)}
                    placeholder="e.g. DVLA-0000-2026"
                  />
                </FormField>
                <FormField label="Assigned vehicle">
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
              </FormSection>
            )}

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={save} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save"}
              </Button>
            </div>
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

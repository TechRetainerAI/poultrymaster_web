"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { NumberInput } from "@/components/ui/number-input"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Loader2, Users, Plus, Edit2, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelStaff, createHotelStaff, updateHotelStaff, deleteHotelStaff, type HotelStaff } from "@/lib/api/hotel"

const DEPARTMENTS = ["Front Desk", "Housekeeping", "Restaurant", "Kitchen", "Bar", "Maintenance", "Security", "Management", "Finance", "Laundry", "Spa", "Other"]
const ROLES = [
  "Receptionist", "Front Desk Agent", "Night Auditor", "Concierge",
  "Cleaner", "Room Attendant", "Housekeeping Supervisor", "Laundry Attendant",
  "Chef", "Sous Chef", "Cook", "Kitchen Porter", "Dishwasher",
  "Waiter", "Waitress", "Server", "Bartender", "Host/Hostess",
  "Bellboy", "Porter", "Doorman",
  "Maintenance Technician", "Electrician", "Plumber", "Groundskeeper",
  "Security Guard", "Night Watchman", "Security Officer",
  "Hotel Manager", "General Manager", "Assistant Manager", "Duty Manager", "Supervisor", "Front Office Manager",
  "Accountant", "HR Officer", "Admin Assistant", "Housekeeper Supervisor",
  "Spa Therapist", "Pool Attendant",
  "Driver", "Other",
]

const DEPT_COLOR: Record<string, string> = {
  "Front Desk": "bg-blue-100 text-blue-700", Housekeeping: "bg-emerald-100 text-emerald-700",
  Restaurant: "bg-violet-100 text-violet-700", Kitchen: "bg-orange-100 text-orange-700",
  Bar: "bg-amber-100 text-amber-700", Maintenance: "bg-slate-100 text-slate-700",
  Security: "bg-red-100 text-red-700", Management: "bg-indigo-100 text-indigo-700",
  Finance: "bg-teal-100 text-teal-700", Laundry: "bg-cyan-100 text-cyan-700", Spa: "bg-pink-100 text-pink-700",
}

// API returns lowercase keys; normalize to access consistently
function g(s: any, key: string): any {
  return s[key] ?? s[key.toLowerCase()] ?? s[key.charAt(0).toLowerCase() + key.slice(1)]
}
function gn(s: any, key: string): number { return Number(g(s, key)) || 0 }
function gs(s: any, key: string): string { return g(s, key) ?? "" }
function gb(s: any, key: string): boolean { const v = g(s, key); return v === true || v === "true" }
function gid(s: any): number { return g(s, "hotelStaffId") ?? g(s, "hotelstaffid") ?? 0 }

interface StaffForm {
  firstName: string; lastName: string; email: string; phone: string
  role: string; department: string; salaryAmount: number; hireDate: string; isActive: boolean
}

export default function HotelStaffPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [staff, setStaff] = useState<any[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [editing, setEditing] = useState<any>(null)
  const [saving, setSaving] = useState(false)
  const [filterDept, setFilterDept] = useState("all")
  const [filterStatus, setFilterStatus] = useState<"all" | "active" | "inactive">("all")
  const emptyForm: StaffForm = { firstName: "", lastName: "", email: "", phone: "", role: "Other", department: "Front Desk", salaryAmount: 0, hireDate: new Date().toISOString().slice(0, 10), isActive: true }
  const [form, setForm] = useState<StaffForm>(emptyForm)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setStaff(await listHotelStaff()) } catch (e: any) { toast({ title: "Failed to load staff", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  function openCreate() {
    setEditing(null)
    setForm(emptyForm)
    setDialogOpen(true)
  }

  function openEdit(s: any) {
    setEditing(s)
    setForm({
      firstName: gs(s, "firstName"), lastName: gs(s, "lastName"),
      email: gs(s, "email"), phone: gs(s, "phone"),
      role: gs(s, "role"), department: gs(s, "department"),
      salaryAmount: gn(s, "salaryAmount"),
      hireDate: (gs(s, "hireDate") || "").slice(0, 10),
      isActive: g(s, "isActive") !== false && g(s, "isactive") !== false,
    })
    setDialogOpen(true)
  }

  async function handleSave() {
    if (!form.firstName.trim() || !form.lastName.trim()) { toast({ title: "Name is required", variant: "destructive" }); return }
    if (!form.role || !form.department) { toast({ title: "Role and Department are required", variant: "destructive" }); return }
    setSaving(true)
    try {
      const payload = { ...form, isActive: form.isActive }
      if (editing) { await updateHotelStaff(gid(editing), payload); toast({ title: "Staff updated" }) }
      else { await createHotelStaff(payload); toast({ title: "Staff member added" }) }
      setDialogOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const activeCount = staff.filter((s) => gb(s, "isActive") || gb(s, "isactive")).length
  const inactiveCount = staff.length - activeCount

  const filtered = staff
    .filter((s) => filterDept === "all" || gs(s, "department") === filterDept)
    .filter((s) => {
      if (filterStatus === "all") return true
      const active = gb(s, "isActive") || gb(s, "isactive")
      return filterStatus === "active" ? active : !active
    })

  const deptCounts = staff.reduce((acc, s) => { const d = gs(s, "department"); acc[d] = (acc[d] || 0) + 1; return acc }, {} as Record<string, number>)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><Users className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Hotel Staff</h1><span className="text-sm text-slate-500">({staff.length} total — {activeCount} active, {inactiveCount} inactive)</span></div>
          <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Staff</Button>
        </div>

        {/* Status filter */}
        <div className="flex gap-2 flex-wrap mb-3">
          <Button variant={filterStatus === "all" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("all")} className={filterStatus === "all" ? "bg-violet-600" : ""}>All ({staff.length})</Button>
          <Button variant={filterStatus === "active" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("active")} className={filterStatus === "active" ? "bg-green-600" : ""}>Active ({activeCount})</Button>
          <Button variant={filterStatus === "inactive" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("inactive")} className={filterStatus === "inactive" ? "bg-red-600" : ""}>Inactive ({inactiveCount})</Button>
        </div>

        {/* Department filter */}
        <div className="flex gap-2 flex-wrap mb-4">
          <Button variant={filterDept === "all" ? "default" : "outline"} size="sm" onClick={() => setFilterDept("all")} className={filterDept === "all" ? "bg-violet-600" : ""}>All Depts</Button>
          {Object.entries(deptCounts).sort().map(([dept, count]) => (
            <Button key={dept} variant={filterDept === dept ? "default" : "outline"} size="sm" onClick={() => setFilterDept(dept)} className={filterDept === dept ? "bg-violet-600" : ""}>
              {dept} ({count})
            </Button>
          ))}
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 border-b"><tr>
                <th className="text-left p-3">Name</th><th className="text-left p-3">Role</th><th className="text-left p-3">Department</th>
                <th className="text-left p-3">Phone</th><th className="text-left p-3">Status</th><th className="text-right p-3">Salary</th><th className="text-right p-3">Actions</th>
              </tr></thead>
              <tbody>
                {filtered.map((s: any, idx: number) => {
                  const active = gb(s, "isActive") || gb(s, "isactive")
                  return (
                    <tr key={gid(s) || `staff-${idx}`} className={`border-b hover:bg-slate-50 ${!active ? "opacity-50" : ""}`}>
                      <td className="p-3 font-semibold">{gs(s, "firstName") || gs(s, "firstname")} {gs(s, "lastName") || gs(s, "lastname")}</td>
                      <td className="p-3">{gs(s, "role")}</td>
                      <td className="p-3"><Badge variant="outline" className={DEPT_COLOR[gs(s, "department")] ?? "bg-slate-100 text-slate-700"}>{gs(s, "department")}</Badge></td>
                      <td className="p-3">{gs(s, "phone") || "-"}</td>
                      <td className="p-3">
                        <Badge className={active ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"}>
                          {active ? "Active" : "Inactive"}
                        </Badge>
                      </td>
                      <td className="p-3 text-right font-semibold tabular-nums">{gn(s, "salaryAmount") > 0 ? gn(s, "salaryAmount").toFixed(2) : (gn(s, "salaryamount") > 0 ? gn(s, "salaryamount").toFixed(2) : "0.00")}</td>
                      <td className="p-3 text-right space-x-1">
                        <Button variant="ghost" size="icon" onClick={() => openEdit(s)}><Edit2 className="h-4 w-4" /></Button>
                        <Button variant="ghost" size="icon" className="text-red-600" onClick={() => setDeleteTarget(s)}><Trash2 className="h-4 w-4" /></Button>
                      </td>
                    </tr>
                  )
                })}
                {filtered.length === 0 && <tr><td colSpan={7} className="p-8 text-center text-slate-400">No staff found. Add your hotel workers.</td></tr>}
              </tbody>
            </table>
          </CardContent></Card>
        )}

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader><DialogTitle>{editing ? `Edit ${gs(editing, "firstName") || gs(editing, "firstname")} ${gs(editing, "lastName") || gs(editing, "lastname")}` : "Add Staff Member"}</DialogTitle></DialogHeader>
            <div className="space-y-4">
              <FormSection title="Person" color="indigo">
                <FormField label="First Name *"><Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} placeholder="e.g. Ama" /></FormField>
                <FormField label="Last Name *"><Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} placeholder="e.g. Mensah" /></FormField>
                <FormField label="Phone"><Input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} placeholder="0241234567" /></FormField>
                <FormField label="Email"><Input value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="ama@hotel.com" /></FormField>
              </FormSection>
              <FormSection title="Role & Pay" color="amber">
                <FormField label="Department *">
                  <Select value={form.department} onValueChange={(v) => setForm({ ...form, department: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{DEPARTMENTS.map((d) => <SelectItem key={d} value={d}>{d}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Role *">
                  <Select value={form.role} onValueChange={(v) => setForm({ ...form, role: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{ROLES.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Monthly Salary"><NumberInput min={0} step={0.01} value={form.salaryAmount} onChange={(e) => setForm({ ...form, salaryAmount: Number(e.target.value) })} /></FormField>
                <FormField label="Hire Date"><Input type="date" value={form.hireDate} onChange={(e) => setForm({ ...form, hireDate: e.target.value })} /></FormField>
              </FormSection>
              <FormSection title="Status" color="slate" columns={1}>
                <FormField label="Active">
                  <div className="flex items-center gap-3">
                    <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
                    <span className="text-sm">{form.isActive ? "Active — employee is on payroll" : "Inactive — employee will not appear in payroll runs"}</span>
                  </div>
                </FormField>
              </FormSection>
            </div>
            <DialogFooter className="gap-2">
              <Button variant="outline" onClick={() => setDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{editing ? "Update" : "Add Staff"}</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        <ConfirmDeleteDialog
          open={!!deleteTarget}
          onOpenChange={(open) => { if (!open) setDeleteTarget(null) }}
          title="Remove staff member?"
          itemLabel={deleteTarget ? `${gs(deleteTarget, "firstName") || gs(deleteTarget, "firstname")} ${gs(deleteTarget, "lastName") || gs(deleteTarget, "lastname")}` : ""}
          successTitle="Staff removed"
          errorTitle="Delete failed"
          onConfirm={async () => { await deleteHotelStaff(gid(deleteTarget)) }}
          onSuccess={() => { setDeleteTarget(null); load() }}
        />
      </main>
    </div></div>
  )
}

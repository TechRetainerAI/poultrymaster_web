"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, Users, Plus, Edit2, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelStaff, createHotelStaff, updateHotelStaff, deleteHotelStaff, type HotelStaff } from "@/lib/api/hotel"

const DEPARTMENTS = ["Front Desk", "Housekeeping", "Restaurant", "Kitchen", "Bar", "Maintenance", "Security", "Management", "Laundry", "Spa", "Other"]
const ROLES = [
  "Receptionist", "Front Desk Agent", "Night Auditor", "Concierge",
  "Cleaner", "Room Attendant", "Housekeeping Supervisor", "Laundry Attendant",
  "Chef", "Sous Chef", "Cook", "Kitchen Porter", "Dishwasher",
  "Waiter", "Waitress", "Server", "Bartender", "Host/Hostess",
  "Bellboy", "Porter", "Doorman",
  "Maintenance Technician", "Electrician", "Plumber", "Groundskeeper",
  "Security Guard", "Night Watchman",
  "Hotel Manager", "Assistant Manager", "Duty Manager", "Supervisor",
  "Accountant", "HR Officer", "Admin Assistant",
  "Spa Therapist", "Pool Attendant",
  "Driver", "Other",
]

const DEPT_COLOR: Record<string, string> = {
  "Front Desk": "bg-blue-100 text-blue-700", Housekeeping: "bg-emerald-100 text-emerald-700",
  Restaurant: "bg-violet-100 text-violet-700", Kitchen: "bg-orange-100 text-orange-700",
  Bar: "bg-amber-100 text-amber-700", Maintenance: "bg-slate-100 text-slate-700",
  Security: "bg-red-100 text-red-700", Management: "bg-indigo-100 text-indigo-700",
  Laundry: "bg-cyan-100 text-cyan-700", Spa: "bg-pink-100 text-pink-700",
}

interface StaffForm {
  firstName: string; lastName: string; email: string; phone: string
  role: string; department: string; salaryAmount: number; hireDate: string
}

export default function HotelStaffPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [staff, setStaff] = useState<HotelStaff[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [editing, setEditing] = useState<HotelStaff | null>(null)
  const [saving, setSaving] = useState(false); const [filterDept, setFilterDept] = useState("all")
  const [form, setForm] = useState<StaffForm>({ firstName: "", lastName: "", email: "", phone: "", role: "Other", department: "Front Desk", salaryAmount: 0, hireDate: new Date().toISOString().slice(0, 10) })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setStaff(await listHotelStaff()) } catch (e: any) { toast({ title: "Failed to load staff", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  function openCreate() {
    setEditing(null)
    setForm({ firstName: "", lastName: "", email: "", phone: "", role: "Other", department: "Front Desk", salaryAmount: 0, hireDate: new Date().toISOString().slice(0, 10) })
    setDialogOpen(true)
  }

  function openEdit(s: HotelStaff) {
    setEditing(s)
    setForm({ firstName: s.firstName, lastName: s.lastName, email: s.email ?? "", phone: s.phone ?? "", role: s.role, department: s.department, salaryAmount: s.salaryAmount, hireDate: s.hireDate?.slice(0, 10) ?? "" })
    setDialogOpen(true)
  }

  async function handleSave() {
    if (!form.firstName.trim() || !form.lastName.trim()) { toast({ title: "Name is required", variant: "destructive" }); return }
    if (!form.role || !form.department) { toast({ title: "Role and Department are required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) { await updateHotelStaff(editing.hotelStaffId ?? editing.hotelstaffid, form); toast({ title: "Staff updated" }) }
      else { await createHotelStaff(form); toast({ title: "Staff member added" }) }
      setDialogOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function handleDelete(s: HotelStaff) {
    if (!confirm(`Remove ${s.firstName} ${s.lastName}?`)) return
    try { await deleteHotelStaff((s as any).hotelStaffId ?? (s as any).hotelstaffid); toast({ title: "Staff removed" }); await load() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  const filtered = staff.filter((s) => filterDept === "all" || s.department === filterDept)
  const deptCounts = staff.reduce((acc, s) => { acc[s.department] = (acc[s.department] || 0) + 1; return acc }, {} as Record<string, number>)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><Users className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Hotel Staff</h1><span className="text-sm text-slate-500">({staff.length} total)</span></div>
          <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Staff</Button>
        </div>

        {/* Department summary cards */}
        <div className="flex gap-2 flex-wrap mb-4">
          <Button variant={filterDept === "all" ? "default" : "outline"} size="sm" onClick={() => setFilterDept("all")} className={filterDept === "all" ? "bg-violet-600" : ""}>All ({staff.length})</Button>
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
                <th className="text-left p-3">Phone</th><th className="text-left p-3">Email</th><th className="text-right p-3">Salary</th><th className="text-right p-3">Actions</th>
              </tr></thead>
              <tbody>
                {filtered.map((s: any, idx: number) => (
                  <tr key={s.hotelStaffId ?? s.hotelstaffid ?? `staff-${idx}`} className="border-b hover:bg-slate-50">
                    <td className="p-3 font-semibold">{s.firstName} {s.lastName}</td>
                    <td className="p-3">{s.role}</td>
                    <td className="p-3"><Badge variant="outline" className={DEPT_COLOR[s.department] ?? "bg-slate-100 text-slate-700"}>{s.department}</Badge></td>
                    <td className="p-3">{s.phone ?? "-"}</td>
                    <td className="p-3">{s.email ?? "-"}</td>
                    <td className="p-3 text-right">{s.salaryAmount?.toFixed(2) ?? "0.00"}</td>
                    <td className="p-3 text-right space-x-1">
                      <Button variant="ghost" size="icon" onClick={() => openEdit(s)}><Edit2 className="h-4 w-4" /></Button>
                      <Button variant="ghost" size="icon" className="text-red-600" onClick={() => handleDelete(s)}><Trash2 className="h-4 w-4" /></Button>
                    </td>
                  </tr>
                ))}
                {filtered.length === 0 && <tr><td colSpan={7} className="p-8 text-center text-slate-400">No staff found. Add your hotel workers.</td></tr>}
              </tbody>
            </table>
          </CardContent></Card>
        )}

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent className="max-w-lg">
            <DialogHeader><DialogTitle>{editing ? `Edit ${editing.firstName} ${editing.lastName}` : "Add Staff Member"}</DialogTitle></DialogHeader>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div><Label>First Name *</Label><Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} placeholder="e.g. Ama" /></div>
                <div><Label>Last Name *</Label><Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} placeholder="e.g. Mensah" /></div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div><Label>Department *</Label>
                  <Select value={form.department} onValueChange={(v) => setForm({ ...form, department: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{DEPARTMENTS.map((d) => <SelectItem key={d} value={d}>{d}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                <div><Label>Role *</Label>
                  <Select value={form.role} onValueChange={(v) => setForm({ ...form, role: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{ROLES.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div><Label>Phone</Label><Input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} placeholder="0241234567" /></div>
                <div><Label>Email</Label><Input value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="ama@hotel.com" /></div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div><Label>Monthly Salary (GHS)</Label><Input type="number" step="0.01" value={form.salaryAmount} onChange={(e) => setForm({ ...form, salaryAmount: Number(e.target.value) })} /></div>
                <div><Label>Hire Date</Label><Input type="date" value={form.hireDate} onChange={(e) => setForm({ ...form, hireDate: e.target.value })} /></div>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
              <Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{editing ? "Update" : "Add Staff"}</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </main>
    </div></div>
  )
}

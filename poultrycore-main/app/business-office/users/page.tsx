"use client"

// Doc 3 §6-7: Business Office → Users & Permissions.
// Company-neutral, org-wide employee list. Unlike the per-company /employees
// page (scoped to the active company's FarmId), this lists every employee
// across all companies in the organization and lets an admin grant/revoke each
// employee's access to individual companies (UserFarms).
import { useEffect, useMemo, useState } from "react"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Search, ShieldCheck, UserPlus, Building2, Check } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import {
  getOrganizationEmployees, assignCompanyAccess, removeCompanyAccess, createEmployee,
  type OrgEmployee,
} from "@/lib/api/admin"
import { getMyCompanies, type Company } from "@/lib/api/companies"

const TYPE_BADGE: Record<string, string> = {
  Poultry: "bg-amber-100 text-amber-700", Water: "bg-blue-100 text-blue-700", Generic: "bg-slate-100 text-slate-700",
}

export default function BusinessOfficeUsersPage() {
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [employees, setEmployees] = useState<OrgEmployee[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [query, setQuery] = useState("")
  const [managed, setManaged] = useState<OrgEmployee | null>(null)
  const [busyFarm, setBusyFarm] = useState<string | null>(null)

  // Doc 3 §6: add an employee at the org level — pick which company they belong
  // to (the Business Office has no active company, so the old /employees create
  // flow failed with "Farm information not found").
  const [addOpen, setAddOpen] = useState(false)
  const [adding, setAdding] = useState(false)
  const emptyAdd = { farmId: "", firstName: "", lastName: "", phoneNumber: "", userName: "", email: "", password: "", confirmPassword: "", isAdmin: false }
  const [addForm, setAddForm] = useState(emptyAdd)

  async function load() {
    setLoading(true)
    try {
      const [empRes, comps] = await Promise.all([getOrganizationEmployees(), getMyCompanies().catch(() => [])])
      if (empRes.success) setEmployees(empRes.data || [])
      else toast({ title: "Could not load employees", description: empRes.message, variant: "destructive" })
      setCompanies(comps || [])
    } finally { setLoading(false) }
  }
  useEffect(() => { load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return employees
    return employees.filter((e) =>
      [e.firstName, e.lastName, e.email, e.userName, e.farmName].filter(Boolean).some((v) => v!.toLowerCase().includes(q)))
  }, [employees, query])

  function accessSet(e: OrgEmployee): Set<string> {
    return new Set((e.companies || []).map((c) => c.farmId))
  }

  async function toggleAccess(emp: OrgEmployee, company: Company, hasAccess: boolean) {
    setBusyFarm(company.farmId)
    try {
      const res = hasAccess
        ? await removeCompanyAccess(emp.id, company.farmId)
        : await assignCompanyAccess(emp.id, company.farmId, "Staff")
      if (!res.success) { toast({ title: "Update failed", description: res.message, variant: "destructive" }); return }
      // Optimistic local update + keep the open dialog in sync.
      const nextCompanies = hasAccess
        ? (emp.companies || []).filter((c) => c.farmId !== company.farmId)
        : [...(emp.companies || []), { farmId: company.farmId, name: company.name, type: company.type, role: "Staff" }]
      const updated = { ...emp, companies: nextCompanies }
      setEmployees((list) => list.map((x) => (x.id === emp.id ? updated : x)))
      setManaged((m) => (m && m.id === emp.id ? updated : m))
      toast({ title: hasAccess ? "Access revoked" : "Access granted", description: company.name })
    } finally { setBusyFarm(null) }
  }

  async function submitAdd() {
    const f = addForm
    if (!f.farmId) return toast({ title: "Pick a company for this employee", variant: "destructive" })
    if (!f.firstName.trim() || !f.lastName.trim()) return toast({ title: "First and last name are required", variant: "destructive" })
    if (!f.userName.trim()) return toast({ title: "Username is required", variant: "destructive" })
    if ((f.password || "").length < 4) return toast({ title: "Password must be at least 4 characters", variant: "destructive" })
    if (f.password !== f.confirmPassword) return toast({ title: "Passwords do not match", variant: "destructive" })
    const company = companies.find((c) => c.farmId === f.farmId)
    setAdding(true)
    try {
      const res = await createEmployee({
        email: f.email, firstName: f.firstName, lastName: f.lastName, phoneNumber: f.phoneNumber,
        userName: f.userName, password: f.password, farmId: f.farmId, farmName: company?.name || "",
        isAdmin: f.isAdmin,
      })
      if (!res.success) { toast({ title: "Could not create employee", description: res.message, variant: "destructive" }); return }
      toast({ title: "Employee created", description: `${f.firstName} ${f.lastName} · ${company?.name ?? ""}` })
      setAddOpen(false); setAddForm(emptyAdd); await load()
    } catch (e: any) {
      toast({ title: "Could not create employee", description: e?.message, variant: "destructive" })
    } finally { setAdding(false) }
  }

  return (
    <BusinessOfficeShell active="users">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2"><ShieldCheck className="h-6 w-6 text-indigo-600" /> Users & Permissions</h1>
            <p className="text-slate-600">Everyone in your organization. Grant each person access to the companies they work in.</p>
          </div>
          <Button onClick={() => { setAddForm(emptyAdd); setAddOpen(true) }}><UserPlus className="h-4 w-4 mr-2" /> Add employee</Button>
        </div>

        <div className="relative max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search employees…" className="pl-9" />
        </div>

        {loading ? (
          <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : filtered.length === 0 ? (
          <Card><CardContent className="p-10 text-center text-slate-500">
            <ShieldCheck className="h-10 w-10 mx-auto mb-3 text-slate-300" />
            <p className="font-medium text-slate-700">No employees yet</p>
            <p className="text-sm">Add your first employee, then assign them to companies.</p>
          </CardContent></Card>
        ) : (
          <Card><CardContent className="p-0 overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
                <tr>
                  <th className="text-left font-semibold px-4 py-3">Employee</th>
                  <th className="text-left font-semibold px-4 py-3">Role</th>
                  <th className="text-left font-semibold px-4 py-3">Company access</th>
                  <th className="text-right font-semibold px-4 py-3">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filtered.map((e) => (
                  <tr key={e.id} className="hover:bg-slate-50/60">
                    <td className="px-4 py-3">
                      <div className="font-medium text-slate-900">{[e.firstName, e.lastName].filter(Boolean).join(" ") || e.userName}</div>
                      <div className="text-xs text-slate-500">{e.email || e.userName}</div>
                    </td>
                    <td className="px-4 py-3">
                      {e.isAdmin ? <Badge className="bg-orange-100 text-orange-700 hover:bg-orange-100">{e.adminTitle || "Admin"}</Badge>
                        : <Badge variant="secondary">Staff</Badge>}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap gap-1">
                        {(e.companies || []).length === 0 ? <span className="text-xs text-slate-400">No companies</span> :
                          (e.companies || []).map((c) => (
                            <span key={c.farmId} className={`text-[11px] px-2 py-0.5 rounded ${TYPE_BADGE[c.type] ?? "bg-slate-100 text-slate-700"}`}>{c.name}</span>
                          ))}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Button variant="outline" size="sm" onClick={() => setManaged(e)}><Building2 className="h-4 w-4 mr-1.5" /> Manage access</Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent></Card>
        )}
      </main>

      <Dialog open={!!managed} onOpenChange={(o) => !o && setManaged(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Company access — {managed ? ([managed.firstName, managed.lastName].filter(Boolean).join(" ") || managed.userName) : ""}</DialogTitle>
          </DialogHeader>
          <div className="space-y-1 max-h-96 overflow-auto">
            {companies.length === 0 ? <p className="text-sm text-slate-500 py-4">No companies in this organization yet.</p> :
              companies.map((c) => {
                const has = managed ? accessSet(managed).has(c.farmId) : false
                return (
                  <button
                    key={c.farmId}
                    disabled={busyFarm === c.farmId}
                    onClick={() => managed && toggleAccess(managed, c, has)}
                    className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg border text-left transition-colors ${has ? "border-indigo-200 bg-indigo-50" : "border-slate-200 hover:bg-slate-50"}`}
                  >
                    <span className={`h-5 w-5 grid place-items-center rounded border ${has ? "bg-indigo-600 border-indigo-600 text-white" : "border-slate-300"}`}>
                      {busyFarm === c.farmId ? <Loader2 className="h-3 w-3 animate-spin" /> : has ? <Check className="h-3.5 w-3.5" /> : null}
                    </span>
                    <span className="flex-1 truncate text-slate-800">{c.name}</span>
                    <span className={`text-[10px] px-1.5 py-0.5 rounded ${TYPE_BADGE[c.type] ?? "bg-slate-100 text-slate-700"}`}>{c.type}</span>
                  </button>
                )
              })}
          </div>
          <p className="text-xs text-slate-400">Toggling access adds or removes this employee from the company. Changes apply immediately.</p>
        </DialogContent>
      </Dialog>

      {/* Doc 3 §6: add an employee under a chosen company */}
      <Dialog open={addOpen} onOpenChange={(o) => { if (!o) setAddOpen(false) }}>
        <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
          <DialogHeader><DialogTitle>Add employee</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1">
              <Label>Company *</Label>
              <Select value={addForm.farmId || undefined} onValueChange={(v) => setAddForm({ ...addForm, farmId: v })}>
                <SelectTrigger><SelectValue placeholder="Select a company for this employee" /></SelectTrigger>
                <SelectContent>
                  {companies.length === 0
                    ? <div className="px-2 py-1.5 text-xs text-slate-400">No companies yet. Create one first.</div>
                    : companies.map((c) => <SelectItem key={c.farmId} value={c.farmId}>{c.name} · {c.type}</SelectItem>)}
                </SelectContent>
              </Select>
              <p className="text-xs text-slate-400">The employee is created under this company. Grant access to more companies afterwards from the list.</p>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1"><Label>First name *</Label><Input value={addForm.firstName} onChange={(e) => setAddForm({ ...addForm, firstName: e.target.value })} /></div>
              <div className="space-y-1"><Label>Last name *</Label><Input value={addForm.lastName} onChange={(e) => setAddForm({ ...addForm, lastName: e.target.value })} /></div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1"><Label>Username *</Label><Input value={addForm.userName} onChange={(e) => setAddForm({ ...addForm, userName: e.target.value })} placeholder="letters, digits, underscores" /></div>
              <div className="space-y-1"><Label>Phone</Label><Input value={addForm.phoneNumber} onChange={(e) => setAddForm({ ...addForm, phoneNumber: e.target.value })} /></div>
            </div>
            <div className="space-y-1"><Label>Email</Label><Input type="email" value={addForm.email} onChange={(e) => setAddForm({ ...addForm, email: e.target.value })} /></div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1"><Label>Password *</Label><Input type="password" value={addForm.password} onChange={(e) => setAddForm({ ...addForm, password: e.target.value })} placeholder="Min 4 characters" /></div>
              <div className="space-y-1"><Label>Confirm password *</Label><Input type="password" value={addForm.confirmPassword} onChange={(e) => setAddForm({ ...addForm, confirmPassword: e.target.value })} /></div>
            </div>
            <label className="flex items-center gap-2 text-sm text-slate-700">
              <input type="checkbox" checked={addForm.isAdmin} onChange={(e) => setAddForm({ ...addForm, isAdmin: e.target.checked })} />
              Create as administrator (grants admin permissions)
            </label>
            <div className="flex justify-end gap-2 pt-1">
              <Button variant="ghost" onClick={() => setAddOpen(false)}>Cancel</Button>
              <Button onClick={submitAdd} disabled={adding}>{adding ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Creating…</> : "Create employee"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </BusinessOfficeShell>
  )
}

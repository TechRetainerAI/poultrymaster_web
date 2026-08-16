"use client"

// Doc 3 §6-7: Business Office → Users & Permissions.
// Company-neutral, org-wide employee list. Unlike the per-company /employees
// page (scoped to the active company's FarmId), this lists every employee
// across all companies in the organization and lets an admin grant/revoke each
// employee's access to individual companies (UserFarms).
// Extracted from the page so Business Setup can render it inline in a tab.
import { useEffect, useMemo, useState } from "react"
import { AddEmployeeDialog } from "@/components/employees/add-employee-dialog"
import { EditEmployeeDialog } from "@/components/employees/edit-employee-dialog"
import { EmployeeAccessFields } from "@/components/employees/employee-access-fields"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Loader2, Search, ShieldCheck, UserPlus, Building2, Check, Pencil, Trash2, Save } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import {
  getOrganizationEmployees, assignCompanyAccess, removeCompanyAccess, deleteEmployee,
  updateEmployee, type OrgEmployee, type UpdateEmployeeData,
} from "@/lib/api/admin"
import { getMyCompanies, type Company } from "@/lib/api/companies"
import {
  blankPermissionSnapshot, cacheEmployeePermissions, resolveEmployeePermissions,
  type EmployeePermissionSnapshot,
} from "@/lib/employees/permissions-io"

const TYPE_BADGE: Record<string, string> = {
  Poultry: "bg-amber-100 text-amber-700", Water: "bg-blue-100 text-blue-700", Generic: "bg-slate-100 text-slate-700",
}

export function UsersPermissionsPanel({ showHeading = true }: { showHeading?: boolean }) {
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [employees, setEmployees] = useState<OrgEmployee[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [query, setQuery] = useState("")
  const [managed, setManaged] = useState<OrgEmployee | null>(null)
  const [busyFarm, setBusyFarm] = useState<string | null>(null)
  const [addOpen, setAddOpen] = useState(false)
  // Same edit dialog the /employees page uses — profile, admin access and staff
  // page permissions, opened in place rather than sending the admin elsewhere.
  const [editOpen, setEditOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<OrgEmployee | null>(null)
  const [deleting, setDeleting] = useState(false)
  // Admin Access + Staff Page Access, same controls as the Edit dialog. Company
  // toggles above them apply immediately; these are a form, so they need a save.
  const [perms, setPerms] = useState<EmployeePermissionSnapshot>(blankPermissionSnapshot())
  const [permsSaving, setPermsSaving] = useState(false)

  // Seed straight from the row rather than re-fetching. GET /Admin/employees/{id}
  // filters by the FarmId claim (the ACTIVE company), but this list is org-wide,
  // so it 404s for anyone outside the company you're currently in. The org
  // endpoint already returns isAdmin, adminTitle, permissions and
  // featurePermissions, so there is nothing extra to fetch.
  // Keyed on the id, NOT the object: toggling company access replaces `managed`
  // with a new object, and depending on that would discard permission edits the
  // user hadn't saved yet.
  const managedId = managed?.id ?? null
  useEffect(() => {
    if (!managed) { setPerms(blankPermissionSnapshot()); return }
    setPerms(resolveEmployeePermissions(managed, managed.id))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [managedId])

  async function savePermissions() {
    if (!managed) return
    setPermsSaving(true)
    try {
      // PUT /Admin/employees/{id} is a full-record update and is NOT farm-scoped,
      // so it works for any employee in the org. The profile fields have to ride
      // along unchanged or the API would blank them — they all come off the row.
      const payload: UpdateEmployeeData = {
        id: managed.id,
        firstName: managed.firstName,
        lastName: managed.lastName,
        phoneNumber: managed.phoneNumber,
        email: managed.email,
        isAdmin: perms.isAdmin,
        adminTitle: perms.isAdmin ? perms.adminTitle.trim() : "",
        adminPermissions: perms.isAdmin ? perms.adminPermissions : undefined,
        featurePermissions: perms.featurePermissions,
      }
      const res = await updateEmployee(managed.id, payload)
      if (res.success) {
        cacheEmployeePermissions(managed.id, { ...perms, adminTitle: perms.isAdmin ? perms.adminTitle.trim() : "" })
        toast({ title: "Access updated", description: "Permissions saved." })
        await load()
      } else {
        toast({ title: "Could not save", description: res.message || "Update failed.", variant: "destructive" })
      }
    } finally { setPermsSaving(false) }
  }

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

  // The row behind the Edit dialog. Looked up once so the dialog's seed record
  // and its company-type list can't drift apart.
  const editingEmployee = useMemo(
    () => employees.find((e) => e.id === editingId) ?? null,
    [employees, editingId],
  )

  function displayName(e: OrgEmployee) {
    return [e.firstName, e.lastName].filter(Boolean).join(" ") || e.userName || e.email || "this employee"
  }

  async function confirmDelete() {
    if (!deleteTarget) return
    setDeleting(true)
    try {
      const res = await deleteEmployee(deleteTarget.id)
      if (!res.success) { toast({ title: "Delete failed", description: res.message, variant: "destructive" }); return }
      setEmployees((list) => list.filter((x) => x.id !== deleteTarget.id))
      toast({ title: "Employee deleted", description: `${displayName(deleteTarget)} has been removed.` })
      setDeleteTarget(null)
    } finally { setDeleting(false) }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        {showHeading ? (
          <div>
            <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2"><ShieldCheck className="h-6 w-6 text-indigo-600" /> Users &amp; Permissions</h1>
            <p className="text-slate-600">Everyone in your organization. Grant each person access to the companies they work in.</p>
          </div>
        ) : (
          <p className="text-slate-600">Everyone in your organization. Grant each person access to the companies they work in.</p>
        )}
        <Button onClick={() => setAddOpen(true)}><UserPlus className="h-4 w-4 mr-2" /> Add employee</Button>
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
                    <div className="flex items-center justify-end gap-2">
                      <Button variant="outline" size="sm" onClick={() => { setEditingId(e.id); setEditOpen(true) }}>
                        <Pencil className="h-4 w-4 mr-1.5" /> Edit
                      </Button>
                      <Button variant="outline" size="sm" onClick={() => setManaged(e)}><Building2 className="h-4 w-4 mr-1.5" /> Manage access</Button>
                      <Button
                        variant="outline"
                        size="sm"
                        className="text-red-600 border-red-200 hover:bg-red-50 hover:text-red-700"
                        onClick={() => setDeleteTarget(e)}
                      >
                        <Trash2 className="h-4 w-4 mr-1.5" /> Delete
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent></Card>
      )}

      <Dialog open={!!managed} onOpenChange={(o) => !o && setManaged(null)}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Manage access — {managed ? ([managed.firstName, managed.lastName].filter(Boolean).join(" ") || managed.userName) : ""}</DialogTitle>
          </DialogHeader>
          <h3 className="text-sm font-semibold text-slate-800">Company access</h3>
          <div className="space-y-1">
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

          {/* Driven by the company toggles directly above: an employee who is
              only in water companies gets only the water switches, only poultry
              gets only the poultry ones, and someone in both sees both. Reading
              off `managed` rather than the active company means the list also
              updates the moment you grant or revoke access up there. */}
          <EmployeeAccessFields
            value={perms}
            onChange={setPerms}
            disabled={permsSaving}
            companyTypes={(managed?.companies ?? []).map((c) => c.type)}
          />
          <div className="flex justify-end">
            <Button onClick={savePermissions} disabled={permsSaving}>
              {permsSaving
                ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Saving…</>
                : <><Save className="h-4 w-4 mr-2" /> Save permissions</>}
            </Button>
          </div>
          <p className="text-xs text-slate-400">
            Admin and staff permissions are a form — they apply when you press Save, unlike the company toggles above.
          </p>
        </DialogContent>
      </Dialog>

      <AddEmployeeDialog open={addOpen} onOpenChange={setAddOpen} boMode onCreated={load} />

      {/* `employee` is passed so the dialog seeds from this org-wide row instead
          of the farm-scoped GET, which 404s for anyone outside the active company. */}
      <EditEmployeeDialog
        open={editOpen}
        onOpenChange={setEditOpen}
        employeeId={editingId}
        employee={editingEmployee}
        companyTypes={(editingEmployee?.companies ?? []).map((c) => c.type)}
        onSaved={load}
      />

      <AlertDialog open={!!deleteTarget} onOpenChange={(o) => { if (!o && !deleting) setDeleteTarget(null) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete employee</AlertDialogTitle>
            <AlertDialogDescription>
              Delete {deleteTarget ? displayName(deleteTarget) : "this employee"}? They lose access to every company in
              the organization and can no longer sign in. This cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={(e) => { e.preventDefault(); confirmDelete() }} disabled={deleting} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              {deleting ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Deleting…</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

"use client"

// Reusable Edit-Employee dialog. Extracted from /employees (same form, same
// behaviour) so it can also open in place from Business Office → Users &
// Permissions instead of sending the admin to the per-company employees page.
// Owns the fetch + form state; the caller only controls open/close, passes the
// employee id, and gets an onSaved callback to refresh its list.

import { useEffect, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Pencil, Loader2, Save, User } from "lucide-react"
import { getEmployee, updateEmployee, type Employee, type UpdateEmployeeData } from "@/lib/api/admin"
import { getEmployeeJobRoles, setEmployeeJobRoles } from "@/lib/api/water"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { EmployeeAccessFields } from "@/components/employees/employee-access-fields"
import {
  blankPermissionSnapshot,
  cacheEmployeePermissions,
  resolveEmployeePermissions,
} from "@/lib/employees/permissions-io"

// #18 Phase 3: water job roles assignable per employee (a person can hold several).
const WATER_JOB_ROLES = ["Driver", "MotorKingRider", "Salesperson", "Loader", "Supervisor", "Cashier", "Other"]

const blankForm = () => ({
  firstName: "", lastName: "", phoneNumber: "", email: "", userName: "", createdDate: "",
  ...blankPermissionSnapshot(),
})

export function EditEmployeeDialog({
  open,
  onOpenChange,
  employeeId,
  employee,
  companyTypes,
  onSaved,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Employee to edit. The dialog fetches the full record unless `employee` is given. */
  employeeId: string | null
  /**
   * Optional preloaded record. Pass this from an ORG-WIDE list: the fetch below
   * hits GET /Admin/employees/{id}, which filters by the caller's FarmId claim
   * (the active company) and therefore 404s for an employee who belongs to a
   * different company in the same organization. The org endpoint already
   * returns every field this form needs, so seeding from the row avoids the
   * request entirely.
   */
  employee?: Employee | null
  /**
   * Company types this employee has access to, e.g. `["Water"]`. Narrows the
   * Staff Page Access switches to the modules that actually apply to them.
   * Pass from an org-wide list (which knows their companies); omit on the
   * per-company page, where the active company is the answer.
   */
  companyTypes?: Array<string | null | undefined>
  onSaved?: () => void
}) {
  const { toast } = useToast()
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editFetching, setEditFetching] = useState(false)
  // #18 Phase 3: water job roles for the employee being edited (water companies only).
  const isWaterCompany = useAuthStore((s) => s.activeFarmType) === "Water"
  const [editRoles, setEditRoles] = useState<string[]>([])
  const [editForm, setEditForm] = useState(blankForm())

  const seedForm = (data: Employee, id: string) => ({
    firstName: data.firstName, lastName: data.lastName,
    phoneNumber: data.phoneNumber, email: data.email,
    userName: data.userName || "", createdDate: data.createdDate || "",
    ...resolveEmployeePermissions(data, id),
  })

  // Load the employee each time the dialog opens.
  useEffect(() => {
    if (!open || !employeeId) return
    let cancelled = false

    setEditError("")
    setEditRoles([])
    // Best-effort; water only.
    if (isWaterCompany) {
      getEmployeeJobRoles(employeeId)
        .then((r) => { if (!cancelled) setEditRoles(Array.isArray(r) ? r : []) })
        .catch(() => {})
    }

    // Caller already has the record (org-wide list) — use it and skip the
    // farm-scoped GET, which would 404 for an out-of-company employee.
    if (employee && employee.id === employeeId) {
      setEditFetching(false)
      setEditForm(seedForm(employee, employeeId))
      return () => { cancelled = true }
    }

    setEditFetching(true)
    ;(async () => {
      try {
        const result = await getEmployee(employeeId)
        if (cancelled) return
        if (result.success && result.data) {
          setEditForm(seedForm(result.data, employeeId))
        } else {
          setEditError(result.message || "Failed to load employee")
        }
      } catch {
        if (!cancelled) setEditError("Unable to load employee.")
      } finally {
        if (!cancelled) setEditFetching(false)
      }
    })()

    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, employeeId, employee?.id])

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!employeeId) return
    setEditLoading(true)
    setEditError("")

    if (!editForm.firstName.trim() || !editForm.lastName.trim() || !editForm.phoneNumber.trim() || !editForm.email.trim()) {
      const msg = "First name, last name, phone number, and email are required."
      setEditError(msg)
      toastFormGuide(toast, "Fill in first name, last name, phone number, and email — they are required to save this profile.")
      setEditLoading(false)
      return
    }

    const employeeData: UpdateEmployeeData = {
      id: employeeId, firstName: editForm.firstName, lastName: editForm.lastName,
      phoneNumber: editForm.phoneNumber, email: editForm.email,
      isAdmin: editForm.isAdmin,
      adminTitle: editForm.isAdmin ? editForm.adminTitle.trim() : "",
      adminPermissions: editForm.isAdmin ? editForm.adminPermissions : undefined,
      featurePermissions: editForm.featurePermissions,
    }
    const result = await updateEmployee(employeeId, employeeData)
    if (result.success) {
      cacheEmployeePermissions(employeeId, {
        isAdmin: editForm.isAdmin,
        adminTitle: editForm.isAdmin ? editForm.adminTitle.trim() : "",
        adminPermissions: editForm.adminPermissions,
        featurePermissions: editForm.featurePermissions,
      })
      // #18 Phase 3: persist water job roles (best-effort — never block the save).
      if (isWaterCompany) {
        try { await setEmployeeJobRoles(employeeId, editRoles.join(",")) } catch {}
      }
      toast({ title: "Success!", description: "Employee updated successfully." })
      onOpenChange(false)
      onSaved?.()
    } else {
      setEditError(result.message || "Failed to update employee")
    }
    setEditLoading(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><Pencil className="w-5 h-5 text-blue-600" /> Edit Employee</DialogTitle>
          <DialogDescription>Update employee profile and access permissions</DialogDescription>
        </DialogHeader>
        {editError && <Alert variant="destructive"><AlertDescription>{editError}</AlertDescription></Alert>}
        {editFetching ? (
          <div className="py-8 text-center"><Loader2 className="w-8 h-8 animate-spin mx-auto mb-2 text-blue-600" /><p className="text-slate-600">Loading employee...</p></div>
        ) : (
          <form onSubmit={handleEditSubmit} className="space-y-4">
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">First Name *</Label>
                  <Input name="firstName" value={editForm.firstName} onChange={(e) => setEditForm({...editForm, firstName: e.target.value})} required disabled={editLoading} placeholder="John" />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Last Name *</Label>
                  <Input name="lastName" value={editForm.lastName} onChange={(e) => setEditForm({...editForm, lastName: e.target.value})} required disabled={editLoading} placeholder="Doe" />
                </div>
              </div>
            </div>
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Contact Information</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Email Address *</Label>
                  <Input name="email" type="email" value={editForm.email} onChange={(e) => setEditForm({...editForm, email: e.target.value})} required disabled={editLoading} placeholder="john@example.com" />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Phone Number *</Label>
                  <Input name="phoneNumber" type="tel" value={editForm.phoneNumber} onChange={(e) => setEditForm({...editForm, phoneNumber: e.target.value})} required disabled={editLoading} placeholder="+1 (555) 123-4567" />
                </div>
              </div>
            </div>
            {/* #18 Phase 3: assign one or more water job roles to this employee. */}
            {isWaterCompany && (
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-amber-600 px-4 py-2 text-sm font-semibold text-white">Job roles</div>
                <div className="p-4 bg-white">
                  <p className="text-xs text-slate-500 mb-2">A person can hold several roles (e.g. Driver + Salesperson). Drivers also appear on the Drivers page.</p>
                  <div className="flex flex-wrap gap-2">
                    {WATER_JOB_ROLES.map((role) => {
                      const on = editRoles.includes(role)
                      return (
                        <button type="button" key={role} disabled={editLoading}
                          onClick={() => setEditRoles(on ? editRoles.filter(r => r !== role) : [...editRoles, role])}
                          className={`px-3 py-1.5 rounded-full border text-sm ${on ? "bg-amber-600 text-white border-amber-600" : "bg-white text-slate-600 border-slate-300"}`}>
                          {role.replace(/([a-z])([A-Z])/g, "$1 $2")}
                        </button>
                      )
                    })}
                  </div>
                </div>
              </div>
            )}
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-slate-600 px-4 py-2 text-sm font-semibold text-white">Account Information</div>
              <div className="p-4 bg-white space-y-3">
                <div className="flex items-center gap-3 text-sm"><User className="w-4 h-4 text-slate-400" /><span className="text-slate-500 w-24">Username:</span><span className="font-medium text-slate-800">{editForm.userName ? `@${editForm.userName}` : "Not set"}</span></div>
                <div className="flex items-center gap-3 text-sm"><User className="w-4 h-4 text-slate-400" /><span className="text-slate-500 w-24">Employee ID:</span><span className="font-mono text-xs text-slate-800">{employeeId}</span></div>
                {editForm.createdDate && <div className="flex items-center gap-3 text-sm"><User className="w-4 h-4 text-slate-400" /><span className="text-slate-500 w-24">Created:</span><span className="text-slate-800">{new Date(editForm.createdDate).toLocaleDateString()}</span></div>}
              </div>
            </div>
            <EmployeeAccessFields
              value={{
                isAdmin: editForm.isAdmin,
                adminTitle: editForm.adminTitle,
                adminPermissions: editForm.adminPermissions,
                featurePermissions: editForm.featurePermissions,
              }}
              onChange={(next) => setEditForm({ ...editForm, ...next })}
              disabled={editLoading}
              companyTypes={companyTypes}
            />
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => onOpenChange(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button type="submit" disabled={editLoading}>
                {editLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : <><Save className="w-4 h-4 mr-2" />Save Changes</>}
              </Button>
            </div>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}

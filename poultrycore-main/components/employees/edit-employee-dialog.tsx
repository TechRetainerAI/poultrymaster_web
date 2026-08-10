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
import { Switch } from "@/components/ui/switch"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Pencil, Loader2, Save, User, ChevronDown } from "lucide-react"
import { cn } from "@/lib/utils"
import { getEmployee, updateEmployee, type Employee, type UpdateEmployeeData } from "@/lib/api/admin"
import { getEmployeeJobRoles, setEmployeeJobRoles } from "@/lib/api/water"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import {
  type AdminPermissionKey,
  DEFAULT_ADMIN_PERMISSIONS,
  ADMIN_PERMISSION_OPTIONS,
  type StaffFeaturePermissionKey,
  DEFAULT_STAFF_FEATURE_PERMISSIONS,
  STAFF_FEATURE_PERMISSION_OPTIONS,
} from "@/lib/employees/permissions"

// #18 Phase 3: water job roles assignable per employee (a person can hold several).
const WATER_JOB_ROLES = ["Driver", "MotorKingRider", "Salesperson", "Loader", "Supervisor", "Cashier", "Other"]

const toBoolean = (value: unknown): boolean | undefined => {
  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase()
    if (normalized === "true") return true
    if (normalized === "false") return false
  }
  return undefined
}

const normalizeAdminPermissions = (source: unknown): Record<AdminPermissionKey, boolean> => {
  const normalized = { ...DEFAULT_ADMIN_PERMISSIONS }
  if (!source || typeof source !== "object") return normalized

  const record = source as Record<string, unknown>
  for (const option of ADMIN_PERMISSION_OPTIONS) {
    const raw = toBoolean(record[option.key] ?? record[option.key.charAt(0).toUpperCase() + option.key.slice(1)])
    if (raw !== undefined) normalized[option.key] = raw
  }

  return normalized
}

const normalizeFeaturePermissions = (source: unknown): Record<StaffFeaturePermissionKey, boolean> => {
  const normalized = { ...DEFAULT_STAFF_FEATURE_PERMISSIONS }
  if (!source || typeof source !== "object") return normalized

  const record = source as Record<string, unknown>
  for (const option of STAFF_FEATURE_PERMISSION_OPTIONS) {
    const raw = toBoolean(record[option.key] ?? record[option.key.charAt(0).toUpperCase() + option.key.slice(1)])
    if (raw !== undefined) normalized[option.key] = raw
  }

  return normalized
}

type EmployeePermissionSnapshot = {
  isAdmin: boolean
  adminTitle: string
  adminPermissions: Record<AdminPermissionKey, boolean>
  featurePermissions: Record<StaffFeaturePermissionKey, boolean>
}

const EMPLOYEE_PERMISSION_CACHE_KEY = "employeePermissionOverrides"

const loadCachedEmployeePermissions = (employeeId: string): EmployeePermissionSnapshot | null => {
  if (typeof window === "undefined") return null
  try {
    const raw = localStorage.getItem(EMPLOYEE_PERMISSION_CACHE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Record<string, unknown>
    const entry = parsed?.[employeeId]
    if (!entry || typeof entry !== "object") return null
    const record = entry as Record<string, unknown>
    return {
      isAdmin: toBoolean(record.isAdmin) ?? false,
      adminTitle: typeof record.adminTitle === "string" ? record.adminTitle : "",
      adminPermissions: normalizeAdminPermissions(record.adminPermissions),
      featurePermissions: normalizeFeaturePermissions(record.featurePermissions),
    }
  } catch {
    return null
  }
}

const cacheEmployeePermissions = (employeeId: string, snapshot: EmployeePermissionSnapshot) => {
  if (typeof window === "undefined") return
  try {
    const raw = localStorage.getItem(EMPLOYEE_PERMISSION_CACHE_KEY)
    const parsed = raw ? (JSON.parse(raw) as Record<string, unknown>) : {}
    const next: Record<string, unknown> = {
      ...parsed,
      [employeeId]: snapshot,
    }
    localStorage.setItem(EMPLOYEE_PERMISSION_CACHE_KEY, JSON.stringify(next))
  } catch {
    // Ignore cache failures: API data remains the source of truth when available.
  }
}

const blankForm = () => ({
  firstName: "", lastName: "", phoneNumber: "", email: "", userName: "", createdDate: "",
  isAdmin: false, adminTitle: "", adminPermissions: { ...DEFAULT_ADMIN_PERMISSIONS },
  featurePermissions: { ...DEFAULT_STAFF_FEATURE_PERMISSIONS },
})

export function EditEmployeeDialog({
  open,
  onOpenChange,
  employeeId,
  onSaved,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Employee to edit. The dialog fetches the full record each time it opens. */
  employeeId: string | null
  onSaved?: () => void
}) {
  const { toast } = useToast()
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editFetching, setEditFetching] = useState(false)
  const [showEditStaffPermissions, setShowEditStaffPermissions] = useState(false)
  // #18 Phase 3: water job roles for the employee being edited (water companies only).
  const isWaterCompany = useAuthStore((s) => s.activeFarmType) === "Water"
  const [editRoles, setEditRoles] = useState<string[]>([])
  const [editForm, setEditForm] = useState(blankForm())

  // Load the employee each time the dialog opens.
  useEffect(() => {
    if (!open || !employeeId) return
    let cancelled = false

    setEditError("")
    setEditFetching(true)
    setShowEditStaffPermissions(false)
    setEditRoles([])
    // Best-effort; water only.
    if (isWaterCompany) {
      getEmployeeJobRoles(employeeId)
        .then((r) => { if (!cancelled) setEditRoles(Array.isArray(r) ? r : []) })
        .catch(() => {})
    }

    ;(async () => {
      try {
        const result = await getEmployee(employeeId)
        if (cancelled) return
        if (result.success && result.data) {
          const employeeData = result.data as Employee & {
            IsAdmin?: boolean
            AdminTitle?: string | null
            Permissions?: Record<string, unknown> | null
            FeaturePermissions?: Record<string, unknown> | null
            FeatureAccess?: Record<string, unknown> | null
          }

          const isAdmin =
            toBoolean(employeeData.isAdmin) ??
            toBoolean(employeeData.IsAdmin) ??
            false
          const adminTitle = employeeData.adminTitle ?? employeeData.AdminTitle ?? ""
          const apiAdminPermissionsSource = employeeData.permissions ?? employeeData.Permissions
          const apiFeaturePermissionsSource =
            employeeData.featurePermissions ?? employeeData.FeaturePermissions ?? employeeData.featureAccess ?? employeeData.FeatureAccess
          const hasApiPermissions =
            apiAdminPermissionsSource !== undefined ||
            apiFeaturePermissionsSource !== undefined ||
            employeeData.isAdmin !== undefined ||
            employeeData.IsAdmin !== undefined ||
            employeeData.adminTitle !== undefined ||
            employeeData.AdminTitle !== undefined
          const cachedPermissions = loadCachedEmployeePermissions(employeeId)
          const adminPermissions = hasApiPermissions
            ? normalizeAdminPermissions(apiAdminPermissionsSource)
            : cachedPermissions?.adminPermissions ?? { ...DEFAULT_ADMIN_PERMISSIONS }
          const featurePermissions = hasApiPermissions
            ? normalizeFeaturePermissions(apiFeaturePermissionsSource)
            : cachedPermissions?.featurePermissions ?? { ...DEFAULT_STAFF_FEATURE_PERMISSIONS }
          const resolvedIsAdmin = hasApiPermissions ? isAdmin : (cachedPermissions?.isAdmin ?? false)
          const resolvedAdminTitle = hasApiPermissions ? (adminTitle ?? "") : (cachedPermissions?.adminTitle ?? "")

          setEditForm({
            firstName: result.data.firstName, lastName: result.data.lastName,
            phoneNumber: result.data.phoneNumber, email: result.data.email,
            userName: result.data.userName || "", createdDate: result.data.createdDate || "",
            isAdmin: resolvedIsAdmin,
            adminTitle: resolvedAdminTitle,
            adminPermissions,
            featurePermissions,
          })
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
  }, [open, employeeId])

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
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-cyan-700 px-4 py-2 text-sm font-semibold text-white">Admin Access</div>
              <div className="p-4 bg-white space-y-4">
                <div className="flex items-center justify-between gap-3 p-3 rounded-lg border border-slate-200 bg-slate-50">
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-slate-800">Grant administrator access</p>
                    <p className="text-xs text-slate-500">Turn on to configure admin-only actions for this employee.</p>
                  </div>
                  <Switch
                    checked={editForm.isAdmin}
                    onCheckedChange={(checked) => setEditForm({ ...editForm, isAdmin: checked })}
                    disabled={editLoading}
                    aria-label="Grant administrator access"
                  />
                </div>

                {editForm.isAdmin && (
                  <div className="space-y-4">
                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Custom title (optional)</Label>
                      <Input
                        name="adminTitle"
                        value={editForm.adminTitle}
                        onChange={(e) => setEditForm({ ...editForm, adminTitle: e.target.value })}
                        disabled={editLoading}
                        placeholder="admin"
                        maxLength={30}
                      />
                    </div>

                    <div className="rounded-lg border border-slate-200 divide-y">
                      <div className="px-3 py-2 bg-slate-50">
                        <p className="text-sm font-semibold text-slate-800">What can this admin do?</p>
                      </div>
                      {ADMIN_PERMISSION_OPTIONS.map((perm) => (
                        <div key={perm.key} className="flex items-center justify-between gap-3 px-3 py-2">
                          <div className="min-w-0">
                            <p className="text-sm text-slate-800">{perm.label}</p>
                            {perm.hint && <p className="text-xs text-slate-500">{perm.hint}</p>}
                          </div>
                          <Switch
                            checked={editForm.adminPermissions[perm.key]}
                            onCheckedChange={(checked) =>
                              setEditForm({
                                ...editForm,
                                adminPermissions: { ...editForm.adminPermissions, [perm.key]: checked },
                              })
                            }
                            disabled={editLoading}
                            aria-label={perm.label}
                          />
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-slate-700 px-4 py-2 text-sm font-semibold text-white">Staff Page Access</div>
              <div className="p-4 bg-white space-y-3">
                <p className="text-xs text-slate-600">Set exactly what this employee can access.</p>
                <Button
                  type="button"
                  variant="outline"
                  className="w-full justify-between"
                  onClick={() => setShowEditStaffPermissions((prev) => !prev)}
                  disabled={editLoading}
                >
                  <span>Select Staff Permissions</span>
                  <ChevronDown className={cn("h-4 w-4 transition-transform", showEditStaffPermissions && "rotate-180")} />
                </Button>

                {showEditStaffPermissions && (
                  <div className="rounded-lg border border-slate-200 divide-y">
                    {STAFF_FEATURE_PERMISSION_OPTIONS.map((perm) => (
                      <div key={perm.key} className="flex items-center justify-between gap-3 px-3 py-2">
                        <p className="text-sm text-slate-800">{perm.label}</p>
                        <Switch
                          checked={editForm.featurePermissions[perm.key]}
                          onCheckedChange={(checked) =>
                            setEditForm({
                              ...editForm,
                              featurePermissions: { ...editForm.featurePermissions, [perm.key]: checked },
                            })
                          }
                          disabled={editLoading}
                          aria-label={perm.label}
                        />
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
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

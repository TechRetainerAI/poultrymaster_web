"use client"

// Reusable Add-Employee dialog. Extracted from /employees so it can open in
// place anywhere (e.g. Business Office → Users & Permissions) instead of
// navigating to the employees page. Owns its own form state; the caller just
// controls open/close and gets an onCreated callback to refresh its list.
//
// `boMode` (Business Office): no active company, so the form shows a Company
// dropdown to choose which company the new employee joins.

import { useEffect, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { UserCog, Loader2, ChevronDown } from "lucide-react"
import { cn } from "@/lib/utils"
import { createEmployee, sendCredentialsEmail, type CreateEmployeeData } from "@/lib/api/admin"
import { getMyCompanies, type Company } from "@/lib/api/companies"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import {
  DEFAULT_ADMIN_PERMISSIONS,
  ADMIN_PERMISSION_OPTIONS,
  DEFAULT_STAFF_FEATURE_PERMISSIONS,
  staffPermissionOptionsForCompanyType,
} from "@/lib/employees/permissions"
import { useAuthStore } from "@/lib/store/auth-store"

const blankForm = () => ({
  userName: "", email: "", password: "", confirmPassword: "", firstName: "", lastName: "", phoneNumber: "",
  isAdmin: false, adminTitle: "", adminPermissions: { ...DEFAULT_ADMIN_PERMISSIONS },
  featurePermissions: { ...DEFAULT_STAFF_FEATURE_PERMISSIONS },
})

export function AddEmployeeDialog({
  open,
  onOpenChange,
  boMode = false,
  onCreated,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  boMode?: boolean
  onCreated?: () => void
}) {
  const { toast } = useToast()
  const [createLoading, setCreateLoading] = useState(false)
  const [createError, setCreateError] = useState("")
  const [showStaffPermissions, setShowStaffPermissions] = useState(false)
  const [boCompanies, setBoCompanies] = useState<Company[]>([])
  const [boFarmId, setBoFarmId] = useState("")
  const [createForm, setCreateForm] = useState(blankForm())
  // Only the toggles that apply to the company this employee is being created
  // in. In Business Office mode that's whichever company is picked in the
  // selector above — the same rule Manage access uses, just with the one company
  // they're starting with. The form still carries every key.
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const newEmployeeFarmType = boMode
    ? boCompanies.find((c) => c.farmId === boFarmId)?.type
    : activeFarmType
  const staffOptions = staffPermissionOptionsForCompanyType(newEmployeeFarmType)

  // Reset the form each time the dialog opens; load companies in office mode.
  useEffect(() => {
    if (!open) return
    setCreateForm(blankForm())
    setCreateError("")
    setShowStaffPermissions(false)
    setBoFarmId("")
    if (boMode) getMyCompanies().then(setBoCompanies).catch(() => {})
  }, [open, boMode])

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setCreateLoading(true)
    setCreateError("")
    // In Business Office mode the company is chosen in the dialog (no active
    // company); otherwise use the active company's context.
    let farmId: string
    let farmName: string
    if (boMode) {
      if (!boFarmId) { setCreateError("Please select a company for this employee."); setCreateLoading(false); return }
      const c = boCompanies.find((x) => x.farmId === boFarmId)
      farmId = boFarmId
      farmName = c?.name || ""
    } else {
      const ctx = getUserContext()
      farmId = ctx.farmId
      farmName = localStorage.getItem("farmName") || "My Farm"
      if (!farmId) { setCreateError("Farm information not found."); setCreateLoading(false); return }
    }
    if (!createForm.firstName.trim() || !createForm.lastName.trim() || !createForm.phoneNumber.trim() || !createForm.email.trim()) {
      const msg = "First name, last name, phone number, and email are required."
      setCreateError(msg)
      toastFormGuide(toast, "Fill in first name, last name, phone number, and email — they are required to create an employee account.")
      setCreateLoading(false)
      return
    }
    if (createForm.password !== createForm.confirmPassword) { setCreateError("Passwords do not match"); setCreateLoading(false); return }
    if (createForm.password.length < 4) { setCreateError("Password must be at least 4 characters long"); setCreateLoading(false); return }
    if (!/^[a-zA-Z0-9_]+$/.test(createForm.userName)) { setCreateError("Username can only contain letters, digits, and underscores"); setCreateLoading(false); return }

    const employeeData: CreateEmployeeData = {
      userName: createForm.userName, email: createForm.email, password: createForm.password,
      firstName: createForm.firstName, lastName: createForm.lastName,
      phoneNumber: createForm.phoneNumber, farmId, farmName,
      isAdmin: createForm.isAdmin,
      adminTitle: createForm.isAdmin ? createForm.adminTitle.trim() : "",
      adminPermissions: createForm.isAdmin ? createForm.adminPermissions : undefined,
      featurePermissions: createForm.featurePermissions,
    }
    const result = await createEmployee(employeeData)
    if (result.success) {
      toast({ title: "Success!", description: "Employee created successfully." })
      const to = createForm.email.trim()
      if (to) {
        const r = await sendCredentialsEmail({ email: to, userName: createForm.userName.trim(), password: createForm.password, farmName })
        if (r.success) toast({ title: "Credentials emailed", description: `Login details sent to ${to}.` })
        else toast({ title: "Couldn't email credentials", description: r.message || "Email was not sent.", variant: "destructive" })
      }
      onOpenChange(false)
      onCreated?.()
    } else {
      setCreateError(result.message || "Failed to create employee")
    }
    setCreateLoading(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><UserCog className="w-5 h-5 text-blue-600" /> Add New Employee</DialogTitle>
          <DialogDescription>Create a staff member or configure an admin with custom permissions</DialogDescription>
        </DialogHeader>
        {createError && <Alert variant="destructive"><AlertDescription>{createError}</AlertDescription></Alert>}
        <form onSubmit={handleCreateSubmit} className="space-y-4">
          {boMode && (
            <div className="rounded-xl border border-orange-200 overflow-hidden">
              <div className="bg-orange-500 px-4 py-2 text-sm font-semibold text-white">Company</div>
              <div className="p-4 bg-white space-y-2">
                <Label className="text-sm font-medium text-slate-700">Assign to company *</Label>
                <Select value={boFarmId || undefined} onValueChange={setBoFarmId} disabled={createLoading}>
                  <SelectTrigger><SelectValue placeholder="Select a company for this employee" /></SelectTrigger>
                  <SelectContent>
                    {boCompanies.length === 0
                      ? <div className="px-2 py-1.5 text-xs text-slate-400">No companies yet. Create one first.</div>
                      : boCompanies.map((c) => <SelectItem key={c.farmId} value={c.farmId}>{c.name} · {c.type}</SelectItem>)}
                  </SelectContent>
                </Select>
                <p className="text-xs text-slate-400">The employee is created under this company. Grant access to more companies afterwards from Users &amp; Permissions.</p>
              </div>
            </div>
          )}
          <div className="rounded-xl border border-slate-200 overflow-hidden">
            <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">First Name *</Label>
                <Input name="firstName" value={createForm.firstName} onChange={(e) => setCreateForm({...createForm, firstName: e.target.value})} required disabled={createLoading} placeholder="John" />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Last Name *</Label>
                <Input name="lastName" value={createForm.lastName} onChange={(e) => setCreateForm({...createForm, lastName: e.target.value})} required disabled={createLoading} placeholder="Doe" />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Phone Number *</Label>
                <Input name="phoneNumber" type="tel" value={createForm.phoneNumber} onChange={(e) => setCreateForm({...createForm, phoneNumber: e.target.value})} required disabled={createLoading} placeholder="+233 533431086" />
              </div>
            </div>
          </div>
          <div className="rounded-xl border border-slate-200 overflow-hidden">
            <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Account Information</div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Username * <span className="text-xs text-slate-500 font-normal">(letters, digits, underscores)</span></Label>
                <Input name="userName" value={createForm.userName} onChange={(e) => setCreateForm({...createForm, userName: e.target.value})} required disabled={createLoading} placeholder="james_quayson" pattern="[a-zA-Z0-9_]+" />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Email *</Label>
                <Input name="email" type="email" value={createForm.email} onChange={(e) => setCreateForm({...createForm, email: e.target.value})} required disabled={createLoading} placeholder="employee@example.com" />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Password *</Label>
                <Input name="password" type="password" value={createForm.password} onChange={(e) => setCreateForm({...createForm, password: e.target.value})} required disabled={createLoading} placeholder="At least 4 characters" />
                <p className="text-xs text-slate-500">Min 4 characters</p>
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Confirm Password *</Label>
                <Input name="confirmPassword" type="password" value={createForm.confirmPassword} onChange={(e) => setCreateForm({...createForm, confirmPassword: e.target.value})} required disabled={createLoading} placeholder="Re-enter password" />
              </div>
            </div>
          </div>
          <div className="rounded-xl border border-slate-200 overflow-hidden">
            <div className="bg-cyan-700 px-4 py-2 text-sm font-semibold text-white">Admin Access</div>
            <div className="p-4 bg-white space-y-4">
              <div className="flex items-center justify-between gap-3 p-3 rounded-lg border border-slate-200 bg-slate-50">
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-slate-800">Create as administrator</p>
                  <p className="text-xs text-slate-500">Enable this to assign granular admin permissions.</p>
                </div>
                <Switch
                  checked={createForm.isAdmin}
                  onCheckedChange={(checked) => setCreateForm({ ...createForm, isAdmin: checked })}
                  disabled={createLoading}
                  aria-label="Create as administrator"
                />
              </div>

              {createForm.isAdmin && (
                <div className="space-y-4">
                  <div className="rounded-lg border border-slate-200 p-3 bg-cyan-50/60">
                    <p className="text-sm font-medium text-slate-800">
                      {createForm.firstName || createForm.userName || "New admin"}
                    </p>
                    <p className="text-xs text-slate-600">
                      Configure what this admin can do. Permissions can be updated later.
                    </p>
                  </div>

                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Custom title (optional)</Label>
                    <Input
                      name="adminTitle"
                      value={createForm.adminTitle}
                      onChange={(e) => setCreateForm({ ...createForm, adminTitle: e.target.value })}
                      disabled={createLoading}
                      placeholder="admin"
                      maxLength={30}
                    />
                    <p className="text-xs text-slate-500">Shown instead of the default admin label.</p>
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
                          checked={createForm.adminPermissions[perm.key]}
                          onCheckedChange={(checked) =>
                            setCreateForm({
                              ...createForm,
                              adminPermissions: { ...createForm.adminPermissions, [perm.key]: checked },
                            })
                          }
                          disabled={createLoading}
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
              <p className="text-xs text-slate-600">Set exactly what employees can access.</p>
              <Button
                type="button"
                variant="outline"
                className="w-full justify-between"
                onClick={() => setShowStaffPermissions((prev) => !prev)}
                disabled={createLoading}
              >
                <span>Select Staff Permissions</span>
                <ChevronDown className={cn("h-4 w-4 transition-transform", showStaffPermissions && "rotate-180")} />
              </Button>

              {showStaffPermissions && (
                <div className="rounded-lg border border-slate-200 divide-y">
                  {staffOptions.map((perm) => (
                    <div key={perm.key} className="flex items-center justify-between gap-3 px-3 py-2">
                      <div className="min-w-0">
                        <p className="text-sm text-slate-800">{perm.label}</p>
                        {perm.hint && <p className="text-xs text-slate-500">{perm.hint}</p>}
                      </div>
                      <Switch
                        checked={createForm.featurePermissions[perm.key]}
                        onCheckedChange={(checked) =>
                          setCreateForm({
                            ...createForm,
                            featurePermissions: { ...createForm.featurePermissions, [perm.key]: checked },
                          })
                        }
                        disabled={createLoading}
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
            <Button type="submit" disabled={createLoading}>
              {createLoading ? (
                <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating...</>
              ) : (
                <><UserCog className="w-4 h-4 mr-2" />{createForm.isAdmin ? "Create Admin" : "Create Employee"}</>
              )}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}

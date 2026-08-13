"use client"

// =============================================================================
// EmployeeAccessFields — the "Admin Access" and "Staff Page Access" panels.
//
// Lifted out of components/employees/edit-employee-dialog.tsx so the Business
// Office "Manage access" dialog renders exactly the same controls rather than a
// second copy that can drift. Purely controlled: the caller owns the snapshot
// and the save.
// =============================================================================

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { ChevronDown } from "lucide-react"
import { cn } from "@/lib/utils"
import { ADMIN_PERMISSION_OPTIONS, STAFF_FEATURE_PERMISSION_OPTIONS } from "@/lib/employees/permissions"
import type { EmployeePermissionSnapshot } from "@/lib/employees/permissions-io"

export function EmployeeAccessFields({
  value,
  onChange,
  disabled = false,
  /** Start the staff list expanded (the Manage access dialog is all about it). */
  defaultStaffOpen = false,
}: {
  value: EmployeePermissionSnapshot
  onChange: (next: EmployeePermissionSnapshot) => void
  disabled?: boolean
  defaultStaffOpen?: boolean
}) {
  const [showStaffPermissions, setShowStaffPermissions] = useState(defaultStaffOpen)

  return (
    <>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-cyan-700 px-4 py-2 text-sm font-semibold text-white">Admin Access</div>
        <div className="p-4 bg-white space-y-4">
          <div className="flex items-center justify-between gap-3 p-3 rounded-lg border border-slate-200 bg-slate-50">
            <div className="min-w-0">
              <p className="text-sm font-semibold text-slate-800">Grant administrator access</p>
              <p className="text-xs text-slate-500">Turn on to configure admin-only actions for this employee.</p>
            </div>
            <Switch
              checked={value.isAdmin}
              onCheckedChange={(checked) => onChange({ ...value, isAdmin: checked })}
              disabled={disabled}
              aria-label="Grant administrator access"
            />
          </div>

          {value.isAdmin && (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Custom title (optional)</Label>
                <Input
                  name="adminTitle"
                  value={value.adminTitle}
                  onChange={(e) => onChange({ ...value, adminTitle: e.target.value })}
                  disabled={disabled}
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
                      checked={value.adminPermissions[perm.key]}
                      onCheckedChange={(checked) =>
                        onChange({ ...value, adminPermissions: { ...value.adminPermissions, [perm.key]: checked } })
                      }
                      disabled={disabled}
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
            onClick={() => setShowStaffPermissions((prev) => !prev)}
            disabled={disabled}
          >
            <span>Select Staff Permissions</span>
            <ChevronDown className={cn("h-4 w-4 transition-transform", showStaffPermissions && "rotate-180")} />
          </Button>

          {showStaffPermissions && (
            <div className="rounded-lg border border-slate-200 divide-y">
              {STAFF_FEATURE_PERMISSION_OPTIONS.map((perm) => (
                <div key={perm.key} className="flex items-center justify-between gap-3 px-3 py-2">
                  <p className="text-sm text-slate-800">{perm.label}</p>
                  <Switch
                    checked={value.featurePermissions[perm.key]}
                    onCheckedChange={(checked) =>
                      onChange({ ...value, featurePermissions: { ...value.featurePermissions, [perm.key]: checked } })
                    }
                    disabled={disabled}
                    aria-label={perm.label}
                  />
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </>
  )
}

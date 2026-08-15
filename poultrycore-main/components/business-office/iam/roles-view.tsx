"use client"

// Access Management → Roles. Lists every role the organization can use and lets
// custom ones be created, renamed and removed.
//
// Built-in roles are read-only by design: they are shared across every customer,
// so renaming "Accountant" here would rename it for everybody. The way to get a
// tailored role is Duplicate, which clones the grants into a role this
// organization owns — a better start than 340 empty checkboxes.
import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import { Crown, Loader2, Pencil, Plus, Copy, Trash2, Users } from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { saveRole, deleteRole, type IamRole } from "@/lib/api/iam"

const COMPANY_TYPES = [
  { value: "any", label: "Any company type" },
  { value: "Poultry", label: "Poultry only" },
  { value: "Water", label: "Water only" },
  { value: "Generic", label: "Company only" },
]

export function RolesView({
  roles, selectedRoleId, onSelect, farmId, canCreate, canEdit, canDelete, onChanged,
}: {
  roles: IamRole[]
  selectedRoleId: number | null
  onSelect: (roleId: number) => void
  farmId: string | null
  canCreate: boolean
  canEdit: boolean
  canDelete: boolean
  onChanged: () => void | Promise<void>
}) {
  const { toast } = useToast()
  const [editorOpen, setEditorOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<IamRole | null>(null)
  const [deleting, setDeleting] = useState(false)

  // The editor doubles as create, rename and duplicate — they differ only in
  // which ids are carried, so one form covers all three.
  const [form, setForm] = useState<{
    roleId?: number; name: string; description: string; companyType: string; copyFromRoleId?: number
  }>({ name: "", description: "", companyType: "any" })

  function openCreate() {
    setForm({ name: "", description: "", companyType: "any" })
    setEditorOpen(true)
  }

  function openEdit(role: IamRole) {
    setForm({
      roleId: role.roleId, name: role.name, description: role.description ?? "",
      companyType: role.companyType ?? "any",
    })
    setEditorOpen(true)
  }

  function openDuplicate(role: IamRole) {
    setForm({
      name: `${role.name} (copy)`, description: role.description ?? "",
      companyType: role.companyType ?? "any", copyFromRoleId: role.roleId,
    })
    setEditorOpen(true)
  }

  async function save() {
    if (!form.name.trim()) {
      toast({ title: "Name required", description: "Give the role a name.", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      const res = await saveRole({
        roleId: form.roleId,
        name: form.name.trim(),
        description: form.description.trim() || null,
        companyType: form.companyType === "any" ? null : form.companyType,
        copyFromRoleId: form.copyFromRoleId ?? null,
      }, farmId)

      if (!res.success) {
        toast({ title: "Could not save role", description: res.message, variant: "destructive" })
        return
      }
      toast({
        title: form.roleId ? "Role updated" : "Role created",
        description: form.copyFromRoleId ? "Permissions were copied from the original." : form.name.trim(),
      })
      setEditorOpen(false)
      await onChanged()
      if (res.roleId) onSelect(res.roleId)
    } finally { setSaving(false) }
  }

  async function confirmDelete() {
    if (!deleteTarget) return
    setDeleting(true)
    try {
      const res = await deleteRole(deleteTarget.roleId, farmId)
      if (!res.success) {
        // The proc refuses while anyone still holds the role and says how many —
        // that message is the useful part, so show it verbatim.
        toast({ title: "Could not delete role", description: res.message, variant: "destructive" })
        return
      }
      toast({ title: "Role deleted", description: deleteTarget.name })
      setDeleteTarget(null)
      await onChanged()
    } finally { setDeleting(false) }
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Button onClick={openCreate} disabled={!canCreate}>
          <Plus className="h-4 w-4 mr-2" /> New role
        </Button>
      </div>

      <div className="grid gap-3 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
        {roles.map((r) => (
          <div
            key={r.roleId}
            onClick={() => onSelect(r.roleId)}
            className={cn(
              "text-left p-4 bg-white rounded-xl border shadow-sm transition-colors cursor-pointer",
              selectedRoleId === r.roleId ? "border-indigo-300 ring-1 ring-indigo-200" : "border-slate-200 hover:bg-slate-50"
            )}
          >
            <div className="flex items-start justify-between gap-2">
              <div className="font-semibold text-slate-900 flex items-center gap-1.5 min-w-0">
                {r.isSuperuser && <Crown className="h-4 w-4 text-amber-500 shrink-0" />}
                <span className="truncate">{r.name}</span>
              </div>
              {r.isSystem
                ? <Badge variant="secondary" className="shrink-0 text-[10px]">Built-in</Badge>
                : <Badge className="shrink-0 text-[10px] bg-indigo-100 text-indigo-700 hover:bg-indigo-100">Custom</Badge>}
            </div>

            <p className="text-xs text-slate-500 mt-1.5 min-h-[2.5rem]">{r.description}</p>

            <div className="flex items-center gap-3 text-xs text-slate-600 tabular-nums">
              <span>
                {r.isSuperuser ? "Every permission" : `${r.permissionCount.toLocaleString()} permissions`}
              </span>
              {/* Guarded: the frontend and Farm API are separate Cloud Run
                  services, so this field can be absent for a deploy or two. */}
              <span className="flex items-center gap-1 text-slate-500">
                <Users className="h-3 w-3" /> {(r.assignedUserCount ?? 0).toLocaleString()}
              </span>
            </div>

            {r.companyType && (
              <div className="mt-1.5"><Badge variant="outline" className="text-[10px]">{r.companyType} only</Badge></div>
            )}

            <div className="flex items-center gap-1 mt-3" onClick={(e) => e.stopPropagation()}>
              <Button variant="outline" size="sm" onClick={() => openDuplicate(r)} disabled={!canCreate}>
                <Copy className="h-3.5 w-3.5 mr-1" /> Duplicate
              </Button>
              {!r.isSystem && (
                <>
                  <Button variant="outline" size="sm" onClick={() => openEdit(r)} disabled={!canEdit}>
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    className="text-red-600 border-red-200 hover:bg-red-50 hover:text-red-700"
                    onClick={() => setDeleteTarget(r)}
                    disabled={!canDelete}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </>
              )}
            </div>
          </div>
        ))}
      </div>

      <Dialog open={editorOpen} onOpenChange={(o) => !saving && setEditorOpen(o)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>
              {form.roleId ? "Rename role" : form.copyFromRoleId ? "Duplicate role" : "New role"}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="iam-role-name">Name</Label>
              <Input
                id="iam-role-name"
                value={form.name}
                onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
                placeholder="e.g. Feed Store Manager"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="iam-role-desc">Description</Label>
              <Textarea
                id="iam-role-desc"
                value={form.description}
                onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
                placeholder="What this role is for."
                rows={3}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Offer this role for</Label>
              <Select value={form.companyType} onValueChange={(v) => setForm((f) => ({ ...f, companyType: v }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {COMPANY_TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
                </SelectContent>
              </Select>
              <p className="text-xs text-slate-500">
                Restricting the type keeps the role out of pickers where it makes no sense.
              </p>
            </div>
            {form.copyFromRoleId && (
              <p className="text-xs text-slate-500">
                Permissions will be copied from the original. You can change them in the Permission Matrix afterwards.
              </p>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditorOpen(false)} disabled={saving}>Cancel</Button>
            <Button onClick={save} disabled={saving}>
              {saving ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Saving…</> : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={!!deleteTarget} onOpenChange={(o) => { if (!o && !deleting) setDeleteTarget(null) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete role</AlertDialogTitle>
            <AlertDialogDescription>
              Delete {deleteTarget?.name}? This cannot be undone. If anyone still holds the role, remove it
              from them first — the delete will be refused until then.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={(e) => { e.preventDefault(); confirmDelete() }}
              disabled={deleting}
              className="bg-red-600 hover:bg-red-700 focus:ring-red-600"
            >
              {deleting ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Deleting…</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

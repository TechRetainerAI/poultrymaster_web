"use client"

// Access Management → Permission Matrix.
//
// Resources down, actions across. Built-in roles render read-only; custom roles
// are editable, with row and column select-all because setting up an Accountant
// one checkbox at a time across 340 keys is not a thing anyone would do twice.
//
// Edits are held locally and saved as one replace-the-whole-set call. The dirty
// state is tracked against what the server returned so "Save" is only offered
// when something actually changed.
import { Fragment, useEffect, useMemo, useState } from "react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import { Loader2, Check, Minus, Save, RotateCcw, Lock } from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { getRolePermissions, setRolePermissions, type IamPermission, type IamRole } from "@/lib/api/iam"
import { ACTIONS, ACTION_LABEL, MODULE_LABEL, buildMatrix } from "./shared"

export function MatrixView({
  catalog, roles, selectedRoleId, onSelectRole, module, onModuleChange, farmId, canEdit, onChanged,
}: {
  catalog: IamPermission[]
  roles: IamRole[]
  selectedRoleId: number | null
  onSelectRole: (roleId: number) => void
  module: string
  onModuleChange: (module: string) => void
  farmId: string | null
  canEdit: boolean
  onChanged: () => void | Promise<void>
}) {
  const { toast } = useToast()
  const [saved, setSaved] = useState<Set<string>>(new Set())
  const [draft, setDraft] = useState<Set<string>>(new Set())
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const role = roles.find((r) => r.roleId === selectedRoleId) ?? null
  // A superuser role holds everything by definition rather than by grant rows,
  // so there is nothing meaningful to edit.
  const editable = canEdit && !!role && !role.isSystem && !role.isSuperuser

  useEffect(() => {
    if (selectedRoleId == null) { setSaved(new Set()); setDraft(new Set()); return }
    let cancelled = false
    void (async () => {
      setLoading(true)
      const keys = await getRolePermissions(selectedRoleId, farmId)
      if (cancelled) return
      const set = new Set(keys ?? [])
      setSaved(set)
      setDraft(new Set(set))
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [selectedRoleId, farmId])

  const matrix = useMemo(() => buildMatrix(catalog, module), [catalog, module])

  const dirty = useMemo(() => {
    if (draft.size !== saved.size) return true
    for (const k of draft) if (!saved.has(k)) return true
    return false
  }, [draft, saved])

  function toggle(key: string, on: boolean) {
    setDraft((prev) => {
      const next = new Set(prev)
      if (on) next.add(key); else next.delete(key)
      return next
    })
  }

  /** Set every key in this list at once — used by the row and column headers. */
  function setMany(keys: string[], on: boolean) {
    setDraft((prev) => {
      const next = new Set(prev)
      for (const k of keys) { if (on) next.add(k); else next.delete(k) }
      return next
    })
  }

  /** Keys for one action across the whole visible module — the column header. */
  function columnKeys(action: string): string[] {
    return matrix.flatMap(({ rows }) =>
      rows.map((r) => r.actions.get(action)?.permissionKey).filter((k): k is string => !!k))
  }

  async function save() {
    if (selectedRoleId == null) return
    setSaving(true)
    try {
      // The draft holds keys for every module, not just the one on screen, so
      // switching module mid-edit does not silently drop the other modules'
      // grants when saving.
      const res = await setRolePermissions(selectedRoleId, Array.from(draft), farmId)
      if (!res.success) {
        toast({ title: "Could not save permissions", description: res.message, variant: "destructive" })
        return
      }
      setSaved(new Set(draft))
      toast({ title: "Permissions saved", description: role?.name })
      await onChanged()
    } finally { setSaving(false) }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Select value={String(selectedRoleId ?? "")} onValueChange={(v) => onSelectRole(Number(v))}>
          <SelectTrigger className="w-[220px] h-9"><SelectValue placeholder="Choose a role" /></SelectTrigger>
          <SelectContent>
            {roles.map((r) => <SelectItem key={r.roleId} value={String(r.roleId)}>{r.name}</SelectItem>)}
          </SelectContent>
        </Select>

        <Select value={module} onValueChange={onModuleChange}>
          <SelectTrigger className="w-[180px] h-9"><SelectValue /></SelectTrigger>
          <SelectContent>
            {Object.entries(MODULE_LABEL).map(([k, label]) => (
              <SelectItem key={k} value={k}>{label}</SelectItem>
            ))}
          </SelectContent>
        </Select>

        {role?.isSuperuser ? (
          <span className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-2 py-1">
            Superuser — holds everything, including permissions added in future
          </span>
        ) : role?.isSystem ? (
          <span className="text-xs text-slate-600 bg-slate-100 border border-slate-200 rounded px-2 py-1 flex items-center gap-1">
            <Lock className="h-3 w-3" /> Built-in role — duplicate it to make an editable copy
          </span>
        ) : null}

        {dirty && editable && (
          <div className="ml-auto flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => setDraft(new Set(saved))} disabled={saving}>
              <RotateCcw className="h-3.5 w-3.5 mr-1.5" /> Reset
            </Button>
            <Button size="sm" onClick={save} disabled={saving}>
              {saving
                ? <><Loader2 className="h-3.5 w-3.5 mr-1.5 animate-spin" /> Saving…</>
                : <><Save className="h-3.5 w-3.5 mr-1.5" /> Save changes</>}
            </Button>
          </div>
        )}
      </div>

      <Card><CardContent className="p-0 overflow-x-auto">
        {loading ? (
          <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
              <tr>
                <th className="text-left font-semibold px-4 py-3 min-w-[220px]">Resource</th>
                {ACTIONS.map((a) => {
                  const keys = columnKeys(a)
                  const all = keys.length > 0 && keys.every((k) => draft.has(k))
                  return (
                    <th key={a} className="font-semibold px-3 py-3 text-center whitespace-nowrap">
                      <div className="flex flex-col items-center gap-1">
                        <span>{ACTION_LABEL[a]}</span>
                        {editable && keys.length > 0 && (
                          <Checkbox
                            checked={all}
                            onCheckedChange={(c) => setMany(keys, c === true)}
                            aria-label={`Grant ${ACTION_LABEL[a]} on everything visible`}
                          />
                        )}
                      </div>
                    </th>
                  )
                })}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {matrix.map(({ group, rows }) => (
                <Fragment key={group}>
                  <tr className="bg-slate-50/70">
                    <td colSpan={ACTIONS.length + 1} className="px-4 py-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
                      {group}
                    </td>
                  </tr>
                  {rows.map((row) => {
                    const rowKeys = Array.from(row.actions.values()).map((p) => p.permissionKey)
                    const allRow = rowKeys.every((k) => draft.has(k))
                    return (
                      <tr key={`${group}-${row.resource}`} className="hover:bg-slate-50/60">
                        <td className="px-4 py-2.5">
                          <div className="flex items-start gap-2">
                            {editable && (
                              <Checkbox
                                className="mt-0.5"
                                checked={allRow}
                                onCheckedChange={(c) => setMany(rowKeys, c === true)}
                                aria-label={`Grant everything on ${row.label}`}
                              />
                            )}
                            <div>
                              <div className="font-medium text-slate-900">{row.label}</div>
                              {row.description && <div className="text-xs text-slate-500">{row.description}</div>}
                            </div>
                          </div>
                        </td>
                        {ACTIONS.map((a) => {
                          const perm = row.actions.get(a)
                          // No catalog entry means the pairing is meaningless (a
                          // report cannot be approved) — distinct from "not granted".
                          if (!perm) return <td key={a} className="px-3 py-2.5 text-center text-slate-200">·</td>
                          const on = draft.has(perm.permissionKey)
                          return (
                            <td key={a} className="px-3 py-2.5 text-center">
                              {editable ? (
                                <Checkbox
                                  checked={on}
                                  onCheckedChange={(c) => toggle(perm.permissionKey, c === true)}
                                  aria-label={`${row.label}: ${ACTION_LABEL[a]}`}
                                  className={cn(perm.isDangerous && "data-[state=checked]:bg-amber-600 data-[state=checked]:border-amber-600")}
                                />
                              ) : on ? (
                                <Check className={cn("h-4 w-4 inline", perm.isDangerous ? "text-amber-600" : "text-emerald-600")} />
                              ) : (
                                <Minus className="h-4 w-4 inline text-slate-300" />
                              )}
                            </td>
                          )
                        })}
                      </tr>
                    )
                  })}
                </Fragment>
              ))}
            </tbody>
          </table>
        )}
      </CardContent></Card>

      <p className="text-xs text-slate-400">
        Amber marks a destructive or sensitive permission — deleting, approving, or seeing cost figures.
        <span className="text-slate-300"> ·</span> means the action does not apply to that resource.
        {editable && " Column and row checkboxes apply to everything currently visible in this module."}
      </p>
    </div>
  )
}

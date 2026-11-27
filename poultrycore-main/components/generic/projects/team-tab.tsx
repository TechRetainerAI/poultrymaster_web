"use client"

// 500: the project TEAM -- which staff work on this project. A plain list: it
// posts nothing and changes no total. Employee Credit and Employee Loans &
// Advances use it to show "the staff working on this project".

import { useCallback, useEffect, useState } from "react"
import { Loader2, Plus, Trash2 } from "lucide-react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { getStaff, type GenericStaff } from "@/lib/api/generic"
import { getProjectTeam, saveProjectTeam, type ProjectTeamMember } from "@/lib/api/generic-projects"

const staffName = (s: GenericStaff) => `${s.firstName ?? ""} ${s.lastName ?? ""}`.trim() || `Staff #${s.genericStaffId}`

export function TeamTab({ projectId }: { projectId: number }) {
  const { toast } = useToast()
  const { can } = usePermissions()
  const canEdit = can("generic.projects.edit")
  const [team, setTeam] = useState<ProjectTeamMember[] | null>(null)
  const [draft, setDraft] = useState<ProjectTeamMember[]>([])
  const [staff, setStaff] = useState<GenericStaff[]>([])
  const [adding, setAdding] = useState("")
  const [saving, setSaving] = useState(false)

  const load = useCallback(async () => {
    try {
      const t = await getProjectTeam(projectId)
      setTeam(t); setDraft(t)
    } catch (e: any) {
      toast({ title: "Could not load the team", description: e?.message, variant: "destructive" })
      setTeam([]); setDraft([])
    }
  }, [projectId, toast])
  useEffect(() => { void load(); getStaff().then(setStaff).catch(() => {}) }, [load])

  const dirty = JSON.stringify(team ?? []) !== JSON.stringify(draft)
  const available = staff.filter((s) => !draft.some((m) => m.staffId === s.genericStaffId))
  const nameOf = (id: number) => {
    const s = staff.find((x) => x.genericStaffId === id)
    return s ? staffName(s) : (team?.find((m) => m.staffId === id)?.name ?? `Staff #${id}`)
  }
  const update = (id: number, patch: Partial<ProjectTeamMember>) =>
    setDraft((d) => d.map((m) => (m.staffId === id ? { ...m, ...patch } : m)))

  const save = async () => {
    setSaving(true)
    try {
      const saved = await saveProjectTeam(projectId, draft.map(({ staffId, role, startDate, endDate }) => ({
        staffId, role: role?.trim() || null, startDate: startDate || null, endDate: endDate || null,
      })))
      setTeam(saved); setDraft(saved)
      toast({ title: "Team saved" })
    } catch (e: any) {
      toast({ title: "Could not save the team", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between space-y-0 gap-3">
        <div>
          <CardTitle className="text-base">Team</CardTitle>
          <CardDescription>
            The staff working on this project. Employee Credit and Employee Loans &amp; Advances can be filtered to them.
            A staff member can be on several projects. Nothing here records money.
          </CardDescription>
        </div>
        {canEdit && dirty && (
          <div className="flex shrink-0 gap-2">
            <Button size="sm" variant="outline" onClick={() => setDraft(team ?? [])} disabled={saving}>Discard</Button>
            <Button size="sm" onClick={save} disabled={saving}>{saving && <Loader2 className="mr-1 h-4 w-4 animate-spin" />}Save team</Button>
          </div>
        )}
      </CardHeader>
      <CardContent className="space-y-3">
        {canEdit && (
          <div className="flex flex-wrap items-end gap-2">
            <div className="w-full sm:w-72">
              <Select value={adding} onValueChange={setAdding}>
                <SelectTrigger><SelectValue placeholder={available.length ? "Choose a staff member" : "Everyone is on the team"} /></SelectTrigger>
                <SelectContent>
                  {available.map((s) => <SelectItem key={s.genericStaffId} value={String(s.genericStaffId)}>{staffName(s)}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <Button size="sm" variant="outline" disabled={!adding} onClick={() => {
              setDraft((d) => [...d, { staffId: Number(adding), role: null, startDate: null, endDate: null }])
              setAdding("")
            }}><Plus className="mr-1 h-4 w-4" />Add to team</Button>
          </div>
        )}
        {!team ? <Loader2 className="h-5 w-5 animate-spin text-slate-400" />
          : draft.length === 0 ? <p className="py-6 text-center text-sm text-slate-500">No one is on this project&apos;s team yet.</p> : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Staff</TableHead><TableHead>Role</TableHead><TableHead>From</TableHead><TableHead>To</TableHead><TableHead />
                </TableRow></TableHeader>
                <TableBody>
                  {draft.map((m) => (
                    <TableRow key={m.staffId}>
                      <TableCell className="font-medium">{nameOf(m.staffId)}</TableCell>
                      <TableCell>{canEdit
                        ? <Input className="h-8 w-44" placeholder="e.g. Site supervisor" value={m.role ?? ""} onChange={(e) => update(m.staffId, { role: e.target.value })} />
                        : (m.role ?? "—")}</TableCell>
                      <TableCell>{canEdit
                        ? <Input type="date" className="h-8 w-40" value={m.startDate?.slice(0, 10) ?? ""} onChange={(e) => update(m.staffId, { startDate: e.target.value })} />
                        : (m.startDate?.slice(0, 10) ?? "—")}</TableCell>
                      <TableCell>{canEdit
                        ? <Input type="date" className="h-8 w-40" value={m.endDate?.slice(0, 10) ?? ""} onChange={(e) => update(m.staffId, { endDate: e.target.value })} />
                        : (m.endDate?.slice(0, 10) ?? "—")}</TableCell>
                      <TableCell className="text-right">{canEdit && (
                        <Button variant="ghost" size="sm" title="Remove from the team"
                          onClick={() => setDraft((d) => d.filter((x) => x.staffId !== m.staffId))}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      )}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        {canEdit && dirty && <p className="text-xs text-amber-700">You have unsaved changes to the team.</p>}
      </CardContent>
    </Card>
  )
}

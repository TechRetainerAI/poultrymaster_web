"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Plus, Pencil, Loader2, UserCog, CalendarCheck, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listPoultryStaff, createPoultryStaff, updatePoultryStaff, deletePoultryStaff,
  upsertPoultryStaffAttendance,
  POULTRY_STAFF_ROLES, POULTRY_STAFF_SALARY_TYPES, POULTRY_ATTENDANCE_STATUS,
  type PoultryStaff,
} from "@/lib/api/poultry-finance"

const ROLES = [...POULTRY_STAFF_ROLES]
const SALARY_TYPES = [...POULTRY_STAFF_SALARY_TYPES]
const ATT_STATUS = [...POULTRY_ATTENDANCE_STATUS]
const today = () => new Date().toISOString().split("T")[0]

export default function PoultryStaffPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [staff, setStaff] = useState<PoultryStaff[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")

  const visible = useMemo(
    () => filterByDateAndSearch(staff, { search, dateFrom: "", dateTo: "", searchKeys: ["firstName", "lastName", "role", "phoneNumber"] }),
    [staff, search],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visible)

  const emptyForm = { firstName: "", lastName: "", phoneNumber: "", email: "", role: "FarmHand", salaryType: "Monthly", basePay: 0, commissionRate: 0, isActive: true, notes: "" }
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState({ ...emptyForm })
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<PoultryStaff | null>(null)

  const [attDlg, setAttDlg] = useState<{ open: boolean; staff?: PoultryStaff }>({ open: false })
  const [att, setAtt] = useState({ attendanceDate: today(), status: "Present", shift: "", notes: "" })
  const [attSaving, setAttSaving] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setStaff(await listPoultryStaff()) }
    catch (e: any) { toast({ title: "Could not load staff", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm({ ...emptyForm }); setOpen(true) }
  function openEdit(s: PoultryStaff) {
    setEditId(s.poultryStaffId)
    setForm({
      firstName: s.firstName, lastName: s.lastName, phoneNumber: s.phoneNumber ?? "", email: s.email ?? "",
      role: s.role, salaryType: s.salaryType, basePay: s.basePay, commissionRate: s.commissionRate ?? 0,
      isActive: s.isActive, notes: s.notes ?? "",
    })
    setOpen(true)
  }

  async function save() {
    if (!form.firstName.trim() || !form.lastName.trim()) return toast({ title: "First and last name required", variant: "destructive" })
    setSaving(true)
    try {
      const payload = {
        firstName: form.firstName, lastName: form.lastName, phoneNumber: form.phoneNumber || null, email: form.email || null,
        role: form.role, salaryType: form.salaryType, basePay: Number(form.basePay) || 0,
        commissionRate: Number(form.commissionRate) || null, isActive: form.isActive, notes: form.notes || null,
      }
      if (editId) { await updatePoultryStaff(editId, payload); toast({ title: "Staff updated" }) }
      else { await createPoultryStaff(payload); toast({ title: "Staff added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(s: PoultryStaff) {
    await deletePoultryStaff(s.poultryStaffId)
    toast({ title: "Staff removed" })
    await load()
  }

  function openAttendance(s: PoultryStaff) { setAttDlg({ open: true, staff: s }); setAtt({ attendanceDate: today(), status: "Present", shift: "", notes: "" }) }
  async function saveAttendance() {
    if (!attDlg.staff) return
    setAttSaving(true)
    try {
      await upsertPoultryStaffAttendance({
        poultryStaffId: attDlg.staff.poultryStaffId,
        attendanceDate: att.attendanceDate,
        status: att.status,
        shift: att.shift || null,
        notes: att.notes || null,
      })
      toast({ title: "Attendance recorded", description: `${attDlg.staff.firstName} ${attDlg.staff.lastName} · ${att.status} on ${att.attendanceDate}` })
      setAttDlg({ open: false })
    } catch (e: any) { toast({ title: "Could not record attendance", description: e?.message, variant: "destructive" }) }
    finally { setAttSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <UserCog className="h-6 w-6 text-indigo-600" /> Staff
            </h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New staff</Button>
          </div>

          <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search name, role or phone" />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : staff.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No staff yet. Add your first team member above.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(s) => s.poultryStaffId}
                  primary={(s) => `${s.firstName} ${s.lastName}`}
                  secondary={(s) => (<><span>{s.role}</span>{s.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</>)}
                  details={(s) => [
                    { label: "Role", value: s.role },
                    { label: "Salary type", value: s.salaryType },
                    { label: "Base pay", value: s.basePay.toFixed(2) },
                    { label: "Phone", value: s.phoneNumber ?? "—" },
                  ]}
                  actions={(s) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openAttendance(s)}><CalendarCheck className="h-4 w-4 mr-1" /> Attendance</Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(s)}>Edit</Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(s)}><Trash2 className="h-4 w-4 mr-1" /> Delete</Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Name</TableHead>
                            <TableHead>Role</TableHead>
                            <TableHead>Salary type</TableHead>
                            <TableHead className="text-right">Base pay</TableHead>
                            <TableHead>Phone</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((s) => (
                            <TableRow key={s.poultryStaffId}>
                              <TableCell className="font-medium">{s.firstName} {s.lastName}</TableCell>
                              <TableCell>{s.role}</TableCell>
                              <TableCell>{s.salaryType}</TableCell>
                              <TableCell className="text-right tabular-nums">{s.basePay.toFixed(2)}</TableCell>
                              <TableCell>{s.phoneNumber ?? "—"}</TableCell>
                              <TableCell>{s.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                              <TableCell className="text-right">
                                <Button size="sm" variant="ghost" onClick={() => openAttendance(s)} title="Record attendance"><CalendarCheck className="h-4 w-4" /></Button>
                                <Button size="sm" variant="ghost" onClick={() => openEdit(s)}>Edit</Button>
                                <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(s)} title="Remove staff"><Trash2 className="h-4 w-4 text-red-500" /></Button>
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* Create/edit staff */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <UserCog className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit staff" : "New staff"}
            </DialogTitle>
            <DialogDescription>Team members available for payroll runs</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Person" color="indigo">
              <FormField label="First name *"><Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} /></FormField>
              <FormField label="Last name *"><Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} /></FormField>
              <FormField label="Phone"><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></FormField>
              <FormField label="Email"><Input value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></FormField>
            </FormSection>

            <FormSection title="Pay" color="amber">
              <FormField label="Role">
                <Select value={form.role} onValueChange={(v) => setForm({ ...form, role: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{ROLES.map(r => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Salary type">
                <Select value={form.salaryType} onValueChange={(v) => setForm({ ...form, salaryType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{SALARY_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Base pay"><NumberInput step="0.01" value={form.basePay} onChange={(e) => setForm({ ...form, basePay: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="Commission rate"><NumberInput step="0.0001" value={form.commissionRate} onChange={(e) => setForm({ ...form, commissionRate: Number(e.target.value) || 0 })} /></FormField>
            </FormSection>

            <FormSection title="Other" color="slate" columns={1}>
              {editId && (
                <FormField label="Active">
                  <div className="flex items-center justify-between rounded border p-2">
                    <span className="text-sm text-slate-700">Active</span>
                    <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
                  </div>
                </FormField>
              )}
              <FormField label="Notes"><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={save} disabled={saving}>{saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Record attendance */}
      <Dialog open={attDlg.open} onOpenChange={(v) => setAttDlg({ open: v, staff: v ? attDlg.staff : undefined })}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><CalendarCheck className="w-5 h-5 text-indigo-600" /> Attendance</DialogTitle>
            <DialogDescription>{attDlg.staff ? `${attDlg.staff.firstName} ${attDlg.staff.lastName}` : ""}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Day" color="indigo" columns={1}>
              <FormField label="Date"><Input type="date" value={att.attendanceDate} onChange={(e) => setAtt({ ...att, attendanceDate: e.target.value })} /></FormField>
              <FormField label="Status">
                <Select value={att.status} onValueChange={(v) => setAtt({ ...att, status: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{ATT_STATUS.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Shift"><Input value={att.shift} onChange={(e) => setAtt({ ...att, shift: e.target.value })} placeholder="e.g. Morning" /></FormField>
              <FormField label="Notes"><Input value={att.notes} onChange={(e) => setAtt({ ...att, notes: e.target.value })} /></FormField>
            </FormSection>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" variant="ghost" onClick={() => setAttDlg({ open: false })}>Cancel</Button>
              <Button onClick={saveAttendance} disabled={attSaving}>{attSaving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save attendance"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title={`Remove ${deleteTarget ? `${deleteTarget.firstName} ${deleteTarget.lastName}` : "this staff"}?`}
        description="The staff member is deactivated so their attendance and payroll history stays intact."
        confirmLabel="Remove staff"
        errorTitle="Could not remove staff"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

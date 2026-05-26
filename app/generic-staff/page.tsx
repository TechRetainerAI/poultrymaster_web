"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Plus, Users2, Pencil, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { createStaff, deleteStaff, getStaff, type GenericStaff, type GenericStaffRole, type GenericStaffSalaryType } from "@/lib/api/generic"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"

const ROLES: GenericStaffRole[] = [
  "Owner", "Manager", "Accountant", "Cashier", "Salesperson",
  "InventoryOfficer", "Cleaner", "Security", "Driver", "ServiceProvider", "Other",
]
const SALARY_TYPES: GenericStaffSalaryType[] = ["Daily", "Weekly", "Monthly", "Commission", "Mixed"]

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

export default function GenericStaffPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericStaff[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [filterRole, setFilterRole] = useState<string>("all")
  const [deleteTarget, setDeleteTarget] = useState<GenericStaff | null>(null)

  const [form, setForm] = useState({
    firstName: "",
    lastName: "",
    phoneNumber: "",
    email: "",
    role: "Other" as string,
    salaryType: "Monthly" as string,
    basePay: "0",
    commissionRate: "",
    isActive: true,
    notes: "",
  })

  const load = async () => {
    setLoading(true)
    try {
      setRows(await getStaff(filterRole === "all" ? null : filterRole))
    } catch (e: any) {
      toast({ title: "Could not load staff", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, filterRole])

  const onSave = async () => {
    if (!form.firstName.trim() || !form.lastName.trim()) {
      toast({ title: "First and last name required", variant: "destructive" })
      return
    }
    const basePay = Number(form.basePay)
    if (Number.isNaN(basePay) || basePay < 0) {
      toast({ title: "Base pay must be 0 or more", variant: "destructive" })
      return
    }
    const commissionRate = form.commissionRate.trim() === "" ? null : Number(form.commissionRate)
    if (commissionRate != null && (Number.isNaN(commissionRate) || commissionRate < 0)) {
      toast({ title: "Commission rate must be a non-negative number", variant: "destructive" })
      return
    }

    setSaving(true)
    try {
      const created = await createStaff({
        firstName: form.firstName.trim(),
        lastName:  form.lastName.trim(),
        phoneNumber: form.phoneNumber || null,
        email: form.email || null,
        role: form.role,
        salaryType: form.salaryType,
        basePay,
        commissionRate,
        isActive: form.isActive,
        notes: form.notes || null,
      })
      if (created) {
        toast({ title: `${created.firstName} ${created.lastName} added.` })
        setOpen(false)
        setForm({
          firstName: "", lastName: "", phoneNumber: "", email: "",
          role: "Other", salaryType: "Monthly", basePay: "0", commissionRate: "",
          isActive: true, notes: "",
        })
        await load()
      }
    } catch (e: any) {
      toast({ title: "Could not add staff", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Users2 className="h-6 w-6 text-emerald-600" /> Staff
              </h1>
              <p className="text-sm text-slate-500">{rows.length} staff member(s)</p>
            </div>

            <div className="flex items-center gap-2">
              <Select value={filterRole} onValueChange={setFilterRole}>
                <SelectTrigger className="w-48"><SelectValue placeholder="Filter by role" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All roles</SelectItem>
                  {ROLES.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}
                </SelectContent>
              </Select>

              <Dialog open={open} onOpenChange={setOpen}>
                <DialogTrigger asChild>
                  <Button><Plus className="h-4 w-4 mr-1" />Add staff</Button>
                </DialogTrigger>
                <DialogContent className="max-w-2xl">
                  <DialogHeader>
                    <DialogTitle>New staff member</DialogTitle>
                    <DialogDescription>Names, role, salary basis, and base pay. Commission rate is optional.</DialogDescription>
                  </DialogHeader>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div>
                      <Label>First name *</Label>
                      <Input value={form.firstName} onChange={(e) => setForm((f) => ({ ...f, firstName: e.target.value }))} maxLength={100} />
                    </div>
                    <div>
                      <Label>Last name *</Label>
                      <Input value={form.lastName} onChange={(e) => setForm((f) => ({ ...f, lastName: e.target.value }))} maxLength={100} />
                    </div>
                    <div>
                      <Label>Phone</Label>
                      <Input value={form.phoneNumber} onChange={(e) => setForm((f) => ({ ...f, phoneNumber: e.target.value }))} maxLength={50} />
                    </div>
                    <div>
                      <Label>Email</Label>
                      <Input type="email" value={form.email} onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))} maxLength={200} />
                    </div>
                    <div>
                      <Label>Role</Label>
                      <Select value={form.role} onValueChange={(v) => setForm((f) => ({ ...f, role: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{ROLES.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div>
                      <Label>Salary type</Label>
                      <Select value={form.salaryType} onValueChange={(v) => setForm((f) => ({ ...f, salaryType: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{SALARY_TYPES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div>
                      <Label>Base pay</Label>
                      <Input type="number" step="0.01" min="0" value={form.basePay} onChange={(e) => setForm((f) => ({ ...f, basePay: e.target.value }))} />
                    </div>
                    <div>
                      <Label>Commission rate (optional)</Label>
                      <Input type="number" step="0.0001" min="0" placeholder="e.g. 0.05 for 5%" value={form.commissionRate} onChange={(e) => setForm((f) => ({ ...f, commissionRate: e.target.value }))} />
                    </div>
                    <div className="md:col-span-2 flex items-center gap-2">
                      <Switch checked={form.isActive} onCheckedChange={(v) => setForm((f) => ({ ...f, isActive: v }))} id="active" />
                      <Label htmlFor="active" className="cursor-pointer">Active (uncheck to hide from new payroll runs)</Label>
                    </div>
                    <div className="md:col-span-2">
                      <Label>Notes</Label>
                      <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                    </div>
                  </div>
                  <DialogFooter>
                    <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                    <Button onClick={onSave} disabled={saving}>{saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Create</Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No staff yet. Add your first one.</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
                      <TableHead>Role</TableHead>
                      <TableHead>Salary type</TableHead>
                      <TableHead className="text-right">Base pay</TableHead>
                      <TableHead className="text-right">Commission</TableHead>
                      <TableHead>Phone</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((s) => (
                      <TableRow key={s.genericStaffId}>
                        <TableCell className="font-medium">
                          <Link href={`/generic-staff/${s.genericStaffId}`} className="text-emerald-700 hover:underline">
                            {s.firstName} {s.lastName}
                          </Link>
                        </TableCell>
                        <TableCell><Badge variant="outline">{s.role}</Badge></TableCell>
                        <TableCell>{s.salaryType}</TableCell>
                        <TableCell className="text-right">{fmt(s.basePay)}</TableCell>
                        <TableCell className="text-right">{s.commissionRate != null ? s.commissionRate : "—"}</TableCell>
                        <TableCell>{s.phoneNumber ?? "—"}</TableCell>
                        <TableCell>
                          {s.isActive
                            ? <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Active</Badge>
                            : <Badge variant="secondary">Inactive</Badge>}
                        </TableCell>
                        <TableCell className="text-right">
                          <Link href={`/generic-staff/${s.genericStaffId}`}>
                            <Button size="sm" variant="ghost" title="Edit"><Pencil className="h-4 w-4" /></Button>
                          </Link>
                          <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(s)} title="Archive"><Trash2 className="h-4 w-4 text-red-500" /></Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Archive staff member?"
        description={deleteTarget
          ? `"${deleteTarget.firstName} ${deleteTarget.lastName}" will be soft-deleted. Attendance and payroll history stay intact; they'll be hidden from new payroll runs.`
          : undefined}
        confirmLabel="Archive"
        successTitle="Staff archived"
        errorTitle="Could not archive"
        onConfirm={async () => {
          if (deleteTarget) {
            await deleteStaff(deleteTarget.genericStaffId)
            await load()
          }
        }}
      />
    </div>
  )
}

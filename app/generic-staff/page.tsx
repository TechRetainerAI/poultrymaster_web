"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Plus, Users2, Pencil, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { createStaff, deleteStaff, getStaff, type GenericStaff, type GenericStaffRole, type GenericStaffSalaryType } from "@/lib/api/generic"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"

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
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
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

  const visibleRows = useMemo(
    () => filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      searchKeys: ["firstName", "lastName", "phoneNumber", "email", "role"],
    }),
    [rows, search, dateFrom, dateTo],
  )

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

            <div className="flex items-center gap-2 flex-wrap w-full sm:w-auto">
              <Select value={filterRole} onValueChange={setFilterRole}>
                <SelectTrigger className="w-48"><SelectValue placeholder="Filter by role" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All roles</SelectItem>
                  {ROLES.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}
                </SelectContent>
              </Select>

              <Dialog open={open} onOpenChange={setOpen}>
                <DialogTrigger asChild>
                  <Button className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" />Add staff</Button>
                </DialogTrigger>
                <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
                  <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                      <Users2 className="w-5 h-5 text-blue-600" /> New staff member
                    </DialogTitle>
                    <DialogDescription>Names, role, salary basis, and base pay. Commission rate is optional.</DialogDescription>
                  </DialogHeader>
                  <div className="space-y-4">
                    <FormSection title="Personal information" color="indigo">
                      <FormField label="First name *">
                        <Input value={form.firstName} onChange={(e) => setForm((f) => ({ ...f, firstName: e.target.value }))} maxLength={100} />
                      </FormField>
                      <FormField label="Last name *">
                        <Input value={form.lastName} onChange={(e) => setForm((f) => ({ ...f, lastName: e.target.value }))} maxLength={100} />
                      </FormField>
                      <FormField label="Phone">
                        <Input value={form.phoneNumber} onChange={(e) => setForm((f) => ({ ...f, phoneNumber: e.target.value }))} maxLength={50} />
                      </FormField>
                      <FormField label="Email">
                        <Input type="email" value={form.email} onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))} maxLength={200} />
                      </FormField>
                    </FormSection>

                    <FormSection title="Role & pay" color="blue">
                      <FormField label="Role">
                        <Select value={form.role} onValueChange={(v) => setForm((f) => ({ ...f, role: v }))}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>{ROLES.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
                        </Select>
                      </FormField>
                      <FormField label="Salary type">
                        <Select value={form.salaryType} onValueChange={(v) => setForm((f) => ({ ...f, salaryType: v }))}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>{SALARY_TYPES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                        </Select>
                      </FormField>
                      <FormField label="Base pay">
                        <NumberInput step="0.01" min="0" value={form.basePay} onChange={(e) => setForm((f) => ({ ...f, basePay: e.target.value }))} />
                      </FormField>
                      <FormField label="Commission rate (optional)">
                        <NumberInput step="0.0001" min="0" placeholder="e.g. 0.05 for 5%" value={form.commissionRate} onChange={(e) => setForm((f) => ({ ...f, commissionRate: e.target.value }))} />
                      </FormField>
                    </FormSection>

                    <FormSection title="Status & notes" color="slate" columns={1}>
                      <FormField label="Active">
                        <div className="flex items-center gap-2">
                          <Switch checked={form.isActive} onCheckedChange={(v) => setForm((f) => ({ ...f, isActive: v }))} id="active" />
                          <Label htmlFor="active" className="cursor-pointer text-sm text-slate-600">Uncheck to hide from new payroll runs</Label>
                        </div>
                      </FormField>
                      <FormField label="Notes">
                        <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                      </FormField>
                    </FormSection>

                    <div className="flex gap-3 justify-end pt-2">
                      <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                      <Button onClick={onSave} disabled={saving}>
                        {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Create"}
                      </Button>
                    </div>
                  </div>
                </DialogContent>
              </Dialog>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No staff yet. Add your first one.</CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              searchOnly
              searchPlaceholder="Search name, phone, email or role"
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(s) => s.genericStaffId}
                  primary={(s) => (
                    <Link href={`/generic-staff/${s.genericStaffId}`} className="text-emerald-700 hover:underline">
                      {s.firstName} {s.lastName}
                    </Link>
                  )}
                  secondary={(s) => (
                    <>
                      <Badge variant="outline">{s.role}</Badge>
                      <span>· {s.salaryType}</span>
                    </>
                  )}
                  trailing={(s) => (
                    s.isActive
                      ? <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Active</Badge>
                      : <Badge variant="secondary">Inactive</Badge>
                  )}
                  details={(s) => [
                    { label: "Role", value: s.role },
                    { label: "Salary type", value: s.salaryType },
                    { label: "Base pay", value: fmt(s.basePay) },
                    { label: "Commission", value: s.commissionRate != null ? s.commissionRate : "—" },
                    { label: "Phone", value: s.phoneNumber ?? "—" },
                  ]}
                  actions={(s) => (
                    <>
                      <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                        <Link href={`/generic-staff/${s.genericStaffId}`}>
                          <Pencil className="h-4 w-4 mr-1" /> Edit
                        </Link>
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(s)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Archive
                      </Button>
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
                          <TableHead className="text-right">Commission</TableHead>
                          <TableHead>Phone</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((s) => (
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
                    </div>
                  }
                />
              </CardContent>
            </Card>
            </>
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

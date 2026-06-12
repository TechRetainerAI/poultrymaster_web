"use client"

import { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Loader2, ArrowLeft, Trash2, Save } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  deleteStaff, getStaffMember, updateStaff,
  type GenericStaffRole, type GenericStaffSalaryType,
} from "@/lib/api/generic"

const ROLES: GenericStaffRole[] = [
  "Owner", "Manager", "Accountant", "Cashier", "Salesperson",
  "InventoryOfficer", "Cleaner", "Security", "Driver", "ServiceProvider", "Other",
]
const SALARY_TYPES: GenericStaffSalaryType[] = ["Daily", "Weekly", "Monthly", "Commission", "Mixed"]

export default function GenericStaffDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading]   = useState(true)
  const [saving, setSaving]     = useState(false)
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false)
  const [notFound, setNotFound] = useState(false)

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

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    if (!id || Number.isNaN(id)) { setNotFound(true); setLoading(false); return }
    (async () => {
      try {
        const s = await getStaffMember(id)
        if (!s) { setNotFound(true); return }
        setForm({
          firstName: s.firstName,
          lastName:  s.lastName,
          phoneNumber: s.phoneNumber ?? "",
          email: s.email ?? "",
          role: s.role,
          salaryType: s.salaryType,
          basePay: String(s.basePay),
          commissionRate: s.commissionRate != null ? String(s.commissionRate) : "",
          isActive: s.isActive,
          notes: s.notes ?? "",
        })
      } catch (e: any) {
        toast({ title: "Could not load staff member", description: e?.message ?? String(e), variant: "destructive" })
      } finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, activeFarmType, router])

  const onSave = async () => {
    if (!form.firstName.trim() || !form.lastName.trim()) {
      toast({ title: "First and last name required", variant: "destructive" }); return
    }
    const basePay = Number(form.basePay)
    if (Number.isNaN(basePay) || basePay < 0) {
      toast({ title: "Base pay must be 0 or more", variant: "destructive" }); return
    }
    const commissionRate = form.commissionRate.trim() === "" ? null : Number(form.commissionRate)
    if (commissionRate != null && (Number.isNaN(commissionRate) || commissionRate < 0)) {
      toast({ title: "Commission rate must be a non-negative number", variant: "destructive" }); return
    }

    setSaving(true)
    try {
      await updateStaff(id, {
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
      toast({ title: "Saved." })
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const performDelete = async () => {
    await deleteStaff(id)
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4">
            <Link href="/generic-staff" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700">
              <ArrowLeft className="h-4 w-4 mr-1" /> Back to staff
            </Link>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : notFound ? (
            <Card><CardContent className="py-8 text-center text-slate-500">Staff member not found.</CardContent></Card>
          ) : (
            <Card className="max-w-3xl">
              <CardHeader>
                <CardTitle>Edit staff member</CardTitle>
              </CardHeader>
              <CardContent>
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
                    <NumberInput step="0.01" min="0" value={form.basePay} onChange={(e) => setForm((f) => ({ ...f, basePay: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Commission rate (optional)</Label>
                    <NumberInput step="0.0001" min="0" value={form.commissionRate} onChange={(e) => setForm((f) => ({ ...f, commissionRate: e.target.value }))} />
                  </div>
                  <div className="md:col-span-2 flex items-center gap-2">
                    <Switch checked={form.isActive} onCheckedChange={(v) => setForm((f) => ({ ...f, isActive: v }))} id="active" />
                    <Label htmlFor="active" className="cursor-pointer">Active</Label>
                  </div>
                  <div className="md:col-span-2">
                    <Label>Notes</Label>
                    <Textarea rows={3} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                  </div>
                </div>

                <div className="mt-6 flex items-center justify-between">
                  <Button variant="outline" onClick={() => setConfirmDeleteOpen(true)} className="text-rose-700 hover:bg-rose-50">
                    <Trash2 className="h-4 w-4 mr-2" />
                    Archive
                  </Button>
                  <Button onClick={onSave} disabled={saving}>
                    {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
                    Save changes
                  </Button>
                </div>
              </CardContent>
            </Card>
          )}
        </main>
      </div>

      <ConfirmDeleteDialog
        open={confirmDeleteOpen}
        onOpenChange={setConfirmDeleteOpen}
        title="Archive this staff member?"
        description="The staff member will be soft-deleted. Their attendance and payroll history will remain intact."
        confirmLabel="Archive"
        successTitle="Staff member archived."
        errorTitle="Could not delete"
        onConfirm={performDelete}
        onSuccess={() => router.replace("/generic-staff")}
      />
    </div>
  )
}

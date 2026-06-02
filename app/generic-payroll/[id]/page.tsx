"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Loader2, ArrowLeft, CheckCircle2, Wallet, XCircle, Plus, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  approvePayrollRun, cancelPayrollRun, deletePayrollItem, getPayrollRun, getStaff,
  markPayrollRunPaid, upsertPayrollItem,
  type GenericPayrollRun, type GenericStaff,
} from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function statusBadgeClass(s: string) {
  switch (s) {
    case "Draft":     return "bg-slate-100 text-slate-700 hover:bg-slate-100"
    case "Approved":  return "bg-sky-100 text-sky-800 hover:bg-sky-100"
    case "Paid":      return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    default:          return "bg-slate-100 text-slate-700 hover:bg-slate-100"
  }
}

const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Card"]

export default function GenericPayrollRunDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [run, setRun] = useState<GenericPayrollRun | null>(null)
  const [staff, setStaff] = useState<GenericStaff[]>([])
  const [loading, setLoading] = useState(true)
  const [actionBusy, setActionBusy] = useState<"approve" | "pay" | "cancel" | null>(null)

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [editingItemId, setEditingItemId] = useState<number | null>(null)  // null = new
  const [deleteItemId, setDeleteItemId] = useState<number | null>(null)
  const [form, setForm] = useState({
    genericStaffId: "",
    basicPay: "0",
    dailyWage: "0",
    commission: "0",
    bonus: "0",
    deductions: "0",
    paymentMethod: "Cash",
    notes: "",
  })

  const reload = async () => {
    setLoading(true)
    try {
      const [r, s] = await Promise.all([getPayrollRun(id), getStaff()])
      setRun(r)
      setStaff(s.filter((x) => x.isActive))
    } catch (e: any) {
      toast({ title: "Could not load payroll run", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    if (!id || Number.isNaN(id)) { setLoading(false); return }
    reload()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, activeFarmType, router])

  const isDraft = run?.status === "Draft"
  const isApproved = run?.status === "Approved"
  const isPaid = run?.status === "Paid"
  const isCancelled = run?.status === "Cancelled"

  // Staff already on the run (for the "add line" dialog dropdown).
  const staffOnRun = useMemo(() => new Set((run?.items ?? []).map((i) => i.genericStaffId)), [run])
  const eligibleStaffForNewLine = useMemo(
    () => staff.filter((s) => !staffOnRun.has(s.genericStaffId)),
    [staff, staffOnRun]
  )

  const openAddLine = () => {
    setEditingItemId(null)
    const first = eligibleStaffForNewLine[0]
    setForm({
      genericStaffId: first ? String(first.genericStaffId) : "",
      basicPay:   first?.salaryType === "Monthly" || first?.salaryType === "Weekly" || first?.salaryType === "Daily" ? String(first.basePay) : "0",
      dailyWage:  "0",
      commission: "0",
      bonus:      "0",
      deductions: "0",
      paymentMethod: "Cash",
      notes: "",
    })
    setOpen(true)
  }

  const openEditLine = (itemId: number) => {
    const item = run?.items.find((i) => i.genericPayrollItemId === itemId)
    if (!item) return
    setEditingItemId(itemId)
    setForm({
      genericStaffId: String(item.genericStaffId),
      basicPay:   String(item.basicPay),
      dailyWage:  String(item.dailyWage),
      commission: String(item.commission),
      bonus:      String(item.bonus),
      deductions: String(item.deductions),
      paymentMethod: item.paymentMethod ?? "Cash",
      notes: item.notes ?? "",
    })
    setOpen(true)
  }

  const onSaveLine = async () => {
    if (!form.genericStaffId) {
      toast({ title: "Pick a staff member", variant: "destructive" }); return
    }
    const nums = {
      basicPay:   Number(form.basicPay),
      dailyWage:  Number(form.dailyWage),
      commission: Number(form.commission),
      bonus:      Number(form.bonus),
      deductions: Number(form.deductions),
    }
    for (const [k, v] of Object.entries(nums)) {
      if (Number.isNaN(v) || v < 0) {
        toast({ title: `${k} must be a non-negative number`, variant: "destructive" }); return
      }
    }
    const net = nums.basicPay + nums.dailyWage + nums.commission + nums.bonus - nums.deductions
    if (net < 0) {
      toast({ title: "Net pay cannot be negative", variant: "destructive" }); return
    }

    setSaving(true)
    try {
      await upsertPayrollItem(id, {
        genericStaffId: Number(form.genericStaffId),
        basicPay:   nums.basicPay,
        dailyWage:  nums.dailyWage,
        commission: nums.commission,
        bonus:      nums.bonus,
        deductions: nums.deductions,
        paymentMethod: form.paymentMethod || null,
        notes: form.notes || null,
      })
      toast({ title: editingItemId == null ? "Line added." : "Line updated." })
      setOpen(false)
      await reload()
    } catch (e: any) {
      toast({ title: "Could not save line", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const onDeleteLine = (itemId: number) => {
    setDeleteItemId(itemId)
  }

  const onApprove = async () => {
    if (!run || run.items.length === 0) {
      toast({ title: "Add at least one staff line first", variant: "destructive" }); return
    }
    setActionBusy("approve")
    try {
      await approvePayrollRun(id)
      toast({ title: "Run approved." })
      await reload()
    } catch (e: any) {
      toast({ title: "Could not approve", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActionBusy(null) }
  }

  const onMarkPaid = async () => {
    if (!run?.genericCashAccountId) {
      toast({ title: "Set a cash account on the run before paying", variant: "destructive" }); return
    }
    if (!confirm(`Mark this run Paid? This will debit ${fmt(run.totalNetPay)} from ${run.cashAccountName ?? "the cash account"}.`)) return
    setActionBusy("pay")
    try {
      await markPayrollRunPaid(id)
      toast({ title: "Run marked Paid; cash debited." })
      await reload()
    } catch (e: any) {
      toast({ title: "Could not mark paid", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActionBusy(null) }
  }

  const onCancel = async () => {
    const reason = prompt("Cancellation reason (optional):") ?? undefined
    if (reason === null) return
    setActionBusy("cancel")
    try {
      await cancelPayrollRun(id, reason || undefined)
      toast({ title: "Run cancelled." })
      await reload()
    } catch (e: any) {
      toast({ title: "Could not cancel", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActionBusy(null) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4">
            <Link href="/generic-payroll" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700">
              <ArrowLeft className="h-4 w-4 mr-1" /> Back to payroll
            </Link>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !run ? (
            <Card><CardContent className="py-8 text-center text-slate-500">Payroll run not found.</CardContent></Card>
          ) : (
            <>
              {/* Header card */}
              <Card className="mb-4">
                <CardHeader className="flex flex-row items-center justify-between flex-wrap gap-2">
                  <div>
                    <CardTitle className="flex items-center gap-2">
                      Payroll run #{run.genericPayrollRunId}
                      <Badge className={statusBadgeClass(run.status)}>{run.status}</Badge>
                    </CardTitle>
                    <p className="text-sm text-slate-500 mt-1">
                      Period {run.periodStart.slice(0, 10)} → {run.periodEnd.slice(0, 10)}
                      {run.payDate ? ` · Pay date ${run.payDate.slice(0, 10)}` : ""}
                      {run.cashAccountName ? ` · Pay from ${run.cashAccountName}` : ""}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    {isDraft && (
                      <Button onClick={onApprove} disabled={actionBusy !== null}>
                        {actionBusy === "approve" ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <CheckCircle2 className="h-4 w-4 mr-2" />}
                        Approve
                      </Button>
                    )}
                    {isApproved && (
                      <Button onClick={onMarkPaid} disabled={actionBusy !== null} className="bg-emerald-600 hover:bg-emerald-700">
                        {actionBusy === "pay" ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Wallet className="h-4 w-4 mr-2" />}
                        Mark paid
                      </Button>
                    )}
                    {!isCancelled && (
                      <Button variant="outline" onClick={onCancel} disabled={actionBusy !== null} className="text-rose-700 hover:bg-rose-50">
                        {actionBusy === "cancel" ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <XCircle className="h-4 w-4 mr-2" />}
                        Cancel
                      </Button>
                    )}
                  </div>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                    <div>
                      <div className="text-slate-500">Gross pay</div>
                      <div className="text-lg font-semibold">{fmt(run.totalGrossPay)}</div>
                    </div>
                    <div>
                      <div className="text-slate-500">Deductions</div>
                      <div className="text-lg font-semibold">{fmt(run.totalDeductions)}</div>
                    </div>
                    <div>
                      <div className="text-slate-500">Net pay</div>
                      <div className="text-lg font-semibold text-emerald-700">{fmt(run.totalNetPay)}</div>
                    </div>
                    <div>
                      <div className="text-slate-500">Staff lines</div>
                      <div className="text-lg font-semibold">{run.items.length}</div>
                    </div>
                  </div>
                  {run.notes && (
                    <div className="mt-4 text-sm">
                      <div className="text-slate-500 mb-1">Notes</div>
                      <div className="whitespace-pre-line">{run.notes}</div>
                    </div>
                  )}
                </CardContent>
              </Card>

              {/* Items */}
              <Card>
                <CardHeader className="flex flex-row items-center justify-between">
                  <CardTitle className="text-base">Staff lines</CardTitle>
                  {isDraft && (
                    <Dialog open={open} onOpenChange={setOpen}>
                      <DialogTrigger asChild>
                        <Button size="sm" onClick={openAddLine} disabled={eligibleStaffForNewLine.length === 0}>
                          <Plus className="h-4 w-4 mr-1" />Add line
                        </Button>
                      </DialogTrigger>
                      <DialogContent>
                        <DialogHeader>
                          <DialogTitle>{editingItemId == null ? "Add staff line" : "Edit staff line"}</DialogTitle>
                          <DialogDescription>Net pay = Basic + Daily wage + Commission + Bonus − Deductions.</DialogDescription>
                        </DialogHeader>
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                          <div className="md:col-span-2">
                            <Label>Staff *</Label>
                            <Select
                              value={form.genericStaffId}
                              onValueChange={(v) => setForm((f) => ({ ...f, genericStaffId: v }))}
                              disabled={editingItemId != null}
                            >
                              <SelectTrigger><SelectValue placeholder="Select staff" /></SelectTrigger>
                              <SelectContent>
                                {(editingItemId == null ? eligibleStaffForNewLine : staff).map((s) => (
                                  <SelectItem key={s.genericStaffId} value={String(s.genericStaffId)}>
                                    {s.firstName} {s.lastName} — {s.role}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                          <div><Label>Basic pay</Label>
                            <NumberInput step="0.01" min="0" value={form.basicPay} onChange={(e) => setForm((f) => ({ ...f, basicPay: e.target.value }))} /></div>
                          <div><Label>Daily wage</Label>
                            <NumberInput step="0.01" min="0" value={form.dailyWage} onChange={(e) => setForm((f) => ({ ...f, dailyWage: e.target.value }))} /></div>
                          <div><Label>Commission</Label>
                            <NumberInput step="0.01" min="0" value={form.commission} onChange={(e) => setForm((f) => ({ ...f, commission: e.target.value }))} /></div>
                          <div><Label>Bonus</Label>
                            <NumberInput step="0.01" min="0" value={form.bonus} onChange={(e) => setForm((f) => ({ ...f, bonus: e.target.value }))} /></div>
                          <div><Label>Deductions</Label>
                            <NumberInput step="0.01" min="0" value={form.deductions} onChange={(e) => setForm((f) => ({ ...f, deductions: e.target.value }))} /></div>
                          <div>
                            <Label>Payment method</Label>
                            <Select value={form.paymentMethod} onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                              <SelectTrigger><SelectValue /></SelectTrigger>
                              <SelectContent>{PAYMENT_METHODS.map((p) => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent>
                            </Select>
                          </div>
                          <div className="md:col-span-2">
                            <Label>Notes</Label>
                            <Input value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                          </div>
                        </div>
                        <DialogFooter>
                          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                          <Button onClick={onSaveLine} disabled={saving}>{saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Save</Button>
                        </DialogFooter>
                      </DialogContent>
                    </Dialog>
                  )}
                </CardHeader>
                <CardContent className="p-0">
                  {run.items.length === 0 ? (
                    <div className="py-8 text-center text-slate-500 text-sm">No staff lines yet. {isDraft && "Click \"Add line\" to start."}</div>
                  ) : (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Staff</TableHead>
                          <TableHead className="text-right">Basic</TableHead>
                          <TableHead className="text-right">Daily</TableHead>
                          <TableHead className="text-right">Commission</TableHead>
                          <TableHead className="text-right">Bonus</TableHead>
                          <TableHead className="text-right">Deductions</TableHead>
                          <TableHead className="text-right">Net</TableHead>
                          <TableHead>Method</TableHead>
                          {isDraft && <TableHead></TableHead>}
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {run.items.map((it) => (
                          <TableRow
                            key={it.genericPayrollItemId}
                            className={isDraft ? "cursor-pointer hover:bg-slate-50" : undefined}
                            onClick={isDraft ? () => openEditLine(it.genericPayrollItemId) : undefined}
                          >
                            <TableCell className="font-medium">
                              {it.staffName} <span className="text-slate-400 text-xs">({it.staffRole})</span>
                            </TableCell>
                            <TableCell className="text-right">{fmt(it.basicPay)}</TableCell>
                            <TableCell className="text-right">{fmt(it.dailyWage)}</TableCell>
                            <TableCell className="text-right">{fmt(it.commission)}</TableCell>
                            <TableCell className="text-right">{fmt(it.bonus)}</TableCell>
                            <TableCell className="text-right">{fmt(it.deductions)}</TableCell>
                            <TableCell className="text-right font-semibold text-emerald-700">{fmt(it.netPay)}</TableCell>
                            <TableCell>{it.paymentMethod ?? "—"}</TableCell>
                            {isDraft && (
                              <TableCell>
                                <Button
                                  size="icon" variant="ghost"
                                  className="text-rose-600 hover:bg-rose-50"
                                  onClick={(e) => { e.stopPropagation(); onDeleteLine(it.genericPayrollItemId) }}
                                  title="Remove line"
                                ><Trash2 className="h-4 w-4" /></Button>
                              </TableCell>
                            )}
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  )}
                </CardContent>
              </Card>

              {(isApproved || isPaid) && (
                <p className="text-xs text-slate-500 mt-3">
                  {isApproved
                    ? "Run is approved. Click \"Mark paid\" to debit the cash account."
                    : `Paid on ${run.paidAt ? new Date(run.paidAt).toLocaleString() : "—"} by ${run.paidBy ?? "—"}. A CashOut transaction was written for ${fmt(run.totalNetPay)}.`}
                </p>
              )}
            </>
          )}
        </main>
      </div>

      <ConfirmDeleteDialog
        open={deleteItemId !== null}
        onOpenChange={(o) => { if (!o) setDeleteItemId(null) }}
        title="Remove this payroll line?"
        description="This staff line will be removed from the run."
        confirmLabel="Remove"
        successTitle="Line removed."
        errorTitle="Could not remove line"
        onConfirm={async () => {
          if (deleteItemId === null) return
          await deletePayrollItem(deleteItemId)
          await reload()
        }}
      />
    </div>
  )
}

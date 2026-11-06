"use client"

// Generic Payroll — mirrors the poultry payroll page with stat cards,
// inline action buttons, staff lines dialog, and mark-paid workflow.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Loader2, Plus, Banknote, Eye, Users, Trash2, CheckCircle2, XCircle, HandCoins,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  getPayrollRuns, createPayrollRun, approvePayrollRun, markPayrollRunPaid, cancelPayrollRun,
  upsertPayrollItem, deletePayrollItem, getPayrollRun,
  getCashAccounts, getStaff,
  type GenericPayrollRun, type GenericCashAccount, type GenericStaff,
} from "@/lib/api/generic"

const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card", "Mixed"]

const STATUS_STYLE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-800",
  Approved: "bg-sky-100 text-sky-800",
  Paid: "bg-emerald-100 text-emerald-800",
  Cancelled: "bg-rose-100 text-rose-800",
}

function IconBtn({ label, onClick, children, className }: { label: string; onClick: () => void; children: React.ReactNode; className?: string }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button variant="ghost" size="sm" className={className} onClick={onClick}>{children}</Button>
      </TooltipTrigger>
      <TooltipContent side="top">{label}</TooltipContent>
    </Tooltip>
  )
}

function firstOfMonth() {
  const d = new Date()
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().slice(0, 10)
}

export default function GenericPayrollPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [runs, setRuns] = useState<GenericPayrollRun[]>([])
  const [accounts, setAccounts] = useState<GenericCashAccount[]>([])
  const [staffList, setStaffList] = useState<GenericStaff[]>([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState("all")

  // Create dialog
  const [createOpen, setCreateOpen] = useState(false)
  const [createForm, setCreateForm] = useState({ periodStart: firstOfMonth(), periodEnd: new Date().toISOString().slice(0, 10), payDate: new Date().toISOString().slice(0, 10), cashAccountId: "", notes: "" })
  const [creating, setCreating] = useState(false)

  // Items dialog
  const [itemsRun, setItemsRun] = useState<GenericPayrollRun | null>(null)
  const [itemForm, setItemForm] = useState({ staffId: "", paymentMethod: "Cash", basicPay: "0", dailyWage: "0", commission: "0", bonus: "0", deductions: "0", notes: "" })
  const [itemSaving, setItemSaving] = useState(false)

  // Mark paid
  const [paidRun, setPaidRun] = useState<GenericPayrollRun | null>(null)
  const [payDate, setPayDate] = useState(new Date().toISOString().slice(0, 10))

  // Delete
  const [deleteTarget, setDeleteTarget] = useState<GenericPayrollRun | null>(null)

  const visible = useMemo(() => statusFilter === "all" ? runs : runs.filter((r) => r.status === statusFilter), [runs, statusFilter])
  const pg = usePagination(visible)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [r, a, s] = await Promise.all([getPayrollRuns(null), getCashAccounts(), getStaff()])
      setRuns(r); setAccounts(a.filter((x) => x.isActive)); setStaffList(s.filter((x) => x.isActive))
      if (!createForm.cashAccountId && a.length > 0) {
        const first = a.find((x) => x.isActive)
        if (first) setCreateForm((f) => ({ ...f, cashAccountId: String(first.genericCashAccountId) }))
      }
    } catch (e: any) {
      toast({ title: "Could not load payroll", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  const stats = useMemo(() => ({
    total: runs.length,
    draft: runs.filter((r) => r.status === "Draft").length,
    approved: runs.filter((r) => r.status === "Approved").length,
    totalNet: runs.filter((r) => r.status === "Paid").reduce((s, r) => s + r.totalNetPay, 0),
  }), [runs])

  const isEditable = (r: GenericPayrollRun) => r.status === "Draft"

  const fmtPeriod = (r: GenericPayrollRun) => {
    const s = new Date(r.periodStart).toLocaleDateString(undefined, { day: "numeric", month: "short" })
    const e = new Date(r.periodEnd).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })
    return `${s} → ${e}`
  }

  // ---- Actions ----
  async function onCreate() {
    setCreating(true)
    try {
      const created = await createPayrollRun({
        periodStart: createForm.periodStart, periodEnd: createForm.periodEnd,
        payDate: createForm.payDate || null,
        genericCashAccountId: createForm.cashAccountId ? Number(createForm.cashAccountId) : null,
        notes: createForm.notes || null,
      })
      if (created) {
        toast({ title: `Run #${created.genericPayrollRunId} created` })
        setCreateOpen(false); await load()
        const full = await getPayrollRun(created.genericPayrollRunId)
        if (full) setItemsRun(full)
      }
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
    finally { setCreating(false) }
  }

  async function onApprove(id: number) {
    try { await approvePayrollRun(id); toast({ title: "Run approved" }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  async function onMarkPaid() {
    if (!paidRun) return
    try { await markPayrollRunPaid(paidRun.genericPayrollRunId, payDate); toast({ title: "Marked as paid" }); setPaidRun(null); await load() }
    catch (e: any) { toast({ title: "Mark paid failed", description: e?.message, variant: "destructive" }) }
  }

  async function onCancel(id: number) {
    try { await cancelPayrollRun(id); toast({ title: "Run cancelled" }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }

  async function onDelete() {
    if (!deleteTarget) return
    try { await cancelPayrollRun(deleteTarget.genericPayrollRunId); toast({ title: "Run deleted" }); setDeleteTarget(null); await load() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  async function openItems(r: GenericPayrollRun) {
    const full = await getPayrollRun(r.genericPayrollRunId)
    if (full) setItemsRun(full)
  }

  async function saveItem() {
    if (!itemsRun || !itemForm.staffId) return
    setItemSaving(true)
    try {
      await upsertPayrollItem(itemsRun.genericPayrollRunId, {
        genericStaffId: Number(itemForm.staffId),
        basicPay: Number(itemForm.basicPay) || 0, dailyWage: Number(itemForm.dailyWage) || 0,
        commission: Number(itemForm.commission) || 0, bonus: Number(itemForm.bonus) || 0,
        deductions: Number(itemForm.deductions) || 0,
        paymentMethod: itemForm.paymentMethod || null, notes: itemForm.notes || null,
      })
      toast({ title: "Staff line saved" })
      setItemForm({ staffId: "", paymentMethod: "Cash", basicPay: "0", dailyWage: "0", commission: "0", bonus: "0", deductions: "0", notes: "" })
      const fresh = await getPayrollRun(itemsRun.genericPayrollRunId)
      if (fresh) setItemsRun(fresh)
      await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setItemSaving(false) }
  }

  async function removeItem(itemId: number) {
    if (!itemsRun) return
    try {
      await deletePayrollItem(itemId); toast({ title: "Line removed" })
      const fresh = await getPayrollRun(itemsRun.genericPayrollRunId)
      if (fresh) setItemsRun(fresh)
      await load()
    } catch (e: any) { toast({ title: "Remove failed", description: e?.message, variant: "destructive" }) }
  }

  function renderActions(r: GenericPayrollRun) {
    return (
      <>
        <IconBtn label="Details" onClick={() => router.push(`/generic-payroll/${r.genericPayrollRunId}`)}><Eye className="w-4 h-4" /></IconBtn>
        <IconBtn label={isEditable(r) ? "Edit lines" : "View lines"} onClick={() => openItems(r)}><Users className="w-4 h-4" /></IconBtn>
        {isEditable(r) && <IconBtn label="Approve" onClick={() => onApprove(r.genericPayrollRunId)} className="text-blue-700"><CheckCircle2 className="w-4 h-4" /></IconBtn>}
        {r.status === "Approved" && <IconBtn label="Mark paid" onClick={() => { setPaidRun(r); setPayDate(new Date().toISOString().slice(0, 10)) }} className="text-emerald-700"><Banknote className="w-4 h-4" /></IconBtn>}
        {(r.status === "Draft" || r.status === "Approved") && <IconBtn label="Cancel" onClick={() => onCancel(r.genericPayrollRunId)} className="text-rose-600"><XCircle className="w-4 h-4" /></IconBtn>}
        {r.status === "Draft" && <IconBtn label="Delete" onClick={() => setDeleteTarget(r)} className="text-red-600"><Trash2 className="w-4 h-4" /></IconBtn>}
      </>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2"><Banknote className="h-6 w-6 text-emerald-600" /> Payroll</h1>
              <p className="text-sm text-slate-500">{runs.length} run(s)</p>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" asChild><Link href="/generic-employee-loans"><HandCoins className="w-4 h-4 mr-1" /> Employee Loans</Link></Button>
              <Button onClick={() => setCreateOpen(true)}><Plus className="w-4 h-4 mr-1" /> New run</Button>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : (
            <>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                <div className="rounded-xl border bg-white p-3 shadow-sm"><div className="text-[11px] font-medium uppercase text-slate-500">Total runs</div><div className="mt-1 text-xl font-bold">{stats.total}</div></div>
                <div className="rounded-xl border bg-white p-3 shadow-sm"><div className="text-[11px] font-medium uppercase text-slate-500">Draft</div><div className="mt-1 text-xl font-bold text-slate-600">{stats.draft}</div></div>
                <div className="rounded-xl border bg-white p-3 shadow-sm"><div className="text-[11px] font-medium uppercase text-slate-500">Approved</div><div className="mt-1 text-xl font-bold text-sky-700">{stats.approved}</div></div>
                <div className="rounded-xl border bg-white p-3 shadow-sm"><div className="text-[11px] font-medium uppercase text-slate-500">Total net paid</div><div className="mt-1 text-xl font-bold text-emerald-700 tabular-nums">{gh(stats.totalNet)}</div></div>
              </div>

              <div className="flex gap-1 flex-wrap">
                {["all", "Draft", "Approved", "Paid", "Cancelled"].map((s) => (
                  <Button key={s} size="sm" variant={s === statusFilter ? "default" : "outline"} onClick={() => setStatusFilter(s)}>{s === "all" ? "All" : s}</Button>
                ))}
              </div>

              <Card><CardContent className="p-0">
                {visible.length === 0 ? (
                  <div className="py-8 text-center text-slate-500">No payroll runs{statusFilter !== "all" ? ` with status "${statusFilter}"` : ""}.</div>
                ) : (
                  <>
                    <div className="hidden md:block overflow-x-auto">
                      <Table>
                        <TableHeader><TableRow>
                          <TableHead>Period</TableHead>
                          <TableHead className="text-right">Gross</TableHead>
                          <TableHead className="text-right">Deductions</TableHead>
                          <TableHead className="text-right">Net</TableHead>
                          <TableHead>Cash account</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow></TableHeader>
                        <TableBody>
                          {pg.pageItems.map((r) => (
                            <TableRow key={r.genericPayrollRunId}>
                              <TableCell className="whitespace-nowrap text-sm font-medium">{fmtPeriod(r)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.totalGrossPay)}</TableCell>
                              <TableCell className="text-right tabular-nums text-rose-600">{gh(r.totalDeductions)}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">{gh(r.totalNetPay)}</TableCell>
                              <TableCell className="text-sm text-slate-600">{r.cashAccountName ?? "—"}</TableCell>
                              <TableCell><Badge className={STATUS_STYLE[r.status] ?? STATUS_STYLE.Draft}>{r.status}</Badge></TableCell>
                              <TableCell className="text-right whitespace-nowrap">{renderActions(r)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                    <div className="md:hidden space-y-2 p-3">
                      {pg.pageItems.map((r) => (
                        <div key={r.genericPayrollRunId} className="rounded-lg border p-3">
                          <div className="flex justify-between items-center">
                            <span className="font-medium text-sm">{fmtPeriod(r)}</span>
                            <Badge className={STATUS_STYLE[r.status] ?? STATUS_STYLE.Draft}>{r.status}</Badge>
                          </div>
                          <div className="mt-2 grid grid-cols-2 gap-1 text-sm">
                            <div><span className="text-slate-500">Gross: </span><span className="tabular-nums">{gh(r.totalGrossPay)}</span></div>
                            <div><span className="text-slate-500">Deductions: </span><span className="tabular-nums text-rose-600">{gh(r.totalDeductions)}</span></div>
                            <div><span className="text-slate-500">Net: </span><span className="tabular-nums font-semibold">{gh(r.totalNetPay)}</span></div>
                            <div><span className="text-slate-500">Account: </span>{r.cashAccountName ?? "—"}</div>
                          </div>
                          <div className="mt-2 flex gap-1 border-t pt-2 justify-end">{renderActions(r)}</div>
                        </div>
                      ))}
                    </div>
                  </>
                )}
              </CardContent></Card>
              <DataPagination {...pg.paginationProps} />
            </>
          )}
        </main>
      </div>

      {/* Create run */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle><Banknote className="w-5 h-5 inline mr-2" />New payroll run</DialogTitle></DialogHeader>
          <FormSection title="Period" color="indigo">
            <FormField label="Period start"><Input type="date" value={createForm.periodStart} onChange={(e) => setCreateForm((f) => ({ ...f, periodStart: e.target.value }))} /></FormField>
            <FormField label="Period end"><Input type="date" value={createForm.periodEnd} onChange={(e) => setCreateForm((f) => ({ ...f, periodEnd: e.target.value }))} /></FormField>
            <FormField label="Pay date"><Input type="date" value={createForm.payDate} onChange={(e) => setCreateForm((f) => ({ ...f, payDate: e.target.value }))} /></FormField>
            <FormField label="Cash account">
              <Select value={createForm.cashAccountId} onValueChange={(v) => setCreateForm((f) => ({ ...f, cashAccountId: v }))}>
                <SelectTrigger><SelectValue placeholder="Select account" /></SelectTrigger>
                <SelectContent>{accounts.map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate">
            <FormField label="Notes"><Input value={createForm.notes} onChange={(e) => setCreateForm((f) => ({ ...f, notes: e.target.value }))} /></FormField>
          </FormSection>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
            <Button onClick={onCreate} disabled={creating}>{creating && <Loader2 className="w-4 h-4 animate-spin mr-1" />}Create</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Staff lines */}
      <Dialog open={!!itemsRun} onOpenChange={(o) => !o && setItemsRun(null)}>
        <DialogContent className="max-w-5xl max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle><Users className="w-5 h-5 inline mr-2" />Staff lines — {itemsRun ? fmtPeriod(itemsRun) : ""}</DialogTitle></DialogHeader>
          {itemsRun && itemsRun.items.length > 0 && (
            <div className="overflow-x-auto">
              <Table className="text-xs">
                <TableHeader><TableRow>
                  <TableHead className="whitespace-nowrap">Staff</TableHead>
                  <TableHead className="text-right whitespace-nowrap">Basic</TableHead>
                  <TableHead className="text-right whitespace-nowrap">Daily</TableHead>
                  <TableHead className="text-right whitespace-nowrap">Comm.</TableHead>
                  <TableHead className="text-right whitespace-nowrap">Bonus</TableHead>
                  <TableHead className="text-right whitespace-nowrap">Deduct</TableHead>
                  <TableHead className="text-right whitespace-nowrap">Net</TableHead>
                  <TableHead className="w-8"></TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {itemsRun.items.map((it) => (
                    <TableRow key={it.genericPayrollItemId}>
                      <TableCell className="font-medium whitespace-nowrap">{it.staffName ?? `Staff #${it.genericStaffId}`}</TableCell>
                      <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(it.basicPay)}</TableCell>
                      <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(it.dailyWage)}</TableCell>
                      <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(it.commission)}</TableCell>
                      <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(it.bonus)}</TableCell>
                      <TableCell className="text-right tabular-nums whitespace-nowrap text-rose-600">{gh(it.deductions)}</TableCell>
                      <TableCell className="text-right tabular-nums whitespace-nowrap font-semibold">{gh(it.netPay)}</TableCell>
                      <TableCell>{isEditable(itemsRun) && <Button variant="ghost" size="sm" onClick={() => removeItem(it.genericPayrollItemId)}><Trash2 className="w-3 h-3 text-red-500" /></Button>}</TableCell>
                    </TableRow>
                  ))}
                  <TableRow className="bg-slate-50 font-semibold">
                    <TableCell className="whitespace-nowrap">Total ({itemsRun.items.length})</TableCell>
                    <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(itemsRun.items.reduce((s, i) => s + i.basicPay, 0))}</TableCell>
                    <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(itemsRun.items.reduce((s, i) => s + i.dailyWage, 0))}</TableCell>
                    <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(itemsRun.items.reduce((s, i) => s + i.commission, 0))}</TableCell>
                    <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(itemsRun.items.reduce((s, i) => s + i.bonus, 0))}</TableCell>
                    <TableCell className="text-right tabular-nums whitespace-nowrap text-rose-600">{gh(itemsRun.totalDeductions)}</TableCell>
                    <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(itemsRun.totalNetPay)}</TableCell>
                    <TableCell></TableCell>
                  </TableRow>
                </TableBody>
              </Table>
            </div>
          )}
          {itemsRun && itemsRun.items.length === 0 && <div className="text-center text-slate-500 py-4">No staff lines yet. Add one below.</div>}
          {itemsRun && isEditable(itemsRun) && (
            <FormSection title="Add / update a line" color="amber">
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                <FormField label="Staff *">
                  <Select value={itemForm.staffId} onValueChange={(v) => setItemForm((f) => ({ ...f, staffId: v }))}>
                    <SelectTrigger><SelectValue placeholder="Select staff" /></SelectTrigger>
                    <SelectContent>{staffList.map((s) => <SelectItem key={s.genericStaffId} value={String(s.genericStaffId)}>{s.firstName} {s.lastName}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Method">
                  <Select value={itemForm.paymentMethod} onValueChange={(v) => setItemForm((f) => ({ ...f, paymentMethod: v }))}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{PAY_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                  </Select>
                </FormField>
                <FormField label="Basic pay"><NumberInput step="0.01" min="0" value={itemForm.basicPay} onChange={(e) => setItemForm((f) => ({ ...f, basicPay: e.target.value }))} /></FormField>
                <FormField label="Daily wage"><NumberInput step="0.01" min="0" value={itemForm.dailyWage} onChange={(e) => setItemForm((f) => ({ ...f, dailyWage: e.target.value }))} /></FormField>
                <FormField label="Commission"><NumberInput step="0.01" min="0" value={itemForm.commission} onChange={(e) => setItemForm((f) => ({ ...f, commission: e.target.value }))} /></FormField>
                <FormField label="Bonus"><NumberInput step="0.01" min="0" value={itemForm.bonus} onChange={(e) => setItemForm((f) => ({ ...f, bonus: e.target.value }))} /></FormField>
                <FormField label="Deductions"><NumberInput step="0.01" min="0" value={itemForm.deductions} onChange={(e) => setItemForm((f) => ({ ...f, deductions: e.target.value }))} /></FormField>
                <FormField label="Notes"><Input value={itemForm.notes} onChange={(e) => setItemForm((f) => ({ ...f, notes: e.target.value }))} /></FormField>
              </div>
              <div className="flex justify-end mt-2">
                <Button onClick={saveItem} disabled={itemSaving || !itemForm.staffId}>{itemSaving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : <Plus className="w-4 h-4 mr-1" />}Add line</Button>
              </div>
            </FormSection>
          )}
        </DialogContent>
      </Dialog>

      {/* Mark paid */}
      <Dialog open={!!paidRun} onOpenChange={(o) => !o && setPaidRun(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Mark as paid</DialogTitle></DialogHeader>
          {paidRun && (
            <div className="space-y-3">
              <p className="text-sm text-slate-600">Confirm that <strong>{gh(paidRun.totalNetPay)}</strong> has been paid out{paidRun.cashAccountName ? ` from ${paidRun.cashAccountName}` : ""}.</p>
              <div><Label className="text-xs text-slate-500">Pay date</Label><Input type="date" value={payDate} onChange={(e) => setPayDate(e.target.value)} /></div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setPaidRun(null)}>Cancel</Button>
            <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={onMarkPaid}>Confirm paid</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete */}
      <ConfirmDeleteDialog open={!!deleteTarget} onOpenChange={(o) => !o && setDeleteTarget(null)}
        title="Delete payroll run" description={`Delete run for ${deleteTarget ? fmtPeriod(deleteTarget) : ""}? This cannot be undone.`} onConfirm={onDelete} />
    </div>
  )
}

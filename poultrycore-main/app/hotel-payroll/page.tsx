"use client"
import { useEffect, useState, useCallback } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { NumberInput } from "@/components/ui/number-input"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Loader2, Banknote, Plus, Eye, Check, X, Trash2, Wallet, Users, Building2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelPayrollRuns,
  getHotelPayrollRun,
  createHotelPayrollRun,
  upsertHotelPayrollItem,
  deleteHotelPayrollItem,
  approveHotelPayrollRun,
  markHotelPayrollRunPaid,
  cancelHotelPayrollRun,
  deleteHotelPayrollRun,
  listHotelCashAccounts,
  listHotelStaff,
  type HotelPayrollRun,
  type HotelPayrollItem,
  type HotelPayrollRunDetail,
  type HotelCashAccount,
  type HotelStaff,
} from "@/lib/api/hotel"

const STATUS_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-blue-100 text-blue-700",
  Paid: "bg-green-100 text-green-700",
  Cancelled: "bg-red-100 text-red-700",
}

const PAYMENT_METHODS = ["Cash", "MoMo", "Bank"]

function currency(v: number | null | undefined): string {
  return `GH\u20B5 ${(v ?? 0).toFixed(2)}`
}

export default function HotelPayrollPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [runs, setRuns] = useState<HotelPayrollRun[]>([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState("all")

  // New run dialog
  const [newOpen, setNewOpen] = useState(false)
  const [newSaving, setNewSaving] = useState(false)
  const [newForm, setNewForm] = useState({ periodStart: "", periodEnd: "", payDate: "", hotelCashAccountId: 0, notes: "" })
  const [cashAccounts, setCashAccounts] = useState<HotelCashAccount[]>([])

  // Detail dialog
  const [detailOpen, setDetailOpen] = useState(false)
  const [detail, setDetail] = useState<HotelPayrollRunDetail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [staffList, setStaffList] = useState<HotelStaff[]>([])

  // Add item form
  const [itemForm, setItemForm] = useState({
    hotelStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash",
  })
  const [itemSaving, setItemSaving] = useState(false)
  const [bulkAdding, setBulkAdding] = useState(false)

  // Cancel dialog
  const [cancelTarget, setCancelTarget] = useState<HotelPayrollRun | null>(null)

  // Delete dialog
  const [deleteTarget, setDeleteTarget] = useState<HotelPayrollRun | null>(null)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      setRuns(await listHotelPayrollRuns())
    } catch (e: any) {
      toast({ title: "Failed to load payroll runs", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [toast])

  // ----- New Run -----
  async function openNewDialog() {
    setNewForm({ periodStart: "", periodEnd: "", payDate: "", hotelCashAccountId: 0, notes: "" })
    try { setCashAccounts(await listHotelCashAccounts()) } catch { setCashAccounts([]) }
    setNewOpen(true)
  }

  async function handleCreateRun() {
    if (!newForm.periodStart || !newForm.periodEnd) {
      toast({ title: "Period start and end are required", variant: "destructive" }); return
    }
    setNewSaving(true)
    try {
      const input: any = { periodStart: newForm.periodStart, periodEnd: newForm.periodEnd }
      if (newForm.payDate) input.payDate = newForm.payDate
      if (newForm.hotelCashAccountId) input.hotelCashAccountId = newForm.hotelCashAccountId
      if (newForm.notes.trim()) input.notes = newForm.notes.trim()
      await createHotelPayrollRun(input)
      toast({ title: "Payroll run created" })
      setNewOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Create failed", description: e?.message, variant: "destructive" })
    } finally {
      setNewSaving(false)
    }
  }

  // ----- Detail -----
  async function openDetail(run: HotelPayrollRun) {
    setDetailOpen(true)
    setDetailLoading(true)
    setDetail(null)
    try {
      const [d, staff] = await Promise.all([
        getHotelPayrollRun(run.hotelpayrollrunid),
        listHotelStaff(),
      ])
      setDetail(d)
      setStaffList(staff.filter((s: any) => s.isactive !== false && s.isActive !== false))
      setItemForm({ hotelStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash" })
    } catch (e: any) {
      toast({ title: "Failed to load run details", description: e?.message, variant: "destructive" })
      setDetailOpen(false)
    } finally {
      setDetailLoading(false)
    }
  }

  async function handleSaveItem() {
    if (!detail) return
    if (!itemForm.hotelStaffId) {
      toast({ title: "Select a staff member", variant: "destructive" }); return
    }
    const staff: any = staffList.find((s: any) => (s.hotelStaffId ?? s.hotelstaffid) === itemForm.hotelStaffId)
    setItemSaving(true)
    try {
      await upsertHotelPayrollItem(detail.run.hotelpayrollrunid, {
        hotelStaffId: itemForm.hotelStaffId,
        staffName: staff ? `${staff.firstName ?? staff.firstname} ${staff.lastName ?? staff.lastname}` : undefined,
        staffRole: staff?.role ?? staff?.department,
        basicPay: itemForm.basicPay,
        dailyWage: itemForm.dailyWage,
        commission: itemForm.commission,
        bonus: itemForm.bonus,
        deductions: itemForm.deductions,
        paymentMethod: itemForm.paymentMethod,
      })
      toast({ title: "Line item saved" })
      const d = await getHotelPayrollRun(detail.run.hotelpayrollrunid)
      setDetail(d)
      setItemForm({ hotelStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash" })
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally {
      setItemSaving(false)
    }
  }

  async function handleDeleteItem(item: HotelPayrollItem) {
    if (!detail) return
    try {
      await deleteHotelPayrollItem(item.hotelpayrollitemid)
      toast({ title: "Item removed" })
      const d = await getHotelPayrollRun(detail.run.hotelpayrollrunid)
      setDetail(d)
    } catch (e: any) {
      toast({ title: "Delete failed", description: e?.message, variant: "destructive" })
    }
  }

  async function handleBulkAddStaff(staffToAdd: any[]) {
    if (!detail || staffToAdd.length === 0) return
    setBulkAdding(true)
    let added = 0
    try {
      for (const s of staffToAdd) {
        const sid = (s as any).hotelStaffId ?? (s as any).hotelstaffid
        const name = `${(s as any).firstName ?? (s as any).firstname} ${(s as any).lastName ?? (s as any).lastname}`
        const role = (s as any).role ?? (s as any).department
        const salary = (s as any).salaryAmount ?? (s as any).salaryamount ?? 0
        await upsertHotelPayrollItem(detail.run.hotelpayrollrunid, {
          hotelStaffId: sid, staffName: name, staffRole: role,
          basicPay: salary, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash",
        })
        added++
      }
      toast({ title: `${added} staff member(s) added with their base salary` })
      const d = await getHotelPayrollRun(detail.run.hotelpayrollrunid)
      setDetail(d)
    } catch (e: any) {
      toast({ title: `Added ${added}, then failed`, description: e?.message, variant: "destructive" })
      const d = await getHotelPayrollRun(detail.run.hotelpayrollrunid)
      setDetail(d)
    } finally { setBulkAdding(false) }
  }

  async function handleAddAllStaff() {
    if (!detail) return
    const remaining = staffList.filter((s: any) => !detail.items.some((it: any) => it.hotelstaffid === (s.hotelStaffId ?? s.hotelstaffid)))
    if (remaining.length === 0) { toast({ title: "All staff already added" }); return }
    await handleBulkAddStaff(remaining)
  }

  async function handleAddDepartment(dept: string) {
    if (!detail) return
    const remaining = staffList.filter((s: any) => {
      const sDept = ((s as any).department ?? (s as any).Department ?? "").toLowerCase()
      return sDept === dept.toLowerCase() && !detail.items.some((it: any) => it.hotelstaffid === ((s as any).hotelStaffId ?? (s as any).hotelstaffid))
    })
    if (remaining.length === 0) { toast({ title: `All ${dept} staff already added` }); return }
    await handleBulkAddStaff(remaining)
  }

  // ----- Actions -----
  async function handleApprove(run: HotelPayrollRun) {
    try {
      await approveHotelPayrollRun(run.hotelpayrollrunid)
      toast({ title: "Payroll run approved" })
      await load()
      if (detail && detail.run.hotelpayrollrunid === run.hotelpayrollrunid) {
        const d = await getHotelPayrollRun(run.hotelpayrollrunid)
        setDetail(d)
      }
    } catch (e: any) {
      toast({ title: "Approve failed", description: e?.message, variant: "destructive" })
    }
  }

  async function handleMarkPaid(run: HotelPayrollRun) {
    try {
      await markHotelPayrollRunPaid(run.hotelpayrollrunid)
      toast({ title: "Payroll run marked as paid" })
      await load()
      if (detail && detail.run.hotelpayrollrunid === run.hotelpayrollrunid) {
        const d = await getHotelPayrollRun(run.hotelpayrollrunid)
        setDetail(d)
      }
    } catch (e: any) {
      toast({ title: "Mark paid failed", description: e?.message, variant: "destructive" })
    }
  }

  // ----- Computed -----
  const filtered = runs.filter((r) => statusFilter === "all" || r.status === statusFilter)
  const draftCount = runs.filter((r) => r.status === "Draft").length
  const approvedCount = runs.filter((r) => r.status === "Approved").length
  const totalNetPaid = runs.filter((r) => r.status === "Paid").reduce((s, r) => s + (r.totalnetpay ?? 0), 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Header */}
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-3">
              <Banknote className="h-6 w-6 text-violet-600" />
              <h1 className="text-2xl font-bold">Payroll</h1>
            </div>
            <Button onClick={openNewDialog} className="bg-violet-600 hover:bg-violet-700">
              <Plus className="h-4 w-4 mr-1" /> New payroll run
            </Button>
          </div>

          {/* Summary cards */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
            <Card>
              <CardContent className="p-4">
                <p className="text-xs text-slate-500 mb-1">Total Runs</p>
                <p className="text-2xl font-bold">{runs.length}</p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <p className="text-xs text-slate-500 mb-1">Draft</p>
                <p className="text-2xl font-bold text-slate-700">{draftCount}</p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <p className="text-xs text-slate-500 mb-1">Approved</p>
                <p className="text-2xl font-bold text-blue-700">{approvedCount}</p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <p className="text-xs text-slate-500 mb-1">Total Net Paid</p>
                <p className="text-2xl font-bold text-green-700">{currency(totalNetPaid)}</p>
              </CardContent>
            </Card>
          </div>

          {/* Status filter */}
          <div className="mb-4 w-48">
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger><SelectValue placeholder="Filter by status" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All</SelectItem>
                <SelectItem value="Draft">Draft</SelectItem>
                <SelectItem value="Approved">Approved</SelectItem>
                <SelectItem value="Paid">Paid</SelectItem>
                <SelectItem value="Cancelled">Cancelled</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Table */}
          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <Card>
              <CardContent className="p-0">
                <table className="w-full text-sm">
                  <thead className="bg-slate-50 border-b">
                    <tr>
                      <th className="text-left p-3">Period</th>
                      <th className="text-right p-3">Gross</th>
                      <th className="text-right p-3">Deductions</th>
                      <th className="text-right p-3">Net</th>
                      <th className="text-left p-3">Cash Account</th>
                      <th className="text-left p-3">Status</th>
                      <th className="text-right p-3">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.map((r, idx) => (
                      <tr key={r.hotelpayrollrunid ?? `run-${idx}`} className="border-b hover:bg-slate-50">
                        <td className="p-3 font-medium">
                          {r.periodstart?.slice(0, 10)} — {r.periodend?.slice(0, 10)}
                        </td>
                        <td className="p-3 text-right">{currency(r.totalgrosspay)}</td>
                        <td className="p-3 text-right">{currency(r.totaldeductions)}</td>
                        <td className="p-3 text-right font-semibold">{currency(r.totalnetpay)}</td>
                        <td className="p-3">{r.cashaccountname ?? "-"}</td>
                        <td className="p-3">
                          <Badge variant="outline" className={STATUS_BADGE[r.status] ?? "bg-slate-100 text-slate-700"}>
                            {r.status}
                          </Badge>
                        </td>
                        <td className="p-3 text-right">
                          <div className="flex items-center justify-end gap-1">
                            <Button variant="ghost" size="icon" title="Details" onClick={() => openDetail(r)}>
                              <Eye className="h-4 w-4" />
                            </Button>
                            {r.status === "Draft" && (
                              <>
                                <Button variant="ghost" size="icon" title="Approve" onClick={() => handleApprove(r)}>
                                  <Check className="h-4 w-4 text-blue-600" />
                                </Button>
                                <Button variant="ghost" size="icon" title="Cancel" onClick={() => setCancelTarget(r)}>
                                  <X className="h-4 w-4 text-orange-600" />
                                </Button>
                                <Button variant="ghost" size="icon" title="Delete" onClick={() => setDeleteTarget(r)}>
                                  <Trash2 className="h-4 w-4 text-red-600" />
                                </Button>
                              </>
                            )}
                            {r.status === "Approved" && (
                              <>
                                <Button variant="ghost" size="icon" title="Mark Paid" onClick={() => handleMarkPaid(r)}>
                                  <Wallet className="h-4 w-4 text-green-600" />
                                </Button>
                                <Button variant="ghost" size="icon" title="Cancel" onClick={() => setCancelTarget(r)}>
                                  <X className="h-4 w-4 text-orange-600" />
                                </Button>
                              </>
                            )}
                            {r.status === "Cancelled" && (
                              <Button variant="ghost" size="icon" title="Delete" onClick={() => setDeleteTarget(r)}>
                                <Trash2 className="h-4 w-4 text-red-600" />
                              </Button>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                    {filtered.length === 0 && (
                      <tr>
                        <td colSpan={7} className="p-8 text-center text-slate-400">
                          No payroll runs found. Create one to get started.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </CardContent>
            </Card>
          )}

          {/* ========== NEW RUN DIALOG ========== */}
          <Dialog open={newOpen} onOpenChange={setNewOpen}>
            <DialogContent className="max-w-lg">
              <DialogHeader>
                <DialogTitle>New Payroll Run</DialogTitle>
                <DialogDescription>Create a new payroll period. You can add staff line items after creation.</DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <FormSection title="Period" color="indigo">
                  <FormField label="Period Start *">
                    <Input type="date" value={newForm.periodStart} onChange={(e) => setNewForm({ ...newForm, periodStart: e.target.value })} />
                  </FormField>
                  <FormField label="Period End *">
                    <Input type="date" value={newForm.periodEnd} onChange={(e) => setNewForm({ ...newForm, periodEnd: e.target.value })} />
                  </FormField>
                </FormSection>
                <FormSection title="Payment" color="amber" columns={1}>
                  <FormField label="Cash Account">
                    <Select
                      value={newForm.hotelCashAccountId ? String(newForm.hotelCashAccountId) : "none"}
                      onValueChange={(v) => setNewForm({ ...newForm, hotelCashAccountId: v === "none" ? 0 : Number(v) })}
                    >
                      <SelectTrigger><SelectValue placeholder="Select cash account" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">-- None --</SelectItem>
                        {cashAccounts.map((ca: any, idx: number) => (
                          <SelectItem key={ca.hotelCashAccountId ?? ca.hotelcashaccountid ?? `ca-${idx}`} value={String(ca.hotelCashAccountId ?? ca.hotelcashaccountid)}>
                            {ca.accountName ?? ca.accountname} ({ca.accountType ?? ca.accounttype})
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </FormField>
                </FormSection>
                <FormSection title="Notes" color="slate" columns={1}>
                  <FormField label="Notes">
                    <Input value={newForm.notes} onChange={(e) => setNewForm({ ...newForm, notes: e.target.value })} placeholder="Optional notes" />
                  </FormField>
                </FormSection>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setNewOpen(false)}>Cancel</Button>
                <Button onClick={handleCreateRun} disabled={newSaving} className="bg-violet-600 hover:bg-violet-700">
                  {newSaving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Create
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* ========== DETAIL DIALOG ========== */}
          <Dialog open={detailOpen} onOpenChange={(v) => { setDetailOpen(v); if (!v) load() }}>
            <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
              <DialogHeader>
                <DialogTitle>
                  Payroll Run: {detail?.run.periodstart?.slice(0, 10)} — {detail?.run.periodend?.slice(0, 10)}
                </DialogTitle>
                <DialogDescription>
                  Status: {detail?.run.status ?? "..."}
                </DialogDescription>
              </DialogHeader>

              {detailLoading ? (
                <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
              ) : detail ? (
                <div className="space-y-6">
                  {/* Summary cards */}
                  <div className="grid grid-cols-3 gap-4">
                    <Card>
                      <CardContent className="p-4">
                        <p className="text-xs text-slate-500 mb-1">Gross Pay</p>
                        <p className="text-xl font-bold">{currency(detail.run.totalgrosspay)}</p>
                      </CardContent>
                    </Card>
                    <Card>
                      <CardContent className="p-4">
                        <p className="text-xs text-slate-500 mb-1">Deductions</p>
                        <p className="text-xl font-bold text-red-600">{currency(detail.run.totaldeductions)}</p>
                      </CardContent>
                    </Card>
                    <Card>
                      <CardContent className="p-4">
                        <p className="text-xs text-slate-500 mb-1">Net Pay</p>
                        <p className="text-xl font-bold text-green-700">{currency(detail.run.totalnetpay)}</p>
                      </CardContent>
                    </Card>
                  </div>

                  {/* Items table */}
                  <Card>
                    <CardContent className="p-0">
                      <table className="w-full text-sm">
                        <thead className="bg-slate-50 border-b">
                          <tr>
                            <th className="text-left p-3">Staff</th>
                            <th className="text-right p-3">Basic</th>
                            <th className="text-right p-3">Daily</th>
                            <th className="text-right p-3">Commission</th>
                            <th className="text-right p-3">Bonus</th>
                            <th className="text-right p-3">Deductions</th>
                            <th className="text-right p-3">Net</th>
                            {detail.run.status === "Draft" && <th className="text-right p-3">Actions</th>}
                          </tr>
                        </thead>
                        <tbody>
                          {detail.items.map((item, idx) => (
                            <tr key={item.hotelpayrollitemid ?? `item-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">
                                {item.staffname ?? `Staff #${item.hotelstaffid}`}
                                {item.staffrole && <span className="text-xs text-slate-500 ml-1">({item.staffrole})</span>}
                              </td>
                              <td className="p-3 text-right">{currency(item.basicpay)}</td>
                              <td className="p-3 text-right">{currency(item.dailywage)}</td>
                              <td className="p-3 text-right">{currency(item.commission)}</td>
                              <td className="p-3 text-right">{currency(item.bonus)}</td>
                              <td className="p-3 text-right">{currency(item.deductions)}</td>
                              <td className="p-3 text-right font-semibold">{currency(item.netpay)}</td>
                              {detail.run.status === "Draft" && (
                                <td className="p-3 text-right">
                                  <Button variant="ghost" size="icon" className="text-red-600" onClick={() => handleDeleteItem(item)}>
                                    <Trash2 className="h-4 w-4" />
                                  </Button>
                                </td>
                              )}
                            </tr>
                          ))}
                          {detail.items.length === 0 && (
                            <tr>
                              <td colSpan={detail.run.status === "Draft" ? 8 : 7} className="p-8 text-center text-slate-400">
                                No line items yet. Add staff below.
                              </td>
                            </tr>
                          )}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>

                  {/* Add item form (Draft only) */}
                  {detail.run.status === "Draft" && (
                    <>
                    {/* Quick actions — Add All / Add by Department */}
                    {(() => {
                      const remaining = staffList.filter((s: any) => !detail?.items?.some((it: any) => it.hotelstaffid === ((s as any).hotelStaffId ?? (s as any).hotelstaffid)))
                      if (remaining.length === 0 && detail.items.length > 0) return (
                        <div className="flex items-center gap-2 p-3 bg-emerald-50 rounded-lg border border-emerald-200">
                          <Check className="h-4 w-4 text-emerald-600" />
                          <span className="text-sm text-emerald-700">All {detail.items.length} active staff members have been added to this run.</span>
                        </div>
                      )
                      // Group remaining by department
                      const deptMap = new Map<string, number>()
                      remaining.forEach((s: any) => {
                        const dept = (s as any).department ?? (s as any).Department ?? "Other"
                        deptMap.set(dept, (deptMap.get(dept) ?? 0) + 1)
                      })
                      const departments = Array.from(deptMap.entries()).sort((a, b) => a[0].localeCompare(b[0]))

                      return remaining.length > 0 ? (
                        <div className="space-y-3">
                          {/* Add All */}
                          <div className="flex items-center gap-3 p-3 bg-violet-50 rounded-lg border border-violet-200">
                            <div className="flex-1 text-sm text-violet-700">
                              <strong>{remaining.length}</strong> staff member(s) not yet added to this run
                            </div>
                            <Button onClick={handleAddAllStaff} disabled={bulkAdding} variant="outline" className="border-violet-300 text-violet-700 hover:bg-violet-100">
                              {bulkAdding ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Adding...</> : <><Users className="h-4 w-4 mr-1" /> Add All Staff</>}
                            </Button>
                          </div>
                          {/* Add by Department */}
                          {departments.length > 1 && (
                            <div className="p-3 bg-slate-50 rounded-lg border border-slate-200">
                              <div className="text-xs font-semibold text-slate-500 mb-2 flex items-center gap-1"><Building2 className="h-3 w-3" /> Add by Department</div>
                              <div className="flex flex-wrap gap-2">
                                {departments.map(([dept, count]) => (
                                  <Button key={dept} size="sm" variant="outline" disabled={bulkAdding} onClick={() => handleAddDepartment(dept)} className="text-xs">
                                    {dept} ({count})
                                  </Button>
                                ))}
                              </div>
                            </div>
                          )}
                        </div>
                      ) : null
                    })()}
                    {/* Only show individual add form if there are staff left to add */}
                    {staffList.filter((s: any) => !detail?.items?.some((it: any) => it.hotelstaffid === ((s as any).hotelStaffId ?? (s as any).hotelstaffid))).length > 0 && (
                    <FormSection title="Add individual staff" color="indigo" columns={3}>
                      <FormField label="Staff *">
                        <Select
                          value={itemForm.hotelStaffId ? String(itemForm.hotelStaffId) : "none"}
                          onValueChange={(v) => {
                            const sid = v === "none" ? 0 : Number(v)
                            const s: any = staffList.find((st: any) => (st.hotelStaffId ?? st.hotelstaffid) === sid)
                            setItemForm({
                              ...itemForm,
                              hotelStaffId: sid,
                              basicPay: s?.salaryAmount ?? s?.salaryamount ?? s?.salary ?? 0,
                            })
                          }}
                        >
                          <SelectTrigger><SelectValue placeholder="Select staff" /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="none">-- Select --</SelectItem>
                            {staffList
                              .filter((s: any) => !detail?.items?.some((it: any) => it.hotelstaffid === (s.hotelStaffId ?? s.hotelstaffid)))
                              .map((s: any) => (
                              <SelectItem key={s.hotelStaffId ?? s.hotelstaffid} value={String(s.hotelStaffId ?? s.hotelstaffid)}>
                                {s.firstName ?? s.firstname} {s.lastName ?? s.lastname} — {s.role ?? s.department ?? "Staff"}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </FormField>
                      <FormField label="Basic Pay">
                        <NumberInput step="0.01" value={itemForm.basicPay} onChange={(e) => setItemForm({ ...itemForm, basicPay: Number(e.target.value) || 0 })} />
                      </FormField>
                      <FormField label="Daily Wage">
                        <NumberInput step="0.01" value={itemForm.dailyWage} onChange={(e) => setItemForm({ ...itemForm, dailyWage: Number(e.target.value) || 0 })} />
                      </FormField>
                      <FormField label="Commission">
                        <NumberInput step="0.01" value={itemForm.commission} onChange={(e) => setItemForm({ ...itemForm, commission: Number(e.target.value) || 0 })} />
                      </FormField>
                      <FormField label="Bonus">
                        <NumberInput step="0.01" value={itemForm.bonus} onChange={(e) => setItemForm({ ...itemForm, bonus: Number(e.target.value) || 0 })} />
                      </FormField>
                      <FormField label="Deductions">
                        <NumberInput step="0.01" value={itemForm.deductions} onChange={(e) => setItemForm({ ...itemForm, deductions: Number(e.target.value) || 0 })} />
                      </FormField>
                      <FormField label="Payment Method">
                        <Select value={itemForm.paymentMethod} onValueChange={(v) => setItemForm({ ...itemForm, paymentMethod: v })}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {PAYMENT_METHODS.map((m) => (
                              <SelectItem key={m} value={m}>{m}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </FormField>
                      <FormField label=" ">
                        <Button onClick={handleSaveItem} disabled={itemSaving} className="bg-violet-600 hover:bg-violet-700 w-full">
                          {itemSaving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Save Line
                        </Button>
                      </FormField>
                    </FormSection>
                    )}
                    </>
                  )}

                  {/* Audit info */}
                  <div className="text-xs text-slate-500 space-y-1 border-t pt-4">
                    {detail.run.createdby && <p>Created by: {detail.run.createdby} on {detail.run.createdat?.slice(0, 10)}</p>}
                    {detail.run.approvedby && <p>Approved by: {detail.run.approvedby} on {detail.run.approvedat?.slice(0, 10)}</p>}
                    {detail.run.paidby && <p>Paid by: {detail.run.paidby} on {detail.run.paidat?.slice(0, 10)}</p>}
                    {detail.run.cancelledby && <p>Cancelled by: {detail.run.cancelledby} — Reason: {detail.run.cancelreason ?? "N/A"}</p>}
                  </div>
                </div>
              ) : null}
            </DialogContent>
          </Dialog>

          {/* ========== CANCEL DIALOG ========== */}
          <PromptDialog
            open={!!cancelTarget}
            onOpenChange={(v) => { if (!v) setCancelTarget(null) }}
            title="Cancel Payroll Run"
            description={`Cancel run for period ${cancelTarget?.periodstart?.slice(0, 10)} — ${cancelTarget?.periodend?.slice(0, 10)}?`}
            label="Reason (optional)"
            placeholder="e.g. Duplicate run, incorrect period"
            allowEmpty
            confirmLabel="Cancel Run"
            confirmVariant="destructive"
            onSubmit={async (reason) => {
              if (!cancelTarget) return
              await cancelHotelPayrollRun(cancelTarget.hotelpayrollrunid, reason || undefined)
              toast({ title: "Payroll run cancelled" })
              setCancelTarget(null)
              await load()
              if (detail && detail.run.hotelpayrollrunid === cancelTarget.hotelpayrollrunid) {
                const d = await getHotelPayrollRun(cancelTarget.hotelpayrollrunid)
                setDetail(d)
              }
            }}
          />

          {/* ========== DELETE DIALOG ========== */}
          <ConfirmDeleteDialog
            open={!!deleteTarget}
            onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}
            title="Delete Payroll Run?"
            itemLabel={deleteTarget ? `${deleteTarget.periodstart?.slice(0, 10)} — ${deleteTarget.periodend?.slice(0, 10)}` : ""}
            onConfirm={async () => {
              if (!deleteTarget) return
              await deleteHotelPayrollRun(deleteTarget.hotelpayrollrunid)
            }}
            onSuccess={() => { setDeleteTarget(null); load() }}
            successTitle="Payroll run deleted"
          />
        </main>
      </div>
    </div>
  )
}

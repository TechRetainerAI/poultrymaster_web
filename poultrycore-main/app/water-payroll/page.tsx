"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, Banknote, CheckCircle2, XCircle, Trash2, ExternalLink } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  listWaterPayrollRuns, getWaterPayrollRun, createWaterPayrollRun,
  upsertWaterPayrollItem, deleteWaterPayrollItem,
  approveWaterPayrollRun, markWaterPayrollRunPaid, cancelWaterPayrollRun,
  unapproveWaterPayrollRun, deleteWaterPayrollRun,
  listWaterStaff, listWaterCashAccounts,
  type WaterPayrollRun, type WaterStaff, type WaterCashAccount, type WaterPayrollItem,
} from "@/lib/api/water"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"

const STATUS_COLORS: Record<string, string> = {
  Draft:     "bg-slate-100 text-slate-700",
  Pending:   "bg-slate-100 text-slate-700",
  Approved:  "bg-blue-100 text-blue-700",
  Paid:      "bg-green-100 text-green-700",
  Reopened:  "bg-amber-100 text-amber-800",
  Cancelled: "bg-rose-100 text-rose-700",
}

// Editable / deletable status set. Reopened sits with Draft/Pending so
// corrections can be made after an Unapprove (Prompt 3 §1 + §5).
const EDITABLE_STATUSES = new Set(["Draft", "Pending", "Reopened"])
const isEditable = (r: WaterPayrollRun) => EDITABLE_STATUSES.has(r.status)

export default function WaterPayrollPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [runs, setRuns] = useState<WaterPayrollRun[]>([])
  const [staff, setStaff] = useState<WaterStaff[]>([])
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleRuns = useMemo(
    () => filterByDateAndSearch(runs, {
      search, dateFrom, dateTo,
      searchKeys: ["status", "notes"],
      dateKey: "periodStart",
    }),
    [runs, search, dateFrom, dateTo],
  )

  const [newRunDlg, setNewRunDlg] = useState(false)
  const [runForm, setRunForm] = useState({ periodStart: "", periodEnd: "", waterCashAccountId: 0, notes: "" })
  // Cancel target → opens the PromptDialog (replaces window.prompt).
  const [cancelTarget, setCancelTarget] = useState<WaterPayrollRun | null>(null)
  // Unapprove target → reopen reason required (Prompt 3 §3).
  const [unapproveTarget, setUnapproveTarget] = useState<WaterPayrollRun | null>(null)
  // Delete target (Draft/Pending/Reopened with no linked active expense).
  const [deleteTarget, setDeleteTarget] = useState<WaterPayrollRun | null>(null)

  const [editing, setEditing] = useState<WaterPayrollRun | null>(null)
  const [itemForm, setItemForm] = useState({ waterStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [rs, ss, accs] = await Promise.all([listWaterPayrollRuns(), listWaterStaff(), listWaterCashAccounts()])
      setRuns(rs); setStaff(ss); setAccounts(accs)
    } catch (e: any) { toast({ title: "Could not load payroll", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function createRun() {
    if (!runForm.periodStart || !runForm.periodEnd) return toast({ title: "Period required", variant: "destructive" })
    try {
      await createWaterPayrollRun({ ...runForm, waterCashAccountId: runForm.waterCashAccountId || null, notes: runForm.notes || null })
      toast({ title: "Run created" })
      setNewRunDlg(false); setRunForm({ periodStart: "", periodEnd: "", waterCashAccountId: 0, notes: "" })
      await load()
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
  }

  async function openEditing(r: WaterPayrollRun) {
    try {
      const full = await getWaterPayrollRun(r.waterPayrollRunId)
      setEditing(full)
    } catch (e: any) { toast({ title: "Load failed", description: e?.message, variant: "destructive" }) }
  }

  async function refreshEditing() {
    if (!editing) return
    try {
      const full = await getWaterPayrollRun(editing.waterPayrollRunId)
      setEditing(full)
    } catch { /* no-op */ }
  }

  async function addItem() {
    if (!editing) return
    if (!itemForm.waterStaffId) return toast({ title: "Pick staff", variant: "destructive" })
    try {
      await upsertWaterPayrollItem(editing.waterPayrollRunId, itemForm)
      setItemForm({ waterStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })
      await refreshEditing(); await load()
      toast({ title: "Item saved" })
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
  }

  async function removeItem(item: WaterPayrollItem) {
    try { await deleteWaterPayrollItem(item.waterPayrollItemId); await refreshEditing(); await load() }
    catch (e: any) { toast({ title: "Remove failed", description: e?.message, variant: "destructive" }) }
  }

  async function doAction(r: WaterPayrollRun, action: "approve" | "pay") {
    try {
      if (action === "approve") await approveWaterPayrollRun(r.waterPayrollRunId)
      if (action === "pay") await markWaterPayrollRunPaid(r.waterPayrollRunId)
      toast({ title: `Run ${action === "pay" ? "marked paid" : action + "d"}` })
      if (editing && editing.waterPayrollRunId === r.waterPayrollRunId) await refreshEditing()
      await load()
    } catch (e: any) { toast({ title: `${action} failed`, description: e?.message, variant: "destructive" }) }
  }

  async function confirmCancelRun(reason: string) {
    if (!cancelTarget) return
    try {
      await cancelWaterPayrollRun(cancelTarget.waterPayrollRunId, reason || undefined)
      toast({ title: "Payroll run cancelled" })
      if (editing && editing.waterPayrollRunId === cancelTarget.waterPayrollRunId) await refreshEditing()
      setCancelTarget(null); await load()
    } catch (e: any) {
      toast({ title: "Cancel failed", description: e?.message, variant: "destructive" })
      throw e
    }
  }

  // Reopen approved/paid run for corrections. Reverses the linked expense
  // (and refunds cash if the run was Paid). See migration 080.
  async function confirmUnapproveRun(reason: string) {
    if (!unapproveTarget) return
    if (!reason || !reason.trim()) {
      toast({ title: "Reason required", description: "Tell future-you why this payroll is being reopened.", variant: "destructive" })
      throw new Error("Reason required")
    }
    try {
      await unapproveWaterPayrollRun(unapproveTarget.waterPayrollRunId, reason.trim())
      toast({ title: "Payroll reopened", description: "Linked expense reversed. Make corrections and approve again." })
      if (editing && editing.waterPayrollRunId === unapproveTarget.waterPayrollRunId) await refreshEditing()
      setUnapproveTarget(null); await load()
    } catch (e: any) {
      toast({ title: "Reopen failed", description: e?.message, variant: "destructive" })
      throw e
    }
  }

  async function performDelete(r: WaterPayrollRun) {
    await deleteWaterPayrollRun(r.waterPayrollRunId)
    if (editing && editing.waterPayrollRunId === r.waterPayrollRunId) setEditing(null)
    await load()
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Banknote className="h-6 w-6 text-sky-600" /> Payroll
            </h1>
            <Button onClick={() => setNewRunDlg(true)} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New run</Button>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search status or notes"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : runs.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No payroll runs yet.</div>
              ) : (
                <MobileCardList
                  items={visibleRuns}
                  getKey={(r) => r.waterPayrollRunId}
                  primary={(r) => `${r.periodStart.split("T")[0]} → ${r.periodEnd.split("T")[0]}`}
                  secondary={(r) => (
                    <>
                      <span>Net {r.totalNetPay.toFixed(2)}</span>
                      <Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge>
                    </>
                  )}
                  details={(r) => [
                    { label: "Period", value: `${r.periodStart.split("T")[0]} → ${r.periodEnd.split("T")[0]}` },
                    { label: "Gross", value: r.totalGrossPay.toFixed(2) },
                    { label: "Net", value: r.totalNetPay.toFixed(2) },
                    { label: "Cash account", value: r.cashAccountName ?? "—" },
                    { label: "Status", value: r.status },
                  ]}
                  actions={(r) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => router.push(`/water-payroll/${r.waterPayrollRunId}`)}>
                        <ExternalLink className="h-4 w-4 mr-1" /> Details
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEditing(r)}>Open</Button>
                      {isEditable(r) && (
                        <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => doAction(r, "approve")}>
                          <CheckCircle2 className="h-4 w-4 mr-1" /> {r.status === "Reopened" ? "Re-approve" : "Approve"}
                        </Button>
                      )}
                      {r.status === "Approved" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={() => doAction(r, "pay")}>Mark paid</Button>
                      )}
                      {(r.status === "Approved" || r.status === "Paid") && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => setUnapproveTarget(r)}>
                          Reopen
                        </Button>
                      )}
                      {isEditable(r) && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(r)}>
                          <Trash2 className="h-4 w-4 mr-1" /> Delete
                        </Button>
                      )}
                      {r.status !== "Cancelled" && r.status !== "Paid" && r.status !== "Approved" && r.status !== "Reopened" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setCancelTarget(r)}>
                          <XCircle className="h-4 w-4 mr-1" /> Cancel
                        </Button>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Period</TableHead><TableHead className="text-right">Gross</TableHead><TableHead className="text-right">Net</TableHead><TableHead>Cash account</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRuns.map((r) => (
                          <TableRow key={r.waterPayrollRunId}>
                            <TableCell className="font-medium">{r.periodStart.split("T")[0]} → {r.periodEnd.split("T")[0]}</TableCell>
                            <TableCell className="text-right tabular-nums">{r.totalGrossPay.toFixed(2)}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold">{r.totalNetPay.toFixed(2)}</TableCell>
                            <TableCell>{r.cashAccountName ?? "—"}</TableCell>
                            <TableCell><Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" title="Open details page" onClick={() => router.push(`/water-payroll/${r.waterPayrollRunId}`)}>
                                <ExternalLink className="h-4 w-4 text-slate-500" />
                              </Button>
                              <Button size="sm" variant="ghost" onClick={() => openEditing(r)}>Open</Button>
                              {isEditable(r) && <Button size="sm" variant="ghost" title={r.status === "Reopened" ? "Re-approve" : "Approve"} onClick={() => doAction(r, "approve")}><CheckCircle2 className="h-4 w-4 text-blue-600" /></Button>}
                              {r.status === "Approved" && <Button size="sm" variant="ghost" onClick={() => doAction(r, "pay")}>Mark paid</Button>}
                              {(r.status === "Approved" || r.status === "Paid") && <Button size="sm" variant="ghost" className="text-amber-700" onClick={() => setUnapproveTarget(r)}>Reopen</Button>}
                              {isEditable(r) && <Button size="sm" variant="ghost" title="Delete run" onClick={() => setDeleteTarget(r)}><Trash2 className="h-4 w-4 text-red-500" /></Button>}
                              {r.status !== "Cancelled" && r.status !== "Paid" && r.status !== "Approved" && r.status !== "Reopened" && <Button size="sm" variant="ghost" title="Cancel run" onClick={() => setCancelTarget(r)}><XCircle className="h-4 w-4 text-rose-500" /></Button>}
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

      {/* New run */}
      <Dialog open={newRunDlg} onOpenChange={setNewRunDlg}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Banknote className="w-5 h-5 text-blue-600" /> New payroll run
            </DialogTitle>
            <DialogDescription>Open a payroll run for a pay period</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Period" color="indigo">
              <FormField label="Period start *">
                <Input type="date" value={runForm.periodStart} onChange={(e) => setRunForm({ ...runForm, periodStart: e.target.value })} />
              </FormField>
              <FormField label="Period end *">
                <Input type="date" value={runForm.periodEnd} onChange={(e) => setRunForm({ ...runForm, periodEnd: e.target.value })} />
              </FormField>
            </FormSection>

            <FormSection title="Payment" color="amber" columns={1}>
              <FormField label="Cash account (used at Mark-Paid)">
                <Select value={String(runForm.waterCashAccountId)} onValueChange={(v) => setRunForm({ ...runForm, waterCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Pick account" /></SelectTrigger>
                  <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName} ({a.currentBalance.toFixed(2)})</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={runForm.notes} onChange={(e) => setRunForm({ ...runForm, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setNewRunDlg(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={createRun}>Create</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Open run / edit items */}
      <Dialog open={!!editing} onOpenChange={(v) => { if (!v) setEditing(null) }}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>
            {editing && (<>Run: {editing.periodStart.split("T")[0]} → {editing.periodEnd.split("T")[0]} <Badge className={STATUS_COLORS[editing.status] ?? ""}>{editing.status}</Badge></>)}
          </DialogTitle></DialogHeader>
          {editing && (
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-3 text-sm">
                <div><span className="text-slate-500">Gross:</span> <span className="font-semibold tabular-nums">{editing.totalGrossPay.toFixed(2)}</span></div>
                <div><span className="text-slate-500">Deductions:</span> <span className="font-semibold tabular-nums">{editing.totalDeductions.toFixed(2)}</span></div>
                <div><span className="text-slate-500">Net:</span> <span className="font-semibold text-green-700 tabular-nums">{editing.totalNetPay.toFixed(2)}</span></div>
              </div>

              <div className="border-t pt-3">
                <div className="font-medium mb-2">Items</div>
                {editing.items && editing.items.length > 0 ? (
                  <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow><TableHead>Staff</TableHead><TableHead className="text-right">Basic</TableHead><TableHead className="text-right">Daily</TableHead><TableHead className="text-right">Commission</TableHead><TableHead className="text-right">Bonus</TableHead><TableHead className="text-right">Deductions</TableHead><TableHead className="text-right">Net</TableHead><TableHead /></TableRow>
                    </TableHeader>
                    <TableBody>
                      {editing.items.map((i) => (
                        <TableRow key={i.waterPayrollItemId}>
                          <TableCell>{i.staffName ?? i.waterStaffId}</TableCell>
                          <TableCell className="text-right tabular-nums">{i.basicPay.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums">{i.dailyWage.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums">{i.commission.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums">{i.bonus.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums">{i.deductions.toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums font-semibold">{i.netPay.toFixed(2)}</TableCell>
                          <TableCell>
                            {isEditable(editing) && <Button size="sm" variant="ghost" onClick={() => removeItem(i)}><Trash2 className="h-4 w-4 text-red-500" /></Button>}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  </div>
                ) : <div className="text-slate-500 text-sm">No items yet.</div>}
              </div>

              {/* Audit panel — visible whenever any audit field is populated.
                  Tracks both the initial approval cycle and any reopen/reapprove
                  cycles (migration 080). */}
              {(editing.approvedBy || editing.paidBy || editing.reopenedBy || editing.reapprovedBy) && (
                <div className="border-t pt-3">
                  <div className="font-medium mb-2">History</div>
                  <ul className="text-sm text-slate-600 space-y-1">
                    {editing.approvedBy && (
                      <li>Approved by <span className="font-medium">{editing.approvedBy}</span>{editing.approvedAt ? ` on ${editing.approvedAt.split("T")[0]}` : ""}</li>
                    )}
                    {editing.paidBy && (
                      <li>Paid by <span className="font-medium">{editing.paidBy}</span>{editing.paidAt ? ` on ${editing.paidAt.split("T")[0]}` : ""}</li>
                    )}
                    {editing.reopenedBy && (
                      <li>
                        Reopened by <span className="font-medium">{editing.reopenedBy}</span>
                        {editing.reopenedAt ? ` on ${editing.reopenedAt.split("T")[0]}` : ""}
                        {editing.reopenReason ? <> — <span className="italic">"{editing.reopenReason}"</span></> : null}
                      </li>
                    )}
                    {editing.reapprovedBy && (
                      <li>Re-approved by <span className="font-medium">{editing.reapprovedBy}</span>{editing.reapprovedAt ? ` on ${editing.reapprovedAt.split("T")[0]}` : ""}</li>
                    )}
                  </ul>
                </div>
              )}

              {isEditable(editing) && (
                <div className="border-t pt-3">
                  <div className="font-medium mb-2">Add / replace item</div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                    <div className="md:col-span-2"><Label>Staff</Label>
                      <Select value={String(itemForm.waterStaffId)} onValueChange={(v) => setItemForm({ ...itemForm, waterStaffId: Number(v) })}>
                        <SelectTrigger><SelectValue placeholder="Pick staff" /></SelectTrigger>
                        <SelectContent>{staff.filter(s => s.isActive).map(s => <SelectItem key={s.waterStaffId} value={String(s.waterStaffId)}>{s.firstName} {s.lastName} ({s.role})</SelectItem>)}</SelectContent>
                      </Select></div>
                    <div><Label>Basic</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.basicPay} onChange={(e) => setItemForm({ ...itemForm, basicPay: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Daily</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.dailyWage} onChange={(e) => setItemForm({ ...itemForm, dailyWage: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Commission</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.commission} onChange={(e) => setItemForm({ ...itemForm, commission: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Bonus</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.bonus} onChange={(e) => setItemForm({ ...itemForm, bonus: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Deductions</Label>
                      <NumberInput min={0} step="0.01" value={itemForm.deductions} onChange={(e) => setItemForm({ ...itemForm, deductions: Number(e.target.value) || 0 })} /></div>
                    <div className="md:col-span-2 flex items-end">
                      <Button className="w-full" onClick={addItem}>Save item</Button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      <PromptDialog
        open={!!cancelTarget}
        onOpenChange={(v) => { if (!v) setCancelTarget(null) }}
        title="Cancel payroll run"
        description={cancelTarget ? `Run for ${cancelTarget.periodStart?.split("T")[0]} → ${cancelTarget.periodEnd?.split("T")[0]} will be cancelled.` : ""}
        label="Reason (optional)"
        placeholder="e.g. ran twice, wrong period, replacing with corrected run…"
        confirmLabel="Cancel run"
        confirmVariant="destructive"
        allowEmpty
        onSubmit={confirmCancelRun}
      />

      <PromptDialog
        open={!!unapproveTarget}
        onOpenChange={(v) => { if (!v) setUnapproveTarget(null) }}
        title="Reopen payroll run"
        description={
          unapproveTarget
            ? `Run for ${unapproveTarget.periodStart?.split("T")[0]} → ${unapproveTarget.periodEnd?.split("T")[0]} will be reopened. The linked payroll expense will be reversed${unapproveTarget.status === "Paid" ? " and the cash account refunded" : ""}.`
            : ""
        }
        label="Reason *"
        placeholder="e.g. wrong amount for Kofi, missed bonus, correcting period…"
        confirmLabel="Reopen run"
        confirmVariant="destructive"
        onSubmit={confirmUnapproveRun}
      />

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete payroll run?"
        description="This removes the payroll run and all its employee payroll lines. Only available while the run is Draft, Pending, or Reopened — and never while an approved expense is still linked."
        itemLabel={deleteTarget ? `${deleteTarget.periodStart?.split("T")[0]} → ${deleteTarget.periodEnd?.split("T")[0]}` : undefined}
        successTitle="Payroll run removed"
        errorTitle="Delete failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

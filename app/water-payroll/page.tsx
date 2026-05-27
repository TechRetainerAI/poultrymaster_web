"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, Banknote, AlertCircle, CheckCircle2, XCircle, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  listWaterPayrollRuns, getWaterPayrollRun, createWaterPayrollRun,
  upsertWaterPayrollItem, deleteWaterPayrollItem,
  approveWaterPayrollRun, markWaterPayrollRunPaid, cancelWaterPayrollRun,
  listWaterStaff, listWaterCashAccounts,
  type WaterPayrollRun, type WaterStaff, type WaterCashAccount, type WaterPayrollItem,
} from "@/lib/api/water"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-blue-100 text-blue-700",
  Paid: "bg-green-100 text-green-700",
  Cancelled: "bg-amber-100 text-amber-700",
}

export default function WaterPayrollPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [runs, setRuns] = useState<WaterPayrollRun[]>([])
  const [staff, setStaff] = useState<WaterStaff[]>([])
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [newRunDlg, setNewRunDlg] = useState(false)
  const [runForm, setRunForm] = useState({ periodStart: "", periodEnd: "", waterCashAccountId: 0, notes: "" })
  // Cancel target → opens the PromptDialog (replaces window.prompt).
  const [cancelTarget, setCancelTarget] = useState<WaterPayrollRun | null>(null)

  const [editing, setEditing] = useState<WaterPayrollRun | null>(null)
  const [itemForm, setItemForm] = useState({ waterStaffId: 0, basicPay: 0, dailyWage: 0, commission: 0, bonus: 0, deductions: 0, paymentMethod: "Cash", notes: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try {
      const [rs, ss, accs] = await Promise.all([listWaterPayrollRuns(), listWaterStaff(), listWaterCashAccounts()])
      setRuns(rs); setStaff(ss); setAccounts(accs)
    } catch (e: any) { setError(e?.message ?? String(e)) }
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

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Banknote className="h-6 w-6 text-sky-600" /> Payroll
            </h1>
            <Button onClick={() => setNewRunDlg(true)}><Plus className="h-4 w-4 mr-1" /> New run</Button>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700"><AlertCircle className="h-4 w-4" /> {error}</CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : runs.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No payroll runs yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Period</TableHead><TableHead className="text-right">Gross</TableHead><TableHead className="text-right">Net</TableHead><TableHead>Cash account</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {runs.map((r) => (
                      <TableRow key={r.waterPayrollRunId}>
                        <TableCell className="font-medium">{r.periodStart.split("T")[0]} → {r.periodEnd.split("T")[0]}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.totalGrossPay.toFixed(2)}</TableCell>
                        <TableCell className="text-right tabular-nums font-semibold">{r.totalNetPay.toFixed(2)}</TableCell>
                        <TableCell>{r.cashAccountName ?? "—"}</TableCell>
                        <TableCell><Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          <Button size="sm" variant="ghost" onClick={() => openEditing(r)}>Open</Button>
                          {r.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => doAction(r, "approve")}><CheckCircle2 className="h-4 w-4 text-blue-600" /></Button>}
                          {r.status === "Approved" && <Button size="sm" variant="ghost" onClick={() => doAction(r, "pay")}>Mark paid</Button>}
                          {r.status !== "Cancelled" && r.status !== "Paid" && <Button size="sm" variant="ghost" onClick={() => setCancelTarget(r)}><XCircle className="h-4 w-4 text-rose-500" /></Button>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* New run */}
      <Dialog open={newRunDlg} onOpenChange={setNewRunDlg}>
        <DialogContent>
          <DialogHeader><DialogTitle>New payroll run</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>Period start *</Label>
              <Input type="date" value={runForm.periodStart} onChange={(e) => setRunForm({ ...runForm, periodStart: e.target.value })} /></div>
            <div><Label>Period end *</Label>
              <Input type="date" value={runForm.periodEnd} onChange={(e) => setRunForm({ ...runForm, periodEnd: e.target.value })} /></div>
            <div className="col-span-2"><Label>Cash account (used at Mark-Paid)</Label>
              <Select value={String(runForm.waterCashAccountId)} onValueChange={(v) => setRunForm({ ...runForm, waterCashAccountId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick account" /></SelectTrigger>
                <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName} ({a.currentBalance.toFixed(2)})</SelectItem>)}</SelectContent>
              </Select></div>
            <div className="col-span-2"><Label>Notes</Label>
              <Input value={runForm.notes} onChange={(e) => setRunForm({ ...runForm, notes: e.target.value })} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setNewRunDlg(false)}>Cancel</Button>
            <Button onClick={createRun}>Create</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Open run / edit items */}
      <Dialog open={!!editing} onOpenChange={(v) => { if (!v) setEditing(null) }}>
        <DialogContent className="max-w-4xl">
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
                            {editing.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => removeItem(i)}><Trash2 className="h-4 w-4 text-red-500" /></Button>}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                ) : <div className="text-slate-500 text-sm">No items yet.</div>}
              </div>

              {editing.status === "Draft" && (
                <div className="border-t pt-3">
                  <div className="font-medium mb-2">Add / replace item</div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                    <div className="md:col-span-2"><Label>Staff</Label>
                      <Select value={String(itemForm.waterStaffId)} onValueChange={(v) => setItemForm({ ...itemForm, waterStaffId: Number(v) })}>
                        <SelectTrigger><SelectValue placeholder="Pick staff" /></SelectTrigger>
                        <SelectContent>{staff.filter(s => s.isActive).map(s => <SelectItem key={s.waterStaffId} value={String(s.waterStaffId)}>{s.firstName} {s.lastName} ({s.role})</SelectItem>)}</SelectContent>
                      </Select></div>
                    <div><Label>Basic</Label>
                      <Input type="number" min={0} step="0.01" value={itemForm.basicPay} onChange={(e) => setItemForm({ ...itemForm, basicPay: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Daily</Label>
                      <Input type="number" min={0} step="0.01" value={itemForm.dailyWage} onChange={(e) => setItemForm({ ...itemForm, dailyWage: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Commission</Label>
                      <Input type="number" min={0} step="0.01" value={itemForm.commission} onChange={(e) => setItemForm({ ...itemForm, commission: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Bonus</Label>
                      <Input type="number" min={0} step="0.01" value={itemForm.bonus} onChange={(e) => setItemForm({ ...itemForm, bonus: Number(e.target.value) || 0 })} /></div>
                    <div><Label>Deductions</Label>
                      <Input type="number" min={0} step="0.01" value={itemForm.deductions} onChange={(e) => setItemForm({ ...itemForm, deductions: Number(e.target.value) || 0 })} /></div>
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
    </div>
  )
}

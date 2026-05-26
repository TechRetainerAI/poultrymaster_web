"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, Wrench, AlertCircle, CheckCircle2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterMaintenanceLogs, createWaterMaintenanceLog, completeWaterMaintenanceLog, deleteWaterMaintenanceLog,
  listWaterMaintenanceDueAlerts, listWaterCashAccounts,
  type WaterMaintenanceLog, type WaterMaintenanceLogInput, type WaterMaintenanceAlert, type WaterCashAccount,
} from "@/lib/api/water"

const ASSET_TYPES = ["Machine", "Vehicle", "Borehole", "Generator", "Other"]

const STATUS_COLORS: Record<string, string> = {
  Open: "bg-amber-100 text-amber-700",
  InProgress: "bg-blue-100 text-blue-700",
  Completed: "bg-green-100 text-green-700",
  Cancelled: "bg-slate-100 text-slate-700",
}

const SEVERITY_COLORS: Record<string, string> = {
  Overdue: "bg-rose-100 text-rose-700",
  DueSoon: "bg-amber-100 text-amber-700",
  Upcoming: "bg-blue-100 text-blue-700",
}

const EMPTY: WaterMaintenanceLogInput = {
  assetType: "Machine",
  assetId: null,
  assetLabel: "",
  issueDescription: "",
  technicianName: "",
  repairCost: 0,
  partsReplaced: "",
  downtimeHours: null,
  notes: "",
}

export default function WaterMaintenancePage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [logs, setLogs] = useState<WaterMaintenanceLog[]>([])
  const [alerts, setAlerts] = useState<WaterMaintenanceAlert[]>([])
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<WaterMaintenanceLogInput>(EMPTY)
  const [saving, setSaving] = useState(false)

  const [completeDlg, setCompleteDlg] = useState<{ open: boolean; log?: WaterMaintenanceLog }>({ open: false })
  const [completeCashId, setCompleteCashId] = useState<number | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<WaterMaintenanceLog | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try {
      const [ls, al, accs] = await Promise.all([listWaterMaintenanceLogs(), listWaterMaintenanceDueAlerts(), listWaterCashAccounts()])
      setLogs(ls); setAlerts(al); setAccounts(accs)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() { setForm(EMPTY); setOpen(true) }

  async function save() {
    if (!form.issueDescription.trim()) return toast({ title: "Issue description required", variant: "destructive" })
    setSaving(true)
    try {
      await createWaterMaintenanceLog(form)
      toast({ title: "Maintenance logged" })
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function complete() {
    if (!completeDlg.log) return
    try {
      await completeWaterMaintenanceLog(completeDlg.log.waterMaintenanceLogId, {
        waterCashAccountId: completeCashId,
      })
      toast({ title: "Marked completed" + (completeCashId ? " — cash booked" : "") })
      setCompleteDlg({ open: false }); setCompleteCashId(null); await load()
    } catch (e: any) { toast({ title: "Complete failed", description: e?.message, variant: "destructive" }) }
  }

  async function performDelete(l: WaterMaintenanceLog) {
    await deleteWaterMaintenanceLog(l.waterMaintenanceLogId)
    await load()
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Wrench className="h-6 w-6 text-sky-600" /> Maintenance
            </h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> Log issue</Button>
          </div>

          {alerts.length > 0 && (
            <Card className="mb-4 border-amber-200 bg-amber-50">
              <CardContent className="p-4">
                <div className="font-medium text-amber-900 mb-2">Due maintenance ({alerts.length})</div>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
                  {alerts.map((a, i) => (
                    <div key={`${a.assetType}-${a.assetId}-${i}`} className="rounded border bg-white p-2 text-sm flex items-center justify-between">
                      <div>
                        <div className="font-medium">{a.assetLabel} <span className="text-slate-400 text-xs">({a.assetType})</span></div>
                        <div className="text-xs text-slate-500">Due {a.nextDueDate.split("T")[0]} ({a.daysUntilDue >= 0 ? `in ${a.daysUntilDue}d` : `${Math.abs(a.daysUntilDue)}d ago`})</div>
                      </div>
                      <Badge className={SEVERITY_COLORS[a.severity] ?? ""}>{a.severity}</Badge>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700"><AlertCircle className="h-4 w-4" /> {error}</CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : logs.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No maintenance logs yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead><TableHead>Asset</TableHead><TableHead>Issue</TableHead>
                      <TableHead>Technician</TableHead><TableHead className="text-right">Cost</TableHead>
                      <TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {logs.map((l) => (
                      <TableRow key={l.waterMaintenanceLogId}>
                        <TableCell>{l.issueDate.split("T")[0]}</TableCell>
                        <TableCell><Badge variant="outline">{l.assetType}</Badge> {l.assetLabel ?? ""}</TableCell>
                        <TableCell className="max-w-xs truncate">{l.issueDescription}</TableCell>
                        <TableCell>{l.technicianName ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{l.repairCost.toFixed(2)}</TableCell>
                        <TableCell>
                          <Badge className={STATUS_COLORS[l.status] ?? ""}>{l.status}</Badge>
                          {l.cashTransactionWritten && <span className="ml-1 text-xs text-green-700">💸</span>}
                        </TableCell>
                        <TableCell className="text-right">
                          {l.status !== "Completed" && l.status !== "Cancelled" && (
                            <Button size="sm" variant="ghost" onClick={() => { setCompleteDlg({ open: true, log: l }); setCompleteCashId(null) }}>
                              <CheckCircle2 className="h-4 w-4 text-green-600" />
                            </Button>
                          )}
                          <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(l)}>×</Button>
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

      {/* Log new */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Log maintenance issue</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>Asset type</Label>
              <Select value={form.assetType} onValueChange={(v) => setForm({ ...form, assetType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{ASSET_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Asset label / name</Label>
              <Input value={form.assetLabel ?? ""} onChange={(e) => setForm({ ...form, assetLabel: e.target.value })} placeholder="e.g. Truck 1, Genset" /></div>
            <div className="col-span-2"><Label>Issue description *</Label>
              <Textarea value={form.issueDescription} onChange={(e) => setForm({ ...form, issueDescription: e.target.value })} /></div>
            <div><Label>Technician</Label>
              <Input value={form.technicianName ?? ""} onChange={(e) => setForm({ ...form, technicianName: e.target.value })} /></div>
            <div><Label>Repair cost (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={form.repairCost ?? 0} onChange={(e) => setForm({ ...form, repairCost: Number(e.target.value) || 0 })} /></div>
            <div><Label>Downtime hours</Label>
              <Input type="number" min={0} step="0.1" value={form.downtimeHours ?? ""} onChange={(e) => setForm({ ...form, downtimeHours: e.target.value ? Number(e.target.value) : null })} /></div>
            <div className="col-span-2"><Label>Parts replaced</Label>
              <Input value={form.partsReplaced ?? ""} onChange={(e) => setForm({ ...form, partsReplaced: e.target.value })} /></div>
            <div className="col-span-2"><Label>Notes</Label>
              <Textarea value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? "Saving…" : "Log"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete maintenance log?"
        description={deleteTarget ? `Delete the log for "${deleteTarget.assetLabel ?? deleteTarget.assetType}"? This action cannot be undone.` : undefined}
        successTitle="Log deleted"
        errorTitle="Delete failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />

      {/* Complete */}
      <Dialog open={completeDlg.open} onOpenChange={(v) => { if (!v) setCompleteDlg({ open: false }) }}>
        <DialogContent>
          <DialogHeader><DialogTitle>Complete maintenance</DialogTitle></DialogHeader>
          <p className="text-sm text-slate-600 mb-3">
            Cost: <span className="font-semibold">{completeDlg.log?.repairCost.toFixed(2)}</span>.
            Picking a cash account will book a CashOut at the same time.
          </p>
          <div><Label>Cash account (optional)</Label>
            <Select value={String(completeCashId ?? "")} onValueChange={(v) => setCompleteCashId(v ? Number(v) : null)}>
              <SelectTrigger><SelectValue placeholder="None (no cash impact)" /></SelectTrigger>
              <SelectContent>
                {accounts.filter(a => a.isActive).map(a => <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName} ({a.currentBalance.toFixed(2)})</SelectItem>)}
              </SelectContent>
            </Select></div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setCompleteDlg({ open: false })}>Cancel</Button>
            <Button onClick={complete}>Mark completed</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

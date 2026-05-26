"use client"

import { useEffect, useMemo, useState } from "react"
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
import { Plus, Loader2, Factory, AlertCircle, CheckCircle2, XCircle, Pencil, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterProductionBatches, createWaterProductionBatch, updateWaterProductionBatch,
  approveWaterProductionBatch, cancelWaterProductionBatch, reopenWaterProductionBatch,
  listWaterMachines, listWaterProducts,
  type WaterProductionBatch, type WaterMachine, type WaterProduct,
} from "@/lib/api/water"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-green-100 text-green-700",
  Cancelled: "bg-amber-100 text-amber-700",
}

const SHIFTS = ["Morning", "Afternoon", "Night", "FullDay"]

export default function WaterProductionBatchesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [batches, setBatches] = useState<WaterProductionBatch[]>([])
  const [machines, setMachines] = useState<WaterMachine[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  // null = create mode, number = edit mode (the WaterProductionBatchId being edited).
  // Only Draft batches can be edited; Approved/Cancelled rows show no pencil.
  const [editingId, setEditingId] = useState<number | null>(null)
  const [reopenTarget, setReopenTarget] = useState<WaterProductionBatch | null>(null)
  // Backend requires BatchNumber (max 60 chars). Frontend auto-generates a
  // timestamp-based default the user can override before submitting; without
  // this the POST was returning 400 "BatchNumber field is required."
  const makeBatchNumber = () => {
    const d = new Date()
    const pad = (n: number) => String(n).padStart(2, "0")
    return `B-${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  }

  const [form, setForm] = useState({
    batchNumber: makeBatchNumber(),
    productionDate: new Date().toISOString().split("T")[0],
    shift: "Morning",
    waterMachineId: 0,
    waterProductId: 0,
    bagsProduced: 0,
    sachetsPerBag: 30,
    rejectedSachets: 0,
    damagedBags: 0,
    electricityCost: 0,
    fuelCost: 0,
    laborCost: 0,
    otherProductionCost: 0,
    notes: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try {
      const [bs, ms, ps] = await Promise.all([listWaterProductionBatches(), listWaterMachines(), listWaterProducts()])
      setBatches(bs); setMachines(ms); setProducts(ps)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() {
    setEditingId(null)
    setForm({
      batchNumber: makeBatchNumber(),
      productionDate: new Date().toISOString().split("T")[0],
      shift: "Morning",
      waterMachineId: machines.find(m => m.status === "Active")?.waterMachineId ?? 0,
      waterProductId: products[0]?.waterProductId ?? 0,
      bagsProduced: 0,
      sachetsPerBag: 30,
      rejectedSachets: 0,
      damagedBags: 0,
      electricityCost: 0,
      fuelCost: 0,
      laborCost: 0,
      otherProductionCost: 0,
      notes: "",
    })
    setOpen(true)
  }

  function openEdit(b: WaterProductionBatch) {
    setEditingId(b.waterProductionBatchId)
    setForm({
      batchNumber: b.batchNumber ?? makeBatchNumber(),
      productionDate: b.productionDate ? b.productionDate.split("T")[0] : new Date().toISOString().split("T")[0],
      shift: b.shift ?? "Morning",
      waterMachineId: b.waterMachineId ?? 0,
      waterProductId: b.waterProductId ?? 0,
      bagsProduced: b.bagsProduced ?? 0,
      sachetsPerBag: b.sachetsPerBag ?? 30,
      rejectedSachets: b.rejectedSachets ?? 0,
      damagedBags: b.damagedBags ?? 0,
      electricityCost: b.electricityCost ?? 0,
      fuelCost: b.fuelCost ?? 0,
      laborCost: b.laborCost ?? 0,
      otherProductionCost: b.otherProductionCost ?? 0,
      notes: b.notes ?? "",
    })
    setOpen(true)
  }

  async function save() {
    if (!form.batchNumber.trim()) return toast({ title: "Batch number is required", variant: "destructive" })
    if (!form.waterProductId)     return toast({ title: "Pick a product first", variant: "destructive" })
    if (form.bagsProduced <= 0)   return toast({ title: "Bags produced must be greater than zero", variant: "destructive" })
    if (form.sachetsPerBag <= 0)  return toast({ title: "Sachets per bag must be greater than zero", variant: "destructive" })
    setSaving(true)
    try {
      const payload = {
        ...form,
        productionDate: form.productionDate,
        waterMachineId: form.waterMachineId || null as any,
        waterProductId: form.waterProductId || null as any,
      }
      if (editingId != null) {
        await updateWaterProductionBatch(editingId, payload as any)
        toast({ title: "Production batch updated" })
      } else {
        await createWaterProductionBatch(payload as any)
        toast({ title: "Production batch saved as Draft", description: "Approve to add to inventory." })
      }
      setOpen(false); setEditingId(null); await load()
    } catch (e: any) { toast({ title: editingId != null ? "Update failed" : "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function approve(b: WaterProductionBatch) {
    try { await approveWaterProductionBatch(b.waterProductionBatchId); toast({ title: "Batch approved — bags added to inventory" }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  async function cancel(b: WaterProductionBatch) {
    try { await cancelWaterProductionBatch(b.waterProductionBatchId); toast({ title: "Batch cancelled" }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }

  async function performReopen(b: WaterProductionBatch) {
    await reopenWaterProductionBatch(b.waterProductionBatchId)
    await load()
  }

  // Derived totals: today's bags + month's bags from Approved batches only
  const totals = useMemo(() => {
    const today = new Date().toISOString().slice(0, 10)
    const month = today.slice(0, 7)
    const approved = batches.filter(b => b.status === "Approved")
    const todayBags = approved.filter(b => b.productionDate.startsWith(today)).reduce((s, b) => s + (b.bagsProduced - (b.damagedBags ?? 0)), 0)
    const monthBags = approved.filter(b => b.productionDate.startsWith(month)).reduce((s, b) => s + (b.bagsProduced - (b.damagedBags ?? 0)), 0)
    return { todayBags, monthBags, draftCount: batches.filter(b => b.status === "Draft").length }
  }, [batches])

  // Live preview values in the dialog
  const totalSachets = form.bagsProduced * form.sachetsPerBag
  const totalProductionCost = form.electricityCost + form.fuelCost + form.laborCost + form.otherProductionCost
  const costPerBag = form.bagsProduced > 0 ? totalProductionCost / form.bagsProduced : 0
  const efficiency = totalSachets > 0 ? ((totalSachets - form.rejectedSachets) / totalSachets) * 100 : 0

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          {/* Header — stacks on mobile, side-by-side from sm: */}
          <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 bg-sky-100 rounded-lg flex items-center justify-center">
                <Factory className="h-5 w-5 text-sky-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-semibold text-slate-900 truncate">Production batches</h1>
                <p className="text-xs sm:text-sm text-slate-500">{batches.length} batch{batches.length === 1 ? "" : "es"} on record.</p>
              </div>
            </div>
            <Button onClick={openNew} className="gap-2 w-full sm:w-auto h-11 sm:h-10 shrink-0">
              <Plus className="h-4 w-4" /> Record production
            </Button>
          </div>

          {/* Stat cards — 2 cols on mobile, 4 on md+ */}
          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Today's bags (good)</div><div className="text-xl font-semibold tabular-nums">{totals.todayBags.toLocaleString()}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Month's bags</div><div className="text-xl font-semibold tabular-nums">{totals.monthBags.toLocaleString()}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Pending approval</div><div className="text-xl font-semibold">{totals.draftCount}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Active machines</div><div className="text-xl font-semibold">{machines.filter(m => m.status === "Active").length}</div></CardContent></Card>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700"><AlertCircle className="h-4 w-4 shrink-0" /> <span className="text-sm break-words">{error}</span></CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : batches.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No production batches yet.</div>
              ) : (
                // Horizontal scroll on narrow screens so columns don't overflow the card.
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Shift</TableHead>
                        <TableHead>Machine</TableHead>
                        <TableHead className="text-right">Bags</TableHead>
                        <TableHead className="text-right">Damaged</TableHead>
                        <TableHead className="text-right">Cost</TableHead>
                        <TableHead className="text-right">Cost/bag</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {batches.map((b) => (
                        <TableRow key={b.waterProductionBatchId}>
                          <TableCell className="whitespace-nowrap">{b.productionDate ? b.productionDate.split("T")[0] : "—"}</TableCell>
                          <TableCell>{b.shift ?? "—"}</TableCell>
                          <TableCell className="max-w-[160px] truncate">{b.machineName ?? "—"}</TableCell>
                          <TableCell className="text-right tabular-nums">{b.bagsProduced}</TableCell>
                          <TableCell className="text-right tabular-nums">{b.damagedBags ?? 0}</TableCell>
                          <TableCell className="text-right tabular-nums whitespace-nowrap">GHC {(b.totalProductionCost ?? 0).toFixed(2)}</TableCell>
                          <TableCell className="text-right tabular-nums">{(b.costPerBag ?? 0).toFixed(2)}</TableCell>
                          <TableCell><Badge className={STATUS_COLORS[b.status] ?? ""}>{b.status}</Badge></TableCell>
                          <TableCell className="text-right whitespace-nowrap">
                            {/* Edit only allowed in Draft — once approved the batch has moved stock + cash and edits would corrupt the books. */}
                            {b.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => openEdit(b)} title="Edit"><Pencil className="h-4 w-4" /></Button>}
                            {b.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => approve(b)} title="Approve"><CheckCircle2 className="h-4 w-4 text-green-600" /></Button>}
                            {b.status !== "Cancelled" && b.status !== "Approved" && <Button size="sm" variant="ghost" onClick={() => cancel(b)} title="Cancel"><XCircle className="h-4 w-4 text-rose-500" /></Button>}
                            {/* Reopen reverses the stock txn and flips back to Draft so the user can edit/delete. Blocked by backend if bags have already sold. */}
                            {b.status === "Approved" && <Button size="sm" variant="ghost" onClick={() => setReopenTarget(b)} title="Reopen for edit"><Undo2 className="h-4 w-4 text-amber-600" /></Button>}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) setEditingId(null) }}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>{editingId != null ? "Edit production batch" : "Record production batch"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <div className="col-span-4 md:col-span-4"><Label>Batch number *</Label>
              <Input maxLength={60} value={form.batchNumber} onChange={(e) => setForm({ ...form, batchNumber: e.target.value })} placeholder="e.g. B-20260524-093015" /></div>
            <div className="col-span-2"><Label>Production date</Label>
              <Input type="date" value={form.productionDate} onChange={(e) => setForm({ ...form, productionDate: e.target.value })} /></div>
            <div className="col-span-2"><Label>Shift</Label>
              <Select value={form.shift} onValueChange={(v) => setForm({ ...form, shift: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{SHIFTS.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
              </Select></div>

            <div className="col-span-2"><Label>Machine</Label>
              <Select value={String(form.waterMachineId)} onValueChange={(v) => setForm({ ...form, waterMachineId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick machine" /></SelectTrigger>
                <SelectContent>{machines.filter(m => m.status === "Active").map(m => <SelectItem key={m.waterMachineId} value={String(m.waterMachineId)}>{m.machineName}</SelectItem>)}</SelectContent>
              </Select></div>
            <div className="col-span-2"><Label>Product</Label>
              <Select value={String(form.waterProductId)} onValueChange={(v) => setForm({ ...form, waterProductId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                <SelectContent>{products.map(p => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}</SelectContent>
              </Select></div>

            <div><Label>Bags produced *</Label>
              <Input type="number" min={0} value={form.bagsProduced} onChange={(e) => setForm({ ...form, bagsProduced: Number(e.target.value) || 0 })} /></div>
            <div><Label>Sachets/bag</Label>
              <Input type="number" min={1} value={form.sachetsPerBag} onChange={(e) => setForm({ ...form, sachetsPerBag: Number(e.target.value) || 30 })} /></div>
            <div><Label>Damaged bags</Label>
              <Input type="number" min={0} value={form.damagedBags} onChange={(e) => setForm({ ...form, damagedBags: Number(e.target.value) || 0 })} /></div>
            <div><Label>Rejected sachets</Label>
              <Input type="number" min={0} value={form.rejectedSachets} onChange={(e) => setForm({ ...form, rejectedSachets: Number(e.target.value) || 0 })} /></div>

            <div><Label>Electricity (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={form.electricityCost} onChange={(e) => setForm({ ...form, electricityCost: Number(e.target.value) || 0 })} /></div>
            <div><Label>Fuel (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={form.fuelCost} onChange={(e) => setForm({ ...form, fuelCost: Number(e.target.value) || 0 })} /></div>
            <div><Label>Labor (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={form.laborCost} onChange={(e) => setForm({ ...form, laborCost: Number(e.target.value) || 0 })} /></div>
            <div><Label>Other (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={form.otherProductionCost} onChange={(e) => setForm({ ...form, otherProductionCost: Number(e.target.value) || 0 })} /></div>

            <div className="col-span-4"><Label>Notes</Label>
              <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>
          </div>

          <div className="border-t pt-3 grid grid-cols-2 md:grid-cols-4 gap-2 text-sm">
            <div><span className="text-slate-500">Total sachets:</span> <span className="font-semibold tabular-nums">{totalSachets.toLocaleString()}</span></div>
            <div><span className="text-slate-500">Total cost:</span> <span className="font-semibold tabular-nums">GHC {totalProductionCost.toFixed(2)}</span></div>
            <div><span className="text-slate-500">Cost/bag:</span> <span className="font-semibold tabular-nums">GHC {costPerBag.toFixed(2)}</span></div>
            <div><span className="text-slate-500">Efficiency:</span> <span className="font-semibold tabular-nums">{efficiency.toFixed(1)}%</span></div>
          </div>

          <div className="flex flex-col-reverse sm:flex-row sm:justify-end gap-2 pt-3 sticky bottom-0 bg-white pb-1">
            <Button variant="ghost" onClick={() => setOpen(false)} className="h-11 sm:h-10">Cancel</Button>
            <Button onClick={save} disabled={saving} className="h-11 sm:h-10">{saving ? "Saving…" : editingId != null ? "Save changes" : "Save as Draft"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!reopenTarget}
        onOpenChange={(o) => { if (!o) setReopenTarget(null) }}
        title="Reopen this approved batch?"
        description={reopenTarget
          ? `Reversing batch "${reopenTarget.batchNumber}" will subtract its ${(reopenTarget.bagsProduced ?? 0) - (reopenTarget.damagedBags ?? 0)} good bags from stock and flip it back to Draft. If those bags have already been sold this will fail — cancel the sales first.`
          : undefined}
        confirmLabel="Reopen"
        successTitle="Batch reopened — back to Draft"
        errorTitle="Reopen failed"
        onConfirm={async () => { if (reopenTarget) await performReopen(reopenTarget) }}
      />
    </div>
  )
}

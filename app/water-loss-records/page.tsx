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
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, AlertTriangle, AlertCircle, CheckCircle2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterLossRecords, createWaterLossRecord, approveWaterLossRecord,
  listWaterProducts, type WaterLossRecord, type WaterProduct,
} from "@/lib/api/water"

function gh(n: number) { return `GHC ${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` }

const LOSS_TYPES = ["BurstSachets","DamagedBags","ReturnedBags","MachineWaste","PackagingWaste","DriverShortage","MissingStock","BadDebt","Other"]
const STATUS_COLOR: Record<string, string> = {
  Pending: "bg-amber-100 text-amber-700",
  Approved: "bg-green-100 text-green-700",
}

export default function WaterLossRecordsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<WaterLossRecord[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [typeFilter, setTypeFilter] = useState<string>("ALL")
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState({
    lossDate: new Date().toISOString().split("T")[0],
    lossType: "DamagedBags",
    waterProductId: 0,
    quantityBags: 0,
    quantitySachets: 0,
    estimatedValue: 0,
    reason: "",
    notes: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, typeFilter])

  async function load() {
    setLoading(true); setError(null)
    try {
      const [ls, ps] = await Promise.all([
        listWaterLossRecords(typeFilter === "ALL" ? undefined : { lossType: typeFilter }),
        listWaterProducts(),
      ])
      setItems(ls); setProducts(ps)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNew() {
    setForm({
      lossDate: new Date().toISOString().split("T")[0],
      lossType: "DamagedBags",
      waterProductId: products[0]?.waterProductId ?? 0,
      quantityBags: 0, quantitySachets: 0, estimatedValue: 0, reason: "", notes: "",
    })
    setOpen(true)
  }

  async function save() {
    if (!form.reason.trim()) return toast({ title: "Reason required", variant: "destructive" })
    try {
      await createWaterLossRecord({
        ...form,
        waterProductId: form.waterProductId || null,
        quantityBags: form.quantityBags || null,
        quantitySachets: form.quantitySachets || null,
        estimatedValue: form.estimatedValue || null,
      } as any)
      toast({ title: "Loss recorded — pending approval" })
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
  }

  async function approve(l: WaterLossRecord) {
    try { await approveWaterLossRecord(l.waterLossRecordId); toast({ title: "Loss approved" }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  const totals = useMemo(() => {
    const approved = items.filter(i => i.status === "Approved")
    return {
      approvedValue: approved.reduce((s, i) => s + (i.estimatedValue ?? 0), 0),
      approvedBags: approved.reduce((s, i) => s + (i.quantityBags ?? 0), 0),
      pending: items.filter(i => i.status !== "Approved").length,
    }
  }, [items])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2 flex-wrap">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <AlertTriangle className="h-6 w-6 text-rose-600" /> Loss records
            </h1>
            <div className="flex items-center gap-2">
              <Select value={typeFilter} onValueChange={setTypeFilter}>
                <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All types</SelectItem>
                  {LOSS_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                </SelectContent>
              </Select>
              <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> Record loss</Button>
            </div>
          </div>

          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved value</div><div className="text-xl font-semibold tabular-nums">{gh(totals.approvedValue)}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved bags lost</div><div className="text-xl font-semibold">{totals.approvedBags}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Pending</div><div className="text-xl font-semibold">{totals.pending}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total records</div><div className="text-xl font-semibold">{items.length}</div></CardContent></Card>
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
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No losses recorded yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead className="text-right">Bags</TableHead><TableHead className="text-right">Sachets</TableHead><TableHead className="text-right">Value</TableHead><TableHead>Reason</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {items.map((l) => (
                      <TableRow key={l.waterLossRecordId}>
                        <TableCell>{l.lossDate.split("T")[0]}</TableCell>
                        <TableCell><Badge variant="outline">{l.lossType}</Badge></TableCell>
                        <TableCell className="text-right tabular-nums">{l.quantityBags ?? 0}</TableCell>
                        <TableCell className="text-right tabular-nums">{l.quantitySachets ?? 0}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(l.estimatedValue ?? 0)}</TableCell>
                        <TableCell className="max-w-xs truncate">{l.reason ?? "—"}</TableCell>
                        <TableCell><Badge className={STATUS_COLOR[l.status ?? "Pending"] ?? ""}>{l.status ?? "Pending"}</Badge></TableCell>
                        <TableCell className="text-right">
                          {l.status !== "Approved" && <Button size="sm" variant="ghost" onClick={() => approve(l)}><CheckCircle2 className="h-4 w-4 text-green-600" /></Button>}
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

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>Record loss</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>Date</Label>
              <Input type="date" value={form.lossDate} onChange={(e) => setForm({ ...form, lossDate: e.target.value })} /></div>
            <div><Label>Loss type</Label>
              <Select value={form.lossType} onValueChange={(v) => setForm({ ...form, lossType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{LOSS_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select></div>
            <div className="col-span-2"><Label>Product</Label>
              <Select value={String(form.waterProductId)} onValueChange={(v) => setForm({ ...form, waterProductId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="(optional)" /></SelectTrigger>
                <SelectContent>{products.map(p => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Bags</Label>
              <Input type="number" min={0} value={form.quantityBags} onChange={(e) => setForm({ ...form, quantityBags: Number(e.target.value) || 0 })} /></div>
            <div><Label>Sachets</Label>
              <Input type="number" min={0} value={form.quantitySachets} onChange={(e) => setForm({ ...form, quantitySachets: Number(e.target.value) || 0 })} /></div>
            <div className="col-span-2"><Label>Estimated value (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={form.estimatedValue} onChange={(e) => setForm({ ...form, estimatedValue: Number(e.target.value) || 0 })} /></div>
            <div className="col-span-2"><Label>Reason *</Label>
              <Textarea value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} /></div>
            <div className="col-span-2"><Label>Notes</Label>
              <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save}>Record</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

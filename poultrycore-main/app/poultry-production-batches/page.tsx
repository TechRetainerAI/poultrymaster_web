"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, CheckCircle2, XCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryProductionBatches, createPoultryProductionBatch, approvePoultryProductionBatch, cancelPoultryProductionBatch,
  listPoultryProducts, getPoultryRecipe, type PoultryProductionBatch, type PoultryProduct, type PoultryMaterialUsageInput,
} from "@/lib/api/poultry-inventory"

type MatRow = { poultryRawMaterialItemId: number; itemName: string; unit: string; expected: number; actual: number; unitCost: number }
const STATUS_COLORS: Record<string, string> = { Draft: "bg-slate-100 text-slate-700", Approved: "bg-green-100 text-green-700", Cancelled: "bg-amber-100 text-amber-700" }

function genBatchNo() {
  const d = new Date(); const p = (n: number) => String(n).padStart(2, "0")
  return `PB-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}`
}

export default function PoultryProductionBatchesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [batches, setBatches] = useState<PoultryProductionBatch[]>([])
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ batchNumber: genBatchNo(), productionDate: new Date().toISOString().split("T")[0], poultryProductId: 0, quantityProduced: 0, unit: "", damagedQuantity: 0, laborCost: 0, otherCost: 0, notes: "" })
  const [matRows, setMatRows] = useState<MatRow[]>([])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { const [bs, ps] = await Promise.all([listPoultryProductionBatches(), listPoultryProducts()]); setBatches(bs); setProducts(ps) }
    catch (e: any) { toast({ title: "Could not load batches", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    setForm({ batchNumber: genBatchNo(), productionDate: new Date().toISOString().split("T")[0], poultryProductId: 0, quantityProduced: 0, unit: "", damagedQuantity: 0, laborCost: 0, otherCost: 0, notes: "" })
    setMatRows([]); setOpen(true)
  }

  async function loadRecipe(productId: number, qty: number) {
    try {
      const r = await getPoultryRecipe(productId)
      if (!r || !r.items?.length) { setMatRows([]); return }
      setMatRows(r.items.map((it) => {
        const expected = (it.quantityPerOutputUnit || 0) * qty * (1 + (it.wasteAllowancePercent || 0) / 100)
        return { poultryRawMaterialItemId: it.poultryRawMaterialItemId, itemName: it.itemName ?? "", unit: it.unitOfMeasure ?? "", expected, actual: expected, unitCost: it.latestUnitCost ?? 0 }
      }))
    } catch (e: any) { toast({ title: "Could not load recipe", description: e?.message, variant: "destructive" }) }
  }

  async function save() {
    if (!form.poultryProductId) { toast({ title: "Pick a product", variant: "destructive" }); return }
    if (form.quantityProduced <= 0) { toast({ title: "Quantity produced must be > 0", variant: "destructive" }); return }
    const materialsUsed: PoultryMaterialUsageInput[] = matRows.map((m) => ({ poultryRawMaterialItemId: m.poultryRawMaterialItemId, quantityUsed: m.actual, expectedQuantityUsed: m.expected, unitCost: m.unitCost }))
    setSaving(true)
    try {
      await createPoultryProductionBatch({ ...form, materialsUsed })
      toast({ title: "Batch created (Draft)" }); setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function approve(id: number) {
    try { await approvePoultryProductionBatch(id); toast({ title: "Batch approved — stock updated" }); await load() }
    catch (e: any) { toast({ title: "Approval failed", description: e?.message, variant: "destructive" }) }
  }
  async function cancel(id: number) {
    try { await cancelPoultryProductionBatch(id); toast({ title: "Batch cancelled" }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }

  const matTotal = matRows.reduce((s, m) => s + m.actual * m.unitCost, 0)

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold">Production Batches</h1><p className="text-sm text-slate-500">Turn raw materials into finished products. Approving a batch consumes materials and adds finished stock.</p></div>
            <Button onClick={openNew}><Plus className="w-4 h-4 mr-1" /> New batch</Button>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Batch #</TableHead><TableHead>Date</TableHead><TableHead>Product</TableHead>
                  <TableHead className="text-right">Produced</TableHead><TableHead className="text-right">Cost/unit</TableHead>
                  <TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {batches.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">No batches yet.</TableCell></TableRow>
                    : batches.map((b) => (
                      <TableRow key={b.poultryProductionBatchId}>
                        <TableCell className="font-medium">{b.batchNumber}</TableCell>
                        <TableCell>{(b.productionDate || "").split("T")[0]}</TableCell>
                        <TableCell>{b.productName}</TableCell>
                        <TableCell className="text-right">{b.quantityProduced.toLocaleString()} {b.unit ?? ""}</TableCell>
                        <TableCell className="text-right">{b.status === "Draft" ? "—" : gh(b.costPerUnit)}</TableCell>
                        <TableCell><Badge className={STATUS_COLORS[b.status] ?? "bg-gray-100"}>{b.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          {b.status === "Draft" && <>
                            <Button variant="ghost" size="sm" onClick={() => approve(b.poultryProductionBatchId)} title="Approve"><CheckCircle2 className="w-4 h-4 text-green-600" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => cancel(b.poultryProductionBatchId)} title="Cancel"><XCircle className="w-4 h-4 text-amber-600" /></Button>
                          </>}
                        </TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table>
            )}
          </CardContent></Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-3xl">
          <DialogHeader><DialogTitle>New production batch</DialogTitle></DialogHeader>
          <FormSection title="Batch details" color="blue">
            <FormField label="Batch #"><Input value={form.batchNumber} onChange={(e) => setForm({ ...form, batchNumber: e.target.value })} /></FormField>
            <FormField label="Date"><Input type="date" value={form.productionDate} onChange={(e) => setForm({ ...form, productionDate: e.target.value })} /></FormField>
            <FormField label="Product *">
              <Select value={form.poultryProductId ? String(form.poultryProductId) : ""} onValueChange={(v) => { const id = Number(v); const p = products.find((x) => x.poultryProductId === id); setForm({ ...form, poultryProductId: id, unit: p?.unit ?? form.unit }); void loadRecipe(id, form.quantityProduced) }}>
                <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                <SelectContent>{products.filter((p) => p.isActive).map((p) => <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity produced *"><NumberInput min={0} step="0.001" value={form.quantityProduced} onChange={(e) => { const q = Number(e.target.value) || 0; setForm({ ...form, quantityProduced: q }); if (form.poultryProductId) void loadRecipe(form.poultryProductId, q) }} /></FormField>
            <FormField label="Damaged (auto-loss)"><NumberInput min={0} step="0.001" value={form.damagedQuantity} onChange={(e) => setForm({ ...form, damagedQuantity: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Labor cost"><NumberInput min={0} step="0.01" value={form.laborCost} onChange={(e) => setForm({ ...form, laborCost: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Other cost"><NumberInput min={0} step="0.01" value={form.otherCost} onChange={(e) => setForm({ ...form, otherCost: Number(e.target.value) || 0 })} /></FormField>
          </FormSection>

          <FormSection title={`Raw materials used — materials cost ${gh(matTotal)}`} color="indigo" columns={1}>
            {matRows.length === 0 ? <p className="text-xs text-amber-600">No recipe for this product (or none picked). Add a recipe on the Products page, or this batch will record no material usage.</p> : (
              <div className="space-y-2">
                <div className="grid grid-cols-12 gap-2 text-xs font-medium text-slate-500"><div className="col-span-4">Material</div><div className="col-span-2 text-right">Expected</div><div className="col-span-3 text-right">Actual used</div><div className="col-span-3 text-right">Unit cost</div></div>
                {matRows.map((m, i) => (
                  <div key={i} className="grid grid-cols-12 gap-2 items-center">
                    <div className="col-span-4 text-sm">{m.itemName} <span className="text-slate-400">{m.unit}</span></div>
                    <div className="col-span-2 text-right text-sm text-slate-500">{m.expected.toFixed(2)}</div>
                    <div className="col-span-3"><NumberInput min={0} step="0.0001" value={m.actual} onChange={(e) => { const rows = [...matRows]; rows[i] = { ...m, actual: Number(e.target.value) || 0 }; setMatRows(rows) }} /></div>
                    <div className="col-span-3"><NumberInput min={0} step="0.0001" value={m.unitCost} onChange={(e) => { const rows = [...matRows]; rows[i] = { ...m, unitCost: Number(e.target.value) || 0 }; setMatRows(rows) }} /></div>
                  </div>
                ))}
              </div>
            )}
          </FormSection>

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save draft"}</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

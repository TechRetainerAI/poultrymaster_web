"use client"

import { useEffect, useMemo, useState } from "react"
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
import { FieldCard } from "@/components/ui/field-card"
import { Plus, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryProducts, listPoultryStockTransactions, addPoultryStockTransaction,
  listPoultryRawMaterialPurchases, listPoultryRawMaterialUsageHistory,
  type PoultryProduct, type PoultryStockTransaction,
} from "@/lib/api/poultry-inventory"

// Doc 5: movement types with sign. Positive = increase, negative = decrease.
const MOVEMENTS: { value: string; sign: 1 | -1 }[] = [
  { value: "Increase", sign: 1 }, { value: "Adjustment", sign: 1 },
  { value: "Decrease", sign: -1 }, { value: "Sale", sign: -1 }, { value: "Damage/Loss", sign: -1 },
]
const MOVE_COLORS: Record<string, string> = {
  Increase: "bg-green-100 text-green-700", Restock: "bg-green-100 text-green-700", Production: "bg-emerald-100 text-emerald-700",
  Adjustment: "bg-slate-100 text-slate-700", Adjust: "bg-slate-100 text-slate-700",
  Decrease: "bg-amber-100 text-amber-700", Sale: "bg-blue-100 text-blue-700", Return: "bg-amber-100 text-amber-700",
  "Damage/Loss": "bg-red-100 text-red-700", "Delivery Load": "bg-indigo-100 text-indigo-700", "Delivery Return": "bg-amber-100 text-amber-700",
}
type Move = { key: string; date: string; item: string; parentType: string; movementType: string; qty: number; unitCost: number | null; total: number | null; source: string; note: string | null }

function sourceFor(txnType: string, relatedId?: number | null): string {
  if (txnType === "Production") return "Production Record"
  if (txnType === "Sale") return "Sale"
  if (txnType === "Restock" || txnType === "Increase") return "Manual / Product Stock Entry"
  return "Stock Page"
}

export default function PoultryStockPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [txns, setTxns] = useState<PoultryStockTransaction[]>([])
  const [rawMoves, setRawMoves] = useState<Move[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ poultryProductId: 0, movementType: "Increase", quantity: 0, unitCost: 0, note: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [ps, ts, purch, usage] = await Promise.all([
        listPoultryProducts(), listPoultryStockTransactions(),
        listPoultryRawMaterialPurchases().catch(() => []), listPoultryRawMaterialUsageHistory().catch(() => []),
      ])
      setProducts(ps); setTxns(ts)
      const rm: Move[] = [
        ...purch.map((p) => ({ key: `rp${p.poultryRawMaterialPurchaseId}`, date: p.purchaseDate, item: p.itemName ?? "", parentType: "Raw Material", movementType: "Increase", qty: p.quantity, unitCost: p.unitCost, total: p.totalCost, source: "Raw Material Purchase", note: p.notes ?? null })),
        ...usage.map((u) => ({ key: `ru${u.poultryRawMaterialUsageId}`, date: u.usedDate, item: u.itemName ?? "", parentType: "Raw Material", movementType: "Decrease", qty: -Math.abs(u.quantityUsed), unitCost: null, total: null, source: "Production Usage", note: u.varianceReason ?? null })),
      ]
      setRawMoves(rm)
    } catch (e: any) { toast({ title: "Could not load stock", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const moves: Move[] = useMemo(() => {
    const prod: Move[] = txns.map((t) => ({
      key: `pt${t.poultryStockTransactionId}`, date: t.createdDate, item: t.productName ?? "", parentType: "Finished Product",
      movementType: t.txnType, qty: t.quantity, unitCost: t.unitCost ?? null,
      total: t.unitCost != null ? Number((t.unitCost * Math.abs(t.quantity)).toFixed(2)) : null,
      source: sourceFor(t.txnType, t.relatedId), note: t.note ?? null,
    }))
    return [...prod, ...rawMoves].sort((a, b) => (b.date || "").localeCompare(a.date || ""))
  }, [txns, rawMoves])

  async function save() {
    if (!form.poultryProductId) { toast({ title: "Pick a product", variant: "destructive" }); return }
    if (form.quantity <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    const mv = MOVEMENTS.find((m) => m.value === form.movementType)!
    const signed = mv.sign * Math.abs(form.quantity)
    setSaving(true)
    try {
      await addPoultryStockTransaction({ poultryProductId: form.poultryProductId, txnType: form.movementType, quantity: signed, unitCost: form.unitCost || null, note: form.note || "Manual stock entry" })
      toast({ title: "Stock movement added" }); setOpen(false); setForm({ poultryProductId: 0, movementType: "Increase", quantity: 0, unitCost: 0, note: "" }); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold">Stock Movements</h1><p className="text-sm text-slate-500">All stock increases and decreases — finished products and raw materials. Production, sales, purchases and manual entries.</p></div>
            <Button onClick={() => setOpen(true)}><Plus className="w-4 h-4 mr-1" /> New movement</Button>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <><div className="hidden md:block overflow-x-auto"><Table className="min-w-[640px]">
                <TableHeader><TableRow>
                  <TableHead>Date</TableHead><TableHead>Item</TableHead><TableHead>Parent Type</TableHead><TableHead>Movement</TableHead>
                  <TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Unit Price</TableHead><TableHead className="text-right">Total Value</TableHead>
                  <TableHead>Source</TableHead><TableHead>Note</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {moves.length === 0 ? <TableRow><TableCell colSpan={9} className="text-center text-slate-500 py-6">No stock movements yet.</TableCell></TableRow>
                    : moves.map((m) => (
                      <TableRow key={m.key}>
                        <TableCell>{(m.date || "").split("T")[0]}</TableCell>
                        <TableCell className="font-medium">{m.item}</TableCell>
                        <TableCell><Badge className={m.parentType === "Finished Product" ? "bg-blue-100 text-blue-700" : "bg-slate-100 text-slate-700"}>{m.parentType}</Badge></TableCell>
                        <TableCell><Badge className={MOVE_COLORS[m.movementType] ?? "bg-gray-100"}>{m.movementType}</Badge></TableCell>
                        <TableCell className={`text-right ${m.qty < 0 ? "text-red-600" : "text-green-700"}`}>{m.qty > 0 ? "+" : ""}{m.qty.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{m.unitCost != null ? gh(m.unitCost) : "—"}</TableCell>
                        <TableCell className="text-right">{m.total != null ? gh(m.total) : "—"}</TableCell>
                        <TableCell className="text-slate-500">{m.source}</TableCell>
                        <TableCell className="text-slate-500">{m.note ?? "—"}</TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table></div>
              {/* Mobile cards */}
              <div className="md:hidden space-y-2">
                {moves.length === 0 ? <div className="text-center text-slate-500 py-6">No stock movements yet.</div>
                  : moves.map((m) => (
                    <FieldCard key={m.key} title={m.item}
                      badge={<Badge className={MOVE_COLORS[m.movementType] ?? "bg-gray-100"}>{m.movementType}</Badge>}
                      fields={[["Date", (m.date || "").split("T")[0]], ["Type", m.parentType], ["Qty", <span className={m.qty < 0 ? "text-red-600" : "text-green-700"}>{m.qty > 0 ? "+" : ""}{m.qty.toLocaleString()}</span>], ["Unit price", m.unitCost != null ? gh(m.unitCost) : "—"], ["Total", m.total != null ? gh(m.total) : "—"], ["Source", m.source]]} />
                  ))}
              </div></>
            )}
          </CardContent></Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>New stock movement</DialogTitle></DialogHeader>
          <FormSection title="Movement (finished product)" color="blue">
            <FormField label="Product *">
              <Select value={form.poultryProductId ? String(form.poultryProductId) : ""} onValueChange={(v) => setForm({ ...form, poultryProductId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                <SelectContent>{products.filter((p) => p.isActive).map((p) => <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Movement type">
              <Select value={form.movementType} onValueChange={(v) => setForm({ ...form, movementType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{MOVEMENTS.map((m) => <SelectItem key={m.value} value={m.value}>{m.value}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity" hint="Always enter a positive number; the movement type sets the direction."><NumberInput min={0} step="0.001" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Unit cost / value"><NumberInput min={0} step="0.01" value={form.unitCost} onChange={(e) => setForm({ ...form, unitCost: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Note" full><Input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

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
import { Plus, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { listPoultryProducts, listPoultryStockTransactions, addPoultryStockTransaction, type PoultryProduct, type PoultryStockTransaction } from "@/lib/api/poultry-inventory"

const TXN_TYPES = ["Restock", "Adjust", "Sale", "Return"]
const TXN_COLORS: Record<string, string> = { Restock: "bg-green-100 text-green-700", Production: "bg-emerald-100 text-emerald-700", Adjust: "bg-slate-100 text-slate-700", Sale: "bg-blue-100 text-blue-700", Return: "bg-amber-100 text-amber-700" }

export default function PoultryStockPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [txns, setTxns] = useState<PoultryStockTransaction[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ poultryProductId: 0, txnType: "Restock", quantity: 0, unitCost: 0, note: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { const [ps, ts] = await Promise.all([listPoultryProducts(), listPoultryStockTransactions()]); setProducts(ps); setTxns(ts) }
    catch (e: any) { toast({ title: "Could not load stock", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function save() {
    if (!form.poultryProductId) { toast({ title: "Pick a product", variant: "destructive" }); return }
    if (form.quantity === 0) { toast({ title: "Quantity cannot be 0", variant: "destructive" }); return }
    // Sale/Adjust-out should reduce stock — encode sign by type.
    const signed = form.txnType === "Sale" ? -Math.abs(form.quantity) : form.quantity
    setSaving(true)
    try {
      await addPoultryStockTransaction({ poultryProductId: form.poultryProductId, txnType: form.txnType, quantity: signed, unitCost: form.unitCost || null, note: form.note || null })
      toast({ title: "Stock transaction added" }); setOpen(false); setForm({ poultryProductId: 0, txnType: "Restock", quantity: 0, unitCost: 0, note: "" }); await load()
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
            <div><h1 className="text-2xl font-bold">Stock Movements</h1><p className="text-sm text-slate-500">Finished-product stock in/out history. Production batches add stock automatically.</p></div>
            <Button onClick={() => setOpen(true)}><Plus className="w-4 h-4 mr-1" /> New movement</Button>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Product</TableHead><TableHead>Type</TableHead><TableHead className="text-right">Qty</TableHead><TableHead>Note</TableHead></TableRow></TableHeader>
                <TableBody>
                  {txns.length === 0 ? <TableRow><TableCell colSpan={5} className="text-center text-slate-500 py-6">No movements yet.</TableCell></TableRow>
                    : txns.map((t) => (
                      <TableRow key={t.poultryStockTransactionId}>
                        <TableCell>{(t.createdDate || "").split("T")[0]}</TableCell>
                        <TableCell className="font-medium">{t.productName}</TableCell>
                        <TableCell><Badge className={TXN_COLORS[t.txnType] ?? "bg-gray-100"}>{t.txnType}</Badge></TableCell>
                        <TableCell className={`text-right ${t.quantity < 0 ? "text-red-600" : "text-green-700"}`}>{t.quantity > 0 ? "+" : ""}{t.quantity.toLocaleString()}</TableCell>
                        <TableCell className="text-slate-500">{t.note ?? "—"}</TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table>
            )}
          </CardContent></Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>New stock movement</DialogTitle></DialogHeader>
          <FormSection title="Movement" color="blue">
            <FormField label="Product *">
              <Select value={form.poultryProductId ? String(form.poultryProductId) : ""} onValueChange={(v) => setForm({ ...form, poultryProductId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                <SelectContent>{products.filter((p) => p.isActive).map((p) => <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Type">
              <Select value={form.txnType} onValueChange={(v) => setForm({ ...form, txnType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{TXN_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity"><NumberInput step="0.001" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Unit cost"><NumberInput min={0} step="0.01" value={form.unitCost} onChange={(e) => setForm({ ...form, unitCost: Number(e.target.value) || 0 })} /></FormField>
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

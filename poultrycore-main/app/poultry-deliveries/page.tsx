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
import { Plus, Loader2, CheckCircle2, Undo2, XCircle, Truck } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryDeliveries, loadPoultryDelivery, reconcilePoultryDelivery, reversePoultryDelivery, cancelPoultryDelivery,
  listPoultryProducts, ensureDefaultPoultryEgg, type PoultryDelivery, type PoultryProduct,
} from "@/lib/api/poultry-inventory"

const UNITS = ["Egg", "Tray", "Crate", "Dozen", "Piece", "Unit"]
const STATUS_COLORS: Record<string, string> = { Loaded: "bg-indigo-100 text-indigo-700", Reconciled: "bg-green-100 text-green-700", Cancelled: "bg-amber-100 text-amber-700" }

export default function PoultryDeliveriesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [rows, setRows] = useState<PoultryDelivery[]>([])
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [loadOpen, setLoadOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [loadForm, setLoadForm] = useState({ poultryProductId: 0, quantityLoaded: 0, unit: "Crate", unitPrice: 0, driverName: "", vehicleName: "", route: "", deliveryDate: new Date().toISOString().split("T")[0], notes: "" })

  const [recTarget, setRecTarget] = useState<PoultryDelivery | null>(null)
  const [recForm, setRecForm] = useState({ quantitySold: 0, quantityReturned: 0, quantityBroken: 0, quantityShort: 0, cashCollected: 0, creditSales: 0, deliveryExpenses: 0, paymentMethod: "Cash" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      await ensureDefaultPoultryEgg().catch(() => {})
      const [ds, ps] = await Promise.all([listPoultryDeliveries(), listPoultryProducts()])
      setRows(ds); setProducts(ps)
      if (!loadForm.poultryProductId) {
        const egg = ps.find((p) => p.isRawEggProduct) ?? ps[0]
        if (egg) setLoadForm((f) => ({ ...f, poultryProductId: egg.poultryProductId, unitPrice: egg.unitPrice || 0 }))
      }
    } catch (e: any) { toast({ title: "Could not load deliveries", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function doLoad() {
    if (!loadForm.poultryProductId) { toast({ title: "Pick a product", variant: "destructive" }); return }
    if (loadForm.quantityLoaded <= 0) { toast({ title: "Quantity loaded must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try { await loadPoultryDelivery(loadForm); toast({ title: "Eggs loaded — stock reduced" }); setLoadOpen(false); await load() }
    catch (e: any) { toast({ title: "Load failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function openReconcile(d: PoultryDelivery) {
    setRecTarget(d)
    setRecForm({ quantitySold: d.quantityLoaded, quantityReturned: 0, quantityBroken: 0, quantityShort: 0, cashCollected: d.quantityLoaded * d.unitPrice, creditSales: 0, deliveryExpenses: 0, paymentMethod: "Cash" })
  }
  const recAccounted = recForm.quantitySold + recForm.quantityReturned + recForm.quantityBroken + recForm.quantityShort
  async function doReconcile() {
    if (!recTarget) return
    if (Math.abs(recAccounted - recTarget.quantityLoaded) > 0.001) { toast({ title: `Sold + returned + broken + short must equal ${recTarget.quantityLoaded}`, variant: "destructive" }); return }
    setSaving(true)
    try { await reconcilePoultryDelivery(recTarget.poultryDeliveryId, recForm); toast({ title: "Delivery reconciled" }); setRecTarget(null); await load() }
    catch (e: any) { toast({ title: "Reconcile failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }
  async function doReverse(id: number) { try { await reversePoultryDelivery(id); toast({ title: "Delivery reversed" }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function doCancel(id: number) { try { await cancelPoultryDelivery(id); toast({ title: "Delivery cancelled — stock restored" }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold flex items-center gap-2"><Truck className="w-6 h-6" /> Egg Deliveries</h1><p className="text-sm text-slate-500">Load eggs onto a vehicle, then record the driver return &amp; reconcile.</p></div>
            <Button onClick={() => setLoadOpen(true)}><Plus className="w-4 h-4 mr-1" /> New load</Button>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Date</TableHead><TableHead>Driver / Vehicle</TableHead><TableHead className="text-right">Loaded</TableHead>
                  <TableHead className="text-right">Sold</TableHead><TableHead className="text-right">Ret</TableHead><TableHead className="text-right">Brk</TableHead><TableHead className="text-right">Short</TableHead>
                  <TableHead className="text-right">Sales</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {rows.length === 0 ? <TableRow><TableCell colSpan={10} className="text-center text-slate-500 py-6">No deliveries yet.</TableCell></TableRow>
                    : rows.map((d) => (
                      <TableRow key={d.poultryDeliveryId}>
                        <TableCell>{(d.deliveryDate || "").split("T")[0]}</TableCell>
                        <TableCell>{d.driverName ?? "—"}{d.vehicleName ? ` / ${d.vehicleName}` : ""}</TableCell>
                        <TableCell className="text-right">{d.quantityLoaded.toLocaleString()} {d.unit ?? ""}</TableCell>
                        <TableCell className="text-right">{d.status === "Loaded" ? "—" : d.quantitySold.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{d.status === "Loaded" ? "—" : d.quantityReturned.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{d.status === "Loaded" ? "—" : d.quantityBroken.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{d.status === "Loaded" ? "—" : d.quantityShort.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{d.status === "Loaded" ? "—" : gh(d.totalSales)}</TableCell>
                        <TableCell><Badge className={STATUS_COLORS[d.status] ?? "bg-gray-100"}>{d.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          {d.status === "Loaded" && <>
                            <Button variant="ghost" size="sm" onClick={() => openReconcile(d)} title="Record return & reconcile"><CheckCircle2 className="w-4 h-4 text-green-600" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => doCancel(d.poultryDeliveryId)} title="Cancel load"><XCircle className="w-4 h-4 text-amber-600" /></Button>
                          </>}
                          {d.status === "Reconciled" && <Button variant="ghost" size="sm" onClick={() => doReverse(d.poultryDeliveryId)} title="Reverse"><Undo2 className="w-4 h-4 text-amber-600" /></Button>}
                        </TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table>
            )}
          </CardContent></Card>
        </main>
      </div>

      {/* Load dialog */}
      <Dialog open={loadOpen} onOpenChange={setLoadOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>Load eggs for delivery</DialogTitle></DialogHeader>
          <FormSection title="Load details" color="indigo">
            <FormField label="Product *">
              <Select value={loadForm.poultryProductId ? String(loadForm.poultryProductId) : ""} onValueChange={(v) => { const id = Number(v); const p = products.find((x) => x.poultryProductId === id); setLoadForm({ ...loadForm, poultryProductId: id, unitPrice: p?.unitPrice ?? loadForm.unitPrice, unit: p?.unit ?? loadForm.unit }) }}>
                <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                <SelectContent>{products.filter((p) => p.isActive).map((p) => <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity loaded *"><NumberInput min={0} step="1" value={loadForm.quantityLoaded} onChange={(e) => setLoadForm({ ...loadForm, quantityLoaded: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Unit">
              <Select value={loadForm.unit} onValueChange={(v) => setLoadForm({ ...loadForm, unit: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{UNITS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Unit price"><NumberInput min={0} step="0.01" value={loadForm.unitPrice} onChange={(e) => setLoadForm({ ...loadForm, unitPrice: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Driver"><Input value={loadForm.driverName} onChange={(e) => setLoadForm({ ...loadForm, driverName: e.target.value })} /></FormField>
            <FormField label="Vehicle"><Input value={loadForm.vehicleName} onChange={(e) => setLoadForm({ ...loadForm, vehicleName: e.target.value })} /></FormField>
            <FormField label="Route"><Input value={loadForm.route} onChange={(e) => setLoadForm({ ...loadForm, route: e.target.value })} /></FormField>
            <FormField label="Date"><Input type="date" value={loadForm.deliveryDate} onChange={(e) => setLoadForm({ ...loadForm, deliveryDate: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setLoadOpen(false)}>Cancel</Button>
            <Button onClick={doLoad} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Load"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reconcile dialog */}
      <Dialog open={!!recTarget} onOpenChange={(o) => !o && setRecTarget(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>Driver return &amp; reconcile — {recTarget?.quantityLoaded.toLocaleString()} loaded</DialogTitle></DialogHeader>
          {recTarget && (
            <>
              <FormSection title="Egg accounting" color="blue">
                <FormField label="Sold"><NumberInput min={0} step="1" value={recForm.quantitySold} onChange={(e) => setRecForm({ ...recForm, quantitySold: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Returned"><NumberInput min={0} step="1" value={recForm.quantityReturned} onChange={(e) => setRecForm({ ...recForm, quantityReturned: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Broken"><NumberInput min={0} step="1" value={recForm.quantityBroken} onChange={(e) => setRecForm({ ...recForm, quantityBroken: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Short / missing"><NumberInput min={0} step="1" value={recForm.quantityShort} onChange={(e) => setRecForm({ ...recForm, quantityShort: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="" full>
                  <p className={`text-sm ${Math.abs(recAccounted - recTarget.quantityLoaded) < 0.001 ? "text-green-600" : "text-red-600"}`}>
                    Accounted: {recAccounted.toLocaleString()} / {recTarget.quantityLoaded.toLocaleString()} loaded {Math.abs(recAccounted - recTarget.quantityLoaded) < 0.001 ? "✓ balances" : "✗ must balance"}
                  </p>
                </FormField>
              </FormSection>
              <FormSection title="Money" color="emerald">
                <FormField label="Cash collected"><NumberInput min={0} step="0.01" value={recForm.cashCollected} onChange={(e) => setRecForm({ ...recForm, cashCollected: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Credit sales"><NumberInput min={0} step="0.01" value={recForm.creditSales} onChange={(e) => setRecForm({ ...recForm, creditSales: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Delivery expenses"><NumberInput min={0} step="0.01" value={recForm.deliveryExpenses} onChange={(e) => setRecForm({ ...recForm, deliveryExpenses: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Expected sales (auto)"><Input readOnly tabIndex={-1} className="bg-slate-100 pointer-events-none" value={gh(recForm.quantitySold * recTarget.unitPrice)} /></FormField>
              </FormSection>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setRecTarget(null)}>Cancel</Button>
                <Button onClick={doReconcile} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Reconcile"}</Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

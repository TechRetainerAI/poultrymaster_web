"use client"

// Generic Deliveries — load products onto a driver/vehicle, then reconcile
// what was sold/returned/damaged/short. Same pattern as poultry deliveries.

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
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Plus, Loader2, CheckCircle2, Undo2, XCircle, Truck } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getDeliveries, loadDelivery, reconcileDelivery, reverseDelivery, cancelDelivery,
  getProducts, type GenericDelivery, type GenericProduct,
} from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const UNITS = ["Piece", "Unit", "Kg", "Bag", "Box", "Crate", "Tray", "Dozen", "Bundle", "Litre"]
const STATUS_COLORS: Record<string, string> = {
  Loaded: "bg-indigo-100 text-indigo-700",
  Reconciled: "bg-green-100 text-green-700",
  Cancelled: "bg-amber-100 text-amber-700",
}

export default function GenericDeliveriesPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [rows, setRows] = useState<GenericDelivery[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [loadOpen, setLoadOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [loadForm, setLoadForm] = useState({
    genericProductId: 0, quantityLoaded: 0, unit: "Piece", unitPrice: 0,
    driverName: "", vehicleName: "", route: "",
    deliveryDate: new Date().toISOString().split("T")[0], notes: "",
  })

  const [recTarget, setRecTarget] = useState<GenericDelivery | null>(null)
  const [recForm, setRecForm] = useState({
    quantitySold: 0, quantityReturned: 0, quantityDamaged: 0, quantityShort: 0,
    cashCollected: 0, creditSales: 0, deliveryExpenses: 0,
  })

  const pg = usePagination(rows)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [dsResult, psResult] = await Promise.allSettled([getDeliveries(), getProducts()])
      if (dsResult.status === "fulfilled") setRows(dsResult.value)
      else setRows([])
      const ps = psResult.status === "fulfilled" ? psResult.value : []
      setProducts(ps)
      if (!loadForm.genericProductId && ps.length > 0) {
        const first = ps.find((p) => p.isActive) ?? ps[0]
        if (first) setLoadForm((f) => ({ ...f, genericProductId: first.genericProductId, unitPrice: first.sellingPrice || 0 }))
      }
    } catch (e: any) {
      toast({ title: "Could not load deliveries", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function doLoad() {
    if (!loadForm.genericProductId) { toast({ title: "Pick a product", variant: "destructive" }); return }
    if (loadForm.quantityLoaded <= 0) { toast({ title: "Quantity must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try {
      await loadDelivery(loadForm)
      toast({ title: "Product loaded — stock reduced" })
      setLoadOpen(false)
      await load()
    } catch (e: any) { toast({ title: "Load failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function openReconcile(d: GenericDelivery) {
    setRecTarget(d)
    setRecForm({
      quantitySold: d.quantityLoaded, quantityReturned: 0, quantityDamaged: 0, quantityShort: 0,
      cashCollected: d.quantityLoaded * d.unitPrice, creditSales: 0, deliveryExpenses: 0,
    })
  }

  const recAccounted = recForm.quantitySold + recForm.quantityReturned + recForm.quantityDamaged + recForm.quantityShort

  async function doReconcile() {
    if (!recTarget) return
    if (Math.abs(recAccounted - recTarget.quantityLoaded) > 0.001) {
      toast({ title: `Sold + returned + damaged + short must equal ${recTarget.quantityLoaded}`, variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await reconcileDelivery(recTarget.genericDeliveryId, recForm)
      toast({ title: "Delivery reconciled" })
      setRecTarget(null)
      await load()
    } catch (e: any) { toast({ title: "Reconcile failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doReverse(id: number) {
    try { await reverseDelivery(id); toast({ title: "Delivery reversed" }); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function doCancel(id: number) {
    try { await cancelDelivery(id); toast({ title: "Delivery cancelled — stock restored" }); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Truck className="h-5 w-5 text-emerald-600" /> Deliveries
              </h1>
              <p className="text-xs text-slate-500">
                Load products onto a vehicle, then record the driver return &amp; reconcile.
              </p>
            </div>
            <Button onClick={() => setLoadOpen(true)}>
              <Plus className="h-4 w-4 mr-1" /> New Load
            </Button>
          </div>

          <Card>
            <CardContent className="p-0 md:p-2">
              {loading ? (
                <div className="flex items-center gap-2 text-slate-500 p-8">
                  <Loader2 className="h-4 w-4 animate-spin" /> Loading…
                </div>
              ) : (
                <MobileCardList
                  defaultOpen
                  striped
                  stripeAccent="blue"
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(d: any) => d.genericDeliveryId}
                  primary={(d: any) => d.productName ?? `Product #${d.genericProductId}`}
                  secondary={(d: any) => (
                    <>
                      <span>{fmtDateTime(d.deliveryDate, d)}</span>
                      {d.driverName && <><span>·</span><span>{d.driverName}</span></>}
                    </>
                  )}
                  trailing={(d: any) => (
                    <Badge className={STATUS_COLORS[d.status] ?? "bg-slate-100"}>
                      {d.status}
                    </Badge>
                  )}
                  highlights={(d: any) => [
                    { label: "Loaded", value: `${d.quantityLoaded} ${d.unit ?? ""}`, accent: "blue" },
                    ...(d.status === "Reconciled" ? [
                      { label: "Sold", value: String(d.quantitySold), accent: "emerald" as const },
                      { label: "Sales", value: gh(d.totalSales), accent: "emerald" as const },
                    ] : []),
                  ]}
                  details={(d: any) => [
                    { label: "Vehicle", value: d.vehicleName ?? "—" },
                    { label: "Route", value: d.route ?? "—" },
                    { label: "Returned", value: String(d.quantityReturned) },
                    { label: "Damaged", value: String(d.quantityDamaged) },
                    { label: "Short", value: String(d.quantityShort) },
                    { label: "Cash collected", value: gh(d.cashCollected) },
                  ]}
                  actions={(d: any) => (
                    <>
                      {d.status === "Loaded" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200"
                            onClick={() => openReconcile(d)}>
                            <CheckCircle2 className="h-4 w-4 mr-1" /> Reconcile
                          </Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200"
                            onClick={() => doCancel(d.genericDeliveryId)}>
                            <XCircle className="h-4 w-4 mr-1" /> Cancel
                          </Button>
                        </>
                      )}
                      {d.status === "Reconciled" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200"
                          onClick={() => doReverse(d.genericDeliveryId)}>
                          <Undo2 className="h-4 w-4 mr-1" /> Reverse
                        </Button>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>Product</TableHead>
                            <TableHead>Driver / Vehicle</TableHead>
                            <TableHead className="text-right">Loaded</TableHead>
                            <TableHead className="text-right">Sold</TableHead>
                            <TableHead className="text-right">Ret</TableHead>
                            <TableHead className="text-right">Dmg</TableHead>
                            <TableHead className="text-right">Short</TableHead>
                            <TableHead className="text-right">Sales</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {rows.length === 0 ? (
                            <TableRow>
                              <TableCell colSpan={11} className="text-center text-slate-500 py-6">
                                No deliveries yet. Load a product to get started.
                              </TableCell>
                            </TableRow>
                          ) : pg.pageItems.map((d: any) => (
                            <TableRow key={d.genericDeliveryId}>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(d.deliveryDate, d)}</TableCell>
                              <TableCell className="font-medium">{d.productName ?? "—"}</TableCell>
                              <TableCell>{d.driverName ?? "—"}{d.vehicleName ? ` / ${d.vehicleName}` : ""}</TableCell>
                              <TableCell className="text-right">{d.quantityLoaded} {d.unit ?? ""}</TableCell>
                              <TableCell className="text-right">{d.status === "Loaded" ? "—" : d.quantitySold}</TableCell>
                              <TableCell className="text-right">{d.status === "Loaded" ? "—" : d.quantityReturned}</TableCell>
                              <TableCell className="text-right">{d.status === "Loaded" ? "—" : d.quantityDamaged}</TableCell>
                              <TableCell className="text-right">{d.status === "Loaded" ? "—" : d.quantityShort}</TableCell>
                              <TableCell className="text-right">{d.status === "Loaded" ? "—" : gh(d.totalSales)}</TableCell>
                              <TableCell>
                                <Badge className={STATUS_COLORS[d.status] ?? "bg-slate-100"}>
                                  {d.status}
                                </Badge>
                              </TableCell>
                              <TableCell className="text-right whitespace-nowrap">
                                {d.status === "Loaded" && (
                                  <>
                                    <Button variant="ghost" size="sm" onClick={() => openReconcile(d)} title="Reconcile">
                                      <CheckCircle2 className="h-4 w-4 text-green-600" />
                                    </Button>
                                    <Button variant="ghost" size="sm" onClick={() => doCancel(d.genericDeliveryId)} title="Cancel">
                                      <XCircle className="h-4 w-4 text-amber-600" />
                                    </Button>
                                  </>
                                )}
                                {d.status === "Reconciled" && (
                                  <Button variant="ghost" size="sm" onClick={() => doReverse(d.genericDeliveryId)} title="Reverse">
                                    <Undo2 className="h-4 w-4 text-amber-600" />
                                  </Button>
                                )}
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

      {/* Load dialog */}
      <Dialog open={loadOpen} onOpenChange={setLoadOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>Load product for delivery</DialogTitle></DialogHeader>
          <FormSection title="Load details" color="indigo">
            <FormField label="Product *">
              <Select
                value={loadForm.genericProductId ? String(loadForm.genericProductId) : ""}
                onValueChange={(v) => {
                  const id = Number(v)
                  const p = products.find((x) => x.genericProductId === id)
                  setLoadForm({ ...loadForm, genericProductId: id, unitPrice: p?.sellingPrice ?? loadForm.unitPrice })
                }}
              >
                <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                <SelectContent>
                  {products.filter((p) => p.isActive).map((p) => (
                    <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>{p.productName}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity *">
              <NumberInput min={0} step="1" value={loadForm.quantityLoaded}
                onChange={(e) => setLoadForm({ ...loadForm, quantityLoaded: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Unit">
              <Select value={loadForm.unit} onValueChange={(v) => setLoadForm({ ...loadForm, unit: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{UNITS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Unit price">
              <NumberInput min={0} step="0.01" value={loadForm.unitPrice}
                onChange={(e) => setLoadForm({ ...loadForm, unitPrice: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Driver">
              <Input value={loadForm.driverName} onChange={(e) => setLoadForm({ ...loadForm, driverName: e.target.value })} />
            </FormField>
            <FormField label="Vehicle">
              <Input value={loadForm.vehicleName} onChange={(e) => setLoadForm({ ...loadForm, vehicleName: e.target.value })} />
            </FormField>
            <FormField label="Route">
              <Input value={loadForm.route} onChange={(e) => setLoadForm({ ...loadForm, route: e.target.value })} />
            </FormField>
            <FormField label="Date">
              <Input type="date" value={loadForm.deliveryDate}
                onChange={(e) => setLoadForm({ ...loadForm, deliveryDate: e.target.value })} />
            </FormField>
            <FormField label="Notes">
              <Input value={loadForm.notes} onChange={(e) => setLoadForm({ ...loadForm, notes: e.target.value })} />
            </FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setLoadOpen(false)}>Cancel</Button>
            <Button onClick={doLoad} disabled={saving}>
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Load"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reconcile dialog */}
      <Dialog open={!!recTarget} onOpenChange={(o) => !o && setRecTarget(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>
              Driver return &amp; reconcile — {recTarget?.quantityLoaded} {recTarget?.unit ?? ""} loaded
            </DialogTitle>
          </DialogHeader>
          {recTarget && (
            <>
              <FormSection title="Product accounting" color="blue">
                <FormField label="Sold">
                  <NumberInput min={0} step="1" value={recForm.quantitySold}
                    onChange={(e) => setRecForm({ ...recForm, quantitySold: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="Returned">
                  <NumberInput min={0} step="1" value={recForm.quantityReturned}
                    onChange={(e) => setRecForm({ ...recForm, quantityReturned: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="Damaged">
                  <NumberInput min={0} step="1" value={recForm.quantityDamaged}
                    onChange={(e) => setRecForm({ ...recForm, quantityDamaged: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="Short / missing">
                  <NumberInput min={0} step="1" value={recForm.quantityShort}
                    onChange={(e) => setRecForm({ ...recForm, quantityShort: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="" full>
                  <p className={`text-sm ${Math.abs(recAccounted - recTarget.quantityLoaded) < 0.001 ? "text-green-600" : "text-red-600"}`}>
                    Accounted: {recAccounted} / {recTarget.quantityLoaded} loaded{" "}
                    {Math.abs(recAccounted - recTarget.quantityLoaded) < 0.001 ? "✓ balances" : "✗ must balance"}
                  </p>
                </FormField>
              </FormSection>
              <FormSection title="Money" color="emerald">
                <FormField label="Cash collected">
                  <NumberInput min={0} step="0.01" value={recForm.cashCollected}
                    onChange={(e) => setRecForm({ ...recForm, cashCollected: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="Credit sales">
                  <NumberInput min={0} step="0.01" value={recForm.creditSales}
                    onChange={(e) => setRecForm({ ...recForm, creditSales: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="Delivery expenses">
                  <NumberInput min={0} step="0.01" value={recForm.deliveryExpenses}
                    onChange={(e) => setRecForm({ ...recForm, deliveryExpenses: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="Expected sales (auto)">
                  <Input readOnly tabIndex={-1} className="bg-slate-100 pointer-events-none"
                    value={gh(recForm.quantitySold * recTarget.unitPrice)} />
                </FormField>
              </FormSection>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setRecTarget(null)}>Cancel</Button>
                <Button onClick={doReconcile} disabled={saving}>
                  {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Reconcile"}
                </Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

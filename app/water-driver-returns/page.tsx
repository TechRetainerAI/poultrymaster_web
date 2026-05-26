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
import { Plus, Loader2, Truck, AlertCircle, CheckCircle2, XCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterVehicleLoadings, createWaterVehicleLoading, approveWaterVehicleLoading, cancelWaterVehicleLoading,
  listWaterDriverReturns, createWaterDriverReturn, approveWaterDriverReturn,
  listWaterVehicles, listWaterRoutes, listWaterProducts,
  type WaterVehicleLoading, type WaterDriverReturn, type WaterVehicle, type WaterRoute, type WaterProduct,
} from "@/lib/api/water"

function gh(n: number) { return `GHC ${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` }

const LOAD_STATUS: Record<string, string> = {
  Loaded: "bg-blue-100 text-blue-700",
  Returned: "bg-amber-100 text-amber-700",
  Reconciled: "bg-green-100 text-green-700",
  Cancelled: "bg-slate-100 text-slate-700",
}

export default function WaterDriverReturnsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [loadings, setLoadings] = useState<WaterVehicleLoading[]>([])
  const [returns, setReturns] = useState<WaterDriverReturn[]>([])
  const [vehicles, setVehicles] = useState<WaterVehicle[]>([])
  const [routes, setRoutes] = useState<WaterRoute[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Load form (Load Vehicle)
  const [loadDlg, setLoadDlg] = useState(false)
  const [loadForm, setLoadForm] = useState({
    waterVehicleId: 0,
    waterRouteId: 0,
    waterProductId: 0,
    bagsLoaded: 0,
    sachetsPerBag: 30,
    expectedSellingPricePerBag: 0,
    openingCashWithDriver: 0,
    notes: "",
  })

  // Return form (reconcile a loading)
  const [returnDlg, setReturnDlg] = useState<{ open: boolean; loading?: WaterVehicleLoading }>({ open: false })
  const [returnForm, setReturnForm] = useState({
    bagsSold: 0,
    bagsReturned: 0,
    bagsDamaged: 0,
    cashCollected: 0,
    moMoCollected: 0,
    bankCollected: 0,
    creditSalesAmount: 0,
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
      const [ls, rs, vs, rts, ps] = await Promise.all([
        listWaterVehicleLoadings(), listWaterDriverReturns(),
        listWaterVehicles(), listWaterRoutes(), listWaterProducts(),
      ])
      setLoadings(ls); setReturns(rs); setVehicles(vs); setRoutes(rts); setProducts(ps)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openLoadDlg() {
    setLoadForm({
      waterVehicleId: vehicles.find(v => v.status === "Active")?.waterVehicleId ?? 0,
      waterRouteId: routes[0]?.waterRouteId ?? 0,
      waterProductId: products[0]?.waterProductId ?? 0,
      bagsLoaded: 0, sachetsPerBag: 30, expectedSellingPricePerBag: 0,
      openingCashWithDriver: 0, notes: "",
    })
    setLoadDlg(true)
  }

  async function saveLoad() {
    if (loadForm.bagsLoaded <= 0) return toast({ title: "Bags loaded must be > 0", variant: "destructive" })
    if (!loadForm.waterVehicleId) return toast({ title: "Pick a vehicle", variant: "destructive" })
    try {
      const created = await createWaterVehicleLoading({
        ...loadForm,
        loadDate: new Date().toISOString(),
        waterRouteId: loadForm.waterRouteId || null as any,
        waterProductId: loadForm.waterProductId || null as any,
      } as any)
      // Approve immediately so stock moves out — matches the typical "load and go" flow.
      if (created?.waterVehicleLoadingId) {
        await approveWaterVehicleLoading(created.waterVehicleLoadingId)
      }
      toast({ title: "Vehicle loaded — stock moved out" })
      setLoadDlg(false); await load()
    } catch (e: any) { toast({ title: "Load failed", description: e?.message, variant: "destructive" }) }
  }

  function openReturnDlg(l: WaterVehicleLoading) {
    setReturnForm({
      bagsSold: l.bagsLoaded, bagsReturned: 0, bagsDamaged: 0,
      cashCollected: l.expectedCash ?? 0,
      moMoCollected: 0, bankCollected: 0, creditSalesAmount: 0,
      notes: "",
    })
    setReturnDlg({ open: true, loading: l })
  }

  async function saveReturn() {
    if (!returnDlg.loading) return
    const totalBags = returnForm.bagsSold + returnForm.bagsReturned + returnForm.bagsDamaged
    if (totalBags !== returnDlg.loading.bagsLoaded) {
      return toast({
        title: "Bags don't reconcile",
        description: `Sold + Returned + Damaged = ${totalBags}, but Loaded = ${returnDlg.loading.bagsLoaded}`,
        variant: "destructive",
      })
    }
    try {
      const created = await createWaterDriverReturn({
        ...returnForm,
        waterVehicleLoadingId: returnDlg.loading.waterVehicleLoadingId,
        returnDate: new Date().toISOString(),
      })
      if (created?.waterDriverReturnId) {
        await approveWaterDriverReturn(created.waterDriverReturnId)
      }
      toast({ title: "Driver return reconciled — cash + sales booked" })
      setReturnDlg({ open: false }); await load()
    } catch (e: any) { toast({ title: "Return failed", description: e?.message, variant: "destructive" }) }
  }

  // Derived: cash totals + shortage on the return form
  const collected = returnForm.cashCollected + returnForm.moMoCollected + returnForm.bankCollected + returnForm.creditSalesAmount
  const expected = returnDlg.loading ? returnForm.bagsSold * (returnDlg.loading.expectedSellingPricePerBag ?? 0) : 0
  const shortage = Math.max(expected - collected, 0)
  const overage  = Math.max(collected - expected, 0)

  const totals = useMemo(() => ({
    openLoadings: loadings.filter(l => l.status === "Loaded").length,
    totalShortage: returns.reduce((s, r) => s + (r.shortageAmount ?? 0), 0),
    todayReturns: returns.filter(r => r.returnDate?.slice(0, 10) === new Date().toISOString().slice(0, 10)).length,
  }), [loadings, returns])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Truck className="h-6 w-6 text-sky-600" /> Driver returns
            </h1>
            <Button onClick={openLoadDlg}><Plus className="h-4 w-4 mr-1" /> Load vehicle</Button>
          </div>

          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Vehicles out</div><div className="text-xl font-semibold">{totals.openLoadings}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Returns today</div><div className="text-xl font-semibold">{totals.todayReturns}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total shortages</div><div className="text-xl font-semibold tabular-nums">{gh(totals.totalShortage)}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Active vehicles</div><div className="text-xl font-semibold">{vehicles.filter(v => v.status === "Active").length}</div></CardContent></Card>
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
              ) : loadings.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No vehicle loadings yet. Load a vehicle above to start.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Vehicle</TableHead>
                      <TableHead>Route</TableHead>
                      <TableHead className="text-right">Bags loaded</TableHead>
                      <TableHead className="text-right">Expected cash</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {loadings.map((l) => (
                      <TableRow key={l.waterVehicleLoadingId}>
                        <TableCell>{l.loadDate.split("T")[0]}</TableCell>
                        <TableCell>{l.vehicleName ?? "—"}</TableCell>
                        <TableCell>{l.routeName ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{l.bagsLoaded}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(l.expectedCash ?? 0)}</TableCell>
                        <TableCell><Badge className={LOAD_STATUS[l.status] ?? ""}>{l.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          {l.status === "Loaded" && <Button size="sm" onClick={() => openReturnDlg(l)}>Record return</Button>}
                          {l.status === "Loaded" && <Button size="sm" variant="ghost" onClick={async () => { await cancelWaterVehicleLoading(l.waterVehicleLoadingId); await load() }}><XCircle className="h-4 w-4 text-rose-500" /></Button>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          {returns.length > 0 && (
            <Card className="mt-4">
              <CardContent className="p-4">
                <div className="mb-2 font-medium text-slate-700">Recent driver returns</div>
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Date</TableHead><TableHead className="text-right">Sold</TableHead><TableHead className="text-right">Returned</TableHead><TableHead className="text-right">Damaged</TableHead><TableHead className="text-right">Cash</TableHead><TableHead className="text-right">MoMo</TableHead><TableHead className="text-right">Credit</TableHead><TableHead className="text-right">Shortage</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {returns.slice(0, 8).map((r) => (
                      <TableRow key={r.waterDriverReturnId}>
                        <TableCell>{r.returnDate.split("T")[0]}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.bagsSold}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.bagsReturned}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.bagsDamaged}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(r.cashCollected)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(r.moMoCollected)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(r.creditSalesAmount)}</TableCell>
                        <TableCell className={`text-right tabular-nums ${(r.shortageAmount ?? 0) > 0 ? "text-rose-600" : ""}`}>{gh(r.shortageAmount ?? 0)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>

      {/* Load Vehicle */}
      <Dialog open={loadDlg} onOpenChange={setLoadDlg}>
        <DialogContent>
          <DialogHeader><DialogTitle>Load vehicle</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Vehicle</Label>
              <Select value={String(loadForm.waterVehicleId)} onValueChange={(v) => setLoadForm({ ...loadForm, waterVehicleId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick vehicle" /></SelectTrigger>
                <SelectContent>{vehicles.filter(v => v.status === "Active").map(v => <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>{v.vehicleName} ({v.vehicleType})</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Route</Label>
              <Select value={String(loadForm.waterRouteId)} onValueChange={(v) => setLoadForm({ ...loadForm, waterRouteId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick route" /></SelectTrigger>
                <SelectContent>{routes.map(r => <SelectItem key={r.waterRouteId} value={String(r.waterRouteId)}>{r.routeName}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Product</Label>
              <Select value={String(loadForm.waterProductId)} onValueChange={(v) => setLoadForm({ ...loadForm, waterProductId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                <SelectContent>{products.map(p => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Bags loaded *</Label>
              <Input type="number" min={1} value={loadForm.bagsLoaded} onChange={(e) => setLoadForm({ ...loadForm, bagsLoaded: Number(e.target.value) || 0 })} /></div>
            <div><Label>Selling price/bag (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={loadForm.expectedSellingPricePerBag} onChange={(e) => setLoadForm({ ...loadForm, expectedSellingPricePerBag: Number(e.target.value) || 0 })} /></div>
            <div><Label>Opening cash w/ driver</Label>
              <Input type="number" min={0} step="0.01" value={loadForm.openingCashWithDriver} onChange={(e) => setLoadForm({ ...loadForm, openingCashWithDriver: Number(e.target.value) || 0 })} /></div>
            <div><Label>Sachets/bag</Label>
              <Input type="number" min={1} value={loadForm.sachetsPerBag} onChange={(e) => setLoadForm({ ...loadForm, sachetsPerBag: Number(e.target.value) || 30 })} /></div>
            <div className="col-span-2"><Label>Notes</Label>
              <Textarea value={loadForm.notes} onChange={(e) => setLoadForm({ ...loadForm, notes: e.target.value })} /></div>
          </div>
          <div className="border-t pt-2 text-sm">
            <span className="text-slate-500">Expected cash:</span> <span className="font-semibold tabular-nums">{gh(loadForm.bagsLoaded * loadForm.expectedSellingPricePerBag)}</span>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setLoadDlg(false)}>Cancel</Button>
            <Button onClick={saveLoad}>Load &amp; approve</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Driver Return */}
      <Dialog open={returnDlg.open} onOpenChange={(v) => { if (!v) setReturnDlg({ open: false }) }}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>Record driver return — {returnDlg.loading?.vehicleName} / {returnDlg.loading?.routeName ?? "—"}</DialogTitle></DialogHeader>
          {returnDlg.loading && (
            <>
              <div className="text-sm text-slate-600 mb-2">
                Loaded: <span className="font-semibold">{returnDlg.loading.bagsLoaded} bags</span> @ <span className="font-semibold">{gh(returnDlg.loading.expectedSellingPricePerBag ?? 0)}/bag</span> = expected <span className="font-semibold">{gh(returnDlg.loading.expectedCash ?? 0)}</span>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                <div><Label>Bags sold</Label>
                  <Input type="number" min={0} value={returnForm.bagsSold} onChange={(e) => setReturnForm({ ...returnForm, bagsSold: Number(e.target.value) || 0 })} /></div>
                <div><Label>Bags returned</Label>
                  <Input type="number" min={0} value={returnForm.bagsReturned} onChange={(e) => setReturnForm({ ...returnForm, bagsReturned: Number(e.target.value) || 0 })} /></div>
                <div><Label>Bags damaged</Label>
                  <Input type="number" min={0} value={returnForm.bagsDamaged} onChange={(e) => setReturnForm({ ...returnForm, bagsDamaged: Number(e.target.value) || 0 })} /></div>
                <div><Label>Cash collected (GHC)</Label>
                  <Input type="number" min={0} step="0.01" value={returnForm.cashCollected} onChange={(e) => setReturnForm({ ...returnForm, cashCollected: Number(e.target.value) || 0 })} /></div>
                <div><Label>MoMo collected (GHC)</Label>
                  <Input type="number" min={0} step="0.01" value={returnForm.moMoCollected} onChange={(e) => setReturnForm({ ...returnForm, moMoCollected: Number(e.target.value) || 0 })} /></div>
                <div><Label>Bank collected (GHC)</Label>
                  <Input type="number" min={0} step="0.01" value={returnForm.bankCollected} onChange={(e) => setReturnForm({ ...returnForm, bankCollected: Number(e.target.value) || 0 })} /></div>
                <div className="col-span-3"><Label>Credit sales (GHC)</Label>
                  <Input type="number" min={0} step="0.01" value={returnForm.creditSalesAmount} onChange={(e) => setReturnForm({ ...returnForm, creditSalesAmount: Number(e.target.value) || 0 })} /></div>
                <div className="col-span-3"><Label>Notes</Label>
                  <Textarea value={returnForm.notes} onChange={(e) => setReturnForm({ ...returnForm, notes: e.target.value })} /></div>
              </div>

              <div className="border-t pt-3 grid grid-cols-2 md:grid-cols-4 gap-2 text-sm">
                <div><span className="text-slate-500">Expected cash:</span> <span className="font-semibold tabular-nums">{gh(expected)}</span></div>
                <div><span className="text-slate-500">Collected:</span> <span className="font-semibold tabular-nums">{gh(collected)}</span></div>
                <div><span className="text-slate-500">Shortage:</span> <span className={`font-semibold tabular-nums ${shortage > 0 ? "text-rose-600" : ""}`}>{gh(shortage)}</span></div>
                <div><span className="text-slate-500">Overage:</span> <span className={`font-semibold tabular-nums ${overage > 0 ? "text-green-700" : ""}`}>{gh(overage)}</span></div>
              </div>
            </>
          )}
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setReturnDlg({ open: false })}>Cancel</Button>
            <Button onClick={saveReturn}>Reconcile &amp; approve</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

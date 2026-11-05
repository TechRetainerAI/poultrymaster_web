"use client"

// Generic Deliveries — the complete delivery management system.
// Everything linked: drivers, routes, products, transport modes, GPS locations.
// Flow: Loaded → Dispatch → InTransit → Mark Delivered → Delivered → Reconcile → Reconciled

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
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
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import {
  Plus, Loader2, CheckCircle2, Undo2, XCircle, Truck, Send, PackageCheck,
  LocateFixed, Search, MapPin, Users2, Package, TrendingUp,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  getDeliveries, loadDelivery, reconcileDelivery, reverseDelivery, cancelDelivery,
  dispatchDelivery, markDeliveryDelivered,
  getProducts, getDrivers, getRoutes, getCustomers,
  type GenericDelivery, type GenericProduct, type GenericDriver, type GenericRoute, type GenericCustomer,
} from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const UNITS = ["Piece", "Unit", "Kg", "Bag", "Box", "Crate", "Tray", "Dozen", "Bundle", "Litre"]
const TRANSPORT_MODES = ["Car", "Motorcycle", "Bicycle", "Truck", "Van", "Tricycle", "On Foot", "Other"]
const STATUS_COLORS: Record<string, string> = {
  Loaded: "bg-slate-100 text-slate-700", InTransit: "bg-blue-100 text-blue-700",
  Delivered: "bg-emerald-100 text-emerald-700", Reconciled: "bg-green-100 text-green-700",
  Cancelled: "bg-amber-100 text-amber-700",
}
const STATUS_NOT_RECONCILED = ["Loaded", "InTransit", "Delivered"]

const emptyForm = () => ({
  genericProductId: 0, quantityLoaded: 0, unit: "Piece", unitPrice: 0,
  driverName: "", vehicleName: "", route: "",
  customerName: "", startPoint: "", destination: "", transportMode: "Car",
  deliveryDate: new Date().toISOString().split("T")[0], notes: "",
})

export default function GenericDeliveriesPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [rows, setRows] = useState<GenericDelivery[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [driversList, setDriversList] = useState<GenericDriver[]>([])
  const [routesList, setRoutesList] = useState<GenericRoute[]>([])
  const [customersList, setCustomersList] = useState<GenericCustomer[]>([])
  const [loading, setLoading] = useState(true)
  const [loadOpen, setLoadOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [locating, setLocating] = useState(false)
  const [loadForm, setLoadForm] = useState(emptyForm())
  const [statusFilter, setStatusFilter] = useState("All")
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  const [recTarget, setRecTarget] = useState<GenericDelivery | null>(null)
  const [recForm, setRecForm] = useState({
    quantitySold: 0, quantityReturned: 0, quantityDamaged: 0, quantityShort: 0,
    cashCollected: 0, creditSales: 0, deliveryExpenses: 0,
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [dsR, psR, drR, rtR, cuR] = await Promise.allSettled([
        getDeliveries(), getProducts(), getDrivers(), getRoutes(), getCustomers(),
      ])
      if (dsR.status === "fulfilled") setRows(dsR.value); else setRows([])
      const ps = psR.status === "fulfilled" ? psR.value : []
      setProducts(ps)
      setDriversList(drR.status === "fulfilled" ? drR.value.filter((d) => d.isActive) : [])
      setRoutesList(rtR.status === "fulfilled" ? rtR.value.filter((r) => r.isActive) : [])
      setCustomersList(cuR.status === "fulfilled" ? cuR.value : [])
      if (!loadForm.genericProductId && ps.length > 0) {
        const first = ps.find((p) => p.isActive) ?? ps[0]
        if (first) setLoadForm((f) => ({ ...f, genericProductId: first.genericProductId, unitPrice: first.sellingPrice || 0 }))
      }
    } catch (e: any) {
      toast({ title: "Could not load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  // --- GPS + search helpers ---
  function pickGps(field: "startPoint" | "destination") {
    if (!navigator.geolocation) { toast({ title: "Geolocation not supported", variant: "destructive" }); return }
    setLocating(true)
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const { latitude, longitude } = pos.coords
        let name = `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`
        try {
          const res = await fetch(`https://nominatim.openstreetmap.org/reverse?lat=${latitude}&lon=${longitude}&format=json&zoom=16`)
          const data = await res.json()
          if (data.display_name) name = data.display_name
        } catch {}
        setLoadForm((f) => ({ ...f, [field]: name }))
        setLocating(false)
      },
      (err) => { toast({ title: "Could not get location", description: err.message, variant: "destructive" }); setLocating(false) },
      { enableHighAccuracy: true, timeout: 10000 }
    )
  }

  async function searchPlace(field: "startPoint" | "destination") {
    const query = field === "startPoint" ? loadForm.startPoint : loadForm.destination
    if (!query.trim()) { toast({ title: "Type a location name first", variant: "destructive" }); return }
    setLocating(true)
    try {
      const res = await fetch(`https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&limit=1`)
      const data = await res.json()
      if (data[0]) {
        setLoadForm((f) => ({ ...f, [field]: data[0].display_name }))
      } else {
        toast({ title: "Location not found", description: `Could not find "${query}".`, variant: "destructive" })
      }
    } catch { toast({ title: "Search failed", variant: "destructive" }) }
    setLocating(false)
  }

  // --- Delivery actions ---
  async function doLoad() {
    if (!loadForm.genericProductId) { toast({ title: "Pick a product", variant: "destructive" }); return }
    if (loadForm.quantityLoaded <= 0) { toast({ title: "Quantity must be > 0", variant: "destructive" }); return }
    if (!loadForm.driverName && driversList.length > 0) { toast({ title: "Select a driver", variant: "destructive" }); return }
    setSaving(true)
    try {
      await loadDelivery(loadForm)
      toast({ title: "Product loaded — stock reduced" })
      setLoadOpen(false)
      setLoadForm(emptyForm())
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
      toast({ title: `Sold + returned + damaged + short must equal ${recTarget.quantityLoaded}`, variant: "destructive" }); return
    }
    setSaving(true)
    try { await reconcileDelivery(recTarget.genericDeliveryId, recForm); toast({ title: "Delivery reconciled" }); setRecTarget(null); await load() }
    catch (e: any) { toast({ title: "Reconcile failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doDispatch(id: number) { try { await dispatchDelivery(id); toast({ title: "Dispatched — in transit" }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function doMarkDelivered(id: number) { try { await markDeliveryDelivered(id); toast({ title: "Marked as delivered" }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function doReverse(id: number) { try { await reverseDelivery(id); toast({ title: "Reversed" }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function doCancel(id: number) { try { await cancelDelivery(id); toast({ title: "Cancelled — stock restored" }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  // --- Filtering ---
  const filtered = useMemo(() => {
    let data = rows
    if (statusFilter !== "All") data = data.filter((d) => d.status === statusFilter)
    return filterByDateAndSearch(data, { search, dateFrom, dateTo, searchKeys: ["productName", "driverName", "customerName", "destination", "route", "transportMode"], dateKey: "deliveryDate" })
  }, [rows, statusFilter, search, dateFrom, dateTo])
  const pg = usePagination(filtered)

  // --- KPI totals ---
  const kpi = useMemo(() => {
    let total = 0, inTransit = 0, delivered = 0, sales = 0
    for (const d of rows) { total++; if (d.status === "InTransit") inTransit++; if (d.status === "Delivered") delivered++; sales += d.totalSales }
    return { total, inTransit, delivered, sales }
  }, [rows])

  // --- Selected route info ---
  const selectedRoute = routesList.find((r) => r.routeName === loadForm.route)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          {/* Header */}
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Truck className="h-5 w-5 text-emerald-600" /> Deliveries
              </h1>
              <p className="text-xs text-slate-500">Load, dispatch, track and reconcile product deliveries.</p>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" size="sm" asChild><Link href="/generic-drivers"><Users2 className="h-4 w-4 mr-1" />Drivers</Link></Button>
              <Button variant="outline" size="sm" asChild><Link href="/generic-routes"><MapPin className="h-4 w-4 mr-1" />Routes</Link></Button>
              <Button onClick={() => { setLoadForm(emptyForm()); setLoadOpen(true) }}><Plus className="h-4 w-4 mr-1" /> New Load</Button>
            </div>
          </div>

          {/* KPI tiles */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><Package className="h-3.5 w-3.5" /> Total</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{kpi.total}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><Send className="h-3.5 w-3.5" /> In Transit</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-blue-700">{kpi.inTransit}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><PackageCheck className="h-3.5 w-3.5" /> Delivered</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{kpi.delivered}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><TrendingUp className="h-3.5 w-3.5" /> Total Sales</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{gh(kpi.sales)}</div>
            </CardContent></Card>
          </div>

          {/* Status filter + search */}
          <div className="flex flex-wrap items-center gap-2">
            <div className="flex gap-1 flex-wrap">
              {["All", "Loaded", "InTransit", "Delivered", "Reconciled", "Cancelled"].map((s) => (
                <Button key={s} size="sm" variant={statusFilter === s ? "default" : "outline"} onClick={() => setStatusFilter(s)}>
                  {s === "InTransit" ? "In Transit" : s}
                  {s !== "All" && <span className="ml-1 text-xs opacity-70">({rows.filter((d) => d.status === s).length})</span>}
                </Button>
              ))}
            </div>
          </div>
          <ListFilters search={search} setSearch={setSearch} searchPlaceholder="Search product, driver, customer, route…"
            dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} />

          {/* Table */}
          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600"><Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading…</CardContent></Card>
          ) : filtered.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-slate-500">{rows.length === 0 ? "No deliveries yet. Load a product to get started." : "No deliveries match this filter."}</CardContent></Card>
          ) : (
            <Card><CardContent className="p-0 md:p-2">
              <MobileCardList defaultOpen striped stripeAccent="blue"
                items={pg.pageItems} pagination={pg.paginationProps}
                getKey={(d: any) => d.genericDeliveryId}
                primary={(d: any) => d.productName ?? `Product #${d.genericProductId}`}
                secondary={(d: any) => (<>{fmtDateTime(d.deliveryDate, d)}{d.driverName && <> · {d.driverName}</>}{d.transportMode && <> · <Badge className="bg-blue-50 text-blue-700 text-[10px] ml-1">{d.transportMode}</Badge></>}</>)}
                trailing={(d: any) => <Badge className={STATUS_COLORS[d.status] ?? "bg-slate-100"}>{d.status === "InTransit" ? "In Transit" : d.status}</Badge>}
                highlights={(d: any) => [
                  { label: "Loaded", value: `${d.quantityLoaded} ${d.unit ?? ""}`, accent: "blue" },
                  ...(d.status === "Reconciled" ? [{ label: "Sold", value: String(d.quantitySold), accent: "emerald" as const }, { label: "Sales", value: gh(d.totalSales), accent: "emerald" as const }] : []),
                ]}
                details={(d: any) => [
                  { label: "Customer", value: d.customerName ?? "—" },
                  { label: "Destination", value: d.destination ?? "—" },
                  { label: "Route", value: d.route ?? "—" },
                  { label: "Vehicle", value: d.vehicleName ?? "—" },
                  { label: "Transport", value: d.transportMode ?? "—" },
                  ...(d.deliveredAt ? [{ label: "Delivered at", value: fmtDateTime(d.deliveredAt, d) }] : []),
                  ...(d.status === "Reconciled" ? [
                    { label: "Returned", value: String(d.quantityReturned) },
                    { label: "Damaged", value: String(d.quantityDamaged) },
                    { label: "Short", value: String(d.quantityShort) },
                    { label: "Cash collected", value: gh(d.cashCollected) },
                  ] : []),
                ]}
                actions={(d: any) => (<>
                  {d.status === "Loaded" && (<>
                    <Button size="sm" variant="outline" className="flex-1 h-10 text-blue-700 border-blue-200" onClick={() => doDispatch(d.genericDeliveryId)}><Send className="h-4 w-4 mr-1" /> Dispatch</Button>
                    <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => doCancel(d.genericDeliveryId)}><XCircle className="h-4 w-4 mr-1" /> Cancel</Button>
                  </>)}
                  {d.status === "InTransit" && <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200" onClick={() => doMarkDelivered(d.genericDeliveryId)}><PackageCheck className="h-4 w-4 mr-1" /> Mark Delivered</Button>}
                  {STATUS_NOT_RECONCILED.includes(d.status) && <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={() => openReconcile(d)}><CheckCircle2 className="h-4 w-4 mr-1" /> Reconcile</Button>}
                  {d.status === "Reconciled" && <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => doReverse(d.genericDeliveryId)}><Undo2 className="h-4 w-4 mr-1" /> Reverse</Button>}
                </>)}
                desktopTable={
                  <div className="overflow-x-auto"><Table>
                    <TableHeader><TableRow>
                      <TableHead>Date</TableHead><TableHead>Product</TableHead><TableHead>Customer / Dest.</TableHead>
                      <TableHead>Driver</TableHead><TableHead>Route</TableHead><TableHead>Transport</TableHead>
                      <TableHead className="text-right">Loaded</TableHead><TableHead className="text-right">Sold</TableHead>
                      <TableHead className="text-right">Sales</TableHead><TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {pg.pageItems.map((d: any) => (
                        <TableRow key={d.genericDeliveryId}>
                          <TableCell className="whitespace-nowrap">{fmtDateTime(d.deliveryDate, d)}</TableCell>
                          <TableCell className="font-medium">{d.productName ?? "—"}</TableCell>
                          <TableCell className="max-w-[150px] truncate">{d.customerName ?? "—"}{d.destination ? ` · ${d.destination}` : ""}</TableCell>
                          <TableCell>{d.driverName ?? "—"}{d.vehicleName ? ` / ${d.vehicleName}` : ""}</TableCell>
                          <TableCell>{d.route ?? "—"}</TableCell>
                          <TableCell>{d.transportMode ? <Badge className="bg-blue-50 text-blue-700">{d.transportMode}</Badge> : "—"}</TableCell>
                          <TableCell className="text-right tabular-nums">{d.quantityLoaded} {d.unit ?? ""}</TableCell>
                          <TableCell className="text-right tabular-nums">{d.status === "Loaded" ? "—" : d.quantitySold}</TableCell>
                          <TableCell className="text-right tabular-nums">{d.status === "Loaded" ? "—" : gh(d.totalSales)}</TableCell>
                          <TableCell><Badge className={STATUS_COLORS[d.status] ?? "bg-slate-100"}>{d.status === "InTransit" ? "In Transit" : d.status}</Badge></TableCell>
                          <TableCell className="text-right whitespace-nowrap">
                            {d.status === "Loaded" && <><Button variant="ghost" size="sm" onClick={() => doDispatch(d.genericDeliveryId)} title="Dispatch"><Send className="h-4 w-4 text-blue-600" /></Button><Button variant="ghost" size="sm" onClick={() => doCancel(d.genericDeliveryId)} title="Cancel"><XCircle className="h-4 w-4 text-amber-600" /></Button></>}
                            {d.status === "InTransit" && <Button variant="ghost" size="sm" onClick={() => doMarkDelivered(d.genericDeliveryId)} title="Mark Delivered"><PackageCheck className="h-4 w-4 text-emerald-600" /></Button>}
                            {STATUS_NOT_RECONCILED.includes(d.status) && <Button variant="ghost" size="sm" onClick={() => openReconcile(d)} title="Reconcile"><CheckCircle2 className="h-4 w-4 text-green-600" /></Button>}
                            {(d.status === "InTransit" || d.status === "Delivered") && <Button variant="ghost" size="sm" onClick={() => doCancel(d.genericDeliveryId)} title="Cancel"><XCircle className="h-4 w-4 text-amber-600" /></Button>}
                            {d.status === "Reconciled" && <Button variant="ghost" size="sm" onClick={() => doReverse(d.genericDeliveryId)} title="Reverse"><Undo2 className="h-4 w-4 text-amber-600" /></Button>}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                }
              />
            </CardContent></Card>
          )}
        </main>
      </div>

      {/* ============================================================
         LOAD DIALOG — fully linked: driver → vehicle + transport,
         route → start + destination + est. time, GPS + search on both
         ============================================================ */}
      <Dialog open={loadOpen} onOpenChange={setLoadOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>Load product for delivery</DialogTitle></DialogHeader>

          {/* Product section */}
          <FormSection title="Product" color="indigo">
            <FormField label="Product *">
              <Select value={loadForm.genericProductId ? String(loadForm.genericProductId) : ""} onValueChange={(v) => {
                const id = Number(v); const p = products.find((x) => x.genericProductId === id)
                setLoadForm({ ...loadForm, genericProductId: id, unitPrice: p?.sellingPrice ?? loadForm.unitPrice })
              }}>
                <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                <SelectContent>{products.filter((p) => p.isActive).map((p) => (
                  <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>{p.productName} ({p.currentStock} in stock)</SelectItem>
                ))}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity *">
              <NumberInput min={0} step="1" value={loadForm.quantityLoaded} onChange={(e) => setLoadForm({ ...loadForm, quantityLoaded: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Unit">
              <Select value={loadForm.unit} onValueChange={(v) => setLoadForm({ ...loadForm, unit: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{UNITS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Unit price">
              <NumberInput min={0} step="0.01" value={loadForm.unitPrice} onChange={(e) => setLoadForm({ ...loadForm, unitPrice: Number(e.target.value) || 0 })} />
            </FormField>
          </FormSection>

          {/* Driver + Transport section */}
          <FormSection title="Driver & Transport" color="blue">
            <FormField label="Driver *">
              {driversList.length > 0 ? (
                <Select value={loadForm.driverName} onValueChange={(v) => {
                  const dr = driversList.find((d) => d.driverName === v)
                  setLoadForm({ ...loadForm, driverName: v, vehicleName: dr?.vehicleName ?? "", transportMode: dr?.transportMode ?? "Car" })
                }}>
                  <SelectTrigger><SelectValue placeholder="Select driver" /></SelectTrigger>
                  <SelectContent>{driversList.map((d) => (
                    <SelectItem key={d.genericDriverId} value={d.driverName}>{d.driverName}{d.transportMode ? ` (${d.transportMode})` : ""}</SelectItem>
                  ))}</SelectContent>
                </Select>
              ) : (
                <div className="space-y-1">
                  <Input value={loadForm.driverName} onChange={(e) => setLoadForm({ ...loadForm, driverName: e.target.value })} placeholder="Type driver name" />
                  <p className="text-xs text-slate-400">No drivers set up. <Link href="/generic-drivers" className="text-emerald-600 underline">Add drivers</Link></p>
                </div>
              )}
            </FormField>
            <FormField label="Vehicle">
              <Input value={loadForm.vehicleName} onChange={(e) => setLoadForm({ ...loadForm, vehicleName: e.target.value })} />
            </FormField>
            <FormField label="Transport mode">
              <Select value={loadForm.transportMode} onValueChange={(v) => setLoadForm({ ...loadForm, transportMode: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{TRANSPORT_MODES.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
          </FormSection>

          {/* Route + Destination section */}
          <FormSection title="Route & Destination" color="emerald">
            <FormField label="Route">
              {routesList.length > 0 ? (
                <Select value={loadForm.route} onValueChange={(v) => {
                  const rt = routesList.find((r) => r.routeName === v)
                  setLoadForm({ ...loadForm, route: v, startPoint: rt?.startPoint ?? loadForm.startPoint, destination: rt?.endPoint ?? loadForm.destination })
                }}>
                  <SelectTrigger><SelectValue placeholder="Select delivery route" /></SelectTrigger>
                  <SelectContent>{routesList.map((r) => (
                    <SelectItem key={r.genericRouteId} value={r.routeName}>
                      {r.routeName}{r.startPoint && r.endPoint ? ` (${r.startPoint} → ${r.endPoint})` : ""}
                    </SelectItem>
                  ))}</SelectContent>
                </Select>
              ) : (
                <div className="space-y-1">
                  <Input value={loadForm.route} onChange={(e) => setLoadForm({ ...loadForm, route: e.target.value })} placeholder="Type route name" />
                  <p className="text-xs text-slate-400">No routes set up. <Link href="/generic-routes" className="text-emerald-600 underline">Add routes</Link></p>
                </div>
              )}
              {selectedRoute?.estimatedTime && (
                <p className="text-xs text-emerald-600 mt-1">Est. time: {selectedRoute.estimatedTime}</p>
              )}
            </FormField>
            <FormField label="Starting point">
              <div className="flex gap-1">
                <Input className="flex-1" value={loadForm.startPoint} onChange={(e) => setLoadForm({ ...loadForm, startPoint: e.target.value })} placeholder="Where you're leaving from" />
                <Button type="button" variant="outline" size="icon" className="shrink-0" disabled={locating} onClick={() => pickGps("startPoint")} title="My location">
                  {locating ? <Loader2 className="h-4 w-4 animate-spin" /> : <LocateFixed className="h-4 w-4" />}
                </Button>
                <Button type="button" variant="outline" size="icon" className="shrink-0" disabled={locating} onClick={() => searchPlace("startPoint")} title="Search">
                  <Search className="h-4 w-4" />
                </Button>
              </div>
            </FormField>
            <FormField label="Destination">
              <div className="flex gap-1">
                <Input className="flex-1" value={loadForm.destination} onChange={(e) => setLoadForm({ ...loadForm, destination: e.target.value })} placeholder="Where you're delivering to" />
                <Button type="button" variant="outline" size="icon" className="shrink-0" disabled={locating} onClick={() => searchPlace("destination")} title="Search">
                  {locating ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
                </Button>
                <Button type="button" variant="outline" size="icon" className="shrink-0" disabled={locating} onClick={() => pickGps("destination")} title="My location">
                  <LocateFixed className="h-4 w-4" />
                </Button>
              </div>
            </FormField>
            <FormField label="Customer">
              {customersList.length > 0 ? (
                <Select value={loadForm.customerName} onValueChange={(v) => setLoadForm({ ...loadForm, customerName: v })}>
                  <SelectTrigger><SelectValue placeholder="Select customer (optional)" /></SelectTrigger>
                  <SelectContent>{customersList.filter((c) => c.isActive !== false).map((c) => (
                    <SelectItem key={c.genericCustomerId} value={c.customerName}>{c.customerName}</SelectItem>
                  ))}</SelectContent>
                </Select>
              ) : (
                <Input value={loadForm.customerName} onChange={(e) => setLoadForm({ ...loadForm, customerName: e.target.value })} placeholder="Who is this for?" />
              )}
            </FormField>
          </FormSection>

          {/* Date + Notes */}
          <FormSection title="Other" color="slate">
            <FormField label="Date">
              <Input type="date" value={loadForm.deliveryDate} onChange={(e) => setLoadForm({ ...loadForm, deliveryDate: e.target.value })} />
            </FormField>
            <FormField label="Notes">
              <Input value={loadForm.notes} onChange={(e) => setLoadForm({ ...loadForm, notes: e.target.value })} />
            </FormField>
          </FormSection>

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setLoadOpen(false)}>Cancel</Button>
            <Button onClick={doLoad} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Load & Create Delivery"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reconcile dialog */}
      <Dialog open={!!recTarget} onOpenChange={(o) => !o && setRecTarget(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>Reconcile — {recTarget?.productName} ({recTarget?.quantityLoaded} {recTarget?.unit ?? ""} loaded)</DialogTitle></DialogHeader>
          {recTarget && (<>
            <div className="rounded-lg bg-slate-50 p-3 text-sm text-slate-600 space-y-1">
              <p><strong>Driver:</strong> {recTarget.driverName ?? "—"} · <strong>Route:</strong> {recTarget.route ?? "—"} · <strong>Transport:</strong> {recTarget.transportMode ?? "—"}</p>
              <p><strong>Customer:</strong> {recTarget.customerName ?? "—"} · <strong>Destination:</strong> {recTarget.destination ?? "—"}</p>
            </div>
            <FormSection title="Product accounting" color="blue">
              <FormField label="Sold"><NumberInput min={0} step="1" value={recForm.quantitySold} onChange={(e) => setRecForm({ ...recForm, quantitySold: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="Returned"><NumberInput min={0} step="1" value={recForm.quantityReturned} onChange={(e) => setRecForm({ ...recForm, quantityReturned: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="Damaged"><NumberInput min={0} step="1" value={recForm.quantityDamaged} onChange={(e) => setRecForm({ ...recForm, quantityDamaged: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="Short / missing"><NumberInput min={0} step="1" value={recForm.quantityShort} onChange={(e) => setRecForm({ ...recForm, quantityShort: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="" full>
                <p className={cn("text-sm font-medium", Math.abs(recAccounted - recTarget.quantityLoaded) < 0.001 ? "text-green-600" : "text-red-600")}>
                  Accounted: {recAccounted} / {recTarget.quantityLoaded} loaded {Math.abs(recAccounted - recTarget.quantityLoaded) < 0.001 ? "— balances" : "— must balance"}
                </p>
              </FormField>
            </FormSection>
            <FormSection title="Money" color="emerald">
              <FormField label="Cash collected"><NumberInput min={0} step="0.01" value={recForm.cashCollected} onChange={(e) => setRecForm({ ...recForm, cashCollected: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="Credit sales"><NumberInput min={0} step="0.01" value={recForm.creditSales} onChange={(e) => setRecForm({ ...recForm, creditSales: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="Delivery expenses"><NumberInput min={0} step="0.01" value={recForm.deliveryExpenses} onChange={(e) => setRecForm({ ...recForm, deliveryExpenses: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="Expected sales (auto)">
                <Input readOnly tabIndex={-1} className="bg-slate-100 pointer-events-none" value={gh(recForm.quantitySold * recTarget.unitPrice)} />
              </FormField>
            </FormSection>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setRecTarget(null)}>Cancel</Button>
              <Button onClick={doReconcile} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Reconcile"}</Button>
            </div>
          </>)}
        </DialogContent>
      </Dialog>
    </div>
  )
}

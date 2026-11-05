"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Building2, Plus, Loader2, TrendingDown, XCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { getAssets, createAsset, disposeAsset, depreciateAsset, type GenericAsset } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const CATEGORIES = ["Vehicle", "Equipment", "Furniture", "Building", "Land", "Technology", "Other"]
const STATUS_COLORS: Record<string, string> = { Active: "bg-emerald-100 text-emerald-700", Disposed: "bg-amber-100 text-amber-700" }

export default function GenericAssetsPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [rows, setRows] = useState<GenericAsset[]>([])
  const [loading, setLoading] = useState(true)
  const [createOpen, setCreateOpen] = useState(false)
  const [disposeTarget, setDisposeTarget] = useState<GenericAsset | null>(null)
  const [depTarget, setDepTarget] = useState<GenericAsset | null>(null)
  const [saving, setSaving] = useState(false)

  const [form, setForm] = useState({
    assetName: "", category: "Equipment", purchaseDate: new Date().toISOString().split("T")[0],
    purchaseCost: 0, usefulLifeMonths: 60, depreciationMethod: "StraightLine",
    location: "", serialNumber: "", notes: "",
  })
  const [dispForm, setDispForm] = useState({ disposalDate: new Date().toISOString().split("T")[0], disposalAmount: 0 })
  const [depAmount, setDepAmount] = useState(0)

  const pg = usePagination(rows)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setRows(await getAssets()) }
    catch (e: any) { toast({ title: "Could not load assets", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const totals = useMemo(() => {
    let cost = 0, value = 0, dep = 0, active = 0
    for (const a of rows) { cost += a.purchaseCost; value += a.currentValue; dep += a.totalDepreciation; if (a.status === "Active") active++ }
    return { cost, value, dep, active }
  }, [rows])

  async function doCreate() {
    if (!form.assetName.trim()) { toast({ title: "Asset name required", variant: "destructive" }); return }
    if (form.purchaseCost <= 0) { toast({ title: "Cost must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createAsset(form)
      toast({ title: "Asset registered" })
      setCreateOpen(false)
      setForm({ assetName: "", category: "Equipment", purchaseDate: new Date().toISOString().split("T")[0], purchaseCost: 0, usefulLifeMonths: 60, depreciationMethod: "StraightLine", location: "", serialNumber: "", notes: "" })
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doDispose() {
    if (!disposeTarget) return
    setSaving(true)
    try {
      await disposeAsset(disposeTarget.genericAssetId, dispForm)
      toast({ title: "Asset disposed" })
      setDisposeTarget(null)
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doDepreciate() {
    if (!depTarget || depAmount <= 0) return
    setSaving(true)
    try {
      await depreciateAsset(depTarget.genericAssetId, depAmount)
      toast({ title: "Depreciation recorded" })
      setDepTarget(null); setDepAmount(0)
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Building2 className="h-5 w-5 text-emerald-600" /> Capital Investments / Assets
              </h1>
              <p className="text-xs text-slate-500">Track business assets, depreciation and disposals.</p>
            </div>
            <Button onClick={() => setCreateOpen(true)}><Plus className="h-4 w-4 mr-1" /> New Asset</Button>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <Card><CardContent className="p-3"><div className="text-[11px] uppercase tracking-wide text-slate-500">Total Cost</div><div className="mt-1 text-lg font-semibold tabular-nums">{gh(totals.cost)}</div></CardContent></Card>
            <Card><CardContent className="p-3"><div className="text-[11px] uppercase tracking-wide text-slate-500">Current Value</div><div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{gh(totals.value)}</div></CardContent></Card>
            <Card><CardContent className="p-3"><div className="text-[11px] uppercase tracking-wide text-slate-500">Total Depreciation</div><div className="mt-1 text-lg font-semibold tabular-nums text-red-700">{gh(totals.dep)}</div></CardContent></Card>
            <Card><CardContent className="p-3"><div className="text-[11px] uppercase tracking-wide text-slate-500">Active Assets</div><div className="mt-1 text-lg font-semibold tabular-nums">{totals.active}</div></CardContent></Card>
          </div>

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600"><Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading…</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0 md:p-2">
                <MobileCardList
                  defaultOpen striped stripeAccent="blue"
                  items={pg.pageItems} pagination={pg.paginationProps}
                  getKey={(a: any) => a.genericAssetId}
                  primary={(a: any) => a.assetName}
                  secondary={(a: any) => `${a.category ?? "—"} · ${fmtDateTime(a.purchaseDate, a)}`}
                  trailing={(a: any) => <Badge className={STATUS_COLORS[a.status] ?? "bg-slate-100"}>{a.status}</Badge>}
                  highlights={(a: any) => [
                    { label: "Cost", value: gh(a.purchaseCost), accent: "blue" },
                    { label: "Value", value: gh(a.currentValue), accent: "emerald" },
                  ]}
                  details={(a: any) => [
                    { label: "Depreciation", value: gh(a.totalDepreciation) },
                    { label: "Method", value: a.depreciationMethod ?? "—" },
                    { label: "Useful life", value: a.usefulLifeMonths ? `${a.usefulLifeMonths} months` : "—" },
                    { label: "Location", value: a.location ?? "—" },
                    { label: "Serial #", value: a.serialNumber ?? "—" },
                  ]}
                  actions={(a: any) => (
                    <>
                      {a.status === "Active" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => { setDepTarget(a); setDepAmount(a.usefulLifeMonths ? Math.round(a.purchaseCost / a.usefulLifeMonths * 100) / 100 : 0) }}>
                            <TrendingDown className="h-4 w-4 mr-1" /> Depreciate
                          </Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => { setDisposeTarget(a); setDispForm({ disposalDate: new Date().toISOString().split("T")[0], disposalAmount: a.currentValue }) }}>
                            <XCircle className="h-4 w-4 mr-1" /> Dispose
                          </Button>
                        </>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader><TableRow>
                          <TableHead>Name</TableHead><TableHead>Category</TableHead><TableHead>Date</TableHead>
                          <TableHead className="text-right">Cost</TableHead><TableHead className="text-right">Value</TableHead>
                          <TableHead className="text-right">Depreciation</TableHead><TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow></TableHeader>
                        <TableBody>
                          {rows.length === 0 ? (
                            <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-6">No assets registered.</TableCell></TableRow>
                          ) : pg.pageItems.map((a: any) => (
                            <TableRow key={a.genericAssetId}>
                              <TableCell className="font-medium">{a.assetName}</TableCell>
                              <TableCell>{a.category ?? "—"}</TableCell>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(a.purchaseDate, a)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(a.purchaseCost)}</TableCell>
                              <TableCell className="text-right tabular-nums text-emerald-700">{gh(a.currentValue)}</TableCell>
                              <TableCell className="text-right tabular-nums text-red-600">{gh(a.totalDepreciation)}</TableCell>
                              <TableCell><Badge className={STATUS_COLORS[a.status] ?? "bg-slate-100"}>{a.status}</Badge></TableCell>
                              <TableCell className="text-right whitespace-nowrap">
                                {a.status === "Active" && (
                                  <>
                                    <Button size="sm" variant="ghost" onClick={() => { setDepTarget(a); setDepAmount(a.usefulLifeMonths ? Math.round(a.purchaseCost / a.usefulLifeMonths * 100) / 100 : 0) }} title="Depreciate"><TrendingDown className="h-4 w-4 text-blue-600" /></Button>
                                    <Button size="sm" variant="ghost" onClick={() => { setDisposeTarget(a); setDispForm({ disposalDate: new Date().toISOString().split("T")[0], disposalAmount: a.currentValue }) }} title="Dispose"><XCircle className="h-4 w-4 text-amber-600" /></Button>
                                  </>
                                )}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  }
                />
              </CardContent>
            </Card>
          )}
        </main>
      </div>

      {/* Create */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-lg"><DialogHeader><DialogTitle>Register a new asset</DialogTitle></DialogHeader>
          <FormSection title="Asset details" color="indigo">
            <FormField label="Name *"><Input value={form.assetName} onChange={(e) => setForm({ ...form, assetName: e.target.value })} /></FormField>
            <FormField label="Category">
              <Select value={form.category} onValueChange={(v) => setForm({ ...form, category: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{CATEGORIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Purchase date"><Input type="date" value={form.purchaseDate} onChange={(e) => setForm({ ...form, purchaseDate: e.target.value })} /></FormField>
            <FormField label="Purchase cost *"><NumberInput min={0} step="0.01" value={form.purchaseCost} onChange={(e) => setForm({ ...form, purchaseCost: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Useful life (months)"><NumberInput min={0} step="1" value={form.usefulLifeMonths} onChange={(e) => setForm({ ...form, usefulLifeMonths: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Location"><Input value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} /></FormField>
            <FormField label="Serial number"><Input value={form.serialNumber} onChange={(e) => setForm({ ...form, serialNumber: e.target.value })} /></FormField>
            <FormField label="Notes"><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
            <Button onClick={doCreate} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Register"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Depreciate */}
      <Dialog open={!!depTarget} onOpenChange={(o) => !o && setDepTarget(null)}>
        <DialogContent className="max-w-sm"><DialogHeader><DialogTitle>Depreciate — {depTarget?.assetName}</DialogTitle></DialogHeader>
          {depTarget && (
            <>
              <p className="text-sm text-slate-600">Current value: <strong>{gh(depTarget.currentValue)}</strong></p>
              <FormField label="Depreciation amount"><NumberInput min={0} step="0.01" value={depAmount} onChange={(e) => setDepAmount(Number(e.target.value) || 0)} /></FormField>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setDepTarget(null)}>Cancel</Button>
                <Button onClick={doDepreciate} disabled={saving || depAmount <= 0}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Record"}</Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>

      {/* Dispose */}
      <Dialog open={!!disposeTarget} onOpenChange={(o) => !o && setDisposeTarget(null)}>
        <DialogContent className="max-w-sm"><DialogHeader><DialogTitle>Dispose — {disposeTarget?.assetName}</DialogTitle></DialogHeader>
          {disposeTarget && (
            <>
              <p className="text-sm text-slate-600">Current value: <strong>{gh(disposeTarget.currentValue)}</strong></p>
              <FormField label="Disposal date"><Input type="date" value={dispForm.disposalDate} onChange={(e) => setDispForm({ ...dispForm, disposalDate: e.target.value })} /></FormField>
              <FormField label="Sale / disposal amount"><NumberInput min={0} step="0.01" value={dispForm.disposalAmount} onChange={(e) => setDispForm({ ...dispForm, disposalAmount: Number(e.target.value) || 0 })} /></FormField>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setDisposeTarget(null)}>Cancel</Button>
                <Button onClick={doDispose} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Dispose Asset"}</Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

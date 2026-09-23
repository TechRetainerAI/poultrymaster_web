"use client"
import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Plus, Play, RotateCcw, Eye, XCircle, Calendar } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelAssets, createHotelAsset, activateHotelAsset, disposeHotelAsset, reverseHotelAsset,
  getHotelAssetSummary, listHotelAssetCategories, generateHotelDepreciation,
  type HotelCapitalAsset, type HotelCapitalAssetSummary, type HotelAssetCategory, type HotelDepreciationRunResult,
} from "@/lib/api/hotel-assets"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700", Active: "bg-blue-100 text-blue-700",
  FullyDepreciated: "bg-amber-100 text-amber-700", Disposed: "bg-purple-100 text-purple-700",
  Reversed: "bg-red-100 text-red-700",
}

function todayLocal(): string { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export default function HotelAssetsPage() {
  const router = useRouter(); const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [assets, setAssets] = useState<HotelCapitalAsset[]>([])
  const [categories, setCategories] = useState<HotelAssetCategory[]>([])
  const [summary, setSummary] = useState<HotelCapitalAssetSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState("ALL")
  const [search, setSearch] = useState("")

  const [createOpen, setCreateOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({
    assetName: "", hotelAssetCategoryId: null as number | null,
    acquisitionDate: todayLocal(), inServiceDate: "", residualValue: 0,
    usefulLifeMonths: 60, amount: 0, supplier: "", location: "", serialNumber: "", notes: "",
  })

  const [reasonOpen, setReasonOpen] = useState(false)
  const [reasonAction, setReasonAction] = useState<"dispose" | "reverse">("dispose")
  const [reasonTarget, setReasonTarget] = useState<HotelCapitalAsset | null>(null)
  const [reason, setReason] = useState("")
  const [disposalDate, setDisposalDate] = useState(todayLocal())

  const [depRunning, setDepRunning] = useState(false)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try { const [a, c, s] = await Promise.all([listHotelAssets(), listHotelAssetCategories(), getHotelAssetSummary()]); setAssets(a); setCategories(c); setSummary(s) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function saveCreate() {
    if (!form.assetName.trim()) { toast({ title: "Asset name required", variant: "destructive" }); return }
    setSaving(true)
    try { await createHotelAsset({ ...form, farmId: "" }); toast({ title: "Asset created as Draft" }); setCreateOpen(false); await load() }
    catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doActivate(id: number) {
    try { await activateHotelAsset(id); toast({ title: "Asset activated" }); await load() }
    catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
  }

  function openReason(action: "dispose" | "reverse", target: HotelCapitalAsset) {
    setReasonAction(action); setReasonTarget(target); setReason(""); setDisposalDate(todayLocal()); setReasonOpen(true)
  }

  async function submitReason() {
    if (!reasonTarget) return
    try {
      if (reasonAction === "dispose") await disposeHotelAsset(reasonTarget.hotelCapitalAssetId, disposalDate, reason)
      else await reverseHotelAsset(reasonTarget.hotelCapitalAssetId, reason)
      toast({ title: reasonAction === "dispose" ? "Asset disposed" : "Asset reversed" })
      setReasonOpen(false); await load()
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
  }

  async function runDepreciation() {
    setDepRunning(true)
    try {
      const result = await generateHotelDepreciation(todayLocal())
      toast({ title: `Depreciation complete: ${result.entriesCreated} entries, ${fmt(result.totalAmount)} charged across ${result.assetsProcessed} assets` })
      await load()
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setDepRunning(false) }
  }

  const filtered = useMemo(() => {
    let list = assets
    if (statusFilter !== "ALL") list = list.filter(a => a.status === statusFilter)
    if (search) { const s = search.toLowerCase(); list = list.filter(a => a.assetName.toLowerCase().includes(s) || (a.assetNumber || "").toLowerCase().includes(s)) }
    return list
  }, [assets, statusFilter, search])

  const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  const fmtDate = (s?: string | null) => s ? new Date(s).toLocaleDateString() : "—"

  if (loading) return (<div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader /><div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-muted-foreground" /></div></div></div>)

  return (
    <div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 md:p-6 space-y-6">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <h1 className="text-2xl font-bold">Capital Assets</h1>
          <div className="flex gap-2">
            <Button variant="outline" onClick={runDepreciation} disabled={depRunning}>
              {depRunning ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Calendar className="h-4 w-4 mr-2" />}Run Depreciation
            </Button>
            <Button onClick={() => { setForm({ assetName: "", hotelAssetCategoryId: null, acquisitionDate: todayLocal(), inServiceDate: "", residualValue: 0, usefulLifeMonths: 60, amount: 0, supplier: "", location: "", serialNumber: "", notes: "" }); setCreateOpen(true) }}>
              <Plus className="h-4 w-4 mr-2" />New Asset
            </Button>
          </div>
        </div>

        {summary && (<div className="grid grid-cols-1 sm:grid-cols-3 lg:grid-cols-6 gap-4">
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Total Assets</p><p className="text-2xl font-bold">{summary.totalAssets}</p></CardContent></Card>
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Active</p><p className="text-2xl font-bold text-blue-600">{summary.activeAssets}</p></CardContent></Card>
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Draft</p><p className="text-2xl font-bold text-slate-600">{summary.draftAssets}</p></CardContent></Card>
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Total Cost</p><p className="text-2xl font-bold">{fmt(summary.totalAssetCost)}</p></CardContent></Card>
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Depreciation</p><p className="text-2xl font-bold text-amber-600">{fmt(summary.accumulatedDepreciation)}</p></CardContent></Card>
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Book Value</p><p className="text-2xl font-bold text-emerald-600">{fmt(summary.currentBookValue)}</p></CardContent></Card>
        </div>)}

        <div className="flex gap-4 flex-wrap">
          <Select value={statusFilter} onValueChange={setStatusFilter}><SelectTrigger className="w-44"><SelectValue /></SelectTrigger><SelectContent>
            <SelectItem value="ALL">All</SelectItem><SelectItem value="Draft">Draft</SelectItem><SelectItem value="Active">Active</SelectItem>
            <SelectItem value="FullyDepreciated">Fully Depreciated</SelectItem><SelectItem value="Disposed">Disposed</SelectItem><SelectItem value="Reversed">Reversed</SelectItem>
          </SelectContent></Select>
          <Input placeholder="Search by name or number..." value={search} onChange={(e) => setSearch(e.target.value)} className="max-w-xs" />
        </div>

        <Card><CardContent className="p-0"><div className="overflow-x-auto"><table className="w-full text-sm">
          <thead><tr className="border-b bg-muted/50">
            <th className="text-left p-3">Asset #</th><th className="text-left p-3">Name</th><th className="text-left p-3">Category</th>
            <th className="text-right p-3">Cost</th><th className="text-right p-3">Depreciation</th><th className="text-right p-3">Book Value</th>
            <th className="text-center p-3">Status</th><th className="text-right p-3">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.length === 0 && <tr><td colSpan={8} className="text-center p-8 text-muted-foreground">No assets found</td></tr>}
            {filtered.map(a => (
              <tr key={a.hotelCapitalAssetId} className="border-b hover:bg-muted/30">
                <td className="p-3 font-mono text-sm">{a.assetNumber || "—"}</td>
                <td className="p-3 font-medium">{a.assetName}</td>
                <td className="p-3">{a.categoryName || "—"}</td>
                <td className="p-3 text-right font-mono">{fmt(a.totalCapitalizedCost)}</td>
                <td className="p-3 text-right font-mono text-amber-600">{fmt(a.accumulatedDepreciation)}</td>
                <td className="p-3 text-right font-mono font-semibold">{fmt(a.currentBookValue)}</td>
                <td className="p-3 text-center"><Badge className={STATUS_COLORS[a.status] || ""}>{a.status}</Badge></td>
                <td className="p-3 text-right space-x-1">
                  <Button size="sm" variant="ghost" onClick={() => router.push(`/hotel-assets/${a.hotelCapitalAssetId}`)}><Eye className="h-4 w-4" /></Button>
                  {a.status === "Draft" && <Button size="sm" variant="outline" onClick={() => doActivate(a.hotelCapitalAssetId)}><Play className="h-4 w-4 mr-1" />Activate</Button>}
                  {(a.status === "Active" || a.status === "FullyDepreciated") && <Button size="sm" variant="ghost" onClick={() => openReason("dispose", a)}><XCircle className="h-4 w-4 text-purple-500" /></Button>}
                  {a.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => openReason("reverse", a)}><RotateCcw className="h-4 w-4 text-red-500" /></Button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table></div></CardContent></Card>

        {/* Create Dialog */}
        <Dialog open={createOpen} onOpenChange={setCreateOpen}><DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>New Capital Asset</DialogTitle><DialogDescription>Register a new fixed asset. It starts as Draft.</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <FormField label="Asset Name *"><Input value={form.assetName} onChange={(e) => setForm({ ...form, assetName: e.target.value })} /></FormField>
            <FormField label="Category"><Select value={form.hotelAssetCategoryId ? String(form.hotelAssetCategoryId) : "none"} onValueChange={(v) => {
              const catId = v === "none" ? null : Number(v)
              const cat = categories.find(c => c.hotelAssetCategoryId === catId)
              setForm({ ...form, hotelAssetCategoryId: catId, usefulLifeMonths: cat?.defaultUsefulLifeMonths ?? form.usefulLifeMonths })
            }}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>
              <SelectItem value="none">Uncategorized</SelectItem>
              {categories.filter(c => c.isActive).map(c => <SelectItem key={c.hotelAssetCategoryId} value={String(c.hotelAssetCategoryId)}>{c.categoryName}</SelectItem>)}
            </SelectContent></Select></FormField>
            <FormField label="Acquisition Date"><Input type="date" value={form.acquisitionDate} onChange={(e) => setForm({ ...form, acquisitionDate: e.target.value })} /></FormField>
            <FormField label="In-Service Date"><Input type="date" value={form.inServiceDate} onChange={(e) => setForm({ ...form, inServiceDate: e.target.value })} /></FormField>
            <FormField label="Acquisition Cost"><Input type="number" step="0.01" value={form.amount || ""} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) })} /></FormField>
            <FormField label="Residual Value"><Input type="number" step="0.01" value={form.residualValue || ""} onChange={(e) => setForm({ ...form, residualValue: Number(e.target.value) })} /></FormField>
            <FormField label="Useful Life (Months)"><Input type="number" value={form.usefulLifeMonths} onChange={(e) => setForm({ ...form, usefulLifeMonths: Number(e.target.value) })} /></FormField>
            <FormField label="Supplier"><Input value={form.supplier} onChange={(e) => setForm({ ...form, supplier: e.target.value })} /></FormField>
            <FormField label="Location"><Input value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} /></FormField>
            <FormField label="Serial Number"><Input value={form.serialNumber} onChange={(e) => setForm({ ...form, serialNumber: e.target.value })} /></FormField>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button><Button onClick={saveCreate} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Create</Button></DialogFooter>
        </DialogContent></Dialog>

        {/* Reason Dialog */}
        <Dialog open={reasonOpen} onOpenChange={setReasonOpen}><DialogContent>
          <DialogHeader><DialogTitle>{reasonAction === "dispose" ? "Dispose Asset" : "Reverse Asset"}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            {reasonAction === "dispose" && <FormField label="Disposal Date"><Input type="date" value={disposalDate} onChange={(e) => setDisposalDate(e.target.value)} /></FormField>}
            <FormField label="Reason"><Textarea value={reason} onChange={(e) => setReason(e.target.value)} /></FormField>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setReasonOpen(false)}>Cancel</Button><Button variant="destructive" onClick={submitReason}>Confirm</Button></DialogFooter>
        </DialogContent></Dialog>
      </main>
    </div></div>
  )
}

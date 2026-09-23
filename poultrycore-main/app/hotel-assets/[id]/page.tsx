"use client"
import { useEffect, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormField } from "@/components/ui/form-section"
import { Loader2, ArrowLeft, Plus, RotateCcw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  getHotelAsset, getHotelAssetCosts, addHotelAssetCost, reverseHotelAssetCost,
  listHotelDepreciation, reverseHotelDepreciation,
  type HotelCapitalAsset, type HotelCapitalAssetCost, type HotelAssetDepreciation,
} from "@/lib/api/hotel-assets"

const STATUS_COLORS: Record<string, string> = { Draft: "bg-slate-100 text-slate-700", Active: "bg-blue-100 text-blue-700", FullyDepreciated: "bg-amber-100 text-amber-700", Disposed: "bg-purple-100 text-purple-700", Reversed: "bg-red-100 text-red-700", Posted: "bg-emerald-100 text-emerald-700" }

function todayLocal(): string { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export default function HotelAssetDetailPage() {
  const router = useRouter(); const params = useParams(); const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const assetId = Number(params.id)

  const [asset, setAsset] = useState<HotelCapitalAsset | null>(null)
  const [costs, setCosts] = useState<HotelCapitalAssetCost[]>([])
  const [depreciation, setDepreciation] = useState<HotelAssetDepreciation[]>([])
  const [loading, setLoading] = useState(true)

  const [costOpen, setCostOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [costForm, setCostForm] = useState({ amount: 0, description: "", costDate: todayLocal() })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, assetId])

  async function load() {
    setLoading(true)
    try {
      const [a, c, d] = await Promise.all([getHotelAsset(assetId), getHotelAssetCosts(assetId), listHotelDepreciation(assetId)])
      setAsset(a); setCosts(c); setDepreciation(d)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function saveCost() {
    if (costForm.amount <= 0) { toast({ title: "Amount required", variant: "destructive" }); return }
    setSaving(true)
    try { await addHotelAssetCost(assetId, costForm.amount, costForm.description, costForm.costDate); toast({ title: "Cost added" }); setCostOpen(false); await load() }
    catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doReverseCost(costId: number) {
    try { await reverseHotelAssetCost(assetId, costId); toast({ title: "Cost reversed" }); await load() }
    catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
  }

  async function doReverseDep(entryId: number) {
    try { await reverseHotelDepreciation(entryId); toast({ title: "Depreciation reversed" }); await load() }
    catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
  }

  const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  const fmtDate = (s?: string | null) => s ? new Date(s).toLocaleDateString() : "—"

  if (loading) return (<div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader /><div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-muted-foreground" /></div></div></div>)
  if (!asset) return (<div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader /><div className="flex-1 flex items-center justify-center text-muted-foreground">Asset not found</div></div></div>)

  const monthlyDep = asset.usefulLifeMonths > 0 ? (asset.totalCapitalizedCost - asset.residualValue) / asset.usefulLifeMonths : 0

  return (
    <div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 md:p-6 space-y-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="sm" onClick={() => router.push("/hotel-assets")}><ArrowLeft className="h-4 w-4 mr-2" />Back</Button>
          <h1 className="text-2xl font-bold">{asset.assetName}</h1>
          <Badge className={STATUS_COLORS[asset.status] || ""}>{asset.status}</Badge>
        </div>

        {/* Info Cards */}
        <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-6 gap-4">
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Asset #</p><p className="font-mono">{asset.assetNumber || "—"}</p></CardContent></Card>
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Category</p><p>{asset.categoryName || "—"}</p></CardContent></Card>
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Total Cost</p><p className="font-bold">{fmt(asset.totalCapitalizedCost)}</p></CardContent></Card>
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Accumulated Dep.</p><p className="text-amber-600">{fmt(asset.accumulatedDepreciation)}</p></CardContent></Card>
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Book Value</p><p className="font-bold text-emerald-600">{fmt(asset.currentBookValue)}</p></CardContent></Card>
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Monthly Dep.</p><p>{fmt(Math.max(monthlyDep, 0))}</p></CardContent></Card>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
          <div><span className="text-muted-foreground">Acquisition Date:</span> {fmtDate(asset.acquisitionDate)}</div>
          <div><span className="text-muted-foreground">In-Service Date:</span> {fmtDate(asset.inServiceDate)}</div>
          <div><span className="text-muted-foreground">Residual Value:</span> {fmt(asset.residualValue)}</div>
          <div><span className="text-muted-foreground">Useful Life:</span> {asset.usefulLifeMonths} months</div>
        </div>

        {/* Costs */}
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold">Cost Entries</h2>
          {(asset.status === "Draft" || asset.status === "Active") && (
            <Button size="sm" onClick={() => { setCostForm({ amount: 0, description: "", costDate: todayLocal() }); setCostOpen(true) }}><Plus className="h-4 w-4 mr-1" />Add Cost</Button>
          )}
        </div>
        <Card><CardContent className="p-0"><div className="overflow-x-auto"><table className="w-full text-sm">
          <thead><tr className="border-b bg-muted/50">
            <th className="text-left p-3">Date</th><th className="text-left p-3">Type</th><th className="text-left p-3">Description</th>
            <th className="text-right p-3">Amount</th><th className="text-center p-3">Status</th><th className="text-right p-3"></th>
          </tr></thead>
          <tbody>
            {costs.length === 0 && <tr><td colSpan={6} className="text-center p-6 text-muted-foreground">No costs recorded</td></tr>}
            {costs.map(c => (
              <tr key={c.hotelCapitalAssetCostId} className="border-b">
                <td className="p-3">{fmtDate(c.costDate)}</td>
                <td className="p-3"><Badge variant="outline">{c.sourceType}</Badge></td>
                <td className="p-3">{c.description || "—"}</td>
                <td className="p-3 text-right font-mono">{fmt(c.amount)}</td>
                <td className="p-3 text-center"><Badge className={STATUS_COLORS[c.status] || ""}>{c.status}</Badge></td>
                <td className="p-3 text-right">
                  {c.status === "Posted" && c.sourceType !== "Acquisition" && (
                    <Button size="sm" variant="ghost" onClick={() => doReverseCost(c.hotelCapitalAssetCostId)}><RotateCcw className="h-3 w-3" /></Button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table></div></CardContent></Card>

        {/* Depreciation */}
        <h2 className="text-lg font-semibold">Depreciation History</h2>
        <Card><CardContent className="p-0"><div className="overflow-x-auto"><table className="w-full text-sm">
          <thead><tr className="border-b bg-muted/50">
            <th className="text-left p-3">Period</th><th className="text-right p-3">Amount</th>
            <th className="text-right p-3">Accumulated</th><th className="text-right p-3">Book Value</th>
            <th className="text-left p-3">Type</th><th className="text-center p-3">Status</th><th className="text-right p-3"></th>
          </tr></thead>
          <tbody>
            {depreciation.length === 0 && <tr><td colSpan={7} className="text-center p-6 text-muted-foreground">No depreciation recorded</td></tr>}
            {depreciation.map(d => (
              <tr key={d.hotelAssetDepreciationId} className="border-b">
                <td className="p-3">{fmtDate(d.periodStart)}</td>
                <td className="p-3 text-right font-mono">{fmt(d.amount)}</td>
                <td className="p-3 text-right font-mono">{fmt(d.accumulatedAfter)}</td>
                <td className="p-3 text-right font-mono">{fmt(d.bookValueAfter)}</td>
                <td className="p-3"><Badge variant="outline">{d.sourceType}</Badge></td>
                <td className="p-3 text-center"><Badge className={STATUS_COLORS[d.status] || ""}>{d.status}</Badge></td>
                <td className="p-3 text-right">
                  {d.status === "Posted" && <Button size="sm" variant="ghost" onClick={() => doReverseDep(d.hotelAssetDepreciationId)}><RotateCcw className="h-3 w-3" /></Button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table></div></CardContent></Card>

        {/* Add Cost Dialog */}
        <Dialog open={costOpen} onOpenChange={setCostOpen}><DialogContent>
          <DialogHeader><DialogTitle>Add Cost</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <FormField label="Amount *"><Input type="number" step="0.01" value={costForm.amount || ""} onChange={(e) => setCostForm({ ...costForm, amount: Number(e.target.value) })} /></FormField>
            <FormField label="Description"><Input value={costForm.description} onChange={(e) => setCostForm({ ...costForm, description: e.target.value })} /></FormField>
            <FormField label="Date"><Input type="date" value={costForm.costDate} onChange={(e) => setCostForm({ ...costForm, costDate: e.target.value })} /></FormField>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setCostOpen(false)}>Cancel</Button><Button onClick={saveCost} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Add</Button></DialogFooter>
        </DialogContent></Dialog>
      </main>
    </div></div>
  )
}

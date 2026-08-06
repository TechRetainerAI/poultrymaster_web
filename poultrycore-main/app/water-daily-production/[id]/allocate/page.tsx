"use client"

// Allocation workspace — split the batch's totals across the machines that ran.
// Nothing here touches stock: Post is what creates and approves the per-machine
// production records.

import React, { useEffect, useMemo, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Loader2, ArrowLeft, Save, CheckCircle2, Wand2, AlertTriangle } from "lucide-react"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getWaterDailyProduction, saveWaterDailyProductionAllocation, postWaterDailyProduction,
  listWaterProductionBatches,
  type WaterDailyProduction, type WaterAllocationMethod,
} from "@/lib/api/water"
import {
  METHODS, buildBlankRows, allocationsToRows, applyMethod, buildReconciliation,
  rowsToAllocations, rowGoodBags, rowAllInCost, rowCostPerBag, rowErrors, dayCostPerBag,
  type AllocRow,
} from "@/lib/utils/water-daily-allocation"

export default function AllocateWaterDailyProductionPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [day, setDay] = useState<WaterDailyProduction | null>(null)
  const [rows, setRows] = useState<AllocRow[]>([])
  const [history, setHistory] = useState<Record<number, number>>({})
  const [method, setMethod] = useState<WaterAllocationMethod>("Manual")
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [methodOpen, setMethodOpen] = useState(false)
  const [reconOpen, setReconOpen] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id])

  async function load() {
    setLoading(true)
    try {
      const d = await getWaterDailyProduction(id)
      setDay(d)

      if (d.allocations?.length) {
        setRows(allocationsToRows(d.allocations, d.machines || []))
        setMethod("Manual")
      } else {
        setRows(buildBlankRows(d.machines || []))
        setMethodOpen(true)
      }

      // Recent machine output, for the ByPreviousProduction weighting. Bounded
      // to 30 days — the poultry equivalent loads the farm's whole history.
      const to = (d.productionDate || new Date().toISOString()).slice(0, 10)
      const from = new Date(new Date(to).getTime() - 30 * 86400000).toISOString().slice(0, 10)
      try {
        const recent = await listWaterProductionBatches({ fromDate: from, toDate: to })
        const acc: Record<number, { sum: number; n: number }> = {}
        for (const b of recent) {
          if (b.status !== "Approved" || !b.waterMachineId) continue
          const k = b.waterMachineId
          acc[k] ??= { sum: 0, n: 0 }
          acc[k].sum += b.bagsProduced || 0
          acc[k].n += 1
        }
        setHistory(Object.fromEntries(Object.entries(acc).map(([k, v]) => [Number(k), v.n ? v.sum / v.n : 0])))
      } catch { /* weighting falls back to capacity */ }
    } catch (e: any) {
      toast({ title: "Failed to load the batch", description: e?.message ?? String(e), variant: "destructive" })
      router.replace("/water-daily-production")
    } finally {
      setLoading(false)
    }
  }

  const readOnly = !!day && !["PendingAllocation", "Allocated", "Reversed"].includes(day.status)

  const recon = useMemo(
    () => (day ? buildReconciliation(rows, day) : { lines: [], balanced: false }),
    [rows, day],
  )
  const reconByKey = useMemo(
    () => Object.fromEntries(recon.lines.map((l) => [l.key, l])),
    [recon],
  )

  function setRow(i: number, patch: Partial<AllocRow>) {
    setRows((rs) => rs.map((r, idx) => (idx === i ? { ...r, ...patch } : r)))
  }
  function setRowMaterial(i: number, itemId: number, qty: number) {
    setRows((rs) => rs.map((r, idx) => (idx === i ? { ...r, materialQty: { ...r.materialQty, [itemId]: qty } } : r)))
  }

  function runMethod(m: WaterAllocationMethod) {
    if (!day) return
    setMethod(m)
    setRows((rs) => applyMethod(m, rs, day, history))
    setMethodOpen(false)
    if (m !== "Manual") toast({ title: `Split ${METHODS.find((x) => x.value === m)?.label.toLowerCase()}` })
  }

  async function handleSave(): Promise<boolean> {
    if (!day) return false
    setBusy(true)
    try {
      await saveWaterDailyProductionAllocation(id, rowsToAllocations(rows, day, method))
      toast({ title: "Allocation saved" })
      return true
    } catch (e: any) {
      toast({ title: "Failed to save the allocation", description: e?.message ?? String(e), variant: "destructive" })
      return false
    } finally {
      setBusy(false)
    }
  }

  async function handlePost() {
    if (!day) return
    const anyRowError = rows.some((r) => rowErrors(r, day.sachetsPerBag).length > 0)
    if (anyRowError) { toast({ title: "Fix the highlighted rows first", variant: "destructive" }); return }

    setBusy(true)
    try {
      await saveWaterDailyProductionAllocation(id, rowsToAllocations(rows, day, method))
      await postWaterDailyProduction(id)
      toast({
        title: "Batch posted",
        description: "A production record was created and approved for each machine. Stock, expenses and losses are updated.",
      })
      router.push(`/water-daily-production/${id}`)
    } catch (e: any) {
      toast({ title: "Failed to post", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  if (loading || !day) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="p-6 flex items-center gap-2 text-slate-500">
            <Loader2 className="w-4 h-4 animate-spin" /> Loading…
          </main>
        </div>
      </div>
    )
  }

  const materials = day.materials || []

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="mb-4 flex flex-wrap items-center gap-2">
            <Button variant="ghost" size="sm" onClick={() => router.push(`/water-daily-production/${id}`)}>
              <ArrowLeft className="w-4 h-4 mr-1" /> Back
            </Button>
            <h1 className="text-xl sm:text-2xl font-semibold text-slate-900">
              Allocate {day.productionNumber || `batch #${day.waterDailyProductionId}`}
            </h1>
            <Badge variant="outline">{(day.productionDate || "").slice(0, 10)}</Badge>
            <Badge variant="outline">{day.productName ?? "—"}</Badge>
          </div>

          {readOnly && (
            <Card className="mb-4 border-amber-300 bg-amber-50">
              <CardContent className="p-3 text-sm text-amber-900">
                This batch is <span className="font-semibold">{day.status}</span> and can no longer be allocated.
              </CardContent>
            </Card>
          )}

          <div className="mb-3 flex flex-wrap items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => setMethodOpen(true)} disabled={readOnly}>
              <Wand2 className="w-4 h-4 mr-1" /> Split automatically
            </Button>
            <Button variant="ghost" size="sm" onClick={() => setReconOpen(true)}>
              Reconciliation details
            </Button>
            <div className={cn("ml-auto text-sm font-medium inline-flex items-center gap-1.5",
                               recon.balanced ? "text-emerald-700" : "text-amber-700")}>
              {recon.balanced ? <CheckCircle2 className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
              {recon.balanced ? "Balanced — ready to post" : "Does not add up to the batch totals yet"}
            </div>
          </div>

          <Card>
            <CardContent className="p-0 overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 text-slate-600">
                  <tr>
                    <th className="sticky left-0 bg-slate-50 text-left p-2 font-medium">Machine</th>
                    <th className="text-right p-2 font-medium">Bags</th>
                    <th className="text-right p-2 font-medium">Loose</th>
                    <th className="text-right p-2 font-medium">Rejected</th>
                    <th className="text-right p-2 font-medium">Damaged</th>
                    <th className="text-right p-2 font-medium">Rolls</th>
                    <th className="text-right p-2 font-medium">Litres</th>
                    <th className="text-right p-2 font-medium">Elec</th>
                    <th className="text-right p-2 font-medium">Fuel</th>
                    <th className="text-right p-2 font-medium">Labor</th>
                    <th className="text-right p-2 font-medium">Other</th>
                    {materials.map((m) => (
                      <th key={m.waterRawMaterialItemId} className="text-right p-2 font-medium whitespace-nowrap">
                        {m.itemName}{m.unitOfMeasure ? ` (${m.unitOfMeasure})` : ""}
                      </th>
                    ))}
                    <th className="text-right p-2 font-medium">Good</th>
                    <th className="text-right p-2 font-medium">Cost/bag</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r, i) => {
                    const errs = rowErrors(r, day.sachetsPerBag)
                    return (
                      <tr key={r.waterMachineId} className={cn("border-t border-slate-100", errs.length && "bg-red-50")}>
                        <td className="sticky left-0 bg-white p-2 font-medium whitespace-nowrap">
                          {r.machineName}
                          {r.capacityPerHour > 0 && (
                            <div className="text-[11px] text-slate-400">{r.capacityPerHour}/hr</div>
                          )}
                          {errs.length > 0 && <div className="text-[11px] text-red-600">{errs[0]}</div>}
                        </td>
                        <td className="p-1"><NumberInput className="w-20 text-right" min={0} value={String(r.bagsProduced)} disabled={readOnly}
                          onChange={(e) => setRow(i, { bagsProduced: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-20 text-right" min={0} value={String(r.looseSachetsProduced)} disabled={readOnly}
                          onChange={(e) => setRow(i, { looseSachetsProduced: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-20 text-right" min={0} value={String(r.rejectedSachets)} disabled={readOnly}
                          onChange={(e) => setRow(i, { rejectedSachets: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-20 text-right" min={0} value={String(r.damagedBags)} disabled={readOnly}
                          onChange={(e) => setRow(i, { damagedBags: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-20 text-right" min={0} value={String(r.packagingRollsUsed)} disabled={readOnly}
                          onChange={(e) => setRow(i, { packagingRollsUsed: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-20 text-right" min={0} value={String(r.estimatedWaterUsedLitres)} disabled={readOnly}
                          onChange={(e) => setRow(i, { estimatedWaterUsedLitres: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-24 text-right" min={0} step="0.01" value={String(r.electricityCost)} disabled={readOnly}
                          onChange={(e) => setRow(i, { electricityCost: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-24 text-right" min={0} step="0.01" value={String(r.fuelCost)} disabled={readOnly}
                          onChange={(e) => setRow(i, { fuelCost: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-24 text-right" min={0} step="0.01" value={String(r.laborCost)} disabled={readOnly}
                          onChange={(e) => setRow(i, { laborCost: Number(e.target.value) || 0 })} /></td>
                        <td className="p-1"><NumberInput className="w-24 text-right" min={0} step="0.01" value={String(r.otherProductionCost)} disabled={readOnly}
                          onChange={(e) => setRow(i, { otherProductionCost: Number(e.target.value) || 0 })} /></td>
                        {materials.map((m) => (
                          <td key={m.waterRawMaterialItemId} className="p-1">
                            <NumberInput className="w-24 text-right" min={0} step="0.001" disabled={readOnly}
                              value={String(r.materialQty[m.waterRawMaterialItemId] ?? 0)}
                              onChange={(e) => setRowMaterial(i, m.waterRawMaterialItemId, Number(e.target.value) || 0)} />
                          </td>
                        ))}
                        <td className="p-2 text-right tabular-nums text-slate-700">{rowGoodBags(r).toLocaleString()}</td>
                        <td className="p-2 text-right tabular-nums text-slate-700">{gh(rowCostPerBag(r, day))}</td>
                      </tr>
                    )
                  })}
                </tbody>
                <tfoot className="bg-slate-50 text-slate-700">
                  {(["allocated", "dayTotal", "diff"] as const).map((kind) => (
                    <tr key={kind} className="border-t border-slate-200">
                      <td className="sticky left-0 bg-slate-50 p-2 text-xs font-semibold uppercase tracking-wide">
                        {kind === "allocated" ? "Allocated" : kind === "dayTotal" ? "Batch total" : "Difference"}
                      </td>
                      {["bags", "loose", "rejected", "damaged", "rolls", "litres", "elec", "fuel", "labor", "other",
                        ...materials.map((m) => `mat-${m.waterRawMaterialItemId}`)].map((key) => {
                        const line = reconByKey[key]
                        if (!line) return <td key={key} className="p-2 text-right text-slate-300">—</td>
                        const v = kind === "allocated" ? line.allocated : kind === "dayTotal" ? line.dayTotal : line.diff
                        const text = line.money ? gh(v) : (line.decimals ? v.toFixed(line.decimals) : v.toLocaleString())
                        return (
                          <td key={key} className={cn("p-2 text-right tabular-nums text-xs",
                            kind === "diff" && !line.balanced && "text-red-600 font-semibold",
                            kind === "diff" && line.balanced && "text-emerald-600")}>
                            {kind === "diff" && v > 0 ? `+${text}` : text}
                          </td>
                        )
                      })}
                      <td className="p-2 text-right text-xs tabular-nums">
                        {kind === "allocated" ? rows.reduce((s, r) => s + rowGoodBags(r), 0).toLocaleString() : ""}
                      </td>
                      <td className="p-2 text-right text-xs tabular-nums">
                        {kind === "allocated" ? gh(dayCostPerBag(rows, day)) : ""}
                      </td>
                    </tr>
                  ))}
                </tfoot>
              </table>
            </CardContent>
          </Card>

          <div className="flex flex-wrap justify-end gap-2 pt-4 pb-8">
            <Button variant="outline" onClick={() => router.push(`/water-daily-production/${id}`)} disabled={busy}>Cancel</Button>
            <Button variant="outline" onClick={() => void handleSave()} disabled={busy || readOnly}>
              {busy ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Saving…</> : <><Save className="w-4 h-4 mr-1" /> Save allocation</>}
            </Button>
            <Button onClick={() => void handlePost()} disabled={busy || readOnly || !recon.balanced}
                    title={recon.balanced ? undefined : "The allocation has to add up to the batch totals first"}>
              {busy ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Posting…</> : <><CheckCircle2 className="w-4 h-4 mr-1" /> Post allocation</>}
            </Button>
          </div>
        </main>
      </div>

      <Dialog open={methodOpen} onOpenChange={setMethodOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Split the batch automatically</DialogTitle>
            <DialogDescription>
              Every method distributes exactly — the parts always add back up to the batch totals.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            {METHODS.map((m) => (
              <button key={m.value} type="button" onClick={() => runMethod(m.value)}
                className="w-full text-left rounded-lg border border-slate-200 p-3 hover:border-sky-400 hover:bg-sky-50">
                <div className="font-medium text-slate-900">{m.label}</div>
                <div className="text-xs text-slate-500">{m.description}</div>
              </button>
            ))}
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={reconOpen} onOpenChange={setReconOpen}>
        <DialogContent className="max-w-[640px]">
          <DialogHeader>
            <DialogTitle>Reconciliation</DialogTitle>
            <DialogDescription>
              Output and production-cost lines must match to post. Material cost is informational — the real
              price comes from the stock lots when each machine&apos;s production record is approved.
            </DialogDescription>
          </DialogHeader>
          <div className="max-h-[60vh] overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="text-slate-500 text-xs">
                <tr>
                  <th className="text-left p-1.5">Field</th>
                  <th className="text-right p-1.5">Allocated</th>
                  <th className="text-right p-1.5">Batch total</th>
                  <th className="text-right p-1.5">Difference</th>
                  <th className="text-right p-1.5">Status</th>
                </tr>
              </thead>
              <tbody>
                {recon.lines.map((l) => {
                  const fmt = (v: number) => l.money ? gh(v) : (l.decimals ? v.toFixed(l.decimals) : v.toLocaleString())
                  return (
                    <tr key={l.key} className="border-t border-slate-100">
                      <td className="p-1.5">{l.label}</td>
                      <td className="p-1.5 text-right tabular-nums">{fmt(l.allocated)}</td>
                      <td className="p-1.5 text-right tabular-nums">{fmt(l.dayTotal)}</td>
                      <td className={cn("p-1.5 text-right tabular-nums", !l.balanced && !l.info && "text-red-600 font-semibold")}>
                        {l.diff > 0 ? `+${fmt(l.diff)}` : fmt(l.diff)}
                      </td>
                      <td className="p-1.5 text-right text-xs">
                        {l.info ? <span className="text-slate-400">Info only</span>
                          : l.balanced ? <span className="text-emerald-600">OK</span>
                          : <span className="text-red-600">Off</span>}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

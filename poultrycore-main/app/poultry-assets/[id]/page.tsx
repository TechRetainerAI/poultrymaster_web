"use client"

// Asset detail (§60) — everything about one asset in one place:
// what it is, what it cost, how it is depreciating, and where each cedi came
// from. The depreciation history reads like a statement, with the book value as
// at each row, because "what is it worth now" is the question a register exists
// to answer.

import { useCallback, useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { ArrowLeft, Loader2, Undo2, Info } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import {
  getPoultryAsset, reversePoultryDepreciation,
  type PoultryCapitalAsset,
} from "@/lib/api/poultry-assets"
import {
  assetStatusLabel, ASSET_STATUS_CLASS,
  BOOK_VALUE_TOOLTIP, ORIGINAL_COST_TOOLTIP,
  DEPRECIATION_CONVENTION_NOTE, DEPRECIATION_NONCASH_NOTE,
} from "@/lib/poultry/financial-classification"

export default function PoultryAssetDetailPage() {
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const router = useRouter()
  const gh = useFmt()
  const { toast } = useToast()

  const [asset, setAsset] = useState<PoultryCapitalAsset | null>(null)
  const [loading, setLoading] = useState(true)
  const [reversing, setReversing] = useState<number | null>(null)
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)

  const load = useCallback(async () => {
    if (!Number.isFinite(id)) return
    setLoading(true)
    try { setAsset(await getPoultryAsset(id)) }
    catch (e: any) { toast({ title: "Could not load the investment", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }, [id, toast])

  useEffect(() => { void load() }, [load])

  const doReverse = async () => {
    if (reversing == null) return
    if (!reason.trim()) { toast({ title: "A reason is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await reversePoultryDepreciation(reversing, reason.trim())
      toast({
        title: "Depreciation reversed",
        description: "The original entry is kept and an opposite entry added. No cash moved.",
      })
      setReversing(null); setReason(""); await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  if (loading) {
    return <div className="p-10 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-slate-400" /></div>
  }
  if (!asset) {
    return <div className="p-6 text-sm text-slate-600">
      Capital investment not found. <Link href="/poultry-assets" className="underline">Back to Capital Investments</Link>
    </div>
  }

  const costs = (asset.costs ?? []).filter((c) => c.status === "Posted")
  const reversedCosts = (asset.costs ?? []).filter((c) => c.status !== "Posted")

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="ghost" size="sm" onClick={() => router.push("/poultry-assets")}>
              <ArrowLeft className="w-4 h-4 mr-1" /> Capital Investments
            </Button>
            <div>
              <h1 className="text-lg font-semibold text-slate-900">{asset.assetName}</h1>
              <p className="text-xs text-slate-500 font-mono">{asset.assetNumber}</p>
            </div>
            <Badge variant="outline" className={cn("ml-auto text-[11px] font-normal", ASSET_STATUS_CLASS[asset.status])}>
              {assetStatusLabel(asset.status)}
            </Badge>
          </div>

          {asset.status === "Reversed" && asset.reversalReason && (
            <Card className="border-red-200 bg-red-50"><CardContent className="p-3 text-sm text-red-800">
              This acquisition was reversed: {asset.reversalReason}
            </CardContent></Card>
          )}

          <div className="grid gap-3 lg:grid-cols-3">
            <Card><CardContent className="p-4 space-y-1.5">
              <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">General</div>
              <Line label="Category" value={asset.categoryName ?? "—"} />
              <Line label="Description" value={asset.description ?? "—"} />
              <Line label="Acquired" value={(asset.acquisitionDate || "").split("T")[0]} />
              <Line label="In service" value={(asset.inServiceDate ?? "").split("T")[0] || "Not in service"} />
              <Line label="Location" value={asset.location ?? "—"} />
              <Line label="Serial number" value={asset.serialNumber ?? "—"} />
            </CardContent></Card>

            <Card><CardContent className="p-4 space-y-1.5">
              <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Financial</div>
              <Line label="Original cost" value={gh(asset.originalCost)} hint={ORIGINAL_COST_TOOLTIP} bold />
              <Line label="Residual value" value={gh(asset.residualValue)} />
              <Line label="Depreciable amount" value={gh(asset.depreciableAmount)} />
              <Line label="Useful life" value={asset.usefulLifeMonths ? `${asset.usefulLifeMonths} months` : "Not set"} />
              <Line label="Monthly depreciation" value={asset.monthlyDepreciation ? gh(asset.monthlyDepreciation) : "—"} />
              <Line label="Depreciation so far" value={gh(asset.accumulatedDepreciation)} tone="amber" />
              <Line label="Book value" value={gh(asset.currentBookValue)} hint={BOOK_VALUE_TOOLTIP} bold tone="emerald" />
            </CardContent></Card>

            <Card><CardContent className="p-4 space-y-1.5">
              <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Source &amp; audit</div>
              <Line label="Supplier" value={asset.supplierName ?? "—"} />
              <Line label="Cost entries" value={String(asset.costEntries)} />
              <Line label="Depreciation entries" value={String(asset.depreciationEntries)} />
              <Line label="Recorded by" value={asset.createdBy ?? "—"} />
              <Line label="Recorded" value={(asset.createdAt ?? "").split("T")[0] || "—"} />
              {asset.disposalDate && <>
                <Line label="Disposed" value={(asset.disposalDate || "").split("T")[0]} />
                <Line label="Proceeds" value={asset.disposalProceeds != null ? gh(asset.disposalProceeds) : "—"} />
              </>}
            </CardContent></Card>
          </div>

          {/* ---- what was capitalised into it ---------------------------- */}
          <Card><CardContent className="p-4">
            <div className="text-sm font-semibold mb-2">Capitalised costs</div>
            <div className="overflow-x-auto"><Table className="min-w-[760px]">
              <TableHeader><TableRow>
                <TableHead>Date</TableHead><TableHead>What for</TableHead><TableHead>Type</TableHead>
                <TableHead>Supplier</TableHead><TableHead>Payment</TableHead>
                <TableHead className="text-right">Amount</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {costs.length === 0 ? (
                  <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-6">
                    Nothing capitalised yet. Use &quot;Add cost&quot; on the register to build this investment up.
                  </TableCell></TableRow>
                ) : costs.map((c) => (
                  <TableRow key={c.poultryCapitalAssetCostId}>
                    <TableCell className="whitespace-nowrap text-sm">{(c.costDate || "").split("T")[0]}</TableCell>
                    <TableCell className="text-sm">{c.description ?? "—"}</TableCell>
                    <TableCell className="text-sm text-slate-500">{c.costCategory ?? c.sourceType ?? "—"}</TableCell>
                    <TableCell className="text-sm">{c.supplierName ?? "—"}</TableCell>
                    <TableCell className="text-sm">
                      {c.paymentStatus ?? "—"}
                      {(c.balance ?? 0) > 0 && <div className="text-[11px] text-amber-700">{gh(c.balance ?? 0)} owed</div>}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{gh(c.amount)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table></div>
            {reversedCosts.length > 0 && (
              <p className="mt-2 text-[11px] text-slate-500">
                {reversedCosts.length} reversed cost entr{reversedCosts.length === 1 ? "y is" : "ies are"} kept on the
                record and excluded from the total.
              </p>
            )}
          </CardContent></Card>

          {/* ---- how it is being charged to profit ------------------------ */}
          <Card><CardContent className="p-4">
            <div className="flex flex-wrap items-center gap-2 mb-2">
              <div className="text-sm font-semibold">Depreciation history</div>
              <span className="text-[11px] text-slate-500">{DEPRECIATION_NONCASH_NOTE}</span>
            </div>
            <div className="overflow-x-auto"><Table className="min-w-[760px]">
              <TableHeader><TableRow>
                <TableHead>Period</TableHead><TableHead>Type</TableHead>
                <TableHead className="text-right">Charge</TableHead>
                <TableHead className="text-right">Accumulated</TableHead>
                <TableHead className="text-right">Book value</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {(asset.depreciation ?? []).length === 0 ? (
                  <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-6">
                    Nothing charged yet.{asset.status === "Draft" && " This investment is not in service, so it does not depreciate."}
                  </TableCell></TableRow>
                ) : (asset.depreciation ?? []).map((d) => (
                  <TableRow key={d.poultryAssetDepreciationId} className={cn(d.status === "Reversed" && "opacity-60")}>
                    <TableCell className="whitespace-nowrap text-sm">
                      {(d.periodStart || "").split("T")[0]?.slice(0, 7)}
                      {d.status === "Reversed" && <span className="ml-2 text-[11px] text-red-600">reversed</span>}
                    </TableCell>
                    <TableCell className="text-sm text-slate-500">
                      {d.sourceType}
                      {d.reversalReason && <div className="text-[11px]">{d.reversalReason}</div>}
                    </TableCell>
                    <TableCell className={cn("text-right tabular-nums text-sm", d.amount < 0 && "text-red-600")}>
                      {gh(d.amount)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-sm text-slate-500">
                      {d.accumulatedAfter != null ? gh(d.accumulatedAfter) : "—"}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-sm">
                      {d.bookValueAfter != null ? gh(d.bookValueAfter) : "—"}
                    </TableCell>
                    <TableCell className="text-right">
                      {d.status === "Posted" && d.amount > 0 && (
                        <Button variant="ghost" size="sm" title="Reverse this charge"
                                onClick={() => { setReversing(d.poultryAssetDepreciationId); setReason("") }}>
                          <Undo2 className="w-4 h-4 text-red-500" />
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table></div>
            <p className="mt-2 flex items-start gap-1.5 text-[11px] text-slate-500">
              <Info className="w-3.5 h-3.5 mt-0.5 shrink-0" />{DEPRECIATION_CONVENTION_NOTE}
            </p>
          </CardContent></Card>

          <Dialog open={reversing != null} onOpenChange={(o) => { if (!o) setReversing(null) }}>
            <DialogContent className="max-w-lg">
              <DialogHeader>
                <DialogTitle>Reverse this depreciation charge</DialogTitle>
                <DialogDescription>
                  The original entry is kept and an opposite one is written beside it, so the history still shows what
                  was charged and when. No cash is affected. The month is NOT reopened to the automatic run — post a
                  corrected amount as an adjustment if one is needed.
                </DialogDescription>
              </DialogHeader>
              <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)}
                        placeholder="Wrong in-service month" />
              <div className="flex justify-end gap-2 pt-2">
                <Button variant="outline" onClick={() => setReversing(null)}>Cancel</Button>
                <Button variant="destructive" onClick={doReverse} disabled={saving}>
                  {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Reverse
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

function Line({ label, value, hint, bold, tone }: {
  label: string; value: string; hint?: string; bold?: boolean; tone?: "amber" | "emerald"
}) {
  return (
    <div className="flex justify-between gap-4 text-sm" title={hint}>
      <span className="shrink-0 text-slate-600">{label}</span>
      <span className={cn("text-right tabular-nums truncate",
        bold && "font-semibold", tone === "amber" && "text-amber-800", tone === "emerald" && "text-emerald-800")}>
        {value}
      </span>
    </div>
  )
}

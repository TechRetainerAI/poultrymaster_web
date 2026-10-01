"use client"

// Capital investment detail — a copy of app/poultry-assets/[id] for the
// Restaurant (migration 328): what it is, what it cost, how it is depreciating,
// and where each amount came from. The depreciation history reads like a
// statement, with the book value as at each row.

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
import { ArrowLeft, Building2, Loader2, Undo2, Info } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { cn } from "@/lib/utils"
import {
  getRestaurantAsset, reverseRestaurantDepreciation,
  type RestaurantCapitalAsset,
} from "@/lib/api/restaurant-assets"
import {
  assetStatusLabel, ASSET_STATUS_CLASS,
  BOOK_VALUE_TOOLTIP,
  ACQUISITION_COST_LABEL, ADDITIONAL_COST_LABEL, TOTAL_CAPITALIZED_COST_LABEL,
  ACQUISITION_COST_TOOLTIP, ADDITIONAL_COST_TOOLTIP, TOTAL_CAPITALIZED_COST_TOOLTIP,
  DEPRECIATION_CONVENTION_NOTE, DEPRECIATION_NONCASH_NOTE,
} from "@/lib/restaurant/capital-assets"
import { DateTimeCell } from "@/components/ui/date-time-cell"
import { fmtDateTime, fmtInstant, fmtMonthYear } from "@/lib/utils/company-datetime"

export default function RestaurantAssetDetailPage() {
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const router = useRouter()
  const gh = useFmt()
  const { toast } = useToast()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canView = permissions.isAdmin || permissions.featureAccess.canEnterExpenses || permissions.featureAccess.canViewFinancial

  const [asset, setAsset] = useState<RestaurantCapitalAsset | null>(null)
  const [loading, setLoading] = useState(true)
  const [reversing, setReversing] = useState<number | null>(null)
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") router.replace("/dashboard")
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    if (!Number.isFinite(id)) return
    setLoading(true)
    try { setAsset(await getRestaurantAsset(id)) }
    catch (e: any) { toast({ title: "Could not load the investment", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }, [id, toast])

  useEffect(() => {
    if (!activeFarmId || !canView) { setLoading(false); return }
    void load()
  }, [activeFarmId, canView, load])

  const doReverse = async () => {
    if (reversing == null) return
    if (!reason.trim()) { toast({ title: "A reason is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await reverseRestaurantDepreciation(reversing, reason.trim())
      toast({
        title: "Depreciation reversed",
        description: "The original entry is kept and an opposite entry added. No cash moved.",
      })
      setReversing(null); setReason(""); await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const shell = (children: React.ReactNode) => (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 min-w-0 overflow-y-auto p-4 sm:p-6 space-y-4">{children}</main>
      </div>
    </div>
  )

  if (!canView) return shell(
    <Card><CardContent className="py-12 text-center text-slate-600">
      You do not have access to Capital Investments/Assets. Ask an admin for the expenses or financial permission.
    </CardContent></Card>,
  )
  if (loading) {
    return shell(<div className="p-10 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-slate-400" /></div>)
  }
  if (!asset) {
    return shell(<div className="p-6 text-sm text-slate-600">
      Capital investment not found. <Link href="/restaurant-assets" className="underline">Back to Capital Investments/Assets</Link>
    </div>)
  }

  const costs = (asset.costs ?? []).filter((c) => c.status === "Posted")
  const reversedCosts = (asset.costs ?? []).filter((c) => c.status !== "Posted")

  return shell(<>
    <div className="flex items-center gap-2">
      <Button variant="ghost" size="sm" className="gap-1" onClick={() => router.push("/restaurant-assets")}>
        <ArrowLeft className="h-4 w-4" /> Back to Capital Investments
      </Button>
    </div>

    <div className="flex items-start gap-3">
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-rose-100">
        <Building2 className="h-5 w-5 text-rose-600" />
      </div>
      <div className="min-w-0 flex-1">
        <h1 className="break-words text-xl font-semibold text-slate-900 sm:text-2xl">{asset.assetName}</h1>
        <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-slate-500 sm:text-sm">
          <Badge variant="outline" className={cn("text-[11px] font-normal", ASSET_STATUS_CLASS[asset.status])}>
            {assetStatusLabel(asset.status)}
          </Badge>
          <span className="font-mono">{asset.assetNumber}</span>
          {asset.categoryName && <span>· {asset.categoryName}</span>}
          <span>· Acquired {fmtDateTime(asset.acquisitionDate, asset)}</span>
          {asset.location && <span>· {asset.location}</span>}
        </div>
      </div>
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
        <Line label="Acquired" value={fmtDateTime(asset.acquisitionDate, asset) || "—"} />
        <Line label="In service" value={asset.inServiceDate ? fmtDateTime(asset.inServiceDate) : "Not in service"} />
        <Line label="Location" value={asset.location ?? "—"} />
        <Line label="Serial number" value={asset.serialNumber ?? "—"} />
      </CardContent></Card>

      <Card><CardContent className="p-4 space-y-1.5">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Financial</div>
        <Line label={ACQUISITION_COST_LABEL} value={gh(asset.acquisitionCost)} hint={ACQUISITION_COST_TOOLTIP} />
        <Line label={ADDITIONAL_COST_LABEL} value={gh(asset.additionalCost)} hint={ADDITIONAL_COST_TOOLTIP} />
        <Line label={TOTAL_CAPITALIZED_COST_LABEL} value={gh(asset.totalCapitalizedCost)} hint={TOTAL_CAPITALIZED_COST_TOOLTIP} bold />
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
        <Line label="Owed to supplier" value={asset.amountOwed > 0 ? gh(asset.amountOwed) : "—"} tone={asset.amountOwed > 0 ? "amber" : undefined} />
        <Line label="Cost entries" value={String(asset.costEntries)} />
        <Line label="Depreciation entries" value={String(asset.depreciationEntries)} />
        <Line label="Recorded by" value={asset.createdBy ?? "—"} />
        <Line label="Recorded" value={asset.createdAt ? fmtInstant(asset.createdAt) : "—"} />
        {asset.disposalDate && <>
          <Line label="Disposed" value={fmtDateTime(asset.disposalDate) || "—"} />
          <Line label="Proceeds" value={asset.disposalProceeds != null ? gh(asset.disposalProceeds) : "—"} />
        </>}
      </CardContent></Card>
    </div>

    {/* ---- what was capitalised into it ---------------------------- */}
    <Card><CardContent className="p-4">
      <div className="text-sm font-semibold mb-2">Cost history</div>
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
            <TableRow key={c.assetCostId}>
              <TableCell className="align-top text-sm"><DateTimeCell value={c.costDate} row={c} /></TableCell>
              <TableCell className="text-sm">{c.description ?? "—"}</TableCell>
              <TableCell className="text-sm text-slate-500">
                {c.sourceType === "Acquisition" ? "Original acquisition" : (c.costCategory ?? c.sourceType ?? "—")}
              </TableCell>
              <TableCell className="text-sm">{c.supplierName ?? "—"}</TableCell>
              <TableCell className="text-sm">
                {c.paymentStatus ?? "—"}
                {(c.balance ?? 0) > 0 && <div className="text-[11px] text-amber-700">{gh(c.balance ?? 0)} owed</div>}
              </TableCell>
              <TableCell className={cn("text-right tabular-nums", c.amount < 0 && "text-red-600")}>
                {c.amount < 0 ? `−${gh(Math.abs(c.amount))}` : gh(c.amount)}
              </TableCell>
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
            <TableRow key={d.assetDepreciationId} className={cn(d.status === "Reversed" && "opacity-60")}>
              <TableCell className="whitespace-nowrap text-sm">
                {fmtMonthYear(d.periodStart)}
                {d.status === "Reversed" && <span className="ml-2 text-[11px] text-red-600">reversed</span>}
              </TableCell>
              <TableCell className="text-sm text-slate-500">
                {d.sourceType}
                {d.reversalReason && <div className="text-[11px]">{d.reversalReason}</div>}
              </TableCell>
              <TableCell className={cn("text-right tabular-nums text-sm", d.amount < 0 && "text-red-600")}>{gh(d.amount)}</TableCell>
              <TableCell className="text-right tabular-nums text-sm text-slate-500">
                {d.accumulatedAfter != null ? gh(d.accumulatedAfter) : "—"}
              </TableCell>
              <TableCell className="text-right tabular-nums text-sm">
                {d.bookValueAfter != null ? gh(d.bookValueAfter) : "—"}
              </TableCell>
              <TableCell className="text-right">
                {d.status === "Posted" && d.amount > 0 && (
                  <Button variant="ghost" size="sm" title="Reverse this charge"
                          onClick={() => { setReversing(d.assetDepreciationId); setReason("") }}>
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
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Reverse this depreciation charge</DialogTitle>
          <DialogDescription>
            The original entry is kept and an opposite one is written beside it, so the history still shows what
            was charged and when. No cash is affected. The month is NOT reopened to the automatic run — post a
            corrected amount as an adjustment if one is needed.
          </DialogDescription>
        </DialogHeader>
        <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Wrong in-service month" />
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={() => setReversing(null)}>Cancel</Button>
          <Button variant="destructive" onClick={doReverse} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Reverse
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  </>)
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

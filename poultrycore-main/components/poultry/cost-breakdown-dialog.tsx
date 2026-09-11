"use client"

// "View cost breakdown" — how one consumption's cost was arrived at.
// Migration 288, function sppoultryconsumption_costbreakdown.
//
// Shared by the feed tracker, the medication tracker and the expense that a
// consumption generated, because all three are asking the same question and
// three answers to it would drift.
//
// THE POINT OF THIS DIALOG
// ------------------------
// A usage that drew 150kg costing 900 may have taken it from two purchases at
// two different prices, and only part of that 900 may be an expense today. The
// blended "6.00/kg" an owner sees elsewhere is a DISPLAY figure derived from
// the split below; the split is the audit trail, and it is read back from the
// stored allocations rather than recomputed -- re-deriving it would use today's
// stock levels rather than the ones that applied when the usage was posted.
//
// Keyed on the PRODUCTION RECORD, not the usage row: editing a record deletes
// and rewrites its usage rows, so a usage id captured in a link dangles after
// the first edit. Same reason migration 266 links its expense that way.

import { useEffect, useState } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { Loader2, AlertTriangle } from "lucide-react"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import {
  OPERATIONAL_COST_TOOLTIP, NEWLY_RECOGNIZED_TOOLTIP, ALREADY_EXPENSED_TOOLTIP,
  NO_SECOND_PAYMENT_TOOLTIP,
} from "@/lib/poultry/cost-recognition"
import {
  getPoultryConsumptionCostBreakdown,
  type PoultryConsumptionCostLayer,
} from "@/lib/api/poultry-inventory"

export function CostBreakdownDialog({
  productionRecordId,
  title,
  onClose,
}: {
  /** Null closes the dialog. */
  productionRecordId: number | null
  title?: string
  onClose: () => void
}) {
  const gh = useFmt()
  const [rows, setRows] = useState<PoultryConsumptionCostLayer[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (productionRecordId == null) { setRows(null); setError(null); return }
    let cancelled = false
    setRows(null)
    setError(null)
    getPoultryConsumptionCostBreakdown(productionRecordId)
      .then((r) => { if (!cancelled) setRows(r) })
      .catch((e) => { if (!cancelled) setError(e?.message ?? String(e)) })
    return () => { cancelled = true }
  }, [productionRecordId])

  if (productionRecordId == null) return null

  // Reversed allocations keep their rows (append-only, migration 266) but must
  // not be added into the totals.
  const live = (rows ?? []).filter((r) => !r.isReversed)
  const operational = live.reduce((a, r) => a + r.operationalCost, 0)
  const recognized = live.reduce((a, r) => a + r.recognizedCost, 0)
  const already = operational - recognized
  const quantity = live.reduce((a, r) => a + r.quantityDrawn, 0)
  const unit = live[0]?.productionUnit ?? ""

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>{title ?? "Cost breakdown"}</DialogTitle>
        </DialogHeader>

        {error ? (
          <div className="flex items-start gap-2 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-900">
            <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        ) : rows == null ? (
          <div className="flex items-center gap-2 p-6 text-sm text-slate-500">
            <Loader2 className="w-4 h-4 animate-spin" /> Loading cost breakdown…
          </div>
        ) : rows.length === 0 ? (
          <div className="p-6 text-sm text-slate-500">
            No cost layers were recorded for this record. Stock removed by a manual
            adjustment or internal-use entry does not draw from purchase lots, so it
            has no breakdown.
          </div>
        ) : (
          <div className="space-y-3">
            <div className="overflow-x-auto rounded-md border border-slate-200">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="text-xs">Purchase</TableHead>
                    <TableHead className="text-xs">Item</TableHead>
                    <TableHead className="text-xs text-right">Qty drawn</TableHead>
                    <TableHead className="text-xs text-right">Unit cost</TableHead>
                    <TableHead className="text-xs text-right">Cost</TableHead>
                    <TableHead className="text-xs">Recognition</TableHead>
                    <TableHead className="text-xs text-right" title={NEWLY_RECOGNIZED_TOOLTIP}>
                      New expense
                    </TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={`${r.poultryRawMaterialUsageId}-${r.poultryRawMaterialPurchaseId}`}
                              className={cn(r.isReversed && "opacity-60 line-through")}>
                      <TableCell className="text-xs whitespace-nowrap">
                        <div className="font-medium">#{r.poultryRawMaterialPurchaseId}</div>
                        <div className="text-[11px] text-slate-500">
                          {r.purchaseDate?.slice(0, 10)}
                          {r.supplierName ? ` · ${r.supplierName}` : ""}
                          {r.feedProductionBatchNumber ? ` · ${r.feedProductionBatchNumber}` : ""}
                        </div>
                      </TableCell>
                      <TableCell className="text-xs">{r.itemName}</TableCell>
                      <TableCell className="text-xs text-right whitespace-nowrap">
                        {r.quantityDrawn.toLocaleString(undefined, { maximumFractionDigits: 3 })}
                        {r.productionUnit ? ` ${r.productionUnit}` : ""}
                      </TableCell>
                      <TableCell className="text-xs text-right">{gh(r.unitCostAtDraw)}</TableCell>
                      <TableCell className="text-xs text-right">{gh(r.operationalCost)}</TableCell>
                      <TableCell className="text-xs">
                        {/* The LOT's own label. Two rows here can disagree, and
                            that is the whole reason the breakdown exists. */}
                        <Badge variant="outline"
                               className={cn("text-[10px] font-normal",
                                 r.recognizedCost > 0
                                   ? "border-amber-300 bg-amber-50 text-amber-800"
                                   : "border-emerald-300 bg-emerald-50 text-emerald-800")}
                               title={r.recognizedCost > 0 ? NEWLY_RECOGNIZED_TOOLTIP : ALREADY_EXPENSED_TOOLTIP}>
                          {r.recognitionLabel}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-xs text-right">
                        {r.recognizedCost > 0
                          ? <span className="font-medium text-amber-700">{gh(r.recognizedCost)}</span>
                          : <span className="text-slate-300">—</span>}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>

            {/* The summary the brief asks for, in the owner's words. */}
            <div className="rounded-md border border-slate-200 bg-slate-50 p-3 text-sm space-y-1">
              <div className="flex justify-between">
                <span className="text-slate-500">Total quantity</span>
                <span className="tabular-nums">
                  {quantity.toLocaleString(undefined, { maximumFractionDigits: 3 })}{unit ? ` ${unit}` : ""}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500" title={OPERATIONAL_COST_TOOLTIP}>Stock used (cost)</span>
                <span className="tabular-nums font-medium">{gh(operational)}</span>
              </div>
              {quantity > 0 && (
                <div className="flex justify-between">
                  <span className="text-slate-500">Effective unit cost</span>
                  <span className="tabular-nums text-slate-600">
                    {gh(operational / quantity)}{unit ? ` / ${unit}` : ""}
                  </span>
                </div>
              )}
              <div className="flex justify-between border-t pt-1">
                <span className="text-slate-500" title={ALREADY_EXPENSED_TOOLTIP}>Already expensed earlier</span>
                <span className="tabular-nums text-slate-600">{gh(already)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500" title={NEWLY_RECOGNIZED_TOOLTIP}>
                  Charged to Profit &amp; Loss now
                </span>
                <span className={cn("tabular-nums font-medium",
                                    recognized > 0 ? "text-amber-700" : "text-slate-500")}>
                  {gh(recognized)}
                </span>
              </div>
            </div>

            <p className="text-[11px] text-slate-500">{NO_SECOND_PAYMENT_TOOLTIP}</p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}

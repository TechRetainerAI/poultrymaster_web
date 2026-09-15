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
import { explainLoadFailure } from "@/lib/api/http-error"
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
      {/* Sized like the All-payments dialog on /customer-balances, which is the
          house pattern for a wide table in a modal: 95vw rather than the base
          full-width-minus-2rem, because setting any max-w-* overrides that
          mobile cap and the modal would otherwise run edge to edge. Seven
          columns clear 7xl with room, and tighter padding on a phone buys back
          a column. */}
      <DialogContent className="w-[95vw] max-w-[95vw] max-h-[92vh] overflow-y-auto p-4 sm:max-w-7xl sm:p-6">
        <DialogHeader>
          <DialogTitle>{title ?? "Cost breakdown"}</DialogTitle>
        </DialogHeader>

        {error ? (
          // Same rule as the deferred-costs page: a headline somebody can act
          // on, with the server's own words demoted rather than deleted.
          <div className="p-4 text-center">
            <AlertTriangle className="mx-auto h-7 w-7 text-amber-500" />
            <h3 className="mt-2 text-sm font-semibold text-slate-900">
              {explainLoadFailure(error, "the cost breakdown").headline}
            </h3>
            <p className="mt-1 text-xs text-slate-500">
              {explainLoadFailure(error, "the cost breakdown").hint}
            </p>
            <details className="mt-3 text-left">
              <summary className="cursor-pointer text-[11px] text-slate-400 hover:text-slate-600">
                Technical detail
              </summary>
              <p className="mt-1 break-words rounded bg-slate-50 p-2 font-mono text-[11px] text-slate-500">
                {error}
              </p>
            </details>
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
            {/* ---- Phones and tablets: one card per lot ------------------- */}
            {/* Seven columns on a 360px screen is a sideways drag through a
                figure nobody can line up. Same lg break as the payment
                history, so the two dialogs change shape together. */}
            <div className="space-y-2 lg:hidden">
              {rows.map((r) => (
                <div key={`m-${r.poultryRawMaterialUsageId}-${r.poultryRawMaterialPurchaseId}`}
                     className={cn("rounded-lg border border-slate-200 border-l-4 p-3",
                       r.isReversed ? "border-l-rose-400 bg-rose-100/70 text-slate-400" : "border-l-transparent")}>
                  <div className="flex items-start justify-between gap-3">
                    <div className={cn("min-w-0", r.isReversed && "line-through")}>
                      <div className="text-sm font-medium text-slate-900 break-words">{r.itemName}</div>
                      <div className="text-[11px] text-slate-500">
                        #{r.poultryRawMaterialPurchaseId}
                        {r.purchaseDate ? ` · ${r.purchaseDate.slice(0, 10)}` : ""}
                        {r.supplierName ? ` · ${r.supplierName}` : ""}
                        {r.feedProductionBatchNumber ? ` · ${r.feedProductionBatchNumber}` : ""}
                      </div>
                    </div>
                    <Badge variant="outline"
                           className={cn("shrink-0 text-[10px] font-normal",
                             r.recognizedCost > 0
                               ? "border-amber-300 bg-amber-50 text-amber-800"
                               : "border-emerald-300 bg-emerald-50 text-emerald-800")}>
                      {r.recognitionLabel}
                    </Badge>
                  </div>
                  <div className={cn("mt-2 grid grid-cols-2 gap-x-4 gap-y-1 text-xs", r.isReversed && "line-through")}>
                    <div className="flex justify-between"><span className="text-slate-500">Qty drawn</span>
                      <span className="tabular-nums">
                        {r.quantityDrawn.toLocaleString(undefined, { maximumFractionDigits: 3 })}
                        {r.productionUnit ? ` ${r.productionUnit}` : ""}
                      </span></div>
                    <div className="flex justify-between"><span className="text-slate-500">Unit cost</span>
                      <span className="tabular-nums">{gh(r.unitCostAtDraw)}</span></div>
                    <div className="flex justify-between"><span className="text-slate-500">Cost</span>
                      <span className="tabular-nums">{gh(r.operationalCost)}</span></div>
                    <div className="flex justify-between"><span className="text-slate-500">New expense</span>
                      {r.recognizedCost > 0
                        ? <span className="font-medium tabular-nums text-amber-700">{gh(r.recognizedCost)}</span>
                        : <span className="text-slate-300">—</span>}</div>
                  </div>
                </div>
              ))}
            </div>

            {/* ---- lg and up: the full table ------------------------------ */}
            {/* Every cell in <Table> is whitespace-nowrap by default and the
                component wraps itself in an overflow-x-auto div, so a wide row
                can only ever scroll. Letting the text wrap lets the columns
                shrink to the dialog instead; the money and quantity cells keep
                the important form of nowrap so a figure never splits. */}
            <div className="hidden rounded-md border border-slate-200 lg:block">
              <Table className="w-full [&_td]:whitespace-normal [&_th]:whitespace-normal">
                <TableHeader>
                  {/* A header, not row zero: darker ground and a heavy rule
                      under it, so the eye has a hard line to start from. */}
                  <TableRow className="border-b-2 border-slate-300 bg-slate-300/60 hover:bg-slate-300/60 [&_th]:font-semibold [&_th]:text-slate-700">
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
                  {rows.map((r, i) => (
                    <TableRow key={`${r.poultryRawMaterialUsageId}-${r.poultryRawMaterialPurchaseId}`}
                              className={cn(
                                i % 2 === 1 && "bg-slate-50/70",
                                r.isReversed && "bg-rose-100/70 text-slate-400 line-through",
                              )}>
                      <TableCell className="text-xs whitespace-nowrap!">
                        <div className="font-medium">#{r.poultryRawMaterialPurchaseId}</div>
                        <div className="text-[11px] text-slate-500">
                          {r.purchaseDate?.slice(0, 10)}
                          {r.supplierName ? ` · ${r.supplierName}` : ""}
                          {r.feedProductionBatchNumber ? ` · ${r.feedProductionBatchNumber}` : ""}
                        </div>
                      </TableCell>
                      <TableCell className="text-xs">{r.itemName}</TableCell>
                      <TableCell className="text-xs text-right whitespace-nowrap!">
                        {r.quantityDrawn.toLocaleString(undefined, { maximumFractionDigits: 3 })}
                        {r.productionUnit ? ` ${r.productionUnit}` : ""}
                      </TableCell>
                      <TableCell className="text-xs text-right whitespace-nowrap!">{gh(r.unitCostAtDraw)}</TableCell>
                      <TableCell className="text-xs text-right whitespace-nowrap!">{gh(r.operationalCost)}</TableCell>
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

            {/* The summary the brief asks for, in the owner's words. Five
                stacked rows pushed the table off a laptop screen; across the
                foot of a wide dialog they are read in one glance, and the two
                that answer "what did this cost me" sit together at the end. */}
            <div className="grid gap-2 rounded-md border border-slate-200 bg-slate-50 p-3 text-sm sm:grid-cols-2 lg:grid-cols-5 lg:gap-4">
              <div>
                <div className="text-xs text-slate-500">Total quantity</div>
                <div className="tabular-nums">
                  {quantity.toLocaleString(undefined, { maximumFractionDigits: 3 })}{unit ? ` ${unit}` : ""}
                </div>
              </div>
              <div>
                <div className="text-xs text-slate-500" title={OPERATIONAL_COST_TOOLTIP}>Stock used (cost)</div>
                <div className="font-medium tabular-nums">{gh(operational)}</div>
              </div>
              <div>
                <div className="text-xs text-slate-500">Effective unit cost</div>
                <div className="tabular-nums text-slate-600">
                  {quantity > 0 ? `${gh(operational / quantity)}${unit ? ` / ${unit}` : ""}` : "—"}
                </div>
              </div>
              <div className="lg:border-l lg:border-slate-200 lg:pl-4">
                <div className="text-xs text-slate-500" title={ALREADY_EXPENSED_TOOLTIP}>Already expensed earlier</div>
                <div className="tabular-nums text-slate-600">{gh(already)}</div>
              </div>
              <div>
                <div className="text-xs text-slate-500" title={NEWLY_RECOGNIZED_TOOLTIP}>Charged to P&amp;L now</div>
                <div className={cn("font-medium tabular-nums",
                                   recognized > 0 ? "text-amber-700" : "text-slate-500")}>
                  {gh(recognized)}
                </div>
              </div>
            </div>

            <p className="text-[11px] text-slate-500">{NO_SECOND_PAYMENT_TOOLTIP}</p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}

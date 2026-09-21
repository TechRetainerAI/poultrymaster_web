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
//
// LAYOUT: VERTICAL, AND THE SAME SHAPE AS EVERY OTHER READ MODAL HERE
// ==================================================================
// This used to be a 95vw dialog wrapping a seven-column table, with a separate
// card layout for phones. Two layouts meant two things to keep in step, and the
// wide table was the reason the modal had to be so large.
//
// It now follows the house read-modal pattern (cash-flow-insights-dialog is the
// clearest example of it): max-w-2xl, a header with a description, and
// `<section>`s introduced by a small uppercase label. One lot per card, stacked,
// at every screen size -- the same shape a phone was already getting, which was
// the more readable of the two anyway. Seven columns of figures are not
// something anyone lines up by eye; the question is "which lots, at what price,
// and how much of it is an expense today", and that reads better as a list.

import { useEffect, useState, type ReactNode } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Badge } from "@/components/ui/badge"
import { HIGHLIGHT_TONES, STRIPE_TONES, type HighlightAccent } from "@/components/ui/mobile-card-list"
import { Loader2, AlertTriangle, Layers } from "lucide-react"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { explainLoadFailure } from "@/lib/api/http-error"
import { fmtDateTime } from "@/lib/utils/company-datetime"
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
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Layers className="h-4 w-4 text-sky-600" />
            {title ?? "Cost breakdown"}
          </DialogTitle>
          <DialogDescription>
            Which purchase lots this usage drew from, and how much of that cost
            reaches Profit &amp; Loss today.
          </DialogDescription>
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
          <div className="space-y-4">
            {/* THE ANSWER FIRST. This used to sit under the table, which on a
                phone meant scrolling past every lot to reach the number you
                opened the dialog for. */}
            <section>
              <SectionLabel>What this cost</SectionLabel>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                <Figure
                  label="Total quantity"
                  value={`${quantity.toLocaleString(undefined, { maximumFractionDigits: 3 })}${unit ? ` ${unit}` : ""}`}
                  accent="blue"
                />
                <Figure
                  label="Stock used (cost)"
                  value={gh(operational)}
                  accent="violet"
                  hint={OPERATIONAL_COST_TOOLTIP}
                />
                <Figure
                  label="Effective unit cost"
                  value={quantity > 0 ? `${gh(operational / quantity)}${unit ? ` / ${unit}` : ""}` : "—"}
                  accent="slate"
                />
              </div>

              {/* The two that answer "what hit my P&L" are separated from the
                  three above, which only describe the draw. */}
              <div className="mt-2 grid grid-cols-2 gap-2">
                <Figure
                  label="Already expensed earlier"
                  value={gh(already)}
                  accent="emerald"
                  hint={ALREADY_EXPENSED_TOOLTIP}
                />
                {/* Accented only when non-zero: a zero here is a perfectly
                    normal answer and should not shout. */}
                {/* Amber when it is non-zero -- that is the figure that changes
                    this month's profit. A zero is a normal answer, so it drops
                    to slate rather than shouting in amber. */}
                <Figure
                  label="Charged to P&L now"
                  value={gh(recognized)}
                  accent={recognized > 0 ? "amber" : "slate"}
                  hint={NEWLY_RECOGNIZED_TOOLTIP}
                />
              </div>
            </section>

            <section>
              <SectionLabel>
                Where it came from{rows.length > 1 ? ` · ${rows.length} lots` : ""}
              </SectionLabel>
              <div className="space-y-2">
                {rows.map((r, i) => {
                  // Alternate tint, exactly as the mobile card lists stripe
                  // (STRIPE_TONES, blue accent). With several lots the stripe is
                  // what separates one from the next once each card carries
                  // coloured tiles of its own.
                  const stripe = i % 2 === 0
                  return (
                  <div
                    key={`${r.poultryRawMaterialUsageId}-${r.poultryRawMaterialPurchaseId}`}
                    className={cn(
                      "rounded-lg border border-l-4 p-3 shadow-sm",
                      // A reversed lot overrides the stripe: it is struck through
                      // and must read as withdrawn, not as just another row.
                      r.isReversed
                        ? "border-rose-300 border-l-rose-400 bg-rose-100/70 text-slate-400"
                        : stripe
                          ? cn(STRIPE_TONES.blue, "border-l-blue-300")
                          : "border-slate-200 border-l-slate-200 bg-white",
                    )}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className={cn("min-w-0", r.isReversed && "line-through")}>
                        <div className="text-sm font-medium text-slate-900 break-words">{r.itemName}</div>
                        <div className="text-[11px] text-slate-500">
                          #{r.poultryRawMaterialPurchaseId}
                          {r.purchaseDate ? ` · ${fmtDateTime(r.purchaseDate)}` : ""}
                          {r.supplierName ? ` · ${r.supplierName}` : ""}
                          {r.feedProductionBatchNumber ? ` · ${r.feedProductionBatchNumber}` : ""}
                        </div>
                      </div>
                      {/* The LOT's own label. Two rows here can disagree, and
                          that is the whole reason the breakdown exists. */}
                      <Badge
                        variant="outline"
                        title={r.recognizedCost > 0 ? NEWLY_RECOGNIZED_TOOLTIP : ALREADY_EXPENSED_TOOLTIP}
                        className={cn(
                          "shrink-0 text-[10px] font-normal",
                          r.recognizedCost > 0
                            ? "border-amber-300 bg-amber-50 text-amber-800"
                            : "border-emerald-300 bg-emerald-50 text-emerald-800",
                        )}
                      >
                        {r.recognitionLabel}
                      </Badge>
                    </div>

                    <div className={cn("mt-2 grid grid-cols-2 gap-x-4 gap-y-1 text-xs sm:grid-cols-4",
                                       r.isReversed && "line-through")}>
                      <LotFact label="Qty drawn">
                        {r.quantityDrawn.toLocaleString(undefined, { maximumFractionDigits: 3 })}
                        {r.productionUnit ? ` ${r.productionUnit}` : ""}
                      </LotFact>
                      <LotFact label="Unit cost">{gh(r.unitCostAtDraw)}</LotFact>
                      <LotFact label="Cost">{gh(r.operationalCost)}</LotFact>
                      <LotFact label="New expense">
                        {r.recognizedCost > 0
                          ? <span className="font-medium text-amber-700">{gh(r.recognizedCost)}</span>
                          : <span className="text-slate-300">—</span>}
                      </LotFact>
                    </div>
                  </div>
                  )
                })}
              </div>
            </section>

            <p className="text-[11px] text-slate-500">{NO_SECOND_PAYMENT_TOOLTIP}</p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}

/** House section heading — matches cash-flow-insights-dialog. */
function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <h3 className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
      {children}
    </h3>
  )
}

/**
 * A figure tile, using the SAME tones and markup as the highlight tiles on the
 * mobile card lists (HIGHLIGHT_TONES), so the dialog reads as part of the same
 * design rather than a greyscale cousin of it.
 *
 * The colour carries meaning here, it is not decoration:
 *   blue    the draw itself (how much stock moved)
 *   violet  what that stock cost
 *   slate   a derived figure (the blended rate)
 *   emerald cost already charged to P&L in an earlier period — settled
 *   amber   cost hitting P&L now — the figure that changes this month's profit
 * Amber and emerald match the per-lot recognition badges below, so the same two
 * ideas keep the same two colours throughout.
 */
function Figure({
  label, value, accent = "slate", hint,
}: {
  label: string; value: string; accent?: HighlightAccent; hint?: string
}) {
  const tone = HIGHLIGHT_TONES[accent]
  return (
    <div className={cn("rounded-lg border px-3 py-2 shadow-sm", tone.tile)}>
      <p className={cn("text-[11px] font-semibold uppercase tracking-wide", tone.label)} title={hint}>
        {label}
      </p>
      <p className={cn("text-base font-extrabold leading-tight tabular-nums break-words", tone.value)}>
        {value}
      </p>
    </div>
  )
}

/** One figure inside a lot card: label above, value below, so a long unit wraps
    under its own label rather than pushing the next column out. */
function LotFact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <div className="text-[11px] leading-tight text-slate-500">{label}</div>
      <div className="font-medium tabular-nums text-slate-900">{children}</div>
    </div>
  )
}

"use client"

// =============================================================================
// One capitalised cost, in full (migrations 313, 314).
//
// The complaint this answers: Add cost asks for a date, an amount, a supplier, a
// payment method, an account and a due date -- and then shows none of it back.
// A financial transaction that cannot be read after it is entered is not a
// record, it is a rumour.
//
// Read modal, house pattern: max-w-2xl, vertical, SectionLabel + rows, no wide
// table. Every field here is one the model actually stores; nothing is invented
// to fill a column, and a field with nothing behind it is left out rather than
// printed as a dash.
// =============================================================================

import Link from "next/link"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Receipt, Undo2 } from "lucide-react"
import { cn } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import type { AssetCostRow } from "./asset-details-panel"

export interface CostDetailDialogProps {
  cost: AssetCostRow | null
  assetName?: string
  onClose: () => void
  fmt: (n: number) => string
  term: "investment" | "asset"
  expensesHref: string
  /** Offered only where the server would accept it; see AssetDetailsPanel. */
  onReverse?: (row: AssetCostRow) => void
  reverseDisabledReason?: string | null
}

export function CostDetailDialog({
  cost, assetName, onClose, fmt, term, expensesHref, onReverse, reverseDisabledReason,
}: CostDetailDialogProps) {
  if (!cost) return null

  const isCorrection = cost.sourceType === "OriginalCostCorrection"
  const isAcquisition = cost.sourceType === "Acquisition"
  const typeLabel = isCorrection
    ? "Original cost correction"
    : isAcquisition
      ? "Original acquisition"
      : (cost.costCategory ?? "").trim() || "Additional cost"
  const reversible = !isCorrection && !isAcquisition && cost.status === "Posted"

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{typeLabel}</DialogTitle>
          <DialogDescription>
            {isCorrection
              ? `A correction to what this ${term} was recorded as costing. It amended the original acquisition's own document — no second payment and no second expense were created.`
              : `One amount capitalised into ${assetName ?? `this ${term}`}. It increased what the ${term} is worth and was not charged against this period's profit.`}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <section>
            <SectionLabel>The cost</SectionLabel>
            <div className="space-y-1">
              <Row label="Amount">
                <span className={cn("font-semibold tabular-nums", cost.amount < 0 && "text-red-600")}>
                  {cost.amount < 0 ? `−${fmt(Math.abs(cost.amount))}` : fmt(cost.amount)}
                </span>
              </Row>
              <Row label="Date">{fmtDateTime(cost.costDate, cost) || "—"}</Row>
              <Row label="Cost type">
                <Badge variant="outline" className="text-[10px] font-normal">{typeLabel}</Badge>
              </Row>
              <Row label={isCorrection ? "Reason" : "What it was for"}>{cost.description ?? "—"}</Row>
              <Row label="Status">
                <Badge
                  variant="outline"
                  className={cn("text-[10px] font-normal",
                    cost.status === "Posted"
                      ? "border-emerald-300 bg-emerald-50 text-emerald-700"
                      : "border-red-300 bg-red-50 text-red-700")}
                >
                  {cost.status}
                </Badge>
              </Row>
            </div>
          </section>

          {/* A correction has no payment of its own -- it moved the acquisition's
              figures -- so this whole section would be three wrong numbers. */}
          {!isCorrection && (
            <section>
              <SectionLabel>Who was paid, and how</SectionLabel>
              <div className="space-y-1">
                <Row label="Supplier / payee">{cost.supplierName ?? "—"}</Row>
                <Row label="Payment status">{cost.paymentStatus ?? "—"}</Row>
                <Row label="Payment method">{cost.paymentMethod ?? "—"}</Row>
                {cost.amountPaid != null && (
                  <Row label="Amount paid"><span className="tabular-nums">{fmt(cost.amountPaid)}</span></Row>
                )}
                {(cost.balance ?? 0) > 0 && (
                  <Row label="Balance owed">
                    <span className="tabular-nums text-amber-700">{fmt(cost.balance ?? 0)}</span>
                  </Row>
                )}
                {cost.dueDate && <Row label="Balance due">{fmtDateTime(cost.dueDate)}</Row>}
                {cost.cashAccountName && <Row label="Paid from">{cost.cashAccountName}</Row>}
              </div>
            </section>
          )}

          <section>
            <SectionLabel>The record behind it</SectionLabel>
            <div className="space-y-1">
              {cost.expenseId ? (
                <Row label="Expense">
                  <Link href={expensesHref}
                        className="inline-flex items-center gap-1 underline underline-offset-2">
                    <Receipt className="h-3.5 w-3.5" /> Expense #{cost.expenseId}
                  </Link>
                </Row>
              ) : (
                <Row label="Expense">
                  <span className="text-slate-500">None — nothing was paid or owed for this entry.</span>
                </Row>
              )}
              {cost.expenseCategory && <Row label="Filed under">{cost.expenseCategory}</Row>}
              {cost.expenseAmount != null && (
                <Row label={isCorrection ? "Document now reads" : "Document total"}>
                  <span className="tabular-nums">{fmt(cost.expenseAmount)}</span>
                </Row>
              )}
              <Row label="Recorded by">{cost.createdBy ?? "—"}</Row>
              <Row label="Recorded">{cost.createdAt ? fmtDateTime(cost.createdAt) : "—"}</Row>
              {cost.status !== "Posted" && (
                <>
                  <Row label="Reversed by">{cost.reversedBy ?? "—"}</Row>
                  <Row label="Reversed">{cost.reversedAt ? fmtDateTime(cost.reversedAt) : "—"}</Row>
                  <Row label="Reversal reason">{cost.reversalReason ?? "—"}</Row>
                </>
              )}
            </div>
          </section>

          <div className="flex flex-wrap justify-end gap-2 pt-1">
            {onReverse && reversible && (
              <Button
                variant="outline"
                className="text-red-600"
                disabled={!!reverseDisabledReason}
                title={reverseDisabledReason ?? "Reverse this cost"}
                onClick={() => onReverse(cost)}
              >
                <Undo2 className="mr-1 h-4 w-4" /> Reverse this cost
              </Button>
            )}
            <Button variant="outline" onClick={onClose}>Close</Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <h4 className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
      {children}
    </h4>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-4 text-sm">
      <span className="shrink-0 text-slate-600">{label}</span>
      <span className="text-right text-slate-900">{children}</span>
    </div>
  )
}

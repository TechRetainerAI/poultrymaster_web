"use client"

// View a sale (migration 351). Replaces "Edit" on the Sales page: a posted
// sale's financial content is immutable, so this shows it read-only and offers
// the actions that ARE allowed -- change the note, Correct Sale, Reverse Sale,
// Invoice. A reversed sale shows when, by whom, why, what happened to its
// money, and the sale that corrected it.

import { useEffect, useState } from "react"
import { FileText, Loader2, RotateCcw, ShoppingCart, Undo2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
import { Textarea } from "@/components/ui/textarea"
import { formatCurrency } from "@/lib/utils/currency"
import { cn, formatDateShort } from "@/lib/utils"
import { getSaleReversal, type Sale, type SaleLine, type SaleReversalRecord } from "@/lib/api/sale"
import { restoreLabel } from "@/lib/sales/reversal"

type SaleRow = Sale & { lines?: SaleLine[] }

interface Props {
  sale: SaleRow | null
  farmId: string
  currencyCode: string
  flockLabel: (flockId?: number | null) => string
  lineLabel: (line: SaleLine) => string
  canReverse: boolean
  onOpenChange: (open: boolean) => void
  onSaveNote: (sale: SaleRow, note: string) => Promise<boolean>
  onReverse: (sale: SaleRow) => void
  onCorrect: (sale: SaleRow) => void
  /** A reversed, not yet corrected sale: enter it again, fixed, as a new linked sale. */
  canRepost?: boolean
  onRepost?: (sale: SaleRow) => void
  onInvoice: (sale: SaleRow) => void
  onShowSale: (saleId: number) => void
}

const HANDLING_LABEL: Record<SaleReversalRecord["paymentHandling"], string> = {
  None: "Nothing had been paid",
  KeepAsCredit: "Kept as customer credit",
  ReversePayment: "Payment reversed",
  Mixed: "Partly kept as credit, partly reversed",
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3 text-sm">
      <span className="text-slate-500">{label}</span>
      <span className="text-right font-medium text-slate-900">{children}</span>
    </div>
  )
}

export function SaleDetailsDialog({
  sale, farmId, currencyCode, flockLabel, lineLabel, canReverse,
  onOpenChange, onSaveNote, onReverse, onCorrect, onInvoice, onShowSale, canRepost, onRepost,
}: Props) {
  const [note, setNote] = useState("")
  const [savingNote, setSavingNote] = useState(false)
  const [reversal, setReversal] = useState<SaleReversalRecord | null>(null)
  const reversed = sale?.status === "Reversed"
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  useEffect(() => {
    setNote(sale?.saleDescription ?? "")
    setReversal(null)
    if (sale && sale.status === "Reversed") {
      void getSaleReversal(sale.saleId, farmId).then((r) => { if (r.success && r.data) setReversal(r.data) })
    }
  }, [sale, farmId])

  if (!sale) return null
  const label = sale.saleGroupNo ?? `#${sale.saleId}`
  // 358: the sale's own lines; an older payload without them reads as one line.
  const lines: SaleLine[] = sale.lines?.length ? sale.lines : [{
    saleLineId: 0, lineNo: 1, product: sale.product, eggProductId: sale.eggProductId, size: sale.size,
    quantity: sale.quantity, unitPrice: sale.unitPrice, totalAmount: sale.totalAmount,
  }]
  const paid = Number(sale.amountPaid ?? (sale.paid === false ? 0 : sale.totalAmount)) || 0
  const noteChanged = (note ?? "") !== (sale.saleDescription ?? "")

  return (
    <Dialog open={!!sale} onOpenChange={onOpenChange}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={ShoppingCart} color="blue">
            <span className="flex flex-wrap items-center gap-2">
              Sale {label}
              {reversed
                ? <Badge variant="outline" className="border-red-300 bg-red-50 text-red-700">Reversed</Badge>
                : <Badge variant="outline" className="border-emerald-300 bg-emerald-50 text-emerald-700">Posted</Badge>}
            </span>
          </FormDialogTitle>
          <DialogDescription>
            {reversed
              ? "This sale was reversed. It stays here for the record; it no longer counts as revenue, stock sold or money owed. Use Edit & repost to enter it again with the mistake fixed."
              : "A posted sale cannot be edited. If something is wrong, use Correct Sale (reverse it and enter it again) or Reverse Sale."}
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-4">
          {sale.correctsSaleId ? (
            <p className="rounded-md bg-blue-50 p-2.5 text-sm text-blue-800">
              Correction of sale{" "}
              <button className="font-semibold underline" onClick={() => onShowSale(sale.correctsSaleId!)}>#{sale.correctsSaleId}</button>
            </p>
          ) : null}

          <FormSection title="Sale" color="blue" tinted columns={1} className="[&>div:last-child]:gap-1.5">
            <Row label="Date">{formatDateShort(sale.saleDate)}</Row>
            <Row label="Customer">{sale.customerName || "Walk-in"}</Row>
            <Row label="Flock">{flockLabel(sale.flockId)}</Row>
            <Row label="Payment method">{sale.paymentMethod || "—"}</Row>
            <Row label="Total">{money(sale.totalAmount)}</Row>
            {!reversed && <Row label="Paid">{money(paid)}</Row>}
            {!reversed && <Row label="Balance">{money(Math.max(0, (Number(sale.totalAmount) || 0) - paid))}</Row>}
          </FormSection>

          <FormSection title={lines.length > 1 ? "Lines" : "Item"} color="amber" tinted columns={1} className="[&>div:last-child]:gap-2">
            {lines.map((l) => (
              <div key={l.lineNo} className="flex justify-between gap-3 rounded-md border bg-white p-2.5 text-sm">
                <span>{lineLabel(l)}</span>
                <span className="tabular-nums font-medium">{money(l.totalAmount)}</span>
              </div>
            ))}
          </FormSection>

          {reversed && (
            <FormSection title="Reversal" color="rose" tinted columns={1}>
              <div className="space-y-1.5">
                <Row label="Reversed">{reversal ? `${reversal.reversalNumber} · ${formatDateShort(reversal.businessDate)}` : (sale.reversedAt ? formatDateShort(sale.reversedAt) : "—")}</Row>
                <Row label="By">{reversal?.reversedBy || sale.reversedBy || "—"}</Row>
                <Row label="Reason">{reversal ? [reversal.reasonCode, reversal.reason].filter(Boolean).join(": ") : (sale.reversalReason || "—")}</Row>
                {reversal && <Row label="Payment handling">{HANDLING_LABEL[reversal.paymentHandling]}</Row>}
                {reversal && reversal.creditCreated > 0 && <Row label="Customer credit created">{money(reversal.creditCreated)}</Row>}
                {reversal && reversal.cashReversed > 0 && <Row label="Paid back out of cash">{money(reversal.cashReversed)}</Row>}
                {reversal?.payments.map((p) => (
                  <Row key={p.paymentGroupId} label={p.paymentNumbers || "Payment"}>
                    {money(p.amount)} — {p.action === "ReversePayment" ? "reversed" : "kept as credit"}
                  </Row>
                ))}
                {(reversal?.lines ?? []).map((l) => restoreLabel(l)).filter(Boolean).map((t) => (
                  <Row key={t!} label="Stock put back">{t}</Row>
                ))}
                {(sale.correctedBySaleId || reversal?.correctionSaleId) && (
                  <Row label="Corrected by">
                    <button className="font-semibold text-blue-700 underline" onClick={() => onShowSale((sale.correctedBySaleId || reversal?.correctionSaleId)!)}>
                      #{sale.correctedBySaleId || reversal?.correctionSaleId}
                    </button>
                  </Row>
                )}
              </div>
            </FormSection>
          )}

          <FormSection title="Note" color="slate" tinted columns={1}>
            {reversed ? (
              <p className="text-sm text-slate-700">{sale.saleDescription || "—"}</p>
            ) : (
              <>
                <Textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} className="bg-white"
                          placeholder="Internal note (does not change the sale's money or stock)" />
                {noteChanged && (
                  <Button size="sm" variant="outline" disabled={savingNote} className="w-fit bg-white"
                          onClick={async () => { setSavingNote(true); try { await onSaveNote(sale, note) } finally { setSavingNote(false) } }}>
                    {savingNote && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Save note
                  </Button>
                )}
              </>
            )}
          </FormSection>
        </div>

        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelLabel="Close">
          <Button variant="outline" onClick={() => onInvoice(sale)}><FileText className="mr-2 h-4 w-4" /> Invoice</Button>
          {reversed && canRepost && onRepost && !reversal?.correctionSaleId && (
            <Button className={FORM_DIALOG_PRIMARY.blue} onClick={() => onRepost(sale)}>
              <RotateCcw className="mr-2 h-4 w-4" /> Edit &amp; repost
            </Button>
          )}
          {!reversed && canReverse && (
            <>
              <Button variant="outline" className="border-red-200 text-red-700 hover:bg-red-50" onClick={() => onReverse(sale)}>
                <Undo2 className="mr-2 h-4 w-4" /> Reverse sale
              </Button>
              <Button className={FORM_DIALOG_PRIMARY.blue} onClick={() => onCorrect(sale)}>
                <RotateCcw className="mr-2 h-4 w-4" /> Correct sale
              </Button>
            </>
          )}
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}

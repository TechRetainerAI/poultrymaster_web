"use client"

// Payment history, with the allocation behind each payment.
//
// Every payment expands to show exactly which sales or purchases it settled and
// what each one's balance was before and after -- the audit trail that makes a
// bulk payment explainable six months later. Reversal lives here too, because
// this is the only screen that shows enough context to reverse the right one.
//
// Nine columns, and a six-column allocation table nested inside them, is a
// desktop layout. Below `lg` the same payments render as cards and the
// allocation opens underneath as its own small stack -- the pattern used by the
// list pages -- so a phone never has to scroll a table sideways inside a modal.

import { Fragment, useEffect, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ChevronDown, ChevronRight, Loader2, Undo2 } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import {
  getPayment, listPayments, reversePayment,
  type BalanceModule, type BalanceSide, type PaymentAllocationRow, type PaymentHistoryRow,
} from "@/lib/api/balances"

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
  module: BalanceModule
  side: BalanceSide
  partyId?: number | null
  partyName?: string | null
  /** Scope to one sale/purchase's payments. */
  documentType?: string | null
  documentId?: number | null
  /** Whether this user may reverse a posted payment. */
  canReverse: boolean
  onReversed: () => void
}

// Where the payment was taken. The API's raw code is the widest thing in the
// row -- "CustomerBalances" pushed the last two columns off the screen -- and
// it says no more than the short word does. The raw value stays on the title
// attribute for anyone who needs it.
const SOURCE_LABEL: Record<string, string> = {
  CustomerBalances: "Balances",
  SupplierBalances: "Balances",
  SaleEntry: "Sale",
  PurchaseEntry: "Purchase",
}
const sourceLabel = (s?: string | null) => (s ? SOURCE_LABEL[s] ?? s : "—")

// PAY-0001 (migration 240), falling back to the group uuid's first block where
// there is no number -- the supplier side, or an API that predates it.
const paymentRef = (row: { paymentNumber?: string | null; paymentId: string }) =>
  row.paymentNumber?.trim() || `#${String(row.paymentId).slice(0, 8)}`

export function PaymentHistoryDialog({
  open, onOpenChange, module, side, partyId, partyName, documentType, documentId, canReverse, onReversed,
}: Props) {
  const fmt = useFmt()
  const { toast } = useToast()

  const [rows, setRows] = useState<PaymentHistoryRow[]>([])
  const [loading, setLoading] = useState(false)
  const [expanded, setExpanded] = useState<string | null>(null)
  const [allocations, setAllocations] = useState<Record<string, PaymentAllocationRow[]>>({})
  const [reversing, setReversing] = useState<string | null>(null)
  const [reason, setReason] = useState("")

  const load = async () => {
    setLoading(true)
    try {
      const list = await listPayments(module, side, { partyId, documentType, documentId })
      setRows(list)
    } catch (e: any) {
      toast({ title: "Could not load payments", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (!open) return
    setExpanded(null)
    setReversing(null)
    setReason("")
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, partyId, documentId, module, side])

  const toggle = async (row: PaymentHistoryRow) => {
    if (expanded === row.paymentId) { setExpanded(null); return }
    setExpanded(row.paymentId)
    if (allocations[row.paymentId]) return
    try {
      const detail = await getPayment(module, side, row.paymentId)
      setAllocations((prev) => ({ ...prev, [row.paymentId]: detail.allocations }))
    } catch (e: any) {
      toast({ title: "Could not load allocation", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const doReverse = async (row: PaymentHistoryRow) => {
    if (!reason.trim()) {
      toast({ title: "A reason is required", description: "Say why this payment is being reversed — it is written to the audit trail.", variant: "destructive" })
      return
    }
    try {
      await reversePayment(module, side, row.paymentId, reason.trim())
      toast({ title: "Payment reversed", description: `${fmt(row.totalAmount)} put back on the balance.` })
      setReversing(null)
      setReason("")
      await load()
      onReversed()
    } catch (e: any) {
      toast({ title: "Could not reverse payment", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const shortDate = (d?: string | null) => (d ? new Date(d).toLocaleDateString() : "—")

  // Posted vs Reversed is the field you scan a whole column for, so it gets
  // real colour rather than two greys that have to be read one at a time.
  const statusBadge = (row: PaymentHistoryRow) =>
    (row.status ?? "Posted") === "Reversed"
      ? <Badge variant="outline" className="border-rose-200 bg-rose-50 text-rose-700">Reversed</Badge>
      : <Badge variant="outline" className="border-emerald-200 bg-emerald-50 text-emerald-700">Posted</Badge>

  // The reversal form, written once and rendered in both layouts so the wording
  // and the guard on the reason cannot drift apart. Stacked on a phone, one row
  // from `sm` up.
  const reverseForm = (row: PaymentHistoryRow) => (
    <>
      <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-end">
        <div className="space-y-1.5 sm:min-w-[18rem] sm:flex-1">
          <Label htmlFor={`reason-${row.paymentId}`}>Why is this being reversed?</Label>
          <Input
            id={`reason-${row.paymentId}`}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. entered twice"
          />
        </div>
        <div className="flex gap-2">
          <Button size="sm" variant="destructive" className="h-10 flex-1 sm:h-9 sm:flex-none" onClick={() => doReverse(row)}>
            Reverse payment
          </Button>
          <Button size="sm" variant="ghost" className="h-10 flex-1 sm:h-9 sm:flex-none" onClick={() => setReversing(null)}>
            Cancel
          </Button>
        </div>
      </div>
      <p className="mt-2 text-xs text-slate-500">
        The balance goes back onto the {side === "customer" ? "sales" : "purchases"} it was applied to and the
        cash movement is undone. The payment is kept and marked reversed, never deleted.
      </p>
    </>
  )

  // The allocation behind one payment, as a stack. Six numeric columns do not
  // survive a phone, but the before/applied/after trio is the whole point of
  // the screen, so it is kept -- paired up two to a line.
  const allocationCards = (list: PaymentAllocationRow[]) => (
    <div className="space-y-2">
      {list.map((a) => (
        <div key={a.allocationId} className="rounded-md border border-slate-200 bg-white p-2.5 text-xs">
          <div className="flex items-start justify-between gap-2">
            <span className="min-w-0 truncate font-medium text-slate-900">{a.reference ?? a.documentId}</span>
            <span className="shrink-0 font-semibold tabular-nums">{fmt(a.amountApplied)}</span>
          </div>
          {a.label ? <div className="truncate text-slate-500">{a.label}</div> : null}
          <div className="mt-1.5 grid grid-cols-2 gap-x-3 gap-y-1 text-slate-500">
            <span>{shortDate(a.documentDate)}</span>
            <span className="text-right tabular-nums">Total {fmt(a.documentTotal)}</span>
            <span className="tabular-nums">Before {fmt(a.balanceBefore)}</span>
            <span className="text-right tabular-nums">After {fmt(a.balanceAfter)}</span>
          </div>
        </div>
      ))}
    </div>
  )

  const loadingAllocation = (
    <span className="flex items-center gap-2 text-sm text-slate-500">
      <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading allocation…
    </span>
  )

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      {/* Wide enough that NOTHING here scrolls sideways. Two tables have to fit,
          not one: the ten-column payment list, and the six-column allocation
          table nested inside an expanded row -- it was the nested one that
          still overflowed at 5xl, cutting off "Balance after" and "Status".
          7xl clears both with room to spare.

          95vw rather than the base full-width-minus-2rem, because setting any
          max-w-* overrides that mobile cap and the modal would otherwise run
          edge to edge; tighter padding on a phone buys back a column. */}
      <DialogContent className="w-[95vw] max-w-[95vw] max-h-[92vh] overflow-y-auto p-4 sm:max-w-7xl sm:p-6">
        <DialogHeader>
          <DialogTitle>Payment history</DialogTitle>
          <DialogDescription>
            {partyName ?? (side === "customer" ? "All customers" : "All suppliers")}
            {documentId ? ` · ${documentType ?? ""} #${documentId}` : ""}
          </DialogDescription>
        </DialogHeader>

        <div className="rounded-md border">
          {loading ? (
            <div className="flex items-center gap-2 p-6 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <div className="p-8 text-center text-slate-500">No payments recorded yet.</div>
          ) : (
            <>
              {/* ---- Phones: one card per payment ---------------------------- */}
              <div className="divide-y divide-slate-100 lg:hidden">
                {rows.map((row) => {
                  const isReversed = row.status === "Reversed"
                  const isOpen = expanded === row.paymentId
                  return (
                    <div
                      key={row.paymentId}
                      className={cn(
                        "border-l-4 p-3",
                        isOpen
                          ? "border-l-indigo-600 bg-indigo-200/70"
                          : isReversed
                            ? "border-l-rose-400 bg-rose-100/70 text-slate-400"
                            : "border-l-transparent",
                      )}
                    >
                      <button
                        type="button"
                        onClick={() => toggle(row)}
                        aria-label="Show allocation"
                        className="flex w-full items-start justify-between gap-3 text-left"
                      >
                        <div className="min-w-0 flex-1">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className={cn("font-semibold text-slate-900 tabular-nums", isReversed && "text-slate-400 line-through")}>
                              {fmt(row.totalAmount)}
                            </span>
                            {statusBadge(row)}
                          </div>
                          <div className="mt-1 text-xs text-slate-500">
                            {shortDate(row.paymentDate)} · {row.paymentMethod ?? "—"} ·{" "}
                            {row.allocationCount} item{row.allocationCount === 1 ? "" : "s"}
                          </div>
                        </div>
                        {isOpen
                          ? <ChevronDown className="mt-0.5 h-4 w-4 shrink-0 text-slate-400" />
                          : <ChevronRight className="mt-0.5 h-4 w-4 shrink-0 text-slate-400" />}
                      </button>

                      <div className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-xs text-slate-500">
                        <span className="min-w-0 truncate">{paymentRef(row)}</span>
                        <span className="min-w-0 truncate text-right">Source: {sourceLabel(row.sourceType)}</span>
                        <span className="min-w-0 truncate">Ref: {row.reference ?? "—"}</span>
                      </div>

                      {isReversed && row.reversalReason && (
                        <p className="mt-2 text-xs text-slate-500">
                          Reversed{row.reversedBy ? ` by ${row.reversedBy}` : ""}
                          {row.reversedAt ? ` on ${shortDate(row.reversedAt)}` : ""}: {row.reversalReason}
                        </p>
                      )}

                      {canReverse && !isReversed && reversing !== row.paymentId && (
                        <Button
                          variant="outline"
                          size="sm"
                          className="mt-2 h-10 w-full bg-white"
                          onClick={() => { setReversing(row.paymentId); setReason("") }}
                        >
                          <Undo2 className="mr-1.5 h-3.5 w-3.5" /> Reverse
                        </Button>
                      )}

                      {reversing === row.paymentId && (
                        <div className="mt-2 rounded-md bg-amber-50 p-3">{reverseForm(row)}</div>
                      )}

                      {isOpen && (
                        <div className="mt-2 rounded-md bg-slate-50 p-2">
                          {!allocations[row.paymentId] ? loadingAllocation : allocationCards(allocations[row.paymentId])}
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>

              {/* ---- lg and up: the full table ------------------------------- */}
              {/* Every cell in <Table> is whitespace-nowrap by default and the
                  component wraps itself in an overflow-x-auto div, so a wide
                  row can only ever scroll. Letting the text wrap lets the
                  columns shrink to the dialog instead -- nothing here is so
                  long that two lines hurt. The money and date cells use the
                  important form of nowrap, because this selector otherwise
                  out-specifies a plain whitespace-nowrap on the cell itself
                  and "GHS 2,000.00" would split at the space. */}
              <div className="hidden lg:block">
                <Table className="w-full [&_td]:whitespace-normal [&_th]:whitespace-normal">
                  <TableHeader>
                    {/* A header, not row zero: darker ground and a heavy rule
                        under it, so the eye has a hard line to start from. */}
                    <TableRow className="border-b-2 border-slate-300 bg-slate-300/60 hover:bg-slate-300/60 [&_th]:font-semibold [&_th]:text-slate-700">
                      <TableHead className="w-8" />
                      <TableHead>Date</TableHead>
                      <TableHead>Payment</TableHead>
                      <TableHead className="text-right">Amount</TableHead>
                      <TableHead>Method</TableHead>
                      <TableHead>Reference</TableHead>
                      <TableHead>Applied to</TableHead>
                      <TableHead>Source</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((row, i) => {
                      const isReversed = row.status === "Reversed"
                      const isOpen = expanded === row.paymentId
                      return (
                        <Fragment key={row.paymentId}>
                          {/* Three states worth a colour, in priority order.
                              OPEN wins: sky marks the payment whose allocation
                              is showing, and the panel below carries the same
                              tint so the two read as one block. REVERSED is
                              money that did not stay, so it recedes rather
                              than shouting. Everything else alternates, which
                              is what makes a long list scannable across ten
                              columns. */}
                          <TableRow
                            className={cn(
                              // A 4px bar down the first cell is what separates
                              // one payment from the next: it survives the
                              // zebra, and on the open row it runs straight
                              // into the allocation panel below, so the two
                              // read as one block rather than two rows.
                              "[&>*:first-child]:border-l-4",
                              isOpen
                                ? "bg-indigo-200/70 hover:bg-indigo-200/70 [&>*:first-child]:border-l-indigo-600"
                                : isReversed
                                  // Rose, not grey: a reversal is a state, and
                                  // a state deserves a colour you can find by
                                  // scrolling rather than by reading.
                                  ? "bg-rose-100/70 text-slate-400 [&>*:first-child]:border-l-rose-400"
                                  : cn(
                                      "[&>*:first-child]:border-l-transparent",
                                      i % 2 === 1 && "bg-slate-100",
                                    ),
                            )}
                          >
                            <TableCell>
                              <button type="button" onClick={() => toggle(row)} aria-label="Show allocation">
                                {isOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                              </button>
                            </TableCell>
                            <TableCell className="whitespace-nowrap!">{new Date(row.paymentDate).toLocaleDateString()}</TableCell>
                            <TableCell className="whitespace-nowrap! font-medium text-slate-700" title={row.paymentId}>
                              {paymentRef(row)}
                            </TableCell>
                            <TableCell className={`whitespace-nowrap! text-right font-medium ${isReversed ? "line-through" : ""}`}>
                              {fmt(row.totalAmount)}
                            </TableCell>
                            <TableCell>{row.paymentMethod ?? "—"}</TableCell>
                            <TableCell className="break-words">{row.reference ?? "—"}</TableCell>
                            <TableCell className="whitespace-nowrap!">{row.allocationCount} sale{row.allocationCount === 1 ? "" : "s"}</TableCell>
                            <TableCell className="text-xs text-slate-500" title={row.sourceType ?? undefined}>{sourceLabel(row.sourceType)}</TableCell>
                            <TableCell>
                              {statusBadge(row)}
                            </TableCell>
                            <TableCell className="text-right">
                              {canReverse && !isReversed && (
                                <Button variant="ghost" size="sm" className="text-slate-600 hover:bg-rose-50 hover:text-rose-700" onClick={() => { setReversing(row.paymentId); setReason("") }}>
                                  <Undo2 className="mr-1.5 h-3.5 w-3.5" /> Reverse
                                </Button>
                              )}
                            </TableCell>
                          </TableRow>

                          {isReversed && row.reversalReason && (
                            <TableRow className="border-b-2 border-rose-200 bg-rose-100/70 hover:bg-rose-100/70 [&>*:first-child]:border-l-4 [&>*:first-child]:border-l-rose-400">
                              <TableCell />
                              <TableCell colSpan={9} className="py-1 text-xs text-slate-500">
                                Reversed{row.reversedBy ? ` by ${row.reversedBy}` : ""}
                                {row.reversedAt ? ` on ${new Date(row.reversedAt).toLocaleDateString()}` : ""}: {row.reversalReason}
                              </TableCell>
                            </TableRow>
                          )}

                          {reversing === row.paymentId && (
                            <TableRow className="bg-amber-50">
                              <TableCell />
                              <TableCell colSpan={9} className="py-3">{reverseForm(row)}</TableCell>
                            </TableRow>
                          )}

                          {isOpen && (
                            <TableRow className="border-b-2 border-indigo-300 bg-indigo-100 hover:bg-indigo-100 [&>*:first-child]:border-l-4 [&>*:first-child]:border-l-indigo-600">
                              <TableCell />
                              <TableCell colSpan={9} className="py-3">
                                {!allocations[row.paymentId] ? loadingAllocation : (
                                  /* A panel, not a second full-width table. Auto
                                     layout spread these six columns across the
                                     whole dialog, so the headings sat in the
                                     middle of nowhere with the numbers nowhere
                                     near them. table-fixed with declared widths
                                     puts every heading directly over its own
                                     column, and the left rule plus the indent
                                     say this belongs to the payment above it
                                     rather than being a second list. */
                                  <div className="rounded-lg border border-indigo-300 bg-white p-2 shadow-sm">
                                    <div className="mb-1.5 px-1 text-[11px] font-semibold uppercase tracking-wide text-indigo-800">
                                      Applied to
                                    </div>
                                    <Table className="w-full table-fixed overflow-hidden rounded-md [&_td]:whitespace-normal [&_th]:whitespace-normal">
                                      <colgroup>
                                        <col className="w-[12%]" />
                                        <col className="w-[20%]" />
                                        <col className="w-[13%]" />
                                        <col className="w-[14%]" />
                                        <col className="w-[14%]" />
                                        <col className="w-[13%]" />
                                        <col className="w-[14%]" />
                                      </colgroup>
                                      <TableHeader>
                                        <TableRow className="border-b border-indigo-300 bg-indigo-200/70 hover:bg-indigo-200/70 [&_th]:font-semibold [&_th]:text-indigo-900">
                                          <TableHead>{side === "customer" ? "Sale" : "Purchase"}</TableHead>
                                          <TableHead>Description</TableHead>
                                          <TableHead>Date</TableHead>
                                          <TableHead className="text-right">Total</TableHead>
                                          <TableHead className="text-right">Balance before</TableHead>
                                          <TableHead className="text-right">Applied</TableHead>
                                          <TableHead className="text-right">Balance after</TableHead>
                                        </TableRow>
                                      </TableHeader>
                                      <TableBody>
                                        {allocations[row.paymentId].map((a) => (
                                          <TableRow key={a.allocationId}>
                                            <TableCell className="whitespace-nowrap! font-medium">
                                              {a.reference ?? a.documentId}
                                            </TableCell>
                                            <TableCell className="text-slate-600">{a.label ?? "—"}</TableCell>
                                            <TableCell className="whitespace-nowrap!">{a.documentDate ? new Date(a.documentDate).toLocaleDateString() : "—"}</TableCell>
                                            <TableCell className="whitespace-nowrap! text-right">{fmt(a.documentTotal)}</TableCell>
                                            <TableCell className="whitespace-nowrap! text-right text-slate-500">{fmt(a.balanceBefore)}</TableCell>
                                            {/* Applied is money that moved; the
                                                balance after says whether the
                                                sale is done. Green for settled,
                                                amber for still owing -- the same
                                                pair the balances page uses. */}
                                            <TableCell className="whitespace-nowrap! text-right font-semibold text-emerald-700">{fmt(a.amountApplied)}</TableCell>
                                            <TableCell
                                              className={cn(
                                                "whitespace-nowrap! text-right font-medium",
                                                a.balanceAfter <= 0 ? "text-emerald-700" : "text-amber-700",
                                              )}
                                            >
                                              {fmt(a.balanceAfter)}
                                            </TableCell>
                                          </TableRow>
                                        ))}
                                      </TableBody>
                                    </Table>
                                  </div>
                                )}
                              </TableCell>
                            </TableRow>
                          )}
                        </Fragment>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
            </>
          )}
        </div>

        <DialogFooter>
          <Button className="h-10 w-full sm:h-9 sm:w-auto" onClick={() => onOpenChange(false)}>Close</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

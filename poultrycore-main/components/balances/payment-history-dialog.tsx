"use client"

// Payment history, with the allocation behind each payment.
//
// Every payment expands to show exactly which sales or purchases it settled and
// what each one's balance was before and after -- the audit trail that makes a
// bulk payment explainable six months later. Reversal lives here too, because
// this is the only screen that shows enough context to reverse the right one.

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

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[92vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Payment history</DialogTitle>
          <DialogDescription>
            {partyName ?? (side === "customer" ? "All customers" : "All suppliers")}
            {documentId ? ` · ${documentType ?? ""} #${documentId}` : ""}
          </DialogDescription>
        </DialogHeader>

        <div className="overflow-x-auto rounded-md border">
          {loading ? (
            <div className="flex items-center gap-2 p-6 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <div className="p-8 text-center text-slate-500">No payments recorded yet.</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-8" />
                  <TableHead>Date</TableHead>
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
                {rows.map((row) => {
                  const isReversed = row.status === "Reversed"
                  const isOpen = expanded === row.paymentId
                  return (
                    <Fragment key={row.paymentId}>
                      <TableRow className={isReversed ? "text-slate-400" : undefined}>
                        <TableCell>
                          <button type="button" onClick={() => toggle(row)} aria-label="Show allocation">
                            {isOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                          </button>
                        </TableCell>
                        <TableCell className="whitespace-nowrap">{new Date(row.paymentDate).toLocaleDateString()}</TableCell>
                        <TableCell className={`text-right font-medium ${isReversed ? "line-through" : ""}`}>
                          {fmt(row.totalAmount)}
                        </TableCell>
                        <TableCell>{row.paymentMethod ?? "—"}</TableCell>
                        <TableCell>{row.reference ?? "—"}</TableCell>
                        <TableCell>{row.allocationCount} item{row.allocationCount === 1 ? "" : "s"}</TableCell>
                        <TableCell className="text-xs text-slate-500">{row.sourceType ?? "—"}</TableCell>
                        <TableCell>
                          {isReversed
                            ? <Badge variant="outline" className="text-slate-500">Reversed</Badge>
                            : <Badge variant="secondary">Posted</Badge>}
                        </TableCell>
                        <TableCell className="text-right">
                          {canReverse && !isReversed && (
                            <Button variant="ghost" size="sm" onClick={() => { setReversing(row.paymentId); setReason("") }}>
                              <Undo2 className="mr-1.5 h-3.5 w-3.5" /> Reverse
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>

                      {isReversed && row.reversalReason && (
                        <TableRow>
                          <TableCell />
                          <TableCell colSpan={8} className="py-1 text-xs text-slate-500">
                            Reversed{row.reversedBy ? ` by ${row.reversedBy}` : ""}
                            {row.reversedAt ? ` on ${new Date(row.reversedAt).toLocaleDateString()}` : ""}: {row.reversalReason}
                          </TableCell>
                        </TableRow>
                      )}

                      {reversing === row.paymentId && (
                        <TableRow className="bg-amber-50">
                          <TableCell />
                          <TableCell colSpan={8} className="py-3">
                            <div className="flex flex-wrap items-end gap-2">
                              <div className="min-w-[18rem] flex-1 space-y-1.5">
                                <Label htmlFor={`reason-${row.paymentId}`}>Why is this being reversed?</Label>
                                <Input
                                  id={`reason-${row.paymentId}`}
                                  value={reason}
                                  onChange={(e) => setReason(e.target.value)}
                                  placeholder="e.g. entered twice"
                                />
                              </div>
                              <Button size="sm" variant="destructive" onClick={() => doReverse(row)}>Reverse payment</Button>
                              <Button size="sm" variant="ghost" onClick={() => setReversing(null)}>Cancel</Button>
                            </div>
                            <p className="mt-2 text-xs text-slate-500">
                              The balance goes back onto the {side === "customer" ? "sales" : "purchases"} it was applied to and the
                              cash movement is undone. The payment is kept and marked reversed, never deleted.
                            </p>
                          </TableCell>
                        </TableRow>
                      )}

                      {isOpen && (
                        <TableRow>
                          <TableCell />
                          <TableCell colSpan={8} className="py-2">
                            {!allocations[row.paymentId] ? (
                              <span className="flex items-center gap-2 text-sm text-slate-500">
                                <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading allocation…
                              </span>
                            ) : (
                              <Table>
                                <TableHeader>
                                  <TableRow>
                                    <TableHead>{side === "customer" ? "Sale" : "Purchase"}</TableHead>
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
                                      <TableCell className="font-medium">
                                        {a.reference ?? a.documentId}
                                        {a.label ? <span className="block text-xs text-slate-500">{a.label}</span> : null}
                                      </TableCell>
                                      <TableCell>{a.documentDate ? new Date(a.documentDate).toLocaleDateString() : "—"}</TableCell>
                                      <TableCell className="text-right">{fmt(a.documentTotal)}</TableCell>
                                      <TableCell className="text-right text-slate-500">{fmt(a.balanceBefore)}</TableCell>
                                      <TableCell className="text-right font-medium">{fmt(a.amountApplied)}</TableCell>
                                      <TableCell className="text-right">{fmt(a.balanceAfter)}</TableCell>
                                    </TableRow>
                                  ))}
                                </TableBody>
                              </Table>
                            )}
                          </TableCell>
                        </TableRow>
                      )}
                    </Fragment>
                  )
                })}
              </TableBody>
            </Table>
          )}
        </div>

        <DialogFooter>
          <Button onClick={() => onOpenChange(false)}>Close</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

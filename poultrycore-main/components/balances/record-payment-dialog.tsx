"use client"

// Receive Payment / Record Supplier Payment.
//
// The allocation grid is the point of this dialog: one amount coming in, spread
// across the specific sales or purchases it settles. It opens in two modes —
// against a single document (from a row's "Receive payment") or against every
// open document for the party (from "Receive bulk payment") — and both post
// through the same endpoint, so a single-line payment is just a bulk payment
// with one line.
//
// The maths lives in lib/balances/allocate.ts, in integer pesewas. The server
// enforces every rule again; this is here so the user sees the problem while
// they can still fix it.

import { useEffect, useMemo, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AlertTriangle, Loader2, Wand2, X } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import {
  autoAllocateOldestFirst, balanceAfter, docKey, totalAllocated, totalOpenBalance,
  validateAllocations, type AllocationMap,
} from "@/lib/balances/allocate"
import type { BalanceModule, BalanceSide, OpenDocumentRow, PartyBalanceRow } from "@/lib/api/balances"
import { listOpenDocuments, recordPayment } from "@/lib/api/balances"
import { entryTimestamp } from "@/lib/utils/date-key"

const PAYMENT_METHODS = ["Cash", "MoMo", "Bank Transfer", "Cheque", "Card", "Other"] as const

export interface CashAccountOption {
  id: number
  name: string
  currentBalance?: number
  allowNegativeBalance?: boolean
}

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
  module: BalanceModule
  side: BalanceSide
  party: PartyBalanceRow | null
  /** Set to pre-scope the dialog to one row; null opens the full bulk grid. */
  singleDocument?: OpenDocumentRow | null
  cashAccounts: CashAccountOption[]
  /**
   * Where the payment was entered from, recorded on the payment header so the
   * Supplier Payments ledger can say so. Defaults to the balances page, which is
   * where this dialog is opened from everywhere except the Expenses page.
   */
  sourceType?: string
  onPosted: () => void
}

export function RecordPaymentDialog({
  open, onOpenChange, module, side, party, singleDocument = null, cashAccounts, sourceType, onPosted,
}: Props) {
  const fmt = useFmt()
  const { toast } = useToast()
  const isCustomer = side === "customer"

  const [documents, setDocuments] = useState<OpenDocumentRow[]>([])
  const [loading, setLoading] = useState(false)
  const [posting, setPosting] = useState(false)

  const [amount, setAmount] = useState("")
  const [paymentDate, setPaymentDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [method, setMethod] = useState<string>("Cash")
  const [cashAccountId, setCashAccountId] = useState<number | null>(null)
  const [reference, setReference] = useState("")
  const [notes, setNotes] = useState("")
  const [allocation, setAllocation] = useState<AllocationMap>({})
  const [touched, setTouched] = useState(false)

  // Load the lines this payment can be spread over. A single-document payment
  // still goes through the grid, so the two modes cannot drift apart.
  useEffect(() => {
    if (!open || !party) return
    let cancelled = false
    setTouched(false)

    if (singleDocument) {
      setDocuments([singleDocument])
      setAmount(singleDocument.balance.toFixed(2))
      setAllocation({ [docKey(singleDocument)]: singleDocument.balance })
      setCashAccountId(singleDocument.cashAccountId ?? null)
      return
    }

    setLoading(true)
    setAllocation({})
    setAmount("")
    ;(async () => {
      try {
        const rows = await listOpenDocuments(module, side, party.partyId)
        if (!cancelled) setDocuments(rows)
      } catch (e: any) {
        if (!cancelled) {
          toast({ title: "Could not load open items", description: e?.message ?? String(e), variant: "destructive" })
          onOpenChange(false)
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, party?.partyId, singleDocument?.documentId, module, side])

  const openTotal = useMemo(() => totalOpenBalance(documents), [documents])
  const allocated = useMemo(() => totalAllocated(allocation), [allocation])

  const selectedAccount = cashAccounts.find((a) => a.id === cashAccountId) ?? null

  const validation = useMemo(
    () => validateAllocations(Number(amount) || 0, documents, allocation, {
      // Customer payments credit whichever account the sale is filed against, so
      // the field is optional there. A supplier payment has to name the account
      // the money physically left, and the server refuses without one when the
      // account would go negative.
      cashAccountRequired: !isCustomer,
      cashAccountId,
    }),
    [amount, documents, allocation, cashAccountId, isCustomer],
  )

  // Would this payment overdraw the account? The server blocks it too; catching
  // it here saves a round trip and names the account.
  const overdraws = useMemo(() => {
    if (isCustomer || !selectedAccount || selectedAccount.allowNegativeBalance) return false
    if (selectedAccount.currentBalance === undefined) return false
    return selectedAccount.currentBalance - (Number(amount) || 0) < 0
  }, [isCustomer, selectedAccount, amount])

  const autoAllocate = () => {
    setTouched(true)
    setAllocation(autoAllocateOldestFirst(Number(amount) || 0, documents))
  }

  const clearAllocation = () => {
    setTouched(true)
    setAllocation({})
  }

  const setLine = (doc: OpenDocumentRow, raw: string) => {
    setTouched(true)
    const value = Number(raw)
    setAllocation((prev) => {
      const next = { ...prev }
      if (!raw || Number.isNaN(value) || value === 0) delete next[docKey(doc)]
      else next[docKey(doc)] = value
      return next
    })
  }

  // The picker is date-only, so `new Date("2026-08-27").toISOString()` stamps
  // every payment at midnight — which is why the Payments list read back
  // "12:00:00 AM" for a payment taken at 8am. A payment dated today gets the
  // real clock time (UTC, matching the SP's `now() at time zone 'utc'`
  // default and the /sales payment path, which sends no date at all). A
  // deliberately back-dated one keeps midnight: its true time is unknown.
  // Shared with the cash adjustment dialog: a rule about where a new row sorts
  // is not something two screens should each decide for themselves.
  const paymentTimestamp = () => entryTimestamp(paymentDate)

  const submit = async () => {
    if (!party) return
    setTouched(true)
    if (!validation.ok || overdraws) return

    setPosting(true)
    try {
      await recordPayment(module, side, {
        partyId: party.partyId,
        amount: Number(amount),
        paymentDate: paymentTimestamp(),
        paymentMethod: method,
        cashAccountId,
        reference: reference.trim() || null,
        notes: notes.trim() || null,
        sourceType: sourceType ?? (isCustomer ? "CustomerBalances" : "SupplierBalances"),
        allocations: documents
          .filter((d) => (allocation[docKey(d)] ?? 0) > 0)
          .map((d) => ({
            saleId: isCustomer ? d.documentId : undefined,
            documentType: d.documentType,
            documentId: d.documentId,
            amount: allocation[docKey(d)],
          })),
      })
      toast({
        title: isCustomer ? "Payment received" : "Payment recorded",
        description: `${fmt(Number(amount))} applied across ${Object.keys(allocation).length} item(s).`,
      })
      onOpenChange(false)
      onPosted()
    } catch (e: any) {
      toast({
        title: isCustomer ? "Could not receive payment" : "Could not record payment",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setPosting(false)
    }
  }

  const blockingProblems = validation.problems.filter((p) => p.key === null)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[92vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {isCustomer
              ? singleDocument ? "Receive payment" : "Receive bulk payment"
              : singleDocument ? "Record payment" : "Record bulk payment"}
          </DialogTitle>
          <DialogDescription>
            {party?.partyName}
            {" · "}
            {singleDocument
              ? `${singleDocument.reference ?? singleDocument.documentId} · ${fmt(singleDocument.balance)} outstanding`
              : `${fmt(openTotal)} outstanding across ${documents.length} open item(s)`}
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div className="space-y-1.5">
            <Label htmlFor="pay-amount">Payment amount</Label>
            <Input
              id="pay-amount" type="number" min="0" step="0.01" inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-date">Payment date</Label>
            <Input id="pay-date" type="date" value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Payment method</Label>
            <Select value={method} onValueChange={setMethod}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Cash account{isCustomer ? " (optional)" : ""}</Label>
            <Select
              value={cashAccountId ? String(cashAccountId) : ""}
              onValueChange={(v) => setCashAccountId(v ? Number(v) : null)}
            >
              <SelectTrigger><SelectValue placeholder="Select account" /></SelectTrigger>
              <SelectContent>
                {cashAccounts.map((a) => (
                  <SelectItem key={a.id} value={String(a.id)}>
                    {a.name}
                    {a.currentBalance !== undefined ? ` · ${fmt(a.currentBalance)}` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-ref">Reference</Label>
            <Input id="pay-ref" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-notes">Notes</Label>
            <Textarea id="pay-notes" rows={1} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" />
          </div>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2 border-t pt-3">
          <div className="flex items-center gap-2">
            <Button type="button" variant="outline" size="sm" onClick={autoAllocate} disabled={!amount || loading}>
              <Wand2 className="mr-1.5 h-3.5 w-3.5" /> Auto-allocate oldest first
            </Button>
            <Button type="button" variant="ghost" size="sm" onClick={clearAllocation} disabled={loading}>
              <X className="mr-1.5 h-3.5 w-3.5" /> Clear
            </Button>
          </div>
          <div className="text-sm">
            <span className="text-slate-500">Allocated </span>
            <span className="font-medium">{fmt(allocated)}</span>
            <span className="text-slate-400"> / {fmt(Number(amount) || 0)}</span>
            {validation.unallocated !== 0 && (
              <span className={validation.unallocated > 0 ? "ml-2 text-amber-600" : "ml-2 text-red-600"}>
                ({validation.unallocated > 0 ? `${fmt(validation.unallocated)} unallocated` : `${fmt(-validation.unallocated)} over`})
              </span>
            )}
          </div>
        </div>

        <div className="overflow-x-auto rounded-md border">
          {loading ? (
            <div className="flex items-center gap-2 p-6 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading open items…
            </div>
          ) : documents.length === 0 ? (
            <div className="p-8 text-center text-slate-500">Nothing outstanding for this {isCustomer ? "customer" : "supplier"}.</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{isCustomer ? "Sale" : "Purchase"}</TableHead>
                  <TableHead>Date</TableHead>
                  <TableHead className="text-right">Total</TableHead>
                  <TableHead className="text-right">Paid</TableHead>
                  <TableHead className="text-right">Balance</TableHead>
                  <TableHead className="text-right w-40">Amount to apply</TableHead>
                  <TableHead className="text-right">Balance after</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {documents.map((d) => {
                  const key = docKey(d)
                  const over = validation.overAllocated[key]
                  return (
                    <TableRow key={key} className={over ? "bg-red-50" : undefined}>
                      <TableCell className="font-medium">
                        {d.reference ?? d.documentId}
                        {d.label ? <span className="block text-xs text-slate-500">{d.label}</span> : null}
                      </TableCell>
                      <TableCell className="whitespace-nowrap">
                        {new Date(d.documentDate).toLocaleDateString()}
                        {d.isOverdue && (
                          <span className="ml-1.5 rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-medium text-red-700">
                            {d.ageDays}d
                          </span>
                        )}
                      </TableCell>
                      <TableCell className="text-right">{fmt(d.totalAmount)}</TableCell>
                      <TableCell className="text-right text-slate-500">{fmt(d.amountPaid)}</TableCell>
                      <TableCell className="text-right font-medium">{fmt(d.balance)}</TableCell>
                      <TableCell className="text-right">
                        <Input
                          type="number" min="0" max={d.balance} step="0.01" inputMode="decimal"
                          className={`h-8 text-right ${over ? "border-red-400" : ""}`}
                          value={allocation[key] ?? ""}
                          onChange={(e) => setLine(d, e.target.value)}
                          placeholder="0.00"
                        />
                      </TableCell>
                      <TableCell className="text-right">{fmt(balanceAfter(d, allocation))}</TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          )}
        </div>

        {touched && (blockingProblems.length > 0 || overdraws) && (
          <Alert variant="destructive">
            <AlertTriangle className="h-4 w-4" />
            <AlertDescription>
              <ul className="list-inside list-disc space-y-0.5">
                {blockingProblems.map((p, i) => <li key={i}>{p.message}</li>)}
                {overdraws && selectedAccount && (
                  <li>
                    {selectedAccount.name} holds {fmt(selectedAccount.currentBalance ?? 0)} — this payment would overdraw it.
                  </li>
                )}
              </ul>
            </AlertDescription>
          </Alert>
        )}

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={posting}>Cancel</Button>
          <Button onClick={submit} disabled={posting || loading || !validation.ok || overdraws}>
            {posting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {isCustomer ? "Receive payment" : "Record payment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

"use client"

// Receive Payment / Record Supplier Payment.
//
// The allocation grid is the point of this dialog: one amount coming in, spread
// across the specific sales or purchases it settles. It opens in two modes —
// against a single document (from a row's "Receive payment") or against every
// open document for the party (from the summary row) — and both post through
// the same endpoint, so a single-line payment is just a bulk payment with one
// line.
//
// The maths lives in lib/balances/allocate.ts, in integer pesewas. The server
// enforces every rule again; this is here so the user sees the problem while
// they can still fix it.
//
// With only one line to pay -- because a row's button scoped it, or because the
// party simply has one open item -- the grid is hidden: there is nothing to
// choose, so the line follows the payment amount and a summary card stands in
// for the table. It still posts as a one-line allocation.
//
// The amount opens at the full amount owed, already spread over every line. Until
// the user types into a line, changing the amount re-spreads it oldest first, so
// paying less than the whole never leaves the grid over-allocated.

import { useEffect, useMemo, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Checkbox } from "@/components/ui/checkbox"
import { AlertTriangle, Loader2, Wallet, Wand2, X } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { cn } from "@/lib/utils"
import {
  autoAllocateOldestFirst, balanceAfter, docKey, totalAllocated, totalOpenBalance,
  validateAllocations, type AllocationMap,
} from "@/lib/balances/allocate"
import type { BalanceModule, BalanceSide, OpenDocumentRow, PartyBalanceRow } from "@/lib/api/balances"
import { listOpenDocuments, recordPayment } from "@/lib/api/balances"
import { entryTimestamp } from "@/lib/utils/date-key"
import { fmtDateTime } from "@/lib/utils/company-datetime"

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
  /**
   * 383 (poultry: Record customer / supplier payment): money not applied to
   * anything paid something owed from before the system -- recorded as that debt
   * and paid now, so it is on Profit & Loss -- unless the user keeps it as credit.
   */
  remainderAsOldDebt?: boolean
  onPosted: () => void
}

export function RecordPaymentDialog({
  open, onOpenChange, module, side, party, singleDocument = null, cashAccounts, sourceType, remainderAsOldDebt = false, onPosted,
}: Props) {
  const fmt = useFmt()
  const { toast } = useToast()
  const isCustomer = side === "customer"
  // 367 / 370: a poultry payment need not be applied in full -- the rest is
  // kept as the customer's / supplier's credit (applied to nothing = an advance).
  const allowUnallocated = module === "poultry"
  const creditWord = isCustomer ? "customer credit" : "supplier credit"
  const docWord = isCustomer ? "sale" : "purchase"
  const { isAdmin } = usePermissions()

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
  // Once a line is typed into, the grid is the user's: the amount stops re-spreading it.
  const [linesEdited, setLinesEdited] = useState(false)
  // 382: money on a debt is on Profit & Loss unless the owner / an admin says not.
  const [countOnPL, setCountOnPL] = useState(true)
  // 383: the leftover is an old debt by default; the user can keep it as credit instead.
  const [keepAsCredit, setKeepAsCredit] = useState(false)

  // Load the lines this payment can be spread over. A single-document payment
  // still goes through the grid, so the two modes cannot drift apart.
  useEffect(() => {
    if (!open || !party) return
    let cancelled = false
    setTouched(false)
    setLinesEdited(false)
    setCountOnPL(true)
    setKeepAsCredit(false)

    if (singleDocument) {
      setDocuments([singleDocument])
      setAmount(singleDocument.balance.toFixed(2))
      setAllocation({ [docKey(singleDocument)]: singleDocument.balance })
      setCashAccountId(singleDocument.cashAccountId ?? null)
      return
    }

    setLoading(true)
    setDocuments([])
    setAllocation({})
    setAmount("")
    ;(async () => {
      try {
        const rows = await listOpenDocuments(module, side, party.partyId)
        if (cancelled) return
        setDocuments(rows)
        // Default to settling everything owed: the common case is paying in full.
        const owed = totalOpenBalance(rows)
        if (owed > 0) {
          setAmount(owed.toFixed(2))
          setAllocation(autoAllocateOldestFirst(owed, rows))
        }
        if (rows.length === 1) setCashAccountId(rows[0].cashAccountId ?? null)
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

  // The one line being paid, when there is only one -- scoped by the caller, or
  // the only thing this party owes. Either way there is no grid to choose from.
  const single: OpenDocumentRow | null = singleDocument ?? (!loading && documents.length === 1 ? documents[0] : null)
  const isBulk = !single && (loading ? (party?.openDocumentCount ?? 0) > 1 : documents.length > 1)

  const openTotal = useMemo(() => totalOpenBalance(documents), [documents])
  const allocated = useMemo(() => totalAllocated(allocation), [allocation])
  const amountValue = Number(amount) || 0

  // 382: the part paid on debts recorded by hand -- the only part that is new to
  // Profit & Loss (a sale or purchase is already on it).
  const recordedDebtAllocated = useMemo(() => module !== "poultry" ? 0 : documents
    .filter((d) => d.documentType === "CustomerDebt" || d.documentType === "SupplierDebt")
    .reduce((t, d) => t + (allocation[docKey(d)] ?? 0), 0), [module, documents, allocation])

  const selectedAccount = cashAccounts.find((a) => a.id === cashAccountId) ?? null

  const validation = useMemo(
    () => validateAllocations(amountValue, documents, allocation, {
      // Customer payments credit whichever account the sale is filed against, so
      // the field is optional there. A supplier payment has to name the account
      // the money physically left, and the server refuses without one when the
      // account would go negative.
      cashAccountRequired: !isCustomer,
      cashAccountId,
      allowUnallocated,
    }),
    [amountValue, documents, allocation, cashAccountId, isCustomer, allowUnallocated],
  )

  // 383: what is left over pays an old debt, unless kept as credit.
  const oldDebt = remainderAsOldDebt && allowUnallocated && !keepAsCredit && validation.unallocated > 0
    ? validation.unallocated : 0
  const debtAllocated = recordedDebtAllocated + oldDebt
  const leftoverWord = oldDebt > 0 ? (isCustomer ? "old customer debt" : "old supplier debt") : creditWord

  // Would this payment overdraw the account? The server blocks it too; catching
  // it here saves a round trip and names the account.
  const overdraws = useMemo(() => {
    if (isCustomer || !selectedAccount || selectedAccount.allowNegativeBalance) return false
    if (selectedAccount.currentBalance === undefined) return false
    return selectedAccount.currentBalance - amountValue < 0
  }, [isCustomer, selectedAccount, amountValue])

  const autoAllocate = () => {
    setTouched(true)
    setLinesEdited(false)
    setAllocation(autoAllocateOldestFirst(amountValue, documents))
  }

  const clearAllocation = () => {
    setTouched(true)
    setLinesEdited(true)
    setAllocation({})
  }

  // One line: it tracks the amount. Several: the amount re-spreads oldest first
  // until the user has typed into a line themselves.
  const changeAmount = (raw: string) => {
    setAmount(raw)
    setTouched(true)
    const value = Number(raw)
    const empty = !raw || Number.isNaN(value) || value <= 0
    if (single) {
      // 367: paying more than the line owes keeps the rest as credit.
      const applied = allowUnallocated ? Math.min(value, single.balance) : value
      setAllocation(empty ? {} : { [docKey(single)]: applied })
    } else if (!linesEdited) {
      setAllocation(empty ? {} : autoAllocateOldestFirst(value, documents))
    }
  }

  const setLine = (doc: OpenDocumentRow, raw: string) => {
    setTouched(true)
    setLinesEdited(true)
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
        amount: amountValue,
        paymentDate: paymentTimestamp(),
        paymentMethod: method,
        cashAccountId,
        reference: reference.trim() || null,
        notes: notes.trim() || null,
        sourceType: sourceType ?? (isCustomer ? "CustomerBalances" : "SupplierBalances"),
        allocations: documents
          .filter((d) => (allocation[docKey(d)] ?? 0) > 0)
          .map((d) => ({
            // 369: a customer debt goes as its own document type, never as a sale id.
            saleId: isCustomer && d.documentType !== "CustomerDebt" ? d.documentId : undefined,
            documentType: d.documentType,
            documentId: d.documentId,
            amount: allocation[docKey(d)],
          })),
        excludeFromPL: debtAllocated > 0 && !countOnPL,
        remainderAsOldDebt: oldDebt > 0,
      })
      toast({
        title: isCustomer ? "Payment received" : "Payment recorded",
        description: `${fmt(amountValue)} applied across ${Object.keys(allocation).length} item(s).`,
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

  // With the grid hidden, a line problem (e.g. paying more than the balance)
  // has nowhere else to show, so every problem goes in the alert.
  const blockingProblems = single
    ? validation.problems
    : validation.problems.filter((p) => p.key === null)

  const owedAfter = Math.max(0, openTotal - allocated)
  const fullAmount = single ? single.balance : openTotal
  const isFullAmount = Math.abs(amountValue - fullAmount) < 0.005

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      {/* The width MUST carry the sm: prefix. An unprefixed `max-w-4xl` does
          not override the `sm:max-w-2xl` in ui/dialog.tsx -- tailwind-merge
          only drops a class conflicting under the SAME modifier -- so this
          dialog was silently pinned to 672px and the allocation table below was
          squeezing seven columns into it. The paired `w-[95vw] max-w-[95vw]`
          puts the mobile gutter back, which the unprefixed value had also
          taken. Same shape as the statement and history dialogs beside it. */}
      <DialogContent className={cn("w-[95vw] max-w-[95vw] max-h-[92vh] gap-5 overflow-y-auto p-4 sm:p-6", isBulk ? "sm:max-w-4xl" : "sm:max-w-2xl")}>
        <DialogHeader className="flex-row items-center gap-3 space-y-0 text-left">
          <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
            isCustomer ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700")}>
            <Wallet className="h-5 w-5" />
          </div>
          <div className="min-w-0">
            <DialogTitle>
              {isCustomer
                ? isBulk ? "Receive bulk payment" : "Receive payment"
                : isBulk ? "Record bulk payment" : "Record payment"}
            </DialogTitle>
            <DialogDescription className="truncate">
              {party?.partyName}
              {single ? ` · ${single.reference ?? single.documentId}` : ""}
            </DialogDescription>
          </div>
        </DialogHeader>

        {/* Where the money stands, live: what is owed, what this payment pays, what is left. */}
        <div className="grid grid-cols-3 divide-x rounded-lg border bg-slate-50">
          <div className="px-3 py-2.5">
            <p className="text-[11px] font-medium uppercase tracking-wide text-slate-500">Outstanding</p>
            <p className="text-lg font-semibold tabular-nums text-slate-900">{loading ? "…" : fmt(openTotal)}</p>
            {!loading && isBulk && <p className="text-xs text-slate-500">{documents.length} open {docWord}s</p>}
          </div>
          <div className="px-3 py-2.5">
            <p className="text-[11px] font-medium uppercase tracking-wide text-slate-500">This payment</p>
            <p className={cn("text-lg font-semibold tabular-nums", isCustomer ? "text-emerald-700" : "text-amber-700")}>{fmt(amountValue)}</p>
          </div>
          <div className="px-3 py-2.5">
            <p className="text-[11px] font-medium uppercase tracking-wide text-slate-500">Still owed after</p>
            <p className={cn("text-lg font-semibold tabular-nums", owedAfter > 0 ? "text-slate-900" : "text-emerald-700")}>
              {loading ? "…" : owedAfter > 0 ? fmt(owedAfter) : "Settled"}
            </p>
          </div>
        </div>

        <div className="grid gap-x-4 gap-y-3 sm:grid-cols-3">
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <Label htmlFor="pay-amount">Payment amount</Label>
              {!loading && fullAmount > 0 && !isFullAmount && (
                <button type="button" className="text-xs font-medium text-blue-700 hover:underline" onClick={() => changeAmount(fullAmount.toFixed(2))}>
                  Pay in full
                </button>
              )}
            </div>
            <Input
              id="pay-amount" type="number" min="0" step="0.01" inputMode="decimal"
              className="text-right font-semibold tabular-nums"
              value={amount}
              onChange={(e) => changeAmount(e.target.value)}
              placeholder="0.00"
              disabled={loading}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-date">Payment date</Label>
            <Input id="pay-date" type="date" value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Payment method</Label>
            <Select value={method} onValueChange={setMethod}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Cash account{isCustomer ? <span className="font-normal text-slate-400"> (optional)</span> : null}</Label>
            <Select
              value={cashAccountId ? String(cashAccountId) : ""}
              onValueChange={(v) => setCashAccountId(v ? Number(v) : null)}
            >
              <SelectTrigger className="w-full"><SelectValue placeholder="Select account" /></SelectTrigger>
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
            <Label htmlFor="pay-ref">Reference <span className="font-normal text-slate-400">(optional)</span></Label>
            <Input id="pay-ref" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="e.g. MoMo ID, cheque no." />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-notes">Notes <span className="font-normal text-slate-400">(optional)</span></Label>
            <Input id="pay-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Anything to remember" />
          </div>
        </div>

        {single ? (
          <div className="rounded-lg border px-3 py-2.5 text-sm">
            <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
              <div className="min-w-0">
                <span className="text-slate-500">Applies to </span>
                <span className="font-medium text-slate-900">{single.reference ?? single.documentId}</span>
                {single.label ? <span className="text-slate-500"> · {single.label}</span> : null}
                <span className="text-slate-400"> · {fmtDateTime(single.documentDate, single)}</span>
                {single.isOverdue && (
                  <span className="ml-1.5 rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-medium text-red-700">{single.ageDays}d overdue</span>
                )}
              </div>
              <div className="whitespace-nowrap tabular-nums">
                <span className="text-slate-500">{fmt(single.balance)} → </span>
                <span className={cn("font-semibold", balanceAfter(single, allocation) < 0 ? "text-red-600" : "text-slate-900")}>
                  {fmt(balanceAfter(single, allocation))}
                </span>
              </div>
            </div>
            {allowUnallocated && validation.unallocated > 0 && !remainderAsOldDebt && (
              <p className="mt-1 text-xs text-blue-700">{fmt(validation.unallocated)} over the balance is kept as {creditWord}.</p>
            )}
          </div>
        ) : (
          <div className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="text-sm">
                <span className="font-medium text-slate-900">Apply to open {docWord}s</span>
                <span className="ml-2 text-slate-500">
                  {fmt(allocated)} of {fmt(amountValue)} allocated
                </span>
                {validation.unallocated !== 0 && (
                  <span className={cn("ml-1",
                    validation.unallocated > 0 ? (allowUnallocated ? "text-blue-700" : "text-amber-600") : "text-red-600")}>
                    · {validation.unallocated > 0
                      ? allowUnallocated
                        ? `${fmt(validation.unallocated)} ${oldDebt > 0 ? "pays an" : "kept as"} ${leftoverWord}`
                        : `${fmt(validation.unallocated)} unallocated`
                      : `${fmt(-validation.unallocated)} over`}
                  </span>
                )}
              </div>
              <div className="flex items-center gap-1">
                <Button type="button" variant="outline" size="sm" onClick={autoAllocate} disabled={!amount || loading}>
                  <Wand2 className="mr-1.5 h-3.5 w-3.5" /> Oldest first
                </Button>
                <Button type="button" variant="ghost" size="sm" onClick={clearAllocation} disabled={loading}>
                  <X className="mr-1.5 h-3.5 w-3.5" /> Clear
                </Button>
              </div>
            </div>

            <div className="overflow-x-auto rounded-lg border">
              {loading ? (
                <div className="flex items-center gap-2 p-6 text-slate-500">
                  <Loader2 className="h-4 w-4 animate-spin" /> Loading open items…
                </div>
              ) : documents.length === 0 ? (
                <div className="p-8 text-center text-slate-500">Nothing outstanding for this {isCustomer ? "customer" : "supplier"}.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow className="bg-slate-50 hover:bg-slate-50">
                      <TableHead className="capitalize">{docWord}</TableHead>
                      {/* What the document was for, in its own column. Stacked
                          under the reference it read as part of the number --
                          "S2222 Fresh Eggs" -- and made the row two lines tall for
                          a value that is really a second field. */}
                      <TableHead>Item</TableHead>
                      <TableHead>Date</TableHead>
                      {/* Balance carries the total under it rather than Total and
                          Paid each taking a column: the grid fits without a
                          sideways scroll, and paid = total − balance is plain. */}
                      <TableHead className="text-right">Balance</TableHead>
                      <TableHead className="w-36 text-right">Amount to apply</TableHead>
                      <TableHead className="text-right">After</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {documents.map((d) => {
                      const key = docKey(d)
                      const over = validation.overAllocated[key]
                      const after = balanceAfter(d, allocation)
                      return (
                        <TableRow key={key} className={over ? "bg-red-50" : undefined}>
                          <TableCell className="whitespace-nowrap font-medium">{d.reference ?? d.documentId}</TableCell>
                          <TableCell className="text-slate-600">{d.label ?? <span className="text-slate-400">—</span>}</TableCell>
                          <TableCell className="whitespace-nowrap">
                            {fmtDateTime(d.documentDate, d)}
                            {d.isOverdue && (
                              <span className="ml-1.5 rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-medium text-red-700">{d.ageDays}d</span>
                            )}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            <div className="font-medium">{fmt(d.balance)}</div>
                            <div className="text-xs text-slate-400">of {fmt(d.totalAmount)}</div>
                          </TableCell>
                          <TableCell className="text-right">
                            <Input
                              type="number" min="0" max={d.balance} step="0.01" inputMode="decimal"
                              className={cn("h-8 text-right tabular-nums", over && "border-red-400")}
                              value={allocation[key] ?? ""}
                              onChange={(e) => setLine(d, e.target.value)}
                              placeholder="0.00"
                            />
                          </TableCell>
                          <TableCell className={cn("text-right tabular-nums", after === 0 ? "text-emerald-700" : after < 0 ? "text-red-600" : "")}>
                            {after === 0 ? "Paid" : fmt(after)}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              )}
            </div>
          </div>
        )}

        {remainderAsOldDebt && allowUnallocated && validation.unallocated > 0 && (
          <div className="rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">
            <p>
              {fmt(validation.unallocated)} is not applied to anything listed.{" "}
              {keepAsCredit
                ? `It will be kept as ${creditWord} (an advance) -- not on Profit & Loss until it is used.`
                : `It will be recorded as ${isCustomer ? "a debt the customer owed" : "a debt we owed the supplier"} from before the system, paid now.`}
            </p>
            <label className="mt-1.5 flex items-center gap-2 text-xs">
              <Checkbox checked={keepAsCredit} onCheckedChange={(v) => setKeepAsCredit(v === true)} />
              Keep it as {creditWord} (an advance) instead
            </label>
          </div>
        )}

        {debtAllocated > 0 && (
          <div className="rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-900">
            {isAdmin ? (
              <label className="flex items-start gap-2">
                <Checkbox className="mt-0.5" checked={countOnPL} onCheckedChange={(v) => setCountOnPL(v === true)} />
                <span>
                  Count the {fmt(debtAllocated)} paid on debts on Profit &amp; Loss as{" "}
                  {isCustomer ? "revenue" : "an operating expense"}.
                  <span className="block text-xs text-emerald-800/80">
                    Untick to keep it off Profit &amp; Loss. You can change this later from the payments list.
                  </span>
                </span>
              </label>
            ) : (
              <>The {fmt(debtAllocated)} paid on debts goes on Profit &amp; Loss as {isCustomer ? "revenue" : "an operating expense"}.</>
            )}
          </div>
        )}

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

        <DialogFooter className="border-t pt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={posting}>Cancel</Button>
          <Button onClick={submit} disabled={posting || loading || !validation.ok || overdraws}>
            {posting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {isCustomer ? "Receive" : "Record"} {amountValue > 0 ? fmt(amountValue) : "payment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

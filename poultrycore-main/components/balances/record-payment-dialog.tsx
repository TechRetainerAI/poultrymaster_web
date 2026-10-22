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

import { useEffect, useMemo, useState, type ReactNode } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Checkbox } from "@/components/ui/checkbox"
import { AlertCircle, AlertTriangle, BarChart3, FileText, Loader2, Wallet, Wand2, X } from "lucide-react"
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
import { SALE_PRODUCT_OPTIONS } from "@/components/sales/sale-item-row"

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
   * anything can pay something owed from before the system -- recorded as that
   * debt and paid now, so it is on Profit & Loss.
   *   supplier  old debt by default; the user can keep it as credit instead.
   *   customer  (384) customer credit by default; the user ticks "add to Profit
   *             & Loss" and says which sale type it paid for.
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
  // 384 (customer): the leftover is credit unless ticked onto P&L with a sale type.
  const [addToPL, setAddToPL] = useState(false)
  const [saleType, setSaleType] = useState("")
  const [saleTypeOther, setSaleTypeOther] = useState("")
  // "Payment for an earlier sale": on Profit & Loss unless the income was
  // already recorded (owner / admin only -- it is a P&L exclusion).
  const [earlierSaleOnPL, setEarlierSaleOnPL] = useState(true)

  // Load the lines this payment can be spread over. A single-document payment
  // still goes through the grid, so the two modes cannot drift apart.
  useEffect(() => {
    if (!open || !party) return
    let cancelled = false
    setTouched(false)
    setLinesEdited(false)
    setCountOnPL(true)
    setKeepAsCredit(false)
    setAddToPL(false)
    setSaleType("")
    setSaleTypeOther("")
    setEarlierSaleOnPL(true)

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
  // 384: on the customer side only when ticked onto Profit & Loss.
  const leftoverIsOldDebt = isCustomer ? addToPL : !keepAsCredit
  const oldDebt = remainderAsOldDebt && allowUnallocated && leftoverIsOldDebt && validation.unallocated > 0
    ? validation.unallocated : 0
  const oldDebtSaleType = saleType === "Other" ? saleTypeOther.trim() : saleType
  // 384: an old customer debt on P&L must say what was sold.
  const saleTypeMissing = isCustomer && oldDebt > 0 && earlierSaleOnPL && !oldDebtSaleType
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
    if (!validation.ok || overdraws || saleTypeMissing) return

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
        excludeFromPL: (debtAllocated > 0 && !countOnPL) || (isCustomer && oldDebt > 0 && !earlierSaleOnPL),
        remainderAsOldDebt: oldDebt > 0,
        oldDebtSaleType: isCustomer && oldDebt > 0 ? oldDebtSaleType : null,
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
      <DialogContent className={cn(FORM_DIALOG_CONTENT, isBulk ? "sm:max-w-4xl" : "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={Wallet} color={isCustomer ? "emerald" : "amber"}>
            {isCustomer
              ? isBulk ? "Receive bulk payment" : "Receive payment"
              : isBulk ? "Record bulk payment" : "Record payment"}
          </FormDialogTitle>
          <DialogDescription className="truncate text-left">
            {party?.partyName}
            {single ? ` · ${single.reference ?? single.documentId}` : ""}
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-4">
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

        <FormSection title="Payment" color="green" tinted columns={3} stackOnMobile>
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
              className="bg-white text-right font-semibold tabular-nums"
              value={amount}
              onChange={(e) => changeAmount(e.target.value)}
              placeholder="0.00"
              disabled={loading}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-date">Payment date</Label>
            <Input id="pay-date" type="date" className="bg-white" value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Payment method</Label>
            <Select value={method} onValueChange={setMethod}>
              <SelectTrigger className="w-full bg-white"><SelectValue /></SelectTrigger>
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
              <SelectTrigger className="w-full bg-white"><SelectValue placeholder="Select account" /></SelectTrigger>
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
            <Input id="pay-ref" className="bg-white" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="e.g. MoMo ID, cheque no." />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-notes">Notes <span className="font-normal text-slate-400">(optional)</span></Label>
            <Input id="pay-notes" className="bg-white" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Anything to remember" />
          </div>
        </FormSection>

        {single ? (
          <FormSection title={`Applies to this ${docWord}`} color="blue" tinted columns={1}>
          <div className="rounded-lg border bg-white px-3 py-2.5 text-sm">
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
          </FormSection>
        ) : (
          <FormSection
            title={`Apply to open ${docWord}s`} color="blue" tinted columns={1}
            action={
              <div className="flex items-center gap-1">
                <Button type="button" size="sm" onClick={autoAllocate} disabled={!amount || loading}
                        className="h-8 bg-white text-blue-700 shadow-sm hover:bg-blue-50">
                  <Wand2 className="mr-1.5 h-3.5 w-3.5" /> Oldest first
                </Button>
                <Button type="button" size="sm" onClick={clearAllocation} disabled={loading}
                        className="h-8 bg-white/20 text-white hover:bg-white/30">
                  <X className="mr-1.5 h-3.5 w-3.5" /> Clear
                </Button>
              </div>
            }
          >
              <div className="text-sm">
                <span className="text-slate-600">
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
            <div className="overflow-x-auto rounded-lg border bg-white">
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
          </FormSection>
        )}

        {/* 384: customer -- what to do with money left over after the open sales.
            Credit by default; "Payment for an Earlier Sale" records the old debt
            it pays, on Profit & Loss unless the income was already recorded. */}
        {remainderAsOldDebt && isCustomer && allowUnallocated && validation.unallocated > 0 && (() => {
          const remaining = validation.unallocated
          const appliedDocs = documents.filter((d) => (allocation[docKey(d)] ?? 0) > 0)
          const option = (active: boolean, onPick: () => void, icon: ReactNode, iconCls: string, title: string, body: ReactNode, extra?: ReactNode) => (
            <div className={cn("rounded-lg border p-3 transition-colors",
                               active ? "border-emerald-300 bg-emerald-50" : "border-slate-200 bg-white")}>
              <button type="button" role="radio" aria-checked={active} onClick={onPick}
                      className="flex w-full items-start gap-3 text-left">
                <span className={cn("mt-1 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border-2",
                                    active ? "border-blue-600" : "border-slate-300")}>
                  {active && <span className="h-2 w-2 rounded-full bg-blue-600" />}
                </span>
                <span className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-full", iconCls)}>{icon}</span>
                <span className="min-w-0">
                  <span className="block text-sm font-semibold text-slate-900">{title}</span>
                  <span className="block text-sm text-slate-600">{body}</span>
                </span>
              </button>
              {extra}
            </div>
          )
          return (
            <FormSection title={`Overpayment (Money Left Over) — ${fmt(remaining)}`} color="orange" tinted columns={1}>
              <div className="flex items-start gap-3 text-sm text-slate-700">
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-orange-100 text-orange-600">
                  <AlertCircle className="h-4 w-4" />
                </span>
                <p>
                  You received <b>{fmt(amountValue)}</b> from this customer.{" "}
                  {allocated > 0
                    ? <><b>{fmt(allocated)}</b> will settle the outstanding {docWord}{appliedDocs.length === 1 ? "" : "s"}. </>
                    : null}
                  There is <b>{fmt(remaining)}</b> remaining. What would you like to do with it?
                </p>
              </div>

              <div role="radiogroup" aria-label="What to do with the money left over" className="space-y-2">
                {option(!addToPL, () => setAddToPL(false),
                  <Wallet className="h-5 w-5" />, "bg-emerald-100 text-emerald-700",
                  "Keep as Customer Credit (Advance Payment)",
                  <>The customer is paying in advance for future purchases. We will save <b>{fmt(remaining)}</b> as {creditWord}, which can be used when they buy from you later.</>)}
                {option(addToPL, () => setAddToPL(true),
                  <FileText className="h-5 w-5" />, "bg-blue-100 text-blue-700",
                  "Payment for an Earlier Sale",
                  "The customer is paying for goods you sold before recording the sale in VisibilityCore.",
                  addToPL && (
                    <div className="mt-3 space-y-3 rounded-md bg-slate-50 p-3 sm:ml-[4.25rem]">
                      <label className="flex items-start gap-2 text-sm">
                        <Checkbox className="mt-0.5" checked={earlierSaleOnPL} onCheckedChange={(v) => setEarlierSaleOnPL(v === true)} />
                        <span>
                          Include this payment as income in Profit &amp; Loss?
                          <span className="block text-xs text-slate-500">Record this amount as sales income in Profit &amp; Loss.</span>
                        </span>
                      </label>
                      <label className={cn("flex items-start gap-2 text-sm", !isAdmin && "opacity-60")}>
                        <Checkbox className="mt-0.5" checked={!earlierSaleOnPL} disabled={!isAdmin}
                                  onCheckedChange={(v) => setEarlierSaleOnPL(v !== true)} />
                        <span>
                          <b className="font-medium">Income was already recorded</b> or should not be recognized again
                          <span className="block text-xs text-slate-500">
                            Do not record this amount as income in Profit &amp; Loss.
                            {!isAdmin && " Only the owner or an admin can choose this."}
                          </span>
                        </span>
                      </label>
                      <div className="grid gap-2 sm:grid-cols-2">
                        <div className={cn("space-y-1", saleType !== "Other" && "sm:col-span-2")}>
                          <Label className="text-xs">What was sold?</Label>
                          <Select value={saleType} onValueChange={setSaleType}>
                            <SelectTrigger className="w-full bg-white"><SelectValue placeholder="Select sale type or product" /></SelectTrigger>
                            <SelectContent>
                              {SALE_PRODUCT_OPTIONS.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </div>
                        {saleType === "Other" && (
                          <div className="space-y-1">
                            <Label htmlFor="old-debt-type" className="text-xs">Describe it</Label>
                            <Input id="old-debt-type" className="bg-white" value={saleTypeOther}
                                   onChange={(e) => setSaleTypeOther(e.target.value)} placeholder="e.g. Egg trays" />
                          </div>
                        )}
                      </div>
                      <p className={cn("text-xs", saleTypeMissing ? "text-amber-700" : "text-slate-500")}>
                        {saleTypeMissing
                          ? "Choose what was sold to add it to Profit & Loss."
                          : earlierSaleOnPL
                            ? `${fmt(remaining)} goes on Profit & Loss as Revenue${oldDebtSaleType ? ` (${oldDebtSaleType})` : ""}.`
                            : "Recorded as an earlier sale paid now, but kept off Profit & Loss."}
                      </p>
                    </div>
                  ))}
              </div>

              <div className="overflow-hidden rounded-lg border border-blue-200 bg-blue-50/40">
                <div className="flex items-center justify-between px-3 py-2">
                  <span className="flex items-center gap-2 text-sm font-semibold text-slate-900">
                    <BarChart3 className="h-4 w-4 text-blue-600" /> Payment breakdown
                  </span>
                  <span className="text-xs text-slate-500">Amount</span>
                </div>
                <div className="divide-y divide-slate-100 bg-white text-sm">
                  <div className="flex justify-between gap-3 px-3 py-1.5">
                    <span>Total received from customer</span>
                    <span className="tabular-nums">{fmt(amountValue)}</span>
                  </div>
                  {appliedDocs.map((d) => (
                    <div key={docKey(d)} className="flex justify-between gap-3 px-3 py-1.5">
                      <span className="min-w-0">Applied to outstanding {docWord} ({d.reference ?? d.documentId}{d.label ? ` - ${d.label}` : ""})</span>
                      <span className="font-semibold tabular-nums">{fmt(allocation[docKey(d)] ?? 0)}</span>
                    </div>
                  ))}
                  <div className="flex justify-between gap-3 px-3 py-1.5">
                    <span className="min-w-0">
                      {addToPL
                        ? `Payment for an earlier sale${oldDebtSaleType ? ` (${oldDebtSaleType})` : ""}${earlierSaleOnPL ? "" : ", not on Profit & Loss"}`
                        : "Customer credit (advance payment)"}
                    </span>
                    <span className="tabular-nums">{fmt(remaining)}</span>
                  </div>
                </div>
                <div className="flex justify-between gap-3 bg-blue-100/70 px-3 py-2 text-sm font-semibold text-slate-900">
                  <span>Total allocated</span>
                  <span className="tabular-nums">{fmt(allocated + remaining)}</span>
                </div>
              </div>
            </FormSection>
          )
        })()}

        {remainderAsOldDebt && !isCustomer && allowUnallocated && validation.unallocated > 0 && (
          <FormSection title="Overpayment (Money Left Over)" color="amber" tinted columns={1}>
          <div className="text-sm text-slate-800">
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
          </FormSection>
        )}

        {/* 384: on the customer side the old debt was ticked onto P&L above, so this
            box only appears for debts recorded by hand. */}
        {(isCustomer ? recordedDebtAllocated > 0 : debtAllocated > 0) && (
          <FormSection title="Profit & Loss" color="emerald" tinted columns={1}>
          <div className="text-sm text-emerald-900">
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
          </FormSection>
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

        </div>

        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={posting}>
          <Button onClick={submit} disabled={posting || loading || !validation.ok || overdraws || saleTypeMissing}
                  className={cn("px-6", FORM_DIALOG_PRIMARY[isCustomer ? "emerald" : "amber"])}>
            {posting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {isCustomer ? "Receive" : "Record"} {amountValue > 0 ? fmt(amountValue) : "payment"}
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}

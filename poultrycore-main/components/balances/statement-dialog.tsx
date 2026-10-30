"use client"

// Customer / Supplier statement.
//
// Opening balance, every document and every payment in the window, and a
// running balance down the right. Derived from the sales/purchases and their
// allocations rather than from a ledger table -- so it cannot disagree with the
// balances page, which is the whole reason this feature exists.

import { Fragment, useEffect, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ChevronDown, ChevronRight, FileText, Loader2, Printer } from "lucide-react"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import {
  getPayment, getStatement,
  type BalanceModule, type BalanceSide, type PartyBalanceRow,
  type PaymentAllocationRow, type StatementLine,
} from "@/lib/api/balances"
import { fmtDateTime } from "@/lib/utils/company-datetime"

// Where the payment was taken. "Counter" is this screen's own: a sale written
// as already paid has no payment row behind it, so its credit comes from the
// sale itself.
const SOURCE_LABEL: Record<string, string> = {
  SaleEntry: "Sale",
  CustomerBalances: "Balances",
  CustomerProfile: "Customer",
  PaymentsPage: "Payments",
  ImportedPayment: "Imported",
  Backfill: "Backfill",
  Counter: "Counter",
  // 363: credit added by hand on Customer Credits.
  OpeningCredit: "Opening credit",
  Deposit: "Customer advance",
  CreditNote: "Credit note",
}
// A Sale line has no source worth printing \u2014 it IS the source.
const sourceLabel = (s?: string | null) =>
  s && s !== "Sale" ? SOURCE_LABEL[s] ?? s : "\u2014"

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
  module: BalanceModule
  side: BalanceSide
  party: PartyBalanceRow | null
}

export function StatementDialog({ open, onOpenChange, module, side, party }: Props) {
  const fmt = useFmt()
  const { toast } = useToast()
  const isCustomer = side === "customer"

  const [lines, setLines] = useState<StatementLine[]>([])
  const [loading, setLoading] = useState(false)
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  // A payment that settled several sales is one line; this is what sits behind
  // it, fetched only when someone opens it.
  const [openPayment, setOpenPayment] = useState<string | null>(null)
  const [allocations, setAllocations] = useState<Record<string, PaymentAllocationRow[]>>({})

  const togglePayment = async (paymentId: string) => {
    if (openPayment === paymentId) { setOpenPayment(null); return }
    setOpenPayment(paymentId)
    if (allocations[paymentId]) return
    try {
      const detail = await getPayment(module, side, paymentId)
      setAllocations((prev) => ({ ...prev, [paymentId]: detail.allocations }))
    } catch (e: any) {
      toast({ title: "Could not load the allocation", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  useEffect(() => {
    if (!open || !party) return
    let cancelled = false
    setLoading(true)
    ;(async () => {
      try {
        const rows = await getStatement(module, side, party.partyId, { from: from || null, to: to || null })
        if (!cancelled) setLines(rows)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load statement", description: e?.message ?? String(e), variant: "destructive" })
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, party?.partyId, from, to, module, side])

  const closing = lines.length > 0 ? lines[lines.length - 1].runningBalance : 0

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-6xl print:max-w-none")}>
        <DialogHeader>
          <FormDialogTitle icon={FileText} color="blue">{isCustomer ? "Customer statement" : "Supplier statement"}</FormDialogTitle>
          <DialogDescription className="text-left">
            {party?.partyName}
            {party?.contactPhone ? ` · ${party.contactPhone}` : ""}
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-4">
        {/* The period is a screen control; the printed statement is just the table. */}
        <FormSection title="Period" color="blue" tinted columns={1} className="print:hidden">
          <div className="flex flex-wrap items-end gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="stmt-from">From</Label>
              <Input id="stmt-from" type="date" className="bg-white" value={from} onChange={(e) => setFrom(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="stmt-to">To</Label>
              <Input id="stmt-to" type="date" className="bg-white" value={to} onChange={(e) => setTo(e.target.value)} />
            </div>
            {(from || to) && (
              <Button variant="ghost" size="sm" onClick={() => { setFrom(""); setTo("") }}>
                All history
              </Button>
            )}
          </div>
        </FormSection>

        {/* Printed plain, as before: no band, no tint, no border. */}
        <FormSection
          title={isCustomer ? "Charges & payments" : "Bills & payments"} color="green" tinted columns={1}
          className="print:rounded-none print:border-0 print:[&>div:first-child]:hidden print:[&>div:last-child]:bg-white print:[&>div:last-child]:p-0"
        >
        <div className="rounded-md border bg-white">
          {loading ? (
            <div className="flex items-center gap-2 p-6 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading statement…
            </div>
          ) : lines.length === 0 ? (
            <div className="p-8 text-center text-slate-500">Nothing to show for this period.</div>
          ) : (
            <Table className="w-full [&_td]:whitespace-normal [&_th]:whitespace-normal">
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Reference</TableHead>
                  <TableHead>Description</TableHead>
                  <TableHead>Source</TableHead>
                  <TableHead className="text-right">{isCustomer ? "Charges" : "Billed"}</TableHead>
                  <TableHead className="text-right">{isCustomer ? "Payments" : "Paid"}</TableHead>
                  <TableHead className="text-right">Balance</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {lines.map((l, i) => {
                  // Only a payment across several sales has anything to open: a
                  // one-sale payment already names its sale in the line itself.
                  const drillable = !!l.paymentId && (l.allocationCount ?? 1) > 1
                  const isOpen = !!l.paymentId && openPayment === l.paymentId
                  return (
                    <Fragment key={i}>
                      <TableRow className={l.entryType === "OpeningBalance" ? "bg-slate-50 font-medium" : undefined}>
                        <TableCell className="whitespace-nowrap!">
                          {l.entryDate ? fmtDateTime(l.entryDate, l) : "—"}
                        </TableCell>
                        <TableCell>{l.entryType === "OpeningBalance" ? "Opening" : l.entryType}</TableCell>
                        <TableCell className="whitespace-nowrap! font-medium">{l.reference ?? "—"}</TableCell>
                        <TableCell>
                          {drillable ? (
                            <>
                              <button
                                type="button"
                                onClick={() => void togglePayment(l.paymentId!)}
                                className="flex items-center gap-1 text-left text-sky-700 hover:underline print:hidden"
                              >
                                {isOpen
                                  ? <ChevronDown className="h-3.5 w-3.5 shrink-0" />
                                  : <ChevronRight className="h-3.5 w-3.5 shrink-0" />}
                                {l.description ?? "—"}
                              </button>
                              {/* A printed statement cannot be expanded, so the
                                  description still prints as plain text. */}
                              <span className="hidden print:inline">{l.description ?? "—"}</span>
                            </>
                          ) : (
                            <span>{l.description ?? "—"}</span>
                          )}
                        </TableCell>
                        <TableCell className="text-xs text-slate-500">{sourceLabel(l.sourceType)}</TableCell>
                        <TableCell className="whitespace-nowrap! text-right">{l.debit ? fmt(l.debit) : "—"}</TableCell>
                        <TableCell className="whitespace-nowrap! text-right">{l.credit ? fmt(l.credit) : "—"}</TableCell>
                        <TableCell className="whitespace-nowrap! text-right font-medium">{fmt(l.runningBalance)}</TableCell>
                      </TableRow>

                      {isOpen && (
                        <TableRow className="bg-slate-50/60">
                          <TableCell />
                          <TableCell colSpan={7} className="py-2">
                            {!allocations[l.paymentId!] ? (
                              <span className="flex items-center gap-2 text-sm text-slate-500">
                                <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading allocation…
                              </span>
                            ) : (
                              <div className="space-y-1">
                                {allocations[l.paymentId!].map((a) => (
                                  <div key={a.allocationId} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 text-sm">
                                    <span className="font-medium">
                                      Sale #{a.documentId}
                                      {a.label ? <span className="ml-1.5 font-normal text-slate-500">{a.label}</span> : null}
                                    </span>
                                    <span className="tabular-nums text-slate-600">
                                      {fmt(a.balanceBefore)} &rarr; {fmt(a.balanceAfter)}
                                      <span className="ml-3 font-semibold text-slate-900">{fmt(a.amountApplied)}</span>
                                    </span>
                                  </div>
                                ))}
                              </div>
                            )}
                          </TableCell>
                        </TableRow>
                      )}
                    </Fragment>
                  )
                })}
              </TableBody>
              <TableFooter>
                <TableRow>
                  <TableCell colSpan={7} className="text-right font-medium">
                    {isCustomer ? "Closing balance owed to us" : "Closing balance we owe"}
                  </TableCell>
                  <TableCell className="text-right font-semibold">{fmt(closing)}</TableCell>
                </TableRow>
              </TableFooter>
            </Table>
          )}
        </div>
        </FormSection>
        </div>

        {/* `contents` keeps the footer sticky inside the dialog; print:hidden keeps it off paper. */}
        <div className="contents print:hidden">
          <FormDialogFooter onCancel={() => onOpenChange(false)} cancelLabel="Close">
            <Button onClick={() => window.print()} disabled={loading || lines.length === 0}
                    className={cn("px-6", FORM_DIALOG_PRIMARY.blue)}>
              <Printer className="mr-2 h-4 w-4" /> Print
            </Button>
          </FormDialogFooter>
        </div>
      </DialogContent>
    </Dialog>
  )
}

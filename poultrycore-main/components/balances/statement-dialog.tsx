"use client"

// Customer / Supplier statement.
//
// Opening balance, every document and every payment in the window, and a
// running balance down the right. Derived from the sales/purchases and their
// allocations rather than from a ledger table -- so it cannot disagree with the
// balances page, which is the whole reason this feature exists.

import { useEffect, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, Printer } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { getStatement, type BalanceModule, type BalanceSide, type PartyBalanceRow, type StatementLine } from "@/lib/api/balances"

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
      <DialogContent className="max-w-4xl max-h-[92vh] overflow-y-auto print:max-w-none">
        <DialogHeader>
          <DialogTitle>{isCustomer ? "Customer statement" : "Supplier statement"}</DialogTitle>
          <DialogDescription>
            {party?.partyName}
            {party?.contactPhone ? ` · ${party.contactPhone}` : ""}
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-wrap items-end gap-3 print:hidden">
          <div className="space-y-1.5">
            <Label htmlFor="stmt-from">From</Label>
            <Input id="stmt-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="stmt-to">To</Label>
            <Input id="stmt-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          {(from || to) && (
            <Button variant="ghost" size="sm" onClick={() => { setFrom(""); setTo("") }}>
              All history
            </Button>
          )}
        </div>

        <div className="overflow-x-auto rounded-md border">
          {loading ? (
            <div className="flex items-center gap-2 p-6 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading statement…
            </div>
          ) : lines.length === 0 ? (
            <div className="p-8 text-center text-slate-500">Nothing to show for this period.</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Reference</TableHead>
                  <TableHead>Description</TableHead>
                  <TableHead className="text-right">{isCustomer ? "Charges" : "Billed"}</TableHead>
                  <TableHead className="text-right">{isCustomer ? "Payments" : "Paid"}</TableHead>
                  <TableHead className="text-right">Balance</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {lines.map((l, i) => (
                  <TableRow key={i} className={l.entryType === "OpeningBalance" ? "bg-slate-50 font-medium" : undefined}>
                    <TableCell className="whitespace-nowrap">
                      {l.entryDate ? new Date(l.entryDate).toLocaleDateString() : "—"}
                    </TableCell>
                    <TableCell>{l.entryType === "OpeningBalance" ? "Opening" : l.entryType}</TableCell>
                    <TableCell>{l.reference ?? "—"}</TableCell>
                    <TableCell className="max-w-[22rem] truncate">{l.description ?? "—"}</TableCell>
                    <TableCell className="text-right">{l.debit ? fmt(l.debit) : "—"}</TableCell>
                    <TableCell className="text-right">{l.credit ? fmt(l.credit) : "—"}</TableCell>
                    <TableCell className="text-right font-medium">{fmt(l.runningBalance)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
              <TableFooter>
                <TableRow>
                  <TableCell colSpan={6} className="text-right font-medium">
                    {isCustomer ? "Closing balance owed to us" : "Closing balance we owe"}
                  </TableCell>
                  <TableCell className="text-right font-semibold">{fmt(closing)}</TableCell>
                </TableRow>
              </TableFooter>
            </Table>
          )}
        </div>

        <DialogFooter className="print:hidden">
          <Button variant="outline" onClick={() => window.print()} disabled={loading || lines.length === 0}>
            <Printer className="mr-2 h-4 w-4" /> Print
          </Button>
          <Button onClick={() => onOpenChange(false)}>Close</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

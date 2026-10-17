"use client"

/**
 * Poultry (382): money paid on a debt recorded by hand goes on Profit & Loss --
 * a customer's as revenue, ours to a supplier as an operating expense. Only that
 * part of a payment is new to P&L (a sale or purchase is already on it), so the
 * badge and the toggle show only when the payment has some (`plAmount > 0`).
 *
 * The owner or an admin can keep a single payment off P&L, and put it back.
 */

import { useState } from "react"
import { Loader2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { setPaymentPLExclusion, type BalanceSide, type PaymentHistoryRow } from "@/lib/api/balances"

const onPL = (row: PaymentHistoryRow) =>
  (row.plAmount ?? 0) > 0 && (row.status ?? "Posted") !== "Reversed"

/** "On P&L" / "Not on P&L" -- nothing for a payment with no debt in it. */
export function PaymentPLBadge({ row, side, className }: { row: PaymentHistoryRow; side: BalanceSide; className?: string }) {
  const fmt = useFmt()
  if (!onPL(row)) return null
  const what = side === "customer" ? "revenue" : "an operating expense"
  return row.excludedFromPL ? (
    <Badge variant="outline" className={cn("border-slate-300 text-slate-500", className)}
           title={`${fmt(row.plAmount ?? 0)} paid on debts is kept off Profit & Loss`}>
      Not on P&amp;L
    </Badge>
  ) : (
    <Badge variant="outline" className={cn("border-emerald-300 bg-emerald-50 text-emerald-800", className)}
           title={`${fmt(row.plAmount ?? 0)} paid on debts is on Profit & Loss as ${what}`}>
      On P&amp;L
    </Badge>
  )
}

/** Exclude from P&L / Include in P&L, with a confirmation. Owner / admin only. */
export function PaymentPLToggle({
  row, side, onChanged, className,
}: { row: PaymentHistoryRow; side: BalanceSide; onChanged: () => void; className?: string }) {
  const fmt = useFmt()
  const { toast } = useToast()
  const { isAdmin } = usePermissions()
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  if (!isAdmin || !onPL(row)) return null

  const exclude = !row.excludedFromPL
  const what = side === "customer" ? "revenue" : "an operating expense"
  const ref = row.paymentNumber ?? `payment #${row.paymentId}`

  const run = async () => {
    setBusy(true)
    try {
      await setPaymentPLExclusion(side, row.paymentId, exclude)
      toast({ title: exclude ? "Kept off Profit & Loss" : "Back on Profit & Loss", description: `${ref} · ${fmt(row.plAmount ?? 0)}` })
      setOpen(false)
      onChanged()
    } catch (e: any) {
      toast({ title: "Could not change Profit & Loss", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <Button type="button" variant="outline" size="sm" className={cn("h-8 bg-white text-xs", className)} onClick={() => setOpen(true)}>
        {exclude ? "Exclude from P&L" : "Include in P&L"}
      </Button>
      <AlertDialog open={open} onOpenChange={(o) => { if (!busy) setOpen(o) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{exclude ? "Keep this payment off Profit & Loss?" : "Put this payment back on Profit & Loss?"}</AlertDialogTitle>
            <AlertDialogDescription>
              {exclude
                ? `${fmt(row.plAmount ?? 0)} of ${ref} was paid on debts and counts as ${what}. Excluding it takes it off Profit & Loss; the payment, the debt and the cash are not changed.`
                : `${fmt(row.plAmount ?? 0)} of ${ref} will count as ${what} on Profit & Loss again, on the payment date.`}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy}>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={busy} onClick={(e) => { e.preventDefault(); void run() }}>
              {busy && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              {exclude ? "Exclude from P&L" : "Include in P&L"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}

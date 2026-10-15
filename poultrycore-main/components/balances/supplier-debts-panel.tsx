"use client"

// Supplier debts (370), on Poultry Supplier Balances.
//
// What the business owes suppliers without a purchase, recorded by hand. There
// is no separate debts table: an open debt already shows in the balances table
// among the supplier's open items (and on the statement), so listing it again
// showed it twice. Laid out like Customer Balances:
//   - RecordSupplierDebtButton, in the page header (owner / admin);
//   - ReverseSupplierDebtButton, on a debt's row in the balances table
//     (owner / admin, only while nothing is paid on it).
// Paying a debt is done like paying a purchase: Record payment on its row.

import { REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useState } from "react"
import { Loader2, Plus, Undo2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { formatCurrency, getSelectedCurrency } from "@/lib/utils/currency"
import { useCurrency } from "@/lib/currency"
import { reverseSupplierDebt } from "@/lib/api/supplier-credit"
import type { OpenDocumentRow } from "@/lib/api/balances"
import { SupplierDebtDialog } from "./supplier-debt-dialog"

function useMoney() {
  const { code } = useCurrency()
  const currencyCode = code || getSelectedCurrency()
  return { currencyCode, money: (n: number) => formatCurrency(Number(n) || 0, currencyCode) }
}

/** "Record supplier debt", for the page header. Owner / admin only. */
export function RecordSupplierDebtButton({ onChanged }: { onChanged?: () => void }) {
  const { toast } = useToast()
  const { isAdmin } = usePermissions()
  const { currencyCode, money } = useMoney()
  const [open, setOpen] = useState(false)

  if (!isAdmin) return null
  return (
    <>
      <Button onClick={() => setOpen(true)} className="h-10 bg-amber-600 hover:bg-amber-700">
        <Plus className="mr-1 h-4 w-4" /> Record supplier debt
      </Button>
      <SupplierDebtDialog
        open={open}
        currencyCode={currencyCode}
        onOpenChange={setOpen}
        onCreated={(d) => {
          toast({ title: "Debt recorded", description: `${d.debtNumber}: you owe ${d.supplierName} ${money(d.amount)} more.` })
          setOpen(false)
          onChanged?.()
        }}
      />
    </>
  )
}

/**
 * Reverse a supplier debt from its row in the balances table. Renders nothing
 * for anything but a debt, or for someone who may not reverse.
 */
export function ReverseSupplierDebtButton({ doc, partyName, compact, onChanged }: {
  doc: OpenDocumentRow
  partyName?: string | null
  /** Icon-sized, for the desktop table row. */
  compact?: boolean
  onChanged?: () => void
}) {
  const { toast } = useToast()
  const { isAdmin } = usePermissions()
  const { money } = useMoney()
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (!isAdmin || doc.documentType !== "SupplierDebt") return null
  const paid = (Number(doc.amountPaid) || 0) > 0
  const number = doc.reference ?? `debt ${doc.documentId}`

  const doReverse = async () => {
    if (!reason.trim()) return
    setBusy(true); setError(null)
    try {
      await reverseSupplierDebt(doc.documentId, reason.trim())
      toast({ title: "Debt reversed", description: `${number} to ${partyName ?? "the supplier"} is no longer owed.` })
      setOpen(false)
      onChanged?.()
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <Button size="sm" variant={compact ? "ghost" : "outline"} className={compact ? undefined : "h-10 w-full"}
              disabled={paid}
              title={paid ? "Reverse the payments on it first (Supplier Payments)." : "Reverse this debt"}
              onClick={(e) => { e.stopPropagation(); setReason(""); setError(null); setOpen(true) }}>
        <Undo2 className={compact ? "h-3.5 w-3.5" : "mr-2 h-4 w-4"} />
        {compact ? <span className="sr-only">Reverse debt</span> : "Reverse debt"}
      </Button>

      <Dialog open={open} onOpenChange={(o) => { if (!o && !busy) setOpen(false) }}>
        <DialogContent className="max-w-md" onClick={(e) => e.stopPropagation()}>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Undo2 className="h-5 w-5 text-red-600" /> Reverse {number}?</DialogTitle>
            <DialogDescription>
              You will no longer owe {partyName ?? "the supplier"} {money(doc.totalAmount)}. The debt stays in the
              history, marked Reversed. No cash moves.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3 text-sm">
            <div className="space-y-1">
              <Label htmlFor="sd-reverse-reason">Reason *</Label>
              <ReasonSelect id="sd-reverse-reason" options={REVERSAL_REASONS} value={reason} onChange={setReason} />
            </div>
            {error && <p className="rounded-md bg-red-50 p-2.5 text-red-700">{error}</p>}
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={busy}>Cancel</Button>
            <Button className="bg-red-600 hover:bg-red-700" onClick={doReverse} disabled={busy || !reason.trim()}>
              {busy && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Reverse debt
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}

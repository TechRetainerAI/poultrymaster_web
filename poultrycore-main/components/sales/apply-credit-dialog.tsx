"use client"

// Apply customer credit to a sale (migration 351). An allocation only: no new
// payment, no Money In, no cash movement -- the money was received once, when
// the original payment came in.

import { useEffect, useState } from "react"
import { Loader2, Wallet } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { formatCurrency } from "@/lib/utils/currency"
import { applyCustomerCredit, customerCreditTotal } from "@/lib/api/customer-credit"

export interface ApplyCreditTarget {
  customerId: number
  customerName: string
  /** The sale row to apply to (the first line of a multi-size sale is fine: the server applies to that row). */
  saleId: number
  saleLabel: string
  outstanding: number
}

interface Props {
  target: ApplyCreditTarget | null
  currencyCode: string
  onOpenChange: (open: boolean) => void
  onApplied: (amount: number) => void
}

export function ApplyCreditDialog({ target, currencyCode, onOpenChange, onApplied }: Props) {
  const [credit, setCredit] = useState<number | null>(null)
  const [amount, setAmount] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  useEffect(() => {
    setCredit(null); setError(null); setAmount("")
    if (!target) return
    customerCreditTotal(target.customerId)
      .then((c) => {
        setCredit(c)
        const suggested = Math.min(c, target.outstanding)
        setAmount(suggested > 0 ? suggested.toFixed(2) : "")
      })
      .catch((e) => setError(e?.message ?? String(e)))
  }, [target])

  const value = Number(amount)
  const valid = !!target && credit != null && value > 0 && value <= credit + 0.005 && value <= target.outstanding + 0.005

  const apply = async () => {
    if (!target || !valid) return
    setSaving(true); setError(null)
    try {
      await applyCustomerCredit(target.customerId, target.saleId, Math.round(value * 100) / 100)
      onApplied(value)
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!target} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><Wallet className="h-5 w-5 text-emerald-600" /> Apply customer credit</DialogTitle>
          <DialogDescription>
            Use money {target?.customerName || "the customer"} already paid to settle sale {target?.saleLabel}.
            No new payment is recorded and no cash moves.
          </DialogDescription>
        </DialogHeader>
        {target && (
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div className="rounded-md border p-2.5">
                <p className="text-[11px] text-slate-500">Available credit</p>
                <p className="font-semibold tabular-nums">{credit == null ? "…" : money(credit)}</p>
              </div>
              <div className="rounded-md border p-2.5">
                <p className="text-[11px] text-slate-500">Sale outstanding</p>
                <p className="font-semibold tabular-nums">{money(target.outstanding)}</p>
              </div>
            </div>
            <div className="space-y-1">
              <Label htmlFor="credit-amount">Amount to apply</Label>
              <Input id="credit-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
              {credit != null && credit <= 0 && <p className="text-xs text-slate-500">This customer has no credit to apply.</p>}
            </div>
            {error && <p className="rounded-md bg-red-50 p-2.5 text-sm text-red-700">{error}</p>}
          </div>
        )}
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Not now</Button>
          <Button onClick={apply} disabled={!valid || saving} className="bg-emerald-600 hover:bg-emerald-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Apply credit
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

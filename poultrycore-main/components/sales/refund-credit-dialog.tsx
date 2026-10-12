"use client"

// Refund customer credit (migration 351): the business physically hands money
// back. Real Money Out from the account chosen here -- which may differ from
// the one the money came in on. Not an expense, and no stock moves (a pure
// refund is not a sales return).

import { useEffect, useState } from "react"
import { HandCoins, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { formatCurrency } from "@/lib/utils/currency"
import { recordCustomerRefund } from "@/lib/api/customer-credit"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"

export interface RefundTarget {
  customerId: number
  customerName: string
  availableCredit: number
}

interface Props {
  target: RefundTarget | null
  currencyCode: string
  onOpenChange: (open: boolean) => void
  onRefunded: () => void
}

const METHODS = ["Cash", "Mobile Money", "Bank Transfer", "Check"]

export function RefundCreditDialog({ target, currencyCode, onOpenChange, onRefunded }: Props) {
  const [accounts, setAccounts] = useState<PoultryCashAccount[]>([])
  const [accountId, setAccountId] = useState<string>("")
  const [method, setMethod] = useState("Cash")
  const [amount, setAmount] = useState("")
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  useEffect(() => {
    setError(null); setReason(""); setMethod("Cash")
    if (!target) return
    setAmount(target.availableCredit > 0 ? target.availableCredit.toFixed(2) : "")
    listPoultryCashAccounts()
      .then((a: PoultryCashAccount[]) => {
        const active = a.filter((x: any) => x.isActive !== false)
        setAccounts(active)
        if (active[0]) setAccountId(String(active[0].poultryCashAccountId))
      })
      .catch(() => setAccounts([]))
  }, [target])

  const value = Number(amount)
  const valid = !!target && value > 0 && value <= target.availableCredit + 0.005 && !!accountId && reason.trim().length > 0

  const save = async () => {
    if (!target || !valid) return
    setSaving(true); setError(null)
    try {
      await recordCustomerRefund({
        customerId: target.customerId,
        amount: Math.round(value * 100) / 100,
        poultryCashAccountId: Number(accountId),
        paymentMethod: method,
        reason: reason.trim(),
      })
      onRefunded()
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!target} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><HandCoins className="h-5 w-5 text-amber-600" /> Refund customer credit</DialogTitle>
          <DialogDescription>
            Give {target?.customerName || "the customer"} back money they paid and you still hold. This is money going out of the
            account you choose; it is recorded as a refund, not an expense, and no stock moves.
          </DialogDescription>
        </DialogHeader>
        {target && (
          <div className="space-y-3">
            <p className="text-sm text-slate-600">Available credit: <span className="font-semibold tabular-nums">{money(target.availableCredit)}</span></p>
            <div className="grid grid-cols-2 gap-2">
              <div className="space-y-1">
                <Label htmlFor="refund-amount">Amount</Label>
                <Input id="refund-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>Method</Label>
                <Select value={method} onValueChange={setMethod}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-1">
              <Label>Paid from</Label>
              <Select value={accountId} onValueChange={setAccountId}>
                <SelectTrigger><SelectValue placeholder="Choose a cash account" /></SelectTrigger>
                <SelectContent>
                  {accounts.map((a) => (
                    <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                      {a.accountName} · {money(a.currentBalance)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label htmlFor="refund-reason">Reason</Label>
              <Textarea id="refund-reason" rows={2} value={reason} onChange={(e) => setReason(e.target.value)}
                        placeholder="e.g. Sale cancelled, customer asked for the money back" />
            </div>
            {error && <p className="rounded-md bg-red-50 p-2.5 text-sm text-red-700">{error}</p>}
          </div>
        )}
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={save} disabled={!valid || saving} className="bg-amber-600 hover:bg-amber-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Refund
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

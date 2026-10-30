"use client"

// Refund customer credit (migration 351): the business physically hands money
// back. Real Money Out from the account chosen here -- which may differ from
// the one the money came in on. Not an expense, and no stock moves (a pure
// refund is not a sales return).

import { CUSTOMER_REFUND_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useEffect, useState } from "react"
import { HandCoins, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { cn } from "@/lib/utils"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { formatCurrency } from "@/lib/utils/currency"
import { recordCustomerRefund } from "@/lib/api/customer-credit"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"

export interface RefundTarget {
  customerId: number
  customerName: string
  availableCredit: number
  /** 367: refund out of this one credit (its payment row). Absent = oldest credit first. */
  poultryPaymentId?: number | null
  /** e.g. "PAY-0012 · Customer advance", shown on the dialog. */
  creditLabel?: string | null
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
        poultryPaymentId: target.poultryPaymentId ?? null,
      })
      onRefunded()
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!target} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-lg")}>
        <DialogHeader>
          <FormDialogTitle icon={HandCoins} color="amber">Refund customer credit</FormDialogTitle>
          <DialogDescription>
            Give {target?.customerName || "the customer"} back money they paid and you still hold. This is money going out of the
            account you choose; it is recorded as a refund, not an expense, and no stock moves.
          </DialogDescription>
        </DialogHeader>
        {target && (
          <div className="min-w-0 space-y-4">
            <FormSection title="Customer" color="blue" tinted columns={1}>
              <div className="space-y-1 text-sm text-slate-600">
                <p>Customer: <span className="font-medium text-slate-900">{target.customerName}</span></p>
                {target.creditLabel && <p>Credit: <span className="font-medium text-slate-900">{target.creditLabel}</span></p>}
                <p>Available {target.poultryPaymentId ? "on this credit" : "credit"}: <span className="font-semibold tabular-nums text-slate-900">{money(target.availableCredit)}</span></p>
              </div>
            </FormSection>
            <FormSection title="Refund" color="green" tinted stackOnMobile>
              <div className="min-w-0 space-y-1">
                <Label htmlFor="refund-amount">Amount</Label>
                <Input id="refund-amount" type="number" min={0} step="0.01" className="bg-white text-right font-semibold tabular-nums"
                       value={amount} onChange={(e) => setAmount(e.target.value)} />
              </div>
              <div className="min-w-0 space-y-1">
                <Label>Method</Label>
                <Select value={method} onValueChange={setMethod}>
                  <SelectTrigger className="w-full bg-white"><SelectValue /></SelectTrigger>
                  <SelectContent>{METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div className="col-span-full min-w-0 space-y-1">
                <Label>Paid from</Label>
                <Select value={accountId} onValueChange={setAccountId}>
                  <SelectTrigger className="w-full bg-white"><SelectValue placeholder="Choose a cash account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.map((a) => (
                      <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                        {a.accountName} · {money(a.currentBalance)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </FormSection>
            <FormSection title="Reason" color="slate" tinted columns={1}>
              <div className="min-w-0 space-y-1">
                <Label htmlFor="refund-reason">Reason</Label>
                <ReasonSelect id="refund-reason" options={CUSTOMER_REFUND_REASONS} value={reason} onChange={setReason} />
              </div>
            </FormSection>
            {error && <p className="rounded-md bg-red-50 p-2.5 text-sm text-red-700">{error}</p>}
          </div>
        )}
        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={saving}>
          <Button onClick={save} disabled={!valid || saving} className={cn("px-6", FORM_DIALOG_PRIMARY.amber)}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {value > 0 ? `Refund · ${money(value)}` : "Refund"}
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}

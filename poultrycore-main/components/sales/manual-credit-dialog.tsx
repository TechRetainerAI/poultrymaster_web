"use client"

// Add customer credit by hand (migration 363), owner / admin only.
//
// The user never types a balance. They say WHERE the money came from, and
// that decides what else moves:
//   Opening balance  credit held before the farm used the system -- no cash, no P&L
//   Customer advance paid in advance, no sale yet -- real cash in to an account
//   Credit note      goodwill credit -- no cash; a cost on Profit & Loss

import { CUSTOMER_CREDIT_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useEffect, useState } from "react"
import { Loader2, PiggyBank } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"
import { formatCurrency } from "@/lib/utils/currency"
import { getCustomers } from "@/lib/api"
import { getUserContext } from "@/lib/api/config"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { createManualCredit, type ManualCreditKind } from "@/lib/api/customer-credit"

const KINDS: { value: ManualCreditKind; title: string; body: string }[] = [
  {
    value: "OpeningCredit",
    title: "Opening balance",
    body: "Credit the customer already had before you started using the system. No cash moves and profit is not affected.",
  },
  {
    value: "Deposit",
    title: "Customer advance",
    body: "The customer paid in advance, before buying anything. The money goes into the cash account you choose and shows in Cash Flow.",
  },
  {
    value: "CreditNote",
    title: "Credit note",
    body: "Credit you give the customer, e.g. for broken eggs or a late delivery. No cash moves; it is a cost, shown on Profit & Loss.",
  },
]

const METHODS = ["Cash", "Mobile Money", "Bank Transfer", "Check"]

interface Props {
  open: boolean
  currencyCode: string
  onOpenChange: (open: boolean) => void
  onCreated: (summary: { customerName: string; kind: ManualCreditKind; amount: number; paymentNumber: string | null }) => void
}

function today(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export function ManualCreditDialog({ open, currencyCode, onOpenChange, onCreated }: Props) {
  const [customers, setCustomers] = useState<{ id: number; name: string }[]>([])
  const [accounts, setAccounts] = useState<PoultryCashAccount[]>([])
  const [customerId, setCustomerId] = useState("")
  const [kind, setKind] = useState<ManualCreditKind>("OpeningCredit")
  const [amount, setAmount] = useState("")
  const [date, setDate] = useState(today())
  const [accountId, setAccountId] = useState("")
  const [method, setMethod] = useState("Cash")
  const [reference, setReference] = useState("")
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setCustomerId(""); setKind("OpeningCredit"); setAmount(""); setDate(today())
    setMethod("Cash"); setReference(""); setReason(""); setError(null)
    const { userId, farmId } = getUserContext()
    getCustomers(userId, farmId)
      .then((r: any) => {
        const list = (r?.success ? r.data : r) ?? []
        setCustomers((Array.isArray(list) ? list : [])
          .map((c: any) => ({ id: Number(c.customerId ?? c.id), name: String(c.name ?? c.customerName ?? "") }))
          .filter((c: { id: number; name: string }) => c.id > 0 && c.name)
          .sort((a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name)))
      })
      .catch(() => setCustomers([]))
    listPoultryCashAccounts()
      .then((a) => {
        const active = a.filter((x) => x.isActive !== false)
        setAccounts(active)
        setAccountId(active[0] ? String(active[0].poultryCashAccountId) : "")
      })
      .catch(() => setAccounts([]))
  }, [open])

  const value = Math.round((Number(amount) || 0) * 100) / 100
  const isDeposit = kind === "Deposit"
  const valid = !!customerId && value > 0 && reason.trim().length > 0 && !!date && (!isDeposit || !!accountId)
  const customerName = customers.find((c) => String(c.id) === customerId)?.name ?? ""

  const save = async () => {
    if (!valid) return
    setSaving(true); setError(null)
    try {
      const res = await createManualCredit({
        customerId: Number(customerId),
        kind,
        amount: value,
        creditDate: date,
        poultryCashAccountId: isDeposit ? Number(accountId) : null,
        paymentMethod: isDeposit ? method : null,
        reference: reference.trim() || null,
        reason: reason.trim(),
      })
      onCreated({ customerName, kind, amount: value, paymentNumber: res?.paymentNumber ?? null })
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><PiggyBank className="h-5 w-5 text-blue-600" /> Add customer credit</DialogTitle>
          <DialogDescription>
            Money held for a customer, to use on their next sales or refund. Say where it came from — that decides whether cash or profit moves.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Customer *</Label>
            <Select value={customerId} onValueChange={setCustomerId}>
              <SelectTrigger><SelectValue placeholder={customers.length ? "Choose the customer" : "Loading customers…"} /></SelectTrigger>
              <SelectContent>
                {customers.map((c) => <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label>Where the credit came from *</Label>
            <div className="space-y-2">
              {KINDS.map((k) => (
                <label key={k.value}
                       className={cn("flex cursor-pointer gap-2.5 rounded-md border p-2.5", kind === k.value ? "border-blue-400 bg-blue-50/60" : "border-slate-200")}>
                  <input type="radio" name="manual-credit-kind" className="mt-1" checked={kind === k.value} onChange={() => { setKind(k.value); setReason("") }} />
                  <span className="text-sm">
                    <span className="font-medium text-slate-900">{k.title}</span>
                    <span className="block text-xs text-slate-600">{k.body}</span>
                  </span>
                </label>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="mc-amount">Amount *</Label>
              <Input id="mc-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="mc-date">{kind === "OpeningCredit" ? "As at *" : "Date *"}</Label>
              <Input id="mc-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>

          {isDeposit && (
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Received into *</Label>
                <Select value={accountId} onValueChange={setAccountId}>
                  <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.map((a) => (
                      <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>Method</Label>
                <Select value={method} onValueChange={setMethod}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>
          )}

          <div className="space-y-1.5">
            <Label htmlFor="mc-ref">Reference</Label>
            <Input id="mc-ref" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional, e.g. receipt or old ledger page" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="mc-reason">Reason *</Label>
            <ReasonSelect id="mc-reason" options={CUSTOMER_CREDIT_REASONS[kind]} value={reason} onChange={setReason} />
          </div>

          {value > 0 && customerName && (
            <p className="rounded-md bg-slate-50 p-2.5 text-sm text-slate-700">
              {customerName} will hold <b className="tabular-nums">{formatCurrency(value, currencyCode)}</b> of credit.{" "}
              {isDeposit
                ? `${accounts.find((a) => String(a.poultryCashAccountId) === accountId)?.accountName ?? "The account"} goes up by the same amount.`
                : kind === "CreditNote"
                  ? "Profit & Loss shows it as a credit note (a cost). No cash moves."
                  : "No cash moves and profit is not affected."}
            </p>
          )}
          {error && <p className="rounded-md bg-red-50 p-2.5 text-sm text-red-700">{error}</p>}
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={save} disabled={!valid || saving} className="bg-blue-600 hover:bg-blue-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Add credit
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

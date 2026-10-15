"use client"

// Record customer debt (369), owner / admin only.
//
// What a customer already owes without a sale in the system -- e.g. eggs
// supplied before the farm started using it. The user records the event and
// why; the balance is derived. Not a sale: no revenue, no stock, no cash.

import { useEffect, useState } from "react"
import { FileWarning, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { formatCurrency } from "@/lib/utils/currency"
import { getCustomers } from "@/lib/api"
import { getUserContext } from "@/lib/api/config"
import {
  createCustomerDebt, CUSTOMER_DEBT_ENTRY_LABEL, type CustomerDebtEntryType,
} from "@/lib/api/customer-debt"

const ENTRY_TYPES = Object.keys(CUSTOMER_DEBT_ENTRY_LABEL) as CustomerDebtEntryType[]

interface Props {
  open: boolean
  currencyCode: string
  onOpenChange: (open: boolean) => void
  onCreated: (summary: { customerName: string; amount: number; debtNumber: string }) => void
}

function today(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export function CustomerDebtDialog({ open, currencyCode, onOpenChange, onCreated }: Props) {
  const [customers, setCustomers] = useState<{ id: number; name: string }[]>([])
  const [customerId, setCustomerId] = useState("")
  const [amount, setAmount] = useState("")
  const [date, setDate] = useState(today())
  const [entryType, setEntryType] = useState<CustomerDebtEntryType>("OpeningBalance")
  const [description, setDescription] = useState("")
  const [reference, setReference] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setCustomerId(""); setAmount(""); setDate(today()); setEntryType("OpeningBalance")
    setDescription(""); setReference(""); setNotes(""); setError(null)
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
  }, [open])

  const value = Math.round((Number(amount) || 0) * 100) / 100
  const valid = !!customerId && value > 0 && !!date && description.trim().length > 0
  const customerName = customers.find((c) => String(c.id) === customerId)?.name ?? ""

  const save = async () => {
    if (!valid || saving) return
    setSaving(true); setError(null)
    try {
      const res = await createCustomerDebt({
        customerId: Number(customerId),
        amount: value,
        debtDate: date,
        entryType,
        description: description.trim(),
        reference: reference.trim() || null,
        notes: notes.trim() || null,
      })
      onCreated({ customerName, amount: value, debtNumber: res?.debtNumber ?? "" })
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
          <DialogTitle className="flex items-center gap-2"><FileWarning className="h-5 w-5 text-amber-600" /> Record customer debt</DialogTitle>
          <DialogDescription>
            Money a customer already owes that is not on any sale here, e.g. eggs supplied before you started using the
            system. It is added to what they owe and can be paid like a sale. It is not a sale: no revenue, no stock and no cash.
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

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="cd-amount">Amount owed *</Label>
              <Input id="cd-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="cd-date">Owed from *</Label>
              <Input id="cd-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label>Why is it owed *</Label>
            <Select value={entryType} onValueChange={(v) => setEntryType(v as CustomerDebtEntryType)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {ENTRY_TYPES.map((t) => <SelectItem key={t} value={t}>{CUSTOMER_DEBT_ENTRY_LABEL[t]}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="cd-desc">Description *</Label>
            <Input id="cd-desc" value={description} onChange={(e) => setDescription(e.target.value)}
                   placeholder="e.g. Eggs supplied before we started using the system" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cd-ref">Reference</Label>
            <Input id="cd-ref" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional, e.g. old ledger page or invoice" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cd-notes">Notes</Label>
            <Textarea id="cd-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" />
          </div>

          {value > 0 && customerName && (
            <p className="rounded-md bg-slate-50 p-2.5 text-sm text-slate-700">
              {customerName} will owe <b className="tabular-nums">{formatCurrency(value, currencyCode)}</b> more. No cash moves and
              sales are not affected.
            </p>
          )}
          {error && <p className="rounded-md bg-red-50 p-2.5 text-sm text-red-700">{error}</p>}
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={save} disabled={!valid || saving} className="bg-amber-600 hover:bg-amber-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Record debt
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

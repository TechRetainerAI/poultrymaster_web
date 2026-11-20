"use client"

// Receive money from a customer: into a cash account, set against their
// oldest unpaid sales (or one sale, when opened from it).

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { listCashAccounts, receivePayment, type CashAccount } from "@/lib/api/livestock"
import { AMBER_BUTTON, fmtMoney, todayIso } from "./livestock-page"

export function ReceivePaymentDialog({ customerId, customerName, owes, saleId, onClose, onDone }: {
  customerId: number
  customerName: string
  owes: number
  saleId?: number
  onClose: () => void
  onDone: () => void
}) {
  const { toast } = useToast()
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [accountId, setAccountId] = useState<number | null>(null)
  const [amount, setAmount] = useState(String(owes))
  const [date, setDate] = useState(todayIso())
  const [reference, setReference] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => {
    listCashAccounts().then((a) => { setAccounts(a); setAccountId(a.find((x) => x.isDefault)?.accountId ?? a[0]?.accountId ?? null) }).catch(() => setAccounts([]))
  }, [])
  const n = Number(amount) || 0
  const save = async () => {
    setSaving(true)
    try {
      await receivePayment({ customerId, date, amount: n, accountId: accountId!, reference: reference.trim() || null, notes: notes.trim() || null, saleId: saleId ?? null })
      toast({ title: `Received ${fmtMoney(n)} from ${customerName}` })
      onDone()
    } catch (e: any) {
      toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Receive payment from {customerName}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-stone-600">Owes{saleId ? " on this sale" : ""}: <strong>{fmtMoney(owes)}</strong></p>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="rp-amt">Amount</Label><Input id="rp-amt" type="number" min={0} max={owes} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
            <div><Label htmlFor="rp-date">Date</Label><Input id="rp-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
          </div>
          <div>
            <Label>Into</Label>
            <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
              <SelectTrigger><SelectValue placeholder={accounts.length ? "Choose" : "Add a cash account first"} /></SelectTrigger>
              <SelectContent>{accounts.map((a) => <SelectItem key={a.accountId} value={String(a.accountId)}>{a.name}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div><Label htmlFor="rp-ref">Reference (mobile money ID, cheque no.)</Label><Input id="rp-ref" value={reference} onChange={(e) => setReference(e.target.value)} /></div>
          <div><Label htmlFor="rp-notes">Notes</Label><Textarea id="rp-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || n <= 0 || n > owes || !accountId} onClick={save}>{saving ? "Saving…" : "Receive"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

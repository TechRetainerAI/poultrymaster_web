"use client"

// Pay a supplier: from a cash account, set against their oldest unpaid
// purchases (or one purchase, when opened from it).

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { listCashAccounts, paySupplier, type CashAccount } from "@/lib/api/livestock"
import { AMBER_BUTTON, fmtMoney, todayIso } from "./livestock-page"

export function PaySupplierDialog({ supplierId, supplierName, owed, purchaseId, onClose, onDone }: {
  supplierId: number
  supplierName: string
  owed: number
  purchaseId?: number
  onClose: () => void
  onDone: () => void
}) {
  const { toast } = useToast()
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [accountId, setAccountId] = useState<number | null>(null)
  const [amount, setAmount] = useState(String(owed))
  const [date, setDate] = useState(todayIso())
  const [reference, setReference] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => {
    listCashAccounts().then((a) => { setAccounts(a); setAccountId(a.find((x) => x.isDefault)?.accountId ?? a[0]?.accountId ?? null) }).catch(() => setAccounts([]))
  }, [])
  const n = Number(amount) || 0
  const acct = accounts.find((a) => a.accountId === accountId)
  const short = acct && !acct.allowNegative && n > acct.balance
  const save = async () => {
    setSaving(true)
    try {
      await paySupplier({ supplierId, date, amount: n, accountId: accountId!, reference: reference.trim() || null, notes: notes.trim() || null, purchaseId: purchaseId ?? null })
      toast({ title: `Paid ${supplierName} ${fmtMoney(n)}` })
      onDone()
    } catch (e: any) {
      toast({ title: "Not paid", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Pay {supplierName}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-stone-600">Owed{purchaseId ? " on this purchase" : ""}: <strong>{fmtMoney(owed)}</strong></p>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ps-amt">Amount</Label><Input id="ps-amt" type="number" min={0} max={owed} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
            <div><Label htmlFor="ps-date">Date</Label><Input id="ps-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
          </div>
          <div>
            <Label>Paid from</Label>
            <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
              <SelectTrigger><SelectValue placeholder={accounts.length ? "Choose" : "Add a cash account first"} /></SelectTrigger>
              <SelectContent>{accounts.map((a) => <SelectItem key={a.accountId} value={String(a.accountId)}>{a.name} · {fmtMoney(a.balance)}</SelectItem>)}</SelectContent>
            </Select>
            {short && <p className="text-xs text-rose-700 mt-1">{acct!.name} holds only {fmtMoney(acct!.balance)}.</p>}
          </div>
          <div><Label htmlFor="ps-ref">Reference (cheque, transfer no.)</Label><Input id="ps-ref" value={reference} onChange={(e) => setReference(e.target.value)} /></div>
          <div><Label htmlFor="ps-notes">Notes</Label><Textarea id="ps-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || n <= 0 || n > owed || !accountId || !!short} onClick={save}>{saving ? "Paying…" : "Pay"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

"use client"

// Buy stock from Feed & stock without leaving the page -- the livestock twin
// of poultry's "Record Purchase" / "Buy more" on /poultry-supply-purchases.
//
// Items only. It records the same purchase as /livestock-purchases/new
// (splivestockpurchase_post): each line goes into stock at the price paid,
// and what was paid now leaves the chosen cash account. The invoice number
// (LP-0001, ...) is given by the database (470), never typed. Animals and bills
// stay on the full purchase page.

import { useEffect, useMemo, useState } from "react"
import { Plus, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { createPurchase, listCashAccounts, type CashAccount, type LivestockItem } from "@/lib/api/livestock"
import { SupplierSelect } from "@/components/livestock/supplier-select"
import { AMBER_BUTTON, fmtMoney, todayIso } from "./livestock-page"

type Line = { itemId: number | null; quantity: string; unitCost: string }
const blankLine = (itemId: number | null = null): Line => ({ itemId, quantity: "", unitCost: "" })

export function ItemPurchaseDialog({ open, onOpenChange, items, presetItemId, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  /** Active items the farm can buy. */
  items: LivestockItem[]
  presetItemId?: number | null
  onSaved: () => void
}) {
  const { toast } = useToast()
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [supplierId, setSupplierId] = useState<number | null>(null)
  const [date, setDate] = useState(todayIso())
  const [lines, setLines] = useState<Line[]>([blankLine()])
  const [payment, setPayment] = useState<"full" | "part" | "none">("full")
  const [paid, setPaid] = useState("")
  const [accountId, setAccountId] = useState<number | null>(null)
  const [dueDate, setDueDate] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open) return
    setSupplierId(null); setDate(todayIso()); setLines([blankLine(presetItemId ?? null)])
    setPayment("full"); setPaid(""); setDueDate(""); setNotes("")
    listCashAccounts().then((a) => {
      setAccounts(a)
      setAccountId(a.find((x) => x.isDefault)?.accountId ?? a[0]?.accountId ?? null)
    }).catch(() => setAccounts([]))
  }, [open, presetItemId])

  // No supplier: a cash purchase, paid in full there and then.
  useEffect(() => { if (!supplierId) setPayment("full") }, [supplierId])

  const total = useMemo(() => lines.reduce((s, l) => s + (Number(l.quantity) || 0) * (Number(l.unitCost) || 0), 0), [lines])
  const amountPaid = payment === "full" ? total : payment === "none" ? 0 : Number(paid) || 0
  const account = accounts.find((a) => a.accountId === accountId)
  const short = !!account && !account.allowNegative && amountPaid > account.balance
  const overpaid = payment === "part" && amountPaid > total
  const setLine = (i: number, patch: Partial<Line>) => setLines((ls) => ls.map((l, j) => (j === i ? { ...l, ...patch } : l)))

  const used = lines.filter((l) => Number(l.quantity) > 0)
  const linesOk = used.length > 0 && used.every((l) => l.itemId)
  const canSave = linesOk && !!date && (payment === "none" || !!accountId) && (!!supplierId || amountPaid >= total) && !short && !overpaid

  const save = async () => {
    setSaving(true)
    try {
      await createPurchase({
        supplierId, date, reference: null,
        dueDate: payment !== "full" ? dueDate || null : null, notes: notes.trim() || null,
        lines: used.map((l) => ({ lineType: "Item" as const, itemId: l.itemId as number, quantity: Number(l.quantity), unitCost: Number(l.unitCost) || 0 })),
        amountPaid, accountId: amountPaid > 0 ? accountId : null,
      })
      toast({ title: "Purchase recorded", description: "The items are in stock." })
      onOpenChange(false)
      onSaved()
    } catch (e: any) {
      toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-5xl">
        <DialogHeader><DialogTitle>Record purchase</DialogTitle></DialogHeader>
        <div className="space-y-4 max-h-[75vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
            <div className="sm:col-span-2"><Label>Supplier</Label><SupplierSelect value={supplierId} onChange={setSupplierId} allowNone /></div>
            <div><Label htmlFor="ip-date">Date</Label><Input id="ip-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div><Label>Invoice no.</Label><div className="h-9 px-3 flex items-center rounded-md border border-dashed bg-stone-50 text-sm text-stone-500">Given automatically (LP-0001…)</div></div>
          </div>

          <div className="rounded-md border">
            <div className="hidden sm:grid grid-cols-[1fr_8rem_9rem_8rem_2.5rem] gap-2 px-3 py-2 bg-stone-50 text-xs font-medium text-stone-600">
              <div>Item</div><div>Quantity</div><div>Price per unit</div><div className="text-right">Amount</div><div />
            </div>
            <div className="divide-y">
              {lines.map((l, i) => {
                const it = items.find((x) => x.itemId === l.itemId)
                return (
                  <div key={i} className="grid grid-cols-1 sm:grid-cols-[1fr_8rem_9rem_8rem_2.5rem] gap-2 px-3 py-2 items-center">
                    <Select value={l.itemId ? String(l.itemId) : ""} onValueChange={(v) => setLine(i, { itemId: Number(v) })}>
                      <SelectTrigger><SelectValue placeholder={items.length ? "Choose an item" : "Add an item first"} /></SelectTrigger>
                      <SelectContent>
                        {items.map((x) => <SelectItem key={x.itemId} value={String(x.itemId)}>{x.name} ({x.unit})</SelectItem>)}
                      </SelectContent>
                    </Select>
                    <Input type="number" min={0} step="any" placeholder={it?.unit ?? "Qty"} aria-label="Quantity"
                      value={l.quantity} onChange={(e) => setLine(i, { quantity: e.target.value })} />
                    <Input type="number" min={0} step="0.01" placeholder={`Per ${it?.unit ?? "unit"}`} aria-label="Price per unit"
                      value={l.unitCost} onChange={(e) => setLine(i, { unitCost: e.target.value })} />
                    <div className="text-right text-sm">{fmtMoney((Number(l.quantity) || 0) * (Number(l.unitCost) || 0))}</div>
                    <Button variant="ghost" size="icon" aria-label="Remove line" disabled={lines.length === 1}
                      onClick={() => setLines((ls) => ls.filter((_, j) => j !== i))}><X className="h-4 w-4" /></Button>
                  </div>
                )
              })}
            </div>
            <div className="flex items-center justify-between px-3 py-2 border-t">
              <Button variant="outline" size="sm" onClick={() => setLines((ls) => [...ls, blankLine()])}><Plus className="h-4 w-4 mr-1" />Another item</Button>
              <div className="text-base font-semibold text-stone-900">Total {fmtMoney(total)}</div>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
            <div>
              <Label>Paid now</Label>
              <Select value={payment} onValueChange={(v) => setPayment(v as typeof payment)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="full">All of it</SelectItem>
                  {supplierId && <SelectItem value="part">Part of it</SelectItem>}
                  {supplierId && <SelectItem value="none">Nothing yet (on credit)</SelectItem>}
                </SelectContent>
              </Select>
              {!supplierId && <p className="text-xs text-stone-500 mt-1">Choose a supplier to buy on credit.</p>}
            </div>
            {payment === "part" && (
              <div>
                <Label htmlFor="ip-paid">Amount paid</Label>
                <Input id="ip-paid" type="number" min={0} step="0.01" value={paid} onChange={(e) => setPaid(e.target.value)} />
                {overpaid && <p className="text-xs text-rose-700 mt-1">More than the total.</p>}
              </div>
            )}
            {payment !== "none" && (
              <div>
                <Label>Paid from (cash account)</Label>
                <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
                  <SelectTrigger><SelectValue placeholder={accounts.length ? "Choose" : "Add a cash account first"} /></SelectTrigger>
                  <SelectContent>{accounts.map((a) => <SelectItem key={a.accountId} value={String(a.accountId)}>{a.name} · {fmtMoney(a.balance)}</SelectItem>)}</SelectContent>
                </Select>
                {short && <p className="text-xs text-rose-700 mt-1">{account!.name} holds only {fmtMoney(account!.balance)}.</p>}
              </div>
            )}
            {payment !== "full" && (
              <div><Label htmlFor="ip-due">Pay by</Label><Input id="ip-due" type="date" min={date} value={dueDate} onChange={(e) => setDueDate(e.target.value)} /></div>
            )}
            {payment !== "full" && total > 0 && (
              <p className="sm:col-span-4 text-sm text-stone-600">Paying now: <strong className="text-emerald-700">{fmtMoney(amountPaid)}</strong> · Still owed: <strong>{fmtMoney(Math.max(total - amountPaid, 0))}</strong></p>
            )}
          </div>
          <div><Label htmlFor="ip-notes">Notes</Label><Textarea id="ip-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>
            {saving ? "Saving…" : (amountPaid > 0 ? `Record purchase · paying ${fmtMoney(amountPaid)} now` : "Record purchase · nothing paid now")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

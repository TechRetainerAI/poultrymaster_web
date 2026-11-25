"use client"

// 494: Collect feed -- grass, leaves, cassava tops and other feed cut in the
// forest / bush and carried back (cut-and-carry). The forage goes into stock
// like bought feed, so daily records and Distribute Feed take it out the same
// way. What collecting it cost (transport, fuel, a cutter's wage, a permit) is
// optional; when there is one it is paid from a cash account and becomes the
// forage's cost, so the P&L counts it once, when the forage is fed.

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { collectForage, listCashAccounts, type CashAccount, type LivestockItem } from "@/lib/api/livestock"
import { AMBER_BUTTON, fmtMoney, fmtNum, todayIso } from "./livestock-page"

export function ForageCollectDialog({ open, onOpenChange, items, presetItemId, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  /** Active items marked as collected feed (isForage). */
  items: LivestockItem[]
  presetItemId?: number | null
  onSaved: () => void
}) {
  const { toast } = useToast()
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [itemId, setItemId] = useState<number | null>(null)
  const [date, setDate] = useState(todayIso())
  const [quantity, setQuantity] = useState("")
  const [place, setPlace] = useState("")
  const [collectedBy, setCollectedBy] = useState("")
  const [hasCost, setHasCost] = useState(false)
  const [cost, setCost] = useState("")
  const [accountId, setAccountId] = useState<number | null>(null)
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open) return
    setItemId(presetItemId ?? (items.length === 1 ? items[0].itemId : null))
    setDate(todayIso()); setQuantity(""); setPlace(""); setCollectedBy("")
    setHasCost(false); setCost(""); setNotes("")
    listCashAccounts().then((a) => {
      setAccounts(a)
      setAccountId(a.find((x) => x.isDefault)?.accountId ?? a[0]?.accountId ?? null)
    }).catch(() => setAccounts([]))
  }, [open, presetItemId, items])

  const item = items.find((i) => i.itemId === itemId)
  const qty = Number(quantity) || 0
  const amount = hasCost ? Number(cost) || 0 : 0
  const account = accounts.find((a) => a.accountId === accountId)
  const short = amount > 0 && !!account && !account.allowNegative && amount > account.balance
  const canSave = !!itemId && qty > 0 && !!date && (!hasCost || (amount > 0 && !!accountId)) && !short

  const save = async () => {
    setSaving(true)
    try {
      await collectForage({
        itemId: itemId as number, date, quantity: qty,
        place: place.trim() || null, collectedBy: collectedBy.trim() || null,
        cost: amount, accountId: amount > 0 ? accountId : null, notes: notes.trim() || null,
      })
      toast({ title: "Feed collected", description: `${fmtNum(qty)} ${item?.unit ?? ""} of ${item?.name ?? "feed"} is in stock.` })
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
      <DialogContent className="sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>Collect feed</DialogTitle>
          <DialogDescription>Grass, leaves or other feed cut in the forest or bush and brought back to the farm.</DialogDescription>
        </DialogHeader>
        {items.length === 0 ? (
          <p className="text-sm text-stone-600">
            No collected feed yet. Use <strong>Add item</strong>, choose kind <strong>Feed</strong> and switch on
            {" "}<strong>Collected from the forest / bush</strong> (e.g. &quot;Elephant grass&quot;, counted in bundles).
          </p>
        ) : (
          <div className="space-y-4 max-h-[70vh] overflow-y-auto pr-1">
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div className="sm:col-span-2">
                <Label>Feed</Label>
                <Select value={itemId ? String(itemId) : ""} onValueChange={(v) => setItemId(Number(v))}>
                  <SelectTrigger><SelectValue placeholder="Choose the feed" /></SelectTrigger>
                  <SelectContent>
                    {items.map((i) => <SelectItem key={i.itemId} value={String(i.itemId)}>{i.name} ({i.unit})</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label htmlFor="fc-date">Date</Label>
                <Input id="fc-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
              </div>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div>
                <Label htmlFor="fc-qty">How much was brought back{item ? ` (${item.unit})` : ""}</Label>
                <Input id="fc-qty" type="number" min={0} step="any" value={quantity} onChange={(e) => setQuantity(e.target.value)} />
                {item?.kgPerUnit && item.unit !== "kg" && qty > 0 && (
                  <p className="text-xs text-stone-500 mt-1">About {fmtNum(qty * item.kgPerUnit)} kg</p>
                )}
              </div>
              <div>
                <Label htmlFor="fc-place">Where from</Label>
                <Input id="fc-place" value={place} placeholder="e.g. Afram forest" onChange={(e) => setPlace(e.target.value)} />
              </div>
              <div>
                <Label htmlFor="fc-by">Collected by</Label>
                <Input id="fc-by" value={collectedBy} placeholder="Who went" onChange={(e) => setCollectedBy(e.target.value)} />
              </div>
            </div>

            <div className="rounded-md border p-3 space-y-3">
              <label className="flex items-center gap-2 text-sm font-medium">
                <Switch checked={hasCost} onCheckedChange={setHasCost} /> Collecting it cost money
              </label>
              <p className="text-xs text-stone-500">
                Transport, fuel, a cutter&apos;s wage or a permit. It is paid from a cash account and becomes the cost of this feed,
                so it counts as feed cost when the animals eat it. Leave it off if it cost nothing.
              </p>
              {hasCost && (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div>
                    <Label htmlFor="fc-cost">Total cost</Label>
                    <Input id="fc-cost" type="number" min={0} step="0.01" value={cost} onChange={(e) => setCost(e.target.value)} />
                    {amount > 0 && qty > 0 && (
                      <p className="text-xs text-stone-500 mt-1">{fmtMoney(amount / qty)} per {item?.unit ?? "unit"}</p>
                    )}
                  </div>
                  <div>
                    <Label>Paid from (cash account)</Label>
                    <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
                      <SelectTrigger><SelectValue placeholder={accounts.length ? "Choose" : "Add a cash account first"} /></SelectTrigger>
                      <SelectContent>{accounts.map((a) => <SelectItem key={a.accountId} value={String(a.accountId)}>{a.name} · {fmtMoney(a.balance)}</SelectItem>)}</SelectContent>
                    </Select>
                    {short && <p className="text-xs text-rose-700 mt-1">{account!.name} holds only {fmtMoney(account!.balance)}.</p>}
                  </div>
                </div>
              )}
            </div>
            <div><Label htmlFor="fc-notes">Notes</Label><Textarea id="fc-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
          </div>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          {items.length > 0 && (
            <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>
              {saving ? "Saving…" : amount > 0 ? `Collect · paying ${fmtMoney(amount)}` : "Collect · no cost"}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

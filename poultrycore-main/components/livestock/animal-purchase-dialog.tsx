"use client"

// Buy animals from Intake batches without leaving the page -- the livestock
// twin of buying birds from poultry's Flock Batch page. It records the same
// purchase as /livestock-purchases/new (splivestockpurchase_post): each line of
// animals becomes an intake batch, and what was paid now leaves the chosen
// cash account. The invoice number (LP-0001, ...) is given by the database.

import { useEffect, useMemo, useState } from "react"
import { Plus, ShoppingCart, Wallet, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { createPurchase, listCashAccounts, type CashAccount } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { SupplierSelect } from "@/components/livestock/supplier-select"
import { AgeTextInput, BreedSelect } from "@/components/livestock/breed-age-inputs"
import { AMBER_BUTTON, fmtMoney, todayIso } from "./livestock-page"

type Line = { batchCode: string; speciesCode: string; breed: string; age: string; quantity: string; unitCost: string }

export function AnimalPurchaseDialog({ open, onOpenChange, onSaved }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  onSaved: () => void
}) {
  const { toast } = useToast()
  const { kept } = useLivestockSpecies()
  const blankLine = (): Line => ({ batchCode: "", speciesCode: kept.length === 1 ? kept[0].speciesCode : "", breed: "", age: "", quantity: "", unitCost: "" })
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
  const [resetKey, setResetKey] = useState(0)

  useEffect(() => {
    if (!open) return
    setSupplierId(null); setDate(todayIso()); setLines([blankLine()]); setResetKey((k) => k + 1)
    setPayment("full"); setPaid(""); setDueDate(""); setNotes("")
    listCashAccounts().then((a) => {
      setAccounts(a)
      setAccountId(a.find((x) => x.isDefault)?.accountId ?? a[0]?.accountId ?? null)
    }).catch(() => setAccounts([]))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  // No supplier: a cash purchase, paid in full there and then.
  useEffect(() => { if (!supplierId) setPayment("full") }, [supplierId])

  const total = useMemo(() => lines.reduce((s, l) => s + (Number(l.quantity) || 0) * (Number(l.unitCost) || 0), 0), [lines])
  const amountPaid = payment === "full" ? total : payment === "none" ? 0 : Number(paid) || 0
  const account = accounts.find((a) => a.accountId === accountId)
  const short = !!account && !account.allowNegative && amountPaid > account.balance
  const overpaid = payment === "part" && amountPaid > total
  const setLine = (i: number, patch: Partial<Line>) => setLines((ls) => ls.map((l, j) => (j === i ? { ...l, ...patch } : l)))

  const used = lines.filter((l) => Number(l.quantity) > 0)
  const codes = used.map((l) => l.batchCode.trim().toLowerCase()).filter(Boolean)
  const dupCode = codes.length !== new Set(codes).size
  const linesOk = used.length > 0 && used.every((l) => l.speciesCode) && !dupCode
  const canSave = linesOk && !!date && (payment === "none" || !!accountId) && (!!supplierId || amountPaid >= total) && !short && !overpaid

  const save = async () => {
    setSaving(true)
    try {
      await createPurchase({
        supplierId, date, reference: null,
        dueDate: payment !== "full" ? dueDate || null : null, notes: notes.trim() || null,
        lines: used.map((l) => ({ lineType: "Animals" as const, batchCode: l.batchCode.trim() || null, speciesCode: l.speciesCode, quantity: Number(l.quantity),
          unitCost: Number(l.unitCost) || 0, breed: l.breed || null, ageAtIntake: l.age || null })),
        amountPaid, accountId: amountPaid > 0 ? accountId : null,
      })
      toast({ title: "Purchase recorded", description: "The animals are in as an intake batch." })
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
      <DialogContent className="sm:max-w-6xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-amber-900">
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-amber-100 text-amber-700"><ShoppingCart className="h-4 w-4" /></span>
            Buy animals
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4 max-h-[75vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-1 sm:grid-cols-4 gap-3 rounded-lg border border-amber-200 bg-amber-50/60 p-3">
            <div className="sm:col-span-2"><Label>Supplier</Label><SupplierSelect value={supplierId} onChange={setSupplierId} allowNone /></div>
            <div><Label htmlFor="ap-date">Date</Label><Input id="ap-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div><Label>Invoice no.</Label><div className="h-9 px-3 flex items-center rounded-md border border-dashed border-amber-300 bg-white text-sm text-amber-800">Given automatically (LP-0001…)</div></div>
          </div>

          <div className="rounded-lg border border-amber-200 overflow-hidden">
            <div className="hidden sm:grid grid-cols-[8rem_1fr_1fr_14rem_7rem_8rem_7rem_2.5rem] gap-2 px-3 py-2 bg-amber-600 text-xs font-semibold text-white">
              <div>Batch code</div><div>Animal</div><div>Breed</div><div>Age when bought</div><div>Quantity</div><div>Price each</div><div className="text-right">Amount</div><div />
            </div>
            <div className="divide-y divide-amber-100">
              {lines.map((l, i) => (
                <div key={i} className="grid grid-cols-1 sm:grid-cols-[8rem_1fr_1fr_14rem_7rem_8rem_7rem_2.5rem] gap-2 px-3 py-2 items-center odd:bg-white even:bg-amber-50/40">
                  <Input placeholder="Made for you" aria-label="Batch code" maxLength={50}
                    value={l.batchCode} onChange={(e) => setLine(i, { batchCode: e.target.value })} />
                  <Select value={l.speciesCode} onValueChange={(v) => setLine(i, { speciesCode: v, breed: "" })}>
                    <SelectTrigger><SelectValue placeholder="Animal" /></SelectTrigger>
                    <SelectContent>{kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}</SelectContent>
                  </Select>
                  <BreedSelect speciesCode={l.speciesCode} value={l.breed || null} onChange={(v) => setLine(i, { breed: v ?? "" })} placeholder="Breed" />
                  <AgeTextInput key={`${resetKey}-${i}-${lines.length}`} value={l.age || null} onChange={(v) => setLine(i, { age: v ?? "" })} />
                  <Input type="number" min={0} step={1} placeholder="Quantity" aria-label="Quantity"
                    value={l.quantity} onChange={(e) => setLine(i, { quantity: e.target.value })} />
                  <Input type="number" min={0} step="0.01" placeholder="Price each" aria-label="Price each"
                    value={l.unitCost} onChange={(e) => setLine(i, { unitCost: e.target.value })} />
                  <div className="text-right text-sm font-medium text-amber-900">{fmtMoney((Number(l.quantity) || 0) * (Number(l.unitCost) || 0))}</div>
                  <Button variant="ghost" size="icon" aria-label="Remove line" disabled={lines.length === 1}
                    onClick={() => setLines((ls) => ls.filter((_, j) => j !== i))}><X className="h-4 w-4 text-rose-600" /></Button>
                </div>
              ))}
            </div>
            {dupCode && <p className="px-3 py-1 text-xs text-rose-700">Two lines have the same batch code.</p>}
            <div className="flex items-center justify-between px-3 py-2 border-t border-amber-200 bg-amber-50">
              <Button variant="outline" size="sm" className="border-amber-300 text-amber-800 hover:bg-amber-100" onClick={() => setLines((ls) => [...ls, blankLine()])}><Plus className="h-4 w-4 mr-1" />More animals</Button>
              <div className="text-base font-bold text-amber-900">Total {fmtMoney(total)}</div>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-4 gap-3 rounded-lg border border-emerald-200 bg-emerald-50/60 p-3">
            <p className="sm:col-span-4 flex items-center gap-2 text-sm font-semibold text-emerald-800"><Wallet className="h-4 w-4" />Payment</p>
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
                <Label htmlFor="ap-paid">Amount paid</Label>
                <Input id="ap-paid" type="number" min={0} step="0.01" value={paid} onChange={(e) => setPaid(e.target.value)} />
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
              <div><Label htmlFor="ap-due">Pay by</Label><Input id="ap-due" type="date" min={date} value={dueDate} onChange={(e) => setDueDate(e.target.value)} /></div>
            )}
            {payment !== "full" && total > 0 && (
              <p className="sm:col-span-4 text-sm text-stone-600">Paying now: <strong className="text-emerald-700">{fmtMoney(amountPaid)}</strong> · Still owed: <strong>{fmtMoney(Math.max(total - amountPaid, 0))}</strong></p>
            )}
          </div>
          <div><Label htmlFor="ap-notes">Notes</Label><Textarea id="ap-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
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

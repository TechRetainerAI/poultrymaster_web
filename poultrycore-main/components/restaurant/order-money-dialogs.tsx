"use client"

/**
 * Take Payment and Refund, shared by the POS and the Orders screen.
 *
 * The rules they follow come from the server (migration 323), so these dialogs
 * only shape the request:
 *  - A payment sends the amount APPLIED to the bill, never the cash tendered.
 *    Change is shown here and never stored; the server refuses more than the
 *    balance due.
 *  - Cash goes to a till. With several tills open the server needs to know which
 *    one, so the dialog asks; with none open it lands in the main cash box.
 *  - A gift card is a payment method: the card is debited in the same call that
 *    records the payment, so the order and the card can never disagree.
 */

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Banknote, Check, CreditCard, Gift, Loader2, RotateCcw, Smartphone } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { addOrderPayment, checkGiftCardBalance, getOrder, refundOrder, type Order } from "@/lib/api/restaurant"
import { listShifts, type CashShift } from "@/lib/api/restaurant-finance"

const round2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100
const money = (n: number) => round2(n).toFixed(2)

export interface PaymentResult {
  order: Order
  payment: { method: string; applied: number; tendered: number; change: number; tip: number }
}

const PAY_METHODS = [
  { id: "Cash", icon: Banknote, label: "Cash" },
  { id: "Card", icon: CreditCard, label: "Card" },
  { id: "MobileMoney", icon: Smartphone, label: "Mobile Money" },
  { id: "GiftCard", icon: Gift, label: "Gift Card" },
] as const

/** Open tills, loaded when a dialog opens. Failure is non-fatal: cash then goes to the cash box. */
function useOpenShifts(open: boolean) {
  const [shifts, setShifts] = useState<CashShift[]>([])
  useEffect(() => {
    if (!open) return
    listShifts("Open").then(setShifts).catch(() => setShifts([]))
  }, [open])
  return shifts
}

function TillPicker({ shifts, value, onChange }: { shifts: CashShift[]; value: number | null; onChange: (v: number | null) => void }) {
  if (shifts.length === 0) {
    return <p className="text-xs text-muted-foreground">No till shift is open — cash will be recorded in the main cash box.</p>
  }
  if (shifts.length === 1) {
    return <p className="text-xs text-muted-foreground">Cash goes into <b>{shifts[0].tillName}</b> ({shifts[0].shiftNumber}).</p>
  }
  return (
    <div className="space-y-1.5">
      <Label>Till</Label>
      <Select value={value ? String(value) : ""} onValueChange={(v) => onChange(v ? Number(v) : null)}>
        <SelectTrigger className="h-10"><SelectValue placeholder="Which till is the cash going into?" /></SelectTrigger>
        <SelectContent>
          {shifts.map((s) => (
            <SelectItem key={s.shiftId} value={String(s.shiftId)}>{s.tillName} — {s.shiftNumber}{s.openedBy ? ` (${s.openedBy})` : ""}</SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}

export function TakePaymentDialog({
  open, onOpenChange, order, onPaid,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  order: Order | null
  onPaid: (result: PaymentResult) => void
}) {
  const { toast } = useToast()
  const shifts = useOpenShifts(open)
  const due = order ? round2(order.totalAmount - order.paidAmount) : 0

  const [method, setMethod] = useState<string>("Cash")
  const [tendered, setTendered] = useState<string>("")
  const [amount, setAmount] = useState<string>("")
  const [tip, setTip] = useState<string>("")
  const [reference, setReference] = useState("")
  const [shiftId, setShiftId] = useState<number | null>(null)
  const [cardBalance, setCardBalance] = useState<number | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open) return
    setMethod("Cash"); setTendered(due ? money(due) : ""); setAmount(due ? money(due) : "")
    setTip(""); setReference(""); setShiftId(null); setCardBalance(null)
  }, [open, due])

  const isCash = method === "Cash"
  const tenderedNum = round2(parseFloat(tendered))
  const applied = isCash ? round2(Math.min(tenderedNum || 0, due)) : round2(parseFloat(amount) || 0)
  const change = isCash ? round2(Math.max(0, (tenderedNum || 0) - due)) : 0
  const tipNum = round2(parseFloat(tip) || 0)

  const problem = useMemo(() => {
    if (!order) return "No order selected."
    if (due <= 0) return "This order is already fully paid."
    if (applied <= 0) return isCash ? "Enter the cash received." : "Enter the amount."
    if (!isCash && applied > due) return `The most you can take is ${money(due)}.`
    if (method === "GiftCard" && !reference.trim()) return "Enter the gift card number."
    if (method === "GiftCard" && cardBalance !== null && applied > cardBalance) return `The card only has ${money(cardBalance)}.`
    if (isCash && shifts.length > 1 && !shiftId) return "Choose the till."
    if (tipNum < 0) return "A tip cannot be negative."
    if (method === "GiftCard" && tipNum > 0) return "A tip cannot be paid from a gift card."
    return null
  }, [order, due, applied, isCash, method, reference, cardBalance, shifts.length, shiftId, tipNum])

  async function lookUpCard() {
    if (!reference.trim()) return
    const card = await checkGiftCardBalance(reference.trim())
    if (!card) { setCardBalance(null); toast({ title: "Card not found", variant: "destructive" }); return }
    setCardBalance(card.currentBalance)
    setAmount(money(Math.min(card.currentBalance, due)))
    if (card.status !== "Active") toast({ title: `Card is ${card.status}`, variant: "destructive" })
  }

  async function submit() {
    if (!order || problem) return
    setSaving(true)
    try {
      await addOrderPayment(order.orderId, {
        paymentMethod: method, amount: applied, tipAmount: tipNum,
        reference: method === "GiftCard" ? reference.trim() : null,
        shiftId: isCash ? shiftId : null,
      })
      const fresh = await getOrder(order.orderId)
      onPaid({ order: fresh, payment: { method, applied, tendered: isCash ? tenderedNum : applied, change, tip: tipNum } })
    } catch (e: any) {
      toast({ title: "Payment not recorded", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Take payment{order ? ` — ${order.orderNumber}` : ""}</DialogTitle>
          <DialogDescription>
            {order && <>Total {money(order.totalAmount)}{order.paidAmount > 0 && <> · paid {money(order.paidAmount)}</>} · <b>due {money(due)}</b></>}
          </DialogDescription>
        </DialogHeader>
        {order && (
          <div className="space-y-4">
            {(order.taxAmount > 0 || order.serviceChargeAmount > 0 || order.discountAmount > 0) && (
              <div className="rounded-lg bg-gray-50 p-3 text-xs space-y-1">
                <div className="flex justify-between"><span>Subtotal</span><span>{money(order.subtotal)}</span></div>
                {order.discountAmount > 0 && <div className="flex justify-between text-red-600"><span>Discount</span><span>-{money(order.discountAmount)}</span></div>}
                {order.serviceChargeAmount > 0 && <div className="flex justify-between"><span>Service charge</span><span>{money(order.serviceChargeAmount)}</span></div>}
                {order.taxAmount > 0 && <div className="flex justify-between"><span>Tax</span><span>{money(order.taxAmount)}</span></div>}
              </div>
            )}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {PAY_METHODS.map((m) => (
                <button key={m.id} type="button" onClick={() => setMethod(m.id)}
                  className={`flex flex-col items-center gap-1.5 p-3 rounded-xl border-2 transition-all ${method === m.id ? "border-rose-500 bg-rose-50" : "border-gray-200 hover:border-gray-300"}`}>
                  <m.icon className={`h-5 w-5 ${method === m.id ? "text-rose-600" : "text-gray-500"}`} />
                  <span className={`text-xs font-medium ${method === m.id ? "text-rose-700" : "text-gray-600"}`}>{m.label}</span>
                </button>
              ))}
            </div>

            {isCash ? (
              <>
                <div className="space-y-1.5">
                  <Label>Cash received</Label>
                  <Input type="number" inputMode="decimal" step="0.01" min={0} value={tendered} onChange={(e) => setTendered(e.target.value)}
                    className="h-12 text-lg font-bold text-center" />
                </div>
                <div className="grid grid-cols-2 gap-2 text-sm">
                  <div className="rounded-lg border p-2 text-center"><div className="text-xs text-muted-foreground">Applied to bill</div><div className="font-semibold">{money(applied)}</div></div>
                  <div className={`rounded-lg border p-2 text-center ${change > 0 ? "bg-green-50 border-green-200" : ""}`}><div className="text-xs text-muted-foreground">Change to give</div><div className="font-semibold">{money(change)}</div></div>
                </div>
                <TillPicker shifts={shifts} value={shiftId} onChange={setShiftId} />
              </>
            ) : (
              <>
                {method === "GiftCard" && (
                  <div className="space-y-1.5">
                    <Label>Gift card number</Label>
                    <div className="flex gap-2">
                      <Input value={reference} onChange={(e) => { setReference(e.target.value); setCardBalance(null) }} placeholder="GC-XXXXXXXX" className="h-10 uppercase" />
                      <Button type="button" variant="outline" onClick={lookUpCard}>Check</Button>
                    </div>
                    {cardBalance !== null && <p className="text-xs text-muted-foreground">Balance {money(cardBalance)}</p>}
                  </div>
                )}
                <div className="space-y-1.5">
                  <Label>Amount</Label>
                  <Input type="number" inputMode="decimal" step="0.01" min={0} max={due} value={amount} onChange={(e) => setAmount(e.target.value)}
                    className="h-12 text-lg font-bold text-center" />
                  {applied > 0 && applied < due && <p className="text-xs text-amber-700">Part payment — {money(due - applied)} will still be due.</p>}
                </div>
              </>
            )}
            {method !== "GiftCard" && (
              <div className="space-y-1.5">
                <Label>Tip (optional)</Label>
                <Input type="number" inputMode="decimal" step="0.01" min={0} value={tip} onChange={(e) => setTip(e.target.value)} className="h-10" />
              </div>
            )}
            {problem && order && due > 0 && <p className="text-xs text-rose-700">{problem}</p>}
          </div>
        )}
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button className="bg-green-600 hover:bg-green-700" onClick={submit} disabled={!!problem || saving}>
            {saving ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Check className="h-4 w-4 mr-2" />}
            Record {money(applied)}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

const REFUND_METHODS = [
  { id: "Cash", label: "Cash" },
  { id: "Card", label: "Card" },
  { id: "MobileMoney", label: "Mobile Money" },
  { id: "Bank Transfer", label: "Bank Transfer" },
]

export function RefundDialog({
  open, onOpenChange, order, onRefunded,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  order: Order | null
  onRefunded: (order: Order) => void
}) {
  const { toast } = useToast()
  const shifts = useOpenShifts(open)
  const [amount, setAmount] = useState("")
  const [method, setMethod] = useState("Cash")
  const [reason, setReason] = useState("")
  const [shiftId, setShiftId] = useState<number | null>(null)
  const [saving, setSaving] = useState(false)
  const paid = order ? round2(order.paidAmount) : 0

  useEffect(() => {
    if (!open) return
    setAmount(paid ? money(paid) : ""); setMethod("Cash"); setReason(""); setShiftId(null)
  }, [open, paid])

  const amt = round2(parseFloat(amount) || 0)
  const problem = !order ? "No order selected."
    : paid <= 0 ? "Nothing has been paid on this order."
    : amt <= 0 ? "Enter the amount to refund."
    : amt > paid ? `You cannot refund more than the ${money(paid)} paid.`
    : !reason.trim() ? "Give a reason."
    : method === "Cash" && shifts.length > 1 && !shiftId ? "Choose the till the cash comes out of."
    : null

  async function submit() {
    if (!order || problem) return
    setSaving(true)
    try {
      await refundOrder(order.orderId, { amount: amt, paymentMethod: method, reason: reason.trim(), shiftId: method === "Cash" ? shiftId : null })
      const fresh = await getOrder(order.orderId)
      toast({ title: `Refunded ${money(amt)}`, description: fresh.status === "Refunded" ? "The order is now Refunded." : undefined })
      onRefunded(fresh)
    } catch (e: any) {
      toast({ title: "Refund not recorded", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Refund{order ? ` — ${order.orderNumber}` : ""}</DialogTitle>
          <DialogDescription>Paid so far: {money(paid)}. Refunding all of it marks the order Refunded.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Amount</Label>
              <Input type="number" inputMode="decimal" step="0.01" min={0} max={paid} value={amount} onChange={(e) => setAmount(e.target.value)} className="h-10" />
            </div>
            <div className="space-y-1.5">
              <Label>Refund as</Label>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                <SelectContent>{REFUND_METHODS.map((m) => <SelectItem key={m.id} value={m.id}>{m.label}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Reason</Label>
            <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Wrong dish served" className="h-10" />
          </div>
          {method === "Cash" && <TillPicker shifts={shifts} value={shiftId} onChange={setShiftId} />}
          {problem && order && paid > 0 && <p className="text-xs text-rose-700">{problem}</p>}
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button className="bg-rose-600 hover:bg-rose-700" onClick={submit} disabled={!!problem || saving}>
            {saving ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <RotateCcw className="h-4 w-4 mr-2" />}
            Refund {money(amt)}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

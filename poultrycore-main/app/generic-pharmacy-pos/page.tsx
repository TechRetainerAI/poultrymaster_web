"use client"

// Pharmacy -> Pharmacy till (migration 511).
// A point of sale for medicines. It sells through the normal Generic sale (createSale +
// approveSale), so the sale shows on Sales, Cash, Daily closing and P&L like any other.
// What it adds for a pharmacy:
//   - search by brand, generic name, barcode or SKU;
//   - sell by the tablet, strip or box (each with its own price); stock goes down in tablets;
//   - never sells more than the stock that has not expired;
//   - a chemical shop cannot sell Class A or B medicines;
//   - a Class A medicine needs a prescription record (patient, prescriber), saved with the sale.

import { useEffect, useMemo, useRef, useState } from "react"
import Link from "next/link"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { AlertTriangle, ClipboardList, Loader2, Minus, Plus, Printer, Search, ShoppingCart, Trash2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { PharmacyShell } from "@/components/generic/pharmacy/pharmacy-shell"
import { ClassBadge } from "@/components/generic/pharmacy/badges"
import {
  approveSale, createSale, getCashAccounts, getCustomers,
  type GenericCashAccount, type GenericCustomer, type GenericSaleItem,
} from "@/lib/api/generic"
import {
  createPrescription, getMedicines, getPharmacySettings,
  type Medicine, type PharmacySettings,
} from "@/lib/api/generic-pharmacy"
import { describeQty, sellBlockReason, sellUnits, sellableStock } from "@/lib/generic/pharmacy"

const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card", "Credit"]

type Line = { key: number; med: Medicine; unit: string; factor: number; qty: number; price: number; directions: string }

type Receipt = {
  saleId: number; receiptNumber: string; date: string; customer: string; paymentMethod: string
  lines: { name: string; qty: number; unit: string; price: number; total: number; directions?: string }[]
  total: number; received: number; change: number; prescriptionId?: number | null
}

const round2 = (n: number) => Math.round(n * 100) / 100

export default function PharmacyPosPage() {
  const { toast } = useToast()
  const fmt = useFmt()
  const searchRef = useRef<HTMLInputElement>(null)
  const nextKey = useRef(1)

  const [loading, setLoading] = useState(true)
  const [meds, setMeds] = useState<Medicine[]>([])
  const [settings, setSettings] = useState<PharmacySettings>({ shopType: "Pharmacy", requirePrescriptionClassA: true, expiryWarningDays: 90, saved: false })
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])

  const [search, setSearch] = useState("")
  const [lines, setLines] = useState<Line[]>([])
  const [customerId, setCustomerId] = useState("walk-in")
  const [walkInName, setWalkInName] = useState("")
  const [payMethod, setPayMethod] = useState("Cash")
  const [cashAccountId, setCashAccountId] = useState("")
  const [received, setReceived] = useState("")
  const [rx, setRx] = useState({ patientName: "", patientPhone: "", prescriberName: "", prescriberFacility: "", prescriptionRef: "", prescriptionDate: new Date().toISOString().slice(0, 10) })
  const [completing, setCompleting] = useState(false)
  const [receipt, setReceipt] = useState<Receipt | null>(null)

  const loadMeds = () => getMedicines().then((ms) => setMeds(ms.filter((m) => m.isActive)))

  useEffect(() => {
    ;(async () => {
      try {
        const [ms, st, cs, ca] = await Promise.all([
          getMedicines(), getPharmacySettings(), getCustomers().catch(() => [] as GenericCustomer[]), getCashAccounts(),
        ])
        setMeds(ms.filter((m) => m.isActive)); setSettings(st); setCustomers(cs); setCashAccounts(ca)
        const first = ca.find((a) => a.isActive)
        if (first) setCashAccountId(String(first.genericCashAccountId))
      } catch (e: any) {
        toast({ title: "Could not load the till", description: e?.message, variant: "destructive" })
      } finally { setLoading(false) }
    })()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const results = useMemo(() => {
    const q = search.trim().toLowerCase()
    const list = q
      ? meds.filter((m) => [m.productName, m.genericName, m.barcode, m.sku, m.strength].some((v) => (v ?? "").toLowerCase().includes(q)))
      : meds
    return list.slice(0, 30)
  }, [meds, search])

  /** Base units of each medicine already in the cart. */
  const inCart = useMemo(() => {
    const m = new Map<number, number>()
    for (const l of lines) m.set(l.med.genericProductId, (m.get(l.med.genericProductId) ?? 0) + l.qty * l.factor)
    return m
  }, [lines])

  const overStock = useMemo(() => {
    const out = new Set<number>()
    for (const [pid, qty] of inCart) {
      const m = meds.find((x) => x.genericProductId === pid)
      if (m && m.trackInventory && qty > sellableStock(m) + 1e-9) out.add(pid)
    }
    return out
  }, [inCart, meds])

  const needsRx = lines.some((l) => l.med.isMedicine && l.med.medicineClass === "A")
  const rxRequired = needsRx && settings.requirePrescriptionClassA
  const total = round2(lines.reduce((s, l) => s + l.qty * l.price, 0))
  const receivedNum = Number(received) || 0
  const change = payMethod === "Cash" ? round2(receivedNum - total) : 0

  const addMed = (m: Medicine) => {
    const block = m.isMedicine ? sellBlockReason(settings.shopType, m.medicineClass) : null
    if (block) { toast({ title: "Cannot sell this here", description: block, variant: "destructive" }); return }
    const u = sellUnits(m)[0]
    setLines((ls) => {
      const same = ls.find((l) => l.med.genericProductId === m.genericProductId && l.unit === u.unit)
      if (same) return ls.map((l) => (l === same ? { ...l, qty: l.qty + 1 } : l))
      return [...ls, { key: nextKey.current++, med: m, unit: u.unit, factor: u.factor, qty: 1, price: u.price, directions: "" }]
    })
    setSearch("")
    searchRef.current?.focus()
  }

  const setLine = (key: number, patch: Partial<Line>) => setLines((ls) => ls.map((l) => (l.key === key ? { ...l, ...patch } : l)))

  const pickUnit = (l: Line, unit: string) => {
    const u = sellUnits(l.med).find((x) => x.unit === unit)
    if (u) setLine(l.key, { unit: u.unit, factor: u.factor, price: u.price })
  }

  const clear = () => {
    setLines([]); setReceived(""); setCustomerId("walk-in"); setWalkInName("")
    setRx({ patientName: "", patientPhone: "", prescriberName: "", prescriberFacility: "", prescriptionRef: "", prescriptionDate: new Date().toISOString().slice(0, 10) })
  }

  const complete = async () => {
    if (lines.length === 0) { toast({ title: "Nothing to sell yet", variant: "destructive" }); return }
    if (lines.some((l) => !(l.qty > 0))) { toast({ title: "Every line needs a quantity", variant: "destructive" }); return }
    if (overStock.size > 0) { toast({ title: "Not enough stock that has not expired", description: "Lower the quantities shown in red.", variant: "destructive" }); return }
    const blocked = lines.find((l) => l.med.isMedicine && sellBlockReason(settings.shopType, l.med.medicineClass))
    if (blocked) { toast({ title: "Cannot sell this here", description: sellBlockReason(settings.shopType, blocked.med.medicineClass)!, variant: "destructive" }); return }
    if (rxRequired && (!rx.patientName.trim() || !rx.prescriberName.trim())) {
      toast({ title: "Prescription needed", description: "A Class A medicine is in the sale: enter the patient and the prescriber.", variant: "destructive" }); return
    }
    const credit = payMethod === "Credit"
    if (credit && customerId === "walk-in") { toast({ title: "Choose the customer", description: "A credit sale must be on a customer's account.", variant: "destructive" }); return }
    if (!credit && !cashAccountId) { toast({ title: "Choose where the money goes", description: "Pick a cash account.", variant: "destructive" }); return }
    if (payMethod === "Cash" && received && receivedNum < total) { toast({ title: "Amount received is less than the total", variant: "destructive" }); return }

    setCompleting(true)
    const now = new Date()
    const stamp = `${now.toISOString().slice(0, 10).replace(/-/g, "")}-${String(now.getHours()).padStart(2, "0")}${String(now.getMinutes()).padStart(2, "0")}${String(Math.floor(Math.random() * 10000)).padStart(4, "0")}`
    const receiptNumber = `RX-${stamp}`
    const cust = customerId !== "walk-in" ? customers.find((c) => String(c.genericCustomerId) === customerId) : undefined
    try {
      const items: GenericSaleItem[] = lines.map((l) => ({
        itemType: "Product",
        genericProductId: l.med.genericProductId,
        genericServiceId: null,
        description: `${l.med.productName}${l.unit !== l.med.baseUnit ? ` (${l.unit})` : ""}`,
        quantity: l.qty,
        unitPrice: l.price,
        discountAmount: 0,
        saleUnit: l.unit,
        unitFactor: l.factor,
        notes: l.directions || null,
      }))
      const sale = await createSale({
        saleDate: now.toISOString().slice(0, 10),
        genericCustomerId: cust ? cust.genericCustomerId : null,
        salesType: cust ? "CustomerSale" : "WalkInSale",
        salesChannel: "Pharmacy till",
        headerDiscountAmount: 0,
        taxAmount: 0,
        amountPaid: credit ? 0 : total,
        paymentMethod: payMethod,
        genericCashAccountId: credit ? null : Number(cashAccountId),
        receiptNumber,
        notes: !cust && walkInName.trim() ? `Walk-in: ${walkInName.trim()}` : null,
        items,
      })
      if (!sale) throw new Error("The sale was not created.")
      await approveSale(sale.genericSaleId)

      let prescriptionId: number | null = null
      if (needsRx && rx.patientName.trim() && rx.prescriberName.trim()) {
        try {
          const r = await createPrescription({
            genericSaleId: sale.genericSaleId,
            prescriptionDate: rx.prescriptionDate || null,
            patientName: rx.patientName, patientPhone: rx.patientPhone || null,
            prescriberName: rx.prescriberName, prescriberFacility: rx.prescriberFacility || null,
            prescriptionRef: rx.prescriptionRef || null,
            items: lines.filter((l) => l.med.medicineClass === "A").map((l) => ({
              genericProductId: l.med.genericProductId, medicineName: l.med.productName,
              quantity: l.qty * l.factor, unit: l.med.baseUnit, directions: l.directions || null,
            })),
          })
          prescriptionId = r?.genericPrescriptionId ?? null
        } catch (e: any) {
          toast({ title: "Sale done, but the prescription was not saved", description: e?.message, variant: "destructive" })
        }
      }

      setReceipt({
        saleId: sale.genericSaleId, receiptNumber, date: now.toLocaleString(),
        customer: cust?.customerName ?? (walkInName.trim() || "Walk-in"), paymentMethod: payMethod,
        lines: lines.map((l) => ({ name: l.med.productName, qty: l.qty, unit: l.unit, price: l.price, total: round2(l.qty * l.price), directions: l.directions || undefined })),
        total, received: payMethod === "Cash" ? (receivedNum || total) : credit ? 0 : total,
        change: payMethod === "Cash" && receivedNum > total ? change : 0, prescriptionId,
      })
      toast({ title: `Sale ${receiptNumber} completed` })
      clear()
      loadMeds().catch(() => {})
    } catch (e: any) {
      toast({ title: "Could not complete the sale", description: e?.message, variant: "destructive" })
    } finally { setCompleting(false) }
  }

  return (
    <PharmacyShell title="Pharmacy till" subtitle={settings.shopType === "ChemicalShop" ? "Chemical shop: over-the-counter (Class C) medicines only" : "Sell medicines by the tablet, strip or box"} wide>
      {loading ? (
        <div className="flex justify-center py-16"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[1.1fr_1fr]">
          {/* ---- Pick medicines ---- */}
          <Card>
            <CardContent className="space-y-3 p-3">
              <div className="relative">
                <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
                <Input ref={searchRef} autoFocus className="pl-8" placeholder="Search brand, generic name, barcode…" value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Enter" && results.length === 1) addMed(results[0]) }} />
              </div>
              {meds.length === 0 ? (
                <p className="py-8 text-center text-sm text-slate-500">
                  No products yet. Add them in <Link className="text-emerald-700 underline" href="/generic-products">Products &amp; Services</Link>,
                  then set them up in <Link className="text-emerald-700 underline" href="/generic-medicines">Medicines</Link>.
                </p>
              ) : (
                <div className="grid gap-2 sm:grid-cols-2 max-h-[65vh] overflow-y-auto pr-1">
                  {results.map((m) => {
                    const units = sellUnits(m)
                    const sellable = sellableStock(m)
                    const block = m.isMedicine ? sellBlockReason(settings.shopType, m.medicineClass) : null
                    const out = m.trackInventory && sellable <= 0
                    return (
                      <button key={m.genericProductId} onClick={() => addMed(m)} disabled={!!block}
                        className={`rounded-md border bg-white p-2.5 text-left transition hover:border-emerald-400 hover:bg-emerald-50 disabled:cursor-not-allowed disabled:opacity-50 ${out ? "border-rose-200" : ""}`}>
                        <div className="flex items-start justify-between gap-2">
                          <div className="font-medium leading-tight">{m.productName}</div>
                          {m.isMedicine && <ClassBadge cls={m.medicineClass} />}
                        </div>
                        <div className="text-xs text-slate-500">{[m.genericName, m.strength, m.dosageForm].filter(Boolean).join(" · ")}</div>
                        <div className="mt-1 text-xs">
                          {units.map((u) => <span key={u.unit} className="mr-2 whitespace-nowrap">{u.unit} <strong>{fmt(u.price)}</strong></span>)}
                        </div>
                        <div className={`mt-1 text-xs ${out ? "text-rose-600" : "text-slate-500"}`}>
                          {m.trackInventory ? (out ? "Out of stock" : `In stock: ${describeQty(sellable, units)}`) : "Not stock-tracked"}
                          {m.expiredQty > 0 && <span className="text-rose-600"> · {describeQty(m.expiredQty, units)} expired</span>}
                        </div>
                        {block && <div className="mt-1 text-[11px] text-amber-700">Pharmacy only</div>}
                      </button>
                    )
                  })}
                </div>
              )}
            </CardContent>
          </Card>

          {/* ---- Cart & payment ---- */}
          <div className="space-y-4">
            <Card>
              <CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><ShoppingCart className="h-4 w-4" /> Sale</CardTitle></CardHeader>
              <CardContent className="space-y-2 p-3 pt-0">
                {lines.length === 0 ? (
                  <p className="py-6 text-center text-sm text-slate-500">Tap a medicine to add it.</p>
                ) : lines.map((l) => {
                  const units = sellUnits(l.med)
                  const over = overStock.has(l.med.genericProductId)
                  return (
                    <div key={l.key} className={`rounded-md border p-2 ${over ? "border-rose-300 bg-rose-50" : ""}`}>
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <div className="font-medium leading-tight">{l.med.productName}</div>
                          {over && (
                            <div className="flex items-center gap-1 text-xs text-rose-600">
                              <AlertTriangle className="h-3 w-3" /> Only {describeQty(sellableStock(l.med), units)} can be sold
                            </div>
                          )}
                        </div>
                        <Button variant="ghost" size="sm" onClick={() => setLines((ls) => ls.filter((x) => x.key !== l.key))} title="Remove">
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      </div>
                      <div className="mt-1 grid grid-cols-[auto_1fr_1fr_auto] items-center gap-2">
                        <div className="flex items-center">
                          <Button variant="outline" size="sm" className="h-8 w-8 p-0" onClick={() => setLine(l.key, { qty: Math.max(1, l.qty - 1) })}><Minus className="h-3 w-3" /></Button>
                          <NumberInput className="h-8 w-14 text-center" min="0" step="1" value={l.qty} onChange={(e) => setLine(l.key, { qty: Number(e.target.value) || 0 })} />
                          <Button variant="outline" size="sm" className="h-8 w-8 p-0" onClick={() => setLine(l.key, { qty: l.qty + 1 })}><Plus className="h-3 w-3" /></Button>
                        </div>
                        <Select value={l.unit} onValueChange={(v) => pickUnit(l, v)}>
                          <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {units.map((u) => <SelectItem key={u.unit} value={u.unit}>{u.unit}{u.factor !== 1 ? ` (${u.factor} ${l.med.baseUnit})` : ""}</SelectItem>)}
                          </SelectContent>
                        </Select>
                        <NumberInput className="h-8 text-right" min="0" step="0.01" value={l.price} onChange={(e) => setLine(l.key, { price: Number(e.target.value) || 0 })} title="Price each" />
                        <div className="w-20 text-right font-medium">{fmt(l.qty * l.price)}</div>
                      </div>
                      {l.med.medicineClass === "A" && (
                        <Input className="mt-1 h-8 text-xs" placeholder="Directions, e.g. 1 tablet 3 times a day for 5 days" value={l.directions}
                          onChange={(e) => setLine(l.key, { directions: e.target.value })} />
                      )}
                    </div>
                  )
                })}
                <div className="flex items-center justify-between border-t pt-2 text-lg font-semibold">
                  <span>Total</span><span>{fmt(total)}</span>
                </div>
              </CardContent>
            </Card>

            {needsRx && (
              <Card className="border-rose-200">
                <CardHeader className="pb-2">
                  <CardTitle className="flex items-center gap-2 text-base"><ClipboardList className="h-4 w-4" /> Prescription {rxRequired ? "(required)" : "(optional)"}</CardTitle>
                  <p className="text-xs text-slate-500">A prescription-only (Class A) medicine is in this sale.</p>
                </CardHeader>
                <CardContent className="grid gap-2 p-3 pt-0 sm:grid-cols-2">
                  <div><Label className="text-xs">Patient name {rxRequired && "*"}</Label><Input value={rx.patientName} maxLength={200} onChange={(e) => setRx((r) => ({ ...r, patientName: e.target.value }))} /></div>
                  <div><Label className="text-xs">Patient phone</Label><Input value={rx.patientPhone} maxLength={40} onChange={(e) => setRx((r) => ({ ...r, patientPhone: e.target.value }))} /></div>
                  <div><Label className="text-xs">Prescriber (doctor) {rxRequired && "*"}</Label><Input value={rx.prescriberName} maxLength={200} onChange={(e) => setRx((r) => ({ ...r, prescriberName: e.target.value }))} /></div>
                  <div><Label className="text-xs">Hospital / clinic</Label><Input value={rx.prescriberFacility} maxLength={200} onChange={(e) => setRx((r) => ({ ...r, prescriberFacility: e.target.value }))} /></div>
                  <div><Label className="text-xs">Prescription no.</Label><Input value={rx.prescriptionRef} maxLength={80} onChange={(e) => setRx((r) => ({ ...r, prescriptionRef: e.target.value }))} /></div>
                  <div><Label className="text-xs">Prescription date</Label><Input type="date" value={rx.prescriptionDate} onChange={(e) => setRx((r) => ({ ...r, prescriptionDate: e.target.value }))} /></div>
                </CardContent>
              </Card>
            )}

            <Card>
              <CardContent className="grid gap-3 p-3 sm:grid-cols-2">
                <div>
                  <Label className="text-xs">Customer</Label>
                  <Select value={customerId} onValueChange={setCustomerId}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="walk-in">Walk-in</SelectItem>
                      {customers.filter((c) => c.isActive !== false).map((c) => <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>{c.customerName}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                {customerId === "walk-in" ? (
                  <div><Label className="text-xs">Name (optional)</Label><Input value={walkInName} maxLength={100} onChange={(e) => setWalkInName(e.target.value)} /></div>
                ) : <div />}
                <div>
                  <Label className="text-xs">Payment</Label>
                  <Select value={payMethod} onValueChange={setPayMethod}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{PAY_METHODS.map((p) => <SelectItem key={p} value={p}>{p === "Credit" ? "Credit (pay later)" : p === "MoMo" ? "Mobile money" : p}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                {payMethod !== "Credit" && (
                  <div>
                    <Label className="text-xs">Into</Label>
                    <Select value={cashAccountId} onValueChange={setCashAccountId}>
                      <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
                      <SelectContent>{cashAccounts.filter((a) => a.isActive).map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                )}
                {payMethod === "Cash" && (
                  <>
                    <div><Label className="text-xs">Amount received</Label><NumberInput min="0" step="0.01" value={received} placeholder={String(total)} onChange={(e) => setReceived(e.target.value)} /></div>
                    <div className="flex flex-col justify-end text-sm">
                      <span className="text-slate-500">Change</span>
                      <span className={`text-lg font-semibold ${change < 0 ? "text-rose-600" : ""}`}>{received ? fmt(Math.max(0, change)) : "—"}</span>
                    </div>
                  </>
                )}
                <div className="flex gap-2 sm:col-span-2">
                  <Button variant="outline" onClick={clear} disabled={completing || lines.length === 0}>Clear</Button>
                  <Button className="flex-1 bg-emerald-600 hover:bg-emerald-700" onClick={complete} disabled={completing || lines.length === 0}>
                    {completing && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Complete sale · {fmt(total)}
                  </Button>
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      )}

      <Dialog open={!!receipt} onOpenChange={(o) => { if (!o) setReceipt(null) }}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader><DialogTitle>Receipt {receipt?.receiptNumber}</DialogTitle></DialogHeader>
          {receipt && (
            <div id="pharmacy-receipt" className="space-y-2 text-sm">
              <div className="text-slate-500">{receipt.date} · {receipt.customer}</div>
              {receipt.lines.map((l, i) => (
                <div key={i}>
                  <div className="flex justify-between gap-2"><span>{l.qty} {l.unit} {l.name}</span><span>{fmt(l.total)}</span></div>
                  {l.directions && <div className="text-xs text-slate-500">{l.directions}</div>}
                </div>
              ))}
              <div className="flex justify-between border-t pt-2 font-semibold"><span>Total</span><span>{fmt(receipt.total)}</span></div>
              <div className="flex justify-between"><span>{receipt.paymentMethod === "Credit" ? "On account" : `Paid (${receipt.paymentMethod})`}</span><span>{fmt(receipt.received)}</span></div>
              {receipt.change > 0 && <div className="flex justify-between"><span>Change</span><span>{fmt(receipt.change)}</span></div>}
              {receipt.prescriptionId && <div className="text-xs text-slate-500">Prescription #{receipt.prescriptionId} recorded.</div>}
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => window.print()}><Printer className="h-4 w-4 mr-1" /> Print</Button>
            <Button onClick={() => setReceipt(null)}>Next sale</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </PharmacyShell>
  )
}

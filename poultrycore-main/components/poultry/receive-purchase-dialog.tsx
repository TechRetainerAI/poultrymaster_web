"use client"

// Receive Purchase (migration 345): one supplier invoice -- several items,
// additional costs, and whatever was paid on the spot -- received in ONE save.
//
// The form shows the posting BEFORE it saves (lib/poultry/purchase-receipt.ts
// mirrors the database's arithmetic), so the person receiving the goods sees
// what will reach stock, cash, the supplier's balance and the P&L. The server
// redoes all of it; nothing here is trusted.
//
// Each line's cost-recognition method is the ITEM's (Setup > Financial Settings
// or the item's own override). It is shown, never chosen here: the method is
// decided before a purchase exists, never per purchase (deferred-inventory-costs).

import { useEffect, useMemo, useRef, useState } from "react"
import { AlertTriangle, Loader2, Plus, Trash2, PackageCheck } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { SuggestInput } from "@/components/ui/suggest-input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import type { PoultryRawMaterialItem } from "@/lib/api/poultry-inventory"
import type { PoultryCashAccount } from "@/lib/api/poultry-finance"
import type { Supplier } from "@/lib/api/supplier"
import {
  newClientRequestId, receivePurchase, type PurchaseReceipt,
} from "@/lib/api/poultry-purchase-receipts"
import { previewReceipt, validateReceipt, type ReceiptLineDraft } from "@/lib/poultry/purchase-receipt"
import { EXPENSE_WHEN_CONSUMED } from "@/lib/poultry/cost-recognition"

const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Card"]

type PayMode = "full" | "part" | "credit"

interface LineState {
  key: number
  itemId: number
  quantity: number
  unitCost: number
  unitsPerPurchaseUnit: number
  notes: string
}

const blankLine = (key: number): LineState =>
  ({ key, itemId: 0, quantity: 0, unitCost: 0, unitsPerPurchaseUnit: 1, notes: "" })

export interface ReceivePurchaseDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  items: PoultryRawMaterialItem[]
  suppliers: Supplier[]
  cashAccounts: PoultryCashAccount[]
  /** The company's business date, yyyy-mm-dd. */
  today: string
  /** Whether this user may pay on receipt (supplier-payments.create). */
  canPay: boolean
  onReceived?: (receipt: PurchaseReceipt) => void | Promise<void>
}

export function ReceivePurchaseDialog({
  open, onOpenChange, items, suppliers, cashAccounts, today, canPay, onReceived,
}: ReceivePurchaseDialogProps) {
  const { toast } = useToast()
  const gh = useFmt()

  const [supplierText, setSupplierText] = useState("")
  const [purchaseDate, setPurchaseDate] = useState(today)
  const [referenceNo, setReferenceNo] = useState("")
  const [notes, setNotes] = useState("")
  const [lines, setLines] = useState<LineState[]>([blankLine(1)])
  const [additional, setAdditional] = useState(0)
  const [additionalNote, setAdditionalNote] = useState("")
  const [payMode, setPayMode] = useState<PayMode>("full")
  const [partAmount, setPartAmount] = useState(0)
  const [paymentMethod, setPaymentMethod] = useState("Cash")
  const [cashAccountId, setCashAccountId] = useState<number>(0)
  const [dueDate, setDueDate] = useState("")
  const [showErrors, setShowErrors] = useState(false)
  const [saving, setSaving] = useState(false)
  const savingRef = useRef(false)
  // One idempotency key per opened form: a double-clicked or retried Save
  // returns the receipt the first one made instead of receiving it twice.
  const requestIdRef = useRef<string>("")
  const nextKey = useRef(2)

  const itemById = useMemo(() => new Map(items.map((i) => [i.poultryRawMaterialItemId, i])), [items])
  const activeItems = useMemo(() => items.filter((i) => i.isActive), [items])

  useEffect(() => {
    if (!open) return
    requestIdRef.current = newClientRequestId()
    nextKey.current = 2
    setSupplierText(""); setPurchaseDate(today); setReferenceNo(""); setNotes("")
    setLines([blankLine(1)]); setAdditional(0); setAdditionalNote("")
    setPayMode(canPay ? "full" : "credit"); setPartAmount(0); setPaymentMethod("Cash")
    setCashAccountId(cashAccounts.find((a) => a.isActive)?.poultryCashAccountId ?? 0)
    setDueDate(""); setShowErrors(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const matchedSupplier = useMemo(() => {
    const t = supplierText.trim().toLowerCase()
    return t ? suppliers.find((s) => s.name.trim().toLowerCase() === t) ?? null : null
  }, [supplierText, suppliers])

  const drafts: ReceiptLineDraft[] = lines.map((l) => ({
    itemId: l.itemId || null,
    quantity: l.quantity,
    unitCost: l.unitCost,
    unitsPerPurchaseUnit: l.unitsPerPurchaseUnit || 1,
    method: itemById.get(l.itemId)?.effectiveCostRecognitionMethod ?? null,
  }))
  const totalOnly = previewReceipt(drafts, additional, 0).total
  const amountPaid = payMode === "full" ? totalOnly : payMode === "part" ? partAmount : 0
  const preview = previewReceipt(drafts, additional, amountPaid)

  const errors = validateReceipt({
    supplierChosen: supplierText.trim().length > 0,
    purchaseDate, today, dueDate: dueDate || null,
    lines: drafts, additionalCosts: additional, amountPaid,
    cashAccountId: cashAccountId || null,
  })
  if (payMode === "part" && (partAmount <= 0 || partAmount >= totalOnly) && totalOnly > 0) {
    errors.push("A part payment must be more than 0 and less than the total. Use Paid in full or On credit otherwise.")
  }

  const setLine = (key: number, patch: Partial<LineState>) =>
    setLines((ls) => ls.map((l) => (l.key === key ? { ...l, ...patch } : l)))

  async function save() {
    if (savingRef.current) return
    if (errors.length > 0) { setShowErrors(true); return }
    savingRef.current = true
    setSaving(true)
    try {
      const receipt = await receivePurchase({
        supplierId: matchedSupplier?.supplierId ?? null,
        supplierName: matchedSupplier ? null : supplierText.trim(),
        purchaseDate,
        referenceNo: referenceNo.trim() || null,
        dueDate: preview.balance > 0 && dueDate ? dueDate : null,
        notes: notes.trim() || null,
        additionalCosts: additional,
        additionalCostsNote: additional > 0 ? additionalNote.trim() || null : null,
        amountPaid,
        paymentMethod: amountPaid > 0 ? paymentMethod : null,
        cashAccountId: amountPaid > 0 ? cashAccountId : null,
        clientRequestId: requestIdRef.current,
        lines: lines.map((l) => {
          const it = itemById.get(l.itemId)
          return {
            poultryRawMaterialItemId: l.itemId,
            quantity: l.quantity,
            unitCost: l.unitCost,
            productionUnit: it?.unitOfMeasure ?? null,
            productionUnitsPerPurchaseUnit: l.unitsPerPurchaseUnit && l.unitsPerPurchaseUnit !== 1 ? l.unitsPerPurchaseUnit : null,
            notes: l.notes.trim() || null,
          }
        }),
      })
      toast({
        title: `Received as ${receipt.receiptNumber}`,
        description: `${receipt.lineCount} item${receipt.lineCount === 1 ? "" : "s"} · ${gh(receipt.totalCost)} · ${receipt.paymentStatus}`,
      })
      onOpenChange(false)
      await onReceived?.(receipt)
    } catch (e: any) {
      toast({ title: "Could not receive the purchase", description: e?.message, variant: "destructive" })
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  const deferredAny = preview.lines.some((l) => l.deferred)
  const account = cashAccounts.find((a) => a.poultryCashAccountId === cashAccountId)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] max-w-[1100px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><PackageCheck className="h-5 w-5 text-emerald-600" /> Receive purchase</DialogTitle>
          <DialogDescription>
            One supplier invoice: the stock, what you owe and anything you paid now are recorded together.
          </DialogDescription>
        </DialogHeader>

        <FormSection title="Supplier & Invoice" color="indigo">
          <FormField label="Supplier *" full hint={supplierText.trim() && !matchedSupplier ? "New supplier — it will be added to your suppliers." : undefined}>
            <SuggestInput value={supplierText} onChange={setSupplierText} suggestions={suppliers.map((s) => s.name)} placeholder="Pick or type a supplier" />
          </FormField>
          <FormField label="Purchase date *"><Input type="date" max={today} value={purchaseDate} onChange={(e) => setPurchaseDate(e.target.value)} /></FormField>
          <FormField label="Invoice / reference" hint="The same invoice can't be received twice from one supplier.">
            <Input value={referenceNo} onChange={(e) => setReferenceNo(e.target.value)} placeholder="e.g. INV-2041" />
          </FormField>
        </FormSection>

        <FormSection title="Items received" color="blue" columns={1}>
          <div className="space-y-3">
            {lines.map((l, idx) => {
              const it = itemById.get(l.itemId)
              const p = preview.lines[idx]
              const deferred = it?.effectiveCostRecognitionMethod === EXPENSE_WHEN_CONSUMED
              return (
                <div key={l.key} className="rounded-lg border border-slate-200 bg-white p-3 space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">Item {idx + 1}</span>
                    <div className="flex items-center gap-2">
                      {it && (
                        <Badge variant="outline" className={cn(deferred ? "border-violet-300 text-violet-800 bg-violet-50" : "border-amber-300 text-amber-800 bg-amber-50")}>
                          {deferred ? "Expensed when used" : "Expensed as paid"}
                        </Badge>
                      )}
                      {lines.length > 1 && (
                        <Button type="button" size="sm" variant="ghost" className="h-8 w-8 p-0 text-rose-600" title="Remove item"
                          onClick={() => setLines((ls) => ls.filter((x) => x.key !== l.key))}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      )}
                    </div>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-12 gap-2">
                    <div className="sm:col-span-4">
                      <label className="text-xs text-slate-500">Item *</label>
                      <Select value={l.itemId ? String(l.itemId) : ""} onValueChange={(v) => setLine(l.key, { itemId: Number(v) })}>
                        <SelectTrigger><SelectValue placeholder="Pick item" /></SelectTrigger>
                        <SelectContent>
                          {activeItems.map((i) => (
                            <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>
                              {i.itemName}{i.unitOfMeasure ? ` (${i.unitOfMeasure})` : ""}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="sm:col-span-2">
                      <label className="text-xs text-slate-500">Quantity{it?.purchaseUnitOfMeasure ? ` (${it.purchaseUnitOfMeasure})` : ""} *</label>
                      <NumberInput min={0} step="0.001" value={l.quantity} onChange={(e) => setLine(l.key, { quantity: Number(e.target.value) || 0 })} />
                    </div>
                    <div className="sm:col-span-2">
                      <label className="text-xs text-slate-500">Unit cost *</label>
                      <NumberInput min={0} step="0.01" value={l.unitCost} onChange={(e) => setLine(l.key, { unitCost: Number(e.target.value) || 0 })} />
                    </div>
                    <div className="sm:col-span-2">
                      <label className="text-xs text-slate-500">{it?.unitOfMeasure ? `${it.unitOfMeasure} per unit` : "Units per purchase unit"}</label>
                      <NumberInput min={0} step="0.0001" value={l.unitsPerPurchaseUnit} onChange={(e) => setLine(l.key, { unitsPerPurchaseUnit: Number(e.target.value) || 0 })} />
                    </div>
                    <div className="sm:col-span-2 text-right">
                      <label className="text-xs text-slate-500">Line total</label>
                      <div className="h-10 flex items-center justify-end font-semibold tabular-nums">{gh(p?.total ?? 0)}</div>
                    </div>
                  </div>
                  {p && (p.allocatedAdditional > 0 || (l.unitsPerPurchaseUnit && l.unitsPerPurchaseUnit !== 1)) && (
                    <div className="text-xs text-slate-500">
                      {p.allocatedAdditional > 0 && <>Includes {gh(p.allocatedAdditional)} of additional costs · landed {gh(p.landedUnitCost)} per unit. </>}
                      {l.unitsPerPurchaseUnit && l.unitsPerPurchaseUnit !== 1 ? <>Adds {p.productionQuantity.toLocaleString()} {it?.unitOfMeasure ?? "units"} to stock.</> : null}
                    </div>
                  )}
                </div>
              )
            })}
            <Button type="button" variant="outline" size="sm" onClick={() => setLines((ls) => [...ls, blankLine(nextKey.current++)])} disabled={lines.length >= 50}>
              <Plus className="h-4 w-4 mr-1" /> Add item
            </Button>
          </div>
        </FormSection>

        <FormSection title="Additional costs" color="slate">
          <FormField label="Amount" hint="Transport, offloading … spread over the items by value, so it becomes part of their stock cost.">
            <NumberInput min={0} step="0.01" value={additional} onChange={(e) => setAdditional(Number(e.target.value) || 0)} />
          </FormField>
          <FormField label="What it was for"><Input value={additionalNote} onChange={(e) => setAdditionalNote(e.target.value)} placeholder="e.g. Transport" disabled={additional <= 0} /></FormField>
        </FormSection>

        <FormSection title="Payment" color="amber">
          <FormField label="Payment status *" full>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
              {([
                ["full", "Paid in full", "Cash leaves now; nothing owed."],
                ["part", "Part payment", "Pay some now; the rest is owed."],
                ["credit", "On credit", "Nothing paid; all of it is owed."],
              ] as [PayMode, string, string][]).map(([m, label, hint]) => {
                const disabled = m !== "credit" && !canPay
                return (
                  <button key={m} type="button" disabled={disabled} onClick={() => setPayMode(m)}
                    className={cn("rounded-lg border p-3 text-left transition",
                      payMode === m ? "border-emerald-500 bg-emerald-50 ring-1 ring-emerald-500" : "border-slate-200 bg-white hover:bg-slate-50",
                      disabled && "opacity-50 cursor-not-allowed")}>
                    <div className="text-sm font-medium text-slate-800">{label}</div>
                    <div className="text-xs text-slate-500">{disabled ? "You can't record supplier payments." : hint}</div>
                  </button>
                )
              })}
            </div>
          </FormField>
          {payMode === "part" && (
            <FormField label="Amount paid now *"><NumberInput min={0} step="0.01" value={partAmount} onChange={(e) => setPartAmount(Number(e.target.value) || 0)} /></FormField>
          )}
          {payMode !== "credit" && (
            <>
              <FormField label="Paid from *">
                <Select value={cashAccountId ? String(cashAccountId) : ""} onValueChange={(v) => setCashAccountId(Number(v))}>
                  <SelectTrigger><SelectValue placeholder="Pick cash account" /></SelectTrigger>
                  <SelectContent>
                    {cashAccounts.filter((a) => a.isActive).map((a) => (
                      <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                        {a.accountName} ({gh(a.currentBalance)})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Method">
                <Select value={paymentMethod} onValueChange={setPaymentMethod}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </>
          )}
          {preview.balance > 0 && (
            <FormField label="Due date" hint="Empty = the supplier's payment terms.">
              <Input type="date" min={purchaseDate} value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
            </FormField>
          )}
        </FormSection>

        <FormSection title="Notes" color="slate" columns={1}>
          <FormField label="Notes"><Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" /></FormField>
        </FormSection>

        {/* --------------------------------------------- what will be posted */}
        <section className="rounded-lg border border-slate-200 bg-slate-50 p-3 space-y-2">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">What this will record</div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <Figure label="Stock value in" value={gh(preview.inventoryIncrease)} />
            <Figure label={`Cash out${account && preview.cashOut > 0 ? ` · ${account.accountName}` : ""}`} value={gh(preview.cashOut)} />
            <Figure label="Owed to supplier" value={gh(preview.payableIncrease)} tone={preview.payableIncrease > 0 ? "text-amber-700" : undefined} />
            <Figure label="Expense today" value={gh(preview.expenseNow)} />
          </div>
          <ul className="text-xs text-slate-600 list-disc pl-5 space-y-0.5">
            {preview.expenseNow > 0 && <li>{gh(preview.expenseNow)} reaches Profit &amp; Loss today — items expensed as they are paid.</li>}
            {preview.expenseWhenBalancePaid > 0 && <li>{gh(preview.expenseWhenBalancePaid)} more will be expensed as the balance is paid.</li>}
            {deferredAny && <li>{gh(preview.deferredToConsumption)} is held as stock and reaches Profit &amp; Loss only when it is used (Awaiting P&amp;L until then).</li>}
            {account && preview.cashOut > 0 && account.currentBalance < preview.cashOut && !account.allowNegativeBalance && (
              <li className="text-rose-700">{account.accountName} only holds {gh(account.currentBalance)}; this payment would overdraw it.</li>
            )}
          </ul>
        </section>

        {showErrors && errors.length > 0 && (
          <div className="rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800 space-y-1">
            {errors.map((e) => <div key={e} className="flex gap-2"><AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />{e}</div>)}
          </div>
        )}

        <div className="flex flex-col-reverse sm:flex-row sm:items-center sm:justify-between gap-2">
          <div className="text-sm text-slate-600">
            Total <span className="font-semibold tabular-nums text-slate-900">{gh(preview.total)}</span>
            {preview.additionalCosts > 0 && <> (incl. {gh(preview.additionalCosts)} additional)</>}
          </div>
          <div className="flex gap-2 justify-end">
            <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={() => void save()} disabled={saving}>
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Receive purchase"}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function Figure({ label, value, tone }: { label: string; value: string; tone?: string }) {
  return (
    <div className="rounded-md border border-slate-200 bg-white p-2.5">
      <div className="text-[11px] leading-tight text-slate-500">{label}</div>
      <div className={cn("text-base font-semibold tabular-nums leading-snug", tone)}>{value}</div>
    </div>
  )
}

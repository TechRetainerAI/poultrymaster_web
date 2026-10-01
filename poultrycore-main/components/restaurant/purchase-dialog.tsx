"use client"

// The Restaurant "Record Purchase" form (migration 329), copied from Poultry's
// components/raw-materials/poultry-purchase-dialog.tsx: same sections, same
// labels, same payment rules. What differs is the domain -- an ingredient or
// supply (food, drinks, packaging, tableware, cleaning) instead of a raw
// material, and no production-unit conversion, because the restaurant counts
// stock in the unit it buys in.
//
// Saving records the purchase in ONE database call: the stock is added as a
// FIFO lot, the ingredient's cost per unit is refreshed, only the amount paid
// now leaves the chosen cash account, and any balance is owed to the supplier
// (it appears on Supplier Balances). The caller owns open/close and supplies
// the ingredients, suppliers and accounts it has already loaded.

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import type { Ingredient } from "@/lib/api/restaurant"
import type { CashAccount } from "@/lib/api/restaurant-finance"
import {
  createPurchase, COST_MODE_LABELS,
  type RestaurantSupplierRow, type RestaurantCostModeRow,
} from "@/lib/api/restaurant-suppliers"

const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Credit"]
const roCls = "bg-slate-100 text-slate-600 font-medium pointer-events-none cursor-default border-dashed"
const today = () => new Date().toISOString().split("T")[0]

export interface RestaurantPurchaseDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  ingredients: Ingredient[]
  suppliers: RestaurantSupplierRow[]
  cashAccounts: CashAccount[]
  costModes: RestaurantCostModeRow[]
  /** Seeds a NEW purchase, e.g. from ?purchase=1&itemId=&qty= or a low-stock row. */
  defaults?: { itemId?: number | null; quantity?: number | null }
  onSaved?: () => void | Promise<void>
}

export function RestaurantPurchaseDialog({
  open, onOpenChange, ingredients, suppliers, cashAccounts, costModes, defaults, onSaved,
}: RestaurantPurchaseDialogProps) {
  const { toast } = useToast()
  const gh = useFmt()
  const blank = () => ({
    ingredientId: defaults?.itemId ?? 0,
    supplierId: 0,
    purchaseDate: today(),
    paymentMethod: "Cash",
    quantity: defaults?.quantity ?? 0,
    totalCost: 0,
    amountPaid: 0,
    cashAccountId: 0,
    dueDate: "",
    notes: "",
  })
  const [f, setF] = useState(blank)
  // Until the user types an amount, "Amount paid" follows the total (nothing,
  // on Credit) -- Poultry's rule.
  const [paidTouched, setPaidTouched] = useState(false)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open) return
    const b = blank()
    const cash = cashAccounts.find((a) => a.isActive && a.defaultFor === "Cash") ?? cashAccounts.find((a) => a.isActive)
    setF({ ...b, cashAccountId: cash?.cashAccountId ?? 0 })
    setPaidTouched(false)
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  const item = useMemo(() => ingredients.find((i) => i.ingredientId === f.ingredientId), [ingredients, f.ingredientId])
  const total = Number(f.totalCost) || 0
  const qty = Number(f.quantity) || 0
  const unitCost = qty > 0 ? total / qty : 0
  const credit = f.paymentMethod === "Credit"
  const paid = paidTouched ? (Number(f.amountPaid) || 0) : (credit ? 0 : total)
  const balance = Math.max(0, total - paid)
  const mode = costModes.find((m) => m.category.toLowerCase() === (item?.category ?? "").toLowerCase())?.costMode
    ?? "EXPENSE_WHEN_PURCHASED"

  const save = async () => {
    if (!f.ingredientId) { toast({ title: "Pick an ingredient or supply", variant: "destructive" }); return }
    if (qty <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    if (paid > total) { toast({ title: "Amount paid cannot be more than the total cost", variant: "destructive" }); return }
    if (balance > 0 && !f.supplierId) {
      toast({ title: "Choose the supplier", description: "Part of this purchase is still owed; Supplier Balances needs to know to whom.", variant: "destructive" })
      return
    }
    if (paid > 0 && !f.cashAccountId) { toast({ title: "Choose the cash account this was paid from", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createPurchase({
        ingredientId: f.ingredientId,
        quantity: qty,
        totalCost: total,
        purchaseDate: f.purchaseDate || null,
        supplierId: f.supplierId || null,
        paymentMethod: f.paymentMethod,
        amountPaid: paid,
        cashAccountId: paid > 0 ? (f.cashAccountId || null) : null,
        dueDate: balance > 0 && f.dueDate ? f.dueDate : null,
        notes: f.notes || null,
      })
      toast({ title: "Purchase recorded" })
      onOpenChange(false)
      await onSaved?.()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const unitLabel = item?.unit || "unit"

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>New purchase</DialogTitle></DialogHeader>

        <FormSection title="Item, Supplier & Date" color="indigo">
          <FormField label="Ingredient or supply *" full>
            <Select value={f.ingredientId ? String(f.ingredientId) : ""} onValueChange={(v) => setF({ ...f, ingredientId: Number(v) })}>
              <SelectTrigger><SelectValue placeholder="Pick item" /></SelectTrigger>
              <SelectContent>
                {ingredients.filter((i) => i.isActive !== false).map((i) => (
                  <SelectItem key={i.ingredientId} value={String(i.ingredientId)}>
                    {i.name}{i.unit ? ` (${i.unit})` : ""}{i.category ? ` · ${i.category}` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Supplier" full>
            <Select value={f.supplierId ? String(f.supplierId) : "none"} onValueChange={(v) => setF({ ...f, supplierId: v === "none" ? 0 : Number(v) })}>
              <SelectTrigger><SelectValue placeholder="Supplier name" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">Not linked to a supplier</SelectItem>
                {suppliers.filter((s) => s.isactive !== false).map((s) => (
                  <SelectItem key={s.restaurantsupplierid} value={String(s.restaurantsupplierid)}>
                    {s.name}{s.category ? ` (${s.category})` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Purchase date"><Input type="date" max={today()} value={f.purchaseDate} onChange={(e) => setF({ ...f, purchaseDate: e.target.value })} /></FormField>
          <FormField label="Payment method">
            <Select value={f.paymentMethod} onValueChange={(v) => setF({ ...f, paymentMethod: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
            </Select>
          </FormField>
        </FormSection>

        <FormSection title="Purchase Quantity & Costing" color="blue">
          <FormField label={`Purchase quantity (${unitLabel}) *`}>
            <NumberInput min={0} step="0.001" value={f.quantity} onChange={(e) => setF({ ...f, quantity: Number(e.target.value) || 0 })} />
          </FormField>
          <FormField label="Total purchase cost *">
            <NumberInput min={0} step="0.01" value={f.totalCost} onChange={(e) => setF({ ...f, totalCost: Number(e.target.value) || 0 })} />
          </FormField>
          <FormField label="Purchase unit cost (auto)">
            <Input readOnly tabIndex={-1} className={roCls} value={`${gh(unitCost)} per ${unitLabel}`} />
          </FormField>
          <FormField label="Cost recognition">
            <Input readOnly tabIndex={-1} className={roCls} value={item ? COST_MODE_LABELS[mode] : "—"} />
          </FormField>
          <FormField label="" full>
            <p className="text-xs text-slate-500">
              {mode === "EXPENSE_WHEN_CONSUMED"
                ? `${item?.category ?? "This category"} is expensed when consumed: the cost is held as stock value and reaches Profit & Loss as the stock is sold, wasted or adjusted out.`
                : "Expensed when purchased: the whole cost reaches Profit & Loss on the purchase date, and using the stock adds no second expense."}
            </p>
          </FormField>
        </FormSection>

        <FormSection title="Payment" color="amber">
          <FormField label="Amount paid">
            <NumberInput min={0} step="0.01" value={paid} onChange={(e) => { setPaidTouched(true); setF({ ...f, amountPaid: Number(e.target.value) || 0 }) }} />
          </FormField>
          <FormField label="Pay from cash account">
            <Select value={f.cashAccountId ? String(f.cashAccountId) : ""} onValueChange={(v) => setF({ ...f, cashAccountId: Number(v) })} disabled={paid <= 0}>
              <SelectTrigger><SelectValue placeholder={paid <= 0 ? "None (no cash movement)" : "Choose an account"} /></SelectTrigger>
              <SelectContent>
                {cashAccounts.filter((a) => a.isActive).map((a) => (
                  <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>
                    {a.name} ({gh(a.currentBalance)})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Balance (auto)"><Input readOnly tabIndex={-1} className={roCls} value={gh(balance)} /></FormField>
          <FormField label="Due date">
            <Input type="date" value={f.dueDate} disabled={balance <= 0} onChange={(e) => setF({ ...f, dueDate: e.target.value })} />
          </FormField>
          <FormField label="" full>
            <p className="text-xs text-slate-500">
              The cash account is charged only for the amount paid now. Any balance is owed to the supplier and appears on Supplier Balances.
            </p>
          </FormField>
        </FormSection>

        <FormSection title="Notes" color="slate" columns={1}>
          <FormField label="Notes"><Textarea rows={3} placeholder="Optional notes about this purchase" value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} /></FormField>
        </FormSection>

        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => void save()} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

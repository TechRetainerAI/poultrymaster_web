"use client"

// The "Record purchase" form, lifted out of /poultry-raw-materials so Feed
// Production can raise the same dialog without navigating away from a
// half-finished batch. One copy, one behaviour: whichever page opens it, the
// purchase, its stock lot and its cash-out are recorded identically.
//
// The caller owns open/close and supplies the items and cash accounts it has
// already loaded; the form state, the manual-cost back-solving and the save all
// live here.

import { useEffect, useMemo, useRef, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2 } from "lucide-react"
import { RAW_MATERIAL_UNITS as UNITS } from "@/lib/units"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  createPoultryRawMaterialPurchase, updatePoultryRawMaterialPurchase,
  type PoultryRawMaterialItem, type PoultryRawMaterialPurchase,
} from "@/lib/api/poultry-inventory"
import type { PoultryCashAccount } from "@/lib/api/poultry-finance"

const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Credit"]
const roCls = "bg-slate-100 text-slate-600 font-medium pointer-events-none cursor-default border-dashed"

const EMPTY_PURCHASE = {
  poultryRawMaterialItemId: 0,
  supplierName: "",
  purchaseDate: new Date().toISOString().split("T")[0],
  quantity: 0,
  unitCost: 0,
  totalPurchaseCost: 0,
  purchaseUnit: "",
  productionUnit: "",
  productionUnitsPerPurchaseUnit: 1,
  paymentMethod: "Cash",
  poultryCashAccountId: 0,
  amountPaid: 0,
  receiptUrl: "",
  notes: "",
}
export type PoultryPurchaseForm = typeof EMPTY_PURCHASE

export interface PoultryPurchaseDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  items: PoultryRawMaterialItem[]
  cashAccounts: PoultryCashAccount[]
  /** Editing an existing purchase; omit or null for a new one. */
  editing?: PoultryRawMaterialPurchase | null
  /** Seeds a NEW purchase — e.g. the ingredient and quantity a batch is short of. */
  defaults?: { itemId?: number | null; quantity?: number | null }
  /** Cash account preselected on a new purchase. */
  defaultCashAccountId?: number | null
  /** Fired after a successful save, with the item that was bought. */
  onSaved?: (info: { itemId: number; quantity: number }) => void | Promise<void>
}

export function PoultryPurchaseDialog({
  open, onOpenChange, items, cashAccounts, editing, defaults, defaultCashAccountId, onSaved,
}: PoultryPurchaseDialogProps) {
  const { toast } = useToast()
  const gh = useFmt()

  const [f, setF] = useState<PoultryPurchaseForm>({ ...EMPTY_PURCHASE })
  // When ON, the user enters the production-level unit cost directly instead of
  // it auto-calculating from the purchase total ÷ production quantity. We store
  // it by back-solving the units-per-purchase-unit factor, so it persists with
  // no schema change.
  const [manualProdCost, setManualProdCost] = useState(false)
  // Same idea for the purchase unit cost: when ON, type the unit cost and we
  // back-solve the total (total = unitCost × quantity) so it persists.
  const [manualPurchaseCost, setManualPurchaseCost] = useState(false)
  const [saving, setSaving] = useState(false)
  const savingRef = useRef(false) // synchronous re-entry guard against double/triple submits

  const itemById = useMemo(() => new Map(items.map((i) => [i.poultryRawMaterialItemId, i])), [items])

  // Build the form each time the dialog opens, so a reopen never inherits the
  // last one's figures. Deliberately keyed on `open` alone — retyped values
  // must survive the items/accounts arrays refreshing underneath.
  useEffect(() => {
    if (!open) return
    setManualProdCost(false); setManualPurchaseCost(false)
    if (editing) {
      setF({
        poultryRawMaterialItemId: editing.poultryRawMaterialItemId,
        supplierName: editing.supplierName ?? "",
        purchaseDate: (editing.purchaseDate || "").split("T")[0] || new Date().toISOString().split("T")[0],
        quantity: editing.quantity, unitCost: editing.unitCost, totalPurchaseCost: editing.totalCost,
        purchaseUnit: editing.unitOfMeasure ?? "", productionUnit: editing.productionUnit ?? "",
        productionUnitsPerPurchaseUnit: editing.productionUnitsPerPurchaseUnit ?? 1,
        paymentMethod: editing.paymentMethod ?? "Cash",
        poultryCashAccountId: editing.poultryCashAccountId ?? 0,
        amountPaid: editing.amountPaid, receiptUrl: editing.receiptUrl ?? "", notes: editing.notes ?? "",
      })
      return
    }
    const seed = defaults?.itemId ? itemById.get(defaults.itemId) : undefined
    setF({
      ...EMPTY_PURCHASE,
      poultryCashAccountId: defaultCashAccountId ?? 0,
      poultryRawMaterialItemId: seed?.poultryRawMaterialItemId ?? 0,
      purchaseUnit: seed?.purchaseUnitOfMeasure || seed?.unitOfMeasure || "",
      productionUnit: seed?.unitOfMeasure || "",
      quantity: defaults?.quantity && defaults.quantity > 0 ? defaults.quantity : 0,
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const unitOptions = (current?: string | null) => {
    const set = [...UNITS]; const c = (current ?? "").trim()
    if (c && !set.includes(c)) set.unshift(c)
    return set
  }

  async function save() {
    if (savingRef.current) return // already submitting — ignore extra clicks (slow network)
    if (!f.poultryRawMaterialItemId) { toast({ title: "Pick a raw material item", variant: "destructive" }); return }
    if (f.quantity <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    const total = f.totalPurchaseCost > 0 ? f.totalPurchaseCost : f.quantity * f.unitCost
    const payload = {
      poultryRawMaterialItemId: f.poultryRawMaterialItemId,
      supplierName: f.supplierName || null,
      purchaseDate: f.purchaseDate,
      quantity: f.quantity,
      unitCost: f.quantity > 0 ? Number((total / f.quantity).toFixed(4)) : f.unitCost,
      totalCost: total,
      productionUnit: f.productionUnit || null,
      productionUnitsPerPurchaseUnit: f.productionUnitsPerPurchaseUnit || null,
      paymentMethod: f.paymentMethod,
      poultryCashAccountId: f.poultryCashAccountId ? f.poultryCashAccountId : null,
      amountPaid: f.amountPaid,
      receiptUrl: f.receiptUrl || null,
      notes: f.notes || null,
    }
    savingRef.current = true
    setSaving(true)
    try {
      if (editing) await updatePoultryRawMaterialPurchase(editing.poultryRawMaterialPurchaseId, payload)
      else await createPoultryRawMaterialPurchase(payload)
      toast({ title: editing ? "Purchase updated" : "Purchase recorded" })
      onOpenChange(false)
      await onSaved?.({ itemId: f.poultryRawMaterialItemId, quantity: f.quantity })
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally {
      savingRef.current = false; setSaving(false)
    }
  }

  const qty = f.quantity || 0
  const total = f.totalPurchaseCost || 0
  const unitCost = qty > 0 ? total / qty : 0
  const perPurchase = f.productionUnitsPerPurchaseUnit || 0
  const prodQty = qty * perPurchase
  const prodUnitCost = prodQty > 0 ? total / prodQty : 0
  const selItem = itemById.get(f.poultryRawMaterialItemId)
  // Purchase unit is an editable per-entry label (mirrors the water side);
  // it defaults to the item's unit of measure. Display-only (drives the
  // quantity/cost labels) — not persisted, so no schema impact.
  const purchaseUnitLabel = f.purchaseUnit || selItem?.unitOfMeasure || "unit"

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] max-w-[1100px] max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>{editing ? "Edit purchase" : "New raw material purchase"}</DialogTitle></DialogHeader>

        <FormSection title="Item, Supplier & Date" color="indigo">
          <FormField label="Raw material item *" full>
            <Select value={f.poultryRawMaterialItemId ? String(f.poultryRawMaterialItemId) : ""} onValueChange={(v) => { const id = Number(v); const it = itemById.get(id); setF({ ...f, poultryRawMaterialItemId: id, purchaseUnit: it?.purchaseUnitOfMeasure || it?.unitOfMeasure || f.purchaseUnit, productionUnit: it?.unitOfMeasure || f.productionUnit }) }}>
              <SelectTrigger><SelectValue placeholder="Pick item" /></SelectTrigger>
              <SelectContent>{items.filter((i) => i.isActive).map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}{i.unitOfMeasure ? ` (${i.unitOfMeasure})` : ""}</SelectItem>)}</SelectContent>
            </Select>
          </FormField>
          <FormField label="Supplier" full><Input value={f.supplierName} onChange={(e) => setF({ ...f, supplierName: e.target.value })} placeholder="Supplier name" /></FormField>
          <FormField label="Purchase date"><Input type="date" value={f.purchaseDate} onChange={(e) => setF({ ...f, purchaseDate: e.target.value })} /></FormField>
          <FormField label="Payment method">
            <Select value={f.paymentMethod} onValueChange={(v) => setF({ ...f, paymentMethod: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
            </Select>
          </FormField>
        </FormSection>

        <FormSection title="Purchase Quantity & Production Costing" color="blue">
          <FormField label="Purchase unit *">
            <Select value={f.purchaseUnit || ""} onValueChange={(v) => setF({ ...f, purchaseUnit: v })}>
              <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
              <SelectContent>{unitOptions(f.purchaseUnit).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
            </Select>
          </FormField>
          <FormField label={`Purchase quantity${purchaseUnitLabel ? ` (${purchaseUnitLabel})` : ""} *`}><NumberInput min={0} step="0.001" value={f.quantity} onChange={(e) => setF({ ...f, quantity: Number(e.target.value) || 0 })} /></FormField>
          <FormField label="" full>
            <div className="flex items-center justify-between rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
              <div>
                <div className="text-sm font-medium text-slate-700">Enter purchase unit cost manually</div>
                <div className="text-xs text-slate-500">Turn off the auto-calculation and type the purchase unit cost yourself.</div>
              </div>
              <Switch checked={manualPurchaseCost} onCheckedChange={setManualPurchaseCost} />
            </div>
          </FormField>
          <FormField label="Total purchase cost *"><NumberInput min={0} step="0.01" value={Number(total.toFixed(2))} disabled={manualPurchaseCost} onChange={(e) => setF({ ...f, totalPurchaseCost: Number(e.target.value) || 0 })} /></FormField>
          {manualPurchaseCost ? (
            <FormField label={`Purchase unit cost${purchaseUnitLabel ? ` (per ${purchaseUnitLabel})` : ""}`} hint="Manual — sets the total for you">
              <NumberInput min={0} step="0.0001" value={Number(unitCost.toFixed(4))} onChange={(e) => {
                const c = Number(e.target.value) || 0
                setF({ ...f, totalPurchaseCost: qty > 0 ? Number((c * qty).toFixed(2)) : f.totalPurchaseCost })
              }} />
            </FormField>
          ) : (
            <FormField label="Purchase unit cost (auto)"><Input readOnly tabIndex={-1} className={roCls} value={`${gh(unitCost)}${purchaseUnitLabel ? ` per ${purchaseUnitLabel}` : ""}`} /></FormField>
          )}
        </FormSection>

        <FormSection title="Production Conversion" color="indigo">
          <FormField label="" full>
            <div className="flex items-center justify-between rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
              <div>
                <div className="text-sm font-medium text-slate-700">Enter production cost manually</div>
                <div className="text-xs text-slate-500">Turn off the auto-calculation and type the production-level unit cost yourself.</div>
              </div>
              <Switch checked={manualProdCost} onCheckedChange={setManualProdCost} />
            </div>
          </FormField>
          <FormField label="Production unit">
            <Select value={f.productionUnit || ""} onValueChange={(v) => setF({ ...f, productionUnit: v })}>
              <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
              <SelectContent>{unitOptions(f.productionUnit).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
            </Select>
          </FormField>
          <FormField label="Production units per purchase unit"><NumberInput min={0} step="0.0001" value={f.productionUnitsPerPurchaseUnit} onChange={(e) => setF({ ...f, productionUnitsPerPurchaseUnit: Number(e.target.value) || 0 })} /></FormField>
          <FormField label="Production-level quantity" hint="Editable — sets units per purchase unit"><NumberInput min={0} step="0.001" value={Number(prodQty.toFixed(4))} onChange={(e) => { const v = Number(e.target.value) || 0; setF({ ...f, productionUnitsPerPurchaseUnit: qty > 0 ? Number((v / qty).toFixed(8)) : f.productionUnitsPerPurchaseUnit }) }} /></FormField>
          {manualProdCost ? (
            <FormField label="Production-level unit cost" hint="Manual — sets the conversion for you">
              <NumberInput min={0} step="0.0001" value={Number(prodUnitCost.toFixed(4))} onChange={(e) => {
                const c = Number(e.target.value) || 0
                // production unit cost = total / (qty × perPurchase) ⇒ perPurchase = total / (cost × qty)
                const newPer = (c > 0 && qty > 0 && total > 0) ? Number((total / (c * qty)).toFixed(8)) : f.productionUnitsPerPurchaseUnit
                setF({ ...f, productionUnitsPerPurchaseUnit: newPer })
              }} />
            </FormField>
          ) : (
            <FormField label="Production-level unit cost (auto)"><Input readOnly tabIndex={-1} className={roCls} value={`${gh(prodUnitCost)}${f.productionUnit ? ` per ${f.productionUnit}` : ""}`} /></FormField>
          )}
          <FormField label="" full><p className="text-xs text-slate-500">If you buy and use the same unit, set <span className="font-medium">Production units per purchase unit = 1</span> — the production figures then match the purchase figures.</p></FormField>
        </FormSection>

        <FormSection title="Payment" color="amber">
          <FormField label="Amount paid"><NumberInput min={0} step="0.01" value={f.amountPaid} onChange={(e) => setF({ ...f, amountPaid: Number(e.target.value) || 0 })} /></FormField>
          <FormField label="Pay from cash account">
            <Select value={f.poultryCashAccountId ? String(f.poultryCashAccountId) : "none"} onValueChange={(v) => setF({ ...f, poultryCashAccountId: v === "none" ? 0 : Number(v) })}>
              <SelectTrigger><SelectValue placeholder="None (no cash movement)" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">None (no cash movement)</SelectItem>
                {cashAccounts.map((a) => (
                  <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                    {a.accountName} ({gh(a.currentBalance)})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Balance (auto)"><Input readOnly tabIndex={-1} className={roCls} value={gh(Math.max(0, total - (f.amountPaid || 0)))} /></FormField>
          <FormField label="" full><p className="text-xs text-slate-500">Choosing a cash account posts a cash-out for the amount paid and reduces that account&apos;s balance.</p></FormField>
        </FormSection>

        <FormSection title="Notes" color="slate" columns={1}>
          <FormField label="Notes"><Textarea rows={3} placeholder="Optional notes about this purchase" value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} /></FormField>
        </FormSection>

        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={() => void save()} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

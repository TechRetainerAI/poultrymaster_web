"use client"

import { useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Trash2, Loader2, Save, ArrowLeft, RefreshCw, CheckCircle2 } from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { usePermissions } from "@/hooks/use-permissions"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import {
  listFeedProductionItems, listFeedFormulas, getFeedFormula, saveFeedProductionBatch, postFeedProductionBatch,
  type FeedBatchItem, type FeedFormula, type FeedProductionBatch, type FeedProductionSourceType,
  type PaymentStatus,
} from "@/lib/api/poultry-feed-production"

const isFinishedFeed = (c?: string | null) => !!c && /finish/i.test(c)
const isIngredient = (c?: string | null) => !!c && /feed/i.test(c) && !isFinishedFeed(c)

const SOURCE_TYPES: { value: FeedProductionSourceType; label: string }[] = [
  { value: "FromInventory", label: "From Inventory" },
  { value: "BoughtDuringProduction", label: "Bought During Production" },
  { value: "MixedSource", label: "Mixed Source" },
]
const COST_TYPES = ["Labor", "Grinding", "Transport", "Electricity", "Fuel", "Packaging", "MachineMaintenance", "Other"]
const COST_LABELS: Record<string, string> = { MachineMaintenance: "Machine Maintenance" }
const costLabel = (c: string) => COST_LABELS[c] ?? c
const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Card"]
const PAYMENT_STATUSES: PaymentStatus[] = ["Paid", "Unpaid", "Partial"]

const num = (v: string | number | null | undefined) => (typeof v === "number" ? v : Number(v) || 0)
const rid = () => Math.random().toString(36).slice(2)

type LineState = {
  key: string
  ingredientItemId: number | null
  sourceType: FeedProductionSourceType
  quantityUsed: string
  unitOfMeasure: string
  inventoryQuantityUsed: string
  purchasedQuantityUsed: string
  inventoryUnitCost: string
  purchasedUnitCost: string
  supplierName: string
  purchaseReference: string
  paymentStatus: PaymentStatus
  amountPaid: string
  paidFromCashAccountId: number | null
  paymentMethod: string
  notes: string
}
const newLine = (): LineState => ({
  key: rid(), ingredientItemId: null, sourceType: "FromInventory", quantityUsed: "", unitOfMeasure: "",
  inventoryQuantityUsed: "", purchasedQuantityUsed: "", inventoryUnitCost: "", purchasedUnitCost: "",
  supplierName: "", purchaseReference: "", paymentStatus: "Unpaid", amountPaid: "", paidFromCashAccountId: null, paymentMethod: "Cash", notes: "",
})

type CostState = {
  key: string
  costType: string
  amount: string
  paymentStatus: PaymentStatus
  amountPaid: string
  paidFromCashAccountId: number | null
  paymentMethod: string
  payeeName: string
  notes: string
}
const newCost = (): CostState => ({ key: rid(), costType: "Labor", amount: "", paymentStatus: "Unpaid", amountPaid: "", paidFromCashAccountId: null, paymentMethod: "Cash", payeeName: "", notes: "" })

type HeaderState = {
  finishedFeedItemId: number | null
  formulaId: number | null
  productionDate: string
  quantityProduced: string
  outputUnit: string
  batchNumber: string
  notes: string
}

function lineDerived(l: LineState) {
  const qty = num(l.quantityUsed)
  const invUnit = num(l.inventoryUnitCost)
  const purUnit = num(l.purchasedUnitCost)
  let invQty = 0, purQty = 0
  if (l.sourceType === "FromInventory") invQty = qty
  else if (l.sourceType === "BoughtDuringProduction") purQty = qty
  else { invQty = num(l.inventoryQuantityUsed); purQty = num(l.purchasedQuantityUsed) }
  const invCost = invQty * invUnit
  const purCost = purQty * purUnit
  const total = invCost + purCost
  const unit = qty > 0 ? total / qty : 0
  const paid = l.paymentStatus === "Paid" ? purCost : l.paymentStatus === "Partial" ? num(l.amountPaid) : 0
  const payable = Math.max(0, purCost - paid)
  const mixedBalanced = l.sourceType !== "MixedSource" || Math.abs(invQty + purQty - qty) < 0.001
  const hasPurchase = l.sourceType !== "FromInventory"
  return { qty, invQty, purQty, invCost, purCost, total, unit, paid, payable, mixedBalanced, hasPurchase }
}
function costDerived(c: CostState) {
  const amount = num(c.amount)
  const paid = c.paymentStatus === "Paid" ? amount : c.paymentStatus === "Partial" ? num(c.amountPaid) : 0
  const payable = Math.max(0, amount - paid)
  return { amount, paid, payable }
}

export function FeedProductionBatchForm({ existing }: { existing?: FeedProductionBatch | null }) {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const canPost = usePermissions().featureAccess.canManageFeedProduction

  const [loading, setLoading] = useState(true)
  const [items, setItems] = useState<FeedBatchItem[]>([])
  const [formulas, setFormulas] = useState<FeedFormula[]>([])
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])

  const [header, setHeader] = useState<HeaderState>({
    finishedFeedItemId: existing?.finishedFeedItemId ?? null,
    formulaId: existing?.formulaId ?? null,
    productionDate: (existing?.productionDate ?? new Date().toISOString()).slice(0, 10),
    quantityProduced: existing ? String(existing.quantityProduced) : "",
    outputUnit: existing?.outputUnit ?? "",
    batchNumber: existing?.batchNumber ?? "",
    notes: existing?.notes ?? "",
  })
  const [lines, setLines] = useState<LineState[]>(
    existing?.lines?.length
      ? existing.lines.map((l) => ({
          key: rid(), ingredientItemId: l.ingredientItemId, sourceType: l.sourceType, quantityUsed: String(l.quantityUsed),
          unitOfMeasure: l.unitOfMeasure ?? "", inventoryQuantityUsed: l.inventoryQuantityUsed != null ? String(l.inventoryQuantityUsed) : "",
          purchasedQuantityUsed: l.purchasedQuantityUsed != null ? String(l.purchasedQuantityUsed) : "",
          inventoryUnitCost: l.inventoryUnitCost != null ? String(l.inventoryUnitCost) : "",
          purchasedUnitCost: l.purchasedUnitCost != null ? String(l.purchasedUnitCost) : "",
          supplierName: l.supplierName ?? "", purchaseReference: l.purchaseReference ?? "",
          paymentStatus: (l.paymentStatus ?? "Unpaid") as PaymentStatus, amountPaid: l.amountPaid != null ? String(l.amountPaid) : "",
          paidFromCashAccountId: l.paidFromCashAccountId ?? null, paymentMethod: l.paymentMethod ?? "Cash", notes: l.notes ?? "",
        }))
      : [newLine()],
  )
  const [costs, setCosts] = useState<CostState[]>(
    existing?.additionalCosts?.length
      ? existing.additionalCosts.map((c) => ({
          key: rid(), costType: c.costType, amount: String(c.amount), paymentStatus: (c.paymentStatus ?? "Unpaid") as PaymentStatus,
          amountPaid: c.amountPaid != null ? String(c.amountPaid) : "", paidFromCashAccountId: c.paidFromCashAccountId ?? null,
          paymentMethod: c.paymentMethod ?? "Cash", payeeName: c.payeeName ?? "", notes: c.notes ?? "",
        }))
      : [],
  )
  const [saving, setSaving] = useState(false)
  const savingRef = useRef(false)

  const itemById = useMemo(() => new Map(items.map((i) => [i.poultryRawMaterialItemId, i])), [items])
  const finishedFeedItems = useMemo(() => items.filter((i) => isFinishedFeed(i.category)), [items])
  const ingredientItems = useMemo(() => items.filter((i) => isIngredient(i.category)), [items])
  // A formula is a reusable ingredient pattern — any active formula can be applied
  // to any finished feed the batch produces (it is not bound to a feed item).
  const activeFormulas = useMemo(() => formulas.filter((f) => f.isActive), [formulas])

  useEffect(() => {
    (async () => {
      setLoading(true)
      try {
        const [it, f, ca] = await Promise.all([listFeedProductionItems(), listFeedFormulas(), listPoultryCashAccounts().catch(() => [])])
        setItems(it); setFormulas(f); setCashAccounts(ca)
      } catch (e: any) {
        toast({ title: "Failed to load form data", description: e?.message ?? String(e), variant: "destructive" })
      } finally {
        setLoading(false)
      }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  function setLine(key: string, patch: Partial<LineState>) {
    setLines((ls) => ls.map((l) => (l.key === key ? { ...l, ...patch } : l)))
  }
  function pickIngredient(key: string, itemId: number) {
    const it = itemById.get(itemId)
    setLine(key, { ingredientItemId: itemId, unitOfMeasure: it?.unitOfMeasure ?? "", inventoryUnitCost: it ? String(it.latestUnitCost) : "" })
  }
  const addLine = () => setLines((ls) => [...ls, newLine()])
  const removeLine = (key: string) => setLines((ls) => (ls.length > 1 ? ls.filter((l) => l.key !== key) : ls))

  function setCost(key: string, patch: Partial<CostState>) {
    setCosts((cs) => cs.map((c) => (c.key === key ? { ...c, ...patch } : c)))
  }
  const addCost = () => setCosts((cs) => [...cs, newCost()])
  const removeCost = (key: string) => setCosts((cs) => cs.filter((c) => c.key !== key))

  // Build ingredient lines from a formula at a given quantity to produce.
  // Percentage lines scale with quantity; fixed lines stay fixed.
  const [appliedFormula, setAppliedFormula] = useState<FeedFormula | null>(null)
  function linesFromFormula(f: FeedFormula, qty: number): LineState[] {
    return (f.lines ?? []).map((fl) => {
      const it = itemById.get(fl.ingredientItemId)
      const required = fl.quantityMode === "Percentage" ? (qty * (fl.percentage ?? 0)) / 100 : (fl.fixedQuantity ?? 0)
      return {
        ...newLine(),
        ingredientItemId: fl.ingredientItemId,
        unitOfMeasure: fl.unitOfMeasure ?? it?.unitOfMeasure ?? "",
        quantityUsed: required ? String(Number(required.toFixed(3))) : "",
        inventoryUnitCost: it ? String(it.latestUnitCost) : "",
      }
    })
  }

  // Apply a formula: fill ingredient lines by percentage/fixed.
  async function applyFormula(formulaId: number) {
    setHeader((h) => ({ ...h, formulaId }))
    const qty = num(header.quantityProduced)
    try {
      const full = await getFeedFormula(formulaId)
      setAppliedFormula(full)
      if (full.finishedFeedItemId) setHeader((h) => ({ ...h, finishedFeedItemId: full.finishedFeedItemId, formulaId }))
      const filled = linesFromFormula(full, qty)
      if (filled.length) setLines(filled)
      toast({ title: "Formula applied", description: qty > 0 ? "Ingredient quantities calculated from the quantity to produce." : "Enter a quantity to produce, then Recalculate to fill amounts." })
    } catch (e: any) {
      toast({ title: "Failed to apply formula", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  // Re-fill lines from the applied formula at the current quantity (used after
  // the quantity produced changes). Overwrites the ingredient lines.
  function recalcFromFormula() {
    if (!appliedFormula) return
    const qty = num(header.quantityProduced)
    if (qty <= 0) { toast({ title: "Enter a quantity to produce first", variant: "destructive" }); return }
    const filled = linesFromFormula(appliedFormula, qty)
    if (filled.length) setLines(filled)
    toast({ title: "Ingredient quantities recalculated", description: `Scaled to ${qty.toLocaleString()}${header.outputUnit ? ` ${header.outputUnit}` : ""}.` })
  }

  // Totals / previews
  const lineCalcs = useMemo(() => lines.map((l) => ({ l, d: lineDerived(l) })), [lines])
  const costCalcs = useMemo(() => costs.map((c) => ({ c, d: costDerived(c) })), [costs])
  const totalIngredientCost = useMemo(() => lineCalcs.reduce((s, x) => s + x.d.total, 0), [lineCalcs])
  const totalAdditionalCost = useMemo(() => costCalcs.reduce((s, x) => s + x.d.amount, 0), [costCalcs])
  const totalProductionCost = totalIngredientCost + totalAdditionalCost
  const qtyProduced = num(header.quantityProduced)
  const costPerUnit = qtyProduced > 0 ? totalProductionCost / qtyProduced : 0

  const cashOut = useMemo(() => {
    const map = new Map<number, number>()
    const add = (acctId: number | null, amt: number) => {
      if (!acctId || amt <= 0) return
      map.set(acctId, (map.get(acctId) ?? 0) + amt)
    }
    lineCalcs.forEach(({ l, d }) => add(l.paidFromCashAccountId, d.paid))
    costCalcs.forEach(({ c, d }) => add(c.paidFromCashAccountId, d.paid))
    return map
  }, [lineCalcs, costCalcs])
  const totalCashOut = useMemo(() => Array.from(cashOut.values()).reduce((s, v) => s + v, 0), [cashOut])
  const totalPayable = useMemo(
    () => lineCalcs.reduce((s, x) => s + x.d.payable, 0) + costCalcs.reduce((s, x) => s + x.d.payable, 0),
    [lineCalcs, costCalcs],
  )
  const acctName = (id: number) => cashAccounts.find((a) => a.poultryCashAccountId === id)?.accountName ?? `Account #${id}`
  const finishedFeedName = finishedFeedItems.find((i) => i.poultryRawMaterialItemId === header.finishedFeedItemId)?.itemName

  function validate(): string | null {
    if (!header.finishedFeedItemId) return "Pick the finished feed this batch produces."
    if (qtyProduced <= 0) return "Quantity produced must be greater than zero."
    const active = lineCalcs.filter((x) => x.l.ingredientItemId && x.d.qty > 0)
    if (!active.length) return "Add at least one ingredient line."
    for (const { l, d } of active) {
      if (!d.mixedBalanced) return "A mixed-source line's inventory + purchased quantities must equal the quantity used."
      if (d.hasPurchase && num(l.purchasedUnitCost) <= 0) return "Enter the purchased unit cost for bought / mixed ingredient lines."
      if (l.paymentStatus === "Partial" && num(l.amountPaid) > d.purCost) return "Amount paid cannot exceed the purchased cost."
    }
    for (const { c, d } of costCalcs) {
      if (d.amount < 0) return "Additional cost amounts cannot be negative."
      if (c.paymentStatus === "Partial" && num(c.amountPaid) > d.amount) return "Amount paid cannot exceed the cost amount."
    }
    return null
  }

  const [posting, setPosting] = useState(false)

  async function persist(): Promise<FeedProductionBatch> {
    return saveFeedProductionBatch({
        poultryFeedProductionBatchId: existing?.poultryFeedProductionBatchId ?? undefined,
        batchNumber: header.batchNumber || null,
        productionDate: header.productionDate ? new Date(header.productionDate).toISOString() : null,
        finishedFeedItemId: header.finishedFeedItemId!,
        formulaId: header.formulaId ?? null,
        quantityProduced: qtyProduced,
        outputUnit: header.outputUnit || null,
        notes: header.notes || null,
        lines: lineCalcs
          .filter((x) => x.l.ingredientItemId && x.d.qty > 0)
          .map((x, idx) => ({
            ingredientItemId: x.l.ingredientItemId!,
            sourceType: x.l.sourceType,
            quantityUsed: x.d.qty,
            unitOfMeasure: x.l.unitOfMeasure || null,
            inventoryQuantityUsed: x.l.sourceType === "MixedSource" ? x.d.invQty : x.l.sourceType === "FromInventory" ? x.d.qty : 0,
            purchasedQuantityUsed: x.l.sourceType === "MixedSource" ? x.d.purQty : x.l.sourceType === "BoughtDuringProduction" ? x.d.qty : 0,
            inventoryUnitCost: num(x.l.inventoryUnitCost),
            purchasedUnitCost: num(x.l.purchasedUnitCost),
            supplierName: x.l.supplierName || null,
            purchaseReference: x.l.purchaseReference || null,
            paymentStatus: x.d.hasPurchase ? x.l.paymentStatus : null,
            amountPaid: x.d.hasPurchase ? x.d.paid : null,
            paidFromCashAccountId: x.d.hasPurchase && x.d.paid > 0 ? x.l.paidFromCashAccountId : null,
            paymentMethod: x.d.hasPurchase && x.d.paid > 0 ? x.l.paymentMethod : null,
            sortOrder: idx,
            notes: x.l.notes || null,
          })),
        additionalCosts: costCalcs
          .filter((x) => x.d.amount > 0)
          .map((x, idx) => ({
            costType: x.c.costType,
            amount: x.d.amount,
            paymentStatus: x.c.paymentStatus,
            amountPaid: x.d.paid,
            paidFromCashAccountId: x.d.paid > 0 ? x.c.paidFromCashAccountId : null,
            paymentMethod: x.d.paid > 0 ? x.c.paymentMethod : null,
            payeeName: x.c.payeeName || null,
            sortOrder: idx,
            notes: x.c.notes || null,
          })),
    })
  }

  async function save() {
    if (savingRef.current) return
    const err = validate()
    if (err) { toast({ title: err, variant: "destructive" }); return }
    savingRef.current = true
    setSaving(true)
    try {
      const saved = await persist()
      toast({ title: existing ? "Draft updated" : "Draft saved", description: saved?.batchNumber ? `Batch ${saved.batchNumber}` : undefined })
      router.push(`/poultry-feed-production/${saved.poultryFeedProductionBatchId}`)
    } catch (e: any) {
      toast({ title: "Failed to save batch", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  // Save the draft, then post it (inventory draws, produced stock, cash/payables).
  async function saveAndPost() {
    if (savingRef.current) return
    const err = validate()
    if (err) { toast({ title: err, variant: "destructive" }); return }
    savingRef.current = true
    setPosting(true)
    try {
      const saved = await persist()
      const posted = await postFeedProductionBatch(saved.poultryFeedProductionBatchId)
      toast({ title: "Batch posted", description: `Cost/unit ${gh(posted?.costPerOutputUnit ?? 0)} · stock & cash updated.` })
      router.push(`/poultry-feed-production/${saved.poultryFeedProductionBatchId}`)
    } catch (e: any) {
      toast({ title: "Failed to post batch", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      savingRef.current = false
      setPosting(false)
    }
  }

  if (loading) return <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="ghost" size="sm" onClick={() => router.push("/poultry-feed-production")}><ArrowLeft className="w-4 h-4 mr-1" /> Back</Button>
        <h1 className="text-2xl font-bold">{existing ? `Edit Batch ${existing.batchNumber ?? ""}` : "New Feed Production Batch"}</h1>
        {existing && <Badge variant="outline">Draft</Badge>}
      </div>

      {/* Section 1 — Finished feed output */}
      <FormSection title="Finished feed output" color="blue">
        <FormField label="Finished feed *">
          <Select value={header.finishedFeedItemId ? String(header.finishedFeedItemId) : ""} onValueChange={(v) => setHeader({ ...header, finishedFeedItemId: Number(v) })}>
            <SelectTrigger><SelectValue placeholder={finishedFeedItems.length ? "Pick finished feed" : "No finished-feed items — create one first"} /></SelectTrigger>
            <SelectContent>{finishedFeedItems.map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}</SelectItem>)}</SelectContent>
          </Select>
        </FormField>
        <FormField label="Feed formula" hint="Optional — auto-calculates ingredient quantities">
          <Select value={header.formulaId ? String(header.formulaId) : ""} onValueChange={(v) => void applyFormula(Number(v))}>
            <SelectTrigger><SelectValue placeholder={activeFormulas.length ? "Pick a formula" : "No formulas"} /></SelectTrigger>
            <SelectContent>{activeFormulas.map((f) => <SelectItem key={f.poultryFeedFormulaId} value={String(f.poultryFeedFormulaId)}>{f.formulaName}</SelectItem>)}</SelectContent>
          </Select>
        </FormField>
        <FormField label="Production date"><Input type="date" value={header.productionDate} onChange={(e) => setHeader({ ...header, productionDate: e.target.value })} /></FormField>
        <FormField label="Quantity produced *"><NumberInput min={0} step="0.001" value={header.quantityProduced} onChange={(e) => setHeader({ ...header, quantityProduced: e.target.value })} /></FormField>
        <FormField label="Output unit" hint="e.g. kg, bag"><Input value={header.outputUnit} onChange={(e) => setHeader({ ...header, outputUnit: e.target.value })} /></FormField>
        <FormField label="Batch number" hint="Auto-generated if left blank"><Input value={header.batchNumber} onChange={(e) => setHeader({ ...header, batchNumber: e.target.value })} placeholder="FP-2026-0001" /></FormField>
        <FormField label="Notes" full><Textarea rows={2} value={header.notes} onChange={(e) => setHeader({ ...header, notes: e.target.value })} /></FormField>
      </FormSection>

      {/* Section 2 — Ingredient breakdown */}
      <FormSection title="Ingredient breakdown" color="emerald" columns={1}>
        <div className="space-y-3">
          {lineCalcs.map(({ l, d }) => {
            const it = l.ingredientItemId ? itemById.get(l.ingredientItemId) : undefined
            return (
              <div key={l.key} className="rounded-lg border border-slate-200 p-3 bg-white space-y-2">
                <div className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-end">
                  <div className="sm:col-span-4">
                    <label className="text-xs text-slate-500">Ingredient</label>
                    <Select value={l.ingredientItemId ? String(l.ingredientItemId) : ""} onValueChange={(v) => pickIngredient(l.key, Number(v))}>
                      <SelectTrigger><SelectValue placeholder="Pick ingredient" /></SelectTrigger>
                      <SelectContent>{ingredientItems.map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div className="sm:col-span-3">
                    <label className="text-xs text-slate-500">Source</label>
                    <Select value={l.sourceType} onValueChange={(v) => setLine(l.key, { sourceType: v as FeedProductionSourceType })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{SOURCE_TYPES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div className="sm:col-span-2">
                    <label className="text-xs text-slate-500">Qty used{l.unitOfMeasure ? ` (${l.unitOfMeasure})` : ""}</label>
                    <NumberInput min={0} step="0.001" value={l.quantityUsed} onChange={(e) => setLine(l.key, { quantityUsed: e.target.value })} />
                    {it && <div className="text-[11px] text-slate-400 mt-0.5">In stock: {it.currentQuantity.toLocaleString()}</div>}
                  </div>
                  <div className="sm:col-span-2 text-right">
                    <label className="text-xs text-slate-500">Line cost</label>
                    <div className="font-semibold tabular-nums text-slate-800">{gh(d.total)}</div>
                    <div className="text-[11px] text-slate-400">{gh(d.unit)}/unit</div>
                  </div>
                  <div className="sm:col-span-1 flex sm:justify-end">
                    <Button variant="ghost" size="sm" onClick={() => removeLine(l.key)} disabled={lines.length <= 1}><Trash2 className="w-4 h-4 text-red-600" /></Button>
                  </div>
                </div>

                {/* From-inventory cost */}
                {l.sourceType === "FromInventory" && (
                  <div className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-end">
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">Inventory unit cost</label>
                      <NumberInput min={0} step="0.0001" value={l.inventoryUnitCost} onChange={(e) => setLine(l.key, { inventoryUnitCost: e.target.value })} />
                      <div className="text-[11px] text-slate-400 mt-0.5">Latest cost — refined from stock lots at posting</div>
                    </div>
                  </div>
                )}

                {/* Mixed-source split */}
                {l.sourceType === "MixedSource" && (
                  <div className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-end">
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">From inventory qty</label>
                      <NumberInput min={0} step="0.001" value={l.inventoryQuantityUsed} onChange={(e) => setLine(l.key, { inventoryQuantityUsed: e.target.value })} />
                    </div>
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">Inventory unit cost</label>
                      <NumberInput min={0} step="0.0001" value={l.inventoryUnitCost} onChange={(e) => setLine(l.key, { inventoryUnitCost: e.target.value })} />
                    </div>
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">Purchased qty</label>
                      <NumberInput min={0} step="0.001" value={l.purchasedQuantityUsed} onChange={(e) => setLine(l.key, { purchasedQuantityUsed: e.target.value })} />
                    </div>
                    <div className="sm:col-span-3">
                      {!d.mixedBalanced && <div className="text-[11px] text-amber-600">Inventory + purchased must equal {d.qty || "qty used"}</div>}
                    </div>
                  </div>
                )}

                {/* Purchased portion (bought + mixed) */}
                {d.hasPurchase && (
                  <div className="rounded-md bg-slate-50 border border-slate-200 p-2.5 grid grid-cols-1 sm:grid-cols-12 gap-2 items-end">
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">Purchased unit cost *</label>
                      <NumberInput min={0} step="0.0001" value={l.purchasedUnitCost} onChange={(e) => setLine(l.key, { purchasedUnitCost: e.target.value })} />
                    </div>
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">Supplier</label>
                      <Input value={l.supplierName} onChange={(e) => setLine(l.key, { supplierName: e.target.value })} />
                    </div>
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">Payment</label>
                      <Select value={l.paymentStatus} onValueChange={(v) => setLine(l.key, { paymentStatus: v as PaymentStatus })}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{PAYMENT_STATUSES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div className="sm:col-span-3 text-right">
                      <label className="text-xs text-slate-500">Purchased cost</label>
                      <div className="font-medium tabular-nums">{gh(d.purCost)}</div>
                    </div>
                    {l.paymentStatus === "Partial" && (
                      <div className="sm:col-span-3">
                        <label className="text-xs text-slate-500">Amount paid</label>
                        <NumberInput min={0} step="0.01" value={l.amountPaid} onChange={(e) => setLine(l.key, { amountPaid: e.target.value })} />
                      </div>
                    )}
                    {l.paymentStatus !== "Unpaid" && (
                      <>
                        <div className="sm:col-span-3">
                          <label className="text-xs text-slate-500">Paid from</label>
                          <Select value={l.paidFromCashAccountId ? String(l.paidFromCashAccountId) : ""} onValueChange={(v) => setLine(l.key, { paidFromCashAccountId: Number(v) })}>
                            <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
                            <SelectContent>{cashAccounts.map((a) => <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                          </Select>
                        </div>
                        <div className="sm:col-span-3">
                          <label className="text-xs text-slate-500">Method</label>
                          <Select value={l.paymentMethod} onValueChange={(v) => setLine(l.key, { paymentMethod: v })}>
                            <SelectTrigger><SelectValue /></SelectTrigger>
                            <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                          </Select>
                        </div>
                      </>
                    )}
                    {d.payable > 0 && <div className="sm:col-span-3 text-right text-[11px] text-red-600 self-center">Payable: {gh(d.payable)}</div>}
                  </div>
                )}
              </div>
            )
          })}
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="outline" size="sm" onClick={addLine}><Plus className="w-4 h-4 mr-1" /> Add ingredient</Button>
            {appliedFormula && (
              <Button variant="ghost" size="sm" onClick={recalcFromFormula} title="Refill ingredient quantities from the formula at the current quantity to produce">
                <RefreshCw className="w-4 h-4 mr-1" /> Recalculate from {appliedFormula.formulaName}
              </Button>
            )}
          </div>
        </div>
      </FormSection>

      {/* Section 3 — Additional production costs */}
      <FormSection title="Additional production costs" color="amber" columns={1}>
        <div className="space-y-2">
          {costs.length === 0 && <p className="text-sm text-slate-400">No additional costs. Add grinding, labor, transport, etc. if any.</p>}
          {costCalcs.map(({ c, d }) => (
            <div key={c.key} className="rounded-lg border border-slate-200 p-2.5 bg-white grid grid-cols-1 sm:grid-cols-12 gap-2 items-end">
              <div className="sm:col-span-2">
                <label className="text-xs text-slate-500">Type</label>
                <Select value={c.costType} onValueChange={(v) => setCost(c.key, { costType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{COST_TYPES.map((t) => <SelectItem key={t} value={t}>{costLabel(t)}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div className="sm:col-span-2">
                <label className="text-xs text-slate-500">Amount</label>
                <NumberInput min={0} step="0.01" value={c.amount} onChange={(e) => setCost(c.key, { amount: e.target.value })} />
              </div>
              <div className="sm:col-span-2">
                <label className="text-xs text-slate-500">Payment</label>
                <Select value={c.paymentStatus} onValueChange={(v) => setCost(c.key, { paymentStatus: v as PaymentStatus })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PAYMENT_STATUSES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              {c.paymentStatus === "Partial" && (
                <div className="sm:col-span-2">
                  <label className="text-xs text-slate-500">Amount paid</label>
                  <NumberInput min={0} step="0.01" value={c.amountPaid} onChange={(e) => setCost(c.key, { amountPaid: e.target.value })} />
                </div>
              )}
              {c.paymentStatus !== "Unpaid" && (
                <div className="sm:col-span-2">
                  <label className="text-xs text-slate-500">Paid from</label>
                  <Select value={c.paidFromCashAccountId ? String(c.paidFromCashAccountId) : ""} onValueChange={(v) => setCost(c.key, { paidFromCashAccountId: Number(v) })}>
                    <SelectTrigger><SelectValue placeholder="Account" /></SelectTrigger>
                    <SelectContent>{cashAccounts.map((a) => <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
              )}
              <div className="sm:col-span-3">
                <label className="text-xs text-slate-500">Payee / notes</label>
                <Input value={c.payeeName} onChange={(e) => setCost(c.key, { payeeName: e.target.value })} placeholder="Who was paid" />
              </div>
              <div className="sm:col-span-1 flex sm:justify-end">
                <Button variant="ghost" size="sm" onClick={() => removeCost(c.key)}><Trash2 className="w-4 h-4 text-red-600" /></Button>
              </div>
            </div>
          ))}
          <Button variant="outline" size="sm" onClick={addCost}><Plus className="w-4 h-4 mr-1" /> Add cost</Button>
        </div>
      </FormSection>

      {/* Section 4 — Summary & impact previews */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-3">
        <Card><CardContent className="p-4 space-y-2">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Cost summary</div>
          <Row label="Total ingredient cost" value={gh(totalIngredientCost)} />
          <Row label="Additional production costs" value={gh(totalAdditionalCost)} />
          <div className="border-t border-slate-200 my-1" />
          <Row label="Total production cost" value={gh(totalProductionCost)} bold />
          <Row label={`Cost per unit${header.outputUnit ? ` (${header.outputUnit})` : ""}`} value={gh(costPerUnit)} bold />
          <Row label="Quantity produced" value={`${qtyProduced.toLocaleString()}${header.outputUnit ? ` ${header.outputUnit}` : ""}`} />
        </CardContent></Card>

        <Card><CardContent className="p-4 space-y-1.5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Inventory impact</div>
          {lineCalcs.filter((x) => x.l.ingredientItemId && x.d.invQty > 0).map(({ l, d }) => (
            <div key={l.key} className="flex justify-between text-sm"><span className="text-slate-600">{itemById.get(l.ingredientItemId!)?.itemName}</span><span className="tabular-nums text-red-600">-{d.invQty.toLocaleString()}</span></div>
          ))}
          {lineCalcs.filter((x) => x.l.ingredientItemId && x.d.purQty > 0).map(({ l, d }) => (
            <div key={l.key} className="flex justify-between text-sm"><span className="text-slate-600">{itemById.get(l.ingredientItemId!)?.itemName} <span className="text-[11px] text-slate-400">(bought → used)</span></span><span className="tabular-nums text-slate-400">+{d.purQty.toLocaleString()} / -{d.purQty.toLocaleString()}</span></div>
          ))}
          <div className="border-t border-slate-200 my-1" />
          <div className="flex justify-between text-sm font-medium"><span>{finishedFeedName ?? "Finished feed"}</span><span className="tabular-nums text-emerald-600">+{qtyProduced.toLocaleString()}</span></div>
        </CardContent></Card>

        <Card><CardContent className="p-4 space-y-1.5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Cash & payable impact</div>
          {Array.from(cashOut.entries()).map(([id, amt]) => (
            <div key={id} className="flex justify-between text-sm"><span className="text-slate-600">{acctName(id)}</span><span className="tabular-nums text-red-600">-{gh(amt)}</span></div>
          ))}
          <div className="flex justify-between text-sm font-medium"><span>Total cash out</span><span className="tabular-nums">{gh(totalCashOut)}</span></div>
          <div className="border-t border-slate-200 my-1" />
          <div className="flex justify-between text-sm"><span className="text-slate-600">Supplier payables (unpaid)</span><span className={cn("tabular-nums", totalPayable > 0 ? "text-red-600" : "text-emerald-600")}>{gh(totalPayable)}</span></div>
          <p className="text-[11px] text-slate-400 pt-1">Cash & payables post when the batch is posted, not while it's a draft.</p>
        </CardContent></Card>
      </div>

      <div className="flex flex-wrap justify-end gap-2 pt-1 pb-8">
        <Button variant="outline" onClick={() => router.push("/poultry-feed-production")} disabled={saving || posting}>Cancel</Button>
        <Button variant="outline" onClick={() => void save()} disabled={saving || posting}>
          {saving ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Saving…</> : <><Save className="w-4 h-4 mr-1" /> Save Draft</>}
        </Button>
        {canPost && (
          <Button onClick={() => void saveAndPost()} disabled={saving || posting}>
            {posting ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Posting…</> : <><CheckCircle2 className="w-4 h-4 mr-1" /> Save &amp; Post</>}
          </Button>
        )}
      </div>
    </div>
  )
}

function Row({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div className={cn("flex justify-between text-sm", bold && "font-semibold text-slate-900")}>
      <span className={cn(!bold && "text-slate-600")}>{label}</span>
      <span className="tabular-nums">{value}</span>
    </div>
  )
}

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
  type FeedBatchItem, type FeedFormula, type FeedFormulaLine, type FeedProductionBatch, type FeedProductionSourceType,
  type PaymentStatus,
} from "@/lib/api/poultry-feed-production"
import { scaleFormulaLines, formulaCoverage, formulaUnitFactors, roundQty } from "@/lib/feed-formula-scale"
import {
  AlertDialog, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"

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
// A derived number shown inside an input: trimmed to dp, no trailing zeros,
// and blank at zero so the field doesn't read as a real entry.
const numStr = (n: number, dp: number) => (n > 0 ? String(Number(n.toFixed(dp))) : "")

// Stock errors from the shared lot-consumption SP arrive as one raw line per
// ingredient. Tidy them into something a farmer can read, and drop the
// internal wording, in case one slips past the pre-flight check.
function readableError(e: any): string {
  const raw = String(e?.message ?? e ?? "").trim()
  if (!raw) return "Something went wrong."
  const parts = raw.split(/\r?\n/).map((s) => s.trim()).filter(Boolean)
  if (!parts.some((p) => /tracked batch stock/i.test(p))) return raw
  const items = parts
    .map((p) => p.match(/for\s+"([^"]+)":\s*need\s+([\d.]+),\s*only\s+([\d.]+)/i))
    .filter(Boolean)
    .map((m) => `${m![1]} (needs ${Number(m![2]).toLocaleString()}, only ${Number(m![3]).toLocaleString()} available)`)
  return items.length
    ? `Not enough ingredient stock to post: ${items.join("; ")}. Lower the quantity produced, or buy the shortfall during production.`
    : raw
}

type LineState = {
  key: string
  ingredientItemId: number | null
  // Which formula line this row came from. null = added by hand — the formula
  // never rescales it. qtyOverridden = the farmer typed a quantity themselves,
  // so the formula stops overwriting it until they reset the row.
  formulaLineId: number | null
  qtyOverridden: boolean
  sourceType: FeedProductionSourceType
  quantityUsed: string
  unitOfMeasure: string
  inventoryQuantityUsed: string
  purchasedQuantityUsed: string
  inventoryUnitCost: string
  purchasedUnitCost: string
  // The purchased cost can be given per unit or as a total; this says which the
  // farmer typed, and the other is shown derived. Only the unit cost is stored
  // — the line has no total column.
  purchasedTotalCost: string
  purchasedCostMode: "Unit" | "Total"
  supplierName: string
  purchaseReference: string
  paymentStatus: PaymentStatus
  amountPaid: string
  paidFromCashAccountId: number | null
  paymentMethod: string
  notes: string
}
const newLine = (): LineState => ({
  key: rid(), ingredientItemId: null, formulaLineId: null, qtyOverridden: false,
  sourceType: "FromInventory", quantityUsed: "", unitOfMeasure: "",
  inventoryQuantityUsed: "", purchasedQuantityUsed: "", inventoryUnitCost: "", purchasedUnitCost: "",
  purchasedTotalCost: "", purchasedCostMode: "Unit",
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
  let invQty = 0, purQty = 0
  if (l.sourceType === "FromInventory") invQty = qty
  else if (l.sourceType === "BoughtDuringProduction") purQty = qty
  else { invQty = num(l.inventoryQuantityUsed); purQty = num(l.purchasedQuantityUsed) }

  // The purchased cost is entered either way round: per unit, or as the cost of
  // the purchased portion. Whichever was typed is authoritative and the other is
  // derived, so they can't drift as the formula rescales the quantity. The
  // inventory portion is never typed — posting prices it from the stock lots.
  const invUnit = num(l.inventoryUnitCost)
  const invCost = invQty * invUnit
  const purCost = purQty > 0
    ? (l.purchasedCostMode === "Total" ? num(l.purchasedTotalCost) : purQty * num(l.purchasedUnitCost))
    : 0
  const purUnit = purQty > 0 ? purCost / purQty : 0

  const total = invCost + purCost
  const unit = qty > 0 ? total / qty : 0
  const paid = l.paymentStatus === "Paid" ? purCost : l.paymentStatus === "Partial" ? num(l.amountPaid) : 0
  const payable = Math.max(0, purCost - paid)
  const mixedBalanced = l.sourceType !== "MixedSource" || Math.abs(invQty + purQty - qty) < 0.001
  const hasPurchase = l.sourceType !== "FromInventory"
  return { qty, invQty, purQty, invCost, purCost, invUnit, purUnit, total, unit, paid, payable, mixedBalanced, hasPurchase }
}
// A mixed-source row splits its quantity between inventory and a fresh
// purchase. When the formula rescales the row, move the split with it so the
// two halves still add up to the new quantity. An unsplit row is left alone —
// the farmer hasn't decided the split yet.
function splitMixed(l: LineState, want: number): Partial<LineState> {
  if (l.sourceType !== "MixedSource") return {}
  const inv = num(l.inventoryQuantityUsed)
  const pur = num(l.purchasedQuantityUsed)
  const old = inv + pur
  if (old <= 0) return {}
  const scaled = roundQty(inv * (want / old))
  return { inventoryQuantityUsed: String(scaled), purchasedQuantityUsed: String(roundQty(want - scaled)) }
}

// Re-attach a saved draft's rows to their formula lines (matched on ingredient).
// A saved quantity that doesn't match what the formula would produce at the
// saved batch size was hand-tuned — keep it marked as overridden so reopening
// the draft doesn't silently rewrite it.
function relinkToFormula(lines: LineState[], formulaLines: FeedFormulaLine[], savedQty: number): LineState[] {
  const required = scaleFormulaLines(formulaLines, savedQty)
  const unclaimed = [...formulaLines]
  return lines.map((l) => {
    const idx = unclaimed.findIndex((fl) => fl.ingredientItemId === l.ingredientItemId)
    if (idx < 0) return l
    const [fl] = unclaimed.splice(idx, 1)
    const want = required.get(fl.poultryFeedFormulaLineId) ?? 0
    return { ...l, formulaLineId: fl.poultryFeedFormulaLineId, qtyOverridden: Math.abs(num(l.quantityUsed) - want) > 0.001 }
  })
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
  // The formula currently driving the ingredient quantities (full detail, with lines).
  const [appliedFormula, setAppliedFormula] = useState<FeedFormula | null>(null)

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
          key: rid(), ingredientItemId: l.ingredientItemId, formulaLineId: null, qtyOverridden: false,
          sourceType: l.sourceType, quantityUsed: String(l.quantityUsed),
          unitOfMeasure: l.unitOfMeasure ?? "", inventoryQuantityUsed: l.inventoryQuantityUsed != null ? String(l.inventoryQuantityUsed) : "",
          purchasedQuantityUsed: l.purchasedQuantityUsed != null ? String(l.purchasedQuantityUsed) : "",
          inventoryUnitCost: l.inventoryUnitCost != null ? String(l.inventoryUnitCost) : "",
          purchasedUnitCost: l.purchasedUnitCost != null ? String(l.purchasedUnitCost) : "",
          purchasedTotalCost: "", purchasedCostMode: "Unit" as const,
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
        const savedFormulaId = existing?.formulaId ?? null
        const [it, f, ca, full] = await Promise.all([
          listFeedProductionItems(),
          listFeedFormulas(),
          listPoultryCashAccounts().catch(() => []),
          savedFormulaId ? getFeedFormula(savedFormulaId).catch(() => null) : Promise.resolve(null),
        ])
        setItems(it); setFormulas(f); setCashAccounts(ca)
        // Re-link a saved draft to its formula so quantities keep scaling on edit.
        if (full?.lines?.length) {
          setLines((ls) => relinkToFormula(ls, full.lines!, num(existing?.quantityProduced)))
          setAppliedFormula(full)
        }
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

  // Seed one ingredient row per formula line. Quantities are left to the
  // scaling effect below, so picking a formula before typing a quantity works.
  function linesFromFormula(f: FeedFormula): LineState[] {
    return (f.lines ?? []).map((fl) => {
      const it = itemById.get(fl.ingredientItemId)
      return {
        ...newLine(),
        ingredientItemId: fl.ingredientItemId,
        formulaLineId: fl.poultryFeedFormulaLineId,
        unitOfMeasure: fl.unitOfMeasure ?? it?.unitOfMeasure ?? "",
        inventoryUnitCost: it ? String(it.latestUnitCost) : "",
      }
    })
  }

  // Apply a formula: rebuild the formula-driven rows, keep hand-added ones.
  async function applyFormula(formulaId: number) {
    setHeader((h) => ({ ...h, formulaId }))
    try {
      const full = await getFeedFormula(formulaId)
      // Output unit is derived, not set here — see the effect below.
      setHeader((h) => ({
        ...h,
        formulaId,
        finishedFeedItemId: full.finishedFeedItemId ?? h.finishedFeedItemId,
      }))
      const seeded = linesFromFormula(full)
      if (seeded.length) {
        // Hand-added rows the farmer already filled in survive a formula swap.
        setLines((ls) => [...seeded, ...ls.filter((l) => l.formulaLineId === null && l.ingredientItemId && num(l.quantityUsed) > 0)])
      }
      setAppliedFormula(full)
      toast({ title: "Formula applied", description: `${seeded.length} ingredient${seeded.length === 1 ? "" : "s"} — quantities follow the quantity produced.` })
    } catch (e: any) {
      toast({ title: "Failed to apply formula", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  // Hand back every overridden row to the formula.
  function resetToFormula() {
    if (!appliedFormula) return
    setLines((ls) => ls.map((l) => (l.formulaLineId !== null ? { ...l, qtyOverridden: false } : l)))
    toast({ title: "Reset to formula", description: "Edited quantities now follow the quantity produced again." })
  }

  const formulaLineById = useMemo(
    () => new Map((appliedFormula?.lines ?? []).map((fl) => [fl.poultryFeedFormulaLineId, fl])),
    [appliedFormula],
  )
  const coverage = useMemo(() => formulaCoverage(appliedFormula?.lines), [appliedFormula])

  // Output unit isn't typed — it comes from the formula's default unit, falling
  // back to the finished feed item's own unit. Keeping it derived stops a batch
  // being recorded in a unit the ingredients and stock aren't measured in.
  const finishedFeedUnit = header.finishedFeedItemId ? itemById.get(header.finishedFeedItemId)?.unitOfMeasure ?? "" : ""
  const derivedOutputUnit = appliedFormula?.defaultOutputUnit || finishedFeedUnit || ""
  const outputUnitSource = appliedFormula?.defaultOutputUnit
    ? `From formula ${appliedFormula.formulaName}`
    : finishedFeedUnit
      ? "From the finished feed item"
      : "Set a unit on the formula or the finished feed item"
  useEffect(() => {
    // Only overwrite when we actually derived something, so an older draft's
    // saved unit isn't wiped when neither source has one.
    if (derivedOutputUnit && derivedOutputUnit !== header.outputUnit) {
      setHeader((h) => ({ ...h, outputUnit: derivedOutputUnit }))
    }
  }, [derivedOutputUnit, header.outputUnit])

  // What the formula says this row's share is — shown under the quantity.
  function formulaShareOf(l: LineState): string | null {
    const fl = l.formulaLineId !== null ? formulaLineById.get(l.formulaLineId) : undefined
    if (!fl) return null
    if (fl.quantityMode === "Percentage") return `${roundQty(num(fl.percentage))}% of batch`
    if (coverage.fixedBase <= 0) return null
    const share = num(fl.fixedQuantity) / coverage.fixedBase
    // In a mixed formula the fixed lines share whatever the percentages leave
    // over, so "parts" would misread — quote the effective share instead.
    return coverage.shape === "mixed"
      ? `${roundQty(share * (100 - coverage.pctTotal))}% of batch`
      : `${roundQty(num(fl.fixedQuantity))} of ${roundQty(coverage.fixedBase)} parts`
  }

  // Totals / previews
  const lineCalcs = useMemo(() => lines.map((l) => ({ l, d: lineDerived(l) })), [lines])
  const costCalcs = useMemo(() => costs.map((c) => ({ c, d: costDerived(c) })), [costs])
  const totalIngredientCost = useMemo(() => lineCalcs.reduce((s, x) => s + x.d.total, 0), [lineCalcs])
  const totalAdditionalCost = useMemo(() => costCalcs.reduce((s, x) => s + x.d.amount, 0), [costCalcs])
  const totalProductionCost = totalIngredientCost + totalAdditionalCost
  const totalIngredientQty = useMemo(() => lineCalcs.reduce((s, x) => s + (x.l.ingredientItemId ? x.d.qty : 0), 0), [lineCalcs])
  const hasOverrides = useMemo(() => lines.some((l) => l.formulaLineId !== null && l.qtyOverridden), [lines])
  const qtyProduced = num(header.quantityProduced)
  const costPerUnit = qtyProduced > 0 ? totalProductionCost / qtyProduced : 0
  // Within half a percent of the batch is close enough — rounding, and a few
  // formulas legitimately run a little over or under.
  const ingredientsCoverBatch = qtyProduced <= 0 || Math.abs(totalIngredientQty - qtyProduced) <= qtyProduced * 0.005

  // Stock check. Measured against availableFromLots — the drawable purchase-lot
  // pool — because that is what posting actually consumes. It can be lower than
  // currentQuantity when stock was added by adjustment rather than by a
  // purchase, and posting fails on the pool, not on the headline figure.
  // Only the inventory portion can be short; bought-during-production
  // quantities are purchased with the batch.
  const shortages = useMemo(() => {
    const out: { name: string; unit: string; need: number; have: number; short: number; byAdjustment: number }[] = []
    for (const { l, d } of lineCalcs) {
      if (!l.ingredientItemId || d.invQty <= 0) continue
      const it = itemById.get(l.ingredientItemId)
      if (!it) continue
      const short = d.invQty - it.availableFromLots
      if (short > 0.001) {
        out.push({
          name: it.itemName,
          unit: l.unitOfMeasure || it.unitOfMeasure || "",
          need: roundQty(d.invQty),
          have: roundQty(it.availableFromLots),
          short: roundQty(short),
          // Stock on the item that has no lot behind it — the confusing part.
          byAdjustment: roundQty(Math.max(0, it.currentQuantity - it.availableFromLots)),
        })
      }
    }
    return out
  }, [lineCalcs, itemById])

  // The largest batch current stock can cover at this formula's ratios, and
  // which ingredient runs out first. Rows sourced by purchase aren't limited by
  // stock, and a hand-overridden row no longer follows the ratios, so both sit
  // this out.
  const stockLimit = useMemo(() => {
    if (!appliedFormula?.lines?.length) return null
    const factors = formulaUnitFactors(appliedFormula.lines)
    let limit = Infinity
    let by = ""
    for (const l of lines) {
      if (l.formulaLineId === null || l.qtyOverridden || l.sourceType !== "FromInventory") continue
      const f = factors.get(l.formulaLineId)
      const it = l.ingredientItemId ? itemById.get(l.ingredientItemId) : undefined
      if (!f || f <= 0 || !it) continue
      const max = it.availableFromLots / f
      if (max < limit) { limit = max; by = it.itemName }
    }
    // Floor, so the suggested quantity can never round back into a shortfall.
    return Number.isFinite(limit) ? { max: Math.floor(limit * 1000) / 1000, by } : null
  }, [appliedFormula, lines, itemById])

  // The distribution itself: whenever the quantity to produce (or the formula)
  // changes, redistribute the ingredients by ratio. Patches quantity only —
  // source, unit cost, supplier and payment details on the row are untouched,
  // and rows the farmer typed a quantity into keep their number.
  useEffect(() => {
    if (!appliedFormula?.lines?.length) return
    const required = scaleFormulaLines(appliedFormula.lines, qtyProduced)
    setLines((ls) => {
      let changed = false
      const next = ls.map((l) => {
        if (l.formulaLineId === null || l.qtyOverridden) return l
        const want = required.get(l.formulaLineId)
        if (want === undefined) return l
        const text = want > 0 ? String(want) : ""
        if (text === l.quantityUsed) return l
        changed = true
        return { ...l, quantityUsed: text, ...splitMixed(l, want) }
      })
      return changed ? next : ls
    })
  }, [appliedFormula, qtyProduced])

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
      if (d.hasPurchase && d.purUnit <= 0) return "Enter the purchased unit cost, or the line cost, for bought / mixed ingredient lines."
      if (l.paymentStatus === "Partial" && num(l.amountPaid) > d.purCost) return "Amount paid cannot exceed the purchased cost."
    }
    for (const { c, d } of costCalcs) {
      if (d.amount < 0) return "Additional cost amounts cannot be negative."
      if (c.paymentStatus === "Partial" && num(c.amountPaid) > d.amount) return "Amount paid cannot exceed the cost amount."
    }
    return null
  }

  const [posting, setPosting] = useState(false)
  const [shortStockBlocked, setShortStockBlocked] = useState(false)

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
            // Always the resolved per-unit figures — the line has no total
            // column. Rounded to DECIMAL(18,4) so client and server agree.
            inventoryUnitCost: Number(x.d.invUnit.toFixed(4)),
            purchasedUnitCost: Number(x.d.purUnit.toFixed(4)),
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

  // A short batch can't be posted at all: the draw goes through the shared
  // spPoultryRawMaterialItem_ConsumeBatches, which rejects it. Explain that here
  // rather than letting the server return a raw error mid-post.
  function requestPost() {
    const err = validate()
    if (err) { toast({ title: err, variant: "destructive" }); return }
    if (shortages.length) { setShortStockBlocked(true); return }
    void saveAndPost()
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
      toast({ title: "Failed to post batch", description: readableError(e), variant: "destructive" })
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
        <FormField label="Quantity produced *" hint={appliedFormula ? `Ingredients redistribute from ${appliedFormula.formulaName} as you type` : undefined}>
          <NumberInput min={0} step="0.001" value={header.quantityProduced} onChange={(e) => setHeader({ ...header, quantityProduced: e.target.value })} />
        </FormField>
        <FormField label="Output unit" hint={outputUnitSource}>
          <Input value={header.outputUnit} readOnly disabled className="bg-slate-50 text-slate-600" placeholder="—" />
        </FormField>
        <FormField label="Batch number" hint="Auto-generated if left blank"><Input value={header.batchNumber} onChange={(e) => setHeader({ ...header, batchNumber: e.target.value })} placeholder="FP-2026-0001" /></FormField>
        <FormField label="Notes" full><Textarea rows={2} value={header.notes} onChange={(e) => setHeader({ ...header, notes: e.target.value })} /></FormField>
      </FormSection>

      {/* Section 2 — Ingredient breakdown */}
      <FormSection title="Ingredient breakdown" color="emerald" columns={1}>
        <div className="space-y-3">
          {lineCalcs.map(({ l, d }) => {
            const it = l.ingredientItemId ? itemById.get(l.ingredientItemId) : undefined
            const shortBy = it && d.invQty > it.availableFromLots ? roundQty(d.invQty - it.availableFromLots) : 0
            // A From-Inventory line's quantity is whatever the formula worked
            // out — change the batch quantity to move it. Hand-added lines have
            // no formula behind them, so they stay editable or they'd be unusable.
            const qtyLocked = l.sourceType === "FromInventory" && l.formulaLineId !== null
            return (
              <div key={l.key} className={cn("rounded-lg border p-3 bg-white space-y-2", shortBy > 0 ? "border-red-300" : "border-slate-200")}>
                <div className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-end">
                  <div className="sm:col-span-4">
                    <label className="text-xs text-slate-500">Ingredient</label>
                    <Select value={l.ingredientItemId ? String(l.ingredientItemId) : ""} onValueChange={(v) => pickIngredient(l.key, Number(v))}>
                      <SelectTrigger><SelectValue placeholder="Pick ingredient" /></SelectTrigger>
                      <SelectContent>{ingredientItems.map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div className="sm:col-span-2">
                    <label className="text-xs text-slate-500">Source</label>
                    <Select value={l.sourceType} onValueChange={(v) => setLine(l.key, { sourceType: v as FeedProductionSourceType })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{SOURCE_TYPES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div className="sm:col-span-2">
                    <label className="text-xs text-slate-500">Qty used{l.unitOfMeasure ? ` (${l.unitOfMeasure})` : ""}</label>
                    <NumberInput
                      min={0} step="0.001" value={l.quantityUsed}
                      readOnly={qtyLocked} disabled={qtyLocked}
                      className={cn(qtyLocked && "bg-slate-50 text-slate-600")}
                      onChange={(e) => setLine(l.key, { quantityUsed: e.target.value, qtyOverridden: l.formulaLineId !== null })}
                    />
                    {qtyLocked ? (
                      <div className="text-[11px] text-slate-400 mt-0.5">{formulaShareOf(l) ?? "Set by the formula"}</div>
                    ) : l.qtyOverridden ? (
                      <div className="text-[11px] text-amber-600 mt-0.5">
                        ✎ edited —{" "}
                        <button type="button" className="underline hover:text-amber-700" onClick={() => setLine(l.key, { qtyOverridden: false })}>reset</button>
                      </div>
                    ) : formulaShareOf(l) ? (
                      <div className="text-[11px] text-slate-400 mt-0.5">{formulaShareOf(l)}</div>
                    ) : null}
                  </div>
                  <div className="sm:col-span-3">
                    {d.hasPurchase ? (
                      <>
                        <label className="text-xs text-slate-500">Purchased cost *</label>
                        <NumberInput
                          min={0} step="0.01"
                          value={l.purchasedCostMode === "Total" ? l.purchasedTotalCost : numStr(d.purCost, 2)}
                          onChange={(e) => setLine(l.key, { purchasedTotalCost: e.target.value, purchasedCostMode: "Total" })}
                        />
                        <div className="text-[11px] text-slate-400 mt-0.5">
                          {d.purQty > 0
                            ? `${gh(d.purUnit)}/unit${l.sourceType === "MixedSource" ? " · purchased part only" : ""}`
                            : "Enter the quantity first"}
                        </div>
                      </>
                    ) : (
                      <>
                        <label className="text-xs text-slate-500">Cost from stock</label>
                        <div className="h-9 flex items-center font-semibold tabular-nums text-slate-800">{gh(d.total)}</div>
                        <div className="text-[11px] text-slate-400 mt-0.5">{gh(d.unit)}/unit — priced from stock lots at posting</div>
                      </>
                    )}
                  </div>
                  <div className="sm:col-span-1 flex sm:justify-end">
                    <Button variant="ghost" size="sm" onClick={() => removeLine(l.key)} disabled={lines.length <= 1}><Trash2 className="w-4 h-4 text-red-600" /></Button>
                  </div>
                </div>

                {/* Stock availability — the figure that decides whether it posts. */}
                {it && (
                  <div className={cn("text-[11px]", shortBy > 0 ? "text-red-600 font-medium" : "text-slate-400")}>
                    {shortBy > 0
                      ? `Short ${shortBy.toLocaleString()} — only ${it.availableFromLots.toLocaleString()} of ${it.itemName} available to draw`
                      : `Available: ${it.availableFromLots.toLocaleString()}${l.unitOfMeasure ? ` ${l.unitOfMeasure}` : ""}`}
                  </div>
                )}

                {/* Mixed-source split */}
                {l.sourceType === "MixedSource" && (
                  <div className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-start">
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">From inventory qty</label>
                      <NumberInput min={0} step="0.001" value={l.inventoryQuantityUsed} onChange={(e) => setLine(l.key, { inventoryQuantityUsed: e.target.value })} />
                      <div className="text-[11px] text-slate-400 mt-0.5">{gh(d.invCost)} at {gh(d.invUnit)}/unit</div>
                    </div>
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">Purchased qty</label>
                      <NumberInput min={0} step="0.001" value={l.purchasedQuantityUsed} onChange={(e) => setLine(l.key, { purchasedQuantityUsed: e.target.value })} />
                    </div>
                    <div className="sm:col-span-6">
                      {!d.mixedBalanced && (
                        <div className="text-[11px] text-amber-600 pt-5">Inventory + purchased must equal {d.qty || "qty used"}</div>
                      )}
                    </div>
                  </div>
                )}

                {/* Purchased portion (bought + mixed) */}
                {d.hasPurchase && (
                  <div className="rounded-md bg-slate-50 border border-slate-200 p-2.5 grid grid-cols-1 sm:grid-cols-12 gap-2 items-start">
                    <div className="sm:col-span-3">
                      <label className="text-xs text-slate-500">Purchased unit cost *</label>
                      <NumberInput
                        min={0} step="0.0001"
                        value={l.purchasedCostMode === "Unit" ? l.purchasedUnitCost : numStr(d.purUnit, 4)}
                        onChange={(e) => setLine(l.key, { purchasedUnitCost: e.target.value, purchasedCostMode: "Unit" })}
                      />
                      <div className="text-[11px] text-slate-400 mt-0.5">
                        {l.purchasedCostMode === "Total" ? "From the purchased cost" : "or type the purchased cost above"}
                      </div>
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
                      <label className="text-xs text-slate-500">Payable</label>
                      <div className={cn("h-9 flex items-center justify-end font-medium tabular-nums", d.payable > 0 ? "text-red-600" : "text-slate-400")}>{gh(d.payable)}</div>
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
                  </div>
                )}
              </div>
            )
          })}
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="outline" size="sm" onClick={addLine}><Plus className="w-4 h-4 mr-1" /> Add ingredient</Button>
            {appliedFormula && (
              <Button variant="ghost" size="sm" onClick={resetToFormula} disabled={!hasOverrides} title={`Discard hand-edited quantities and follow ${appliedFormula.formulaName} again`}>
                <RefreshCw className="w-4 h-4 mr-1" /> Reset to {appliedFormula.formulaName}
              </Button>
            )}
          </div>

          {/* Can stock actually cover this batch? */}
          {shortages.length > 0 && (
            <div className="text-xs rounded-md border border-red-300 bg-red-50 px-3 py-2 text-red-800 space-y-1">
              <div className="font-semibold">
                Not enough stock for {shortages.length} ingredient{shortages.length === 1 ? "" : "s"}
              </div>
              {shortages.map((s) => (
                <div key={s.name} className="tabular-nums">
                  {s.name} — need {s.need.toLocaleString()}, available {s.have.toLocaleString()}
                  <span className="font-semibold"> (short {s.short.toLocaleString()}{s.unit ? ` ${s.unit}` : ""})</span>
                </div>
              ))}
              <div className="text-red-700">
                Reduce the quantity produced, or set the short lines to <span className="font-medium">Bought During Production</span> / <span className="font-medium">Mixed Source</span>. This batch can&apos;t be posted until it fits.
              </div>
              {shortages.some((s) => s.byAdjustment > 0) && (
                <div className="text-red-700 border-t border-red-200 pt-1">
                  Some of this stock was added by a <span className="font-medium">stock adjustment</span> rather than a purchase, so there is no batch to draw it from
                  {shortages.filter((s) => s.byAdjustment > 0).map((s) => ` (${s.name}: ${s.byAdjustment.toLocaleString()})`).join(", ")}. Record it as a purchase to make it usable.
                </div>
              )}
            </div>
          )}

          {stockLimit && stockLimit.by && qtyProduced > stockLimit.max && (
            <div className="text-xs rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-amber-800 flex flex-wrap items-center gap-2">
              <span>
                Stock covers about <span className="font-semibold tabular-nums">{stockLimit.max.toLocaleString()}</span>
                {header.outputUnit ? ` ${header.outputUnit}` : ""} with this formula — limited by <span className="font-medium">{stockLimit.by}</span>.
              </span>
              {stockLimit.max > 0 && (
                <Button variant="outline" size="sm" className="h-6 px-2 text-xs" onClick={() => setHeader((h) => ({ ...h, quantityProduced: String(stockLimit.max) }))}>
                  Use {stockLimit.max.toLocaleString()}
                </Button>
              )}
            </div>
          )}

          {/* Does the formula actually fill the batch? */}
          {appliedFormula && qtyProduced > 0 && (
            <div className={cn("text-xs rounded-md border px-3 py-2", ingredientsCoverBatch ? "border-slate-200 bg-slate-50 text-slate-600" : "border-amber-300 bg-amber-50 text-amber-800")}>
              Ingredients total <span className="font-semibold tabular-nums">{roundQty(totalIngredientQty).toLocaleString()}</span> of{" "}
              <span className="font-semibold tabular-nums">{qtyProduced.toLocaleString()}</span>
              {header.outputUnit ? ` ${header.outputUnit}` : ""} produced ({((totalIngredientQty / qtyProduced) * 100).toFixed(1)}%)
              {!ingredientsCoverBatch && (
                <> — check <span className="font-medium">{appliedFormula.formulaName}</span>
                  {coverage.shape !== "fixed" && Math.abs(coverage.pctTotal - 100) > 0.01 ? `: its percentages total ${roundQty(coverage.pctTotal)}%, not 100%.` : "."}
                </>
              )}
            </div>
          )}
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
          <Button onClick={requestPost} disabled={saving || posting}>
            {posting ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Posting…</> : <><CheckCircle2 className="w-4 h-4 mr-1" /> Save &amp; Post</>}
          </Button>
        )}
      </div>

      {/* A short batch cannot be posted — explain what to do instead. */}
      <AlertDialog open={shortStockBlocked} onOpenChange={(open) => { if (!open) setShortStockBlocked(false) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Not enough ingredient stock to post</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-3">
                <div>This batch needs more than these ingredients have available to draw:</div>
                <div className="rounded-md border border-red-200 bg-red-50 p-2 space-y-1">
                  {shortages.map((s) => (
                    <div key={s.name} className="flex justify-between gap-3 text-sm tabular-nums text-red-800">
                      <span className="font-medium">{s.name}</span>
                      <span>needs {s.need.toLocaleString()}, only {s.have.toLocaleString()}{s.unit ? ` ${s.unit}` : ""} available</span>
                    </div>
                  ))}
                </div>
                <div className="space-y-1">
                  <div className="font-medium text-slate-700">What you can do:</div>
                  <ul className="list-disc pl-5 space-y-0.5">
                    <li>Lower the quantity produced{stockLimit && stockLimit.max > 0 ? ` — stock covers about ${stockLimit.max.toLocaleString()}` : ""}.</li>
                    <li>Set the short ingredients to <span className="font-medium">Bought During Production</span> so they&apos;re purchased with the batch.</li>
                    {shortages.some((s) => s.byAdjustment > 0) && (
                      <li>Record a <span className="font-medium">purchase</span> for stock that was added by adjustment — adjusted stock has no batch to draw from.</li>
                    )}
                  </ul>
                </div>
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Close</AlertDialogCancel>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
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

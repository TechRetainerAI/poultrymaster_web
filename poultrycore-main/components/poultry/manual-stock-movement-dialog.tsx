"use client"

// 373: the Stock page's "New movement". Every movement entered by hand goes
// through one server call that checks batch -> flock, the effective date and the
// reason, and posts to whichever stock owns the item:
//   Birds          the flock's count (its latest production record), never a
//                  bare ledger row; Historical Mortality also fills Dead Birds
//   Products       the stock ledger (eggs, Broken Eggs, Dead Birds, others)
//   Raw materials  the item's stock, dated to the effective date
// The "now -> after" figures come from the server's preview; posting checks again.

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import {
  listPoultryBirdAdjustmentOptions, previewPoultryManualMovement, postPoultryManualMovement,
  MANUAL_MOVEMENT_REASONS,
  type PoultryProduct, type PoultryRawMaterialItem, type PoultryBirdAdjustmentOption, type PoultryManualMovementPreview,
} from "@/lib/api/poultry-inventory"

// Positive = increase, negative = decrease. 'Production' and 'Sale' stay with
// the modules that own them (see the note on the Stock page).
export const MANUAL_MOVEMENTS: { value: string; sign: 1 | -1 }[] = [
  { value: "Increase", sign: 1 }, { value: "Adjustment", sign: 1 },
  { value: "Decrease", sign: -1 }, { value: "Damage/Loss", sign: -1 },
]

const UNPLACED = "unplaced"
const NONE = "none"
const isBirdProduct = (p: PoultryProduct) => (!!p.isBirdProduct || p.name === "Birds") && p.name !== "Dead Birds"

type Kind = "birds" | "product" | "raw"

/** The reasons that fit the item and direction (the server applies the same rules). */
function reasonsFor(kind: Kind, sign: 1 | -1, role: string | null, isEgg: boolean): string[] {
  return MANUAL_MOVEMENT_REASONS.filter((r) => {
    switch (r) {
      case "Historical Mortality": return (kind === "birds" && sign < 0) || (role === "DeadBirds" && sign > 0)
      case "Cull": return kind === "birds" && sign < 0
      case "Opening Bird Count": return kind === "birds" && sign > 0
      case "Opening Inventory": return kind !== "birds" && sign > 0
      case "Disposal": return kind !== "birds" && sign < 0
      case "Unrecorded Breakage": return (isEgg && sign < 0) || (role === "BrokenEggs" && sign > 0)
      default: return true
    }
  })
}

function localToday(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}
function newRequestKey(): string {
  try { return crypto.randomUUID() } catch { return `msm-${Date.now()}-${Math.random().toString(36).slice(2)}` }
}
const fmtN = (n: number | null | undefined) => (n == null ? "—" : Number(n).toLocaleString(undefined, { maximumFractionDigits: 3 }))

const EMPTY = {
  target: "", movementType: "Increase", quantity: 0, unitCost: 0, note: "",
  batchId: "", flockId: "", effectiveDate: "", reason: "", disposition: "Keep" as "Keep" | "Disposed",
}

export function ManualStockMovementDialog({
  open, onOpenChange, products, rawItems, onSaved,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  products: PoultryProduct[]
  rawItems: PoultryRawMaterialItem[]
  onSaved: () => void
}) {
  const { toast } = useToast()
  const [form, setForm] = useState(EMPTY)
  const [saving, setSaving] = useState(false)
  const [requestKey, setRequestKey] = useState(newRequestKey)
  const [options, setOptions] = useState<PoultryBirdAdjustmentOption[] | null>(null)
  const [preview, setPreview] = useState<PoultryManualMovementPreview | null>(null)

  // A fresh form (and request key) each time it opens.
  useEffect(() => {
    if (!open) return
    setForm({ ...EMPTY, effectiveDate: localToday() })
    setRequestKey(newRequestKey())
    setPreview(null)
    listPoultryBirdAdjustmentOptions()
      .then(setOptions)
      .catch((e: any) => toast({ title: "Could not load batches and flocks", description: e?.message, variant: "destructive" }))
  }, [open, toast])

  const [tKind, tId] = form.target.split(":")
  const product = tKind === "p" ? products.find((p) => p.poultryProductId === Number(tId)) ?? null : null
  const kind: Kind | null = !form.target ? null : tKind === "r" ? "raw" : product && isBirdProduct(product) ? "birds" : "product"
  const sign = MANUAL_MOVEMENTS.find((m) => m.value === form.movementType)?.sign ?? 1
  const qty = Math.abs(Number(form.quantity) || 0)
  const role = preview?.systemRole ?? (product?.name === "Broken Eggs" ? "BrokenEggs" : product?.name === "Dead Birds" ? "DeadBirds" : null)
  const isEgg = preview?.isEgg ?? false

  const batches = useMemo(() => {
    const seen = new Map<number, PoultryBirdAdjustmentOption>()
    for (const o of options ?? []) if (!seen.has(o.batchId)) seen.set(o.batchId, o)
    return Array.from(seen.values())
  }, [options])
  const flocks = useMemo(
    () => (options ?? []).filter((o) => o.flockId != null && (!form.batchId || form.batchId === NONE || String(o.batchId) === form.batchId)),
    [options, form.batchId])
  const pickedBatch = batches.find((b) => String(b.batchId) === form.batchId) ?? null
  const pickedFlock = (options ?? []).find((o) => o.flockId != null && String(o.flockId) === form.flockId) ?? null
  const flockIdNum = form.flockId && form.flockId !== UNPLACED && form.flockId !== NONE ? Number(form.flockId) : null
  const batchIdNum = form.batchId && form.batchId !== NONE ? Number(form.batchId) : null

  const reasons = kind ? reasonsFor(kind, sign, role, isEgg) : []
  // A reason that no longer fits (item or direction changed) is cleared.
  useEffect(() => {
    if (form.reason && kind && !reasons.includes(form.reason)) setForm((f) => ({ ...f, reason: "" }))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [form.reason, kind, sign, role, isEgg])

  // The server's figures for what is picked now.
  useEffect(() => {
    if (!open || !kind) { setPreview(null); return }
    let cancelled = false
    previewPoultryManualMovement({
      productId: kind === "raw" ? null : Number(tId),
      rawItemId: kind === "raw" ? Number(tId) : null,
      batchId: form.flockId === UNPLACED ? batchIdNum : null,
      flockId: flockIdNum,
    })
      .then((p) => { if (!cancelled) setPreview(p) })
      .catch(() => { if (!cancelled) setPreview(null) })
    return () => { cancelled = true }
  }, [open, kind, tId, form.flockId, batchIdNum, flockIdNum])

  const maxDate = preview?.businessDate ?? localToday()
  const histMortality = kind === "birds" && form.reason === "Historical Mortality"
  const signed = sign * qty

  // ------------------------------------------------------------ the impact
  const impact: { label: string; now: number | null; after: number | null; bad?: boolean }[] = []
  if (preview && kind && qty > 0) {
    if (kind === "birds") {
      const here = form.flockId === UNPLACED ? preview.unplacedBirds : preview.flockLiveBirds
      if (form.flockId) impact.push({
        label: form.flockId === UNPLACED ? `Batch ${pickedBatch?.batchCode ?? ""} birds not in a flock` : `${pickedFlock?.flockName ?? "Flock"} birds`,
        now: here, after: here == null ? null : here + signed, bad: here != null && here + signed < 0,
      })
      if (form.flockId !== UNPLACED) impact.push({ label: "Farm live birds", now: preview.farmLiveBirds, after: preview.farmLiveBirds + signed })
      if (histMortality) impact.push({
        label: form.disposition === "Keep" ? "Dead Birds on hand" : "Dead Birds on hand (generated and disposed)",
        now: preview.deadBirdsOnHand, after: preview.deadBirdsOnHand + (form.disposition === "Keep" ? qty : 0),
      })
    } else {
      const now = preview.itemOnHand ?? 0
      impact.push({ label: `${kind === "raw" ? rawItems.find((i) => i.poultryRawMaterialItemId === Number(tId))?.itemName ?? "Item" : product?.name ?? "Item"} on hand`,
        now, after: now + signed, bad: (role != null || kind === "raw") && now + signed < 0 })
      if (form.reason === "Unrecorded Breakage" && isEgg && sign < 0) {
        impact.push({ label: "Broken Eggs on hand", now: preview.brokenEggsOnHand, after: preview.brokenEggsOnHand + qty })
      }
    }
  }

  async function save() {
    if (!kind) { toast({ title: "Pick an item", variant: "destructive" }); return }
    if (qty <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    if (!form.reason) { toast({ title: "Choose the reason", variant: "destructive" }); return }
    if (!form.effectiveDate) { toast({ title: "Enter the effective date", variant: "destructive" }); return }
    if (form.effectiveDate > maxDate) { toast({ title: "The effective date is in the future", variant: "destructive" }); return }
    if (form.reason === "Other" && !form.note.trim()) { toast({ title: "Say what happened", description: "Reason \"Other\" needs a note.", variant: "destructive" }); return }
    if (kind === "birds") {
      if (!batchIdNum) { toast({ title: "Choose the batch", variant: "destructive" }); return }
      if (!form.flockId) { toast({ title: "Choose the flock", description: "Or \"Not placed in a flock\" for the batch's birds that are not in any flock yet.", variant: "destructive" }); return }
      if (!Number.isInteger(qty)) { toast({ title: "Birds are whole numbers", variant: "destructive" }); return }
    }
    const bad = impact.find((i) => i.bad)
    if (bad) { toast({ title: "Not enough stock", description: `${bad.label}: only ${fmtN(bad.now)}.`, variant: "destructive" }); return }

    setSaving(true)
    try {
      const res = await postPoultryManualMovement({
        poultryProductId: kind === "raw" ? null : Number(tId),
        rawMaterialItemId: kind === "raw" ? Number(tId) : null,
        movementType: form.movementType,
        quantity: qty,
        unitCost: kind === "birds" ? null : form.unitCost || null,
        batchId: kind === "raw" ? null : batchIdNum,
        flockId: kind === "raw" ? null : flockIdNum,
        effectiveDate: form.effectiveDate,
        reason: form.reason,
        disposition: histMortality ? form.disposition : null,
        note: form.note.trim() || null,
        requestKey,
      })
      toast({ title: `${res.movementNo} posted`, description: res.repeated ? "This movement was already saved." : undefined })
      onOpenChange(false)
      onSaved()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>New stock movement</DialogTitle></DialogHeader>
        <FormSection title="Movement" color="blue">
          <FormField label="Item *" full>
            <Select value={form.target} onValueChange={(v) => setForm({ ...form, target: v, batchId: "", flockId: "", reason: "" })}>
              <SelectTrigger><SelectValue placeholder="Pick a finished product, raw material or supply" /></SelectTrigger>
              <SelectContent>
                {products.filter((p) => p.isActive).length > 0 && (
                  <SelectGroup>
                    <SelectLabel>Finished products</SelectLabel>
                    {products.filter((p) => p.isActive).map((p) => <SelectItem key={`p${p.poultryProductId}`} value={`p:${p.poultryProductId}`}>{p.name}</SelectItem>)}
                  </SelectGroup>
                )}
                {rawItems.filter((i) => i.isActive).length > 0 && (
                  <SelectGroup>
                    <SelectLabel>Raw materials &amp; supplies</SelectLabel>
                    {rawItems.filter((i) => i.isActive).map((i) => (
                      <SelectItem key={`r${i.poultryRawMaterialItemId}`} value={`r:${i.poultryRawMaterialItemId}`}>
                        {i.itemName}{i.category ? ` — ${i.category}` : ""}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                )}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Movement type *">
            <Select value={form.movementType} onValueChange={(v) => setForm({ ...form, movementType: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{MANUAL_MOVEMENTS.map((m) => <SelectItem key={m.value} value={m.value}>{m.value}</SelectItem>)}</SelectContent>
            </Select>
          </FormField>
          <FormField label="Reason *">
            <Select value={form.reason} onValueChange={(v) => setForm({ ...form, reason: v })} disabled={!kind}>
              <SelectTrigger><SelectValue placeholder={kind ? "Choose the reason" : "Pick the item first"} /></SelectTrigger>
              <SelectContent>{reasons.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
            </Select>
          </FormField>
          <FormField label={kind === "birds" ? "Birds *" : "Quantity *"} hint="Always positive; the movement type sets the direction.">
            <NumberInput min={0} step={kind === "birds" ? "1" : "0.001"} value={form.quantity} onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) || 0 })} />
          </FormField>
          {kind !== "birds"
            ? <FormField label="Unit cost / value"><NumberInput min={0} step="0.01" value={form.unitCost} onChange={(e) => setForm({ ...form, unitCost: Number(e.target.value) || 0 })} /></FormField>
            : <div />}

          {kind && kind !== "raw" && (
            <>
              <FormField label={kind === "birds" ? "Batch *" : "Batch"} hint={kind === "birds" ? "Birds are counted per flock." : "Optional: where this stock came from."}>
                <Select value={form.batchId} onValueChange={(v) => setForm({ ...form, batchId: v, flockId: "" })}>
                  <SelectTrigger><SelectValue placeholder={options ? (kind === "birds" ? "Choose the batch" : "No batch") : "Loading batches..."} /></SelectTrigger>
                  <SelectContent>
                    {kind !== "birds" && <SelectItem value={NONE}>No batch</SelectItem>}
                    {batches.map((b) => (
                      <SelectItem key={b.batchId} value={String(b.batchId)}>{b.batchCode}{b.batchName ? ` — ${b.batchName}` : ""}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label={kind === "birds" ? "Flock *" : "Flock"}>
                <Select
                  value={form.flockId}
                  onValueChange={(v) => {
                    // Picking a flock fills in its batch.
                    const f = (options ?? []).find((o) => String(o.flockId) === v)
                    setForm({ ...form, flockId: v, batchId: f ? String(f.batchId) : form.batchId })
                  }}
                  disabled={kind === "birds" && !batchIdNum}
                >
                  <SelectTrigger><SelectValue placeholder={kind === "birds" ? (batchIdNum ? "Choose the flock" : "Choose the batch first") : "No flock"} /></SelectTrigger>
                  <SelectContent>
                    {kind !== "birds" && <SelectItem value={NONE}>No flock</SelectItem>}
                    {flocks.map((f) => {
                      const why = kind === "birds" ? (f.isClosed ? "closed" : !f.hasProductionRecord ? "no production record yet" : null) : null
                      return (
                        <SelectItem key={f.flockId!} value={String(f.flockId)} disabled={!!why}>
                          {f.flockName}{kind === "birds" ? ` · ${why ?? `${(f.liveBirds ?? 0).toLocaleString()} birds`}` : ""}
                        </SelectItem>
                      )
                    })}
                    {kind === "birds" && pickedBatch && (
                      <SelectItem value={UNPLACED}>Not placed in a flock · {pickedBatch.unplacedBirds.toLocaleString()} birds</SelectItem>
                    )}
                  </SelectContent>
                </Select>
              </FormField>
            </>
          )}

          <FormField label="Effective date *" hint="When it happened, not when you are entering it.">
            <Input type="date" value={form.effectiveDate} max={maxDate} onChange={(e) => setForm({ ...form, effectiveDate: e.target.value })} />
          </FormField>
          {histMortality ? (
            <FormField label="Dead birds">
              <Select value={form.disposition} onValueChange={(v) => setForm({ ...form, disposition: v as "Keep" | "Disposed" })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Keep">Keep in Dead Bird inventory</SelectItem>
                  <SelectItem value="Disposed">Already disposed</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
          ) : <div />}
          <FormField label={form.reason === "Other" ? "Note *" : "Note"} full>
            <Input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} placeholder="Anything that explains it further" />
          </FormField>
        </FormSection>

        {impact.length > 0 && (
          <div className="rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-sm">
            <div className="mb-1 text-xs font-medium uppercase tracking-wide text-slate-500">Impact</div>
            {impact.map((i) => (
              <div key={i.label} className="flex justify-between gap-3">
                <span className="text-slate-600">{i.label}</span>
                <span className="tabular-nums">
                  {fmtN(i.now)} → <span className={i.bad ? "font-semibold text-red-600" : "font-semibold"}>{fmtN(i.after)}</span>
                </span>
              </div>
            ))}
            {kind === "birds" && form.flockId && form.flockId !== UNPLACED && (
              <p className="mt-1 text-xs text-slate-500">
                The flock&apos;s latest production record takes the corrected count. No production record is created and no day&apos;s deaths change.
              </p>
            )}
            {form.reason === "Unrecorded Breakage" && isEgg && sign < 0 && (
              <p className="mt-1 text-xs text-slate-500">The eggs are not lost: they move to Broken Eggs.</p>
            )}
          </div>
        )}

        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

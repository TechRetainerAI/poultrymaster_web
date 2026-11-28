"use client"

// The pharmacy part of the Products & Services form (migration 515). Shown only when the
// business's industry template is "Pharmacy": medicine details, the packs a medicine is sold
// in with a price each, and the batch number + expiry date of the opening stock.
// Saved with the product: products page -> saveMedicine (+ addBatch for opening stock).

import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Plus, Trash2, Save, Loader2 } from "lucide-react"
import { useEffect, useState } from "react"
import Link from "next/link"
import { useToast } from "@/hooks/use-toast"
import { getBatches, updateBatch, type Medicine, type MedicineClass, type MedicineInput, type PharmacyShopType, type ProductBatch } from "@/lib/api/generic-pharmacy"
import { DOSAGE_FORMS, MEDICINE_CLASSES, packProblems, sellBlockReason } from "@/lib/generic/pharmacy"

/** What a pharmacist sells by: offered first in the base-unit picker. */
export const PHARMACY_UNITS = ["tablet", "capsule", "caplet", "bottle", "tube", "sachet", "vial", "ampoule", "piece", "pack", "pair", "roll"]

/** Product categories a pharmacy uses (replaces the general shop list for a pharmacy). */
export const PHARMACY_CATEGORIES = [
  "Pain relief & fever", "Antibiotics", "Antimalarials", "Cough, cold & flu", "Vitamins & supplements",
  "Antacids & digestive", "Blood pressure & heart", "Diabetes", "Skin care & dermatology", "Eye & ear",
  "Mother & baby", "Family planning & sexual health", "Dewormers", "Herbal medicines",
  "First aid & medical supplies", "Medical devices", "Personal care", "Other",
]

export type MedicineForm = {
  genericName: string; strength: string; dosageForm: string; medicineClass: MedicineClass
  fdaRegNo: string; manufacturer: string; storageNote: string; isControlled: boolean
  packs: { packName: string; unitsPerPack: string; sellingPrice: string }[]
  /** Opening stock: its batch no. and expiry (new medicine only). */
  openingBatchNumber: string
  openingExpiryDate: string
}

export const EMPTY_MEDICINE_FORM: MedicineForm = {
  genericName: "", strength: "", dosageForm: "", medicineClass: "C", fdaRegNo: "", manufacturer: "",
  storageNote: "", isControlled: false, packs: [], openingBatchNumber: "", openingExpiryDate: "",
}

export function medicineFormFrom(m: Medicine | undefined): MedicineForm {
  if (!m) return EMPTY_MEDICINE_FORM
  return {
    genericName: m.genericName ?? "", strength: m.strength ?? "", dosageForm: m.dosageForm ?? "",
    medicineClass: m.medicineClass ?? "C", fdaRegNo: m.fdaRegNo ?? "", manufacturer: m.manufacturer ?? "",
    storageNote: m.storageNote ?? "", isControlled: !!m.isControlled,
    packs: (m.packs ?? []).map((p) => ({ packName: p.packName, unitsPerPack: String(p.unitsPerPack), sellingPrice: String(p.sellingPrice) })),
    openingBatchNumber: "", openingExpiryDate: "",
  }
}

export function medicineInputFrom(f: MedicineForm): MedicineInput {
  return {
    genericName: f.genericName.trim() || null, strength: f.strength.trim() || null, dosageForm: f.dosageForm || null,
    medicineClass: f.medicineClass, fdaRegNo: f.fdaRegNo.trim() || null, manufacturer: f.manufacturer.trim() || null,
    storageNote: f.storageNote.trim() || null, isControlled: f.isControlled,
    packs: f.packs.filter((p) => p.packName.trim()).map((p) => ({
      packName: p.packName.trim(), unitsPerPack: Number(p.unitsPerPack) || 0, sellingPrice: Number(p.sellingPrice) || 0,
    })),
  }
}

/** Problems to fix before saving (empty = fine). */
export function medicineFormProblems(f: MedicineForm, baseUnit: string): string[] {
  return packProblems(baseUnit || "unit", medicineInputFrom(f).packs)
}

const money = (n: number) => new Intl.NumberFormat(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export function PharmacyProductFields({ value, onChange, baseUnit, isNew, openingStock, shopType, productId }: {
  value: MedicineForm
  onChange: (patch: Partial<MedicineForm>) => void
  baseUnit: string
  isNew: boolean
  openingStock: number
  shopType: PharmacyShopType
  /** Set when editing: shows the batches on the shelf with their expiry. */
  productId?: number | null
}) {
  const unit = baseUnit || "unit"
  const classWarning = sellBlockReason(shopType, value.medicineClass)
  const setPack = (i: number, patch: Partial<MedicineForm["packs"][number]>) =>
    onChange({ packs: value.packs.map((p, k) => (k === i ? { ...p, ...patch } : p)) })

  return (
    <>
      <FormSection title="Medicine details" color="teal">
        <FormField label="Generic name" hint="The active ingredient, e.g. Paracetamol">
          <Input value={value.genericName} maxLength={200} placeholder="e.g. Paracetamol, Amoxicillin, Artemether/Lumefantrine"
            onChange={(e) => onChange({ genericName: e.target.value })} />
        </FormField>
        <FormField label="Strength">
          <Input value={value.strength} maxLength={80} placeholder="e.g. 500mg, 250mg/5ml, 20/120mg"
            onChange={(e) => onChange({ strength: e.target.value })} />
        </FormField>
        <FormField label="Form">
          <Select value={value.dosageForm || "__none"} onValueChange={(v) => onChange({ dosageForm: v === "__none" ? "" : v })}>
            <SelectTrigger><SelectValue placeholder="Tablet, syrup…" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__none">—</SelectItem>
              {DOSAGE_FORMS.map((d) => <SelectItem key={d} value={d}>{d}</SelectItem>)}
            </SelectContent>
          </Select>
        </FormField>
        <FormField label="Class *" hint={classWarning ?? MEDICINE_CLASSES.find((c) => c.value === value.medicineClass)?.hint}>
          <Select value={value.medicineClass} onValueChange={(v) => onChange({ medicineClass: v as MedicineClass })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {MEDICINE_CLASSES.map((c) => <SelectItem key={c.value} value={c.value}>{c.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </FormField>
        <FormField label="FDA Ghana registration no.">
          <Input value={value.fdaRegNo} maxLength={80} placeholder="e.g. FDA/SD.123-45678" onChange={(e) => onChange({ fdaRegNo: e.target.value })} />
        </FormField>
        <FormField label="Manufacturer">
          <Input value={value.manufacturer} maxLength={200} placeholder="e.g. Ernest Chemists, Kinapharma" onChange={(e) => onChange({ manufacturer: e.target.value })} />
        </FormField>
        <FormField label="Storage">
          <Input value={value.storageNote} maxLength={300} placeholder="e.g. Store below 25°C, keep in fridge (2–8°C)" onChange={(e) => onChange({ storageNote: e.target.value })} />
        </FormField>
        <FormField label="Controlled drug">
          <div className="flex items-center gap-3">
            <Switch id="med-controlled" checked={value.isControlled} onCheckedChange={(v) => onChange({ isControlled: v })} />
            <Label htmlFor="med-controlled" className="cursor-pointer text-sm text-slate-600">Listed on the controlled drugs report</Label>
          </div>
        </FormField>
      </FormSection>

      <FormSection title="Packs and prices" color="blue" columns={1}>
        <p className="text-xs text-slate-600">
          The selling price above is for <strong>one {unit}</strong>. Add the bigger packs you also sell, each with its own price.
          Stock is always counted in {unit}s, so selling a strip takes its {unit}s out of stock. Purchases offer these packs too.
        </p>
        {value.packs.map((p, i) => {
          const per = Number(p.unitsPerPack) > 0 ? (Number(p.sellingPrice) || 0) / Number(p.unitsPerPack) : null
          return (
            <div key={i} className="grid grid-cols-[1.2fr_1fr_1fr_auto] items-end gap-2">
              <div>
                <Label className="text-xs">Pack</Label>
                <Input value={p.packName} maxLength={50} placeholder="Strip, Card, Box, Pack" onChange={(e) => setPack(i, { packName: e.target.value })} />
              </div>
              <div>
                <Label className="text-xs">{unit}s in one</Label>
                <NumberInput min="0" step="1" value={p.unitsPerPack} placeholder="10" onChange={(e) => setPack(i, { unitsPerPack: e.target.value })} />
              </div>
              <div>
                <Label className="text-xs">Price of one</Label>
                <NumberInput min="0" step="0.01" value={p.sellingPrice} onChange={(e) => setPack(i, { sellingPrice: e.target.value })} />
                {per != null && <div className="text-[11px] text-slate-500">= {money(per)} per {unit}</div>}
              </div>
              <Button type="button" variant="ghost" size="sm" title="Remove pack" onClick={() => onChange({ packs: value.packs.filter((_, k) => k !== i) })}>
                <Trash2 className="h-4 w-4 text-red-500" />
              </Button>
            </div>
          )
        })}
        <div>
          <Button type="button" variant="outline" size="sm"
            onClick={() => onChange({ packs: [...value.packs, { packName: value.packs.length === 0 ? "Strip" : value.packs.length === 1 ? "Box" : "", unitsPerPack: "", sellingPrice: "" }] })}>
            <Plus className="h-3.5 w-3.5 mr-1" /> Add a pack (strip, box…)
          </Button>
        </div>
      </FormSection>

      {!isNew && productId != null && <ShelfBatches productId={productId} unit={unit} />}

      {isNew && (
        <FormSection title="Opening stock batch and expiry" color="rose">
          <FormField label="Batch no." hint="Printed on the pack, e.g. BN 23A114">
            <Input value={value.openingBatchNumber} maxLength={80} placeholder="e.g. 23A114" onChange={(e) => onChange({ openingBatchNumber: e.target.value })} />
          </FormField>
          <FormField label="Expiry date" hint={openingStock > 0 ? `For the ${openingStock} ${unit}s of opening stock` : "Enter the opening stock first"}>
            <Input type="date" value={value.openingExpiryDate} onChange={(e) => onChange({ openingExpiryDate: e.target.value })} />
          </FormField>
          <p className="text-xs text-slate-500 col-span-full">
            Each new delivery gets its own batch no. and expiry on the purchase. See them all in Pharmacy → Batches &amp; expiry.
          </p>
        </FormSection>
      )}
    </>
  )
}

/**
 * Edit form only: every batch of this medicine still on the shelf, with its batch no. and
 * expiry date editable in place (saved one batch at a time).
 */
function ShelfBatches({ productId, unit }: { productId: number; unit: string }) {
  const { toast } = useToast()
  const [rows, setRows] = useState<(ProductBatch & { _no: string; _exp: string })[] | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)

  useEffect(() => {
    let off = false
    getBatches(productId)
      .then((bs) => {
        if (off) return
        setRows(bs.filter((b) => b.quantityRemaining > 0).map((b) => ({
          ...b, _no: b.batchNumber ?? "", _exp: b.expiryDate ? String(b.expiryDate).slice(0, 10) : "",
        })))
      })
      .catch(() => { if (!off) setRows([]) })
    return () => { off = true }
  }, [productId])

  const save = async (b: NonNullable<typeof rows>[number]) => {
    setSavingId(b.genericProductBatchId)
    try {
      await updateBatch(b.genericProductBatchId, { batchNumber: b._no.trim() || null, expiryDate: b._exp || null, notes: b.notes ?? null })
      setRows((rs) => rs?.map((r) => r.genericProductBatchId === b.genericProductBatchId
        ? { ...r, batchNumber: b._no.trim() || null, expiryDate: b._exp || null } : r) ?? rs)
      toast({ title: "Batch saved", description: `Batch ${b._no.trim() || "(no number)"} expires ${b._exp || "(no date)"}.` })
    } catch (e: any) {
      toast({ title: "Could not save the batch", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSavingId(null) }
  }

  return (
    <FormSection title="Batches on the shelf and expiry" color="rose" columns={1}>
      <p className="text-xs text-slate-600">
        A medicine has one expiry date <strong>per batch</strong> (each delivery), not one for the product. Fix a batch no.
        or expiry here. New deliveries get their batch no. and expiry on the purchase.
      </p>
      {rows == null ? (
        <div className="text-xs text-slate-500 flex items-center gap-2"><Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading batches…</div>
      ) : rows.length === 0 ? (
        <div className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded p-2">
          No batch on the shelf has an expiry recorded yet. Label the stock already on the shelf in{" "}
          <Link className="underline" href={`/generic-batches?productId=${productId}`}>Pharmacy → Batches &amp; expiry</Link>.
        </div>
      ) : (
        rows.map((b) => {
          const changed = b._no !== (b.batchNumber ?? "") || b._exp !== (b.expiryDate ? String(b.expiryDate).slice(0, 10) : "")
          return (
            <div key={b.genericProductBatchId} className="grid grid-cols-[1fr_1fr_1fr_auto] items-end gap-2">
              <div>
                <Label className="text-xs">Batch no.</Label>
                <Input value={b._no} maxLength={80} placeholder="e.g. 23A114"
                  onChange={(e) => setRows((rs) => rs?.map((r) => r.genericProductBatchId === b.genericProductBatchId ? { ...r, _no: e.target.value } : r) ?? rs)} />
              </div>
              <div>
                <Label className="text-xs">Expiry date</Label>
                <Input type="date" value={b._exp}
                  onChange={(e) => setRows((rs) => rs?.map((r) => r.genericProductBatchId === b.genericProductBatchId ? { ...r, _exp: e.target.value } : r) ?? rs)} />
              </div>
              <div className="text-xs text-slate-600 pb-2">
                {b.quantityRemaining.toLocaleString(undefined, { maximumFractionDigits: 3 })} {unit}s left
                <div className="text-[11px] text-slate-400">received {String(b.receivedDate).slice(0, 10)}</div>
              </div>
              <Button type="button" size="sm" variant={changed ? "default" : "outline"} disabled={!changed || savingId === b.genericProductBatchId}
                title="Save this batch" onClick={() => save(b)}>
                {savingId === b.genericProductBatchId ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
              </Button>
            </div>
          )
        })
      )}
    </FormSection>
  )
}

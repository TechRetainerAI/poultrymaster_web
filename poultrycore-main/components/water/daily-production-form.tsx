"use client"

// Create / edit form for a Water Batch Production record (migration 193).
// Shared by /water-daily-production/new and /water-daily-production/[id]/edit.
//
// The record is deliberately INERT until an allocation is posted: nothing here
// touches stock, cash or finished goods.

import React, { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Checkbox } from "@/components/ui/checkbox"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Save, ArrowLeft, Plus, Trash2, Wand2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listWaterMachines, listWaterProducts, listWaterBoreholes, listWaterRawMaterialItems,
  getWaterProductionRecipe, createWaterDailyProduction, updateWaterDailyProduction,
  type WaterDailyProduction, type WaterDailyProductionMachine, type WaterDailyProductionMaterial,
  type WaterMachine, type WaterProduct, type WaterBorehole, type WaterRawMaterialItem,
  type WaterMachineSelectionType,
} from "@/lib/api/water"

const SHIFTS = ["Morning", "Afternoon", "Night", "FullDay"]
const num = (v: string | number | null | undefined) => (typeof v === "number" ? v : Number(v) || 0)
const round3 = (n: number) => Math.round(n * 1000) / 1000

type MaterialRow = WaterDailyProductionMaterial & { key: string }
const rid = () => Math.random().toString(36).slice(2)

export function WaterDailyProductionForm({ existing }: { existing?: WaterDailyProduction | null }) {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [machines, setMachines] = useState<WaterMachine[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [boreholes, setBoreholes] = useState<WaterBorehole[]>([])
  const [items, setItems] = useState<WaterRawMaterialItem[]>([])

  const [productionNumber, setProductionNumber] = useState(existing?.productionNumber ?? "")
  const [productionDate, setProductionDate] = useState(
    (existing?.productionDate ?? new Date().toISOString()).slice(0, 10))
  const [shift, setShift] = useState(existing?.shift ?? "FullDay")
  const [scope, setScope] = useState<WaterMachineSelectionType>(existing?.machineSelectionType ?? "AllMachines")
  const [productId, setProductId] = useState<number | null>(existing?.waterProductId ?? null)
  const [boreholeId, setBoreholeId] = useState<number | null>(existing?.waterBoreholeId ?? null)
  const [selectedMachineIds, setSelectedMachineIds] = useState<number[]>(
    (existing?.machines ?? []).map((m) => m.waterMachineId))

  const [bags, setBags] = useState(String(existing?.bagsProduced ?? ""))
  const [sachetsPerBag, setSachetsPerBag] = useState(String(existing?.sachetsPerBag ?? 30))
  const [loose, setLoose] = useState(String(existing?.looseSachetsProduced ?? ""))
  const [rejected, setRejected] = useState(String(existing?.rejectedSachets ?? ""))
  const [damaged, setDamaged] = useState(String(existing?.damagedBags ?? ""))
  const [rolls, setRolls] = useState(String(existing?.packagingRollsUsed ?? ""))
  const [litres, setLitres] = useState(existing?.estimatedWaterUsedLitres != null ? String(existing.estimatedWaterUsedLitres) : "")

  const [elec, setElec] = useState(String(existing?.electricityCost ?? ""))
  const [fuel, setFuel] = useState(String(existing?.fuelCost ?? ""))
  const [labor, setLabor] = useState(String(existing?.laborCost ?? ""))
  const [other, setOther] = useState(String(existing?.otherProductionCost ?? ""))
  const [notes, setNotes] = useState(existing?.notes ?? "")

  const [materials, setMaterials] = useState<MaterialRow[]>(
    (existing?.materials ?? []).map((m) => ({ ...m, key: rid() })))

  useEffect(() => {
    (async () => {
      setLoading(true)
      try {
        const [ms, ps, bs, its] = await Promise.all([
          listWaterMachines(), listWaterProducts(), listWaterBoreholes().catch(() => []), listWaterRawMaterialItems(),
        ])
        setMachines(ms); setProducts(ps); setBoreholes(bs); setItems(its)
        if (!existing && ps.length === 1) setProductId(ps[0].waterProductId)
      } catch (e: any) {
        toast({ title: "Failed to load form data", description: e?.message ?? String(e), variant: "destructive" })
      } finally {
        setLoading(false)
      }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const activeMachines = useMemo(() => machines.filter((m) => m.status === "Active"), [machines])
  const itemById = useMemo(() => new Map(items.map((i) => [i.waterRawMaterialItemId, i])), [items])

  // The machine set this day covers. 'AllMachines' is frozen at save time so a
  // machine going UnderMaintenance later doesn't silently change the scope.
  const scopedMachines: WaterDailyProductionMachine[] = useMemo(() => {
    const pick = scope === "AllMachines"
      ? activeMachines
      : machines.filter((m) => selectedMachineIds.includes(m.waterMachineId))
    return pick.map((m) => ({
      waterMachineId: m.waterMachineId,
      machineName: m.machineName,
      machineNumber: m.machineNumber ?? null,
      capacityPerHour: m.capacityPerHour ?? null,
      operatorStaffId: m.assignedOperatorStaffId ?? null,
    }))
  }, [scope, activeMachines, machines, selectedMachineIds])

  const totalCost = num(elec) + num(fuel) + num(labor) + num(other)
  const materialCost = materials.reduce((s, m) => s + m.quantityUsed * (Number(m.unitCost) || 0), 0)
  const goodBags = Math.max(0, num(bags) - num(damaged))

  function setMaterial(key: string, patch: Partial<MaterialRow>) {
    setMaterials((rows) => rows.map((r) => (r.key === key ? { ...r, ...patch } : r)))
  }
  const addMaterial = () => setMaterials((rows) => [...rows, {
    key: rid(), waterRawMaterialItemId: 0, quantityUsed: 0, itemName: null, unitOfMeasure: null,
    expectedQuantityUsed: null, unitCost: null,
  }])
  const removeMaterial = (key: string) => setMaterials((rows) => rows.filter((r) => r.key !== key))

  function pickMaterialItem(key: string, itemId: number) {
    const it = itemById.get(itemId)
    setMaterial(key, {
      waterRawMaterialItemId: itemId,
      itemName: it?.itemName ?? null,
      unitOfMeasure: it?.unitOfMeasure ?? null,
    })
  }

  // Seed the material lines from the product's recipe scaled to the day's bags.
  async function seedFromRecipe() {
    if (!productId) { toast({ title: "Pick the product first", variant: "destructive" }); return }
    const qty = num(bags)
    if (qty <= 0) { toast({ title: "Enter the bags produced first", variant: "destructive" }); return }
    try {
      const recipe = await getWaterProductionRecipe(productId)
      if (!recipe?.items?.length) {
        toast({ title: "No recipe for this product", description: "Set one up on the product page, or add materials by hand." })
        return
      }
      setMaterials(recipe.items.map((ri) => {
        const expected = round3(ri.quantityPerOutputUnit * qty * (1 + (ri.wasteAllowancePercent || 0) / 100))
        return {
          key: rid(),
          waterRawMaterialItemId: ri.waterRawMaterialItemId,
          itemName: ri.rawMaterialName ?? null,
          unitOfMeasure: ri.rawMaterialUnit ?? null,
          quantityUsed: expected,
          expectedQuantityUsed: expected,
          unitCost: ri.latestUnitCost ?? null,
        }
      }))
      toast({ title: "Materials seeded from the recipe", description: `Scaled to ${qty.toLocaleString()} bags. Adjust to what was actually used.` })
    } catch (e: any) {
      toast({ title: "Could not load the recipe", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  function validate(): string | null {
    if (!productId) return "Pick the product this batch produces."
    if (num(bags) <= 0) return "Bags produced must be greater than zero."
    if (num(damaged) > num(bags)) return "Damaged bags cannot exceed bags produced."
    if (!scopedMachines.length) return "This batch needs at least one machine."
    if (productionDate > new Date().toISOString().slice(0, 10)) return "Production date cannot be in the future."
    for (const m of materials) {
      if (m.waterRawMaterialItemId && m.quantityUsed < 0) return "Material quantities cannot be negative."
    }
    return null
  }

  async function save(status: "Draft" | "PendingAllocation") {
    const err = validate()
    if (err) { toast({ title: err, variant: "destructive" }); return }
    setSaving(true)
    try {
      const payload = {
        productionNumber: productionNumber || null,
        productionDate,
        shift,
        machineSelectionType: scope,
        waterProductId: productId!,
        waterBoreholeId: boreholeId,
        bagsProduced: num(bags),
        sachetsPerBag: num(sachetsPerBag) || 30,
        looseSachetsProduced: num(loose),
        rejectedSachets: num(rejected),
        damagedBags: num(damaged),
        packagingRollsUsed: num(rolls),
        estimatedWaterUsedLitres: litres === "" ? null : num(litres),
        electricityCost: num(elec),
        fuelCost: num(fuel),
        laborCost: num(labor),
        otherProductionCost: num(other),
        rawMaterialCost: materialCost,
        status,
        notes: notes || null,
        machines: scopedMachines,
        materials: materials
          .filter((m) => m.waterRawMaterialItemId > 0 && m.quantityUsed > 0)
          .map(({ key, ...m }) => m),
      }

      if (existing) {
        await updateWaterDailyProduction(existing.waterDailyProductionId, payload as any)
        toast({ title: "Batch production updated" })
        router.push(`/water-daily-production/${existing.waterDailyProductionId}`)
      } else {
        const saved = await createWaterDailyProduction(payload as any)
        toast({
          title: status === "Draft" ? "Draft saved" : "Batch production logged",
          description: status === "Draft" ? undefined : "Now allocate the batch across the machines.",
        })
        router.push(saved?.waterDailyProductionId
          ? `/water-daily-production/${saved.waterDailyProductionId}/allocate`
          : "/water-daily-production")
      }
    } catch (e: any) {
      toast({ title: "Failed to save", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="ghost" size="sm" onClick={() => router.push("/water-daily-production")}>
          <ArrowLeft className="w-4 h-4 mr-1" /> Back
        </Button>
        <h1 className="text-2xl font-bold">
          {existing ? `Edit ${existing.productionNumber || `batch #${existing.waterDailyProductionId}`}` : "Log Batch Production"}
        </h1>
      </div>

      <Card className="border-sky-200 bg-sky-50">
        <CardContent className="p-3 text-sm text-sky-900">
          <span className="font-semibold">Enter the batch totals only.</span>{" "}
          Record everything the factory produced and consumed, combined across every machine.
          This record does nothing on its own — stock, expenses and finished goods are only touched
          once you allocate the batch across machines and post it.
        </CardContent>
      </Card>

      <FormSection title="Batch & scope" color="blue">
        <FormField label="Production date *">
          <Input type="date" max={new Date().toISOString().slice(0, 10)}
                 value={productionDate} onChange={(e) => setProductionDate(e.target.value)} />
        </FormField>
        <FormField label="Document number" hint="Optional — used as the production number prefix">
          <Input value={productionNumber} onChange={(e) => setProductionNumber(e.target.value)} placeholder="DP-20260812-01" />
        </FormField>
        <FormField label="Shift">
          <Select value={shift} onValueChange={setShift}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>{SHIFTS.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
          </Select>
        </FormField>
        <FormField label="Product *">
          <Select value={productId ? String(productId) : ""} onValueChange={(v) => setProductId(Number(v))}>
            <SelectTrigger><SelectValue placeholder={products.length ? "Pick product" : "No products"} /></SelectTrigger>
            <SelectContent>
              {products.map((p) => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}
            </SelectContent>
          </Select>
        </FormField>
        <FormField label="Borehole">
          <Select value={boreholeId ? String(boreholeId) : "none"}
                  onValueChange={(v) => setBoreholeId(v === "none" ? null : Number(v))}>
            <SelectTrigger><SelectValue placeholder="Not recorded" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="none">Not recorded</SelectItem>
              {boreholes.map((b) => <SelectItem key={b.waterBoreholeId} value={String(b.waterBoreholeId)}>{b.boreholeName}</SelectItem>)}
            </SelectContent>
          </Select>
        </FormField>
        <FormField label="Machines *" hint="Which machines ran for this batch">
          <Select value={scope} onValueChange={(v) => setScope(v as WaterMachineSelectionType)}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="AllMachines">All active machines</SelectItem>
              <SelectItem value="CustomMachines">Pick machines…</SelectItem>
            </SelectContent>
          </Select>
        </FormField>

        {scope === "CustomMachines" && (
          <div className="sm:col-span-2 rounded-lg border border-slate-200 bg-white p-3">
            <div className="text-xs text-slate-500 mb-2">Select the machines that ran</div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
              {machines.map((m) => (
                <label key={m.waterMachineId} className="flex items-center gap-2 text-sm">
                  <Checkbox
                    checked={selectedMachineIds.includes(m.waterMachineId)}
                    onCheckedChange={(c) => setSelectedMachineIds((ids) =>
                      c ? [...ids, m.waterMachineId] : ids.filter((x) => x !== m.waterMachineId))}
                  />
                  <span className="truncate">
                    {m.machineName}
                    {m.status !== "Active" && <span className="text-[11px] text-amber-600 ml-1">({m.status})</span>}
                  </span>
                </label>
              ))}
            </div>
          </div>
        )}

        <div className="sm:col-span-2 text-xs text-slate-500">
          {scopedMachines.length} machine{scopedMachines.length === 1 ? "" : "s"} in scope
          {scopedMachines.length > 0 && ` — ${scopedMachines.map((m) => m.machineName).join(", ")}`}
        </div>
      </FormSection>

      <FormSection title="Batch output" color="emerald">
        <FormField label="Bags produced *"><NumberInput min={0} value={bags} onChange={(e) => setBags(e.target.value)} /></FormField>
        <FormField label="Sachets per bag"><NumberInput min={1} value={sachetsPerBag} onChange={(e) => setSachetsPerBag(e.target.value)} /></FormField>
        <FormField label="Loose sachets"><NumberInput min={0} value={loose} onChange={(e) => setLoose(e.target.value)} /></FormField>
        <FormField label="Rejected sachets"><NumberInput min={0} value={rejected} onChange={(e) => setRejected(e.target.value)} /></FormField>
        <FormField label="Damaged bags"><NumberInput min={0} value={damaged} onChange={(e) => setDamaged(e.target.value)} /></FormField>
        <FormField label="Packaging rolls used"><NumberInput min={0} value={rolls} onChange={(e) => setRolls(e.target.value)} /></FormField>
        <FormField label="Water used (litres)" hint="Optional"><NumberInput min={0} value={litres} onChange={(e) => setLitres(e.target.value)} /></FormField>
        <FormField label="Good bags" hint="Bags produced less damaged">
          <div className="h-9 flex items-center font-semibold tabular-nums text-slate-800">{goodBags.toLocaleString()}</div>
        </FormField>
      </FormSection>

      <FormSection title="Production costs" color="amber">
        <FormField label="Electricity"><NumberInput min={0} step="0.01" value={elec} onChange={(e) => setElec(e.target.value)} /></FormField>
        <FormField label="Fuel"><NumberInput min={0} step="0.01" value={fuel} onChange={(e) => setFuel(e.target.value)} /></FormField>
        <FormField label="Labor"><NumberInput min={0} step="0.01" value={labor} onChange={(e) => setLabor(e.target.value)} /></FormField>
        <FormField label="Other"><NumberInput min={0} step="0.01" value={other} onChange={(e) => setOther(e.target.value)} /></FormField>
        <div className="sm:col-span-2 text-xs text-slate-500">
          Each bucket becomes a real expense on every machine&apos;s production record when the batch is posted, so the
          allocation has to add up to these figures exactly.
        </div>
      </FormSection>

      <FormSection title="Raw materials used" color="emerald" columns={1}>
        <div className="space-y-2">
          {materials.length === 0 && (
            <p className="text-sm text-slate-400">
              No materials yet. Seed them from the product recipe, or add lines by hand.
            </p>
          )}
          {materials.map((m) => {
            const it = m.waterRawMaterialItemId ? itemById.get(m.waterRawMaterialItemId) : undefined
            return (
              <div key={m.key} className="rounded-lg border border-slate-200 p-2.5 bg-white grid grid-cols-1 sm:grid-cols-12 gap-2 items-start">
                <div className="sm:col-span-4">
                  <label className="text-xs text-slate-500">Material</label>
                  <Select value={m.waterRawMaterialItemId ? String(m.waterRawMaterialItemId) : ""}
                          onValueChange={(v) => pickMaterialItem(m.key, Number(v))}>
                    <SelectTrigger><SelectValue placeholder="Pick material" /></SelectTrigger>
                    <SelectContent>
                      {items.map((i) => (
                        <SelectItem key={i.waterRawMaterialItemId} value={String(i.waterRawMaterialItemId)}>{i.itemName}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="sm:col-span-2">
                  <label className="text-xs text-slate-500">Used{m.unitOfMeasure ? ` (${m.unitOfMeasure})` : ""}</label>
                  <NumberInput min={0} step="0.001" value={String(m.quantityUsed ?? "")}
                               onChange={(e) => setMaterial(m.key, { quantityUsed: num(e.target.value) })} />
                  {it && <div className="text-[11px] text-slate-400 mt-0.5">In stock: {(it.currentQuantity ?? 0).toLocaleString()}</div>}
                </div>
                <div className="sm:col-span-2">
                  <label className="text-xs text-slate-500">Expected</label>
                  <NumberInput min={0} step="0.001" value={m.expectedQuantityUsed != null ? String(m.expectedQuantityUsed) : ""}
                               onChange={(e) => setMaterial(m.key, { expectedQuantityUsed: e.target.value === "" ? null : num(e.target.value) })} />
                  <div className="text-[11px] text-slate-400 mt-0.5">From the recipe</div>
                </div>
                <div className="sm:col-span-2">
                  <label className="text-xs text-slate-500">Unit cost</label>
                  <NumberInput min={0} step="0.0001" value={m.unitCost != null ? String(m.unitCost) : ""}
                               onChange={(e) => setMaterial(m.key, { unitCost: e.target.value === "" ? null : num(e.target.value) })} />
                  <div className="text-[11px] text-slate-400 mt-0.5">Priced from lots at posting</div>
                </div>
                <div className="sm:col-span-1 text-right">
                  <label className="text-xs text-slate-500">Cost</label>
                  <div className="h-9 flex items-center justify-end tabular-nums text-slate-700">
                    {gh(m.quantityUsed * (Number(m.unitCost) || 0))}
                  </div>
                </div>
                <div className="sm:col-span-1 flex sm:justify-end pt-5">
                  <Button variant="ghost" size="sm" onClick={() => removeMaterial(m.key)}>
                    <Trash2 className="w-4 h-4 text-red-600" />
                  </Button>
                </div>
              </div>
            )
          })}
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="outline" size="sm" onClick={addMaterial}><Plus className="w-4 h-4 mr-1" /> Add material</Button>
            <Button variant="ghost" size="sm" onClick={() => void seedFromRecipe()}>
              <Wand2 className="w-4 h-4 mr-1" /> Seed from recipe
            </Button>
            <span className="ml-auto text-sm text-slate-600">
              Material cost (preview): <span className="font-semibold tabular-nums">{gh(materialCost)}</span>
            </span>
          </div>
        </div>
      </FormSection>

      <FormSection title="Notes" color="blue" columns={1}>
        <Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
      </FormSection>

      <Card>
        <CardContent className="p-4 grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
          <div><div className="text-slate-500 text-xs">Production cost</div><div className="font-semibold tabular-nums">{gh(totalCost)}</div></div>
          <div><div className="text-slate-500 text-xs">Material cost</div><div className="font-semibold tabular-nums">{gh(materialCost)}</div></div>
          <div><div className="text-slate-500 text-xs">All-in cost</div><div className="font-semibold tabular-nums">{gh(totalCost + materialCost)}</div></div>
          <div>
            <div className="text-slate-500 text-xs">Cost / good bag</div>
            <div className="font-semibold tabular-nums">{gh(goodBags > 0 ? (totalCost + materialCost) / goodBags : 0)}</div>
          </div>
        </CardContent>
      </Card>

      <div className="flex flex-wrap justify-end gap-2 pt-1 pb-8">
        <Button variant="outline" onClick={() => router.push("/water-daily-production")} disabled={saving}>Cancel</Button>
        {!existing && (
          <Button variant="outline" onClick={() => void save("Draft")} disabled={saving}>
            {saving ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Saving…</> : <><Save className="w-4 h-4 mr-1" /> Save as draft</>}
          </Button>
        )}
        <Button onClick={() => void save(existing ? (existing.status as any) : "PendingAllocation")} disabled={saving}>
          {saving ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Saving…</> : <><Save className="w-4 h-4 mr-1" /> {existing ? "Save changes" : "Log batch & allocate"}</>}
        </Button>
      </div>
    </div>
  )
}

"use client"

import { useEffect, useMemo, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft, Plus, Trash2, Save, Loader2, ShoppingBag } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getWaterProduct, updateWaterProduct, listWaterProducts,
  getWaterProductionRecipe, upsertWaterProductionRecipe,
  listWaterRawMaterialItems,
  type WaterProduct, type WaterProductInput, type WaterProductionRecipe,
  type WaterRawMaterialItem,
} from "@/lib/api/water"

const PRODUCT_TYPES: { value: NonNullable<WaterProductInput["productType"]>; label: string }[] = [
  { value: "FinishedGood",       label: "Finished good" },
  { value: "RawMaterial",        label: "Raw material" },
  { value: "PackagingMaterial",  label: "Packaging material" },
  { value: "Other",              label: "Other" },
]

// What the Recipe tab edits in memory. Pre-fills LatestUnitCost from the
// material's most recent purchase so the Estimated Cost column on the
// production batch can be filled without another fetch.
type RecipeRow = {
  waterRawMaterialItemId: number
  quantityPerOutputUnit: number
  outputUnit: string
  wasteAllowancePercent: number
  isOptional: boolean
  notes: string
}

export default function WaterProductDetailsPage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const fmtGhc = useFmt()

  const productId = Number(params?.id)

  const [product, setProduct] = useState<WaterProduct | null>(null)
  const [allProducts, setAllProducts] = useState<WaterProduct[]>([])
  const [rawMaterials, setRawMaterials] = useState<WaterRawMaterialItem[]>([])
  const [recipe, setRecipe] = useState<WaterProductionRecipe | null>(null)
  const [recipeRows, setRecipeRows] = useState<RecipeRow[]>([])

  const [loading, setLoading] = useState(true)
  const [savingRecipe, setSavingRecipe] = useState(false)
  const [savingSettings, setSavingSettings] = useState(false)

  const [settingsForm, setSettingsForm] = useState<WaterProductInput>({
    name: "", sku: "", sizeMl: undefined, unit: "", unitPrice: 0,
    isActive: true, productType: "FinishedGood", notes: "",
    // Migration 084 — sachet-water defaults. When isSachetProduct is on, the
    // product can be sold by bag OR sachet using BagPrice / SachetPrice.
    baseUnit: null, sachetsPerBag: null, bagPrice: null, sachetPrice: null, isSachetProduct: false,
  })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Water") { router.replace("/dashboard"); return }
    if (!productId || Number.isNaN(productId)) { router.replace("/water-products"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, productId])

  async function load() {
    setLoading(true)
    try {
      const [p, all, mats, r] = await Promise.all([
        getWaterProduct(productId),
        listWaterProducts(),
        listWaterRawMaterialItems(),
        // Recipe is only meaningful for finished goods, but fetch it
        // anyway — if the user later flips ProductType to FinishedGood the
        // UI already has the data.
        getWaterProductionRecipe(productId).catch(() => null),
      ])
      setProduct(p)
      setAllProducts(all)
      setRawMaterials(mats)
      setRecipe(r)
      setRecipeRows((r?.items ?? []).map(it => ({
        waterRawMaterialItemId: it.waterRawMaterialItemId,
        quantityPerOutputUnit: Number(it.quantityPerOutputUnit ?? 0),
        outputUnit: it.outputUnit ?? "bag",
        wasteAllowancePercent: Number(it.wasteAllowancePercent ?? 0),
        isOptional: !!it.isOptional,
        notes: it.notes ?? "",
      })))
      setSettingsForm({
        name: p.name,
        sku: p.sku ?? "",
        sizeMl: p.sizeMl ?? undefined,
        unit: p.unit ?? "",
        unitPrice: p.unitPrice,
        isActive: p.isActive,
        productType: p.productType ?? "FinishedGood",
        notes: p.notes ?? "",
        baseUnit: p.baseUnit ?? null,
        sachetsPerBag: p.sachetsPerBag ?? null,
        bagPrice: p.bagPrice ?? null,
        sachetPrice: p.sachetPrice ?? null,
        isSachetProduct: !!p.isSachetProduct,
      })
    } catch (e: any) {
      toast({ title: "Could not load product", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  const isFinishedGood = (settingsForm.productType ?? product?.productType) === "FinishedGood"

  // Sort raw materials so already-picked ones float to the top of the dropdown,
  // and inactive ones drop to the bottom but stay selectable.
  const materialPicker = useMemo(() => {
    return [...rawMaterials]
      .filter(m => m.isActive)
      .sort((a, b) => a.itemName.localeCompare(b.itemName))
  }, [rawMaterials])

  function addRecipeRow() {
    const firstUnused = materialPicker.find(m => !recipeRows.some(r => r.waterRawMaterialItemId === m.waterRawMaterialItemId))
    if (!firstUnused) {
      toast({ title: "No raw materials left to add", description: "Create more raw materials first.", variant: "destructive" })
      return
    }
    setRecipeRows([
      ...recipeRows,
      {
        waterRawMaterialItemId: firstUnused.waterRawMaterialItemId,
        quantityPerOutputUnit: 0,
        outputUnit: "bag",
        wasteAllowancePercent: 0,
        isOptional: false,
        notes: "",
      },
    ])
  }

  function removeRecipeRow(idx: number) {
    setRecipeRows(recipeRows.filter((_, i) => i !== idx))
  }

  function updateRecipeRow(idx: number, patch: Partial<RecipeRow>) {
    setRecipeRows(recipeRows.map((r, i) => i === idx ? { ...r, ...patch } : r))
  }

  async function saveRecipe() {
    // No finished-good check on the backend, but the UI surfaces the warning
    // up front so users don't think they can build a recipe for a raw material.
    if (!isFinishedGood) {
      toast({
        title: "Only finished goods can have recipes",
        description: "Change Product type to 'Finished good' in Settings first.",
        variant: "destructive",
      })
      return
    }

    // Spot dupes — the SP would accept them but the user almost certainly
    // didn't mean to add the same material twice.
    const seen = new Set<number>()
    for (const r of recipeRows) {
      if (seen.has(r.waterRawMaterialItemId)) {
        toast({ title: "Duplicate material", description: "Each raw material can appear once.", variant: "destructive" })
        return
      }
      seen.add(r.waterRawMaterialItemId)
      if (r.quantityPerOutputUnit < 0) {
        toast({ title: "Quantity cannot be negative", variant: "destructive" })
        return
      }
    }

    setSavingRecipe(true)
    try {
      await upsertWaterProductionRecipe(productId, {
        recipeName: recipe?.recipeName ?? "Default",
        notes: recipe?.notes ?? null,
        items: recipeRows.map((r, i) => ({
          waterRawMaterialItemId: r.waterRawMaterialItemId,
          quantityPerOutputUnit: r.quantityPerOutputUnit,
          outputUnit: r.outputUnit || "bag",
          wasteAllowancePercent: r.wasteAllowancePercent,
          isOptional: r.isOptional,
          displayOrder: i,
          notes: r.notes || null,
        })),
      })
      toast({ title: "Recipe saved" })
      // Re-fetch so we get joined LatestUnitCost values and IDs for new rows.
      await load()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally {
      setSavingRecipe(false)
    }
  }

  async function saveSettings() {
    if (!settingsForm.name.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSavingSettings(true)
    try {
      await updateWaterProduct(productId, settingsForm)
      toast({ title: "Product updated" })
      await load()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally {
      setSavingSettings(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center gap-2">
            <Link href="/water-products">
              <Button variant="ghost" size="sm" className="gap-1">
                <ArrowLeft className="h-4 w-4" /> Back
              </Button>
            </Link>
          </div>

          {loading ? (
            <Card>
              <CardContent className="p-6 text-slate-500 flex items-center gap-2">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading product…
              </CardContent>
            </Card>
          ) : !product ? (
            <Card>
              <CardContent className="p-6 text-slate-500">Product not found.</CardContent>
            </Card>
          ) : (
            <>
              {/* Title + summary cards */}
              <div className="mb-4 flex items-start gap-3">
                <div className="w-10 h-10 shrink-0 bg-sky-100 rounded-lg flex items-center justify-center">
                  <ShoppingBag className="h-5 w-5 text-sky-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-semibold text-slate-900">{product.name}</h1>
                  <div className="text-xs sm:text-sm text-slate-500 flex flex-wrap gap-2">
                    <Badge variant="outline">{product.productType}</Badge>
                    {product.sku && <span>SKU {product.sku}</span>}
                    {product.unit && <span>· {product.unit}</span>}
                    {product.sizeMl && <span>· {product.sizeMl} ml</span>}
                  </div>
                </div>
              </div>

              <div className="mb-4 grid grid-cols-2 md:grid-cols-4 gap-3">
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Unit price</div><div className="text-xl font-semibold tabular-nums">{fmtGhc(product.unitPrice)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Stock on hand</div><div className="text-xl font-semibold tabular-nums">{product.stockOnHand.toLocaleString()}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Status</div><div className="text-xl font-semibold">{product.isActive ? <span className="text-emerald-600">Active</span> : <span className="text-slate-400">Inactive</span>}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Recipe items</div><div className="text-xl font-semibold">{recipeRows.length}</div></CardContent></Card>
              </div>

              <Tabs defaultValue="overview">
                <TabsList>
                  <TabsTrigger value="overview">Overview</TabsTrigger>
                  {/* Recipe tab is only relevant for FinishedGood. We still show
                      it for other types so the user can switch + immediately
                      configure once they fix Settings. */}
                  <TabsTrigger value="recipe">Production recipe</TabsTrigger>
                  <TabsTrigger value="settings">Settings</TabsTrigger>
                </TabsList>

                {/* OVERVIEW */}
                <TabsContent value="overview">
                  <Card>
                    <CardContent className="p-4 space-y-3">
                      <Row label="Name" value={product.name} />
                      <Row label="Product type" value={product.productType} />
                      <Row label="SKU" value={product.sku ?? "—"} />
                      <Row label="Unit" value={product.unit ?? "—"} />
                      <Row label="Size" value={product.sizeMl ? `${product.sizeMl} ml` : "—"} />
                      <Row label="Unit price" value={fmtGhc(product.unitPrice)} />
                      <Row label="Stock on hand" value={product.stockOnHand.toLocaleString()} />
                      <Row label="Active" value={product.isActive ? "Yes" : "No"} />
                      <Row label="Notes" value={product.notes ?? "—"} />
                    </CardContent>
                  </Card>
                </TabsContent>

                {/* RECIPE */}
                <TabsContent value="recipe">
                  {!isFinishedGood && (
                    <Card className="border-amber-200 bg-amber-50 mb-4">
                      <CardContent className="p-3 text-sm text-amber-900">
                        Recipes only apply to finished goods. Change the product type to
                        <span className="font-semibold"> Finished good</span> in
                        <span className="font-semibold"> Settings</span> to use this tab.
                      </CardContent>
                    </Card>
                  )}

                  <Card>
                    <CardContent className="p-4">
                      <div className="mb-3 flex items-center justify-between gap-2">
                        <div>
                          <div className="font-medium">Production recipe</div>
                          <div className="text-xs text-slate-500">
                            What raw materials are needed per output unit (typically per bag).
                          </div>
                        </div>
                        <div className="flex gap-2">
                          <Button variant="outline" size="sm" onClick={addRecipeRow} disabled={!isFinishedGood}>
                            <Plus className="h-4 w-4 mr-1" /> Add material
                          </Button>
                          <Button size="sm" onClick={saveRecipe} disabled={savingRecipe || !isFinishedGood}>
                            <Save className="h-4 w-4 mr-1" /> {savingRecipe ? "Saving…" : "Save recipe"}
                          </Button>
                        </div>
                      </div>

                      {recipeRows.length === 0 ? (
                        <div className="p-6 text-center text-slate-500 text-sm">
                          No materials in this recipe yet. Click <span className="font-medium">Add material</span> to start.
                        </div>
                      ) : (
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead className="min-w-[180px]">Raw material</TableHead>
                                <TableHead className="text-right">Qty / output</TableHead>
                                <TableHead>Per (unit)</TableHead>
                                <TableHead className="text-right">Waste %</TableHead>
                                <TableHead>Optional</TableHead>
                                <TableHead className="text-right">Stock</TableHead>
                                <TableHead></TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {recipeRows.map((row, idx) => {
                                const mat = rawMaterials.find(m => m.waterRawMaterialItemId === row.waterRawMaterialItemId)
                                return (
                                  <TableRow key={idx}>
                                    <TableCell>
                                      <Select
                                        value={String(row.waterRawMaterialItemId)}
                                        onValueChange={(v) => updateRecipeRow(idx, { waterRawMaterialItemId: Number(v) })}
                                      >
                                        <SelectTrigger><SelectValue /></SelectTrigger>
                                        <SelectContent>
                                          {materialPicker.map(m => (
                                            <SelectItem key={m.waterRawMaterialItemId} value={String(m.waterRawMaterialItemId)}>
                                              {m.itemName} ({m.unitOfMeasure ?? "—"})
                                            </SelectItem>
                                          ))}
                                        </SelectContent>
                                      </Select>
                                    </TableCell>
                                    <TableCell className="text-right">
                                      <NumberInput
                                         min={0} step="0.0001"
                                        value={row.quantityPerOutputUnit}
                                        onChange={(e) => updateRecipeRow(idx, { quantityPerOutputUnit: Number(e.target.value) || 0 })}
                                        className="w-24 ml-auto text-right"
                                      />
                                    </TableCell>
                                    <TableCell>
                                      <Input
                                        value={row.outputUnit}
                                        onChange={(e) => updateRecipeRow(idx, { outputUnit: e.target.value })}
                                        className="w-20"
                                      />
                                    </TableCell>
                                    <TableCell className="text-right">
                                      <NumberInput
                                         min={0} step="0.01"
                                        value={row.wasteAllowancePercent}
                                        onChange={(e) => updateRecipeRow(idx, { wasteAllowancePercent: Number(e.target.value) || 0 })}
                                        className="w-20 ml-auto text-right"
                                      />
                                    </TableCell>
                                    <TableCell>
                                      <input
                                        type="checkbox"
                                        checked={row.isOptional}
                                        onChange={(e) => updateRecipeRow(idx, { isOptional: e.target.checked })}
                                      />
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums">
                                      {mat ? `${(mat.currentQuantity ?? 0).toLocaleString()} ${mat.unitOfMeasure ?? ""}` : "—"}
                                    </TableCell>
                                    <TableCell className="text-right">
                                      <Button size="sm" variant="ghost" onClick={() => removeRecipeRow(idx)}>
                                        <Trash2 className="h-4 w-4 text-red-500" />
                                      </Button>
                                    </TableCell>
                                  </TableRow>
                                )
                              })}
                            </TableBody>
                          </Table>
                        </div>
                      )}
                    </CardContent>
                  </Card>
                </TabsContent>

                {/* SETTINGS */}
                <TabsContent value="settings">
                  <Card>
                    <CardContent className="p-4 grid grid-cols-2 gap-3">
                      <div className="col-span-2"><Label>Name *</Label>
                        <Input value={settingsForm.name} onChange={(e) => setSettingsForm({ ...settingsForm, name: e.target.value })} /></div>
                      <div><Label>Product type</Label>
                        <Select value={settingsForm.productType ?? "FinishedGood"} onValueChange={(v) => setSettingsForm({ ...settingsForm, productType: v as any })}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>{PRODUCT_TYPES.map(t => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}</SelectContent>
                        </Select></div>
                      <div><Label>SKU</Label>
                        <Input value={settingsForm.sku ?? ""} onChange={(e) => setSettingsForm({ ...settingsForm, sku: e.target.value })} /></div>
                      <div><Label>Unit</Label>
                        <Input placeholder="sachet / bottle / gallon" value={settingsForm.unit ?? ""} onChange={(e) => setSettingsForm({ ...settingsForm, unit: e.target.value })} /></div>
                      <div><Label>Size (ml)</Label>
                        <NumberInput value={settingsForm.sizeMl ?? ""} onChange={(e) => setSettingsForm({ ...settingsForm, sizeMl: e.target.value === "" ? undefined : parseInt(e.target.value, 10) })} /></div>
                      <div><Label>Unit price *</Label>
                        <NumberInput min={0} step="0.01" value={settingsForm.unitPrice} onChange={(e) => setSettingsForm({ ...settingsForm, unitPrice: parseFloat(e.target.value || "0") })} /></div>
                      <div className="col-span-2"><Label>Notes</Label>
                        <Textarea value={settingsForm.notes ?? ""} onChange={(e) => setSettingsForm({ ...settingsForm, notes: e.target.value })} /></div>

                      {/* Migration 084 — sachet-water support. When checked, sales
                          can be recorded in either Bag or Sachet units, and stock
                          is tracked internally in sachets. */}
                      <div className="col-span-2 border-t pt-3 mt-1 space-y-2">
                        <label className="flex items-center gap-2 text-sm font-medium">
                          <input type="checkbox" checked={!!settingsForm.isSachetProduct}
                                 onChange={(e) => setSettingsForm({
                                   ...settingsForm,
                                   isSachetProduct: e.target.checked,
                                   baseUnit: e.target.checked ? (settingsForm.baseUnit ?? "Sachet") : null,
                                 })} />
                          Sachet product — sells by Bag or Sachet
                        </label>
                        {settingsForm.isSachetProduct && (
                          <div className="grid grid-cols-3 gap-3">
                            <div><Label>Sachets per bag</Label>
                              <NumberInput min={1} value={settingsForm.sachetsPerBag ?? ""}
                                     onChange={(e) => setSettingsForm({ ...settingsForm, sachetsPerBag: e.target.value === "" ? null : parseInt(e.target.value, 10) })} /></div>
                            <div><Label>Bag price</Label>
                              <NumberInput min={0} step="0.01" value={settingsForm.bagPrice ?? ""}
                                     onChange={(e) => setSettingsForm({ ...settingsForm, bagPrice: e.target.value === "" ? null : parseFloat(e.target.value) })} /></div>
                            <div><Label>Sachet price</Label>
                              <NumberInput min={0} step="0.01" value={settingsForm.sachetPrice ?? ""}
                                     onChange={(e) => setSettingsForm({ ...settingsForm, sachetPrice: e.target.value === "" ? null : parseFloat(e.target.value) })} /></div>
                          </div>
                        )}
                      </div>

                      <label className="col-span-2 flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={settingsForm.isActive ?? true} onChange={(e) => setSettingsForm({ ...settingsForm, isActive: e.target.checked })} />
                        Active (visible in sales)
                      </label>
                      <div className="col-span-2 flex justify-end gap-2 pt-2">
                        <Button onClick={saveSettings} disabled={savingSettings}>
                          {savingSettings ? "Saving…" : "Save settings"}
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                </TabsContent>
              </Tabs>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="grid grid-cols-3 gap-2 text-sm">
      <div className="text-slate-500">{label}</div>
      <div className="col-span-2 text-slate-900">{value}</div>
    </div>
  )
}

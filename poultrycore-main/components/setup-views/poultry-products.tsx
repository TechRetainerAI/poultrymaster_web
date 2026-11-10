"use client"

import { useSetupEmbedded, shellClass, SetupTaskBar } from "@/components/setup/setup-embed"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { FieldCard } from "@/components/ui/field-card"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Plus, Pencil, Loader2, Trash2, ListChecks, Package } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryProducts, createPoultryProduct, updatePoultryProduct, deletePoultryProduct,
  getPoultryRecipe, upsertPoultryRecipe, listPoultryRawMaterialItems,
  ensurePoultryDefaults, postPoultryManualMovement, MANUAL_MOVEMENT_REASONS,
  getPoultryByproductSettings, setPoultryByproductSettings, type PoultryByproductSettings,
  type PoultryProduct, type PoultryRawMaterialItem, type PoultryRecipeItem,
} from "@/lib/api/poultry-inventory"

const PRODUCT_TYPES = ["FinishedGood", "RawMaterial", "PackagingMaterial", "Other"]
const UNITS = ["Bag", "Crate", "Tray", "Dozen", "Egg", "Piece", "Kilogram", "Carton", "Box", "Pack", "Unit", "Other"]
const EMPTY = { name: "", sku: "", unit: "", size: "", unitPrice: 0, productType: "FinishedGood", isActive: true, notes: "", isRawEggProduct: false, requiresRecipeSetup: true }

export function PoultryProductsPage() {
  const embedded = useSetupEmbedded()
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [products, setProducts] = useState<PoultryProduct[]>([])
  const pg = usePagination(products)
  const [rawItems, setRawItems] = useState<PoultryRawMaterialItem[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState({ ...EMPTY })
  const [saving, setSaving] = useState(false)
  const [delTarget, setDelTarget] = useState<PoultryProduct | null>(null)

  // Recipe editor
  const [recipeProduct, setRecipeProduct] = useState<PoultryProduct | null>(null)
  const [recipeRows, setRecipeRows] = useState<PoultryRecipeItem[]>([])
  const [recipeName, setRecipeName] = useState("")
  const [recipeSaving, setRecipeSaving] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      await ensurePoultryDefaults().catch(() => {})   // default Eggs + Birds products exist
      const [ps, ri] = await Promise.all([listPoultryProducts(), listPoultryRawMaterialItems()]); setProducts(ps); setRawItems(ri)
    }
    catch (e: any) { toast({ title: "Could not load products", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // 372: Broken Eggs / Dead Birds are system products. The list does not return
  // their role, so they are known by the names the database gives them; the
  // database refuses the change anyway, this only keeps the buttons honest.
  const isSystemProduct = (p: { name: string }) => p.name === "Broken Eggs" || p.name === "Dead Birds"
  const editingSystem = editId != null && products.some((p) => p.poultryProductId === editId && isSystemProduct(p))
  const editingName = products.find((p) => p.poultryProductId === editId)?.name ?? ""
  // 374: whether each byproduct is offered in Add Sale (Dead Birds off by default).
  const [byproductSettings, setByproductSettings] = useState<PoultryByproductSettings | null>(null)
  const [offerInSales, setOfferInSales] = useState(false)
  const offerKey: "brokenEggsInSales" | "deadBirdsInSales" = editingName === "Dead Birds" ? "deadBirdsInSales" : "brokenEggsInSales"

  function openNew() { setEditId(null); setForm({ ...EMPTY }); setOpen(true) }
  function openEdit(p: PoultryProduct) {
    setEditId(p.poultryProductId)
    if (isSystemProduct(p)) {
      getPoultryByproductSettings()
        .then((s) => { setByproductSettings(s); setOfferInSales(p.name === "Dead Birds" ? s.deadBirdsInSales : s.brokenEggsInSales) })
        .catch(() => { setByproductSettings(null); setOfferInSales(p.name !== "Dead Birds") })
    }
    setForm({ name: p.name, sku: p.sku ?? "", unit: p.unit ?? "", size: p.size ?? "", unitPrice: p.unitPrice, productType: p.productType, isActive: p.isActive, notes: p.notes ?? "", isRawEggProduct: p.isRawEggProduct, requiresRecipeSetup: p.requiresRecipeSetup })
    setOpen(true)
  }

  // Add-stock dialog (doc 7c)
  const [stockProduct, setStockProduct] = useState<PoultryProduct | null>(null)
  // 373: a manual movement like any other -- with a reason and the date it happened.
  const todayStr = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }
  const EMPTY_STOCK = { quantity: 0, unitCost: 0, note: "", reason: "", effectiveDate: "" }
  const [stockForm, setStockForm] = useState(EMPTY_STOCK)
  const [stockKey, setStockKey] = useState("")
  const ADD_STOCK_REASONS = MANUAL_MOVEMENT_REASONS.filter((r) => !["Historical Mortality", "Cull", "Opening Bird Count", "Disposal", "Unrecorded Breakage", "Damage", "Loss"].includes(r))
  function openStock(p: PoultryProduct) {
    setStockProduct(p); setStockForm({ ...EMPTY_STOCK, effectiveDate: todayStr() })
    try { setStockKey(crypto.randomUUID()) } catch { setStockKey(`add-${Date.now()}-${Math.random().toString(36).slice(2)}`) }
  }
  const [stockSaving, setStockSaving] = useState(false)
  async function saveStock() {
    if (!stockProduct) return
    if (stockForm.quantity <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    if (!stockForm.reason) { toast({ title: "Choose the reason", variant: "destructive" }); return }
    if (stockForm.reason === "Other" && !stockForm.note.trim()) { toast({ title: "Say what happened", description: "Reason \"Other\" needs a note.", variant: "destructive" }); return }
    setStockSaving(true)
    try {
      const res = await postPoultryManualMovement({
        poultryProductId: stockProduct.poultryProductId, movementType: "Increase", quantity: stockForm.quantity,
        unitCost: stockForm.unitCost || null, effectiveDate: stockForm.effectiveDate || todayStr(), reason: stockForm.reason,
        note: stockForm.note.trim() || null, requestKey: stockKey,
      })
      toast({ title: `Stock added (${res.movementNo})` }); setStockProduct(null); setStockForm(EMPTY_STOCK); await load()
    } catch (e: any) { toast({ title: "Could not add stock", description: e?.message, variant: "destructive" }) }
    finally { setStockSaving(false) }
  }
  async function save() {
    if (!form.name.trim()) { toast({ title: "Name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editId) await updatePoultryProduct(editId, form); else await createPoultryProduct(form)
      if (editingSystem && (byproductSettings == null || byproductSettings[offerKey] !== offerInSales)) {
        await setPoultryByproductSettings({ [offerKey]: offerInSales })
      }
      toast({ title: editId ? "Product updated" : "Product added" }); setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }
  async function confirmDelete() {
    if (!delTarget) return
    try { await deletePoultryProduct(delTarget.poultryProductId); toast({ title: "Product removed" }); setDelTarget(null); await load() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  async function openRecipe(p: PoultryProduct) {
    setRecipeProduct(p); setRecipeRows([]); setRecipeName("")
    try {
      const r = await getPoultryRecipe(p.poultryProductId)
      if (r) { setRecipeName(r.recipeName ?? ""); setRecipeRows(r.items ?? []) }
    } catch (e: any) { toast({ title: "Could not load recipe", description: e?.message, variant: "destructive" }) }
  }
  function addRecipeRow() {
    setRecipeRows([...recipeRows, { poultryRawMaterialItemId: 0, quantityPerOutputUnit: 0, wasteAllowancePercent: 0, isOptional: false, displayOrder: recipeRows.length }])
  }
  async function saveRecipe() {
    if (!recipeProduct) return
    const items = recipeRows.filter((r) => r.poultryRawMaterialItemId && r.quantityPerOutputUnit > 0)
    setRecipeSaving(true)
    try {
      await upsertPoultryRecipe(recipeProduct.poultryProductId, { recipeName: recipeName || null, items })
      toast({ title: "Recipe saved" }); setRecipeProduct(null)
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setRecipeSaving(false) }
  }

  return (
    <div className={shellClass(embedded, "flex h-screen bg-gray-50")}>
      {!embedded && <DashboardSidebar />}
      <div className={shellClass(embedded, "flex-1 flex flex-col min-w-0")}>
        {!embedded && <DashboardHeader />}
        <main className={embedded ? "space-y-4 min-w-0" : "flex-1 overflow-y-auto p-4 sm:p-6 space-y-4"}>
          <div className={embedded ? "hidden" : "flex items-center justify-between"}>
            <div><h1 className="text-2xl font-bold">Products</h1><p className="text-sm text-slate-500">Finished goods you produce and stock.</p></div>
            <SetupTaskBar tasks={[{ id: "new", label: "New product", icon: Plus, primary: true, onClick: openNew }]} />
          </div>
          <Card className="gap-0 py-0"><CardContent className={embedded ? "p-0" : "p-4"}>
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
             : products.length === 0 ? (
              <div className="flex flex-col items-center justify-center gap-3 px-6 py-12 text-center">
                <span className="grid h-12 w-12 place-items-center rounded-full bg-blue-50 text-blue-600"><Package className="h-6 w-6" /></span>
                <div>
                  <p className="text-sm font-semibold text-slate-900">No products yet</p>
                  <p className="text-sm text-slate-500">Finished goods you produce and stock will appear here.</p>
                </div>
              </div>
             ) : (
              <><div className="hidden md:block overflow-x-auto rounded-xl border border-slate-200 bg-white"><Table className="min-w-[640px]">
                <TableHeader><TableRow className="bg-slate-50">
                  <TableHead className="font-semibold text-slate-900">Product</TableHead><TableHead className="font-semibold text-slate-900">Type</TableHead><TableHead className="font-semibold text-slate-900">Unit</TableHead>
                  <TableHead className="text-right font-semibold text-slate-900">Price</TableHead><TableHead className="text-right font-semibold text-slate-900">In stock</TableHead>
                  <TableHead className="font-semibold text-slate-900">Status</TableHead><TableHead className="text-right font-semibold text-slate-900">Actions</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {pg.pageItems.map((p) => (
                      <TableRow key={p.poultryProductId} className="hover:bg-slate-50">
                        <TableCell className="font-medium text-slate-900">
                          <span className="flex items-center gap-2.5">
                            <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-blue-50 text-blue-600"><Package className="h-4 w-4" /></span>
                            {p.name}
                          </span>
                        </TableCell>
                        <TableCell className="text-slate-600">{p.productType}</TableCell>
                        <TableCell className="text-slate-600">{p.unit ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(p.unitPrice)}</TableCell>
                        <TableCell className="text-right tabular-nums">{p.stockOnHand.toLocaleString()}</TableCell>
                        <TableCell>{p.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="secondary">Inactive</Badge>}</TableCell>
                        <TableCell className="text-right">
                          {/* 359: birds are adjusted per flock / batch on the Stock page */}
{!(p.isBirdProduct || p.name === "Birds") && !isSystemProduct(p) && <Button variant="ghost" size="sm" onClick={() => openStock(p)} title="Add stock"><Plus className="w-4 h-4 text-emerald-600" /></Button>}
                          {p.requiresRecipeSetup && !p.isRawEggProduct && (
                            <Button variant="ghost" size="sm" onClick={() => openRecipe(p)} title="Recipe"><ListChecks className="w-4 h-4 text-indigo-600" /></Button>
                          )}
                          <Button variant="ghost" size="sm" onClick={() => openEdit(p)}><Pencil className="w-4 h-4" /></Button>
                          {!isSystemProduct(p) && <Button variant="ghost" size="sm" onClick={() => setDelTarget(p)}><Trash2 className="w-4 h-4 text-red-500" /></Button>}
                        </TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table></div>
              <DataPagination {...pg.paginationProps} />
              {/* Mobile cards */}
              <div className="md:hidden space-y-2">
                {products.map((p) => (
                    <FieldCard key={p.poultryProductId} title={p.name}
                      badge={p.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="secondary">Inactive</Badge>}
                      fields={[["Type", p.productType], ["Unit", p.unit ?? "—"], ["Price", gh(p.unitPrice)], ["In stock", p.stockOnHand.toLocaleString()]]}
                      actions={<>
                        {/* 359: birds are adjusted per flock / batch on the Stock page */}
{!(p.isBirdProduct || p.name === "Birds") && !isSystemProduct(p) && <Button variant="ghost" size="sm" onClick={() => openStock(p)} title="Add stock"><Plus className="w-4 h-4 text-emerald-600" /></Button>}
                        {p.requiresRecipeSetup && !p.isRawEggProduct && <Button variant="ghost" size="sm" onClick={() => openRecipe(p)} title="Recipe"><ListChecks className="w-4 h-4 text-indigo-600" /></Button>}
                        <Button variant="ghost" size="sm" onClick={() => openEdit(p)}><Pencil className="w-4 h-4" /></Button>
                        {!isSystemProduct(p) && <Button variant="ghost" size="sm" onClick={() => setDelTarget(p)}><Trash2 className="w-4 h-4 text-red-500" /></Button>}
                      </>} />
                  ))}
              </div></>
            )}
          </CardContent></Card>
        </main>
      </div>

      {/* Product dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>{editId ? "Edit product" : "New product"}</DialogTitle></DialogHeader>
          {editingSystem && (
            <p className="rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-xs text-slate-600">
              A system product: production records add to its stock. Its name and unit are fixed; you can change its price.
            </p>
          )}
          {editingSystem && (
            <label className="flex items-start gap-2 rounded-md border border-slate-200 px-3 py-2 text-sm">
              <input type="checkbox" className="mt-0.5" checked={offerInSales} onChange={(e) => setOfferInSales(e.target.checked)} />
              <span>
                <span className="font-medium">Offer in Add Sale</span>
                <span className="block text-xs text-slate-500">
                  {editingName === "Dead Birds"
                    ? "Off for farms that dispose of mortality. The stock is kept either way."
                    : "Broken eggs can be sold by the egg. The stock is kept either way."}
                </span>
              </span>
            </label>
          )}
          <FormSection title="Product details" color="blue">
            <FormField label="Name *"><Input value={form.name} disabled={editingSystem} onChange={(e) => setForm({ ...form, name: e.target.value })} /></FormField>
            <FormField label="Type">
              <Select value={form.productType} onValueChange={(v) => setForm({ ...form, productType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{PRODUCT_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Unit">
              <Select value={form.unit || ""} disabled={editingSystem} onValueChange={(v) => setForm({ ...form, unit: v })}>
                <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                <SelectContent>{UNITS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Selling price"><NumberInput min={0} step="0.01" value={form.unitPrice} onChange={(e) => setForm({ ...form, unitPrice: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Size" hint="e.g. Small / Medium / Large / Crate"><Input value={form.size} onChange={(e) => setForm({ ...form, size: e.target.value })} /></FormField>
            <FormField label="SKU"><Input value={form.sku} onChange={(e) => setForm({ ...form, sku: e.target.value })} /></FormField>
            <FormField label="Is this a raw egg product?">
              <Select value={form.isRawEggProduct ? "yes" : "no"} disabled={editingSystem} onValueChange={(v) => setForm({ ...form, isRawEggProduct: v === "yes", requiresRecipeSetup: v === "yes" ? false : form.requiresRecipeSetup })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="no">No</SelectItem><SelectItem value="yes">Yes</SelectItem></SelectContent>
              </Select>
            </FormField>
            <FormField label="Requires recipe setup?">
              <Select value={form.requiresRecipeSetup ? "yes" : "no"} onValueChange={(v) => setForm({ ...form, requiresRecipeSetup: v === "yes" })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="yes">Yes</SelectItem><SelectItem value="no">No</SelectItem></SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Recipe dialog */}
      <Dialog open={!!recipeProduct} onOpenChange={(o) => !o && setRecipeProduct(null)}>
        <DialogContent className="max-w-3xl">
          <DialogHeader><DialogTitle>Recipe — {recipeProduct?.name}</DialogTitle></DialogHeader>
          <FormSection title="Bill of materials (per output unit)" color="indigo" columns={1}>
            <FormField label="Recipe name"><Input value={recipeName} onChange={(e) => setRecipeName(e.target.value)} placeholder="Optional" /></FormField>
            <div className="space-y-2">
              {recipeRows.map((row, i) => (
                <div key={i} className="grid grid-cols-12 gap-2 items-center">
                  <div className="col-span-5">
                    <Select value={row.poultryRawMaterialItemId ? String(row.poultryRawMaterialItemId) : ""} onValueChange={(v) => { const rows = [...recipeRows]; rows[i] = { ...row, poultryRawMaterialItemId: Number(v) }; setRecipeRows(rows) }}>
                      <SelectTrigger><SelectValue placeholder="Raw material" /></SelectTrigger>
                      <SelectContent>{rawItems.filter((it) => it.isActive).map((it) => <SelectItem key={it.poultryRawMaterialItemId} value={String(it.poultryRawMaterialItemId)}>{it.itemName}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div className="col-span-3"><NumberInput min={0} step="0.0001" value={row.quantityPerOutputUnit} onChange={(e) => { const rows = [...recipeRows]; rows[i] = { ...row, quantityPerOutputUnit: Number(e.target.value) || 0 }; setRecipeRows(rows) }} placeholder="Qty/unit" /></div>
                  <div className="col-span-3"><NumberInput min={0} step="0.01" value={row.wasteAllowancePercent} onChange={(e) => { const rows = [...recipeRows]; rows[i] = { ...row, wasteAllowancePercent: Number(e.target.value) || 0 }; setRecipeRows(rows) }} placeholder="Waste %" /></div>
                  <div className="col-span-1"><Button variant="ghost" size="sm" onClick={() => setRecipeRows(recipeRows.filter((_, j) => j !== i))}><Trash2 className="w-4 h-4 text-red-500" /></Button></div>
                </div>
              ))}
              <Button variant="outline" size="sm" onClick={addRecipeRow}><Plus className="w-4 h-4 mr-1" /> Add material</Button>
            </div>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setRecipeProduct(null)}>Cancel</Button>
            <Button onClick={saveRecipe} disabled={recipeSaving}>{recipeSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save recipe"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Add stock dialog */}
      <Dialog open={!!stockProduct} onOpenChange={(o) => !o && setStockProduct(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Add stock — {stockProduct?.name}</DialogTitle></DialogHeader>
          <FormSection title="Stock addition" color="emerald">
            <FormField label="Quantity *"><NumberInput min={0} step="0.001" value={stockForm.quantity} onChange={(e) => setStockForm({ ...stockForm, quantity: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Unit cost / value"><NumberInput min={0} step="0.01" value={stockForm.unitCost} onChange={(e) => setStockForm({ ...stockForm, unitCost: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Reason *">
              <Select value={stockForm.reason} onValueChange={(v) => setStockForm({ ...stockForm, reason: v })}>
                <SelectTrigger><SelectValue placeholder="Choose the reason" /></SelectTrigger>
                <SelectContent>{ADD_STOCK_REASONS.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Effective date *" hint="When the stock came in."><Input type="date" value={stockForm.effectiveDate} max={todayStr()} onChange={(e) => setStockForm({ ...stockForm, effectiveDate: e.target.value })} /></FormField>
            <FormField label={stockForm.reason === "Other" ? "Note *" : "Note"} full><Input value={stockForm.note} onChange={(e) => setStockForm({ ...stockForm, note: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setStockProduct(null)}>Cancel</Button>
            <Button onClick={saveStock} disabled={stockSaving}>{stockSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Add stock"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog open={!!delTarget} onOpenChange={(o) => !o && setDelTarget(null)} onConfirm={confirmDelete} title="Remove product?" description={`Remove "${delTarget?.name}"? If it has stock history it will be deactivated instead.`} />
    </div>
  )
}

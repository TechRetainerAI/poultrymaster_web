"use client"

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
import { Plus, Pencil, Loader2, Trash2, ListChecks } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryProducts, createPoultryProduct, updatePoultryProduct, deletePoultryProduct,
  getPoultryRecipe, upsertPoultryRecipe, listPoultryRawMaterialItems,
  type PoultryProduct, type PoultryRawMaterialItem, type PoultryRecipeItem,
} from "@/lib/api/poultry-inventory"

const PRODUCT_TYPES = ["FinishedGood", "RawMaterial", "PackagingMaterial", "Other"]
const UNITS = ["Bag", "Crate", "Dozen", "Piece", "Kilogram", "Carton", "Box", "Pack", "Unit", "Other"]
const EMPTY = { name: "", sku: "", unit: "", unitPrice: 0, productType: "FinishedGood", isActive: true, notes: "" }

export default function PoultryProductsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [products, setProducts] = useState<PoultryProduct[]>([])
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
    try { const [ps, ri] = await Promise.all([listPoultryProducts(), listPoultryRawMaterialItems()]); setProducts(ps); setRawItems(ri) }
    catch (e: any) { toast({ title: "Could not load products", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm({ ...EMPTY }); setOpen(true) }
  function openEdit(p: PoultryProduct) {
    setEditId(p.poultryProductId)
    setForm({ name: p.name, sku: p.sku ?? "", unit: p.unit ?? "", unitPrice: p.unitPrice, productType: p.productType, isActive: p.isActive, notes: p.notes ?? "" })
    setOpen(true)
  }
  async function save() {
    if (!form.name.trim()) { toast({ title: "Name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editId) await updatePoultryProduct(editId, form); else await createPoultryProduct(form)
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
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold">Products</h1><p className="text-sm text-slate-500">Finished goods you produce and stock.</p></div>
            <Button onClick={openNew}><Plus className="w-4 h-4 mr-1" /> New product</Button>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Product</TableHead><TableHead>Type</TableHead><TableHead>Unit</TableHead>
                  <TableHead className="text-right">Price</TableHead><TableHead className="text-right">In stock</TableHead>
                  <TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {products.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">No products yet.</TableCell></TableRow>
                    : products.map((p) => (
                      <TableRow key={p.poultryProductId}>
                        <TableCell className="font-medium">{p.name}</TableCell>
                        <TableCell>{p.productType}</TableCell>
                        <TableCell>{p.unit ?? "—"}</TableCell>
                        <TableCell className="text-right">{gh(p.unitPrice)}</TableCell>
                        <TableCell className="text-right">{p.stockOnHand.toLocaleString()}</TableCell>
                        <TableCell>{p.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="secondary">Inactive</Badge>}</TableCell>
                        <TableCell className="text-right">
                          <Button variant="ghost" size="sm" onClick={() => openRecipe(p)} title="Recipe"><ListChecks className="w-4 h-4 text-indigo-600" /></Button>
                          <Button variant="ghost" size="sm" onClick={() => openEdit(p)}><Pencil className="w-4 h-4" /></Button>
                          <Button variant="ghost" size="sm" onClick={() => setDelTarget(p)}><Trash2 className="w-4 h-4 text-red-500" /></Button>
                        </TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table>
            )}
          </CardContent></Card>
        </main>
      </div>

      {/* Product dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>{editId ? "Edit product" : "New product"}</DialogTitle></DialogHeader>
          <FormSection title="Product details" color="blue">
            <FormField label="Name *"><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></FormField>
            <FormField label="Type">
              <Select value={form.productType} onValueChange={(v) => setForm({ ...form, productType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{PRODUCT_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Unit">
              <Select value={form.unit || ""} onValueChange={(v) => setForm({ ...form, unit: v })}>
                <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                <SelectContent>{UNITS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Selling price"><NumberInput min={0} step="0.01" value={form.unitPrice} onChange={(e) => setForm({ ...form, unitPrice: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="SKU"><Input value={form.sku} onChange={(e) => setForm({ ...form, sku: e.target.value })} /></FormField>
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

      <ConfirmDeleteDialog open={!!delTarget} onOpenChange={(o) => !o && setDelTarget(null)} onConfirm={confirmDelete} title="Remove product?" description={`Remove "${delTarget?.name}"? If it has stock history it will be deactivated instead.`} />
    </div>
  )
}

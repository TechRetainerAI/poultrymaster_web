"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Plus, Pencil, Trash2, Loader2, ShoppingBag, PackagePlus, ChefHat } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterProducts, createWaterProduct, updateWaterProduct, deleteWaterProduct,
  addWaterStockTransaction, type WaterProduct, type WaterProductInput, type WaterProductType,
} from "@/lib/api/water"

const EMPTY: WaterProductInput = { name: "", sku: "", sizeMl: undefined, unit: "sachet", unitPrice: 0, isActive: true, productType: "FinishedGood", notes: "" }

const PRODUCT_TYPES: { value: WaterProductType; label: string; hint?: string }[] = [
  { value: "FinishedGood",      label: "Finished good",      hint: "Sold to customers, e.g. sachet water" },
  { value: "RawMaterial",       label: "Raw material",       hint: "Consumed during production" },
  { value: "PackagingMaterial", label: "Packaging material", hint: "Rolls, bags, etc." },
  { value: "Other",             label: "Other" },
]

export default function WaterProductsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [products, setProducts] = useState<WaterProduct[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleProducts = useMemo(
    () => filterByDateAndSearch(products, {
      search, dateFrom, dateTo,
      searchKeys: ["name", "sku"],
    }),
    [products, search, dateFrom, dateTo],
  )

  const [createOpen, setCreateOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [restockOpen, setRestockOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<WaterProductInput>(EMPTY)
  const [editId, setEditId] = useState<number | null>(null)
  const [restockProduct, setRestockProduct] = useState<WaterProduct | null>(null)
  const [restockQty, setRestockQty] = useState<number>(0)
  const [restockCost, setRestockCost] = useState<number | undefined>(undefined)
  const [deleteTarget, setDeleteTarget] = useState<WaterProduct | null>(null)
  // Post-create nudge: when the user just made a FinishedGood, ask if they
  // want to set up its production recipe right away (deep link to Product
  // Details → Recipe tab).
  const [postCreateProduct, setPostCreateProduct] = useState<WaterProduct | null>(null)

  useEffect(() => {
    // Wait for Zustand to hydrate before deciding. Without this guard the
    // load() call fires with whatever farmId is in localStorage on first
    // render, which may belong to a different company type and cause 400s.
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Water") {
      router.replace("/dashboard")
      return
    }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setProducts(await listWaterProducts()) }
    catch (e: any) { toast({ title: "Could not load products", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function handleCreate() {
    if (!form.name.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      const created = await createWaterProduct(form)
      toast({ title: "Product created" })
      setCreateOpen(false); setForm(EMPTY); await load()
      // Recipe nudge only applies to finished goods — raw/packaging materials
      // don't get a recipe, they ARE the recipe ingredients.
      if (form.productType === "FinishedGood" && created?.waterProductId) {
        setPostCreateProduct(created)
      }
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function openEdit(p: WaterProduct) {
    setEditId(p.waterProductId)
    setForm({ name: p.name, sku: p.sku ?? "", sizeMl: p.sizeMl ?? undefined, unit: p.unit ?? "", unitPrice: p.unitPrice, isActive: p.isActive, productType: p.productType ?? "FinishedGood", notes: p.notes ?? "" })
    setEditOpen(true)
  }

  async function handleUpdate() {
    if (!editId) return
    setSaving(true)
    try {
      await updateWaterProduct(editId, form)
      toast({ title: "Product updated" })
      setEditOpen(false); setEditId(null); setForm(EMPTY); await load()
    } catch (e: any) { toast({ title: "Update failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(p: WaterProduct) {
    await deleteWaterProduct(p.waterProductId)
    await load()
  }

  function openRestock(p: WaterProduct) {
    setRestockProduct(p); setRestockQty(0); setRestockCost(undefined); setRestockOpen(true)
  }

  async function handleRestock() {
    if (!restockProduct || restockQty <= 0) return toast({ title: "Enter a positive quantity", variant: "destructive" })
    setSaving(true)
    try {
      await addWaterStockTransaction({
        waterProductId: restockProduct.waterProductId,
        txnType: "Restock", quantity: restockQty,
        unitCost: restockCost ?? null,
        note: `Restocked ${restockQty}`,
      })
      toast({ title: "Stock added" })
      setRestockOpen(false); setRestockProduct(null); await load()
    } catch (e: any) { toast({ title: "Restock failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <ShoppingBag className="h-6 w-6 text-sky-600" /> Water products
            </h1>
            <Button onClick={() => { setForm(EMPTY); setCreateOpen(true) }} className="w-full sm:w-auto h-11 sm:h-10">
              <Plus className="h-4 w-4 mr-1" /> New product
            </Button>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search name or SKU"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : products.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  No products yet. Click <span className="font-medium">New product</span> to add your first SKU.
                </div>
              ) : (
                <MobileCardList
                  items={visibleProducts}
                  getKey={(p) => p.waterProductId}
                  primary={(p) => (
                    <Link href={`/water-products/${p.waterProductId}`} className="text-sky-700 hover:underline">
                      {p.name}
                    </Link>
                  )}
                  secondary={(p) => (
                    <>
                      <Badge variant="outline">{p.productType ?? "FinishedGood"}</Badge>
                      <span className={p.isActive ? "text-emerald-600" : "text-slate-400"}>
                        {p.isActive ? "Active" : "Inactive"}
                      </span>
                    </>
                  )}
                  details={(p) => [
                    { label: "SKU", value: p.sku ?? "—" },
                    { label: "Size", value: p.sizeMl ? `${p.sizeMl} ml` : "—" },
                    { label: "Unit", value: p.unit ?? "—" },
                    { label: "Price", value: p.unitPrice.toFixed(2) },
                    { label: "Stock", value: p.stockOnHand },
                  ]}
                  actions={(p) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openRestock(p)}>
                        <PackagePlus className="h-4 w-4 mr-1" /> Restock
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(p)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(p)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Name</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead>SKU</TableHead>
                          <TableHead>Size</TableHead>
                          <TableHead>Unit</TableHead>
                          <TableHead className="text-right">Price</TableHead>
                          <TableHead className="text-right">Stock</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleProducts.map((p) => (
                          <TableRow key={p.waterProductId}>
                            <TableCell className="font-medium">
                              {/* Make the name a deep link into the details page so
                                  users don't need to find a separate "View" button. */}
                              <Link href={`/water-products/${p.waterProductId}`} className="text-sky-700 hover:underline">
                                {p.name}
                              </Link>
                            </TableCell>
                            <TableCell><Badge variant="outline">{p.productType ?? "FinishedGood"}</Badge></TableCell>
                            <TableCell className="text-slate-500">{p.sku ?? "—"}</TableCell>
                            <TableCell>{p.sizeMl ? `${p.sizeMl} ml` : "—"}</TableCell>
                            <TableCell>{p.unit ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{p.unitPrice.toFixed(2)}</TableCell>
                            <TableCell className="text-right tabular-nums">{p.stockOnHand}</TableCell>
                            <TableCell>
                              <span className={p.isActive ? "text-emerald-600" : "text-slate-400"}>
                                {p.isActive ? "Active" : "Inactive"}
                              </span>
                            </TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openRestock(p)} title="Add stock">
                                <PackagePlus className="h-4 w-4" />
                              </Button>
                              <Button size="sm" variant="ghost" onClick={() => openEdit(p)}>
                                <Pencil className="h-4 w-4" />
                              </Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(p)}>
                                <Trash2 className="h-4 w-4 text-red-500" />
                              </Button>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      <ProductDialog open={createOpen} onOpenChange={setCreateOpen} title="New water product"
        form={form} setForm={setForm} saving={saving} onSubmit={handleCreate} />
      <ProductDialog open={editOpen} onOpenChange={setEditOpen} title="Edit water product"
        form={form} setForm={setForm} saving={saving} onSubmit={handleUpdate} />

      <Dialog open={restockOpen} onOpenChange={setRestockOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <PackagePlus className="w-5 h-5 text-blue-600" /> Add stock — {restockProduct?.name}
            </DialogTitle>
            <DialogDescription>Record a restock for this product</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Restock" color="blue">
              <FormField label="Quantity">
                <NumberInput min={1} value={restockQty || ""} onChange={(e) => setRestockQty(parseInt(e.target.value || "0", 10))} />
              </FormField>
              <FormField label="Unit cost (optional)">
                <NumberInput min={0} step="0.01" value={restockCost ?? ""} onChange={(e) => setRestockCost(e.target.value === "" ? undefined : parseFloat(e.target.value))} />
              </FormField>
            </FormSection>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setRestockOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={handleRestock} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Add stock"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete product?"
        description={deleteTarget ? `Delete or deactivate "${deleteTarget.name}"? Existing sales will be preserved, but it will no longer appear in product lists.` : undefined}
        successTitle="Product removed"
        errorTitle="Delete failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />

      {/* Post-create nudge for FinishedGood — links to the Recipe tab. */}
      <Dialog open={!!postCreateProduct} onOpenChange={(o) => { if (!o) setPostCreateProduct(null) }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ChefHat className="h-5 w-5 text-sky-600" /> Product created successfully
            </DialogTitle>
          </DialogHeader>
          <p className="text-sm text-slate-600">
            Do you want to set up the production recipe for <span className="font-medium">{postCreateProduct?.name}</span> now?
            The recipe tells the app which raw materials are used to produce one bag, so production batches auto-load them.
          </p>
          <DialogFooter className="gap-2">
            <Button variant="ghost" onClick={() => setPostCreateProduct(null)}>Later</Button>
            <Button onClick={() => {
              const id = postCreateProduct?.waterProductId
              setPostCreateProduct(null)
              if (id) router.push(`/water-products/${id}`)
            }}>
              Add recipe
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function ProductDialog({
  open, onOpenChange, title, form, setForm, saving, onSubmit,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  title: string
  form: WaterProductInput
  setForm: (f: WaterProductInput) => void
  saving: boolean
  onSubmit: () => void
}) {
  const isEdit = /edit/i.test(title)
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {isEdit ? <Pencil className="w-5 h-5 text-blue-600" /> : <ShoppingBag className="w-5 h-5 text-blue-600" />}
            {title}
          </DialogTitle>
          <DialogDescription>{isEdit ? "Update the product details below" : "Add a new product to your catalog"}</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Basics" color="indigo">
            <FormField label="Name *" full>
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            </FormField>
            <FormField label="Product type" full>
              <Select value={form.productType ?? "FinishedGood"} onValueChange={(v) => setForm({ ...form, productType: v as WaterProductType })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{PRODUCT_TYPES.map(t => (
                  <SelectItem key={t.value} value={t.value}>{t.label}{t.hint ? ` — ${t.hint}` : ""}</SelectItem>
                ))}</SelectContent>
              </Select>
            </FormField>
            <FormField label="SKU">
              <Input value={form.sku ?? ""} onChange={(e) => setForm({ ...form, sku: e.target.value })} />
            </FormField>
            <FormField label="Unit">
              <Input placeholder="sachet / bottle / gallon" value={form.unit ?? ""} onChange={(e) => setForm({ ...form, unit: e.target.value })} />
            </FormField>
          </FormSection>

          <FormSection title="Details" color="blue">
            <FormField label="Size (ml)">
              <NumberInput value={form.sizeMl ?? ""} onChange={(e) => setForm({ ...form, sizeMl: e.target.value === "" ? undefined : parseInt(e.target.value, 10) })} />
            </FormField>
            <FormField label="Unit price *">
              <NumberInput min={0} step="0.01" value={form.unitPrice} onChange={(e) => setForm({ ...form, unitPrice: parseFloat(e.target.value || "0") })} />
            </FormField>
            <FormField label="Active" full>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={form.isActive ?? true} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} />
                Active (visible in sales)
              </label>
            </FormField>
          </FormSection>

          <FormSection title="Notes" color="green" columns={1}>
            <FormField label="Notes">
              <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
            </FormField>
          </FormSection>

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => onOpenChange(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={onSubmit} disabled={saving}>
              {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save"}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

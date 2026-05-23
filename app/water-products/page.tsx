"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Plus, Pencil, Trash2, Loader2, ShoppingBag, AlertCircle, PackagePlus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterProducts, createWaterProduct, updateWaterProduct, deleteWaterProduct,
  addWaterStockTransaction, type WaterProduct, type WaterProductInput,
} from "@/lib/api/water"

const EMPTY: WaterProductInput = { name: "", sku: "", sizeMl: undefined, unit: "sachet", unitPrice: 0, isActive: true, notes: "" }

export default function WaterProductsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [products, setProducts] = useState<WaterProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [createOpen, setCreateOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [restockOpen, setRestockOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<WaterProductInput>(EMPTY)
  const [editId, setEditId] = useState<number | null>(null)
  const [restockProduct, setRestockProduct] = useState<WaterProduct | null>(null)
  const [restockQty, setRestockQty] = useState<number>(0)
  const [restockCost, setRestockCost] = useState<number | undefined>(undefined)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") {
      router.replace("/dashboard")
      return
    }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try { setProducts(await listWaterProducts()) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  async function handleCreate() {
    if (!form.name.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      await createWaterProduct(form)
      toast({ title: "Product created" })
      setCreateOpen(false); setForm(EMPTY); await load()
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function openEdit(p: WaterProduct) {
    setEditId(p.waterProductId)
    setForm({ name: p.name, sku: p.sku ?? "", sizeMl: p.sizeMl ?? undefined, unit: p.unit ?? "", unitPrice: p.unitPrice, isActive: p.isActive, notes: p.notes ?? "" })
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

  async function handleDelete(p: WaterProduct) {
    if (!confirm(`Delete or deactivate "${p.name}"?`)) return
    try {
      await deleteWaterProduct(p.waterProductId)
      toast({ title: "Removed" })
      await load()
    } catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
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
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <ShoppingBag className="h-6 w-6 text-sky-600" /> Water products
            </h1>
            <Button onClick={() => { setForm(EMPTY); setCreateOpen(true) }}>
              <Plus className="h-4 w-4 mr-1" /> New product
            </Button>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700">
                <AlertCircle className="h-4 w-4" /> {error}
              </CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : products.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  No products yet. Click <span className="font-medium">New product</span> to add your first SKU.
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
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
                    {products.map((p) => (
                      <TableRow key={p.waterProductId}>
                        <TableCell className="font-medium">{p.name}</TableCell>
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
                          <Button size="sm" variant="ghost" onClick={() => handleDelete(p)}>
                            <Trash2 className="h-4 w-4 text-red-500" />
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
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
        <DialogContent>
          <DialogHeader><DialogTitle>Add stock — {restockProduct?.name}</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Quantity</Label>
              <Input type="number" min={1} value={restockQty || ""} onChange={(e) => setRestockQty(parseInt(e.target.value || "0", 10))} /></div>
            <div><Label>Unit cost (optional)</Label>
              <Input type="number" min={0} step="0.01" value={restockCost ?? ""} onChange={(e) => setRestockCost(e.target.value === "" ? undefined : parseFloat(e.target.value))} /></div>
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setRestockOpen(false)}>Cancel</Button>
              <Button onClick={handleRestock} disabled={saving}>{saving ? "Saving…" : "Add stock"}</Button>
            </div>
          </div>
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
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>{title}</DialogTitle></DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="col-span-2"><Label>Name *</Label>
            <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></div>
          <div><Label>SKU</Label>
            <Input value={form.sku ?? ""} onChange={(e) => setForm({ ...form, sku: e.target.value })} /></div>
          <div><Label>Unit</Label>
            <Input placeholder="sachet / bottle / gallon" value={form.unit ?? ""} onChange={(e) => setForm({ ...form, unit: e.target.value })} /></div>
          <div><Label>Size (ml)</Label>
            <Input type="number" value={form.sizeMl ?? ""} onChange={(e) => setForm({ ...form, sizeMl: e.target.value === "" ? undefined : parseInt(e.target.value, 10) })} /></div>
          <div><Label>Unit price *</Label>
            <Input type="number" min={0} step="0.01" value={form.unitPrice} onChange={(e) => setForm({ ...form, unitPrice: parseFloat(e.target.value || "0") })} /></div>
          <div className="col-span-2"><Label>Notes</Label>
            <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>
          <label className="col-span-2 flex items-center gap-2 text-sm">
            <input type="checkbox" checked={form.isActive ?? true} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} />
            Active (visible in sales)
          </label>
        </div>
        <div className="flex justify-end gap-2 pt-3">
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={onSubmit} disabled={saving}>{saving ? "Saving…" : "Save"}</Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Loader2, ShoppingBag, Plus, Pencil, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getProducts, createGenericProduct, updateGenericProduct, deleteGenericProduct,
  type GenericProduct, type GenericProductInput,
} from "@/lib/api/generic"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

const EMPTY_FORM = {
  productName: "",
  sku: "",
  barcode: "",
  unitOfMeasure: "",
  costPrice: "0",
  sellingPrice: "0",
  wholesalePrice: "",
  retailPrice: "",
  openingStock: "0",
  minimumStockAlert: "0",
  trackInventory: true,
  isActive: true,
  notes: "",
}

export default function GenericProductsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<GenericProduct | null>(null)
  const [form, setForm] = useState(EMPTY_FORM)

  const openNew = () => { setEditingId(null); setForm(EMPTY_FORM); setOpen(true) }
  const openEdit = (p: GenericProduct) => {
    setEditingId(p.genericProductId)
    setForm({
      productName: p.productName,
      sku: p.sku ?? "",
      barcode: p.barcode ?? "",
      unitOfMeasure: p.unitOfMeasure ?? "",
      costPrice: String(p.costPrice),
      sellingPrice: String(p.sellingPrice),
      wholesalePrice: p.wholesalePrice != null ? String(p.wholesalePrice) : "",
      retailPrice: p.retailPrice != null ? String(p.retailPrice) : "",
      openingStock: String(p.openingStock),
      minimumStockAlert: String(p.minimumStockAlert),
      trackInventory: p.trackInventory,
      isActive: p.isActive,
      notes: p.notes ?? "",
    })
    setOpen(true)
  }

  const load = async () => {
    setLoading(true)
    try {
      setRows(await getProducts())
    } catch (e: any) {
      toast({ title: "Could not load products", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const onSave = async () => {
    if (!form.productName.trim()) {
      toast({ title: "Product name is required", variant: "destructive" })
      return
    }
    const cost = Number(form.costPrice); const sell = Number(form.sellingPrice)
    if (Number.isNaN(cost) || cost < 0) return toast({ title: "Cost price must be 0 or more", variant: "destructive" })
    if (Number.isNaN(sell) || sell < 0) return toast({ title: "Selling price must be 0 or more", variant: "destructive" })

    const opt = (s: string) => s.trim() === "" ? null : Number(s)
    const optStr = (s: string) => s.trim() === "" ? null : s.trim()

    setSaving(true)
    try {
      const input: GenericProductInput = {
        productName: form.productName.trim(),
        sku: optStr(form.sku),
        barcode: optStr(form.barcode),
        unitOfMeasure: optStr(form.unitOfMeasure),
        costPrice: cost,
        sellingPrice: sell,
        wholesalePrice: opt(form.wholesalePrice),
        retailPrice: opt(form.retailPrice),
        openingStock: Number(form.openingStock) || 0,
        minimumStockAlert: Number(form.minimumStockAlert) || 0,
        trackInventory: form.trackInventory,
        isActive: form.isActive,
        notes: optStr(form.notes),
      }
      if (editingId != null) {
        await updateGenericProduct(editingId, input)
        toast({ title: `Product updated.` })
      } else {
        const created = await createGenericProduct(input)
        if (created) toast({ title: `Product "${created.productName}" created.` })
      }
      setOpen(false)
      setForm(EMPTY_FORM)
      setEditingId(null)
      await load()
    } catch (e: any) {
      toast({ title: editingId != null ? "Could not save changes" : "Could not create product", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <ShoppingBag className="h-6 w-6 text-emerald-600" /> Products
              </h1>
              <p className="text-sm text-slate-500">{rows.length} product(s)</p>
            </div>
            <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) setEditingId(null) }}>
              <DialogTrigger asChild>
                <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" />New product</Button>
              </DialogTrigger>
              <DialogContent className="max-w-2xl">
                <DialogHeader>
                  <DialogTitle>{editingId != null ? "Edit product" : "New product"}</DialogTitle>
                  <DialogDescription>Add a product or item your business sells. Turn off "Track inventory" for services or items you don't count stock for.</DialogDescription>
                </DialogHeader>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div className="md:col-span-2">
                    <Label>Product name *</Label>
                    <Input value={form.productName} onChange={(e) => setForm((f) => ({ ...f, productName: e.target.value }))} maxLength={200} />
                  </div>
                  <div>
                    <Label>SKU (code)</Label>
                    <Input value={form.sku} onChange={(e) => setForm((f) => ({ ...f, sku: e.target.value }))} maxLength={60} />
                  </div>
                  <div>
                    <Label>Barcode</Label>
                    <Input value={form.barcode} onChange={(e) => setForm((f) => ({ ...f, barcode: e.target.value }))} maxLength={60} />
                  </div>
                  <div>
                    <Label>Unit (e.g. piece, kg)</Label>
                    <Input value={form.unitOfMeasure} onChange={(e) => setForm((f) => ({ ...f, unitOfMeasure: e.target.value }))} maxLength={30} />
                  </div>
                  <div>
                    <Label>Cost price *</Label>
                    <Input type="number" step="0.01" min="0" value={form.costPrice} onChange={(e) => setForm((f) => ({ ...f, costPrice: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Selling price *</Label>
                    <Input type="number" step="0.01" min="0" value={form.sellingPrice} onChange={(e) => setForm((f) => ({ ...f, sellingPrice: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Wholesale price (optional)</Label>
                    <Input type="number" step="0.01" min="0" value={form.wholesalePrice} onChange={(e) => setForm((f) => ({ ...f, wholesalePrice: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Retail price (optional)</Label>
                    <Input type="number" step="0.01" min="0" value={form.retailPrice} onChange={(e) => setForm((f) => ({ ...f, retailPrice: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Opening stock</Label>
                    <Input type="number" step="0.01" min="0" value={form.openingStock} onChange={(e) => setForm((f) => ({ ...f, openingStock: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Low-stock alert at</Label>
                    <Input type="number" step="0.01" min="0" value={form.minimumStockAlert} onChange={(e) => setForm((f) => ({ ...f, minimumStockAlert: e.target.value }))} />
                  </div>
                  <div className="md:col-span-2 flex items-center gap-3">
                    <Switch checked={form.trackInventory} onCheckedChange={(v) => setForm((f) => ({ ...f, trackInventory: v }))} id="track" />
                    <Label htmlFor="track" className="cursor-pointer">Track inventory (uncheck for services or non-stocked items)</Label>
                  </div>
                  <div className="md:col-span-2 flex items-center gap-3">
                    <Switch checked={form.isActive} onCheckedChange={(v) => setForm((f) => ({ ...f, isActive: v }))} id="active" />
                    <Label htmlFor="active" className="cursor-pointer">Active (uncheck to hide from sales without deleting)</Label>
                  </div>
                  <div className="md:col-span-2">
                    <Label>Notes</Label>
                    <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                  </div>
                </div>
                <DialogFooter>
                  <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                  <Button onClick={onSave} disabled={saving}>{saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}{editingId != null ? "Save changes" : "Create"}</Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No products yet. Create your first one.</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
                      <TableHead>SKU</TableHead>
                      <TableHead>Category</TableHead>
                      <TableHead className="text-right">Cost</TableHead>
                      <TableHead className="text-right">Selling</TableHead>
                      <TableHead className="text-right">Stock</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((p) => {
                      const isLow = p.trackInventory && p.currentStock <= p.minimumStockAlert
                      return (
                        <TableRow key={p.genericProductId}>
                          <TableCell>
                            <div className="font-medium">{p.productName}</div>
                            {p.unitOfMeasure && <div className="text-xs text-slate-500">/ {p.unitOfMeasure}</div>}
                          </TableCell>
                          <TableCell className="font-mono text-xs">{p.sku ?? "—"}</TableCell>
                          <TableCell>{p.categoryName ?? "—"}</TableCell>
                          <TableCell className="text-right">{fmt(p.costPrice)}</TableCell>
                          <TableCell className="text-right">{fmt(p.sellingPrice)}</TableCell>
                          <TableCell className="text-right">
                            {p.trackInventory ? p.currentStock.toLocaleString(undefined, { maximumFractionDigits: 3 }) : <span className="text-slate-400">n/a</span>}
                          </TableCell>
                          <TableCell>
                            {!p.isActive ? <Badge variant="secondary">Inactive</Badge>
                              : isLow ? <Badge className="bg-rose-100 text-rose-800 hover:bg-rose-100">Low stock</Badge>
                              : <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">OK</Badge>}
                          </TableCell>
                          <TableCell className="text-right">
                            <Button size="sm" variant="ghost" onClick={() => openEdit(p)} title="Edit"><Pencil className="h-4 w-4" /></Button>
                            <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(p)} title="Delete"><Trash2 className="h-4 w-4 text-red-500" /></Button>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete product?"
        itemLabel={deleteTarget?.productName}
        description={deleteTarget?.trackInventory && deleteTarget.currentStock > 0
          ? `"${deleteTarget.productName}" has ${deleteTarget.currentStock} units in stock. Backend will refuse if it's tied to sales or purchases — deactivate from the edit form to hide instead.`
          : undefined}
        successTitle="Product deleted"
        errorTitle="Delete failed"
        onConfirm={async () => {
          if (deleteTarget) {
            await deleteGenericProduct(deleteTarget.genericProductId)
            await load()
          }
        }}
      />
    </div>
  )
}

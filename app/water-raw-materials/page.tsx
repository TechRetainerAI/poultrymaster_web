"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Loader2, Box, AlertCircle, ShoppingCart, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterRawMaterialItems, createWaterRawMaterialItem, updateWaterRawMaterialItem, deleteWaterRawMaterialItem,
  listWaterRawMaterialPurchases, createWaterRawMaterialPurchase, updateWaterRawMaterialPurchase, deleteWaterRawMaterialPurchase,
  type WaterRawMaterialItem, type WaterRawMaterialPurchase,
} from "@/lib/api/water"

function gh(n: number) { return `GHC ${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` }

const CATEGORIES = ["PackagingRoll","SachetFilm","OuterBag","Chemical","Filter","UVLamp","SparePart","Fuel","CleaningSupply","Other"]
const PAYMENT_METHODS = ["Cash","MoMo","Bank","Credit"]

type ItemForm = Omit<WaterRawMaterialItem, "waterRawMaterialItemId" | "farmId" | "currentQuantity">
const EMPTY_ITEM: ItemForm = { itemName: "", category: "PackagingRoll", unitOfMeasure: "", minimumStockAlert: 0, isActive: true, notes: null }

export default function WaterRawMaterialsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<WaterRawMaterialItem[]>([])
  const [purchases, setPurchases] = useState<WaterRawMaterialPurchase[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [itemOpen, setItemOpen] = useState(false)
  const [editItemId, setEditItemId] = useState<number | null>(null)
  const [itemForm, setItemForm] = useState<ItemForm>(EMPTY_ITEM)
  const [deleteItemTarget, setDeleteItemTarget] = useState<WaterRawMaterialItem | null>(null)

  const [purchaseOpen, setPurchaseOpen] = useState(false)
  const [editPurchaseId, setEditPurchaseId] = useState<number | null>(null)
  const [purchaseForm, setPurchaseForm] = useState({
    waterRawMaterialItemId: 0, supplierId: null as number | null, purchaseDate: new Date().toISOString().split("T")[0],
    quantity: 0, unitCost: 0, paymentMethod: "Cash", amountPaid: 0, receiptUrl: "", notes: "",
  })
  const [deletePurchaseTarget, setDeletePurchaseTarget] = useState<WaterRawMaterialPurchase | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try { const [is, ps] = await Promise.all([listWaterRawMaterialItems(), listWaterRawMaterialPurchases()]); setItems(is); setPurchases(ps) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  function openNewItem() { setEditItemId(null); setItemForm(EMPTY_ITEM); setItemOpen(true) }
  function openEditItem(it: WaterRawMaterialItem) {
    setEditItemId(it.waterRawMaterialItemId)
    setItemForm({ itemName: it.itemName, category: it.category, unitOfMeasure: it.unitOfMeasure, minimumStockAlert: it.minimumStockAlert, isActive: it.isActive, notes: it.notes })
    setItemOpen(true)
  }

  async function saveItem() {
    if (!itemForm.itemName.trim()) return toast({ title: "Item name required", variant: "destructive" })
    try {
      if (editItemId) { await updateWaterRawMaterialItem(editItemId, itemForm); toast({ title: "Item updated" }) }
      else { await createWaterRawMaterialItem(itemForm); toast({ title: "Item added" }) }
      setItemOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
  }

  function openNewPurchase() {
    setEditPurchaseId(null)
    setPurchaseForm({
      waterRawMaterialItemId: items[0]?.waterRawMaterialItemId ?? 0,
      supplierId: null, purchaseDate: new Date().toISOString().split("T")[0],
      quantity: 0, unitCost: 0, paymentMethod: "Cash", amountPaid: 0, receiptUrl: "", notes: "",
    })
    setPurchaseOpen(true)
  }

  function openEditPurchase(p: WaterRawMaterialPurchase) {
    setEditPurchaseId(p.waterRawMaterialPurchaseId)
    setPurchaseForm({
      waterRawMaterialItemId: p.waterRawMaterialItemId,
      supplierId: null,
      purchaseDate: p.purchaseDate.split("T")[0],
      quantity: p.quantity,
      unitCost: p.unitCost,
      paymentMethod: p.paymentMethod ?? "Cash",
      amountPaid: p.amountPaid ?? 0,
      receiptUrl: p.receiptUrl ?? "",
      notes: p.notes ?? "",
    })
    setPurchaseOpen(true)
  }

  async function savePurchase() {
    if (!purchaseForm.waterRawMaterialItemId) return toast({ title: "Pick an item", variant: "destructive" })
    if (purchaseForm.quantity <= 0) return toast({ title: "Quantity must be > 0", variant: "destructive" })
    try {
      if (editPurchaseId != null) {
        await updateWaterRawMaterialPurchase(editPurchaseId, {
          purchaseDate: purchaseForm.purchaseDate,
          quantity: purchaseForm.quantity,
          unitCost: purchaseForm.unitCost,
          paymentMethod: purchaseForm.paymentMethod,
          amountPaid: purchaseForm.amountPaid,
          receiptUrl: purchaseForm.receiptUrl || null,
          notes: purchaseForm.notes || null,
        } as any)
        toast({ title: "Purchase updated — stock adjusted" })
      } else {
        await createWaterRawMaterialPurchase({
          ...purchaseForm,
          receiptUrl: purchaseForm.receiptUrl || null,
          notes: purchaseForm.notes || null,
        } as any)
        toast({ title: "Purchase recorded — stock updated" })
      }
      setPurchaseOpen(false); setEditPurchaseId(null); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
  }

  const lowStock = useMemo(() => items.filter(i => i.isActive && (i.currentQuantity ?? 0) <= (i.minimumStockAlert ?? 0)), [items])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Box className="h-6 w-6 text-sky-600" /> Raw materials
            </h1>
            <div className="flex gap-2">
              <Button variant="outline" onClick={openNewItem}><Plus className="h-4 w-4 mr-1" /> New item</Button>
              <Button onClick={openNewPurchase}><ShoppingCart className="h-4 w-4 mr-1" /> Record purchase</Button>
            </div>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700"><AlertCircle className="h-4 w-4" /> {error}</CardContent>
            </Card>
          )}

          {lowStock.length > 0 && (
            <Card className="border-amber-200 bg-amber-50 mb-4">
              <CardContent className="p-3">
                <div className="font-medium text-amber-900 mb-1">Low-stock items ({lowStock.length})</div>
                <div className="text-sm text-slate-700">{lowStock.map(i => `${i.itemName} (${i.currentQuantity ?? 0} / min ${i.minimumStockAlert ?? 0})`).join(" · ")}</div>
              </CardContent>
            </Card>
          )}

          <Tabs defaultValue="items">
            <TabsList>
              <TabsTrigger value="items">Items ({items.length})</TabsTrigger>
              <TabsTrigger value="purchases">Purchases ({purchases.length})</TabsTrigger>
            </TabsList>

            <TabsContent value="items">
              <Card>
                <CardContent className="p-0">
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : items.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No raw material items yet.</div>
                  ) : (
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Name</TableHead><TableHead>Category</TableHead><TableHead>Unit</TableHead><TableHead className="text-right">Current</TableHead><TableHead className="text-right">Min alert</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {items.map((it) => {
                          const low = (it.currentQuantity ?? 0) <= (it.minimumStockAlert ?? 0)
                          return (
                            <TableRow key={it.waterRawMaterialItemId}>
                              <TableCell className="font-medium">{it.itemName}</TableCell>
                              <TableCell><Badge variant="outline">{it.category}</Badge></TableCell>
                              <TableCell>{it.unitOfMeasure ?? "—"}</TableCell>
                              <TableCell className={`text-right tabular-nums ${low ? "text-rose-600 font-semibold" : ""}`}>{it.currentQuantity ?? 0}</TableCell>
                              <TableCell className="text-right tabular-nums">{it.minimumStockAlert ?? 0}</TableCell>
                              <TableCell>{it.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                              <TableCell className="text-right">
                                <Button size="sm" variant="ghost" onClick={() => openEditItem(it)}><Pencil className="h-4 w-4" /></Button>
                                <Button size="sm" variant="ghost" onClick={() => setDeleteItemTarget(it)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                              </TableCell>
                            </TableRow>
                          )
                        })}
                      </TableBody>
                    </Table>
                  )}
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="purchases">
              <Card>
                <CardContent className="p-0">
                  {purchases.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No purchases recorded yet.</div>
                  ) : (
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Date</TableHead><TableHead>Item</TableHead><TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Unit cost</TableHead><TableHead className="text-right">Total</TableHead><TableHead>Method</TableHead><TableHead className="text-right">Balance</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {purchases.map((p) => (
                          <TableRow key={p.waterRawMaterialPurchaseId}>
                            <TableCell>{p.purchaseDate.split("T")[0]}</TableCell>
                            <TableCell>{p.itemName ?? items.find(i => i.waterRawMaterialItemId === p.waterRawMaterialItemId)?.itemName ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{p.quantity}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(p.unitCost)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(p.totalCost ?? p.quantity * p.unitCost)}</TableCell>
                            <TableCell>{p.paymentMethod ?? "—"}</TableCell>
                            <TableCell className={`text-right tabular-nums ${(p.balance ?? 0) > 0 ? "text-rose-600" : ""}`}>{gh(p.balance ?? 0)}</TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openEditPurchase(p)}><Pencil className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeletePurchaseTarget(p)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  )}
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </main>
      </div>

      {/* Item dialog */}
      <Dialog open={itemOpen} onOpenChange={setItemOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>{editItemId ? "Edit item" : "New item"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Item name *</Label>
              <Input value={itemForm.itemName} onChange={(e) => setItemForm({ ...itemForm, itemName: e.target.value })} /></div>
            <div><Label>Category</Label>
              <Select value={itemForm.category} onValueChange={(v) => setItemForm({ ...itemForm, category: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{CATEGORIES.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Unit</Label>
              <Input value={itemForm.unitOfMeasure ?? ""} onChange={(e) => setItemForm({ ...itemForm, unitOfMeasure: e.target.value || null })} placeholder="kg / roll / pcs" /></div>
            <div className="col-span-2"><Label>Minimum stock alert</Label>
              <Input type="number" min={0} value={itemForm.minimumStockAlert ?? 0} onChange={(e) => setItemForm({ ...itemForm, minimumStockAlert: Number(e.target.value) || 0 })} /></div>
            <div className="col-span-2"><Label>Notes</Label>
              <Input value={itemForm.notes ?? ""} onChange={(e) => setItemForm({ ...itemForm, notes: e.target.value || null })} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setItemOpen(false)}>Cancel</Button>
            <Button onClick={saveItem}>Save</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Purchase dialog */}
      <Dialog open={purchaseOpen} onOpenChange={(o) => { setPurchaseOpen(o); if (!o) setEditPurchaseId(null) }}>
        <DialogContent>
          <DialogHeader><DialogTitle>{editPurchaseId != null ? "Edit purchase" : "Record raw material purchase"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Item{editPurchaseId != null && <span className="text-xs text-slate-500 ml-2">(fixed — delete and recreate to change item)</span>}</Label>
              <Select value={String(purchaseForm.waterRawMaterialItemId)} onValueChange={(v) => setPurchaseForm({ ...purchaseForm, waterRawMaterialItemId: Number(v) })} disabled={editPurchaseId != null}>
                <SelectTrigger><SelectValue placeholder="Pick item" /></SelectTrigger>
                <SelectContent>{items.filter(i => i.isActive || i.waterRawMaterialItemId === purchaseForm.waterRawMaterialItemId).map(i => <SelectItem key={i.waterRawMaterialItemId} value={String(i.waterRawMaterialItemId)}>{i.itemName} ({i.unitOfMeasure ?? "—"})</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Date</Label>
              <Input type="date" value={purchaseForm.purchaseDate} onChange={(e) => setPurchaseForm({ ...purchaseForm, purchaseDate: e.target.value })} /></div>
            <div><Label>Payment method</Label>
              <Select value={purchaseForm.paymentMethod} onValueChange={(v) => setPurchaseForm({ ...purchaseForm, paymentMethod: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{PAYMENT_METHODS.map(p => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent>
              </Select></div>
            <div><Label>Quantity *</Label>
              <Input type="number" min={0} step="0.001" value={purchaseForm.quantity} onChange={(e) => setPurchaseForm({ ...purchaseForm, quantity: Number(e.target.value) || 0 })} /></div>
            <div><Label>Unit cost (GHC) *</Label>
              <Input type="number" min={0} step="0.01" value={purchaseForm.unitCost} onChange={(e) => setPurchaseForm({ ...purchaseForm, unitCost: Number(e.target.value) || 0 })} /></div>
            <div><Label>Amount paid (GHC)</Label>
              <Input type="number" min={0} step="0.01" value={purchaseForm.amountPaid} onChange={(e) => setPurchaseForm({ ...purchaseForm, amountPaid: Number(e.target.value) || 0 })} /></div>
            <div><Label>Receipt URL</Label>
              <Input value={purchaseForm.receiptUrl} onChange={(e) => setPurchaseForm({ ...purchaseForm, receiptUrl: e.target.value })} /></div>
            <div className="col-span-2"><Label>Notes</Label>
              <Input value={purchaseForm.notes} onChange={(e) => setPurchaseForm({ ...purchaseForm, notes: e.target.value })} /></div>
          </div>
          <div className="border-t pt-2 text-sm">
            <span className="text-slate-500">Total:</span> <span className="font-semibold tabular-nums">{gh(purchaseForm.quantity * purchaseForm.unitCost)}</span>
            {" · "}
            <span className="text-slate-500">Balance:</span> <span className="font-semibold tabular-nums">{gh(Math.max((purchaseForm.quantity * purchaseForm.unitCost) - purchaseForm.amountPaid, 0))}</span>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setPurchaseOpen(false)}>Cancel</Button>
            <Button onClick={savePurchase}>{editPurchaseId != null ? "Save changes" : "Record purchase"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deletePurchaseTarget}
        onOpenChange={(o) => { if (!o) setDeletePurchaseTarget(null) }}
        title="Delete purchase?"
        description={deletePurchaseTarget
          ? `This will subtract ${deletePurchaseTarget.quantity} ${items.find(i => i.waterRawMaterialItemId === deletePurchaseTarget.waterRawMaterialItemId)?.unitOfMeasure ?? "units"} of "${deletePurchaseTarget.itemName ?? items.find(i => i.waterRawMaterialItemId === deletePurchaseTarget.waterRawMaterialItemId)?.itemName ?? "this item"}" from current stock. If some has already been used in production, the delete will fail — reverse those usages first.`
          : undefined}
        successTitle="Purchase deleted"
        errorTitle="Delete failed"
        onConfirm={async () => {
          if (deletePurchaseTarget) {
            await deleteWaterRawMaterialPurchase(deletePurchaseTarget.waterRawMaterialPurchaseId)
            await load()
          }
        }}
      />

      <ConfirmDeleteDialog
        open={!!deleteItemTarget}
        onOpenChange={(o) => { if (!o) setDeleteItemTarget(null) }}
        title="Deactivate raw material item?"
        description={deleteItemTarget ? `"${deleteItemTarget.itemName}" will be hidden from new purchases. Existing purchases and usage history stay intact. You can reactivate it later by editing and ticking Active.` : undefined}
        confirmLabel="Deactivate"
        successTitle="Item deactivated"
        errorTitle="Delete failed"
        onConfirm={async () => {
          if (deleteItemTarget) {
            await deleteWaterRawMaterialItem(deleteItemTarget.waterRawMaterialItemId)
            await load()
          }
        }}
      />
    </div>
  )
}

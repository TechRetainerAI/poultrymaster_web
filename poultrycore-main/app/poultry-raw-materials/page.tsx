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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Loader2, Box, ShoppingCart, Trash2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryRawMaterialItems, createPoultryRawMaterialItem, updatePoultryRawMaterialItem, deletePoultryRawMaterialItem,
  listPoultryRawMaterialPurchases, createPoultryRawMaterialPurchase, updatePoultryRawMaterialPurchase, deletePoultryRawMaterialPurchase,
  payPoultryRawMaterialPurchaseBalance, listPoultryRawMaterialUsageHistory,
  type PoultryRawMaterialItem, type PoultryRawMaterialPurchase, type PoultryRawMaterialUsage,
} from "@/lib/api/poultry-inventory"

const CATEGORIES = ["FeedIngredient", "Packaging", "Medication", "Vaccine", "Bedding", "Disinfectant", "SparePart", "Fuel", "Other"]
const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Credit"]
const UNITS = ["Bag", "Sack", "Kilogram", "Gram", "Litre", "Millilitre", "Bottle", "Sachet", "Piece", "Pack", "Carton", "Box", "Bundle", "Dozen", "Crate", "Unit", "Other"]

type ItemForm = { itemName: string; category: string; unitOfMeasure: string; minimumStockAlert: number; isActive: boolean; notes: string | null }
const EMPTY_ITEM: ItemForm = { itemName: "", category: "FeedIngredient", unitOfMeasure: "", minimumStockAlert: 0, isActive: true, notes: null }

const EMPTY_PURCHASE = {
  poultryRawMaterialItemId: 0,
  supplierName: "",
  purchaseDate: new Date().toISOString().split("T")[0],
  quantity: 0,
  unitCost: 0,
  totalPurchaseCost: 0,
  purchaseUnit: "",
  productionUnit: "",
  productionUnitsPerPurchaseUnit: 1,
  paymentMethod: "Cash",
  amountPaid: 0,
  receiptUrl: "",
  notes: "",
}

export default function PoultryRawMaterialsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [purchases, setPurchases] = useState<PoultryRawMaterialPurchase[]>([])
  const [usage, setUsage] = useState<PoultryRawMaterialUsage[]>([])
  const [usageLoaded, setUsageLoaded] = useState(false)
  const [loading, setLoading] = useState(true)

  const [itemOpen, setItemOpen] = useState(false)
  const [editItemId, setEditItemId] = useState<number | null>(null)
  const [itemForm, setItemForm] = useState<ItemForm>(EMPTY_ITEM)
  const [deleteItemTarget, setDeleteItemTarget] = useState<PoultryRawMaterialItem | null>(null)
  const [savingItem, setSavingItem] = useState(false)

  const [purchaseOpen, setPurchaseOpen] = useState(false)
  const [editPurchaseId, setEditPurchaseId] = useState<number | null>(null)
  const [purchaseForm, setPurchaseForm] = useState({ ...EMPTY_PURCHASE })
  const [deletePurchaseTarget, setDeletePurchaseTarget] = useState<PoultryRawMaterialPurchase | null>(null)
  const [savingPurchase, setSavingPurchase] = useState(false)

  const [payTarget, setPayTarget] = useState<PoultryRawMaterialPurchase | null>(null)
  const [payForm, setPayForm] = useState({ amount: 0, paymentMethod: "Cash", paymentDate: new Date().toISOString().split("T")[0] })
  const [paySaving, setPaySaving] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [is, ps] = await Promise.all([listPoultryRawMaterialItems(), listPoultryRawMaterialPurchases()])
      setItems(is); setPurchases(ps)
    } catch (e: any) {
      toast({ title: "Could not load raw materials", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function loadUsage() {
    if (usageLoaded) return
    try { setUsage(await listPoultryRawMaterialUsageHistory()); setUsageLoaded(true) }
    catch (e: any) { toast({ title: "Could not load usage history", description: e?.message, variant: "destructive" }) }
  }

  const itemById = useMemo(() => new Map(items.map((i) => [i.poultryRawMaterialItemId, i])), [items])
  const unitOptions = (current?: string | null) => {
    const set = [...UNITS]; const c = (current ?? "").trim()
    if (c && !set.includes(c)) set.unshift(c)
    return set
  }

  // ---- Item CRUD ----
  function openNewItem() { setEditItemId(null); setItemForm(EMPTY_ITEM); setItemOpen(true) }
  function openEditItem(i: PoultryRawMaterialItem) {
    setEditItemId(i.poultryRawMaterialItemId)
    setItemForm({ itemName: i.itemName, category: i.category, unitOfMeasure: i.unitOfMeasure ?? "", minimumStockAlert: i.minimumStockAlert, isActive: i.isActive, notes: i.notes ?? null })
    setItemOpen(true)
  }
  async function saveItem() {
    if (!itemForm.itemName.trim()) { toast({ title: "Item name is required", variant: "destructive" }); return }
    setSavingItem(true)
    try {
      if (editItemId) await updatePoultryRawMaterialItem(editItemId, itemForm)
      else await createPoultryRawMaterialItem(itemForm)
      toast({ title: editItemId ? "Item updated" : "Item added" })
      setItemOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSavingItem(false) }
  }
  async function confirmDeleteItem() {
    if (!deleteItemTarget) return
    try { await deletePoultryRawMaterialItem(deleteItemTarget.poultryRawMaterialItemId); toast({ title: "Item removed" }); setDeleteItemTarget(null); await load() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  // ---- Purchase CRUD ----
  function openNewPurchase() { setEditPurchaseId(null); setPurchaseForm({ ...EMPTY_PURCHASE }); setPurchaseOpen(true) }
  function openEditPurchase(p: PoultryRawMaterialPurchase) {
    setEditPurchaseId(p.poultryRawMaterialPurchaseId)
    setPurchaseForm({
      poultryRawMaterialItemId: p.poultryRawMaterialItemId,
      supplierName: p.supplierName ?? "",
      purchaseDate: (p.purchaseDate || "").split("T")[0] || new Date().toISOString().split("T")[0],
      quantity: p.quantity, unitCost: p.unitCost, totalPurchaseCost: p.totalCost,
      purchaseUnit: p.unitOfMeasure ?? "", productionUnit: p.productionUnit ?? "",
      productionUnitsPerPurchaseUnit: p.productionUnitsPerPurchaseUnit ?? 1,
      paymentMethod: p.paymentMethod ?? "Cash", amountPaid: p.amountPaid, receiptUrl: p.receiptUrl ?? "", notes: p.notes ?? "",
    })
    setPurchaseOpen(true)
  }
  async function savePurchase() {
    const f = purchaseForm
    if (!f.poultryRawMaterialItemId) { toast({ title: "Pick a raw material item", variant: "destructive" }); return }
    if (f.quantity <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    const total = f.totalPurchaseCost > 0 ? f.totalPurchaseCost : f.quantity * f.unitCost
    const payload = {
      poultryRawMaterialItemId: f.poultryRawMaterialItemId,
      supplierName: f.supplierName || null,
      purchaseDate: f.purchaseDate,
      quantity: f.quantity,
      unitCost: f.quantity > 0 ? Number((total / f.quantity).toFixed(4)) : f.unitCost,
      totalCost: total,
      productionUnit: f.productionUnit || null,
      productionUnitsPerPurchaseUnit: f.productionUnitsPerPurchaseUnit || null,
      paymentMethod: f.paymentMethod,
      amountPaid: f.amountPaid,
      receiptUrl: f.receiptUrl || null,
      notes: f.notes || null,
    }
    setSavingPurchase(true)
    try {
      if (editPurchaseId) await updatePoultryRawMaterialPurchase(editPurchaseId, payload)
      else await createPoultryRawMaterialPurchase(payload)
      toast({ title: editPurchaseId ? "Purchase updated" : "Purchase recorded" })
      setPurchaseOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSavingPurchase(false) }
  }
  async function confirmDeletePurchase() {
    if (!deletePurchaseTarget) return
    try { await deletePoultryRawMaterialPurchase(deletePurchaseTarget.poultryRawMaterialPurchaseId); toast({ title: "Purchase removed" }); setDeletePurchaseTarget(null); await load() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  function openPayBalance(p: PoultryRawMaterialPurchase) {
    setPayTarget(p); setPayForm({ amount: p.balance ?? 0, paymentMethod: "Cash", paymentDate: new Date().toISOString().split("T")[0] })
  }
  async function submitPayBalance() {
    if (!payTarget) return
    const outstanding = payTarget.balance ?? 0
    if (payForm.amount <= 0) { toast({ title: "Enter an amount greater than 0", variant: "destructive" }); return }
    if (payForm.amount > outstanding) { toast({ title: `Amount exceeds the outstanding balance (${gh(outstanding)})`, variant: "destructive" }); return }
    setPaySaving(true)
    try {
      await payPoultryRawMaterialPurchaseBalance(payTarget.poultryRawMaterialPurchaseId, { amount: payForm.amount, paymentMethod: payForm.paymentMethod, paymentDate: payForm.paymentDate })
      toast({ title: "Balance payment recorded" }); setPayTarget(null); await load()
    } catch (e: any) { toast({ title: "Could not record payment", description: e?.message, variant: "destructive" }) }
    finally { setPaySaving(false) }
  }

  const roCls = "bg-slate-100 text-slate-600 font-medium pointer-events-none cursor-default border-dashed"

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold">Raw Materials &amp; Supplies</h1>
              <p className="text-sm text-slate-500">Track feed inputs, packaging, medication and other supplies — purchases, costing and usage.</p>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
          ) : (
            <Tabs defaultValue="items" onValueChange={(v) => { if (v === "usage") void loadUsage() }}>
              <TabsList>
                <TabsTrigger value="items"><Box className="w-4 h-4 mr-1" /> Items</TabsTrigger>
                <TabsTrigger value="purchases"><ShoppingCart className="w-4 h-4 mr-1" /> Purchases</TabsTrigger>
                <TabsTrigger value="usage"><Wallet className="w-4 h-4 mr-1" /> Usage History</TabsTrigger>
              </TabsList>

              {/* ITEMS */}
              <TabsContent value="items">
                <Card><CardContent className="p-4">
                  <div className="flex justify-end mb-3"><Button onClick={openNewItem}><Plus className="w-4 h-4 mr-1" /> New item</Button></div>
                  <Table>
                    <TableHeader><TableRow>
                      <TableHead>Item</TableHead><TableHead>Category</TableHead><TableHead>Unit</TableHead>
                      <TableHead className="text-right">In stock</TableHead><TableHead className="text-right">Min alert</TableHead>
                      <TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {items.length === 0 ? (
                        <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">No items yet.</TableCell></TableRow>
                      ) : items.map((i) => (
                        <TableRow key={i.poultryRawMaterialItemId}>
                          <TableCell className="font-medium">{i.itemName}</TableCell>
                          <TableCell>{i.category}</TableCell>
                          <TableCell>{i.unitOfMeasure ?? "—"}</TableCell>
                          <TableCell className="text-right">{i.currentQuantity.toLocaleString()}</TableCell>
                          <TableCell className="text-right">{i.minimumStockAlert.toLocaleString()}</TableCell>
                          <TableCell>
                            {!i.isActive ? <Badge variant="secondary">Inactive</Badge>
                              : i.isLowStock ? <Badge className="bg-amber-100 text-amber-700">Low stock</Badge>
                              : <Badge className="bg-green-100 text-green-700">OK</Badge>}
                          </TableCell>
                          <TableCell className="text-right">
                            <Button variant="ghost" size="sm" onClick={() => openEditItem(i)}><Pencil className="w-4 h-4" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDeleteItemTarget(i)}><Trash2 className="w-4 h-4 text-red-500" /></Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent></Card>
              </TabsContent>

              {/* PURCHASES */}
              <TabsContent value="purchases">
                <Card><CardContent className="p-4">
                  <div className="flex justify-end mb-3"><Button onClick={openNewPurchase}><Plus className="w-4 h-4 mr-1" /> New purchase</Button></div>
                  <Table>
                    <TableHeader><TableRow>
                      <TableHead>Date</TableHead><TableHead>Item</TableHead><TableHead>Supplier</TableHead>
                      <TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Total</TableHead>
                      <TableHead className="text-right">Paid</TableHead><TableHead className="text-right">Balance</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {purchases.length === 0 ? (
                        <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-6">No purchases yet.</TableCell></TableRow>
                      ) : purchases.map((p) => (
                        <TableRow key={p.poultryRawMaterialPurchaseId}>
                          <TableCell>{(p.purchaseDate || "").split("T")[0]}</TableCell>
                          <TableCell className="font-medium">{p.itemName}</TableCell>
                          <TableCell>{p.supplierName ?? "—"}</TableCell>
                          <TableCell className="text-right">{p.quantity.toLocaleString()} {p.unitOfMeasure ?? ""}</TableCell>
                          <TableCell className="text-right">{gh(p.totalCost)}</TableCell>
                          <TableCell className="text-right">{gh(p.amountPaid)}</TableCell>
                          <TableCell className="text-right">{p.balance > 0 ? <span className="text-amber-600 font-medium">{gh(p.balance)}</span> : gh(0)}</TableCell>
                          <TableCell className="text-right">
                            {p.balance > 0 && <Button variant="ghost" size="sm" onClick={() => openPayBalance(p)} title="Pay balance"><Wallet className="w-4 h-4 text-emerald-600" /></Button>}
                            <Button variant="ghost" size="sm" onClick={() => openEditPurchase(p)}><Pencil className="w-4 h-4" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDeletePurchaseTarget(p)}><Trash2 className="w-4 h-4 text-red-500" /></Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent></Card>
              </TabsContent>

              {/* USAGE */}
              <TabsContent value="usage">
                <Card><CardContent className="p-4">
                  <Table>
                    <TableHeader><TableRow>
                      <TableHead>Date</TableHead><TableHead>Item</TableHead>
                      <TableHead className="text-right">Used</TableHead><TableHead className="text-right">Expected</TableHead>
                      <TableHead className="text-right">Variance</TableHead><TableHead>Reason</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {usage.length === 0 ? (
                        <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-6">No usage recorded yet. Usage is created when production batches are approved (coming with the production slice).</TableCell></TableRow>
                      ) : usage.map((u) => (
                        <TableRow key={u.poultryRawMaterialUsageId}>
                          <TableCell>{(u.usedDate || "").split("T")[0]}</TableCell>
                          <TableCell className="font-medium">{u.itemName}</TableCell>
                          <TableCell className="text-right">{u.quantityUsed.toLocaleString()} {u.unitOfMeasure ?? ""}</TableCell>
                          <TableCell className="text-right">{u.expectedQuantityUsed?.toLocaleString() ?? "—"}</TableCell>
                          <TableCell className="text-right">{u.variance.toLocaleString()}</TableCell>
                          <TableCell>{u.varianceReason ?? "—"}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent></Card>
              </TabsContent>
            </Tabs>
          )}
        </main>
      </div>

      {/* Item dialog */}
      <Dialog open={itemOpen} onOpenChange={setItemOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>{editItemId ? "Edit item" : "New raw material item"}</DialogTitle></DialogHeader>
          <FormSection title="Item details" color="blue">
            <FormField label="Item name *"><Input value={itemForm.itemName} onChange={(e) => setItemForm({ ...itemForm, itemName: e.target.value })} /></FormField>
            <FormField label="Category *">
              <Select value={itemForm.category} onValueChange={(v) => setItemForm({ ...itemForm, category: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{CATEGORIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Unit of measure">
              <Select value={itemForm.unitOfMeasure || ""} onValueChange={(v) => setItemForm({ ...itemForm, unitOfMeasure: v })}>
                <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                <SelectContent>{unitOptions(itemForm.unitOfMeasure).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Low-stock alert at"><NumberInput min={0} step="0.001" value={itemForm.minimumStockAlert} onChange={(e) => setItemForm({ ...itemForm, minimumStockAlert: Number(e.target.value) || 0 })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setItemOpen(false)}>Cancel</Button>
            <Button onClick={saveItem} disabled={savingItem}>{savingItem ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Purchase dialog */}
      <Dialog open={purchaseOpen} onOpenChange={setPurchaseOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>{editPurchaseId ? "Edit purchase" : "New raw material purchase"}</DialogTitle></DialogHeader>
          {(() => {
            const f = purchaseForm
            const qty = f.quantity || 0
            const total = f.totalPurchaseCost || 0
            const unitCost = qty > 0 ? total / qty : 0
            const perPurchase = f.productionUnitsPerPurchaseUnit || 0
            const prodQty = qty * perPurchase
            const prodUnitCost = prodQty > 0 ? total / prodQty : 0
            const selItem = itemById.get(f.poultryRawMaterialItemId)
            const purchaseUnitLabel = selItem?.unitOfMeasure || f.purchaseUnit || "unit"
            return (
              <>
                <FormSection title="Purchase Quantity & Production Costing" color="blue">
                  <FormField label="Raw material item *">
                    <Select value={f.poultryRawMaterialItemId ? String(f.poultryRawMaterialItemId) : ""} onValueChange={(v) => setPurchaseForm({ ...f, poultryRawMaterialItemId: Number(v) })}>
                      <SelectTrigger><SelectValue placeholder="Pick item" /></SelectTrigger>
                      <SelectContent>{items.filter((i) => i.isActive).map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Purchase quantity *"><NumberInput min={0} step="0.001" value={f.quantity} onChange={(e) => setPurchaseForm({ ...f, quantity: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Total purchase cost *"><NumberInput min={0} step="0.01" value={f.totalPurchaseCost} onChange={(e) => setPurchaseForm({ ...f, totalPurchaseCost: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Purchase unit cost (auto)"><Input readOnly tabIndex={-1} className={roCls} value={`${gh(unitCost)}${purchaseUnitLabel ? ` per ${purchaseUnitLabel}` : ""}`} /></FormField>
                </FormSection>

                <FormSection title="Production Conversion" color="indigo">
                  <FormField label="Production unit">
                    <Select value={f.productionUnit || ""} onValueChange={(v) => setPurchaseForm({ ...f, productionUnit: v })}>
                      <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                      <SelectContent>{unitOptions(f.productionUnit).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Production units per purchase unit"><NumberInput min={0} step="0.0001" value={f.productionUnitsPerPurchaseUnit} onChange={(e) => setPurchaseForm({ ...f, productionUnitsPerPurchaseUnit: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Production-level quantity (auto)"><Input readOnly tabIndex={-1} className={roCls} value={`${prodQty.toLocaleString()}${f.productionUnit ? ` ${f.productionUnit}` : ""}`} /></FormField>
                  <FormField label="Production-level unit cost (auto)"><Input readOnly tabIndex={-1} className={roCls} value={`${gh(prodUnitCost)}${f.productionUnit ? ` per ${f.productionUnit}` : ""}`} /></FormField>
                  <FormField label="" full><p className="text-xs text-slate-500">If you buy and use the same unit, set <span className="font-medium">Production units per purchase unit = 1</span> — the production figures then match the purchase figures.</p></FormField>
                </FormSection>

                <FormSection title="Supplier & Payment" color="amber">
                  <FormField label="Supplier"><Input value={f.supplierName} onChange={(e) => setPurchaseForm({ ...f, supplierName: e.target.value })} placeholder="Supplier name" /></FormField>
                  <FormField label="Purchase date"><Input type="date" value={f.purchaseDate} onChange={(e) => setPurchaseForm({ ...f, purchaseDate: e.target.value })} /></FormField>
                  <FormField label="Payment method">
                    <Select value={f.paymentMethod} onValueChange={(v) => setPurchaseForm({ ...f, paymentMethod: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Amount paid"><NumberInput min={0} step="0.01" value={f.amountPaid} onChange={(e) => setPurchaseForm({ ...f, amountPaid: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Balance (auto)"><Input readOnly tabIndex={-1} className={roCls} value={gh(Math.max(0, total - (f.amountPaid || 0)))} /></FormField>
                </FormSection>

                <div className="flex justify-end gap-2">
                  <Button variant="outline" onClick={() => setPurchaseOpen(false)}>Cancel</Button>
                  <Button onClick={savePurchase} disabled={savingPurchase}>{savingPurchase ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
                </div>
              </>
            )
          })()}
        </DialogContent>
      </Dialog>

      {/* Pay balance dialog */}
      <Dialog open={!!payTarget} onOpenChange={(o) => !o && setPayTarget(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Pay balance</DialogTitle></DialogHeader>
          {payTarget && (
            <FormSection title={`Outstanding: ${gh(payTarget.balance ?? 0)}`} color="emerald">
              <FormField label="Amount"><NumberInput min={0} step="0.01" value={payForm.amount} onChange={(e) => setPayForm({ ...payForm, amount: Number(e.target.value) || 0 })} /></FormField>
              <FormField label="Method">
                <Select value={payForm.paymentMethod} onValueChange={(v) => setPayForm({ ...payForm, paymentMethod: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PAYMENT_METHODS.filter((m) => m !== "Credit").map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Date"><Input type="date" value={payForm.paymentDate} onChange={(e) => setPayForm({ ...payForm, paymentDate: e.target.value })} /></FormField>
            </FormSection>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setPayTarget(null)}>Cancel</Button>
            <Button onClick={submitPayBalance} disabled={paySaving}>{paySaving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Record payment"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog open={!!deleteItemTarget} onOpenChange={(o) => !o && setDeleteItemTarget(null)} onConfirm={confirmDeleteItem} title="Remove item?" description={`Remove "${deleteItemTarget?.itemName}"? If it has purchase/usage history it will be deactivated instead.`} />
      <ConfirmDeleteDialog open={!!deletePurchaseTarget} onOpenChange={(o) => !o && setDeletePurchaseTarget(null)} onConfirm={confirmDeletePurchase} title="Delete purchase?" description="This will reverse the stock it added." />
    </div>
  )
}

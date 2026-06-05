"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Loader2, Box, ShoppingCart, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listWaterRawMaterialItems, createWaterRawMaterialItem, updateWaterRawMaterialItem, deleteWaterRawMaterialItem,
  listWaterRawMaterialPurchases, createWaterRawMaterialPurchase, updateWaterRawMaterialPurchase, deleteWaterRawMaterialPurchase,
  listWaterRawMaterialUsageHistory,
  type WaterRawMaterialItem, type WaterRawMaterialPurchase, type WaterProductionMaterialUsageRow,
} from "@/lib/api/water"
import { SupplierSelect } from "@/components/water/supplier-select"

const CATEGORIES = ["PackagingRoll","SachetFilm","OuterBag","Chemical","Filter","UVLamp","SparePart","Fuel","CleaningSupply","Other"]
const PAYMENT_METHODS = ["Cash","MoMo","Bank","Credit"]

type ItemForm = Omit<WaterRawMaterialItem, "waterRawMaterialItemId" | "farmId" | "currentQuantity">
const EMPTY_ITEM: ItemForm = { itemName: "", category: "PackagingRoll", unitOfMeasure: "", minimumStockAlert: 0, isActive: true, notes: null }

export default function WaterRawMaterialsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()

  const [items, setItems] = useState<WaterRawMaterialItem[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [purchases, setPurchases] = useState<WaterRawMaterialPurchase[]>([])
  // Loaded lazily when the user opens the Usage History tab.
  const [usage, setUsage] = useState<WaterProductionMaterialUsageRow[]>([])
  const [usageLoaded, setUsageLoaded] = useState(false)
  const [usageLoading, setUsageLoading] = useState(false)
  const [loading, setLoading] = useState(true)

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
    setLoading(true)
    try { const [is, ps] = await Promise.all([listWaterRawMaterialItems(), listWaterRawMaterialPurchases()]); setItems(is); setPurchases(ps) }
    catch (e: any) { toast({ title: "Could not load raw materials", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // Lazy-loads on first visit to the Usage History tab — usage data isn't
  // needed for the default Items view, no reason to pay for it upfront.
  async function loadUsage() {
    if (usageLoaded) return
    setUsageLoading(true)
    try { setUsage(await listWaterRawMaterialUsageHistory()) }
    catch (e: any) { toast({ title: "Couldn't load usage history", description: e?.message, variant: "destructive" }) }
    finally { setUsageLoading(false); setUsageLoaded(true) }
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
      supplierId: p.supplierId ?? null,
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
          supplierId: purchaseForm.supplierId,
        } as any)
        toast({ title: "Purchase updated — stock adjusted" })
      } else {
        await createWaterRawMaterialPurchase({
          ...purchaseForm,
          receiptUrl: purchaseForm.receiptUrl || null,
          notes: purchaseForm.notes || null,
          supplierId: purchaseForm.supplierId,
        } as any)
        toast({ title: "Purchase recorded — stock updated" })
      }
      setPurchaseOpen(false); setEditPurchaseId(null); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
  }

  const lowStock = useMemo(() => items.filter(i => i.isActive && (i.currentQuantity ?? 0) <= (i.minimumStockAlert ?? 0)), [items])

  const visibleItems = useMemo(
    () => filterByDateAndSearch(items, {
      search, dateFrom, dateTo,
      searchKeys: ["itemName", "category"],
    }),
    [items, search, dateFrom, dateTo],
  )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Box className="h-6 w-6 text-sky-600" /> Raw materials &amp; supplies
            </h1>
            <div className="flex flex-wrap gap-2">
              <Button variant="outline" onClick={openNewItem}><Plus className="h-4 w-4 mr-1" /> New item</Button>
              <Button onClick={openNewPurchase}><ShoppingCart className="h-4 w-4 mr-1" /> Record purchase</Button>
            </div>
          </div>

          <Tabs defaultValue="items" onValueChange={(v) => { if (v === "usage") void loadUsage() }}>
            <TabsList>
              <TabsTrigger value="items">Items ({items.length})</TabsTrigger>
              <TabsTrigger value="purchases">Purchases ({purchases.length})</TabsTrigger>
              <TabsTrigger value="usage">Usage history</TabsTrigger>
            </TabsList>

            <TabsContent value="items">
              {/* Prompt 2 Part 2 §3 — filters before the low-stock alert. */}
              <ListFilters
                search={search} setSearch={setSearch}
                searchOnly
                searchPlaceholder="Search item or category"
              />

              {lowStock.length > 0 && (
                <Card className="border-amber-200 bg-amber-50 my-3">
                  <CardContent className="p-3">
                    <div className="font-medium text-amber-900 mb-1">Low-stock items ({lowStock.length})</div>
                    <div className="text-sm text-slate-700">{lowStock.map(i => `${i.itemName} (${i.currentQuantity ?? 0} / min ${i.minimumStockAlert ?? 0})`).join(" · ")}</div>
                  </CardContent>
                </Card>
              )}

              <Card>
                <CardContent className="p-0">
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : items.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No raw material items yet.</div>
                  ) : (
                    <MobileCardList
                      items={visibleItems}
                      getKey={(it) => it.waterRawMaterialItemId}
                      primary={(it) => it.itemName}
                      secondary={(it) => (
                        <>
                          <Badge variant="outline">{it.category}</Badge>
                          {it.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}
                        </>
                      )}
                      details={(it) => {
                        const low = (it.currentQuantity ?? 0) <= (it.minimumStockAlert ?? 0)
                        return [
                          { label: "Category", value: it.category },
                          { label: "Unit", value: it.unitOfMeasure ?? "—" },
                          { label: "Current", value: <span className={low ? "text-rose-600 font-semibold" : ""}>{it.currentQuantity ?? 0}</span> },
                          { label: "Min alert", value: it.minimumStockAlert ?? 0 },
                          { label: "Status", value: it.isActive ? "Active" : "Inactive" },
                        ]
                      }}
                      actions={(it) => (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEditItem(it)}>
                            <Pencil className="h-4 w-4 mr-1" /> Edit
                          </Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteItemTarget(it)}>
                            <Trash2 className="h-4 w-4 mr-1" /> Delete
                          </Button>
                        </>
                      )}
                      desktopTable={
                        <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow><TableHead>Name</TableHead><TableHead>Category</TableHead><TableHead>Unit</TableHead><TableHead className="text-right">Current</TableHead><TableHead className="text-right">Min alert</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                          </TableHeader>
                          <TableBody>
                            {visibleItems.map((it) => {
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
                        </div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="usage">
              <Card>
                <CardContent className="p-0">
                  {usageLoading && !usageLoaded ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading usage…</div>
                  ) : usage.length === 0 ? (
                    <div className="p-8 text-center text-slate-500 text-sm">
                      No usage recorded yet. Raw materials &amp; supplies are consumed when production batches are approved.
                    </div>
                  ) : (
                    <MobileCardList
                      items={usage}
                      getKey={(u) => u.waterRawMaterialUsageId}
                      primary={(u) => u.itemName ?? "—"}
                      secondary={(u) => (
                        <>
                          <span>{u.usedDate.split("T")[0]}</span>
                          <span>·</span>
                          <span>{Number(u.quantityUsed ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 })} {u.unitOfMeasure ?? ""}</span>
                        </>
                      )}
                      details={(u) => [
                        { label: "Date", value: u.usedDate.split("T")[0] },
                        { label: "Material", value: u.itemName ?? "—" },
                        { label: "Qty used", value: Number(u.quantityUsed ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 }) },
                        { label: "Unit", value: u.unitOfMeasure ?? "—" },
                        { label: "Cost", value: u.totalCost ? gh(Number(u.totalCost)) : "—" },
                        { label: "Source batch", value: u.batchNumber ?? "—" },
                        { label: "Finished product", value: u.finishedProductName ?? "—" },
                      ]}
                      desktopTable={
                        <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Date</TableHead>
                              <TableHead>Material</TableHead>
                              <TableHead className="text-right">Qty used</TableHead>
                              <TableHead>Unit</TableHead>
                              <TableHead className="text-right">Cost</TableHead>
                              <TableHead>Source batch</TableHead>
                              <TableHead>Finished product</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {usage.map((u) => (
                              <TableRow key={u.waterRawMaterialUsageId}>
                                <TableCell className="whitespace-nowrap">{u.usedDate.split("T")[0]}</TableCell>
                                <TableCell className="font-medium">{u.itemName ?? "—"}</TableCell>
                                <TableCell className="text-right tabular-nums">
                                  {Number(u.quantityUsed ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 })}
                                </TableCell>
                                <TableCell>{u.unitOfMeasure ?? "—"}</TableCell>
                                <TableCell className="text-right tabular-nums">{u.totalCost ? gh(Number(u.totalCost)) : "—"}</TableCell>
                                <TableCell className="text-slate-600">{u.batchNumber ?? "—"}</TableCell>
                                <TableCell className="text-slate-600">{u.finishedProductName ?? "—"}</TableCell>
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
            </TabsContent>

            <TabsContent value="purchases">
              <Card>
                <CardContent className="p-0">
                  {purchases.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No purchases recorded yet.</div>
                  ) : (
                    <MobileCardList
                      items={purchases}
                      getKey={(p) => p.waterRawMaterialPurchaseId}
                      primary={(p) => p.itemName ?? items.find(i => i.waterRawMaterialItemId === p.waterRawMaterialItemId)?.itemName ?? "—"}
                      secondary={(p) => (
                        <>
                          <span>{p.purchaseDate.split("T")[0]}</span>
                          <span>·</span>
                          <span>{gh(p.totalCost ?? p.quantity * p.unitCost)}</span>
                        </>
                      )}
                      details={(p) => [
                        { label: "Date", value: p.purchaseDate.split("T")[0] },
                        { label: "Item", value: p.itemName ?? items.find(i => i.waterRawMaterialItemId === p.waterRawMaterialItemId)?.itemName ?? "—" },
                        { label: "Supplier", value: p.supplierName ?? "—" },
                        { label: "Qty", value: p.quantity },
                        { label: "Unit cost", value: gh(p.unitCost) },
                        { label: "Total", value: gh(p.totalCost ?? p.quantity * p.unitCost) },
                        { label: "Method", value: p.paymentMethod ?? "—" },
                        { label: "Balance", value: <span className={(p.balance ?? 0) > 0 ? "text-rose-600" : ""}>{gh(p.balance ?? 0)}</span> },
                      ]}
                      actions={(p) => (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEditPurchase(p)}>
                            <Pencil className="h-4 w-4 mr-1" /> Edit
                          </Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeletePurchaseTarget(p)}>
                            <Trash2 className="h-4 w-4 mr-1" /> Delete
                          </Button>
                        </>
                      )}
                      desktopTable={
                        <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow><TableHead>Date</TableHead><TableHead>Item</TableHead><TableHead>Supplier</TableHead><TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Unit cost</TableHead><TableHead className="text-right">Total</TableHead><TableHead>Method</TableHead><TableHead className="text-right">Balance</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                          </TableHeader>
                          <TableBody>
                            {purchases.map((p) => (
                              <TableRow key={p.waterRawMaterialPurchaseId}>
                                <TableCell>{p.purchaseDate.split("T")[0]}</TableCell>
                                <TableCell>{p.itemName ?? items.find(i => i.waterRawMaterialItemId === p.waterRawMaterialItemId)?.itemName ?? "—"}</TableCell>
                                <TableCell>{p.supplierName ?? "—"}</TableCell>
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
                        </div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </main>
      </div>

      {/* Item dialog */}
      <Dialog open={itemOpen} onOpenChange={setItemOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editItemId ? <Pencil className="w-5 h-5 text-blue-600" /> : <Box className="w-5 h-5 text-blue-600" />}
              {editItemId ? "Edit item" : "New item"}
            </DialogTitle>
            <DialogDescription>Track production materials, packaging items, spare parts, fuel kept in stock, cleaning supplies, and other stock-tracked supplies.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Basics" color="indigo">
              <FormField label="Item name *" full>
                <Input value={itemForm.itemName} onChange={(e) => setItemForm({ ...itemForm, itemName: e.target.value })} />
              </FormField>
              <FormField label="Category">
                <Select value={itemForm.category} onValueChange={(v) => setItemForm({ ...itemForm, category: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{CATEGORIES.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Unit">
                <Input value={itemForm.unitOfMeasure ?? ""} onChange={(e) => setItemForm({ ...itemForm, unitOfMeasure: e.target.value || null })} placeholder="kg / roll / pcs" />
              </FormField>
              <FormField label="Minimum stock alert" full>
                <NumberInput min={0} value={itemForm.minimumStockAlert ?? 0} onChange={(e) => setItemForm({ ...itemForm, minimumStockAlert: Number(e.target.value) || 0 })} />
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={itemForm.notes ?? ""} onChange={(e) => setItemForm({ ...itemForm, notes: e.target.value || null })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setItemOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={saveItem}>Save</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Purchase dialog */}
      <Dialog open={purchaseOpen} onOpenChange={(o) => { setPurchaseOpen(o); if (!o) setEditPurchaseId(null) }}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editPurchaseId != null ? <Pencil className="w-5 h-5 text-blue-600" /> : <ShoppingCart className="w-5 h-5 text-blue-600" />}
              {editPurchaseId != null ? "Edit purchase" : "Record raw material purchase"}
            </DialogTitle>
            <DialogDescription>Log a Raw Materials &amp; Supplies purchase to update stock and create the linked expense.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Item, Supplier & Date" color="indigo">
              <FormField label={`Item${editPurchaseId != null ? " (fixed — delete and recreate to change item)" : ""}`} full>
                <Select value={String(purchaseForm.waterRawMaterialItemId)} onValueChange={(v) => setPurchaseForm({ ...purchaseForm, waterRawMaterialItemId: Number(v) })} disabled={editPurchaseId != null}>
                  <SelectTrigger><SelectValue placeholder="Pick item" /></SelectTrigger>
                  <SelectContent>{items.filter(i => i.isActive || i.waterRawMaterialItemId === purchaseForm.waterRawMaterialItemId).map(i => <SelectItem key={i.waterRawMaterialItemId} value={String(i.waterRawMaterialItemId)}>{i.itemName} ({i.unitOfMeasure ?? "—"})</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Supplier" full>
                <SupplierSelect
                  value={purchaseForm.supplierId}
                  onChange={(id) => setPurchaseForm({ ...purchaseForm, supplierId: id })}
                  defaultNewSupplierType="Raw Material Supplier"
                />
              </FormField>
              <FormField label="Date">
                <Input type="date" value={purchaseForm.purchaseDate} onChange={(e) => setPurchaseForm({ ...purchaseForm, purchaseDate: e.target.value })} />
              </FormField>
              <FormField label="Payment method">
                <Select value={purchaseForm.paymentMethod} onValueChange={(v) => setPurchaseForm({ ...purchaseForm, paymentMethod: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PAYMENT_METHODS.map(p => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Quantity & Pricing" color="blue">
              <FormField label="Quantity *">
                <NumberInput min={0} step="0.001" value={purchaseForm.quantity} onChange={(e) => setPurchaseForm({ ...purchaseForm, quantity: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Unit cost *">
                <NumberInput min={0} step="0.01" value={purchaseForm.unitCost} onChange={(e) => setPurchaseForm({ ...purchaseForm, unitCost: Number(e.target.value) || 0 })} />
              </FormField>
            </FormSection>

            <FormSection title="Payment" color="amber">
              <FormField label="Amount paid">
                <NumberInput min={0} step="0.01" value={purchaseForm.amountPaid} onChange={(e) => setPurchaseForm({ ...purchaseForm, amountPaid: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Receipt URL">
                <Input value={purchaseForm.receiptUrl} onChange={(e) => setPurchaseForm({ ...purchaseForm, receiptUrl: e.target.value })} />
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={purchaseForm.notes} onChange={(e) => setPurchaseForm({ ...purchaseForm, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="border-t pt-2 text-sm">
              <span className="text-slate-500">Total:</span> <span className="font-semibold tabular-nums">{gh(purchaseForm.quantity * purchaseForm.unitCost)}</span>
              {" · "}
              <span className="text-slate-500">Balance:</span> <span className="font-semibold tabular-nums">{gh(Math.max((purchaseForm.quantity * purchaseForm.unitCost) - purchaseForm.amountPaid, 0))}</span>
            </div>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setPurchaseOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={savePurchase}>{editPurchaseId != null ? "Save changes" : "Record purchase"}</Button>
            </div>
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

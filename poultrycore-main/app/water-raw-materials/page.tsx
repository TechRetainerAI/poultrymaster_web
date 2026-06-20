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
import { Plus, Pencil, Loader2, Box, ShoppingCart, Trash2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listWaterRawMaterialItems, createWaterRawMaterialItem, updateWaterRawMaterialItem, deleteWaterRawMaterialItem,
  listWaterRawMaterialPurchases, createWaterRawMaterialPurchase, updateWaterRawMaterialPurchase, deleteWaterRawMaterialPurchase,
  payWaterRawMaterialPurchaseBalance,
  listWaterRawMaterialUsageHistory,
  listWaterCashAccounts,
  type WaterRawMaterialItem, type WaterRawMaterialPurchase, type WaterProductionMaterialUsageRow,
  type WaterCashAccount,
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
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
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
    // Which cash account the payment comes out of (like Expenses). null until picked.
    waterCashAccountId: null as number | null,
    // #12: purchase vs production costing. quantity = Purchase Quantity.
    totalPurchaseCost: 0, purchaseUnit: "", productionUnit: "", productionUnitsPerPurchaseUnit: 1,
  })
  const [deletePurchaseTarget, setDeletePurchaseTarget] = useState<WaterRawMaterialPurchase | null>(null)

  // Pay-balance dialog (records a follow-up payment against an outstanding purchase).
  const [payTarget, setPayTarget] = useState<WaterRawMaterialPurchase | null>(null)
  const [payForm, setPayForm] = useState({ amount: 0, paymentMethod: "Cash", paymentDate: new Date().toISOString().split("T")[0] })
  const [paySaving, setPaySaving] = useState(false)

  function openPayBalance(p: WaterRawMaterialPurchase) {
    setPayTarget(p)
    setPayForm({ amount: p.balance ?? 0, paymentMethod: "Cash", paymentDate: new Date().toISOString().split("T")[0] })
  }

  async function submitPayBalance() {
    if (!payTarget) return
    const outstanding = payTarget.balance ?? 0
    if (payForm.amount <= 0) { toast({ title: "Enter an amount greater than 0", variant: "destructive" }); return }
    if (payForm.amount > outstanding) { toast({ title: `Amount exceeds the outstanding balance (${gh(outstanding)})`, variant: "destructive" }); return }
    setPaySaving(true)
    try {
      await payWaterRawMaterialPurchaseBalance(payTarget.waterRawMaterialPurchaseId, {
        amount: payForm.amount, paymentMethod: payForm.paymentMethod, paymentDate: payForm.paymentDate,
      })
      toast({ title: "Balance payment recorded", description: "An expense was posted for the amount paid." })
      setPayTarget(null)
      await load()
    } catch (e: any) {
      toast({ title: "Could not record payment", description: e?.message, variant: "destructive" })
    } finally { setPaySaving(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { const [is, ps, accs] = await Promise.all([listWaterRawMaterialItems(), listWaterRawMaterialPurchases(), listWaterCashAccounts()]); setItems(is); setPurchases(ps); setAccounts(accs) }
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
    const it0 = items[0]
    setPurchaseForm({
      waterRawMaterialItemId: it0?.waterRawMaterialItemId ?? 0,
      supplierId: null, purchaseDate: new Date().toISOString().split("T")[0],
      quantity: 0, unitCost: 0, paymentMethod: "Cash", amountPaid: 0, receiptUrl: "", notes: "",
      waterCashAccountId: null,
      totalPurchaseCost: 0, purchaseUnit: it0?.unitOfMeasure ?? "", productionUnit: it0?.unitOfMeasure ?? "", productionUnitsPerPurchaseUnit: 1,
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
      waterCashAccountId: p.waterCashAccountId ?? null,
      receiptUrl: p.receiptUrl ?? "",
      notes: p.notes ?? "",
      // N2: use the stored exact total when present.
      totalPurchaseCost: Number((p.totalCost ?? (p.quantity * p.unitCost)).toFixed(2)),
      purchaseUnit: items.find(i => i.waterRawMaterialItemId === p.waterRawMaterialItemId)?.unitOfMeasure ?? "",
      productionUnit: "",
      productionUnitsPerPurchaseUnit: 1,
    })
    setPurchaseOpen(true)
  }

  async function savePurchase() {
    if (!purchaseForm.waterRawMaterialItemId) return toast({ title: "Pick an item", variant: "destructive" })
    if (purchaseForm.quantity <= 0) return toast({ title: "Purchase quantity must be > 0", variant: "destructive" })
    if (purchaseForm.totalPurchaseCost <= 0) return toast({ title: "Total purchase cost must be > 0", variant: "destructive" })
    // Like Expenses: a non-credit payment must say which cash account it leaves.
    if (purchaseForm.paymentMethod !== "Credit" && purchaseForm.amountPaid > 0 && !purchaseForm.waterCashAccountId)
      return toast({ title: "Pick the cash account to pay from", variant: "destructive" })
    // N2: send the EXACT total the operator entered (the SP stores it verbatim);
    // quantity is in the item's unit. No production conversion (removed per new feedback).
    const qty = purchaseForm.quantity
    const total = Number(purchaseForm.totalPurchaseCost.toFixed(2))
    const unitCost = purchaseForm.unitCost || (qty > 0 ? total / qty : 0)
    try {
      if (editPurchaseId != null) {
        await updateWaterRawMaterialPurchase(editPurchaseId, {
          purchaseDate: purchaseForm.purchaseDate,
          quantity: qty,
          unitCost,
          totalCost: total,
          paymentMethod: purchaseForm.paymentMethod,
          amountPaid: purchaseForm.amountPaid,
          waterCashAccountId: purchaseForm.paymentMethod === "Credit" ? null : purchaseForm.waterCashAccountId,
          receiptUrl: purchaseForm.receiptUrl || null,
          notes: purchaseForm.notes || null,
          supplierId: purchaseForm.supplierId,
        } as any)
        toast({ title: "Purchase updated — stock adjusted" })
      } else {
        await createWaterRawMaterialPurchase({
          waterRawMaterialItemId: purchaseForm.waterRawMaterialItemId,
          purchaseDate: purchaseForm.purchaseDate,
          quantity: qty,
          unitCost,
          totalCost: total,
          paymentMethod: purchaseForm.paymentMethod,
          amountPaid: purchaseForm.amountPaid,
          waterCashAccountId: purchaseForm.paymentMethod === "Credit" ? null : purchaseForm.waterCashAccountId,
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
              <Box className="h-6 w-6 text-sky-600" /> Raw materials
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
                      defaultOpen
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
                      defaultOpen
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
                      defaultOpen
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
                          {(p.balance ?? 0) > 0 && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200" onClick={() => openPayBalance(p)}>
                              <Wallet className="h-4 w-4 mr-1" /> Pay balance
                            </Button>
                          )}
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
                                  {(p.balance ?? 0) > 0 && (
                                    <Button size="sm" variant="ghost" className="text-emerald-700" onClick={() => openPayBalance(p)}><Wallet className="h-4 w-4" /></Button>
                                  )}
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
                <Select value={String(purchaseForm.waterRawMaterialItemId)} onValueChange={(v) => { const id = Number(v); const it = items.find(i => i.waterRawMaterialItemId === id); setPurchaseForm({ ...purchaseForm, waterRawMaterialItemId: id, purchaseUnit: it?.unitOfMeasure ?? purchaseForm.purchaseUnit }) }} disabled={editPurchaseId != null}>
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

            {(() => {
              const qty = purchaseForm.quantity || 0
              // N1: two-way unit-cost <-> total-cost binding (both editable).
              const setUnitCost = (u: number) => setPurchaseForm({ ...purchaseForm, unitCost: u, totalPurchaseCost: Number((qty * u).toFixed(2)) })
              const setTotal    = (t: number) => setPurchaseForm({ ...purchaseForm, totalPurchaseCost: t, unitCost: qty > 0 ? Number((t / qty).toFixed(4)) : 0 })
              const setQty      = (q: number) => setPurchaseForm({ ...purchaseForm, quantity: q, totalPurchaseCost: Number((q * (purchaseForm.unitCost || 0)).toFixed(2)) })
              return (
                <FormSection title="Quantity & Pricing" color="blue">
                  <FormField label="Purchase unit *">
                    {/* N1: auto-populated from the item's unit of measure; editable. */}
                    <Input value={purchaseForm.purchaseUnit} onChange={(e) => setPurchaseForm({ ...purchaseForm, purchaseUnit: e.target.value })} placeholder="e.g. Roll, Bag, Litre" />
                  </FormField>
                  <FormField label="Purchase quantity *">
                    <NumberInput min={0} step="0.001" value={purchaseForm.quantity} onChange={(e) => setQty(Number(e.target.value) || 0)} />
                  </FormField>
                  <FormField label="Purchase unit cost *">
                    {/* N1/N2: free field; editing it recomputes the total (and vice-versa). */}
                    <NumberInput min={0} step="0.0001" value={purchaseForm.unitCost} onChange={(e) => setUnitCost(Number(e.target.value) || 0)} />
                  </FormField>
                  <FormField label="Total purchase cost *">
                    <NumberInput min={0} step="0.01" value={purchaseForm.totalPurchaseCost} onChange={(e) => setTotal(Number(e.target.value) || 0)} />
                  </FormField>
                  <FormField label="" full>
                    <p className="text-xs text-slate-500">Enter the unit cost and we calculate the total, or enter the total and we calculate the unit cost. The total is saved exactly as entered.</p>
                  </FormField>
                </FormSection>
              )
            })()}

            <FormSection title="Payment" color="amber">
              <FormField label="Amount paid">
                <NumberInput min={0} step="0.01" value={purchaseForm.amountPaid} onChange={(e) => setPurchaseForm({ ...purchaseForm, amountPaid: Number(e.target.value) || 0 })} />
              </FormField>
              {/* #2: choose which cash account the payment leaves (same as the
                  Expenses form). Not required for Credit / nothing-paid. */}
              <FormField label={`Cash account${purchaseForm.paymentMethod !== "Credit" && purchaseForm.amountPaid > 0 ? " *" : ""}`}>
                <Select
                  value={purchaseForm.waterCashAccountId ? String(purchaseForm.waterCashAccountId) : ""}
                  onValueChange={(v) => setPurchaseForm({ ...purchaseForm, waterCashAccountId: v ? Number(v) : null })}
                  disabled={purchaseForm.paymentMethod === "Credit"}
                >
                  <SelectTrigger><SelectValue placeholder={purchaseForm.paymentMethod === "Credit" ? "(not required for credit)" : "Pick account"} /></SelectTrigger>
                  <SelectContent>
                    {accounts.filter(a => a.isActive).length === 0
                      ? <div className="px-2 py-1.5 text-sm text-slate-500">No cash accounts — add one on Cash &amp; Accounts.</div>
                      : accounts.filter(a => a.isActive).map(a => (
                          <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName} ({a.currentBalance.toFixed(2)})</SelectItem>
                        ))}
                  </SelectContent>
                </Select>
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
              <span className="text-slate-500">Total:</span> <span className="font-semibold tabular-nums">{gh(purchaseForm.totalPurchaseCost)}</span>
              {" · "}
              <span className="text-slate-500">Balance:</span> <span className="font-semibold tabular-nums">{gh(Math.max(purchaseForm.totalPurchaseCost - purchaseForm.amountPaid, 0))}</span>
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

      {/* Pay balance dialog — records a follow-up payment against an outstanding purchase. */}
      <Dialog open={!!payTarget} onOpenChange={(o) => { if (!o) setPayTarget(null) }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Wallet className="h-5 w-5 text-emerald-600" /> Pay balance</DialogTitle>
            <DialogDescription>
              {payTarget ? `${payTarget.itemName ?? "Purchase"} — outstanding ${gh(payTarget.balance ?? 0)} of ${gh(payTarget.totalCost ?? (payTarget.quantity * payTarget.unitCost))}. This records an expense for the amount paid.` : ""}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Payment" color="amber">
              <FormField label="Amount paid *">
                <NumberInput min={0} step="0.01" value={payForm.amount} onChange={(e) => setPayForm({ ...payForm, amount: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Payment method">
                <Select value={payForm.paymentMethod} onValueChange={(v) => setPayForm({ ...payForm, paymentMethod: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PAYMENT_METHODS.filter(m => m !== "Credit").map(m => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Payment date">
                <Input type="date" value={payForm.paymentDate} onChange={(e) => setPayForm({ ...payForm, paymentDate: e.target.value })} />
              </FormField>
            </FormSection>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" variant="outline" onClick={() => setPayTarget(null)}>Cancel</Button>
              <Button onClick={submitPayBalance} disabled={paySaving}>
                {paySaving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Record payment"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

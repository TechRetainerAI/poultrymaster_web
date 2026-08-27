"use client"

import { Suspense, useEffect, useMemo, useRef, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
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
  listWaterRawMaterialUsageHistory, listWaterRawMaterialAdjustments,
  listWaterCashAccounts,
  type WaterRawMaterialItem, type WaterRawMaterialUsageMethod, type WaterRawMaterialPurchase, type WaterProductionMaterialUsageRow,
  type WaterCashAccount,
} from "@/lib/api/water"
import { SupplierSelect } from "@/components/water/supplier-select"
import { WaterRecalculateStockButton } from "@/components/water/recalculate-stock-button"

const CATEGORIES = ["PackagingRoll","SachetFilm","OuterBag","Chemical","Filter","UVLamp","SparePart","Fuel","CleaningSupply","Other"]
const PAYMENT_METHODS = ["Cash","MoMo","Bank","Credit"]
// Spec #12: purchase / production units are dropdowns. The item's own unit is
// merged in at render time so custom units aren't lost.
const UNITS = ["Roll","Bag","Sachet","Bottle","Piece","Pack","Carton","Box","Bundle","Dozen","Litre","Millilitre","Tonne","Kilogram","Gram","Bale","Unit","Other"]

type ItemForm = Omit<WaterRawMaterialItem, "waterRawMaterialItemId" | "farmId" | "currentQuantity">
const EMPTY_ITEM: ItemForm = { itemName: "", category: "PackagingRoll", unitOfMeasure: "", purchaseUnitOfMeasure: "", minimumStockAlert: 0, isActive: true, notes: null, usageMethod: "FIFO" }

// Which purchase lot an approved production batch draws from first. Offered on
// every category — unlike Poultry, any water raw material can appear in a
// product recipe, so any of them can be drawn.
const USAGE_METHOD_OPTIONS: { value: WaterRawMaterialUsageMethod; label: string; hint: string }[] = [
  { value: "FIFO", label: "FIFO", hint: "First bought, first used" },
  { value: "LIFO", label: "LIFO", hint: "Last bought, first used" },
  { value: "HIFO", label: "HIFO", hint: "Highest cost, first used" },
]

const TABS = ["items", "purchases", "usage"] as const
type TabKey = (typeof TABS)[number]

function WaterRawMaterialsPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()

  // The URL is the source of truth for which tab is showing; an unknown or
  // missing ?tab= falls back to Items rather than rendering an empty panel.
  const tabParam = searchParams.get("tab")
  const tab: TabKey = (TABS as readonly string[]).includes(tabParam ?? "") ? (tabParam as TabKey) : "items"

  // ?purchaseId= from Supplier Balances -> Open purchase.
  const purchaseIdParam = Number(searchParams.get("purchaseId"))
  const focusPurchaseId = Number.isFinite(purchaseIdParam) && purchaseIdParam > 0 ? purchaseIdParam : null

  // Clearing the focus has to drop ?purchaseId= too, or it comes straight back
  // on the next render.
  const clearPurchaseFocus = () => router.replace("/water-raw-materials?tab=purchases", { scroll: false })

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

  // Item dropdown filter shared by Purchases + Usage ("all" = no item filter).
  const [itemFilter, setItemFilter] = useState("all")
  // Items tab: category + unit dropdowns (records grow fast in production).
  const [categoryFilter, setCategoryFilter] = useState("all")
  const [unitFilter, setUnitFilter] = useState("all")
  // Per-tab column sort (label click cycles asc → desc → off).
  const [itemsSort, setItemsSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })
  const [purchasesSort, setPurchasesSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })
  const [usageSort, setUsageSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })

  const [itemOpen, setItemOpen] = useState(false)
  const [editItemId, setEditItemId] = useState<number | null>(null)
  const [itemForm, setItemForm] = useState<ItemForm>(EMPTY_ITEM)
  const [deleteItemTarget, setDeleteItemTarget] = useState<WaterRawMaterialItem | null>(null)

  const [purchaseOpen, setPurchaseOpen] = useState(false)
  const [editPurchaseId, setEditPurchaseId] = useState<number | null>(null)
  // Manual-entry toggles: turn off auto-calc and type the cost directly (we
  // back-solve total / conversion factor so the values persist unchanged).
  const [manualPurchaseCost, setManualPurchaseCost] = useState(false)
  const [manualProdCost, setManualProdCost] = useState(false)
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
  // Prevent double/triple submits (slow network → operator clicks Record again).
  // The ref is the real guard (synchronous, blocks re-entry before the first
  // await); the state just drives the disabled/spinner UI.
  const [savingPurchase, setSavingPurchase] = useState(false)
  const savingPurchaseRef = useRef(false)

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
  // Tab changes go through the URL so the tab is linkable and survives the
  // back button -- same pattern as the poultry raw-materials page.
  const selectTab = (v: string) => {
    router.replace(v === "items" ? "/water-raw-materials" : `/water-raw-materials?tab=${v}`, { scroll: false })
  }

  // Usage history is fetched lazily the first time its tab is shown -- including
  // when the page is opened straight at ?tab=usage, which no click would cover.
  useEffect(() => {
    if (tab === "usage") void loadUsage()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab])

  async function loadUsage() {
    if (usageLoaded) return
    setUsageLoading(true)
    try {
      const [hist, adj] = await Promise.all([
        listWaterRawMaterialUsageHistory(),
        listWaterRawMaterialAdjustments().catch(() => []),
      ])
      // Show manual stock adjustments alongside production usage. An adjustment
      // that decreases stock reads as a positive "used"; an increase as a
      // negative used (a return). Synthetic negative id keeps React keys unique.
      const adjRows: WaterProductionMaterialUsageRow[] = adj.map((a) => ({
        waterRawMaterialUsageId: -a.waterRawMaterialAdjustmentId,
        farmId: a.farmId,
        waterRawMaterialItemId: a.waterRawMaterialItemId,
        itemName: a.itemName ?? null,
        unitOfMeasure: a.unitOfMeasure ?? null,
        usedDate: a.adjustedDate,
        quantityUsed: -Number(a.quantity),
        expectedQuantityUsed: null,
        variance: 0,
        varianceReason: `Manual adjustment${a.movementType ? ` (${a.movementType})` : ""}${a.note ? ` — ${a.note}` : ""}`,
        unitCost: a.unitCost ?? null,
        notes: a.note ?? null,
        createdAt: a.createdAt,
      }))
      setUsage([...hist, ...adjRows])
    }
    catch (e: any) { toast({ title: "Couldn't load usage history", description: e?.message, variant: "destructive" }) }
    finally { setUsageLoading(false); setUsageLoaded(true) }
  }

  function openNewItem() { setEditItemId(null); setItemForm(EMPTY_ITEM); setItemOpen(true) }
  function openEditItem(it: WaterRawMaterialItem) {
    setEditItemId(it.waterRawMaterialItemId)
    setItemForm({ itemName: it.itemName, category: it.category, unitOfMeasure: it.unitOfMeasure, purchaseUnitOfMeasure: it.purchaseUnitOfMeasure ?? "", minimumStockAlert: it.minimumStockAlert, isActive: it.isActive, notes: it.notes, usageMethod: it.usageMethod ?? "FIFO" })
    setItemOpen(true)
  }

  async function saveItem() {
    if (!itemForm.itemName.trim()) return toast({ title: "Item name required", variant: "destructive" })
    // Blank purchase unit → null so the backend defaults it to the production unit.
    const itemPayload = { ...itemForm, purchaseUnitOfMeasure: (itemForm.purchaseUnitOfMeasure ?? "").trim() || null }
    try {
      if (editItemId) { await updateWaterRawMaterialItem(editItemId, itemPayload); toast({ title: "Item updated" }) }
      else { await createWaterRawMaterialItem(itemPayload); toast({ title: "Item added" }) }
      setItemOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
  }

  function openNewPurchase() {
    setEditPurchaseId(null)
    setManualPurchaseCost(false); setManualProdCost(false)
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
    setManualPurchaseCost(false); setManualProdCost(false)
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
      productionUnit: p.productionUnit ?? "",
      productionUnitsPerPurchaseUnit: p.productionUnitsPerPurchaseUnit ?? 1,
    })
    setPurchaseOpen(true)
  }

  async function savePurchase() {
    if (savingPurchaseRef.current) return // already submitting — ignore extra clicks
    if (!purchaseForm.waterRawMaterialItemId) return toast({ title: "Pick an item", variant: "destructive" })
    if (purchaseForm.quantity <= 0) return toast({ title: "Purchase quantity must be > 0", variant: "destructive" })
    if (purchaseForm.totalPurchaseCost <= 0) return toast({ title: "Total purchase cost must be > 0", variant: "destructive" })
    // Like Expenses: a non-credit payment must say which cash account it leaves.
    if (purchaseForm.paymentMethod !== "Credit" && purchaseForm.amountPaid > 0 && !purchaseForm.waterCashAccountId)
      return toast({ title: "Pick the cash account to pay from", variant: "destructive" })
    savingPurchaseRef.current = true
    setSavingPurchase(true)
    // N2: send the EXACT total the operator entered (the SP stores it verbatim);
    // quantity is in the item's purchase unit. Migration 116: the production-unit
    // conversion (unit + units-per-purchase-unit) is persisted with the purchase.
    const qty = purchaseForm.quantity
    const total = Number(purchaseForm.totalPurchaseCost.toFixed(2))
    const unitCost = purchaseForm.unitCost || (qty > 0 ? total / qty : 0)
    const productionUnit = purchaseForm.productionUnit?.trim() || null
    const productionUnitsPerPurchaseUnit =
      purchaseForm.productionUnitsPerPurchaseUnit && purchaseForm.productionUnitsPerPurchaseUnit > 0
        ? purchaseForm.productionUnitsPerPurchaseUnit
        : null
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
          productionUnit,
          productionUnitsPerPurchaseUnit,
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
          productionUnit,
          productionUnitsPerPurchaseUnit,
        } as any)
        toast({ title: "Purchase recorded — stock updated" })
      }
      setPurchaseOpen(false); setEditPurchaseId(null); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { savingPurchaseRef.current = false; setSavingPurchase(false) }
  }

  const lowStock = useMemo(() => items.filter(i => i.isActive && (i.currentQuantity ?? 0) <= (i.minimumStockAlert ?? 0)), [items])

  const visibleItems = useMemo(() => {
    let rows = filterByDateAndSearch(items, { search, dateFrom, dateTo, searchKeys: ["itemName", "category"] })
    if (categoryFilter !== "all") rows = rows.filter((i) => i.category === categoryFilter)
    if (unitFilter !== "all") rows = rows.filter((i) => i.unitOfMeasure === unitFilter || i.purchaseUnitOfMeasure === unitFilter)
    return rows
  }, [items, search, dateFrom, dateTo, categoryFilter, unitFilter])

  // Distinct units actually in use (either role), for the Items unit dropdown.
  const unitOptionsInUse = useMemo(() => {
    const set = new Set<string>()
    items.forEach((i) => { if (i.unitOfMeasure) set.add(i.unitOfMeasure); if (i.purchaseUnitOfMeasure) set.add(i.purchaseUnitOfMeasure) })
    return Array.from(set).sort()
  }, [items])

  const byItem = <T extends { waterRawMaterialItemId: number }>(rows: T[]) =>
    itemFilter === "all" ? rows : rows.filter((r) => String(r.waterRawMaterialItemId) === itemFilter)

  // ?purchaseId= from Supplier Balances -> Open purchase. Narrowing to the one
  // purchase is the point of the link, so it wins over the other filters; the
  // banner above the table offers the way back out.
  const filteredPurchases = useMemo(
    () => {
      if (focusPurchaseId !== null) {
        return purchases.filter((p) => p.waterRawMaterialPurchaseId === focusPurchaseId)
      }
      return byItem(filterByDateAndSearch(purchases, { search, dateFrom, dateTo, searchKeys: ["itemName", "supplierName"], dateKey: "purchaseDate" }))
    },
    [purchases, search, dateFrom, dateTo, itemFilter, focusPurchaseId],
  )

  // Supplier name for the banner, so the link reads as "this supplier's
  // purchase" rather than a bare id.
  const focusedPurchaseSupplier = useMemo(
    () => (focusPurchaseId === null
      ? null
      : purchases.find((p) => p.waterRawMaterialPurchaseId === focusPurchaseId)?.supplierName ?? null),
    [purchases, focusPurchaseId],
  )
  const filteredUsage = useMemo(
    () => byItem(filterByDateAndSearch(usage, { search, dateFrom, dateTo, searchKeys: ["itemName"], dateKey: "usedDate" })),
    [usage, search, dateFrom, dateTo, itemFilter],
  )

  const sortedItems = useMemo(() => sortData(visibleItems, itemsSort.key, itemsSort.direction), [visibleItems, itemsSort])
  const sortedPurchases = useMemo(() => sortData(filteredPurchases, purchasesSort.key, purchasesSort.direction), [filteredPurchases, purchasesSort])
  const sortedUsage = useMemo(() => sortData(filteredUsage, usageSort.key, usageSort.direction), [filteredUsage, usageSort])

  // Client-side paging — one pager per tab, each fed the same slice its cards
  // and its desktop table render.
  const pgItems = usePagination(sortedItems)
  const pgUsage = usePagination(sortedUsage)
  const pgPurchases = usePagination(sortedPurchases)

  // Item dropdown shared by the Purchases + Usage filter strips.
  const itemFilterDropdown = (
    <Select value={itemFilter} onValueChange={setItemFilter}>
      <SelectTrigger className="w-[160px]"><SelectValue placeholder="All items" /></SelectTrigger>
      <SelectContent>
        <SelectItem value="all">All items</SelectItem>
        {items.map((i) => <SelectItem key={i.waterRawMaterialItemId} value={String(i.waterRawMaterialItemId)}>{i.itemName}</SelectItem>)}
      </SelectContent>
    </Select>
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
              <WaterRecalculateStockButton items={items} onDone={load} />
              <Button variant="outline" onClick={openNewItem}><Plus className="h-4 w-4 mr-1" /> New item</Button>
              <Button onClick={openNewPurchase}><ShoppingCart className="h-4 w-4 mr-1" /> Record purchase</Button>
            </div>
          </div>

          {/* Controlled by the URL so ?tab=purchases can be linked to -- which
              is how Supplier Balances lands on the right tab. */}
          <Tabs value={tab} onValueChange={selectTab}>
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
                extras={<>
                  <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                    <SelectTrigger className="w-[160px]"><SelectValue placeholder="All categories" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All categories</SelectItem>
                      {CATEGORIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Select value={unitFilter} onValueChange={setUnitFilter}>
                    <SelectTrigger className="w-[140px]"><SelectValue placeholder="All units" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All units</SelectItem>
                      {unitOptionsInUse.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </>}
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
                      items={pgItems.pageItems}
                      pagination={pgItems.paginationProps}
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
                          { label: "Purchase Unit", value: it.purchaseUnitOfMeasure ?? "—" },
                          { label: "Production Unit", value: it.unitOfMeasure ?? "—" },
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
                            <TableRow>
                              {(() => { const onSort = (k: string) => setItemsSort((s) => toggleSort(k, s.key, s.direction)); const cs = itemsSort.key, cd = itemsSort.direction; return (<>
                              <SortableHeader label="Name" sortKey="itemName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Category" sortKey="category" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Purchase Unit" sortKey="purchaseUnitOfMeasure" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Production Unit" sortKey="unitOfMeasure" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Current" sortKey="currentQuantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              <SortableHeader label="Min alert" sortKey="minimumStockAlert" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              <SortableHeader label="Status" sortKey="isActive" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              </>) })()}
                              <TableHead className="text-right">Actions</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pgItems.pageItems.map((it) => {
                              const low = (it.currentQuantity ?? 0) <= (it.minimumStockAlert ?? 0)
                              return (
                                <TableRow key={it.waterRawMaterialItemId}>
                                  <TableCell className="font-medium">{it.itemName}</TableCell>
                                  <TableCell><Badge variant="outline">{it.category}</Badge></TableCell>
                                  <TableCell>{it.purchaseUnitOfMeasure ?? "—"}</TableCell>
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
              <ListFilters
                search={search} setSearch={setSearch}
                dateFrom={dateFrom} setDateFrom={setDateFrom}
                dateTo={dateTo} setDateTo={setDateTo}
                searchPlaceholder="Search item"
                extras={itemFilterDropdown}
              />
              <Card>
                <CardContent className="p-0">
                  {usageLoading && !usageLoaded ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading usage…</div>
                  ) : usage.length === 0 ? (
                    <div className="p-8 text-center text-slate-500 text-sm">
                      No usage recorded yet. Raw materials &amp; supplies are consumed when production records are approved.
                    </div>
                  ) : (
                    <MobileCardList
                      items={pgUsage.pageItems}
                      pagination={pgUsage.paginationProps}
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
                              {(() => { const onSort = (k: string) => setUsageSort((s) => toggleSort(k, s.key, s.direction)); const cs = usageSort.key, cd = usageSort.direction; return (<>
                              <SortableHeader label="Date" sortKey="usedDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Material" sortKey="itemName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Qty used" sortKey="quantityUsed" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              <SortableHeader label="Unit" sortKey="unitOfMeasure" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Cost" sortKey="totalCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              <SortableHeader label="Source batch" sortKey="batchNumber" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Finished product" sortKey="finishedProductName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              </>) })()}
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pgUsage.pageItems.map((u) => (
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
              {/* Arrived here from Supplier Balances -> Open purchase. */}
              {focusPurchaseId !== null && (
                <div className="mb-3 flex flex-wrap items-center justify-between gap-2 rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-sm text-sky-900">
                  <span>
                    Showing purchase <strong>#{focusPurchaseId}</strong> only
                    {focusedPurchaseSupplier ? <> — <strong>{focusedPurchaseSupplier}</strong></> : null}.
                  </span>
                  <Button variant="ghost" size="sm" onClick={clearPurchaseFocus}>Show all purchases</Button>
                </div>
              )}
              <ListFilters
                search={search} setSearch={setSearch}
                dateFrom={dateFrom} setDateFrom={setDateFrom}
                dateTo={dateTo} setDateTo={setDateTo}
                searchPlaceholder="Search item or supplier"
                extras={itemFilterDropdown}
              />
              <Card>
                <CardContent className="p-0">
                  {filteredPurchases.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">
                      {focusPurchaseId !== null
                        ? `Purchase #${focusPurchaseId} is not in this list.`
                        : "No purchases recorded yet."}
                    </div>
                  ) : (
                    <MobileCardList
                      items={pgPurchases.pageItems}
                      pagination={pgPurchases.paginationProps}
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
                        { label: "Purchase Qty", value: p.quantity },
                        { label: "Production Level Qty", value: p.productionQuantity != null ? `${p.productionQuantity.toLocaleString()} ${p.productionUnit ?? ""}`.trim() : "—" },
                        { label: "Unit Price", value: gh(p.unitCost) },
                        { label: "Total", value: gh(p.totalCost ?? p.quantity * p.unitCost) },
                        { label: "Method", value: p.paymentMethod ?? "—" },
                        { label: "Balance", value: <span className={(p.balance ?? 0) > 0 ? "text-rose-600" : ""}>{gh(p.balance ?? 0)}</span> },
                        // Migration 116: show the persisted production-unit conversion.
                        { label: "Production", value: p.productionUnit
                            ? `${(p.productionQuantity ?? 0).toLocaleString()} ${p.productionUnit}${p.productionUnitCost ? ` @ ${gh(p.productionUnitCost)}` : ""}`
                            : "—" },
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
                            <TableRow>
                              {(() => { const onSort = (k: string) => setPurchasesSort((s) => toggleSort(k, s.key, s.direction)); const cs = purchasesSort.key, cd = purchasesSort.direction; return (<>
                              <SortableHeader label="Date" sortKey="purchaseDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Item" sortKey="itemName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Supplier" sortKey="supplierName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Purchase Qty" sortKey="quantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              <SortableHeader label="Production Level Qty" sortKey="productionQuantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              <SortableHeader label="Unit Price" sortKey="unitCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              <SortableHeader label="Total" sortKey="totalCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              <SortableHeader label="Method" sortKey="paymentMethod" currentSort={cs} currentDirection={cd} onSort={onSort} />
                              <SortableHeader label="Balance" sortKey="balance" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                              </>) })()}
                              <TableHead className="text-right">Actions</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pgPurchases.pageItems.map((p) => (
                              <TableRow key={p.waterRawMaterialPurchaseId}>
                                <TableCell>{p.purchaseDate.split("T")[0]}</TableCell>
                                <TableCell>{p.itemName ?? items.find(i => i.waterRawMaterialItemId === p.waterRawMaterialItemId)?.itemName ?? "—"}</TableCell>
                                <TableCell>{p.supplierName ?? "—"}</TableCell>
                                <TableCell className="text-right tabular-nums">{p.quantity}</TableCell>
                                <TableCell className="text-right tabular-nums">{p.productionQuantity != null ? `${p.productionQuantity.toLocaleString()} ${p.productionUnit ?? ""}`.trim() : "—"}</TableCell>
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
              <FormField label="Production unit of measure">
                <Select value={itemForm.unitOfMeasure ?? ""} onValueChange={(v) => setItemForm({ ...itemForm, unitOfMeasure: v || null })}>
                  <SelectTrigger><SelectValue placeholder="Pick a unit" /></SelectTrigger>
                  <SelectContent>
                    {(itemForm.unitOfMeasure && !UNITS.includes(itemForm.unitOfMeasure) ? [itemForm.unitOfMeasure, ...UNITS] : UNITS).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Purchase unit of measure">
                <Select value={itemForm.purchaseUnitOfMeasure || "__same__"} onValueChange={(v) => setItemForm({ ...itemForm, purchaseUnitOfMeasure: v === "__same__" ? null : v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__same__">Same as production unit</SelectItem>
                    {(itemForm.purchaseUnitOfMeasure && !UNITS.includes(itemForm.purchaseUnitOfMeasure) ? [itemForm.purchaseUnitOfMeasure, ...UNITS] : UNITS).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Minimum stock alert" full>
                <NumberInput min={0} value={itemForm.minimumStockAlert ?? 0} onChange={(e) => setItemForm({ ...itemForm, minimumStockAlert: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Order of item usage" hint="Decides which purchase batch a production run consumes, and the price it is costed at" full>
                <div className="flex flex-col gap-2">
                  {USAGE_METHOD_OPTIONS.map((o) => (
                    <label
                      key={o.value}
                      className={`flex items-start gap-2.5 rounded-md border px-3 py-2 cursor-pointer transition-colors ${
                        itemForm.usageMethod === o.value
                          ? "border-sky-600 bg-sky-50"
                          : "border-slate-200 hover:border-slate-300"
                      }`}
                    >
                      <input
                        type="radio"
                        name="usageMethod"
                        value={o.value}
                        checked={itemForm.usageMethod === o.value}
                        onChange={() => setItemForm({ ...itemForm, usageMethod: o.value })}
                        className="mt-0.5 accent-sky-600"
                      />
                      <span>
                        <span className="block text-sm font-semibold text-slate-800">{o.label}</span>
                        <span className="block text-xs text-slate-500">{o.hint}</span>
                      </span>
                    </label>
                  ))}
                </div>
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
                <Select value={String(purchaseForm.waterRawMaterialItemId)} onValueChange={(v) => { const id = Number(v); const it = items.find(i => i.waterRawMaterialItemId === id); setPurchaseForm({ ...purchaseForm, waterRawMaterialItemId: id, purchaseUnit: it?.purchaseUnitOfMeasure || it?.unitOfMeasure || purchaseForm.purchaseUnit, productionUnit: it?.unitOfMeasure || purchaseForm.productionUnit }) }} disabled={editPurchaseId != null}>
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
              const qty   = purchaseForm.quantity || 0
              const total = purchaseForm.totalPurchaseCost || 0
              // Spec #12: Quantity + Total Purchase Cost are the inputs.
              // Purchase Unit Cost is SYSTEM CALCULATED = Total / Quantity.
              // We keep unitCost in sync so it persists with the purchase.
              const setQty   = (q: number) => setPurchaseForm({ ...purchaseForm, quantity: q, unitCost: q > 0 ? Number((total / q).toFixed(4)) : 0 })
              const setTotal = (t: number) => setPurchaseForm({ ...purchaseForm, totalPurchaseCost: t, unitCost: qty > 0 ? Number((t / qty).toFixed(4)) : 0 })
              const unitCost = qty > 0 ? total / qty : 0
              // Production conversion (persisted, migration 116). Both derived:
              //   Production-Level Quantity  = unitsPerPurchase × Purchase Quantity
              //   Production-Level Unit Cost = Total / Production-Level Quantity
              const perPurchase  = purchaseForm.productionUnitsPerPurchaseUnit || 0
              const prodQty      = qty * perPurchase
              const prodUnitCost = prodQty > 0 ? total / prodQty : 0
              const unitOptions = (current?: string | null) => {
                const set = [...UNITS]
                const c = (current ?? "").trim()
                if (c && !set.includes(c)) set.unshift(c)
                return set
              }
              const roCls = "bg-slate-100 text-slate-600 font-medium pointer-events-none cursor-default border-dashed"
              return (
                <>
                  <FormSection title="Purchase Quantity & Production Costing" color="blue">
                    <FormField label="Purchase unit *">
                      <Select value={purchaseForm.purchaseUnit || ""} onValueChange={(v) => setPurchaseForm({ ...purchaseForm, purchaseUnit: v })}>
                        <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                        <SelectContent>{unitOptions(purchaseForm.purchaseUnit).map(u => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
                      </Select>
                    </FormField>
                    <FormField label={`Purchase quantity${purchaseForm.purchaseUnit ? ` (${purchaseForm.purchaseUnit})` : ""} *`}>
                      <NumberInput min={0} step="0.001" value={purchaseForm.quantity} onChange={(e) => setQty(Number(e.target.value) || 0)} />
                    </FormField>
                    <FormField label="" full>
                      <div className="flex items-center justify-between rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
                        <div>
                          <div className="text-sm font-medium text-slate-700">Enter purchase unit cost manually</div>
                          <div className="text-xs text-slate-500">Turn off the auto-calculation and type the purchase unit cost yourself.</div>
                        </div>
                        <Switch checked={manualPurchaseCost} onCheckedChange={setManualPurchaseCost} />
                      </div>
                    </FormField>
                    <FormField label="Total purchase cost *">
                      <NumberInput min={0} step="0.01" value={Number(total.toFixed(2))} disabled={manualPurchaseCost} onChange={(e) => setTotal(Number(e.target.value) || 0)} />
                    </FormField>
                    {manualPurchaseCost ? (
                      <FormField label={`Purchase unit cost${purchaseForm.purchaseUnit ? ` (per ${purchaseForm.purchaseUnit})` : ""}`} hint="Manual — sets the total for you">
                        <NumberInput min={0} step="0.0001" value={Number(unitCost.toFixed(4))} onChange={(e) => {
                          const c = Number(e.target.value) || 0
                          setPurchaseForm({ ...purchaseForm, totalPurchaseCost: qty > 0 ? Number((c * qty).toFixed(2)) : purchaseForm.totalPurchaseCost, unitCost: c })
                        }} />
                      </FormField>
                    ) : (
                      <FormField label="Purchase unit cost (auto)">
                        {/* System calculated = Total Purchase Cost / Purchase Quantity. */}
                        <Input readOnly tabIndex={-1} className={roCls}
                          value={`${gh(unitCost)}${purchaseForm.purchaseUnit ? ` per ${purchaseForm.purchaseUnit}` : ""}`} />
                      </FormField>
                    )}
                  </FormSection>

                  <FormSection title="Production Conversion" color="indigo">
                    <FormField label="" full>
                      <div className="flex items-center justify-between rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
                        <div>
                          <div className="text-sm font-medium text-slate-700">Enter production cost manually</div>
                          <div className="text-xs text-slate-500">Turn off the auto-calculation and type the production-level unit cost yourself.</div>
                        </div>
                        <Switch checked={manualProdCost} onCheckedChange={setManualProdCost} />
                      </div>
                    </FormField>
                    <FormField label="Production unit *">
                      <Select value={purchaseForm.productionUnit || ""} onValueChange={(v) => setPurchaseForm({ ...purchaseForm, productionUnit: v })}>
                        <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                        <SelectContent>{unitOptions(purchaseForm.productionUnit).map(u => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Production units per purchase unit *">
                      <NumberInput min={0} step="0.0001" value={purchaseForm.productionUnitsPerPurchaseUnit}
                        onChange={(e) => setPurchaseForm({ ...purchaseForm, productionUnitsPerPurchaseUnit: Number(e.target.value) || 0 })} />
                    </FormField>
                    <FormField label="Production-level quantity" hint="Editable — sets units per purchase unit">
                      <NumberInput min={0} step="0.001" value={Number(prodQty.toFixed(4))}
                        onChange={(e) => { const v = Number(e.target.value) || 0; setPurchaseForm({ ...purchaseForm, productionUnitsPerPurchaseUnit: qty > 0 ? Number((v / qty).toFixed(8)) : perPurchase }) }} />
                    </FormField>
                    {manualProdCost ? (
                      <FormField label={`Production-level unit cost${purchaseForm.productionUnit ? ` (per ${purchaseForm.productionUnit})` : ""}`} hint="Manual — sets the conversion for you">
                        <NumberInput min={0} step="0.0001" value={Number(prodUnitCost.toFixed(4))} onChange={(e) => {
                          const c = Number(e.target.value) || 0
                          const newPer = (c > 0 && qty > 0 && total > 0) ? Number((total / (c * qty)).toFixed(8)) : perPurchase
                          setPurchaseForm({ ...purchaseForm, productionUnitsPerPurchaseUnit: newPer })
                        }} />
                      </FormField>
                    ) : (
                      <FormField label="Production-level unit cost (auto)">
                        {/* Total Purchase Cost / Production-Level Quantity */}
                        <Input readOnly tabIndex={-1} className={roCls}
                          value={`${gh(prodUnitCost)}${purchaseForm.productionUnit ? ` per ${purchaseForm.productionUnit}` : ""}`} />
                      </FormField>
                    )}
                    <FormField label="" full>
                      <p className="text-xs text-slate-500">If you buy and use the same unit, set <span className="font-medium">Production units per purchase unit = 1</span> — the production figures then match the purchase figures. These values are saved with the purchase.</p>
                    </FormField>
                  </FormSection>
                </>
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
              <Button onClick={savePurchase} disabled={savingPurchase}>
                {savingPurchase ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : (editPurchaseId != null ? "Save changes" : "Record purchase")}
              </Button>
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

export default function WaterRawMaterialsPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <WaterRawMaterialsPageInner />
    </Suspense>
  )
}

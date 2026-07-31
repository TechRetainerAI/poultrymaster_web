"use client"

import { useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Loader2, Box, ShoppingCart, Trash2, Wallet, AlertTriangle, Factory } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { cn } from "@/lib/utils"
import { RAW_MATERIAL_UNITS } from "@/lib/units"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryRawMaterialItems, createPoultryRawMaterialItem, updatePoultryRawMaterialItem, deletePoultryRawMaterialItem,
  listPoultryRawMaterialPurchases, createPoultryRawMaterialPurchase, updatePoultryRawMaterialPurchase, deletePoultryRawMaterialPurchase,
  payPoultryRawMaterialPurchaseBalance, listPoultryRawMaterialUsageHistory, listPoultryRawMaterialAdjustments,
  type PoultryRawMaterialItem, type PoultryRawMaterialPurchase, type PoultryRawMaterialUsage, type RawMaterialUsageMethod,
} from "@/lib/api/poultry-inventory"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { RecalculateStockButton } from "@/components/poultry/recalculate-stock-button"

const CATEGORIES = ["FeedIngredient", "FinishedFeed", "Packaging", "Medication", "Vaccine", "Bedding", "Disinfectant", "SparePart", "Fuel", "Other"]
// Readable labels for the camel-case category codes stored in the DB.
const CATEGORY_LABELS: Record<string, string> = {
  FeedIngredient: "Feed Ingredient",
  FinishedFeed: "Finished Feed",
  SparePart: "Spare Part",
}
const categoryLabel = (c: string) => CATEGORY_LABELS[c] ?? c
const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Credit"]
const UNITS = RAW_MATERIAL_UNITS

type ItemForm = { itemName: string; category: string; unitOfMeasure: string; purchaseUnitOfMeasure: string; minimumStockAlert: number; isActive: boolean; notes: string | null; usageMethod: RawMaterialUsageMethod }
const EMPTY_ITEM: ItemForm = { itemName: "", category: "FeedIngredient", unitOfMeasure: "", purchaseUnitOfMeasure: "", minimumStockAlert: 0, isActive: true, notes: null, usageMethod: "FIFO" }

// Categories whose stock is actually drawn from a specific batch when recorded
// as "used" (production-records feed/medication pickers). Only these show the
// FIFO/LIFO/HIFO consumption-policy picker on the item form.
const USAGE_METHOD_CATEGORIES = ["FeedIngredient", "FinishedFeed", "Medication"]
const USAGE_METHOD_OPTIONS: { value: RawMaterialUsageMethod; label: string; hint: string }[] = [
  { value: "FIFO", label: "FIFO", hint: "First bought, first used" },
  { value: "LIFO", label: "LIFO", hint: "Last bought, first used" },
  { value: "HIFO", label: "HIFO", hint: "Highest cost, first used" },
]

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
  poultryCashAccountId: 0,
  amountPaid: 0,
  receiptUrl: "",
  notes: "",
}

// Mobile card for a table row: title + optional badge, a 2-col field grid, and
// an actions row. Used to render these tables as cards on small screens.
function FieldCard({ title, badge, fields, actions }: { title: React.ReactNode; badge?: React.ReactNode; fields: [string, React.ReactNode][]; actions?: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-slate-200 p-3">
      <div className="flex items-center justify-between gap-2">
        <div className="font-medium text-slate-900 min-w-0 truncate">{title}</div>
        {badge}
      </div>
      <div className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-sm">
        {fields.map(([l, v], idx) => <div key={idx} className="min-w-0 truncate"><span className="text-slate-500">{l}: </span><span className="tabular-nums">{v}</span></div>)}
      </div>
      {actions && <div className="mt-2 flex justify-end gap-1 border-t pt-2">{actions}</div>}
    </div>
  )
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
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])

  // Shared list filters (mirrors the water raw-materials + /sales pages):
  // search applies to every tab; the date range + item dropdown apply to
  // Purchases/Usage (which reference an item). "all" = no item filter.
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
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
  const [deleteItemTarget, setDeleteItemTarget] = useState<PoultryRawMaterialItem | null>(null)
  const [savingItem, setSavingItem] = useState(false)

  const [purchaseOpen, setPurchaseOpen] = useState(false)
  const [editPurchaseId, setEditPurchaseId] = useState<number | null>(null)
  const [purchaseForm, setPurchaseForm] = useState({ ...EMPTY_PURCHASE })
  // When ON, the user enters the production-level unit cost directly instead of
  // it auto-calculating from the purchase total ÷ production quantity. We store
  // it by back-solving the units-per-purchase-unit factor, so it persists with
  // no schema change.
  const [manualProdCost, setManualProdCost] = useState(false)
  // Same idea for the purchase unit cost: when ON, type the unit cost and we
  // back-solve the total (total = unitCost × quantity) so it persists.
  const [manualPurchaseCost, setManualPurchaseCost] = useState(false)
  const [deletePurchaseTarget, setDeletePurchaseTarget] = useState<PoultryRawMaterialPurchase | null>(null)
  const [savingPurchase, setSavingPurchase] = useState(false)
  const savingPurchaseRef = useRef(false) // synchronous re-entry guard against double/triple submits

  const [payTarget, setPayTarget] = useState<PoultryRawMaterialPurchase | null>(null)
  const [payForm, setPayForm] = useState({ amount: 0, paymentMethod: "Cash", paymentDate: new Date().toISOString().split("T")[0] })
  const [paySaving, setPaySaving] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  // Default cash account for new purchases (mirrors /sales): prefer "Main Cash
  // Account" by name, else fall back to the first active account.
  const defaultCashAccountId = useMemo(() => {
    const main = cashAccounts.find((a) => a.accountName.trim().toLowerCase() === "main cash account")
    return (main ?? cashAccounts[0])?.poultryCashAccountId ?? null
  }, [cashAccounts])

  // Preselect it for NEW purchases once accounts have loaded (edits keep
  // whatever account the purchase was actually saved with).
  useEffect(() => {
    if (purchaseOpen && !editPurchaseId && defaultCashAccountId != null) {
      setPurchaseForm((prev) => (prev.poultryCashAccountId ? prev : { ...prev, poultryCashAccountId: defaultCashAccountId }))
    }
  }, [purchaseOpen, editPurchaseId, defaultCashAccountId])

  // ?purchase=1[&itemId=N][&qty=X] opens the purchase dialog straight away with
  // the item preselected and the quantity prefilled. Feed Production sends
  // farmers here to buy an ingredient rather than recording it inline, and
  // passes the quantity that batch is short of. Waits for the items to load so
  // the item can actually be matched, and only fires once. Read off
  // window.location so this stays a plain client page — useSearchParams would
  // need a Suspense boundary around the whole thing.
  const deepLinkHandled = useRef(false)
  useEffect(() => {
    if (deepLinkHandled.current || loading) return
    let qs: URLSearchParams
    try { qs = new URLSearchParams(window.location.search) } catch { return }
    if (qs.get("purchase") !== "1") return
    deepLinkHandled.current = true
    const it = items.find((i) => i.poultryRawMaterialItemId === Number(qs.get("itemId")) && i.isActive)
    const qty = Number(qs.get("qty"))
    setEditPurchaseId(null); setManualProdCost(false); setManualPurchaseCost(false)
    setPurchaseForm({
      ...EMPTY_PURCHASE,
      poultryCashAccountId: defaultCashAccountId ?? 0,
      poultryRawMaterialItemId: it?.poultryRawMaterialItemId ?? 0,
      purchaseUnit: it?.purchaseUnitOfMeasure || it?.unitOfMeasure || "",
      productionUnit: it?.unitOfMeasure || "",
      quantity: Number.isFinite(qty) && qty > 0 ? qty : 0,
    })
    setPurchaseOpen(true)
    // Drop the params so a refresh or a back-navigation doesn't reopen it.
    router.replace("/poultry-raw-materials", { scroll: false })
  }, [loading, items, defaultCashAccountId, router])

  async function load() {
    setLoading(true)
    try {
      const [is, ps, cas] = await Promise.all([listPoultryRawMaterialItems(), listPoultryRawMaterialPurchases(), listPoultryCashAccounts().catch(() => [])])
      setItems(is); setPurchases(ps); setCashAccounts((cas as PoultryCashAccount[]).filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Could not load raw materials", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function loadUsage() {
    if (usageLoaded) return
    try {
      const [hist, adj] = await Promise.all([
        listPoultryRawMaterialUsageHistory(),
        listPoultryRawMaterialAdjustments().catch(() => []),
      ])
      // Show manual stock adjustments alongside production usage. An adjustment
      // that decreases stock reads as a positive "used"; an increase reads as a
      // negative used (a return). Synthetic negative id keeps React keys unique.
      const adjRows: PoultryRawMaterialUsage[] = adj.map((a) => ({
        poultryRawMaterialUsageId: -a.poultryRawMaterialAdjustmentId,
        farmId: a.farmId,
        poultryRawMaterialItemId: a.poultryRawMaterialItemId,
        itemName: a.itemName ?? null,
        unitOfMeasure: a.unitOfMeasure ?? null,
        poultryProductionBatchId: null,
        usedDate: a.adjustedDate,
        quantityUsed: -Number(a.quantity),
        expectedQuantityUsed: null,
        variance: 0,
        varianceReason: `Manual adjustment${a.movementType ? ` (${a.movementType})` : ""}${a.note ? ` — ${a.note}` : ""}`,
        notes: a.note ?? null,
        createdAt: a.createdAt,
      }))
      setUsage([...hist, ...adjRows])
      setUsageLoaded(true)
    }
    catch (e: any) { toast({ title: "Could not load usage history", description: e?.message, variant: "destructive" }) }
  }

  const itemById = useMemo(() => new Map(items.map((i) => [i.poultryRawMaterialItemId, i])), [items])

  // Filtered + sorted views fed to the tables (stats above stay on the full set).
  const byItem = <T extends { poultryRawMaterialItemId: number }>(rows: T[]) =>
    itemFilter === "all" ? rows : rows.filter((r) => String(r.poultryRawMaterialItemId) === itemFilter)

  const filteredItems = useMemo(() => {
    let rows = filterByDateAndSearch(items, { search, searchKeys: ["itemName", "category"] })
    if (categoryFilter !== "all") rows = rows.filter((i) => i.category === categoryFilter)
    if (unitFilter !== "all") rows = rows.filter((i) => i.unitOfMeasure === unitFilter || i.purchaseUnitOfMeasure === unitFilter)
    return rows
  }, [items, search, categoryFilter, unitFilter])

  // Distinct units actually in use (either role), for the Items unit dropdown.
  const unitOptionsInUse = useMemo(() => {
    const set = new Set<string>()
    items.forEach((i) => { if (i.unitOfMeasure) set.add(i.unitOfMeasure); if (i.purchaseUnitOfMeasure) set.add(i.purchaseUnitOfMeasure) })
    return Array.from(set).sort()
  }, [items])
  const filteredPurchases = useMemo(
    () => byItem(filterByDateAndSearch(purchases, { search, dateFrom, dateTo, searchKeys: ["itemName", "supplierName"], dateKey: "purchaseDate" })),
    [purchases, search, dateFrom, dateTo, itemFilter],
  )
  const filteredUsage = useMemo(
    () => byItem(filterByDateAndSearch(usage, { search, dateFrom, dateTo, searchKeys: ["itemName"], dateKey: "usedDate" })),
    [usage, search, dateFrom, dateTo, itemFilter],
  )

  const sortedItems = useMemo(() => sortData(filteredItems, itemsSort.key, itemsSort.direction), [filteredItems, itemsSort])
  const sortedPurchases = useMemo(() => sortData(filteredPurchases, purchasesSort.key, purchasesSort.direction), [filteredPurchases, purchasesSort])
  const sortedUsage = useMemo(() => sortData(filteredUsage, usageSort.key, usageSort.direction), [filteredUsage, usageSort])

  // Item dropdown shared by the Purchases + Usage filter strips.
  const itemFilterDropdown = (
    <Select value={itemFilter} onValueChange={setItemFilter}>
      <SelectTrigger className="w-[160px]"><SelectValue placeholder="All items" /></SelectTrigger>
      <SelectContent>
        <SelectItem value="all">All items</SelectItem>
        {items.map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}</SelectItem>)}
      </SelectContent>
    </Select>
  )

  // Headline figures for the summary cards.
  const stats = useMemo(() => ({
    itemsCount: items.length,
    activeCount: items.filter((i) => i.isActive).length,
    lowStock: items.filter((i) => i.isActive && i.isLowStock).length,
    purchaseTotal: purchases.reduce((s, p) => s + (Number(p.totalCost) || 0), 0),
    paidTotal: purchases.reduce((s, p) => s + (Number(p.amountPaid) || 0), 0),
    outstanding: purchases.reduce((s, p) => s + (Number(p.balance) || 0), 0),
  }), [items, purchases])
  const unitOptions = (current?: string | null) => {
    const set = [...UNITS]; const c = (current ?? "").trim()
    if (c && !set.includes(c)) set.unshift(c)
    return set
  }

  // ---- Item CRUD ----
  // Tracks the usage method the item had when the edit dialog was opened, so we
  // can warn if the user changes it — switching FIFO/LIFO/HIFO on an item that
  // already has purchases/usage recorded changes which batch future usage draws
  // from, without touching anything already recorded.
  const [originalUsageMethod, setOriginalUsageMethod] = useState<RawMaterialUsageMethod | null>(null)
  function openNewItem() { setEditItemId(null); setItemForm(EMPTY_ITEM); setOriginalUsageMethod(null); setItemOpen(true) }
  function openEditItem(i: PoultryRawMaterialItem) {
    setEditItemId(i.poultryRawMaterialItemId)
    const usageMethod = i.usageMethod ?? "FIFO"
    setItemForm({ itemName: i.itemName, category: i.category, unitOfMeasure: i.unitOfMeasure ?? "", purchaseUnitOfMeasure: i.purchaseUnitOfMeasure ?? "", minimumStockAlert: i.minimumStockAlert, isActive: i.isActive, notes: i.notes ?? null, usageMethod })
    setOriginalUsageMethod(usageMethod)
    setItemOpen(true)
  }
  const usageMethodChanged = editItemId != null && originalUsageMethod != null && itemForm.usageMethod !== originalUsageMethod
  async function saveItem() {
    if (!itemForm.itemName.trim()) { toast({ title: "Item name is required", variant: "destructive" }); return }
    setSavingItem(true)
    // Blank purchase unit → null so the backend defaults it to the production unit.
    const itemPayload = { ...itemForm, purchaseUnitOfMeasure: itemForm.purchaseUnitOfMeasure.trim() || null }
    try {
      if (editItemId) await updatePoultryRawMaterialItem(editItemId, itemPayload)
      else await createPoultryRawMaterialItem(itemPayload)
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
  function openNewPurchase() { setEditPurchaseId(null); setManualProdCost(false); setManualPurchaseCost(false); setPurchaseForm({ ...EMPTY_PURCHASE, poultryCashAccountId: defaultCashAccountId ?? 0 }); setPurchaseOpen(true) }
  function openEditPurchase(p: PoultryRawMaterialPurchase) {
    setEditPurchaseId(p.poultryRawMaterialPurchaseId)
    setManualProdCost(false); setManualPurchaseCost(false)
    setPurchaseForm({
      poultryRawMaterialItemId: p.poultryRawMaterialItemId,
      supplierName: p.supplierName ?? "",
      purchaseDate: (p.purchaseDate || "").split("T")[0] || new Date().toISOString().split("T")[0],
      quantity: p.quantity, unitCost: p.unitCost, totalPurchaseCost: p.totalCost,
      purchaseUnit: p.unitOfMeasure ?? "", productionUnit: p.productionUnit ?? "",
      productionUnitsPerPurchaseUnit: p.productionUnitsPerPurchaseUnit ?? 1,
      paymentMethod: p.paymentMethod ?? "Cash", poultryCashAccountId: p.poultryCashAccountId ?? 0, amountPaid: p.amountPaid, receiptUrl: p.receiptUrl ?? "", notes: p.notes ?? "",
    })
    setPurchaseOpen(true)
  }
  async function savePurchase() {
    if (savingPurchaseRef.current) return // already submitting — ignore extra clicks (slow network)
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
      poultryCashAccountId: f.poultryCashAccountId ? f.poultryCashAccountId : null,
      amountPaid: f.amountPaid,
      receiptUrl: f.receiptUrl || null,
      notes: f.notes || null,
    }
    savingPurchaseRef.current = true
    setSavingPurchase(true)
    try {
      if (editPurchaseId) await updatePoultryRawMaterialPurchase(editPurchaseId, payload)
      else await createPoultryRawMaterialPurchase(payload)
      toast({ title: editPurchaseId ? "Purchase updated" : "Purchase recorded" })
      setPurchaseOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { savingPurchaseRef.current = false; setSavingPurchase(false) }
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
          <Tabs defaultValue="items" onValueChange={(v) => { if (v === "usage") void loadUsage() }} className="gap-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h1 className="text-2xl font-bold">Raw Materials &amp; Supplies</h1>
              <p className="text-sm text-slate-500">Track feed inputs, packaging, medication and other supplies — purchases, costing and usage.</p>
            </div>
            <div className="flex flex-wrap items-center gap-2 self-start sm:self-auto sm:ml-auto">
              <RecalculateStockButton items={items} onDone={load} />
              <Button variant="outline" onClick={openNewItem}><Plus className="w-4 h-4 mr-1" /> New Item</Button>
              <Button variant="outline" onClick={() => router.push("/poultry-feed-production")}><Factory className="w-4 h-4 mr-1" /> Produce Feed</Button>
              <Button onClick={openNewPurchase}><ShoppingCart className="w-4 h-4 mr-1" /> Record Purchase</Button>
            </div>
          </div>
          <TabsList className="self-start">
            <TabsTrigger value="items"><Box className="w-4 h-4 mr-1" /> Items</TabsTrigger>
            <TabsTrigger value="purchases"><ShoppingCart className="w-4 h-4 mr-1" /> Purchases</TabsTrigger>
            <TabsTrigger value="usage"><Wallet className="w-4 h-4 mr-1" /> Usage History</TabsTrigger>
          </TabsList>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
          ) : (
            <>
              {/* Summary */}
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide">
                    <Box className="w-4 h-4 text-blue-600" /> Active Items
                  </div>
                  <div className="mt-1 text-2xl font-bold text-slate-900 tabular-nums">{stats.activeCount.toLocaleString()}</div>
                  <div className="text-xs text-slate-400 mt-0.5">of {stats.itemsCount.toLocaleString()} total</div>
                </div>
                <div className={cn("p-4 rounded-xl border shadow-sm", stats.lowStock > 0 ? "bg-amber-50 border-amber-200" : "bg-white border-slate-200")}>
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide">
                    <AlertTriangle className={cn("w-4 h-4", stats.lowStock > 0 ? "text-amber-600" : "text-slate-400")} /> Low Stock
                  </div>
                  <div className={cn("mt-1 text-2xl font-bold tabular-nums", stats.lowStock > 0 ? "text-amber-700" : "text-slate-900")}>{stats.lowStock.toLocaleString()}</div>
                  <div className="text-xs text-slate-400 mt-0.5">{stats.lowStock > 0 ? "need restocking" : "all stocked"}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide">
                    <ShoppingCart className="w-4 h-4 text-emerald-600" /> Purchases Value
                  </div>
                  <div className="mt-1 text-2xl font-bold text-slate-900 tabular-nums">{gh(stats.purchaseTotal)}</div>
                  <div className="text-xs text-slate-400 mt-0.5">Paid {gh(stats.paidTotal)}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide">
                    <Wallet className={cn("w-4 h-4", stats.outstanding > 0 ? "text-red-600" : "text-slate-400")} /> Outstanding
                  </div>
                  <div className={cn("mt-1 text-2xl font-bold tabular-nums", stats.outstanding > 0 ? "text-red-600" : "text-emerald-700")}>{gh(stats.outstanding)}</div>
                  <div className="text-xs text-slate-400 mt-0.5">owed to suppliers</div>
                </div>
              </div>

              {/* ITEMS */}
              <TabsContent value="items">
                <Card><CardContent className="p-4">
                  <div className="mb-3">
                    <h2 className="text-base font-semibold text-slate-900">Inventory Items</h2>
                    <p className="text-xs text-slate-500">Feed, packaging, medication and other stock-tracked supplies.</p>
                  </div>
                  <div className="mb-3"><ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search item or category" extras={<>
                    <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                      <SelectTrigger className="w-[160px]"><SelectValue placeholder="All categories" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All categories</SelectItem>
                        {CATEGORIES.map((c) => <SelectItem key={c} value={c}>{categoryLabel(c)}</SelectItem>)}
                      </SelectContent>
                    </Select>
                    <Select value={unitFilter} onValueChange={setUnitFilter}>
                      <SelectTrigger className="w-[140px]"><SelectValue placeholder="All units" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All units</SelectItem>
                        {unitOptionsInUse.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </>} /></div>
                  <div className="hidden md:block overflow-x-auto"><Table className="min-w-[640px]">
                    <TableHeader><TableRow>
                      {(() => { const onSort = (k: string) => setItemsSort((s) => toggleSort(k, s.key, s.direction)); const cs = itemsSort.key, cd = itemsSort.direction; return (<>
                      <SortableHeader label="Item" sortKey="itemName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Category" sortKey="category" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Purchase Unit" sortKey="purchaseUnitOfMeasure" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Production Unit" sortKey="unitOfMeasure" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="In stock" sortKey="currentQuantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Min alert" sortKey="minimumStockAlert" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Status" sortKey="isActive" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      </>) })()}
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {filteredItems.length === 0 ? (
                        <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-6">No items yet.</TableCell></TableRow>
                      ) : sortedItems.map((i) => (
                        <TableRow key={i.poultryRawMaterialItemId}>
                          <TableCell className="font-medium">{i.itemName}</TableCell>
                          <TableCell>{categoryLabel(i.category)}</TableCell>
                          <TableCell>{i.purchaseUnitOfMeasure ?? "—"}</TableCell>
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
                  </Table></div>
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {filteredItems.length === 0 ? <div className="text-center text-slate-500 py-6">No items yet.</div>
                      : sortedItems.map((i) => (
                        <FieldCard key={i.poultryRawMaterialItemId} title={i.itemName}
                          badge={!i.isActive ? <Badge variant="secondary">Inactive</Badge> : i.isLowStock ? <Badge className="bg-amber-100 text-amber-700">Low stock</Badge> : <Badge className="bg-green-100 text-green-700">OK</Badge>}
                          fields={[["Category", categoryLabel(i.category)], ["Purchase Unit", i.purchaseUnitOfMeasure ?? "—"], ["Production Unit", i.unitOfMeasure ?? "—"], ["In stock", i.currentQuantity.toLocaleString()], ["Min alert", i.minimumStockAlert.toLocaleString()]]}
                          actions={<>
                            <Button variant="ghost" size="sm" onClick={() => openEditItem(i)}><Pencil className="w-4 h-4" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDeleteItemTarget(i)}><Trash2 className="w-4 h-4 text-red-500" /></Button>
                          </>} />
                      ))}
                  </div>
                </CardContent></Card>
              </TabsContent>

              {/* PURCHASES */}
              <TabsContent value="purchases">
                <Card><CardContent className="p-4">
                  <div className="mb-3">
                    <h2 className="text-base font-semibold text-slate-900">Purchase History</h2>
                    <p className="text-xs text-slate-500">Stock received, costing, and supplier part payments.</p>
                  </div>
                  <div className="mb-3"><ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search item or supplier" extras={itemFilterDropdown} /></div>
                  <div className="hidden md:block overflow-x-auto"><Table className="min-w-[640px]">
                    <TableHeader><TableRow>
                      {(() => { const onSort = (k: string) => setPurchasesSort((s) => toggleSort(k, s.key, s.direction)); const cs = purchasesSort.key, cd = purchasesSort.direction; return (<>
                      <SortableHeader label="Date" sortKey="purchaseDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Item" sortKey="itemName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Supplier" sortKey="supplierName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Purchase Qty" sortKey="quantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Production Level Qty" sortKey="productionQuantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Unit Price" sortKey="unitCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Total" sortKey="totalCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Paid" sortKey="amountPaid" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Balance" sortKey="balance" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      </>) })()}
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {filteredPurchases.length === 0 ? (
                        <TableRow><TableCell colSpan={10} className="text-center text-slate-500 py-6">No purchases yet.</TableCell></TableRow>
                      ) : sortedPurchases.map((p) => (
                        <TableRow key={p.poultryRawMaterialPurchaseId}>
                          <TableCell>{(p.purchaseDate || "").split("T")[0]}</TableCell>
                          <TableCell className="font-medium">{p.itemName}</TableCell>
                          <TableCell>{p.supplierName ?? "—"}</TableCell>
                          <TableCell className="text-right">{p.quantity.toLocaleString()} {p.unitOfMeasure ?? ""}</TableCell>
                          <TableCell className="text-right">{p.productionQuantity != null ? `${p.productionQuantity.toLocaleString()} ${p.productionUnit ?? ""}`.trim() : "—"}</TableCell>
                          <TableCell className="text-right">{gh(p.unitCost)}{p.unitOfMeasure ? ` / ${p.unitOfMeasure}` : ""}</TableCell>
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
                  </Table></div>
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {filteredPurchases.length === 0 ? <div className="text-center text-slate-500 py-6">No purchases yet.</div>
                      : sortedPurchases.map((p) => (
                        <FieldCard key={p.poultryRawMaterialPurchaseId} title={p.itemName}
                          badge={<span className="text-xs text-slate-500">{(p.purchaseDate || "").split("T")[0]}</span>}
                          fields={[["Supplier", p.supplierName ?? "—"], ["Purchase Qty", `${p.quantity.toLocaleString()} ${p.unitOfMeasure ?? ""}`], ["Production Qty", p.productionQuantity != null ? `${p.productionQuantity.toLocaleString()} ${p.productionUnit ?? ""}`.trim() : "—"], ["Unit Price", gh(p.unitCost)], ["Total", gh(p.totalCost)], ["Paid", gh(p.amountPaid)], ["Balance", p.balance > 0 ? <span className="text-amber-600 font-medium">{gh(p.balance)}</span> : gh(0)]]}
                          actions={<>
                            {p.balance > 0 && <Button variant="ghost" size="sm" onClick={() => openPayBalance(p)} title="Pay balance"><Wallet className="w-4 h-4 text-emerald-600" /></Button>}
                            <Button variant="ghost" size="sm" onClick={() => openEditPurchase(p)}><Pencil className="w-4 h-4" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDeletePurchaseTarget(p)}><Trash2 className="w-4 h-4 text-red-500" /></Button>
                          </>} />
                      ))}
                  </div>
                </CardContent></Card>
              </TabsContent>

              {/* USAGE */}
              <TabsContent value="usage">
                <Card><CardContent className="p-4">
                  <div className="mb-3">
                    <h2 className="text-base font-semibold text-slate-900">Usage History</h2>
                    <p className="text-xs text-slate-500">Stock consumed when production batches are recorded.</p>
                  </div>
                  <div className="mb-3"><ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search item" extras={itemFilterDropdown} /></div>
                  <div className="hidden md:block overflow-x-auto"><Table className="min-w-[640px]">
                    <TableHeader><TableRow>
                      {(() => { const onSort = (k: string) => setUsageSort((s) => toggleSort(k, s.key, s.direction)); const cs = usageSort.key, cd = usageSort.direction; return (<>
                      <SortableHeader label="Date" sortKey="usedDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Item" sortKey="itemName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Used" sortKey="quantityUsed" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Expected" sortKey="expectedQuantityUsed" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Variance" sortKey="variance" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Reason" sortKey="varianceReason" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      </>) })()}
                    </TableRow></TableHeader>
                    <TableBody>
                      {filteredUsage.length === 0 ? (
                        <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-6">No usage recorded yet. Usage is created when production batches are approved (coming with the production slice).</TableCell></TableRow>
                      ) : sortedUsage.map((u) => (
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
                  </Table></div>
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {filteredUsage.length === 0 ? <div className="text-center text-slate-500 py-6">No usage recorded yet.</div>
                      : sortedUsage.map((u) => (
                        <FieldCard key={u.poultryRawMaterialUsageId} title={u.itemName}
                          badge={<span className="text-xs text-slate-500">{(u.usedDate || "").split("T")[0]}</span>}
                          fields={[["Used", `${u.quantityUsed.toLocaleString()} ${u.unitOfMeasure ?? ""}`], ["Expected", u.expectedQuantityUsed?.toLocaleString() ?? "—"], ["Variance", u.variance.toLocaleString()], ["Reason", u.varianceReason ?? "—"]]} />
                      ))}
                  </div>
                </CardContent></Card>
              </TabsContent>
            </>
          )}
          </Tabs>
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
                <SelectContent>{CATEGORIES.map((c) => <SelectItem key={c} value={c}>{categoryLabel(c)}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Production unit of measure" hint="How it's stocked & consumed">
              <Select value={itemForm.unitOfMeasure || ""} onValueChange={(v) => setItemForm({ ...itemForm, unitOfMeasure: v })}>
                <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                <SelectContent>{unitOptions(itemForm.unitOfMeasure).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Purchase unit of measure" hint="How it's bought — defaults to the production unit">
              <Select value={itemForm.purchaseUnitOfMeasure || ""} onValueChange={(v) => setItemForm({ ...itemForm, purchaseUnitOfMeasure: v })}>
                <SelectTrigger><SelectValue placeholder="Same as production unit" /></SelectTrigger>
                <SelectContent>{unitOptions(itemForm.purchaseUnitOfMeasure).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Low-stock alert at"><NumberInput min={0} step="0.001" value={itemForm.minimumStockAlert} onChange={(e) => setItemForm({ ...itemForm, minimumStockAlert: Number(e.target.value) || 0 })} /></FormField>
            {USAGE_METHOD_CATEGORIES.includes(itemForm.category) && (
              <FormField label="Order of item usage">
                <div className="flex flex-col gap-2">
                  {USAGE_METHOD_OPTIONS.map((o) => (
                    <label
                      key={o.value}
                      className={`flex items-start gap-2.5 rounded-md border px-3 py-2 cursor-pointer transition-colors ${
                        itemForm.usageMethod === o.value
                          ? "border-emerald-600 bg-emerald-50"
                          : "border-slate-200 hover:border-slate-300"
                      }`}
                    >
                      <input
                        type="radio"
                        name="usageMethod"
                        value={o.value}
                        checked={itemForm.usageMethod === o.value}
                        onChange={() => setItemForm({ ...itemForm, usageMethod: o.value })}
                        className="mt-0.5 accent-emerald-600"
                      />
                      <span>
                        <span className="block text-sm font-semibold text-slate-800">{o.label}</span>
                        <span className="block text-xs text-slate-500">{o.hint}</span>
                      </span>
                    </label>
                  ))}
                </div>
                {usageMethodChanged && (
                  <div className="mt-2 flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-2">
                    <AlertTriangle className="w-4 h-4 text-amber-600 mt-0.5 flex-shrink-0" />
                    <p className="text-xs text-amber-800">
                      <strong>This is a big change.</strong> It won't touch anything already recorded as used — but from now on, this item will draw from a different batch first. If this item already has purchases or usage history, double-check this is really what you want before saving.
                    </p>
                  </div>
                )}
                <p className="text-xs text-slate-500 mt-1">
                  Decides which purchase batch gets used first when this item is picked as "used" on a production record.
                </p>
              </FormField>
            )}
            <FormField label="Notes"><Textarea rows={3} placeholder="Optional notes about this item" value={itemForm.notes ?? ""} onChange={(e) => setItemForm({ ...itemForm, notes: e.target.value || null })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setItemOpen(false)}>Cancel</Button>
            <Button onClick={saveItem} disabled={savingItem}>{savingItem ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Purchase dialog */}
      <Dialog open={purchaseOpen} onOpenChange={setPurchaseOpen}>
        <DialogContent className="w-[95vw] max-w-[1100px] max-h-[90vh] overflow-y-auto">
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
            // Purchase unit is an editable per-entry label (mirrors the water side);
            // it defaults to the item's unit of measure. Display-only (drives the
            // quantity/cost labels) — not persisted, so no schema impact.
            const purchaseUnitLabel = f.purchaseUnit || selItem?.unitOfMeasure || "unit"
            return (
              <>
                <FormSection title="Item, Supplier & Date" color="indigo">
                  <FormField label="Raw material item *" full>
                    <Select value={f.poultryRawMaterialItemId ? String(f.poultryRawMaterialItemId) : ""} onValueChange={(v) => { const id = Number(v); const it = itemById.get(id); setPurchaseForm({ ...f, poultryRawMaterialItemId: id, purchaseUnit: it?.purchaseUnitOfMeasure || it?.unitOfMeasure || f.purchaseUnit, productionUnit: it?.unitOfMeasure || f.productionUnit }) }}>
                      <SelectTrigger><SelectValue placeholder="Pick item" /></SelectTrigger>
                      <SelectContent>{items.filter((i) => i.isActive).map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}{i.unitOfMeasure ? ` (${i.unitOfMeasure})` : ""}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Supplier" full><Input value={f.supplierName} onChange={(e) => setPurchaseForm({ ...f, supplierName: e.target.value })} placeholder="Supplier name" /></FormField>
                  <FormField label="Purchase date"><Input type="date" value={f.purchaseDate} onChange={(e) => setPurchaseForm({ ...f, purchaseDate: e.target.value })} /></FormField>
                  <FormField label="Payment method">
                    <Select value={f.paymentMethod} onValueChange={(v) => setPurchaseForm({ ...f, paymentMethod: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                </FormSection>

                <FormSection title="Purchase Quantity & Production Costing" color="blue">
                  <FormField label="Purchase unit *">
                    <Select value={f.purchaseUnit || ""} onValueChange={(v) => setPurchaseForm({ ...f, purchaseUnit: v })}>
                      <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                      <SelectContent>{unitOptions(f.purchaseUnit).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label={`Purchase quantity${purchaseUnitLabel ? ` (${purchaseUnitLabel})` : ""} *`}><NumberInput min={0} step="0.001" value={f.quantity} onChange={(e) => setPurchaseForm({ ...f, quantity: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="" full>
                    <div className="flex items-center justify-between rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
                      <div>
                        <div className="text-sm font-medium text-slate-700">Enter purchase unit cost manually</div>
                        <div className="text-xs text-slate-500">Turn off the auto-calculation and type the purchase unit cost yourself.</div>
                      </div>
                      <Switch checked={manualPurchaseCost} onCheckedChange={setManualPurchaseCost} />
                    </div>
                  </FormField>
                  <FormField label="Total purchase cost *"><NumberInput min={0} step="0.01" value={Number(total.toFixed(2))} disabled={manualPurchaseCost} onChange={(e) => setPurchaseForm({ ...f, totalPurchaseCost: Number(e.target.value) || 0 })} /></FormField>
                  {manualPurchaseCost ? (
                    <FormField label={`Purchase unit cost${purchaseUnitLabel ? ` (per ${purchaseUnitLabel})` : ""}`} hint="Manual — sets the total for you">
                      <NumberInput min={0} step="0.0001" value={Number(unitCost.toFixed(4))} onChange={(e) => {
                        const c = Number(e.target.value) || 0
                        setPurchaseForm({ ...f, totalPurchaseCost: qty > 0 ? Number((c * qty).toFixed(2)) : f.totalPurchaseCost })
                      }} />
                    </FormField>
                  ) : (
                    <FormField label="Purchase unit cost (auto)"><Input readOnly tabIndex={-1} className={roCls} value={`${gh(unitCost)}${purchaseUnitLabel ? ` per ${purchaseUnitLabel}` : ""}`} /></FormField>
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
                  <FormField label="Production unit">
                    <Select value={f.productionUnit || ""} onValueChange={(v) => setPurchaseForm({ ...f, productionUnit: v })}>
                      <SelectTrigger><SelectValue placeholder="Pick unit" /></SelectTrigger>
                      <SelectContent>{unitOptions(f.productionUnit).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Production units per purchase unit"><NumberInput min={0} step="0.0001" value={f.productionUnitsPerPurchaseUnit} onChange={(e) => setPurchaseForm({ ...f, productionUnitsPerPurchaseUnit: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Production-level quantity" hint="Editable — sets units per purchase unit"><NumberInput min={0} step="0.001" value={Number(prodQty.toFixed(4))} onChange={(e) => { const v = Number(e.target.value) || 0; setPurchaseForm({ ...f, productionUnitsPerPurchaseUnit: qty > 0 ? Number((v / qty).toFixed(8)) : f.productionUnitsPerPurchaseUnit }) }} /></FormField>
                  {manualProdCost ? (
                    <FormField label="Production-level unit cost" hint="Manual — sets the conversion for you">
                      <NumberInput min={0} step="0.0001" value={Number(prodUnitCost.toFixed(4))} onChange={(e) => {
                        const c = Number(e.target.value) || 0
                        // production unit cost = total / (qty × perPurchase) ⇒ perPurchase = total / (cost × qty)
                        const newPer = (c > 0 && qty > 0 && total > 0) ? Number((total / (c * qty)).toFixed(8)) : f.productionUnitsPerPurchaseUnit
                        setPurchaseForm({ ...f, productionUnitsPerPurchaseUnit: newPer })
                      }} />
                    </FormField>
                  ) : (
                    <FormField label="Production-level unit cost (auto)"><Input readOnly tabIndex={-1} className={roCls} value={`${gh(prodUnitCost)}${f.productionUnit ? ` per ${f.productionUnit}` : ""}`} /></FormField>
                  )}
                  <FormField label="" full><p className="text-xs text-slate-500">If you buy and use the same unit, set <span className="font-medium">Production units per purchase unit = 1</span> — the production figures then match the purchase figures.</p></FormField>
                </FormSection>

                <FormSection title="Payment" color="amber">
                  <FormField label="Amount paid"><NumberInput min={0} step="0.01" value={f.amountPaid} onChange={(e) => setPurchaseForm({ ...f, amountPaid: Number(e.target.value) || 0 })} /></FormField>
                  <FormField label="Pay from cash account">
                    <Select value={f.poultryCashAccountId ? String(f.poultryCashAccountId) : "none"} onValueChange={(v) => setPurchaseForm({ ...f, poultryCashAccountId: v === "none" ? 0 : Number(v) })}>
                      <SelectTrigger><SelectValue placeholder="None (no cash movement)" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">None (no cash movement)</SelectItem>
                        {cashAccounts.map((a) => (
                          <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                            {a.accountName} ({gh(a.currentBalance)})
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Balance (auto)"><Input readOnly tabIndex={-1} className={roCls} value={gh(Math.max(0, total - (f.amountPaid || 0)))} /></FormField>
                  <FormField label="" full><p className="text-xs text-slate-500">Choosing a cash account posts a cash-out for the amount paid and reduces that account's balance.</p></FormField>
                </FormSection>

                <FormSection title="Notes" color="slate" columns={1}>
                  <FormField label="Notes"><Textarea rows={3} placeholder="Optional notes about this purchase" value={f.notes} onChange={(e) => setPurchaseForm({ ...f, notes: e.target.value })} /></FormField>
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

"use client"

import { Suspense, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
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
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
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
import { PoultryPurchaseDialog } from "@/components/raw-materials/poultry-purchase-dialog"

const CATEGORIES = ["FeedIngredient", "FinishedFeed", "Packaging", "Medication", "Vaccine", "Bedding", "Disinfectant", "Equipment", "SparePart", "Fuel", "Other"]
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

// Tabs are reflected in the URL as ?tab=items|purchases|usage, so a tab can be
// linked to, bookmarked and reached with the back button — same pattern as
// /business-office/setup.
const TABS = ["items", "purchases", "usage"] as const
type TabKey = (typeof TABS)[number]

function PoultryRawMaterialsPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
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
  const [editingPurchase, setEditingPurchase] = useState<PoultryRawMaterialPurchase | null>(null)
  // Seeds a new purchase — set by the Feed Production deep link.
  const [purchaseDefaults, setPurchaseDefaults] = useState<{ itemId?: number | null; quantity?: number | null } | undefined>(undefined)
  const [deletePurchaseTarget, setDeletePurchaseTarget] = useState<PoultryRawMaterialPurchase | null>(null)

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

  // ?purchase=1[&itemId=N][&qty=X] opens the purchase dialog straight away with
  // the item preselected and the quantity prefilled. Feed Production sends
  // farmers here to buy an ingredient rather than recording it inline, and
  // passes the quantity that batch is short of; Operations > Purchase > Record
  // Purchase in the top nav uses the bare ?purchase=1 form. Waits for the items
  // to load so the item can actually be matched.
  //
  // Driven off searchParams (not window.location) so a click on the nav link
  // while already on this page re-fires it — a ref guard would swallow the
  // second visit. The router.replace below clears the param, so the next run
  // falls straight through the early return: no loop.
  useEffect(() => {
    if (loading) return
    if (searchParams.get("purchase") !== "1") return
    const qty = Number(searchParams.get("qty"))
    setEditingPurchase(null)
    setPurchaseDefaults({ itemId: Number(searchParams.get("itemId")) || null, quantity: Number.isFinite(qty) && qty > 0 ? qty : null })
    setPurchaseOpen(true)
    // Drop the params so a refresh or a back-navigation doesn't reopen it.
    router.replace("/poultry-raw-materials", { scroll: false })
  }, [loading, items, defaultCashAccountId, router, searchParams])

  async function load() {
    setLoading(true)
    try {
      const [is, ps, cas] = await Promise.all([listPoultryRawMaterialItems(), listPoultryRawMaterialPurchases(), listPoultryCashAccounts().catch(() => [])])
      setItems(is); setPurchases(ps); setCashAccounts((cas as PoultryCashAccount[]).filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Could not load raw materials", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  // The URL is the source of truth for which tab is showing; an unknown or
  // missing ?tab= falls back to Items rather than rendering an empty panel.
  const tabParam = searchParams.get("tab")
  const tab: TabKey = (TABS as readonly string[]).includes(tabParam ?? "") ? (tabParam as TabKey) : "items"

  const selectTab = (v: string) => {
    // replace, not push: flipping between tabs shouldn't bury the previous page
    // under a stack of history entries. scroll:false keeps the list in place.
    router.replace(v === "items" ? "/poultry-raw-materials" : `/poultry-raw-materials?tab=${v}`, { scroll: false })
  }

  // Usage history is fetched lazily the first time its tab is shown — including
  // when the page is opened straight at ?tab=usage, which no click would cover.
  useEffect(() => {
    if (tab === "usage") void loadUsage()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab])

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
  const pgItems = usePagination(sortedItems)
  const sortedPurchases = useMemo(() => sortData(filteredPurchases, purchasesSort.key, purchasesSort.direction), [filteredPurchases, purchasesSort])
  const pgPurchases = usePagination(sortedPurchases)
  const sortedUsage = useMemo(() => sortData(filteredUsage, usageSort.key, usageSort.direction), [filteredUsage, usageSort])
  const pgUsage = usePagination(sortedUsage)

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

  // Headline figures for the summary cards. Feed the farm produced is listed in
  // the history but kept out of the spend figures — its cost is the ingredients,
  // which were already counted when they were bought. Ingredients a batch bought
  // are real supplier spend, so those do count.
  const spend = useMemo(() => purchases.filter((p) => p.feedProductionRole !== "Produced"), [purchases])
  const stats = useMemo(() => ({
    itemsCount: items.length,
    activeCount: items.filter((i) => i.isActive).length,
    lowStock: items.filter((i) => i.isActive && i.isLowStock).length,
    purchaseTotal: spend.reduce((s, p) => s + (Number(p.totalCost) || 0), 0),
    paidTotal: spend.reduce((s, p) => s + (Number(p.amountPaid) || 0), 0),
    outstanding: spend.reduce((s, p) => s + (Number(p.balance) || 0), 0),
    produced: purchases.filter((p) => p.feedProductionRole === "Produced").length,
  }), [items, purchases, spend])
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
  function openNewPurchase() { setEditingPurchase(null); setPurchaseDefaults(undefined); setPurchaseOpen(true) }
  function openEditPurchase(p: PoultryRawMaterialPurchase) { setEditingPurchase(p); setPurchaseDefaults(undefined); setPurchaseOpen(true) }
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

  // Segmented control styling. The shadcn default (muted bar, white active pill)
  // reads as almost-flat on this page's grey background, so the active tab gets
  // a solid blue fill, white text and a lift — the switch is unmissable.
  const tabTriggerCls =
    "h-auto flex-none shrink-0 gap-1.5 rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 sm:px-4 " +
    "transition-all hover:bg-slate-100 hover:text-slate-900 " +
    "data-[state=active]:bg-blue-600 data-[state=active]:text-white data-[state=active]:shadow-md " +
    "data-[state=active]:shadow-blue-600/25 data-[state=active]:hover:bg-blue-600 data-[state=active]:hover:text-white"
  // Count pill inside each trigger — inverted on the active (blue) tab.
  const tabCountCls =
    "ml-0.5 rounded-full bg-slate-100 px-1.5 py-0.5 text-[11px] font-bold tabular-nums text-slate-600 " +
    "group-data-[state=active]:bg-white/20 group-data-[state=active]:text-white"

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <Tabs value={tab} onValueChange={selectTab} className="gap-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="min-w-0">
              <h1 className="text-2xl font-bold">Raw Materials &amp; Supplies</h1>
              <p className="text-sm text-slate-500">Track feed inputs, packaging, medication and other supplies — purchases, costing and usage.</p>
            </div>
            {/* One row from sm up — the heading shrinks rather than pushing
                Record Purchase onto a line of its own. */}
            <div className="flex flex-wrap items-center gap-2 self-start sm:self-auto sm:ml-auto sm:flex-nowrap sm:shrink-0">
              <RecalculateStockButton items={items} onDone={load} />
              <Button variant="outline" onClick={openNewItem}><Plus className="w-4 h-4 mr-1" /> New Item</Button>
              <Button variant="outline" onClick={() => router.push("/poultry-feed-production")}><Factory className="w-4 h-4 mr-1" /> Produce Feed</Button>
              <Button onClick={openNewPurchase}><ShoppingCart className="w-4 h-4 mr-1" /> Record Purchase</Button>
            </div>
          </div>
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
                  <div className="text-xs text-slate-400 mt-0.5">
                    Paid {gh(stats.paidTotal)}
                    {stats.produced > 0 && <> · excludes {stats.produced} produced feed {stats.produced === 1 ? "lot" : "lots"}</>}
                  </div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide">
                    <Wallet className={cn("w-4 h-4", stats.outstanding > 0 ? "text-red-600" : "text-slate-400")} /> Outstanding
                  </div>
                  <div className={cn("mt-1 text-2xl font-bold tabular-nums", stats.outstanding > 0 ? "text-red-600" : "text-emerald-700")}>{gh(stats.outstanding)}</div>
                  <div className="text-xs text-slate-400 mt-0.5">owed to suppliers</div>
                </div>
              </div>

              {/* Tabs sit between the summary cards and the table they switch. */}
              <TabsList className="h-auto w-full max-w-full justify-start gap-1 overflow-x-auto rounded-xl border border-slate-200 bg-white p-1 shadow-sm sm:w-fit">
                <TabsTrigger value="items" className={cn("group", tabTriggerCls)}>
                  <Box className="w-4 h-4" /> Items
                  <span className={tabCountCls}>{items.length.toLocaleString()}</span>
                </TabsTrigger>
                <TabsTrigger value="purchases" className={cn("group", tabTriggerCls)}>
                  <ShoppingCart className="w-4 h-4" /> Purchases
                  <span className={tabCountCls}>{purchases.length.toLocaleString()}</span>
                </TabsTrigger>
                <TabsTrigger value="usage" className={cn("group", tabTriggerCls)}>
                  <Wallet className="w-4 h-4" /> Usage History
                  {usageLoaded && <span className={tabCountCls}>{usage.length.toLocaleString()}</span>}
                </TabsTrigger>
              </TabsList>

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
                      ) : pgItems.pageItems.map((i) => (
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
                  <DataPagination {...pgItems.paginationProps} />
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
                    <p className="text-xs text-slate-500">Stock received, costing, and supplier part payments. Feed produced on the farm appears here too, tagged with its batch.</p>
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
                      ) : pgPurchases.pageItems.map((p) => (
                        <TableRow key={p.poultryRawMaterialPurchaseId}>
                          <TableCell>{(p.purchaseDate || "").split("T")[0]}</TableCell>
                          <TableCell className="font-medium">
                            {p.itemName}
                            {p.feedProductionRole && (
                              <Badge variant="outline" className={cn("ml-2 text-[10px] font-normal", p.feedProductionRole === "Produced" ? "border-emerald-300 text-emerald-700" : "border-indigo-300 text-indigo-700")}>
                                {p.feedProductionRole === "Produced" ? "Produced" : "Bought for production"}
                                {p.feedProductionBatchNumber ? ` · ${p.feedProductionBatchNumber}` : ""}
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell>{p.supplierName ?? "—"}</TableCell>
                          <TableCell className="text-right">{p.quantity.toLocaleString()} {p.unitOfMeasure ?? ""}</TableCell>
                          <TableCell className="text-right">{p.productionQuantity != null ? `${p.productionQuantity.toLocaleString()} ${p.productionUnit ?? ""}`.trim() : "—"}</TableCell>
                          <TableCell className="text-right">{gh(p.unitCost)}{p.unitOfMeasure ? ` / ${p.unitOfMeasure}` : ""}</TableCell>
                          <TableCell className="text-right">{gh(p.totalCost)}</TableCell>
                          <TableCell className="text-right">{gh(p.amountPaid)}</TableCell>
                          <TableCell className="text-right">{p.balance > 0 ? <span className="text-amber-600 font-medium">{gh(p.balance)}</span> : gh(0)}</TableCell>
                          <TableCell className="text-right">
                            {/* A feed-production lot belongs to its batch: editing or
                                deleting it here would desync the batch's costing and
                                its stock. Reverse the batch instead. */}
                            {p.sourceFeedProductionBatchId ? (
                              <Button variant="ghost" size="sm" onClick={() => router.push(`/poultry-feed-production/${p.sourceFeedProductionBatchId}`)} title="Open the feed production batch">
                                <Factory className="w-4 h-4 text-indigo-600" />
                              </Button>
                            ) : (
                              <>
                                {p.balance > 0 && <Button variant="ghost" size="sm" onClick={() => openPayBalance(p)} title="Pay balance"><Wallet className="w-4 h-4 text-emerald-600" /></Button>}
                                <Button variant="ghost" size="sm" onClick={() => openEditPurchase(p)}><Pencil className="w-4 h-4" /></Button>
                                <Button variant="ghost" size="sm" onClick={() => setDeletePurchaseTarget(p)}><Trash2 className="w-4 h-4 text-red-500" /></Button>
                              </>
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                  <DataPagination {...pgPurchases.paginationProps} />
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {filteredPurchases.length === 0 ? <div className="text-center text-slate-500 py-6">No purchases yet.</div>
                      : sortedPurchases.map((p) => (
                        <FieldCard key={p.poultryRawMaterialPurchaseId} title={p.itemName}
                          badge={p.feedProductionRole
                            ? <Badge variant="outline" className={cn("text-[10px] font-normal", p.feedProductionRole === "Produced" ? "border-emerald-300 text-emerald-700" : "border-indigo-300 text-indigo-700")}>{p.feedProductionRole === "Produced" ? "Produced" : "Bought for production"}{p.feedProductionBatchNumber ? ` · ${p.feedProductionBatchNumber}` : ""}</Badge>
                            : <span className="text-xs text-slate-500">{(p.purchaseDate || "").split("T")[0]}</span>}
                          fields={[["Supplier", p.supplierName ?? "—"], ["Purchase Qty", `${p.quantity.toLocaleString()} ${p.unitOfMeasure ?? ""}`], ["Production Qty", p.productionQuantity != null ? `${p.productionQuantity.toLocaleString()} ${p.productionUnit ?? ""}`.trim() : "—"], ["Unit Price", gh(p.unitCost)], ["Total", gh(p.totalCost)], ["Paid", gh(p.amountPaid)], ["Balance", p.balance > 0 ? <span className="text-amber-600 font-medium">{gh(p.balance)}</span> : gh(0)]]}
                          actions={p.sourceFeedProductionBatchId
                            ? <Button variant="ghost" size="sm" onClick={() => router.push(`/poultry-feed-production/${p.sourceFeedProductionBatchId}`)} title="Open the feed production batch"><Factory className="w-4 h-4 text-indigo-600" /></Button>
                            : <>
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
                    <p className="text-xs text-slate-500">Stock consumed when production batches are recorded, including ingredients mixed into feed. Stock adjustments show here too.</p>
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
                      ) : pgUsage.pageItems.map((u) => (
                        <TableRow key={u.poultryRawMaterialUsageId}>
                          <TableCell>{(u.usedDate || "").split("T")[0]}</TableCell>
                          <TableCell className="font-medium">
                            {u.itemName}
                            {u.poultryFeedProductionBatchId && (
                              <button
                                type="button"
                                onClick={() => router.push(`/poultry-feed-production/${u.poultryFeedProductionBatchId}`)}
                                title={u.feedProductionFeedName ? `Produced ${u.feedProductionFeedName}` : "Open the feed production batch"}
                              >
                                <Badge variant="outline" className="ml-2 text-[10px] font-normal border-indigo-300 text-indigo-700 hover:bg-indigo-50">
                                  <Factory className="w-3 h-3 mr-1" />
                                  Feed production{u.feedProductionBatchNumber ? ` · ${u.feedProductionBatchNumber}` : ""}
                                </Badge>
                              </button>
                            )}
                          </TableCell>
                          <TableCell className="text-right">{u.quantityUsed.toLocaleString()} {u.unitOfMeasure ?? ""}</TableCell>
                          <TableCell className="text-right">{u.expectedQuantityUsed?.toLocaleString() ?? "—"}</TableCell>
                          <TableCell className="text-right">{u.variance.toLocaleString()}</TableCell>
                          <TableCell>{u.varianceReason ?? (u.feedProductionFeedName ? `Mixed into ${u.feedProductionFeedName}` : "—")}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                  <DataPagination {...pgUsage.paginationProps} />
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {filteredUsage.length === 0 ? <div className="text-center text-slate-500 py-6">No usage recorded yet.</div>
                      : sortedUsage.map((u) => (
                        <FieldCard key={u.poultryRawMaterialUsageId} title={u.itemName}
                          badge={u.poultryFeedProductionBatchId
                            ? <Badge variant="outline" className="text-[10px] font-normal border-indigo-300 text-indigo-700"><Factory className="w-3 h-3 mr-1" />Feed production{u.feedProductionBatchNumber ? ` · ${u.feedProductionBatchNumber}` : ""}</Badge>
                            : <span className="text-xs text-slate-500">{(u.usedDate || "").split("T")[0]}</span>}
                          fields={[["Used", `${u.quantityUsed.toLocaleString()} ${u.unitOfMeasure ?? ""}`], ["Expected", u.expectedQuantityUsed?.toLocaleString() ?? "—"], ["Variance", u.variance.toLocaleString()], ["Reason", u.varianceReason ?? (u.feedProductionFeedName ? `Mixed into ${u.feedProductionFeedName}` : "—")]]}
                          actions={u.poultryFeedProductionBatchId
                            ? <Button variant="ghost" size="sm" onClick={() => router.push(`/poultry-feed-production/${u.poultryFeedProductionBatchId}`)} title="Open the feed production batch"><Factory className="w-4 h-4 text-indigo-600" /></Button>
                            : undefined} />
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

      {/* Purchase dialog — shared with Feed Production, which raises it inline
          when a batch needs an ingredient bought. */}
      <PoultryPurchaseDialog
        open={purchaseOpen}
        onOpenChange={setPurchaseOpen}
        items={items}
        cashAccounts={cashAccounts}
        editing={editingPurchase}
        defaults={purchaseDefaults}
        defaultCashAccountId={defaultCashAccountId}
        onSaved={load}
      />

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

export default function PoultryRawMaterialsPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <PoultryRawMaterialsPageInner />
    </Suspense>
  )
}

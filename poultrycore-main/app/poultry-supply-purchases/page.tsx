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
import {
  EXPENSE_WHEN_PURCHASED, EXPENSE_WHEN_CONSUMED,
  effectiveCostRecognition, methodLabel, methodShortLabel, METHOD_HELP,
  CHANGE_WARNING, DEFERRED_ACTIVE_NOTE, costRecognitionGroup,
  recognitionTone, RECOGNITION_TONE_CLASS,
  DEFERRED_INVENTORY_TOOLTIP, EXPENSED_AT_PURCHASE_TOOLTIP, OPERATIONAL_VALUE_TOOLTIP,
  type CostRecognitionMethod, type CostRecognitionOverride,
  type FarmCostRecognitionDefaults,
} from "@/lib/poultry/cost-recognition"
import {
  getPoultryFinancialSettings, getPoultryInventoryValuation,
  type PoultryInventoryValuation,
} from "@/lib/api/poultry-inventory"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Badge } from "@/components/ui/badge"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import Link from "next/link"
import { Plus, Pencil, Loader2, Box, ShoppingCart, Trash2, Wallet, AlertTriangle, Factory, History, MoreHorizontal, RefreshCw, PackageCheck } from "lucide-react"
import { feedItemKind } from "@/lib/utils/feed-item-ledger"
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
import { fmtDateTime } from "@/lib/utils/company-datetime"

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

type ItemForm = { itemName: string; category: string; unitOfMeasure: string; purchaseUnitOfMeasure: string; minimumStockAlert: number; isActive: boolean; notes: string | null; usageMethod: RawMaterialUsageMethod; costRecognitionOverride: CostRecognitionOverride }
const EMPTY_ITEM: ItemForm = { itemName: "", category: "FeedIngredient", unitOfMeasure: "", purchaseUnitOfMeasure: "", minimumStockAlert: 0, isActive: true, notes: null, usageMethod: "FIFO", costRecognitionOverride: null }

// The three radio values on the item form. "Use farm default" is the ABSENCE of
// an override, not a third method -- storing it as one would give the same fact
// two spellings and let them drift.
const OVERRIDE_CHOICES: { value: CostRecognitionOverride; label: string }[] = [
  { value: null, label: "Use farm default" },
  { value: EXPENSE_WHEN_PURCHASED, label: methodLabel(EXPENSE_WHEN_PURCHASED) },
  { value: EXPENSE_WHEN_CONSUMED, label: methodLabel(EXPENSE_WHEN_CONSUMED) },
]

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

// ---- Small building blocks for a less cluttered page --------------------------

/** One summary card. With onClick it is a button that opens a filtered list. */
function Kpi({ icon, label, value, sub, tone, onClick, title }: {
  icon: React.ReactNode; label: string; value: React.ReactNode; sub?: React.ReactNode
  tone?: "warn" | "bad" | "good"; onClick?: () => void; title?: string
}) {
  const body = (
    <>
      <div className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-slate-500">{icon} {label}</div>
      <div className={cn("mt-1 text-xl font-bold tabular-nums sm:text-2xl",
        tone === "warn" ? "text-amber-700" : tone === "bad" ? "text-red-600" : tone === "good" ? "text-emerald-700" : "text-slate-900")}>{value}</div>
      {sub && <div className="mt-0.5 truncate text-xs text-slate-500">{sub}</div>}
    </>
  )
  const cls = cn("min-w-0 rounded-xl border bg-white p-3 text-left shadow-sm sm:p-4",
    tone === "warn" ? "border-amber-200" : tone === "bad" ? "border-red-200" : "border-slate-200")
  return onClick
    ? <button type="button" title={title} onClick={onClick} className={cn(cls, "transition-colors hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500")}>{body}</button>
    : <div title={title} className={cls}>{body}</div>
}

/** Quick filter chip with a count. */
function Chip({ active, onClick, count, tone, children }: {
  active: boolean; onClick: () => void; count?: number; tone?: "warn" | "bad"; children: React.ReactNode
}) {
  return (
    <button type="button" onClick={onClick} aria-pressed={active}
      className={cn("inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium transition-colors",
        active ? "border-blue-600 bg-blue-600 text-white" : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50")}>
      {children}
      {count != null && (
        <span className={cn("rounded-full px-1.5 text-[10px] font-bold tabular-nums",
          active ? "bg-white/20 text-white"
            : tone === "warn" && count > 0 ? "bg-amber-100 text-amber-800"
            : tone === "bad" && count > 0 ? "bg-red-100 text-red-700"
            : "bg-slate-100 text-slate-600")}>{count.toLocaleString()}</span>
      )}
    </button>
  )
}

/** Purchase unit -> production unit, or the one unit when they are the same. */
const unitsText = (i: PoultryRawMaterialItem) => {
  const prod = i.unitOfMeasure ?? ""
  const buy = i.purchaseUnitOfMeasure ?? ""
  if (!prod && !buy) return "—"
  if (!buy || buy === prod) return prod || buy
  return `${buy} → ${prod}`
}

/** Stock with its unit, and how it stands against the minimum alert. */
function StockLevel({ item }: { item: PoultryRawMaterialItem }) {
  const qty = Number(item.currentQuantity) || 0
  const min = Number(item.minimumStockAlert) || 0
  // Full bar at twice the minimum: anything above that is comfortably stocked.
  const pct = min > 0 ? Math.min(100, (qty / (min * 2)) * 100) : null
  const low = item.isActive && item.isLowStock
  return (
    <div className="min-w-[7rem]">
      <div className={cn("font-medium tabular-nums", low ? "text-amber-700" : "text-slate-900")}>
        {qty.toLocaleString()} <span className="text-xs font-normal text-slate-500">{item.unitOfMeasure ?? ""}</span>
      </div>
      {pct != null && (
        <>
          <div className="mt-1 h-1.5 w-24 overflow-hidden rounded-full bg-slate-100">
            <div className={cn("h-full rounded-full", low ? "bg-amber-500" : "bg-emerald-500")} style={{ width: `${Math.max(pct, qty > 0 ? 4 : 0)}%` }} />
          </div>
          <div className="mt-0.5 text-[11px] text-slate-500">min {min.toLocaleString()}</div>
        </>
      )}
    </div>
  )
}

function ItemStatus({ item }: { item: PoultryRawMaterialItem }) {
  if (!item.isActive) return <Badge variant="secondary">Inactive</Badge>
  if (item.isLowStock) return <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100">Low stock</Badge>
  return <Badge className="bg-emerald-50 text-emerald-700 hover:bg-emerald-50">In stock</Badge>
}

/** Paid / Part paid / Unpaid, with what is still owed -- Paid and Balance in one. */
function PaymentPill({ p, fmt }: { p: PoultryRawMaterialPurchase; fmt: (n: number) => string }) {
  if (p.feedProductionRole === "Produced") return <span className="text-xs text-slate-400">Produced</span>
  if (p.isReversed) return <span className="text-xs text-slate-400">Reversed</span>
  const balance = Number(p.balance) || 0
  const paid = Number(p.amountPaid) || 0
  if (balance <= 0) return <Badge className="bg-emerald-50 text-emerald-700 hover:bg-emerald-50">Paid</Badge>
  return (
    <div className="whitespace-nowrap">
      <Badge className={paid > 0 ? "bg-amber-100 text-amber-800 hover:bg-amber-100" : "bg-red-50 text-red-700 hover:bg-red-50"}>
        {paid > 0 ? "Part paid" : "Unpaid"}
      </Badge>
      <div className="mt-0.5 text-[11px] text-slate-500">{fmt(balance)} due</div>
    </div>
  )
}

function ProductionRoleBadge({ p }: { p: PoultryRawMaterialPurchase }) {
  return (
    <Badge variant="outline" className={cn("ml-2 text-[10px] font-normal", p.feedProductionRole === "Produced" ? "border-emerald-300 text-emerald-700" : "border-indigo-300 text-indigo-700")}>
      {p.feedProductionRole === "Produced" ? "Produced" : "For production"}
      {p.feedProductionBatchNumber ? ` · ${p.feedProductionBatchNumber}` : ""}
    </Badge>
  )
}

// 345. The receipt a lot came in on, and whether that receipt was reversed.
function ReceiptBadges({ p }: { p: PoultryRawMaterialPurchase }) {
  if (!p.receiptNumber && !p.isReversed) return null
  return (
    <>
      {p.receiptNumber && (
        <Badge variant="outline" className="ml-2 text-[10px] font-normal border-emerald-300 text-emerald-700">{p.receiptNumber}</Badge>
      )}
      {p.isReversed && (
        <Badge variant="outline" className="ml-2 text-[10px] font-normal border-slate-300 text-slate-500">Reversed</Badge>
      )}
    </>
  )
}

/** Icon button that says what it does on hover (and to screen readers). */
function IconAction({ label, onClick, href, children }: { label: string; onClick?: () => void; href?: string; children: React.ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        {href ? (
          <Button asChild variant="ghost" size="sm" aria-label={label}><Link href={href}>{children}</Link></Button>
        ) : (
          <Button variant="ghost" size="sm" aria-label={label} onClick={onClick}>{children}</Button>
        )}
      </TooltipTrigger>
      <TooltipContent side="top">{label}</TooltipContent>
    </Tooltip>
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
  // 267/268. Read-only: what the stock cost, and what of that still has to reach
  // Profit & Loss. Never blocks the page -- an older API simply leaves it null
  // and the value columns fall back to a dash.
  const [valuation, setValuation] = useState<PoultryInventoryValuation | null>(null)
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
  // ?purchaseId= from Supplier Balances -> Open purchase. Narrows the Purchases
  // tab to that one row, the way ?saleId= narrows /sales for Customer Balances.
  // Held in state rather than read from the URL on every render so clearing it
  // does not need a navigation.
  const [focusPurchaseId, setFocusPurchaseId] = useState<number | null>(null)
  // Items tab: category + unit dropdowns (records grow fast in production).
  const [categoryFilter, setCategoryFilter] = useState("all")
  const [unitFilter, setUnitFilter] = useState("all")
  // Quick filter chips (and the clickable Low stock / Outstanding cards).
  const [stockFilter, setStockFilter] = useState<"all" | "low" | "inactive">("all")
  const [payFilter, setPayFilter] = useState<"all" | "unpaid" | "paid">("all")
  const [recalcOpen, setRecalcOpen] = useState(false)

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
    router.replace("/poultry-supply-purchases", { scroll: false })
  }, [loading, items, defaultCashAccountId, router, searchParams])

  // ?purchaseId=N from Supplier Balances. Copied into state and left in the URL
  // — unlike ?purchase=1 there is no dialog to guard against reopening, and
  // keeping it means a refresh still shows the purchase the link pointed at.
  useEffect(() => {
    const pid = Number(searchParams.get("purchaseId"))
    setFocusPurchaseId(Number.isFinite(pid) && pid > 0 ? pid : null)
  }, [searchParams])

  async function load() {
    setLoading(true)
    try {
      const [is, ps, cas, val] = await Promise.all([
        listPoultryRawMaterialItems(), listPoultryRawMaterialPurchases(),
        listPoultryCashAccounts().catch(() => []),
        getPoultryInventoryValuation().catch(() => null),
      ])
      setItems(is); setPurchases(ps); setCashAccounts((cas as PoultryCashAccount[]).filter((a) => a.isActive))
      setValuation(val)
    } catch (e: any) {
      toast({ title: "Could not load raw materials", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  // Valuation by item, so a row can show its two values without a second call.
  const valuationByItem = useMemo(() => {
    const m = new Map<number, NonNullable<typeof valuation>["items"][number]>()
    for (const v of valuation?.items ?? []) m.set(v.poultryRawMaterialItemId, v)
    return m
  }, [valuation])

  // The URL is the source of truth for which tab is showing; an unknown or
  // missing ?tab= falls back to Items rather than rendering an empty panel.
  const tabParam = searchParams.get("tab")
  const tab: TabKey = (TABS as readonly string[]).includes(tabParam ?? "") ? (tabParam as TabKey) : "items"

  const selectTab = (v: string) => {
    // replace, not push: flipping between tabs shouldn't bury the previous page
    // under a stack of history entries. scroll:false keeps the list in place.
    router.replace(v === "items" ? "/poultry-supply-purchases" : `/poultry-supply-purchases?tab=${v}`, { scroll: false })
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
    if (stockFilter === "low") rows = rows.filter((i) => i.isActive && i.isLowStock)
    if (stockFilter === "inactive") rows = rows.filter((i) => !i.isActive)
    return rows
  }, [items, search, categoryFilter, unitFilter, stockFilter])

  // Distinct units actually in use (either role), for the Items unit dropdown.
  const unitOptionsInUse = useMemo(() => {
    const set = new Set<string>()
    items.forEach((i) => { if (i.unitOfMeasure) set.add(i.unitOfMeasure); if (i.purchaseUnitOfMeasure) set.add(i.purchaseUnitOfMeasure) })
    return Array.from(set).sort()
  }, [items])
  const filteredPurchases = useMemo(
    () => {
      // Arriving from Supplier Balances -> Open purchase. Narrowing to the one
      // purchase is the point of the link, so it wins over the other filters
      // (the banner above the table offers the way back out).
      if (focusPurchaseId !== null) {
        return purchases.filter((p) => p.poultryRawMaterialPurchaseId === focusPurchaseId)
      }
      let rows = byItem(filterByDateAndSearch(purchases, { search, dateFrom, dateTo, searchKeys: ["itemName", "supplierName"], dateKey: "purchaseDate" }))
      if (payFilter === "unpaid") rows = rows.filter((p) => !p.isReversed && (Number(p.balance) || 0) > 0)
      if (payFilter === "paid") rows = rows.filter((p) => (Number(p.balance) || 0) <= 0)
      return rows
    },
    [purchases, search, dateFrom, dateTo, itemFilter, focusPurchaseId, payFilter],
  )
  const unpaidCount = useMemo(() => purchases.filter((p) => !p.isReversed && (Number(p.balance) || 0) > 0).length, [purchases])
  const filteredUsage = useMemo(
    () => byItem(filterByDateAndSearch(usage, { search, dateFrom, dateTo, searchKeys: ["itemName"], dateKey: "usedDate" })),
    [usage, search, dateFrom, dateTo, itemFilter],
  )

  // Supplier name for the focus banner, so the link reads as "this supplier's
  // purchase" rather than a bare id.
  const focusedPurchaseSupplier = useMemo(
    () => (focusPurchaseId === null
      ? null
      : purchases.find((p) => p.poultryRawMaterialPurchaseId === focusPurchaseId)?.supplierName ?? null),
    [purchases, focusPurchaseId],
  )

  // Clearing the focus has to drop ?purchaseId= too, or the effect that reads it
  // puts the focus straight back on the next render.
  const clearPurchaseFocus = () => {
    setFocusPurchaseId(null)
    router.replace("/poultry-supply-purchases?tab=purchases", { scroll: false })
  }

  const sortedItems = useMemo(() => sortData(filteredItems, itemsSort.key, itemsSort.direction), [filteredItems, itemsSort])
  const pgItems = usePagination(sortedItems)
  const sortedPurchases = useMemo(() => sortData(filteredPurchases, purchasesSort.key, purchasesSort.direction), [filteredPurchases, purchasesSort])
  const pgPurchases = usePagination(sortedPurchases)
  const sortedUsage = useMemo(() => sortData(filteredUsage, usageSort.key, usageSort.direction), [filteredUsage, usageSort])
  const pgUsage = usePagination(sortedUsage)

  // Item dropdown shared by the Purchases + Usage filter strips.
  const itemFilterDropdown = (
    <Select value={itemFilter} onValueChange={setItemFilter}>
      <SelectTrigger className="w-full sm:w-[160px]"><SelectValue placeholder="All items" /></SelectTrigger>
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
  // A reversed receipt's lot (migration 345) stays in the history but was never spend.
  const spend = useMemo(() => purchases.filter((p) => p.feedProductionRole !== "Produced" && !p.isReversed), [purchases])
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
  // undefined = "new item, nothing to compare"; null = "was following the farm".
  // The two have to stay distinguishable or a new item would look like a change.
  const [originalOverride, setOriginalOverride] = useState<CostRecognitionOverride | undefined>(undefined)
  function openNewItem() { setEditItemId(null); setItemForm(EMPTY_ITEM); setOriginalUsageMethod(null); setOriginalOverride(undefined); setItemOpen(true) }
  function openEditItem(i: PoultryRawMaterialItem) {
    setEditItemId(i.poultryRawMaterialItemId)
    const usageMethod = i.usageMethod ?? "FIFO"
    const override = i.costRecognitionOverride ?? null
    setItemForm({ itemName: i.itemName, category: i.category, unitOfMeasure: i.unitOfMeasure ?? "", purchaseUnitOfMeasure: i.purchaseUnitOfMeasure ?? "", minimumStockAlert: i.minimumStockAlert, isActive: i.isActive, notes: i.notes ?? null, usageMethod, costRecognitionOverride: override })
    setOriginalUsageMethod(usageMethod)
    setOriginalOverride(override)
    setItemOpen(true)
  }
  const usageMethodChanged = editItemId != null && originalUsageMethod != null && itemForm.usageMethod !== originalUsageMethod

  // The farm's own settings, so the form can say what "use farm default"
  // actually resolves to for THIS item's category, and what an override would
  // be overriding. Never used to decide anything -- the server resolves and
  // stamps the real answer on each purchase.
  const [farmDefaults, setFarmDefaults] = useState<FarmCostRecognitionDefaults>({
    feed: EXPENSE_WHEN_PURCHASED, medication: EXPENSE_WHEN_PURCHASED,
  })
  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const s = await getPoultryFinancialSettings()
        if (!cancelled) setFarmDefaults({
          feed: s.feedCostRecognitionMethod,
          medication: s.medicationCostRecognitionMethod,
        })
      } catch {
        // A farm that cannot read its settings still gets a working item form;
        // the preview just shows today's behaviour, which is what an
        // unconfigured farm has anyway.
      }
    })()
    return () => { cancelled = true }
  }, [])

  const itemCategoryGroup = costRecognitionGroup(itemForm.category)
  const itemEffective = effectiveCostRecognition(
    itemForm.costRecognitionOverride, itemForm.category, farmDefaults)
  const overrideChanged =
    editItemId != null && originalOverride !== undefined
    && itemForm.costRecognitionOverride !== originalOverride
  async function saveItem() {
    if (!itemForm.itemName.trim()) { toast({ title: "Item name is required", variant: "destructive" }); return }
    setSavingItem(true)
    // Blank purchase unit → null so the backend defaults it to the production unit.
    const itemPayload = {
      ...itemForm,
      purchaseUnitOfMeasure: itemForm.purchaseUnitOfMeasure.trim() || null,
      // Null is a real value here ("follow the farm"), so the server cannot
      // tell it from "unchanged" without being told. This form always knows its
      // own mind, so it always says yes.
      setCostRecognitionOverride: true,
    }
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

  // Row actions, shared by the table and the phone cards. Every icon says what
  // it does on hover.
  const itemActions = (i: PoultryRawMaterialItem) => (
    <>
      {/* Feed items only: the tracker reads the two feed categories, so the
          link would open an empty page for packaging or a spare part. */}
      {feedItemKind(i.category) && (
        <IconAction label="Track movements" href={`/feed-inventory-tracker?itemId=${i.poultryRawMaterialItemId}`}>
          <History className="w-4 h-4 text-amber-700" />
        </IconAction>
      )}
      <IconAction label="Buy more" onClick={() => { setEditingPurchase(null); setPurchaseDefaults({ itemId: i.poultryRawMaterialItemId }); setPurchaseOpen(true) }}>
        <ShoppingCart className="w-4 h-4 text-blue-600" />
      </IconAction>
      <IconAction label="Edit item" onClick={() => openEditItem(i)}><Pencil className="w-4 h-4" /></IconAction>
      <IconAction label="Delete item" onClick={() => setDeleteItemTarget(i)}><Trash2 className="w-4 h-4 text-red-500" /></IconAction>
    </>
  )
  // A feed-production lot belongs to its batch: editing or deleting it here
  // would desync the batch's costing and its stock. Reverse the batch instead.
  const purchaseActions = (p: PoultryRawMaterialPurchase) => p.sourceFeedProductionBatchId ? (
    <IconAction label="Open feed production batch" onClick={() => router.push(`/poultry-feed-production/${p.sourceFeedProductionBatchId}`)}>
      <Factory className="w-4 h-4 text-indigo-600" />
    </IconAction>
  ) : (p.poultryPurchaseReceiptId || p.isReversed) ? (
    <>
      {!p.isReversed && p.balance > 0 && (
        <IconAction label="Pay balance" onClick={() => openPayBalance(p)}><Wallet className="w-4 h-4 text-emerald-600" /></IconAction>
      )}
      {p.poultryPurchaseReceiptId && (
        <IconAction label={`Open receipt ${p.receiptNumber ?? ""}`.trim()} onClick={() => router.push("/poultry-purchase-receipts")}>
          <PackageCheck className="w-4 h-4 text-emerald-600" />
        </IconAction>
      )}
    </>
  ) : (
    <>
      {p.balance > 0 && (
        <IconAction label="Pay balance" onClick={() => openPayBalance(p)}><Wallet className="w-4 h-4 text-emerald-600" /></IconAction>
      )}
      <IconAction label="Edit purchase" onClick={() => openEditPurchase(p)}><Pencil className="w-4 h-4" /></IconAction>
      <IconAction label="Delete purchase" onClick={() => setDeletePurchaseTarget(p)}><Trash2 className="w-4 h-4 text-red-500" /></IconAction>
    </>
  )

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
              <h1 className="text-xl font-bold text-slate-900 sm:text-2xl">Inventory &amp; Supply Purchases</h1>
              <p className="text-sm text-slate-500">Feed inputs, packaging, medication and other supplies — what you hold, what you bought, what was used.</p>
            </div>
            {/* One clear primary action. Produce Feed and Recalculate stock are
                occasional jobs, so they live under More instead of competing
                with Record Purchase for attention. */}
            <div className="flex w-full items-center gap-2 sm:w-auto sm:shrink-0">
              <Button variant="outline" className="flex-1 sm:flex-none" onClick={openNewItem}><Plus className="w-4 h-4 mr-1" /> New Item</Button>
              {/* 345. A whole supplier invoice (several items, part payment, due date) in one step. */}
              <Button variant="outline" className="hidden sm:inline-flex" onClick={() => router.push("/poultry-purchase-receipts?receive=1")}><PackageCheck className="w-4 h-4 mr-1" /> Receive Invoice</Button>
              <Button className="flex-1 sm:flex-none" onClick={openNewPurchase}><ShoppingCart className="w-4 h-4 mr-1" /> Record Purchase</Button>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="outline" size="icon" aria-label="More actions"><MoreHorizontal className="w-4 h-4" /></Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem className="sm:hidden" onSelect={() => router.push("/poultry-purchase-receipts?receive=1")}>
                    <PackageCheck className="w-4 h-4 mr-2" /> Receive invoice
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => router.push("/poultry-feed-production")}>
                    <Factory className="w-4 h-4 mr-2" /> Produce feed
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => setRecalcOpen(true)}>
                    <RefreshCw className="w-4 h-4 mr-2" /> Recalculate stock
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
              <RecalculateStockButton items={items} onDone={load} hideTrigger open={recalcOpen} onOpenChange={setRecalcOpen} />
            </div>
          </div>
          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
          ) : (
            <>
              {/* One summary row (it used to be seven boxes over two rows). The
                  two that call for action -- Low stock and Outstanding -- are
                  buttons that open the list already filtered to them. */}
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <Kpi icon={<Box className="w-4 h-4 text-blue-600" />} label="Stock value"
                  value={valuation ? gh(valuation.summary.operationalValue) : stats.activeCount.toLocaleString()}
                  title={valuation ? OPERATIONAL_VALUE_TOOLTIP : undefined}
                  sub={valuation ? (
                    <>
                      {valuation.summary.itemsWithStock} item{valuation.summary.itemsWithStock === 1 ? "" : "s"} in stock
                      {valuation.summary.deferredValue > 0 && (
                        <> · <button type="button" className="text-amber-700 underline decoration-dotted underline-offset-2 hover:text-amber-900"
                          title="See the purchases this is waiting on" onClick={() => router.push("/poultry-deferred-costs")}>
                          {gh(valuation.summary.deferredValue)} deferred
                        </button></>
                      )}
                    </>
                  ) : `active of ${stats.itemsCount.toLocaleString()} items`} />
                <Kpi icon={<AlertTriangle className={cn("w-4 h-4", stats.lowStock > 0 ? "text-amber-600" : "text-slate-400")} />} label="Low stock"
                  value={stats.lowStock.toLocaleString()} tone={stats.lowStock > 0 ? "warn" : undefined}
                  sub={stats.lowStock > 0 ? "need restocking · view" : "all stocked"}
                  onClick={stats.lowStock > 0 ? () => { setStockFilter("low"); selectTab("items") } : undefined} />
                <Kpi icon={<ShoppingCart className="w-4 h-4 text-emerald-600" />} label="Purchases"
                  value={gh(stats.purchaseTotal)} sub={`Paid ${gh(stats.paidTotal)}`}
                  title={stats.produced > 0 ? `Excludes ${stats.produced} feed lot(s) produced on the farm: their cost is the ingredients, already counted.` : undefined} />
                <Kpi icon={<Wallet className={cn("w-4 h-4", stats.outstanding > 0 ? "text-red-600" : "text-slate-400")} />} label="Outstanding"
                  value={gh(stats.outstanding)} tone={stats.outstanding > 0 ? "bad" : "good"}
                  sub={stats.outstanding > 0 ? "owed to suppliers · view" : "nothing owed"}
                  onClick={stats.outstanding > 0 ? () => { setPayFilter("unpaid"); selectTab("purchases") } : undefined} />
              </div>

              {/* The costing audit is silent when healthy, so anything here is
                  worth reading. Reported, never silently repaired. */}
              {valuation && valuation.auditFindings.length > 0 && (
                <div className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2">
                  <div className="flex items-start gap-2">
                    <AlertTriangle className="w-4 h-4 text-amber-600 mt-0.5 flex-shrink-0" />
                    <div className="text-xs text-amber-900">
                      <div className="font-medium">{valuation.auditFindings.length} stock costing issue(s) found</div>
                      <ul className="mt-1 space-y-0.5">
                        {valuation.auditFindings.slice(0, 5).map((f, idx) => (
                          <li key={idx}>
                            <span className="font-medium">{f.severity}</span>
                            {f.itemName ? ` · ${f.itemName}` : ""} — {f.detail}
                          </li>
                        ))}
                      </ul>
                      {valuation.auditFindings.length > 5 && <div className="mt-1">…and {valuation.auditFindings.length - 5} more.</div>}
                    </div>
                  </div>
                </div>
              )}

              {/* Tabs sit between the summary and the list they switch. */}
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
                  <History className="w-4 h-4" /> Usage
                  {usageLoaded && <span className={tabCountCls}>{usage.length.toLocaleString()}</span>}
                </TabsTrigger>
              </TabsList>

              {/* ITEMS */}
              <TabsContent value="items">
                <Card><CardContent className="space-y-3 p-3 sm:p-4">
                  <div className="flex flex-wrap gap-1.5">
                    <Chip active={stockFilter === "all"} onClick={() => setStockFilter("all")} count={items.length}>All</Chip>
                    <Chip active={stockFilter === "low"} onClick={() => setStockFilter("low")} count={stats.lowStock} tone="warn">Low stock</Chip>
                    <Chip active={stockFilter === "inactive"} onClick={() => setStockFilter("inactive")} count={stats.itemsCount - stats.activeCount}>Inactive</Chip>
                  </div>
                  <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search item or category" extras={<>
                    <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                      <SelectTrigger className="w-full sm:w-[160px]"><SelectValue placeholder="All categories" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All categories</SelectItem>
                        {CATEGORIES.map((c) => <SelectItem key={c} value={c}>{categoryLabel(c)}</SelectItem>)}
                      </SelectContent>
                    </Select>
                    <Select value={unitFilter} onValueChange={setUnitFilter}>
                      <SelectTrigger className="w-full sm:w-[140px]"><SelectValue placeholder="All units" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All units</SelectItem>
                        {unitOptionsInUse.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </>} />
                  {/* Six columns, not ten: category and cost treatment ride under
                      the name, the two units share one cell, and the minimum sits
                      under the stock it applies to. */}
                  <div className="hidden md:block overflow-x-auto"><Table>
                    <TableHeader><TableRow>
                      {(() => { const onSort = (k: string) => setItemsSort((s) => toggleSort(k, s.key, s.direction)); const cs = itemsSort.key, cd = itemsSort.direction; return (<>
                      <SortableHeader label="Item" sortKey="itemName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <TableHead>Units</TableHead>
                      <SortableHeader label="In stock" sortKey="currentQuantity" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Status" sortKey="isLowStock" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      </>) })()}
                      <TableHead className="text-right">Stock value</TableHead>
                      <TableHead className="w-[1%] text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {filteredItems.length === 0 ? (
                        <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-8">{items.length === 0 ? "No items yet — add one with New Item." : "No items match these filters."}</TableCell></TableRow>
                      ) : pgItems.pageItems.map((i) => (
                        <TableRow key={i.poultryRawMaterialItemId} className={cn(!i.isActive && "text-slate-500")}>
                          <TableCell>
                            <div className="font-medium text-slate-900">{i.itemName}</div>
                            <div className="text-xs text-slate-500">
                              {categoryLabel(i.category)} · {methodShortLabel(i.effectiveCostRecognitionMethod)}
                              {i.costRecognitionSource === "ItemOverride" && <span className="text-emerald-700"> (override)</span>}
                            </div>
                          </TableCell>
                          <TableCell className="text-sm text-slate-600 whitespace-nowrap">{unitsText(i)}</TableCell>
                          <TableCell><StockLevel item={i} /></TableCell>
                          <TableCell><ItemStatus item={i} /></TableCell>
                          {/* What the stock cost, and -- only where it applies --
                              what of that has still to be expensed. An item
                              expensed at purchase says so in words rather than
                              showing a deferred value of zero. */}
                          <TableCell className="text-right whitespace-nowrap">
                            {(() => {
                              const v = valuationByItem.get(i.poultryRawMaterialItemId)
                              if (!v) return <span className="text-slate-400">—</span>
                              return (
                                <>
                                  <div className="font-medium" title={OPERATIONAL_VALUE_TOOLTIP}>{gh(v.operationalValue)}</div>
                                  {v.deferredValue > 0 ? (
                                    <button type="button"
                                      className="text-[11px] text-amber-700 underline decoration-dotted underline-offset-2 hover:text-amber-900"
                                      title="See the purchases this is waiting on"
                                      onClick={(e) => { e.stopPropagation(); router.push(`/poultry-deferred-costs?itemId=${i.poultryRawMaterialItemId}`) }}>
                                      {gh(v.deferredValue)} deferred
                                    </button>
                                  ) : (
                                    <div className="text-[11px] text-slate-500" title={EXPENSED_AT_PURCHASE_TOOLTIP}>Already expensed</div>
                                  )}
                                </>
                              )
                            })()}
                          </TableCell>
                          <TableCell className="whitespace-nowrap text-right">{itemActions(i)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {filteredItems.length === 0 ? <div className="text-center text-slate-500 py-6">{items.length === 0 ? "No items yet — add one with New Item." : "No items match these filters."}</div>
                      : pgItems.pageItems.map((i) => (
                        <FieldCard key={i.poultryRawMaterialItemId} title={i.itemName}
                          badge={<ItemStatus item={i} />}
                          fields={[["Category", categoryLabel(i.category)], ["Units", unitsText(i)], ["In stock", `${i.currentQuantity.toLocaleString()} ${i.unitOfMeasure ?? ""}`.trim()], ["Min alert", i.minimumStockAlert.toLocaleString()], ["Cost", `${methodShortLabel(i.effectiveCostRecognitionMethod)}${i.costRecognitionSource === "ItemOverride" ? " (override)" : ""}`], ["Stock value", (() => { const v = valuationByItem.get(i.poultryRawMaterialItemId); return v ? gh(v.operationalValue) : "—" })()]]}
                          actions={itemActions(i)} />
                      ))}
                  </div>
                  {/* After BOTH lists, so it reads as "below the table" in either layout. */}
                  <DataPagination {...pgItems.paginationProps} />
                </CardContent></Card>
              </TabsContent>

              {/* PURCHASES */}
              <TabsContent value="purchases">
                <Card><CardContent className="space-y-3 p-3 sm:p-4">
                  {/* Arrived here from Supplier Balances -> Open purchase. Say so,
                      and give a one-click way back to the whole list. */}
                  {focusPurchaseId !== null && (
                    <div className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-sm text-sky-900">
                      <span>
                        Showing purchase <strong>#{focusPurchaseId}</strong> only
                        {focusedPurchaseSupplier ? <> — <strong>{focusedPurchaseSupplier}</strong></> : null}.
                      </span>
                      <Button variant="ghost" size="sm" onClick={clearPurchaseFocus}>Show all purchases</Button>
                    </div>
                  )}
                  {focusPurchaseId === null && (
                    <div className="flex flex-wrap gap-1.5">
                      <Chip active={payFilter === "all"} onClick={() => setPayFilter("all")} count={purchases.length}>All</Chip>
                      <Chip active={payFilter === "unpaid"} onClick={() => setPayFilter("unpaid")} count={unpaidCount} tone="bad">Unpaid</Chip>
                      <Chip active={payFilter === "paid"} onClick={() => setPayFilter("paid")} count={purchases.length - unpaidCount}>Paid</Chip>
                    </div>
                  )}
                  <ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search item or supplier" extras={itemFilterDropdown} />
                  {/* Eight columns, not eleven: supplier rides under the item,
                      the production quantity under the purchase quantity, and
                      Paid + Balance become one payment pill. */}
                  <div className="hidden md:block overflow-x-auto"><Table>
                    <TableHeader><TableRow>
                      {(() => { const onSort = (k: string) => setPurchasesSort((s) => toggleSort(k, s.key, s.direction)); const cs = purchasesSort.key, cd = purchasesSort.direction; return (<>
                      <SortableHeader label="Date" sortKey="purchaseDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Item / supplier" sortKey="itemName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      <SortableHeader label="Quantity" sortKey="quantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Unit price" sortKey="unitCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Total" sortKey="totalCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                      <SortableHeader label="Payment" sortKey="balance" currentSort={cs} currentDirection={cd} onSort={onSort} />
                      </>) })()}
                      <TableHead>Cost treatment</TableHead>
                      <TableHead className="w-[1%] text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {filteredPurchases.length === 0 ? (
                        <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-8">{focusPurchaseId !== null ? `Purchase #${focusPurchaseId} is not in this list.` : purchases.length === 0 ? "No purchases yet — record one with Record Purchase." : "No purchases match these filters."}</TableCell></TableRow>
                      ) : pgPurchases.pageItems.map((p) => (
                        <TableRow key={p.poultryRawMaterialPurchaseId}>
                          <TableCell className="whitespace-nowrap text-sm">{fmtDateTime(p.purchaseDate, p)}</TableCell>
                          <TableCell>
                            <div className="font-medium text-slate-900">
                              {p.itemName}
                              {p.feedProductionRole && <ProductionRoleBadge p={p} />}
                              <ReceiptBadges p={p} />
                            </div>
                            <div className="text-xs text-slate-500">{p.supplierName ?? "No supplier"}</div>
                          </TableCell>
                          <TableCell className="text-right whitespace-nowrap">
                            <div>{p.quantity.toLocaleString()} {p.unitOfMeasure ?? ""}</div>
                            {p.productionQuantity != null && p.productionUnit && p.productionUnit !== p.unitOfMeasure && (
                              <div className="text-xs text-slate-500">= {p.productionQuantity.toLocaleString()} {p.productionUnit}</div>
                            )}
                          </TableCell>
                          <TableCell className="text-right whitespace-nowrap">{gh(p.unitCost)}{p.unitOfMeasure ? <span className="text-xs text-slate-500"> / {p.unitOfMeasure}</span> : ""}</TableCell>
                          <TableCell className="text-right font-medium whitespace-nowrap">{gh(p.totalCost)}</TableCell>
                          <TableCell><PaymentPill p={p} fmt={gh} /></TableCell>
                          {/* The lot's OWN snapshot, not today's farm setting:
                              changing the setting never restates a purchase
                              already recorded. */}
                          <TableCell className="whitespace-nowrap">
                            {p.costRecognitionStatus ? (
                              <>
                                <Badge variant="outline" className={cn("text-[10px] font-normal", RECOGNITION_TONE_CLASS[recognitionTone(p.deferredRemainingCost)])}>
                                  {p.costRecognitionStatus}
                                </Badge>
                                {(p.deferredRemainingCost ?? 0) > 0 && (
                                  <button type="button"
                                    className="mt-0.5 block text-[11px] text-amber-700 underline decoration-dotted underline-offset-2 hover:text-amber-900"
                                    title="See this purchase's recognition history"
                                    onClick={(e) => { e.stopPropagation(); router.push(`/poultry-deferred-costs?itemId=${p.poultryRawMaterialItemId}`) }}>
                                    {gh(p.deferredRemainingCost ?? 0)} deferred
                                  </button>
                                )}
                              </>
                            ) : <span className="text-slate-400">—</span>}
                          </TableCell>
                          <TableCell className="whitespace-nowrap text-right">{purchaseActions(p)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {filteredPurchases.length === 0 ? <div className="text-center text-slate-500 py-6">{focusPurchaseId !== null ? `Purchase #${focusPurchaseId} is not in this list.` : purchases.length === 0 ? "No purchases yet — record one with Record Purchase." : "No purchases match these filters."}</div>
                      : pgPurchases.pageItems.map((p) => (
                        <FieldCard key={p.poultryRawMaterialPurchaseId} title={p.itemName}
                          badge={<PaymentPill p={p} fmt={gh} />}
                          fields={[["Date", fmtDateTime(p.purchaseDate, p)], ["Supplier", p.supplierName ?? "—"], ["Quantity", `${p.quantity.toLocaleString()} ${p.unitOfMeasure ?? ""}`.trim()], ["Unit price", gh(p.unitCost)], ["Total", gh(p.totalCost)], ...(p.feedProductionRole ? [["Feed", <ProductionRoleBadge key="r" p={p} />] as [string, React.ReactNode]] : []), ...((p.receiptNumber || p.isReversed) ? [["Receipt", <ReceiptBadges key="rc" p={p} />] as [string, React.ReactNode]] : [])]}
                          actions={purchaseActions(p)} />
                      ))}
                  </div>
                  {/* After BOTH lists, so it reads as "below the table" in either layout. */}
                  <DataPagination {...pgPurchases.paginationProps} />
                </CardContent></Card>
              </TabsContent>

              {/* USAGE */}
              <TabsContent value="usage">
                <Card><CardContent className="space-y-3 p-3 sm:p-4">
                  <p className="text-xs text-slate-500">Stock used by production and feed mixing, plus manual stock adjustments.</p>
                  <div><ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search item" extras={itemFilterDropdown} /></div>
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
                        <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-8">{usage.length === 0 ? "No usage recorded yet. It appears when production records or feed batches use stock." : "No usage matches these filters."}</TableCell></TableRow>
                      ) : pgUsage.pageItems.map((u) => (
                        <TableRow key={u.poultryRawMaterialUsageId}>
                          <TableCell>{fmtDateTime(u.usedDate, u)}</TableCell>
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
                          <TableCell className={cn("text-right whitespace-nowrap", u.quantityUsed < 0 && "text-emerald-700")}>
                            {u.quantityUsed < 0 ? `+${Math.abs(u.quantityUsed).toLocaleString()}` : u.quantityUsed.toLocaleString()} <span className="text-xs text-slate-500">{u.unitOfMeasure ?? ""}</span>
                            {u.quantityUsed < 0 && <div className="text-[11px] text-emerald-700">added back</div>}
                          </TableCell>
                          <TableCell className="text-right text-slate-600">{u.expectedQuantityUsed?.toLocaleString() ?? "—"}</TableCell>
                          {/* Over the expected use is the one worth noticing. */}
                          <TableCell className={cn("text-right tabular-nums", u.variance > 0 ? "font-medium text-red-600" : u.variance < 0 ? "text-emerald-700" : "text-slate-400")}>
                            {u.variance > 0 ? "+" : ""}{u.variance.toLocaleString()}
                          </TableCell>
                          <TableCell>{u.varianceReason ?? (u.feedProductionFeedName ? `Mixed into ${u.feedProductionFeedName}` : "—")}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                  {/* Mobile cards */}
                  <div className="md:hidden space-y-2">
                    {filteredUsage.length === 0 ? <div className="text-center text-slate-500 py-6">No usage recorded yet.</div>
                      : pgUsage.pageItems.map((u) => (
                        <FieldCard key={u.poultryRawMaterialUsageId} title={u.itemName}
                          badge={u.poultryFeedProductionBatchId
                            ? <Badge variant="outline" className="text-[10px] font-normal border-indigo-300 text-indigo-700"><Factory className="w-3 h-3 mr-1" />Feed production{u.feedProductionBatchNumber ? ` · ${u.feedProductionBatchNumber}` : ""}</Badge>
                            : <span className="text-xs text-slate-500">{fmtDateTime(u.usedDate, u)}</span>}
                          fields={[["Used", `${u.quantityUsed.toLocaleString()} ${u.unitOfMeasure ?? ""}`], ["Expected", u.expectedQuantityUsed?.toLocaleString() ?? "—"], ["Variance", u.variance.toLocaleString()], ["Reason", u.varianceReason ?? (u.feedProductionFeedName ? `Mixed into ${u.feedProductionFeedName}` : "—")]]}
                          actions={u.poultryFeedProductionBatchId
                            ? <Button variant="ghost" size="sm" onClick={() => router.push(`/poultry-feed-production/${u.poultryFeedProductionBatchId}`)} title="Open the feed production batch"><Factory className="w-4 h-4 text-indigo-600" /></Button>
                            : undefined} />
                      ))}
                  </div>
                  {/* Sits after BOTH lists, so it reads as "below the table" in
                      either layout — it used to render between them, which put it
                      above the cards on a phone. */}
                  <DataPagination {...pgUsage.paginationProps} />
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

          {/* Financial treatment. Deliberately its own section rather than
              another field in "Item details": when a cost hits Profit & Loss is
              a different kind of decision from what unit the thing is measured
              in, and burying it among the units invites people to skip it. */}
          <FormSection title="Financial treatment" color="emerald">
            <FormField label="Cost recognition" full>
              <div className="flex flex-col gap-2">
                {OVERRIDE_CHOICES.map((o) => {
                  const selected = itemForm.costRecognitionOverride === o.value
                  return (
                    <label
                      key={o.label}
                      className={`flex items-start gap-2.5 rounded-md border px-3 py-2 cursor-pointer transition-colors ${
                        selected ? "border-emerald-600 bg-emerald-50" : "border-slate-200 hover:border-slate-300"
                      }`}
                    >
                      <input
                        type="radio"
                        name="costRecognitionOverride"
                        checked={selected}
                        onChange={() => setItemForm({ ...itemForm, costRecognitionOverride: o.value })}
                        className="mt-0.5 accent-emerald-600"
                      />
                      <span className="min-w-0">
                        <span className="block text-sm font-semibold text-slate-800">{o.label}</span>
                        <span className="block text-xs text-slate-500">
                          {o.value === null
                            ? (itemCategoryGroup === "Unconfigured"
                                // Being honest about this matters: otherwise a
                                // user turns the farm setting on, sees this item
                                // unchanged, and concludes the feature is broken.
                                ? `${categoryLabel(itemForm.category)} does not follow either farm setting, so this stays on ${methodLabel(EXPENSE_WHEN_PURCHASED).toLowerCase()}.`
                                : `The farm setting for ${itemCategoryGroup === "Feed" ? "feed & raw materials" : "medication"} — currently ${methodLabel(itemEffective.farmDefault).toLowerCase()}.`)
                            : METHOD_HELP[o.value]}
                        </span>
                      </span>
                    </label>
                  )
                })}
              </div>

              <p className="text-xs text-slate-600 mt-2">
                Effective for this item:{" "}
                <strong>{methodLabel(itemEffective.method)}</strong>
                {itemEffective.source === "ItemOverride" ? " (overriding the farm default)" : " (from the farm default)"}
              </p>

              {overrideChanged && (
                <div className="mt-2 flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-2">
                  <AlertTriangle className="w-4 h-4 text-amber-600 mt-0.5 flex-shrink-0" />
                  <p className="text-xs text-amber-800">{CHANGE_WARNING}</p>
                </div>
              )}
              {itemEffective.method === EXPENSE_WHEN_CONSUMED && (
                <div className="mt-2 flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-2">
                  <AlertTriangle className="w-4 h-4 text-amber-600 mt-0.5 flex-shrink-0" />
                  <p className="text-xs text-amber-800">{DEFERRED_ACTIVE_NOTE}</p>
                </div>
              )}
            </FormField>
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

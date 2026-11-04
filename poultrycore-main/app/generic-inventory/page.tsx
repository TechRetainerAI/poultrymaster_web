"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
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
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { REJECT_REASONS, STOCK_ADJUSTMENT_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import {
  Plus, Pencil, Loader2, Box, ShoppingCart, Trash2, Wallet, AlertTriangle,
  History, MoreHorizontal, Check, Package, ArrowUpCircle, ArrowDownCircle,
  Boxes, ExternalLink,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import {
  getProducts, createGenericProduct, updateGenericProduct, deleteGenericProduct,
  getPurchases, approvePurchase, cancelPurchase, createPurchase,
  getStockAdjustments, createStockAdjustment, submitStockAdjustment,
  approveStockAdjustment, rejectStockAdjustment,
  getSuppliers, getCashAccounts,
  type GenericProduct, type GenericPurchase, type GenericStockAdjustment,
  type GenericSupplier, type GenericCashAccount, type GenericProductInput,
  type GenericPurchaseCreateInput, type GenericPurchaseItem,
  type GenericStockAdjustmentCreateInput,
} from "@/lib/api/generic"

// ---- Shared building blocks (mirrors poultry-supply-purchases) ----------------

/** Extract supplier name from notes when no registered supplier. */
function displaySupplier(p: GenericPurchase): string {
  if (p.supplierName) return p.supplierName
  if (p.notes?.startsWith("Supplier: ")) {
    const pipe = p.notes.indexOf(" | ")
    return pipe > 0 ? p.notes.slice(10, pipe) : p.notes.slice(10)
  }
  return "No supplier"
}

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

function ItemStatus({ product }: { product: GenericProduct }) {
  if (!product.trackInventory) return <Badge variant="secondary">Not tracked</Badge>
  if (!product.isActive) return <Badge variant="secondary">Inactive</Badge>
  const s = product.currentStock ?? 0
  const min = product.minimumStockAlert ?? 0
  if (s <= 0) return <Badge className="bg-rose-100 text-rose-700 hover:bg-rose-100">Out of stock</Badge>
  if (min > 0 && s <= min) return <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100">Low stock</Badge>
  return <Badge className="bg-emerald-50 text-emerald-700 hover:bg-emerald-50">In stock</Badge>
}

function StockLevel({ product }: { product: GenericProduct }) {
  if (!product.trackInventory) return <span className="text-slate-400">n/a</span>
  const qty = product.currentStock ?? 0
  const min = product.minimumStockAlert ?? 0
  const pct = min > 0 ? Math.min(100, (qty / (min * 2)) * 100) : null
  const low = product.isActive && product.trackInventory && min > 0 && qty <= min && qty > 0
  const out = product.isActive && product.trackInventory && qty <= 0
  return (
    <div className="min-w-[7rem]">
      <div className={cn("font-medium tabular-nums", out ? "text-rose-600" : low ? "text-amber-700" : "text-slate-900")}>
        {qty.toLocaleString()} <span className="text-xs font-normal text-slate-500">{product.unitOfMeasure ?? ""}</span>
      </div>
      {pct != null && (
        <>
          <div className="mt-1 h-1.5 w-24 overflow-hidden rounded-full bg-slate-100">
            <div className={cn("h-full rounded-full", out ? "bg-rose-500" : low ? "bg-amber-500" : "bg-emerald-500")} style={{ width: `${Math.max(pct, qty > 0 ? 4 : 0)}%` }} />
          </div>
          <div className="mt-0.5 text-[11px] text-slate-500">min {min.toLocaleString()}</div>
        </>
      )}
    </div>
  )
}

function PaymentStatusBadge({ status }: { status: string }) {
  if (status === "Paid") return <Badge className="bg-emerald-50 text-emerald-700 hover:bg-emerald-50">Paid</Badge>
  if (status === "Partial") return <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100">Part paid</Badge>
  return <Badge className="bg-red-50 text-red-700 hover:bg-red-50">Unpaid</Badge>
}

function PurchaseStatusBadge({ status }: { status: string }) {
  if (status === "Approved") return <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Approved</Badge>
  if (status === "Cancelled") return <Badge className="bg-rose-100 text-rose-800 hover:bg-rose-100">Cancelled</Badge>
  return <Badge className="bg-slate-100 text-slate-800 hover:bg-slate-100">Draft</Badge>
}

function AdjustmentBadge({ status }: { status: string }) {
  switch (status) {
    case "Approved": return <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Approved</Badge>
    case "Submitted": return <Badge className="bg-sky-100 text-sky-800 hover:bg-sky-100">Submitted</Badge>
    case "Rejected": return <Badge className="bg-rose-100 text-rose-800 hover:bg-rose-100">Rejected</Badge>
    default: return <Badge className="bg-slate-100 text-slate-800 hover:bg-slate-100">Draft</Badge>
  }
}

function ExpiryBadge({ product }: { product: GenericProduct }) {
  if (!product.trackExpiry || !product.expiryDate) return null
  const now = new Date()
  const exp = new Date(product.expiryDate)
  const daysUntil = Math.ceil((exp.getTime() - now.getTime()) / (1000 * 60 * 60 * 24))
  if (daysUntil < 0) return <Badge className="bg-rose-100 text-rose-700 ml-1">Expired {Math.abs(daysUntil)}d ago</Badge>
  if (daysUntil <= 30) return <Badge className="bg-amber-100 text-amber-700 ml-1">Expires in {daysUntil}d</Badge>
  return null
}

// URL-reflected tabs
const TABS = ["items", "purchases", "adjustments"] as const
type TabKey = (typeof TABS)[number]

const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card", "Credit"]

function GenericInventoryPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()

  // ---- Data ----
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [purchases, setPurchases] = useState<GenericPurchase[]>([])
  const [adjustments, setAdjustments] = useState<GenericStockAdjustment[]>([])
  const [adjustmentsLoaded, setAdjustmentsLoaded] = useState(false)
  const [suppliers, setSuppliers] = useState<GenericSupplier[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])
  const [loading, setLoading] = useState(true)

  // ---- Filters ----
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [categoryFilter, setCategoryFilter] = useState("all")
  const [unitFilter, setUnitFilter] = useState("all")
  const [stockFilter, setStockFilter] = useState<"all" | "low" | "out" | "inactive">("all")
  const [payFilter, setPayFilter] = useState<"all" | "unpaid" | "paid">("all")
  const [purchaseStatusFilter, setPurchaseStatusFilter] = useState<"all" | "Draft" | "Approved" | "Cancelled">("all")

  // ---- Sort ----
  const [itemsSort, setItemsSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })
  const [purchasesSort, setPurchasesSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })
  const [adjSort, setAdjSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })

  // ---- Dialogs ----
  const [deleteTarget, setDeleteTarget] = useState<GenericProduct | null>(null)

  // Adjustment dialog
  const [adjOpen, setAdjOpen] = useState(false)
  const [adjSaving, setAdjSaving] = useState(false)
  const [rejectTarget, setRejectTarget] = useState<number | null>(null)
  const [adjForm, setAdjForm] = useState({
    genericProductId: "",
    adjustmentType: "Increase" as "Increase" | "Decrease",
    quantity: "0",
    reason: "",
    adjustmentDate: new Date().toISOString().slice(0, 10),
    notes: "",
  })

  // ---- Tab ----
  const tabParam = searchParams.get("tab")
  const tab: TabKey = (TABS as readonly string[]).includes(tabParam ?? "") ? (tabParam as TabKey) : "items"
  const selectTab = (v: string) => {
    router.replace(v === "items" ? "/generic-inventory" : `/generic-inventory?tab=${v}`, { scroll: false })
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  // Lazy-load adjustments on first tab visit
  useEffect(() => {
    if (tab === "adjustments") void loadAdjustments()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab])

  async function load() {
    setLoading(true)
    try {
      const [ps, purs, sups, cas] = await Promise.all([
        getProducts(),
        getPurchases(null),
        getSuppliers().catch(() => []),
        getCashAccounts().catch(() => []),
      ])
      setProducts(Array.isArray(ps) ? ps : [])
      setPurchases(Array.isArray(purs) ? purs : [])
      setSuppliers(sups)
      setCashAccounts((cas as GenericCashAccount[]).filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Could not load data", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function loadAdjustments() {
    if (adjustmentsLoaded) return
    try {
      const data = await getStockAdjustments(null)
      setAdjustments(data)
      setAdjustmentsLoaded(true)
    } catch (e: any) {
      toast({ title: "Could not load adjustments", description: e?.message, variant: "destructive" })
    }
  }

  // ---- Derived data ----
  const categories = useMemo(() => {
    const set = new Set<string>()
    for (const p of products) if (p.categoryName) set.add(p.categoryName)
    return Array.from(set).sort()
  }, [products])

  const unitOptions = useMemo(() => {
    const set = new Set<string>()
    products.forEach((p) => { if (p.unitOfMeasure) set.add(p.unitOfMeasure) })
    return Array.from(set).sort()
  }, [products])

  const stockStatus = (p: GenericProduct) => {
    if (!p.trackInventory) return "untracked" as const
    const s = p.currentStock ?? 0
    const min = p.minimumStockAlert ?? 0
    if (s <= 0) return "out" as const
    if (min > 0 && s <= min) return "low" as const
    return "ok" as const
  }

  const stats = useMemo(() => {
    let total = products.length, low = 0, out = 0, inactive = 0, trackedValue = 0
    for (const p of products) {
      const st = stockStatus(p)
      if (st === "low") low++
      else if (st === "out") out++
      if (!p.isActive) inactive++
      if (p.trackInventory) trackedValue += (p.currentStock ?? 0) * (p.costPrice ?? 0)
    }
    const approvedPurchases = purchases.filter((p) => p.status === "Approved")
    const purchaseTotal = approvedPurchases.reduce((s, p) => s + (p.totalAmount ?? 0), 0)
    const paidTotal = approvedPurchases.reduce((s, p) => s + (p.amountPaid ?? 0), 0)
    const outstanding = approvedPurchases.reduce((s, p) => s + (p.balance ?? 0), 0)
    return { total, low, out, inactive, trackedValue, purchaseTotal, paidTotal, outstanding }
  }, [products, purchases])

  // ---- Filtered items ----
  const filteredItems = useMemo(() => {
    let rows = filterByDateAndSearch(products, { search, searchKeys: ["productName", "sku", "barcode", "categoryName"] })
    if (categoryFilter !== "all") rows = rows.filter((p) => p.categoryName === categoryFilter)
    if (unitFilter !== "all") rows = rows.filter((p) => p.unitOfMeasure === unitFilter)
    if (stockFilter === "low") rows = rows.filter((p) => stockStatus(p) === "low")
    else if (stockFilter === "out") rows = rows.filter((p) => stockStatus(p) === "out")
    else if (stockFilter === "inactive") rows = rows.filter((p) => !p.isActive)
    return rows
  }, [products, search, categoryFilter, unitFilter, stockFilter])

  // ---- Filtered purchases ----
  const filteredPurchases = useMemo(() => {
    let rows = filterByDateAndSearch(purchases, { search, dateFrom, dateTo, searchKeys: ["supplierName", "invoiceNumber", "notes"], dateKey: "purchaseDate" })
    if (purchaseStatusFilter !== "all") rows = rows.filter((p) => p.status === purchaseStatusFilter)
    if (payFilter === "unpaid") rows = rows.filter((p) => p.status !== "Cancelled" && (p.balance ?? 0) > 0)
    if (payFilter === "paid") rows = rows.filter((p) => (p.balance ?? 0) <= 0)
    return rows
  }, [purchases, search, dateFrom, dateTo, purchaseStatusFilter, payFilter])

  const unpaidCount = useMemo(() => purchases.filter((p) => p.status !== "Cancelled" && (p.balance ?? 0) > 0).length, [purchases])

  // ---- Filtered adjustments ----
  const filteredAdjustments = useMemo(() => {
    return filterByDateAndSearch(adjustments, { search, dateFrom, dateTo, searchKeys: ["productName", "reason"], dateKey: "adjustmentDate" })
  }, [adjustments, search, dateFrom, dateTo])

  // ---- Sorted + paginated ----
  const sortedItems = useMemo(() => sortData(filteredItems, itemsSort.key, itemsSort.direction), [filteredItems, itemsSort])
  const pgItems = usePagination(sortedItems)
  const sortedPurchases = useMemo(() => sortData(filteredPurchases, purchasesSort.key, purchasesSort.direction), [filteredPurchases, purchasesSort])
  const pgPurchases = usePagination(sortedPurchases)
  const sortedAdj = useMemo(() => sortData(filteredAdjustments, adjSort.key, adjSort.direction), [filteredAdjustments, adjSort])
  const pgAdj = usePagination(sortedAdj)

  // ---- Delete product ----
  async function confirmDeleteProduct() {
    if (!deleteTarget) return
    try {
      await deleteGenericProduct(deleteTarget.genericProductId)
      toast({ title: "Product removed" })
      setDeleteTarget(null)
      await load()
    } catch (e: any) {
      toast({ title: "Delete failed", description: e?.message, variant: "destructive" })
    }
  }

  // ---- Purchase actions ----
  async function onApprove(id: number) {
    try {
      await approvePurchase(id)
      toast({ title: `Purchase #${id} approved`, description: "Inventory and cash/supplier balances updated." })
      await load()
    } catch (e: any) {
      toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  async function onCancel(id: number) {
    try {
      await cancelPurchase(id)
      toast({ title: `Purchase #${id} cancelled` })
      await load()
    } catch (e: any) {
      toast({ title: "Cancel failed", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  // ---- Adjustment actions ----
  async function saveAdjustment() {
    const qty = Number(adjForm.quantity)
    if (!adjForm.genericProductId || qty <= 0 || !adjForm.reason.trim()) {
      toast({ title: "Fill all required fields", variant: "destructive" }); return
    }
    setAdjSaving(true)
    try {
      const created = await createStockAdjustment({
        genericProductId: Number(adjForm.genericProductId),
        adjustmentType: adjForm.adjustmentType,
        quantity: qty,
        reason: adjForm.reason,
        adjustmentDate: adjForm.adjustmentDate || null,
        notes: adjForm.notes || null,
      })
      // Auto-submit + approve for convenience (same as stock adjustments page)
      if (created?.genericStockAdjustmentId) {
        await submitStockAdjustment(created.genericStockAdjustmentId).catch(() => {})
        await approveStockAdjustment(created.genericStockAdjustmentId).catch(() => {})
      }
      toast({ title: "Stock adjusted" })
      setAdjOpen(false)
      setAdjForm({ genericProductId: "", adjustmentType: "Increase", quantity: "0", reason: "", adjustmentDate: new Date().toISOString().slice(0, 10), notes: "" })
      setAdjustmentsLoaded(false)
      await load()
      if (tab === "adjustments") await loadAdjustments()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setAdjSaving(false) }
  }

  async function onSubmitAdj(id: number) {
    try { await submitStockAdjustment(id); toast({ title: "Submitted for approval" }); setAdjustmentsLoaded(false); await loadAdjustments() }
    catch (e: any) { toast({ title: "Submit failed", description: e?.message, variant: "destructive" }) }
  }

  async function onApproveAdj(id: number) {
    try { await approveStockAdjustment(id); toast({ title: "Adjustment approved" }); setAdjustmentsLoaded(false); await loadAdjustments(); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  async function onRejectAdj(id: number, reason: string) {
    try { await rejectStockAdjustment(id, reason); toast({ title: "Adjustment rejected" }); setRejectTarget(null); setAdjustmentsLoaded(false); await loadAdjustments() }
    catch (e: any) { toast({ title: "Reject failed", description: e?.message, variant: "destructive" }) }
  }

  // ---- Item row actions ----
  const itemActions = (p: GenericProduct) => (
    <>
      <IconAction label="Adjust stock" onClick={() => { setAdjForm({ ...adjForm, genericProductId: String(p.genericProductId) }); setAdjOpen(true) }}>
        <ArrowUpCircle className="w-4 h-4 text-emerald-600" />
      </IconAction>
      <IconAction label="Edit product" href={`/generic-products?edit=${p.genericProductId}`}>
        <Pencil className="w-4 h-4" />
      </IconAction>
      <IconAction label="Delete product" onClick={() => setDeleteTarget(p)}>
        <Trash2 className="w-4 h-4 text-red-500" />
      </IconAction>
    </>
  )

  // ---- Tab styling (same as poultry) ----
  const tabTriggerCls =
    "h-auto flex-none shrink-0 gap-1.5 rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 sm:px-4 " +
    "transition-all hover:bg-slate-100 hover:text-slate-900 " +
    "data-[state=active]:bg-blue-600 data-[state=active]:text-white data-[state=active]:shadow-md " +
    "data-[state=active]:shadow-blue-600/25 data-[state=active]:hover:bg-blue-600 data-[state=active]:hover:text-white"
  const tabCountCls =
    "ml-0.5 rounded-full bg-slate-100 px-1.5 py-0.5 text-[11px] font-bold tabular-nums text-slate-600 " +
    "group-data-[state=active]:bg-white/20 group-data-[state=active]:text-white"

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <Tabs value={tab} onValueChange={selectTab} className="gap-4">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0">
                <h1 className="text-xl font-bold text-slate-900 sm:text-2xl">Inventory &amp; Supply Purchases</h1>
                <p className="text-sm text-slate-500">Products, purchases, and stock adjustments — what you hold, what you bought, what changed.</p>
              </div>
              <div className="flex w-full items-center gap-2 sm:w-auto sm:shrink-0">
                <Button variant="outline" className="flex-1 sm:flex-none" asChild>
                  <Link href="/generic-products"><Plus className="w-4 h-4 mr-1" /> New Product</Link>
                </Button>
                <Button className="flex-1 sm:flex-none" asChild>
                  <Link href="/generic-purchases/new"><ShoppingCart className="w-4 h-4 mr-1" /> Record Purchase</Link>
                </Button>
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="outline" size="icon" aria-label="More actions"><MoreHorizontal className="w-4 h-4" /></Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem onSelect={() => setAdjOpen(true)}>
                      <ArrowUpCircle className="w-4 h-4 mr-2" /> Adjust stock
                    </DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => router.push("/generic-products")}>
                      <Package className="w-4 h-4 mr-2" /> Manage products
                    </DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => router.push("/generic-suppliers")}>
                      <Wallet className="w-4 h-4 mr-2" /> Manage suppliers
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            </div>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading...</div>
            ) : (
              <>
                {/* KPI cards */}
                <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                  <Kpi icon={<Box className="w-4 h-4 text-blue-600" />} label="Stock value"
                    value={gh(stats.trackedValue)}
                    sub={`${stats.total} product${stats.total === 1 ? "" : "s"} total`} />
                  <Kpi icon={<AlertTriangle className={cn("w-4 h-4", stats.low > 0 ? "text-amber-600" : "text-slate-400")} />} label="Low stock"
                    value={stats.low.toLocaleString()} tone={stats.low > 0 ? "warn" : undefined}
                    sub={stats.low > 0 ? "need restocking · view" : "all stocked"}
                    onClick={stats.low > 0 ? () => { setStockFilter("low"); selectTab("items") } : undefined} />
                  <Kpi icon={<ShoppingCart className="w-4 h-4 text-emerald-600" />} label="Purchases"
                    value={gh(stats.purchaseTotal)} sub={`Paid ${gh(stats.paidTotal)}`} />
                  <Kpi icon={<Wallet className={cn("w-4 h-4", stats.outstanding > 0 ? "text-red-600" : "text-slate-400")} />} label="Outstanding"
                    value={gh(stats.outstanding)} tone={stats.outstanding > 0 ? "bad" : "good"}
                    sub={stats.outstanding > 0 ? "owed to suppliers · view" : "nothing owed"}
                    onClick={stats.outstanding > 0 ? () => { setPayFilter("unpaid"); selectTab("purchases") } : undefined} />
                </div>

                {/* Tabs */}
                <TabsList className="h-auto w-full max-w-full justify-start gap-1 overflow-x-auto rounded-xl border border-slate-200 bg-white p-1 shadow-sm sm:w-fit">
                  <TabsTrigger value="items" className={cn("group", tabTriggerCls)}>
                    <Box className="w-4 h-4" /> Items
                    <span className={tabCountCls}>{products.length.toLocaleString()}</span>
                  </TabsTrigger>
                  <TabsTrigger value="purchases" className={cn("group", tabTriggerCls)}>
                    <ShoppingCart className="w-4 h-4" /> Purchases
                    <span className={tabCountCls}>{purchases.length.toLocaleString()}</span>
                  </TabsTrigger>
                  <TabsTrigger value="adjustments" className={cn("group", tabTriggerCls)}>
                    <History className="w-4 h-4" /> Adjustments
                    {adjustmentsLoaded && <span className={tabCountCls}>{adjustments.length.toLocaleString()}</span>}
                  </TabsTrigger>
                </TabsList>

                {/* ===== ITEMS TAB ===== */}
                <TabsContent value="items">
                  <Card><CardContent className="space-y-3 p-3 sm:p-4">
                    <div className="flex flex-wrap gap-1.5">
                      <Chip active={stockFilter === "all"} onClick={() => setStockFilter("all")} count={products.length}>All</Chip>
                      <Chip active={stockFilter === "low"} onClick={() => setStockFilter("low")} count={stats.low} tone="warn">Low stock</Chip>
                      <Chip active={stockFilter === "out"} onClick={() => setStockFilter("out")} count={stats.out} tone="bad">Out of stock</Chip>
                      <Chip active={stockFilter === "inactive"} onClick={() => setStockFilter("inactive")} count={stats.inactive}>Inactive</Chip>
                    </div>
                    <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search product, SKU, or category" extras={<>
                      <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                        <SelectTrigger className="w-full sm:w-[160px]"><SelectValue placeholder="All categories" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="all">All categories</SelectItem>
                          {categories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                        </SelectContent>
                      </Select>
                      <Select value={unitFilter} onValueChange={setUnitFilter}>
                        <SelectTrigger className="w-full sm:w-[140px]"><SelectValue placeholder="All units" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="all">All units</SelectItem>
                          {unitOptions.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </>} />

                    {/* Desktop table */}
                    <div className="hidden md:block overflow-x-auto"><Table>
                      <TableHeader><TableRow>
                        {(() => { const onSort = (k: string) => setItemsSort((s) => toggleSort(k, s.key, s.direction)); const cs = itemsSort.key, cd = itemsSort.direction; return (<>
                        <SortableHeader label="Product" sortKey="productName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <TableHead>Units</TableHead>
                        <SortableHeader label="In stock" sortKey="currentStock" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <SortableHeader label="Status" sortKey="currentStock" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <TableHead className="text-right">Stock value</TableHead>
                        <TableHead className="w-[1%] text-right">Actions</TableHead>
                        </>) })()}
                      </TableRow></TableHeader>
                      <TableBody>
                        {filteredItems.length === 0 ? (
                          <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-8">
                            {products.length === 0
                              ? <>No products yet. <Link href="/generic-products" className="text-indigo-600 hover:underline">Add your first product</Link>.</>
                              : "No products match these filters."}
                          </TableCell></TableRow>
                        ) : pgItems.pageItems.map((p) => (
                          <TableRow key={p.genericProductId} className={cn(!p.isActive && "text-slate-500")}>
                            <TableCell>
                              <div className="font-medium text-slate-900">{p.productName}</div>
                              <div className="text-xs text-slate-500">
                                {p.categoryName ?? "Uncategorized"}
                                {p.sku && <> · <span className="text-slate-400">{p.sku}</span></>}
                              </div>
                            </TableCell>
                            <TableCell className="text-sm text-slate-600 whitespace-nowrap">{p.unitOfMeasure ?? "—"}</TableCell>
                            <TableCell><StockLevel product={p} /></TableCell>
                            <TableCell><ItemStatus product={p} /><ExpiryBadge product={p} /></TableCell>
                            <TableCell className="text-right whitespace-nowrap">
                              {p.trackInventory
                                ? <div className="font-medium">{gh((p.currentStock ?? 0) * (p.costPrice ?? 0))}</div>
                                : <span className="text-slate-400">—</span>}
                            </TableCell>
                            <TableCell className="whitespace-nowrap text-right">{itemActions(p)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table></div>

                    {/* Mobile cards */}
                    <div className="md:hidden space-y-2">
                      {filteredItems.length === 0
                        ? <div className="text-center text-slate-500 py-6">{products.length === 0 ? "No products yet." : "No products match these filters."}</div>
                        : pgItems.pageItems.map((p) => (
                          <FieldCard key={p.genericProductId} title={p.productName}
                            badge={<ItemStatus product={p} />}
                            fields={[
                              ["Category", p.categoryName ?? "Uncategorized"],
                              ["Units", p.unitOfMeasure ?? "—"],
                              ["In stock", p.trackInventory ? `${(p.currentStock ?? 0).toLocaleString()} ${p.unitOfMeasure ?? ""}`.trim() : "n/a"],
                              ["Min alert", p.trackInventory ? (p.minimumStockAlert ?? 0).toLocaleString() : "—"],
                              ["Cost", gh(p.costPrice)],
                              ["Stock value", p.trackInventory ? gh((p.currentStock ?? 0) * (p.costPrice ?? 0)) : "—"],
                            ]}
                            actions={itemActions(p)} />
                        ))}
                    </div>
                    <DataPagination {...pgItems.paginationProps} />
                  </CardContent></Card>
                </TabsContent>

                {/* ===== PURCHASES TAB ===== */}
                <TabsContent value="purchases">
                  <Card><CardContent className="space-y-3 p-3 sm:p-4">
                    <div className="flex flex-wrap gap-1.5">
                      <Chip active={payFilter === "all"} onClick={() => setPayFilter("all")} count={purchases.length}>All</Chip>
                      <Chip active={payFilter === "unpaid"} onClick={() => setPayFilter("unpaid")} count={unpaidCount} tone="bad">Unpaid</Chip>
                      <Chip active={payFilter === "paid"} onClick={() => setPayFilter("paid")} count={purchases.length - unpaidCount}>Paid</Chip>
                    </div>
                    <div className="flex flex-wrap gap-1 mb-1">
                      {(["all", "Draft", "Approved", "Cancelled"] as const).map((s) => (
                        <Button key={s} size="sm" variant={s === purchaseStatusFilter ? "default" : "outline"}
                          onClick={() => setPurchaseStatusFilter(s)}>{s === "all" ? "All status" : s}</Button>
                      ))}
                    </div>
                    <ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search supplier, invoice or notes" />

                    {/* Desktop table */}
                    <div className="hidden md:block overflow-x-auto"><Table>
                      <TableHeader><TableRow>
                        {(() => { const onSort = (k: string) => setPurchasesSort((s) => toggleSort(k, s.key, s.direction)); const cs = purchasesSort.key, cd = purchasesSort.direction; return (<>
                        <SortableHeader label="Date" sortKey="purchaseDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <SortableHeader label="Supplier" sortKey="supplierName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <TableHead>Invoice</TableHead>
                        <SortableHeader label="Total" sortKey="totalAmount" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                        <SortableHeader label="Paid" sortKey="amountPaid" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                        <SortableHeader label="Balance" sortKey="balance" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                        <TableHead>Payment</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="w-[1%] text-right">Actions</TableHead>
                        </>) })()}
                      </TableRow></TableHeader>
                      <TableBody>
                        {filteredPurchases.length === 0 ? (
                          <TableRow><TableCell colSpan={9} className="text-center text-slate-500 py-8">
                            {purchases.length === 0 ? "No purchases yet — record one with Record Purchase." : "No purchases match these filters."}
                          </TableCell></TableRow>
                        ) : pgPurchases.pageItems.map((p) => (
                          <TableRow key={p.genericPurchaseId}>
                            <TableCell className="whitespace-nowrap text-sm">{fmtDateTime(p.purchaseDate, p)}</TableCell>
                            <TableCell>
                              <div className="font-medium text-slate-900">{displaySupplier(p)}</div>
                            </TableCell>
                            <TableCell className="text-sm text-slate-600">{p.invoiceNumber ?? "—"}</TableCell>
                            <TableCell className="text-right font-medium whitespace-nowrap">{gh(p.totalAmount)}</TableCell>
                            <TableCell className="text-right whitespace-nowrap">{gh(p.amountPaid)}</TableCell>
                            <TableCell className={cn("text-right whitespace-nowrap", p.balance > 0 && "text-red-600 font-semibold")}>{gh(p.balance)}</TableCell>
                            <TableCell><PaymentStatusBadge status={p.paymentStatus} /></TableCell>
                            <TableCell><PurchaseStatusBadge status={p.status} /></TableCell>
                            <TableCell className="whitespace-nowrap text-right">
                              {p.status === "Draft" && (
                                <>
                                  <AlertDialog>
                                    <AlertDialogTrigger asChild>
                                      <Button size="sm" variant="ghost" className="text-emerald-700">
                                        <Check className="h-4 w-4" />
                                      </Button>
                                    </AlertDialogTrigger>
                                    <AlertDialogContent>
                                      <AlertDialogHeader>
                                        <AlertDialogTitle>Approve purchase #{p.genericPurchaseId}?</AlertDialogTitle>
                                        <AlertDialogDescription>This will update inventory, cash, and supplier balances.</AlertDialogDescription>
                                      </AlertDialogHeader>
                                      <AlertDialogFooter>
                                        <AlertDialogCancel>Cancel</AlertDialogCancel>
                                        <AlertDialogAction onClick={() => onApprove(p.genericPurchaseId)}>Approve</AlertDialogAction>
                                      </AlertDialogFooter>
                                    </AlertDialogContent>
                                  </AlertDialog>
                                  <IconAction label="Cancel purchase" onClick={() => onCancel(p.genericPurchaseId)}>
                                    <Trash2 className="w-4 h-4 text-red-500" />
                                  </IconAction>
                                </>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table></div>

                    {/* Mobile cards */}
                    <div className="md:hidden space-y-2">
                      {filteredPurchases.length === 0
                        ? <div className="text-center text-slate-500 py-6">{purchases.length === 0 ? "No purchases yet." : "No purchases match."}</div>
                        : pgPurchases.pageItems.map((p) => (
                          <FieldCard key={p.genericPurchaseId}
                            title={`#${p.genericPurchaseId} · ${displaySupplier(p)}`}
                            badge={<PurchaseStatusBadge status={p.status} />}
                            fields={[
                              ["Date", fmtDateTime(p.purchaseDate, p)],
                              ["Invoice", p.invoiceNumber ?? "—"],
                              ["Total", gh(p.totalAmount)],
                              ["Paid", gh(p.amountPaid)],
                              ["Balance", p.balance > 0 ? gh(p.balance) : "—"],
                              ["Payment", p.paymentStatus],
                            ]}
                            actions={p.status === "Draft" ? (
                              <>
                                <Button size="sm" variant="outline" className="text-emerald-700" onClick={() => onApprove(p.genericPurchaseId)}>
                                  <Check className="h-4 w-4 mr-1" /> Approve
                                </Button>
                                <Button size="sm" variant="outline" className="text-red-600" onClick={() => onCancel(p.genericPurchaseId)}>
                                  Cancel
                                </Button>
                              </>
                            ) : undefined}
                          />
                        ))}
                    </div>
                    <DataPagination {...pgPurchases.paginationProps} />
                  </CardContent></Card>
                </TabsContent>

                {/* ===== ADJUSTMENTS TAB ===== */}
                <TabsContent value="adjustments">
                  <Card><CardContent className="space-y-3 p-3 sm:p-4">
                    <p className="text-xs text-slate-500">Manual stock adjustments — increases, decreases, and corrections.</p>
                    <ListFilters search={search} setSearch={setSearch} dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} searchPlaceholder="Search product or reason" />

                    {/* Desktop table */}
                    <div className="hidden md:block overflow-x-auto"><Table>
                      <TableHeader><TableRow>
                        {(() => { const onSort = (k: string) => setAdjSort((s) => toggleSort(k, s.key, s.direction)); const cs = adjSort.key, cd = adjSort.direction; return (<>
                        <SortableHeader label="Date" sortKey="adjustmentDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <SortableHeader label="Product" sortKey="productName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <SortableHeader label="Type" sortKey="adjustmentType" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <SortableHeader label="Quantity" sortKey="quantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                        <SortableHeader label="Reason" sortKey="reason" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <TableHead>Status</TableHead>
                        <TableHead className="w-[1%] text-right">Actions</TableHead>
                        </>) })()}
                      </TableRow></TableHeader>
                      <TableBody>
                        {filteredAdjustments.length === 0 ? (
                          <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-8">
                            {adjustments.length === 0 ? "No adjustments recorded yet." : "No adjustments match these filters."}
                          </TableCell></TableRow>
                        ) : pgAdj.pageItems.map((a) => (
                          <TableRow key={a.genericStockAdjustmentId}>
                            <TableCell className="whitespace-nowrap text-sm">{fmtDateTime(a.adjustmentDate, a)}</TableCell>
                            <TableCell className="font-medium">{a.productName ?? "—"}</TableCell>
                            <TableCell>
                              <Badge variant="outline" className={a.adjustmentType === "Increase" ? "border-emerald-300 text-emerald-700" : "border-red-300 text-red-700"}>
                                {a.adjustmentType === "Increase" ? <ArrowUpCircle className="w-3 h-3 mr-1" /> : <ArrowDownCircle className="w-3 h-3 mr-1" />}
                                {a.adjustmentType}
                              </Badge>
                            </TableCell>
                            <TableCell className={cn("text-right tabular-nums font-medium", a.adjustmentType === "Increase" ? "text-emerald-700" : "text-red-600")}>
                              {a.adjustmentType === "Increase" ? "+" : "-"}{a.quantity.toLocaleString()}
                            </TableCell>
                            <TableCell className="text-sm">{a.reason}</TableCell>
                            <TableCell><AdjustmentBadge status={a.status} /></TableCell>
                            <TableCell className="whitespace-nowrap text-right">
                              {a.status === "Draft" && (
                                <IconAction label="Submit" onClick={() => onSubmitAdj(a.genericStockAdjustmentId)}>
                                  <Check className="w-4 h-4 text-sky-600" />
                                </IconAction>
                              )}
                              {a.status === "Submitted" && (
                                <>
                                  <IconAction label="Approve" onClick={() => onApproveAdj(a.genericStockAdjustmentId)}>
                                    <Check className="w-4 h-4 text-emerald-600" />
                                  </IconAction>
                                  <IconAction label="Reject" onClick={() => setRejectTarget(a.genericStockAdjustmentId)}>
                                    <Trash2 className="w-4 h-4 text-red-500" />
                                  </IconAction>
                                </>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table></div>

                    {/* Mobile cards */}
                    <div className="md:hidden space-y-2">
                      {filteredAdjustments.length === 0
                        ? <div className="text-center text-slate-500 py-6">No adjustments recorded yet.</div>
                        : pgAdj.pageItems.map((a) => (
                          <FieldCard key={a.genericStockAdjustmentId}
                            title={a.productName ?? "—"}
                            badge={<AdjustmentBadge status={a.status} />}
                            fields={[
                              ["Date", fmtDateTime(a.adjustmentDate, a)],
                              ["Type", a.adjustmentType],
                              ["Quantity", `${a.adjustmentType === "Increase" ? "+" : "-"}${a.quantity.toLocaleString()}`],
                              ["Reason", a.reason],
                            ]}
                            actions={
                              a.status === "Draft" ? (
                                <Button size="sm" variant="outline" className="text-sky-700" onClick={() => onSubmitAdj(a.genericStockAdjustmentId)}>
                                  <Check className="h-4 w-4 mr-1" /> Submit
                                </Button>
                              ) : a.status === "Submitted" ? (
                                <>
                                  <Button size="sm" variant="outline" className="text-emerald-700" onClick={() => onApproveAdj(a.genericStockAdjustmentId)}>
                                    <Check className="h-4 w-4 mr-1" /> Approve
                                  </Button>
                                  <Button size="sm" variant="outline" className="text-red-600" onClick={() => setRejectTarget(a.genericStockAdjustmentId)}>
                                    Reject
                                  </Button>
                                </>
                              ) : undefined
                            }
                          />
                        ))}
                    </div>
                    <DataPagination {...pgAdj.paginationProps} />
                  </CardContent></Card>
                </TabsContent>
              </>
            )}
          </Tabs>
        </main>
      </div>

      {/* Adjust stock dialog */}
      <Dialog open={adjOpen} onOpenChange={setAdjOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Adjust stock</DialogTitle></DialogHeader>
          <FormSection title="Adjustment details" color="blue">
            <FormField label="Product *">
              <Select value={adjForm.genericProductId} onValueChange={(v) => setAdjForm({ ...adjForm, genericProductId: v })}>
                <SelectTrigger><SelectValue placeholder="Select product" /></SelectTrigger>
                <SelectContent>
                  {products.filter((p) => p.trackInventory).map((p) => (
                    <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>
                      {p.productName} ({(p.currentStock ?? 0).toLocaleString()} {p.unitOfMeasure ?? ""})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Type *">
              <Select value={adjForm.adjustmentType} onValueChange={(v: "Increase" | "Decrease") => setAdjForm({ ...adjForm, adjustmentType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Increase">Increase</SelectItem>
                  <SelectItem value="Decrease">Decrease</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity *">
              <NumberInput min={0} step="1" value={adjForm.quantity} onChange={(e) => setAdjForm({ ...adjForm, quantity: e.target.value })} />
            </FormField>
            <FormField label="Reason *">
              <ReasonSelect options={STOCK_ADJUSTMENT_REASONS} value={adjForm.reason} onChange={(v) => setAdjForm({ ...adjForm, reason: v })} placeholder="Select or type a reason" />
            </FormField>
            <FormField label="Date">
              <Input type="date" value={adjForm.adjustmentDate} onChange={(e) => setAdjForm({ ...adjForm, adjustmentDate: e.target.value })} />
            </FormField>
            <FormField label="Notes">
              <Textarea rows={2} value={adjForm.notes} onChange={(e) => setAdjForm({ ...adjForm, notes: e.target.value })} placeholder="Optional notes" />
            </FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setAdjOpen(false)}>Cancel</Button>
            <Button onClick={saveAdjustment} disabled={adjSaving}>{adjSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => !o && setDeleteTarget(null)}
        title="Delete product"
        description={`Are you sure you want to delete "${deleteTarget?.productName}"? This cannot be undone.`}
        onConfirm={confirmDeleteProduct}
      />

      {/* Reject adjustment dialog */}
      <PromptDialog
        open={rejectTarget !== null}
        onOpenChange={(o) => !o && setRejectTarget(null)}
        title="Reject adjustment"
        description="Provide a reason for rejecting this stock adjustment."
        label="Reason"
        placeholder="Enter rejection reason"
        confirmLabel="Reject"
        onConfirm={(reason) => rejectTarget !== null && onRejectAdj(rejectTarget, reason)}
      />
    </div>
  )
}

export default function GenericInventoryPage() {
  return (
    <Suspense fallback={<div className="flex items-center gap-2 p-8 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>}>
      <GenericInventoryPageInner />
    </Suspense>
  )
}

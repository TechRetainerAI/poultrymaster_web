"use client"

import { useEffect, useMemo, useState, useCallback } from "react"
import { useRouter } from "next/navigation"
import { useGlobalSearchPrefill } from "@/hooks/use-global-search-prefill"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Loader2, Package, Plus, Pencil, Trash2, ArrowLeft, ShoppingCart,
  Factory, Users, Eye, ChevronDown, ChevronUp, X, ImageIcon, Upload,
  Wrench, Search,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getProducts, createGenericProduct, updateGenericProduct, deleteGenericProduct,
  getProductCategories, createProductCategory,
  getUomConversions, upsertUomConversion, deleteUomConversion,
  getUnitsOfMeasure, upsertUnitOfMeasure,
  getStockMovementsForProduct, getSales, getPurchases,
  getItemCostReconciliation,
  type GenericProduct, type GenericProductInput, type GenericProductCategory, type GenericUomConversion,
  type GenericUnitOfMeasure,
  type GenericStockMovement, type GenericSale, type GenericPurchase,
  type GenericItemCostReconciliation,
} from "@/lib/api/generic"
import { getProductionRecords, type GenericProductionRecord } from "@/lib/api/generic-production"
import { RAW_MATERIAL_UNITS, unitOptions } from "@/lib/units"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { filterByDateAndSearch } from "@/components/ui/list-filters"
import { GenericServicesTab } from "@/components/generic/services-tab"

// =============================================================================
// Helpers
// =============================================================================

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function purposeLabels(p: GenericProduct): string {
  const parts: string[] = []
  if (p.canSell) parts.push("Sale")
  if (p.canUseInProduction) parts.push("Production")
  if (p.canUseInternally) parts.push("Internal Use")
  if (parts.length === 0) {
    // Fallback for pre-migration-441 items
    if (p.itemType === "SupplyItem") return "Internal Use"
    return "Sale"
  }
  return parts.join(" · ")
}

function purposeBadges(p: GenericProduct) {
  const badges: { label: string; className: string }[] = []
  if (p.canSell) badges.push({ label: "Sale", className: "bg-blue-100 text-blue-800" })
  if (p.canUseInProduction) badges.push({ label: "Production", className: "bg-amber-100 text-amber-800" })
  if (p.canUseInternally) badges.push({ label: "Internal", className: "bg-purple-100 text-purple-800" })
  if (badges.length === 0) {
    if (p.itemType === "SupplyItem") badges.push({ label: "Internal", className: "bg-purple-100 text-purple-800" })
    else badges.push({ label: "Sale", className: "bg-blue-100 text-blue-800" })
  }
  return badges
}

function stockStatus(p: GenericProduct) {
  if (!p.trackInventory) return { label: "Not tracked", className: "bg-slate-100 text-slate-600" }
  if (!p.isActive) return { label: "Inactive", className: "bg-slate-100 text-slate-600" }
  if (p.currentStock <= 0) return { label: "Out of stock", className: "bg-red-100 text-red-800" }
  if (p.currentStock <= p.minimumStockAlert) return { label: "Low stock", className: "bg-rose-100 text-rose-800" }
  return { label: "In stock", className: "bg-emerald-100 text-emerald-800" }
}

// =============================================================================
// Tabs config
// =============================================================================

type TabKey = "all" | "sellable" | "production" | "internal"
const TABS: { key: TabKey; label: string; icon: React.ElementType; filter: (p: GenericProduct) => boolean }[] = [
  { key: "all", label: "All Items", icon: Package, filter: () => true },
  { key: "sellable", label: "Products for Sale", icon: ShoppingCart, filter: (p) => p.canSell === true || (p.canSell == null && p.itemType !== "SupplyItem") },
  { key: "production", label: "Raw Materials (used in Production)", icon: Factory, filter: (p) => p.canUseInProduction === true },
  { key: "internal", label: "Internal Use", icon: Users, filter: (p) => p.canUseInternally === true || (p.canUseInternally == null && p.itemType === "SupplyItem") },
]

// =============================================================================
// Empty form
// =============================================================================

const EMPTY_FORM = {
  productName: "",
  sku: "",
  barcode: "",
  description: "",
  unitOfMeasure: "",
  purchaseUnit: "",
  salesUnit: "",
  costPrice: "0",
  sellingPrice: "0",
  wholesalePrice: "",
  retailPrice: "",
  openingStock: "0",
  minimumStockAlert: "0",
  trackInventory: true,
  trackExpiry: false,
  expiryDate: "",
  isActive: true,
  notes: "",
  categoryId: "",
  canSell: true,
  canUseInProduction: false,
  canUseInternally: false,
  imageUrl: "" as string,
}

// General categories offered in the Category picker. One is saved to the
// company's own list the first time it is picked; companies add their own too.
const DEFAULT_PRODUCT_CATEGORIES = [
  "Groceries", "Beverages", "Household Items", "Personal Care", "Cleaning Supplies",
  "Health & Pharmacy", "Cosmetics & Beauty", "Baby Products", "Clothing & Apparel",
  "Electronics", "Stationery & Office Supplies", "Hardware & Tools", "Building Materials",
  "Kitchenware", "Furniture", "Auto Parts", "Agricultural Inputs", "Raw Materials",
  "Packaging", "Spare Parts", "Other",
]
const DEFAULT_OPTION_PREFIX = "__default__:"


// =============================================================================
// Page component
// =============================================================================

export default function GenericProductsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [topTab, setTopTab] = useState<"physical" | "services">("physical")
  /** Bumped by "New service": the Services tab opens its form (switching to it first if needed). */
  const [serviceRequest, setServiceRequest] = useState(0)
  const [rows, setRows] = useState<GenericProduct[]>([])
  const [search, setSearch] = useState("")
  useGlobalSearchPrefill(setSearch)
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState<TabKey>("all")

  // Dialog state
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<GenericProduct | null>(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [categories, setCategories] = useState<GenericProductCategory[]>([])
  const [newCategoryName, setNewCategoryName] = useState("")
  const [showAdvanced, setShowAdvanced] = useState(false)

  // Details panel
  const [detailItem, setDetailItem] = useState<GenericProduct | null>(null)
  const [detailMovements, setDetailMovements] = useState<GenericStockMovement[]>([])
  const [detailSales, setDetailSales] = useState<GenericSale[]>([])
  const [detailPurchases, setDetailPurchases] = useState<GenericPurchase[]>([])
  const [detailProduction, setDetailProduction] = useState<GenericProductionRecord[]>([])
  const [detailCostRecon, setDetailCostRecon] = useState<GenericItemCostReconciliation | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)

  // UOM conversions for the currently-editing product
  const [conversions, setConversions] = useState<GenericUomConversion[]>([])
  const [newConv, setNewConv] = useState({ fromUnit: "", toUnit: "", factor: "" })

  // Units of measure from DB
  const [units, setUnits] = useState<GenericUnitOfMeasure[]>([])
  const [unitSearch, setUnitSearch] = useState("")
  const [unitDropdownOpen, setUnitDropdownOpen] = useState(false)
  const [newSalesUnit, setNewSalesUnit] = useState("")

  // Dialog tab (two-tab form)
  const [formTab, setFormTab] = useState<"details" | "image">("details")

  // Category filter
  const [filterCategory, setFilterCategory] = useState<string>("")

  // Save a sales unit to the company's unit list (if not already there) so it is offered next time.
  const addSalesUnitToList = async (name: string) => {
    if (!name || units.some((u) => u.unitName.trim().toLowerCase() === name.toLowerCase())) return
    try {
      await upsertUnitOfMeasure({ unitName: name })
      setUnits(await getUnitsOfMeasure())
    } catch (e: any) { toast({ title: "Could not add unit", description: e?.message, variant: "destructive" }) }
  }

  const openNew = () => {
    setEditingId(null)
    setForm(EMPTY_FORM)
    setConversions([])
    setShowAdvanced(false)
    setFormTab("details")
    setOpen(true)
  }

  const openEdit = (p: GenericProduct) => {
    setEditingId(p.genericProductId)
    setForm({
      productName: p.productName,
      sku: p.sku ?? "",
      barcode: p.barcode ?? "",
      description: p.description ?? "",
      unitOfMeasure: p.unitOfMeasure ?? "",
      purchaseUnit: p.purchaseUnit ?? "",
      salesUnit: p.salesUnit ?? "",
      costPrice: String(p.costPrice),
      sellingPrice: String(p.sellingPrice),
      wholesalePrice: p.wholesalePrice != null ? String(p.wholesalePrice) : "",
      retailPrice: p.retailPrice != null ? String(p.retailPrice) : "",
      openingStock: String(p.openingStock),
      minimumStockAlert: String(p.minimumStockAlert),
      trackInventory: p.trackInventory,
      trackExpiry: p.trackExpiry ?? false,
      expiryDate: p.expiryDate ? p.expiryDate.slice(0, 10) : "",
      isActive: p.isActive,
      notes: p.notes ?? "",
      categoryId: p.genericProductCategoryId ? String(p.genericProductCategoryId) : "",
      canSell: p.canSell ?? (p.itemType !== "SupplyItem"),
      canUseInProduction: p.canUseInProduction ?? false,
      canUseInternally: p.canUseInternally ?? (p.itemType === "SupplyItem"),
      imageUrl: p.imageUrl ?? "",
    })
    setShowAdvanced(false)
    setFormTab("details")
    getUomConversions(p.genericProductId).then(setConversions).catch(() => setConversions([]))
    setOpen(true)
  }

  const addConversion = async () => {
    if (!editingId || !newConv.fromUnit.trim() || !newConv.toUnit.trim() || !Number(newConv.factor)) return
    try {
      await upsertUomConversion({
        genericProductId: editingId,
        fromUnit: newConv.fromUnit.trim(),
        toUnit: newConv.toUnit.trim(),
        conversionFactor: Number(newConv.factor),
      })
      setNewConv({ fromUnit: "", toUnit: "", factor: "" })
      const updated = await getUomConversions(editingId)
      setConversions(updated)
    } catch (e: any) {
      toast({ title: "Could not save conversion", description: e?.message, variant: "destructive" })
    }
  }

  const removeConversion = async (id: number) => {
    try {
      await deleteUomConversion(id)
      setConversions((prev) => prev.filter((c) => c.genericUomConversionId !== id))
    } catch (e: any) {
      toast({ title: "Could not delete conversion", description: e?.message, variant: "destructive" })
    }
  }

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [prods, cats, uoms] = await Promise.all([
        getProducts(),
        getProductCategories().catch(() => []),
        getUnitsOfMeasure().catch(() => []),
      ])
      setRows(prods)
      setCategories(cats)
      setUnits(uoms)
    } catch (e: any) {
      toast({ title: "Could not load products", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }, [toast])

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router, load])

  // Load detail data when an item is selected
  useEffect(() => {
    if (!detailItem) return
    setDetailLoading(true)
    setDetailMovements([]); setDetailSales([]); setDetailPurchases([]); setDetailProduction([]); setDetailCostRecon(null)
    const pid = detailItem.genericProductId
    Promise.allSettled([
      getStockMovementsForProduct(pid),
      getSales(),
      getPurchases(),
      getProductionRecords(),
      getItemCostReconciliation(pid),
    ]).then(([mvRes, slRes, puRes, prRes, crRes]) => {
      if (mvRes.status === "fulfilled") setDetailMovements(mvRes.value.slice(0, 50))
      if (slRes.status === "fulfilled") setDetailSales(slRes.value.filter((s) => s.items?.some((i) => i.genericProductId === pid)).slice(0, 20))
      if (puRes.status === "fulfilled") setDetailPurchases(puRes.value.slice(0, 20))
      if (prRes.status === "fulfilled") setDetailProduction(prRes.value.filter((r) => r.genericProductId === pid).slice(0, 20))
      if (crRes.status === "fulfilled") setDetailCostRecon(crRes.value)
      setDetailLoading(false)
    })
  }, [detailItem])

  // Filter by tab + search + category
  const visibleRows = useMemo(() => {
    const tabFilter = TABS.find((t) => t.key === activeTab)?.filter ?? (() => true)
    let filtered = rows.filter(tabFilter)
    if (filterCategory) {
      filtered = filtered.filter((p) =>
        p.genericProductCategoryId === Number(filterCategory)
      )
    }
    return filterByDateAndSearch(filtered, {
      search,
      searchKeys: ["productName", "sku", "categoryName", "description"],
    })
  }, [rows, search, activeTab, filterCategory])

  // Tab counts
  const tabCounts = useMemo(() => {
    const counts: Record<TabKey, number> = { all: 0, sellable: 0, production: 0, internal: 0 }
    for (const p of rows) {
      counts.all++
      if (p.canSell || (p.canSell == null && p.itemType !== "SupplyItem")) counts.sellable++
      if (p.canUseInProduction) counts.production++
      if (p.canUseInternally || (p.canUseInternally == null && p.itemType === "SupplyItem")) counts.internal++
    }
    return counts
  }, [rows])

  const onSave = async () => {
    if (!form.productName.trim()) {
      toast({ title: "Item name is required", variant: "destructive" }); return
    }
    if (!form.canSell && !form.canUseInProduction && !form.canUseInternally) {
      toast({ title: "Select at least one purpose", description: "An item must be used for at least one purpose.", variant: "destructive" }); return
    }
    const cost = Number(form.costPrice)
    const sell = form.canSell ? Number(form.sellingPrice) : 0
    if (Number.isNaN(cost) || cost < 0) return toast({ title: "Cost price must be 0 or more", variant: "destructive" })
    if (form.canSell && (Number.isNaN(sell) || sell < 0)) return toast({ title: "Selling price must be 0 or more", variant: "destructive" })

    const opt = (s: string) => s.trim() === "" ? null : Number(s)
    const optStr = (s: string) => s.trim() === "" ? null : s.trim()

    // Determine itemType from purposes for backward compatibility
    const itemType: "Product" | "SupplyItem" = form.canSell ? "Product" : "SupplyItem"

    setSaving(true)
    try {
      const input: GenericProductInput = {
        productName: form.productName.trim(),
        sku: optStr(form.sku),
        barcode: optStr(form.barcode),
        description: optStr(form.description),
        unitOfMeasure: optStr(form.unitOfMeasure),
        purchaseUnit: optStr(form.purchaseUnit),
        salesUnit: form.canSell ? optStr(form.salesUnit) : null,
        itemType,
        costPrice: cost,
        sellingPrice: sell,
        wholesalePrice: form.canSell ? opt(form.wholesalePrice) : null,
        retailPrice: form.canSell ? opt(form.retailPrice) : null,
        openingStock: Number(form.openingStock) || 0,
        minimumStockAlert: Number(form.minimumStockAlert) || 0,
        trackInventory: form.trackInventory,
        trackExpiry: form.trackExpiry,
        expiryDate: form.expiryDate || null,
        isActive: form.isActive,
        notes: optStr(form.notes),
        genericProductCategoryId: form.categoryId ? Number(form.categoryId) : null,
        canSell: form.canSell,
        canUseInProduction: form.canUseInProduction,
        canUseInternally: form.canUseInternally,
        imageUrl: form.imageUrl || null,
      }
      if (editingId != null) {
        await updateGenericProduct(editingId, input)
        toast({ title: `Item updated.` })
      } else {
        const created = await createGenericProduct(input)
        if (created) toast({ title: `"${created.productName}" created.` })
      }
      setOpen(false)
      setForm(EMPTY_FORM)
      setEditingId(null)
      await load()
    } catch (e: any) {
      toast({ title: editingId != null ? "Could not save changes" : "Could not create item", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  // =========================================================================
  // Render
  // =========================================================================
  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Page header */}
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <button onClick={() => router.back()} className="rounded-full p-1 hover:bg-slate-200 transition" title="Go back">
                <ArrowLeft className="w-5 h-5 text-slate-600" />
              </button>
              <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
                <Package className="h-6 w-6 text-blue-600" /> Products & Services
              </h1>
              <p className="text-sm text-slate-500">Manage the products, materials, supplies, and services your business sells or uses.</p>
            </div>
            {/* Both "new" buttons sit together and show on either tab: a service
                can be added without switching to Services first. */}
            <div className="flex w-full gap-2 sm:w-auto">
              <Button onClick={() => { setTopTab("physical"); openNew() }} className="flex-1 sm:flex-none h-11 sm:h-10">
                <Plus className="h-4 w-4 mr-1" /> New item
              </Button>
              <Button variant="outline" onClick={() => { setTopTab("services"); setServiceRequest((n) => n + 1) }}
                className="flex-1 sm:flex-none h-11 sm:h-10">
                <Wrench className="h-4 w-4 mr-1" /> New service
              </Button>
            </div>
          </div>

          {/* Top-level tabs: Physical Items | Services */}
          <div className="flex gap-2 mb-4">
            <button
              onClick={() => setTopTab("physical")}
              className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-semibold transition-colors ${
                topTab === "physical"
                  ? "bg-blue-600 text-white shadow-sm"
                  : "bg-white text-slate-600 hover:bg-slate-100 border border-slate-200"
              }`}
            >
              <Package className="h-4 w-4" /> Physical Items
            </button>
            <button
              onClick={() => setTopTab("services")}
              className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-semibold transition-colors ${
                topTab === "services"
                  ? "bg-blue-600 text-white shadow-sm"
                  : "bg-white text-slate-600 hover:bg-slate-100 border border-slate-200"
              }`}
            >
              <Wrench className="h-4 w-4" /> Services
            </button>
          </div>

          {topTab === "services" ? (
            <GenericServicesTab hideNewButton newRequest={serviceRequest} onNewHandled={() => setServiceRequest(0)} />
          ) : (
          <>
          {/* Physical Item sub-tabs, search and category: one strip, one background. */}
          {/* Two parts on one line from lg up: the filter buttons (which wrap among
              themselves if space runs out) and the search + category beside them. */}
          <div className="mb-4 flex flex-col gap-2 rounded-lg border border-slate-200 bg-white p-2 shadow-sm lg:flex-row lg:items-center">
            <div className="flex flex-wrap items-center gap-1.5 lg:shrink-0 lg:flex-nowrap">
            {TABS.map((tab) => {
              const Icon = tab.icon
              const isActive = activeTab === tab.key
              return (
                <button
                  key={tab.key}
                  onClick={() => setActiveTab(tab.key)}
                  className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                    isActive
                      ? "bg-blue-600 text-white shadow-sm"
                      : "bg-white text-slate-600 hover:bg-slate-100 border border-slate-200"
                  }`}
                >
                  <Icon className="h-4 w-4" />
                  <span className="hidden sm:inline">{tab.label}</span>
                  <span className={`ml-1 text-xs px-1.5 py-0.5 rounded-full ${
                    isActive ? "bg-blue-500 text-white" : "bg-slate-100 text-slate-600"
                  }`}>
                    {tabCounts[tab.key]}
                  </span>
                </button>
              )
            })}
            </div>
          {!loading && rows.length > 0 && (
            <div className="flex w-full items-center gap-1.5 lg:min-w-0 lg:flex-1">
              <div className="relative min-w-0 flex-1">
                <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <Input value={search} onChange={(e) => setSearch(e.target.value)}
                  placeholder="Search items" title="Search by name, SKU, category or description" className="h-9 bg-white pl-8" />
              </div>
              {categories.length > 0 && (
                <Select value={filterCategory || "__all__"} onValueChange={(v) => setFilterCategory(v === "__all__" ? "" : v)}>
                  <SelectTrigger className="h-9 w-36 shrink-0 bg-white">
                    <SelectValue placeholder="All categories" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__all__">All categories</SelectItem>
                    {categories.filter((c) => c.isActive).map((c) => (
                      <SelectItem key={c.genericProductCategoryId} value={String(c.genericProductCategoryId)}>
                        {c.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
          )}
          </div>

          {/* Content */}
          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading items…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-slate-500">
              <Package className="h-12 w-12 mx-auto text-slate-300 mb-3" />
              <p className="font-medium text-slate-700">No items yet</p>
              <p className="text-sm mt-1">Create your first product, raw material, or supply item.</p>
              <Button onClick={openNew} className="mt-4"><Plus className="h-4 w-4 mr-1" /> New item</Button>
            </CardContent></Card>
          ) : visibleRows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              No items match the current filters.
            </CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(p) => p.genericProductId}
                  primary={(p) => p.productName}
                  secondary={(p) => (
                    <div className="flex flex-wrap gap-1">
                      {purposeBadges(p).map((b, i) => (
                        <span key={i} className={`inline-flex text-[10px] font-medium px-1.5 py-0.5 rounded ${b.className}`}>{b.label}</span>
                      ))}
                    </div>
                  )}
                  trailing={(p) => {
                    const s = stockStatus(p)
                    return <Badge className={`${s.className} hover:${s.className}`}>{s.label}</Badge>
                  }}
                  details={(p) => [
                    { label: "Category", value: p.categoryName ?? "—" },
                    { label: "Unit", value: p.unitOfMeasure ?? "—" },
                    { label: "Cost", value: fmt(p.costPrice) },
                    { label: "Selling", value: p.canSell ? fmt(p.sellingPrice) : "—" },
                    { label: "Stock", value: p.trackInventory ? p.currentStock.toLocaleString(undefined, { maximumFractionDigits: 3 }) : "n/a" },
                  ]}
                  actions={(p) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => setDetailItem(p)}>
                        <Eye className="h-4 w-4 mr-1" /> View
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(p)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(p)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Item Name</TableHead>
                          <TableHead>Category</TableHead>
                          <TableHead>Purpose</TableHead>
                          <TableHead>Unit</TableHead>
                          <TableHead className="text-right">Current Stock</TableHead>
                          <TableHead>Stock Status</TableHead>
                          <TableHead className="text-right"></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((p) => {
                          const s = stockStatus(p)
                          return (
                            <TableRow key={p.genericProductId} className="cursor-pointer hover:bg-slate-50" onClick={() => setDetailItem(p)}>
                              <TableCell>
                                <div className="font-medium">{p.productName}</div>
                                {p.sku && <div className="text-xs text-slate-500 font-mono">{p.sku}</div>}
                              </TableCell>
                              <TableCell className="text-sm">{p.categoryName ?? "—"}</TableCell>
                              <TableCell>
                                <div className="flex flex-wrap gap-1">
                                  {purposeBadges(p).map((b, i) => (
                                    <span key={i} className={`inline-flex text-[10px] font-medium px-1.5 py-0.5 rounded ${b.className}`}>{b.label}</span>
                                  ))}
                                </div>
                              </TableCell>
                              <TableCell className="text-sm">{p.unitOfMeasure ?? "—"}</TableCell>
                              <TableCell className="text-right">
                                {p.trackInventory
                                  ? p.currentStock.toLocaleString(undefined, { maximumFractionDigits: 3 })
                                  : <span className="text-slate-400">n/a</span>}
                              </TableCell>
                              <TableCell>
                                <Badge className={`${s.className} hover:${s.className}`}>{s.label}</Badge>
                              </TableCell>
                              <TableCell className="text-right" onClick={(e) => e.stopPropagation()}>
                                <Button size="sm" variant="ghost" onClick={() => openEdit(p)} title="Edit"><Pencil className="h-4 w-4" /></Button>
                                <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(p)} title="Delete"><Trash2 className="h-4 w-4 text-red-500" /></Button>
                              </TableCell>
                            </TableRow>
                          )
                        })}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              </CardContent>
            </Card>
          )}
          </>
          )}
        </main>
      </div>

      {/* ================================================================= */}
      {/* Add / Edit Dialog                                                  */}
      {/* ================================================================= */}
      <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) setEditingId(null) }}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editingId != null
                ? <><Pencil className="w-5 h-5 text-blue-600" /> Edit item</>
                : <><Package className="w-5 h-5 text-blue-600" /> New item</>}
            </DialogTitle>
            <DialogDescription>
              {editingId != null
                ? "Update item details and purposes."
                : "Create a product, raw material, or supply item. Select what it will be used for."}
            </DialogDescription>
          </DialogHeader>

          {/* Two-tab layout */}
          <div className="flex gap-1 border-b mb-3">
            <button type="button" onClick={() => setFormTab("details")}
              className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${formTab === "details" ? "border-blue-600 text-blue-600" : "border-transparent text-slate-500 hover:text-slate-700"}`}>
              Details
            </button>
            <button type="button" onClick={() => setFormTab("image")}
              className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors flex items-center gap-1.5 ${formTab === "image" ? "border-blue-600 text-blue-600" : "border-transparent text-slate-500 hover:text-slate-700"}`}>
              <ImageIcon className="h-3.5 w-3.5" /> Image {form.imageUrl && <span className="h-2 w-2 rounded-full bg-emerald-500" />}
            </button>
          </div>

          {formTab === "image" ? (
            <div className="space-y-4">
              <div className="flex flex-col items-center gap-4 py-6">
                {form.imageUrl ? (
                  <div className="relative group">
                    <img src={form.imageUrl} alt="Product" className="h-48 w-48 rounded-lg object-cover border shadow-sm" />
                    <button type="button" onClick={() => setForm((f) => ({ ...f, imageUrl: "" }))}
                      className="absolute -top-2 -right-2 rounded-full bg-red-500 text-white p-1 opacity-0 group-hover:opacity-100 transition-opacity"
                      title="Remove image">
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ) : (
                  <div className="h-48 w-48 rounded-lg border-2 border-dashed border-slate-300 flex flex-col items-center justify-center text-slate-400">
                    <ImageIcon className="h-10 w-10 mb-2" />
                    <span className="text-xs">No image</span>
                  </div>
                )}
                <label className="cursor-pointer">
                  <input type="file" accept="image/*" className="hidden" onChange={(e) => {
                    const file = e.target.files?.[0]
                    if (!file) return
                    if (file.size > 2 * 1024 * 1024) {
                      toast({ title: "Image too large", description: "Max 2 MB", variant: "destructive" }); return
                    }
                    const reader = new FileReader()
                    reader.onload = () => setForm((f) => ({ ...f, imageUrl: reader.result as string }))
                    reader.readAsDataURL(file)
                  }} />
                  <span className="inline-flex items-center gap-1.5 rounded-lg border px-4 py-2 text-sm font-medium hover:bg-slate-50 transition-colors">
                    <Upload className="h-4 w-4" /> {form.imageUrl ? "Change Image" : "Upload Image"}
                  </span>
                </label>
                <p className="text-xs text-slate-500">JPG, PNG or WebP. Max 2 MB.</p>
              </div>
              {/* Preview card */}
              {form.productName && (
                <div className="rounded-lg border p-4 bg-white">
                  <h4 className="text-sm font-medium text-slate-500 mb-2">Preview</h4>
                  <div className="flex items-center gap-3">
                    {form.imageUrl
                      ? <img src={form.imageUrl} alt="" className="h-12 w-12 rounded-lg object-cover border" />
                      : <div className="h-12 w-12 rounded-lg bg-slate-100 flex items-center justify-center"><Package className="h-6 w-6 text-slate-400" /></div>}
                    <div>
                      <div className="font-medium text-slate-900">{form.productName || "Product name"}</div>
                      <div className="text-xs text-slate-500">{form.unitOfMeasure || "unit"} · {form.canSell ? "Sale" : ""}{form.canUseInProduction ? " · Production" : ""}{form.canUseInternally ? " · Internal" : ""}</div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          ) : (
          <div className="space-y-4">
            {/* Item Purpose — compact inline chips */}
            <div>
              <label className="text-xs font-medium text-slate-600 mb-1.5 block">What will this item be used for?</label>
              <div className="flex flex-wrap gap-2">
                <label className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium cursor-pointer transition-colors ${form.canSell ? "border-blue-300 bg-blue-50 text-blue-700" : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50"}`}>
                  <input type="checkbox" checked={form.canSell} onChange={(e) => setForm((f) => ({ ...f, canSell: e.target.checked }))} className="h-3 w-3 rounded border-slate-300 text-blue-600" />
                  <ShoppingCart className="h-3 w-3" /> Sell to Customers
                </label>
                <label className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium cursor-pointer transition-colors ${form.canUseInProduction ? "border-amber-300 bg-amber-50 text-amber-700" : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50"}`}>
                  <input type="checkbox" checked={form.canUseInProduction} onChange={(e) => setForm((f) => ({ ...f, canUseInProduction: e.target.checked }))} className="h-3 w-3 rounded border-slate-300 text-amber-600" />
                  <Factory className="h-3 w-3" /> Raw Materials (used in Production)
                </label>
                <label className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium cursor-pointer transition-colors ${form.canUseInternally ? "border-purple-300 bg-purple-50 text-purple-700" : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50"}`}>
                  <input type="checkbox" checked={form.canUseInternally} onChange={(e) => setForm((f) => ({ ...f, canUseInternally: e.target.checked }))} className="h-3 w-3 rounded border-slate-300 text-purple-600" />
                  <Users className="h-3 w-3" /> Use Internally
                </label>
              </div>
              {!form.canSell && !form.canUseInProduction && !form.canUseInternally && (
                <p className="text-xs text-red-500 mt-1">Select at least one purpose.</p>
              )}
            </div>

            {/* Basic Details */}
            <FormSection title="Basic Details" color="indigo">
              <FormField label="Item name *" full>
                <Input value={form.productName} onChange={(e) => setForm((f) => ({ ...f, productName: e.target.value }))} maxLength={200} placeholder="e.g. Maize, Packaging Bags, Rice" />
              </FormField>
              <FormField label="SKU / Item code">
                <Input value={form.sku} onChange={(e) => setForm((f) => ({ ...f, sku: e.target.value }))} maxLength={60} />
              </FormField>
              <FormField label="Barcode">
                <Input value={form.barcode} onChange={(e) => setForm((f) => ({ ...f, barcode: e.target.value }))} maxLength={60} />
              </FormField>
              <FormField label="Description" full>
                <Textarea rows={2} value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} placeholder="Describe this item (optional)" />
              </FormField>
              <FormField label="Category">
                <Select value={form.categoryId || "__none__"} onValueChange={async (v) => {
                  if (!v.startsWith(DEFAULT_OPTION_PREFIX)) {
                    setForm((f) => ({ ...f, categoryId: v === "__none__" ? "" : v }))
                    return
                  }
                  // A general category not yet in this company's list: save it, then select it.
                  const name = v.slice(DEFAULT_OPTION_PREFIX.length)
                  try {
                    const created = await createProductCategory({ name })
                    if (created) {
                      setCategories((prev) => [...prev, created])
                      setForm((f) => ({ ...f, categoryId: String(created.genericProductCategoryId) }))
                    }
                  } catch (e: any) { toast({ title: "Could not add category", description: e?.message, variant: "destructive" }) }
                }}>
                  <SelectTrigger><SelectValue placeholder="-- none --" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">-- No category --</SelectItem>
                    {categories.filter((c) => c.isActive).map((c) => (
                      <SelectItem key={c.genericProductCategoryId} value={String(c.genericProductCategoryId)}>{c.name}</SelectItem>
                    ))}
                    {DEFAULT_PRODUCT_CATEGORIES
                      .filter((name) => !categories.some((c) => c.name.trim().toLowerCase() === name.toLowerCase()))
                      .map((name) => (
                        <SelectItem key={`default-${name}`} value={`${DEFAULT_OPTION_PREFIX}${name}`}>{name}</SelectItem>
                      ))}
                  </SelectContent>
                </Select>
                <div className="flex gap-1.5 mt-1.5">
                  <Input className="h-8 text-xs" placeholder="New category name" value={newCategoryName} onChange={(e) => setNewCategoryName(e.target.value)} />
                  <Button type="button" size="sm" variant="outline" className="h-8 shrink-0 text-xs" disabled={!newCategoryName.trim()} onClick={async () => {
                    try {
                      const created = await createProductCategory({ name: newCategoryName.trim() })
                      if (created) {
                        setCategories((prev) => [...prev, created])
                        setForm((f) => ({ ...f, categoryId: String(created.genericProductCategoryId) }))
                        setNewCategoryName("")
                        toast({ title: `Category "${created.name}" created` })
                      }
                    } catch (e: any) { toast({ title: "Could not create category", description: e?.message, variant: "destructive" }) }
                  }}>
                    <Plus className="h-3 w-3 mr-1" /> Add
                  </Button>
                </div>
              </FormField>
              <FormField label="Base stock unit" hint="Pick from the list or type a custom unit below">
                <Select value={form.unitOfMeasure || "__none__"} onValueChange={(v) => { setForm((f) => ({ ...f, unitOfMeasure: v === "__none__" ? "" : v })); setUnitSearch("") }}>
                  <SelectTrigger><SelectValue placeholder="e.g. kg, piece, litre" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">— None —</SelectItem>
                    {/* The same unit list as the poultry side (lib/units.ts). */}
                    {unitOptions(form.unitOfMeasure).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                  </SelectContent>
                </Select>
                <div className="flex gap-2 mt-1.5">
                  <Input
                    value={unitSearch}
                    onChange={(e) => setUnitSearch(e.target.value)}
                    placeholder="Or type a custom unit…"
                    maxLength={30}
                    className="text-sm h-8"
                  />
                  {unitSearch.trim() && (
                    <Button type="button" size="sm" className="h-8 shrink-0"
                      onClick={() => {
                        setForm((f) => ({ ...f, unitOfMeasure: unitSearch.trim() }))
                        setUnitSearch("")
                      }}>
                      Use &quot;{unitSearch.trim()}&quot;
                    </Button>
                  )}
                </div>
                {form.unitOfMeasure && !RAW_MATERIAL_UNITS.some((u) => u.toLowerCase() === form.unitOfMeasure.toLowerCase()) && (
                  <p className="text-[11px] text-blue-600 mt-1">Custom unit &quot;{form.unitOfMeasure}&quot; will be added automatically when you save.</p>
                )}
              </FormField>
            </FormSection>

            {/* Dynamic: Sale settings */}
            {form.canSell && (
              <FormSection title="Sale Settings" color="blue">
                <FormField label="Selling price *">
                  <NumberInput step="0.01" min="0" value={form.sellingPrice} onChange={(e) => setForm((f) => ({ ...f, sellingPrice: e.target.value }))} />
                </FormField>
                <FormField label="Sales unit" hint="Unit used when selling (optional, defaults to base unit)">
                  <Select value={form.salesUnit || "__none__"} onValueChange={(v) => {
                    setForm((f) => ({ ...f, salesUnit: v === "__none__" ? "" : v }))
                  }}>
                    <SelectTrigger><SelectValue placeholder="e.g. piece" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="__none__">— Same as base unit —</SelectItem>
                      {/* The same unit list as the poultry side (lib/units.ts). */}
                      {unitOptions(form.salesUnit).map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <div className="flex gap-1.5 mt-1.5">
                    <Input className="h-8 text-xs" placeholder="New sales unit" maxLength={50} value={newSalesUnit} onChange={(e) => setNewSalesUnit(e.target.value)} />
                    <Button type="button" size="sm" variant="outline" className="h-8 shrink-0 text-xs" disabled={!newSalesUnit.trim()} onClick={async () => {
                      const name = newSalesUnit.trim()
                      setForm((f) => ({ ...f, salesUnit: name }))
                      setNewSalesUnit("")
                      await addSalesUnitToList(name)
                    }}>
                      <Plus className="h-3 w-3 mr-1" /> Add
                    </Button>
                  </div>
                </FormField>
                <FormField label="Wholesale price (optional)">
                  <NumberInput step="0.01" min="0" value={form.wholesalePrice} onChange={(e) => setForm((f) => ({ ...f, wholesalePrice: e.target.value }))} />
                </FormField>
                <FormField label="Retail price (optional)">
                  <NumberInput step="0.01" min="0" value={form.retailPrice} onChange={(e) => setForm((f) => ({ ...f, retailPrice: e.target.value }))} />
                </FormField>
              </FormSection>
            )}

            {/* Dynamic: Production settings */}
            {form.canUseInProduction && (
              <FormSection title="Production Settings" color="amber">
                <FormField label="Purchase / consumption unit" hint="Unit used when purchasing or consuming in production (optional)">
                  <Input value={form.purchaseUnit} onChange={(e) => setForm((f) => ({ ...f, purchaseUnit: e.target.value }))} maxLength={50} placeholder="e.g. bag" />
                </FormField>
                <p className="text-xs text-slate-500 col-span-full">Production workflows will be configured in later phases.</p>
              </FormSection>
            )}

            {/* Dynamic: Internal use settings */}
            {form.canUseInternally && !form.canUseInProduction && (
              <FormSection title="Internal Use Settings" color="purple">
                <FormField label="Purchase / consumption unit" hint="Unit used when purchasing or consuming internally (optional)">
                  <Input value={form.purchaseUnit} onChange={(e) => setForm((f) => ({ ...f, purchaseUnit: e.target.value }))} maxLength={50} placeholder="e.g. bag" />
                </FormField>
              </FormSection>
            )}

            {/* Pricing (cost always shown) */}
            <FormSection title="Cost & Inventory" color="amber">
              <FormField label="Cost price *">
                <NumberInput step="0.01" min="0" value={form.costPrice} onChange={(e) => setForm((f) => ({ ...f, costPrice: e.target.value }))} />
              </FormField>
              {/* Opening stock is set once, when the item is created (it posts the
                  "Opening stock" movement); the update call has no opening-stock
                  field. So on edit it is shown as saved, read-only. */}
              <FormField
                label="Opening stock"
                hint={editingId ? "Set when the item was created. To change the stock, use Adjust Stock on Inventory." : undefined}
              >
                <NumberInput
                  step="0.01" min="0" value={form.openingStock}
                  disabled={editingId != null}
                  onChange={(e) => setForm((f) => ({ ...f, openingStock: e.target.value }))}
                />
              </FormField>
              <FormField label="Low-stock alert at">
                <NumberInput step="0.01" min="0" value={form.minimumStockAlert} onChange={(e) => setForm((f) => ({ ...f, minimumStockAlert: e.target.value }))} />
              </FormField>
            </FormSection>

            {/* Advanced (collapsible) */}
            <div>
              <button
                type="button"
                onClick={() => setShowAdvanced(!showAdvanced)}
                className="flex items-center gap-1.5 text-sm font-medium text-slate-600 hover:text-slate-900 transition-colors"
              >
                {showAdvanced ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                Advanced settings
              </button>
              {showAdvanced && (
                <div className="mt-2 space-y-4">
                  <FormSection title="Status & Tracking" color="slate" columns={1}>
                    <FormField label="Track inventory">
                      <div className="flex items-center gap-3">
                        <Switch checked={form.trackInventory} onCheckedChange={(v) => setForm((f) => ({ ...f, trackInventory: v }))} id="track" />
                        <Label htmlFor="track" className="cursor-pointer text-sm text-slate-600">Uncheck for services or non-stocked items</Label>
                      </div>
                    </FormField>
                    <FormField label="Track expiry date">
                      <div className="flex items-center gap-3">
                        <Switch checked={form.trackExpiry} onCheckedChange={(v) => setForm((f) => ({ ...f, trackExpiry: v, expiryDate: v ? form.expiryDate : "" }))} id="expiry-toggle" />
                        <Label htmlFor="expiry-toggle" className="cursor-pointer text-sm text-slate-600">For perishable items (food, medicine)</Label>
                      </div>
                    </FormField>
                    {form.trackExpiry && (
                      <FormField label="Expiry date">
                        <Input type="date" value={form.expiryDate} onChange={(e) => setForm((f) => ({ ...f, expiryDate: e.target.value }))} />
                      </FormField>
                    )}
                    <FormField label="Active">
                      <div className="flex items-center gap-3">
                        <Switch checked={form.isActive} onCheckedChange={(v) => setForm((f) => ({ ...f, isActive: v }))} id="active" />
                        <Label htmlFor="active" className="cursor-pointer text-sm text-slate-600">Uncheck to hide from lists without deleting</Label>
                      </div>
                    </FormField>
                    <FormField label="Notes">
                      <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  {editingId && (
                    <FormSection title="Unit conversions" color="teal" columns={1}>
                      {conversions.length > 0 && (
                        <div className="space-y-1.5">
                          {conversions.map((c) => (
                            <div key={c.genericUomConversionId} className="flex items-center justify-between gap-2 rounded-md border px-3 py-1.5 text-sm">
                              <span>1 <strong>{c.fromUnit}</strong> = {c.conversionFactor} <strong>{c.toUnit}</strong></span>
                              <button type="button" onClick={() => removeConversion(c.genericUomConversionId)} className="text-slate-400 hover:text-red-500">
                                <Trash2 className="h-3.5 w-3.5" />
                              </button>
                            </div>
                          ))}
                        </div>
                      )}
                      <div className="flex gap-2 items-end">
                        <div className="flex-1">
                          <Label className="text-xs">From</Label>
                          <Input value={newConv.fromUnit} maxLength={50} onChange={(e) => setNewConv((p) => ({ ...p, fromUnit: e.target.value }))} placeholder="e.g. basket" />
                        </div>
                        <div className="flex-1">
                          <Label className="text-xs">To</Label>
                          <Input value={newConv.toUnit} maxLength={50} onChange={(e) => setNewConv((p) => ({ ...p, toUnit: e.target.value }))} placeholder="e.g. tuber" />
                        </div>
                        <div className="w-24">
                          <Label className="text-xs">Factor</Label>
                          <NumberInput step="0.01" min="0" value={newConv.factor} onChange={(e) => setNewConv((p) => ({ ...p, factor: e.target.value }))} placeholder="20" />
                        </div>
                        <Button type="button" variant="outline" size="sm" onClick={addConversion} className="shrink-0">
                          <Plus className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                      <p className="text-xs text-slate-500">Example: 1 basket = 20 tubers</p>
                    </FormSection>
                  )}
                </div>
              )}
            </div>

          </div>
          )}

          {/* Footer — shared by both tabs */}
          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={onSave} disabled={saving}>
              {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : (editingId != null ? "Save changes" : "Create item")}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ================================================================= */}
      {/* Item Details Dialog                                                */}
      {/* ================================================================= */}
      <Dialog open={!!detailItem} onOpenChange={(o) => { if (!o) setDetailItem(null) }}>
        <DialogContent className="w-[95vw] max-w-[900px] max-h-[90vh] overflow-y-auto">
          {detailItem && (
            <>
              <DialogHeader>
                <DialogTitle className="flex items-center gap-2">
                  <Package className="w-5 h-5 text-blue-600" /> {detailItem.productName}
                </DialogTitle>
                <DialogDescription>
                  Item #{detailItem.genericProductId} {detailItem.sku ? `· ${detailItem.sku}` : ""}
                </DialogDescription>
              </DialogHeader>

              <div className="space-y-4">
                {/* Identity & Purposes */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-3">
                    <div>
                      <div className="text-xs text-slate-500 uppercase font-medium">Category</div>
                      <div className="text-sm font-medium">{detailItem.categoryName ?? "—"}</div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500 uppercase font-medium">Description</div>
                      <div className="text-sm">{detailItem.description || "—"}</div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500 uppercase font-medium">Purposes</div>
                      <div className="flex flex-wrap gap-1 mt-1">
                        {purposeBadges(detailItem).map((b, i) => (
                          <span key={i} className={`inline-flex text-xs font-medium px-2 py-1 rounded ${b.className}`}>{b.label}</span>
                        ))}
                      </div>
                    </div>
                  </div>
                  <div className="space-y-3">
                    <div>
                      <div className="text-xs text-slate-500 uppercase font-medium">Units</div>
                      <div className="text-sm">
                        Base: <strong>{detailItem.unitOfMeasure || "—"}</strong>
                        {detailItem.purchaseUnit && <> · Purchase: <strong>{detailItem.purchaseUnit}</strong></>}
                        {detailItem.salesUnit && <> · Sales: <strong>{detailItem.salesUnit}</strong></>}
                      </div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500 uppercase font-medium">Stock Status</div>
                      <div className="flex items-center gap-2 mt-1">
                        {(() => { const s = stockStatus(detailItem); return <Badge className={`${s.className} hover:${s.className}`}>{s.label}</Badge> })()}
                        {detailItem.trackInventory && (
                          <span className="text-sm font-medium">{detailItem.currentStock.toLocaleString(undefined, { maximumFractionDigits: 3 })} {detailItem.unitOfMeasure}</span>
                        )}
                      </div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500 uppercase font-medium">Pricing</div>
                      <div className="text-sm space-y-0.5">
                        <div>Cost: <strong>{fmt(detailItem.costPrice)}</strong></div>
                        {detailItem.canSell && <div>Selling: <strong>{fmt(detailItem.sellingPrice)}</strong></div>}
                        {detailItem.wholesalePrice != null && <div>Wholesale: {fmt(detailItem.wholesalePrice)}</div>}
                        {detailItem.retailPrice != null && <div>Retail: {fmt(detailItem.retailPrice)}</div>}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Activity History */}
                <div className="border-t pt-4 space-y-4">
                  <h3 className="text-sm font-semibold text-slate-700">Activity History</h3>

                  {detailLoading ? (
                    <div className="flex items-center gap-2 text-slate-500 text-sm py-4"><Loader2 className="h-4 w-4 animate-spin" /> Loading history…</div>
                  ) : (
                    <>
                      {/* Stock Movements */}
                      <div>
                        <h4 className="text-xs font-semibold text-slate-600 uppercase mb-2 flex items-center gap-1.5">
                          <Package className="h-3.5 w-3.5" /> Stock Movements ({detailMovements.length})
                        </h4>
                        {detailMovements.length === 0 ? (
                          <p className="text-xs text-slate-400">No stock movements recorded.</p>
                        ) : (
                          <div className="max-h-48 overflow-y-auto border rounded-lg">
                            <table className="w-full text-xs">
                              <thead className="bg-slate-50 sticky top-0">
                                <tr>
                                  <th className="text-left p-2 font-medium text-slate-600">Date</th>
                                  <th className="text-left p-2 font-medium text-slate-600">Type</th>
                                  <th className="text-right p-2 font-medium text-slate-600">Qty</th>
                                  <th className="text-left p-2 font-medium text-slate-600">Reason</th>
                                </tr>
                              </thead>
                              <tbody>
                                {detailMovements.map((m) => (
                                  <tr key={m.genericStockMovementId} className="border-t">
                                    <td className="p-2 whitespace-nowrap">{new Date(m.movementDate).toLocaleDateString()}</td>
                                    <td className="p-2">
                                      <span className={`px-1.5 py-0.5 rounded text-[10px] font-medium ${
                                        m.quantity > 0 ? "bg-emerald-100 text-emerald-800" : "bg-rose-100 text-rose-800"
                                      }`}>{m.movementType}</span>
                                    </td>
                                    <td className={`p-2 text-right font-mono ${m.quantity > 0 ? "text-emerald-700" : "text-rose-700"}`}>
                                      {m.quantity > 0 ? "+" : ""}{m.quantity.toLocaleString(undefined, { maximumFractionDigits: 3 })}
                                    </td>
                                    <td className="p-2 text-slate-500 truncate max-w-[150px]">{m.reason ?? "—"}</td>
                                  </tr>
                                ))}
                              </tbody>
                            </table>
                          </div>
                        )}
                      </div>

                      {/* Sales */}
                      {detailItem.canSell && (
                        <div>
                          <h4 className="text-xs font-semibold text-slate-600 uppercase mb-2 flex items-center gap-1.5">
                            <ShoppingCart className="h-3.5 w-3.5" /> Sales ({detailSales.length})
                          </h4>
                          {detailSales.length === 0 ? (
                            <p className="text-xs text-slate-400">No sales found for this item.</p>
                          ) : (
                            <div className="max-h-36 overflow-y-auto border rounded-lg">
                              <table className="w-full text-xs">
                                <thead className="bg-slate-50 sticky top-0">
                                  <tr>
                                    <th className="text-left p-2 font-medium text-slate-600">Date</th>
                                    <th className="text-left p-2 font-medium text-slate-600">Receipt</th>
                                    <th className="text-left p-2 font-medium text-slate-600">Customer</th>
                                    <th className="text-right p-2 font-medium text-slate-600">Total</th>
                                    <th className="text-left p-2 font-medium text-slate-600">Status</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  {detailSales.map((s) => (
                                    <tr key={s.genericSaleId} className="border-t">
                                      <td className="p-2 whitespace-nowrap">{new Date(s.saleDate).toLocaleDateString()}</td>
                                      <td className="p-2 font-mono">{s.receiptNumber ?? "—"}</td>
                                      <td className="p-2">{s.customerName ?? "Walk-in"}</td>
                                      <td className="p-2 text-right">{fmt(s.totalAmount)}</td>
                                      <td className="p-2"><Badge variant={s.status === "Approved" ? "default" : "secondary"} className="text-[10px]">{s.status}</Badge></td>
                                    </tr>
                                  ))}
                                </tbody>
                              </table>
                            </div>
                          )}
                        </div>
                      )}

                      {/* Production Records */}
                      {detailItem.canUseInProduction && (
                        <div>
                          <h4 className="text-xs font-semibold text-slate-600 uppercase mb-2 flex items-center gap-1.5">
                            <Factory className="h-3.5 w-3.5" /> Production Records ({detailProduction.length})
                          </h4>
                          {detailProduction.length === 0 ? (
                            <p className="text-xs text-slate-400">No production records found for this item.</p>
                          ) : (
                            <div className="max-h-36 overflow-y-auto border rounded-lg">
                              <table className="w-full text-xs">
                                <thead className="bg-slate-50 sticky top-0">
                                  <tr>
                                    <th className="text-left p-2 font-medium text-slate-600">Date</th>
                                    <th className="text-left p-2 font-medium text-slate-600">Batch</th>
                                    <th className="text-right p-2 font-medium text-slate-600">Qty Produced</th>
                                    <th className="text-right p-2 font-medium text-slate-600">Total Cost</th>
                                    <th className="text-left p-2 font-medium text-slate-600">Status</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  {detailProduction.map((r) => (
                                    <tr key={r.genericProductionRecordId} className="border-t">
                                      <td className="p-2 whitespace-nowrap">{new Date(r.productionDate).toLocaleDateString()}</td>
                                      <td className="p-2 font-mono">{r.batchNumber ?? "—"}</td>
                                      <td className="p-2 text-right">{r.quantityProduced.toLocaleString(undefined, { maximumFractionDigits: 3 })}</td>
                                      <td className="p-2 text-right">{fmt(r.totalCost)}</td>
                                      <td className="p-2"><Badge variant={r.status === "Posted" ? "default" : "secondary"} className="text-[10px]">{r.status}</Badge></td>
                                    </tr>
                                  ))}
                                </tbody>
                              </table>
                            </div>
                          )}
                        </div>
                      )}
                    </>
                  )}
                </div>

                {/* Cost Reconciliation */}
                {detailCostRecon && (detailCostRecon.totalPurchasedCost > 0 || detailCostRecon.totalProducedCost > 0) && (
                  <div className="border-t pt-4">
                    <h3 className="text-sm font-semibold text-slate-700 mb-2">Cost Reconciliation</h3>
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                      <div className="rounded-lg bg-blue-50 p-3">
                        <div className="text-blue-600 font-medium">Purchased</div>
                        <div className="text-lg font-bold text-blue-800">{fmt(detailCostRecon.totalPurchasedCost)}</div>
                        <div className="text-blue-600">{detailCostRecon.totalPurchasedQty.toLocaleString()} units</div>
                      </div>
                      <div className="rounded-lg bg-rose-50 p-3">
                        <div className="text-rose-600 font-medium">Sold (COGS)</div>
                        <div className="text-lg font-bold text-rose-800">{fmt(detailCostRecon.soldCost)}</div>
                        <div className="text-rose-600">{detailCostRecon.soldQty.toLocaleString()} units</div>
                      </div>
                      <div className="rounded-lg bg-purple-50 p-3">
                        <div className="text-purple-600 font-medium">Internal Use</div>
                        <div className="text-lg font-bold text-purple-800">{fmt(detailCostRecon.internalUseCost)}</div>
                        <div className="text-purple-600">{detailCostRecon.internalUseQty.toLocaleString()} units</div>
                      </div>
                      <div className="rounded-lg bg-emerald-50 p-3">
                        <div className="text-emerald-600 font-medium">Remaining</div>
                        <div className="text-lg font-bold text-emerald-800">{fmt(detailCostRecon.remainingCostBasis)}</div>
                        <div className="text-emerald-600">{detailCostRecon.remainingQty.toLocaleString()} units</div>
                      </div>
                    </div>
                    {!detailCostRecon.costReconciled && (
                      <p className="text-xs text-amber-600 mt-2">Cost reconciliation drift detected. Run stock reconciliation to resolve.</p>
                    )}
                  </div>
                )}

                {/* Actions */}
                <div className="flex gap-3 justify-end pt-2 border-t">
                  <Button variant="outline" onClick={() => { setDetailItem(null); openEdit(detailItem) }}>
                    <Pencil className="h-4 w-4 mr-1" /> Edit
                  </Button>
                  <Button variant="outline" onClick={() => setDetailItem(null)}>Close</Button>
                </div>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete item?"
        itemLabel={deleteTarget?.productName}
        description={deleteTarget?.trackInventory && deleteTarget.currentStock > 0
          ? `"${deleteTarget.productName}" has ${deleteTarget.currentStock} units in stock. Backend will refuse if it's tied to sales or purchases — deactivate from the edit form to hide instead.`
          : undefined}
        successTitle="Item deleted"
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

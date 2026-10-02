"use client"

// =============================================================================
// Capital Investments/Assets — the Hotel asset register (migration 322, 340).
//
// Poultry's page (app/poultry-assets) as the Restaurant built it
// (app/restaurant-assets), with its data calls pointed at the Hotel API through
// lib/hotel/capital-assets-view.ts, in the Hotel's violet. Actions the Hotel
// backend doesn't have (correct original cost, the "what is due" list) are
// hidden via HOTEL_ASSETS_CAN; everything else is the same page.

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { PageHeader } from "@/components/hotel/page-header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  AssetDetailsPanel,
  type AssetCostRow, type AssetDetailsNotes, type AssetDetailsView, type AssetDepreciationRow,
} from "@/components/capital-assets/asset-details-panel"
import { CorrectOriginalCostDialog } from "@/components/capital-assets/correct-original-cost-dialog"
import { CostDetailDialog } from "@/components/capital-assets/cost-detail-dialog"
import {
  Plus, Building2, Loader2, Pencil, Coins, Undo2, PackageMinus, CalendarClock, Info, AlertTriangle,
  ChevronDown, ChevronRight, SlidersHorizontal,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  listHotelAssetViews, listHotelAssetCategoryViews, getHotelAssetSummaryView,
  createHotelAssetView, updateHotelAssetView, addHotelAssetCostView, getHotelAssetView,
  disposeHotelAssetView, reverseHotelAssetView,
  correctHotelAssetOriginalCostView, reverseHotelAssetCostView,
  listHotelDepreciationDueView, generateHotelDepreciationView,
  reverseHotelDepreciationView, ASSET_PAYMENT_METHODS, HOTEL_ASSETS_CAN,
  listHotelCashAccountViews,
  type HotelAssetView, type HotelAssetCategoryView,
  type HotelAssetSummaryView, type HotelAssetDepreciationDueView,
  type HotelCashAccountView as CashAccount,
} from "@/lib/hotel/capital-assets-view"
import {
  assetStatusLabel, ASSET_STATUS_CLASS,
  BOOK_VALUE_TOOLTIP,
  ACQUISITION_COST_LABEL, ADDITIONAL_COST_LABEL, TOTAL_CAPITALIZED_COST_LABEL,
  ACQUISITION_COST_TOOLTIP, ADDITIONAL_COST_TOOLTIP, TOTAL_CAPITALIZED_COST_TOOLTIP,
  CORRECT_ORIGINAL_COST_NOTE, CORRECTION_DEPRECIATION_NOTE,
  COST_TREATMENT_NOTE, COST_LOCKED_BY_DEPRECIATION_NOTE,
  DEPRECIATION_CONVENTION_NOTE, DEPRECIATION_NONCASH_NOTE,
} from "@/lib/restaurant/capital-assets"
import { DateTimeCell } from "@/components/ui/date-time-cell"
import { fmtDateTime, businessSortValue } from "@/lib/utils/company-datetime"

const STATUSES = ["Draft", "Active", "FullyDepreciated", "Disposed", "Reversed"] as const

const today = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

/** The wording the shared panel prints, all of it from this module's own lib. */
const DETAIL_NOTES: AssetDetailsNotes = {
  acquisitionCostTooltip: ACQUISITION_COST_TOOLTIP,
  additionalCostTooltip: ADDITIONAL_COST_TOOLTIP,
  totalCapitalizedCostTooltip: TOTAL_CAPITALIZED_COST_TOOLTIP,
  bookValueTooltip: BOOK_VALUE_TOOLTIP,
  depreciationNonCashNote: DEPRECIATION_NONCASH_NOTE,
  depreciationConventionNote: DEPRECIATION_CONVENTION_NOTE,
  costLockedByDepreciationNote: COST_LOCKED_BY_DEPRECIATION_NOTE,
}

/**
 * The register's own types, adapted to the module-agnostic shape the shared
 * panel reads. Nothing is computed here -- every figure is the one the server
 * sent. A restaurant purchase is not an expense row, so there is no expense id:
 * the purchase document is the cost row itself, and its ledger row points at it.
 */
function toDetailsView(a: HotelAssetView): AssetDetailsView {
  return {
    id: a.capitalAssetId,
    assetNumber: a.assetNumber, assetName: a.assetName, categoryName: a.categoryName,
    description: a.description, location: a.location, serialNumber: a.serialNumber,
    notes: a.notes, supplierName: a.supplierName,
    status: a.status, statusLabel: assetStatusLabel(a.status),
    acquisitionDate: a.acquisitionDate, inServiceDate: a.inServiceDate,
    acquisitionCost: a.acquisitionCost, additionalCost: a.additionalCost,
    totalCapitalizedCost: a.totalCapitalizedCost,
    residualValue: a.residualValue, depreciableAmount: a.depreciableAmount,
    usefulLifeMonths: a.usefulLifeMonths, monthlyDepreciation: a.monthlyDepreciation,
    accumulatedDepreciation: a.accumulatedDepreciation, currentBookValue: a.currentBookValue,
    remainingDepreciable: a.remainingDepreciable, isFullyDepreciated: a.isFullyDepreciated,
    depreciationEntries: a.depreciationEntries,
    createdBy: a.createdBy, createdAt: a.createdAt,
    costs: (a.costs ?? []).map<AssetCostRow>((c) => ({
      id: c.assetCostId,
      costDate: c.costDate, description: c.description, costCategory: c.costCategory,
      amount: c.amount, sourceType: c.sourceType, supplierName: c.supplierName,
      paymentStatus: c.paymentStatus, amountPaid: c.amountPaid, balance: c.balance,
      paymentMethod: c.paymentMethod, dueDate: c.dueDate, cashAccountName: c.cashAccountName,
      expenseId: null, expenseAmount: c.documentAmount, expenseCategory: null,
      status: c.status, createdBy: c.createdBy, createdAt: c.createdAt,
      reversedBy: c.reversedBy, reversedAt: c.reversedAt, reversalReason: c.reversalReason,
    })),
    depreciation: (a.depreciation ?? []).map<AssetDepreciationRow>((d) => ({
      id: d.assetDepreciationId,
      periodStart: d.periodStart, periodEnd: d.periodEnd, depreciationDate: d.depreciationDate,
      amount: d.amount, depreciationMethod: d.depreciationMethod, sourceType: d.sourceType,
      status: d.status, expenseId: null,
      accumulatedAfter: d.accumulatedAfter, bookValueAfter: d.bookValueAfter,
      createdBy: d.createdBy, createdAt: d.createdAt,
      reversedBy: d.reversedBy, reversedAt: d.reversedAt, reversalReason: d.reversalReason,
    })),
  }
}

/** Where a capital purchase's money is recorded, in place of Poultry's "Expense #". */
function CostRecordRow(c: AssetCostRow) {
  return (
    <div className="flex justify-between gap-4 text-sm">
      <span className="shrink-0 text-slate-600">Cash ledger</span>
      <span className="text-right text-slate-900">
        {(c.amountPaid ?? 0) !== 0
          ? <>Capital investment payment{c.cashAccountName ? ` — ${c.cashAccountName}` : ""}. Not an expense.</>
          : <span className="text-slate-500">No cash moved for this entry.</span>}
      </span>
    </div>
  )
}

export default function HotelAssetsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  // Poultry's gate (financial-nav-access.ts): expenses or financial access.
  const canView = permissions.isAdmin || permissions.featureAccess.canEnterExpenses || permissions.featureAccess.canViewFinancial

  const [assets, setAssets] = useState<HotelAssetView[]>([])
  const [categories, setCategories] = useState<HotelAssetCategoryView[]>([])
  const [summary, setSummary] = useState<HotelAssetSummaryView | null>(null)
  const [due, setDue] = useState<HotelAssetDepreciationDueView[]>([])
  const [cashAccounts, setCashAccounts] = useState<CashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [search, setSearch] = useState("")
  const [statusFilter, setStatusFilter] = useState("all")
  const [categoryFilter, setCategoryFilter] = useState("all")
  const [sort, setSort] = useState<{ key: string | null; direction: SortDirection }>({ key: "acquisitionDate", direction: "desc" })

  const [newOpen, setNewOpen] = useState(false)
  const [editing, setEditing] = useState<HotelAssetView | null>(null)
  const [costFor, setCostFor] = useState<HotelAssetView | null>(null)
  const [disposing, setDisposing] = useState<HotelAssetView | null>(null)
  const [reversing, setReversing] = useState<HotelAssetView | null>(null)
  const [depOpen, setDepOpen] = useState(false)

  // Collapsed by default; the full history is fetched only when a row is opened.
  const [expanded, setExpanded] = useState<Set<number>>(new Set())
  const [details, setDetails] = useState<Record<number, HotelAssetView>>({})
  const [detailBusy, setDetailBusy] = useState<Set<number>>(new Set())
  const [detailError, setDetailError] = useState<Record<number, string>>({})

  const [correcting, setCorrecting] = useState<HotelAssetView | null>(null)
  const [viewingCost, setViewingCost] = useState<{ assetId: number; row: AssetCostRow } | null>(null)
  const [reversingCost, setReversingCost] = useState<{ assetId: number; row: AssetCostRow } | null>(null)
  const [reversingDep, setReversingDep] = useState<{ assetId: number; id: number } | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Hotel") router.replace("/dashboard")
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [a, c, s, d, ca] = await Promise.all([
        listHotelAssetViews(),
        listHotelAssetCategoryViews(),
        getHotelAssetSummaryView(),
        listHotelDepreciationDueView().catch(() => []),
        listHotelCashAccountViews().catch(() => [] as CashAccount[]),
      ])
      setAssets(a); setCategories(c); setSummary(s); setDue(d)
      setCashAccounts((ca as CashAccount[]).filter((x) => x.isActive))
    } catch (e: any) {
      toast({ title: "Could not load capital investments", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }, [toast])

  useEffect(() => {
    if (!activeFarmId || !canView) { setLoading(false); return }
    void load()
  }, [activeFarmId, canView, load])

  const loadDetail = useCallback(async (id: number) => {
    setDetailBusy((prev) => new Set(prev).add(id))
    setDetailError((prev) => { const n = { ...prev }; delete n[id]; return n })
    try {
      const full = await getHotelAssetView(id)
      setDetails((prev) => ({ ...prev, [id]: full }))
    } catch (e: any) {
      setDetailError((prev) => ({ ...prev, [id]: e?.message ?? String(e) }))
    } finally {
      setDetailBusy((prev) => { const n = new Set(prev); n.delete(id); return n })
    }
  }, [])

  const toggleExpanded = useCallback((id: number) => {
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.delete(id)) return next
      next.add(id)
      return next
    })
    if (!details[id]) void loadDetail(id)
  }, [details, loadDetail])

  /** Reload the list AND any open detail, so an expanded history never shows a reversed cost. */
  const reloadWithOpenDetails = useCallback(async () => {
    await load()
    await Promise.all([...expanded].map((id) => loadDetail(id)))
  }, [load, expanded, loadDetail])

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return assets.filter((a) => {
      if (statusFilter !== "all" && a.status !== statusFilter) return false
      if (categoryFilter !== "all" && String(a.assetCategoryId ?? "") !== categoryFilter) return false
      if (!q) return true
      return [a.assetName, a.assetNumber, a.categoryName, a.location, a.serialNumber, a.supplierName]
        .some((v) => (v ?? "").toLowerCase().includes(q))
    })
  }, [assets, search, statusFilter, categoryFilter])

  const sorted = useMemo(
    () => sortData(filtered, sort.key, sort.direction, (a: HotelAssetView, k: string) =>
      k === "acquisitionDate" ? businessSortValue(a.acquisitionDate, a) : (a as any)[k]),
    [filtered, sort],
  )
  const pg = usePagination(sorted)

  const dueTotal = due.reduce((s, d) => s + d.amountDue, 0)
  const dueMonths = due.reduce((s, d) => s + d.monthsDue, 0)

  const runDepreciation = async () => {
    setSaving(true)
    try {
      const res = await generateHotelDepreciationView({})
      toast({
        title: res.entriesCreated > 0 ? "Depreciation posted" : "Nothing was due",
        description: res.entriesCreated > 0
          ? `${res.entriesCreated} month(s) across ${res.assetsProcessed} asset(s), ${gh(res.totalAmount)} charged to Profit & Loss. No cash moved.`
          : "Every capital investment is up to date.",
      })
      setDepOpen(false)
      await reloadWithOpenDetails()
    } catch (e: any) {
      toast({ title: "Could not generate depreciation", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const shell = (children: React.ReactNode) => (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 min-w-0 overflow-y-auto p-4 sm:p-6 space-y-4">{children}</main>
      </div>
    </div>
  )

  if (!canView) return shell(
    <Card><CardContent className="py-12 text-center text-slate-600">
      You do not have access to Capital Investments/Assets. Ask an admin for the expenses or financial permission.
    </CardContent></Card>,
  )

  return shell(<>
    <PageHeader icon={Building2} title="Capital Investments/Assets"
                subtitle="Track major long-term business investments, their cost, depreciation, and current book value.">
      <Button variant="outline" onClick={() => setDepOpen(true)} disabled={loading}>
        <CalendarClock className="w-4 h-4 mr-1" />
        Depreciation
        {dueMonths > 0 && (
          <Badge className="ml-2 bg-amber-100 text-amber-800 hover:bg-amber-100">{dueMonths} due</Badge>
        )}
      </Button>
      <Button className="bg-violet-600 hover:bg-violet-700" onClick={() => setNewOpen(true)}>
        <Plus className="w-4 h-4 mr-1" /> New investment
      </Button>
    </PageHeader>

    {/* ---- the five cards -------------------------------------------- */}
    {summary && (
      <div className="grid gap-3 grid-cols-2 lg:grid-cols-5">
        <StatCard label="Total capitalised cost" value={gh(summary.totalAssetCost)} hint={TOTAL_CAPITALIZED_COST_TOOLTIP} />
        <StatCard label="Depreciation so far" value={gh(summary.accumulatedDepreciation)}
                  hint="Charged to Profit & Loss over time. No cash moved." tone="amber" />
        <StatCard label="Current book value" value={gh(summary.currentBookValue)}
                  hint={BOOK_VALUE_TOOLTIP} tone="emerald" strong />
        <StatCard label="Added this period" value={gh(summary.addedInPeriod)}
                  hint={`${summary.addedCount} asset(s) acquired`} />
        <StatCard label="Active investments" value={String(summary.activeAssets)}
                  hint={`${summary.draftAssets} not in service · ${summary.fullyDepreciated} fully depreciated`} />
      </div>
    )}

    <ListFilters
      search={search} setSearch={setSearch} searchOnly
      searchPlaceholder="Search investment, number, location or supplier"
      extras={<>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-full sm:w-[170px]"><SelectValue placeholder="All statuses" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All statuses</SelectItem>
            {STATUSES.map((s) => <SelectItem key={s} value={s}>{assetStatusLabel(s)}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={categoryFilter} onValueChange={setCategoryFilter}>
          <SelectTrigger className="w-full sm:w-[190px]"><SelectValue placeholder="All categories" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All categories</SelectItem>
            {categories.map((c) => (
              <SelectItem key={c.assetCategoryId} value={String(c.assetCategoryId)}>{c.categoryName}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </>}
    />

    <Card><CardContent className="p-0 lg:p-4">
      {loading ? (
        <div className="py-10 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-slate-400" /></div>
      ) : (
        <MobileCardList
          striped
          defaultOpen
          items={pg.pageItems}
          getKey={(a) => a.capitalAssetId}
          primary={(a) => (
            <span>{a.assetName}</span>
          )}
          secondary={(a) => (
            <span className="truncate">
              {a.assetNumber} · {a.categoryName ?? "Uncategorised"}
              {a.location ? ` · ${a.location}` : ""}
            </span>
          )}
          trailing={(a) => (
            <Badge variant="outline" className={cn("text-[10px] font-normal", ASSET_STATUS_CLASS[a.status])}>
              {assetStatusLabel(a.status)}
            </Badge>
          )}
          highlights={(a) => [
            { label: "Book value", value: gh(a.currentBookValue), accent: "emerald", wide: true },
            { label: "Capitalised cost", value: gh(a.totalCapitalizedCost), accent: "blue" },
            { label: "Depreciation", value: a.accumulatedDepreciation > 0 ? gh(a.accumulatedDepreciation) : "—", accent: "amber" },
          ]}
          details={(a) => [
            { label: "Acquired", value: fmtDateTime(a.acquisitionDate, a) || "—" },
            { label: "Original acquisition", value: gh(a.acquisitionCost) },
            { label: "Added since", value: a.additionalCost > 0 ? gh(a.additionalCost) : "—" },
            {
              label: "Useful life",
              value: a.usefulLifeMonths
                ? `${a.usefulLifeMonths} months${a.monthlyDepreciation ? ` · ${gh(a.monthlyDepreciation)}/month` : ""}`
                : "Not set",
            },
            ...(a.amountOwed > 0 ? [{ label: "Owed to supplier", value: gh(a.amountOwed) }] : []),
          ]}
          actions={(a) => (
            a.status === "Reversed" ? null : (<>
              <Button size="sm" variant="outline" className="basis-full h-10"
                      onClick={() => toggleExpanded(a.capitalAssetId)}>
                {expanded.has(a.capitalAssetId)
                  ? <><ChevronDown className="w-4 h-4 mr-1" /> Hide history</>
                  : <><ChevronRight className="w-4 h-4 mr-1" /> Where these figures came from</>}
              </Button>
              <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => setEditing(a)}>
                <Pencil className="w-4 h-4 mr-1" /> Edit
              </Button>
              {a.status !== "Disposed" && (
                <Button size="sm" variant="outline" className="flex-1 h-10"
                        disabled={a.depreciationEntries > 0}
                        title={a.depreciationEntries > 0 ? COST_LOCKED_BY_DEPRECIATION_NOTE : undefined}
                        onClick={() => setCostFor(a)}>
                  <Coins className="w-4 h-4 mr-1" /> Add cost
                </Button>
              )}
              {HOTEL_ASSETS_CAN.correctOriginalCost && a.status !== "Disposed" && a.acquisitionCost > 0 && (
                <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => setCorrecting(a)}>
                  <SlidersHorizontal className="w-4 h-4 mr-1" /> Correct cost
                </Button>
              )}
              {a.status !== "Disposed" && (
                <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700" onClick={() => setDisposing(a)}>
                  <PackageMinus className="w-4 h-4 mr-1" /> Dispose
                </Button>
              )}
              {a.depreciationEntries === 0 && a.status !== "Disposed" && (
                <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600" onClick={() => setReversing(a)}>
                  <Undo2 className="w-4 h-4 mr-1" /> Reverse
                </Button>
              )}
            </>)
          )}
          extra={(a) => (
            expanded.has(a.capitalAssetId) ? (
              <div className="-mx-1 rounded-md border border-slate-200 bg-slate-50">
                <AssetDetailsPanel
                  view={details[a.capitalAssetId] ? toDetailsView(details[a.capitalAssetId]) : null}
                  loading={detailBusy.has(a.capitalAssetId)}
                  error={detailError[a.capitalAssetId] ?? null}
                  onRetry={() => void loadDetail(a.capitalAssetId)}
                  term="investment"
                  notes={DETAIL_NOTES}
                  fmt={gh}
                                    expensesHref="/hotel-expenses"
                  onEdit={() => setEditing(a)}
                  onAddCost={() => setCostFor(a)}
                  onCorrectOriginalCost={HOTEL_ASSETS_CAN.correctOriginalCost ? () => setCorrecting(a) : undefined}
                  onViewCost={(row) => setViewingCost({ assetId: a.capitalAssetId, row })}
                  onReverseCost={(row) => setReversingCost({ assetId: a.capitalAssetId, row })}
                  onReverseDepreciation={(row) => setReversingDep({ assetId: a.capitalAssetId, id: row.id })}
                />
              </div>
            ) : null
          )}
          emptyState={
            <div className="py-8 text-center text-slate-500 text-sm px-4">
              No capital investments recorded. A combi oven, a walk-in cold room or a delivery motorbike belongs here
              rather than on the Expenses page.
            </div>
          }
          pagination={{ ...pg.paginationProps, variant: "records" }}
          desktopTable={
            <div className="overflow-x-auto"><Table className="min-w-[940px]">
              <TableHeader><TableRow>
                <TableHead className="w-8 px-1" />
                {(() => { const onSort = (k: string) => setSort((s) => toggleSort(k, s.key, s.direction))
                  const cs = sort.key, cd = sort.direction
                  return (<>
                    <SortableHeader label="Investment #" sortKey="assetNumber" currentSort={cs} currentDirection={cd} onSort={onSort} />
                    <SortableHeader label="Investment" sortKey="assetName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                    <SortableHeader label="Category" sortKey="categoryName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                    <SortableHeader label="Acquired" sortKey="acquisitionDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                    <SortableHeader label="Capitalised cost" sortKey="totalCapitalizedCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" title={TOTAL_CAPITALIZED_COST_TOOLTIP} />
                    <SortableHeader label="Depreciation" sortKey="accumulatedDepreciation" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                    <SortableHeader label="Book value" sortKey="currentBookValue" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                    <SortableHeader label="Useful life" sortKey="usefulLifeMonths" currentSort={cs} currentDirection={cd} onSort={onSort} />
                    <SortableHeader label="Status" sortKey="status" currentSort={cs} currentDirection={cd} onSort={onSort} />
                  </>) })()}
                <TableHead className="text-right">Actions</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {sorted.length === 0 ? (
                  <TableRow><TableCell colSpan={11} className="text-center text-slate-500 py-8">
                    No capital investments recorded. A combi oven, a walk-in cold room or a delivery motorbike belongs here rather than on the Expenses page.
                  </TableCell></TableRow>
                ) : pg.pageItems.map((a) => {
                  const open = expanded.has(a.capitalAssetId)
                  return (
                    <Fragment key={a.capitalAssetId}>
                      <TableRow className={cn(a.status === "Reversed" && "opacity-60")}>
                        <TableCell className="px-1">
                          <button
                            type="button"
                            onClick={() => toggleExpanded(a.capitalAssetId)}
                            aria-expanded={open}
                            aria-label={open ? "Hide the cost and depreciation history" : "Show where these figures came from"}
                            title={open ? "Hide the history" : "Show where these figures came from"}
                            className="rounded p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-700"
                          >
                            {open ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                          </button>
                        </TableCell>
                        <TableCell className="whitespace-nowrap text-sm font-mono">{a.assetNumber}</TableCell>
                        <TableCell className="font-medium">
                          <span>{a.assetName}</span>
                          {a.location && <div className="text-[11px] text-slate-500">{a.location}</div>}
                        </TableCell>
                        <TableCell className="text-sm">{a.categoryName ?? "—"}</TableCell>
                        <TableCell className="align-top text-sm"><DateTimeCell value={a.acquisitionDate} row={a} /></TableCell>
                        <TableCell className="text-right tabular-nums" title={TOTAL_CAPITALIZED_COST_TOOLTIP}>
                          {gh(a.totalCapitalizedCost)}
                          {a.additionalCost > 0 && (
                            <div className="text-[11px] font-normal text-slate-500">
                              {gh(a.acquisitionCost)} + {gh(a.additionalCost)} added
                            </div>
                          )}
                          {a.amountOwed > 0 && (
                            <div className="text-[11px] font-normal text-amber-700">{gh(a.amountOwed)} owed</div>
                          )}
                        </TableCell>
                        <TableCell className="text-right tabular-nums text-amber-700">
                          {a.accumulatedDepreciation > 0 ? gh(a.accumulatedDepreciation) : "—"}
                        </TableCell>
                        <TableCell className="text-right tabular-nums font-medium" title={BOOK_VALUE_TOOLTIP}>
                          {gh(a.currentBookValue)}
                        </TableCell>
                        <TableCell className="text-sm whitespace-nowrap">
                          {a.usefulLifeMonths ? `${a.usefulLifeMonths} months` : <span className="text-slate-400">Not set</span>}
                          {a.monthlyDepreciation != null && a.monthlyDepreciation > 0 && (
                            <div className="text-[11px] text-slate-500">{gh(a.monthlyDepreciation)}/month</div>
                          )}
                        </TableCell>
                        <TableCell>
                          <Badge variant="outline" className={cn("text-[10px] font-normal", ASSET_STATUS_CLASS[a.status])}>
                            {assetStatusLabel(a.status)}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right whitespace-nowrap">
                          {a.status !== "Reversed" && (<>
                            <Button variant="ghost" size="sm" title="Edit" onClick={() => setEditing(a)}>
                              <Pencil className="w-4 h-4" />
                            </Button>
                            {a.status !== "Disposed" && (
                              <Button variant="ghost" size="sm"
                                      title={a.depreciationEntries > 0 ? COST_LOCKED_BY_DEPRECIATION_NOTE : "Add capitalised cost"}
                                      disabled={a.depreciationEntries > 0}
                                      onClick={() => setCostFor(a)}>
                                <Coins className="w-4 h-4" />
                              </Button>
                            )}
                            {HOTEL_ASSETS_CAN.correctOriginalCost && a.status !== "Disposed" && a.acquisitionCost > 0 && (
                              <Button variant="ghost" size="sm" title="Correct the original acquisition cost"
                                      onClick={() => setCorrecting(a)}>
                                <SlidersHorizontal className="w-4 h-4" />
                              </Button>
                            )}
                            {a.status !== "Disposed" && (
                              <Button variant="ghost" size="sm" title="Dispose" onClick={() => setDisposing(a)}>
                                <PackageMinus className="w-4 h-4 text-amber-600" />
                              </Button>
                            )}
                            {a.depreciationEntries === 0 && a.status !== "Disposed" && (
                              <Button variant="ghost" size="sm" title="Reverse this acquisition" onClick={() => setReversing(a)}>
                                <Undo2 className="w-4 h-4 text-red-500" />
                              </Button>
                            )}
                          </>)}
                        </TableCell>
                      </TableRow>
                      {open && (
                        <TableRow>
                          <TableCell colSpan={11} className="bg-slate-50 p-0">
                            <AssetDetailsPanel
                              view={details[a.capitalAssetId] ? toDetailsView(details[a.capitalAssetId]) : null}
                              loading={detailBusy.has(a.capitalAssetId)}
                              error={detailError[a.capitalAssetId] ?? null}
                              onRetry={() => void loadDetail(a.capitalAssetId)}
                              term="investment"
                              notes={DETAIL_NOTES}
                              fmt={gh}
                                                            expensesHref="/hotel-expenses"
                              onEdit={() => setEditing(a)}
                              onAddCost={() => setCostFor(a)}
                              onCorrectOriginalCost={HOTEL_ASSETS_CAN.correctOriginalCost ? () => setCorrecting(a) : undefined}
                              onViewCost={(row) => setViewingCost({ assetId: a.capitalAssetId, row })}
                              onReverseCost={(row) => setReversingCost({ assetId: a.capitalAssetId, row })}
                              onReverseDepreciation={(row) => setReversingDep({ assetId: a.capitalAssetId, id: row.id })}
                            />
                          </TableCell>
                        </TableRow>
                      )}
                    </Fragment>
                  )
                })}
              </TableBody>
            </Table></div>
          }
        />
      )}
    </CardContent></Card>

    <p className="text-[11px] text-slate-500">
      Capital investments affect Cash Flow when they are paid for, and anything bought on credit stays owed to the
      supplier. They are not charged against profit in the month they are bought — their cost reaches Profit &amp;
      Loss over time through depreciation.
    </p>

    <AssetFormDialog
      open={newOpen} onOpenChange={setNewOpen} categories={categories} cashAccounts={cashAccounts}
      saving={saving} setSaving={setSaving} onSaved={load}
    />
    <EditDialog asset={editing} onClose={() => setEditing(null)} categories={categories} onSaved={reloadWithOpenDetails}
                onCorrectOriginalCost={(a) => setCorrecting(a)} />
    <AddCostDialog asset={costFor} onClose={() => setCostFor(null)} cashAccounts={cashAccounts} onSaved={reloadWithOpenDetails} />
    <DisposeDialog asset={disposing} onClose={() => setDisposing(null)} cashAccounts={cashAccounts} onSaved={reloadWithOpenDetails} />
    <ReverseDialog asset={reversing} onClose={() => setReversing(null)} onSaved={reloadWithOpenDetails} />

    <CorrectOriginalCostDialog
      asset={correcting ? {
        id: correcting.capitalAssetId,
        assetName: correcting.assetName,
        assetNumber: correcting.assetNumber,
        acquisitionCost: correcting.acquisitionCost,
        additionalCost: correcting.additionalCost,
        totalCapitalizedCost: correcting.totalCapitalizedCost,
        residualValue: correcting.residualValue,
        usefulLifeMonths: correcting.usefulLifeMonths,
        accumulatedDepreciation: correcting.accumulatedDepreciation,
        currentBookValue: correcting.currentBookValue,
        depreciationEntries: correcting.depreciationEntries,
      } : null}
      onClose={() => setCorrecting(null)}
      fmt={gh}
      term="investment"
      notes={{
        correctOriginalCostNote: CORRECT_ORIGINAL_COST_NOTE,
        correctionDepreciationNote: CORRECTION_DEPRECIATION_NOTE,
      }}
      onSubmit={async (input) => {
        const id = correcting!.capitalAssetId
        await correctHotelAssetOriginalCostView(id, input)
        toast({
          title: "Original cost corrected",
          description: "The correction is on the cost history with your reason. Depreciation already posted is unchanged.",
        })
        await reloadWithOpenDetails()
      }}
    />

    <CostDetailDialog
      cost={viewingCost?.row ?? null}
      assetName={assets.find((a) => a.capitalAssetId === viewingCost?.assetId)?.assetName}
      onClose={() => setViewingCost(null)}
      fmt={gh}
      term="investment"
      expensesHref="/hotel-expenses"
      recordRow={CostRecordRow}
      onReverse={(row) => {
        setViewingCost(null)
        setReversingCost({ assetId: viewingCost!.assetId, row })
      }}
      reverseDisabledReason={
        (assets.find((a) => a.capitalAssetId === viewingCost?.assetId)?.depreciationEntries ?? 0) > 0
          ? COST_LOCKED_BY_DEPRECIATION_NOTE
          : null
      }
    />

    {/* The row is kept and marked reversed; nothing is deleted. */}
    <PromptDialog
      open={!!reversingCost}
      onOpenChange={(o) => { if (!o) setReversingCost(null) }}
      title="Reverse this capitalised cost"
      description={
        "The entry is kept on the record and marked reversed, and the investment's value falls by "
        + gh(reversingCost?.row.amount ?? 0)
        + ". Any cash paid is returned and any balance owed is closed. Nothing is charged to profit."
      }
      label="Reason"
      placeholder="Entered against the wrong investment"
      confirmLabel="Reverse cost"
      confirmVariant="destructive"
      onSubmit={async (reason) => {
        const target = reversingCost!
        await reverseHotelAssetCostView(target.assetId, target.row.id, reason)
        toast({ title: "Cost reversed", description: "The entry is kept with its reason." })
        setReversingCost(null)
        await reloadWithOpenDetails()
      }}
    />

    {/* Reversing a posted charge. The month is NOT reopened to the generator. */}
    <PromptDialog
      open={!!reversingDep}
      onOpenChange={(o) => { if (!o) setReversingDep(null) }}
      title="Reverse this depreciation charge"
      description="The original entry is kept and an opposite one is written beside it, so the history still shows what was charged and when. No cash is affected."
      label="Reason"
      placeholder="Wrong in-service month"
      confirmLabel="Reverse charge"
      confirmVariant="destructive"
      onSubmit={async (reason) => {
        const target = reversingDep!
        await reverseHotelDepreciationView(target.id, reason)
        toast({
          title: "Depreciation reversed",
          description: "The original entry is kept and an opposite entry added. No cash moved.",
        })
        setReversingDep(null)
        await reloadWithOpenDetails()
      }}
    />

    {/* ---- generate depreciation ------------------------------------- */}
    <Dialog open={depOpen} onOpenChange={setDepOpen}>
      <DialogContent className="sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>Depreciation</DialogTitle>
          <DialogDescription>{DEPRECIATION_NONCASH_NOTE}</DialogDescription>
        </DialogHeader>
        {due.length === 0 ? (
          HOTEL_ASSETS_CAN.depreciationDue ? (
            <p className="text-sm text-slate-600 py-4">Every capital investment is up to date. Nothing is due.</p>
          ) : (
            // Hotel has no "what is due" query: posting charges every month due, up to today.
            <div className="space-y-3">
              <p className="text-sm text-slate-600">
                Charges every month of depreciation that is due, up to today, for each capital investment in service.
                Months already posted are skipped.
              </p>
              <p className="text-[11px] text-slate-500">{DEPRECIATION_CONVENTION_NOTE}</p>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setDepOpen(false)}>Cancel</Button>
                <Button className="bg-violet-600 hover:bg-violet-700" onClick={runDepreciation} disabled={saving}>
                  {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}
                  Post depreciation
                </Button>
              </div>
            </div>
          )
        ) : (
          <div className="space-y-3">
            <div className="max-h-[45vh] overflow-y-auto">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Investment</TableHead><TableHead>From</TableHead>
                  <TableHead className="text-right">Months</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {due.map((d) => (
                    <TableRow key={d.capitalAssetId}>
                      <TableCell className="text-sm">{d.assetName}</TableCell>
                      <TableCell className="text-sm whitespace-nowrap">{fmtDateTime(d.nextPeriod)}</TableCell>
                      <TableCell className="text-right text-sm">{d.monthsDue}</TableCell>
                      <TableCell className="text-right tabular-nums text-sm">{gh(d.amountDue)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            <div className="flex items-center justify-between rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm">
              <span className="text-amber-900">
                {dueMonths} month(s) across {due.length} asset(s) will be charged to Profit &amp; Loss.
              </span>
              <strong className="tabular-nums text-amber-900">{gh(dueTotal)}</strong>
            </div>
            <p className="text-[11px] text-slate-500">{DEPRECIATION_CONVENTION_NOTE}</p>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDepOpen(false)}>Cancel</Button>
              <Button className="bg-violet-600 hover:bg-violet-700" onClick={runDepreciation} disabled={saving}>
                {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}
                Post depreciation
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  </>)
}

// ------------------------------------------------------------------ pieces ---

function StatCard({ label, value, hint, tone, strong }: {
  label: string; value: string; hint?: string; tone?: "amber" | "emerald"; strong?: boolean
}) {
  return (
    <Card className={cn(tone === "amber" && "border-amber-200", tone === "emerald" && "border-emerald-200",
                        strong && "ring-1 ring-slate-300")}>
      <CardContent className="p-3">
        <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
        <div className={cn("text-lg font-semibold tabular-nums",
          tone === "amber" && "text-amber-800", tone === "emerald" && "text-emerald-800")}>{value}</div>
        {hint && <div className="text-[11px] text-slate-500 line-clamp-2" title={hint}>{hint}</div>}
      </CardContent>
    </Card>
  )
}

function CashAccountSelect({ value, onChange, cashAccounts }: {
  value: string; onChange: (v: string) => void; cashAccounts: CashAccount[]
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
      <SelectContent>
        {cashAccounts.map((a) => (
          <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{a.name}</SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

/**
 * Recording an asset. The cost is OPTIONAL on purpose: a dining-room refit that
 * will be built up starts at nothing and grows through "Add cost".
 */
function AssetFormDialog({ open, onOpenChange, categories, cashAccounts, saving, setSaving, onSaved }: {
  open: boolean; onOpenChange: (o: boolean) => void
  categories: HotelAssetCategoryView[]; cashAccounts: CashAccount[]
  saving: boolean; setSaving: (b: boolean) => void; onSaved: () => Promise<void> | void
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [f, setF] = useState<any>({ acquisitionDate: today(), residualValue: 0, paymentMethod: "Cash" })

  useEffect(() => { if (open) setF({ acquisitionDate: today(), residualValue: 0, paymentMethod: "Cash" }) }, [open])

  const cat = categories.find((c) => String(c.assetCategoryId) === String(f.assetCategoryId))
  const amount = Number(f.amount) || 0
  const paid = f.amountPaid === undefined || f.amountPaid === null || f.amountPaid === "" ? amount : Number(f.amountPaid)
  const owing = Math.max(amount - paid, 0)
  const life = Number(f.usefulLifeMonths) || 0
  const monthly = life > 0 ? Math.round(((amount - (Number(f.residualValue) || 0)) / life) * 100) / 100 : 0

  const save = async () => {
    if (!f.assetName?.trim()) { toast({ title: "Name the investment", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createHotelAssetView({
        assetName: f.assetName, assetCategoryId: f.assetCategoryId ? Number(f.assetCategoryId) : null,
        description: f.description || null,
        acquisitionDate: f.acquisitionDate || null, inServiceDate: f.inServiceDate || null,
        amount: amount > 0 ? amount : null,
        residualValue: Number(f.residualValue) || 0,
        usefulLifeMonths: life > 0 ? life : null,
        supplier: f.supplier || null,
        paymentMethod: f.paymentMethod || "Cash",
        amountPaid: amount > 0 ? paid : null,
        dueDate: f.dueDate || null,
        cashAccountId: f.cashAccountId ? Number(f.cashAccountId) : null,
        location: f.location || null, serialNumber: f.serialNumber || null, notes: f.notes || null,
      })
      toast({ title: "Investment recorded", description: "It is in the register and excluded from this period's operating expenses." })
      onOpenChange(false)
      await onSaved()
    } catch (e: any) {
      toast({ title: "Could not record the investment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>New capital investment</DialogTitle>
          <DialogDescription>
            A major long-term purchase. Cash and supplier balances behave exactly as they do for a bill; the cost is
            recognised over time through depreciation rather than charged to this period.
          </DialogDescription>
        </DialogHeader>

        <FormSection title="What it is">
          <FormField label="Investment name">
            <Input value={f.assetName ?? ""} onChange={(e) => setF({ ...f, assetName: e.target.value })}
                   placeholder="Combi oven" />
          </FormField>
          <FormField label="Category">
            <Select value={f.assetCategoryId ? String(f.assetCategoryId) : ""}
                    onValueChange={(v) => {
                      const c = categories.find((x) => String(x.assetCategoryId) === v)
                      setF({ ...f, assetCategoryId: v, usefulLifeMonths: f.usefulLifeMonths || c?.defaultUsefulLifeMonths || "" })
                    }}>
              <SelectTrigger><SelectValue placeholder="Choose a category" /></SelectTrigger>
              <SelectContent>
                {categories.map((c) => (
                  <SelectItem key={c.assetCategoryId} value={String(c.assetCategoryId)}>{c.categoryName}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Location"><Input value={f.location ?? ""} onChange={(e) => setF({ ...f, location: e.target.value })} /></FormField>
          <FormField label="Serial number"><Input value={f.serialNumber ?? ""} onChange={(e) => setF({ ...f, serialNumber: e.target.value })} /></FormField>
          <FormField label="Description" full>
            <Textarea rows={2} value={f.description ?? ""} onChange={(e) => setF({ ...f, description: e.target.value })} />
          </FormField>
        </FormSection>

        <FormSection title="What it cost">
          <FormField label="Acquisition date">
            <Input type="date" max={today()} value={f.acquisitionDate ?? ""} onChange={(e) => setF({ ...f, acquisitionDate: e.target.value })} />
          </FormField>
          <FormField label="Cost" hint="Leave blank for an investment you will build up cost by cost.">
            <NumberInput value={f.amount ?? ""} onChange={(e) => setF({ ...f, amount: e.target.value })} />
          </FormField>
          <FormField label="Supplier / payee"><Input value={f.supplier ?? ""} onChange={(e) => setF({ ...f, supplier: e.target.value })} /></FormField>
          <FormField label="Amount paid now" hint="Leave blank if paid in full.">
            <NumberInput value={f.amountPaid ?? ""} onChange={(e) => setF({ ...f, amountPaid: e.target.value })} />
          </FormField>
          <FormField label="Paid from">
            <CashAccountSelect value={f.cashAccountId ? String(f.cashAccountId) : ""} cashAccounts={cashAccounts}
                               onChange={(v) => setF({ ...f, cashAccountId: v })} />
          </FormField>
          <FormField label="Balance due date"><Input type="date" value={f.dueDate ?? ""} onChange={(e) => setF({ ...f, dueDate: e.target.value })} /></FormField>
        </FormSection>

        <FormSection title="How it depreciates">
          <FormField label="In-service date" hint="Depreciation starts in this month. Leave blank if it is not in use yet.">
            <Input type="date" value={f.inServiceDate ?? ""} onChange={(e) => setF({ ...f, inServiceDate: e.target.value })} />
          </FormField>
          <FormField label="Useful life (months)" hint={cat?.defaultUsefulLifeMonths ? `${cat.categoryName} usually ${cat.defaultUsefulLifeMonths} months` : undefined}>
            <NumberInput value={f.usefulLifeMonths ?? ""} onChange={(e) => setF({ ...f, usefulLifeMonths: e.target.value })} />
          </FormField>
          <FormField label="Residual value" hint="What you expect it to still be worth at the end. Book value never falls below it.">
            <NumberInput value={f.residualValue ?? 0} onChange={(e) => setF({ ...f, residualValue: e.target.value })} />
          </FormField>
          <FormField label="Method"><Input value="Straight line" disabled /></FormField>
        </FormSection>

        {/* What will actually happen, before it happens. */}
        {amount > 0 && (
          <div className="rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-xs text-sky-900 space-y-1">
            <div className="flex items-start gap-1.5"><Info className="w-3.5 h-3.5 mt-0.5 shrink-0" />
              <span className="font-medium">What this will record</span></div>
            <div>Investment value <strong>{gh(amount)}</strong></div>
            <div>Cash out now <strong>{gh(paid)}</strong>{owing > 0 && <> · owed to the supplier <strong>{gh(owing)}</strong></>}</div>
            <div>Charged against this period&apos;s profit <strong>{gh(0)}</strong></div>
            {monthly > 0 && <div>Depreciation <strong>{gh(monthly)}</strong> a month for {life} months</div>}
            {!f.inServiceDate && <div className="text-amber-800">No in-service date — it will be saved as not in service and will not depreciate yet.</div>}
          </div>
        )}

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className="bg-violet-600 hover:bg-violet-700" onClick={save} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Record investment
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function EditDialog({ asset, onClose, categories, onSaved, onCorrectOriginalCost }: {
  asset: HotelAssetView | null; onClose: () => void
  categories: HotelAssetCategoryView[]; onSaved: () => Promise<void> | void
  /** Hands the investment to the correction workflow, which is not an edit. */
  onCorrectOriginalCost: (a: HotelAssetView) => void
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [f, setF] = useState<any>({})
  const [saving, setSaving] = useState(false)
  useEffect(() => {
    if (asset) setF({
      assetName: asset.assetName, assetCategoryId: asset.assetCategoryId ?? "",
      description: asset.description ?? "", location: asset.location ?? "",
      serialNumber: asset.serialNumber ?? "", notes: asset.notes ?? "",
      inServiceDate: (asset.inServiceDate ?? "").split("T")[0],
      usefulLifeMonths: asset.usefulLifeMonths ?? "", residualValue: asset.residualValue,
    })
  }, [asset])

  // Once a month has been charged, changing the life or the in-service date
  // would silently invalidate every month already posted, so the server refuses.
  const locked = (asset?.depreciationEntries ?? 0) > 0

  const save = async (setFinancials: boolean) => {
    if (!asset) return
    setSaving(true)
    try {
      await updateHotelAssetView(asset.capitalAssetId, {
        assetName: f.assetName, assetCategoryId: f.assetCategoryId ? Number(f.assetCategoryId) : null,
        description: f.description || null, location: f.location || null,
        serialNumber: f.serialNumber || null, notes: f.notes || null,
        inServiceDate: setFinancials ? (f.inServiceDate || null) : null,
        usefulLifeMonths: setFinancials ? (Number(f.usefulLifeMonths) || null) : null,
        residualValue: setFinancials ? (Number(f.residualValue) || 0) : null,
        setFinancials,
      })
      toast({ title: "Investment updated" })
      onClose(); await onSaved()
    } catch (e: any) {
      toast({ title: "Could not update the investment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!asset} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>Edit {asset?.assetName}</DialogTitle></DialogHeader>
        <FormSection title="Details">
          <FormField label="Investment name"><Input value={f.assetName ?? ""} onChange={(e) => setF({ ...f, assetName: e.target.value })} /></FormField>
          <FormField label="Category">
            <Select value={f.assetCategoryId ? String(f.assetCategoryId) : ""} onValueChange={(v) => setF({ ...f, assetCategoryId: v })}>
              <SelectTrigger><SelectValue placeholder="Choose a category" /></SelectTrigger>
              <SelectContent>
                {categories.map((c) => (
                  <SelectItem key={c.assetCategoryId} value={String(c.assetCategoryId)}>{c.categoryName}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Location"><Input value={f.location ?? ""} onChange={(e) => setF({ ...f, location: e.target.value })} /></FormField>
          <FormField label="Serial number"><Input value={f.serialNumber ?? ""} onChange={(e) => setF({ ...f, serialNumber: e.target.value })} /></FormField>
          <FormField label="Acquired" hint="Set when the investment was recorded and not editable here.">
            <Input value={fmtDateTime(asset?.acquisitionDate, asset ?? undefined)} disabled />
          </FormField>
          <FormField label="Investment number"><Input value={asset?.assetNumber ?? ""} disabled /></FormField>
          <FormField label="Description" full>
            <Textarea rows={2} value={f.description ?? ""} onChange={(e) => setF({ ...f, description: e.target.value })} />
          </FormField>
          <FormField label="Notes" full>
            <Textarea rows={2} value={f.notes ?? ""} onChange={(e) => setF({ ...f, notes: e.target.value })} />
          </FormField>
        </FormSection>

        <FormSection title="Depreciation">
          <FormField label="In-service date">
            <Input type="date" disabled={locked} value={f.inServiceDate ?? ""} onChange={(e) => setF({ ...f, inServiceDate: e.target.value })} />
          </FormField>
          <FormField label="Useful life (months)">
            <NumberInput disabled={locked} value={f.usefulLifeMonths ?? ""} onChange={(e) => setF({ ...f, usefulLifeMonths: e.target.value })} />
          </FormField>
          <FormField label="Residual value">
            <NumberInput disabled={locked} value={f.residualValue ?? 0} onChange={(e) => setF({ ...f, residualValue: e.target.value })} />
          </FormField>
          <FormField label="Method"><Input value="Straight line" disabled /></FormField>
        </FormSection>

        <FormSection title="Cost summary">
          <FormField label={ACQUISITION_COST_LABEL} hint={ACQUISITION_COST_TOOLTIP}>
            <Input value={gh(asset?.acquisitionCost ?? 0)} disabled />
          </FormField>
          <FormField label={ADDITIONAL_COST_LABEL} hint={ADDITIONAL_COST_TOOLTIP}>
            <Input value={gh(asset?.additionalCost ?? 0)} disabled />
          </FormField>
          <FormField label={TOTAL_CAPITALIZED_COST_LABEL} hint={TOTAL_CAPITALIZED_COST_TOOLTIP} full>
            <Input value={gh(asset?.totalCapitalizedCost ?? 0)} disabled className="font-semibold" />
          </FormField>
        </FormSection>

        {HOTEL_ASSETS_CAN.correctOriginalCost && <div className="flex flex-wrap items-center gap-2 rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-[11px] text-slate-600">
          <span className="flex-1 min-w-[200px]">
            Spent more on it? Use <strong>Add cost</strong>. Typed the wrong amount in the first
            place? Correct it — the correction is kept on the record with its reason.
          </span>
          <Button size="sm" variant="outline" disabled={(asset?.acquisitionCost ?? 0) <= 0}
                  title={(asset?.acquisitionCost ?? 0) <= 0
                    ? "This investment has no original acquisition to correct — its cost was built up with Add cost."
                    : undefined}
                  onClick={() => { if (asset) { onClose(); onCorrectOriginalCost(asset) } }}>
            <SlidersHorizontal className="w-3.5 h-3.5 mr-1" /> Correct original cost
          </Button>
        </div>}

        {locked && (
          <div className="flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>
              Depreciation has been posted for this investment, so its in-service date, useful life and residual value are
              locked — changing them would make every month already charged wrong. Reverse the depreciation first.
              The name, category and location can still be edited.
            </span>
          </div>
        )}

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className="bg-violet-600 hover:bg-violet-700" onClick={() => save(!locked)} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Save
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function AddCostDialog({ asset, onClose, cashAccounts, onSaved }: {
  asset: HotelAssetView | null; onClose: () => void
  cashAccounts: CashAccount[]; onSaved: () => Promise<void> | void
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [f, setF] = useState<any>({ costDate: today(), paymentMethod: "Cash", treatment: "capitalise" })
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (asset) setF({ costDate: today(), paymentMethod: "Cash", treatment: "capitalise" }) }, [asset])

  // Choosing "operating expense" sends them to the Expenses page that already
  // exists rather than rebuilding it in here.
  const asExpense = f.treatment === "expense"

  const save = async () => {
    if (!asset) return
    const amount = Number(f.amount) || 0
    if (amount <= 0) { toast({ title: "Enter an amount", variant: "destructive" }); return }
    setSaving(true)
    try {
      await addHotelAssetCostView(asset.capitalAssetId, {
        costDate: f.costDate || null, description: f.description || null,
        costCategory: f.costCategory || null, amount,
        supplier: f.supplier || null,
        paymentMethod: f.paymentMethod || "Cash",
        amountPaid: f.amountPaid === "" || f.amountPaid == null ? null : Number(f.amountPaid),
        dueDate: f.dueDate || null,
        cashAccountId: f.cashAccountId ? Number(f.cashAccountId) : null,
      })
      toast({ title: "Cost added", description: "The investment's value has increased. Nothing was charged to profit." })
      onClose(); await onSaved()
    } catch (e: any) {
      toast({ title: "Could not add the cost", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!asset} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add cost to {asset?.assetName}</DialogTitle>
          <DialogDescription>
            Installation, an extraction hood, electrical work — real extra money spent on this investment, added to what
            it is worth. It currently stands at {gh(asset?.totalCapitalizedCost ?? 0)}
            {(asset?.additionalCost ?? 0) > 0
              ? ` (${gh(asset?.acquisitionCost ?? 0)} acquired, ${gh(asset?.additionalCost ?? 0)} added since).`
              : "."}
            {" "}To fix a wrong amount rather than record a new one, use Correct original cost instead.
          </DialogDescription>
        </DialogHeader>
        <FormSection title="How to treat it">
          <FormField label="Cost treatment" full hint={COST_TREATMENT_NOTE}>
            <Select value={f.treatment ?? "capitalise"} onValueChange={(v) => setF({ ...f, treatment: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="capitalise">Capitalise to this investment</SelectItem>
                <SelectItem value="expense">Record as an operating expense</SelectItem>
              </SelectContent>
            </Select>
          </FormField>
        </FormSection>

        {asExpense ? (
          <div className="space-y-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-3 text-xs text-amber-900">
            <div className="flex items-start gap-1.5">
              <Info className="w-3.5 h-3.5 mt-0.5 shrink-0" />
              <span className="font-medium">An operating expense is recorded on the Expenses page</span>
            </div>
            <p>
              It will be charged in full against this period&apos;s profit and will NOT change what this
              investment is worth. Record it there and it behaves exactly like any other bill.
            </p>
            <div className="flex justify-end gap-2 pt-1">
              <Button variant="outline" size="sm" onClick={() => setF({ ...f, treatment: "capitalise" })}>
                Back to capitalising
              </Button>
              <Button size="sm" className="bg-violet-600 hover:bg-violet-700" asChild>
                <Link href="/hotel-expenses">Go to Expenses</Link>
              </Button>
            </div>
          </div>
        ) : (<>
          <FormSection title="Cost">
            <FormField label="Date"><Input type="date" max={today()} value={f.costDate ?? ""} onChange={(e) => setF({ ...f, costDate: e.target.value })} /></FormField>
            <FormField label="Amount"><NumberInput value={f.amount ?? ""} onChange={(e) => setF({ ...f, amount: e.target.value })} /></FormField>
            <FormField label="What it was for"><Input value={f.description ?? ""} onChange={(e) => setF({ ...f, description: e.target.value })} placeholder="Extraction hood" /></FormField>
            <FormField label="Cost type"><Input value={f.costCategory ?? ""} onChange={(e) => setF({ ...f, costCategory: e.target.value })} placeholder="Materials / Labour" /></FormField>
            <FormField label="Supplier / payee"><Input value={f.supplier ?? ""} onChange={(e) => setF({ ...f, supplier: e.target.value })} /></FormField>
            <FormField label="Payment method">
              <Select value={f.paymentMethod ?? "Cash"} onValueChange={(v) => setF({ ...f, paymentMethod: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ASSET_PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Amount paid now" hint="Leave blank if paid in full."><NumberInput value={f.amountPaid ?? ""} onChange={(e) => setF({ ...f, amountPaid: e.target.value })} /></FormField>
            <FormField label="Paid from">
              <CashAccountSelect value={f.cashAccountId ? String(f.cashAccountId) : ""} cashAccounts={cashAccounts}
                                 onChange={(v) => setF({ ...f, cashAccountId: v })} />
            </FormField>
            <FormField label="Balance due date" hint="When the unpaid part falls due.">
              <Input type="date" value={f.dueDate ?? ""} onChange={(e) => setF({ ...f, dueDate: e.target.value })} />
            </FormField>
          </FormSection>
          {(asset?.depreciationEntries ?? 0) > 0 && (
            <div className="flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
              <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
              <span>{COST_LOCKED_BY_DEPRECIATION_NOTE}</span>
            </div>
          )}
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={onClose}>Cancel</Button>
            <Button className="bg-violet-600 hover:bg-violet-700" onClick={save} disabled={saving || (asset?.depreciationEntries ?? 0) > 0}>
              {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Add cost
            </Button>
          </div>
        </>)}
      </DialogContent>
    </Dialog>
  )
}

function DisposeDialog({ asset, onClose, cashAccounts, onSaved }: {
  asset: HotelAssetView | null; onClose: () => void
  cashAccounts: CashAccount[]; onSaved: () => Promise<void> | void
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [f, setF] = useState<any>({ disposalDate: today() })
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (asset) setF({ disposalDate: today() }) }, [asset])

  const save = async () => {
    if (!asset) return
    setSaving(true)
    try {
      await disposeHotelAssetView(asset.capitalAssetId, {
        disposalDate: f.disposalDate || null,
        proceeds: f.proceeds === "" || f.proceeds == null ? null : Number(f.proceeds),
        cashAccountId: f.cashAccountId ? Number(f.cashAccountId) : null,
        notes: f.notes || null,
      })
      toast({ title: "Investment disposed" })
      onClose(); await onSaved()
    } catch (e: any) {
      toast({ title: "Could not dispose the investment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!asset} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="sm:max-w-xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Dispose of {asset?.assetName}</DialogTitle>
          <DialogDescription>
            Its book value today is {gh(asset?.currentBookValue ?? 0)}. Sale proceeds are recorded as money IN and are
            not sales revenue.
          </DialogDescription>
        </DialogHeader>
        <FormSection title="Disposal">
          <FormField label="Date"><Input type="date" max={today()} value={f.disposalDate ?? ""} onChange={(e) => setF({ ...f, disposalDate: e.target.value })} /></FormField>
          <FormField label="Proceeds" hint="Leave blank if nothing was received."><NumberInput value={f.proceeds ?? ""} onChange={(e) => setF({ ...f, proceeds: e.target.value })} /></FormField>
          <FormField label="Received into">
            <CashAccountSelect value={f.cashAccountId ? String(f.cashAccountId) : ""} cashAccounts={cashAccounts}
                               onChange={(v) => setF({ ...f, cashAccountId: v })} />
          </FormField>
          <FormField label="Notes" full>
            <Textarea rows={2} value={f.notes ?? ""} onChange={(e) => setF({ ...f, notes: e.target.value })} />
          </FormField>
        </FormSection>
        <p className="text-[11px] text-slate-500">
          Gain or loss on disposal — the difference between the proceeds and the book value — is not yet calculated.
          It is recorded here as a cash receipt only.
        </p>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className="bg-violet-600 hover:bg-violet-700" onClick={save} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Dispose
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function ReverseDialog({ asset, onClose, onSaved }: {
  asset: HotelAssetView | null; onClose: () => void; onSaved: () => Promise<void> | void
}) {
  const { toast } = useToast()
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (asset) setReason("") }, [asset])

  const save = async () => {
    if (!asset) return
    if (!reason.trim()) { toast({ title: "A reason is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await reverseHotelAssetView(asset.capitalAssetId, reason.trim())
      toast({ title: "Acquisition reversed", description: "Any cash paid has been returned. The record is kept with its reason." })
      onClose(); await onSaved()
    } catch (e: any) {
      toast({ title: "Could not reverse the investment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!asset} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Reverse {asset?.assetName}</DialogTitle>
          <DialogDescription>
            The investment and its costs are kept and marked reversed; any cash paid is returned to its account. This is
            refused if depreciation has been posted or the investment has been disposed of.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <Label className="text-sm">Reason</Label>
          <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)}
                    placeholder="Recorded on the wrong company" />
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button variant="destructive" onClick={save} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Reverse
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

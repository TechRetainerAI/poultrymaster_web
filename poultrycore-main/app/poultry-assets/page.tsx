"use client"

// =============================================================================
// Assets — the poultry Asset Register (migrations 270-273).
//
// "Track major long-term business assets, their cost, depreciation, and current
// book value."
//
// The one thing this page exists to make true: a 600,000 poultry house is money
// the farm STILL OWNS, not a 600,000 hole in last month's profit. It buys with
// the same money rail every bill uses -- cash out, supplier payable, supplier
// payment -- and is simply excluded from profit and depreciated instead.
// =============================================================================

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
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
import { DataPagination } from "@/components/ui/data-pagination"
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
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  listPoultryAssets, listPoultryAssetCategories, getPoultryAssetSummary,
  createPoultryAsset, updatePoultryAsset, addPoultryAssetCost, getPoultryAsset,
  disposePoultryAsset, reversePoultryAsset,
  correctPoultryAssetOriginalCost, reversePoultryAssetCost,
  listPoultryDepreciationDue, generatePoultryDepreciation,
  reversePoultryDepreciation,
  type PoultryCapitalAsset, type PoultryAssetCategory,
  type PoultryCapitalAssetSummary, type PoultryAssetDepreciationDue,
} from "@/lib/api/poultry-assets"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import {
  assetStatusLabel, ASSET_STATUS_CLASS,
  BOOK_VALUE_TOOLTIP,
  ACQUISITION_COST_LABEL, ADDITIONAL_COST_LABEL, TOTAL_CAPITALIZED_COST_LABEL,
  ACQUISITION_COST_TOOLTIP, ADDITIONAL_COST_TOOLTIP, TOTAL_CAPITALIZED_COST_TOOLTIP,
  CORRECT_ORIGINAL_COST_NOTE, CORRECTION_DEPRECIATION_NOTE,
  COST_TREATMENT_NOTE, COST_LOCKED_BY_DEPRECIATION_NOTE,
  DEPRECIATION_CONVENTION_NOTE, DEPRECIATION_NONCASH_NOTE,
} from "@/lib/poultry/financial-classification"
import { DateTimeCell } from "@/components/ui/date-time-cell"
import { fmtDateTime, businessSortValue } from "@/lib/utils/company-datetime"

const STATUSES = ["Draft", "Active", "FullyDepreciated", "Disposed", "Reversed"] as const

const today = () => new Date().toISOString().slice(0, 10)

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
 * sent -- so the panel and this page cannot disagree about a number.
 */
function toDetailsView(a: PoultryCapitalAsset): AssetDetailsView {
  return {
    id: a.poultryCapitalAssetId,
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
      id: c.poultryCapitalAssetCostId,
      costDate: c.costDate, description: c.description, costCategory: c.costCategory,
      amount: c.amount, sourceType: c.sourceType, supplierName: c.supplierName,
      paymentStatus: c.paymentStatus, amountPaid: c.amountPaid, balance: c.balance,
      paymentMethod: c.paymentMethod, dueDate: c.dueDate, cashAccountName: c.cashAccountName,
      expenseId: c.expenseId, expenseAmount: c.expenseAmount, expenseCategory: c.expenseCategory,
      status: c.status, createdBy: c.createdBy, createdAt: c.createdAt,
      reversedBy: c.reversedBy, reversedAt: c.reversedAt, reversalReason: c.reversalReason,
    })),
    depreciation: (a.depreciation ?? []).map<AssetDepreciationRow>((d) => ({
      id: d.poultryAssetDepreciationId,
      periodStart: d.periodStart, periodEnd: d.periodEnd, depreciationDate: d.depreciationDate,
      amount: d.amount, depreciationMethod: d.depreciationMethod, sourceType: d.sourceType,
      status: d.status, expenseId: d.expenseId,
      accumulatedAfter: d.accumulatedAfter, bookValueAfter: d.bookValueAfter,
      createdBy: d.createdBy, createdAt: d.createdAt,
      reversedBy: d.reversedBy, reversedAt: d.reversedAt, reversalReason: d.reversalReason,
    })),
  }
}

export default function PoultryAssetsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [assets, setAssets] = useState<PoultryCapitalAsset[]>([])
  const [categories, setCategories] = useState<PoultryAssetCategory[]>([])
  const [summary, setSummary] = useState<PoultryCapitalAssetSummary | null>(null)
  const [due, setDue] = useState<PoultryAssetDepreciationDue[]>([])
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [search, setSearch] = useState("")
  const [statusFilter, setStatusFilter] = useState("all")
  const [categoryFilter, setCategoryFilter] = useState("all")
  const [sort, setSort] = useState<{ key: string | null; direction: SortDirection }>({ key: "acquisitionDate", direction: "desc" })

  const [newOpen, setNewOpen] = useState(false)
  const [editing, setEditing] = useState<PoultryCapitalAsset | null>(null)
  const [costFor, setCostFor] = useState<PoultryCapitalAsset | null>(null)
  const [disposing, setDisposing] = useState<PoultryCapitalAsset | null>(null)
  const [reversing, setReversing] = useState<PoultryCapitalAsset | null>(null)
  const [depOpen, setDepOpen] = useState(false)

  // ---- the expanded row -------------------------------------------------
  //
  // Collapsed by default, and the full history is fetched only when a row is
  // actually opened. The register can hold hundreds of investments and each
  // detail is three result sets; loading them all up front to satisfy the few
  // that get expanded would make the LIST slow to answer a question nobody
  // asked. Once fetched it is kept, so closing and reopening is instant.
  const [expanded, setExpanded] = useState<Set<number>>(new Set())
  const [details, setDetails] = useState<Record<number, PoultryCapitalAsset>>({})
  const [detailBusy, setDetailBusy] = useState<Set<number>>(new Set())
  const [detailError, setDetailError] = useState<Record<number, string>>({})

  const [correcting, setCorrecting] = useState<PoultryCapitalAsset | null>(null)
  const [viewingCost, setViewingCost] = useState<{ assetId: number; row: AssetCostRow } | null>(null)
  const [reversingCost, setReversingCost] = useState<{ assetId: number; row: AssetCostRow } | null>(null)
  const [reversingDep, setReversingDep] = useState<{ assetId: number; id: number } | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [a, c, s, d, ca] = await Promise.all([
        listPoultryAssets(),
        listPoultryAssetCategories(),
        getPoultryAssetSummary(),
        listPoultryDepreciationDue().catch(() => []),
        listPoultryCashAccounts().catch(() => [] as PoultryCashAccount[]),
      ])
      setAssets(a); setCategories(c); setSummary(s); setDue(d)
      setCashAccounts((ca as PoultryCashAccount[]).filter((x) => x.isActive))
    } catch (e: any) {
      toast({ title: "Could not load capital investments", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }, [toast])

  useEffect(() => { void load() }, [load])

  const loadDetail = useCallback(async (id: number) => {
    setDetailBusy((prev) => new Set(prev).add(id))
    setDetailError((prev) => { const n = { ...prev }; delete n[id]; return n })
    try {
      const full = await getPoultryAsset(id)
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

  /**
   * After anything that changes an investment: reload the list AND any detail
   * that is currently open. Reloading only the list would leave an expanded
   * history showing the cost that was just reversed.
   */
  const reloadWithOpenDetails = useCallback(async () => {
    await load()
    await Promise.all([...expanded].map((id) => loadDetail(id)))
  }, [load, expanded, loadDetail])

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return assets.filter((a) => {
      if (statusFilter !== "all" && a.status !== statusFilter) return false
      if (categoryFilter !== "all" && String(a.poultryAssetCategoryId ?? "") !== categoryFilter) return false
      if (!q) return true
      return [a.assetName, a.assetNumber, a.categoryName, a.location, a.serialNumber, a.supplierName]
        .some((v) => (v ?? "").toLowerCase().includes(q))
    })
  }, [assets, search, statusFilter, categoryFilter])

  const sorted = useMemo(
    () => sortData(filtered, sort.key, sort.direction, (a: PoultryCapitalAsset, k: string) =>
      k === "acquisitionDate" ? businessSortValue(a.acquisitionDate, a) : (a as any)[k]),
    [filtered, sort],
  )
  const pg = usePagination(sorted)

  const dueTotal = due.reduce((s, d) => s + d.amountDue, 0)
  const dueMonths = due.reduce((s, d) => s + d.monthsDue, 0)

  const runDepreciation = async () => {
    setSaving(true)
    try {
      const res = await generatePoultryDepreciation({})
      toast({
        title: res.entriesCreated > 0 ? "Depreciation posted" : "Nothing was due",
        description: res.entriesCreated > 0
          ? `${res.entriesCreated} month(s) across ${res.assetsProcessed} asset(s), ${gh(res.totalAmount)} charged to Profit & Loss. No cash moved.`
          : "Every capital investment is up to date.",
      })
      setDepOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Could not generate depreciation", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  if (activeFarmType && activeFarmType !== "Poultry") {
    return <div className="p-6 text-sm text-slate-600">
      Capital investments are a poultry company feature. <Link href="/dashboard" className="underline">Back to dashboard</Link>
    </div>
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 min-w-0 overflow-y-auto p-4 sm:p-6 space-y-4">
          <div className="flex flex-wrap items-start gap-3">
            <div>
              <h1 className="text-lg font-semibold text-slate-900">Capital Investments/Assets</h1>
              <p className="text-xs text-slate-500">
                Track major long-term business investments, their cost, depreciation, and current book value.
              </p>
            </div>
            <div className="ml-auto flex flex-wrap gap-2">
              <Button variant="outline" onClick={() => setDepOpen(true)} disabled={loading}>
                <CalendarClock className="w-4 h-4 mr-1" />
                Depreciation
                {dueMonths > 0 && (
                  <Badge className="ml-2 bg-amber-100 text-amber-800 hover:bg-amber-100">{dueMonths} due</Badge>
                )}
              </Button>
              <Button onClick={() => setNewOpen(true)}><Plus className="w-4 h-4 mr-1" /> New investment</Button>
            </div>
          </div>

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
                    <SelectItem key={c.poultryAssetCategoryId} value={String(c.poultryAssetCategoryId)}>
                      {c.categoryName}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </>}
          />

          {/* p-0 under lg so the scorecards run the full width of main, the way
              the /poultry-daily-closing cards do. The list supplies its own
              gutter; the Card padding on top of it left them visibly inset.
              Desktop keeps the padding for the table. */}
          <Card><CardContent className="p-0 lg:p-4">
            {loading ? (
              <div className="py-10 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-slate-400" /></div>
            ) : (
              <>
                <MobileCardList
                  striped
                  defaultOpen
                  items={pg.pageItems}
                  getKey={(a) => a.poultryCapitalAssetId}
                  primary={(a) => (
                    <Link href={`/poultry-assets/${a.poultryCapitalAssetId}`} className="hover:underline">
                      {a.assetName}
                    </Link>
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
                  /* Book value first: it is the figure the page exists to give,
                     and cost beside it is what makes it mean something. */
                  highlights={(a) => [
                    { label: "Book value", value: gh(a.currentBookValue), accent: "emerald", wide: true },
                    { label: "Capitalised cost", value: gh(a.totalCapitalizedCost), accent: "blue" },
                    { label: "Depreciation", value: a.accumulatedDepreciation > 0 ? gh(a.accumulatedDepreciation) : "—", accent: "amber" },
                  ]}
                  details={(a) => [
                    { label: "Acquired", value: fmtDateTime(a.acquisitionDate, a) || "—" },
                    // The split, said on the card too: the whole point is that
                    // one number is not allowed to stand for two ideas.
                    { label: "Original acquisition", value: gh(a.acquisitionCost) },
                    { label: "Added since", value: a.additionalCost > 0 ? gh(a.additionalCost) : "—" },
                    {
                      label: "Useful life",
                      value: a.usefulLifeMonths
                        ? `${a.usefulLifeMonths} months${a.monthlyDepreciation ? ` · ${gh(a.monthlyDepreciation)}/month` : ""}`
                        : "Not set",
                    },
                  ]}
                  actions={(a) => (
                    a.status === "Reversed" ? null : (<>
                      {/* On a phone the chevron has nowhere to live, so the same
                          expansion is a full-width button above the rest. */}
                      <Button size="sm" variant="outline" className="basis-full h-10"
                              onClick={() => toggleExpanded(a.poultryCapitalAssetId)}>
                        {expanded.has(a.poultryCapitalAssetId)
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
                      {a.status !== "Disposed" && a.acquisitionCost > 0 && (
                        <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => setCorrecting(a)}>
                          <SlidersHorizontal className="w-4 h-4 mr-1" /> Correct cost
                        </Button>
                      )}
                      {a.status !== "Disposed" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700" onClick={() => setDisposing(a)}>
                          <PackageMinus className="w-4 h-4 mr-1" /> Dispose
                        </Button>
                      )}
                      {/* Same rule as the table: offered only where the server
                          can actually accept it. */}
                      {a.depreciationEntries === 0 && a.status !== "Disposed" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600" onClick={() => setReversing(a)}>
                          <Undo2 className="w-4 h-4 mr-1" /> Reverse
                        </Button>
                      )}
                    </>)
                  )}
                  extra={(a) => (
                    expanded.has(a.poultryCapitalAssetId) ? (
                      <div className="-mx-1 rounded-md border border-slate-200 bg-slate-50">
                        <AssetDetailsPanel
                          view={details[a.poultryCapitalAssetId]
                            ? toDetailsView(details[a.poultryCapitalAssetId])
                            : null}
                          loading={detailBusy.has(a.poultryCapitalAssetId)}
                          error={detailError[a.poultryCapitalAssetId] ?? null}
                          onRetry={() => void loadDetail(a.poultryCapitalAssetId)}
                          term="investment"
                          notes={DETAIL_NOTES}
                          fmt={gh}
                          detailHref={"/poultry-assets/" + a.poultryCapitalAssetId}
                          expensesHref="/expenses"
                          onEdit={() => setEditing(a)}
                          onAddCost={() => setCostFor(a)}
                          onCorrectOriginalCost={() => setCorrecting(a)}
                          onViewCost={(row) => setViewingCost({ assetId: a.poultryCapitalAssetId, row })}
                          onReverseCost={(row) => setReversingCost({ assetId: a.poultryCapitalAssetId, row })}
                          onReverseDepreciation={(row) =>
                            setReversingDep({ assetId: a.poultryCapitalAssetId, id: row.id })}
                        />
                      </div>
                    ) : null
                  )}
                  emptyState={
                    <div className="py-8 text-center text-slate-500 text-sm px-4">
                      No capital investments recorded. A poultry house, a vehicle or a feed mixer belongs here rather
                      than on the Expenses page.
                    </div>
                  }
                  pagination={pg.paginationProps}
                  desktopTable={
                <div className="overflow-x-auto"><Table className="min-w-[940px]">
                  <TableHeader><TableRow>
                    {/* The expansion control gets its own column, separated from
                        the transactional icons at the other end of the row: one
                        reveals an explanation, the others move money. */}
                    <TableHead className="w-8 px-1" />
                    {(() => { const onSort = (k: string) => setSort((s) => toggleSort(k, s.key, s.direction))
                      const cs = sort.key, cd = sort.direction
                      return (<>
                        <SortableHeader label="Investment #" sortKey="assetNumber" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <SortableHeader label="Investment" sortKey="assetName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <SortableHeader label="Category" sortKey="categoryName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        <SortableHeader label="Acquired" sortKey="acquisitionDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                        {/* §5. "Cost" was the TOTAL wearing the acquisition's
                            name. Expanding the row says which is which. */}
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
                        No capital investments recorded. A poultry house, a vehicle or a feed mixer belongs here rather than on the Expenses page.
                      </TableCell></TableRow>
                    ) : pg.pageItems.map((a) => {
                      const open = expanded.has(a.poultryCapitalAssetId)
                      return (
                      <Fragment key={a.poultryCapitalAssetId}>
                      <TableRow className={cn(a.status === "Reversed" && "opacity-60")}>
                        <TableCell className="px-1">
                          <button
                            type="button"
                            onClick={() => toggleExpanded(a.poultryCapitalAssetId)}
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
                          <Link href={`/poultry-assets/${a.poultryCapitalAssetId}`} className="hover:underline">
                            {a.assetName}
                          </Link>
                          {a.location && <div className="text-[11px] text-slate-500">{a.location}</div>}
                        </TableCell>
                        <TableCell className="text-sm">{a.categoryName ?? "—"}</TableCell>
                        <TableCell className="align-top text-sm">
                          <DateTimeCell value={a.acquisitionDate} row={a} />
                        </TableCell>
                        <TableCell className="text-right tabular-nums" title={TOTAL_CAPITALIZED_COST_TOOLTIP}>
                          {gh(a.totalCapitalizedCost)}
                          {a.additionalCost > 0 && (
                            <div className="text-[11px] font-normal text-slate-500">
                              {gh(a.acquisitionCost)} + {gh(a.additionalCost)} added
                            </div>
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
                            {/* Correcting what something was recorded as costing
                                is a different act from spending more on it, so
                                it is a different button. */}
                            {a.status !== "Disposed" && a.acquisitionCost > 0 && (
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
                            {/* Reversal is offered only where it can succeed: the
                                server refuses once depreciation is posted or a
                                supplier has been paid, and a button that always
                                errors is worse than no button. */}
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
                              view={details[a.poultryCapitalAssetId]
                                ? toDetailsView(details[a.poultryCapitalAssetId])
                                : null}
                              loading={detailBusy.has(a.poultryCapitalAssetId)}
                              error={detailError[a.poultryCapitalAssetId] ?? null}
                              onRetry={() => void loadDetail(a.poultryCapitalAssetId)}
                              term="investment"
                              notes={DETAIL_NOTES}
                              fmt={gh}
                              detailHref={"/poultry-assets/" + a.poultryCapitalAssetId}
                              expensesHref="/expenses"
                              onEdit={() => setEditing(a)}
                              onAddCost={() => setCostFor(a)}
                              onCorrectOriginalCost={() => setCorrecting(a)}
                              onViewCost={(row) => setViewingCost({ assetId: a.poultryCapitalAssetId, row })}
                              onReverseCost={(row) => setReversingCost({ assetId: a.poultryCapitalAssetId, row })}
                              onReverseDepreciation={(row) =>
                                setReversingDep({ assetId: a.poultryCapitalAssetId, id: row.id })}
                            />
                          </TableCell>
                        </TableRow>
                      )}
                      </Fragment>
                      )})}
                  </TableBody>
                </Table></div>
                  }
                />
              </>
            )}
          </CardContent></Card>

          <p className="text-[11px] text-slate-500">
            Capital investments affect Cash Flow when they are paid for and appear on Supplier Balances when they are bought
            on credit. They are not charged against profit in the month they are bought — their cost reaches Profit &amp;
            Loss over time through depreciation.
          </p>

          <AssetFormDialog
            open={newOpen} onOpenChange={setNewOpen} categories={categories} cashAccounts={cashAccounts}
            saving={saving} setSaving={setSaving} onSaved={load}
          />
          <EditDialog asset={editing} onClose={() => setEditing(null)} categories={categories} onSaved={load}
                      onCorrectOriginalCost={(a) => setCorrecting(a)} />
          <AddCostDialog asset={costFor} onClose={() => setCostFor(null)} cashAccounts={cashAccounts} onSaved={load} />
          <DisposeDialog asset={disposing} onClose={() => setDisposing(null)} cashAccounts={cashAccounts} onSaved={load} />
          <ReverseDialog asset={reversing} onClose={() => setReversing(null)} onSaved={load} />

          {/* §18. Correcting what something was recorded as costing. Not Add
              cost, and not an editable field -- see the dialog's own header. */}
          <CorrectOriginalCostDialog
            asset={correcting ? {
              id: correcting.poultryCapitalAssetId,
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
              const id = correcting!.poultryCapitalAssetId
              await correctPoultryAssetOriginalCost(id, input)
              toast({
                title: "Original cost corrected",
                description: "The correction is on the cost history with your reason. Depreciation already posted is unchanged.",
              })
              await reloadWithOpenDetails()
            }}
          />

          <CostDetailDialog
            cost={viewingCost?.row ?? null}
            assetName={assets.find((a) => a.poultryCapitalAssetId === viewingCost?.assetId)?.assetName}
            onClose={() => setViewingCost(null)}
            fmt={gh}
            term="investment"
            expensesHref="/expenses"
            onReverse={(row) => {
              setViewingCost(null)
              setReversingCost({ assetId: viewingCost!.assetId, row })
            }}
            reverseDisabledReason={
              (assets.find((a) => a.poultryCapitalAssetId === viewingCost?.assetId)?.depreciationEntries ?? 0) > 0
                ? COST_LOCKED_BY_DEPRECIATION_NOTE
                : null
            }
          />

          {/* §24. The row is kept and marked reversed; nothing is deleted. */}
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
            /* Errors are deliberately NOT caught: PromptDialog shows a
               failed submit inline and keeps the dialog open, which is better
               than closing it and leaving only a toast behind. */
            onSubmit={async (reason) => {
              const target = reversingCost!
              await reversePoultryAssetCost(target.assetId, target.row.id, reason)
              toast({ title: "Cost reversed", description: "The entry is kept with its reason." })
              setReversingCost(null)
              await reloadWithOpenDetails()
            }}
          />

          {/* Reversing a posted charge, from inside the history that shows it.
              The month is NOT reopened to the generator -- see the API note. */}
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
              await reversePoultryDepreciation(target.id, reason)
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
            <DialogContent className="max-w-2xl">
              <DialogHeader>
                <DialogTitle>Depreciation</DialogTitle>
                <DialogDescription>{DEPRECIATION_NONCASH_NOTE}</DialogDescription>
              </DialogHeader>
              {due.length === 0 ? (
                <p className="text-sm text-slate-600 py-4">Every capital investment is up to date. Nothing is due.</p>
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
                          <TableRow key={d.poultryCapitalAssetId}>
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
                    <Button onClick={runDepreciation} disabled={saving}>
                      {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}
                      Post depreciation
                    </Button>
                  </div>
                </div>
              )}
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
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

/**
 * Recording an asset. The cost is OPTIONAL on purpose: a house that will be
 * built starts at nothing and grows through "Add cost", which is §12's
 * construction project without a second set of screens.
 */
function AssetFormDialog({ open, onOpenChange, categories, cashAccounts, saving, setSaving, onSaved }: {
  open: boolean; onOpenChange: (o: boolean) => void
  categories: PoultryAssetCategory[]; cashAccounts: PoultryCashAccount[]
  saving: boolean; setSaving: (b: boolean) => void; onSaved: () => Promise<void> | void
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [f, setF] = useState<any>({ acquisitionDate: today(), residualValue: 0, paymentMethod: "Cash" })

  useEffect(() => { if (open) setF({ acquisitionDate: today(), residualValue: 0, paymentMethod: "Cash" }) }, [open])

  const cat = categories.find((c) => String(c.poultryAssetCategoryId) === String(f.assetCategoryId))
  const amount = Number(f.amount) || 0
  const paid = f.amountPaid === undefined || f.amountPaid === null || f.amountPaid === "" ? amount : Number(f.amountPaid)
  const owing = Math.max(amount - paid, 0)
  const life = Number(f.usefulLifeMonths) || 0
  const monthly = life > 0 ? Math.round(((amount - (Number(f.residualValue) || 0)) / life) * 100) / 100 : 0

  const save = async () => {
    if (!f.assetName?.trim()) { toast({ title: "Name the investment", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createPoultryAsset({
        assetName: f.assetName, assetCategoryId: f.assetCategoryId ? Number(f.assetCategoryId) : null,
        description: f.description || null,
        acquisitionDate: f.acquisitionDate || null, inServiceDate: f.inServiceDate || null,
        amount: amount > 0 ? amount : null,
        residualValue: Number(f.residualValue) || 0,
        usefulLifeMonths: life > 0 ? life : null,
        supplier: f.supplier || null, supplierId: f.supplierId ? Number(f.supplierId) : null,
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
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
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
                   placeholder="Poultry House 4" />
          </FormField>
          <FormField label="Category">
            <Select value={f.assetCategoryId ? String(f.assetCategoryId) : ""}
                    onValueChange={(v) => {
                      const c = categories.find((x) => String(x.poultryAssetCategoryId) === v)
                      setF({ ...f, assetCategoryId: v, usefulLifeMonths: f.usefulLifeMonths || c?.defaultUsefulLifeMonths || "" })
                    }}>
              <SelectTrigger><SelectValue placeholder="Choose a category" /></SelectTrigger>
              <SelectContent>
                {categories.map((c) => (
                  <SelectItem key={c.poultryAssetCategoryId} value={String(c.poultryAssetCategoryId)}>{c.categoryName}</SelectItem>
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
            <Input type="date" value={f.acquisitionDate ?? ""} onChange={(e) => setF({ ...f, acquisitionDate: e.target.value })} />
          </FormField>
          <FormField label="Cost" hint="Leave blank for an investment you will build up cost by cost.">
            <NumberInput value={f.amount ?? ""} onChange={(e) => setF({ ...f, amount: e.target.value })} />
          </FormField>
          <FormField label="Supplier / payee"><Input value={f.supplier ?? ""} onChange={(e) => setF({ ...f, supplier: e.target.value })} /></FormField>
          <FormField label="Amount paid now" hint="Leave blank if paid in full.">
            <NumberInput value={f.amountPaid ?? ""} onChange={(e) => setF({ ...f, amountPaid: e.target.value })} />
          </FormField>
          <FormField label="Paid from">
            <Select value={f.cashAccountId ? String(f.cashAccountId) : ""} onValueChange={(v) => setF({ ...f, cashAccountId: v })}>
              <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
              <SelectContent>
                {cashAccounts.map((a) => (
                  <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>
                ))}
              </SelectContent>
            </Select>
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
          <Button onClick={save} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Record investment
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function EditDialog({ asset, onClose, categories, onSaved, onCorrectOriginalCost }: {
  asset: PoultryCapitalAsset | null; onClose: () => void
  categories: PoultryAssetCategory[]; onSaved: () => Promise<void> | void
  /** Hands the investment to the correction workflow, which is not an edit. */
  onCorrectOriginalCost: (a: PoultryCapitalAsset) => void
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [f, setF] = useState<any>({})
  const [saving, setSaving] = useState(false)
  useEffect(() => {
    if (asset) setF({
      assetName: asset.assetName, assetCategoryId: asset.poultryAssetCategoryId ?? "",
      description: asset.description ?? "", location: asset.location ?? "",
      serialNumber: asset.serialNumber ?? "", notes: asset.notes ?? "",
      inServiceDate: (asset.inServiceDate ?? "").split("T")[0],
      usefulLifeMonths: asset.usefulLifeMonths ?? "", residualValue: asset.residualValue,
    })
  }, [asset])

  // §58. Once a month has been charged, changing the life or the in-service date
  // would silently invalidate every month already posted, so the server refuses.
  const locked = (asset?.depreciationEntries ?? 0) > 0

  const save = async (setFinancials: boolean) => {
    if (!asset) return
    setSaving(true)
    try {
      await updatePoultryAsset(asset.poultryCapitalAssetId, {
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
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>Edit {asset?.assetName}</DialogTitle></DialogHeader>
        <FormSection title="Details">
          <FormField label="Investment name"><Input value={f.assetName ?? ""} onChange={(e) => setF({ ...f, assetName: e.target.value })} /></FormField>
          <FormField label="Category">
            <Select value={f.assetCategoryId ? String(f.assetCategoryId) : ""} onValueChange={(v) => setF({ ...f, assetCategoryId: v })}>
              <SelectTrigger><SelectValue placeholder="Choose a category" /></SelectTrigger>
              <SelectContent>
                {categories.map((c) => (
                  <SelectItem key={c.poultryAssetCategoryId} value={String(c.poultryAssetCategoryId)}>{c.categoryName}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Location"><Input value={f.location ?? ""} onChange={(e) => setF({ ...f, location: e.target.value })} /></FormField>
          <FormField label="Serial number"><Input value={f.serialNumber ?? ""} onChange={(e) => setF({ ...f, serialNumber: e.target.value })} /></FormField>
          {/* Read-only: sppoultrycapitalasset_update takes no acquisition date,
              so an editable box here would silently discard what you typed. */}
          <FormField label="Acquired" hint="Set when the investment was recorded and not editable here.">
            <Input value={fmtDateTime(asset?.acquisitionDate, asset ?? undefined)} disabled />
          </FormField>
          <FormField label="Investment number"><Input value={asset?.assetNumber ?? ""} disabled /></FormField>
          {/* Description is captured when the asset is recorded; without this
              field it could never be read back or corrected. */}
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

        {/* §11. What used to stand here was ONE read-only box labelled "Original
            cost" showing the TOTAL, with a hint telling you to change it with
            Add cost -- which would have made a mistyped 130,000 into 143,000.
            Three separate figures, and a button that corrects rather than adds. */}
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

        <div className="flex flex-wrap items-center gap-2 rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-[11px] text-slate-600">
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
        </div>

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
          <Button onClick={() => save(!locked)} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Save
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function AddCostDialog({ asset, onClose, cashAccounts, onSaved }: {
  asset: PoultryCapitalAsset | null; onClose: () => void
  cashAccounts: PoultryCashAccount[]; onSaved: () => Promise<void> | void
}) {
  const { toast } = useToast()
  const gh = useFmt()
  const [f, setF] = useState<any>({ costDate: today(), paymentMethod: "Cash", treatment: "capitalise" })
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (asset) setF({ costDate: today(), paymentMethod: "Cash", treatment: "capitalise" }) }, [asset])

  // §17. The distinction this form cannot make for the user, made explicit.
  // Choosing "operating expense" does NOT rebuild the Expenses workflow in here
  // -- it sends them to the one that already exists, because a second way to
  // record an expense is a second set of rules to keep in step.
  const asExpense = f.treatment === "expense"

  const save = async () => {
    if (!asset) return
    const amount = Number(f.amount) || 0
    if (amount <= 0) { toast({ title: "Enter an amount", variant: "destructive" }); return }
    setSaving(true)
    try {
      await addPoultryAssetCost(asset.poultryCapitalAssetId, {
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
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add cost to {asset?.assetName}</DialogTitle>
          <DialogDescription>
            Cement, roofing, labour — real extra money spent on this investment, added to what it is
            worth. It currently stands at {gh(asset?.totalCapitalizedCost ?? 0)}
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
              <Button size="sm" asChild>
                <Link href="C:/Program Files/Git/expenses">Go to Expenses</Link>
              </Button>
            </div>
          </div>
        ) : (<>
        <FormSection title="Cost">
          <FormField label="Date"><Input type="date" value={f.costDate ?? ""} onChange={(e) => setF({ ...f, costDate: e.target.value })} /></FormField>
          <FormField label="Amount"><NumberInput value={f.amount ?? ""} onChange={(e) => setF({ ...f, amount: e.target.value })} /></FormField>
          <FormField label="What it was for"><Input value={f.description ?? ""} onChange={(e) => setF({ ...f, description: e.target.value })} placeholder="Roofing sheets" /></FormField>
          <FormField label="Cost type"><Input value={f.costCategory ?? ""} onChange={(e) => setF({ ...f, costCategory: e.target.value })} placeholder="Materials / Labour" /></FormField>
          <FormField label="Supplier / payee"><Input value={f.supplier ?? ""} onChange={(e) => setF({ ...f, supplier: e.target.value })} /></FormField>
          {/* The acquisition form offers this, so adding a cost must too --
              otherwise a cost can only ever be entered as cash. */}
          <FormField label="Payment method">
            <Select value={f.paymentMethod ?? "Cash"} onValueChange={(v) => setF({ ...f, paymentMethod: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {["Cash", "MoMo", "Bank", "Credit"].map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
              </SelectContent>
            </Select>
          </FormField>
          <FormField label="Amount paid now" hint="Leave blank if paid in full."><NumberInput value={f.amountPaid ?? ""} onChange={(e) => setF({ ...f, amountPaid: e.target.value })} /></FormField>
          <FormField label="Paid from">
            <Select value={f.cashAccountId ? String(f.cashAccountId) : ""} onValueChange={(v) => setF({ ...f, cashAccountId: v })}>
              <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
              <SelectContent>
                {cashAccounts.map((a) => (
                  <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormField>
          {/* save() already sends dueDate; without this field it was always null,
              so a cost left part-paid had no due date on Supplier Balances. */}
          <FormField label="Balance due date" hint="When the unpaid part falls due.">
            <Input type="date" value={f.dueDate ?? ""} onChange={(e) => setF({ ...f, dueDate: e.target.value })} />
          </FormField>
        </FormSection>
        {/* The one refusal a user is most likely to hit here, said before they
            fill the form in rather than after they press Save. */}
        {(asset?.depreciationEntries ?? 0) > 0 && (
          <div className="flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>{COST_LOCKED_BY_DEPRECIATION_NOTE}</span>
          </div>
        )}
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={save} disabled={saving || (asset?.depreciationEntries ?? 0) > 0}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Add cost
          </Button>
        </div>
        </>)}
      </DialogContent>
    </Dialog>
  )
}

function DisposeDialog({ asset, onClose, cashAccounts, onSaved }: {
  asset: PoultryCapitalAsset | null; onClose: () => void
  cashAccounts: PoultryCashAccount[]; onSaved: () => Promise<void> | void
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
      await disposePoultryAsset(asset.poultryCapitalAssetId, {
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
      <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Dispose of {asset?.assetName}</DialogTitle>
          <DialogDescription>
            Its book value today is {gh(asset?.currentBookValue ?? 0)}. Sale proceeds are recorded as money IN and are
            not sales revenue.
          </DialogDescription>
        </DialogHeader>
        <FormSection title="Disposal">
          <FormField label="Date"><Input type="date" value={f.disposalDate ?? ""} onChange={(e) => setF({ ...f, disposalDate: e.target.value })} /></FormField>
          <FormField label="Proceeds" hint="Leave blank if nothing was received."><NumberInput value={f.proceeds ?? ""} onChange={(e) => setF({ ...f, proceeds: e.target.value })} /></FormField>
          <FormField label="Received into">
            <Select value={f.cashAccountId ? String(f.cashAccountId) : ""} onValueChange={(v) => setF({ ...f, cashAccountId: v })}>
              <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
              <SelectContent>
                {cashAccounts.map((a) => (
                  <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>
                ))}
              </SelectContent>
            </Select>
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
          <Button onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}Dispose</Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function ReverseDialog({ asset, onClose, onSaved }: {
  asset: PoultryCapitalAsset | null; onClose: () => void; onSaved: () => Promise<void> | void
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
      await reversePoultryAsset(asset.poultryCapitalAssetId, reason.trim())
      toast({ title: "Acquisition reversed", description: "Any cash paid has been returned. The record is kept with its reason." })
      onClose(); await onSaved()
    } catch (e: any) {
      toast({ title: "Could not reverse the investment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!asset} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Reverse {asset?.assetName}</DialogTitle>
          <DialogDescription>
            The investment and its costs are kept and marked reversed; any cash paid is returned to its account. This is
            refused if depreciation has been posted or a supplier payment has been recorded against it.
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

"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { TRACKER_PAGE_SIZE_DEFAULT, TRACKER_PAGE_SIZE_OPTIONS } from "@/components/ui/data-pagination"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { FlowBreakdownCard } from "@/components/cash/flow-breakdown-card"
import { groupLedgerBy, groupLedgerByType, FEED_MOVE_LABELS } from "@/lib/utils/ledger-breakdown"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Label } from "@/components/ui/label"
import { Wheat, RefreshCw, Copy, Plus, Pencil, Trash2, ChevronDown, ChevronUp } from "lucide-react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { getFeedUsages, type FeedUsage } from "@/lib/api/feed-usage"
import { getFlocks, type Flock } from "@/lib/api/flock"
import {
  listPoultryRawMaterialItems, listPoultryRawMaterialPurchases,
  listPoultryRawMaterialUsageHistory, listPoultryRawMaterialAdjustments,
  type PoultryRawMaterialItem, type PoultryRawMaterialPurchase,
  type PoultryRawMaterialUsage, type PoultryRawMaterialAdjustment,
} from "@/lib/api/poultry-inventory"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { formatDateShort, cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { buildFeedStockLedger, type FeedLedgerRow } from "@/lib/utils/feed-ledger"
import { useFmt } from "@/lib/currency"
import { recognizedCostNote } from "@/lib/poultry/cost-recognition"
import {
  getFeedInventoryAdjustments,
  createFeedInventoryAdjustment,
  updateFeedInventoryAdjustment,
  deleteFeedInventoryAdjustment,
  type FeedInventoryAdjustment,
} from "@/lib/api/feed-inventory-adjustment"


const ADJ_TYPES = [
  { value: "Correction", label: "Correction" },
  { value: "Stocktake", label: "Stocktake" },
  { value: "OpeningBalance", label: "Opening balance" },
] as const

type AdjType = (typeof ADJ_TYPES)[number]["value"]

export default function FeedTrackerPage() {
  const router = useRouter()
  const { toast } = useToast()
  const isMobile = useIsMobile()
  const [usages, setUsages] = useState<FeedUsage[]>([])
  const [rmItems, setRmItems] = useState<PoultryRawMaterialItem[]>([])
  const [rmPurchases, setRmPurchases] = useState<PoultryRawMaterialPurchase[]>([])
  const [rmUsage, setRmUsage] = useState<PoultryRawMaterialUsage[]>([])
  const [rmAdjustments, setRmAdjustments] = useState<PoultryRawMaterialAdjustment[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [feedAdjustments, setFeedAdjustments] = useState<FeedInventoryAdjustment[]>([])
  const [loading, setLoading] = useState(true)
  const gh = useFmt()
  const [error, setError] = useState("")
  const [refreshing, setRefreshing] = useState(false)

  const [ledgerTypeFilter, setLedgerTypeFilter] = useState("ALL")
  const [ledgerDescriptionFilter, setLedgerDescriptionFilter] = useState("")
  const [ledgerDateFrom, setLedgerDateFrom] = useState("")
  const [ledgerDateTo, setLedgerDateTo] = useState("")
  const [ledgerSortKey, setLedgerSortKey] = useState<string | null>("date")
  const [ledgerSortDir, setLedgerSortDir] = useState<SortDirection>("desc")
  const [ledgerPage, setLedgerPage] = useState(1)
  const [ledgerPageSize, setLedgerPageSize] = useState(TRACKER_PAGE_SIZE_DEFAULT)
  // Phones open on scorecards; "View table format" flips to the table, the same
  // pair of views /poultry-daily-closing and /egg-tracker offer.
  const [showLedgerTableMobile, setShowLedgerTableMobile] = useState(false)

  const [adjustmentDialogOpen, setAdjustmentDialogOpen] = useState(false)
  const [editingAdjustmentId, setEditingAdjustmentId] = useState<number | null>(null)
  const [adjSubmitting, setAdjSubmitting] = useState(false)
  const [deleteAdjustmentId, setDeleteAdjustmentId] = useState<number | null>(null)
  const [adjForm, setAdjForm] = useState({
    adjustmentType: "Correction" as AdjType,
    feedDeltaKg: "",
    description: "",
    adjustmentDate: new Date().toISOString().split("T")[0],
  })

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  const loadData = useCallback(async () => {
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      setLoading(false)
      setRefreshing(false)
      return
    }
    // Stock now comes from the poultry raw-material store — the same movements
    // that maintain the quantities shown on /poultry-raw-materials. The Supplies
    // table this page used to read has never held a feed row.
    const [feedRes, flocksRes, adjRes, itemsRes, purchasesRes, usageRes, rmAdjRes] = await Promise.all([
      getFeedUsages(userId, farmId),
      getFlocks(userId, farmId),
      getFeedInventoryAdjustments(farmId),
      listPoultryRawMaterialItems().catch(() => [] as PoultryRawMaterialItem[]),
      listPoultryRawMaterialPurchases().catch(() => [] as PoultryRawMaterialPurchase[]),
      listPoultryRawMaterialUsageHistory().catch(() => [] as PoultryRawMaterialUsage[]),
      listPoultryRawMaterialAdjustments().catch(() => [] as PoultryRawMaterialAdjustment[]),
    ])
    setRmItems(itemsRes)
    setRmPurchases(purchasesRes)
    setRmUsage(usageRes)
    setRmAdjustments(rmAdjRes)
    if (feedRes.success && feedRes.data) {
      setUsages(feedRes.data)
      setError("")
    } else {
      setUsages([])
      setError(feedRes.message || "Failed to load feed usage")
    }
    if (flocksRes.success && flocksRes.data) setFlocks(flocksRes.data)
    else setFlocks([])
    if (adjRes.success && adjRes.data) setFeedAdjustments(adjRes.data)
    else {
      setFeedAdjustments([])
      if (!adjRes.success && adjRes.message) {
        console.warn("[feed-tracker] Feed adjustments:", adjRes.message)
      }
    }
    setLoading(false)
    setRefreshing(false)
  }, [])

  useEffect(() => {
    void loadData()
  }, [loadData])

  const adjustmentLedgerInput = useMemo(
    () =>
      feedAdjustments.map((a) => ({
        adjustmentId: a.adjustmentId,
        adjustmentDate: a.adjustmentDate,
        feedDeltaKg: a.feedDeltaKg,
        adjustmentType: a.adjustmentType,
        description: a.description,
      })),
    [feedAdjustments]
  )

  const feedStockLedger = useMemo(
    () =>
      buildFeedStockLedger({
        items: rmItems,
        purchases: rmPurchases,
        usages: rmUsage,
        adjustments: rmAdjustments,
        manualAdjustments: adjustmentLedgerInput,
      }),
    [rmItems, rmPurchases, rmUsage, rmAdjustments, adjustmentLedgerInput]
  )
  const { rows: feedLedgerAllRows, feedKgAtHand, lastUpdatedIso, totalInKg, totalOutKg } = feedStockLedger

  const distinctLedgerTypes = useMemo(() => {
    const set = new Set(feedLedgerAllRows.map((r) => r.type))
    return [...set].sort()
  }, [feedLedgerAllRows])

  const filteredFeedLedgerRows = useMemo(() => {
    let list = [...feedLedgerAllRows]
    if (ledgerTypeFilter !== "ALL") list = list.filter((r) => r.type === ledgerTypeFilter)
    if (ledgerDescriptionFilter.trim()) {
      const q = ledgerDescriptionFilter.trim().toLowerCase()
      list = list.filter((r) => r.description.toLowerCase().includes(q))
    }
    if (ledgerDateFrom) list = list.filter((r) => toLocalDateKey(r.date) >= ledgerDateFrom)
    if (ledgerDateTo) list = list.filter((r) => toLocalDateKey(r.date) <= ledgerDateTo)
    return list
  }, [feedLedgerAllRows, ledgerTypeFilter, ledgerDescriptionFilter, ledgerDateFrom, ledgerDateTo])

  const sortedFeedLedgerRows = useMemo(
    () =>
      sortData(filteredFeedLedgerRows, ledgerSortKey, ledgerSortDir, (item: FeedLedgerRow, key: string) => {
        // The ledger's own sequence, not the raw date: a day's rows share a
        // date, compare equal, and the table then fell back to insertion order
        // — ascending — even under a descending sort. `seq` already encodes
        // date-then-within-day order, so descending puts the last movement of
        // the day at the top, where whoever just entered it looks for it.
        if (key === "date") return item.seq
        if (key === "type") return item.type
        if (key === "description") return item.description
        if (key === "in") return Number(item.in) || 0
        if (key === "out") return Number(item.out) || 0
        if (key === "balance") return Number(item.balance) || 0
        return (item as FeedLedgerRow & Record<string, unknown>)[key]
      }),
    [filteredFeedLedgerRows, ledgerSortKey, ledgerSortDir]
  )

  // The movement figures behind the tiles and the Breakdown. Whole ledger, so
  // they decompose "Total IN" / "Total OUT" rather than the filtered table.
  const purchasedInKg = useMemo(
    () => feedLedgerAllRows.filter((r) => r.type === "Purchase IN").reduce((sum, r) => sum + r.in, 0),
    [feedLedgerAllRows]
  )
  const usedOutKg = useMemo(
    () => feedLedgerAllRows.filter((r) => r.type === "Usage OUT").reduce((sum, r) => sum + r.out, 0),
    [feedLedgerAllRows]
  )
  // Corrections, kept apart from the flows they sit between: a stocktake or a
  // reversal is somebody putting the count right, not feed bought or fed out.
  const adjustmentTotals = useMemo(() => {
    const rows = feedLedgerAllRows.filter((r) => /adjust/i.test(r.type))
    return {
      in: rows.reduce((sum, r) => sum + r.in, 0),
      out: rows.reduce((sum, r) => sum + r.out, 0),
    }
  }, [feedLedgerAllRows])

  const feedInBySource = useMemo(
    () => groupLedgerByType(feedLedgerAllRows, "in", FEED_MOVE_LABELS),
    [feedLedgerAllRows]
  )
  const feedOutByUse = useMemo(
    () => groupLedgerByType(feedLedgerAllRows, "out", FEED_MOVE_LABELS),
    [feedLedgerAllRows]
  )

  // The same two sides again, grouped by WHICH feed rather than by how it
  // moved. "Purchase 15,600" says the feed was bought; it does not say whether
  // that was layer mash or maize, which is the question anyone comparing feeds
  // is actually asking. Rows with no item are this page's own kg corrections,
  // entered against the farm's feed as a whole.
  const feedInByItem = useMemo(
    () => groupLedgerBy(feedLedgerAllRows, "in", (r) => r.itemName || "Not item-specific"),
    [feedLedgerAllRows]
  )
  const feedOutByItem = useMemo(
    () => groupLedgerBy(feedLedgerAllRows, "out", (r) => r.itemName || "Not item-specific"),
    [feedLedgerAllRows]
  )

  // Column totals across the whole filtered set, not just the page on screen,
  // so paging never changes them.
  const filteredLedgerInTotal = useMemo(
    () => sortedFeedLedgerRows.reduce((sum, r) => sum + (Number(r.in) || 0), 0),
    [sortedFeedLedgerRows]
  )
  const filteredLedgerOutTotal = useMemo(
    () => sortedFeedLedgerRows.reduce((sum, r) => sum + (Number(r.out) || 0), 0),
    [sortedFeedLedgerRows]
  )
  const ledgerFiltersActive =
    ledgerTypeFilter !== "ALL" ||
    ledgerDescriptionFilter.trim() !== "" ||
    ledgerDateFrom !== "" ||
    ledgerDateTo !== ""

  // Only what actually reached Profit & Loss, and only from live rows: a
  // reversed usage keeps its row (append-only) and its money has already been
  // taken back, so counting it again would overstate the feed bill.
  const filteredLedgerRecognizedTotal = useMemo(
    () => sortedFeedLedgerRows.reduce((sum, r) => sum + (r.reversed ? 0 : Number(r.recognized) || 0), 0),
    [sortedFeedLedgerRows]
  )

  const ledgerTotalPages = Math.max(1, Math.ceil(sortedFeedLedgerRows.length / ledgerPageSize))
  const ledgerSafePage = Math.min(ledgerPage, ledgerTotalPages)
  const paginatedFeedLedgerRows = useMemo(
    () =>
      sortedFeedLedgerRows.slice(
        (ledgerSafePage - 1) * ledgerPageSize,
        ledgerSafePage * ledgerPageSize
      ),
    [sortedFeedLedgerRows, ledgerSafePage, ledgerPageSize]
  )

  useEffect(() => {
    setLedgerPage(1)
  }, [ledgerTypeFilter, ledgerDescriptionFilter, ledgerDateFrom, ledgerDateTo, ledgerSortKey, ledgerSortDir])

  const handleLedgerSort = (key: string) => {
    const r = toggleSort(key, ledgerSortKey, ledgerSortDir)
    setLedgerSortKey(r.key)
    setLedgerSortDir(r.direction)
  }

  const clearLedgerFilters = () => {
    setLedgerTypeFilter("ALL")
    setLedgerDescriptionFilter("")
    setLedgerDateFrom("")
    setLedgerDateTo("")
    setLedgerSortKey("date")
    setLedgerSortDir("desc")
    setLedgerPage(1)
    toast({ title: "Filters cleared" })
  }

  const handleCopyFeedAtHand = () => {
    navigator.clipboard.writeText(String(Math.round((feedKgAtHand + Number.EPSILON) * 100) / 100))
    toast({ title: "Copied", description: "Feed left / at hand (kg) copied to clipboard" })
  }

  const ledgerLastUpdated = lastUpdatedIso ? new Date(lastUpdatedIso) : null

  const handleRefresh = () => {
    setRefreshing(true)
    void loadData()
  }

  const parseAdjustmentIdFromSortKey = (sortKey: string): number | null => {
    if (!sortKey.startsWith("feedadj_")) return null
    const n = parseInt(sortKey.slice("feedadj_".length), 10)
    return Number.isFinite(n) ? n : null
  }

  const openCreateAdjustment = () => {
    setEditingAdjustmentId(null)
    setAdjForm({
      adjustmentType: "Correction",
      feedDeltaKg: "",
      description: "",
      adjustmentDate: new Date().toISOString().split("T")[0],
    })
    setAdjustmentDialogOpen(true)
  }

  const openEditAdjustment = (row: FeedLedgerRow) => {
    const id = parseAdjustmentIdFromSortKey(row.sortKey)
    if (id == null) return
    const a = feedAdjustments.find((x) => x.adjustmentId === id)
    if (!a) return
    setEditingAdjustmentId(id)
    setAdjForm({
      adjustmentType: a.adjustmentType as AdjType,
      feedDeltaKg: String(a.feedDeltaKg),
      description: a.description || "",
      adjustmentDate: a.adjustmentDate ? String(a.adjustmentDate).slice(0, 10) : new Date().toISOString().split("T")[0],
    })
    setAdjustmentDialogOpen(true)
  }

  const saveAdjustment = async () => {
    const delta = parseFloat(adjForm.feedDeltaKg.trim().replace(",", "."))
    if (!Number.isFinite(delta) || delta === 0) {
      toastFormGuide(
        toast,
        "Enter feed change in kg — positive adds to on-hand feed, negative subtracts. Use decimals if needed; zero is not allowed."
      )
      return
    }
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "Sign in again to continue.", variant: "destructive" })
      return
    }
    const dateIso = adjForm.adjustmentDate
      ? new Date(adjForm.adjustmentDate + "T12:00:00").toISOString()
      : new Date().toISOString()

    setAdjSubmitting(true)
    try {
      if (editingAdjustmentId != null) {
        const res = await updateFeedInventoryAdjustment(editingAdjustmentId, farmId, {
          userId,
          adjustmentDate: dateIso,
          adjustmentType: adjForm.adjustmentType,
          feedDeltaKg: delta,
          description: adjForm.description.trim() || null,
        })
        if (!res.success) {
          toast({ title: "Update failed", description: res.message || "Could not update adjustment", variant: "destructive" })
          return
        }
        toast({ title: "Adjustment updated" })
      } else {
        const res = await createFeedInventoryAdjustment({
          userId,
          farmId,
          adjustmentDate: dateIso,
          adjustmentType: adjForm.adjustmentType,
          feedDeltaKg: delta,
          description: adjForm.description.trim() || null,
        })
        if (!res.success) {
          toast({ title: "Save failed", description: res.message || "Could not save adjustment", variant: "destructive" })
          return
        }
        toast({ title: "Adjustment added" })
      }
      setAdjustmentDialogOpen(false)
      setEditingAdjustmentId(null)
      void loadData()
    } finally {
      setAdjSubmitting(false)
    }
  }

  const deleteAdjustment = (row: FeedLedgerRow) => {
    const id = parseAdjustmentIdFromSortKey(row.sortKey)
    if (id == null) return
    const { farmId } = getUserContext()
    if (!farmId) return
    setDeleteAdjustmentId(id)
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-emerald-100 rounded-lg flex items-center justify-center">
                  <Wheat className="w-5 h-5 text-emerald-800" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Feed at hand / Feed left</h1>
                  <p className="text-sm text-slate-600">
                    <strong>Feed left</strong> (same idea as feed at hand) is the running difference:{" "}
                    <strong>IN − OUT</strong> in kg. <strong>IN</strong> = feed bought into inventory; <strong>OUT</strong> =
                    feed taken from inventory (feed usage). Flock filter only limits which usage rows count in OUT.
                  </p>
                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm">
                    <Link href="/inventory" className="text-blue-600 hover:underline font-medium">
                      Inventory (feed purchases)
                    </Link>
                    <Link href="/feed-usage" className="text-blue-600 hover:underline font-medium">
                      Feed usage (record OUT)
                    </Link>
                    <Link href="/production-records" className="text-blue-600 hover:underline font-medium">
                      Production records
                    </Link>
                  </div>
                </div>
              </div>
              <Button
                type="button"
                variant="outline"
                className="shrink-0 gap-2"
                onClick={handleRefresh}
                disabled={refreshing || loading}
              >
                <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
                Refresh
              </Button>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center text-slate-600">Loading feed left…</CardContent>
              </Card>
            ) : (
              <>
                <Card className="border-emerald-200 bg-emerald-50/40">
                  <CardHeader className="pb-2">
                    <div className={cn("flex justify-between gap-4", isMobile && "flex-col")}>
                      <div>
                        <CardDescription>Feed left · Feed at hand</CardDescription>
                        <CardTitle className="text-base font-semibold text-slate-800 mt-1">IN − OUT = kg on hand</CardTitle>
                      </div>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        className="gap-1.5 shrink-0"
                        onClick={openCreateAdjustment}
                      >
                        <Plus className="h-4 w-4" />
                        Add adjustment
                      </Button>
                      <Dialog
                        open={adjustmentDialogOpen}
                        onOpenChange={(open) => {
                          setAdjustmentDialogOpen(open)
                          if (!open) setEditingAdjustmentId(null)
                        }}
                      >
                        <DialogContent>
                          <DialogHeader>
                            <DialogTitle>
                              {editingAdjustmentId != null ? "Edit feed adjustment" : "Feed inventory adjustment"}
                            </DialogTitle>
                            <DialogDescription>
                              Adjust kg on hand without changing inventory items or feed usage records. Positive adds kg;
                              negative subtracts.
                            </DialogDescription>
                          </DialogHeader>
                          <div className="space-y-4 py-2">
                            <div className="space-y-2">
                              <Label>Type</Label>
                              <Select
                                value={adjForm.adjustmentType}
                                onValueChange={(v) => setAdjForm((p) => ({ ...p, adjustmentType: v as AdjType }))}
                              >
                                <SelectTrigger>
                                  <SelectValue />
                                </SelectTrigger>
                                <SelectContent>
                                  {ADJ_TYPES.map((t) => (
                                    <SelectItem key={t.value} value={t.value}>
                                      {t.label}
                                    </SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            </div>
                            <div className="space-y-2">
                              <Label>Date</Label>
                              <Input
                                type="date"
                                value={adjForm.adjustmentDate}
                                onChange={(e) => setAdjForm((p) => ({ ...p, adjustmentDate: e.target.value }))}
                              />
                            </div>
                            <div className="space-y-2">
                              <Label>Feed change (kg)</Label>
                              <NumberInput
                                
                                step="0.01"
                                placeholder="e.g. 100 or -25.5"
                                value={adjForm.feedDeltaKg}
                                onChange={(e) => setAdjForm((p) => ({ ...p, feedDeltaKg: e.target.value }))}
                              />
                            </div>
                            <div className="space-y-2">
                              <Label>Description (optional)</Label>
                              <Input
                                placeholder="e.g. Stocktake correction"
                                value={adjForm.description}
                                onChange={(e) => setAdjForm((p) => ({ ...p, description: e.target.value }))}
                              />
                            </div>
                            <Button type="button" onClick={() => void saveAdjustment()} disabled={adjSubmitting}>
                              {editingAdjustmentId != null ? "Update" : "Save"}
                            </Button>
                          </div>
                        </DialogContent>
                      </Dialog>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {/* Four equal columns, two rows, every tile the same width
                        and every left edge lined up down the card — the same
                        grid /egg-tracker uses. Eight cells for seven figures, so
                        "Last ledger event", which used to float to the right of
                        the whole block, takes the eighth and the grid has no
                        hole in it. Two across on a phone: eight divides by two
                        as well as by four, so each pair keeps its own line. */}
                    <div className={cn("grid gap-4 min-w-0", isMobile ? "grid-cols-2" : "grid-cols-4")}>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">
                          Feed left / at hand (kg)
                        </div>
                        <div className="mt-1 flex items-center gap-2 flex-wrap">
                          <span
                            className={cn(
                              "text-2xl font-bold tabular-nums",
                              feedKgAtHand < 0 ? "text-red-600" : "text-slate-900"
                            )}
                          >
                            {feedKgAtHand.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                          </span>
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-slate-500 hover:text-slate-700"
                            onClick={handleCopyFeedAtHand}
                            aria-label="Copy feed left (kg)"
                          >
                            <Copy className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Feed purchased (kg)</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-sky-700">
                          {purchasedInKg.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Feed used (kg)</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-amber-800">
                          {usedOutKg.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        </div>
                      </div>
                      {/* Same tile shape as the figures around it, and the
                          table's own date format, so the row reads as one band
                          rather than three numbers and a caption. */}
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Last ledger event</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-slate-600">
                          {ledgerLastUpdated ? formatDateShort(ledgerLastUpdated) : "—"}
                        </div>
                        <div className="text-xs tabular-nums text-slate-500">
                          {ledgerLastUpdated
                            ? ledgerLastUpdated.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
                            : "—"}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Feed in (adjustments)</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-emerald-700">
                          {adjustmentTotals.in.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Feed out (adjustments)</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-rose-600">
                          {adjustmentTotals.out.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total IN (ledger)</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-emerald-800">
                          {totalInKg.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total OUT (ledger)</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-slate-800">
                          {totalOutKg.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        </div>
                      </div>
                    </div>
                    <p className="text-xs text-slate-500 mt-2">
                      IN uses inventory items with category <strong>Feed</strong> (purchase date + quantity; g/ton converted to kg
                      when possible). OUT uses feed usage kg. Flock filter narrows OUT to one flock; IN stays farm-wide. Use{" "}
                      <strong>Add adjustment</strong> to align kg after a stocktake (requires DB migration 014 on the farm API
                      database).
                    </p>
                    {feedKgAtHand < 0 && (
                      <p className="text-xs text-amber-900 mt-2 rounded-md border border-amber-200 bg-amber-100/80 px-2 py-1.5">
                        Negative balance usually means more usage was logged than feed purchases — check inventory and usage dates.
                      </p>
                    )}
                  </CardContent>
                </Card>

                {/* Straight under the tiles, because it is the tiles it breaks
                    apart: both cards total the whole ledger, which is what
                    "Total IN" and "Total OUT" above them count. Side by side
                    from lg up — in and out are meant to be read against each
                    other, and this is a full-width page with the room. */}
                {(feedInBySource.length > 0 || feedOutByUse.length > 0) && (
                  <div className="space-y-3">
                    <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
                      Breakdown
                    </h2>
                    <div className="grid items-start gap-3 lg:grid-cols-2">
                      <FlowBreakdownCard
                        title="Feed in by source"
                        direction="in"
                        buckets={feedInBySource}
                        total={totalInKg}
                        fmtMoney={(n) => n.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        description="Every movement that added feed to stock — the whole ledger, so it breaks down the totals above rather than the filtered table below."
                        emptyText="No feed has come in yet."
                      />
                      <FlowBreakdownCard
                        title="Feed out by use"
                        direction="out"
                        buckets={feedOutByUse}
                        total={totalOutKg}
                        fmtMoney={(n) => n.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        description="Every movement that took feed out of stock — production usage, feed-production batches and corrections."
                        emptyText="No feed has gone out yet."
                      />
                      <FlowBreakdownCard
                        title="Feed in by item"
                        direction="in"
                        buckets={feedInByItem}
                        total={totalInKg}
                        fmtMoney={(n) => n.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        description="The same feed in, by which feed it was — layer mash, maize, concentrate."
                        emptyText="No feed has come in yet."
                      />
                      <FlowBreakdownCard
                        title="Feed out by item"
                        direction="out"
                        buckets={feedOutByItem}
                        total={totalOutKg}
                        fmtMoney={(n) => n.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                        description="The same feed out, by which feed it was — what is actually being eaten, and how fast."
                        emptyText="No feed has gone out yet."
                      />
                    </div>
                  </div>
                )}

                <Card className="bg-white" id="feed-ledger">
                  <CardHeader>
                    <CardTitle>Feed stock ledger</CardTitle>
                    <CardDescription>
                      Purchases in, consumption out, straight from the raw-material store — so this balance matches the stock on Raw Materials &amp; Supplies. Filter the table below.
                    </CardDescription>
                    <div className={cn("grid gap-2 pt-3", isMobile ? "grid-cols-1" : "grid-cols-2 lg:grid-cols-5")}>
                      <Select value={ledgerTypeFilter} onValueChange={setLedgerTypeFilter}>
                        <SelectTrigger>
                          <SelectValue placeholder="Type" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All types</SelectItem>
                          {distinctLedgerTypes.map((t) => (
                            <SelectItem key={t} value={t}>
                              {t}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Input
                        placeholder="Description…"
                        value={ledgerDescriptionFilter}
                        onChange={(e) => setLedgerDescriptionFilter(e.target.value)}
                        className={cn(isMobile ? "" : "lg:col-span-2")}
                      />
                      <Input type="date" value={ledgerDateFrom} onChange={(e) => setLedgerDateFrom(e.target.value)} aria-label="From date" />
                      <Input type="date" value={ledgerDateTo} onChange={(e) => setLedgerDateTo(e.target.value)} aria-label="To date" />
                    </div>
                    <div className="pt-2">
                      <Button type="button" variant="outline" size="sm" onClick={clearLedgerFilters}>
                        Reset ledger filters
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent className="pt-0">
                    {sortedFeedLedgerRows.length === 0 ? (
                      <p className="text-slate-600 py-8 text-center text-sm">
                        No ledger rows yet. Add <strong>Feed</strong> items on Inventory and record usage on Feed usage.
                      </p>
                    ) : isMobile && !showLedgerTableMobile ? (
                      /* Scorecards, following /poultry-daily-closing and
                         /egg-tracker: one card per row, open by default, striped
                         so consecutive rows are told apart at a glance. In and
                         out keep their green and red — they are the two
                         directions the ledger exists to tell apart. */
                      <div className="space-y-3">
                        {paginatedFeedLedgerRows.map((row, idx) => {
                          const isAdj = row.type === "Adjustment"
                          return (
                            <Collapsible
                              key={row.sortKey}
                              defaultOpen
                              className={cn(
                                "group w-full overflow-hidden rounded-xl border shadow-sm",
                                idx % 2 === 0 ? "border-blue-300 bg-blue-100" : "border-slate-200 bg-white"
                              )}
                            >
                              <div className={cn("px-2.5 py-3 transition-colors", idx % 2 === 0 ? "active:bg-black/10" : "active:bg-black/5")}>
                                <CollapsibleTrigger asChild>
                                  <div className="relative cursor-pointer">
                                    <ChevronDown className="absolute right-0 top-0 h-4 w-4 shrink-0 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
                                    <div className="min-w-0">
                                      <div className="flex flex-wrap items-center gap-2 pr-6">
                                        <span className="font-semibold text-slate-900">
                                          {row.date ? formatDateShort(row.date) : "—"}
                                        </span>
                                        <Badge className="bg-blue-200 text-blue-900 hover:bg-blue-200">{row.type}</Badge>
                                      </div>
                                      <div className="mt-3 grid grid-cols-2 gap-2">
                                        <div className="rounded-lg border border-emerald-300 bg-emerald-100 px-3 py-2 shadow-sm">
                                          <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">In (kg)</p>
                                          <p className="text-xl font-extrabold leading-tight text-emerald-800 tabular-nums">
                                            {row.in > 0 ? row.in.toLocaleString(undefined, { maximumFractionDigits: 2 }) : "—"}
                                          </p>
                                        </div>
                                        <div className="rounded-lg border border-red-300 bg-red-100 px-3 py-2 shadow-sm">
                                          <p className="text-[11px] font-semibold uppercase tracking-wide text-red-900">Out (kg)</p>
                                          <p className="text-xl font-extrabold leading-tight text-red-800 tabular-nums">
                                            {row.out > 0 ? row.out.toLocaleString(undefined, { maximumFractionDigits: 2 }) : "—"}
                                          </p>
                                        </div>
                                      </div>
                                    </div>
                                  </div>
                                </CollapsibleTrigger>
                                <CollapsibleContent>
                                  <div className="mt-4 space-y-2 border-t border-slate-200/70 pt-4 text-sm">
                                    <div>
                                      <span className="text-slate-500">Description</span>{" "}
                                      <span className="font-medium text-slate-900">{row.description}</span>
                                    </div>
                                    <div>
                                      <span className="text-slate-500">Balance</span>{" "}
                                      <span className="font-medium tabular-nums text-slate-900">
                                        {row.balance.toLocaleString(undefined, { maximumFractionDigits: 2 })} kg
                                      </span>
                                    </div>
                                    {/* Only this page's own adjustments can be edited or
                                        removed; every other row belongs to the record that
                                        posted it. */}
                                    {isAdj && (
                                      <div className="flex gap-2 pt-2">
                                        <Button
                                          type="button"
                                          variant="outline"
                                          size="sm"
                                          className="h-10 flex-1 bg-white"
                                          onClick={(e) => { e.stopPropagation(); openEditAdjustment(row) }}
                                        >
                                          <Pencil className="mr-2 h-4 w-4" /> Edit
                                        </Button>
                                        <Button
                                          type="button"
                                          variant="outline"
                                          size="sm"
                                          className="h-10 flex-1 bg-white text-red-600"
                                          onClick={(e) => { e.stopPropagation(); void deleteAdjustment(row) }}
                                        >
                                          <Trash2 className="mr-2 h-4 w-4" /> Delete
                                        </Button>
                                      </div>
                                    )}
                                  </div>
                                </CollapsibleContent>
                              </div>
                            </Collapsible>
                          )
                        })}
                        <div className="rounded-lg border bg-slate-50/60 px-4 py-2">
                          <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            className="w-full text-slate-600"
                            onClick={() => setShowLedgerTableMobile(true)}
                          >
                            View table format <ChevronDown className="ml-1 h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    ) : (
                      <>
                      {isMobile && (
                        <div className="-mx-4 -mt-4 mb-3 flex items-center justify-between gap-2 border-b bg-slate-50 px-4 py-2">
                          <span className="text-xs text-slate-600">Table view - scroll for more</span>
                          <Button type="button" variant="ghost" size="sm" onClick={() => setShowLedgerTableMobile(false)}>
                            <ChevronUp className="mr-1 h-4 w-4" /> Cards
                          </Button>
                        </div>
                      )}
                      <div className="overflow-x-auto table-scroll-wrapper pb-2" style={{ WebkitOverflowScrolling: "touch" }}>
                        <Table className="w-full min-w-[720px]">
                          <TableHeader>
                            <TableRow>
                              <SortableHeader
                                label="Date"
                                sortKey="date"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                              />
                              <SortableHeader
                                label="Type"
                                sortKey="type"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                              />
                              <SortableHeader
                                label="Description"
                                sortKey="description"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                              />
                              <SortableHeader
                                label="In (kg)"
                                sortKey="in"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                              <SortableHeader
                                label="Out (kg)"
                                sortKey="out"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                              <SortableHeader
                                label="Balance (kg)"
                                sortKey="balance"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                              <SortableHeader
                                label="Cost recognised"
                                sortKey="recognized"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                              <TableHead className="text-right w-[100px]">Actions</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {paginatedFeedLedgerRows.map((row) => {
                              const isAdj = row.type === "Adjustment"
                              return (
                                <TableRow key={row.sortKey}>
                                  <TableCell className="font-medium whitespace-nowrap text-sm">
                                    {row.date ? formatDateShort(row.date) : "—"}
                                  </TableCell>
                                  <TableCell className="text-sm">{row.type}</TableCell>
                                  <TableCell className="max-w-[260px] truncate text-sm" title={row.description}>
                                    {row.description}
                                  </TableCell>
                                  <TableCell className="text-right text-emerald-600 tabular-nums text-sm">
                                    {row.in > 0 ? row.in.toLocaleString(undefined, { maximumFractionDigits: 2 }) : "—"}
                                  </TableCell>
                                  <TableCell className="text-right text-red-600 tabular-nums text-sm">
                                    {row.out > 0 ? row.out.toLocaleString(undefined, { maximumFractionDigits: 2 }) : "—"}
                                  </TableCell>
                                  <TableCell className="text-right font-medium tabular-nums text-sm">
                                    {row.balance.toLocaleString(undefined, { maximumFractionDigits: 2 })}
                                  </TableCell>
                                  {/* Read-only, and deliberately two facts in one
                                      cell. A usage that recognised nothing is not
                                      a usage that cost nothing -- on a farm that
                                      expenses feed at purchase (the default) every
                                      row here reads zero, and the sub-line is what
                                      stops that being read as free feed. */}
                                  <TableCell className="text-right tabular-nums text-sm">
                                    {row.cost == null ? (
                                      <span className="text-slate-300">—</span>
                                    ) : row.reversed ? (
                                      <span className="text-slate-400">Reversed</span>
                                    ) : (
                                      <span title={recognizedCostNote(row.recognized ?? 0, row.cost ?? 0)}>
                                        <span className={(row.recognized ?? 0) > 0 ? "font-medium text-amber-700" : "text-slate-500"}>
                                          {gh(row.recognized ?? 0)}
                                        </span>
                                        <span className="block text-[11px] text-slate-500">
                                          {(row.recognized ?? 0) > 0
                                            ? `of ${gh(row.cost ?? 0)} stock cost`
                                            : `${gh(row.cost ?? 0)} expensed at purchase`}
                                        </span>
                                      </span>
                                    )}
                                  </TableCell>
                                  <TableCell className="text-right">
                                    {isAdj ? (
                                      <div className="flex justify-end gap-1">
                                        <Button
                                          type="button"
                                          variant="ghost"
                                          size="icon"
                                          className="h-8 w-8"
                                          onClick={() => openEditAdjustment(row)}
                                          aria-label="Edit adjustment"
                                        >
                                          <Pencil className="h-4 w-4" />
                                        </Button>
                                        <Button
                                          type="button"
                                          variant="ghost"
                                          size="icon"
                                          className="h-8 w-8 text-red-600"
                                          onClick={() => void deleteAdjustment(row)}
                                          aria-label="Delete adjustment"
                                        >
                                          <Trash2 className="h-4 w-4" />
                                        </Button>
                                      </div>
                                    ) : (
                                      <span className="text-slate-300 text-sm">—</span>
                                    )}
                                  </TableCell>
                                </TableRow>
                              )
                            })}
                          </TableBody>
                          <TableFooter>
                            <TableRow className="bg-slate-50 hover:bg-slate-50">
                              <TableCell colSpan={3} className="font-medium text-slate-700 text-sm">
                                {ledgerFiltersActive ? "Filtered total" : "Total"}
                                <span className="ml-2 font-normal text-slate-500">
                                  ({sortedFeedLedgerRows.length.toLocaleString()}{" "}
                                  {sortedFeedLedgerRows.length === 1 ? "row" : "rows"})
                                </span>
                              </TableCell>
                              <TableCell className="text-right font-bold text-emerald-700 tabular-nums text-sm">
                                {filteredLedgerInTotal.toLocaleString(undefined, { maximumFractionDigits: 2 })}
                              </TableCell>
                              <TableCell className="text-right font-bold text-red-700 tabular-nums text-sm">
                                {filteredLedgerOutTotal.toLocaleString(undefined, { maximumFractionDigits: 2 })}
                              </TableCell>
                              <TableCell />
                              <TableCell className="text-right font-bold text-amber-700 tabular-nums text-sm">
                                {gh(filteredLedgerRecognizedTotal)}
                              </TableCell>
                              <TableCell />
                            </TableRow>
                          </TableFooter>
                        </Table>
                      </div>
                      </>
                    )}
                    {sortedFeedLedgerRows.length > 0 && (
                      <div className="flex flex-col gap-2 border-t px-2 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-4 bg-slate-50/80">
                        <div className="flex flex-col items-center gap-2 sm:flex-row sm:gap-3">
                          <p className="text-xs text-slate-600 text-center sm:text-left">
                            Showing {(ledgerSafePage - 1) * ledgerPageSize + 1}-
                            {Math.min(ledgerSafePage * ledgerPageSize, sortedFeedLedgerRows.length)} of{" "}
                            {sortedFeedLedgerRows.length}
                          </p>
                          <Select
                            value={String(ledgerPageSize)}
                            onValueChange={(v) => {
                              setLedgerPageSize(Number(v))
                              setLedgerPage(1)
                            }}
                          >
                            <SelectTrigger className="h-8 w-[110px]" aria-label="Rows per page">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {TRACKER_PAGE_SIZE_OPTIONS.map((n) => (
                                <SelectItem key={n} value={String(n)}>
                                  {n} / page
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="flex items-center justify-center gap-2">
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            disabled={ledgerSafePage <= 1}
                            onClick={() => setLedgerPage((p) => Math.max(1, p - 1))}
                          >
                            Previous
                          </Button>
                          <span className="text-xs text-slate-600 whitespace-nowrap">
                            Page {ledgerSafePage} of {ledgerTotalPages}
                          </span>
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            disabled={ledgerSafePage >= ledgerTotalPages}
                            onClick={() => setLedgerPage((p) => Math.min(ledgerTotalPages, p + 1))}
                          >
                            Next
                          </Button>
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </>
            )}
          </div>
        </main>
      </div>

      <ConfirmDeleteDialog
        open={deleteAdjustmentId !== null}
        onOpenChange={(o) => { if (!o) setDeleteAdjustmentId(null) }}
        title="Delete feed inventory adjustment?"
        description="This adjustment will be permanently removed from the ledger."
        successTitle="Adjustment removed"
        errorTitle="Delete failed"
        onConfirm={async () => {
          if (deleteAdjustmentId === null) return { success: false, message: "Missing id" }
          const { farmId } = getUserContext()
          if (!farmId) return { success: false, message: "Missing farm context" }
          const res = await deleteFeedInventoryAdjustment(deleteAdjustmentId, farmId)
          if (res.success) void loadData()
          return res
        }}
      />
    </div>
  )
}

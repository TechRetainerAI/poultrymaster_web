"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { TRACKER_PAGE_SIZE_OPTIONS } from "@/components/ui/data-pagination"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Label } from "@/components/ui/label"
import { Wheat, RefreshCw, Copy, Plus, Pencil, Trash2 } from "lucide-react"
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
import {
  getFeedInventoryAdjustments,
  createFeedInventoryAdjustment,
  updateFeedInventoryAdjustment,
  deleteFeedInventoryAdjustment,
  type FeedInventoryAdjustment,
} from "@/lib/api/feed-inventory-adjustment"

const LEDGER_PAGE_SIZE_DEFAULT = 15

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
  const [error, setError] = useState("")
  const [refreshing, setRefreshing] = useState(false)

  const [ledgerTypeFilter, setLedgerTypeFilter] = useState("ALL")
  const [ledgerDescriptionFilter, setLedgerDescriptionFilter] = useState("")
  const [ledgerDateFrom, setLedgerDateFrom] = useState("")
  const [ledgerDateTo, setLedgerDateTo] = useState("")
  const [ledgerSortKey, setLedgerSortKey] = useState<string | null>("date")
  const [ledgerSortDir, setLedgerSortDir] = useState<SortDirection>("desc")
  const [ledgerPage, setLedgerPage] = useState(1)
  const [ledgerPageSize, setLedgerPageSize] = useState(LEDGER_PAGE_SIZE_DEFAULT)

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
        if (key === "date") return new Date(item.date)
        if (key === "type") return item.type
        if (key === "description") return item.description
        if (key === "in") return Number(item.in) || 0
        if (key === "out") return Number(item.out) || 0
        if (key === "balance") return Number(item.balance) || 0
        return (item as FeedLedgerRow & Record<string, unknown>)[key]
      }),
    [filteredFeedLedgerRows, ledgerSortKey, ledgerSortDir]
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
                    <div className={cn("flex gap-4 flex-wrap", isMobile ? "flex-col" : "items-start justify-between")}>
                      <div className={cn("grid gap-4", isMobile ? "grid-cols-1" : "grid-cols-3")}>
                        <div>
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
                        <div>
                          <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total IN (ledger)</div>
                          <div className="mt-1 text-2xl font-bold tabular-nums text-emerald-800">
                            {totalInKg.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                          </div>
                        </div>
                        <div>
                          <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total OUT (ledger)</div>
                          <div className="mt-1 text-2xl font-bold tabular-nums text-slate-800">
                            {totalOutKg.toLocaleString(undefined, { maximumFractionDigits: 1 })}
                          </div>
                        </div>
                      </div>
                      <div className="text-sm text-slate-500 shrink-0 text-right">
                        <div>
                          Last ledger event:{" "}
                          {ledgerLastUpdated
                            ? ledgerLastUpdated.toLocaleDateString("en-GB", {
                                day: "2-digit",
                                month: "short",
                                year: "numeric",
                              })
                            : "—"}
                        </div>
                        <div className="text-xs mt-0.5 tabular-nums">
                          Last updated:{" "}
                          {ledgerLastUpdated
                            ? ledgerLastUpdated.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
                            : "—"}
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
                    ) : (
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
                              <TableCell />
                            </TableRow>
                          </TableFooter>
                        </Table>
                      </div>
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

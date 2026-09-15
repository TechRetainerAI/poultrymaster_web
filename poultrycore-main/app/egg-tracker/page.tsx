"use client"

import { useCallback, useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { TRACKER_PAGE_SIZE_DEFAULT, TRACKER_PAGE_SIZE_OPTIONS } from "@/components/ui/data-pagination"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { BarChart3, Copy, RefreshCw, Plus, Pencil, Trash2, ChevronDown, ChevronUp } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { getEggProductions, type EggProduction } from "@/lib/api/egg-production"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getSales, type Sale } from "@/lib/api/sale"
import {
  getEggInventoryAdjustments,
  createEggInventoryAdjustment,
  updateEggInventoryAdjustment,
  deleteEggInventoryAdjustment,
  type EggInventoryAdjustment,
} from "@/lib/api/egg-inventory-adjustment"
import {
  listPoultryProducts,
  listPoultryStockTransactions,
  type PoultryStockTransaction,
} from "@/lib/api/poultry-inventory"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { buildEggStockLedger, type EggLedgerRow } from "@/lib/utils/egg-ledger"
import { groupLedgerByType, EGG_MOVE_LABELS } from "@/lib/utils/ledger-breakdown"
import { FlowBreakdownCard } from "@/components/cash/flow-breakdown-card"


const ADJ_TYPES = [
  { value: "Correction", label: "Correction" },
  { value: "Stocktake", label: "Stocktake" },
  { value: "OpeningBalance", label: "Opening balance" },
] as const

type AdjType = (typeof ADJ_TYPES)[number]["value"]

export default function EggTrackerPage() {
  const router = useRouter()
  const { toast } = useToast()
  const isMobile = useIsMobile()
  const [eggProductions, setEggProductions] = useState<EggProduction[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [sales, setSales] = useState<Sale[]>([])
  const [eggAdjustments, setEggAdjustments] = useState<EggInventoryAdjustment[]>([])
  const [eggStockMoves, setEggStockMoves] = useState<PoultryStockTransaction[]>([])
  // Authoritative "Eggs on hand": the server-side ledger sum that
  // /poultry-inventory shows as "In stock" (sppoultryproduct_getall). Read, never
  // recomputed here — see buildEggStockLedger.
  // null = products did not load, so there is no authoritative figure this pass;
  // the ledger falls back to the derived balance rather than reporting a false 0.
  const [eggStockOnHand, setEggStockOnHand] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [refreshing, setRefreshing] = useState(false)

  const [adjustmentDialogOpen, setAdjustmentDialogOpen] = useState(false)
  const [editingAdjustmentId, setEditingAdjustmentId] = useState<number | null>(null)
  const [adjSubmitting, setAdjSubmitting] = useState(false)
  const [deleteAdjustmentId, setDeleteAdjustmentId] = useState<number | null>(null)
  const [adjForm, setAdjForm] = useState({
    adjustmentType: "Correction" as AdjType,
    eggDelta: "",
    description: "",
    adjustmentDate: new Date().toISOString().split("T")[0],
  })

  const [ledgerTypeFilter, setLedgerTypeFilter] = useState("ALL")
  const [ledgerDescriptionFilter, setLedgerDescriptionFilter] = useState("")
  const [ledgerDateFrom, setLedgerDateFrom] = useState("")
  const [ledgerDateTo, setLedgerDateTo] = useState("")
  const [ledgerSortKey, setLedgerSortKey] = useState<string | null>("date")
  const [ledgerSortDir, setLedgerSortDir] = useState<SortDirection>("desc")
  const [ledgerPage, setLedgerPage] = useState(1)
  const [ledgerPageSize, setLedgerPageSize] = useState(TRACKER_PAGE_SIZE_DEFAULT)
  // Phones open on scorecards; "View table format" flips to the six-column
  // table, the same pair of views /poultry-daily-closing offers. Only ever
  // consulted on mobile — the desktop layout is the table, always.
  const [showLedgerTableMobile, setShowLedgerTableMobile] = useState(false)

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
    const [eggRes, flocksRes, salesRes, adjRes, productsRes, stockRes] = await Promise.all([
      getEggProductions(userId, farmId),
      getFlocks(userId, farmId),
      getSales(userId, farmId),
      getEggInventoryAdjustments(farmId),
      // These two throw on failure (unlike the wrappers above, which return a
      // result object), so keep them from rejecting the whole load.
      listPoultryProducts().catch((e) => {
        console.warn("[egg-tracker] Products:", e)
        return [] as Awaited<ReturnType<typeof listPoultryProducts>>
      }),
      listPoultryStockTransactions().catch((e) => {
        console.warn("[egg-tracker] Stock moves:", e)
        return [] as Awaited<ReturnType<typeof listPoultryStockTransactions>>
      }),
    ])
    if (eggRes.success && eggRes.data) {
      setEggProductions(eggRes.data)
      setError("")
    } else {
      setEggProductions([])
      setError(eggRes.message || "Failed to load egg production")
    }
    if (flocksRes.success && flocksRes.data) setFlocks(flocksRes.data)
    else setFlocks([])
    if (salesRes.success && salesRes.data) setSales(salesRes.data)
    else setSales([])
    if (adjRes.success && adjRes.data) setEggAdjustments(adjRes.data)
    else {
      setEggAdjustments([])
      if (!adjRes.success && adjRes.message) {
        console.warn("[egg-tracker] Adjustments:", adjRes.message)
      }
    }
    // Stock-ledger moves for the egg product (driver load-outs, deliveries, Set
    // stock / Reconcile corrections). Without these the balance below drifts from
    // /poultry-inventory's "In stock", which is the same ledger.
    const eggProducts = productsRes.filter(
      (p) => p.isRawEggProduct || p.name === "Eggs" || p.name === "Chicken Eggs"
    )
    const eggProductIds = new Set(eggProducts.map((p) => p.poultryProductId))
    setEggStockMoves(stockRes.filter((t) => eggProductIds.has(t.poultryProductId)))
    // The same number /poultry-inventory prints, straight from the server's
    // ledger sum — so the two pages cannot disagree.
    setEggStockOnHand(
      eggProducts.length > 0
        ? eggProducts.reduce((s, p) => s + (Number(p.stockOnHand) || 0), 0)
        : null
    )
    setLoading(false)
    setRefreshing(false)
  }, [])

  useEffect(() => {
    void loadData()
  }, [loadData])

  const formatDateShort = (d: string | Date) => {
    const dt = typeof d === "string" ? new Date(d) : d
    return dt.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "2-digit" })
  }

  const adjustmentLedgerInput = useMemo(
    () =>
      eggAdjustments.map((a) => ({
        adjustmentId: a.adjustmentId,
        adjustmentDate: a.adjustmentDate,
        eggDelta: a.eggDelta,
        adjustmentType: a.adjustmentType,
        description: a.description,
      })),
    [eggAdjustments]
  )

  const stockMoveLedgerInput = useMemo(
    () =>
      eggStockMoves.map((t) => ({
        poultryStockTransactionId: t.poultryStockTransactionId,
        createdDate: t.createdDate,
        txnType: t.txnType,
        quantity: t.quantity,
        note: t.note,
        relatedId: t.relatedId,
      })),
    [eggStockMoves]
  )

  const eggStockLedger = useMemo(
    () =>
      buildEggStockLedger(
        eggProductions,
        sales,
        flocks,
        adjustmentLedgerInput,
        stockMoveLedgerInput,
        eggStockOnHand ?? undefined
      ),
    [eggProductions, sales, flocks, adjustmentLedgerInput, stockMoveLedgerInput, eggStockOnHand]
  )
  const { rows: eggLedgerAllRows, currentEggsAtHand, lastUpdatedIso } = eggStockLedger

  const distinctLedgerTypes = useMemo(() => {
    const set = new Set(eggLedgerAllRows.map((r) => r.type))
    return [...set].sort()
  }, [eggLedgerAllRows])

  const totalEggsSoldLedger = useMemo(
    () => eggLedgerAllRows.filter((r) => r.type === "Sale").reduce((sum, r) => sum + r.out, 0),
    [eggLedgerAllRows]
  )

  // Eggs the flocks actually laid: the ledger's 'Production' rows and nothing
  // else. Deliberately narrower than "Total eggs in", which also counts
  // stocktake adjustments, restocks and driver returns — real movements into
  // stock, but not eggs any hen produced. This is the collected figure, before
  // the broken / meaty / soft / lost lines take their share back out.
  const totalEggsProducedLedger = useMemo(
    () => eggLedgerAllRows.filter((r) => r.type === "Production").reduce((sum, r) => sum + r.in, 0),
    [eggLedgerAllRows]
  )

  // The "Breakdown" section — the same one the Cash Flow page gives money,
  // over the same rows the tiles above count, so each card's heading total is
  // the "Total eggs in" / "Total eggs out" tile broken into its parts.
  const eggsInBySource = useMemo(
    () => groupLedgerByType(eggLedgerAllRows, "in", EGG_MOVE_LABELS),
    [eggLedgerAllRows],
  )
  const eggsOutByUse = useMemo(
    () => groupLedgerByType(eggLedgerAllRows, "out", EGG_MOVE_LABELS),
    [eggLedgerAllRows],
  )

  // Corrections, kept apart from the flows they sit between. An adjustment is
  // somebody reconciling the count after a stocktake, not eggs laid or sold, so
  // it is worth seeing on its own — a large one is usually the reason the
  // ledger and the shed agree at all. Matched loosely on the type because two
  // sources produce them: the egg adjustments on this page ("Adjustment") and
  // stock-ledger corrections posted from /poultry-stock ("Adjust").
  const adjustmentTotals = useMemo(() => {
    const rows = eggLedgerAllRows.filter((r) => /adjust/i.test(r.type))
    return {
      in: rows.reduce((sum, r) => sum + r.in, 0),
      out: rows.reduce((sum, r) => sum + r.out, 0),
    }
  }, [eggLedgerAllRows])

  // Headline totals: every movement, ignoring the table filters, so they stay
  // put while you narrow the list below. in − out is "Eggs on hand".
  const totalEggsInLedger = useMemo(
    () => eggLedgerAllRows.reduce((sum, r) => sum + r.in, 0),
    [eggLedgerAllRows]
  )
  const totalEggsOutLedger = useMemo(
    () => eggLedgerAllRows.reduce((sum, r) => sum + r.out, 0),
    [eggLedgerAllRows]
  )

  const filteredEggLedgerRows = useMemo(() => {
    let list = [...eggLedgerAllRows]
    if (ledgerTypeFilter !== "ALL") list = list.filter((r) => r.type === ledgerTypeFilter)
    if (ledgerDescriptionFilter.trim()) {
      const q = ledgerDescriptionFilter.trim().toLowerCase()
      list = list.filter((r) => r.description.toLowerCase().includes(q))
    }
    if (ledgerDateFrom) list = list.filter((r) => toLocalDateKey(r.date) >= ledgerDateFrom)
    if (ledgerDateTo) list = list.filter((r) => toLocalDateKey(r.date) <= ledgerDateTo)
    return list
  }, [eggLedgerAllRows, ledgerTypeFilter, ledgerDescriptionFilter, ledgerDateFrom, ledgerDateTo])

  const sortedEggLedgerRows = useMemo(
    () =>
      sortData(filteredEggLedgerRows, ledgerSortKey, ledgerSortDir, (item: EggLedgerRow, key: string) => {
        // Sort on the ledger's own sequence, not the raw date. A day's rows all
        // carry the same date, so comparing dates left them tied and the table
        // fell back to insertion order — ascending — even under a descending
        // sort. `seq` already encodes date-then-within-day order, so descending
        // now puts the last thing entered at the top of the day, where the
        // person who just entered it looks for it.
        if (key === "date") return item.seq
        if (key === "type") return item.type
        if (key === "description") return item.description
        if (key === "in") return Number(item.in) || 0
        if (key === "out") return Number(item.out) || 0
        return (item as EggLedgerRow & Record<string, unknown>)[key]
      }),
    [filteredEggLedgerRows, ledgerSortKey, ledgerSortDir]
  )

  // Column totals for the rows the filters actually left behind — the whole
  // filtered set, not just the page on screen, so paging doesn't change them.
  const filteredLedgerInTotal = useMemo(
    () => sortedEggLedgerRows.reduce((sum, r) => sum + r.in, 0),
    [sortedEggLedgerRows]
  )
  const filteredLedgerOutTotal = useMemo(
    () => sortedEggLedgerRows.reduce((sum, r) => sum + r.out, 0),
    [sortedEggLedgerRows]
  )

  const ledgerFiltersActive =
    ledgerTypeFilter !== "ALL" ||
    ledgerDescriptionFilter.trim() !== "" ||
    ledgerDateFrom !== "" ||
    ledgerDateTo !== ""

  const ledgerTotalPages = Math.max(1, Math.ceil(sortedEggLedgerRows.length / ledgerPageSize))
  const ledgerSafePage = Math.min(ledgerPage, ledgerTotalPages)
  const paginatedEggLedgerRows = useMemo(
    () =>
      sortedEggLedgerRows.slice(
        (ledgerSafePage - 1) * ledgerPageSize,
        ledgerSafePage * ledgerPageSize
      ),
    [sortedEggLedgerRows, ledgerSafePage, ledgerPageSize]
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
  }

  const parseAdjustmentIdFromSortKey = (sortKey: string): number | null => {
    if (!sortKey.startsWith("eggadj_")) return null
    const n = parseInt(sortKey.slice("eggadj_".length), 10)
    return Number.isFinite(n) ? n : null
  }

  const openCreateAdjustment = () => {
    setEditingAdjustmentId(null)
    setAdjForm({
      adjustmentType: "Correction",
      eggDelta: "",
      description: "",
      adjustmentDate: new Date().toISOString().split("T")[0],
    })
    setAdjustmentDialogOpen(true)
  }

  const openEditAdjustment = (row: EggLedgerRow) => {
    const id = parseAdjustmentIdFromSortKey(row.sortKey)
    if (id == null) return
    const a = eggAdjustments.find((x) => x.adjustmentId === id)
    if (!a) return
    setEditingAdjustmentId(id)
    setAdjForm({
      adjustmentType: a.adjustmentType as AdjType,
      eggDelta: String(a.eggDelta),
      description: a.description || "",
      adjustmentDate: a.adjustmentDate ? String(a.adjustmentDate).slice(0, 10) : new Date().toISOString().split("T")[0],
    })
    setAdjustmentDialogOpen(true)
  }

  const saveAdjustment = async () => {
    const delta = parseInt(adjForm.eggDelta.trim(), 10)
    if (!Number.isFinite(delta) || delta === 0) {
      toastFormGuide(toast, "Enter egg change as a whole number — positive adds eggs, negative removes. Zero is not allowed.")
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
        const res = await updateEggInventoryAdjustment(editingAdjustmentId, farmId, {
          userId,
          adjustmentDate: dateIso,
          adjustmentType: adjForm.adjustmentType,
          eggDelta: delta,
          description: adjForm.description.trim() || null,
        })
        if (!res.success) {
          toast({ title: "Update failed", description: res.message || "Could not update adjustment", variant: "destructive" })
          return
        }
        toast({ title: "Adjustment updated" })
      } else {
        const res = await createEggInventoryAdjustment({
          userId,
          farmId,
          adjustmentDate: dateIso,
          adjustmentType: adjForm.adjustmentType,
          eggDelta: delta,
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

  const deleteAdjustment = (row: EggLedgerRow) => {
    const id = parseAdjustmentIdFromSortKey(row.sortKey)
    if (id == null) return
    const { farmId } = getUserContext()
    if (!farmId) return
    setDeleteAdjustmentId(id)
  }

  const handleCopyEggsAtHand = () => {
    navigator.clipboard.writeText(String(Math.round(currentEggsAtHand)))
    toast({ title: "Copied", description: "Egg count copied to clipboard" })
  }

  const ledgerLastUpdated = lastUpdatedIso ? new Date(lastUpdatedIso) : null

  const handleRefresh = () => {
    setRefreshing(true)
    void loadData()
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
                <div className="w-10 h-10 shrink-0 bg-amber-100 rounded-lg flex items-center justify-center">
                  <BarChart3 className="w-5 h-5 text-amber-700" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Egg tracker</h1>
                  <p className="text-sm text-slate-600">
                    Ledger from egg sorting production, egg sales, and optional manual adjustments (like Cash at hand).
                  </p>
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
                <CardContent className="py-12 text-center text-slate-600">Loading egg tracker…</CardContent>
              </Card>
            ) : (
              <>
                <Card className="border-amber-200 bg-amber-50/50">
                  <CardHeader className="pb-2">
                    <div className={cn("flex justify-between gap-4", isMobile && "flex-col")}>
                      <div>
                        <CardDescription>Egg tracker</CardDescription>
                        <CardTitle className="text-base font-semibold text-slate-800 mt-1">Estimated egg inventory</CardTitle>
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
                            <DialogTitle>{editingAdjustmentId != null ? "Edit egg adjustment" : "Egg inventory adjustment"}</DialogTitle>
                            <DialogDescription>
                              Add or remove eggs without creating a production record. Positive count adds to on-hand; negative subtracts.
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
                              <Label>Egg change (whole eggs)</Label>
                              <NumberInput
                                
                                step={1}
                                placeholder="e.g. 50 or -20"
                                value={adjForm.eggDelta}
                                onChange={(e) => setAdjForm((p) => ({ ...p, eggDelta: e.target.value }))}
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
                            <Button type="button" onClick={saveAdjustment} disabled={adjSubmitting}>
                              {editingAdjustmentId != null ? "Update" : "Save"}
                            </Button>
                          </div>
                        </DialogContent>
                      </Dialog>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {/* Four equal columns, two rows, every tile the same width
                        and every left edge lined up down the card. Mixed spans
                        (three-across over four-across) filled the width but left
                        the two rows staggered against each other, which is what
                        made it look off.
                        Four columns needs eight cells for seven figures, so
                        "Last ledger event" — which used to float to the right of
                        the whole block — takes the eighth. It reads as the last
                        thing on the top row, and the grid has no hole in it.
                        On a phone the same eight cells go two across instead of
                        one, which halves the scrolling and — because eight
                        divides by two as well as by four — keeps each pair on
                        its own line: adjustments in/out, then totals in/out. */}
                    <div className={cn("grid gap-4 min-w-0", isMobile ? "grid-cols-2" : "grid-cols-4")}>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Eggs on hand</div>
                        <div className="mt-1 flex items-center gap-2 flex-wrap">
                          <span
                            className={cn(
                              "text-2xl font-bold tabular-nums",
                              currentEggsAtHand < 0 ? "text-red-600" : "text-slate-900"
                            )}
                          >
                            {Math.round(currentEggsAtHand).toLocaleString()}
                          </span>
                          <span className="text-sm text-slate-500">eggs</span>
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-slate-500 hover:text-slate-700"
                            onClick={handleCopyEggsAtHand}
                            aria-label="Copy egg count"
                          >
                            <Copy className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Egg produced</div>
                        <div className="mt-1 text-2xl font-bold text-sky-700 tabular-nums">
                          {totalEggsProducedLedger.toLocaleString()}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Egg sales (units)</div>
                        <div className="mt-1 text-2xl font-bold text-amber-800 tabular-nums">
                          {totalEggsSoldLedger.toLocaleString()}
                        </div>
                      </div>
                      {/* Same tile shape as the figures around it, and the
                          table's own date format, so the row reads as one band
                          rather than four numbers and a caption. It stays in
                          place on a phone too: at two across it closes the
                          second line, and moving it to the end would split the
                          adjustment pair across two lines to do it. */}
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Last ledger event</div>
                        <div className="mt-1 text-2xl font-bold text-slate-600 tabular-nums">
                          {ledgerLastUpdated ? formatDateShort(ledgerLastUpdated) : "—"}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Eggs in (adjustments)</div>
                        <div className="mt-1 text-2xl font-bold text-emerald-700 tabular-nums">
                          {adjustmentTotals.in.toLocaleString()}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Eggs out (adjustments)</div>
                        <div className="mt-1 text-2xl font-bold text-rose-600 tabular-nums">
                          {adjustmentTotals.out.toLocaleString()}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total eggs in</div>
                        <div className="mt-1 text-2xl font-bold text-emerald-600 tabular-nums">
                          {totalEggsInLedger.toLocaleString()}
                        </div>
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total eggs out</div>
                        <div className="mt-1 text-2xl font-bold text-red-600 tabular-nums">
                          {totalEggsOutLedger.toLocaleString()}
                        </div>
                      </div>
                    </div>
                    <p className="text-xs text-slate-500 mt-2">
                      Production adds good eggs; broken eggs and egg sales reduce the total. Use <strong>Add adjustment</strong> to
                      align counts after a stocktake (requires DB migration 012 on the API database).
                    </p>
                    {currentEggsAtHand < 0 && (
                      <p className="text-xs text-amber-900 mt-2 rounded-md border border-amber-200 bg-amber-100/80 px-2 py-1.5">
                        A negative count often means more egg sales were logged than production — confirm dates, production rows, or add
                        an adjustment.
                      </p>
                    )}
                  </CardContent>
                </Card>

                {/* Straight under the tiles, because it is the tiles it breaks
                    apart: both cards total the whole ledger, which is what
                    "Total eggs in" and "Total eggs out" above them count. It sat
                    below the ledger table at first, where its refusal to follow
                    the table's filters read as a bug rather than as a decision.
                    Side by side from lg up: in and out are meant to be read
                    against each other, and this is a full-width page with the
                    room for it. The Cash Flow insights dialog stacks the same
                    two cards because it is a narrow dialog — that reason does
                    not carry over here. */}
                {(eggsInBySource.length > 0 || eggsOutByUse.length > 0) && (
                  <div className="space-y-3">
                    <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
                      Breakdown
                    </h2>
                    <div className="grid gap-3 lg:grid-cols-2 items-start">
                      <FlowBreakdownCard
                        title="Eggs in by source"
                        direction="in"
                        buckets={eggsInBySource}
                        total={totalEggsInLedger}
                        fmtMoney={(n) => n.toLocaleString()}
                        description="Every movement that added eggs to stock — the whole ledger, so it breaks down the totals above rather than the filtered table below."
                        emptyText="No eggs have come in yet."
                      />
                      <FlowBreakdownCard
                        title="Eggs out by use"
                        direction="out"
                        buckets={eggsOutByUse}
                        total={totalEggsOutLedger}
                        fmtMoney={(n) => n.toLocaleString()}
                        description="Every movement that took eggs out of stock — sales, internal use, load-outs and the non-saleable ones."
                        emptyText="No eggs have gone out yet."
                      />
                    </div>
                  </div>
                )}

                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Egg inventory ledger</CardTitle>
                    <CardDescription>Chronological ledger; filter the table below</CardDescription>
                    <div className={cn("grid gap-2 pt-3", isMobile ? "grid-cols-2" : "grid-cols-5")}>
                      <Select value={ledgerTypeFilter} onValueChange={setLedgerTypeFilter}>
                        <SelectTrigger className={cn(isMobile ? "col-span-2" : "")}>
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
                        className={cn(isMobile ? "col-span-2" : "col-span-2")}
                      />
                      <Input type="date" value={ledgerDateFrom} onChange={(e) => setLedgerDateFrom(e.target.value)} />
                      <Input type="date" value={ledgerDateTo} onChange={(e) => setLedgerDateTo(e.target.value)} />
                    </div>
                    <div className="pt-2">
                      <Button type="button" variant="outline" size="sm" onClick={clearLedgerFilters}>
                        Reset ledger filters
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {sortedEggLedgerRows.length === 0 ? (
                      <p className="text-slate-600 py-8 text-center text-sm">
                        No ledger rows yet. Add egg production and egg sales (product name contains &quot;egg&quot;).
                      </p>
                    ) : isMobile && !showLedgerTableMobile ? (
                      /* Scorecards, following /poultry-daily-closing: one card
                         per row, open by default, striped so consecutive rows
                         are told apart at a glance. Blue here rather than that
                         page's amber. In and out keep their green and red —
                         they are the two directions the ledger exists to tell
                         apart, and painting them blue would spend the meaning
                         to gain a colour. */
                      <div className="space-y-3">
                        {paginatedEggLedgerRows.map((row, idx) => {
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
                                          <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">In</p>
                                          <p className="text-xl font-extrabold leading-tight text-emerald-800 tabular-nums">
                                            {row.in > 0 ? row.in.toLocaleString() : "—"}
                                          </p>
                                        </div>
                                        <div className="rounded-lg border border-red-300 bg-red-100 px-3 py-2 shadow-sm">
                                          <p className="text-[11px] font-semibold uppercase tracking-wide text-red-900">Out</p>
                                          <p className="text-xl font-extrabold leading-tight text-red-800 tabular-nums">
                                            {row.out > 0 ? row.out.toLocaleString() : "—"}
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
                                    {/* Only adjustments can be edited or removed here; every
                                        other row belongs to the record that posted it. */}
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
                          <span className="text-xs text-slate-600">Table view • Scroll for more</span>
                          <Button type="button" variant="ghost" size="sm" onClick={() => setShowLedgerTableMobile(false)}>
                            <ChevronUp className="mr-1 h-4 w-4" /> Cards
                          </Button>
                        </div>
                      )}
                      <div className="overflow-x-auto table-scroll-wrapper pb-2" style={{ WebkitOverflowScrolling: "touch" }}>
                        <Table className="w-full min-w-[520px]">
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
                                label="In"
                                sortKey="in"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                              <SortableHeader
                                label="Out"
                                sortKey="out"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                              <TableHead className="text-right w-[100px]">Actions</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {paginatedEggLedgerRows.map((row) => {
                              const isAdj = row.type === "Adjustment"
                              return (
                                <TableRow key={row.sortKey}>
                                  <TableCell className="font-medium whitespace-nowrap">
                                    {row.date ? formatDateShort(row.date) : "—"}
                                  </TableCell>
                                  <TableCell>{row.type}</TableCell>
                                  <TableCell className="max-w-[220px] truncate" title={row.description}>
                                    {row.description}
                                  </TableCell>
                                  <TableCell className="text-right text-emerald-600 tabular-nums">
                                    {row.in > 0 ? row.in.toLocaleString() : "—"}
                                  </TableCell>
                                  <TableCell className="text-right text-red-600 tabular-nums">
                                    {row.out > 0 ? row.out.toLocaleString() : "—"}
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
                                      <span className="text-slate-300">—</span>
                                    )}
                                  </TableCell>
                                </TableRow>
                              )
                            })}
                          </TableBody>
                          <TableFooter>
                            <TableRow className="bg-slate-50 hover:bg-slate-50">
                              <TableCell colSpan={3} className="font-medium text-slate-700">
                                {ledgerFiltersActive ? "Filtered total" : "Total"}
                                <span className="ml-2 font-normal text-slate-500">
                                  ({sortedEggLedgerRows.length.toLocaleString()}{" "}
                                  {sortedEggLedgerRows.length === 1 ? "row" : "rows"})
                                </span>
                              </TableCell>
                              <TableCell className="text-right font-bold text-emerald-700 tabular-nums">
                                {filteredLedgerInTotal.toLocaleString()}
                              </TableCell>
                              <TableCell className="text-right font-bold text-red-700 tabular-nums">
                                {filteredLedgerOutTotal.toLocaleString()}
                              </TableCell>
                              <TableCell />
                            </TableRow>
                          </TableFooter>
                        </Table>
                      </div>
                      </>
                    )}
                    {sortedEggLedgerRows.length > 0 && (
                      <div className="flex flex-col gap-2 border-t px-2 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-4 bg-slate-50/80">
                        <div className="flex flex-col items-center gap-2 sm:flex-row sm:gap-3">
                          <p className="text-xs text-slate-600 text-center sm:text-left">
                            Showing {(ledgerSafePage - 1) * ledgerPageSize + 1}-
                            {Math.min(ledgerSafePage * ledgerPageSize, sortedEggLedgerRows.length)} of{" "}
                            {sortedEggLedgerRows.length}
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
        title="Delete egg inventory adjustment?"
        description="This adjustment will be permanently removed from the ledger."
        successTitle="Adjustment removed"
        errorTitle="Delete failed"
        onConfirm={async () => {
          if (deleteAdjustmentId === null) return { success: false, message: "Missing id" }
          const { farmId } = getUserContext()
          if (!farmId) return { success: false, message: "Missing farm context" }
          const res = await deleteEggInventoryAdjustment(deleteAdjustmentId, farmId)
          if (res.success) void loadData()
          return res
        }}
      />
    </div>
  )
}

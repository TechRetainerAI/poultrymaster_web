"use client"

import { useCallback, useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { BarChart3, Copy, RefreshCw, Plus, Pencil, Trash2 } from "lucide-react"
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
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { buildEggStockLedger, type EggLedgerRow } from "@/lib/utils/egg-ledger"

const LEDGER_PAGE_SIZE = 15

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
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [refreshing, setRefreshing] = useState(false)

  const [adjustmentDialogOpen, setAdjustmentDialogOpen] = useState(false)
  const [editingAdjustmentId, setEditingAdjustmentId] = useState<number | null>(null)
  const [adjSubmitting, setAdjSubmitting] = useState(false)
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
    const [eggRes, flocksRes, salesRes, adjRes] = await Promise.all([
      getEggProductions(userId, farmId),
      getFlocks(userId, farmId),
      getSales(userId, farmId),
      getEggInventoryAdjustments(farmId),
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

  const eggStockLedger = useMemo(
    () => buildEggStockLedger(eggProductions, sales, flocks, adjustmentLedgerInput),
    [eggProductions, sales, flocks, adjustmentLedgerInput]
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
        if (key === "date") return new Date(item.date)
        if (key === "type") return item.type
        if (key === "description") return item.description
        if (key === "in") return Number(item.in) || 0
        if (key === "out") return Number(item.out) || 0
        return (item as EggLedgerRow & Record<string, unknown>)[key]
      }),
    [filteredEggLedgerRows, ledgerSortKey, ledgerSortDir]
  )

  const ledgerTotalPages = Math.max(1, Math.ceil(sortedEggLedgerRows.length / LEDGER_PAGE_SIZE))
  const ledgerSafePage = Math.min(ledgerPage, ledgerTotalPages)
  const paginatedEggLedgerRows = useMemo(
    () =>
      sortedEggLedgerRows.slice(
        (ledgerSafePage - 1) * LEDGER_PAGE_SIZE,
        ledgerSafePage * LEDGER_PAGE_SIZE
      ),
    [sortedEggLedgerRows, ledgerSafePage]
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

  const deleteAdjustment = async (row: EggLedgerRow) => {
    const id = parseAdjustmentIdFromSortKey(row.sortKey)
    if (id == null) return
    const { farmId } = getUserContext()
    if (!farmId) return
    if (!confirm("Delete this egg inventory adjustment?")) return
    const res = await deleteEggInventoryAdjustment(id, farmId)
    if (!res.success) {
      toast({ title: "Delete failed", description: res.message, variant: "destructive" })
      return
    }
    toast({ title: "Adjustment removed" })
    void loadData()
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
                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm">
                    <Link href="/egg-production" className="text-blue-600 hover:underline font-medium">
                      Egg sorting
                    </Link>
                    <Link href="/egg-production#totals-by-size" className="text-blue-600 hover:underline font-medium">
                      Totals by size
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
                              <Input
                                type="number"
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
                    <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-start justify-between")}>
                      <div className={cn("grid gap-4", isMobile ? "grid-cols-1" : "grid-cols-2")}>
                        <div>
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
                        <div>
                          <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Egg sales (units)</div>
                          <div className="mt-1 text-2xl font-bold text-amber-800 tabular-nums">
                            {totalEggsSoldLedger.toLocaleString()}
                          </div>
                        </div>
                      </div>
                      <div className="text-sm text-slate-500 shrink-0">
                        Last ledger event:{" "}
                        {ledgerLastUpdated
                          ? ledgerLastUpdated.toLocaleDateString("en-GB", {
                              day: "2-digit",
                              month: "short",
                              year: "numeric",
                            })
                          : "—"}
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
                    ) : (
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
                        </Table>
                      </div>
                    )}
                    {sortedEggLedgerRows.length > 0 && (
                      <div className="flex flex-col gap-2 border-t px-2 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-4 bg-slate-50/80">
                        <p className="text-xs text-slate-600 text-center sm:text-left">
                          Showing {(ledgerSafePage - 1) * LEDGER_PAGE_SIZE + 1}-
                          {Math.min(ledgerSafePage * LEDGER_PAGE_SIZE, sortedEggLedgerRows.length)} of{" "}
                          {sortedEggLedgerRows.length}
                        </p>
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
    </div>
  )
}

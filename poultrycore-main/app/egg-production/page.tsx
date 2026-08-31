"use client"

import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Plus, Pencil, Trash2, Egg, Search, RefreshCw, Loader2, ChevronDown, ChevronUp, Filter } from "lucide-react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { getEggProductions, deleteEggProduction, type EggProduction } from "@/lib/api/egg-production"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet"
import {
  MOBILE_FILTER_SHEET_CONTENT_CLASS,
  MOBILE_FILTER_SELECT_CONTENT_CLASS,
  MOBILE_FILTERS_TOOLBAR_ROW_CLASS,
  MOBILE_FILTERS_TRIGGER_BUTTON_CLASS,
  MobileFilterSheetBody,
  MobileFilterSheetFooter,
  MobileFilterSheetHeader,
} from "@/components/dashboard/mobile-filters"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { resolveEggProductionFlockName } from "@/lib/utils/resolve-egg-flock-name"
import {
  EGG_GRADE_OPTIONS,
  EGG_GRADE_SELECT_VALUE_NONE,
  eggGradeFromApi,
  formatEggGradeLabel,
} from "@/lib/constants/egg-grade"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { createProductionRecord, getProductionRecords, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"

export default function EggProductionsPage() {
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const [eggProductions, setEggProductions] = useState<EggProduction[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage, setItemsPerPage] = useState(10)

  // Delete confirmation state
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }

  // Filter states
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [selectedFlock, setSelectedFlock] = useState<string>("ALL")
  const [selectedEggGrade, setSelectedEggGrade] = useState<string>("ALL")

  // Mobile: card list by default, filters in sheet
  const isMobile = useIsMobile()

  // This table hides most of its columns behind `sm:`/`md:`/`lg:` breakpoints.
  // A phone never reaches any of them, so on mobile — where the table renders
  // only because the reader chose it over the cards — the hiding is switched
  // off entirely and the table scrolls sideways instead.
  // The class strings are written out in full: Tailwind scans source text, so a
  // composed `hidden ${bp}:table-cell` would never be generated.
  const HIDE_BELOW = {
    sm: "hidden sm:table-cell",
    md: "hidden md:table-cell",
    lg: "hidden lg:table-cell",
    xl: "hidden xl:table-cell",
  } as const
  const hideBelow = (bp: keyof typeof HIDE_BELOW) => (isMobile ? "" : HIDE_BELOW[bp])
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [syncScope, setSyncScope] = useState<"selected" | "all">("selected")
  const [syncingToday, setSyncingToday] = useState(false)
  const [syncCheckMessage, setSyncCheckMessage] = useState("")

  const [draftDateFrom, setDraftDateFrom] = useState("")
  const [draftDateTo, setDraftDateTo] = useState("")
  const [draftSelectedFlock, setDraftSelectedFlock] = useState<string>("ALL")
  const [draftSelectedEggGrade, setDraftSelectedEggGrade] = useState<string>("ALL")

  const hasActiveFilters =
    !!search || !!dateFrom || !!dateTo || selectedFlock !== "ALL" || selectedEggGrade !== "ALL"
  const hasDraftChanges =
    draftDateFrom !== dateFrom ||
    draftDateTo !== dateTo ||
    draftSelectedFlock !== selectedFlock ||
    draftSelectedEggGrade !== selectedEggGrade

  useEffect(() => {
    loadData()
  }, [])

  const loadData = async () => {
    const { farmId, userId } = getUserContext()
    
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      setLoading(false)
      return
    }

    const [eggProductionsResult, flocksResult] = await Promise.all([
      getEggProductions(userId, farmId),
      getFlocks(userId, farmId),
    ])
    
    if (eggProductionsResult.success && eggProductionsResult.data) {
      setEggProductions(eggProductionsResult.data)
    } else {
      setError(eggProductionsResult.message || "Failed to load egg productions")
    }

    if (flocksResult.success && flocksResult.data) {
      setFlocks(flocksResult.data)
    }

    setLoading(false)
  }

  const openDeleteDialog = (id: number) => {
    setDeletingId(id)
    setDeleteDialogOpen(true)
  }

  const handleDelete = async () => {
    if (!deletingId) return

    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }

    setIsDeleting(true)

    const result = await deleteEggProduction(deletingId, userId, farmId)

    if (result.success) {
      toast({
        title: "Record deleted",
        description: "The egg production record has been successfully deleted.",
      })
      loadData()
      setCurrentPage(1)
    } else {
      toast({
        title: "Delete failed",
        description: result.message || "Something went wrong. Please try again.",
        variant: "destructive",
      })
    }

    setIsDeleting(false)
    setDeleteDialogOpen(false)
    setDeletingId(null)
  }

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

  const clearFilters = () => {
    setSearch("")
    setDateFrom("")
    setDateTo("")
    setSelectedFlock("ALL")
    setDraftDateFrom("")
    setDraftDateTo("")
    setDraftSelectedFlock("ALL")
    setSelectedEggGrade("ALL")
    setDraftSelectedEggGrade("ALL")
  }

  const syncDraftFromCommitted = () => {
    setDraftDateFrom(dateFrom)
    setDraftDateTo(dateTo)
    setDraftSelectedFlock(selectedFlock)
    setDraftSelectedEggGrade(selectedEggGrade)
  }

  const applyMobileFilters = () => {
    setDateFrom(draftDateFrom)
    setDateTo(draftDateTo)
    setSelectedFlock(draftSelectedFlock)
    setSelectedEggGrade(draftSelectedEggGrade)
    setCurrentPage(1)
    setFiltersOpen(false)
      toast({ title: "Filters applied", description: "Egg sorting list updated." })
  }

  const formatDateShort = (d: string | Date) => {
    const dt = typeof d === 'string' ? new Date(d) : d
    return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' })
  }

  const getFlockName = (prod: EggProduction) => resolveEggProductionFlockName(prod, flocks)

  useEffect(() => {
    const evaluateDiscrepancies = async () => {
      const { farmId, userId } = getUserContext()
      if (!farmId || !userId) return

      const todayKey = toLocalDateKey(new Date().toISOString())
      const todaysEntries = eggProductions.filter((p) => toLocalDateKey(p.productionDate) === todayKey)
      const scopedEntries =
        syncScope === "selected" && selectedFlock !== "ALL"
          ? todaysEntries.filter((p) => String(p.flockId) === selectedFlock)
          : todaysEntries

      if (scopedEntries.length === 0) {
        setSyncCheckMessage("")
        return
      }

      const groupedEgg = new Map<number, number>()
      for (const row of scopedEntries) {
        const fid = Number(row.flockId)
        if (!fid) continue
        const total = (Number(row.production9AM) || 0) + (Number(row.production12PM) || 0) + (Number(row.production4PM) || 0) + (Number((row as any).production4thPick) || 0)
        groupedEgg.set(fid, (groupedEgg.get(fid) || 0) + total)
      }

      const prodRes = await getProductionRecords(userId, farmId)
      const prodData = prodRes.success && prodRes.data ? prodRes.data : []
      const groupedProd = new Map<number, number>()
      for (const r of prodData) {
        if (toLocalDateKey((r as any).date) !== todayKey) continue
        const fid = Number((r as any).flockId)
        if (!fid) continue
        if (syncScope === "selected" && selectedFlock !== "ALL" && String(fid) !== selectedFlock) continue
        groupedProd.set(fid, (groupedProd.get(fid) || 0) + (Number((r as any).totalProduction) || 0))
      }

      const mismatches: string[] = []
      groupedEgg.forEach((eggTotal, fid) => {
        const prodTotal = groupedProd.get(fid) || 0
        if (eggTotal !== prodTotal) {
          mismatches.push(`Flock #${fid}: Egg Production ${eggTotal} vs Production Records ${prodTotal}`)
        }
      })

      if (mismatches.length > 0) {
        setSyncCheckMessage(`Discrepancy detected for today. ${mismatches.join(" | ")}`)
      } else {
        setSyncCheckMessage("")
      }
    }

    void evaluateDiscrepancies()
  }, [eggProductions, syncScope, selectedFlock])

  const handleSyncTodaysTotals = async () => {
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      toast({ title: "Session issue", description: "Please log in again.", variant: "destructive" })
      return
    }

    const todayKey = toLocalDateKey(new Date().toISOString())
    const todaysEntries = eggProductions.filter((p) => toLocalDateKey(p.productionDate) === todayKey)
    const scopedEntries =
      syncScope === "selected" && selectedFlock !== "ALL"
        ? todaysEntries.filter((p) => String(p.flockId) === selectedFlock)
        : todaysEntries

    if (scopedEntries.length === 0) {
      toast({
        title: "Nothing to sync",
        description: "No egg-production entries found for today in this scope.",
      })
      return
    }

    setSyncingToday(true)
    try {
      const grouped = new Map<number, { p9: number; p12: number; p4: number; p4th: number; broken: number }>()
      for (const row of scopedEntries) {
        const fid = Number(row.flockId)
        if (!fid) continue
        const curr = grouped.get(fid) ?? { p9: 0, p12: 0, p4: 0, p4th: 0, broken: 0 }
        curr.p9 += Number(row.production9AM) || 0
        curr.p12 += Number(row.production12PM) || 0
        curr.p4 += Number(row.production4PM) || 0
        curr.p4th += Number((row as any).production4thPick) || 0
        curr.broken += Number(row.brokenEggs) || 0
        grouped.set(fid, curr)
      }

      if (grouped.size === 0) {
        toast({ title: "Nothing to sync", description: "No valid flock totals were found for today." })
        return
      }

      const prodRes = await getProductionRecords(userId, farmId)
      const existing = prodRes.success && prodRes.data ? prodRes.data : []
      let updated = 0
      let created = 0

      for (const [flockId, sums] of grouped.entries()) {
        const flock = flocks.find((f) => Number((f as any).flockId) === flockId)
        if (!flock) continue

        const total = sums.p9 + sums.p12 + sums.p4 + sums.p4th
        const todayIso = `${todayKey}T00:00:00Z`
        const matched = existing.find(
          (r) => Number((r as any).flockId) === flockId && toLocalDateKey((r as any).date) === todayKey
        )

        if (matched) {
          const updatePayload: ProductionRecordInput = {
            farmId: (matched as any).farmId ?? farmId,
            userId: (matched as any).userId ?? userId,
            createdBy: (matched as any).createdBy ?? userId,
            updatedBy: userId,
            ageInDays: Number((matched as any).ageInDays) || 0,
            ageInWeeks: Number((matched as any).ageInWeeks) || 0,
            date: (matched as any).date ?? todayIso,
            flockId,
            noOfBirds: Number((matched as any).noOfBirds) || 0,
            mortality: Number((matched as any).mortality) || 0,
            noOfBirdsLeft: Number((matched as any).noOfBirdsLeft) || 0,
            feedKg: Number((matched as any).feedKg) || 0,
            medication: (matched as any).medication || "None",
            production9AM: sums.p9,
            production12PM: sums.p12,
            production4PM: sums.p4,
            production4thPick: sums.p4th,
            brokenEggs: sums.broken,
            totalProduction: total,
          }
          await updateProductionRecord((matched as any).id, updatePayload)
          updated += 1
        } else {
          const startKey = toLocalDateKey((flock as any).startDate || todayIso)
          const startDate = new Date(`${startKey}T00:00:00Z`)
          const todayDate = new Date(todayIso)
          const ageDays = Math.max(0, Math.floor((todayDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24)))
          const birds = Number((flock as any).quantity) || 0

          const payload: ProductionRecordInput = {
            farmId,
            userId,
            createdBy: userId,
            updatedBy: userId,
            date: todayIso,
            flockId,
            ageInDays: ageDays,
            ageInWeeks: Math.floor(ageDays / 7),
            noOfBirds: birds,
            mortality: 0,
            noOfBirdsLeft: birds,
            feedKg: 0,
            medication: "None",
            production9AM: sums.p9,
            production12PM: sums.p12,
            production4PM: sums.p4,
            production4thPick: sums.p4th,
            brokenEggs: sums.broken,
            totalProduction: total,
          }
          await createProductionRecord(payload)
          created += 1
        }
      }

      toast({
        title: "Today's totals synced",
        description: `Updated ${updated} and created ${created} production record(s) for ${todayKey}.`,
      })
    } catch (e) {
      console.error("[EggProduction] Sync today's totals failed:", e)
      toast({
        title: "Sync failed",
        description: "Could not sync today's totals. Please try again.",
        variant: "destructive",
      })
    } finally {
      setSyncingToday(false)
    }
  }

  const filteredEggProductions = useMemo(() => {
    let currentList = eggProductions

    if (search) {
      const query = search.toLowerCase()
      currentList = currentList.filter(
        (prod) =>
          getFlockName(prod).toLowerCase().includes(query) ||
          (prod.notes ?? "").toLowerCase().includes(query) ||
          (prod.eggGrade ?? "").toLowerCase().includes(query) ||
          formatEggGradeLabel(prod.eggGrade).toLowerCase().includes(query)
      )
    }

    if (selectedEggGrade !== "ALL") {
      if (selectedEggGrade === EGG_GRADE_SELECT_VALUE_NONE) {
        currentList = currentList.filter((prod) => !(prod.eggGrade ?? "").trim())
      } else {
        currentList = currentList.filter((prod) => eggGradeFromApi(prod.eggGrade) === selectedEggGrade)
      }
    }

    if (dateFrom) {
      currentList = currentList.filter((prod) => toLocalDateKey(prod.productionDate) >= dateFrom)
    }
    if (dateTo) {
      currentList = currentList.filter((prod) => toLocalDateKey(prod.productionDate) <= dateTo)
    }
    if (selectedFlock !== "ALL") {
      currentList = currentList.filter(prod => prod.flockId === parseInt(selectedFlock))
    }

    return currentList
  }, [eggProductions, search, dateFrom, dateTo, selectedFlock, selectedEggGrade])

  const totalEggs = useMemo(() => filteredEggProductions.reduce((sum, p) => sum + p.totalProduction, 0), [filteredEggProductions]);
  const totalBroken = useMemo(() => filteredEggProductions.reduce((sum, p) => sum + (p.brokenEggs ?? 0), 0), [filteredEggProductions]);
  const avgProduction = useMemo(() => filteredEggProductions.length ? totalEggs / filteredEggProductions.length : 0, [totalEggs, filteredEggProductions.length]);

  const EGGS_PER_CRATE = 30
  const totalEggsCrates = Math.floor(totalEggs / EGGS_PER_CRATE)
  const totalEggsPieces = totalEggs % EGGS_PER_CRATE

  // Sort and paginate
  const sortedEggProductions = useMemo(() => sortData(filteredEggProductions, sortKey, sortDir, (item: any, key: string) => {
    if (key === "productionDate") return new Date(item.productionDate)
    if (key === "totalProduction") return Number(item.totalProduction) || 0
    if (key === "brokenEggs") return Number(item.brokenEggs) || 0
    if (key === "production9AM") return Number(item.production9AM) || 0
    if (key === "production12PM") return Number(item.production12PM) || 0
    if (key === "production4PM") return Number(item.production4PM) || 0
    if (key === "production4thPick") return Number(item.production4thPick) || 0
    if (key === "eggGrade") return eggGradeFromApi((item as EggProduction).eggGrade).toLowerCase()
    return (item as any)[key]
  }), [filteredEggProductions, sortKey, sortDir])
  const totalPages = Math.ceil(sortedEggProductions.length / itemsPerPage)
  const startIndex = (currentPage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const currentEggProductions = sortedEggProductions.slice(startIndex, endIndex)

  const handlePageChange = (page: number) => {
    setCurrentPage(page)
  }
  const handlePreviousPage = () => {
    if (currentPage > 1) {
      setCurrentPage(currentPage - 1)
    }
  }

  const handleNextPage = () => {
    if (currentPage < totalPages) {
      setCurrentPage(currentPage + 1)
    }
  }

  const getPageNumbers = () => {
    const pages = []
    const maxVisiblePages = 5
    
    if (totalPages <= maxVisiblePages) {
      for (let i = 1; i <= totalPages; i++) {
        pages.push(i)
      }
    } else {
      if (currentPage <= 3) {
        for (let i = 1; i <= 4; i++) {
          pages.push(i)
        }
        pages.push('ellipsis')
        pages.push(totalPages)
      } else if (currentPage >= totalPages - 2) {
        pages.push(1)
        pages.push('ellipsis')
        for (let i = totalPages - 3; i <= totalPages; i++) {
          pages.push(i)
        }
      } else {
        pages.push(1)
        pages.push('ellipsis')
        for (let i = currentPage - 1; i <= currentPage + 1; i++) {
          pages.push(i)
        }
        pages.push('ellipsis')
        pages.push(totalPages)
      }
    }
    
    return pages
  }


  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-yellow-100 rounded-lg flex items-center justify-center">
                  <Egg className="w-5 h-5 text-yellow-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Egg Sorting</h1>
                  <p className="text-sm text-slate-600">
                    Daily collection by flock (9am / 12pm / 4pm) for the filters below.
                  </p>
                </div>
              </div>
              <Link href="/egg-production/new" prefetch={true} className="w-full sm:w-auto">
                <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700">
                  <Plus className="w-4 h-4" />
                  Add Egg Sorting record
                </Button>
              </Link>
            </div>

            {/* Filters - Mobile: Sheet; Desktop: Inline */}
            {isMobile ? (
              <div className="space-y-3 w-full min-w-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search by flock or notes..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-10 h-11" />
                </div>
                <div className={MOBILE_FILTERS_TOOLBAR_ROW_CLASS}>
                  <Sheet
                    open={filtersOpen}
                    onOpenChange={(open) => {
                      setFiltersOpen(open)
                      syncDraftFromCommitted()
                    }}
                  >
                    <SheetTrigger asChild>
                      <Button variant="outline" className={MOBILE_FILTERS_TRIGGER_BUTTON_CLASS}>
                        <Filter className="h-4 w-4" />
                        <span className="truncate">Filters</span>
                        {hasActiveFilters && (
                          <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-orange-500 text-white text-xs flex items-center justify-center">
                            {
                              [search, dateFrom, dateTo, selectedFlock !== "ALL", selectedEggGrade !== "ALL"].filter(
                                Boolean
                              ).length
                            }
                          </span>
                        )}
                      </Button>
                    </SheetTrigger>
                    <SheetContent side="bottom" className={MOBILE_FILTER_SHEET_CONTENT_CLASS}>
                      <MobileFilterSheetHeader />
                      <MobileFilterSheetBody>
                        <div className="space-y-3">
                          <p className="text-sm font-medium text-slate-700">Date range</p>
                          <div className="flex flex-col gap-4">
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="egg-filter-from" className="text-xs font-medium text-slate-500">
                                Start date
                              </label>
                              <Input
                                id="egg-filter-from"
                                type="date"
                                value={draftDateFrom}
                                onChange={(e) => setDraftDateFrom(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="egg-filter-to" className="text-xs font-medium text-slate-500">
                                End date
                              </label>
                              <Input
                                id="egg-filter-to"
                                type="date"
                                value={draftDateTo}
                                onChange={(e) => setDraftDateTo(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                          </div>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Flock</label>
                          <Select value={draftSelectedFlock} onValueChange={setDraftSelectedFlock}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="All Flocks" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All Flocks</SelectItem>
                              {flocks.map((f) => (
                                <SelectItem key={f.flockId} value={f.flockId.toString()}>
                                  {f.name} ({f.quantity} birds)
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Egg size</label>
                          <Select value={draftSelectedEggGrade} onValueChange={setDraftSelectedEggGrade}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="All sizes" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All sizes</SelectItem>
                              {EGG_GRADE_OPTIONS.map((o) => (
                                <SelectItem key={o.value} value={o.value}>
                                  {o.label}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      </MobileFilterSheetBody>
                      <MobileFilterSheetFooter>
                        <div className="flex gap-3">
                          <Button
                            type="button"
                            variant="outline"
                            className="h-12 flex-1"
                            onClick={() => {
                              clearFilters()
                              setFiltersOpen(false)
                              toast({ title: "Filters cleared" })
                            }}
                          >
                            Clear all
                          </Button>
                          <Button type="button" className="h-12 flex-1" onClick={applyMobileFilters} disabled={!hasDraftChanges}>
                            Apply
                          </Button>
                        </div>
                      </MobileFilterSheetFooter>
                    </SheetContent>
                  </Sheet>
                </div>
              </div>
            ) : (
              <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded-lg border">
                <div className="relative w-[240px]">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search by flock or notes..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                </div>
                <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" />
                <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" />
                <Select value={selectedFlock} onValueChange={setSelectedFlock}>
                  <SelectTrigger className="w-[180px]"><SelectValue placeholder="Flock" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Flocks</SelectItem>
                    {flocks.map(f => (
                      <SelectItem key={f.flockId} value={f.flockId.toString()}>{f.name} ({f.quantity} birds)</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select value={selectedEggGrade} onValueChange={setSelectedEggGrade}>
                  <SelectTrigger className="w-[160px]">
                    <SelectValue placeholder="Size" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All sizes</SelectItem>
                    {EGG_GRADE_OPTIONS.map((o) => (
                      <SelectItem key={o.value} value={o.value}>
                        {o.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <div className="ml-auto">
                  <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                </div>
              </div>
            )}


            <Card className="bg-white">
              <CardContent className="p-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div className="space-y-2">
                  <p className="text-sm font-semibold text-slate-900">Sync today's totals to Production Records</p>
                  <p className="text-xs text-slate-500">
                    Only syncs entries for today ({toLocalDateKey(new Date().toISOString())}), as discussed.
                  </p>
                  <p className="text-xs text-slate-500">
                    For egg inventory and the ledger, open{" "}
                    <Link href="/egg-tracker" className="text-blue-600 font-medium hover:underline">
                      Egg tracker
                    </Link>
                    .
                  </p>
                  {syncCheckMessage && (
                    <Alert variant="destructive" className="mt-2">
                      <AlertDescription className="text-xs">{syncCheckMessage}</AlertDescription>
                    </Alert>
                  )}
                  <RadioGroup
                    className="flex flex-wrap gap-4"
                    value={syncScope}
                    onValueChange={(v) => setSyncScope(v as "selected" | "all")}
                  >
                    <div className="flex items-center gap-2">
                      <RadioGroupItem value="selected" id="sync-selected-flock" />
                      <Label htmlFor="sync-selected-flock" className="text-sm">
                        Selected flock
                      </Label>
                    </div>
                    <div className="flex items-center gap-2">
                      <RadioGroupItem value="all" id="sync-all-flocks" />
                      <Label htmlFor="sync-all-flocks" className="text-sm">
                        All flocks
                      </Label>
                    </div>
                  </RadioGroup>
                </div>
                <Button
                  onClick={handleSyncTodaysTotals}
                  disabled={syncingToday || eggProductions.length === 0 || (syncScope === "selected" && selectedFlock === "ALL")}
                  className="sm:self-start"
                >
                  {syncingToday ? "Syncing..." : "Sync Today's Total"}
                </Button>
              </CardContent>
            </Card>

            {/* Error Alert */}
            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Metrics - Mobile: 2-col grid */}
            {!loading && (
              <div className={cn("grid gap-3", isMobile ? "grid-cols-2" : "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4")}>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Total Eggs</div>
                  <div className={cn("font-bold text-emerald-600", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalEggs.toLocaleString()}</div>
                  <div className="text-xs text-slate-400 mt-0.5">{totalEggsCrates}c + {totalEggsPieces}p</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Crates</div>
                  <div className={cn("font-bold text-amber-600", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalEggsCrates.toLocaleString()}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Broken</div>
                  <div className={cn("font-bold text-red-600", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalBroken.toLocaleString()}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Avg</div>
                  <div className={cn("font-bold text-slate-900", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{avgProduction.toFixed(2)}</div>
                </div>
              </div>
            )}

            {/* Content */}
            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <p className="text-slate-600">Loading egg production records...</p>
                </CardContent>
              </Card>
            ) : filteredEggProductions.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="p-12 text-center">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4">
                    <Egg className="w-8 h-8 text-slate-400" />
                  </div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No production records found</h3>
                  <p className="text-slate-600 mb-6">Get started by creating your first egg production record.</p>
                  <Link href="/egg-production/new" prefetch={true}>
                    <Button className="gap-2 bg-blue-600 hover:bg-blue-700">
                      <Plus className="w-4 h-4" />
                      Add Egg Sorting record
                    </Button>
                  </Link>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {currentEggProductions.map((prod, idx) => (
                        <Collapsible key={prod.productionId} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="relative cursor-pointer">
                                <div className="min-w-0 flex-1 pr-8">
                                  <div className="flex items-center gap-2">
                                    <span className="font-semibold text-slate-900">{formatDateShort(prod.productionDate)}</span>
                                    <span className="text-slate-500">•</span>
                                    <span className="text-slate-600 truncate">{getFlockName(prod)}</span>
                                  </div>
                                  <div className="mt-1 flex items-baseline gap-3 flex-wrap">
                                    <span className="text-xl font-bold text-emerald-600">{prod.totalProduction}</span>
                                    <span className="text-xs text-slate-500">eggs</span>
                                    <span className="text-xs font-medium text-violet-700 bg-violet-50 border border-violet-200 rounded px-1.5 py-0.5">
                                      {formatEggGradeLabel(prod.eggGrade)}
                                    </span>
                                    {(prod.brokenEggs ?? 0) > 0 && (
                                      <>
                                        <span className="text-slate-400">•</span>
                                        <span className="text-sm text-red-600">{prod.brokenEggs} broken</span>
                                      </>
                                    )}
                                  </div>
                                </div>
                                <ChevronDown className="absolute right-0 top-0 h-5 w-5 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">1st Pick</span> <span className="font-medium text-blue-700">{prod.production9AM ?? '-'}</span></div>
                                  <div><span className="text-slate-500">2nd Pick</span> <span className="font-medium text-orange-700">{prod.production12PM ?? '-'}</span></div>
                                  <div><span className="text-slate-500">3rd Pick</span> <span className="font-medium text-purple-700">{prod.production4PM ?? '-'}</span></div>
                                  <div><span className="text-slate-500">4th Pick</span> <span className="font-medium text-teal-700">{(prod as any).production4thPick ?? '-'}</span></div>
                                  <div><span className="text-slate-500">Broken</span> <span className="font-medium text-red-600">{prod.brokenEggs ?? 0}</span></div>
                                  <div className="col-span-2">
                                    <span className="text-slate-500">Size</span>{" "}
                                    <span className="font-medium text-violet-800">{formatEggGradeLabel(prod.eggGrade)}</span>
                                  </div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Link href={`/egg-production/${prod.productionId}`} prefetch={true} className="flex-1">
                                    <Button variant="outline" size="sm" className="w-full h-10">
                                      <Pencil className="h-4 w-4 mr-2" /> Edit
                                    </Button>
                                  </Link>
                                  {permissions.canDelete && (
                                    <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteDialog(prod.productionId)}>
                                      <Trash2 className="h-4 w-4 mr-2" /> Delete
                                    </Button>
                                  )}
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                      ))}
                      {currentEggProductions.length > 0 && (
                        <div className="px-4 py-3 bg-slate-50/50 border-t">
                          <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowAllColumnsMobile(true)}>
                            View table format <ChevronDown className="h-4 w-4 ml-1" />
                          </Button>
                        </div>
                      )}
                    </div>
                  ) : (
                  <div className={cn("overflow-x-auto table-scroll-wrapper", isMobile && "pb-2")} style={{ WebkitOverflowScrolling: 'touch' }}>
                    {isMobile && (
                      <div className="px-4 py-2 border-b bg-slate-50 flex items-center justify-between gap-2 sticky top-0 z-10">
                        <span className="text-xs text-slate-600">Table • Scroll → for more</span>
                        <Button variant="ghost" size="sm" onClick={() => setShowAllColumnsMobile(false)}>
                          <ChevronUp className="h-4 w-4 mr-1" /> Cards
                        </Button>
                      </div>
                    )}
                    <Table className="w-full min-w-[700px]">
                      <TableHeader>
                        <TableRow className="border-b">
                          <SortableHeader label="Date" sortKey="productionDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[100px]", isMobile && "sticky-col-date bg-slate-50")} />
                          <SortableHeader label="Flock" sortKey="flockId" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px]" />
                          <SortableHeader label="Size" sortKey="eggGrade" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[88px]", hideBelow("sm"))} />
                          <SortableHeader label="1st Pick" sortKey="production9AM" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[80px] whitespace-nowrap", hideBelow("lg"))} />
                          <SortableHeader label="2nd Pick" sortKey="production12PM" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[80px] whitespace-nowrap", hideBelow("lg"))} />
                          <SortableHeader label="3rd Pick" sortKey="production4PM" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[80px] whitespace-nowrap", hideBelow("lg"))} />
                          <SortableHeader label="4th Pick" sortKey="production4thPick" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[80px] whitespace-nowrap", hideBelow("lg"))} />
                          <SortableHeader label="Total Production" sortKey="totalProduction" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[120px]", hideBelow("sm"))} />
                          <SortableHeader label="Broken Eggs" sortKey="brokenEggs" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[120px]", hideBelow("md"))} />
                          <TableHead className="font-semibold text-slate-900 text-center min-w-[120px] whitespace-nowrap">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {currentEggProductions.map((prod) => (
                          <TableRow key={prod.productionId} className="hover:bg-slate-50 transition-colors">
                            <TableCell className={cn("font-medium text-slate-900 bg-white", isMobile && "sticky-col-date")}>
                              {isMobile ? formatDateShort(prod.productionDate) : new Date(prod.productionDate).toLocaleDateString()}
                            </TableCell>
                            <TableCell>{getFlockName(prod)}</TableCell>
                            <TableCell className={cn("text-violet-900 font-medium", hideBelow("sm"))}>
                              {formatEggGradeLabel(prod.eggGrade)}
                            </TableCell>
                            <TableCell className={hideBelow("lg")}>{prod.production9AM ?? '-'}</TableCell>
                            <TableCell className={hideBelow("lg")}>{prod.production12PM ?? '-'}</TableCell>
                            <TableCell className={hideBelow("lg")}>{prod.production4PM ?? '-'}</TableCell>
                            <TableCell className={hideBelow("lg")}>{(prod as any).production4thPick ?? '-'}</TableCell>
                            <TableCell className={hideBelow("sm")}>{prod.totalProduction}</TableCell>
                            <TableCell className={hideBelow("md")}>{prod.brokenEggs}</TableCell>
                            <TableCell className="text-center whitespace-nowrap bg-white">
                              <div className="flex items-center justify-center gap-1 min-w-[100px]">
                                <Link href={`/egg-production/${prod.productionId}`} prefetch={true}>
                                  <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-blue-50 hover:text-blue-600">
                                    <Pencil className="w-4 h-4" />
                                  </Button>
                                </Link>
                                {permissions.canDelete && (
                                  <Button
                                    variant="ghost"
                                    size="icon"
                                    className="h-8 w-8 text-red-600 hover:text-red-700 hover:bg-red-50"
                                    onClick={() => openDeleteDialog(prod.productionId)}
                                  >
                                    <Trash2 className="w-4 h-4" />
                                  </Button>
                                )}
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                         <TableRow className="bg-slate-50 font-semibold">
                            <TableCell colSpan={3} className={cn("text-right", isMobile && "sticky-col-date bg-slate-50")}>Total</TableCell>
                            <TableCell className={hideBelow("lg")}></TableCell>
                            <TableCell className={hideBelow("lg")}></TableCell>
                            <TableCell className={hideBelow("lg")}></TableCell>
                            <TableCell className={hideBelow("lg")}></TableCell>
                            <TableCell className={hideBelow("sm")}>{totalEggs.toLocaleString()}<div className="text-xs font-normal text-slate-500">{totalEggsCrates}c + {totalEggsPieces}p</div></TableCell>
                            <TableCell className={hideBelow("md")}>{totalBroken}</TableCell>
                            <TableCell></TableCell>
                        </TableRow>
                      </TableBody>
                    </Table>
                  </div>
                  )}
                </CardContent>
              </Card>
            )}
            
            {/* Pagination */}
            {!loading && filteredEggProductions.length > 0 && totalPages > 1 && (
              <div className="flex flex-col sm:flex-row items-center justify-between gap-4 mt-6">
                <div className="flex items-center gap-4">
                  <span className="text-sm text-slate-600">
                    Showing {startIndex + 1} to {Math.min(endIndex, sortedEggProductions.length)} of {sortedEggProductions.length} records
                  </span>
                  <Select value={String(itemsPerPage)} onValueChange={(v) => { setItemsPerPage(Number(v)); setCurrentPage(1) }}>
                    <SelectTrigger className="w-[100px] h-8">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="5">5 / page</SelectItem>
                      <SelectItem value="10">10 / page</SelectItem>
                      <SelectItem value="15">15 / page</SelectItem>
                      <SelectItem value="25">25 / page</SelectItem>
                      <SelectItem value="50">50 / page</SelectItem>
                      <SelectItem value="100">100 / page</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <Pagination>
                  <PaginationContent>
                    <PaginationItem>
                      <PaginationPrevious 
                        onClick={handlePreviousPage}
                        className={currentPage === 1 ? "pointer-events-none opacity-50" : "cursor-pointer"}
                      />
                    </PaginationItem>
                    
                    {getPageNumbers().map((page, index) => (
                      <PaginationItem key={index}>
                        {page === 'ellipsis' ? (
                          <PaginationEllipsis />
                        ) : (
                          <PaginationLink
                            onClick={() => handlePageChange(page as number)}
                            isActive={currentPage === page}
                            className="cursor-pointer"
                          >
                            {page}
                          </PaginationLink>
                        )}
                      </PaginationItem>
                    ))}
                    
                    <PaginationItem>
                      <PaginationNext 
                        onClick={handleNextPage}
                        className={currentPage === totalPages ? "pointer-events-none opacity-50" : "cursor-pointer"}
                      />
                    </PaginationItem>
                  </PaginationContent>
                </Pagination>
              </div>
            )}
          </div>
        </main>
      </div>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Production Record</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this egg production record? This action cannot be undone and the data will be permanently removed.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              disabled={isDeleting}
              className="bg-red-600 hover:bg-red-700 focus:ring-red-600"
            >
              {isDeleting ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Deleting...
                </>
              ) : (
                "Delete"
              )}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

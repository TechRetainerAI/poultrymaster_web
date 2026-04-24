"use client"

import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Input } from "@/components/ui/input"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Plus, Pencil, Trash2, Calendar as CalendarIcon, Egg, Search, RefreshCw, Loader2, ChevronDown, ChevronUp, Filter } from "lucide-react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { getEggProductions, deleteEggProduction, type EggProduction } from "@/lib/api/egg-production"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { format } from "date-fns"
import { cn } from "@/lib/utils"
import { Calendar } from "@/components/ui/calendar"
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
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"

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

  // Mobile: card list by default, filters in sheet
  const isMobile = useIsMobile()
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const [filtersOpen, setFiltersOpen] = useState(false)

  const [draftDateFrom, setDraftDateFrom] = useState("")
  const [draftDateTo, setDraftDateTo] = useState("")
  const [draftSelectedFlock, setDraftSelectedFlock] = useState<string>("ALL")

  const hasActiveFilters = !!search || !!dateFrom || !!dateTo || selectedFlock !== "ALL"
  const hasDraftChanges =
    draftDateFrom !== dateFrom ||
    draftDateTo !== dateTo ||
    draftSelectedFlock !== selectedFlock

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
      getFlocks(userId, farmId)
    ]);
    
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
  }

  const syncDraftFromCommitted = () => {
    setDraftDateFrom(dateFrom)
    setDraftDateTo(dateTo)
    setDraftSelectedFlock(selectedFlock)
  }

  const applyMobileFilters = () => {
    setDateFrom(draftDateFrom)
    setDateTo(draftDateTo)
    setSelectedFlock(draftSelectedFlock)
    setCurrentPage(1)
    setFiltersOpen(false)
    toast({ title: "Filters applied", description: "Egg production list updated." })
  }

  const formatDateShort = (d: string | Date) => {
    const dt = typeof d === 'string' ? new Date(d) : d
    return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' })
  }

  const getFlockName = (prod: EggProduction) => {
    if (prod.flockName) return prod.flockName
    const flock = flocks.find(f => f.flockId === prod.flockId)
    return flock?.name || `Flock #${prod.flockId}`
  }

  const filteredEggProductions = useMemo(() => {
    let currentList = eggProductions

    if (search) {
      const query = search.toLowerCase()
      currentList = currentList.filter(prod => 
        getFlockName(prod).toLowerCase().includes(query) ||
        (prod.notes ?? '').toLowerCase().includes(query)
      )
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
  }, [eggProductions, search, dateFrom, dateTo, selectedFlock])

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
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Egg Production</h1>
                  <p className="text-sm text-slate-600">Manage your egg production records</p>
                </div>
              </div>
              <Link href="/egg-production/new" prefetch={true} className="w-full sm:w-auto">
                <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700">
                  <Plus className="w-4 h-4" />
                  Add Production Record
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
                            {[search, dateFrom, dateTo, selectedFlock !== "ALL"].filter(Boolean).length}
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
                <div className="ml-auto">
                  <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                </div>
              </div>
            )}

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
                      Add Production Record
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
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2">
                                    <span className="font-semibold text-slate-900">{formatDateShort(prod.productionDate)}</span>
                                    <span className="text-slate-500">•</span>
                                    <span className="text-slate-600 truncate">{getFlockName(prod)}</span>
                                  </div>
                                  <div className="mt-1 flex items-baseline gap-3">
                                    <span className="text-xl font-bold text-emerald-600">{prod.totalProduction}</span>
                                    <span className="text-xs text-slate-500">eggs</span>
                                    {(prod.brokenEggs ?? 0) > 0 && (
                                      <>
                                        <span className="text-slate-400">•</span>
                                        <span className="text-sm text-red-600">{prod.brokenEggs} broken</span>
                                      </>
                                    )}
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">9am</span> <span className="font-medium text-blue-700">{prod.production9AM ?? '-'}</span></div>
                                  <div><span className="text-slate-500">12pm</span> <span className="font-medium text-orange-700">{prod.production12PM ?? '-'}</span></div>
                                  <div><span className="text-slate-500">4pm</span> <span className="font-medium text-purple-700">{prod.production4PM ?? '-'}</span></div>
                                  <div><span className="text-slate-500">Broken</span> <span className="font-medium text-red-600">{prod.brokenEggs ?? 0}</span></div>
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
                    <Table className={cn("w-full", !isMobile && "min-w-[600px]")}>
                      <TableHeader>
                        <TableRow className="border-b">
                          <SortableHeader label="Date" sortKey="productionDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[100px]", isMobile && "sticky-col-date bg-slate-50")} />
                          <SortableHeader label="Flock" sortKey="flockId" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px]" />
                          <SortableHeader label="9 AM" sortKey="production9AM" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[80px] hidden lg:table-cell" />
                          <SortableHeader label="12 PM" sortKey="production12PM" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[80px] hidden lg:table-cell" />
                          <SortableHeader label="4 PM" sortKey="production4PM" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[80px] hidden lg:table-cell" />
                          <SortableHeader label="Total Production" sortKey="totalProduction" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px] hidden sm:table-cell" />
                          <SortableHeader label="Broken Eggs" sortKey="brokenEggs" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px] hidden md:table-cell" />
                          <TableHead className={cn("font-semibold text-slate-900 text-center min-w-[120px] whitespace-nowrap", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {currentEggProductions.map((prod) => (
                          <TableRow key={prod.productionId} className="hover:bg-slate-50 transition-colors">
                            <TableCell className={cn("font-medium text-slate-900 bg-white", isMobile && "sticky-col-date")}>
                              {isMobile ? formatDateShort(prod.productionDate) : new Date(prod.productionDate).toLocaleDateString()}
                            </TableCell>
                            <TableCell>{getFlockName(prod)}</TableCell>
                            <TableCell className="hidden lg:table-cell">{prod.production9AM ?? '-'}</TableCell>
                            <TableCell className="hidden lg:table-cell">{prod.production12PM ?? '-'}</TableCell>
                            <TableCell className="hidden lg:table-cell">{prod.production4PM ?? '-'}</TableCell>
                            <TableCell className="hidden sm:table-cell">{prod.totalProduction}</TableCell>
                            <TableCell className="hidden md:table-cell">{prod.brokenEggs}</TableCell>
                            <TableCell className={cn("text-center whitespace-nowrap bg-white", isMobile && "sticky-col-actions")}>
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
                            <TableCell colSpan={2} className={cn("text-right", isMobile && "sticky-col-date bg-slate-50")}>Total</TableCell>
                            <TableCell className="hidden lg:table-cell"></TableCell>
                            <TableCell className="hidden lg:table-cell"></TableCell>
                            <TableCell className="hidden lg:table-cell"></TableCell>
                            <TableCell className="hidden sm:table-cell">{totalEggs.toLocaleString()}<div className="text-xs font-normal text-slate-500">{totalEggsCrates}c + {totalEggsPieces}p</div></TableCell>
                            <TableCell className="hidden md:table-cell">{totalBroken}</TableCell>
                            <TableCell className={cn(isMobile && "sticky-col-actions bg-slate-50")}></TableCell>
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
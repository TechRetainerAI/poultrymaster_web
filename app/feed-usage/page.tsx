"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Pencil, Trash2, Calendar, Package, Loader2, Search, Filter, ChevronDown, ChevronUp } from "lucide-react"
import { getFeedUsages, getFeedUsage, createFeedUsage, updateFeedUsage, deleteFeedUsage, type FeedUsage, type FeedUsageInput } from "@/lib/api/feed-usage"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"
import { getValidFlocks, getFlocksForSelect } from "@/lib/utils/flock-utils"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { useMemo } from "react"
import { getProductionRecords, createProductionRecord, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"
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
import { formatDateShort, cn } from "@/lib/utils"

export default function FeedUsagePage() {
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const [usages, setUsages] = useState<FeedUsage[]>([])
  const [allFlocks, setAllFlocks] = useState<Flock[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage, setItemsPerPage] = useState(10)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }

  // Filters
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [selectedFlockId, setSelectedFlockId] = useState("ALL")
  const [selectedMonth, setSelectedMonth] = useState("ALL")
  const [selectedYear, setSelectedYear] = useState("ALL")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()

  const [draftDateFrom, setDraftDateFrom] = useState("")
  const [draftDateTo, setDraftDateTo] = useState("")
  const [draftFlockId, setDraftFlockId] = useState("ALL")
  const [draftMonth, setDraftMonth] = useState("ALL")
  const [draftYear, setDraftYear] = useState("ALL")

  const hasDraftChanges =
    draftDateFrom !== dateFrom ||
    draftDateTo !== dateTo ||
    draftFlockId !== selectedFlockId ||
    draftMonth !== selectedMonth ||
    draftYear !== selectedYear

  // Create dialog state
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [createLoading, setCreateLoading] = useState(false)
  const [createError, setCreateError] = useState("")
  const [flocksForSelect, setFlocksForSelect] = useState<{ value: string; label: string }[]>([])
  const [flocksSelectLoading, setFlocksSelectLoading] = useState(false)
  const [createForm, setCreateForm] = useState({ flockId: "", usageDate: new Date().toISOString().split("T")[0], feedType: "", quantityKg: "" })

  // Edit dialog state
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editFetching, setEditFetching] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [editForm, setEditForm] = useState({ flockId: "", usageDate: "", feedType: "", quantityKg: "" })

  const feedTypes = ["Starter Feed", "Grower Feed", "Layer Feed", "Broiler Feed", "Organic Feed", "Custom Mix"]

  useEffect(() => {
    loadUsages()
    loadFlocks()
  }, [])

  const loadFlocks = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    const res = await getFlocks(userId, farmId)
    if (res.success && res.data) setAllFlocks(res.data)
  }

  const loadFlocksForSelect = async () => {
    setFlocksSelectLoading(true)
    try {
      await getValidFlocks()
      const fs = getFlocksForSelect()
      setFlocksForSelect(fs)
    } catch (err) {
      console.error("Error loading flocks:", err)
    } finally {
      setFlocksSelectLoading(false)
    }
  }

  const loadUsages = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }
    const result = await getFeedUsages(userId, farmId)
    if (result.success && result.data) {
      setUsages(result.data)
      setCurrentPage(1)
    } else {
      setError(result.message)
    }
    setLoading(false)
  }

  // Create handlers
  const openCreateDialog = () => {
    setCreateForm({ flockId: "", usageDate: new Date().toISOString().split("T")[0], feedType: "", quantityKg: "" })
    setCreateError("")
    loadFlocksForSelect()
    setIsCreateDialogOpen(true)
  }

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setCreateLoading(true)
    setCreateError("")
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) { setCreateError("User context not found."); toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" }); setCreateLoading(false); return }
    if (!createForm.flockId) { setCreateError("Choose a flock"); toastFormGuide(toast, "Pick which flock this feed was used for from the Flock list."); setCreateLoading(false); return }
    if (!createForm.feedType) { setCreateError("Choose a feed type"); toastFormGuide(toast, "Select the feed type (starter, grower, etc.) so records stay accurate."); setCreateLoading(false); return }
    if (!createForm.quantityKg || Number(createForm.quantityKg) <= 0) { setCreateError("Enter quantity"); toastFormGuide(toast, "Enter how many kilograms were used — use a number greater than zero."); setCreateLoading(false); return }

    const usage: FeedUsageInput = {
      farmId, userId, flockId: Number(createForm.flockId),
      usageDate: createForm.usageDate + "T00:00:00Z",
      feedType: createForm.feedType, quantityKg: Number(createForm.quantityKg),
    }
    const result = await createFeedUsage(usage)
    if (result.success) {
      // Sync to production records
      try {
        const prodRecordsRes = await getProductionRecords(userId, farmId)
        if (prodRecordsRes.success && prodRecordsRes.data) {
          const matchingRecord = prodRecordsRes.data.find(
            (pr: any) => pr.flockId === Number(createForm.flockId) && new Date(pr.date).toISOString().split('T')[0] === createForm.usageDate
          )
          if (matchingRecord) {
            const syncPayload: ProductionRecordInput = {
              farmId: matchingRecord.farmId ?? farmId,
              userId: matchingRecord.userId ?? userId,
              createdBy: matchingRecord.createdBy ?? userId,
              updatedBy: userId,
              ageInWeeks: Number(matchingRecord.ageInWeeks ?? 0),
              ageInDays: Number(matchingRecord.ageInDays ?? 0),
              date: matchingRecord.date,
              noOfBirds: Number(matchingRecord.noOfBirds ?? 0),
              mortality: Number(matchingRecord.mortality ?? 0),
              noOfBirdsLeft: Number(matchingRecord.noOfBirdsLeft ?? 0),
              feedKg: Number(createForm.quantityKg),
              medication: matchingRecord.medication ?? "None",
              production9AM: Number(matchingRecord.production9AM ?? 0),
              production12PM: Number(matchingRecord.production12PM ?? 0),
              production4PM: Number(matchingRecord.production4PM ?? 0),
              brokenEggs: Number(matchingRecord.brokenEggs ?? 0),
              totalProduction: Number(matchingRecord.totalProduction ?? 0),
              flockId: matchingRecord.flockId ?? Number(createForm.flockId),
              eggGrade: matchingRecord.eggGrade ?? null,
            }
            await updateProductionRecord(matchingRecord.id, syncPayload)
          } else {
            const flocksRes = await getValidFlocks()
            const flock = flocksRes.find((f: any) => f.flockId === Number(createForm.flockId))
            if (flock) {
              const startStr = (flock.startDate || "").split("T")[0]
              const usageStr = (createForm.usageDate || "").split("T")[0]
              const [sy, sm, sd] = startStr.split("-").map(Number)
              const [uy, um, ud] = usageStr.split("-").map(Number)
              const startUtc = Date.UTC(sy, sm - 1, sd)
              const usageUtc = Date.UTC(uy, um - 1, ud)
              const ageDays = Math.floor(Math.max(0, usageUtc - startUtc) / (1000 * 60 * 60 * 24))
              const ageWeeks = Math.floor(ageDays / 7)
              const prodInput: ProductionRecordInput = {
                farmId, userId, createdBy: userId, updatedBy: userId,
                ageInWeeks: ageWeeks, ageInDays: ageDays,
                date: createForm.usageDate + 'T00:00:00Z',
                noOfBirds: flock.quantity || 0, mortality: 0, noOfBirdsLeft: flock.quantity || 0,
                feedKg: Number(createForm.quantityKg), medication: "None",
                production9AM: 0, production12PM: 0, production4PM: 0, brokenEggs: 0, totalProduction: 0,
                flockId: Number(createForm.flockId),
              }
              await createProductionRecord(prodInput)
            }
          }
        }
      } catch (syncError) {
        console.error("Error syncing to production records:", syncError)
      }
      toast({ title: "Success!", description: "Feed usage recorded successfully." })
      setIsCreateDialogOpen(false)
      loadUsages()
    } else {
      setCreateError(result.message)
    }
    setCreateLoading(false)
  }

  // Edit handlers
  const openEditDialog = async (feedUsageId: number) => {
    setEditingId(feedUsageId)
    setEditError("")
    setEditFetching(true)
    setIsEditDialogOpen(true)
    loadFlocksForSelect()

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) { setEditError("User context not found."); setEditFetching(false); return }

    const result = await getFeedUsage(feedUsageId, userId, farmId)
    if (result.success && result.data) {
      const u = result.data
      setEditForm({
        flockId: u.flockId.toString(),
        usageDate: u.usageDate.split("T")[0],
        feedType: u.feedType,
        quantityKg: u.quantityKg.toString(),
      })
    } else {
      setEditError(result.message || "Failed to load record")
    }
    setEditFetching(false)
  }

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editingId) return
    setEditLoading(true)
    setEditError("")
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) { setEditError("User context not found."); toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" }); setEditLoading(false); return }
    if (!editForm.flockId) { setEditError("Choose a flock"); toastFormGuide(toast, "Pick which flock this feed was used for from the Flock list."); setEditLoading(false); return }
    if (!editForm.feedType) { setEditError("Choose a feed type"); toastFormGuide(toast, "Select the feed type (starter, grower, etc.) so records stay accurate."); setEditLoading(false); return }
    if (!editForm.quantityKg || Number(editForm.quantityKg) <= 0) { setEditError("Enter quantity"); toastFormGuide(toast, "Enter how many kilograms were used — use a number greater than zero."); setEditLoading(false); return }

    const usage: Partial<FeedUsageInput> = {
      farmId, userId, flockId: Number(editForm.flockId),
      usageDate: editForm.usageDate + "T00:00:00Z",
      feedType: editForm.feedType, quantityKg: Number(editForm.quantityKg),
    }
    const result = await updateFeedUsage(editingId, usage)
    if (result.success) {
      // Sync to production records
      try {
        const prodRecordsRes = await getProductionRecords(userId, farmId)
        if (prodRecordsRes.success && prodRecordsRes.data) {
          const matchingRecord = prodRecordsRes.data.find(
            (pr: any) => pr.flockId === Number(editForm.flockId) && new Date(pr.date).toISOString().split('T')[0] === editForm.usageDate
          )
          if (matchingRecord) {
            const syncPayload: ProductionRecordInput = {
              farmId: matchingRecord.farmId ?? farmId,
              userId: matchingRecord.userId ?? userId,
              createdBy: matchingRecord.createdBy ?? userId,
              updatedBy: userId,
              ageInWeeks: Number(matchingRecord.ageInWeeks ?? 0),
              ageInDays: Number(matchingRecord.ageInDays ?? 0),
              date: matchingRecord.date,
              noOfBirds: Number(matchingRecord.noOfBirds ?? 0),
              mortality: Number(matchingRecord.mortality ?? 0),
              noOfBirdsLeft: Number(matchingRecord.noOfBirdsLeft ?? 0),
              feedKg: Number(editForm.quantityKg),
              medication: matchingRecord.medication ?? "None",
              production9AM: Number(matchingRecord.production9AM ?? 0),
              production12PM: Number(matchingRecord.production12PM ?? 0),
              production4PM: Number(matchingRecord.production4PM ?? 0),
              brokenEggs: Number(matchingRecord.brokenEggs ?? 0),
              totalProduction: Number(matchingRecord.totalProduction ?? 0),
              flockId: matchingRecord.flockId ?? Number(editForm.flockId),
              eggGrade: matchingRecord.eggGrade ?? null,
            }
            await updateProductionRecord(matchingRecord.id, syncPayload)
          }
        }
      } catch (syncError) {
        console.error("Error syncing to production records:", syncError)
      }
      toast({ title: "Success!", description: "Feed usage updated successfully." })
      setIsEditDialogOpen(false)
      loadUsages()
    } else {
      setEditError(result.message)
    }
    setEditLoading(false)
  }

  // Delete handlers
  const openDeleteDialog = (id: number) => { setDeletingId(id); setDeleteDialogOpen(true) }
  const handleDelete = async () => {
    if (!deletingId) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) { toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" }); return }
    setIsDeleting(true)
    const result = await deleteFeedUsage(deletingId, userId, farmId)
    if (result.success) {
      toast({ title: "Record deleted", description: "The feed usage record has been successfully deleted." })
      loadUsages(); setCurrentPage(1)
    } else {
      toast({ title: "Delete failed", description: result.message || "Something went wrong.", variant: "destructive" })
    }
    setIsDeleting(false); setDeleteDialogOpen(false); setDeletingId(null)
  }

  const formatDate = (dateString: string) => new Date(dateString).toLocaleDateString()

  const handleLogout = () => {
    localStorage.removeItem("auth_token"); localStorage.removeItem("refresh_token")
    localStorage.removeItem("username"); localStorage.removeItem("userId")
    localStorage.removeItem("farmId"); localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff"); localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  const syncDraftFromCommitted = () => {
    setDraftDateFrom(dateFrom)
    setDraftDateTo(dateTo)
    setDraftFlockId(selectedFlockId)
    setDraftMonth(selectedMonth)
    setDraftYear(selectedYear)
  }

  const applyMobileFilters = () => {
    setDateFrom(draftDateFrom)
    setDateTo(draftDateTo)
    setSelectedFlockId(draftFlockId)
    setSelectedMonth(draftMonth)
    setSelectedYear(draftYear)
    setCurrentPage(1)
    setFiltersOpen(false)
    toast({ title: "Filters applied", description: "Feed usage list updated." })
  }

  const distinctYears = useMemo(() => {
    const years = Array.from(new Set(usages.map(u => new Date(u.usageDate).getFullYear())))
    return years.sort((a, b) => b - a)
  }, [usages])

  const months = [
    { value: "1", label: "January" }, { value: "2", label: "February" }, { value: "3", label: "March" },
    { value: "4", label: "April" }, { value: "5", label: "May" }, { value: "6", label: "June" },
    { value: "7", label: "July" }, { value: "8", label: "August" }, { value: "9", label: "September" },
    { value: "10", label: "October" }, { value: "11", label: "November" }, { value: "12", label: "December" },
  ]

  const filteredUsages = useMemo(() => {
    let list = [...usages]
    const q = search.trim().toLowerCase()
    if (q) {
      list = list.filter(u =>
        (u.feedType || "").toLowerCase().includes(q) ||
        String(u.flockId || "").includes(q) ||
        String(u.quantityKg || "").includes(q) ||
        new Date(u.usageDate).toLocaleDateString().toLowerCase().includes(q)
      )
    }
    if (dateFrom) list = list.filter((u) => toLocalDateKey(u.usageDate) >= dateFrom)
    if (dateTo) list = list.filter((u) => toLocalDateKey(u.usageDate) <= dateTo)
    if (selectedFlockId !== "ALL") list = list.filter(u => String(u.flockId) === selectedFlockId)
    if (selectedMonth !== "ALL") list = list.filter(u => (new Date(u.usageDate).getMonth() + 1) === Number(selectedMonth))
    if (selectedYear !== "ALL") list = list.filter(u => new Date(u.usageDate).getFullYear().toString() === selectedYear)
    return list
  }, [usages, search, dateFrom, dateTo, selectedFlockId, selectedMonth, selectedYear])

  const sortedUsages = useMemo(() => sortData(filteredUsages, sortKey, sortDir, (item: any, key: string) => {
    if (key === "date") return new Date(item.usageDate)
    if (key === "quantityKg") return Number(item.quantityKg) || 0
    return (item as any)[key]
  }), [filteredUsages, sortKey, sortDir])

  const totalPages = Math.ceil(sortedUsages.length / itemsPerPage)
  const startIndex = (currentPage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const currentUsages = sortedUsages.slice(startIndex, endIndex)
  const totalFeedKg = useMemo(() => filteredUsages.reduce((sum, u) => sum + (u.quantityKg || 0), 0), [filteredUsages])

  const handlePageChange = (page: number) => setCurrentPage(page)
  const handlePreviousPage = () => { if (currentPage > 1) setCurrentPage(currentPage - 1) }
  const handleNextPage = () => { if (currentPage < totalPages) setCurrentPage(currentPage + 1) }

  const getPageNumbers = () => {
    const pages: (number | string)[] = []
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) pages.push(i)
    } else {
      if (currentPage <= 3) { for (let i = 1; i <= 4; i++) pages.push(i); pages.push('ellipsis'); pages.push(totalPages) }
      else if (currentPage >= totalPages - 2) { pages.push(1); pages.push('ellipsis'); for (let i = totalPages - 3; i <= totalPages; i++) pages.push(i) }
      else { pages.push(1); pages.push('ellipsis'); for (let i = currentPage - 1; i <= currentPage + 1; i++) pages.push(i); pages.push('ellipsis'); pages.push(totalPages) }
    }
    return pages
  }

  // Reusable form fields
  const renderFeedFormFields = (
    form: typeof createForm,
    setForm: (f: typeof createForm) => void,
    isLoading: boolean
  ) => (
    <>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock &amp; Date</div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Select Flock *</Label>
            <Select value={form.flockId} onValueChange={(v) => setForm({ ...form, flockId: v })} disabled={flocksSelectLoading || isLoading}>
              <SelectTrigger><SelectValue placeholder={flocksSelectLoading ? "Loading..." : "Select a flock"} /></SelectTrigger>
              <SelectContent>
                {flocksForSelect.map((f) => <SelectItem key={f.value} value={f.value}>{f.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Usage Date *</Label>
            <Input name="usageDate" type="date" value={form.usageDate} onChange={(e) => setForm({ ...form, usageDate: e.target.value })} required disabled={isLoading} />
          </div>
        </div>
      </div>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-amber-500 px-4 py-2 text-sm font-semibold text-white">Feed Details</div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Feed Type *</Label>
            <Select value={form.feedType} onValueChange={(v) => setForm({ ...form, feedType: v })} disabled={isLoading}>
              <SelectTrigger><SelectValue placeholder="Select feed type" /></SelectTrigger>
              <SelectContent>
                {feedTypes.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Quantity (kg) *</Label>
            <Input name="quantityKg" type="number" step="0.1" min="0" placeholder="e.g., 25.5" value={form.quantityKg} onChange={(e) => setForm({ ...form, quantityKg: e.target.value })} required disabled={isLoading} />
          </div>
        </div>
      </div>
    </>
  )

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className="flex items-center justify-between">
              <div>
                <div className="flex items-center gap-3 mb-2">
                  <div className="w-10 h-10 bg-amber-100 rounded-lg flex items-center justify-center">
                    <Package className="w-5 h-5 text-amber-600" />
                  </div>
                  <h1 className="text-2xl font-bold text-slate-900">Feed Usage</h1>
                </div>
                <p className="text-slate-600">Monitor feed consumption and costs</p>
              </div>
              <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}>
                <Plus className="w-4 h-4" /> Add Usage
              </Button>
            </div>

            {/* Filters */}
            {isMobile ? (
              <div className="space-y-3 w-full min-w-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search feed usage..." value={search} onChange={(e) => { setSearch(e.target.value); setCurrentPage(1) }} className="pl-10 h-11" />
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
                        {(!!search || !!dateFrom || !!dateTo || selectedFlockId !== "ALL" || selectedMonth !== "ALL" || selectedYear !== "ALL") && (
                          <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-orange-500 text-white text-xs flex items-center justify-center">
                            {[search, dateFrom, dateTo, selectedFlockId !== "ALL", selectedMonth !== "ALL", selectedYear !== "ALL"].filter(Boolean).length}
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
                              <label htmlFor="feed-filter-from" className="text-xs font-medium text-slate-500">
                                Start date
                              </label>
                              <Input
                                id="feed-filter-from"
                                type="date"
                                value={draftDateFrom}
                                onChange={(e) => setDraftDateFrom(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="feed-filter-to" className="text-xs font-medium text-slate-500">
                                End date
                              </label>
                              <Input
                                id="feed-filter-to"
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
                          <Select value={draftFlockId} onValueChange={setDraftFlockId}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="Flock" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All Flocks</SelectItem>
                              {allFlocks.map((f) => (
                                <SelectItem key={f.flockId} value={String(f.flockId)}>
                                  {f.name}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                          <div className="space-y-2">
                            <label className="text-sm font-medium text-slate-700">Month</label>
                            <Select value={draftMonth} onValueChange={setDraftMonth}>
                              <SelectTrigger className="h-12 text-base">
                                <SelectValue placeholder="Month" />
                              </SelectTrigger>
                              <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                                <SelectItem value="ALL">All Months</SelectItem>
                                {months.map((m) => (
                                  <SelectItem key={m.value} value={m.value}>
                                    {m.label}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                          <div className="space-y-2">
                            <label className="text-sm font-medium text-slate-700">Year</label>
                            <Select value={draftYear} onValueChange={setDraftYear}>
                              <SelectTrigger className="h-12 text-base">
                                <SelectValue placeholder="Year" />
                              </SelectTrigger>
                              <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                                <SelectItem value="ALL">All Years</SelectItem>
                                {distinctYears.map((y) => (
                                  <SelectItem key={y} value={String(y)}>
                                    {y}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        </div>
                      </MobileFilterSheetBody>
                      <MobileFilterSheetFooter>
                        <div className="flex gap-3">
                          <Button
                            type="button"
                            variant="outline"
                            className="h-12 flex-1"
                            onClick={() => {
                              setSearch("")
                              setDateFrom("")
                              setDateTo("")
                              setSelectedFlockId("ALL")
                              setSelectedMonth("ALL")
                              setSelectedYear("ALL")
                              setDraftDateFrom("")
                              setDraftDateTo("")
                              setDraftFlockId("ALL")
                              setDraftMonth("ALL")
                              setDraftYear("ALL")
                              setCurrentPage(1)
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
            <div className="flex flex-wrap items-center gap-2 p-3 bg-white rounded-lg border">
              <div className="relative w-full sm:w-[200px]">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Search..." value={search} onChange={(e) => { setSearch(e.target.value); setCurrentPage(1) }} className="pl-9" />
              </div>
              <div className="relative w-full sm:w-[160px]">
                <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                <Input type="date" value={dateFrom} onChange={(e) => { setDateFrom(e.target.value); setCurrentPage(1) }} className="pl-9" />
              </div>
              <div className="relative w-full sm:w-[160px]">
                <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                <Input type="date" value={dateTo} onChange={(e) => { setDateTo(e.target.value); setCurrentPage(1) }} className="pl-9" />
              </div>
              <Select value={selectedFlockId} onValueChange={(v) => { setSelectedFlockId(v); setCurrentPage(1) }}>
                <SelectTrigger className="w-[180px]"><SelectValue placeholder="Flock" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All Flocks</SelectItem>
                  {allFlocks.map(f => <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name} ({f.quantity} birds)</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={selectedMonth} onValueChange={(v) => { setSelectedMonth(v); setCurrentPage(1) }}>
                <SelectTrigger className="w-[140px]"><SelectValue placeholder="Month" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All Months</SelectItem>
                  {months.map(m => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={selectedYear} onValueChange={(v) => { setSelectedYear(v); setCurrentPage(1) }}>
                <SelectTrigger className="w-[120px]"><SelectValue placeholder="Year" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All Years</SelectItem>
                  {distinctYears.map(y => <SelectItem key={y} value={String(y)}>{y}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            )}

            {/* Summary */}
            <div className={cn("grid gap-3", isMobile ? "grid-cols-2" : "grid-cols-2 md:grid-cols-4")}>
              <div className="p-3 bg-white rounded-lg border">
                <div className="text-xs text-slate-500">Total Records</div>
                <div className="text-lg font-bold text-slate-900">{filteredUsages.length}</div>
              </div>
              <div className="p-3 bg-white rounded-lg border">
                <div className="text-xs text-slate-500">Total Feed (kg)</div>
                <div className="text-lg font-bold text-amber-700">{totalFeedKg.toFixed(2)} kg</div>
              </div>
            </div>

            {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

            {loading ? (
              <Card className="bg-white"><CardContent className="py-12 text-center"><p className="text-slate-600">Loading feed usage records...</p></CardContent></Card>
            ) : sortedUsages.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4"><Package className="w-8 h-8 text-slate-400" /></div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No feed usage records found</h3>
                  <p className="text-slate-600 mb-6">{search || dateFrom || dateTo || selectedFlockId !== "ALL" ? "No records match your current filters." : "Get started by adding your first feed usage record"}</p>
                  <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}><Plus className="w-4 h-4" />Add Your First Record</Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {currentUsages.map((usage, idx) => {
                        const flockName = allFlocks.find(f => f.flockId === usage.flockId)?.name || `Flock #${usage.flockId}`
                        return (
                        <Collapsible key={usage.feedUsageId} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2">
                                    <span className="font-semibold text-slate-900">{formatDateShort(usage.usageDate)}</span>
                                    <span className="text-slate-500">•</span>
                                    <span className="text-slate-600 truncate">{flockName}</span>
                                  </div>
                                  <div className="mt-1 flex items-baseline gap-3">
                                    <span className="text-lg font-bold text-amber-600">{usage.quantityKg} kg</span>
                                    <span className="text-sm text-slate-600">{usage.feedType}</span>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 flex gap-2 pt-2">
                                <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(usage.feedUsageId)}>
                                  <Pencil className="h-4 w-4 mr-2" /> Edit
                                </Button>
                                {permissions.canDelete && (
                                  <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteDialog(usage.feedUsageId)}>
                                    <Trash2 className="h-4 w-4 mr-2" /> Delete
                                  </Button>
                                )}
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                        )
                      })}
                      {currentUsages.length > 0 && (
                        <div className="px-4 py-3 bg-slate-50/50 border-t">
                          <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowAllColumnsMobile(true)}>
                            View table format <ChevronDown className="h-4 w-4 ml-1" />
                          </Button>
                        </div>
                      )}
                    </div>
                  ) : (
                  <div className={cn("overflow-x-auto table-scroll-wrapper", isMobile && "pb-2")} style={{ WebkitOverflowScrolling: "touch" }}>
                    {isMobile && (
                      <div className="px-4 py-2 border-b bg-slate-50 flex items-center justify-between gap-2 sticky top-0 z-10">
                        <span className="text-xs text-slate-600">Table • Scroll → for more</span>
                        <Button variant="ghost" size="sm" onClick={() => setShowAllColumnsMobile(false)}>
                          <ChevronUp className="h-4 w-4 mr-1" /> Cards
                        </Button>
                      </div>
                    )}
                    <Table className={cn("w-full", !isMobile && "min-w-[500px]")}>
                      <TableHeader>
                        <TableRow className="border-b">
                          <SortableHeader label="Date" sortKey="date" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[120px]", isMobile && "sticky-col-date bg-slate-50")} />
                          <SortableHeader label="Flock" sortKey="flockId" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[100px]" />
                          <SortableHeader label="Feed Type" sortKey="feedType" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[150px]" />
                          <SortableHeader label="Quantity (kg)" sortKey="quantityKg" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px]" />
                          <TableHead className={cn("font-semibold text-slate-900 text-center min-w-[100px]", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {currentUsages.map((usage) => (
                          <TableRow key={usage.feedUsageId} className="hover:bg-slate-50 transition-colors">
                            <TableCell className={cn("font-medium text-slate-900 bg-white", isMobile && "sticky-col-date")}>
                              <div className="flex items-center gap-2"><Calendar className="w-4 h-4 text-blue-600" /><span>{isMobile ? formatDateShort(usage.usageDate) : formatDate(usage.usageDate)}</span></div>
                            </TableCell>
                            <TableCell className="text-slate-600">
                              {(() => { const flock = allFlocks.find(f => f.flockId === usage.flockId); return flock ? flock.name : `Flock #${usage.flockId}` })()}
                            </TableCell>
                            <TableCell className="text-slate-900 font-medium">
                              <div className="flex items-center gap-2"><Package className="w-4 h-4 text-amber-600" /><span>{usage.feedType}</span></div>
                            </TableCell>
                            <TableCell className="font-bold text-blue-600">{usage.quantityKg} kg</TableCell>
                            <TableCell className={cn("text-center whitespace-nowrap bg-white", isMobile && "sticky-col-actions")}>
                              <div className="flex items-center justify-center gap-1 min-w-[90px]">
                                <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-blue-50 hover:text-blue-600" onClick={() => openEditDialog(usage.feedUsageId)}>
                                  <Pencil className="w-4 h-4" />
                                </Button>
                                {permissions.canDelete && (
                                  <Button variant="ghost" size="icon" className="h-8 w-8 text-red-600 hover:text-red-700 hover:bg-red-50" onClick={() => openDeleteDialog(usage.feedUsageId)}>
                                    <Trash2 className="w-4 h-4" />
                                  </Button>
                                )}
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                  )}
                </CardContent>
              </Card>
            )}

            {/* Pagination */}
            {!loading && sortedUsages.length > 0 && (
              <div className="flex flex-wrap items-center justify-between gap-4 mt-4">
                <div className="flex items-center gap-2 text-sm text-slate-600">
                  <span>Showing {startIndex + 1} to {Math.min(endIndex, sortedUsages.length)} of {sortedUsages.length} records</span>
                  <Select value={String(itemsPerPage)} onValueChange={(v) => { setItemsPerPage(Number(v)); setCurrentPage(1) }}>
                    <SelectTrigger className="w-[110px] h-8"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="5">5 / page</SelectItem>
                      <SelectItem value="10">10 / page</SelectItem>
                      <SelectItem value="15">15 / page</SelectItem>
                      <SelectItem value="25">25 / page</SelectItem>
                      <SelectItem value="50">50 / page</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {totalPages > 1 && (
                  <Pagination>
                    <PaginationContent>
                      <PaginationItem><PaginationPrevious onClick={handlePreviousPage} className={currentPage === 1 ? "pointer-events-none opacity-50" : "cursor-pointer"} /></PaginationItem>
                      {getPageNumbers().map((page, index) => (
                        <PaginationItem key={index}>
                          {page === 'ellipsis' ? <PaginationEllipsis /> : <PaginationLink onClick={() => handlePageChange(page as number)} isActive={currentPage === page} className="cursor-pointer">{page}</PaginationLink>}
                        </PaginationItem>
                      ))}
                      <PaginationItem><PaginationNext onClick={handleNextPage} className={currentPage === totalPages ? "pointer-events-none opacity-50" : "cursor-pointer"} /></PaginationItem>
                    </PaginationContent>
                  </Pagination>
                )}
              </div>
            )}
          </div>
        </main>
      </div>

      {/* Create Feed Usage Dialog */}
      <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Package className="w-5 h-5 text-amber-600" /> Add Feed Usage</DialogTitle>
            <DialogDescription>Record feed consumption for a flock</DialogDescription>
          </DialogHeader>
          {createError && <Alert variant="destructive"><AlertDescription>{createError}</AlertDescription></Alert>}
          <form onSubmit={handleCreateSubmit} className="space-y-4">
            {renderFeedFormFields(createForm, setCreateForm, createLoading)}
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button type="submit" disabled={createLoading || flocksSelectLoading}>
                {createLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</> : <><Package className="w-4 h-4 mr-2" />Record Usage</>}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit Feed Usage Dialog */}
      <Dialog open={isEditDialogOpen} onOpenChange={setIsEditDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Pencil className="w-5 h-5 text-blue-600" /> Edit Feed Usage</DialogTitle>
            <DialogDescription>Update feed consumption record</DialogDescription>
          </DialogHeader>
          {editError && <Alert variant="destructive"><AlertDescription>{editError}</AlertDescription></Alert>}
          {editFetching ? (
            <div className="py-8 text-center"><Loader2 className="w-8 h-8 animate-spin mx-auto mb-2 text-blue-600" /><p className="text-slate-600">Loading record...</p></div>
          ) : (
            <form onSubmit={handleEditSubmit} className="space-y-4">
              {renderFeedFormFields(editForm, setEditForm, editLoading)}
              <div className="flex gap-3 justify-end pt-2">
                <Button type="button" onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                <Button type="submit" disabled={editLoading || flocksSelectLoading}>
                  {editLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : <><Pencil className="w-4 h-4 mr-2" />Save Changes</>}
                </Button>
              </div>
            </form>
          )}
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Feed Usage Record</AlertDialogTitle>
            <AlertDialogDescription>Are you sure you want to delete this feed usage record? This action cannot be undone.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} disabled={isDeleting} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              {isDeleting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Deleting...</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Calendar as CalendarComponent } from "@/components/ui/calendar"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Plus, Pencil, Trash2, Calendar, Bird, Users, AlertCircle, Search, RefreshCw, ArrowUpDown, ArrowUp, ArrowDown, Filter, Home, Loader2, Save, ChevronDown, ChevronUp } from "lucide-react"
import { useIsMobile } from '@/hooks/use-mobile'
import { Sheet, SheetContent, SheetTrigger } from '@/components/ui/sheet'
import {
  MOBILE_FILTER_SHEET_CONTENT_CLASS,
  MOBILE_FILTER_SELECT_CONTENT_CLASS,
  MOBILE_FILTERS_TOOLBAR_ROW_CLASS,
  MOBILE_FILTERS_TRIGGER_BUTTON_CLASS,
  MobileFilterSheetBody,
  MobileFilterSheetFooter,
  MobileFilterSheetHeader,
} from '@/components/dashboard/mobile-filters'
import { toLocalDateKey } from '@/lib/utils/date-key'
import { format } from "date-fns"
import { cn } from "@/lib/utils"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { getFlocks, getFlock, createFlock, updateFlock, deleteFlock, type Flock, type FlockInput } from "@/lib/api/flock"
import { getHouses, type House } from "@/lib/api/house"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import { getBirdsLeftForFlockFromRecords } from "@/lib/utils/production-records"
import { getUserContext } from "@/lib/utils/user-context"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { useMemo } from "react"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort } from "@/lib/utils"

export default function FlocksPage() {
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage] = useState(10)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)

  // Filter states
  const [search, setSearch] = useState("")
  const [selectedStatus, setSelectedStatus] = useState<string>("ALL") // "ALL", "active", "inactive"
  const [selectedHouseId, setSelectedHouseId] = useState<string>("ALL")
  const [selectedBatchId, setSelectedBatchId] = useState<string>("ALL")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [quantityMin, setQuantityMin] = useState<string>("")
  const [quantityMax, setQuantityMax] = useState<string>("")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()

  const [draftStatus, setDraftStatus] = useState<string>("ALL")
  const [draftHouseId, setDraftHouseId] = useState<string>("ALL")
  const [draftBatchId, setDraftBatchId] = useState<string>("ALL")
  const [draftDateFrom, setDraftDateFrom] = useState("")
  const [draftDateTo, setDraftDateTo] = useState("")
  const [draftQuantityMin, setDraftQuantityMin] = useState<string>("")
  const [draftQuantityMax, setDraftQuantityMax] = useState<string>("")

  const hasDraftChanges =
    draftStatus !== selectedStatus ||
    draftHouseId !== selectedHouseId ||
    draftBatchId !== selectedBatchId ||
    draftDateFrom !== dateFrom ||
    draftDateTo !== dateTo ||
    draftQuantityMin !== quantityMin ||
    draftQuantityMax !== quantityMax

  const hasActiveFilters = !!search || selectedStatus !== "ALL" || selectedHouseId !== "ALL" || selectedBatchId !== "ALL" || !!dateFrom || !!dateTo || !!quantityMin || !!quantityMax
  
  // Sorting state
  const [sortField, setSortField] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<"asc" | "desc">("asc")

  // Data for filter dropdowns
  const [houses, setHouses] = useState<House[]>([])
  const [flockBatches, setFlockBatches] = useState<FlockBatch[]>([])

  // Map of flockId -> noOfBirdsLeft from the most recent production record
  const [flockBirdsLeftMap, setFlockBirdsLeftMap] = useState<Record<number, number>>({})
  // Cumulative mortality across ALL production records (for accurate totals)
  const [cumulativeMortality, setCumulativeMortality] = useState(0)

  // Create dialog state
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [createLoading, setCreateLoading] = useState(false)
  const [createError, setCreateError] = useState("")
  const emptyFlockForm = { name: "", startDate: "", breed: "", quantity: 0, active: true, houseId: null as number | null, batchId: 0, inactivationReason: "", otherReason: "", notes: "" }
  const [createForm, setCreateForm] = useState({ ...emptyFlockForm })
  const [createSelectedBatch, setCreateSelectedBatch] = useState<FlockBatch | null>(null)

  // Edit dialog state
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editingFlockId, setEditingFlockId] = useState<number | null>(null)
  const [editForm, setEditForm] = useState({ ...emptyFlockForm })
  const [editFetching, setEditFetching] = useState(false)
  const [editSelectedBatch, setEditSelectedBatch] = useState<FlockBatch | null>(null)

  // Initial load
  useEffect(() => {
    loadFlocks()
    loadFilterData()
    loadProductionBirdsLeft()
    
    // Check for global search query from header
    if (typeof window !== 'undefined') {
      const globalSearch = sessionStorage.getItem('globalSearchQuery')
      if (globalSearch) {
        setSearch(globalSearch)
        sessionStorage.removeItem('globalSearchQuery') // Clear after using
      }
      
      // Listen for global search events from header
      const handleGlobalSearch = (e: CustomEvent) => {
        setSearch(e.detail.query)
        setCurrentPage(1)
      }
      
      window.addEventListener('globalSearch', handleGlobalSearch as EventListener)
      
      return () => {
        window.removeEventListener('globalSearch', handleGlobalSearch as EventListener)
      }
    }
  }, [])

  const loadFilterData = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return

    const [housesRes, flockBatchesRes] = await Promise.all([
      getHouses(userId, farmId),
      getFlockBatches(userId, farmId),
    ])

    if (housesRes.success && housesRes.data) setHouses(housesRes.data as House[])
    if (flockBatchesRes.success && flockBatchesRes.data) setFlockBatches(flockBatchesRes.data as FlockBatch[])
  }

  // Evans spec: Overall Total Birds = sum of Left values from most recent production records per flock
  // Left = Birds - Mortality
  const loadProductionBirdsLeft = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return

    try {
      const res = await getProductionRecords(userId, farmId)
      if (res.success && res.data && res.data.length > 0) {
        // Per flock: birds left = `noOfBirdsLeft` on the most recent production record for that flockId
        const map: Record<number, number> = {}
        const flockIds = new Set<number>()
        for (const r of res.data) {
          if (r.flockId != null) flockIds.add(r.flockId)
        }
        flockIds.forEach((fid) => {
          map[fid] = getBirdsLeftForFlockFromRecords(res.data, fid)
        })

        const totalMort = res.data.reduce((s, r) => s + (r.mortality ?? 0), 0)
        console.log("[FlocksPage] Birds left map from production records:", map)
        setFlockBirdsLeftMap(map)
        setCumulativeMortality(totalMort)
      }
    } catch (e) {
      console.error("[FlocksPage] Error loading production records for birds left:", e)
    }
  }

  const clearFilters = () => {
    setSearch("")
    setSelectedStatus("ALL")
    setSelectedHouseId("ALL")
    setSelectedBatchId("ALL")
    setDateFrom("")
    setDateTo("")
    setQuantityMin("")
    setQuantityMax("")
    setDraftStatus("ALL")
    setDraftHouseId("ALL")
    setDraftBatchId("ALL")
    setDraftDateFrom("")
    setDraftDateTo("")
    setDraftQuantityMin("")
    setDraftQuantityMax("")
  }

  const syncDraftFromCommitted = () => {
    setDraftStatus(selectedStatus)
    setDraftHouseId(selectedHouseId)
    setDraftBatchId(selectedBatchId)
    setDraftDateFrom(dateFrom)
    setDraftDateTo(dateTo)
    setDraftQuantityMin(quantityMin)
    setDraftQuantityMax(quantityMax)
  }

  const applyMobileFilters = () => {
    setSelectedStatus(draftStatus)
    setSelectedHouseId(draftHouseId)
    setSelectedBatchId(draftBatchId)
    setDateFrom(draftDateFrom)
    setDateTo(draftDateTo)
    setQuantityMin(draftQuantityMin)
    setQuantityMax(draftQuantityMax)
    setCurrentPage(1)
    setFiltersOpen(false)
    toast({ title: "Filters applied", description: "Flock list updated." })
  }
  
  const handleSort = (field: string) => {
    if (sortField === field) {
      setSortDirection(sortDirection === "asc" ? "desc" : "asc")
    } else {
      setSortField(field)
      setSortDirection("asc")
    }
  }

  const loadFlocks = async () => {
    const { farmId, userId } = getUserContext()
    
    if (!farmId || !userId) {
      console.error("[FlocksPage] Missing userId or farmId:", { userId, farmId })
      setError("Farm ID or User ID not found")
      setLoading(false)
      return
    }

    console.log("[FlocksPage] ========================================")
    console.log("[FlocksPage] Loading flocks for:")
    console.log("[FlocksPage]   userId:", userId)
    console.log("[FlocksPage]   farmId:", farmId)
    console.log("[FlocksPage] ========================================")
    
    const result = await getFlocks(userId, farmId)
    console.log("[FlocksPage] API Result:", {
      success: result.success,
      message: result.message,
      dataLength: result.data?.length || 0,
      data: result.data
    })
    
    if (result.success) {
      // Handle both empty arrays and undefined/null
      let flocksData = result.data || []
      console.log("[FlocksPage] Initial flocks received:", flocksData.length, "items")
      
      // Additional client-side filtering by farmId as a safeguard
      // Ensure only flocks belonging to the current farm are displayed
      if (farmId && flocksData.length > 0) {
        const beforeFilter = flocksData.length
        const currentFarmId = String(farmId || '').trim().toLowerCase()
        
        console.log("[FlocksPage] ===== ADDITIONAL CLIENT-SIDE FILTER =====")
        console.log("[FlocksPage] Current farmId:", currentFarmId, "Type:", typeof farmId)
        console.log("[FlocksPage] Flocks before filter:", beforeFilter)
        
        // Show unique farmIds in the data
        const uniqueFarmIds = [...new Set(flocksData.map(f => String(f.farmId || '').trim().toLowerCase()))]
        console.log("[FlocksPage] Unique farmIds in received data:", uniqueFarmIds)
        
        flocksData = flocksData.filter(flock => {
          const flockFarmId = String(flock.farmId || '').trim().toLowerCase()
          const matches = flockFarmId === currentFarmId
          
          if (!matches) {
            console.warn("[FlocksPage] ❌ Filtered out flock:", {
              name: flock.name,
              flockId: flock.flockId,
              flockFarmId: flockFarmId,
              currentFarmId: currentFarmId,
              match: matches
            })
          } else {
            if (flocksData.length <= 5) {
              console.log("[FlocksPage] ✅ Keeping flock:", {
                name: flock.name,
                flockId: flock.flockId,
                flockFarmId: flockFarmId,
                currentFarmId: currentFarmId
              })
            }
          }
          
          return matches
        })
        
        console.log("[FlocksPage] Flocks after filter:", flocksData.length)
        console.log("[FlocksPage] Filtered out:", beforeFilter - flocksData.length, "flocks")
        console.log("[FlocksPage] ===========================================")
        
        if (beforeFilter > flocksData.length) {
          console.error("[FlocksPage] ⚠️ ERROR: Backend returned", beforeFilter - flocksData.length, "flocks that don't belong to current farmId:", farmId)
          console.error("[FlocksPage] This indicates the backend is not filtering correctly by farmId!")
        }
        
        // Final verification - ensure ALL remaining flocks match
        const invalidFlocks = flocksData.filter(f => String(f.farmId || '').trim().toLowerCase() !== currentFarmId)
        if (invalidFlocks.length > 0) {
          console.error("[FlocksPage] ⚠️ CRITICAL ERROR: Found", invalidFlocks.length, "flocks with incorrect farmId after filtering!")
          console.error("[FlocksPage] Invalid flocks:", invalidFlocks.map(f => ({ name: f.name, farmId: f.farmId })))
          // Remove them anyway
          flocksData = flocksData.filter(f => String(f.farmId || '').trim().toLowerCase() === currentFarmId)
        }
      }
      
      if (flocksData.length > 0) {
        console.log("[FlocksPage] Sample flock:", flocksData[0])
        console.log("[FlocksPage] All flock userIds:", flocksData.map(f => f.userId))
        
        // CRITICAL: Show all farmIds to verify if they're all the same
        const allFarmIds = flocksData.map(f => f.farmId)
        const uniqueFarmIds = [...new Set(allFarmIds)]
        console.log("[FlocksPage] 🔍🔍🔍 ALL FARMIDS IN DATA:", allFarmIds)
        console.log("[FlocksPage] 🔍🔍🔍 UNIQUE FARMIDS:", uniqueFarmIds)
        console.log("[FlocksPage] 🔍🔍🔍 NUMBER OF UNIQUE FARMIDS:", uniqueFarmIds.length)
        console.log("[FlocksPage] 🔍🔍🔍 CURRENT FARMID:", farmId)
        
        if (uniqueFarmIds.length > 1) {
          console.error("[FlocksPage] ⚠️⚠️⚠️ CRITICAL: Backend returned flocks from MULTIPLE farms!")
          // Count how many flocks per farmId
          const countsByFarmId: Record<string, number> = {}
          allFarmIds.forEach((fid: string) => {
            countsByFarmId[fid] = (countsByFarmId[fid] || 0) + 1
          })
          console.error("[FlocksPage] Flocks per farmId:", countsByFarmId)
        }
        
        // Verify all flocks belong to the correct farm
        const invalidFlocks = flocksData.filter(f => String(f.farmId) !== String(farmId))
        if (invalidFlocks.length > 0) {
          console.error("[FlocksPage] ERROR: Found", invalidFlocks.length, "flocks with incorrect farmId!")
          console.error("[FlocksPage] Invalid flocks:", invalidFlocks.map(f => ({ name: f.name, farmId: f.farmId })))
        }
      } else {
        console.warn("[FlocksPage] No flocks returned from API")
        console.warn("[FlocksPage] This could mean:")
        console.warn("[FlocksPage]   1. No flocks exist with userId:", userId, "and farmId:", farmId)
        console.warn("[FlocksPage]   2. The stored procedure is filtering them out")
        console.warn("[FlocksPage]   3. The API returned an empty array")
        console.warn("[FlocksPage] Check the database to verify flocks exist with matching userId/farmId")
      }
      
      setFlocks(Array.isArray(flocksData) ? flocksData : [])
      setCurrentPage(1)
    } else {
      console.error("[FlocksPage] Failed to load flocks:", result.message)
      setError(result.message || "Failed to load flocks")
    }
    
    setLoading(false)
  }

  // Create handlers
  const openCreateDialog = () => {
    setCreateForm({ ...emptyFlockForm })
    setCreateSelectedBatch(null)
    setCreateError("")
    setIsCreateDialogOpen(true)
  }

  const handleCreateBatchChange = (batchId: number) => {
    if (batchId === 0 || !batchId) {
      setCreateSelectedBatch(null)
      setCreateForm(prev => ({ ...prev, batchId: 0 }))
    } else {
      const selected = flockBatches.find(b => b.batchId === batchId) || null
      setCreateSelectedBatch(selected)
      setCreateForm(prev => ({ ...prev, batchId }))
    }
  }

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) { toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" }); return }
    if (!createForm.name.trim() || !createForm.breed.trim() || !createForm.startDate) { toastFormGuide(toast, "Add a flock name, breed, and the date the flock started."); return }
    if (createForm.quantity <= 0) { toastFormGuide(toast, "Enter how many birds are in this flock — use a number greater than zero."); return }
    if (!createForm.batchId || createForm.batchId === 0) { toastFormGuide(toast, "Link this flock to a batch so bird counts stay accurate."); return }
    if (createSelectedBatch && createForm.quantity > createSelectedBatch.numberOfBirds) { toastFormGuide(toast, `That batch only has ${createSelectedBatch.numberOfBirds} birds available — lower the flock size or pick another batch.`); return }

    setCreateLoading(true)
    setCreateError("")

    const flockData: FlockInput = {
      farmId, userId,
      name: createForm.name, startDate: createForm.startDate, breed: createForm.breed,
      quantity: createForm.quantity, active: createForm.active,
      houseId: createForm.houseId, batchId: createForm.batchId,
      inactivationReason: createForm.inactivationReason,
      otherReason: createForm.inactivationReason === 'other' ? createForm.otherReason : '',
      notes: createForm.notes,
    }

    const result = await createFlock(flockData)
    if (result.success) {
      toast({ title: "Success!", description: "Flock created successfully." })
      setIsCreateDialogOpen(false)
      loadFlocks()
      loadProductionBirdsLeft()
    } else {
      setCreateError(result.message || "Failed to create flock")
    }
    setCreateLoading(false)
  }

  // Edit handlers
  const openEditDialog = async (flockId: number) => {
    setEditingFlockId(flockId)
    setEditError("")
    setEditFetching(true)
    setIsEditDialogOpen(true)

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) { setEditError("User context not found."); setEditFetching(false); return }

    const result = await getFlock(flockId, userId, farmId)
    if (result.success && result.data) {
      const f = result.data
      setEditForm({
        name: f.name || "", startDate: f.startDate?.split('T')[0] || "", breed: f.breed || "",
        quantity: f.quantity || 0, active: f.active ?? false,
        houseId: f.houseId ?? null, batchId: f.batchId ?? 0,
        inactivationReason: f.inactivationReason ?? "", otherReason: f.otherReason ?? "",
        notes: f.notes ?? "",
      })
      const initialBatch = flockBatches.find(b => b.batchId === f.batchId) || null
      setEditSelectedBatch(initialBatch)
    } else {
      setEditError(result.message || "Failed to load flock")
    }
    setEditFetching(false)
  }

  const handleEditBatchChange = (batchId: number | null) => {
    const selected = flockBatches.find(b => b.batchId === batchId) || null
    setEditSelectedBatch(selected)
    setEditForm(prev => ({ ...prev, batchId: batchId || 0 }))
  }

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editingFlockId) return
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) { toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" }); return }
    if (!editForm.name.trim() || !editForm.breed.trim() || !editForm.startDate) { toastFormGuide(toast, "Add a flock name, breed, and the date the flock started."); return }
    if (editForm.quantity <= 0) { toastFormGuide(toast, "Enter how many birds are in this flock — use a number greater than zero."); return }
    if (editSelectedBatch && editForm.quantity > editSelectedBatch.numberOfBirds) { toastFormGuide(toast, `That batch only has ${editSelectedBatch.numberOfBirds} birds available — lower the flock size or pick another batch.`); return }

    setEditLoading(true)
    setEditError("")

    const flockData: Partial<FlockInput> = {
      name: editForm.name, startDate: editForm.startDate + 'T00:00:00Z', breed: editForm.breed,
      quantity: editForm.quantity, active: editForm.active,
      houseId: editForm.houseId ?? null, batchId: editForm.batchId ?? 0,
      farmId, userId,
      inactivationReason: editForm.inactivationReason,
      otherReason: editForm.inactivationReason === 'other' ? editForm.otherReason : '',
      notes: editForm.notes,
    }

    const result = await updateFlock(editingFlockId, flockData)
    if (result.success) {
      toast({ title: "Success!", description: "Flock updated successfully." })
      setIsEditDialogOpen(false)
      loadFlocks()
      loadFilterData()
      loadProductionBirdsLeft()
    } else {
      setEditError(result.message || "Failed to update flock")
    }
    setEditLoading(false)
  }

  // Delete handlers
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
    const result = await deleteFlock(deletingId, userId, farmId)
    if (result.success) {
      toast({ title: "Flock deleted", description: "The flock has been successfully deleted." })
      loadFlocks()
      setCurrentPage(1)
    } else {
      toast({ title: "Delete failed", description: result.message || "Something went wrong. Please try again.", variant: "destructive" })
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

  const handleQuantityMinChange = (value: string) => {
    setQuantityMin(value || "")
  }

  const handleQuantityMaxChange = (value: string) => {
    setQuantityMax(value || "")
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

  const filteredFlocks = useMemo(() => {
    let currentList = flocks

    if (search) {
      const query = search.toLowerCase()
      currentList = currentList.filter(flock => 
        (flock.name ?? '').toLowerCase().includes(query) ||
        (flock.breed ?? '').toLowerCase().includes(query) ||
        flock.notes?.toLowerCase().includes(query)
      )
    }

    if (selectedStatus !== "ALL") {
      const isActive = selectedStatus === "active"
      currentList = currentList.filter(flock => flock.active === isActive)
    }

    if (selectedHouseId !== "ALL") {
      currentList = currentList.filter(flock => String(flock.houseId) === selectedHouseId)
    }

    if (selectedBatchId !== "ALL") {
      currentList = currentList.filter(flock => String(flock.batchId) === selectedBatchId)
    }

    if (dateFrom) {
      currentList = currentList.filter((flock) => toLocalDateKey(flock.startDate) >= dateFrom)
    }

    if (dateTo) {
      currentList = currentList.filter((flock) => toLocalDateKey(flock.startDate) <= dateTo)
    }

    if (quantityMin) {
      const min = parseInt(quantityMin)
      if (!isNaN(min)) {
        currentList = currentList.filter(flock => flock.quantity >= min)
      }
    }

    if (quantityMax) {
      const max = parseInt(quantityMax)
      if (!isNaN(max)) {
        currentList = currentList.filter(flock => flock.quantity <= max)
      }
    }

    // Apply sorting
    if (sortField) {
      currentList = [...currentList].sort((a, b) => {
        let aVal: any
        let bVal: any
        
        switch (sortField) {
          case "name":
            aVal = a.name ?? ""
            bVal = b.name ?? ""
            break
          case "quantity":
            aVal = a.quantity ?? 0
            bVal = b.quantity ?? 0
            break
          case "startDate":
            aVal = new Date(a.startDate).getTime()
            bVal = new Date(b.startDate).getTime()
            break
          case "breed":
            aVal = a.breed ?? ""
            bVal = b.breed ?? ""
            break
          default:
            return 0
        }
        
        if (aVal < bVal) return sortDirection === "asc" ? -1 : 1
        if (aVal > bVal) return sortDirection === "asc" ? 1 : -1
        return 0
      })
    }

    return currentList
  }, [flocks, search, selectedStatus, selectedHouseId, selectedBatchId, dateFrom, dateTo, quantityMin, quantityMax, sortField, sortDirection])

  // Pagination logic
  const totalPages = Math.ceil(filteredFlocks.length / itemsPerPage)
  const startIndex = (currentPage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const paginatedFlocks = filteredFlocks.slice(startIndex, endIndex)

  const truncateText = (text: string | undefined, maxLength: number) => {
    if (!text) return 'N/A'
    if (text.length > maxLength) {
      return text.substring(0, maxLength) + '...'
    }
    return text
  }

  const getHouseName = (flock: Flock): string => {
    if (!flock.houseId) return 'N/A'
    const house = houses.find(h => h.houseId === flock.houseId)
    if (!house) return `House ${flock.houseId}`
    return (house as any).houseName || (house as any).name || `House ${house.houseId}`
  }

  const calculateAge = (startDate: string) => {
    const start = new Date(startDate)
    const now = new Date()
    const diffTime = Math.abs(now.getTime() - start.getTime())
    const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24))
    const weeks = Math.floor(diffDays / 7)
    const days = diffDays % 7
    return { days: diffDays, weeks, remainingDays: days }
  }

  const formatAge = (startDate: string) => {
    const { days, weeks, remainingDays } = calculateAge(startDate)
    return `${weeks} weeks ${remainingDays} days (${days} days)`
  }

  // Get the actual current bird count for a flock:
  // Use noOfBirdsLeft from the most recent production record, or fall back to the flock's initial quantity
  const getCurrentBirds = (flock: Flock): number => {
    if (flock.flockId in flockBirdsLeftMap) {
      return flockBirdsLeftMap[flock.flockId]
    }
    return flock.quantity || 0
  }

  const hasInactiveFlocks = useMemo(() => {
    return flocks.some(flock => flock.active === false)
  }, [flocks])

  // Overall Total Birds: sum of Quantity from flock table for each flock
  const overallTotalBirds = useMemo(() => {
    return flocks.reduce((sum, flock) => sum + (flock.quantity || 0), 0)
  }, [flocks])

  // Total Mortality: cumulative mortality from ALL production records
  const totalMortality = cumulativeMortality

  // Total birds left = sum of per-flock "current" birds (latest production noOfBirdsLeft, else placed quantity)
  const totalBirdsLeft = useMemo(() => {
    return flocks.reduce((sum, flock) => {
      if (flock.flockId in flockBirdsLeftMap) {
        return sum + flockBirdsLeftMap[flock.flockId]
      }
      return sum + (flock.quantity || 0)
    }, 0)
  }, [flocks, flockBirdsLeftMap])

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
                <div className="w-10 h-10 shrink-0 bg-green-100 rounded-lg flex items-center justify-center">
                  <Bird className="w-5 h-5 text-green-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Flocks</h1>
                  <p className="text-sm text-slate-600">Manage your bird flocks</p>
                </div>
              </div>
              <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700 shrink-0" onClick={openCreateDialog}>
                <Plus className="w-4 h-4" />
                Add Flock
              </Button>
            </div>

            {/* Filters: inline on desktop, sheet on mobile */}
            {isMobile ? (
              <div className="space-y-3 w-full min-w-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search flocks..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-10 h-11" />
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
                            {[search, selectedStatus !== "ALL", selectedHouseId !== "ALL", selectedBatchId !== "ALL", dateFrom, dateTo, quantityMin, quantityMax].filter(Boolean).length}
                          </span>
                        )}
                      </Button>
                    </SheetTrigger>
                    <SheetContent side="bottom" className={MOBILE_FILTER_SHEET_CONTENT_CLASS}>
                      <MobileFilterSheetHeader />
                      <MobileFilterSheetBody>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Status</label>
                          <Select value={draftStatus} onValueChange={setDraftStatus}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="Status" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All Statuses</SelectItem>
                              <SelectItem value="active">Active</SelectItem>
                              <SelectItem value="inactive">Inactive</SelectItem>
                            </SelectContent>
                          </Select>
                        </div>

                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">House</label>
                          <Select value={draftHouseId} onValueChange={setDraftHouseId}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="House" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All Houses</SelectItem>
                              {houses.map((h) => (
                                <SelectItem key={h.houseId} value={String(h.houseId)}>
                                  {(h as any).houseName || (h as any).name || `House ${h.houseId}`}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>

                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Batch</label>
                          <Select value={draftBatchId} onValueChange={setDraftBatchId}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="Batch" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All Batches</SelectItem>
                              {flockBatches.map((b) => (
                                <SelectItem key={b.batchId} value={String(b.batchId)}>
                                  {b.batchName}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>

                        <div className="space-y-3">
                          <p className="text-sm font-medium text-slate-700">Start date range</p>
                          <div className="flex flex-col gap-4">
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="flock-filter-from" className="text-xs font-medium text-slate-500">
                                From
                              </label>
                              <Input
                                id="flock-filter-from"
                                type="date"
                                value={draftDateFrom}
                                onChange={(e) => setDraftDateFrom(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="flock-filter-to" className="text-xs font-medium text-slate-500">
                                To
                              </label>
                              <Input
                                id="flock-filter-to"
                                type="date"
                                value={draftDateTo}
                                onChange={(e) => setDraftDateTo(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                          </div>
                        </div>

                        <div className="space-y-3">
                          <p className="text-sm font-medium text-slate-700">Quantity range</p>
                          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div className="space-y-2">
                              <label className="text-xs font-medium text-slate-500">Min</label>
                              <Input
                                type="number"
                                placeholder="Min"
                                value={draftQuantityMin}
                                onChange={(e) => setDraftQuantityMin(e.target.value || "")}
                                className="h-12 text-base"
                              />
                            </div>
                            <div className="space-y-2">
                              <label className="text-xs font-medium text-slate-500">Max</label>
                              <Input
                                type="number"
                                placeholder="Max"
                                value={draftQuantityMax}
                                onChange={(e) => setDraftQuantityMax(e.target.value || "")}
                                className="h-12 text-base"
                              />
                            </div>
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
              <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded border">
                <div className="relative w-full sm:w-[240px]">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search by name, breed, or notes..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                </div>

                <Select value={selectedStatus} onValueChange={setSelectedStatus}>
                  <SelectTrigger className="w-[180px]">
                    <SelectValue placeholder="Status" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Statuses</SelectItem>
                    <SelectItem value="active">Active</SelectItem>
                    <SelectItem value="inactive">Inactive</SelectItem>
                  </SelectContent>
                </Select>

                <Select value={selectedHouseId} onValueChange={setSelectedHouseId}>
                  <SelectTrigger className="w-[180px]">
                    <SelectValue placeholder="House" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Houses</SelectItem>
                    {houses.map(h => (
                      <SelectItem key={h.houseId} value={String(h.houseId)}>{(h as any).houseName || (h as any).name || `House ${h.houseId}`}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                <Select value={selectedBatchId} onValueChange={setSelectedBatchId}>
                  <SelectTrigger className="w-[180px]">
                    <SelectValue placeholder="Batch" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Batches</SelectItem>
                    {flockBatches.map(b => (
                      <SelectItem key={b.batchId} value={String(b.batchId)}>{b.batchName}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                <Input type="date" placeholder="From" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" />
                <Input type="date" placeholder="To" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" />

                <Input
                  type="number"
                  placeholder="Min Quantity"
                  value={quantityMin}
                  onChange={(e) => handleQuantityMinChange(e.target.value)}
                  className="w-[120px]"
                />

                <Input
                  type="number"
                  placeholder="Max Quantity"
                  value={quantityMax}
                  onChange={(e) => handleQuantityMaxChange(e.target.value)}
                  className="w-[120px]"
                />

                <div className="ml-auto">
                  <Button variant="outline" size="sm" onClick={clearFilters}>
                    <RefreshCw className="h-4 w-4 mr-2" /> Reset
                  </Button>
                </div>
              </div>
            )}

            {/* Error Alert */}
            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Content */}
            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <p className="text-slate-600">Loading flocks...</p>
                </CardContent>
              </Card>
            ) : filteredFlocks.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="p-12 text-center">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4">
                    <Bird className="w-8 h-8 text-slate-400" />
                  </div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No flocks found</h3>
                  <p className="text-slate-600 mb-6">Get started by creating your first flock.</p>
                  <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}>
                    <Plus className="w-4 h-4" />
                    Add Flock
                  </Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {paginatedFlocks.map((flock, idx) => (
                        <Collapsible key={flock.flockId} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2 flex-wrap">
                                    <span className="font-semibold text-slate-900">{flock.name}</span>
                                    <Badge variant={flock.active ? "default" : "secondary"} className={flock.active ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"}>
                                      {flock.active ? "Active" : "Inactive"}
                                    </Badge>
                                  </div>
                                  <div className="mt-1 flex items-baseline gap-3">
                                    <span className="text-lg font-bold text-emerald-600">{getCurrentBirds(flock).toLocaleString()}</span>
                                    <span className="text-xs text-slate-500">birds</span>
                                    <span className="text-slate-400">•</span>
                                    <span className="text-sm text-slate-600">{formatDateShort(flock.startDate)}</span>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Breed</span> <span className="font-medium text-slate-900">{flock.breed}</span></div>
                                  <div><span className="text-slate-500">House</span> <span className="font-medium">{getHouseName(flock)}</span></div>
                                  <div><span className="text-slate-500">Batch</span> <span className="font-medium">{flock.batchName || "N/A"}</span></div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(flock.flockId)}>
                                    <Pencil className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  {permissions.canDelete && (
                                    <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteDialog(flock.flockId)}>
                                      <Trash2 className="h-4 w-4 mr-2" /> Delete
                                    </Button>
                                  )}
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                      ))}
                      {paginatedFlocks.length > 0 && (
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
                    <Table className={cn("w-full", !isMobile && "min-w-[700px]")}>
                      <TableHeader>
                        <TableRow className="border-b">
                          <TableHead 
                            className={cn("font-semibold text-slate-900 min-w-[120px] cursor-pointer hover:bg-slate-50", isMobile && "sticky-col-date bg-slate-50")}
                            onClick={() => handleSort("name")}
                          >
                            <div className="flex items-center gap-2">
                              Name
                              {sortField === "name" ? (
                                sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                              ) : (
                                <ArrowUpDown className="h-4 w-4 text-slate-400" />
                              )}
                            </div>
                          </TableHead>
                          <TableHead className="font-semibold text-slate-900 min-w-[100px] hidden sm:table-cell">Status</TableHead>
                          <TableHead 
                            className="font-semibold text-slate-900 min-w-[120px] hidden md:table-cell cursor-pointer hover:bg-slate-50"
                            onClick={() => handleSort("quantity")}
                          >
                            <div className="flex items-center gap-2">
                              Quantity
                              {sortField === "quantity" ? (
                                sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                              ) : (
                                <ArrowUpDown className="h-4 w-4 text-slate-400" />
                              )}
                            </div>
                          </TableHead>
                          <TableHead 
                            className="font-semibold text-slate-900 min-w-[150px] hidden lg:table-cell cursor-pointer hover:bg-slate-50"
                            onClick={() => handleSort("breed")}
                          >
                            <div className="flex items-center gap-2">
                              Breed
                              {sortField === "breed" ? (
                                sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                              ) : (
                                <ArrowUpDown className="h-4 w-4 text-slate-400" />
                              )}
                            </div>
                          </TableHead>
                          <TableHead className="font-semibold text-slate-900 min-w-[150px] hidden lg:table-cell">House</TableHead>
                          <TableHead className="font-semibold text-slate-900 min-w-[150px] hidden lg:table-cell">Batch</TableHead>
                          <TableHead 
                            className="font-semibold text-slate-900 min-w-[150px] hidden xl:table-cell cursor-pointer hover:bg-slate-50"
                            onClick={() => handleSort("startDate")}
                          >
                            <div className="flex items-center gap-2">
                              Start Date
                              {sortField === "startDate" ? (
                                sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                              ) : (
                                <ArrowUpDown className="h-4 w-4 text-slate-400" />
                              )}
                            </div>
                          </TableHead>
                          <TableHead className="font-semibold text-slate-900 min-w-[150px] hidden xl:table-cell">Age</TableHead>
                          {hasInactiveFlocks && (
                            <TableHead className="font-semibold text-slate-900 min-w-[150px] hidden xl:table-cell">Reason for Inactivation</TableHead>
                          )}
                          <TableHead className="font-semibold text-slate-900 min-w-[150px] hidden xl:table-cell">Notes</TableHead>
                          <TableHead className={cn("font-semibold text-slate-900 text-center min-w-[100px]", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {paginatedFlocks.map((flock) => (
                          <TableRow key={flock.flockId} className="hover:bg-slate-50 transition-colors">
                            <TableCell className={cn("font-medium text-slate-900 bg-white", isMobile && "sticky-col-date")}>
                              <div className="flex flex-col">
                                <span>{flock.name}</span>
                                <div className="flex items-center gap-2 text-xs text-slate-500 sm:hidden mt-1">
                                  <Badge 
                                    variant={flock.active ? "default" : "secondary"}
                                    className={flock.active ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"}
                                  >
                                    {flock.active ? "Active" : "Inactive"}
                                  </Badge>
                                </div>
                              </div>
                            </TableCell>
                            <TableCell className="hidden sm:table-cell">
                              <TooltipProvider>
                                <Tooltip>
                                  <TooltipTrigger>
                                    <Badge 
                                      variant={flock.active ? "default" : "secondary"}
                                      className={flock.active ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"}
                                    >
                                      {flock.active ? "Active" : "Inactive"}
                                    </Badge>
                                  </TooltipTrigger>
                                  {!flock.active && (
                                    <TooltipContent>
                                      <p>{flock.inactivationReason}{flock.inactivationReason === 'other' && `: ${flock.otherReason}`}</p>
                                    </TooltipContent>
                                  )}
                                </Tooltip>
                              </TooltipProvider>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden md:table-cell">
                              <div className="flex items-center gap-2">
                                <Users className="w-4 h-4 text-slate-400" />
                                <span>{getCurrentBirds(flock).toLocaleString()} birds</span>
                                {flock.flockId in flockBirdsLeftMap && flockBirdsLeftMap[flock.flockId] !== flock.quantity && (
                                  <span className="text-xs text-slate-400">(of {flock.quantity.toLocaleString()})</span>
                                )}
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden lg:table-cell">
                              <div className="flex items-center gap-2">
                                <Bird className="w-4 h-4 text-slate-400" />
                                <span>{flock.breed}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden lg:table-cell">
                              <div className="flex items-center gap-2">
                                <Home className="w-4 h-4 text-slate-400" />
                                <span>{getHouseName(flock)}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden lg:table-cell">
                              <div className="flex items-center gap-2">
                                <Users className="w-4 h-4 text-slate-400" />
                                <span>{flock.batchName || 'N/A'}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden xl:table-cell">
                              <div className="flex items-center gap-2">
                                <Calendar className="w-4 h-4 text-slate-400" />
                                <span>{new Date(flock.startDate).toLocaleDateString()}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden xl:table-cell">
                              <span className="text-sm">{formatAge(flock.startDate)}</span>
                            </TableCell>
                            {hasInactiveFlocks && (
                              <TableCell className="text-slate-600 hidden xl:table-cell">
                                <div className="flex items-center gap-2">
                                  <span>{flock.inactivationReason || '-'}</span>
                                  {flock.inactivationReason === 'other' && flock.otherReason && <span>({flock.otherReason})</span>}
                                </div>
                              </TableCell>
                            )}
                            <TableCell className="text-slate-600 hidden xl:table-cell">
                              <span>{truncateText(flock.notes, 50)}</span>
                            </TableCell>
                            <TableCell className={cn("text-center whitespace-nowrap bg-white", isMobile && "sticky-col-actions")}>
                              <div className="flex items-center justify-center gap-1 min-w-[90px]">
                                <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-blue-50 hover:text-blue-600" onClick={() => openEditDialog(flock.flockId)}>
                                  <Pencil className="w-4 h-4" />
                                </Button>
                                {permissions.canDelete && (
                                  <Button
                                    variant="ghost"
                                    size="icon"
                                    className="h-8 w-8 text-red-600 hover:text-red-700 hover:bg-red-50"
                                    onClick={() => openDeleteDialog(flock.flockId)}
                                  >
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

            {/* Flock Totals Summary */}
            {!loading && flocks.length > 0 && (
              <div className={cn("grid gap-3", isMobile ? "grid-cols-1" : "grid-cols-1 sm:grid-cols-3")}>
                <Card className="bg-white">
                  <CardContent className={cn("p-4", isMobile && "p-3")}>
                    <div className={cn("flex gap-3", isMobile ? "flex-col items-start" : "items-center justify-between")}>
                      <div className="flex items-center gap-2">
                        <Bird className="w-5 h-5 text-emerald-600" />
                        <div>
                          <span className="text-sm font-semibold text-slate-900">Overall Total Birds</span>
                          <span className="text-xs text-slate-500 block">Sum of initial flock quantities</span>
                        </div>
                      </div>
                      <span className={cn("font-bold text-emerald-700 leading-tight", isMobile ? "text-3xl" : "text-2xl")}>
                        {overallTotalBirds.toLocaleString()}
                      </span>
                    </div>
                  </CardContent>
                </Card>
                <Card className="bg-white">
                  <CardContent className={cn("p-4", isMobile && "p-3")}>
                    <div className={cn("flex gap-3", isMobile ? "flex-col items-start" : "items-center justify-between")}>
                      <div className="flex items-center gap-2">
                        <AlertCircle className="w-5 h-5 text-red-600" />
                        <div>
                          <span className="text-sm font-semibold text-slate-900">Total Mortality</span>
                          <span className="text-xs text-slate-500 block">Cumulative losses across all flocks</span>
                        </div>
                      </div>
                      <span className={cn("font-bold text-red-600 leading-tight", isMobile ? "text-3xl" : "text-2xl")}>
                        {totalMortality.toLocaleString()}
                      </span>
                    </div>
                  </CardContent>
                </Card>
                <Card className="bg-white">
                  <CardContent className={cn("p-4", isMobile && "p-3")}>
                    <div className={cn("flex gap-3", isMobile ? "flex-col items-start" : "items-center justify-between")}>
                      <div className="flex items-center gap-2">
                        <Users className="w-5 h-5 text-blue-600" />
                        <div>
                          <span className="text-sm font-semibold text-slate-900">Total Birds Left</span>
                          <span className="text-xs text-slate-500 block">
                            Sum of latest production &ldquo;birds left&rdquo; per flock, or placed quantity if none yet
                          </span>
                        </div>
                      </div>
                      <span className={cn("font-bold text-blue-700 leading-tight", isMobile ? "text-3xl" : "text-2xl")}>
                        {totalBirdsLeft.toLocaleString()}
                      </span>
                    </div>
                  </CardContent>
                </Card>
              </div>
            )}
            
            {/* Pagination */}
            {!loading && filteredFlocks.length > 0 && totalPages > 1 && (
              <div className="flex items-center justify-between mt-6">
                <div className="text-sm text-slate-600">
                  Showing {startIndex + 1} to {Math.min(endIndex, filteredFlocks.length)} of {filteredFlocks.length} flocks
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

      {/* Create Flock Dialog */}
      <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Bird className="w-5 h-5 text-green-600" /> Add New Flock
            </DialogTitle>
            <DialogDescription>Enter the flock information below</DialogDescription>
          </DialogHeader>
          {createError && (
            <Alert variant="destructive"><AlertDescription>{createError}</AlertDescription></Alert>
          )}
          <form onSubmit={handleCreateSubmit} className="space-y-4">
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock Information</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Assign to Flock Batch *</Label>
                  <div className="relative">
                    <select className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                      value={createForm.batchId || ''} onChange={(e) => handleCreateBatchChange(e.target.value ? parseInt(e.target.value) : 0)} disabled={createLoading} required>
                      <option value="">Please select a batch</option>
                      {flockBatches.map(b => <option key={b.batchId} value={b.batchId}>{b.batchName}</option>)}
                    </select>
                    <Users className="w-4 h-4 text-slate-400 absolute right-3 top-3 pointer-events-none" />
                  </div>
                  {createSelectedBatch && <p className="text-xs text-slate-500">Available: {createSelectedBatch.numberOfBirds} birds</p>}
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Name *</Label>
                  <Input placeholder="e.g., Flock A - Rhode Island Reds" value={createForm.name} onChange={(e) => setCreateForm({ ...createForm, name: e.target.value })} required disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Breed *</Label>
                  <Input placeholder="e.g., Rhode Island Red" value={createForm.breed} onChange={(e) => setCreateForm({ ...createForm, breed: e.target.value })} required disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Start Date *</Label>
                  <Input type="date" value={createForm.startDate} onChange={(e) => setCreateForm({ ...createForm, startDate: e.target.value })} required disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Number of Birds *</Label>
                  <Input type="number" min="1" placeholder="e.g., 100" value={createForm.quantity} onChange={(e) => setCreateForm({ ...createForm, quantity: parseInt(e.target.value) || 0 })} required disabled={createLoading} />
                  {createSelectedBatch && <p className="text-xs text-slate-500">Remaining: {createSelectedBatch.numberOfBirds - createForm.quantity} birds</p>}
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Assign to House</Label>
                  <div className="relative">
                    <select className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                      value={createForm.houseId ?? ''} onChange={(e) => setCreateForm({ ...createForm, houseId: e.target.value ? parseInt(e.target.value) : null })} disabled={createLoading}>
                      <option value="">No house</option>
                      {houses.map(h => <option key={h.houseId} value={h.houseId}>{(h as any).houseName || (h as any).name || `House ${h.houseId}`}</option>)}
                    </select>
                    <Home className="w-4 h-4 text-slate-400 absolute right-3 top-3" />
                  </div>
                </div>
              </div>
            </div>
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Status &amp; Notes</div>
              <div className="p-4 bg-white space-y-4">
                <div className="flex items-center space-x-2">
                  <Switch checked={createForm.active} onCheckedChange={(checked) => setCreateForm({ ...createForm, active: checked })} disabled={createLoading} />
                  <Label className="text-sm font-medium text-slate-700">Active Flock</Label>
                  <p className="text-xs text-slate-500 ml-2">(Uncheck if this flock is no longer active)</p>
                </div>
                {!createForm.active && (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Inactivation Reason</Label>
                      <select className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                        value={createForm.inactivationReason} onChange={(e) => setCreateForm({ ...createForm, inactivationReason: e.target.value })} disabled={createLoading}>
                        <option value="">Select a reason</option>
                        <option value="all flock sold">All flock sold</option>
                        <option value="all flocks on the market">All flocks on the market</option>
                        <option value="disease outbreak">Disease outbreak</option>
                        <option value="end of production cycle">End of production cycle</option>
                        <option value="relocation">Relocation</option>
                        <option value="other">Other</option>
                      </select>
                    </div>
                    {createForm.inactivationReason === 'other' && (
                      <div className="space-y-2">
                        <Label className="text-sm font-medium text-slate-700">Other Reason</Label>
                        <Input placeholder="Please specify the reason" value={createForm.otherReason} onChange={(e) => setCreateForm({ ...createForm, otherReason: e.target.value })} disabled={createLoading} />
                      </div>
                    )}
                  </div>
                )}
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Notes (Optional)</Label>
                  <textarea placeholder="Add any additional notes about the flock" value={createForm.notes}
                    onChange={(e) => setCreateForm({ ...createForm, notes: e.target.value })}
                    className="w-full rounded-md border border-slate-200 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[80px]" disabled={createLoading} />
                </div>
              </div>
            </div>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button type="submit" disabled={createLoading}>
                {createLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating...</> : <><Bird className="w-4 h-4 mr-2" />Create Flock</>}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit Flock Dialog */}
      <Dialog open={isEditDialogOpen} onOpenChange={setIsEditDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Pencil className="w-5 h-5 text-blue-600" /> Edit Flock
            </DialogTitle>
            <DialogDescription>Update the flock information below</DialogDescription>
          </DialogHeader>
          {editError && (
            <Alert variant="destructive"><AlertDescription>{editError}</AlertDescription></Alert>
          )}
          {editFetching ? (
            <div className="py-8 text-center">
              <Loader2 className="w-8 h-8 animate-spin mx-auto mb-2 text-blue-600" />
              <p className="text-slate-600">Loading flock...</p>
            </div>
          ) : (
            <form onSubmit={handleEditSubmit} className="space-y-4">
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock Information</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Assign to Flock Batch</Label>
                    <div className="relative">
                      <select className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                        value={editForm.batchId ?? ''} onChange={(e) => handleEditBatchChange(e.target.value ? parseInt(e.target.value) : null)} disabled={editLoading}>
                        <option value="">No batch</option>
                        {flockBatches.map(b => <option key={b.batchId} value={b.batchId}>{b.batchName}</option>)}
                      </select>
                      <Users className="w-4 h-4 text-slate-400 absolute right-3 top-3" />
                    </div>
                    {editSelectedBatch && <p className="text-xs text-slate-500">Available: {editSelectedBatch.numberOfBirds} birds</p>}
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Name *</Label>
                    <Input placeholder="e.g., Flock A - Rhode Island Reds" value={editForm.name} onChange={(e) => setEditForm({ ...editForm, name: e.target.value })} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Breed *</Label>
                    <Input placeholder="e.g., Rhode Island Red" value={editForm.breed} onChange={(e) => setEditForm({ ...editForm, breed: e.target.value })} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Start Date *</Label>
                    <Input type="date" value={editForm.startDate} onChange={(e) => setEditForm({ ...editForm, startDate: e.target.value })} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Number of Birds *</Label>
                    <Input type="number" min="1" placeholder="e.g., 100" value={editForm.quantity} onChange={(e) => setEditForm({ ...editForm, quantity: parseInt(e.target.value) || 0 })} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Assign to House</Label>
                    <div className="relative">
                      <select className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                        value={editForm.houseId ?? ''} onChange={(e) => setEditForm({ ...editForm, houseId: e.target.value ? parseInt(e.target.value) : null })} disabled={editLoading}>
                        <option value="">No house</option>
                        {houses.map(h => <option key={h.houseId} value={h.houseId}>{(h as any).houseName || (h as any).name || `House ${h.houseId}`}</option>)}
                      </select>
                      <Home className="w-4 h-4 text-slate-400 absolute right-3 top-3" />
                    </div>
                  </div>
                </div>
              </div>
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Status &amp; Notes</div>
                <div className="p-4 bg-white space-y-4">
                  <div className="flex items-center space-x-2">
                    <Switch checked={editForm.active} onCheckedChange={(checked) => setEditForm({ ...editForm, active: checked })} disabled={editLoading} />
                    <Label className="text-sm font-medium text-slate-700">Active Flock</Label>
                    <p className="text-xs text-slate-500 ml-2">(Uncheck if this flock is no longer active)</p>
                  </div>
                  {!editForm.active && (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div className="space-y-2">
                        <Label className="text-sm font-medium text-slate-700">Reason for Inactivation</Label>
                        <select className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          value={editForm.inactivationReason} onChange={(e) => setEditForm({ ...editForm, inactivationReason: e.target.value })} disabled={editLoading}>
                          <option value="">Select a reason</option>
                          <option value="all flock sold">All flock sold</option>
                          <option value="all flocks on the market">All flocks on the market</option>
                          <option value="disease outbreak">Disease outbreak</option>
                          <option value="end of production cycle">End of production cycle</option>
                          <option value="relocation">Relocation</option>
                          <option value="other">Other</option>
                        </select>
                      </div>
                      {editForm.inactivationReason === 'other' && (
                        <div className="space-y-2">
                          <Label className="text-sm font-medium text-slate-700">Other Reason</Label>
                          <Input placeholder="Please specify the reason" value={editForm.otherReason} onChange={(e) => setEditForm({ ...editForm, otherReason: e.target.value })} disabled={editLoading} />
                        </div>
                      )}
                    </div>
                  )}
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Notes (Optional)</Label>
                    <textarea placeholder="Add any additional notes about the flock" value={editForm.notes || ''}
                      onChange={(e) => setEditForm({ ...editForm, notes: e.target.value })}
                      className="w-full rounded-md border border-slate-200 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[80px]" disabled={editLoading} />
                  </div>
                </div>
              </div>
              <div className="flex gap-3 justify-end pt-2">
                <Button type="button" onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                <Button type="submit" disabled={editLoading}>
                  {editLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : <><Save className="w-4 h-4 mr-2" />Update Flock</>}
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
            <AlertDialogTitle>Delete Flock</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this flock? This action cannot be undone.
            </AlertDialogDescription>
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

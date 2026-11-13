"use client"

import { useSetupEmbedded, shellClass, SetupTaskBar, SetupTabTools } from "@/components/setup/setup-embed"
import { useEffect, useState, useRef, useMemo } from "react"
import { useRouter } from "next/navigation"
import { BreedSelect } from "@/components/poultry/breed-select"
import { FlockTypeSelect } from "@/components/poultry/flock-type-select"
import { defaultFlockType, flockTypeOf, isBroilerFlock, type FlockType } from "@/lib/poultry/flock-type"
import { usePoultryBusinessType, useRefreshPoultryEggFeatures } from "@/hooks/use-poultry-egg-features"
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
import { NumberInput } from "@/components/ui/number-input"
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
import { getFlocks, getFlock, createFlock, updateFlock, deleteFlock, getFlockEditContext, type Flock, type FlockEditContext, type FlockInput } from "@/lib/api/flock"
import { FlockHistoryPanel, openingDraftFrom, openingDraftToEdit, openingDraftWarnings, type OpeningHistoryDraft } from "@/components/poultry/flock-history-panel"
import { createExistingFlock } from "@/lib/api/bird-reconciliation"
import { ExistingFlockFields, FlockModeSelector, emptyExistingFlockDraft, existingFlockHistory, type ExistingFlockDraft, type FlockCreationMode } from "@/components/poultry/existing-flock-fields"
import { getHouses, type House } from "@/lib/api/house"
import { HousePicker } from "@/components/poultry/house-picker"
import { getBatchBirdReconciliation, type BatchBirdReconciliationRow } from "@/lib/api/bird-reconciliation"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import { getFlockPositions, type FlockPositionRow } from "@/lib/api/flock-positions"
import { flockLifetime, positionsById } from "@/lib/flocks/bird-position"
import { farmBirdTotals, isBatchNotArrived } from "@/lib/flocks/farm-bird-totals"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import { getBirdsLeftForFlockFromRecords } from "@/lib/utils/production-records"
import { getOpeningPositions, type OpeningFlockPosition } from "@/lib/api/poultry-farm-setup"
import {
  flockCountsTowardBirdTotals,
  getFlockLifecycleStatus,
  isFlockClosed,
  shouldAutoActivateFlock,
} from "@/lib/utils/flock-eligibility"
import { clearFlocksCache } from "@/lib/utils/flock-utils"
import { BatchAllocationDialog } from "@/components/poultry/batch-allocation-dialog"
import { getUserContext } from "@/lib/utils/user-context"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"

// Scorecards on a phone: tinted in the card's own colour (as on Flock Batch).
// sm and up keep the white card.
const MOBILE_TINT = {
  emerald: "bg-emerald-50 border-emerald-200 sm:bg-white sm:border-slate-200",
  red:     "bg-red-50 border-red-200 sm:bg-white sm:border-slate-200",
  sky:     "bg-sky-50 border-sky-200 sm:bg-white sm:border-slate-200",
  blue:    "bg-blue-50 border-blue-200 sm:bg-white sm:border-slate-200",
  amber:   "bg-amber-50 border-amber-200 sm:bg-white sm:border-slate-200",
  slate:   "bg-slate-50 border-slate-300 sm:bg-white sm:border-slate-200",
} as const

export function FlocksPage() {
  const embedded = useSetupEmbedded()
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  // 399: Layer / Broiler. The business type only shows a new flock its default.
  const businessType = usePoultryBusinessType()
  const refreshEggFeatures = useRefreshPoultryEggFeatures()
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
  // Breeds this farm already uses, offered first in the breed picker. Taken from
  // the batches AND the flocks, because a flock may carry a breed its batch does
  // not -- that is what the per-flock override is for.
  const knownBreeds = useMemo(() => {
    const all = [...flockBatches.map((b) => b.breed), ...flocks.map((f) => f.breed)]
    return Array.from(new Set(all.map((b) => (b ?? "").trim()).filter(Boolean)))
  }, [flockBatches, flocks])

  // Map of flockId -> noOfBirdsLeft from the most recent production record
  const [flockBirdsLeftMap, setFlockBirdsLeftMap] = useState<Record<number, number>>({})
  // Saved opening positions (Initial Farm Setup / "existing flock"): the birds
  // ORIGINALLY placed, keyed by flock. flock.quantity for such a flock is the
  // live count when it was registered, so it cannot be the "of" figure.
  const [openingByFlock, setOpeningByFlock] = useState<Record<number, OpeningFlockPosition>>({})
  // 421: every flock's bird position from the server (fnflock_birdposition):
  // placed, the opening historical reduction, what was recorded since, live
  // now. Empty when the API predates 421 -- the old per-page figures are used.
  const [positionByFlock, setPositionByFlock] = useState<Map<number, FlockPositionRow>>(new Map())
  // The server's bird accounting per batch (migration 413): how many of a
  // batch's birds are still not in any flock, after flocks AND birds sold or
  // lost before placing. A batch's size alone says nothing about what is left.
  const [reconByBatch, setReconByBatch] = useState<Map<number, BatchBirdReconciliationRow>>(new Map())
  const loadReconByBatch = () =>
    getBatchBirdReconciliation()
      .then((rows) => setReconByBatch(new Map(rows.map((r) => [r.batchId, r]))))
      .catch(() => setReconByBatch(new Map()))

  /** Birds a flock was placed with: its opening position, else its quantity. */
  const placedBirds = (f: { flockId: number; quantity?: number | null }) =>
    openingByFlock[f.flockId]?.originallyPlaced ?? (Number(f.quantity) || 0)

  /** Birds of a batch not in any flock yet. */
  const notYetPlaced = (batch: FlockBatch) => {
    const r = reconByBatch.get(batch.batchId)
    if (r) return Math.max(0, r.unallocatedPool)
    // Before 413 is reachable: batch size less the birds its flocks were placed with.
    const used = flocks.filter((f) => f.batchId === batch.batchId).reduce((a, f) => a + placedBirds(f), 0)
    return Math.max(0, (Number(batch.numberOfBirds) || 0) - used)
  }
  /** Loaded once; mortality for the summary is derived in useMemo so it matches the same flocks as the other two cards. */
  const [productionRecordsForFarm, setProductionRecordsForFarm] = useState<ProductionRecord[]>([])
  const autoActivateAttemptedRef = useRef<Set<number>>(new Set())
  const autoActivateSyncInFlightRef = useRef(false)

  // Create dialog state
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  // "Add Multiple Flocks" -- the same allocation workflow the Flock Purchases
  // page opens, entered here with no batch chosen yet.
  const [isAllocateDialogOpen, setIsAllocateDialogOpen] = useState(false)
  const [createLoading, setCreateLoading] = useState(false)
  const [createError, setCreateError] = useState("")
  const emptyFlockForm = { name: "", startDate: "", breed: "", quantity: 0, active: true, hasArrived: false, houseId: null as number | null, batchId: 0, inactivationReason: "", otherReason: "", notes: "",
    /** "" = automatic: the server's default (broiler breed, else company type). */
    flockType: "" as "" | FlockType }
  const [createForm, setCreateForm] = useState({ ...emptyFlockForm })
  const [createSelectedBatch, setCreateSelectedBatch] = useState<FlockBatch | null>(null)
  // 413: new flock, or one already operating (placed vs remaining + history).
  const todayIso = new Date().toISOString().split("T")[0]
  const [createMode, setCreateMode] = useState<FlockCreationMode>("new")
  const [existingDraft, setExistingDraft] = useState<ExistingFlockDraft>(() => emptyExistingFlockDraft(todayIso))

  // Closing and reopening flocks live on their own page, Tools > Flock
  // Closeout (/flock-closeout). This page only shows the Closed state.

  // Edit dialog state
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editingFlockId, setEditingFlockId] = useState<number | null>(null)
  const [editForm, setEditForm] = useState({ ...emptyFlockForm })
  const [editFetching, setEditFetching] = useState(false)
  // 414: the flock as it was registered, read from posted records.
  const [editCtx, setEditCtx] = useState<FlockEditContext | null>(null)
  const [openingDraft, setOpeningDraft] = useState<OpeningHistoryDraft | null>(null)
  const [deleteCtx, setDeleteCtx] = useState<FlockEditContext | null>(null)
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

  // When start date is reached, activate flocks that were only waiting for placement (safe reasons).
  useEffect(() => {
    if (loading || flocks.length === 0 || autoActivateSyncInFlightRef.current) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return

    const candidates = flocks.filter(
      (f) => shouldAutoActivateFlock(f) && !autoActivateAttemptedRef.current.has(f.flockId)
    )
    if (candidates.length === 0) return

    autoActivateSyncInFlightRef.current = true
    void (async () => {
      try {
        for (const f of candidates) {
          autoActivateAttemptedRef.current.add(f.flockId)
          const payload: FlockInput = {
            farmId: f.farmId,
            userId: f.userId,
            name: f.name,
            startDate: f.startDate,
            breed: f.breed,
            quantity: f.quantity,
            active: true,
            hasArrived: Boolean(f.hasArrived),
            houseId: f.houseId ?? null,
            batchId: f.batchId ?? 0,
            inactivationReason: "",
            otherReason: f.otherReason ?? "",
            notes: f.notes ?? "",
          }
          const res = await updateFlock(f.flockId, payload)
          if (!res.success) {
            autoActivateAttemptedRef.current.delete(f.flockId)
            console.warn("[FlocksPage] Auto-activate failed", f.flockId, res.message)
          }
        }
        clearFlocksCache()
        await loadFlocks()
        await loadProductionBirdsLeft()
      } finally {
        autoActivateSyncInFlightRef.current = false
      }
    })()
  }, [loading, flocks])

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

    void getOpeningPositions(userId, farmId)
      .then((r) => {
        if (!r.success || !r.data?.positions) return
        const map: Record<number, OpeningFlockPosition> = {}
        for (const p of r.data.positions) {
          // Latest position per flock wins (same rule as the edit context).
          const prev = map[p.flockId]
          if (!prev || p.openingPositionId > prev.openingPositionId) map[p.flockId] = p
        }
        setOpeningByFlock(map)
      })
      .catch(() => { /* list still shows current birds */ })

    void getFlockPositions(farmId)
      .then((rows) => setPositionByFlock(positionsById(rows)))
      .catch(() => setPositionByFlock(new Map()))

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

        console.log("[FlocksPage] Birds left map from production records:", map)
        setFlockBirdsLeftMap(map)
        setProductionRecordsForFarm(res.data)
      } else {
        setProductionRecordsForFarm([])
      }
    } catch (e) {
      console.error("[FlocksPage] Error loading production records for birds left:", e)
      setProductionRecordsForFarm([])
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
    loadReconByBatch()   // a save or delete changes what each batch has left
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
      // Prefill start date + breed from the batch (editable) to save data entry.
      setCreateForm(prev => ({
        ...prev,
        batchId,
        startDate: selected?.startDate ? String(selected.startDate).split("T")[0] : prev.startDate,
        breed: selected?.breed || prev.breed,
      }))
    }
  }

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) { toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" }); return }
    if (!createForm.name.trim() || !createForm.startDate) { toastFormGuide(toast, "Add a flock name and the date the flock started."); return }
    if (createForm.quantity <= 0) { toastFormGuide(toast, createMode === "existing" ? "Enter how many birds were originally placed in this flock." : "Enter how many birds are in this flock — use a number greater than zero."); return }
    const existing = createMode === "existing" ? existingFlockHistory(createForm.quantity, existingDraft) : null
    if (existing?.problem) { toastFormGuide(toast, existing.problem); return }
    if (!createForm.batchId || createForm.batchId === 0) { toastFormGuide(toast, "Link this flock to a batch so bird counts stay accurate."); return }
    if (createSelectedBatch && createForm.quantity > createSelectedBatch.numberOfBirds) { toastFormGuide(toast, `That batch only has ${createSelectedBatch.numberOfBirds} birds available — lower the flock size or pick another batch.`); return }
    // Room/house capacity — cannot place more birds than the room can hold.
    if (createForm.houseId) {
      const house = houses.find(h => h.houseId === createForm.houseId)
      const cap = house?.capacity ?? 0
      if (cap > 0) {
        const occupied = flocks.filter(f => f.houseId === createForm.houseId && f.active).reduce((s, f) => s + (f.quantity || 0), 0)
        // An existing flock occupies the pen with the birds standing today.
        const standing = existing ? existing.history.currentLiveBirds : createForm.quantity
        if (occupied + standing > cap) {
          toast({ title: "Over room capacity", description: `${house?.name || "That room"} holds ${cap} birds${occupied ? ` and already has ${occupied}` : ""}. You're trying to place ${(occupied + standing).toLocaleString()}. Reduce the number or pick another room.`, variant: "destructive" })
          return
        }
      }
    }

    setCreateLoading(true)
    setCreateError("")

    const flockData: FlockInput = {
      farmId, userId,
      name: createForm.name, startDate: createForm.startDate, breed: createForm.breed,
      quantity: createForm.quantity, active: createForm.active,
      hasArrived: createForm.hasArrived,
      houseId: createForm.houseId, batchId: createForm.batchId,
      inactivationReason: createForm.inactivationReason,
      otherReason: createForm.inactivationReason === 'other' ? createForm.otherReason : '',
      notes: createForm.notes,
      flockType: createForm.flockType || undefined,
    }

    let result: { success: boolean; message?: string }
    if (existing) {
      // One transaction on the server: flock at its remaining birds, the batch
      // charged the placed birds once, the difference as opening history.
      try {
        await createExistingFlock({ ...flockData, startDate: `${flockData.startDate}T00:00:00` }, existing.history, existingDraft.asOfDate,
          embedded ? "Farm Setup" : "Flocks page")
        result = { success: true }
      } catch (err: any) {
        result = { success: false, message: err?.message || "Failed to create flock" }
      }
    } else {
      result = await createFlock(flockData)
    }
    if (result.success) {
      toast({ title: "Success!", description: existing
        ? `Flock created: ${existing.history.originallyPlaced.toLocaleString()} placed, ${existing.history.currentLiveBirds.toLocaleString()} remaining.`
        : "Flock created successfully." })
      setCreateMode("new")
      setExistingDraft(emptyExistingFlockDraft(todayIso))
      setIsCreateDialogOpen(false)
      refreshEggFeatures()
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

    setEditCtx(null)
    setOpeningDraft(null)
    const [result, ctx] = await Promise.all([getFlock(flockId, userId, farmId), getFlockEditContext(flockId, farmId)])
    setEditCtx(ctx)
    setOpeningDraft(openingDraftFrom(ctx))
    if (result.success && result.data) {
      const f = result.data
      setEditForm({
        name: f.name || "", startDate: f.startDate?.split('T')[0] || "", breed: f.breed || "",
        quantity: f.quantity || 0, active: f.active ?? false,
        hasArrived: Boolean(f.hasArrived),
        houseId: f.houseId ?? null, batchId: f.batchId ?? 0,
        inactivationReason: f.inactivationReason ?? "", otherReason: f.otherReason ?? "",
        notes: f.notes ?? "",
        flockType: flockTypeOf(f),
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
    if (!editForm.name.trim() || !editForm.startDate) { toastFormGuide(toast, "Add a flock name and the date the flock started."); return }
    // A flock registered with an opening position takes its count from the
    // history section; any other flock needs a count on the form.
    if (!openingDraft && editForm.quantity <= 0) { toastFormGuide(toast, "Enter how many birds are in this flock — use a number greater than zero."); return }

    // Out-of-proportion numbers are WARNINGS — the save still goes through.
    const localWarnings: string[] = [...openingDraftWarnings(editCtx, openingDraft)]
    const birdsOnForm = openingDraft
      ? Number(openingDraft.live || 0) + (editCtx?.quantityAdjustments ?? 0)
      : editForm.quantity
    if (editForm.houseId) {
      const house = houses.find(h => h.houseId === editForm.houseId)
      const cap = house?.capacity ?? 0
      if (cap > 0) {
        const occupied = flocks.filter(f => f.houseId === editForm.houseId && f.active && f.flockId !== editingFlockId).reduce((s, f) => s + (f.quantity || 0), 0)
        if (occupied + birdsOnForm > cap) {
          localWarnings.push(`${house?.name || "That room"} holds ${cap.toLocaleString()} birds${occupied ? ` and already has ${occupied.toLocaleString()}` : ""}; with this flock it has ${(occupied + birdsOnForm).toLocaleString()}.`)
        }
      }
    }

    setEditLoading(true)
    setEditError("")

    const flockData: Partial<FlockInput> = {
      name: editForm.name, startDate: editForm.startDate + 'T00:00:00Z', breed: editForm.breed,
      quantity: editForm.quantity, active: editForm.active,
      hasArrived: editForm.hasArrived,
      houseId: editForm.houseId ?? null, batchId: editForm.batchId ?? 0,
      farmId, userId,
      inactivationReason: editForm.inactivationReason,
      otherReason: editForm.inactivationReason === 'other' ? editForm.otherReason : '',
      notes: editForm.notes,
      flockType: editForm.flockType || undefined,
      ...(openingDraft ? { openingHistory: openingDraftToEdit(openingDraft), quantity: birdsOnForm } : {}),
    }

    const result = await updateFlock(editingFlockId, flockData)
    if (result.success) {
      clearFlocksCache()
      // Server warnings restate the local ones more precisely; show each once.
      const warnings = Array.from(new Set([...(result.warnings ?? []), ...localWarnings]))
      if (warnings.length > 0) {
        toast({ title: "Flock updated — please check", description: warnings.join(" "), duration: 12000 })
      } else {
        toast({ title: "Success!", description: "Flock updated successfully." })
      }
      setIsEditDialogOpen(false)
      refreshEggFeatures()
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
    setDeleteCtx(null)
    setDeleteDialogOpen(true)
    // 414: say up front whether it can be deleted, and why not.
    const { farmId } = getUserContext()
    if (farmId) void getFlockEditContext(id, farmId).then(setDeleteCtx)
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
      // Only what the server confirmed it did -- see lib/api/flock.ts.
      clearFlocksCache()
      toast({ title: "Flock deleted", description: result.message || "The flock has been deleted." })
      loadFlocks()
      loadFilterData()
      loadProductionBirdsLeft()
      refreshEggFeatures()
      setCurrentPage(1)
    } else {
      toast({ title: "Not deleted", description: result.message || "Something went wrong. Please try again.", variant: "destructive" })
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
      currentList = currentList.filter((flock) => {
        const life = getFlockLifecycleStatus(flock)
        if (selectedStatus === "active") return life === "active"
        if (selectedStatus === "closed") return life === "closed"
        // "Inactive" is everything not running that has not been closed out.
        return life !== "active" && life !== "closed"
      })
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

  // Bottom totals (farm-wide; ignore current filters so the page-level summary stays stable).
  // 421: birds a flock STARTED with -- for an onboarded flock flock.quantity is
  // the opening LIVE count, which drops every bird lost before tracking began.
  const startedBirdsOf = (f: Flock): number => {
    const p = positionByFlock.get(f.flockId)
    return p ? flockLifetime(p).started : (Number(f.quantity) || 0)
  }
  // Active / Inactive: birds ALIVE now in those flocks (deaths and sales
  // taken off), once the bird positions have loaded; placed before that.
  const liveOrStartedOf = (f: Flock): number => {
    const p = positionByFlock.get(f.flockId)
    return p ? p.currentLiveBirds : startedBirdsOf(f)
  }
  const totalBirdsCount = useMemo(() =>
    flocks.filter(f => f.hasArrived).reduce((sum, f) => sum + startedBirdsOf(f), 0),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [flocks, positionByFlock]
  )
  const totalActiveBirdsCount = useMemo(() =>
    flocks.filter(f => f.hasArrived && f.active).reduce((sum, f) => sum + liveOrStartedOf(f), 0),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [flocks, positionByFlock]
  )
  const totalInactiveBirdsCount = useMemo(() =>
    flocks.filter(f => f.hasArrived && !f.active).reduce((sum, f) => sum + liveOrStartedOf(f), 0),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [flocks, positionByFlock]
  )
  // The whole farm, the reports' rule: bought = died + sold + other + left,
  // including birds sold or lost straight from a batch before it went into
  // flocks (summing flocks alone misses those). Null on an older API.
  // Batches still Pending or starting on a later day: their birds are not on
  // the farm yet, so the unplaced ones stay out of every bird total.
  const notArrivedBatchIds = useMemo(
    () => new Set(flockBatches.filter((b) => isBatchNotArrived(b)).map((b) => b.batchId)),
    [flockBatches],
  )
  const farmTotals = useMemo(
    () => farmBirdTotals(reconByBatch.values(), positionByFlock.values(), notArrivedBatchIds),
    [reconByBatch, positionByFlock, notArrivedBatchIds],
  )
  // Every bird sold over the flocks' lives: before tracking began + posted sales.
  const totalBirdsSoldCount = useMemo(() =>
    flocks.filter(f => f.hasArrived).reduce((sum, f) => {
      const p = positionByFlock.get(f.flockId)
      return sum + (p ? flockLifetime(p).sold : 0)
    }, 0),
    [flocks, positionByFlock]
  )

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
    // 421: live now -- the last count less sales / closeouts made after it.
    const p = positionByFlock.get(flock.flockId)
    if (p) return p.currentLiveBirds
    if (flock.flockId in flockBirdsLeftMap) {
      return flockBirdsLeftMap[flock.flockId]
    }
    return flock.quantity || 0
  }

  // Birds originally placed: the saved opening position when the flock was
  // registered as already operating, otherwise the flock's own quantity.
  const getPlacedBirds = (flock: Flock): number => {
    const p = positionByFlock.get(flock.flockId)
    if (p && p.originallyPlaced > 0) return p.originallyPlaced
    const o = openingByFlock[flock.flockId]
    if (o && o.originallyPlaced > 0) return o.originallyPlaced
    return flock.quantity || 0
  }

  const hasInactiveFlocks = useMemo(() => {
    return flocks.some((flock) => getFlockLifecycleStatus(flock) !== "active")
  }, [flocks])

  // Placed quantity only for flocks past start date and active (same rule as birds-left total)
  const overallTotalBirds = useMemo(() => {
    return flocks
      .filter((f) => flockCountsTowardBirdTotals(f))
      .reduce((sum, flock) => sum + startedBirdsOf(flock), 0)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [flocks, positionByFlock])

  // Same flock set as overallTotalBirds / totalBirdsLeft (not farm-wide), so the three cards are comparable.
  const totalMortality = useMemo(() => {
    const eligibleIds = new Set(
      flocks.filter((f) => flockCountsTowardBirdTotals(f)).map((f) => f.flockId)
    )
    // 421: lifetime deaths -- opening historical mortality + recorded.
    if (positionByFlock.size > 0) {
      let total = 0
      for (const id of eligibleIds) {
        const p = positionByFlock.get(id)
        if (p) total += flockLifetime(p).deaths
      }
      return total
    }
    return productionRecordsForFarm.reduce((sum, r) => {
      const fid = r.flockId
      if (fid == null || !eligibleIds.has(fid)) return sum
      return sum + (r.mortality ?? 0)
    }, 0)
  }, [flocks, productionRecordsForFarm, positionByFlock])

  const totalMortalityAllRowsFarm = useMemo(() => {
    // 421: every flock's lifetime deaths (opening historical + recorded).
    if (positionByFlock.size > 0) {
      let total = 0
      for (const p of positionByFlock.values()) if (!p.isDeleted) total += flockLifetime(p).deaths
      return total
    }
    return productionRecordsForFarm.reduce((sum, r) => sum + (Number(r.mortality) || 0), 0)
  }, [productionRecordsForFarm, positionByFlock])

  // Total birds left = same flocks as overallTotalBirds; per-flock current count from production or placed qty
  const totalBirdsLeft = useMemo(() => {
    return flocks
      .filter((f) => flockCountsTowardBirdTotals(f))
      .reduce((sum, flock) => {
        const p = positionByFlock.get(flock.flockId)
        if (p) return sum + p.currentLiveBirds
        if (flock.flockId in flockBirdsLeftMap) {
          return sum + flockBirdsLeftMap[flock.flockId]
        }
        return sum + (flock.quantity || 0)
      }, 0)
  }, [flocks, flockBirdsLeftMap, positionByFlock])

  /** Same flocks as the three summary cards: placed minus latest birds left (compare to sum of daily deaths). */
  const birdsLostPlacedMinusLeft = useMemo(
    () => Math.max(0, overallTotalBirds - totalBirdsLeft),
    [overallTotalBirds, totalBirdsLeft],
  )

  /**
   * Birds that left the same flocks WITHOUT dying: sold, culled, transferred
   * or another opening reduction (lifetime, from the bird position).  A sale
   * lowers the headcount too, so the deaths-vs-headcount check must allow for
   * it.  Null before 421 is deployed -- the check then compares deaths only.
   */
  const birdsRemovedNotDied = useMemo(() => {
    if (positionByFlock.size === 0) return null
    let n = 0
    for (const f of flocks) {
      if (!flockCountsTowardBirdTotals(f)) continue
      const p = positionByFlock.get(f.flockId)
      if (!p) continue
      const l = flockLifetime(p)
      n += l.sold + l.culled + l.transferred + l.other
    }
    return n
  }, [flocks, positionByFlock])
  /** Deaths plus every other recorded way a bird left: what the headcount drop should equal. */
  const accountedLosses = totalMortality + (birdsRemovedNotDied ?? 0)

  const flockLifecycleBadge = (flock: Flock) => {
    const life = getFlockLifecycleStatus(flock)
    if (life === "pending") {
      return (
        <Badge variant="secondary" className="bg-amber-100 text-amber-900 border border-amber-200">
          Pending
        </Badge>
      )
    }
    if (life === "active") {
      return (
        <Badge variant="default" className="bg-green-100 text-green-800">
          Active
        </Badge>
      )
    }
    if (life === "closed") {
      return (
        <Badge variant="secondary" className="bg-slate-800 text-white">
          Closed
        </Badge>
      )
    }
    return (
      <Badge variant="secondary" className="bg-gray-100 text-gray-800">
        Inactive
      </Badge>
    )
  }

  return (
    <div className={shellClass(embedded, "flex h-screen bg-slate-50")}>
      {!embedded && <DashboardSidebar onLogout={handleLogout} />}
      <div className={shellClass(embedded, "flex-1 flex flex-col min-w-0")}>
        {!embedded && <DashboardHeader />}
        <main className={embedded ? "min-w-0" : "flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0"}>
          <div className={embedded ? "space-y-3" : "space-y-6"}>
            {/* Page Header */}
            <div className={embedded ? "hidden" : "flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4"}>
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-green-100 rounded-lg flex items-center justify-center">
                  <Bird className="w-5 h-5 text-green-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Flock Groups (Pens / Flocks)</h1>
                  <p className="text-sm text-slate-600">Manage your bird flocks</p>
                </div>
              </div>
              <SetupTaskBar tasks={[
                { id: "add", label: "Add Flock", icon: Plus, primary: true, onClick: openCreateDialog },
                { id: "bulk", label: "Add Multiple Flocks", icon: Plus, onClick: () => setIsAllocateDialogOpen(true) },
              ]} />
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
                              <SelectItem value="closed">Closed</SelectItem>
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
                              <NumberInput
                                
                                placeholder="Min"
                                value={draftQuantityMin}
                                onChange={(e) => setDraftQuantityMin(e.target.value || "")}
                                className="h-12 text-base"
                              />
                            </div>
                            <div className="space-y-2">
                              <label className="text-xs font-medium text-slate-500">Max</label>
                              <NumberInput
                                
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
              // In Farm Setup the filters sit beside the tab's description line
              // (compact sizes); standalone they keep their own box.
              <SetupTabTools standaloneClassName="flex flex-wrap items-center gap-2 p-2 bg-white rounded border">
                <div className={embedded ? "relative w-40" : "relative w-full sm:w-[240px]"}>
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder={embedded ? "Search flocks" : "Search by name, breed, or notes..."} value={search} onChange={(e) => setSearch(e.target.value)} className={embedded ? "h-9 bg-white pl-9" : "pl-9"} />
                </div>

                <Select value={selectedStatus} onValueChange={setSelectedStatus}>
                  <SelectTrigger className={embedded ? "h-9 w-auto gap-2 bg-white" : "w-[180px]"}>
                    <SelectValue placeholder="Status" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Statuses</SelectItem>
                    <SelectItem value="active">Active</SelectItem>
                    <SelectItem value="inactive">Inactive</SelectItem>
                    <SelectItem value="closed">Closed</SelectItem>
                  </SelectContent>
                </Select>

                <Select value={selectedHouseId} onValueChange={setSelectedHouseId}>
                  <SelectTrigger className={embedded ? "h-9 w-auto gap-2 bg-white" : "w-[180px]"}>
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
                  <SelectTrigger className={embedded ? "h-9 w-auto gap-2 bg-white" : "w-[180px]"}>
                    <SelectValue placeholder="Batch" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Batches</SelectItem>
                    {flockBatches.map(b => (
                      <SelectItem key={b.batchId} value={String(b.batchId)}>{b.batchName}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                <Input type="date" placeholder="From" title="From date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className={embedded ? "h-9 w-[140px] bg-white" : "w-[140px]"} />
                <Input type="date" placeholder="To" title="To date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className={embedded ? "h-9 w-[140px] bg-white" : "w-[140px]"} />

                <NumberInput
                  
                  placeholder={embedded ? "Min qty" : "Min Quantity"}
                  value={quantityMin}
                  onChange={(e) => handleQuantityMinChange(e.target.value)}
                  className={embedded ? "h-9 w-24 bg-white" : "w-[120px]"}
                />

                <NumberInput
                  
                  placeholder={embedded ? "Max qty" : "Max Quantity"}
                  value={quantityMax}
                  onChange={(e) => handleQuantityMaxChange(e.target.value)}
                  className={embedded ? "h-9 w-24 bg-white" : "w-[120px]"}
                />

                {embedded ? (
                  <Button variant="outline" size="icon" className="ml-auto h-9 w-9 bg-white" onClick={clearFilters} title="Reset filters" aria-label="Reset filters">
                    <RefreshCw className="h-4 w-4" />
                  </Button>
                ) : (
                  <div className="ml-auto">
                    <Button variant="outline" size="sm" onClick={clearFilters}>
                      <RefreshCw className="h-4 w-4 mr-2" /> Reset
                    </Button>
                  </div>
                )}
              </SetupTabTools>
            )}

            {/* Error Alert */}
            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Farm totals — compact scorecards (standalone page only) */}
            {!embedded && !loading && flocks.length > 0 && (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <div
                  className={cn("rounded-lg border px-3 py-2.5 shadow-sm", MOBILE_TINT.emerald)}
                  title="Every bird the farm received, including birds that died or were sold before tracking began or before they went into a flock."
                >
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-600">
                    <Bird className="h-3.5 w-3.5 shrink-0 text-emerald-600" />
                    Overall Total Birds
                  </div>
                  <div className="mt-1 text-xl font-bold leading-tight tabular-nums text-emerald-600">
                    {(farmTotals?.bought ?? overallTotalBirds).toLocaleString()}
                  </div>
                  <p className="mt-0.5 truncate text-[11px] text-slate-500">
                    {farmTotals ? "Every bird bought, all batches" : "Placed, including history before setup"}
                  </p>
                </div>
                <div
                  className={cn("rounded-lg border px-3 py-2.5 shadow-sm", MOBILE_TINT.red)}
                  title="Lifetime deaths: before tracking began (Initial Farm Setup), straight from a batch, plus the Deaths on every production record."
                >
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-600">
                    <AlertCircle className="h-3.5 w-3.5 shrink-0 text-red-600" />
                    Total Deaths
                  </div>
                  <div className="mt-1 flex items-baseline justify-between gap-2">
                    <span className="text-xl font-bold leading-tight tabular-nums text-red-600">
                      {(farmTotals?.died ?? totalMortality).toLocaleString()}
                    </span>
                    {!farmTotals && <span className="text-[11px] text-slate-500">
                      + inactive:{" "}
                      <span className="font-semibold tabular-nums text-slate-800">
                        {totalMortalityAllRowsFarm.toLocaleString()}
                      </span>
                    </span>}
                  </div>
                  {farmTotals ? (
                    <p className="mt-0.5 truncate text-[11px] text-slate-500"
                       title="Total birds less deaths and sales (and any culled, moved or corrected birds) gives the birds left.">
                      Sold:{" "}
                      <span className="font-semibold tabular-nums text-slate-800">{farmTotals.sold.toLocaleString()}</span>
                      {farmTotals.other !== 0 && (
                        <> · <span title="Culled, transferred, birds in flocks that were deleted, count corrections, or birds never accounted for.">other</span>:{" "}
                          <span className="font-semibold tabular-nums text-slate-800">{farmTotals.other.toLocaleString()}</span></>
                      )}
                    </p>
                  ) : (
                  <p className="mt-0.5 truncate text-[11px] text-slate-500">
                    Placed − birds left:{" "}
                    <span className="font-semibold tabular-nums text-slate-800">
                      {birdsLostPlacedMinusLeft.toLocaleString()}
                    </span>
                    {(birdsRemovedNotDied ?? 0) > 0 && (
                      <span title="Birds sold, culled or transferred out of these flocks (including before tracking began). They lower the headcount without being deaths.">
                        {" "}· sold / culled / moved:{" "}
                        <span className="font-semibold tabular-nums text-slate-800">
                          {(birdsRemovedNotDied ?? 0).toLocaleString()}
                        </span>
                      </span>
                    )}
                  </p>
                  )}
                  {!farmTotals && accountedLosses > birdsLostPlacedMinusLeft + 1 && (
                    <p
                      className="mt-0.5 truncate text-[11px] text-amber-800/90"
                      title="Deaths plus sold / culled / moved birds are more than the drop in headcount — check rows for cumulative death counts or the same day entered twice."
                    >
                      Higher than headcount drop — check for cumulative or duplicate rows
                    </p>
                  )}
                  {!farmTotals && birdsLostPlacedMinusLeft > accountedLosses + 1 && (
                    <p
                      className="mt-0.5 truncate text-[11px] text-slate-600"
                      title={`Headcount fell by ${(birdsLostPlacedMinusLeft - accountedLosses).toLocaleString()} more than deaths${birdsRemovedNotDied == null ? "" : " plus sold / culled / moved birds"} — some losses were not recorded, or a bird count was corrected.`}
                    >
                      {(birdsLostPlacedMinusLeft - accountedLosses).toLocaleString()} birds unaccounted for
                    </p>
                  )}
                </div>
                <div
                  className={cn("rounded-lg border px-3 py-2.5 shadow-sm", MOBILE_TINT.blue)}
                  title="Birds alive now in flocks (latest count). Batch birds not yet put into a flock are shown in their own card below."
                >
                  <div className="flex items-center gap-1.5 text-xs font-medium text-slate-600">
                    <Users className="h-3.5 w-3.5 shrink-0 text-blue-600" />
                    Total Birds Left
                  </div>
                  <div className="mt-1 text-xl font-bold leading-tight tabular-nums text-blue-700">
                    {(farmTotals ? farmTotals.left - farmTotals.notInFlock : totalBirdsLeft).toLocaleString()}
                  </div>
                  <p className="mt-0.5 truncate text-[11px] text-slate-500">
                    {farmTotals
                      ? (farmTotals.notInFlock > 0
                          ? `Alive in flocks · ${farmTotals.notInFlock.toLocaleString()} more not yet in a flock`
                          : "Alive now")
                      : "Latest birds left per flock, or placed if no log"}
                  </p>
                </div>
              </div>
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
                  <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-emerald-50">
                    <Bird className="h-8 w-8 text-emerald-600" />
                  </div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No flocks found</h3>
                  <p className="text-slate-600 mb-6">Get started by creating your first flock.</p>
                  <div className="flex flex-col sm:flex-row gap-2 justify-center">
                    <Button variant="outline" className="gap-2" onClick={() => setIsAllocateDialogOpen(true)}>
                      <Plus className="w-4 h-4" />
                      Add Multiple Flocks
                    </Button>
                    <Button className="gap-2 bg-emerald-600 hover:bg-emerald-700" onClick={openCreateDialog}>
                      <Plus className="w-4 h-4" />
                      Add Flock
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden gap-0 py-0">
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {paginatedFlocks.map((flock, idx) => (
                        <Collapsible key={flock.flockId} defaultOpen className={cn("group overflow-hidden rounded-xl border shadow-sm transition-shadow hover:shadow-md",
                          // Alternate cards, like Flock Batch, Suppliers and Customers on a phone.
                          idx % 2 === 0 ? "bg-amber-50 border-amber-200" : "bg-white border-slate-200")}>
                          <div className="p-4 transition-colors active:bg-slate-50/80">
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="flex min-w-0 flex-1 items-start gap-2.5">
                                  <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-emerald-50 text-emerald-600"><Bird className="h-4 w-4" /></span>
                                  <div className="min-w-0 flex-1">
                                    <div className="flex items-center gap-2 flex-wrap">
                                      <span className="truncate font-semibold text-slate-900">{flock.name}</span>{isBroilerFlock(flock) && <Badge variant="secondary" className="ml-1.5 bg-orange-100 text-orange-800 border border-orange-200 text-[10px] px-1.5 py-0">Broiler</Badge>}
                                      {flockLifecycleBadge(flock)}
                                    </div>
                                    <div className="mt-1 flex items-baseline gap-2 flex-wrap">
                                      <span className="text-lg font-bold tabular-nums text-emerald-600">{getCurrentBirds(flock).toLocaleString()}</span>
                                      <span className="text-xs text-slate-500">
                                        {getPlacedBirds(flock) !== getCurrentBirds(flock) ? `of ${getPlacedBirds(flock).toLocaleString()} birds` : "birds"}
                                      </span>
                                      <span className="text-slate-300">•</span>
                                      <span className="text-sm text-slate-600">{formatDateShort(flock.startDate)}</span>
                                    </div>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                {/* Each figure in its own tinted box (phone cards). */}
                                <div className="grid grid-cols-2 gap-2 [&>*]:min-w-0">
                                  <div className="flex items-center justify-between gap-2 rounded-lg border px-2.5 py-1.5 border-violet-200 bg-violet-50"><span className="text-violet-700">Breed</span> <span className="truncate font-medium text-slate-900">{flock.breed || "—"}</span></div>
                                  <div className="flex items-center justify-between gap-2 rounded-lg border px-2.5 py-1.5 border-sky-200 bg-sky-50"><span className="text-sky-700">House</span> <span className="truncate font-medium text-slate-900">{getHouseName(flock)}</span></div>
                                  <div className="flex items-center justify-between gap-2 rounded-lg border px-2.5 py-1.5 col-span-2 border-blue-200 bg-blue-50"><span className="text-blue-700">Batch</span> <span className="truncate font-medium text-slate-900">{flock.batchName || "N/A"}</span></div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(flock.flockId)}>
                                    <Pencil className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  {permissions.canDelete && !isFlockClosed(flock) && (
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
                        <TableRow className="border-b bg-slate-50">
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
                                <span>{flock.name}</span>{isBroilerFlock(flock) && <Badge variant="secondary" className="ml-1.5 bg-orange-100 text-orange-800 border border-orange-200 text-[10px] px-1.5 py-0">Broiler</Badge>}
                                <div className="flex items-center gap-2 text-xs text-slate-500 sm:hidden mt-1">
                                  {flockLifecycleBadge(flock)}
                                </div>
                              </div>
                            </TableCell>
                            <TableCell className="hidden sm:table-cell">
                              <TooltipProvider>
                                <Tooltip>
                                  <TooltipTrigger asChild>
                                    <span className="inline-flex">{flockLifecycleBadge(flock)}</span>
                                  </TooltipTrigger>
                                  {getFlockLifecycleStatus(flock) === "pending" && (
                                    <TooltipContent>
                                      <p>Start date not reached — not counted in farm bird totals yet.</p>
                                    </TooltipContent>
                                  )}
                                  {getFlockLifecycleStatus(flock) === "closed" && (
                                    <TooltipContent>
                                      <p>
                                        Closed {(flock.closedDate ?? "").slice(0, 10)}
                                        {flock.closeReason ? ` — ${flock.closeReason}` : ""}
                                      </p>
                                    </TooltipContent>
                                  )}
                                  {getFlockLifecycleStatus(flock) === "inactive" && flock.inactivationReason && (
                                    <TooltipContent>
                                      <p>
                                        {flock.inactivationReason}
                                        {flock.inactivationReason === "other" && flock.otherReason
                                          ? `: ${flock.otherReason}`
                                          : ""}
                                      </p>
                                    </TooltipContent>
                                  )}
                                </Tooltip>
                              </TooltipProvider>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden md:table-cell tabular-nums">
                              <div className="flex items-center gap-2">
                                <Users className="w-4 h-4 text-slate-400" />
                                {getPlacedBirds(flock) !== getCurrentBirds(flock) ? (
                                  <span title={`${getCurrentBirds(flock).toLocaleString()} alive of ${getPlacedBirds(flock).toLocaleString()} originally placed`}>
                                    {getCurrentBirds(flock).toLocaleString()} <span className="text-slate-400">of</span> {getPlacedBirds(flock).toLocaleString()}
                                  </span>
                                ) : (
                                  <span>{getCurrentBirds(flock).toLocaleString()} birds</span>
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
                                <span>{fmtDateTime(flock.startDate, flock)}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden xl:table-cell">
                              <span className="text-sm">{formatAge(flock.startDate)}</span>
                            </TableCell>
                            {hasInactiveFlocks && (
                              <TableCell className="text-slate-600 hidden xl:table-cell">
                                <div className="flex items-center gap-2">
                                  {isFlockClosed(flock) ? (
                                    <span>Closed: {flock.closeReason || '-'}</span>
                                  ) : (
                                    <>
                                      <span>{flock.inactivationReason || '-'}</span>
                                      {flock.inactivationReason === 'other' && flock.otherReason && <span>({flock.otherReason})</span>}
                                    </>
                                  )}
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
                                {/* A closed flock is history: it is reopened, never deleted. */}
                                {permissions.canDelete && !isFlockClosed(flock) && (
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

            {/* Bird totals (page bottom; standalone page only) */}
            {!embedded && !loading && flocks.length > 0 && (
              <div className={cn("grid gap-3", isMobile ? "grid-cols-2" : farmTotals ? "grid-cols-2 sm:grid-cols-3 lg:grid-cols-5" : "grid-cols-2 sm:grid-cols-4")}>
                <div className={cn("p-4 rounded-xl border shadow-sm", MOBILE_TINT.blue)}>
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Total Birds</div>
                  <div className="mt-1 text-2xl font-bold tabular-nums text-slate-900">{(farmTotals?.bought ?? totalBirdsCount).toLocaleString()}</div>
                </div>
                <div className={cn("p-4 rounded-xl border shadow-sm", MOBILE_TINT.emerald)}>
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Total Active Birds</div>
                  <div className="mt-1 text-2xl font-bold tabular-nums text-emerald-600">{(farmTotals ? Math.max(0, farmTotals.left - totalInactiveBirdsCount - farmTotals.notInFlock) : totalActiveBirdsCount).toLocaleString()}</div>
                </div>
                <div className={cn("p-4 rounded-xl border shadow-sm", MOBILE_TINT.slate)}>
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Total Inactive Birds</div>
                  <div className="mt-1 text-2xl font-bold tabular-nums text-slate-600">{totalInactiveBirdsCount.toLocaleString()}</div>
                </div>
                {/* Birds alive on the farm but not divided into flocks yet.
                    Active + Inactive + this = Total Birds Left. */}
                {farmTotals && (
                  <div className={cn("p-4 rounded-xl border shadow-sm", MOBILE_TINT.sky)}
                       title="Birds of arrived batches that have not been divided into flocks yet. They are alive on the farm but have no production records until they are put into a flock.">
                    <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Not Yet in a Flock</div>
                    <div className="mt-1 text-2xl font-bold tabular-nums text-sky-600">{farmTotals.notInFlock.toLocaleString()}</div>
                  </div>
                )}
                <div className={cn("p-4 rounded-xl border shadow-sm", MOBILE_TINT.amber)}>
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Total Birds Sold</div>
                  <div className="mt-1 text-2xl font-bold tabular-nums text-amber-600">{(farmTotals?.sold ?? totalBirdsSoldCount).toLocaleString()}</div>
                </div>
              </div>
            )}
          </div>
        </main>
      </div>

      {/* Create Flock Dialog */}
      <BatchAllocationDialog
        open={isAllocateDialogOpen}
        onOpenChange={setIsAllocateDialogOpen}
        // Only batches that still have birds to place. Allocated totals are
        // derived from the flocks this page already holds -- the same rows
        // spflock_gettotalquantityforbatch sums server-side, so the list cannot
        // offer a batch the server would then refuse.
        batches={flockBatches.map((b) => ({
          batchId: b.batchId,
          batchCode: b.batchCode,
          batchName: b.batchName,
          numberOfBirds: Number(b.numberOfBirds) || 0,
          unallocatedBirds: Math.max(
            0,
            (Number(b.numberOfBirds) || 0) -
              flocks.filter((f) => f.batchId === b.batchId).reduce((sum, f) => sum + (Number(f.quantity) || 0), 0),
          ),
        }))}
        source="Flock Groups page"
        onCreated={async () => { await loadFlocks() }}
      />

      <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
        <DialogContent className="w-[95vw] sm:max-w-4xl max-h-[90vh] overflow-y-auto">
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
            <FlockModeSelector mode={createMode} onChange={setCreateMode} disabled={createLoading} />
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
                  </div>
                  {createSelectedBatch && <BatchAvailability batch={createSelectedBatch} free={notYetPlaced(createSelectedBatch)} recon={reconByBatch.get(createSelectedBatch.batchId)} />}
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Name *</Label>
                  <Input placeholder="e.g., Flock A - Rhode Island Reds" value={createForm.name} onChange={(e) => setCreateForm({ ...createForm, name: e.target.value })} required disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Breed</Label>
                  <BreedSelect value={createForm.breed} known={knownBreeds} disabled={createLoading}
                    onChange={(breed) => setCreateForm({ ...createForm, breed })} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Flock type</Label>
                  <FlockTypeSelect
                    value={createForm.flockType || defaultFlockType(createForm.breed, businessType)}
                    automatic={!createForm.flockType}
                    disabled={createLoading}
                    onChange={(flockType) => setCreateForm({ ...createForm, flockType })} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Start Date *</Label>
                  <Input type="date" value={createForm.startDate} onChange={(e) => setCreateForm({ ...createForm, startDate: e.target.value })} required disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">{createMode === "existing" ? "Birds Originally Placed *" : "Number of Birds *"}</Label>
                  <NumberInput min="1" placeholder="e.g., 100" value={createForm.quantity} onChange={(e) => setCreateForm({ ...createForm, quantity: parseInt(e.target.value) || 0 })} required disabled={createLoading} />
                  {createSelectedBatch && createForm.quantity > 0 && (() => {
                    const left = notYetPlaced(createSelectedBatch) - createForm.quantity
                    return left >= 0
                      ? <p className="text-xs text-slate-500">{left.toLocaleString()} birds left to place after this</p>
                      : <p className="text-xs text-red-600">{(-left).toLocaleString()} more than the batch has left to place</p>
                  })()}
                </div>
                {createMode === "existing" && (
                  <div className="md:col-span-2">
                    <ExistingFlockFields placed={createForm.quantity} draft={existingDraft} onChange={setExistingDraft}
                      maxDate={todayIso} disabled={createLoading} />
                  </div>
                )}
                <div className="space-y-2 md:col-span-2">
                  <Label className="text-sm font-medium text-slate-700">Assign to House</Label>
                  <HousePicker houses={houses} flocks={flocks} disabled={createLoading}
                    value={createForm.houseId}
                    onChange={(houseId) => setCreateForm((prev) => ({ ...prev, houseId }))}
                    birds={createMode === "existing" ? (Number(existingDraft.currentLiveBirds) || 0) : createForm.quantity} />
                </div>
              </div>
            </div>
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Status &amp; Notes</div>
              <div className="p-4 bg-white space-y-4">
                <div className="flex items-center space-x-2">
                  <Switch checked={createForm.hasArrived} onCheckedChange={(checked) => setCreateForm({ ...createForm, hasArrived: checked })} disabled={createLoading} />
                  <Label className="text-sm font-medium text-slate-700">Flock Has Arrived</Label>
                  <p className="text-xs text-slate-500 ml-2">(Leave off until birds physically arrive — status stays Pending)</p>
                </div>
                <div className="flex items-center space-x-2">
                  <Switch checked={createForm.active} onCheckedChange={(checked) => setCreateForm({ ...createForm, active: checked })} disabled={createLoading || !createForm.hasArrived} />
                  <Label className="text-sm font-medium text-slate-700">Active Flock</Label>
                  <p className="text-xs text-slate-500 ml-2">(Only applies once the flock has arrived)</p>
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
        {/* overflow-x-hidden + min-w-0: never wider than the phone (it scrolled sideways). */}
        <DialogContent className="w-[95vw] sm:max-w-4xl max-h-[90vh] overflow-y-auto overflow-x-hidden [&>*]:min-w-0">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Pencil className="w-5 h-5 text-blue-600" /> Edit Flock
            </DialogTitle>
            <DialogDescription>Update the flock information below</DialogDescription>
          </DialogHeader>
          {editError && (
            <Alert variant="destructive"><AlertDescription>{editError}</AlertDescription></Alert>
          )}
          {editingFlockId != null && isFlockClosed(flocks.find((f) => f.flockId === editingFlockId)) && (
            <Alert>
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>
                This flock is closed. Its name, breed and notes can still be corrected; to change its birds,
                house, dates or status, reopen it first from Tools &gt; Flock Closeout.
              </AlertDescription>
            </Alert>
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
                    </div>
                    {editSelectedBatch && (() => {
                      // Editing gives the flock back its own birds: they count
                      // against its batch today and would be freed by the change.
                      const me = flocks.find((f) => f.flockId === editingFlockId)
                      const own = me && me.batchId === editSelectedBatch.batchId ? placedBirds(me) : 0
                      return <BatchAvailability batch={editSelectedBatch} free={notYetPlaced(editSelectedBatch)} recon={reconByBatch.get(editSelectedBatch.batchId)} ownBirds={own} />
                    })()}
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Name *</Label>
                    <Input placeholder="e.g., Flock A - Rhode Island Reds" value={editForm.name} onChange={(e) => setEditForm({ ...editForm, name: e.target.value })} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Breed</Label>
                    <BreedSelect value={editForm.breed} known={knownBreeds} disabled={editLoading}
                      onChange={(breed) => setEditForm({ ...editForm, breed })} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Flock type</Label>
                    <FlockTypeSelect
                      value={editForm.flockType || "Layer"}
                      disabled={editLoading}
                      onChange={(flockType) => setEditForm({ ...editForm, flockType })} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Start Date *</Label>
                    <Input type="date" value={editForm.startDate} onChange={(e) => setEditForm({ ...editForm, startDate: e.target.value })} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Number of Birds *</Label>
                    {openingDraft ? (
                      <>
                        <NumberInput value={Number(openingDraft.live || 0) + (editCtx?.quantityAdjustments ?? 0)} disabled />
                        <p className="text-xs text-slate-500">Set from the registered bird count in Bird history below.</p>
                      </>
                    ) : (
                      <>
                        <NumberInput min="1" placeholder="e.g., 100" value={editForm.quantity} onChange={(e) => setEditForm({ ...editForm, quantity: parseInt(e.target.value) || 0 })} required disabled={editLoading} />
                        {(editCtx?.position?.productionrecordcount ?? 0) > 0 && (
                          <p className="text-xs text-slate-500">
                            Birds placed. Live birds now ({(editCtx?.position?.currentlivebirds ?? 0).toLocaleString()}) come from the latest production record.
                          </p>
                        )}
                      </>
                    )}
                  </div>
                  <div className="space-y-2 md:col-span-2">
                    <Label className="text-sm font-medium text-slate-700">Assign to House</Label>
                    <HousePicker houses={houses} flocks={flocks} disabled={editLoading}
                      value={editForm.houseId} excludeFlockId={editingFlockId}
                      onChange={(houseId) => setEditForm((prev) => ({ ...prev, houseId }))}
                      birds={openingDraft ? Number(openingDraft.live || 0) + (editCtx?.quantityAdjustments ?? 0) : editForm.quantity} />
                  </div>
                </div>
              </div>
              {editCtx && <FlockHistoryPanel ctx={editCtx} draft={openingDraft} onDraftChange={setOpeningDraft} disabled={editLoading} />}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Status &amp; Notes</div>
                <div className="p-4 bg-white space-y-4">
                  <div className="flex items-center space-x-2">
                    <Switch checked={editForm.hasArrived} onCheckedChange={(checked) => setEditForm({ ...editForm, hasArrived: checked })} disabled={editLoading} />
                    <Label className="text-sm font-medium text-slate-700">Flock Has Arrived</Label>
                    <p className="text-xs text-slate-500 ml-2">(Turn on once birds physically arrive)</p>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Switch checked={editForm.active} onCheckedChange={(checked) => setEditForm({ ...editForm, active: checked })} disabled={editLoading || !editForm.hasArrived} />
                    <Label className="text-sm font-medium text-slate-700">Active Flock</Label>
                    <p className="text-xs text-slate-500 ml-2">(Only applies once the flock has arrived)</p>
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
            <AlertDialogDescription asChild>
              <div className="space-y-2">
                {deleteCtx && !deleteCtx.canDelete ? (
                  <>
                    <p>This flock has posted activity and cannot be deleted:</p>
                    <ul className="list-disc pl-5 text-slate-700">
                      {deleteCtx.deleteBlockers.map((b) => <li key={b.source}>{b.rows.toLocaleString()} {b.label}</li>)}
                    </ul>
                    <p>Reverse those entries first, or close the flock (Tools &gt; Flock Closeout) to keep its history.</p>
                  </>
                ) : (
                  <p>
                    Delete this flock?
                    {deleteCtx?.position ? ` Its ${deleteCtx.position.originallyplaced.toLocaleString()} placed birds go back to the batch, and its opening entries are reversed.` : ""}
                    {" "}This cannot be undone.
                  </p>
                )}
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} disabled={isDeleting || (deleteCtx != null && !deleteCtx.canDelete)} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              {isDeleting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Deleting...</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

/** What a batch has left to place, and where the rest went. */
function BatchAvailability({ batch, free, recon, ownBirds = 0 }: {
  batch: FlockBatch
  free: number
  recon?: BatchBirdReconciliationRow
  ownBirds?: number
}) {
  const size = Number(batch.numberOfBirds) || 0
  const inFlocks = recon ? recon.originallyAllocated : Math.max(0, size - free)
  const sold = recon?.batchSold ?? 0
  const lost = recon ? recon.batchMortality + recon.batchCulled + recon.batchTransferred + recon.batchOtherRemovals : 0
  const segs = [
    { label: "in flocks", value: inFlocks, color: "bg-emerald-500" },
    { label: "sold before placing", value: sold, color: "bg-orange-400" },
    { label: "died or removed before placing", value: lost, color: "bg-rose-400" },
    { label: "free to place", value: free, color: "bg-indigo-500" },
  ]
  const total = Math.max(size, segs.reduce((a, g) => a + g.value, 0), 1)
  const max = ownBirds + free

  return (
    <div className="rounded-lg border border-slate-200 bg-slate-50 p-2.5 text-xs">
      <div className="flex items-baseline justify-between gap-2">
        {free > 0 ? (
          <span className="font-semibold text-indigo-700">{free.toLocaleString()} birds free to place</span>
        ) : (
          <span className="font-semibold text-slate-700">No birds left to place</span>
        )}
        <span className="text-slate-500">Batch of {size.toLocaleString()}</span>
      </div>
      <div className="mt-1.5 flex h-1.5 w-full gap-px overflow-hidden rounded-full bg-slate-200">
        {segs.filter((g) => g.value > 0).map((g) => (
          <div key={g.label} className={g.color} style={{ width: `${(g.value / total) * 100}%` }} title={`${g.value.toLocaleString()} ${g.label}`} />
        ))}
      </div>
      <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-0.5 text-slate-600">
        {segs.filter((g) => g.value > 0 && g.label !== "free to place").map((g) => (
          <span key={g.label} className="flex items-center gap-1">
            <span className={`h-2 w-2 rounded-full ${g.color}`} />
            <span className="font-medium tabular-nums text-slate-800">{g.value.toLocaleString()}</span> {g.label}
          </span>
        ))}
      </div>
      {ownBirds > 0 && (
        <div className="mt-2 border-t border-slate-200 pt-1.5 text-slate-600">
          This flock can have up to <span className="font-semibold tabular-nums text-slate-900">{max.toLocaleString()}</span> birds
          {free > 0
            ? <> (its own {ownBirds.toLocaleString()} + {free.toLocaleString()} free).</>
            : <>: the {ownBirds.toLocaleString()} it already has.</>}
        </div>
      )}
    </div>
  )
}

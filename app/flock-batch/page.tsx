"use client"

import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Input } from "@/components/ui/input"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Plus, Pencil, Trash2, Calendar as CalendarIcon, Bird, Users, Search, RefreshCw, Loader2, Save, Filter, ChevronDown, ChevronUp } from "lucide-react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { getFlockBatches, getFlockBatch, createFlockBatch, updateFlockBatch, deleteFlockBatch, type FlockBatch, type FlockBatchInput } from "@/lib/api/flock-batch"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { format } from "date-fns"
import { formatDateShort, cn } from "@/lib/utils"
import { Calendar } from "@/components/ui/calendar"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"

export default function FlockBatchesPage() {
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const [flockBatches, setFlockBatches] = useState<FlockBatch[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage] = useState(10)
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
  const [selectedBreed, setSelectedBreed] = useState<string>("ALL")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()

  useEffect(() => {
    if (isMobile) setShowAllColumnsMobile(false)
  }, [isMobile])
  
  // Dialog state for showing flocks
  const [flocksDialogOpen, setFlocksDialogOpen] = useState(false)
  const [selectedBatch, setSelectedBatch] = useState<FlockBatch | null>(null)
  const [batchFlocks, setBatchFlocks] = useState<Flock[]>([])
  const [loadingFlocks, setLoadingFlocks] = useState(false)

  // Create dialog state
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [createLoading, setCreateLoading] = useState(false)
  const [createError, setCreateError] = useState("")
  const [createForm, setCreateForm] = useState({ batchName: "", batchCode: "", startDate: "", breed: "", numberOfBirds: 0 })

  // Edit dialog state
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editingBatchId, setEditingBatchId] = useState<number | null>(null)
  const [editForm, setEditForm] = useState({ batchName: "", batchCode: "", startDate: "", breed: "", numberOfBirds: 0 })
  const [editFetching, setEditFetching] = useState(false)

  // Initial load
  useEffect(() => {
    loadFlockBatches()
  }, [])

  const loadFlockBatches = async () => {
    const { farmId, userId } = getUserContext()
    
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      setLoading(false)
      return
    }

    const result = await getFlockBatches(userId, farmId)
    
    if (result.success && result.data) {
      setFlockBatches(result.data)
      setCurrentPage(1)
    } else {
      setError(result.message || "Failed to load flock batches")
    }
    
    setLoading(false)
  }

  // Create handlers
  const openCreateDialog = () => {
    setCreateForm({ batchName: "", batchCode: "", startDate: "", breed: "", numberOfBirds: 0 })
    setCreateError("")
    setIsCreateDialogOpen(true)
  }

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      setCreateError("Farm ID or User ID not found")
      toast({ title: "Validation error", description: "Farm ID or User ID not found.", variant: "destructive" })
      return
    }

    if (!createForm.batchName.trim() || !createForm.batchCode.trim() || !createForm.breed.trim() || !createForm.startDate) {
      setCreateError("Please fill in all required fields")
      toast({ title: "Validation error", description: "Batch name, batch code, breed, and start date are required.", variant: "destructive" })
      return
    }
    if (createForm.numberOfBirds <= 0) {
      setCreateError("Number of birds must be greater than 0")
      toast({ title: "Validation error", description: "Number of birds must be greater than 0.", variant: "destructive" })
      return
    }

    setCreateLoading(true)
    setCreateError("")

    const flockBatchData: FlockBatchInput = {
      farmId,
      userId,
      batchName: createForm.batchName,
      batchCode: createForm.batchCode,
      startDate: createForm.startDate,
      breed: createForm.breed,
      numberOfBirds: createForm.numberOfBirds,
    }

    const result = await createFlockBatch(flockBatchData)
    if (result.success) {
      toast({ title: "Success!", description: "Flock batch created successfully." })
      setIsCreateDialogOpen(false)
      loadFlockBatches()
    } else {
      setCreateError(result.message || "Failed to create flock batch")
    }
    setCreateLoading(false)
  }

  // Edit handlers
  const openEditDialog = async (batchId: number) => {
    setEditingBatchId(batchId)
    setEditError("")
    setEditFetching(true)
    setIsEditDialogOpen(true)

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setEditError("User context not found.")
      setEditFetching(false)
      return
    }

    const result = await getFlockBatch(batchId, userId, farmId)
    if (result.success && result.data) {
      const b = result.data
      setEditForm({
        batchName: b.batchName || "",
        batchCode: b.batchCode || "",
        startDate: b.startDate ? b.startDate.split('T')[0] : "",
        breed: b.breed || "",
        numberOfBirds: b.numberOfBirds || 0,
      })
    } else {
      setEditError(result.message || "Failed to load flock batch")
    }
    setEditFetching(false)
  }

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editingBatchId) return
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      setEditError("User context not found.")
      toast({ title: "Validation error", description: "User context not found.", variant: "destructive" })
      return
    }

    if (!editForm.batchName.trim() || !editForm.batchCode.trim() || !editForm.breed.trim() || !editForm.startDate) {
      setEditError("Please fill in all required fields")
      toast({ title: "Validation error", description: "Batch name, batch code, breed, and start date are required.", variant: "destructive" })
      return
    }
    if (editForm.numberOfBirds <= 0) {
      setEditError("Number of birds must be greater than 0")
      toast({ title: "Validation error", description: "Number of birds must be greater than 0.", variant: "destructive" })
      return
    }

    setEditLoading(true)
    setEditError("")

    const flockBatchData: Partial<FlockBatchInput> = {
      batchName: editForm.batchName,
      batchCode: editForm.batchCode,
      startDate: editForm.startDate + 'T00:00:00Z',
      breed: editForm.breed,
      numberOfBirds: editForm.numberOfBirds,
      farmId,
      userId,
    }

    const result = await updateFlockBatch(editingBatchId, flockBatchData)
    if (result.success) {
      toast({ title: "Success!", description: "Flock batch updated successfully." })
      setIsEditDialogOpen(false)
      loadFlockBatches()
    } else {
      setEditError(result.message || "Failed to update flock batch")
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
      toast({ title: "Error", description: "Farm ID or User ID not found.", variant: "destructive" })
      return
    }
    setIsDeleting(true)
    const result = await deleteFlockBatch(deletingId, userId, farmId)
    if (result.success) {
      toast({ title: "Batch deleted", description: "The flock batch has been successfully deleted." })
      loadFlockBatches()
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

  const clearFilters = () => {
    setSearch("")
    setDateFrom("")
    setDateTo("")
    setSelectedBreed("ALL")
  }

  const distinctBreeds = useMemo(() => {
    const breeds = new Set(flockBatches.map(batch => batch.breed).filter(Boolean))
    return Array.from(breeds)
  }, [flockBatches])

  const filteredFlockBatches = useMemo(() => {
    let currentList = flockBatches

    if (search) {
      const query = search.toLowerCase()
      currentList = currentList.filter(batch => 
        (batch.batchName ?? '').toLowerCase().includes(query) ||
        (batch.batchCode ?? '').toLowerCase().includes(query)
      )
    }

    if (dateFrom) {
      currentList = currentList.filter(batch => batch.startDate?.split('T')[0] >= dateFrom)
    }
    if (dateTo) {
      currentList = currentList.filter(batch => batch.startDate?.split('T')[0] <= dateTo)
    }
    if (selectedBreed !== "ALL") {
      currentList = currentList.filter(batch => batch.breed === selectedBreed)
    }

    return currentList
  }, [flockBatches, search, dateFrom, dateTo, selectedBreed])

  // Pagination logic
  const sortedBatches = useMemo(() => sortData(filteredFlockBatches, sortKey, sortDir), [filteredFlockBatches, sortKey, sortDir])
  const totalPages = Math.ceil(sortedBatches.length / itemsPerPage)
  const startIndex = (currentPage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const currentFlockBatches = sortedBatches.slice(startIndex, endIndex)

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

  const handleViewFlocks = async (batch: FlockBatch) => {
    setSelectedBatch(batch)
    setFlocksDialogOpen(true)
    setLoadingFlocks(true)
    
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setLoadingFlocks(false)
      return
    }

    const result = await getFlocks(userId, farmId)
    if (result.success && result.data) {
      // Filter flocks by batchId
      const flocksForBatch = result.data.filter(flock => flock.batchId === batch.batchId)
      setBatchFlocks(flocksForBatch)
    }
    
    setLoadingFlocks(false)
  }


  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-center justify-between")}>
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-green-100 rounded-lg flex items-center justify-center">
                  <Bird className="w-5 h-5 text-green-600" />
                </div>
                <div className="min-w-0">
                  <h1 className={cn("font-bold text-slate-900", isMobile ? "text-xl" : "text-2xl")}>Flock Batches</h1>
                  <p className="text-sm text-slate-600">Manage your bird flock batches</p>
                </div>
              </div>
              <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700 shrink-0" onClick={openCreateDialog}>
                <Plus className="w-4 h-4" />
                Add Flock Batch
              </Button>
            </div>

            {/* Filters */}
            <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded border">
              <div className={cn("relative flex-1 min-w-0", !isMobile && "sm:w-[240px]")}>
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Search by name or code..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
              </div>
              {isMobile ? (
                <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                  <SheetTrigger asChild>
                    <Button variant="outline" size="sm" className="gap-2 shrink-0"><Filter className="h-4 w-4" /> Filters</Button>
                  </SheetTrigger>
                  <SheetContent side="bottom" className="rounded-t-2xl max-h-[85vh]">
                    <SheetHeader><SheetTitle>Filters</SheetTitle></SheetHeader>
                    <div className="space-y-4 pt-4">
                      <div className="grid grid-cols-2 gap-3">
                        <div className="space-y-2"><Label>Date From</Label><Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} /></div>
                        <div className="space-y-2"><Label>Date To</Label><Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} /></div>
                      </div>
                      <div className="space-y-2">
                        <Label>Breed</Label>
                        <Select value={selectedBreed} onValueChange={setSelectedBreed}>
                          <SelectTrigger><SelectValue placeholder="Breed" /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="ALL">All Breeds</SelectItem>
                            {distinctBreeds.map(breed => <SelectItem key={breed} value={breed}>{breed}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="flex gap-2 pt-2">
                        <Button variant="outline" className="flex-1" onClick={clearFilters}>Clear</Button>
                        <Button className="flex-1" onClick={() => setFiltersOpen(false)}>Apply</Button>
                      </div>
                    </div>
                  </SheetContent>
                </Sheet>
              ) : (
                <>
                  <Input type="date" placeholder="From" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" />
                  <Input type="date" placeholder="To" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" />
                  <Select value={selectedBreed} onValueChange={setSelectedBreed}>
                    <SelectTrigger className="w-[180px]"><SelectValue placeholder="Breed" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All Breeds</SelectItem>
                      {distinctBreeds.map(breed => <SelectItem key={breed} value={breed}>{breed}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <div className="ml-auto">
                    <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                  </div>
                </>
              )}
            </div>

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
                  <p className="text-slate-600">Loading flock batches...</p>
                </CardContent>
              </Card>
            ) : filteredFlockBatches.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="p-12 text-center">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4">
                    <Bird className="w-8 h-8 text-slate-400" />
                  </div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No flock batches found</h3>
                  <p className="text-slate-600 mb-6">Get started by creating your first flock batch.</p>
                  <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}>
                    <Plus className="w-4 h-4" />
                    Add Flock Batch
                  </Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {currentFlockBatches.map((batch, idx) => (
                        <Collapsible key={batch.batchId} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")} onClick={() => handleViewFlocks(batch)}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="font-semibold text-slate-900">{batch.batchName}</div>
                                  <div className="mt-1 flex flex-wrap items-baseline gap-2">
                                    <Badge variant="outline">{batch.batchCode}</Badge>
                                    <span className="text-slate-600">{batch.numberOfBirds.toLocaleString()} birds</span>
                                    <span className="text-slate-500">{batch.breed}</span>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm" onClick={(e) => e.stopPropagation()}>
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Start</span> <span className="font-medium">{batch.startDate ? formatDateShort(batch.startDate) : "—"}</span></div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" onClick={(e) => { e.stopPropagation(); openEditDialog(batch.batchId) }}>
                                    <Pencil className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  {permissions.canDelete && (
                                    <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={(e) => { e.stopPropagation(); openDeleteDialog(batch.batchId) }}>
                                      <Trash2 className="h-4 w-4 mr-2" /> Delete
                                    </Button>
                                  )}
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                      ))}
                      {currentFlockBatches.length > 0 && (
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
                        <span className="text-xs text-slate-600">Table view</span>
                        <Button variant="ghost" size="sm" onClick={() => setShowAllColumnsMobile(false)}>
                          <ChevronUp className="h-4 w-4 mr-1" /> Cards
                        </Button>
                      </div>
                    )}
                  <div className="overflow-x-auto">
                    <Table className={cn("w-full", !isMobile && "min-w-[600px]")}>
                      <TableHeader>
                        <TableRow className="border-b">
                          <SortableHeader label="Name" sortKey="name" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[150px]", isMobile && "sticky-col-date bg-slate-50")} />
                          <SortableHeader label="Code" sortKey="code" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[100px] hidden sm:table-cell" />
                          <SortableHeader label="Number of Birds" sortKey="numberOfBirds" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px] hidden md:table-cell" />
                          <SortableHeader label="Breed" sortKey="breed" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[150px] hidden lg:table-cell" />
                          <SortableHeader label="Start Date" sortKey="startDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[150px] hidden xl:table-cell" />
                          <TableHead className="font-semibold text-slate-900 text-center min-w-[100px]">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {currentFlockBatches.map((batch) => (
                          <TableRow 
                            key={batch.batchId} 
                            className="hover:bg-slate-50 transition-colors cursor-pointer"
                            onClick={() => handleViewFlocks(batch)}
                          >
                            <TableCell className={cn("font-medium text-slate-900 bg-white", isMobile && "sticky-col-date")}>
                              {batch.batchName}
                            </TableCell>
                            <TableCell className="hidden sm:table-cell">{batch.batchCode}</TableCell>
                            <TableCell className="text-slate-600 hidden md:table-cell">
                              <div className="flex items-center gap-2">
                                <Users className="w-4 h-4 text-slate-400" />
                                <span>{batch.numberOfBirds.toLocaleString()} birds</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden lg:table-cell">
                              <div className="flex items-center gap-2">
                                <Bird className="w-4 h-4 text-slate-400" />
                                <span>{batch.breed}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden xl:table-cell">
                              <div className="flex items-center gap-2">
                                <span>{new Date(batch.startDate).toLocaleDateString()}</span>
                              </div>
                            </TableCell>
                            <TableCell className={cn("text-center bg-white", isMobile && "sticky-col-actions")}>
                              <div className="flex items-center justify-center gap-1">
                                <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-blue-50 hover:text-blue-600" onClick={(e) => { e.stopPropagation(); openEditDialog(batch.batchId) }}>
                                  <Pencil className="w-4 h-4" />
                                </Button>
                                {permissions.canDelete && (
                                  <Button
                                    variant="ghost"
                                    size="icon"
                                    className="h-8 w-8 text-red-600 hover:text-red-700 hover:bg-red-50"
                                    onClick={(e) => { e.stopPropagation(); openDeleteDialog(batch.batchId) }}
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
                  </div>
                  )}
                </CardContent>
              </Card>
            )}
            
            {/* Pagination */}
            {!loading && sortedBatches.length > 0 && totalPages > 1 && (
              <div className="flex items-center justify-between mt-6">
                <div className="text-sm text-slate-600">
                  Showing {startIndex + 1} to {Math.min(endIndex, sortedBatches.length)} of {sortedBatches.length} flock batches
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

      {/* Flocks Dialog */}
      <Dialog open={flocksDialogOpen} onOpenChange={setFlocksDialogOpen}>
        <DialogContent className="max-w-4xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Flocks in Batch: {selectedBatch?.batchName}</DialogTitle>
            <DialogDescription>
              View all flocks created under this batch
            </DialogDescription>
          </DialogHeader>
          
          {loadingFlocks ? (
            <div className="py-8 text-center">
              <p className="text-slate-600">Loading flocks...</p>
            </div>
          ) : batchFlocks.length === 0 ? (
            <div className="py-8 text-center">
              <Bird className="w-12 h-12 text-slate-400 mx-auto mb-4" />
              <p className="text-slate-600">No flocks found for this batch</p>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="border rounded-lg">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
                      <TableHead>Breed</TableHead>
                      <TableHead>Quantity</TableHead>
                      <TableHead>Start Date</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {batchFlocks.map((flock) => (
                      <TableRow key={flock.flockId}>
                        <TableCell className="font-medium">{flock.name}</TableCell>
                        <TableCell>{flock.breed}</TableCell>
                        <TableCell>{flock.quantity.toLocaleString()} birds</TableCell>
                        <TableCell>{new Date(flock.startDate).toLocaleDateString()}</TableCell>
                        <TableCell>
                          <Badge variant={flock.active ? "default" : "secondary"} className={flock.active ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"}>
                            {flock.active ? "Active" : "Inactive"}
                          </Badge>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
              <div className="flex items-center justify-between pt-4 border-t">
                <div className="text-sm text-slate-600">
                  Total Flocks: <span className="font-semibold">{batchFlocks.length}</span>
                </div>
                <div className="text-sm text-slate-600">
                  Total Birds: <span className="font-semibold">
                    {batchFlocks.reduce((sum, f) => sum + (f.quantity || 0), 0).toLocaleString()}
                  </span>
                </div>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Create Flock Batch Dialog */}
      <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Bird className="w-5 h-5 text-green-600" /> Add New Flock Batch
            </DialogTitle>
            <DialogDescription>Enter the flock batch information below</DialogDescription>
          </DialogHeader>
          {createError && (
            <Alert variant="destructive"><AlertDescription>{createError}</AlertDescription></Alert>
          )}
          <form onSubmit={handleCreateSubmit} className="space-y-4">
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Batch Details</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Batch Name *</Label>
                  <Input placeholder="e.g., Batch A - Rhode Island Reds" value={createForm.batchName} onChange={(e) => setCreateForm({ ...createForm, batchName: e.target.value })} required disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Batch Code *</Label>
                  <Input placeholder="e.g., B-001" value={createForm.batchCode} onChange={(e) => setCreateForm({ ...createForm, batchCode: e.target.value })} required disabled={createLoading} />
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
                  <Input type="number" min="1" placeholder="e.g., 100" value={createForm.numberOfBirds} onChange={(e) => setCreateForm({ ...createForm, numberOfBirds: parseInt(e.target.value) || 0 })} required disabled={createLoading} />
                </div>
              </div>
            </div>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button type="submit" disabled={createLoading}>
                {createLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating...</> : <><Bird className="w-4 h-4 mr-2" />Create Flock Batch</>}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit Flock Batch Dialog */}
      <Dialog open={isEditDialogOpen} onOpenChange={setIsEditDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Pencil className="w-5 h-5 text-blue-600" /> Edit Flock Batch
            </DialogTitle>
            <DialogDescription>Update the flock batch information below</DialogDescription>
          </DialogHeader>
          {editError && (
            <Alert variant="destructive"><AlertDescription>{editError}</AlertDescription></Alert>
          )}
          {editFetching ? (
            <div className="py-8 text-center">
              <Loader2 className="w-8 h-8 animate-spin mx-auto mb-2 text-blue-600" />
              <p className="text-slate-600">Loading flock batch...</p>
            </div>
          ) : (
            <form onSubmit={handleEditSubmit} className="space-y-4">
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Batch Details</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Batch Name *</Label>
                    <Input placeholder="e.g., Batch A - Rhode Island Reds" value={editForm.batchName} onChange={(e) => setEditForm({ ...editForm, batchName: e.target.value })} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Batch Code *</Label>
                    <Input placeholder="e.g., B-001" value={editForm.batchCode} onChange={(e) => setEditForm({ ...editForm, batchCode: e.target.value })} required disabled={editLoading} />
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
                    <Input type="number" min="1" placeholder="e.g., 100" value={editForm.numberOfBirds} onChange={(e) => setEditForm({ ...editForm, numberOfBirds: parseInt(e.target.value) || 0 })} required disabled={editLoading} />
                  </div>
                </div>
              </div>
              <div className="flex gap-3 justify-end pt-2">
                <Button type="button" onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                <Button type="submit" disabled={editLoading}>
                  {editLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : <><Save className="w-4 h-4 mr-2" />Update Flock Batch</>}
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
            <AlertDialogTitle>Delete Flock Batch</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this flock batch? This action cannot be undone.
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

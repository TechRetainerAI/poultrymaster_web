"use client"

import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Plus, Edit, Trash2, ShoppingBag, Search, RefreshCw, ArrowUpDown, ArrowUp, ArrowDown, Loader2, Filter, ChevronDown, ChevronUp } from "lucide-react"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { getSupplies, createSupply, updateSupply, deleteSupply, type SupplyInput, type Supply } from "@/lib/api/supply"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"

type SupplyItem = Supply
type SupplyFormData = {
  name: string
  type: string
  quantity: number
  unit: string
  cost: number
  supplier: string
  purchaseDate: string
  notes: string
}

const EMPTY_FORM_DATA: SupplyFormData = {
  name: "",
  type: "",
  quantity: 0,
  unit: "",
  cost: 0,
  supplier: "",
  purchaseDate: "",
  notes: "",
}

export default function SuppliesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const isMobile = useIsMobile()
  const [supplies, setSupplies] = useState<SupplyItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<SupplyItem | null>(null)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingItem, setDeletingItem] = useState<SupplyItem | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)

  // Filters
  const [search, setSearch] = useState("")
  const [selectedType, setSelectedType] = useState<string>("ALL")
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const [filtersOpen, setFiltersOpen] = useState(false)

  // Sorting
  const [sortField, setSortField] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<"asc" | "desc">("asc")

  // Form state
  const [formData, setFormData] = useState<SupplyFormData>(EMPTY_FORM_DATA)

  const supplyTypes = ["Feed", "Medication", "Equipment", "Tools", "Cleaning Supplies", "Other"]

  useEffect(() => {
    loadData()
    
    // Check for global search query from header
    if (typeof window !== 'undefined') {
      const globalSearch = sessionStorage.getItem('globalSearchQuery')
      if (globalSearch) {
        setSearch(globalSearch)
        sessionStorage.removeItem('globalSearchQuery')
      }
      
      // Listen for global search events from header
      const handleGlobalSearch = (e: CustomEvent) => {
        setSearch(e.detail.query)
      }
      
      window.addEventListener('globalSearch', handleGlobalSearch as EventListener)
      return () => {
        window.removeEventListener('globalSearch', handleGlobalSearch as EventListener)
      }
    }
  }, [])

  const loadData = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }

    try {
      const res = await getSupplies(userId, farmId)
      if (res.success && res.data) {
        setSupplies(res.data)
      } else {
        setError(res.message || "Failed to load supplies")
      }
    } catch (err) {
      console.error("[v0] Failed to load supplies:", err)
      setError("Failed to load supplies")
    } finally {
      setLoading(false)
    }
  }

  const handleSort = (field: string) => {
    if (sortField === field) {
      setSortDirection(sortDirection === "asc" ? "desc" : "asc")
    } else {
      setSortField(field)
      setSortDirection("asc")
    }
  }

  const filteredItems = useMemo(() => {
    let list = supplies

    if (search) {
      const q = search.toLowerCase()
      list = list.filter(item => 
        item.name.toLowerCase().includes(q) ||
        item.type.toLowerCase().includes(q) ||
        item.supplier?.toLowerCase().includes(q)
      )
    }

    if (selectedType !== "ALL") {
      list = list.filter(item => item.type === selectedType)
    }

    if (sortField) {
      list = [...list].sort((a, b) => {
        let aVal: any = a[sortField as keyof SupplyItem]
        let bVal: any = b[sortField as keyof SupplyItem]
        
        if (typeof aVal === 'string') aVal = aVal.toLowerCase()
        if (typeof bVal === 'string') bVal = bVal.toLowerCase()
        
        if (aVal < bVal) return sortDirection === "asc" ? -1 : 1
        if (aVal > bVal) return sortDirection === "asc" ? 1 : -1
        return 0
      })
    }

    return list
  }, [supplies, search, selectedType, sortField, sortDirection])

  const handleCreate = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    if (!formData.name.trim() || !formData.type.trim() || !formData.unit.trim() || !Number.isFinite(formData.quantity) || formData.quantity <= 0) {
      toast({
        title: "Required fields missing",
        description: "Item name, type, quantity (> 0), and unit are required before saving supply.",
        variant: "destructive",
      })
      return
    }

    const input: SupplyInput = {
      userId,
      farmId,
      name: formData.name,
      type: formData.type,
      quantity: formData.quantity,
      unit: formData.unit,
      cost: formData.cost,
      supplier: formData.supplier.trim() ? formData.supplier : null,
      purchaseDate: formData.purchaseDate.trim() ? formData.purchaseDate : null,
      notes: formData.notes.trim() ? formData.notes : null,
    }

    try {
      const res = await createSupply(input)
      if (!res.success) {
        setError(res.message || "Failed to create supply")
        return
      }
      setIsCreateDialogOpen(false)
      resetForm()
      loadData()
    } catch (err) {
      console.error("[v0] Failed to create supply:", err)
      setError("Failed to create supply")
    }
  }

  const handleUpdate = async () => {
    if (!editingItem || !editingItem.id) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    if (!formData.name.trim() || !formData.type.trim() || !formData.unit.trim() || !Number.isFinite(formData.quantity) || formData.quantity <= 0) {
      toast({
        title: "Required fields missing",
        description: "Item name, type, quantity (> 0), and unit are required before saving supply.",
        variant: "destructive",
      })
      return
    }

    const input: SupplyInput = {
      userId,
      farmId,
      name: formData.name,
      type: formData.type,
      quantity: formData.quantity,
      unit: formData.unit,
      cost: formData.cost,
      supplier: formData.supplier.trim() ? formData.supplier : null,
      purchaseDate: formData.purchaseDate.trim() ? formData.purchaseDate : null,
      notes: formData.notes.trim() ? formData.notes : null,
    }

    try {
      const res = await updateSupply(editingItem.id, input)
      if (!res.success) {
        setError(res.message || "Failed to update supply")
        return
      }
      setIsEditDialogOpen(false)
      setEditingItem(null)
      resetForm()
      loadData()
    } catch (err) {
      console.error("[v0] Failed to update supply:", err)
      setError("Failed to update supply")
    }
  }

  const openDeleteDialog = (item: SupplyItem) => {
    setDeletingItem(item)
    setDeleteDialogOpen(true)
  }

  const handleDelete = async () => {
    if (!deletingItem?.id) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Error", description: "Farm ID or User ID not found.", variant: "destructive" })
      return
    }
    setIsDeleting(true)
    try {
      const res = await deleteSupply(deletingItem.id, userId, farmId)
      if (res.success) {
        toast({ title: "Supply deleted", description: `"${deletingItem.name}" has been successfully deleted.` })
        loadData()
      } else {
        toast({ title: "Delete failed", description: res.message || "Failed to delete supply.", variant: "destructive" })
      }
    } catch (err) {
      console.error("[v0] Failed to delete supply:", err)
      toast({ title: "Delete failed", description: "Failed to delete supply.", variant: "destructive" })
    }
    setIsDeleting(false)
    setDeleteDialogOpen(false)
    setDeletingItem(null)
  }

  const resetForm = () => {
    setFormData(EMPTY_FORM_DATA)
  }

  const openEditDialog = (item: SupplyItem) => {
    setEditingItem(item)
    setFormData({
      name: item.name,
      type: item.type,
      quantity: item.quantity,
      unit: item.unit,
      cost: item.cost,
      supplier: item.supplier ?? "",
      purchaseDate: item.purchaseDate ?? "",
      notes: item.notes ?? "",
    })
    setIsEditDialogOpen(true)
  }

  const clearFilters = () => {
    setSearch("")
    setSelectedType("ALL")
  }

  const totalCost = useMemo(() => {
    return filteredItems.reduce((sum, item) => sum + item.cost, 0)
  }, [filteredItems])

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

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-purple-100 rounded-lg flex items-center justify-center">
                  <ShoppingBag className="w-5 h-5 text-purple-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Supplies</h1>
                  <p className="text-sm text-slate-600">Track and manage farm supplies</p>
                </div>
              </div>
              <Dialog
                open={isCreateDialogOpen}
                onOpenChange={(open) => {
                  setIsCreateDialogOpen(open)
                  if (!open) resetForm()
                }}
              >
                <DialogTrigger asChild>
                  <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700 shrink-0">
                    <Plus className="w-4 h-4" />
                    Add Supply
                  </Button>
                </DialogTrigger>
                <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
                  <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                      <div className="w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center">
                        <ShoppingBag className="w-4 h-4 text-purple-600" />
                      </div>
                      Add Supply Item
                    </DialogTitle>
                    <DialogDescription>
                      Add a new supply item to your inventory
                    </DialogDescription>
                  </DialogHeader>
                  <div className="space-y-4">
                    {/* Item Details Section */}
                    <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                      <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Item Details</div>
                      <div className="p-4 space-y-4">
                        <div className="grid grid-cols-2 gap-4">
                          <div className="space-y-2">
                            <Label htmlFor="name" className="text-xs font-medium text-slate-600">Item Name *</Label>
                            <Input
                              id="name"
                              value={formData.name}
                              onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                              className="bg-white"
                              required
                            />
                          </div>
                          <div className="space-y-2">
                            <Label htmlFor="type" className="text-xs font-medium text-slate-600">Type *</Label>
                            <Select
                              value={formData.type}
                              onValueChange={(value) => setFormData(prev => ({ ...prev, type: value }))}
                            >
                              <SelectTrigger className="bg-white">
                                <SelectValue placeholder="Select type" />
                              </SelectTrigger>
                              <SelectContent>
                                {supplyTypes.map(type => (
                                  <SelectItem key={type} value={type}>{type}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Quantity & Cost Section */}
                    <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                      <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Quantity & Cost</div>
                      <div className="p-4 space-y-4">
                        <div className="grid grid-cols-3 gap-4">
                          <div className="space-y-2">
                            <Label htmlFor="quantity" className="text-xs font-medium text-slate-600">Quantity *</Label>
                            <Input
                              id="quantity"
                              type="number"
                              min="0"
                              value={formData.quantity}
                              onChange={(e) => setFormData(prev => ({ ...prev, quantity: parseFloat(e.target.value) || 0 }))}
                              className="bg-white"
                              required
                            />
                          </div>
                          <div className="space-y-2">
                            <Label htmlFor="unit" className="text-xs font-medium text-slate-600">Unit *</Label>
                            <Input
                              id="unit"
                              placeholder="e.g., kg, L, pcs"
                              value={formData.unit}
                              onChange={(e) => setFormData(prev => ({ ...prev, unit: e.target.value }))}
                              className="bg-white"
                              required
                            />
                          </div>
                          <div className="space-y-2">
                            <Label htmlFor="cost" className="text-xs font-medium text-slate-600">Cost</Label>
                            <Input
                              id="cost"
                              type="number"
                              min="0"
                              step="0.01"
                              value={formData.cost}
                              onChange={(e) => setFormData(prev => ({ ...prev, cost: parseFloat(e.target.value) || 0 }))}
                              className="bg-white"
                            />
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Supplier & Date Section */}
                    <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                      <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Supplier & Date</div>
                      <div className="p-4 space-y-4">
                        <div className="grid grid-cols-2 gap-4">
                          <div className="space-y-2">
                            <Label htmlFor="supplier" className="text-xs font-medium text-slate-600">Supplier</Label>
                            <Input
                              id="supplier"
                              value={formData.supplier}
                              onChange={(e) => setFormData(prev => ({ ...prev, supplier: e.target.value }))}
                              className="bg-white"
                            />
                          </div>
                          <div className="space-y-2">
                            <Label htmlFor="purchaseDate" className="text-xs font-medium text-slate-600">Purchase Date</Label>
                            <Input
                              id="purchaseDate"
                              type="date"
                              value={formData.purchaseDate}
                              onChange={(e) => setFormData(prev => ({ ...prev, purchaseDate: e.target.value }))}
                              className="bg-white"
                            />
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Notes Section */}
                    <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                      <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Notes</div>
                      <div className="p-4">
                        <Textarea
                          id="notes"
                          value={formData.notes}
                          onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
                          className="bg-white"
                          placeholder="Add any additional notes..."
                        />
                      </div>
                    </div>
                  </div>
                  <div className="flex justify-end gap-3 pt-2">
                    <Button onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                      Cancel
                    </Button>
                    <Button onClick={handleCreate} className="bg-indigo-600 hover:bg-indigo-700">
                      <Plus className="w-4 h-4 mr-2" />
                      Add Supply
                    </Button>
                  </div>
                </DialogContent>
              </Dialog>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Filters */}
            {isMobile ? (
              <div className="space-y-3">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search supplies..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-10 h-11" />
                </div>
                <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                  <SheetTrigger asChild>
                    <Button variant="outline" className="w-full h-11 gap-2 justify-start">
                      <Filter className="h-4 w-4" />
                      Filters
                      {(!!search || selectedType !== "ALL") && (
                        <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-amber-500 text-white text-xs flex items-center justify-center">
                          {[search, selectedType !== "ALL"].filter(Boolean).length}
                        </span>
                      )}
                    </Button>
                  </SheetTrigger>
                  <SheetContent side="bottom" className="h-[75vh] rounded-t-2xl">
                    <SheetHeader>
                      <SheetTitle>Filters</SheetTitle>
                    </SheetHeader>
                    <div className="space-y-4 overflow-y-auto pb-8">
                      <div>
                        <label className="text-sm font-medium text-slate-700 mb-1 block">Type</label>
                        <Select value={selectedType} onValueChange={setSelectedType}>
                          <SelectTrigger><SelectValue placeholder="Type" /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="ALL">All Types</SelectItem>
                            {supplyTypes.map(type => <SelectItem key={type} value={type}>{type}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="flex gap-2 pt-4">
                        <Button variant="outline" className="flex-1" onClick={clearFilters}>Clear all</Button>
                        <Button className="flex-1" onClick={() => setFiltersOpen(false)}>Apply</Button>
                      </div>
                    </div>
                  </SheetContent>
                </Sheet>
              </div>
            ) : (
            <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded border">
              <div className="relative w-full sm:w-[240px]">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
              </div>
              <Select value={selectedType} onValueChange={setSelectedType}>
                <SelectTrigger className="w-[180px]"><SelectValue placeholder="Type" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All Types</SelectItem>
                  {supplyTypes.map(type => <SelectItem key={type} value={type}>{type}</SelectItem>)}
                </SelectContent>
              </Select>
              <div className="ml-auto">
                <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
              </div>
            </div>
            )}

            {/* Summary Cards */}
            <div className={cn("grid gap-4", isMobile ? "grid-cols-2" : "grid-cols-1 md:grid-cols-3")}>
              <Card>
                <CardHeader className="pb-2">
                  <CardDescription>Total Items</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">{filteredItems.length}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="pb-2">
                  <CardDescription>Total Quantity</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">
                    {filteredItems.reduce((sum, item) => sum + item.quantity, 0).toLocaleString()}
                  </div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="pb-2">
                  <CardDescription>Total Cost</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">
                    ${totalCost.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Table */}
            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <p className="text-slate-600">Loading supplies...</p>
                </CardContent>
              </Card>
            ) : filteredItems.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <ShoppingBag className="w-12 h-12 text-slate-400 mx-auto mb-4" />
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No supply items found</h3>
                  <p className="text-slate-600 mb-6">Get started by adding your first supply item</p>
                  <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={() => setIsCreateDialogOpen(true)}>
                    <Plus className="w-4 h-4" />
                    Add Supply
                  </Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardHeader>
                  <CardTitle>Supply Items</CardTitle>
                  <CardDescription>Manage your farm supplies</CardDescription>
                </CardHeader>
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {filteredItems.map((item, idx) => (
                        <Collapsible key={item.id} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="font-semibold text-slate-900">{item.name}</div>
                                  <div className="mt-1 flex items-baseline gap-3">
                                    <span className="text-lg font-bold text-purple-600">{item.quantity.toLocaleString()} {item.unit}</span>
                                    <Badge variant="outline">{item.type}</Badge>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Cost</span> <span className="font-medium">${item.cost.toFixed(2)}</span></div>
                                  <div><span className="text-slate-500">Supplier</span> <span className="font-medium">{item.supplier || "—"}</span></div>
                                  <div><span className="text-slate-500">Purchase</span> <span className="font-medium">{item.purchaseDate ? formatDateShort(item.purchaseDate) : "—"}</span></div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(item)}>
                                    <Edit className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteDialog(item)}>
                                    <Trash2 className="h-4 w-4 mr-2" /> Delete
                                  </Button>
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                      ))}
                      {filteredItems.length > 0 && (
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
                  <Table className="min-w-[600px]">
                    <TableHeader>
                      <TableRow>
                        <TableHead 
                          className={cn("cursor-pointer hover:bg-slate-50", isMobile && "sticky-col-date bg-slate-50")}
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
                        <TableHead 
                          className="cursor-pointer hover:bg-slate-50"
                          onClick={() => handleSort("type")}
                        >
                          <div className="flex items-center gap-2">
                            Type
                            {sortField === "type" ? (
                              sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                            ) : (
                              <ArrowUpDown className="h-4 w-4 text-slate-400" />
                            )}
                          </div>
                        </TableHead>
                        <TableHead>Quantity</TableHead>
                        <TableHead>Cost</TableHead>
                        <TableHead>Supplier</TableHead>
                        <TableHead>Purchase Date</TableHead>
                        <TableHead className={cn("text-right min-w-[100px]", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filteredItems.map((item) => (
                        <TableRow key={item.id}>
                          <TableCell className={cn("font-medium bg-white", isMobile && "sticky-col-date")}>{item.name}</TableCell>
                          <TableCell>
                            <Badge variant="outline">{item.type}</Badge>
                          </TableCell>
                          <TableCell>{item.quantity.toLocaleString()} {item.unit}</TableCell>
                          <TableCell>${item.cost.toFixed(2)}</TableCell>
                          <TableCell>{item.supplier || "-"}</TableCell>
                          <TableCell>{item.purchaseDate ? (isMobile ? formatDateShort(item.purchaseDate) : new Date(item.purchaseDate).toLocaleDateString()) : "-"}</TableCell>
                          <TableCell className={cn("text-right bg-white", isMobile && "sticky-col-actions")}>
                            <div className="flex items-center justify-end gap-2">
                              <Button variant="ghost" size="sm" onClick={() => openEditDialog(item)}>
                                <Edit className="h-4 w-4" />
                              </Button>
                              <Button variant="ghost" size="sm" className="text-red-600" onClick={() => openDeleteDialog(item)}>
                                <Trash2 className="h-4 w-4" />
                              </Button>
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

            {/* Edit Dialog - Similar structure to create dialog */}
            <Dialog
              open={isEditDialogOpen}
              onOpenChange={(open) => {
                setIsEditDialogOpen(open)
                if (!open) {
                  setEditingItem(null)
                  resetForm()
                }
              }}
            >
              <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <div className="w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center">
                      <Edit className="w-4 h-4 text-purple-600" />
                    </div>
                    Edit Supply Item
                  </DialogTitle>
                  <DialogDescription>
                    Update the supply item information
                  </DialogDescription>
                </DialogHeader>
                <div className="space-y-4">
                  {/* Item Details Section */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Item Details</div>
                    <div className="p-4 space-y-4">
                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="edit-name" className="text-xs font-medium text-slate-600">Item Name *</Label>
                          <Input
                            id="edit-name"
                            value={formData.name}
                            onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                            className="bg-white"
                            required
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-type" className="text-xs font-medium text-slate-600">Type *</Label>
                          <Select
                            value={formData.type}
                            onValueChange={(value) => setFormData(prev => ({ ...prev, type: value }))}
                          >
                            <SelectTrigger className="bg-white">
                              <SelectValue placeholder="Select type" />
                            </SelectTrigger>
                            <SelectContent>
                              {supplyTypes.map(type => (
                                <SelectItem key={type} value={type}>{type}</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Quantity & Cost Section */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Quantity & Cost</div>
                    <div className="p-4 space-y-4">
                      <div className="grid grid-cols-3 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="edit-quantity" className="text-xs font-medium text-slate-600">Quantity *</Label>
                          <Input
                            id="edit-quantity"
                            type="number"
                            min="0"
                            value={formData.quantity}
                            onChange={(e) => setFormData(prev => ({ ...prev, quantity: parseFloat(e.target.value) || 0 }))}
                            className="bg-white"
                            required
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-unit" className="text-xs font-medium text-slate-600">Unit *</Label>
                          <Input
                            id="edit-unit"
                            placeholder="e.g., kg, L, pcs"
                            value={formData.unit}
                            onChange={(e) => setFormData(prev => ({ ...prev, unit: e.target.value }))}
                            className="bg-white"
                            required
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-cost" className="text-xs font-medium text-slate-600">Cost</Label>
                          <Input
                            id="edit-cost"
                            type="number"
                            min="0"
                            step="0.01"
                            value={formData.cost}
                            onChange={(e) => setFormData(prev => ({ ...prev, cost: parseFloat(e.target.value) || 0 }))}
                            className="bg-white"
                          />
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Supplier & Date Section */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Supplier & Date</div>
                    <div className="p-4 space-y-4">
                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="edit-supplier" className="text-xs font-medium text-slate-600">Supplier</Label>
                          <Input
                            id="edit-supplier"
                            value={formData.supplier}
                            onChange={(e) => setFormData(prev => ({ ...prev, supplier: e.target.value }))}
                            className="bg-white"
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-purchaseDate" className="text-xs font-medium text-slate-600">Purchase Date</Label>
                          <Input
                            id="edit-purchaseDate"
                            type="date"
                            value={formData.purchaseDate}
                            onChange={(e) => setFormData(prev => ({ ...prev, purchaseDate: e.target.value }))}
                            className="bg-white"
                          />
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Notes Section */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Notes</div>
                    <div className="p-4">
                      <Textarea
                        id="edit-notes"
                        value={formData.notes}
                        onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
                        className="bg-white"
                        placeholder="Add any additional notes..."
                      />
                    </div>
                  </div>
                </div>
                <div className="flex justify-end gap-3 pt-2">
                  <Button onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                    Cancel
                  </Button>
                  <Button onClick={handleUpdate} className="bg-indigo-600 hover:bg-indigo-700">
                    <Edit className="w-4 h-4 mr-2" />
                    Update Supply
                  </Button>
                </div>
              </DialogContent>
            </Dialog>
          </div>
        </main>
      </div>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Supply</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete &quot;{deletingItem?.name}&quot;? This action cannot be undone.
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

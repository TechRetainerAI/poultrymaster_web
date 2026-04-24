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
import { Plus, Edit, Trash2, Package, Search, RefreshCw, ArrowUpDown, ArrowUp, ArrowDown, Filter, ChevronDown, ChevronUp } from "lucide-react"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { getSupplies, createSupply, updateSupply, deleteSupply, type SupplyInput } from "@/lib/api/supply"
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
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"
import { toastFormGuide } from "@/lib/utils/validation-toast"

interface InventoryItem {
  id?: number
  name: string
  category: string
  quantity: number
  unit: string
  unitPrice: number
  supplier?: string
  location?: string
  expiryDate?: string
  entryDate?: string
  notes?: string
  // For eggs: crates and loose eggs
  crates?: number
  looseEggs?: number
}

export default function InventoryPage() {
  const router = useRouter()
  const { toast } = useToast()
  const [inventory, setInventory] = useState<InventoryItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<InventoryItem | null>(null)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingItem, setDeletingItem] = useState<InventoryItem | null>(null)

  // Filters
  const [search, setSearch] = useState("")
  const [selectedCategory, setSelectedCategory] = useState<string>("ALL")
  const [entryDateFrom, setEntryDateFrom] = useState("")
  const [expiryDateFrom, setExpiryDateFrom] = useState("")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()

  const [draftCategory, setDraftCategory] = useState<string>("ALL")
  const [draftEntryDateFrom, setDraftEntryDateFrom] = useState("")
  const [draftExpiryDateFrom, setDraftExpiryDateFrom] = useState("")
  const hasDraftChanges =
    draftCategory !== selectedCategory ||
    draftEntryDateFrom !== entryDateFrom ||
    draftExpiryDateFrom !== expiryDateFrom

  // Sorting
  const [sortField, setSortField] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<"asc" | "desc">("asc")

  // Form state
  const [formData, setFormData] = useState<InventoryItem>({
    name: "",
    category: "",
    quantity: 0,
    unit: "",
    unitPrice: 0,
    supplier: "",
    location: "",
    expiryDate: "",
    entryDate: new Date().toISOString().split('T')[0],
    notes: "",
    crates: 0,
    looseEggs: 0,
  })

  // Check if current item is eggs (for crates input)
  const isEggsCategory = formData.category === "Eggs" || formData.name.toLowerCase().includes("egg")

  const categories = ["Feed", "Medication", "Equipment", "Supplies", "Eggs", "Other"]

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

  const mapSupplyToInventory = (item: any): InventoryItem => ({
    id: item.id,
    name: item.name ?? "",
    category: item.type ?? "",
    quantity: Number(item.quantity ?? 0),
    unit: item.unit ?? "",
    unitPrice: Number(item.cost ?? 0),
    supplier: item.supplier ?? "",
    location: "",
    expiryDate: "",
    entryDate: item.purchaseDate ?? "",
    notes: item.notes ?? "",
    crates: 0,
    looseEggs: 0,
  })

  const loadData = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }

    try {
      setError("")
      const res = await getSupplies(userId, farmId)
      if (res.success && res.data) {
        setInventory(res.data.map(mapSupplyToInventory))
      } else {
        setError(res.message || "Failed to load inventory")
      }
    } catch (err) {
      setError("Failed to load inventory")
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
    let list = inventory

    if (search) {
      const q = search.toLowerCase()
      list = list.filter(item => 
        item.name.toLowerCase().includes(q) ||
        item.category.toLowerCase().includes(q) ||
        item.supplier?.toLowerCase().includes(q) ||
        item.location?.toLowerCase().includes(q)
      )
    }

    if (selectedCategory !== "ALL") {
      list = list.filter(item => item.category === selectedCategory)
    }

    if (entryDateFrom) {
      list = list.filter(item => item.entryDate && item.entryDate >= entryDateFrom)
    }
    if (expiryDateFrom) {
      list = list.filter(item => item.expiryDate && item.expiryDate >= expiryDateFrom)
    }

    // Apply sorting
    if (sortField) {
      list = [...list].sort((a, b) => {
        let aVal: any = a[sortField as keyof InventoryItem]
        let bVal: any = b[sortField as keyof InventoryItem]
        
        if (typeof aVal === 'string') aVal = aVal.toLowerCase()
        if (typeof bVal === 'string') bVal = bVal.toLowerCase()
        
        if (aVal < bVal) return sortDirection === "asc" ? -1 : 1
        if (aVal > bVal) return sortDirection === "asc" ? 1 : -1
        return 0
      })
    }

    return list
  }, [inventory, search, selectedCategory, entryDateFrom, expiryDateFrom, sortField, sortDirection])

  const handleCreate = async () => {
    if (!formData.name.trim() || !formData.category.trim() || !formData.unit.trim() || !formData.entryDate || !Number.isFinite(formData.quantity) || formData.quantity <= 0) {
      toastFormGuide(
        toast,
        "Add item name, category, unit, entry date, and a quantity greater than zero — then you can save.",
      )
      return
    }

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }

    const input: SupplyInput = {
      userId,
      farmId,
      name: formData.name,
      type: formData.category,
      quantity: formData.quantity,
      unit: formData.unit,
      cost: Number(formData.unitPrice || 0),
      supplier: formData.supplier || null,
      purchaseDate: formData.entryDate || null,
      notes: formData.notes || null,
    }

    const res = await createSupply(input)
    if (!res.success) {
      toast({ title: "Create failed", description: res.message || "Failed to create inventory item.", variant: "destructive" })
      return
    }

    setIsCreateDialogOpen(false)
    resetForm()
    loadData()
  }

  const handleUpdate = async () => {
    if (!editingItem?.id) return
    if (!formData.name.trim() || !formData.category.trim() || !formData.unit.trim() || !formData.entryDate || !Number.isFinite(formData.quantity) || formData.quantity <= 0) {
      toastFormGuide(
        toast,
        "Add item name, category, unit, entry date, and a quantity greater than zero — then you can save.",
      )
      return
    }

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }

    const input: SupplyInput = {
      userId,
      farmId,
      name: formData.name,
      type: formData.category,
      quantity: formData.quantity,
      unit: formData.unit,
      cost: Number(formData.unitPrice || 0),
      supplier: formData.supplier || null,
      purchaseDate: formData.entryDate || null,
      notes: formData.notes || null,
    }

    const res = await updateSupply(editingItem.id, input)
    if (!res.success) {
      toast({ title: "Update failed", description: res.message || "Failed to update inventory item.", variant: "destructive" })
      return
    }

    setIsEditDialogOpen(false)
    setEditingItem(null)
    resetForm()
    loadData()
  }

  const openDeleteDialog = (item: InventoryItem) => {
    setDeletingItem(item)
    setDeleteDialogOpen(true)
  }

  const handleDelete = async () => {
    if (!deletingItem?.id) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }
    const res = await deleteSupply(deletingItem.id, userId, farmId)
    if (!res.success) {
      toast({ title: "Delete failed", description: res.message || "Failed to delete inventory item.", variant: "destructive" })
      return
    }
    toast({ title: "Item deleted", description: `"${deletingItem.name}" has been removed from inventory.` })
    setDeleteDialogOpen(false)
    setDeletingItem(null)
    loadData()
  }

  const resetForm = () => {
    setFormData({
      name: "",
      category: "",
      quantity: 0,
      unit: "",
      unitPrice: 0,
      supplier: "",
      location: "",
      expiryDate: "",
      entryDate: new Date().toISOString().split('T')[0],
      notes: "",
      crates: 0,
      looseEggs: 0,
    })
  }

  const openEditDialog = (item: InventoryItem) => {
    setEditingItem(item)
    setFormData(item)
    setIsEditDialogOpen(true)
  }

  const clearFilters = () => {
    setSearch("")
    setSelectedCategory("ALL")
    setEntryDateFrom("")
    setExpiryDateFrom("")
    setDraftCategory("ALL")
    setDraftEntryDateFrom("")
    setDraftExpiryDateFrom("")
  }

  const syncDraftFromCommitted = () => {
    setDraftCategory(selectedCategory)
    setDraftEntryDateFrom(entryDateFrom)
    setDraftExpiryDateFrom(expiryDateFrom)
  }

  const applyMobileFilters = () => {
    setSelectedCategory(draftCategory)
    setEntryDateFrom(draftEntryDateFrom)
    setExpiryDateFrom(draftExpiryDateFrom)
    setFiltersOpen(false)
    toast({ title: "Filters applied", description: "Inventory list updated." })
  }

  const totalValue = useMemo(() => {
    return filteredItems.reduce((sum, item) => sum + (item.quantity * item.unitPrice), 0)
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
                <div className="w-10 h-10 shrink-0 bg-blue-100 rounded-lg flex items-center justify-center">
                  <Package className="w-5 h-5 text-blue-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Inventory</h1>
                  <p className="text-sm text-slate-600">Manage your farm inventory and supplies</p>
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
                    Add Item
                  </Button>
                </DialogTrigger>
                <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
                  <DialogHeader>
                    <DialogTitle>Add Inventory Item</DialogTitle>
                    <DialogDescription>
                      Add a new item to your inventory
                    </DialogDescription>
                  </DialogHeader>
                  <div className="space-y-4 py-2">
                    {/* Section: Item Details */}
                    <div className="rounded-xl border border-slate-200 overflow-hidden">
                      <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Item Details</div>
                      <div className="grid grid-cols-2 gap-4 p-4 bg-white">
                        <div className="space-y-2">
                          <Label htmlFor="name" className="text-sm font-medium text-slate-700">Item Name *</Label>
                          <Input id="name" value={formData.name} onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))} required />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="category" className="text-sm font-medium text-slate-700">Category *</Label>
                          <Select value={formData.category} onValueChange={(value) => setFormData(prev => ({ ...prev, category: value }))}>
                            <SelectTrigger><SelectValue placeholder="Select category" /></SelectTrigger>
                            <SelectContent>{categories.map(cat => (<SelectItem key={cat} value={cat}>{cat}</SelectItem>))}</SelectContent>
                          </Select>
                        </div>
                      </div>
                    </div>

                    {/* Section: Egg Quantity (conditional) */}
                    {isEggsCategory && (
                      <div className="rounded-xl border border-amber-200 overflow-hidden">
                        <div className="bg-amber-500 px-4 py-2 text-sm font-semibold text-white">Egg Quantity (Crates × 30 + Loose Eggs)</div>
                        <div className="grid grid-cols-3 gap-4 p-4 bg-amber-50">
                          <div className="space-y-2">
                            <Label htmlFor="crates" className="text-sm">Crates (30 eggs)</Label>
                            <Input id="crates" type="number" min="0" value={formData.crates || 0} onChange={(e) => { const crates = parseInt(e.target.value) || 0; const loose = formData.looseEggs || 0; const total = (crates * 30) + loose; setFormData(prev => ({ ...prev, crates, quantity: total, unit: "eggs" })) }} />
                          </div>
                          <div className="space-y-2">
                            <Label htmlFor="looseEggs" className="text-sm">Loose Eggs</Label>
                            <Input id="looseEggs" type="number" min="0" max="29" value={formData.looseEggs || 0} onChange={(e) => { const loose = parseInt(e.target.value) || 0; const crates = formData.crates || 0; const total = (crates * 30) + loose; setFormData(prev => ({ ...prev, looseEggs: loose, quantity: total, unit: "eggs" })) }} />
                          </div>
                          <div className="space-y-2">
                            <Label className="text-sm">Total Eggs</Label>
                            <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-amber-700">{((formData.crates || 0) * 30 + (formData.looseEggs || 0)).toLocaleString()}</div>
                          </div>
                        </div>
                        <div className="px-4 pb-3 bg-amber-50">
                          <p className="text-xs text-amber-600">Calculation: {formData.crates || 0} crates × 30 + {formData.looseEggs || 0} loose = {((formData.crates || 0) * 30 + (formData.looseEggs || 0)).toLocaleString()} eggs</p>
                        </div>
                      </div>
                    )}

                    {/* Section: Quantity & Pricing */}
                    <div className="rounded-xl border border-slate-200 overflow-hidden">
                      <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Quantity &amp; Pricing</div>
                      <div className="grid grid-cols-3 gap-4 p-4 bg-white">
                        <div className="space-y-2">
                          <Label htmlFor="quantity" className="text-sm font-medium text-slate-700">Quantity *</Label>
                          <Input id="quantity" type="number" min="0" value={formData.quantity} onChange={(e) => setFormData(prev => ({ ...prev, quantity: parseFloat(e.target.value) || 0 }))} required disabled={isEggsCategory} className={isEggsCategory ? "bg-slate-50" : ""} />
                          {isEggsCategory && <p className="text-xs text-slate-500">Auto-calculated from crates + eggs above</p>}
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="unit" className="text-sm font-medium text-slate-700">Unit *</Label>
                          <Input id="unit" placeholder="e.g., kg, L, pcs" value={formData.unit} onChange={(e) => setFormData(prev => ({ ...prev, unit: e.target.value }))} required disabled={isEggsCategory} className={isEggsCategory ? "bg-slate-50" : ""} />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="unitPrice" className="text-sm font-medium text-slate-700">Unit Price</Label>
                          <Input id="unitPrice" type="number" min="0" step="0.01" value={formData.unitPrice} onChange={(e) => setFormData(prev => ({ ...prev, unitPrice: parseFloat(e.target.value) || 0 }))} />
                        </div>
                      </div>
                    </div>

                    {/* Section: Additional Info */}
                    <div className="rounded-xl border border-slate-200 overflow-hidden">
                      <div className="bg-slate-600 px-4 py-2 text-sm font-semibold text-white">Additional Information</div>
                      <div className="space-y-4 p-4 bg-white">
                        <div className="grid grid-cols-2 gap-4">
                          <div className="space-y-2">
                            <Label htmlFor="supplier" className="text-sm font-medium text-slate-700">Supplier</Label>
                            <Input id="supplier" value={formData.supplier} onChange={(e) => setFormData(prev => ({ ...prev, supplier: e.target.value }))} />
                          </div>
                          <div className="space-y-2">
                            <Label htmlFor="location" className="text-sm font-medium text-slate-700">Location</Label>
                            <Input id="location" value={formData.location} onChange={(e) => setFormData(prev => ({ ...prev, location: e.target.value }))} />
                          </div>
                        </div>
                        <div className="grid grid-cols-2 gap-4">
                          <div className="space-y-2">
                            <Label htmlFor="entryDate" className="text-sm font-medium text-slate-700">Entry Date *</Label>
                            <Input id="entryDate" type="date" value={formData.entryDate || new Date().toISOString().split('T')[0]} onChange={(e) => setFormData(prev => ({ ...prev, entryDate: e.target.value }))} required />
                          </div>
                          <div className="space-y-2">
                            <Label htmlFor="expiryDate" className="text-sm font-medium text-slate-700">Expiry Date</Label>
                            <Input id="expiryDate" type="date" value={formData.expiryDate} onChange={(e) => setFormData(prev => ({ ...prev, expiryDate: e.target.value }))} />
                          </div>
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="notes" className="text-sm font-medium text-slate-700">Notes</Label>
                          <Textarea id="notes" value={formData.notes} onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))} />
                        </div>
                      </div>
                    </div>
                  </div>
                  <div className="flex justify-end space-x-2 pt-2">
                    <Button onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                    <Button onClick={handleCreate}>Add Item</Button>
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
              <div className="space-y-3 w-full min-w-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search inventory..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-10 h-11" />
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
                        {(!!search || selectedCategory !== "ALL" || !!entryDateFrom || !!expiryDateFrom) && (
                          <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-orange-500 text-white text-xs flex items-center justify-center">
                            {[search, selectedCategory !== "ALL", entryDateFrom, expiryDateFrom].filter(Boolean).length}
                          </span>
                        )}
                      </Button>
                    </SheetTrigger>
                    <SheetContent side="bottom" className={MOBILE_FILTER_SHEET_CONTENT_CLASS}>
                      <MobileFilterSheetHeader />
                      <MobileFilterSheetBody>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Category</label>
                          <Select value={draftCategory} onValueChange={setDraftCategory}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="Category" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All Categories</SelectItem>
                              {categories.map((cat) => (
                                <SelectItem key={cat} value={cat}>
                                  {cat}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-3">
                          <p className="text-sm font-medium text-slate-700">Dates</p>
                          <div className="flex flex-col gap-4">
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="inv-entry-from" className="text-xs font-medium text-slate-500">
                                Entry date from
                              </label>
                              <Input
                                id="inv-entry-from"
                                type="date"
                                value={draftEntryDateFrom}
                                onChange={(e) => setDraftEntryDateFrom(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="inv-expiry-from" className="text-xs font-medium text-slate-500">
                                Expiry date from
                              </label>
                              <Input
                                id="inv-expiry-from"
                                type="date"
                                value={draftExpiryDateFrom}
                                onChange={(e) => setDraftExpiryDateFrom(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
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
                <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
              </div>
              <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                <SelectTrigger className="w-[180px]"><SelectValue placeholder="Category" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All Categories</SelectItem>
                  {categories.map(cat => <SelectItem key={cat} value={cat}>{cat}</SelectItem>)}
                </SelectContent>
              </Select>
              <Input type="date" placeholder="Entry date from" value={entryDateFrom} onChange={(e) => setEntryDateFrom(e.target.value)} className="w-[160px]" />
              <Input type="date" placeholder="Expiry date from" value={expiryDateFrom} onChange={(e) => setExpiryDateFrom(e.target.value)} className="w-[160px]" />
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
                  <CardDescription>Total Value</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">
                    ${totalValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Table */}
            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <p className="text-slate-600">Loading inventory...</p>
                </CardContent>
              </Card>
            ) : filteredItems.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <Package className="w-12 h-12 text-slate-400 mx-auto mb-4" />
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No inventory items found</h3>
                  <p className="text-slate-600 mb-6">Get started by adding your first inventory item</p>
                  <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={() => setIsCreateDialogOpen(true)}>
                    <Plus className="w-4 h-4" />
                    Add Item
                  </Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardHeader>
                  <CardTitle>Inventory Items</CardTitle>
                  <CardDescription>Manage your farm inventory</CardDescription>
                </CardHeader>
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {filteredItems.map((item, idx) => (
                        <Collapsible key={item.id ?? `inv-${idx}`} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="font-semibold text-slate-900">{item.name}</div>
                                  <div className="mt-1 flex items-baseline gap-3">
                                    <span className="text-lg font-bold text-blue-600">{item.quantity.toLocaleString()} {item.unit}</span>
                                    <Badge variant="outline">{item.category}</Badge>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Unit price</span> <span className="font-medium">${item.unitPrice.toFixed(2)}</span></div>
                                  <div><span className="text-slate-500">Value</span> <span className="font-medium">${(item.quantity * item.unitPrice).toFixed(2)}</span></div>
                                  <div><span className="text-slate-500">Supplier</span> <span className="font-medium">{item.supplier || "—"}</span></div>
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
                  <Table className={cn("w-full", !isMobile && "min-w-[800px]")}>
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
                          onClick={() => handleSort("category")}
                        >
                          <div className="flex items-center gap-2">
                            Category
                            {sortField === "category" ? (
                              sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                            ) : (
                              <ArrowUpDown className="h-4 w-4 text-slate-400" />
                            )}
                          </div>
                        </TableHead>
                        <TableHead>Quantity</TableHead>
                        <TableHead>Unit Price</TableHead>
                        <TableHead>Total Value</TableHead>
                        <TableHead>Entry Date</TableHead>
                        <TableHead>Supplier</TableHead>
                        <TableHead>Location</TableHead>
                        <TableHead className={cn("text-right min-w-[100px] whitespace-nowrap", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filteredItems.map((item) => (
                        <TableRow key={item.id}>
                          <TableCell className={cn("font-medium bg-white", isMobile && "sticky-col-date")}>{item.name}</TableCell>
                          <TableCell>
                            <Badge variant="outline">{item.category}</Badge>
                          </TableCell>
                          <TableCell>{item.quantity.toLocaleString()} {item.unit}</TableCell>
                          <TableCell>${item.unitPrice.toFixed(2)}</TableCell>
                          <TableCell>${(item.quantity * item.unitPrice).toFixed(2)}</TableCell>
                          <TableCell>{item.entryDate ? (isMobile ? formatDateShort(item.entryDate) : new Date(item.entryDate).toLocaleDateString()) : "-"}</TableCell>
                          <TableCell>{item.supplier || "-"}</TableCell>
                          <TableCell>{item.location || "-"}</TableCell>
                          <TableCell className={cn("text-right whitespace-nowrap bg-white", isMobile && "sticky-col-actions")}>
                            <div className="flex items-center justify-end gap-2 min-w-[80px]">
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

            {/* Edit Dialog */}
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
                  <DialogTitle>Edit Inventory Item</DialogTitle>
                  <DialogDescription>
                    Update the inventory item information
                  </DialogDescription>
                </DialogHeader>
                <div className="space-y-4 py-2">
                  {/* Section: Item Details */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden">
                    <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Item Details</div>
                    <div className="grid grid-cols-2 gap-4 p-4 bg-white">
                      <div className="space-y-2">
                        <Label htmlFor="edit-name" className="text-sm font-medium text-slate-700">Item Name *</Label>
                        <Input id="edit-name" value={formData.name} onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))} required />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-category" className="text-sm font-medium text-slate-700">Category *</Label>
                        <Select value={formData.category} onValueChange={(value) => setFormData(prev => ({ ...prev, category: value }))}>
                          <SelectTrigger><SelectValue placeholder="Select category" /></SelectTrigger>
                          <SelectContent>{categories.map(cat => (<SelectItem key={cat} value={cat}>{cat}</SelectItem>))}</SelectContent>
                        </Select>
                      </div>
                    </div>
                  </div>

                  {/* Section: Egg Quantity (conditional) */}
                  {isEggsCategory && (
                    <div className="rounded-xl border border-amber-200 overflow-hidden">
                      <div className="bg-amber-500 px-4 py-2 text-sm font-semibold text-white">Egg Quantity (Crates × 30 + Loose Eggs)</div>
                      <div className="grid grid-cols-3 gap-4 p-4 bg-amber-50">
                        <div className="space-y-2">
                          <Label htmlFor="edit-crates" className="text-sm">Crates (30 eggs)</Label>
                          <Input id="edit-crates" type="number" min="0" value={formData.crates || 0} onChange={(e) => { const crates = parseInt(e.target.value) || 0; const loose = formData.looseEggs || 0; const total = (crates * 30) + loose; setFormData(prev => ({ ...prev, crates, quantity: total, unit: "eggs" })) }} />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-looseEggs" className="text-sm">Loose Eggs</Label>
                          <Input id="edit-looseEggs" type="number" min="0" max="29" value={formData.looseEggs || 0} onChange={(e) => { const loose = parseInt(e.target.value) || 0; const crates = formData.crates || 0; const total = (crates * 30) + loose; setFormData(prev => ({ ...prev, looseEggs: loose, quantity: total, unit: "eggs" })) }} />
                        </div>
                        <div className="space-y-2">
                          <Label className="text-sm">Total Eggs</Label>
                          <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-amber-700">{((formData.crates || 0) * 30 + (formData.looseEggs || 0)).toLocaleString()}</div>
                        </div>
                      </div>
                      <div className="px-4 pb-3 bg-amber-50">
                        <p className="text-xs text-amber-600">Calculation: {formData.crates || 0} crates × 30 + {formData.looseEggs || 0} loose = {((formData.crates || 0) * 30 + (formData.looseEggs || 0)).toLocaleString()} eggs</p>
                      </div>
                    </div>
                  )}

                  {/* Section: Quantity & Pricing */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden">
                    <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Quantity &amp; Pricing</div>
                    <div className="grid grid-cols-3 gap-4 p-4 bg-white">
                      <div className="space-y-2">
                        <Label htmlFor="edit-quantity" className="text-sm font-medium text-slate-700">Quantity *</Label>
                        <Input id="edit-quantity" type="number" min="0" value={formData.quantity} onChange={(e) => setFormData(prev => ({ ...prev, quantity: parseFloat(e.target.value) || 0 }))} required disabled={isEggsCategory} className={isEggsCategory ? "bg-slate-50" : ""} />
                        {isEggsCategory && <p className="text-xs text-slate-500">Auto-calculated from crates + eggs</p>}
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-unit" className="text-sm font-medium text-slate-700">Unit *</Label>
                        <Input id="edit-unit" placeholder="e.g., kg, L, pcs" value={formData.unit} onChange={(e) => setFormData(prev => ({ ...prev, unit: e.target.value }))} required disabled={isEggsCategory} className={isEggsCategory ? "bg-slate-50" : ""} />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-unitPrice" className="text-sm font-medium text-slate-700">Unit Price</Label>
                        <Input id="edit-unitPrice" type="number" min="0" step="0.01" value={formData.unitPrice} onChange={(e) => setFormData(prev => ({ ...prev, unitPrice: parseFloat(e.target.value) || 0 }))} />
                      </div>
                    </div>
                  </div>

                  {/* Section: Additional Info */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden">
                    <div className="bg-slate-600 px-4 py-2 text-sm font-semibold text-white">Additional Information</div>
                    <div className="space-y-4 p-4 bg-white">
                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="edit-supplier" className="text-sm font-medium text-slate-700">Supplier</Label>
                          <Input id="edit-supplier" value={formData.supplier} onChange={(e) => setFormData(prev => ({ ...prev, supplier: e.target.value }))} />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-location" className="text-sm font-medium text-slate-700">Location</Label>
                          <Input id="edit-location" value={formData.location} onChange={(e) => setFormData(prev => ({ ...prev, location: e.target.value }))} />
                        </div>
                      </div>
                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="edit-entryDate" className="text-sm font-medium text-slate-700">Entry Date *</Label>
                          <Input id="edit-entryDate" type="date" value={formData.entryDate || new Date().toISOString().split('T')[0]} onChange={(e) => setFormData(prev => ({ ...prev, entryDate: e.target.value }))} required />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-expiryDate" className="text-sm font-medium text-slate-700">Expiry Date</Label>
                          <Input id="edit-expiryDate" type="date" value={formData.expiryDate} onChange={(e) => setFormData(prev => ({ ...prev, expiryDate: e.target.value }))} />
                        </div>
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-notes" className="text-sm font-medium text-slate-700">Notes</Label>
                        <Textarea id="edit-notes" value={formData.notes} onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))} />
                      </div>
                    </div>
                  </div>
                </div>
                <div className="flex justify-end space-x-2 pt-2">
                  <Button onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                  <Button onClick={handleUpdate}>Update Item</Button>
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
            <AlertDialogTitle>Delete Inventory Item</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete &quot;{deletingItem?.name}&quot;? This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

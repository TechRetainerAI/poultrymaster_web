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
import { Plus, Edit, Trash2, Heart, Droplet, Pill, Search, RefreshCw, Calendar as CalendarIcon, ArrowUpDown, ArrowUp, ArrowDown, Building2, Package, Loader2, Filter, ChevronDown, ChevronUp } from "lucide-react"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getHouses, type House } from "@/lib/api/house"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { getHealthRecords, createHealthRecord, updateHealthRecord, deleteHealthRecord, type HealthRecord, type HealthRecordInput } from "@/lib/api/health"
import { format } from "date-fns"
import { formatDateShort, cn } from "@/lib/utils"
import { Calendar } from "@/components/ui/calendar"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"

type HealthType = "flock" | "house" | "inventory"

export default function HealthPage() {
  const router = useRouter()
  const { toast } = useToast()
  const [activeTab, setActiveTab] = useState<HealthType>("flock")
  const [healthRecords, setHealthRecords] = useState<HealthRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [houses, setHouses] = useState<House[]>([])
  const [inventoryItems, setInventoryItems] = useState<any[]>([])
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editingRecord, setEditingRecord] = useState<HealthRecord | null>(null)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingRecord, setDeletingRecord] = useState<HealthRecord | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)

  // Filters
  const [search, setSearch] = useState("")
  const [selectedFlockId, setSelectedFlockId] = useState<string>("ALL")
  const [selectedHouseId, setSelectedHouseId] = useState<string>("ALL")
  const [selectedItemId, setSelectedItemId] = useState<string>("ALL")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()

  // Sorting
  const [sortField, setSortField] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<"asc" | "desc">("asc")

  // Form state
  const [formData, setFormData] = useState<Partial<HealthRecordInput>>({
    flockId: null,
    houseId: null,
    itemId: null,
    recordDate: new Date().toISOString().split('T')[0],
    vaccination: "",
    medication: "",
    waterConsumption: undefined,
    notes: "",
  })
  const healthRecordTypes = ["Vaccination", "Medication", "Treatment", "Illness", "Mortality"] as const
  const [recordType, setRecordType] = useState<(typeof healthRecordTypes)[number]>("Vaccination")

  const withTypePrefix = (type: string, notes?: string | null) => {
    const cleanNotes = (notes || "").replace(/^\[Type:[^\]]+\]\s*/i, "").trim()
    return `[Type:${type}]${cleanNotes ? ` ${cleanNotes}` : ""}`
  }

  const parseTypeFromNotes = (notes?: string | null): (typeof healthRecordTypes)[number] => {
    const match = (notes || "").match(/^\[Type:([^\]]+)\]/i)
    if (!match) return "Vaccination"
    const found = healthRecordTypes.find((t) => t.toLowerCase() === match[1].trim().toLowerCase())
    return found || "Vaccination"
  }

  const stripTypePrefix = (notes?: string | null) => (notes || "").replace(/^\[Type:[^\]]+\]\s*/i, "")

  useEffect(() => {
    loadData()
  }, [])

  const loadData = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }

    try {
      const [flocksRes, housesRes, healthRes] = await Promise.all([
        getFlocks(userId, farmId),
        getHouses(userId, farmId),
        getHealthRecords(userId, farmId),
      ])

      if (flocksRes.success && flocksRes.data) {
        setFlocks(flocksRes.data)
      }

      if (housesRes.success && housesRes.data) {
        setHouses(housesRes.data)
      }

      // Load inventory items from localStorage (since there's no API yet)
      try {
        const stored = localStorage.getItem("inventory_items")
        if (stored) {
          setInventoryItems(JSON.parse(stored))
        }
      } catch (e) {
        console.warn("Failed to load inventory items from localStorage")
      }

      if (healthRes.success && healthRes.data) {
        setHealthRecords(healthRes.data.map((hr: any) => ({
          id: hr.id || hr.Id,
          flockId: hr.flockId || hr.FlockId,
          houseId: hr.houseId || hr.HouseId,
          itemId: hr.itemId || hr.ItemId,
          recordDate: hr.recordDate || hr.RecordDate || hr.date || hr.Date,
          vaccination: hr.vaccination || hr.Vaccination,
          medication: hr.medication || hr.Medication,
          waterConsumption: hr.waterConsumption || hr.WaterConsumption,
          notes: hr.notes || hr.Notes,
        })))
      }
    } catch (err) {
      console.error("Failed to load health records:", err)
      setError("Failed to load health records")
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

  const filteredRecords = useMemo(() => {
    let list = healthRecords

    // Filter by active tab type
    if (activeTab === "flock") {
      list = list.filter(r => r.flockId != null && r.houseId == null && r.itemId == null)
    } else if (activeTab === "house") {
      list = list.filter(r => r.houseId != null && r.flockId == null && r.itemId == null)
    } else if (activeTab === "inventory") {
      list = list.filter(r => r.itemId != null && r.flockId == null && r.houseId == null)
    }

    if (search) {
      const q = search.toLowerCase()
      list = list.filter(r => 
        r.vaccination?.toLowerCase().includes(q) ||
        r.medication?.toLowerCase().includes(q) ||
        r.notes?.toLowerCase().includes(q)
      )
    }

    if (activeTab === "flock" && selectedFlockId !== "ALL") {
      list = list.filter(r => r.flockId === parseInt(selectedFlockId))
    }

    if (activeTab === "house" && selectedHouseId !== "ALL") {
      list = list.filter(r => r.houseId === parseInt(selectedHouseId))
    }

    if (activeTab === "inventory" && selectedItemId !== "ALL") {
      list = list.filter(r => r.itemId === parseInt(selectedItemId))
    }

    if (dateFrom) {
      list = list.filter(r => {
        const recordDate = r.recordDate?.split('T')[0] || ""
        return recordDate >= dateFrom
      })
    }

    if (dateTo) {
      list = list.filter(r => {
        const recordDate = r.recordDate?.split('T')[0] || ""
        return recordDate <= dateTo
      })
    }

    // Apply sorting
    if (sortField) {
      list = [...list].sort((a, b) => {
        let aVal: any
        let bVal: any
        
        switch (sortField) {
          case "date":
            aVal = a.recordDate ? new Date(a.recordDate).getTime() : 0
            bVal = b.recordDate ? new Date(b.recordDate).getTime() : 0
            break
          case "flock":
            aVal = a.flockId || 0
            bVal = b.flockId || 0
            break
          case "house":
            aVal = a.houseId || 0
            bVal = b.houseId || 0
            break
          case "item":
            aVal = a.itemId || 0
            bVal = b.itemId || 0
            break
          default:
            return 0
        }
        
        if (aVal < bVal) return sortDirection === "asc" ? -1 : 1
        if (aVal > bVal) return sortDirection === "asc" ? 1 : -1
        return 0
      })
    }

    return list
  }, [healthRecords, activeTab, search, selectedFlockId, selectedHouseId, selectedItemId, dateFrom, dateTo, sortField, sortDirection])

  const handleCreate = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    const hasTarget = activeTab === "flock" ? !!formData.flockId : activeTab === "house" ? !!formData.houseId : !!formData.itemId
    if (!hasTarget || !formData.recordDate) {
      toast({
        title: "Required fields missing",
        description: "Please select a flock/house/item and provide a record date before saving.",
        variant: "destructive",
      })
      return
    }

    try {
      const input: HealthRecordInput = {
        userId,
        farmId,
        flockId: activeTab === "flock" ? (formData.flockId || null) : null,
        houseId: activeTab === "house" ? (formData.houseId || null) : null,
        itemId: activeTab === "inventory" ? (formData.itemId || null) : null,
        recordDate: formData.recordDate || new Date().toISOString().split('T')[0],
        vaccination: formData.vaccination || null,
        medication: formData.medication || null,
        waterConsumption: formData.waterConsumption || null,
        notes: withTypePrefix(recordType, formData.notes) || null,
      }

      const res = await createHealthRecord(input)
      if (res.success) {
        setIsCreateDialogOpen(false)
        resetForm()
        loadData()
      } else {
        setError(res.message || "Failed to create health record")
      }
    } catch (err) {
      console.error("Create error:", err)
      setError("Failed to create health record")
    }
  }

  const handleUpdate = async () => {
    if (!editingRecord || !editingRecord.id) return

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    const hasTarget = activeTab === "flock" ? !!formData.flockId : activeTab === "house" ? !!formData.houseId : !!formData.itemId
    if (!hasTarget || !formData.recordDate) {
      toast({
        title: "Required fields missing",
        description: "Please select a flock/house/item and provide a record date before saving.",
        variant: "destructive",
      })
      return
    }

    try {
      const input: HealthRecordInput = {
        userId,
        farmId,
        flockId: activeTab === "flock" ? (formData.flockId || null) : null,
        houseId: activeTab === "house" ? (formData.houseId || null) : null,
        itemId: activeTab === "inventory" ? (formData.itemId || null) : null,
        recordDate: formData.recordDate || new Date().toISOString().split('T')[0],
        vaccination: formData.vaccination || null,
        medication: formData.medication || null,
        waterConsumption: formData.waterConsumption || null,
        notes: withTypePrefix(recordType, formData.notes) || null,
      }

      const res = await updateHealthRecord(editingRecord.id, input)
      if (res.success) {
        setIsEditDialogOpen(false)
        setEditingRecord(null)
        resetForm()
        loadData()
      } else {
        setError(res.message || "Failed to update health record")
      }
    } catch (err) {
      console.error("Update error:", err)
      setError("Failed to update health record")
    }
  }

  const openDeleteDialog = (record: HealthRecord) => {
    setDeletingRecord(record)
    setDeleteDialogOpen(true)
  }

  const handleDelete = async () => {
    if (!deletingRecord?.id) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Error", description: "Farm ID or User ID not found.", variant: "destructive" })
      return
    }
    setIsDeleting(true)
    try {
      const res = await deleteHealthRecord(deletingRecord.id, userId, farmId)
      if (res.success) {
        toast({ title: "Record deleted", description: "The health record has been successfully deleted." })
        loadData()
      } else {
        toast({ title: "Delete failed", description: res.message || "Failed to delete health record.", variant: "destructive" })
      }
    } catch (err) {
      console.error("Delete error:", err)
      toast({ title: "Delete failed", description: "Failed to delete health record.", variant: "destructive" })
    }
    setIsDeleting(false)
    setDeleteDialogOpen(false)
    setDeletingRecord(null)
  }

  const resetForm = () => {
    setRecordType("Vaccination")
    setFormData({
      flockId: null,
      houseId: null,
      itemId: null,
      recordDate: new Date().toISOString().split('T')[0],
      vaccination: "",
      medication: "",
      waterConsumption: undefined,
      notes: "",
    })
  }

  const openEditDialog = (record: HealthRecord) => {
    setEditingRecord(record)
    const recordDate = record.recordDate || ""
    setRecordType(parseTypeFromNotes(record.notes))
    setFormData({
      flockId: record.flockId || null,
      houseId: record.houseId || null,
      itemId: record.itemId || null,
      recordDate: recordDate ? recordDate.split('T')[0] : new Date().toISOString().split('T')[0],
      vaccination: record.vaccination || "",
      medication: record.medication || "",
      waterConsumption: record.waterConsumption || undefined,
      notes: stripTypePrefix(record.notes) || "",
    })
    setIsEditDialogOpen(true)
  }

  const clearFilters = () => {
    setSearch("")
    setSelectedFlockId("ALL")
    setSelectedHouseId("ALL")
    setSelectedItemId("ALL")
    setDateFrom("")
    setDateTo("")
  }

  const getFlockName = (flockId: number | null | undefined) => {
    if (!flockId) return "-"
    const flock = flocks.find(f => f.flockId === flockId)
    return flock?.name || `Flock ${flockId}`
  }

  const getHouseName = (houseId: number | null | undefined) => {
    if (!houseId) return "-"
    const house = houses.find(h => h.houseId === houseId)
    return house?.name || `House ${houseId}`
  }

  const getItemName = (itemId: number | null | undefined) => {
    if (!itemId) return "-"
    const item = inventoryItems.find(i => i.id === itemId)
    return item?.name || `Item ${itemId}`
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
                <div className="w-10 h-10 shrink-0 bg-red-100 rounded-lg flex items-center justify-center">
                  <Heart className="w-5 h-5 text-red-600" />
                </div>
                <div className="min-w-0">
                  <h1 className={cn("font-bold text-slate-900", isMobile ? "text-xl" : "text-2xl")}>Health Records</h1>
                  <p className="text-sm text-slate-600">Track vaccinations, medications, and water consumption</p>
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
                    Add Health Record
                  </Button>
                </DialogTrigger>
                <DialogContent className="max-w-4xl w-[95vw] sm:max-w-[900px] max-h-[90vh] flex flex-col">
                  <DialogHeader>
                    <DialogTitle>Create Health Record</DialogTitle>
                    <DialogDescription>
                      Record daily health information for your {activeTab === "flock" ? "flocks" : activeTab === "house" ? "houses" : "inventory items"}
                    </DialogDescription>
                  </DialogHeader>
                  <div className="space-y-5 py-4 overflow-y-auto pr-1">
                    <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                      <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Record Details</div>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4">
                        {activeTab === "flock" && (
                          <div className="space-y-2">
                            <Label htmlFor="flockId">Flock *</Label>
                            <Select
                              value={formData.flockId ? formData.flockId.toString() : ""}
                              onValueChange={(value) => setFormData(prev => ({ ...prev, flockId: parseInt(value), houseId: null, itemId: null }))}
                            >
                              <SelectTrigger>
                                <SelectValue placeholder="Select flock" />
                              </SelectTrigger>
                              <SelectContent>
                                {flocks.map(flock => (
                                  <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                                    {flock.name}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        )}
                        {activeTab === "house" && (
                          <div className="space-y-2">
                            <Label htmlFor="houseId">House *</Label>
                            <Select
                              value={formData.houseId ? formData.houseId.toString() : ""}
                              onValueChange={(value) => setFormData(prev => ({ ...prev, houseId: parseInt(value), flockId: null, itemId: null }))}
                            >
                              <SelectTrigger>
                                <SelectValue placeholder="Select house" />
                              </SelectTrigger>
                              <SelectContent>
                                {houses.map(house => (
                                  <SelectItem key={house.houseId} value={house.houseId.toString()}>
                                    {house.name}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        )}
                        {activeTab === "inventory" && (
                          <div className="space-y-2">
                            <Label htmlFor="itemId">Inventory Item *</Label>
                            <Select
                              value={formData.itemId ? formData.itemId.toString() : ""}
                              onValueChange={(value) => setFormData(prev => ({ ...prev, itemId: parseInt(value), flockId: null, houseId: null }))}
                            >
                              <SelectTrigger>
                                <SelectValue placeholder="Select item" />
                              </SelectTrigger>
                              <SelectContent>
                                {inventoryItems.map(item => (
                                  <SelectItem key={item.id} value={item.id.toString()}>
                                    {item.name}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        )}
                        <div className="space-y-2">
                          <Label htmlFor="date">Date *</Label>
                          <Input
                            id="date"
                            type="date"
                            value={formData.recordDate || ""}
                            onChange={(e) => setFormData(prev => ({ ...prev, recordDate: e.target.value }))}
                            required
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="type">Type *</Label>
                          <Select value={recordType} onValueChange={(value) => setRecordType(value as (typeof healthRecordTypes)[number])}>
                            <SelectTrigger id="type">
                              <SelectValue placeholder="Select type" />
                            </SelectTrigger>
                            <SelectContent>
                              {healthRecordTypes.map((type) => (
                                <SelectItem key={type} value={type}>{type}</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      </div>
                    </div>

                    <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                      <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Treatment Details</div>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4">
                        <div className="space-y-2">
                          <Label htmlFor="vaccination">Name</Label>
                          <Input
                            id="vaccination"
                            placeholder="Medication/vaccine name"
                            value={formData.vaccination || ""}
                            onChange={(e) => setFormData(prev => ({ ...prev, vaccination: e.target.value }))}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="medication">Treatment</Label>
                          <Input
                            id="medication"
                            placeholder="Disease or condition treated"
                            value={formData.medication || ""}
                            onChange={(e) => setFormData(prev => ({ ...prev, medication: e.target.value }))}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="waterConsumption">Dosage</Label>
                          <Input
                            id="waterConsumption"
                            type="number"
                            step="0.1"
                            min="0"
                            placeholder="e.g., 1ml per bird"
                            value={formData.waterConsumption || ""}
                            onChange={(e) => setFormData(prev => ({ ...prev, waterConsumption: e.target.value ? parseFloat(e.target.value) : undefined }))}
                          />
                        </div>
                      </div>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="notes">Notes</Label>
                      <Textarea
                        id="notes"
                        placeholder="Additional notes about health status"
                        value={formData.notes || ""}
                        onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
                      />
                    </div>
                  </div>
                  <div className="flex justify-end space-x-2 pt-2 border-t">
                    <Button onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                      Cancel
                    </Button>
                    <Button onClick={handleCreate}>Create Record</Button>
                  </div>
                </DialogContent>
              </Dialog>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Tabs */}
            <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as HealthType)}>
              <TabsList className={cn("w-full", isMobile && "grid h-auto grid-cols-3 gap-1")}>
                <TabsTrigger value="flock" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <Heart className={cn("w-4 h-4", isMobile && "mr-1", !isMobile && "mr-2")} />
                  {isMobile ? "Flock" : "Flock Health"}
                </TabsTrigger>
                <TabsTrigger value="house" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <Building2 className={cn("w-4 h-4", isMobile && "mr-1", !isMobile && "mr-2")} />
                  {isMobile ? "House" : "House Health"}
                </TabsTrigger>
                <TabsTrigger value="inventory" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <Package className={cn("w-4 h-4", isMobile && "mr-1", !isMobile && "mr-2")} />
                  {isMobile ? "Inventory" : "Inventory Health"}
                </TabsTrigger>
              </TabsList>

              <TabsContent value="flock" className="space-y-4">
                {/* Filters */}
                <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded border">
                  {isMobile ? (
                    <>
                      <div className="relative flex-1 min-w-0">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                        <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                      </div>
                      <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                        <SheetTrigger asChild>
                          <Button variant="outline" size="sm" className="gap-2 shrink-0">
                            <Filter className="h-4 w-4" /> Filters
                          </Button>
                        </SheetTrigger>
                        <SheetContent side="bottom" className="rounded-t-2xl max-h-[85vh]">
                          <SheetHeader>
                            <SheetTitle>Filters</SheetTitle>
                          </SheetHeader>
                          <div className="space-y-4 pt-4">
                            <div className="space-y-2">
                              <Label>Flock</Label>
                              <Select value={selectedFlockId} onValueChange={setSelectedFlockId}>
                                <SelectTrigger><SelectValue placeholder="Flock" /></SelectTrigger>
                                <SelectContent>
                                  <SelectItem value="ALL">All Flocks</SelectItem>
                                  {flocks.map(f => <SelectItem key={f.flockId} value={f.flockId.toString()}>{f.name}</SelectItem>)}
                                </SelectContent>
                              </Select>
                            </div>
                            <div className="grid grid-cols-2 gap-3">
                              <div className="space-y-2">
                                <Label>Date From</Label>
                                <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                              </div>
                              <div className="space-y-2">
                                <Label>Date To</Label>
                                <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                              </div>
                            </div>
                            <div className="flex gap-2 pt-2">
                              <Button variant="outline" className="flex-1" onClick={clearFilters}>Clear</Button>
                              <Button className="flex-1" onClick={() => setFiltersOpen(false)}>Apply</Button>
                            </div>
                          </div>
                        </SheetContent>
                      </Sheet>
                    </>
                  ) : (
                    <>
                      <div className="relative w-[240px]">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                        <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                      </div>
                      <Select value={selectedFlockId} onValueChange={setSelectedFlockId}>
                        <SelectTrigger className="w-[180px]"><SelectValue placeholder="Flock" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All Flocks</SelectItem>
                          {flocks.map(f => <SelectItem key={f.flockId} value={f.flockId.toString()}>{f.name}</SelectItem>)}
                        </SelectContent>
                      </Select>
                      <Input type="date" placeholder="From" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" />
                      <Input type="date" placeholder="To" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" />
                      <div className="ml-auto">
                        <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                      </div>
                    </>
                  )}
                </div>
              </TabsContent>

              <TabsContent value="house" className="space-y-4">
                {/* Filters */}
                <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded border">
                  {isMobile ? (
                    <>
                      <div className="relative flex-1 min-w-0">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                        <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                      </div>
                      <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                        <SheetTrigger asChild>
                          <Button variant="outline" size="sm" className="gap-2 shrink-0"><Filter className="h-4 w-4" /> Filters</Button>
                        </SheetTrigger>
                        <SheetContent side="bottom" className="rounded-t-2xl max-h-[85vh]">
                          <SheetHeader><SheetTitle>Filters</SheetTitle></SheetHeader>
                          <div className="space-y-4 pt-4">
                            <div className="space-y-2">
                              <Label>House</Label>
                              <Select value={selectedHouseId} onValueChange={setSelectedHouseId}>
                                <SelectTrigger><SelectValue placeholder="House" /></SelectTrigger>
                                <SelectContent>
                                  <SelectItem value="ALL">All Houses</SelectItem>
                                  {houses.map(h => <SelectItem key={h.houseId} value={h.houseId.toString()}>{h.name}</SelectItem>)}
                                </SelectContent>
                              </Select>
                            </div>
                            <div className="grid grid-cols-2 gap-3">
                              <div className="space-y-2"><Label>Date From</Label><Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} /></div>
                              <div className="space-y-2"><Label>Date To</Label><Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} /></div>
                            </div>
                            <div className="flex gap-2 pt-2">
                              <Button variant="outline" className="flex-1" onClick={clearFilters}>Clear</Button>
                              <Button className="flex-1" onClick={() => setFiltersOpen(false)}>Apply</Button>
                            </div>
                          </div>
                        </SheetContent>
                      </Sheet>
                    </>
                  ) : (
                    <>
                      <div className="relative w-[240px]">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                        <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                      </div>
                      <Select value={selectedHouseId} onValueChange={setSelectedHouseId}>
                        <SelectTrigger className="w-[180px]"><SelectValue placeholder="House" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All Houses</SelectItem>
                          {houses.map(h => <SelectItem key={h.houseId} value={h.houseId.toString()}>{h.name}</SelectItem>)}
                        </SelectContent>
                      </Select>
                      <Input type="date" placeholder="From" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" />
                      <Input type="date" placeholder="To" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" />
                      <div className="ml-auto">
                        <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                      </div>
                    </>
                  )}
                </div>
              </TabsContent>

              <TabsContent value="inventory" className="space-y-4">
                {/* Filters */}
                <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded border">
                  {isMobile ? (
                    <>
                      <div className="relative flex-1 min-w-0">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                        <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                      </div>
                      <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                        <SheetTrigger asChild>
                          <Button variant="outline" size="sm" className="gap-2 shrink-0"><Filter className="h-4 w-4" /> Filters</Button>
                        </SheetTrigger>
                        <SheetContent side="bottom" className="rounded-t-2xl max-h-[85vh]">
                          <SheetHeader><SheetTitle>Filters</SheetTitle></SheetHeader>
                          <div className="space-y-4 pt-4">
                            <div className="space-y-2">
                              <Label>Item</Label>
                              <Select value={selectedItemId} onValueChange={setSelectedItemId}>
                                <SelectTrigger><SelectValue placeholder="Item" /></SelectTrigger>
                                <SelectContent>
                                  <SelectItem value="ALL">All Items</SelectItem>
                                  {inventoryItems.map(item => <SelectItem key={item.id} value={item.id.toString()}>{item.name}</SelectItem>)}
                                </SelectContent>
                              </Select>
                            </div>
                            <div className="grid grid-cols-2 gap-3">
                              <div className="space-y-2"><Label>Date From</Label><Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} /></div>
                              <div className="space-y-2"><Label>Date To</Label><Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} /></div>
                            </div>
                            <div className="flex gap-2 pt-2">
                              <Button variant="outline" className="flex-1" onClick={clearFilters}>Clear</Button>
                              <Button className="flex-1" onClick={() => setFiltersOpen(false)}>Apply</Button>
                            </div>
                          </div>
                        </SheetContent>
                      </Sheet>
                    </>
                  ) : (
                    <>
                      <div className="relative w-[240px]">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                        <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                      </div>
                      <Select value={selectedItemId} onValueChange={setSelectedItemId}>
                        <SelectTrigger className="w-[180px]"><SelectValue placeholder="Item" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All Items</SelectItem>
                          {inventoryItems.map(item => <SelectItem key={item.id} value={item.id.toString()}>{item.name}</SelectItem>)}
                        </SelectContent>
                      </Select>
                      <Input type="date" placeholder="From" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" />
                      <Input type="date" placeholder="To" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" />
                      <div className="ml-auto">
                        <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                      </div>
                    </>
                  )}
                </div>
              </TabsContent>

            </Tabs>

            {/* Table */}
            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <p className="text-slate-600">Loading health records...</p>
                </CardContent>
              </Card>
            ) : filteredRecords.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <Heart className="w-12 h-12 text-slate-400 mx-auto mb-4" />
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No health records found</h3>
                  <p className="text-slate-600 mb-6">Get started by adding your first health record</p>
                  <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={() => setIsCreateDialogOpen(true)}>
                    <Plus className="w-4 h-4" />
                    Add Health Record
                  </Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardHeader>
                  <CardTitle>Health Records</CardTitle>
                  <CardDescription>Daily health tracking for your flocks</CardDescription>
                </CardHeader>
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {filteredRecords.map((record, idx) => (
                        <Collapsible key={record.id ?? `hr-${idx}`} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="font-semibold text-slate-900">
                                    {record.recordDate ? formatDateShort(record.recordDate) : "—"}
                                  </div>
                                  <div className="mt-1 flex flex-wrap items-baseline gap-2">
                                    {activeTab === "flock" && <Badge variant="outline">{getFlockName(record.flockId)}</Badge>}
                                    {activeTab === "house" && <Badge variant="outline">{getHouseName(record.houseId)}</Badge>}
                                    {activeTab === "inventory" && <Badge variant="outline">{getItemName(record.itemId)}</Badge>}
                                    {record.vaccination && <Badge variant="outline" className="bg-blue-50 text-blue-700"><Pill className="w-3 h-3 mr-1" />{record.vaccination}</Badge>}
                                    {record.medication && <Badge variant="outline" className="bg-green-50 text-green-700"><Heart className="w-3 h-3 mr-1" />{record.medication}</Badge>}
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  {record.waterConsumption != null && <div><span className="text-slate-500">Water</span> <span className="font-medium">{record.waterConsumption}L</span></div>}
                                  {record.notes && <div className="col-span-2"><span className="text-slate-500">Notes</span> <span className="font-medium">{record.notes.length > 60 ? record.notes.slice(0, 60) + "…" : record.notes}</span></div>}
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(record)}>
                                    <Edit className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteDialog(record)}>
                                    <Trash2 className="h-4 w-4 mr-2" /> Delete
                                  </Button>
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                      ))}
                      {filteredRecords.length > 0 && (
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
                  <Table className={cn("w-full", !isMobile && "min-w-[600px]")}>
                    <TableHeader>
                      <TableRow>
                        <TableHead 
                          className={cn("cursor-pointer hover:bg-slate-50", isMobile && "sticky-col-date bg-slate-50")}
                          onClick={() => handleSort("date")}
                        >
                          <div className="flex items-center gap-2">
                            Date
                            {sortField === "date" ? (
                              sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                            ) : (
                              <ArrowUpDown className="h-4 w-4 text-slate-400" />
                            )}
                          </div>
                        </TableHead>
                        {activeTab === "flock" && (
                          <TableHead 
                            className={cn("cursor-pointer hover:bg-slate-50", isMobile && "sticky-col-date bg-slate-50")}
                            onClick={() => handleSort("flock")}
                          >
                            <div className="flex items-center gap-2">
                              Flock
                              {sortField === "flock" ? (
                                sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                              ) : (
                                <ArrowUpDown className="h-4 w-4 text-slate-400" />
                              )}
                            </div>
                          </TableHead>
                        )}
                        {activeTab === "house" && (
                          <TableHead 
                            className={cn("cursor-pointer hover:bg-slate-50", isMobile && "sticky-col-date bg-slate-50")}
                            onClick={() => handleSort("house")}
                          >
                            <div className="flex items-center gap-2">
                              House
                              {sortField === "house" ? (
                                sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                              ) : (
                                <ArrowUpDown className="h-4 w-4 text-slate-400" />
                              )}
                            </div>
                          </TableHead>
                        )}
                        {activeTab === "inventory" && (
                          <TableHead 
                            className={cn("cursor-pointer hover:bg-slate-50", isMobile && "sticky-col-date bg-slate-50")}
                            onClick={() => handleSort("item")}
                          >
                            <div className="flex items-center gap-2">
                              Item
                              {sortField === "item" ? (
                                sortDirection === "asc" ? <ArrowUp className="h-4 w-4" /> : <ArrowDown className="h-4 w-4" />
                              ) : (
                                <ArrowUpDown className="h-4 w-4 text-slate-400" />
                              )}
                            </div>
                          </TableHead>
                        )}
                        <TableHead>Vaccination</TableHead>
                        <TableHead>Medication</TableHead>
                        <TableHead>Water (L)</TableHead>
                        <TableHead>Notes</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filteredRecords.map((record, idx) => (
                        <TableRow key={record.id || idx}>
                          <TableCell className={cn("bg-white", isMobile && "sticky-col-date")}>{record.recordDate ? (isMobile ? formatDateShort(record.recordDate) : new Date(record.recordDate).toLocaleDateString()) : "-"}</TableCell>
                          {activeTab === "flock" && <TableCell>{getFlockName(record.flockId)}</TableCell>}
                          {activeTab === "house" && <TableCell>{getHouseName(record.houseId)}</TableCell>}
                          {activeTab === "inventory" && <TableCell>{getItemName(record.itemId)}</TableCell>}
                          <TableCell>
                            {record.vaccination ? (
                              <Badge variant="outline" className="bg-blue-50 text-blue-700">
                                <Pill className="w-3 h-3 mr-1" />
                                {record.vaccination}
                              </Badge>
                            ) : (
                              <span className="text-slate-400">-</span>
                            )}
                          </TableCell>
                          <TableCell>
                            {record.medication ? (
                              <Badge variant="outline" className="bg-green-50 text-green-700">
                                <Heart className="w-3 h-3 mr-1" />
                                {record.medication}
                              </Badge>
                            ) : (
                              <span className="text-slate-400">-</span>
                            )}
                          </TableCell>
                          <TableCell>
                            {record.waterConsumption ? (
                              <div className="flex items-center gap-1">
                                <Droplet className="w-4 h-4 text-blue-500" />
                                {record.waterConsumption}L
                              </div>
                            ) : (
                              <span className="text-slate-400">-</span>
                            )}
                          </TableCell>
                          <TableCell>
                            <span className="text-sm text-slate-600">
                              {record.notes ? (record.notes.length > 50 ? record.notes.substring(0, 50) + '...' : record.notes) : '-'}
                            </span>
                          </TableCell>
                          <TableCell className={cn("text-right bg-white", isMobile && "sticky-col-actions")}>
                            <div className="flex items-center justify-end gap-2">
                              <Button variant="ghost" size="sm" onClick={() => openEditDialog(record)}>
                                <Edit className="h-4 w-4" />
                              </Button>
                              <Button variant="ghost" size="sm" className="text-red-600" onClick={() => openDeleteDialog(record)}>
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
                  setEditingRecord(null)
                  resetForm()
                }
              }}
            >
              <DialogContent className="max-w-4xl w-[95vw] sm:max-w-[900px] max-h-[90vh] flex flex-col">
                <DialogHeader>
                  <DialogTitle>Edit Health Record</DialogTitle>
                  <DialogDescription>
                    Update the health record information
                  </DialogDescription>
                </DialogHeader>
                <div className="space-y-5 py-4 overflow-y-auto pr-1">
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Record Details</div>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4">
                      {activeTab === "flock" && (
                        <div className="space-y-2">
                          <Label htmlFor="edit-flockId">Flock *</Label>
                          <Select
                            value={formData.flockId ? formData.flockId.toString() : ""}
                            onValueChange={(value) => setFormData(prev => ({ ...prev, flockId: parseInt(value), houseId: null, itemId: null }))}
                          >
                            <SelectTrigger>
                              <SelectValue placeholder="Select flock" />
                            </SelectTrigger>
                            <SelectContent>
                              {flocks.map(flock => (
                                <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                                  {flock.name}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      )}
                      {activeTab === "house" && (
                        <div className="space-y-2">
                          <Label htmlFor="edit-houseId">House *</Label>
                          <Select
                            value={formData.houseId ? formData.houseId.toString() : ""}
                            onValueChange={(value) => setFormData(prev => ({ ...prev, houseId: parseInt(value), flockId: null, itemId: null }))}
                          >
                            <SelectTrigger>
                              <SelectValue placeholder="Select house" />
                            </SelectTrigger>
                            <SelectContent>
                              {houses.map(house => (
                                <SelectItem key={house.houseId} value={house.houseId.toString()}>
                                  {house.name}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      )}
                      {activeTab === "inventory" && (
                        <div className="space-y-2">
                          <Label htmlFor="edit-itemId">Inventory Item *</Label>
                          <Select
                            value={formData.itemId ? formData.itemId.toString() : ""}
                            onValueChange={(value) => setFormData(prev => ({ ...prev, itemId: parseInt(value), flockId: null, houseId: null }))}
                          >
                            <SelectTrigger>
                              <SelectValue placeholder="Select item" />
                            </SelectTrigger>
                            <SelectContent>
                              {inventoryItems.map(item => (
                                <SelectItem key={item.id} value={item.id.toString()}>
                                  {item.name}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      )}
                      <div className="space-y-2">
                        <Label htmlFor="edit-date">Date *</Label>
                        <Input
                          id="edit-date"
                          type="date"
                          value={formData.recordDate || ""}
                          onChange={(e) => setFormData(prev => ({ ...prev, recordDate: e.target.value }))}
                          required
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-type">Type *</Label>
                        <Select value={recordType} onValueChange={(value) => setRecordType(value as (typeof healthRecordTypes)[number])}>
                          <SelectTrigger id="edit-type">
                            <SelectValue placeholder="Select type" />
                          </SelectTrigger>
                          <SelectContent>
                            {healthRecordTypes.map((type) => (
                              <SelectItem key={`edit-${type}`} value={type}>{type}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    </div>
                  </div>

                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Treatment Details</div>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4">
                      <div className="space-y-2">
                        <Label htmlFor="edit-vaccination">Name</Label>
                        <Input
                          id="edit-vaccination"
                          placeholder="Medication/vaccine name"
                          value={formData.vaccination || ""}
                          onChange={(e) => setFormData(prev => ({ ...prev, vaccination: e.target.value }))}
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-medication">Treatment</Label>
                        <Input
                          id="edit-medication"
                          placeholder="Disease or condition treated"
                          value={formData.medication || ""}
                          onChange={(e) => setFormData(prev => ({ ...prev, medication: e.target.value }))}
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-waterConsumption">Dosage</Label>
                        <Input
                          id="edit-waterConsumption"
                          type="number"
                          step="0.1"
                          min="0"
                          placeholder="e.g., 1ml per bird"
                          value={formData.waterConsumption || ""}
                          onChange={(e) => setFormData(prev => ({ ...prev, waterConsumption: e.target.value ? parseFloat(e.target.value) : undefined }))}
                        />
                      </div>
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="edit-notes">Notes</Label>
                    <Textarea
                      id="edit-notes"
                      placeholder="Additional notes about health status"
                      value={formData.notes || ""}
                      onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
                    />
                  </div>
                </div>
                <div className="flex justify-end space-x-2 pt-2 border-t">
                  <Button onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                    Cancel
                  </Button>
                  <Button onClick={handleUpdate}>Update Record</Button>
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
            <AlertDialogTitle>Delete Health Record</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this health record? This action cannot be undone.
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

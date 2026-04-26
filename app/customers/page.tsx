"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Plus, Pencil, Trash2, Mail, Phone, MapPin, Users, Search, RefreshCw, Loader2, UserPlus, ChevronDown, ChevronUp } from "lucide-react"
import { Label } from "@/components/ui/label"
import { getCustomers, getCustomer, createCustomer, updateCustomer, deleteCustomer, type Customer, type CustomerInput } from "@/lib/api/customer"
import { getUserContext } from "@/lib/utils/user-context"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { Input } from "@/components/ui/input"
import { useMemo } from "react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useIsMobile } from "@/hooks/use-mobile"
import { CollapsibleContent, CollapsibleTrigger } from "@radix-ui/react-collapsible"
import { cn } from "@/lib/utils"
import { Collapsible } from "@/components/ui/collapsible"

export default function CustomersPage() {
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage, setItemsPerPage] = useState(10)
  const [searchQuery, setSearchQuery] = useState("")
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }

  // Create dialog state
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [createLoading, setCreateLoading] = useState(false)
  const [createError, setCreateError] = useState("")
  const [createForm, setCreateForm] = useState({ name: "", contactEmail: "", contactPhone: "", address: "", city: "" })

  // Edit dialog state
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editingCustomerId, setEditingCustomerId] = useState<number | null>(null)
  const [editForm, setEditForm] = useState({ name: "", contactEmail: "", contactPhone: "", address: "", city: "" })
  const [editFetching, setEditFetching] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()

  useEffect(() => {
    loadCustomers()
    
    if (typeof window !== 'undefined') {
      const globalSearch = sessionStorage.getItem('globalSearchQuery')
      if (globalSearch) {
        setSearchQuery(globalSearch)
        sessionStorage.removeItem('globalSearchQuery')
      }
      
      const handleGlobalSearch = (e: CustomEvent) => {
        setSearchQuery(e.detail.query)
        setCurrentPage(1)
      }
      
      window.addEventListener('globalSearch', handleGlobalSearch as EventListener)
      return () => {
        window.removeEventListener('globalSearch', handleGlobalSearch as EventListener)
      }
    }
  }, [])

  const loadCustomers = async () => {
    const { userId, farmId } = getUserContext()

    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }

    const result = await getCustomers(userId, farmId)

    if (result.success && result.data) {
      setCustomers(result.data)
      setCurrentPage(1)
    } else {
      setError(result.message)
    }

    setLoading(false)
  }

  // Create handlers
  const openCreateDialog = () => {
    setCreateForm({ name: "", contactEmail: "", contactPhone: "", address: "", city: "" })
    setCreateError("")
    setIsCreateDialogOpen(true)
  }

  const handleCreateChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setCreateForm({ ...createForm, [e.target.name]: e.target.value })
  }

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setCreateLoading(true)
    setCreateError("")

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setCreateError("User context not found. Please log in again.")
      setCreateLoading(false)
      return
    }

    if (!createForm.name.trim() || !createForm.contactPhone.trim() || !createForm.city.trim() || !createForm.address.trim()) {
      const msg = "Name, phone, city, and address are required."
      setCreateError(msg)
      toastFormGuide(toast, "Add the customer name, phone, city, and address — those fields keep deliveries and invoices accurate.")
      setCreateLoading(false)
      return
    }

    const customer: CustomerInput = { farmId, userId, ...createForm }
    const result = await createCustomer(customer)

    if (result.success) {
      toast({ title: "Success!", description: "Customer created successfully." })
      setIsCreateDialogOpen(false)
      loadCustomers()
    } else {
      setCreateError(result.message)
    }
    setCreateLoading(false)
  }

  // Edit handlers
  const openEditDialog = async (customerId: number) => {
    setEditingCustomerId(customerId)
    setEditError("")
    setEditFetching(true)
    setIsEditDialogOpen(true)

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setEditError("User context not found.")
      setEditFetching(false)
      return
    }

    const result = await getCustomer(customerId, userId, farmId)
    if (result.success && result.data) {
      const c = result.data
      setEditForm({
        name: c.name || "",
        contactEmail: c.contactEmail || "",
        contactPhone: c.contactPhone || "",
        address: c.address || "",
        city: c.city || "",
      })
    } else {
      setEditError(result.message || "Failed to load customer")
    }
    setEditFetching(false)
  }

  const handleEditChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setEditForm({ ...editForm, [e.target.name]: e.target.value })
  }

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editingCustomerId) return
    setEditLoading(true)
    setEditError("")

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setEditError("User context not found.")
      setEditLoading(false)
      return
    }

    if (!editForm.name.trim() || !editForm.contactPhone.trim() || !editForm.city.trim() || !editForm.address.trim()) {
      const msg = "Name, phone, city, and address are required."
      setEditError(msg)
      toastFormGuide(toast, "Add the customer name, phone, city, and address — those fields keep deliveries and invoices accurate.")
      setEditLoading(false)
      return
    }

    const customer: CustomerInput = { farmId, userId, ...editForm }
    const result = await updateCustomer(editingCustomerId, customer)

    if (result.success) {
      toast({ title: "Success!", description: "Customer updated successfully." })
      setIsEditDialogOpen(false)
      loadCustomers()
    } else {
      setEditError(result.message)
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
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }
    setIsDeleting(true)
    const result = await deleteCustomer(deletingId, userId, farmId)
    if (result.success) {
      toast({ title: "Customer deleted", description: "The customer has been successfully deleted." })
      loadCustomers()
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
    localStorage.removeItem("roles")
    router.push("/login")
  }

  const filteredCustomers = useMemo(() => {
    if (!searchQuery.trim()) return customers
    const query = searchQuery.toLowerCase()
    return customers.filter(customer => 
      (customer.name || '').toLowerCase().includes(query) ||
      (customer.contactEmail || '').toLowerCase().includes(query) ||
      (customer.contactPhone || '').toLowerCase().includes(query) ||
      (customer.city || '').toLowerCase().includes(query) ||
      (customer.address || '').toLowerCase().includes(query)
    )
  }, [customers, searchQuery])

  const sortedCustomers = useMemo(() => sortData(filteredCustomers, sortKey, sortDir), [filteredCustomers, sortKey, sortDir])
  const totalPages = Math.ceil(sortedCustomers.length / itemsPerPage)
  const startIndex = (currentPage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const currentCustomers = sortedCustomers.slice(startIndex, endIndex)

  const clearFilters = () => { setSearchQuery(""); setCurrentPage(1) }

  const handlePageChange = (page: number) => setCurrentPage(page)
  const handlePreviousPage = () => { if (currentPage > 1) setCurrentPage(currentPage - 1) }
  const handleNextPage = () => { if (currentPage < totalPages) setCurrentPage(currentPage + 1) }

  const getPageNumbers = () => {
    const pages = []
    const maxVisiblePages = 5
    if (totalPages <= maxVisiblePages) {
      for (let i = 1; i <= totalPages; i++) pages.push(i)
    } else {
      if (currentPage <= 3) {
        for (let i = 1; i <= 4; i++) pages.push(i)
        pages.push('ellipsis'); pages.push(totalPages)
      } else if (currentPage >= totalPages - 2) {
        pages.push(1); pages.push('ellipsis')
        for (let i = totalPages - 3; i <= totalPages; i++) pages.push(i)
      } else {
        pages.push(1); pages.push('ellipsis')
        for (let i = currentPage - 1; i <= currentPage + 1; i++) pages.push(i)
        pages.push('ellipsis'); pages.push(totalPages)
      }
    }
    return pages
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
                  <Users className="w-5 h-5 text-purple-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Customers</h1>
                  <p className="text-sm text-slate-600">Manage your customer database</p>
                </div>
              </div>
              <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700 shrink-0" onClick={openCreateDialog}>
                <Plus className="w-4 h-4" />
                Add Customer
              </Button>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {!loading && customers.length > 0 && (
              <div className={isMobile ? "space-y-3" : "flex flex-wrap items-center gap-2 p-3 bg-white rounded-lg border"}>
                {isMobile ? (
                  <>
                    <div className="relative">
                      <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                      <Input 
                        placeholder="Search customers..." 
                        value={searchQuery}
                        onChange={(e) => { setSearchQuery(e.target.value); setCurrentPage(1) }}
                        className="pl-10 h-11"
                      />
                    </div>
                    {searchQuery && (
                      <Button variant="outline" className="w-full h-11" onClick={clearFilters}>
                        <RefreshCw className="h-4 w-4 mr-2" /> Clear search
                      </Button>
                    )}
                  </>
                ) : (
                  <>
                    <div className="relative flex-1 min-w-[200px]">
                      <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                      <Input placeholder="Search by name, email, phone, city, or address..." value={searchQuery} onChange={(e) => { setSearchQuery(e.target.value); setCurrentPage(1) }} className="pl-9" />
                    </div>
                    {searchQuery && (
                      <Button variant="outline" size="sm" onClick={clearFilters}>
                        <RefreshCw className="h-4 w-4 mr-2" /> Clear
                      </Button>
                    )}
                  </>
                )}
              </div>
            )}

            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <p className="text-slate-600">Loading customers...</p>
                </CardContent>
              </Card>
            ) : filteredCustomers.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4">
                    <Search className="w-8 h-8 text-slate-400" />
                  </div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No customers found</h3>
                  <p className="text-slate-600 mb-6">
                    {searchQuery ? `No customers match "${searchQuery}"` : "Get started by adding your first customer"}
                  </p>
                  {!searchQuery && (
                    <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}>
                      <Plus className="w-4 h-4" /> Add Your First Customer
                    </Button>
                  )}
                  {searchQuery && (
                    <Button className="gap-2" variant="outline" onClick={clearFilters}>
                      <RefreshCw className="w-4 h-4" /> Clear Search
                    </Button>
                  )}
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {currentCustomers.map((customer, idx) => (
                        <Collapsible key={customer.customerId} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="font-semibold text-slate-900">{customer.name}</div>
                                  <div className="mt-1 flex items-center gap-2 text-sm text-slate-600">
                                    {customer.contactEmail && <span className="truncate">{customer.contactEmail}</span>}
                                    {customer.city && <span className="text-slate-400">•</span>}
                                    {customer.city && <span>{customer.city}</span>}
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Phone</span> <span className="font-medium">{customer.contactPhone || "—"}</span></div>
                                  <div><span className="text-slate-500">Address</span> <span className="font-medium truncate block">{customer.address || "—"}</span></div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(customer.customerId)}>
                                    <Pencil className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  {permissions.canDelete && (
                                    <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteDialog(customer.customerId)}>
                                      <Trash2 className="h-4 w-4 mr-2" /> Delete
                                    </Button>
                                  )}
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                      ))}
                      {currentCustomers.length > 0 && (
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
                        <TableRow className="border-b">
                          <SortableHeader label="Name" sortKey="name" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[120px]", isMobile && "sticky-col-date bg-slate-50")} />
                          <SortableHeader label="Email" sortKey="contactEmail" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[200px] hidden sm:table-cell" />
                          <SortableHeader label="Phone" sortKey="contactPhone" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[150px] hidden md:table-cell" />
                          <SortableHeader label="City" sortKey="city" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px] hidden lg:table-cell" />
                          <SortableHeader label="Address" sortKey="address" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[200px] hidden xl:table-cell" />
                          <SortableHeader label="Date Added" sortKey="createdDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px] hidden xl:table-cell" />
                          <TableHead className={cn("font-semibold text-slate-900 text-center min-w-[100px]", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {currentCustomers.map((customer) => (
                          <TableRow key={customer.customerId} className="hover:bg-slate-50 transition-colors">
                            <TableCell className={cn("font-medium text-slate-900 bg-white", isMobile && "sticky-col-date")}>
                              <div className="flex flex-col">
                                <span>{customer.name}</span>
                                <div className="flex items-center gap-1 text-xs text-slate-500 sm:hidden">
                                  <MapPin className="w-3 h-3" /><span>{customer.city}</span>
                                </div>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden sm:table-cell">
                              <div className="flex items-center gap-2">
                                <Mail className="w-4 h-4 text-slate-400" />
                                <span className="truncate max-w-[200px]">{customer.contactEmail}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden md:table-cell">
                              <div className="flex items-center gap-2">
                                <Phone className="w-4 h-4 text-slate-400" /><span>{customer.contactPhone}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden lg:table-cell">
                              <div className="flex items-center gap-2">
                                <MapPin className="w-4 h-4 text-slate-400" /><span>{customer.city}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 max-w-[200px] hidden xl:table-cell">
                              <span className="truncate block">{customer.address}</span>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden xl:table-cell">
                              {(customer as any).createdDate ? new Date((customer as any).createdDate).toLocaleDateString() : "-"}
                            </TableCell>
                            <TableCell className={cn("text-center whitespace-nowrap bg-white", isMobile && "sticky-col-actions")}>
                              <div className="flex items-center justify-center gap-1 min-w-[90px]">
                                <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-blue-50 hover:text-blue-600" onClick={() => openEditDialog(customer.customerId)}>
                                  <Pencil className="w-4 h-4" />
                                </Button>
                                {permissions.canDelete && (
                                  <Button variant="ghost" size="icon" className="h-8 w-8 text-red-600 hover:text-red-700 hover:bg-red-50" onClick={() => openDeleteDialog(customer.customerId)}>
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
            
            {!loading && filteredCustomers.length > 0 && totalPages > 1 && (
              <div className="flex flex-col sm:flex-row items-center justify-between gap-4 mt-6">
                <div className="flex items-center gap-4">
                  <span className="text-sm text-slate-600">
                    Showing {startIndex + 1} to {Math.min(endIndex, sortedCustomers.length)} of {sortedCustomers.length} {searchQuery ? 'filtered ' : ''}customers
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
                      <PaginationPrevious onClick={handlePreviousPage} className={currentPage === 1 ? "pointer-events-none opacity-50" : "cursor-pointer"} />
                    </PaginationItem>
                    {getPageNumbers().map((page, index) => (
                      <PaginationItem key={index}>
                        {page === 'ellipsis' ? <PaginationEllipsis /> : (
                          <PaginationLink onClick={() => handlePageChange(page as number)} isActive={currentPage === page} className="cursor-pointer">{page}</PaginationLink>
                        )}
                      </PaginationItem>
                    ))}
                    <PaginationItem>
                      <PaginationNext onClick={handleNextPage} className={currentPage === totalPages ? "pointer-events-none opacity-50" : "cursor-pointer"} />
                    </PaginationItem>
                  </PaginationContent>
                </Pagination>
              </div>
            )}
          </div>
        </main>
      </div>

      {/* Create Customer Dialog */}
      <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <UserPlus className="w-5 h-5 text-blue-600" /> Add New Customer
            </DialogTitle>
            <DialogDescription>Enter the customer information below</DialogDescription>
          </DialogHeader>
          {createError && (
            <Alert variant="destructive"><AlertDescription>{createError}</AlertDescription></Alert>
          )}
          <form onSubmit={handleCreateSubmit} className="space-y-4">
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Full Name *</Label>
                  <Input name="name" placeholder="John Doe" value={createForm.name} onChange={handleCreateChange} required disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Phone Number *</Label>
                  <Input name="contactPhone" type="tel" placeholder="+1 (555) 123-4567" value={createForm.contactPhone} onChange={handleCreateChange} required disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Email Address</Label>
                  <Input name="contactEmail" type="text" placeholder="john@example.com (optional)" value={createForm.contactEmail} onChange={handleCreateChange} disabled={createLoading} />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">City *</Label>
                  <Input name="city" placeholder="New York" value={createForm.city} onChange={handleCreateChange} required disabled={createLoading} />
                </div>
              </div>
            </div>
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Address</div>
              <div className="p-4 bg-white">
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Full Address *</Label>
                  <Input name="address" placeholder="123 Main Street, Apt 4B" value={createForm.address} onChange={handleCreateChange} required disabled={createLoading} />
                </div>
              </div>
            </div>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button type="submit" disabled={createLoading}>
                {createLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating...</> : <><UserPlus className="w-4 h-4 mr-2" />Create Customer</>}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit Customer Dialog */}
      <Dialog open={isEditDialogOpen} onOpenChange={setIsEditDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Pencil className="w-5 h-5 text-blue-600" /> Edit Customer
            </DialogTitle>
            <DialogDescription>Update the customer information below</DialogDescription>
          </DialogHeader>
          {editError && (
            <Alert variant="destructive"><AlertDescription>{editError}</AlertDescription></Alert>
          )}
          {editFetching ? (
            <div className="py-8 text-center">
              <Loader2 className="w-8 h-8 animate-spin mx-auto mb-2 text-blue-600" />
              <p className="text-slate-600">Loading customer...</p>
            </div>
          ) : (
            <form onSubmit={handleEditSubmit} className="space-y-4">
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Full Name *</Label>
                    <Input name="name" placeholder="John Doe" value={editForm.name} onChange={handleEditChange} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Phone Number *</Label>
                    <Input name="contactPhone" type="tel" placeholder="+1 (555) 123-4567" value={editForm.contactPhone} onChange={handleEditChange} required disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Email Address</Label>
                    <Input name="contactEmail" type="text" placeholder="john@example.com (optional)" value={editForm.contactEmail} onChange={handleEditChange} disabled={editLoading} />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">City *</Label>
                    <Input name="city" placeholder="New York" value={editForm.city} onChange={handleEditChange} required disabled={editLoading} />
                  </div>
                </div>
              </div>
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Address</div>
                <div className="p-4 bg-white">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Full Address *</Label>
                    <Input name="address" placeholder="123 Main Street, Apt 4B" value={editForm.address} onChange={handleEditChange} required disabled={editLoading} />
                  </div>
                </div>
              </div>
              <div className="flex gap-3 justify-end pt-2">
                <Button type="button" onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                <Button type="submit" disabled={editLoading}>
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
            <AlertDialogTitle>Delete Customer</AlertDialogTitle>
            <AlertDialogDescription>Are you sure you want to delete this customer? This action cannot be undone.</AlertDialogDescription>
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

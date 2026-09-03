"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { PageShell } from "@/components/dashboard/page-shell"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Plus, Pencil, Trash2, Mail, Phone, UserCog, Users, Calendar, LogIn, Search, RefreshCw, Loader2, ChevronDown, ChevronUp, Download } from "lucide-react"
import { exportTableToPdf, emailTableAsPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"
import { getEmployees, deleteEmployee, getTodayLogins, type Employee } from "@/lib/api/admin"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { useMemo } from "react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { useIsMobile } from "@/hooks/use-mobile"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"
import { AddEmployeeDialog } from "@/components/employees/add-employee-dialog"
import { EditEmployeeDialog } from "@/components/employees/edit-employee-dialog"

export default function EmployeesPage() {
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const [employees, setEmployees] = useState<Employee[]>([])
  const [todayLogins, setTodayLogins] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage] = useState(10)
  const [searchQuery, setSearchQuery] = useState("")
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }
  const [isDeleting, setIsDeleting] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()

  // Create dialog state — the rich form lives in <AddEmployeeDialog>; this page
  // only controls open/close and Business Office mode.
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)

  // Business Office mode (?bo=1): no active company, so the Add-Employee form
  // shows a Company dropdown to choose which company the employee joins. Read
  // from window.location (not useSearchParams) to match the rest of the app and
  // avoid a Next.js prerender/Suspense build error.
  const [boMode, setBoMode] = useState(false)

  // Edit dialog state — the form itself lives in <EditEmployeeDialog>.
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editingEmployeeId, setEditingEmployeeId] = useState<string | null>(null)

  useEffect(() => {
    if (permissions.isLoading) return
    if (!permissions.isAdmin) { router.push("/dashboard"); return }
    loadEmployees()

    if (typeof window !== 'undefined') {
      const globalSearch = sessionStorage.getItem('globalSearchQuery')
      if (globalSearch) { setSearchQuery(globalSearch); sessionStorage.removeItem('globalSearchQuery') }
      const handleGlobalSearch = (e: CustomEvent) => { setSearchQuery(e.detail.query); setCurrentPage(1) }
      window.addEventListener('globalSearch', handleGlobalSearch as EventListener)
      return () => { window.removeEventListener('globalSearch', handleGlobalSearch as EventListener) }
    }
  }, [permissions.isAdmin, permissions.isLoading])

  const loadEmployees = async () => {
    try {
      setError("")
      const [employeesResult, todayLoginsResult] = await Promise.all([getEmployees(), getTodayLogins()])
      if (employeesResult.success && employeesResult.data) { setEmployees(employeesResult.data); setCurrentPage(1) }
      else { setError(employeesResult.message || "Failed to load employees") }
      if (todayLoginsResult.success && todayLoginsResult.data) { setTodayLogins(todayLoginsResult.data) }
    } catch (err) {
      console.error("[v0] Error loading employees:", err)
      setError("Unable to load employees. API may be unavailable.")
    } finally { setLoading(false) }
  }

  // Create handlers — the dialog resets its own form on open.
  const openCreateDialog = () => setIsCreateDialogOpen(true)

  // Deep-link: /employees?bo=1&add=1 sets office mode and opens the Add Employee
  // form straight away (used by the Business Office "Add employee" button).
  useEffect(() => {
    try {
      const p = new URLSearchParams(window.location.search)
      if (p.get("bo") === "1") setBoMode(true)
      if (p.get("add") === "1") openCreateDialog()
    } catch {}
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])


  // Edit handler — the dialog fetches the employee itself.
  const openEditDialog = (employeeId: string) => { setEditingEmployeeId(employeeId); setIsEditDialogOpen(true) }

  // Delete handlers
  const openDeleteDialog = (id: string) => { setDeletingId(id); setDeleteDialogOpen(true) }
  const handleDelete = async () => {
    if (!deletingId) return
    setIsDeleting(true)
    const result = await deleteEmployee(deletingId)
    if (result.success) {
      toast({ title: "Employee deleted", description: "The employee has been removed." })
      loadEmployees(); setCurrentPage(1)
    } else {
      toast({ title: "Delete failed", description: result.message || "Failed to delete employee.", variant: "destructive" })
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

  const filteredEmployees = useMemo(() => {
    if (!searchQuery.trim()) return employees
    const query = searchQuery.toLowerCase()
    return employees.filter(e =>
      (e.firstName || '').toLowerCase().includes(query) ||
      (e.lastName || '').toLowerCase().includes(query) ||
      (e.userName || '').toLowerCase().includes(query) ||
      (e.email || '').toLowerCase().includes(query) ||
      (e.phoneNumber || '').toLowerCase().includes(query) ||
      `${e.firstName} ${e.lastName}`.toLowerCase().includes(query)
    )
  }, [employees, searchQuery])

  const sortedEmployees = useMemo(() => sortData(filteredEmployees, sortKey, sortDir), [filteredEmployees, sortKey, sortDir])
  const totalPages = Math.ceil(sortedEmployees.length / itemsPerPage)
  const startIndex = (currentPage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const currentEmployees = sortedEmployees.slice(startIndex, endIndex)

  const clearFilters = () => { setSearchQuery(""); setCurrentPage(1) }

  const buildEmployeesPdfOpts = (): PdfExportOptions => ({
    title: "Employees Report",
    filename: "employees",
    columns: [
      { header: "Name" },
      { header: "Username" },
      { header: "Email" },
      { header: "Phone" },
      { header: "Role" },
      { header: "Status" },
    ],
    rows: sortedEmployees.map((e: any) => [
      `${e.firstName ?? ""} ${e.lastName ?? ""}`.trim(),
      e.userName ?? "",
      e.email ?? "",
      e.phoneNumber ?? "",
      e.isAdmin ? "Admin" : "Staff",
      e.isActive === false ? "Inactive" : "Active",
    ]),
    summaryLines: [`Total employees: ${filteredEmployees.length}`],
    headFillColor: [59, 130, 246],
  })

  const handleExportPdf = async () => {
    if (filteredEmployees.length === 0) {
      toast({ title: "Nothing to export", description: "No employees match the current filters.", variant: "destructive" })
      return
    }
    try {
      await exportTableToPdf(buildEmployeesPdfOpts())
    } catch (err) {
      toast({ title: "PDF export failed", description: "Could not generate PDF. Please try again.", variant: "destructive" })
    }
  }

  const [emailingReport, setEmailingReport] = useState(false)
  const handleEmailReport = async () => {
    if (filteredEmployees.length === 0) {
      toast({ title: "Nothing to email", description: "No employees match the current filters.", variant: "destructive" })
      return
    }
    setEmailingReport(true)
    try {
      const res = await emailTableAsPdf(buildEmployeesPdfOpts())
      if (res.success) toast({ title: "Report emailed", description: `Sent to ${res.recipient}.` })
      else toast({ title: "Email failed", description: res.message || "Could not send report.", variant: "destructive" })
    } finally {
      setEmailingReport(false)
    }
  }
  const handlePageChange = (page: number) => setCurrentPage(page)
  const handlePreviousPage = () => { if (currentPage > 1) setCurrentPage(currentPage - 1) }
  const handleNextPage = () => { if (currentPage < totalPages) setCurrentPage(currentPage + 1) }

  const getPageNumbers = () => {
    const pages: (number | string)[] = []
    if (totalPages <= 5) { for (let i = 1; i <= totalPages; i++) pages.push(i) }
    else {
      if (currentPage <= 3) { for (let i = 1; i <= 4; i++) pages.push(i); pages.push('ellipsis'); pages.push(totalPages) }
      else if (currentPage >= totalPages - 2) { pages.push(1); pages.push('ellipsis'); for (let i = totalPages - 3; i <= totalPages; i++) pages.push(i) }
      else { pages.push(1); pages.push('ellipsis'); for (let i = currentPage - 1; i <= currentPage + 1; i++) pages.push(i); pages.push('ellipsis'); pages.push(totalPages) }
    }
    return pages
  }

  if (permissions.isLoading) {
    return (
      <PageShell boActive="users">
        <main className="overflow-y-visible p-6 flex items-center justify-center"><p className="text-slate-600">Loading...</p></main>
      </PageShell>
    )
  }

  if (!permissions.isAdmin && !loading) return null

  return (
    <PageShell boActive="users">
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-center justify-between")}>
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-blue-100 rounded-lg flex items-center justify-center"><UserCog className="w-5 h-5 text-blue-600" /></div>
                <div className="min-w-0">
                  <h1 className={cn("font-bold text-slate-900", isMobile ? "text-xl" : "text-2xl")}>Employees</h1>
                  <p className="text-sm text-slate-600">Manage your staff members and their access</p>
                </div>
              </div>
              <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700 shrink-0" onClick={openCreateDialog}>
                <Plus className="w-4 h-4" /> Add Employee
              </Button>
            </div>

            {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

            {!loading && employees.length > 0 && (
              <div className="flex flex-wrap items-center gap-2 p-3 bg-white rounded-lg border">
                <div className="relative flex-1 min-w-[200px]">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search by name, username, email, or phone..." value={searchQuery} onChange={(e) => { setSearchQuery(e.target.value); setCurrentPage(1) }} className="pl-9" />
                </div>
                {searchQuery && <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" />Clear</Button>}
                <Button variant="outline" size="sm" onClick={handleExportPdf} className="gap-2">
                  <Download className="h-4 w-4" /> Export PDF
                </Button>
                <Button variant="outline" size="sm" onClick={handleEmailReport} disabled={emailingReport} className="gap-2">
                  {emailingReport ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />} Email Report
                </Button>
              </div>
            )}

            {todayLogins.length > 0 && (
              <Card className="bg-white border-l-4 border-l-green-500">
                <CardContent className="p-4">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 bg-green-100 rounded-full flex items-center justify-center"><LogIn className="w-5 h-5 text-green-600" /></div>
                    <div>
                      <h3 className="font-semibold text-slate-900">Today&apos;s Logins</h3>
                      <p className="text-sm text-slate-600">{todayLogins.length} {todayLogins.length === 1 ? 'employee has' : 'employees have'} logged in today</p>
                    </div>
                  </div>
                  <div className="mt-3 pt-3 border-t border-slate-200">
                    <div className="flex flex-wrap gap-2">
                      {todayLogins.map((e) => <Badge key={e.id} variant="secondary" className="bg-green-50 text-green-700 border-green-200">{e.firstName} {e.lastName}</Badge>)}
                    </div>
                  </div>
                </CardContent>
              </Card>
            )}

            {loading ? (
              <Card className="bg-white"><CardContent className="py-12 text-center"><p className="text-slate-600">Loading employees...</p></CardContent></Card>
            ) : filteredEmployees.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4"><Search className="w-8 h-8 text-slate-400" /></div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No employees found</h3>
                  <p className="text-slate-600 mb-6">{searchQuery ? `No employees match "${searchQuery}"` : "Get started by adding your first employee"}</p>
                  {!searchQuery && <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}><Plus className="w-4 h-4" />Add Your First Employee</Button>}
                  {searchQuery && <Button className="gap-2" variant="outline" onClick={clearFilters}><RefreshCw className="w-4 h-4" />Clear Search</Button>}
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {currentEmployees.map((employee, idx) => (
                        <Collapsible key={employee.id} defaultOpen className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="font-semibold text-slate-900">{employee.firstName} {employee.lastName}</div>
                                  <div className="mt-1 flex items-baseline gap-2">
                                    <span className="text-slate-600">@{employee.userName}</span>
                                    <Badge variant={employee.emailConfirmed ? "default" : "secondary"} className={employee.emailConfirmed ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"}>
                                      {employee.emailConfirmed ? "Active" : "Pending"}
                                    </Badge>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Email</span> <span className="font-medium truncate block">{employee.email}</span></div>
                                  <div><span className="text-slate-500">Phone</span> <span className="font-medium">{employee.phoneNumber || "—"}</span></div>
                                  <div><span className="text-slate-500">Created</span> <span className="font-medium">{employee.createdDate ? formatDateShort(employee.createdDate) : "—"}</span></div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(employee.id)}>
                                    <Pencil className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteDialog(employee.id)}>
                                    <Trash2 className="h-4 w-4 mr-2" /> Delete
                                  </Button>
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                      ))}
                      {currentEmployees.length > 0 && (
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
                  <div className="overflow-x-auto">
                    <Table className={cn("w-full", !isMobile && "min-w-[600px]")}>
                      <TableHeader>
                        <TableRow className="border-b">
                          <SortableHeader label="Name" sortKey="fullName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("font-semibold text-slate-900 min-w-[150px]", isMobile && "sticky-col-date bg-slate-50")} />
                          <SortableHeader label="Username" sortKey="userName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[150px] hidden sm:table-cell" />
                          <SortableHeader label="Email" sortKey="email" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[200px] hidden md:table-cell" />
                          <SortableHeader label="Phone" sortKey="phoneNumber" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[150px] hidden lg:table-cell" />
                          <SortableHeader label="Status" sortKey="isActive" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[100px] hidden xl:table-cell" />
                          <SortableHeader label="Created" sortKey="createdDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="font-semibold text-slate-900 min-w-[120px] hidden xl:table-cell" />
                          <TableHead className="font-semibold text-slate-900 text-center min-w-[100px]">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {currentEmployees.map((employee) => (
                          <TableRow key={employee.id} className="hover:bg-slate-50 transition-colors">
                            <TableCell className={cn("font-medium text-slate-900 bg-white", isMobile && "sticky-col-date")}>{employee.firstName} {employee.lastName}</TableCell>
                            <TableCell className="text-slate-600 hidden sm:table-cell">@{employee.userName}</TableCell>
                            <TableCell className="text-slate-600 hidden md:table-cell">
                              <div className="flex items-center gap-2"><Mail className="w-4 h-4 text-slate-400" /><span className="truncate max-w-[200px]">{employee.email}</span></div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden lg:table-cell">
                              <div className="flex items-center gap-2"><Phone className="w-4 h-4 text-slate-400" /><span>{employee.phoneNumber}</span></div>
                            </TableCell>
                            <TableCell className="hidden xl:table-cell">
                              <Badge variant={employee.emailConfirmed ? "default" : "secondary"} className={employee.emailConfirmed ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"}>
                                {employee.emailConfirmed ? "Active" : "Pending"}
                              </Badge>
                            </TableCell>
                            <TableCell className="text-slate-600 text-sm hidden xl:table-cell">
                              <div className="flex items-center gap-2"><Calendar className="w-4 h-4 text-slate-400" /><span>{formatDate(employee.createdDate)}</span></div>
                            </TableCell>
                            <TableCell className={cn("text-center bg-white", isMobile && "sticky-col-actions")}>
                              <div className="flex items-center justify-center gap-1">
                                <Button variant="ghost" size="icon" className="h-8 w-8 text-blue-600 hover:text-blue-700 hover:bg-blue-50" onClick={() => openEditDialog(employee.id)}>
                                  <Pencil className="w-4 h-4" />
                                </Button>
                                <Button variant="ghost" size="icon" className="h-8 w-8 text-red-600 hover:text-red-700 hover:bg-red-50" onClick={() => openDeleteDialog(employee.id)}>
                                  <Trash2 className="w-4 h-4" />
                                </Button>
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

            {!loading && filteredEmployees.length > 0 && totalPages > 1 && (
              <div className="flex items-center justify-between mt-6">
                <div className="text-sm text-slate-600">Showing {startIndex + 1} to {Math.min(endIndex, filteredEmployees.length)} of {filteredEmployees.length} {searchQuery ? 'filtered ' : ''}employees</div>
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
              </div>
            )}
          </div>
        </main>

      {/* Create Employee Dialog — rich form extracted to a reusable component. */}
      <AddEmployeeDialog
        open={isCreateDialogOpen}
        onOpenChange={setIsCreateDialogOpen}
        boMode={boMode}
        onCreated={loadEmployees}
      />

      {/* Edit Employee Dialog — shared with Business Office → Users & Permissions. */}
      <EditEmployeeDialog
        open={isEditDialogOpen}
        onOpenChange={setIsEditDialogOpen}
        employeeId={editingEmployeeId}
        onSaved={loadEmployees}
      />


      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Employee</AlertDialogTitle>
            <AlertDialogDescription>Are you sure you want to delete this employee? They will lose access to the system. This action cannot be undone.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} disabled={isDeleting} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              {isDeleting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Deleting...</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </PageShell>
  )
}

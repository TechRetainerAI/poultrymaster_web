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
import { Plus, Pencil, Trash2, Mail, Phone, UserCog, Users, Calendar, LogIn, Search, RefreshCw, Loader2, Save, User, ChevronDown, ChevronUp } from "lucide-react"
import { getEmployees, getEmployee, createEmployee, updateEmployee, deleteEmployee, getTodayLogins, type Employee, type CreateEmployeeData, type UpdateEmployeeData } from "@/lib/api/admin"
import { getUserContext } from "@/lib/utils/user-context"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { useMemo } from "react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { useIsMobile } from "@/hooks/use-mobile"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"

type AdminPermissionKey =
  | "changeGroupInfo"
  | "deleteMessages"
  | "banUsers"
  | "inviteUsers"
  | "pinMessages"
  | "manageStories"
  | "manageVideoChats"
  | "remainAnonymous"
  | "addNewAdmins"

const DEFAULT_ADMIN_PERMISSIONS: Record<AdminPermissionKey, boolean> = {
  changeGroupInfo: true,
  deleteMessages: true,
  banUsers: true,
  inviteUsers: true,
  pinMessages: true,
  manageStories: false,
  manageVideoChats: true,
  remainAnonymous: false,
  addNewAdmins: false,
}

const ADMIN_PERMISSION_OPTIONS: Array<{ key: AdminPermissionKey; label: string; hint?: string }> = [
  { key: "changeGroupInfo", label: "Change group info" },
  { key: "deleteMessages", label: "Delete messages" },
  { key: "banUsers", label: "Ban users" },
  { key: "inviteUsers", label: "Invite users via link" },
  { key: "pinMessages", label: "Pin messages" },
  { key: "manageStories", label: "Manage stories", hint: "0/3 by default" },
  { key: "manageVideoChats", label: "Manage video chats" },
  { key: "remainAnonymous", label: "Remain anonymous" },
  { key: "addNewAdmins", label: "Add new admins" },
]

type StaffFeaturePermissionKey =
  | "canEnterSales"
  | "canEnterExpenses"
  | "canViewCashLedger"
  | "canSeeEmployees"
  | "canViewReports"
  | "canViewFinancial"
  | "canViewActivityLog"
  | "canViewSettings"

const DEFAULT_STAFF_FEATURE_PERMISSIONS: Record<StaffFeaturePermissionKey, boolean> = {
  canEnterSales: true,
  canEnterExpenses: true,
  canViewCashLedger: true,
  canSeeEmployees: false,
  canViewReports: true,
  canViewFinancial: true,
  canViewActivityLog: true,
  canViewSettings: true,
}

const STAFF_FEATURE_PERMISSION_OPTIONS: Array<{ key: StaffFeaturePermissionKey; label: string }> = [
  { key: "canEnterSales", label: "Enter Sales" },
  { key: "canEnterExpenses", label: "Enter Expenses" },
  { key: "canViewCashLedger", label: "View Cash Ledger" },
  { key: "canSeeEmployees", label: "See Employees" },
  { key: "canViewReports", label: "View reports" },
  { key: "canViewFinancial", label: "View Financial" },
  { key: "canViewActivityLog", label: "View Activity Log" },
  { key: "canViewSettings", label: "View Settings" },
]

const toBoolean = (value: unknown): boolean | undefined => {
  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase()
    if (normalized === "true") return true
    if (normalized === "false") return false
  }
  return undefined
}

const normalizeAdminPermissions = (source: unknown): Record<AdminPermissionKey, boolean> => {
  const normalized = { ...DEFAULT_ADMIN_PERMISSIONS }
  if (!source || typeof source !== "object") return normalized

  const record = source as Record<string, unknown>
  for (const option of ADMIN_PERMISSION_OPTIONS) {
    const raw = toBoolean(record[option.key] ?? record[option.key.charAt(0).toUpperCase() + option.key.slice(1)])
    if (raw !== undefined) normalized[option.key] = raw
  }

  return normalized
}

const normalizeFeaturePermissions = (source: unknown): Record<StaffFeaturePermissionKey, boolean> => {
  const normalized = { ...DEFAULT_STAFF_FEATURE_PERMISSIONS }
  if (!source || typeof source !== "object") return normalized

  const record = source as Record<string, unknown>
  for (const option of STAFF_FEATURE_PERMISSION_OPTIONS) {
    const raw = toBoolean(record[option.key] ?? record[option.key.charAt(0).toUpperCase() + option.key.slice(1)])
    if (raw !== undefined) normalized[option.key] = raw
  }

  return normalized
}

type EmployeePermissionSnapshot = {
  isAdmin: boolean
  adminTitle: string
  adminPermissions: Record<AdminPermissionKey, boolean>
  featurePermissions: Record<StaffFeaturePermissionKey, boolean>
}

const EMPLOYEE_PERMISSION_CACHE_KEY = "employeePermissionOverrides"

const loadCachedEmployeePermissions = (employeeId: string): EmployeePermissionSnapshot | null => {
  if (typeof window === "undefined") return null
  try {
    const raw = localStorage.getItem(EMPLOYEE_PERMISSION_CACHE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Record<string, unknown>
    const entry = parsed?.[employeeId]
    if (!entry || typeof entry !== "object") return null
    const record = entry as Record<string, unknown>
    return {
      isAdmin: toBoolean(record.isAdmin) ?? false,
      adminTitle: typeof record.adminTitle === "string" ? record.adminTitle : "",
      adminPermissions: normalizeAdminPermissions(record.adminPermissions),
      featurePermissions: normalizeFeaturePermissions(record.featurePermissions),
    }
  } catch {
    return null
  }
}

const cacheEmployeePermissions = (employeeId: string, snapshot: EmployeePermissionSnapshot) => {
  if (typeof window === "undefined") return
  try {
    const raw = localStorage.getItem(EMPLOYEE_PERMISSION_CACHE_KEY)
    const parsed = raw ? (JSON.parse(raw) as Record<string, unknown>) : {}
    const next: Record<string, unknown> = {
      ...parsed,
      [employeeId]: snapshot,
    }
    localStorage.setItem(EMPLOYEE_PERMISSION_CACHE_KEY, JSON.stringify(next))
  } catch {
    // Ignore cache failures: API data remains the source of truth when available.
  }
}

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

  // Create dialog state
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [createLoading, setCreateLoading] = useState(false)
  const [createError, setCreateError] = useState("")
  const [showStaffPermissions, setShowStaffPermissions] = useState(false)
  const [createForm, setCreateForm] = useState({
    userName: "", email: "", password: "", confirmPassword: "", firstName: "", lastName: "", phoneNumber: "",
    isAdmin: false, adminTitle: "", adminPermissions: { ...DEFAULT_ADMIN_PERMISSIONS },
    featurePermissions: { ...DEFAULT_STAFF_FEATURE_PERMISSIONS },
  })

  // Edit dialog state
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editFetching, setEditFetching] = useState(false)
  const [editingEmployeeId, setEditingEmployeeId] = useState<string | null>(null)
  const [showEditStaffPermissions, setShowEditStaffPermissions] = useState(false)
  const [editForm, setEditForm] = useState({
    firstName: "", lastName: "", phoneNumber: "", email: "", userName: "", createdDate: "",
    isAdmin: false, adminTitle: "", adminPermissions: { ...DEFAULT_ADMIN_PERMISSIONS },
    featurePermissions: { ...DEFAULT_STAFF_FEATURE_PERMISSIONS },
  })

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

  // Create handlers
  const openCreateDialog = () => {
    setCreateForm({
      userName: "", email: "", password: "", confirmPassword: "", firstName: "", lastName: "", phoneNumber: "",
      isAdmin: false, adminTitle: "", adminPermissions: { ...DEFAULT_ADMIN_PERMISSIONS },
      featurePermissions: { ...DEFAULT_STAFF_FEATURE_PERMISSIONS },
    })
    setCreateError("")
    setShowStaffPermissions(false)
    setIsCreateDialogOpen(true)
  }

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setCreateLoading(true)
    setCreateError("")
    const { farmId } = getUserContext()
    const farmName = localStorage.getItem("farmName") || "My Farm"
    if (!farmId) { setCreateError("Farm information not found."); setCreateLoading(false); return }
    if (!createForm.firstName.trim() || !createForm.lastName.trim() || !createForm.phoneNumber.trim() || !createForm.email.trim()) {
      const msg = "First name, last name, phone number, and email are required."
      setCreateError(msg)
      toastFormGuide(toast, "Fill in first name, last name, phone number, and email — they are required to create an employee account.")
      setCreateLoading(false)
      return
    }
    if (createForm.password !== createForm.confirmPassword) { setCreateError("Passwords do not match"); setCreateLoading(false); return }
    if (createForm.password.length < 4) { setCreateError("Password must be at least 4 characters long"); setCreateLoading(false); return }
    if (!/^[a-zA-Z0-9_]+$/.test(createForm.userName)) { setCreateError("Username can only contain letters, digits, and underscores"); setCreateLoading(false); return }

    const employeeData: CreateEmployeeData = {
      userName: createForm.userName, email: createForm.email, password: createForm.password,
      firstName: createForm.firstName, lastName: createForm.lastName,
      phoneNumber: createForm.phoneNumber, farmId, farmName,
      isAdmin: createForm.isAdmin,
      adminTitle: createForm.isAdmin ? createForm.adminTitle.trim() : "",
      adminPermissions: createForm.isAdmin ? createForm.adminPermissions : undefined,
      featurePermissions: createForm.featurePermissions,
    }
    const result = await createEmployee(employeeData)
    if (result.success) {
      toast({ title: "Success!", description: "Employee created successfully." })
      setIsCreateDialogOpen(false)
      loadEmployees()
    } else {
      setCreateError(result.message || "Failed to create employee")
    }
    setCreateLoading(false)
  }

  // Edit handlers
  const openEditDialog = async (employeeId: string) => {
    setEditingEmployeeId(employeeId)
    setEditError("")
    setEditFetching(true)
    setShowEditStaffPermissions(false)
    setIsEditDialogOpen(true)

    try {
      const result = await getEmployee(employeeId)
      if (result.success && result.data) {
        const employeeData = result.data as Employee & {
          IsAdmin?: boolean
          AdminTitle?: string | null
          Permissions?: Record<string, unknown> | null
          FeaturePermissions?: Record<string, unknown> | null
          FeatureAccess?: Record<string, unknown> | null
        }

        const isAdmin =
          toBoolean(employeeData.isAdmin) ??
          toBoolean(employeeData.IsAdmin) ??
          false
        const adminTitle = employeeData.adminTitle ?? employeeData.AdminTitle ?? ""
        const apiAdminPermissionsSource = employeeData.permissions ?? employeeData.Permissions
        const apiFeaturePermissionsSource =
          employeeData.featurePermissions ?? employeeData.FeaturePermissions ?? employeeData.featureAccess ?? employeeData.FeatureAccess
        const hasApiPermissions =
          apiAdminPermissionsSource !== undefined ||
          apiFeaturePermissionsSource !== undefined ||
          employeeData.isAdmin !== undefined ||
          employeeData.IsAdmin !== undefined ||
          employeeData.adminTitle !== undefined ||
          employeeData.AdminTitle !== undefined
        const cachedPermissions = loadCachedEmployeePermissions(employeeId)
        const adminPermissions = hasApiPermissions
          ? normalizeAdminPermissions(apiAdminPermissionsSource)
          : cachedPermissions?.adminPermissions ?? { ...DEFAULT_ADMIN_PERMISSIONS }
        const featurePermissions = hasApiPermissions
          ? normalizeFeaturePermissions(apiFeaturePermissionsSource)
          : cachedPermissions?.featurePermissions ?? { ...DEFAULT_STAFF_FEATURE_PERMISSIONS }
        const resolvedIsAdmin = hasApiPermissions ? isAdmin : (cachedPermissions?.isAdmin ?? false)
        const resolvedAdminTitle = hasApiPermissions ? (adminTitle ?? "") : (cachedPermissions?.adminTitle ?? "")

        setEditForm({
          firstName: result.data.firstName, lastName: result.data.lastName,
          phoneNumber: result.data.phoneNumber, email: result.data.email,
          userName: result.data.userName || "", createdDate: result.data.createdDate || "",
          isAdmin: resolvedIsAdmin,
          adminTitle: resolvedAdminTitle,
          adminPermissions,
          featurePermissions,
        })
      } else {
        setEditError(result.message || "Failed to load employee")
      }
    } catch (err) {
      setEditError("Unable to load employee.")
    }
    setEditFetching(false)
  }

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editingEmployeeId) return
    setEditLoading(true)
    setEditError("")

    if (!editForm.firstName.trim() || !editForm.lastName.trim() || !editForm.phoneNumber.trim() || !editForm.email.trim()) {
      const msg = "First name, last name, phone number, and email are required."
      setEditError(msg)
      toastFormGuide(toast, "Fill in first name, last name, phone number, and email — they are required to save this profile.")
      setEditLoading(false)
      return
    }

    const employeeData: UpdateEmployeeData = {
      id: editingEmployeeId, firstName: editForm.firstName, lastName: editForm.lastName,
      phoneNumber: editForm.phoneNumber, email: editForm.email,
      isAdmin: editForm.isAdmin,
      adminTitle: editForm.isAdmin ? editForm.adminTitle.trim() : "",
      adminPermissions: editForm.isAdmin ? editForm.adminPermissions : undefined,
      featurePermissions: editForm.featurePermissions,
    }
    const result = await updateEmployee(editingEmployeeId, employeeData)
    if (result.success) {
      cacheEmployeePermissions(editingEmployeeId, {
        isAdmin: editForm.isAdmin,
        adminTitle: editForm.isAdmin ? editForm.adminTitle.trim() : "",
        adminPermissions: editForm.adminPermissions,
        featurePermissions: editForm.featurePermissions,
      })
      toast({ title: "Success!", description: "Employee updated successfully." })
      setIsEditDialogOpen(false)
      loadEmployees()
    } else {
      setEditError(result.message || "Failed to update employee")
    }
    setEditLoading(false)
  }

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
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={handleLogout} />
        <div className="flex-1 flex flex-col">
          <DashboardHeader />
          <main className="overflow-y-visible p-6 flex items-center justify-center"><p className="text-slate-600">Loading...</p></main>
        </div>
      </div>
    )
  }

  if (!permissions.isAdmin && !loading) return null

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
                        <Collapsible key={employee.id} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
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
      </div>

      {/* Create Employee Dialog */}
      <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><UserCog className="w-5 h-5 text-blue-600" /> Add New Employee</DialogTitle>
            <DialogDescription>Create a staff member or configure an admin with custom permissions</DialogDescription>
          </DialogHeader>
          {createError && <Alert variant="destructive"><AlertDescription>{createError}</AlertDescription></Alert>}
          <form onSubmit={handleCreateSubmit} className="space-y-4">
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">First Name *</Label>
                  <Input name="firstName" value={createForm.firstName} onChange={(e) => setCreateForm({...createForm, firstName: e.target.value})} required disabled={createLoading} placeholder="John" />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Last Name *</Label>
                  <Input name="lastName" value={createForm.lastName} onChange={(e) => setCreateForm({...createForm, lastName: e.target.value})} required disabled={createLoading} placeholder="Doe" />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Phone Number *</Label>
                  <Input name="phoneNumber" type="tel" value={createForm.phoneNumber} onChange={(e) => setCreateForm({...createForm, phoneNumber: e.target.value})} required disabled={createLoading} placeholder="+233 533431086" />
                </div>
              </div>
            </div>
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Account Information</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Username * <span className="text-xs text-slate-500 font-normal">(letters, digits, underscores)</span></Label>
                  <Input name="userName" value={createForm.userName} onChange={(e) => setCreateForm({...createForm, userName: e.target.value})} required disabled={createLoading} placeholder="james_quayson" pattern="[a-zA-Z0-9_]+" />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Email *</Label>
                  <Input name="email" type="email" value={createForm.email} onChange={(e) => setCreateForm({...createForm, email: e.target.value})} required disabled={createLoading} placeholder="employee@example.com" />
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Password *</Label>
                  <Input name="password" type="password" value={createForm.password} onChange={(e) => setCreateForm({...createForm, password: e.target.value})} required disabled={createLoading} placeholder="At least 4 characters" />
                  <p className="text-xs text-slate-500">Min 4 characters</p>
                </div>
                <div className="space-y-2">
                  <Label className="text-sm font-medium text-slate-700">Confirm Password *</Label>
                  <Input name="confirmPassword" type="password" value={createForm.confirmPassword} onChange={(e) => setCreateForm({...createForm, confirmPassword: e.target.value})} required disabled={createLoading} placeholder="Re-enter password" />
                </div>
              </div>
            </div>
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-cyan-700 px-4 py-2 text-sm font-semibold text-white">Admin Access</div>
              <div className="p-4 bg-white space-y-4">
                <div className="flex items-center justify-between gap-3 p-3 rounded-lg border border-slate-200 bg-slate-50">
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-slate-800">Create as administrator</p>
                    <p className="text-xs text-slate-500">Enable this to assign granular admin permissions.</p>
                  </div>
                  <Switch
                    checked={createForm.isAdmin}
                    onCheckedChange={(checked) => setCreateForm({ ...createForm, isAdmin: checked })}
                    disabled={createLoading}
                    aria-label="Create as administrator"
                  />
                </div>

                {createForm.isAdmin && (
                  <div className="space-y-4">
                    <div className="rounded-lg border border-slate-200 p-3 bg-cyan-50/60">
                      <p className="text-sm font-medium text-slate-800">
                        {createForm.firstName || createForm.userName || "New admin"}
                      </p>
                      <p className="text-xs text-slate-600">
                        Configure what this admin can do. Permissions can be updated later.
                      </p>
                    </div>

                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Custom title (optional)</Label>
                      <Input
                        name="adminTitle"
                        value={createForm.adminTitle}
                        onChange={(e) => setCreateForm({ ...createForm, adminTitle: e.target.value })}
                        disabled={createLoading}
                        placeholder="admin"
                        maxLength={30}
                      />
                      <p className="text-xs text-slate-500">Shown instead of the default admin label.</p>
                    </div>

                    <div className="rounded-lg border border-slate-200 divide-y">
                      <div className="px-3 py-2 bg-slate-50">
                        <p className="text-sm font-semibold text-slate-800">What can this admin do?</p>
                      </div>
                      {ADMIN_PERMISSION_OPTIONS.map((perm) => (
                        <div key={perm.key} className="flex items-center justify-between gap-3 px-3 py-2">
                          <div className="min-w-0">
                            <p className="text-sm text-slate-800">{perm.label}</p>
                            {perm.hint && <p className="text-xs text-slate-500">{perm.hint}</p>}
                          </div>
                          <Switch
                            checked={createForm.adminPermissions[perm.key]}
                            onCheckedChange={(checked) =>
                              setCreateForm({
                                ...createForm,
                                adminPermissions: { ...createForm.adminPermissions, [perm.key]: checked },
                              })
                            }
                            disabled={createLoading}
                            aria-label={perm.label}
                          />
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-slate-700 px-4 py-2 text-sm font-semibold text-white">Staff Page Access</div>
              <div className="p-4 bg-white space-y-3">
                <p className="text-xs text-slate-600">Set exactly what employees can access.</p>
                <Button
                  type="button"
                  variant="outline"
                  className="w-full justify-between"
                  onClick={() => setShowStaffPermissions((prev) => !prev)}
                  disabled={createLoading}
                >
                  <span>Select Staff Permissions</span>
                  <ChevronDown className={cn("h-4 w-4 transition-transform", showStaffPermissions && "rotate-180")} />
                </Button>

                {showStaffPermissions && (
                  <div className="rounded-lg border border-slate-200 divide-y">
                    {STAFF_FEATURE_PERMISSION_OPTIONS.map((perm) => (
                      <div key={perm.key} className="flex items-center justify-between gap-3 px-3 py-2">
                        <p className="text-sm text-slate-800">{perm.label}</p>
                        <Switch
                          checked={createForm.featurePermissions[perm.key]}
                          onCheckedChange={(checked) =>
                            setCreateForm({
                              ...createForm,
                              featurePermissions: { ...createForm.featurePermissions, [perm.key]: checked },
                            })
                          }
                          disabled={createLoading}
                          aria-label={perm.label}
                        />
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button type="submit" disabled={createLoading}>
                {createLoading ? (
                  <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating...</>
                ) : (
                  <><UserCog className="w-4 h-4 mr-2" />{createForm.isAdmin ? "Create Admin" : "Create Employee"}</>
                )}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit Employee Dialog */}
      <Dialog open={isEditDialogOpen} onOpenChange={setIsEditDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Pencil className="w-5 h-5 text-blue-600" /> Edit Employee</DialogTitle>
            <DialogDescription>Update employee profile and access permissions</DialogDescription>
          </DialogHeader>
          {editError && <Alert variant="destructive"><AlertDescription>{editError}</AlertDescription></Alert>}
          {editFetching ? (
            <div className="py-8 text-center"><Loader2 className="w-8 h-8 animate-spin mx-auto mb-2 text-blue-600" /><p className="text-slate-600">Loading employee...</p></div>
          ) : (
            <form onSubmit={handleEditSubmit} className="space-y-4">
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">First Name *</Label>
                    <Input name="firstName" value={editForm.firstName} onChange={(e) => setEditForm({...editForm, firstName: e.target.value})} required disabled={editLoading} placeholder="John" />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Last Name *</Label>
                    <Input name="lastName" value={editForm.lastName} onChange={(e) => setEditForm({...editForm, lastName: e.target.value})} required disabled={editLoading} placeholder="Doe" />
                  </div>
                </div>
              </div>
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Contact Information</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Email Address *</Label>
                    <Input name="email" type="email" value={editForm.email} onChange={(e) => setEditForm({...editForm, email: e.target.value})} required disabled={editLoading} placeholder="john@example.com" />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Phone Number *</Label>
                    <Input name="phoneNumber" type="tel" value={editForm.phoneNumber} onChange={(e) => setEditForm({...editForm, phoneNumber: e.target.value})} required disabled={editLoading} placeholder="+1 (555) 123-4567" />
                  </div>
                </div>
              </div>
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-slate-600 px-4 py-2 text-sm font-semibold text-white">Account Information</div>
                <div className="p-4 bg-white space-y-3">
                  <div className="flex items-center gap-3 text-sm"><User className="w-4 h-4 text-slate-400" /><span className="text-slate-500 w-24">Username:</span><span className="font-medium text-slate-800">{editForm.userName ? `@${editForm.userName}` : "Not set"}</span></div>
                  <div className="flex items-center gap-3 text-sm"><User className="w-4 h-4 text-slate-400" /><span className="text-slate-500 w-24">Employee ID:</span><span className="font-mono text-xs text-slate-800">{editingEmployeeId}</span></div>
                  {editForm.createdDate && <div className="flex items-center gap-3 text-sm"><User className="w-4 h-4 text-slate-400" /><span className="text-slate-500 w-24">Created:</span><span className="text-slate-800">{new Date(editForm.createdDate).toLocaleDateString()}</span></div>}
                </div>
              </div>
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-cyan-700 px-4 py-2 text-sm font-semibold text-white">Admin Access</div>
                <div className="p-4 bg-white space-y-4">
                  <div className="flex items-center justify-between gap-3 p-3 rounded-lg border border-slate-200 bg-slate-50">
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-slate-800">Grant administrator access</p>
                      <p className="text-xs text-slate-500">Turn on to configure admin-only actions for this employee.</p>
                    </div>
                    <Switch
                      checked={editForm.isAdmin}
                      onCheckedChange={(checked) => setEditForm({ ...editForm, isAdmin: checked })}
                      disabled={editLoading}
                      aria-label="Grant administrator access"
                    />
                  </div>

                  {editForm.isAdmin && (
                    <div className="space-y-4">
                      <div className="space-y-2">
                        <Label className="text-sm font-medium text-slate-700">Custom title (optional)</Label>
                        <Input
                          name="adminTitle"
                          value={editForm.adminTitle}
                          onChange={(e) => setEditForm({ ...editForm, adminTitle: e.target.value })}
                          disabled={editLoading}
                          placeholder="admin"
                          maxLength={30}
                        />
                      </div>

                      <div className="rounded-lg border border-slate-200 divide-y">
                        <div className="px-3 py-2 bg-slate-50">
                          <p className="text-sm font-semibold text-slate-800">What can this admin do?</p>
                        </div>
                        {ADMIN_PERMISSION_OPTIONS.map((perm) => (
                          <div key={perm.key} className="flex items-center justify-between gap-3 px-3 py-2">
                            <div className="min-w-0">
                              <p className="text-sm text-slate-800">{perm.label}</p>
                              {perm.hint && <p className="text-xs text-slate-500">{perm.hint}</p>}
                            </div>
                            <Switch
                              checked={editForm.adminPermissions[perm.key]}
                              onCheckedChange={(checked) =>
                                setEditForm({
                                  ...editForm,
                                  adminPermissions: { ...editForm.adminPermissions, [perm.key]: checked },
                                })
                              }
                              disabled={editLoading}
                              aria-label={perm.label}
                            />
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-slate-700 px-4 py-2 text-sm font-semibold text-white">Staff Page Access</div>
                <div className="p-4 bg-white space-y-3">
                  <p className="text-xs text-slate-600">Set exactly what this employee can access.</p>
                  <Button
                    type="button"
                    variant="outline"
                    className="w-full justify-between"
                    onClick={() => setShowEditStaffPermissions((prev) => !prev)}
                    disabled={editLoading}
                  >
                    <span>Select Staff Permissions</span>
                    <ChevronDown className={cn("h-4 w-4 transition-transform", showEditStaffPermissions && "rotate-180")} />
                  </Button>

                  {showEditStaffPermissions && (
                    <div className="rounded-lg border border-slate-200 divide-y">
                      {STAFF_FEATURE_PERMISSION_OPTIONS.map((perm) => (
                        <div key={perm.key} className="flex items-center justify-between gap-3 px-3 py-2">
                          <p className="text-sm text-slate-800">{perm.label}</p>
                          <Switch
                            checked={editForm.featurePermissions[perm.key]}
                            onCheckedChange={(checked) =>
                              setEditForm({
                                ...editForm,
                                featurePermissions: { ...editForm.featurePermissions, [perm.key]: checked },
                              })
                            }
                            disabled={editLoading}
                            aria-label={perm.label}
                          />
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
              <div className="flex gap-3 justify-end pt-2">
                <Button type="button" onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                <Button type="submit" disabled={editLoading}>
                  {editLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : <><Save className="w-4 h-4 mr-2" />Save Changes</>}
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
    </div>
  )
}

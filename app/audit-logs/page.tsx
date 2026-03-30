"use client"

import { useEffect, useState } from "react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Search, Download, FileText, Filter, ChevronDown, ChevronUp } from "lucide-react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { useAuth } from "@/lib/hooks/use-auth"
import { AuditLogsService } from "@/lib/services/audit-logs.service"
import { getUserContext } from "@/lib/utils/user-context"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"
import { Label } from "@/components/ui/label"

interface AuditLog {
  id: string
  userId: string
  userName: string
  action: string
  resource: string
  resourceId: string
  details: string
  ipAddress: string
  userAgent: string
  timestamp: string
  status: "Success" | "Failed"
}

export default function AuditLogsPage() {
  const { user, logout } = useAuth()
  const [logs, setLogs] = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [searchQuery, setSearchQuery] = useState("")
  const [filterStatus, setFilterStatus] = useState<"All" | "Success" | "Failed">("All")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const [currentPage, setCurrentPage] = useState(1)
  const pageSize = 10
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }

  const handleLogout = () => {
    logout()
  }

  	useEffect(() => {
    const fetchLogs = async () => {
       try {
         setLoading(true)
         setError("")
         
         console.log("Starting to fetch audit logs...")
         
         // Set a timeout to prevent infinite loading
         const timeoutId = setTimeout(() => {
           setLoading(false)
           setError("Request timeout. The audit logs API may not be responding.")
           setLogs([])
         }, 10000) // 10 second timeout
         
         // Ensure apiClient has the token
         const token = localStorage.getItem("auth_token")
         console.log("Token exists:", !!token)
         
         if (token) {
           const { apiClient } = await import('@/lib/api/client')
           apiClient.setToken(token)
           console.log("Synced token with apiClient")
         }
         
         // Get farmId from user context
         const { farmId, userId } = getUserContext()
         
         if (!farmId) {
           setError("Farm ID not found. Please log in again.")
           setLoading(false)
           return
         }
         
         console.log("Calling AuditLogsService.getAll with farmId:", farmId)
         const data = await AuditLogsService.getAll({
           farmId,
           userId,
           page: 1,
           pageSize: 200,
         })
         
         clearTimeout(timeoutId)
         console.log("Audit logs data received:", data)
         
         if (data && Array.isArray(data)) {
           setLogs(data)
           console.log(`Loaded ${data.length} audit logs`)
         } else {
           console.warn("Received non-array data:", data)
           setLogs([])
         }
       } catch (err: any) {
         console.error("Error loading audit logs:", err)
         const errorMsg = err?.message || "Failed to load audit logs. Please check your connection."
         setError(errorMsg)
         setLogs([])
       } finally {
         setLoading(false)
       }
    }

    // Always attempt to load, even if user context hasn't hydrated yet
    fetchLogs()
  }, [user])

  const filteredLogs = logs.filter(log => {
    const matchesSearch = 
      log.action.toLowerCase().includes(searchQuery.toLowerCase()) ||
      log.resource.toLowerCase().includes(searchQuery.toLowerCase()) ||
      log.userName.toLowerCase().includes(searchQuery.toLowerCase())
    
    const matchesStatus = filterStatus === "All" || log.status === filterStatus
    
    return matchesSearch && matchesStatus
  })

  const sortedLogs = sortData(filteredLogs, sortKey, sortDir, (item: any, key: string) => {
    if (key === "timestamp") return new Date(item.timestamp)
    return (item as any)[key]
  })
  const totalPages = Math.max(1, Math.ceil(sortedLogs.length / pageSize))
  const safePage = Math.min(currentPage, totalPages)
  const paginatedLogs = sortedLogs.slice((safePage - 1) * pageSize, safePage * pageSize)

  useEffect(() => {
    setCurrentPage(1)
  }, [searchQuery, filterStatus])

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleString()
  }

  const friendlyAction = (method: string) => {
    switch ((method || '').toUpperCase()) {
      case 'GET':
        return 'Viewed'
      case 'POST':
        return 'Created'
      case 'PUT':
        return 'Updated'
      case 'DELETE':
        return 'Deleted'
      default:
        return method
    }
  }

  const displayUser = (name?: string) => {
    if (name && name.toLowerCase() !== 'unknown') return name
    if (typeof window !== 'undefined') {
      const local = localStorage.getItem('username') || localStorage.getItem('userName')
      if (local) return local
    }
    return 'Unknown'
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Header */}
            <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-start justify-between")}>
              <div>
                <h1 className={cn("font-bold text-slate-900", isMobile ? "text-xl" : "text-3xl")}>Audit Logs</h1>
                <p className="text-sm text-slate-600 mt-1">Track all user activities and system events</p>
              </div>
            </div>

            {/* Filters */}
            <div className="flex flex-wrap items-center gap-2">
              <div className="relative flex-1 min-w-[200px]">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400 w-4 h-4" />
                <Input
                  placeholder="Search logs..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-10"
                />
              </div>
              {isMobile ? (
                <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                  <SheetTrigger asChild>
                    <Button variant="outline" size="sm" className="gap-2 shrink-0">
                      <Filter className="h-4 w-4" /> Filters
                    </Button>
                  </SheetTrigger>
                  <SheetContent side="bottom" className="rounded-t-2xl max-h-[85vh]">
                    <SheetHeader><SheetTitle>Filters</SheetTitle></SheetHeader>
                    <div className="space-y-4 pt-4">
                      <div className="space-y-2">
                        <Label>Status</Label>
                        <div className="flex gap-2">
                          <Button variant={filterStatus === "All" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("All")}>All</Button>
                          <Button variant={filterStatus === "Success" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("Success")}>Success</Button>
                          <Button variant={filterStatus === "Failed" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("Failed")}>Failed</Button>
                        </div>
                      </div>
                      <div className="flex gap-2 pt-2">
                        <Button variant="outline" className="flex-1" onClick={() => { setFilterStatus("All"); setSearchQuery("") }}>Clear</Button>
                        <Button className="flex-1" onClick={() => setFiltersOpen(false)}>Apply</Button>
                      </div>
                    </div>
                  </SheetContent>
                </Sheet>
              ) : (
                <div className="flex gap-2">
                  <Button variant={filterStatus === "All" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("All")}>All</Button>
                  <Button variant={filterStatus === "Success" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("Success")}>Success</Button>
                  <Button variant={filterStatus === "Failed" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("Failed")}>Failed</Button>
                </div>
              )}
              <Button variant="outline" size="icon" className="shrink-0">
                <Download className="w-4 h-4" />
              </Button>
            </div>

            {/* Logs Table */}
            <Card>
              <CardHeader>
                <CardTitle>Audit Trail</CardTitle>
                <CardDescription>Recent system activities and user actions</CardDescription>
              </CardHeader>
              <CardContent>
                {loading ? (
                  <div className="flex items-center justify-center py-8">
                    <div className="text-slate-500">Loading logs...</div>
                  </div>
                ) : error ? (
                  <div className="text-red-500 text-center py-8">{error}</div>
                ) : filteredLogs.length === 0 ? (
                  <div className="text-center py-8 text-slate-500">
                    No audit logs found
                  </div>
                ) : isMobile && !showAllColumnsMobile ? (
                  <div className="divide-y divide-slate-100 p-0 -mx-6 -mb-6">
                    {paginatedLogs.map((log, idx) => (
                      <Collapsible key={log.id} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                        <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                          <CollapsibleTrigger asChild>
                            <div className="flex items-start justify-between gap-3 cursor-pointer">
                              <div className="min-w-0 flex-1">
                                <div className="font-semibold text-slate-900">{formatDateShort(log.timestamp)}</div>
                                <div className="mt-1 flex flex-wrap items-baseline gap-2">
                                  <Badge variant={log.status === "Success" ? "default" : "destructive"}>{log.status}</Badge>
                                  <span className="text-slate-600">{displayUser(log.userName as any)}</span>
                                  <span className="text-slate-500">{friendlyAction((log as any).action)}</span>
                                </div>
                              </div>
                              <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                            </div>
                          </CollapsibleTrigger>
                          <CollapsibleContent>
                            <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                              <div className="grid grid-cols-2 gap-2">
                                <div><span className="text-slate-500">Resource</span> <span className="font-medium">{log.resource}</span></div>
                                <div><span className="text-slate-500">IP</span> <span className="font-medium font-mono text-xs">{log.ipAddress}</span></div>
                                {log.details && <div className="col-span-2"><span className="text-slate-500">Details</span> <span className="font-medium block truncate">{log.details}</span></div>}
                              </div>
                            </div>
                          </CollapsibleContent>
                        </div>
                      </Collapsible>
                    ))}
                    <div className="px-4 py-3 bg-slate-50/50 border-t">
                      <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowAllColumnsMobile(true)}>
                        View table format <ChevronDown className="h-4 w-4 ml-1" />
                      </Button>
                    </div>
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
                      <TableRow>
                        <SortableHeader label="Timestamp" sortKey="timestamp" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn(isMobile && "sticky-col-date bg-slate-50")} />
                        <SortableHeader label="User" sortKey="userName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Action" sortKey="action" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Resource" sortKey="resource" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="IP Address" sortKey="ipAddress" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Status" sortKey="status" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <TableHead className={cn(isMobile && "sticky-col-actions bg-slate-50")}>Details</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {paginatedLogs.map((log) => (
                        <TableRow key={log.id}>
                          <TableCell className={cn("font-mono text-sm bg-white", isMobile && "sticky-col-date")}>
                            {isMobile ? formatDateShort(log.timestamp) : formatDate(log.timestamp)}
                          </TableCell>
                          <TableCell>{displayUser(log.userName as any)}</TableCell>
                          <TableCell className="font-medium">{friendlyAction((log as any).action)}</TableCell>
                          <TableCell>{log.resource}</TableCell>
                          <TableCell className="font-mono text-xs">{log.ipAddress}</TableCell>
                          <TableCell>
                            <Badge variant={log.status === "Success" ? "default" : "destructive"}>
                              {log.status}
                            </Badge>
                          </TableCell>
                          <TableCell className={cn("max-w-xs truncate bg-white", isMobile && "sticky-col-actions")}>{log.details}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  </div>
                )}
                {!loading && !error && filteredLogs.length > 0 && (
                  <div className="flex items-center justify-between gap-2 px-4 py-3 border-t bg-slate-50">
                    <p className="text-xs text-slate-600">
                      Showing {(safePage - 1) * pageSize + 1}-{Math.min(safePage * pageSize, sortedLogs.length)} of {sortedLogs.length}
                    </p>
                    <div className="flex items-center gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        disabled={safePage <= 1}
                        onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                      >
                        Previous
                      </Button>
                      <span className="text-xs text-slate-600">
                        Page {safePage} of {totalPages}
                      </span>
                      <Button
                        variant="outline"
                        size="sm"
                        disabled={safePage >= totalPages}
                        onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
                      >
                        Next
                      </Button>
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
    </div>
  )
}

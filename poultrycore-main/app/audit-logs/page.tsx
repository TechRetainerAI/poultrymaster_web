"use client"

import { useEffect, useMemo, useState } from "react"
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
import { useAuthStore } from "@/lib/store/auth-store"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"

interface AuditLog {
  id: string
  userId: string
  userName: string
  action: string
  resource: string
  resourceId: string
  details: string
  data?: string | null
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
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const [filterAction, setFilterAction] = useState("All")
  const [filterResource, setFilterResource] = useState("All")
  const [filterUser, setFilterUser] = useState("All")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [viewLog, setViewLog] = useState<AuditLog | null>(null)

  const prettyData = (raw?: string | null) => {
    if (!raw) return "—"
    try {
      return JSON.stringify(JSON.parse(raw), null, 2)
    } catch {
      return raw
    }
  }
  const hasActiveFilters =
    searchQuery !== "" || filterStatus !== "All" || filterAction !== "All" ||
    filterResource !== "All" || filterUser !== "All" || dateFrom !== "" || dateTo !== ""

  const clearFilters = () => {
    setSearchQuery("")
    setFilterStatus("All")
    setFilterAction("All")
    setFilterResource("All")
    setFilterUser("All")
    setDateFrom("")
    setDateTo("")
  }

  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }

  const handleLogout = () => {
    logout()
  }

  	useEffect(() => {
    const fetchLogs = async () => {
       // Farm proxy uses a 30s upstream timeout; allow headroom so we surface API errors instead of a false "timeout".
       const clientDeadlineMs = 45000
       const ac = new AbortController()
       const timeoutId = setTimeout(() => ac.abort(), clientDeadlineMs)
       const clearDeadline = () => clearTimeout(timeoutId)

       try {
         setLoading(true)
         setError("")
         
         console.log("Starting to fetch audit logs...")
         
         // Ensure apiClient has the token
         const token = localStorage.getItem("auth_token")
         console.log("Token exists:", !!token)
         
         if (token) {
           const { apiClient } = await import('@/lib/api/client')
           apiClient.setToken(token)
           console.log("Synced token with apiClient")
         }
         
         // Use the active farm from the auth store (reactive to company switches)
         const farmId = activeFarmId || localStorage.getItem("farmId") || ""

         if (!farmId) {
           clearDeadline()
           setError("Farm ID not found. Please log in again.")
           setLoading(false)
           return
         }
         
         // Was a single request capped at 200 rows, so anything older simply
         // never appeared and the totals under the table were wrong. Page
         // through until a short page comes back. The cap keeps a runaway loop
         // impossible if the API ever ignores paging.
         const CHUNK = 500
         const MAX_PAGES = 100
         const all: AuditLog[] = []
         for (let pageNo = 1; pageNo <= MAX_PAGES; pageNo++) {
           const batch = await AuditLogsService.getAll(
             { farmId, page: pageNo, pageSize: CHUNK },
             ac.signal
           )
           if (!Array.isArray(batch) || batch.length === 0) break
           all.push(...batch)
           if (batch.length < CHUNK) break
         }

         clearDeadline()
         setLogs(all)
         console.log(`Loaded ${all.length} audit logs`)
       } catch (err: unknown) {
         clearDeadline()
         console.error("Error loading audit logs:", err)
         const name = err instanceof Error ? err.name : ""
         if (name === "AbortError") {
           setError(
             "Request timed out after 45s. The Farm API may be cold-starting or the network is slow. Wait a moment and refresh, or check Cloud Run logs for poultrymaster-farm-api-git."
           )
         } else {
           const errorMsg =
             err instanceof Error ? err.message : "Failed to load audit logs. Please check your connection."
           setError(errorMsg)
         }
         setLogs([])
       } finally {
         setLoading(false)
       }
    }

    // Re-fetch when user or active company changes
    fetchLogs()
  }, [user, activeFarmId])

  // Options come from the rows actually loaded, so they always match what the
  // table can show.
  const actionOptions = useMemo(
    () => Array.from(new Set(logs.map((l) => (l.action || "").trim()).filter(Boolean))).sort(),
    [logs])
  const resourceOptions = useMemo(
    () => Array.from(new Set(logs.map((l) => (l.resource || "").trim()).filter(Boolean))).sort(),
    [logs])
  const userOptions = useMemo(
    () => Array.from(new Set(logs.map((l) => (l.userName || "").trim()).filter(Boolean))).sort(),
    [logs])

  const filteredLogs = useMemo(() => logs.filter((log) => {
    const q = searchQuery.trim().toLowerCase()
    const matchesSearch = !q ||
      (log.action || "").toLowerCase().includes(q) ||
      (log.resource || "").toLowerCase().includes(q) ||
      (log.userName || "").toLowerCase().includes(q) ||
      (log.details || "").toLowerCase().includes(q) ||
      (log.resourceId || "").toLowerCase().includes(q) ||
      (log.ipAddress || "").toLowerCase().includes(q)

    const matchesStatus = filterStatus === "All" || log.status === filterStatus
    const matchesAction = filterAction === "All" || log.action === filterAction
    const matchesResource = filterResource === "All" || log.resource === filterResource
    const matchesUser = filterUser === "All" || log.userName === filterUser

    // Dates are compared on the local calendar day so "from 24th" includes
    // everything logged that day, whatever the time.
    const day = log.timestamp ? new Date(log.timestamp) : null
    const dayKey = day && !Number.isNaN(day.getTime())
      ? `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, "0")}-${String(day.getDate()).padStart(2, "0")}`
      : ""
    const matchesFrom = !dateFrom || (dayKey && dayKey >= dateFrom)
    const matchesTo = !dateTo || (dayKey && dayKey <= dateTo)

    return matchesSearch && matchesStatus && matchesAction && matchesResource && matchesUser && matchesFrom && matchesTo
  }), [logs, searchQuery, filterStatus, filterAction, filterResource, filterUser, dateFrom, dateTo])

  const sortedLogs = sortData(filteredLogs, sortKey, sortDir, (item: any, key: string) => {
    if (key === "timestamp") return new Date(item.timestamp)
    return (item as any)[key]
  })
  // Same paging hook and footer every other table uses, so the rows-per-page
  // dropdown is here too.
  const pg = usePagination(sortedLogs, 10)
  const paginatedLogs = pg.pageItems

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
      
      <div className="flex-1 flex flex-col min-w-0">
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
                      <div className="space-y-2">
                        <Label>Action</Label>
                        <Select value={filterAction} onValueChange={setFilterAction}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="All">All actions</SelectItem>
                            {actionOptions.map((a) => <SelectItem key={a} value={a}>{friendlyAction(a)}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-2">
                        <Label>Resource</Label>
                        <Select value={filterResource} onValueChange={setFilterResource}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="All">All resources</SelectItem>
                            {resourceOptions.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-2">
                        <Label>User</Label>
                        <Select value={filterUser} onValueChange={setFilterUser}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="All">All users</SelectItem>
                            {userOptions.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="grid grid-cols-2 gap-2">
                        <div className="space-y-2">
                          <Label>From</Label>
                          <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                        </div>
                        <div className="space-y-2">
                          <Label>To</Label>
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
              ) : (
                <div className="flex flex-wrap items-center gap-2">
                  <Button variant={filterStatus === "All" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("All")}>All</Button>
                  <Button variant={filterStatus === "Success" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("Success")}>Success</Button>
                  <Button variant={filterStatus === "Failed" ? "default" : "outline"} size="sm" onClick={() => setFilterStatus("Failed")}>Failed</Button>

                  <Select value={filterAction} onValueChange={setFilterAction}>
                    <SelectTrigger className="w-[130px]"><SelectValue placeholder="Action" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="All">All actions</SelectItem>
                      {actionOptions.map((a) => <SelectItem key={a} value={a}>{friendlyAction(a)}</SelectItem>)}
                    </SelectContent>
                  </Select>

                  <Select value={filterResource} onValueChange={setFilterResource}>
                    <SelectTrigger className="w-[190px]"><SelectValue placeholder="Resource" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="All">All resources</SelectItem>
                      {resourceOptions.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}
                    </SelectContent>
                  </Select>

                  <Select value={filterUser} onValueChange={setFilterUser}>
                    <SelectTrigger className="w-[160px]"><SelectValue placeholder="User" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="All">All users</SelectItem>
                      {userOptions.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                    </SelectContent>
                  </Select>

                  <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[150px]" title="From date" />
                  <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[150px]" title="To date" />

                  {hasActiveFilters && (
                    <Button variant="ghost" size="sm" onClick={clearFilters}>Clear</Button>
                  )}
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
                                {log.data && (
                                  <div className="col-span-2">
                                    <span className="text-slate-500">Data</span>
                                    <button
                                      type="button"
                                      onClick={() => setViewLog(log)}
                                      className="ml-2 text-blue-600 hover:underline font-medium"
                                    >
                                      View data
                                    </button>
                                  </div>
                                )}
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
                        <TableHead>Data</TableHead>
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
                          <TableCell className="max-w-xs truncate bg-white">
                            {log.data ? (
                              <button
                                type="button"
                                onClick={() => setViewLog(log)}
                                className="text-blue-600 hover:underline font-medium"
                              >
                                View data
                              </button>
                            ) : (
                              "—"
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  </div>
                )}
                {!loading && !error && filteredLogs.length > 0 && (
                  <DataPagination {...pg.paginationProps} className="px-4 py-3 border-t bg-slate-50" />
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>

      <Dialog open={!!viewLog} onOpenChange={(open) => !open && setViewLog(null)}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[80vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle>Audit log data</DialogTitle>
            <DialogDescription>
              {viewLog
                ? `${friendlyAction(viewLog.action)} ${viewLog.resource} • ${formatDate(viewLog.timestamp)} • ${displayUser(viewLog.userName)}`
                : ""}
            </DialogDescription>
          </DialogHeader>
          <pre className="flex-1 overflow-auto rounded-md bg-slate-50 border p-3 text-xs font-mono whitespace-pre-wrap break-words text-slate-800">
            {prettyData(viewLog?.data)}
          </pre>
        </DialogContent>
      </Dialog>
    </div>
  )
}

"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Input } from "@/components/ui/input"
import { Calendar } from "@/components/ui/calendar"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { FileText, Plus, Calendar as CalendarIcon, Download, Search, X, RefreshCw, Loader2, ChevronDown, ChevronUp, Filter, Pencil, Trash2 } from "lucide-react"
import { getProductionRecords, deleteProductionRecord, type ProductionRecord } from "@/lib/api/production-record"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { ProductionForm } from "@/components/production/production-form"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { format } from "date-fns"
import { cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import jsPDF from "jspdf"
import autoTable from "jspdf-autotable"
import { sumLatestBirdsByFlock, sumLatestBirdsLeftByFlock } from "@/lib/utils/production-records"

export default function ProductionRecordsPage() {
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const [records, setRecords] = useState<ProductionRecord[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  // Filters
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [selectedFlockId, setSelectedFlockId] = useState<string>("ALL")
  const [selectedMonth, setSelectedMonth] = useState<string>("ALL")
  const [selectedYear, setSelectedYear] = useState<string>("ALL")

  // Pagination state
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage, setItemsPerPage] = useState(10)

  // Modal state
  const [formOpen, setFormOpen] = useState(false)
  const [editing, setEditing] = useState<ProductionRecord | null>(null)

  // Sort state
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<SortDirection>(null)

  // Mobile: compact view by default, button to show all columns; filters in sheet
  const isMobile = useIsMobile()
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const [filtersOpen, setFiltersOpen] = useState(false)

  const hasActiveFilters = search || dateFrom || dateTo || selectedFlockId !== "ALL" || selectedMonth !== "ALL" || selectedYear !== "ALL"

  const handleSort = (key: string) => {
    const result = toggleSort(key, sortKey, sortDirection)
    setSortKey(result.key)
    setSortDirection(result.direction)
  }

  useEffect(() => { load() }, [])

  const load = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }
    const [res, flocksRes] = await Promise.all([
      getProductionRecords(userId, farmId),
      getFlocks(userId, farmId),
    ])
    if (res.success && res.data) setRecords(res.data)
    else setError(res.message || "Failed to load records")
    if (flocksRes.success && flocksRes.data) setFlocks(flocksRes.data)
    setLoading(false)
  }

  const openDeleteDialog = (id: number) => {
    setDeletingId(id)
    setDeleteDialogOpen(true)
  }

  const handleDelete = async () => {
    if (!deletingId) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Error", description: "Farm ID or User ID not found.", variant: "destructive" })
      return
    }
    setIsDeleting(true)
    const res = await deleteProductionRecord(deletingId, userId, farmId)
    if (res.success) {
      toast({ title: "Record deleted", description: "The production record has been successfully deleted." })
      load()
    } else {
      toast({ title: "Delete failed", description: res.message || "Something went wrong. Please try again.", variant: "destructive" })
    }
    setIsDeleting(false)
    setDeleteDialogOpen(false)
    setDeletingId(null)
  }

  const handleLogout = () => {
    localStorage.clear()
    router.push("/login")
  }

  // Distinct flocks derived from current records
  const distinctFlocks = useMemo(() => {
    const map = new Map<string, { name: string }>()
    records.forEach((r: any) => {
      if (r.flockId && r.flockName) map.set(String(r.flockId), { name: r.flockName })
    })
    return Array.from(map.entries()).map(([id, v]) => ({ id, name: v.name }))
  }, [records])

  // Distinct months/years
  const { distinctMonths, distinctYears } = useMemo(() => {
    const monthSet = new Set<string>()
    const yearSet = new Set<string>()
    records.forEach((r) => {
      const d = new Date(r.date)
      const year = `${d.getFullYear()}`
      const month = `${year}-${String(d.getMonth() + 1).padStart(2, '0')}`
      monthSet.add(month)
      yearSet.add(year)
    })
    return { distinctMonths: Array.from(monthSet).sort().reverse(), distinctYears: Array.from(yearSet).sort().reverse() }
  }, [records])

  // Apply filters
  const filtered = useMemo(() => {
    let list = records.slice()
    if (search) {
      const q = search.toLowerCase()
      list = list.filter((r: any) => (
        r.flockName?.toLowerCase().includes(q) ||
        r.medication?.toLowerCase().includes(q) ||
        new Date(r.date).toLocaleDateString().toLowerCase().includes(q)
      ))
    }
    if (dateFrom) list = list.filter(r => r.date?.split('T')[0] >= dateFrom)
    if (dateTo) list = list.filter(r => r.date?.split('T')[0] <= dateTo)
    if (selectedFlockId !== "ALL") list = list.filter((r: any) => String(r.flockId) === selectedFlockId)
    if (selectedMonth !== "ALL") list = list.filter(r => {
      const d = new Date(r.date); const m = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`; return m === selectedMonth
    })
    if (selectedYear !== "ALL") list = list.filter(r => new Date(r.date).getFullYear().toString() === selectedYear)
    return list
  }, [records, search, dateFrom, dateTo, selectedFlockId, selectedMonth, selectedYear])

  // Summaries
  const totalEggs = useMemo(() => filtered.reduce((s, r) => s + (Number(r.totalProduction) || 0), 0), [filtered])
  const totalFeed = useMemo(() => filtered.reduce((s, r) => s + (Number(r.feedKg) || 0), 0), [filtered])
  const totalDeaths = useMemo(() => filtered.reduce((s, r) => s + (Number(r.mortality) || 0), 0), [filtered])
  const total9AM = useMemo(() => filtered.reduce((s, r) => s + (Number(r.production9AM) || 0), 0), [filtered])
  const total12PM = useMemo(() => filtered.reduce((s, r) => s + (Number(r.production12PM) || 0), 0), [filtered])
  const total4PM = useMemo(() => filtered.reduce((s, r) => s + (Number(r.production4PM) || 0), 0), [filtered])
  const totalBrokens = useMemo(() => filtered.reduce((s, r) => s + (Number((r as any).brokenEggs) || 0), 0), [filtered])

  // Use the same latest-per-flock selector for both totals, so cards stay consistent.
  const totalBirds = useMemo(() => sumLatestBirdsByFlock(filtered), [filtered])

  // Birds Left: sum latest noOfBirdsLeft per flock (James's rule).
  const totalBirdsLeft = useMemo(() => sumLatestBirdsLeftByFlock(filtered), [filtered])
  const avgEggsPerRecord = useMemo(() => filtered.length ? Math.round(totalEggs / filtered.length) : 0, [filtered, totalEggs])
  const EGGS_PER_CRATE = 30
  const totalEggsCrates = Math.floor(totalEggs / EGGS_PER_CRATE)
  const totalEggsPieces = totalEggs % EGGS_PER_CRATE

  // Sort filtered data
  const sortedFiltered = useMemo(() => {
    return sortData(filtered, sortKey, sortDirection, (item: any, key: string) => {
      switch (key) {
        case "date": return new Date(item.date)
        case "flockId": return item.flockId ?? 0
        case "age": return item.ageInDays ?? 0
        case "production9AM": return Number(item.production9AM) || 0
        case "production12PM": return Number(item.production12PM) || 0
        case "production4PM": return Number(item.production4PM) || 0
        case "brokenEggs": return Number(item.brokenEggs) || 0
        case "totalProduction": return Number(item.totalProduction) || 0
        case "eggPercent": {
          const b = Number(item.noOfBirds) || 0
          const t = Number(item.totalProduction) || 0
          return b ? (t / b) * 100 : 0
        }
        case "feedKg": return Number(item.feedKg) || 0
        case "noOfBirds": return Number(item.noOfBirds) || 0
        case "mortality": return Number(item.mortality) || 0
        case "left": return (Number(item.noOfBirds) || 0) - (Number(item.mortality) || 0)
        case "medication": return item.medication || ""
        default: return (item as any)[key]
      }
    })
  }, [filtered, sortKey, sortDirection])

  // Pagination logic
  const totalPages = Math.ceil(sortedFiltered.length / itemsPerPage)
  const startIndex = (currentPage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const paginatedRecords = useMemo(() => sortedFiltered.slice(startIndex, endIndex), [sortedFiltered, startIndex, endIndex])

  // Reset to page 1 when filters change
  useEffect(() => {
    setCurrentPage(1)
  }, [search, dateFrom, dateTo, selectedFlockId, selectedMonth, selectedYear])

  const handlePageChange = (page: number) => {
    setCurrentPage(page)
  }

  const handlePreviousPage = () => {
    if (currentPage > 1) setCurrentPage(currentPage - 1)
  }

  const handleNextPage = () => {
    if (currentPage < totalPages) setCurrentPage(currentPage + 1)
  }

  const getPageNumbers = () => {
    const pages: (number | string)[] = []
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) pages.push(i)
    } else {
      if (currentPage <= 3) {
        for (let i = 1; i <= 4; i++) pages.push(i)
        pages.push('ellipsis')
        pages.push(totalPages)
      } else if (currentPage >= totalPages - 2) {
        pages.push(1)
        pages.push('ellipsis')
        for (let i = totalPages - 3; i <= totalPages; i++) pages.push(i)
      } else {
        pages.push(1)
        pages.push('ellipsis')
        for (let i = currentPage - 1; i <= currentPage + 1; i++) pages.push(i)
        pages.push('ellipsis')
        pages.push(totalPages)
      }
    }
    return pages
  }

  const formatDateShort = (d: string | Date) => {
    const dt = typeof d === 'string' ? new Date(d) : d
    return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' })
  }

  const formatAge = (r: any) => {
    const daysRaw = Number(r.ageInDays ?? r.ageDays)
    const weeksRaw = Number(r.ageInWeeks ?? r.ageWeeks)
    const d = daysRaw || (weeksRaw ? weeksRaw * 7 : 0)
    if (!d) return "-"
    const y = Math.floor(d / 365)
    const w = Math.floor((d % 365) / 7)
    const dd = d % 7
    return `${y} yr ${w} wk ${dd} d (${d} days)`
  }

  const clearFilters = () => {
    setSearch("")
    setDateFrom("")
    setDateTo("")
    setSelectedFlockId("ALL")
    setSelectedMonth("ALL")
    setSelectedYear("ALL")
  }

  const exportCsv = () => {
    const headers = [
      "Date","FlockId","Age","9am","12pm","4pm","Total","EggPercent","FeedKg","Birds","Deaths","Left","Medication"
    ]
    const rows = filtered.map((r: any) => [
      new Date(r.date).toLocaleDateString(),
      r.flockId ?? "",
      formatAge(r),
      r.production9AM ?? 0,
      r.production12PM ?? 0,
      r.production4PM ?? 0,
      r.totalProduction ?? 0,
      (() => { const b = Number(r.noOfBirds)||0; const t = Number(r.totalProduction)||0; return b? ((t/b)*100).toFixed(1):"" })(),
      r.feedKg ?? 0,
      r.noOfBirds ?? 0,
      r.mortality ?? 0,
      (Number(r.noOfBirds) || 0) - (Number(r.mortality) || 0),
      r.medication || "",
    ])
    const csv = [headers, ...rows].map(r => r.map(v => typeof v === 'string' && v.includes(',') ? `"${v}"` : v).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `production-${new Date().toISOString().slice(0,10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const exportPdf = () => {
    if (filtered.length === 0) {
      alert("No records to export. Adjust your filters.")
      return
    }

    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" })
    const farmName = localStorage.getItem("farmName") || "Farm"
    const today = new Date().toLocaleDateString()

    // Title
    doc.setFontSize(16)
    doc.setTextColor(33, 37, 41)
    doc.text(`${farmName} - Egg Production Report`, 14, 18)
    doc.setFontSize(10)
    doc.setTextColor(100, 100, 100)
    doc.text(`Generated: ${today}  |  Records: ${filtered.length}`, 14, 25)

    // Summary row
    doc.setFontSize(9)
    doc.text(
      `Total Eggs: ${totalEggs.toLocaleString()} (${totalEggsCrates} crates + ${totalEggsPieces} pcs)  |  Feed: ${totalFeed.toFixed(2)} kg  |  Deaths: ${totalDeaths}  |  Birds: ${totalBirds}  |  Left: ${totalBirdsLeft}`,
      14, 31
    )

    // Table
    const headers = [
      "Date", "Flock", "Age", "9am", "12pm", "4pm", "Total", "Egg%", "Feed(kg)", "Birds", "Deaths", "Left", "Medication"
    ]

    const rows = filtered.map((r: any) => {
      const b = Number(r.noOfBirds) || 0
      const t = Number(r.totalProduction) || 0
      const m = Number(r.mortality) || 0
      const eggPct = b ? ((t / b) * 100).toFixed(1) + "%" : "-"
      return [
        new Date(r.date).toLocaleDateString(),
        r.flockId != null ? `#${r.flockId}` : "-",
        formatAge(r),
        r.production9AM ?? 0,
        r.production12PM ?? 0,
        r.production4PM ?? 0,
        r.totalProduction ?? 0,
        eggPct,
        (r.feedKg ?? 0).toFixed ? Number(r.feedKg).toFixed(2) : r.feedKg,
        b,
        m,
        b - m,
        r.medication || "-",
      ]
    })

    // Add totals row
    rows.push([
      "TOTALS", "", "",
      total9AM, total12PM, total4PM,
      `${totalEggs} (${totalEggsCrates}c+${totalEggsPieces}p)`,
      "", totalFeed.toFixed(2),
      totalBirds, totalDeaths, totalBirdsLeft, ""
    ])

    autoTable(doc, {
      startY: 35,
      head: [headers],
      body: rows,
      styles: { fontSize: 7, cellPadding: 1.5 },
      headStyles: { fillColor: [37, 99, 235], textColor: 255, fontStyle: "bold", fontSize: 7 },
      alternateRowStyles: { fillColor: [248, 250, 252] },
      footStyles: { fillColor: [226, 232, 240], textColor: [30, 41, 59], fontStyle: "bold" },
      columnStyles: {
        0: { cellWidth: 22 },
        2: { cellWidth: 28 },
        12: { cellWidth: 22 },
      },
      didParseCell: (data: any) => {
        // Bold the last (totals) row
        if (data.row.index === rows.length - 1) {
          data.cell.styles.fontStyle = "bold"
          data.cell.styles.fillColor = [226, 232, 240]
        }
      },
    })

    doc.save(`production-${new Date().toISOString().slice(0, 10)}.pdf`)
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-x-hidden px-2 py-4 sm:p-6 pb-20 lg:pb-4">
          <div className="space-y-4 sm:space-y-6 min-w-0 w-full">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-emerald-100 rounded-lg flex items-center justify-center">
                  <FileText className="w-5 h-5 text-emerald-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Production Records</h1>
                  <p className="text-sm text-slate-600">Track daily egg production and performance metrics</p>
                </div>
              </div>
              <Button className="gap-2 shrink-0 w-full sm:w-auto h-11 sm:h-10 bg-emerald-600 hover:bg-emerald-700" onClick={() => router.push("/production-records/new")}>
                <Plus className="w-4 h-4" /> Log Production
              </Button>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Filters - Mobile: Sheet; Desktop: Inline */}
            {isMobile ? (
              <div className="space-y-3 w-full min-w-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search records..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-10 h-11" />
                </div>
                <div className="flex gap-2 items-stretch min-w-0 w-full">
                  <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                    <SheetTrigger asChild>
                      <Button variant="outline" className="flex-1 min-w-0 h-11 gap-2 justify-start">
                        <Filter className="h-4 w-4" />
                        <span className="truncate">Filters</span>
                        {hasActiveFilters && (
                          <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-orange-500 text-white text-xs flex items-center justify-center">
                            {[search, dateFrom, dateTo, selectedFlockId !== "ALL", selectedMonth !== "ALL", selectedYear !== "ALL"].filter(Boolean).length}
                          </span>
                        )}
                      </Button>
                    </SheetTrigger>
                    <SheetContent side="bottom" className="h-[85vh] rounded-t-2xl">
                      <SheetHeader>
                        <SheetTitle>Filters</SheetTitle>
                      </SheetHeader>
                      <div className="space-y-4 overflow-y-auto pb-8">
                        <div>
                          <label className="text-sm font-medium text-slate-700 mb-1 block">Date range</label>
                          <div className="grid grid-cols-2 gap-2">
                            <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                            <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                          </div>
                        </div>
                        <div>
                          <label className="text-sm font-medium text-slate-700 mb-1 block">Flock</label>
                          <Select value={selectedFlockId} onValueChange={setSelectedFlockId}>
                            <SelectTrigger><SelectValue placeholder="All Flocks" /></SelectTrigger>
                            <SelectContent>
                              <SelectItem value="ALL">All Flocks</SelectItem>
                              {flocks.map(f => (
                                <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name} ({f.quantity} birds)</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="grid grid-cols-2 gap-2">
                          <div>
                            <label className="text-sm font-medium text-slate-700 mb-1 block">Month</label>
                            <Select value={selectedMonth} onValueChange={setSelectedMonth}>
                              <SelectTrigger><SelectValue placeholder="All" /></SelectTrigger>
                              <SelectContent>
                                <SelectItem value="ALL">All Months</SelectItem>
                                {distinctMonths.map((m) => {
                                  const [y, mm] = m.split('-'); const d = new Date(parseInt(y), parseInt(mm) - 1)
                                  return <SelectItem key={m} value={m}>{d.toLocaleDateString('en-US', { month: 'short' })}</SelectItem>
                                })}
                              </SelectContent>
                            </Select>
                          </div>
                          <div>
                            <label className="text-sm font-medium text-slate-700 mb-1 block">Year</label>
                            <Select value={selectedYear} onValueChange={setSelectedYear}>
                              <SelectTrigger><SelectValue placeholder="All" /></SelectTrigger>
                              <SelectContent>
                                <SelectItem value="ALL">All</SelectItem>
                                {distinctYears.map((y) => (
                                  <SelectItem key={y} value={y}>{y}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        </div>
                        <div className="flex gap-2 pt-4">
                          <Button variant="outline" className="flex-1" onClick={clearFilters}>Clear all</Button>
                          <Button className="flex-1" onClick={() => setFiltersOpen(false)}>Apply</Button>
                        </div>
                      </div>
                    </SheetContent>
                  </Sheet>
                  <div className="flex gap-2 flex-1 min-w-0">
                    <Button variant="outline" size="sm" onClick={exportCsv} className="flex-1 min-w-0 h-11">CSV</Button>
                    <Button size="sm" onClick={exportPdf} className="flex-1 min-w-0 h-11">PDF</Button>
                  </div>
                </div>
              </div>
            ) : (
              <div className="flex flex-row flex-wrap items-center gap-2 p-2 bg-white rounded-lg border">
                <div className="relative w-[240px] min-w-0">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                </div>
                <Input type="date" placeholder="From" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" />
                <Input type="date" placeholder="To" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" />
                <Select value={selectedFlockId} onValueChange={setSelectedFlockId}>
                  <SelectTrigger className="w-[180px]"><SelectValue placeholder="Flock" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Flocks</SelectItem>
                    {flocks.map(f => (
                      <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name} ({f.quantity} birds)</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select value={selectedMonth} onValueChange={setSelectedMonth}>
                  <SelectTrigger className="w-[120px]"><SelectValue placeholder="Month" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Months</SelectItem>
                    {distinctMonths.map((m) => {
                      const [y, mm] = m.split('-'); const d = new Date(parseInt(y), parseInt(mm) - 1)
                      return <SelectItem key={m} value={m}>{d.toLocaleDateString('en-US', { month: 'long' })}</SelectItem>
                    })}
                  </SelectContent>
                </Select>
                <Select value={selectedYear} onValueChange={setSelectedYear}>
                  <SelectTrigger className="w-[100px]"><SelectValue placeholder="Year" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All</SelectItem>
                    {distinctYears.map((y) => (
                      <SelectItem key={y} value={y}>{y}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <div className="ml-auto flex items-center gap-2">
                  <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                  <Button variant="outline" size="sm" onClick={exportCsv}><Download className="h-4 w-4 mr-2" /> Export CSV</Button>
                  <Button size="sm" onClick={exportPdf}><Download className="h-4 w-4 mr-2" /> Export PDF</Button>
                </div>
              </div>
            )}

            {/* Metrics - Mobile: 2-col grid, larger touch targets */}
            {!loading && (
              <div className={cn(
                "grid gap-3",
                isMobile ? "grid-cols-2" : "grid-cols-1 sm:grid-cols-2 xl:grid-cols-6"
              )}>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Total Eggs</div>
                  <div className={cn("font-bold text-emerald-600", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalEggs.toLocaleString()}</div>
                  <div className="text-xs text-slate-400 mt-0.5">{totalEggsCrates}c + {totalEggsPieces}p</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Avg / Record</div>
                  <div className={cn("font-bold text-slate-900", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{avgEggsPerRecord.toLocaleString()}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Feed (kg)</div>
                  <div className={cn("font-bold text-slate-900", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalFeed.toFixed(2)}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Deaths</div>
                  <div className={cn("font-bold text-red-600", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalDeaths.toLocaleString()}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Total Birds</div>
                  <div className={cn("font-bold text-slate-900", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalBirds.toLocaleString()}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Birds Left</div>
                  <div className={cn("font-bold text-emerald-700", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalBirdsLeft.toLocaleString()}</div>
                </div>
              </div>
            )}

            {/* Table */}
            {loading ? (
              <Card className="bg-white"><CardContent className="py-6">
                <div className="space-y-3">
                  {[...Array(5)].map((_, i) => (
                    <div key={i} className="h-10 w-full bg-slate-50 animate-pulse rounded" />
                  ))}
                </div>
              </CardContent></Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  {/* Mobile: Card list (default) or Table (when "View table" tapped) */}
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {paginatedRecords.length === 0 ? (
                        <div className="py-16 px-4 text-center">
                          <p className="text-slate-500 mb-4">No records found</p>
                          <Button onClick={() => { setEditing(null); setFormOpen(true) }}>Log one now</Button>
                        </div>
                      ) : (
                        paginatedRecords.map((r: any, idx: number) => (
                          <Collapsible
                            key={r.id}
                            className={cn(
                              "group w-full rounded-xl border shadow-sm overflow-hidden",
                              idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200"
                            )}
                          >
                            <div className={cn("px-2.5 py-3 transition-colors", idx % 2 === 1 && "active:bg-black/5", idx % 2 === 0 && "active:bg-black/10")}>
                              <CollapsibleTrigger asChild>
                                <div className="flex items-start justify-between gap-3 cursor-pointer">
                                  <div className="min-w-0 flex-1">
                                    <div className="flex items-center gap-2">
                                      <span className="font-semibold text-slate-900">{formatDateShort(r.date)}</span>
                                      <span className="text-slate-500">•</span>
                                      <span className="text-slate-600 truncate">{r.flockId != null ? `Flock #${r.flockId}` : "—"}</span>
                                    </div>
                                    <div className="mt-3 grid grid-cols-2 gap-2">
                                      <div className="rounded-lg bg-emerald-100 border border-emerald-300 px-3 py-2 shadow-sm">
                                        <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">Eggs</p>
                                        <p className="text-xl font-extrabold text-emerald-800 leading-tight">{(r.totalProduction ?? 0).toLocaleString()}</p>
                                      </div>
                                      <div className="rounded-lg bg-blue-100 border border-blue-300 px-3 py-2 shadow-sm">
                                        <p className="text-[11px] font-semibold uppercase tracking-wide text-blue-900">Birds Left</p>
                                        <p className="text-xl font-extrabold text-blue-800 leading-tight">{((Number(r.noOfBirds) || 0) - (Number(r.mortality) || 0)).toLocaleString()}</p>
                                      </div>
                                      {r.medication && r.medication !== "-" && (
                                        <div className="col-span-2 rounded-lg bg-violet-100 border border-violet-300 px-3 py-2 shadow-sm">
                                          <p className="text-[11px] font-semibold uppercase tracking-wide text-violet-900">Medication</p>
                                          <p className="text-sm font-medium text-violet-900 truncate">{r.medication}</p>
                                        </div>
                                      )}
                                    </div>
                                  </div>
                                  <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                                </div>
                              </CollapsibleTrigger>
                              <CollapsibleContent>
                                <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                  <div className="grid grid-cols-2 gap-2">
                                    <div><span className="text-slate-500">9am</span> <span className="font-medium text-blue-700">{r.production9AM ?? 0}</span></div>
                                    <div><span className="text-slate-500">12pm</span> <span className="font-medium text-orange-700">{r.production12PM ?? 0}</span></div>
                                    <div><span className="text-slate-500">4pm</span> <span className="font-medium text-purple-700">{r.production4PM ?? 0}</span></div>
                                    <div><span className="text-slate-500">Feed</span> <span className="font-medium">{(r.feedKg ?? 0).toFixed ? (r.feedKg ?? 0).toFixed(2) : r.feedKg} kg</span></div>
                                    <div><span className="text-slate-500">Deaths</span> <span className={cn("font-medium", (r.mortality ?? 0) > 0 ? "text-red-600" : "")}>{r.mortality ?? 0}</span></div>
                                    <div><span className="text-slate-500">Age</span> <span className="text-slate-700 truncate">{formatAge(r)}</span></div>
                                  </div>
                                  <div className="flex gap-2 pt-2">
                                    <Button variant="outline" size="sm" className="flex-1 h-10" onClick={(e) => { e.stopPropagation(); setEditing(r); setFormOpen(true) }}>
                                      <Pencil className="h-4 w-4 mr-2" /> Edit
                                    </Button>
                                    {permissions.canDelete && (
                                      <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={(e) => { e.stopPropagation(); openDeleteDialog(r.id) }}>
                                        <Trash2 className="h-4 w-4 mr-2" /> Delete
                                      </Button>
                                    )}
                                  </div>
                                </div>
                              </CollapsibleContent>
                            </div>
                          </Collapsible>
                        ))
                      )}
                      {isMobile && paginatedRecords.length > 0 && (
                        <div className="px-4 py-3 bg-slate-50/50 border-t">
                          <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowAllColumnsMobile(true)}>
                            View table format <ChevronDown className="h-4 w-4 ml-1" />
                          </Button>
                        </div>
                      )}
                    </div>
                  ) : (
                  <div className={cn("overflow-x-auto overflow-y-visible table-scroll-wrapper", isMobile && "pb-2")} style={{ WebkitOverflowScrolling: 'touch' }}>
                    {isMobile && (
                      <>
                        <div className="px-4 py-2 border-b bg-slate-50 flex items-center justify-between gap-2 sticky top-0 z-10">
                          <span className="text-xs text-slate-600">Table view • Scroll → for more</span>
                          <Button variant="ghost" size="sm" onClick={() => setShowAllColumnsMobile(false)}>
                            <ChevronUp className="h-4 w-4 mr-1" /> Cards
                          </Button>
                        </div>
                      </>
                    )}
                    <Table className={cn("min-w-[1400px]", isMobile && "min-w-[1200px]")}>
                      <TableHeader className="sticky top-0 bg-blue-50 z-10">
                        <TableRow className="border-b border-blue-200">
                          <SortableHeader label="Date" sortKey="date" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className={cn("min-w-[100px] px-3 py-2", isMobile && "sticky-col-date bg-blue-50")} />
                          <SortableHeader label="Flock" sortKey="flockId" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className={cn("min-w-[70px] px-3 py-2", isMobile && "sticky-col-flock bg-blue-50")} />
                          <SortableHeader label="Age" sortKey="age" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="min-w-[170px] px-3 py-2" />
                          <SortableHeader label="9am" sortKey="production9AM" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-blue-100 text-blue-900 font-semibold" />
                          <SortableHeader label="12pm" sortKey="production12PM" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-orange-100 text-orange-900 font-semibold" />
                          <SortableHeader label="4pm" sortKey="production4PM" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-purple-100 text-purple-900 font-semibold" />
                          <SortableHeader label="Brokens" sortKey="brokenEggs" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-red-50 text-red-800 font-semibold" />
                          <SortableHeader label="Total" sortKey="totalProduction" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2" />
                          <SortableHeader label="Egg%" sortKey="eggPercent" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2" />
                          <SortableHeader label="Feed" sortKey="feedKg" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2" />
                          <SortableHeader label="Birds" sortKey="noOfBirds" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2" />
                          <SortableHeader label="Deaths" sortKey="mortality" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[72px] px-3 py-2 whitespace-nowrap" />
                          <SortableHeader label="Left" sortKey="left" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[70px] px-3 py-2 whitespace-nowrap" />
                          <SortableHeader label="Meds" sortKey="medication" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="min-w-[100px] px-3 py-2 whitespace-nowrap" />
                          <TableHead className={cn("text-left min-w-[130px] px-3 py-2 whitespace-nowrap", isMobile && "sticky-col-actions bg-blue-50")}>Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {paginatedRecords.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={15} className="py-12 text-center text-slate-500">
                              No records found for the selected filters.
                              <Button variant="link" className="ml-1" onClick={() => { setEditing(null); setFormOpen(true) }}>Log one now</Button>
                            </TableCell>
                          </TableRow>
                        ) : paginatedRecords.map((r: any, idx: number) => (
                          <TableRow
                            key={r.id}
                            className={cn(
                              "hover:bg-slate-50/60",
                              idx % 2 === 0 ? "bg-white" : "bg-slate-50/40"
                            )}
                          >
                            <TableCell className={cn("px-3 py-2 whitespace-nowrap min-w-[100px]", isMobile && "sticky-col-date bg-white")}>{isMobile ? formatDateShort(r.date) : new Date(r.date).toLocaleDateString()}</TableCell>
                            <TableCell className={cn("px-3 py-2 whitespace-nowrap min-w-[70px]", isMobile && "sticky-col-flock bg-white")}>{r.flockId != null ? `#${r.flockId}` : "-"}</TableCell>
                            <TableCell className="px-3 py-2">{formatAge(r)}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-blue-700 bg-blue-50/40 rounded-sm">{r.production9AM ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-orange-700 bg-orange-50/40 rounded-sm">{r.production12PM ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-purple-700 bg-purple-50/40 rounded-sm">{r.production4PM ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-red-700 bg-red-50/40 rounded-sm">{(r as any).brokenEggs ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 font-semibold text-slate-900">{r.totalProduction ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2">{(() => { const b = Number(r.noOfBirds)||0; const t = Number(r.totalProduction)||0; return b? ((t/b)*100).toFixed(1)+"%":"-" })()}</TableCell>
                            <TableCell className="text-right px-3 py-2">{(r.feedKg ?? 0).toFixed ? r.feedKg.toFixed(2) : r.feedKg}</TableCell>
                            <TableCell className="text-right px-3 py-2">{r.noOfBirds ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2">
                              <span className={cn("px-2 py-0.5 rounded text-xs", (r.mortality ?? 0) > 0 ? "bg-red-50 text-red-700" : "bg-slate-50 text-slate-600")}>{r.mortality ?? 0}</span>
                            </TableCell>
                            <TableCell className="text-right px-3 py-2">{(Number(r.noOfBirds) || 0) - (Number(r.mortality) || 0)}</TableCell>
                            <TableCell className="px-3 py-2">{r.medication || "-"}</TableCell>
                            <TableCell className={cn("text-left px-3 py-2 whitespace-nowrap", isMobile && "sticky-col-actions bg-white")}>
                              <div className="flex items-center gap-1 min-w-[110px]">
                                <Button variant="ghost" size="sm" className="shrink-0" onClick={() => { setEditing(r); setFormOpen(true) }}>Edit</Button>
                                {permissions.canDelete && (
                                  <Button variant="ghost" size="sm" className="text-red-600 shrink-0" onClick={() => openDeleteDialog(r.id)}>Delete</Button>
                                )}
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                        {filtered.length > 0 && (
                          <TableRow className="bg-slate-50/60">
                            <TableCell className={cn("font-semibold text-xs px-3 py-2 bg-slate-50", isMobile && "sticky-col-date")}>Totals</TableCell>
                            <TableCell className={cn("bg-slate-50", isMobile && "sticky-col-flock")}></TableCell>
                            <TableCell></TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2 text-blue-800 bg-blue-50 border border-blue-100 rounded">{total9AM.toLocaleString()}<div className="text-xs font-normal text-blue-600">{Math.floor(total9AM / EGGS_PER_CRATE)}c + {total9AM % EGGS_PER_CRATE}p</div></TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2 text-orange-800 bg-orange-50 border border-orange-100 rounded">{total12PM.toLocaleString()}<div className="text-xs font-normal text-orange-600">{Math.floor(total12PM / EGGS_PER_CRATE)}c + {total12PM % EGGS_PER_CRATE}p</div></TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2 text-purple-800 bg-purple-50 border border-purple-100 rounded">{total4PM.toLocaleString()}<div className="text-xs font-normal text-purple-600">{Math.floor(total4PM / EGGS_PER_CRATE)}c + {total4PM % EGGS_PER_CRATE}p</div></TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2 text-red-700 bg-red-50 border border-red-100 rounded">{totalBrokens.toLocaleString()}<div className="text-xs font-normal text-red-500">{Math.floor(totalBrokens / EGGS_PER_CRATE)}c + {totalBrokens % EGGS_PER_CRATE}p</div></TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2 text-emerald-700">{totalEggs.toLocaleString()}<div className="text-xs font-normal text-slate-500">{totalEggsCrates}c + {totalEggsPieces}p</div></TableCell>
                            <TableCell></TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2">{totalFeed.toFixed(2)}</TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2 text-slate-700">{totalBirds.toLocaleString()}</TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2 text-red-700">{totalDeaths.toLocaleString()}</TableCell>
                            <TableCell className="text-right font-semibold px-3 py-2 text-emerald-700">{totalBirdsLeft.toLocaleString()}</TableCell>
                            <TableCell></TableCell>
                            <TableCell className={cn("bg-slate-50", isMobile && "sticky-col-actions")}></TableCell>
                          </TableRow>
                        )}
                      </TableBody>
                    </Table>
                  </div>
                  )}
                </CardContent>
              </Card>
            )}

            {/* Pagination */}
            {!loading && filtered.length > 0 && totalPages > 1 && (
            <div className="flex flex-col sm:flex-row items-center justify-between gap-4 mt-2">
                <div className="flex items-center gap-4">
                  <span className="text-sm text-slate-600">
                    Showing {startIndex + 1} to {Math.min(endIndex, sortedFiltered.length)} of {sortedFiltered.length} records
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

            {/* Summary footer to mirror client - hidden on mobile to save space */}
            {!loading && (
              <div className="hidden md:grid grid-cols-1 md:grid-cols-5 gap-2 mt-2">
                <div className="p-2 bg-muted/30 rounded border"><div className="text-xs">Average Egg %:</div><div className="text-lg font-bold text-emerald-700">{(() => { const percents = filtered.map((r: any)=>{const b=Number(r.noOfBirds)||0;const t=Number(r.totalProduction)||0;return b? (t/b)*100:null}).filter(Boolean) as number[]; const v = percents.length? percents.reduce((a,b)=>a+b,0)/percents.length:0; return v.toFixed(1)+'%'; })()}</div></div>
                <div className="p-2 bg-muted/30 rounded border"><div className="text-xs">Avg Total Eggs:</div><div className="text-lg font-bold">{avgEggsPerRecord}</div></div>
                <div className="p-2 bg-muted/30 rounded border"><div className="text-xs">Total Deaths:</div><div className="text-lg font-bold text-red-600">{totalDeaths.toLocaleString()}</div></div>
                <div className="p-2 bg-muted/30 rounded border"><div className="text-xs">Total Eggs:</div><div className="text-lg font-bold">{totalEggs.toLocaleString()}</div></div>
                <div className="p-2 bg-muted/30 rounded border"><div className="text-xs">Total Crates:</div><div className="text-lg font-bold">{Math.floor(totalEggs/30).toLocaleString()}</div></div>
              </div>
            )}

          </div>
        </main>
      </div>

      <ProductionForm open={formOpen} onOpenChange={setFormOpen} record={editing} onSaved={load} />

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Production Record</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this production record? This action cannot be undone.
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
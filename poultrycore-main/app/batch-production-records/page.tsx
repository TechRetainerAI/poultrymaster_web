"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { BatchProductionRecordModal } from "@/components/production/batch-production-record-modal"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Plus, Download, Search, RefreshCw, Loader2, ChevronDown, ChevronUp, Filter, Mail, Layers } from "lucide-react"
import { sendReportEmail } from "@/lib/api/email"
import {
  getBatchProductionRecords,
  deleteBatchProductionRecord,
  deleteBatchAllocation,
  setBatchStatus,
  reverseBatchProduction,
  postBatchAllocation,
  BATCH_STATUS_LABELS,
  batchNameLabel,
  batchScopeLabel,
  type ProductionBatchRecord,
  type BatchStatus,
} from "@/lib/api/production-batch"
import { getUserContext } from "@/lib/utils/user-context"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { cn } from "@/lib/utils"
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
import { toLocalDateKey } from "@/lib/utils/date-key"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import jsPDF from "jspdf"
import autoTable from "jspdf-autotable"

const ALL_STATUSES: BatchStatus[] = ["Draft", "PendingAllocation", "Allocated", "Posted", "Reversed", "Cancelled"]

const STATUS_BADGE_CLASS: Record<BatchStatus, string> = {
  PendingAllocation: "bg-amber-100 text-amber-800 border border-amber-200",
  Allocated: "bg-blue-100 text-blue-800 border border-blue-200",
  Posted: "bg-emerald-100 text-emerald-800 border border-emerald-200",
  Reversed: "bg-slate-100 text-slate-700 border border-slate-200",
  Draft: "bg-gray-100 text-gray-700 border border-gray-200",
  Cancelled: "bg-red-100 text-red-700 border border-red-200",
}

// Stable per-batch key for the Batch filter: prefer the bird-batch id
// (SpecificBatch records), else group by scope type + name so the AllBatches /
// CustomBatch entries still collapse into stable, selectable options.
const batchFilterKey = (r: ProductionBatchRecord): string =>
  r.selectedBirdBatchId != null
    ? `b:${r.selectedBirdBatchId}`
    : `t:${r.batchSelectionType}:${(r.batchName || "").trim().toLowerCase()}`

type ConfirmType = "delete" | "post" | "reverse" | "cancel" | "deleteAllocation"

interface ConfirmState {
  type: ConfirmType
  id: number
  title: string
  description: string
  actionLabel: string
}

export default function BatchProductionRecordsPage() {
  // Add/Edit open in the wide modal by default; the full-page routes remain
  // reachable from inside it via "Open Full Page".
  const [formOpen, setFormOpen] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const [records, setRecords] = useState<ProductionBatchRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  // Confirm dialog (shared for delete / post / reverse / cancel)
  const [confirm, setConfirm] = useState<ConfirmState | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)

  // Filters
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [selectedStatus, setSelectedStatus] = useState<string>("ALL")
  const [selectedBatch, setSelectedBatch] = useState<string>("ALL")
  const [selectedMonth, setSelectedMonth] = useState<string>("ALL")
  const [selectedYear, setSelectedYear] = useState<string>("ALL")

  // Pagination state
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage, setItemsPerPage] = useState(10)

  // Sort state
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<SortDirection>(null)

  // Mobile: compact view by default, button to show all columns; filters in sheet
  const isMobile = useIsMobile()
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const [filtersOpen, setFiltersOpen] = useState(false)

  /** Mobile sheet: draft values until Apply. */
  const [draftDateFrom, setDraftDateFrom] = useState("")
  const [draftDateTo, setDraftDateTo] = useState("")
  const [draftStatus, setDraftStatus] = useState<string>("ALL")
  const [draftBatch, setDraftBatch] = useState<string>("ALL")
  const [draftMonth, setDraftMonth] = useState<string>("ALL")
  const [draftYear, setDraftYear] = useState<string>("ALL")

  const hasActiveFilters = search || dateFrom || dateTo || selectedStatus !== "ALL" || selectedBatch !== "ALL" || selectedMonth !== "ALL" || selectedYear !== "ALL"
  const hasDraftChanges =
    draftDateFrom !== dateFrom ||
    draftDateTo !== dateTo ||
    draftStatus !== selectedStatus ||
    draftBatch !== selectedBatch ||
    draftMonth !== selectedMonth ||
    draftYear !== selectedYear

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
    const res = await getBatchProductionRecords(userId, farmId)
    if (res.success && res.data) {
      setRecords(res.data)
      setError("")
    } else setError(res.message || "Failed to load records")
    setLoading(false)
  }

  const handleLogout = () => {
    localStorage.clear()
    router.push("/login")
  }

  // ---- Action handlers (all route through the shared confirm dialog) ----

  const openDelete = (r: ProductionBatchRecord) =>
    setConfirm({ type: "delete", id: r.id, title: "Delete Batch Record", description: "Are you sure you want to delete this batch production record? This action cannot be undone.", actionLabel: "Delete" })

  const openPost = (r: ProductionBatchRecord) =>
    setConfirm({ type: "post", id: r.id, title: "Post Allocation", description: "Posting creates flock-level production records and applies bird/inventory side-effects. Continue?", actionLabel: "Post" })

  const openReverse = (r: ProductionBatchRecord) =>
    setConfirm({ type: "reverse", id: r.id, title: "Reverse Batch", description: "Reversing deletes the generated flock records and their side-effects. Continue?", actionLabel: "Reverse" })

  const openRepost = (r: ProductionBatchRecord) =>
    setConfirm({ type: "post", id: r.id, title: "Repost Allocation", description: "Reposting creates fresh flock-level production records and re-applies bird/inventory side-effects. Continue?", actionLabel: "Repost" })

  const openDeleteAllocation = (r: ProductionBatchRecord) =>
    setConfirm({
      type: "deleteAllocation",
      id: r.id,
      title: r.status === "Posted" ? "Delete Posted Allocation?" : "Delete Allocation?",
      description:
        r.status === "Posted"
          ? "This allocation has created flock-level production records and updated inventory. Deleting it will reverse egg production, feed usage, bird mortality and all other inventory effects, remove the generated flock records, and record reversal stock movements. The batch record itself stays available for re-allocation. This cannot be undone automatically."
          : "This removes the allocation rows. No inventory has been affected yet, so nothing is reversed. The batch record stays available and returns to Pending Allocation.",
      actionLabel: r.status === "Posted" ? "Delete and Reverse" : "Delete Allocation",
    })

  const openCancel = (r: ProductionBatchRecord) =>
    setConfirm({ type: "cancel", id: r.id, title: "Cancel Batch", description: "This marks the batch as cancelled. Continue?", actionLabel: "Cancel batch" })

  const runConfirm = async () => {
    if (!confirm) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }
    setIsSubmitting(true)
    let res: { success: boolean; message?: string }
    switch (confirm.type) {
      case "delete":
        res = await deleteBatchProductionRecord(confirm.id, userId, farmId)
        break
      case "post":
        res = await postBatchAllocation(confirm.id, farmId, userId)
        break
      case "reverse":
        res = await reverseBatchProduction(confirm.id, farmId, userId)
        break
      case "cancel":
        res = await setBatchStatus(confirm.id, farmId, "Cancelled", userId)
        break
      case "deleteAllocation":
        res = await deleteBatchAllocation(confirm.id, farmId, userId)
        break
    }
    if (res.success) {
      toast({ title: "Done", description: res.message || "Action completed successfully." })
      await load()
    } else {
      toast({ title: "Action failed", description: res.message || "Something went wrong. Please try again.", variant: "destructive" })
    }
    setIsSubmitting(false)
    setConfirm(null)
  }

  // Distinct months/years derived from records
  const { distinctMonths, distinctYears } = useMemo(() => {
    const monthSet = new Set<string>()
    const yearSet = new Set<string>()
    records.forEach((r) => {
      const d = new Date(r.productionDate)
      const year = `${d.getFullYear()}`
      const month = `${year}-${String(d.getMonth() + 1).padStart(2, "0")}`
      monthSet.add(month)
      yearSet.add(year)
    })
    return { distinctMonths: Array.from(monthSet).sort().reverse(), distinctYears: Array.from(yearSet).sort().reverse() }
  }, [records])

  // Batches present in the loaded records, keyed by a stable id (bird-batch id
  // where available). Only batches that actually have records are offered — a
  // batch with none can't be filtered to meaningfully.
  const distinctBatches = useMemo(() => {
    const map = new Map<string, string>()
    records.forEach((r) => {
      const key = batchFilterKey(r)
      if (!map.has(key)) map.set(key, batchNameLabel(r))
    })
    return Array.from(map, ([key, label]) => ({ key, label })).sort((a, b) => a.label.localeCompare(b.label))
  }, [records])

  // Apply filters
  const filtered = useMemo(() => {
    let list = records.slice()
    if (search) {
      const q = search.toLowerCase()
      list = list.filter((r) => (
        batchNameLabel(r).toLowerCase().includes(q) ||
        batchScopeLabel(r).toLowerCase().includes(q) ||
        (BATCH_STATUS_LABELS[r.status] || "").toLowerCase().includes(q) ||
        new Date(r.productionDate).toLocaleDateString().toLowerCase().includes(q)
      ))
    }
    if (dateFrom) list = list.filter((r) => toLocalDateKey(r.productionDate) >= dateFrom)
    if (dateTo) list = list.filter((r) => toLocalDateKey(r.productionDate) <= dateTo)
    if (selectedStatus !== "ALL") list = list.filter((r) => r.status === selectedStatus)
    if (selectedBatch !== "ALL") list = list.filter((r) => batchFilterKey(r) === selectedBatch)
    if (selectedMonth !== "ALL") list = list.filter((r) => {
      const d = new Date(r.productionDate); const m = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`; return m === selectedMonth
    })
    if (selectedYear !== "ALL") list = list.filter((r) => new Date(r.productionDate).getFullYear().toString() === selectedYear)
    return list
  }, [records, search, dateFrom, dateTo, selectedStatus, selectedBatch, selectedMonth, selectedYear])

  // Summaries
  const totalEggs = useMemo(() => filtered.reduce((s, r) => s + (Number(r.totalEggs) || 0), 0), [filtered])
  const totalFeed = useMemo(() => filtered.reduce((s, r) => s + (Number(r.feedKg) || 0), 0), [filtered])
  const totalDeaths = useMemo(() => filtered.reduce((s, r) => s + (Number(r.deaths) || 0), 0), [filtered])
  const pendingCount = useMemo(() => filtered.filter((r) => r.status === "PendingAllocation").length, [filtered])
  const postedCount = useMemo(() => filtered.filter((r) => r.status === "Posted").length, [filtered])
  const EGGS_PER_CRATE = 30
  const totalEggsCrates = Math.floor(totalEggs / EGGS_PER_CRATE)
  const totalEggsPieces = totalEggs % EGGS_PER_CRATE

  // Sort filtered data
  const sortedFiltered = useMemo(() => {
    return sortData(filtered, sortKey, sortDirection, (item: ProductionBatchRecord, key: string) => {
      switch (key) {
        case "date": return new Date(item.productionDate)
        case "batchName": return batchNameLabel(item).toLowerCase()
        case "age": return item.ageInDays ?? 0
        case "firstPickTotal": return Number(item.firstPickTotal) || 0
        case "secondPickTotal": return Number(item.secondPickTotal) || 0
        case "thirdPickTotal": return Number(item.thirdPickTotal) || 0
        case "fourthPickTotal": return Number(item.fourthPickTotal) || 0
        case "brokenEggs": return Number(item.brokenEggs) || 0
        case "totalEggs": return Number(item.totalEggs) || 0
        case "eggPercent": {
          const b = Number(item.birdsLeft) || 0
          const t = Number(item.totalEggs) || 0
          return b ? (t / b) * 100 : 0
        }
        case "feedKg": return Number(item.feedKg) || 0
        case "birdsLeft": return Number(item.birdsLeft) || 0
        case "deaths": return Number(item.deaths) || 0
        case "meds": return (item.medications || []).length
        case "status": return BATCH_STATUS_LABELS[item.status] || ""
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
  }, [search, dateFrom, dateTo, selectedStatus, selectedBatch, selectedMonth, selectedYear])

  const handlePageChange = (page: number) => setCurrentPage(page)
  const handlePreviousPage = () => { if (currentPage > 1) setCurrentPage(currentPage - 1) }
  const handleNextPage = () => { if (currentPage < totalPages) setCurrentPage(currentPage + 1) }

  const getPageNumbers = () => {
    const pages: (number | string)[] = []
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) pages.push(i)
    } else {
      if (currentPage <= 3) {
        for (let i = 1; i <= 4; i++) pages.push(i)
        pages.push("ellipsis")
        pages.push(totalPages)
      } else if (currentPage >= totalPages - 2) {
        pages.push(1)
        pages.push("ellipsis")
        for (let i = totalPages - 3; i <= totalPages; i++) pages.push(i)
      } else {
        pages.push(1)
        pages.push("ellipsis")
        for (let i = currentPage - 1; i <= currentPage + 1; i++) pages.push(i)
        pages.push("ellipsis")
        pages.push(totalPages)
      }
    }
    return pages
  }

  const formatDateShort = (d: string | Date) => {
    const dt = typeof d === "string" ? new Date(d) : d
    return dt.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "2-digit" })
  }

  const formatAge = (r: ProductionBatchRecord): string => {
    if (r.batchSelectionType !== "SpecificBatch") return "N/A"
    if (r.ageDisplay && r.ageDisplay.trim()) return r.ageDisplay.trim()
    const weeks = r.ageInWeeks ?? (r.ageInDays != null ? Math.floor(r.ageInDays / 7) : null)
    const days = r.ageInDays != null ? r.ageInDays % 7 : 0
    if (weeks == null) return "N/A"
    return `${weeks}w ${days}d`
  }

  const eggPercent = (r: ProductionBatchRecord): string => {
    const b = Number(r.birdsLeft) || 0
    const t = Number(r.totalEggs) || 0
    return b ? ((t / b) * 100).toFixed(1) + "%" : "—"
  }

  const medsLabel = (r: ProductionBatchRecord): string => {
    const n = (r.medications || []).length
    return n > 0 ? `${n} item${n > 1 ? "s" : ""}` : "—"
  }

  const StatusBadge = ({ status }: { status: BatchStatus }) => (
    <span className={cn("inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap", STATUS_BADGE_CLASS[status])}>
      {BATCH_STATUS_LABELS[status]}
    </span>
  )

  const clearFilters = () => {
    setSearch("")
    setDateFrom("")
    setDateTo("")
    setSelectedStatus("ALL")
    setSelectedBatch("ALL")
    setSelectedMonth("ALL")
    setSelectedYear("ALL")
    setDraftDateFrom("")
    setDraftDateTo("")
    setDraftStatus("ALL")
    setDraftBatch("ALL")
    setDraftMonth("ALL")
    setDraftYear("ALL")
  }

  const syncDraftFromCommitted = () => {
    setDraftDateFrom(dateFrom)
    setDraftDateTo(dateTo)
    setDraftStatus(selectedStatus)
    setDraftBatch(selectedBatch)
    setDraftMonth(selectedMonth)
    setDraftYear(selectedYear)
  }

  const applyMobileFilters = () => {
    setDateFrom(draftDateFrom)
    setDateTo(draftDateTo)
    setSelectedStatus(draftStatus)
    setSelectedBatch(draftBatch)
    setSelectedMonth(draftMonth)
    setSelectedYear(draftYear)
    setFiltersOpen(false)
    toast({ title: "Filters applied", description: "Batch list updated." })
  }

  const exportCsv = () => {
    const headers = ["Date", "Batch Name", "Scope", "Age", "1st Pick", "2nd Pick", "3rd Pick", "4th Pick", "Broken", "Total", "Egg%", "Feed", "Birds", "Deaths", "Left", "Meds", "Status"]
    const rows = filtered.map((r) => [
      new Date(r.productionDate).toLocaleDateString(),
      batchNameLabel(r),
      batchScopeLabel(r),
      formatAge(r),
      r.firstPickTotal ?? 0,
      r.secondPickTotal ?? 0,
      r.thirdPickTotal ?? 0,
      r.fourthPickTotal ?? 0,
      r.brokenEggs ?? 0,
      r.totalEggs ?? 0,
      eggPercent(r),
      r.feedKg ?? 0,
      r.birdsLeft ?? "",
      r.deaths ?? 0,
      r.birdsLeft ?? "",
      (r.medications || []).length,
      BATCH_STATUS_LABELS[r.status],
    ])
    const csv = [headers, ...rows].map((row) => row.map((v) => typeof v === "string" && v.includes(",") ? `"${v}"` : v).join(",")).join("\n")
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `batch-production-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const buildPdfDoc = () => {
    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" })
    const farmName = localStorage.getItem("farmName") || "Farm"
    const today = new Date().toLocaleDateString()

    doc.setFontSize(16)
    doc.setTextColor(33, 37, 41)
    doc.text(`${farmName} - Batch Production Report`, 14, 18)
    doc.setFontSize(10)
    doc.setTextColor(100, 100, 100)
    doc.text(`Generated: ${today}  |  Batches: ${filtered.length}`, 14, 25)

    doc.setFontSize(9)
    doc.text(
      `Total Eggs: ${totalEggs.toLocaleString()} (${totalEggsCrates} crates + ${totalEggsPieces} pcs)  |  Feed: ${totalFeed.toFixed(2)} kg  |  Deaths: ${totalDeaths}  |  Pending: ${pendingCount}  |  Posted: ${postedCount}`,
      14, 31,
    )

    const headers = ["Date", "Batch", "Age", "1st", "2nd", "3rd", "4th", "Broken", "Total", "Egg%", "Feed(kg)", "Birds", "Deaths", "Left", "Meds", "Status"]
    const rows = filtered.map((r) => [
      new Date(r.productionDate).toLocaleDateString(),
      batchNameLabel(r),
      formatAge(r),
      r.firstPickTotal ?? 0,
      r.secondPickTotal ?? 0,
      r.thirdPickTotal ?? 0,
      r.fourthPickTotal ?? 0,
      r.brokenEggs ?? 0,
      r.totalEggs ?? 0,
      eggPercent(r),
      Number(r.feedKg ?? 0).toFixed(2),
      r.birdsLeft ?? "—",
      r.deaths ?? 0,
      r.birdsLeft ?? "—",
      (r.medications || []).length,
      BATCH_STATUS_LABELS[r.status],
    ])

    autoTable(doc, {
      startY: 35,
      head: [headers],
      body: rows as any,
      styles: { fontSize: 7, cellPadding: 1.5 },
      headStyles: { fillColor: [37, 99, 235], textColor: 255, fontStyle: "bold", fontSize: 7 },
      alternateRowStyles: { fillColor: [248, 250, 252] },
    })

    return { doc, farmName }
  }

  const exportPdf = () => {
    if (filtered.length === 0) {
      toast({ title: "Nothing to export", description: "Adjust your filters and try again.", variant: "destructive" })
      return
    }
    const { doc } = buildPdfDoc()
    doc.save(`batch-production-${new Date().toISOString().slice(0, 10)}.pdf`)
  }

  const [emailingReport, setEmailingReport] = useState(false)
  const handleEmailReport = async () => {
    if (filtered.length === 0) {
      toast({ title: "Nothing to email", description: "Adjust your filters and try again.", variant: "destructive" })
      return
    }
    const recipient = (typeof window !== "undefined" ? localStorage.getItem("username") || "" : "").trim()
    if (!recipient || !recipient.includes("@")) {
      toast({ title: "No recipient email", description: "Sign in with an email address to receive the report.", variant: "destructive" })
      return
    }
    setEmailingReport(true)
    try {
      const { doc, farmName } = buildPdfDoc()
      const blob = doc.output("blob") as Blob
      const filename = `batch-production-${new Date().toISOString().slice(0, 10)}.pdf`
      const res = await sendReportEmail({ blob, filename, to: recipient, farmName, reportTitle: "Batch Production Report" })
      if (res.success) toast({ title: "Report emailed", description: `Sent to ${recipient}.` })
      else toast({ title: "Email failed", description: res.message || "Unknown error.", variant: "destructive" })
    } finally {
      setEmailingReport(false)
    }
  }

  // Row action buttons gated by status (desktop, ghost buttons).
  const renderActions = (r: ProductionBatchRecord) => {
    const buttons: React.ReactNode[] = []
    const push = (node: React.ReactNode) => buttons.push(node)
    switch (r.status) {
      case "Draft":
        push(<Button key="edit" variant="ghost" size="sm" className="shrink-0" onClick={() => { setEditingId(r.id); setFormOpen(true) }}>Edit</Button>)
        if (permissions.canDelete) push(<Button key="del" variant="ghost" size="sm" className="text-red-600 shrink-0" onClick={() => openDelete(r)}>Delete</Button>)
        push(<Button key="cancel" variant="ghost" size="sm" className="text-slate-500 shrink-0" onClick={() => openCancel(r)}>Cancel</Button>)
        break
      case "PendingAllocation":
        push(<Button key="edit" variant="ghost" size="sm" className="shrink-0" onClick={() => { setEditingId(r.id); setFormOpen(true) }}>Edit</Button>)
        push(<Button key="alloc" variant="ghost" size="sm" className="text-blue-600 shrink-0" onClick={() => router.push(`/batch-production-records/${r.id}/allocate`)}>Allocation</Button>)
        if (permissions.canDelete) push(<Button key="del" variant="ghost" size="sm" className="text-red-600 shrink-0" onClick={() => openDelete(r)}>Delete</Button>)
        push(<Button key="cancel" variant="ghost" size="sm" className="text-slate-500 shrink-0" onClick={() => openCancel(r)}>Cancel</Button>)
        break
      case "Allocated":
        push(<Button key="alloc" variant="ghost" size="sm" className="text-blue-600 shrink-0" onClick={() => router.push(`/batch-production-records/${r.id}/allocate`)}>Allocation</Button>)
        push(<Button key="post" variant="ghost" size="sm" className="text-emerald-600 shrink-0" onClick={() => openPost(r)}>Post</Button>)
        push(<Button key="delalloc" variant="ghost" size="sm" className="text-red-600 shrink-0" onClick={() => openDeleteAllocation(r)}>Delete Allocation</Button>)
        push(<Button key="cancel" variant="ghost" size="sm" className="text-slate-500 shrink-0" onClick={() => openCancel(r)}>Cancel</Button>)
        break
      case "Posted":
        push(<Button key="view" variant="ghost" size="sm" className="shrink-0" onClick={() => router.push(`/batch-production-records/${r.id}`)}>View</Button>)
        push(<Button key="rev" variant="ghost" size="sm" className="text-amber-600 shrink-0" onClick={() => openReverse(r)}>Reverse</Button>)
        if (permissions.canDelete) push(<Button key="delalloc" variant="ghost" size="sm" className="text-red-600 shrink-0" onClick={() => openDeleteAllocation(r)}>Delete Allocation</Button>)
        break
      case "Reversed":
        push(<Button key="view" variant="ghost" size="sm" className="shrink-0" onClick={() => router.push(`/batch-production-records/${r.id}`)}>View</Button>)
        push(<Button key="alloc" variant="ghost" size="sm" className="text-blue-600 shrink-0" onClick={() => router.push(`/batch-production-records/${r.id}/allocate`)}>Edit Allocation</Button>)
        push(<Button key="repost" variant="ghost" size="sm" className="text-emerald-600 shrink-0" onClick={() => openRepost(r)}>Repost</Button>)
        if (permissions.canDelete) push(<Button key="delalloc" variant="ghost" size="sm" className="text-red-600 shrink-0" onClick={() => openDeleteAllocation(r)}>Delete Allocation</Button>)
        break
      case "Cancelled":
        push(<Button key="view" variant="ghost" size="sm" className="shrink-0" onClick={() => router.push(`/batch-production-records/${r.id}`)}>View</Button>)
        break
    }
    return <div className="flex items-center gap-1">{buttons}</div>
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
                  <Layers className="w-5 h-5 text-emerald-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Batch Production Records</h1>
                  <p className="text-sm text-slate-600">Log batch-level production and allocate totals across flocks</p>
                </div>
              </div>
              <Button className="gap-2 shrink-0 w-full sm:w-auto h-11 sm:h-10 bg-emerald-600 hover:bg-emerald-700" onClick={() => { setEditingId(null); setFormOpen(true) }}>
                <Plus className="w-4 h-4" /> Log Batch Production
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
                  <Input placeholder="Search batches..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-10 h-11" />
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
                        {hasActiveFilters && (
                          <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-orange-500 text-white text-xs flex items-center justify-center">
                            {[search, dateFrom, dateTo, selectedStatus !== "ALL", selectedBatch !== "ALL", selectedMonth !== "ALL", selectedYear !== "ALL"].filter(Boolean).length}
                          </span>
                        )}
                      </Button>
                    </SheetTrigger>
                    <SheetContent side="bottom" className={MOBILE_FILTER_SHEET_CONTENT_CLASS}>
                      <MobileFilterSheetHeader />
                      <MobileFilterSheetBody>
                        <div className="space-y-3">
                          <p className="text-sm font-medium text-slate-700">Date range</p>
                          <div className="flex flex-col gap-4">
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="batch-filter-from" className="text-xs font-medium text-slate-500">Start date</label>
                              <Input id="batch-filter-from" type="date" value={draftDateFrom} onChange={(e) => setDraftDateFrom(e.target.value)} className="h-12 min-w-0 w-full text-base" />
                            </div>
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="batch-filter-to" className="text-xs font-medium text-slate-500">End date</label>
                              <Input id="batch-filter-to" type="date" value={draftDateTo} onChange={(e) => setDraftDateTo(e.target.value)} className="h-12 min-w-0 w-full text-base" />
                            </div>
                          </div>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Status</label>
                          <Select value={draftStatus} onValueChange={setDraftStatus}>
                            <SelectTrigger className="h-12 text-base"><SelectValue placeholder="All Statuses" /></SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All Statuses</SelectItem>
                              {ALL_STATUSES.map((s) => (
                                <SelectItem key={s} value={s}>{BATCH_STATUS_LABELS[s]}</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Batch</label>
                          <Select value={draftBatch} onValueChange={setDraftBatch}>
                            <SelectTrigger className="h-12 text-base"><SelectValue placeholder="All Batches" /></SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="ALL">All Batches</SelectItem>
                              {distinctBatches.map((b) => (
                                <SelectItem key={b.key} value={b.key}>{b.label}</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                          <div className="space-y-2">
                            <label className="text-sm font-medium text-slate-700">Month</label>
                            <Select value={draftMonth} onValueChange={setDraftMonth}>
                              <SelectTrigger className="h-12 text-base"><SelectValue placeholder="All months" /></SelectTrigger>
                              <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                                <SelectItem value="ALL">All Months</SelectItem>
                                {distinctMonths.map((m) => {
                                  const [y, mm] = m.split("-")
                                  const d = new Date(parseInt(y, 10), parseInt(mm, 10) - 1)
                                  return <SelectItem key={m} value={m}>{d.toLocaleDateString("en-US", { month: "short", year: "numeric" })}</SelectItem>
                                })}
                              </SelectContent>
                            </Select>
                          </div>
                          <div className="space-y-2">
                            <label className="text-sm font-medium text-slate-700">Year</label>
                            <Select value={draftYear} onValueChange={setDraftYear}>
                              <SelectTrigger className="h-12 text-base"><SelectValue placeholder="All years" /></SelectTrigger>
                              <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                                <SelectItem value="ALL">All</SelectItem>
                                {distinctYears.map((y) => (
                                  <SelectItem key={y} value={y}>{y}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        </div>
                        <p className="text-xs text-slate-500">Choose options, then tap Apply.</p>
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
                          <Button type="button" className="h-12 flex-1" onClick={applyMobileFilters} disabled={!hasDraftChanges}>Apply</Button>
                        </div>
                      </MobileFilterSheetFooter>
                    </SheetContent>
                  </Sheet>
                  <Button variant="outline" size="sm" onClick={exportCsv} className="h-11 px-4 min-w-[72px]">CSV</Button>
                  <Button size="sm" onClick={exportPdf} className="h-11 px-4 min-w-[72px]">PDF</Button>
                  <Button variant="outline" size="sm" onClick={handleEmailReport} disabled={emailingReport} className="h-11 px-4 min-w-[72px] gap-1">
                    {emailingReport ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />} Email
                  </Button>
                </div>
              </div>
            ) : (
              <div className="flex flex-row flex-wrap items-center gap-2 p-2 bg-white rounded-lg border">
                <div className="relative w-[240px] min-w-0">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search batch name..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                </div>
                <Input type="date" placeholder="From" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" />
                <Input type="date" placeholder="To" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" />
                <Select value={selectedStatus} onValueChange={setSelectedStatus}>
                  <SelectTrigger className="w-[180px]"><SelectValue placeholder="Status" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Statuses</SelectItem>
                    {ALL_STATUSES.map((s) => (
                      <SelectItem key={s} value={s}>{BATCH_STATUS_LABELS[s]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select value={selectedBatch} onValueChange={setSelectedBatch}>
                  <SelectTrigger className="w-[200px]"><SelectValue placeholder="Batch" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Batches</SelectItem>
                    {distinctBatches.map((b) => (
                      <SelectItem key={b.key} value={b.key}>{b.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select value={selectedMonth} onValueChange={setSelectedMonth}>
                  <SelectTrigger className="w-[120px]"><SelectValue placeholder="Month" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All Months</SelectItem>
                    {distinctMonths.map((m) => {
                      const [y, mm] = m.split("-"); const d = new Date(parseInt(y), parseInt(mm) - 1)
                      return <SelectItem key={m} value={m}>{d.toLocaleDateString("en-US", { month: "long" })}</SelectItem>
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
                  <Button variant="outline" size="sm" onClick={handleEmailReport} disabled={emailingReport}>
                    {emailingReport ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Mail className="h-4 w-4 mr-2" />} Email Report
                  </Button>
                </div>
              </div>
            )}

            {/* Metrics */}
            {!loading && (
              <div className={cn("grid gap-3", isMobile ? "grid-cols-2" : "grid-cols-1 sm:grid-cols-2 xl:grid-cols-5")}>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Total Batches</div>
                  <div className={cn("font-bold text-slate-900", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{filtered.length.toLocaleString()}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Total Eggs</div>
                  <div className={cn("font-bold text-emerald-600", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalEggs.toLocaleString()}</div>
                  <div className="text-xs text-slate-400 mt-0.5">{totalEggsCrates}c + {totalEggsPieces}p</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Pending Allocation</div>
                  <div className={cn("font-bold text-amber-600", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{pendingCount.toLocaleString()}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Posted</div>
                  <div className={cn("font-bold text-emerald-700", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{postedCount.toLocaleString()}</div>
                </div>
                <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                  <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">Feed (kg)</div>
                  <div className={cn("font-bold text-slate-900", isMobile ? "text-lg mt-0.5" : "text-xl mt-1")}>{totalFeed.toFixed(2)}</div>
                  <div className="text-xs text-slate-400 mt-0.5">Deaths: {totalDeaths.toLocaleString()}</div>
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
                          <p className="text-slate-500 mb-4">No batch records found</p>
                          <Button onClick={() => { setEditingId(null); setFormOpen(true) }}>Log one now</Button>
                        </div>
                      ) : (
                        paginatedRecords.map((r, idx) => (
                          <Collapsible
                            key={r.id}
                            className={cn("group w-full rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}
                          >
                            <div className={cn("px-2.5 py-3 transition-colors", idx % 2 === 1 && "active:bg-black/5", idx % 2 === 0 && "active:bg-black/10")}>
                              <CollapsibleTrigger asChild>
                                <div className="relative cursor-pointer">
                                  <ChevronDown className="absolute right-0 top-0 h-4 w-4 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                                  <div className="min-w-0 pr-6">
                                    <div className="flex items-center gap-2 flex-wrap">
                                      <span className="font-semibold text-slate-900">{formatDateShort(r.productionDate)}</span>
                                      <span className="text-slate-500">•</span>
                                      <span className="text-slate-600 truncate">{batchNameLabel(r)}</span>
                                      <StatusBadge status={r.status} />
                                    </div>
                                    <div className="mt-0.5 text-xs text-slate-500 truncate">{batchScopeLabel(r)}</div>
                                    <div className="mt-3 grid grid-cols-2 gap-2">
                                      <div className="rounded-lg bg-emerald-100 border border-emerald-300 px-3 py-2 shadow-sm">
                                        <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">Eggs</p>
                                        <p className="text-xl font-extrabold text-emerald-800 leading-tight">{(r.totalEggs ?? 0).toLocaleString()}</p>
                                      </div>
                                      <div className="rounded-lg bg-blue-100 border border-blue-300 px-3 py-2 shadow-sm">
                                        <p className="text-[11px] font-semibold uppercase tracking-wide text-blue-900">Birds Left</p>
                                        <p className="text-xl font-extrabold text-blue-800 leading-tight">{r.birdsLeft != null ? Number(r.birdsLeft).toLocaleString() : "—"}</p>
                                      </div>
                                    </div>
                                  </div>
                                </div>
                              </CollapsibleTrigger>
                              <CollapsibleContent>
                                <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                  <div className="grid grid-cols-2 gap-2">
                                    <div><span className="text-slate-500">1st Pick</span> <span className="font-medium text-blue-700">{r.firstPickTotal ?? 0}</span></div>
                                    <div><span className="text-slate-500">2nd Pick</span> <span className="font-medium text-orange-700">{r.secondPickTotal ?? 0}</span></div>
                                    <div><span className="text-slate-500">3rd Pick</span> <span className="font-medium text-purple-700">{r.thirdPickTotal ?? 0}</span></div>
                                    <div><span className="text-slate-500">4th Pick</span> <span className="font-medium text-teal-700">{r.fourthPickTotal ?? 0}</span></div>
                                    <div><span className="text-slate-500">Broken</span> <span className="font-medium text-red-700">{r.brokenEggs ?? 0}</span></div>
                                    <div><span className="text-slate-500">Egg %</span> <span className="font-medium">{eggPercent(r)}</span></div>
                                    <div><span className="text-slate-500">Feed</span> <span className="font-medium">{(Number(r.feedKg) || 0).toFixed(2)} kg</span></div>
                                    <div><span className="text-slate-500">Deaths</span> <span className={cn("font-medium", (r.deaths ?? 0) > 0 ? "text-red-600" : "")}>{r.deaths ?? 0}</span></div>
                                    <div><span className="text-slate-500">Age</span> <span className="text-slate-700 truncate">{formatAge(r)}</span></div>
                                    <div><span className="text-slate-500">Meds</span> <span className="text-slate-700">{medsLabel(r)}</span></div>
                                  </div>
                                  <div className="flex flex-wrap gap-2 pt-2">{renderActions(r)}</div>
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
                  <div className={cn("overflow-x-auto overflow-y-visible table-scroll-wrapper", isMobile && "pb-2")} style={{ WebkitOverflowScrolling: "touch" }}>
                    {isMobile && (
                      <div className="px-4 py-2 border-b bg-slate-50 flex items-center justify-between gap-2 sticky top-0 z-10">
                        <span className="text-xs text-slate-600">Table view • Scroll → for more</span>
                        <Button variant="ghost" size="sm" onClick={() => setShowAllColumnsMobile(false)}>
                          <ChevronUp className="h-4 w-4 mr-1" /> Cards
                        </Button>
                      </div>
                    )}
                    <Table className={cn("min-w-[1700px]", isMobile && "min-w-[1500px]")}>
                      <TableHeader className="sticky top-0 bg-blue-50 z-10">
                        <TableRow className="border-b border-blue-200">
                          <SortableHeader label="Date" sortKey="date" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className={cn("min-w-[100px] px-3 py-2", isMobile && "sticky-col-date bg-blue-50")} />
                          <SortableHeader label="Batch Name" sortKey="batchName" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className={cn("min-w-[180px] px-3 py-2 whitespace-nowrap", isMobile && "sticky-col-flock bg-blue-50")} />
                          <SortableHeader label="Age" sortKey="age" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="min-w-[90px] px-3 py-2" />
                          <SortableHeader label="1st Pick" sortKey="firstPickTotal" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-blue-100 text-blue-900 font-semibold whitespace-nowrap" />
                          <SortableHeader label="2nd Pick" sortKey="secondPickTotal" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-orange-100 text-orange-900 font-semibold whitespace-nowrap" />
                          <SortableHeader label="3rd Pick" sortKey="thirdPickTotal" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-purple-100 text-purple-900 font-semibold whitespace-nowrap" />
                          <SortableHeader label="4th Pick" sortKey="fourthPickTotal" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-teal-100 text-teal-900 font-semibold whitespace-nowrap" />
                          <SortableHeader label="Broken" sortKey="brokenEggs" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2 bg-red-50 text-red-800 font-semibold" />
                          <SortableHeader label="Total" sortKey="totalEggs" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2" />
                          <SortableHeader label="Egg%" sortKey="eggPercent" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2" />
                          <SortableHeader label="Feed" sortKey="feedKg" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2" />
                          <SortableHeader label="Birds" sortKey="birdsLeft" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[80px] px-3 py-2" />
                          <SortableHeader label="Deaths" sortKey="deaths" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[72px] px-3 py-2 whitespace-nowrap" />
                          <SortableHeader label="Left" sortKey="birdsLeft" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right min-w-[70px] px-3 py-2 whitespace-nowrap" />
                          <SortableHeader label="Meds" sortKey="meds" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="min-w-[90px] px-3 py-2 whitespace-nowrap" />
                          <SortableHeader label="Status" sortKey="status" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="min-w-[120px] px-3 py-2 whitespace-nowrap" />
                          <TableHead className={cn("text-left min-w-[200px] px-3 py-2 whitespace-nowrap", isMobile && "sticky-col-actions bg-blue-50")}>Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {paginatedRecords.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={17} className="py-12 text-center text-slate-500">
                              No batch records found for the selected filters.
                              <Button variant="link" className="ml-1" onClick={() => { setEditingId(null); setFormOpen(true) }}>Log one now</Button>
                            </TableCell>
                          </TableRow>
                        ) : paginatedRecords.map((r, idx) => (
                          <TableRow key={r.id} className={cn("hover:bg-slate-50/60", idx % 2 === 0 ? "bg-white" : "bg-slate-50/40")}>
                            <TableCell className={cn("px-3 py-2 whitespace-nowrap min-w-[100px]", isMobile && "sticky-col-date bg-white")}>{isMobile ? formatDateShort(r.productionDate) : new Date(r.productionDate).toLocaleDateString()}</TableCell>
                            <TableCell className={cn("px-3 py-2 min-w-[180px]", isMobile && "sticky-col-flock bg-white")}>
                              <div className="font-medium text-slate-800 truncate max-w-[220px]">{batchNameLabel(r)}</div>
                              <div className="text-xs text-slate-500 truncate max-w-[220px]">{batchScopeLabel(r)}</div>
                            </TableCell>
                            <TableCell className="px-3 py-2 whitespace-nowrap">{formatAge(r)}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-blue-700 bg-blue-50/40 rounded-sm">{r.firstPickTotal ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-orange-700 bg-orange-50/40 rounded-sm">{r.secondPickTotal ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-purple-700 bg-purple-50/40 rounded-sm">{r.thirdPickTotal ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-teal-700 bg-teal-50/40 rounded-sm">{r.fourthPickTotal ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 text-red-700 bg-red-50/40 rounded-sm">{r.brokenEggs ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2 font-semibold text-slate-900">{r.totalEggs ?? 0}</TableCell>
                            <TableCell className="text-right px-3 py-2">{eggPercent(r)}</TableCell>
                            <TableCell className="text-right px-3 py-2">{(Number(r.feedKg) || 0).toFixed(2)}</TableCell>
                            <TableCell className="text-right px-3 py-2">{r.birdsLeft ?? "—"}</TableCell>
                            <TableCell className="text-right px-3 py-2">
                              <span className={cn("px-2 py-0.5 rounded text-xs", (r.deaths ?? 0) > 0 ? "bg-red-50 text-red-700" : "bg-slate-50 text-slate-600")}>{r.deaths ?? 0}</span>
                            </TableCell>
                            <TableCell className="text-right px-3 py-2">{r.birdsLeft ?? "—"}</TableCell>
                            <TableCell className="px-3 py-2 whitespace-nowrap">{medsLabel(r)}</TableCell>
                            <TableCell className="px-3 py-2 whitespace-nowrap"><StatusBadge status={r.status} /></TableCell>
                            <TableCell className={cn("text-left px-3 py-2 whitespace-nowrap", isMobile && "sticky-col-actions bg-white")}>
                              {renderActions(r)}
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

            {/* Pagination */}
            {!loading && filtered.length > 0 && (
              <div className="flex flex-col sm:flex-row items-center justify-between gap-4 mt-2">
                <div className="flex items-center gap-4">
                  <span className="text-sm text-slate-600">
                    Showing {startIndex + 1} to {Math.min(endIndex, sortedFiltered.length)} of {sortedFiltered.length} records
                  </span>
                  <Select value={String(itemsPerPage)} onValueChange={(v) => { setItemsPerPage(Number(v)); setCurrentPage(1) }}>
                    <SelectTrigger className="w-[100px] h-8"><SelectValue /></SelectTrigger>
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
                        {page === "ellipsis" ? (
                          <PaginationEllipsis />
                        ) : (
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

      {/* Shared confirm dialog for Delete / Post / Reverse / Cancel */}
      <AlertDialog open={!!confirm} onOpenChange={(open) => { if (!open) setConfirm(null) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{confirm?.title}</AlertDialogTitle>
            <AlertDialogDescription>{confirm?.description}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isSubmitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={(e) => { e.preventDefault(); runConfirm() }}
              disabled={isSubmitting}
              className={cn(confirm?.type === "delete" && "bg-red-600 hover:bg-red-700 focus:ring-red-600")}
            >
              {isSubmitting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Working...</> : confirm?.actionLabel}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <BatchProductionRecordModal
        open={formOpen}
        onOpenChange={setFormOpen}
        recordId={editingId}
        onSaved={load}
      />
    </div>
  )
}

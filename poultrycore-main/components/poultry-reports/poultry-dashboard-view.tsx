"use client"

// =============================================================================
// Poultry "Farm Dashboards" — the shared engine behind the four dashboard
// reports (Production, Financial, Daily Report, More Reports).
//
// Historically these lived only as tabs on the legacy /reports page. They now
// also each get a dedicated page under /poultry/reports/<view> so they behave
// like the other 20 advanced poultry reports (own URL + header + back button).
//
// This file is the single source of truth for the data, filters and section
// rendering. The legacy /reports page consumes the hook + sections directly
// (keeping its Tabs chrome); the dedicated pages render <PoultryDashboardView />.
// =============================================================================

import { useEffect, useMemo, useState, type ReactNode } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { TrendingUp, TrendingDown, Filter, Search, RotateCcw, ArrowLeft } from "lucide-react"
import { cn } from "@/lib/utils"
import { format } from "date-fns"
import { useIsMobile } from "@/hooks/use-mobile"
import { useLogout } from "@/hooks/use-logout"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { getReportContext } from "@/lib/api"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import { getSales, type Sale } from "@/lib/api/sale"
import { getExpenses, type Expense } from "@/lib/api/expense"
import { getFlocks } from "@/lib/api/flock"
import { PoultryReportSummaryCards, PoultryReportExportButtons, type SummaryCard } from "@/components/poultry-reports/poultry-report-ui"
import { ReportDataTable } from "@/components/poultry-reports/report-data-table"
import { exportMultiTablePdf, emailMultiTableAsPdf, type PdfExportColumn } from "@/lib/utils/pdf-export"
import { formatCurrency, getSelectedCurrency } from "@/lib/utils/currency"
import { getBirdsLeftForFlockFromRecords, sumLatestBirdsLeftByFlock } from "@/lib/utils/production-records"

export type DashboardView = "production" | "financial" | "daily" | "insights"

/** Title + blurb per dashboard view (mirrors the catalogue cards). */
export const DASHBOARD_VIEW_META: Record<DashboardView, { title: string; description: string }> = {
  production: { title: "Production", description: "Egg production trends, collection times and flock metrics." },
  financial: { title: "Financial", description: "Revenue, expenses and net profit / loss." },
  daily: { title: "Daily Report", description: "Daily eggs vs expenses, best and worst days." },
  insights: { title: "More Reports", description: "Sales by product, expense categories and flock performance." },
}

// -----------------------------------------------------------------------------
// Data hook — loads records / sales / expenses / flocks and derives every metric
// used by the four sections. Owns the filter state too.
// -----------------------------------------------------------------------------
export function usePoultryDashboardData() {
  const { toast } = useToast()
  const currencyCode = getSelectedCurrency()

  const [records, setRecords] = useState<ProductionRecord[]>([])
  const [sales, setSales] = useState<Sale[]>([])
  const [expenses, setExpenses] = useState<Expense[]>([])
  const [flocks, setFlocks] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  // Filter states
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [selectedFlock, setSelectedFlock] = useState("ALL")
  const [searchQuery, setSearchQuery] = useState("")

  useEffect(() => {
    const load = async () => {
      try {
        const { userId, farmId } = getReportContext()
        if (!userId || !farmId) return

        const [prodRes, salesRes, expRes, flocksRes] = await Promise.all([
          getProductionRecords(userId, farmId),
          getSales(userId, farmId),
          getExpenses(userId, farmId),
          getFlocks(userId, farmId),
        ])

        if (prodRes.success && prodRes.data) setRecords(prodRes.data)
        else toast({ title: "Failed to fetch", description: prodRes.message || "Could not load records", variant: "destructive" })
        if (salesRes.success && salesRes.data) setSales(salesRes.data)
        if (expRes.success && expRes.data) setExpenses(expRes.data)
        if (flocksRes.success && flocksRes.data) setFlocks(flocksRes.data)
      } finally {
        setLoading(false)
      }
    }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // ---------- Filtered data ----------
  const filteredRecords = useMemo(() => {
    let list = records
    if (dateFrom) {
      list = list.filter(r => new Date(r.date) >= new Date(dateFrom))
    }
    if (dateTo) {
      const to = new Date(dateTo)
      to.setHours(23, 59, 59, 999)
      list = list.filter(r => new Date(r.date) <= to)
    }
    if (selectedFlock !== "ALL") {
      const fid = parseInt(selectedFlock)
      list = list.filter(r => r.flockId === fid)
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      list = list.filter(r =>
        (r.flockName ?? "").toLowerCase().includes(q) ||
        (r.medication ?? "").toLowerCase().includes(q)
      )
    }
    return list
  }, [records, dateFrom, dateTo, selectedFlock, searchQuery])

  const filteredSales = useMemo(() => {
    let list = sales
    if (dateFrom) {
      list = list.filter(s => new Date(s.saleDate) >= new Date(dateFrom))
    }
    if (dateTo) {
      const to = new Date(dateTo)
      to.setHours(23, 59, 59, 999)
      list = list.filter(s => new Date(s.saleDate) <= to)
    }
    if (selectedFlock !== "ALL") {
      const fid = parseInt(selectedFlock)
      list = list.filter(s => s.flockId === fid)
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      list = list.filter(s =>
        (s.product ?? "").toLowerCase().includes(q) ||
        (s.customerName ?? "").toLowerCase().includes(q)
      )
    }
    return list
  }, [sales, dateFrom, dateTo, selectedFlock, searchQuery])

  const filteredExpenses = useMemo(() => {
    let list = expenses
    if (dateFrom) {
      list = list.filter((e: any) => new Date(e.expenseDate || e.expense_date) >= new Date(dateFrom))
    }
    if (dateTo) {
      const to = new Date(dateTo)
      to.setHours(23, 59, 59, 999)
      list = list.filter((e: any) => new Date(e.expenseDate || e.expense_date) <= to)
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      list = list.filter((e: any) =>
        (e.description ?? "").toLowerCase().includes(q) ||
        (e.category ?? "").toLowerCase().includes(q)
      )
    }
    return list
  }, [expenses, dateFrom, dateTo, searchQuery])

  // ---------- Production metrics ----------
  const totalEggs = useMemo(() => filteredRecords.reduce((s, r: any) => s + (r.totalProduction || 0), 0), [filteredRecords])
  const totalCrates = Math.floor(totalEggs / 30)
  const looseEggs = totalEggs % 30
  const avgDaily = filteredRecords.length ? Math.round(totalEggs / filteredRecords.length) : 0
  const totalMortality = useMemo(() => filteredRecords.reduce((s, r: any) => s + (r.mortality || 0), 0), [filteredRecords])
  /** Latest `noOfBirdsLeft` per flock from full production history (not date-filtered). */
  const birdsLeftLatestTotal = useMemo(() => {
    if (records.length === 0) return 0
    if (selectedFlock === "ALL") return sumLatestBirdsLeftByFlock(records)
    const fid = parseInt(selectedFlock, 10)
    if (!Number.isFinite(fid)) return 0
    return getBirdsLeftForFlockFromRecords(records, fid)
  }, [records, selectedFlock])
  const totalFeedKg = useMemo(() => filteredRecords.reduce((s, r: any) => s + (r.feedKg || 0), 0), [filteredRecords])
  const totalRevenue = useMemo(
    () => filteredSales.reduce((s: number, x: any) => s + Number(x.totalAmount || 0), 0),
    [filteredSales]
  )
  const totalExpensesAmount = useMemo(
    () => filteredExpenses.reduce((s: number, x: any) => s + Number(x.amount || 0), 0),
    [filteredExpenses]
  )
  const netProfit = totalRevenue - totalExpensesAmount

  // Per-day production rows (table form) — one row per record, with the
  // collection-time breakdown, total and crate split.
  const prodDailyRows = useMemo(() =>
    filteredRecords
      .map((r: any) => {
        const total = r.totalProduction || 0
        return {
          date: new Date(r.date).toLocaleDateString(),
          rawDate: new Date(r.date).getTime(),
          flockName: r.flockName || (r.flockId ? `Flock #${r.flockId}` : "—"),
          m9: r.production9AM || 0,
          m12: r.production12PM || 0,
          m4: r.production4PM || 0,
          total,
          crates: Math.floor(total / 30),
          loose: total % 30,
        }
      })
      .sort((a, b) => a.rawDate - b.rawDate),
    [filteredRecords]
  )

  // Financial chart data
  const revenueByDate = useMemo(() => {
    const acc: any[] = []
    filteredSales.forEach((s: any) => {
      const date = new Date(s.saleDate || s.sale_date).toLocaleDateString()
      const found = acc.find((x) => x.date === date)
      if (found) found.revenue += Number(s.totalAmount || 0)
      else acc.push({ date, revenue: Number(s.totalAmount || 0), expenses: 0 })
    })
    filteredExpenses.forEach((e: any) => {
      const date = new Date(e.expenseDate || e.expense_date).toLocaleDateString()
      const found = acc.find((x) => x.date === date)
      if (found) found.expenses += Number(e.amount || 0)
      else acc.push({ date, revenue: 0, expenses: Number(e.amount || 0) })
    })
    acc.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
    return acc
  }, [filteredSales, filteredExpenses])

  const dailyEggExpenseReport = useMemo(() => {
    const bucket = new Map<string, { eggs: number; expenses: number }>()

    filteredRecords.forEach((r: any) => {
      const d = new Date(r.date)
      const key = format(d, "yyyy-MM-dd")
      const existing = bucket.get(key) || { eggs: 0, expenses: 0 }
      existing.eggs += Number(r.totalProduction || 0)
      bucket.set(key, existing)
    })

    filteredExpenses.forEach((e: any) => {
      const d = new Date(e.expenseDate || e.expense_date)
      const key = format(d, "yyyy-MM-dd")
      const existing = bucket.get(key) || { eggs: 0, expenses: 0 }
      existing.expenses += Number(e.amount || 0)
      bucket.set(key, existing)
    })

    return Array.from(bucket.entries())
      .map(([date, value]) => ({
        date,
        eggs: value.eggs,
        crates: Math.floor(value.eggs / 30),
        looseEggs: value.eggs % 30,
        expenses: value.expenses,
        eggsPerExpenseUnit: value.expenses > 0 ? value.eggs / value.expenses : value.eggs,
      }))
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
  }, [filteredRecords, filteredExpenses])

  const bestEggDay = useMemo(() => {
    if (!dailyEggExpenseReport.length) return null
    return [...dailyEggExpenseReport].sort((a, b) => b.eggs - a.eggs)[0]
  }, [dailyEggExpenseReport])

  const highestExpenseDay = useMemo(() => {
    if (!dailyEggExpenseReport.length) return null
    return [...dailyEggExpenseReport].sort((a, b) => b.expenses - a.expenses)[0]
  }, [dailyEggExpenseReport])

  const salesByProduct = useMemo(() => {
    const productMap = new Map<string, { qty: number; revenue: number; salesCount: number }>()
    filteredSales.forEach((s: any) => {
      const key = (s.product || "Unknown").trim() || "Unknown"
      const current = productMap.get(key) || { qty: 0, revenue: 0, salesCount: 0 }
      current.qty += Number(s.quantity || 0)
      current.revenue += Number(s.totalAmount || 0)
      current.salesCount += 1
      productMap.set(key, current)
    })
    return Array.from(productMap.entries())
      .map(([product, value]) => ({
        product,
        quantity: value.qty,
        revenue: value.revenue,
        salesCount: value.salesCount,
      }))
      .sort((a, b) => b.revenue - a.revenue)
  }, [filteredSales])

  const expensesByCategory = useMemo(() => {
    const categoryMap = new Map<string, number>()
    filteredExpenses.forEach((e: any) => {
      const key = (e.category || "Uncategorized").trim() || "Uncategorized"
      categoryMap.set(key, (categoryMap.get(key) || 0) + Number(e.amount || 0))
    })
    return Array.from(categoryMap.entries())
      .map(([category, total]) => ({ category, total }))
      .sort((a, b) => b.total - a.total)
  }, [filteredExpenses])

  const flockProductionSummary = useMemo(() => {
    const map = new Map<number, { flockId: number; flockName: string; eggs: number; feedKg: number; mortality: number; days: number }>()
    filteredRecords.forEach((r: any) => {
      const id = Number(r.flockId || 0)
      const current = map.get(id) || {
        flockId: id,
        flockName: r.flockName || `Flock #${id}`,
        eggs: 0,
        feedKg: 0,
        mortality: 0,
        days: 0,
      }
      current.eggs += Number(r.totalProduction || 0)
      current.feedKg += Number(r.feedKg || 0)
      current.mortality += Number(r.mortality || 0)
      current.days += 1
      map.set(id, current)
    })
    return Array.from(map.values())
      .map((x) => ({
        ...x,
        avgEggsPerDay: x.days > 0 ? Math.round(x.eggs / x.days) : 0,
        birdsLeftLatest: getBirdsLeftForFlockFromRecords(records, x.flockId),
      }))
      .sort((a, b) => b.eggs - a.eggs)
  }, [filteredRecords, records])

  const clearFilters = () => {
    setDateFrom("")
    setDateTo("")
    setSelectedFlock("ALL")
    setSearchQuery("")
  }

  return {
    loading,
    currencyCode,
    flocks,
    // filters
    dateFrom, setDateFrom,
    dateTo, setDateTo,
    selectedFlock, setSelectedFlock,
    searchQuery, setSearchQuery,
    clearFilters,
    // filtered lists
    filteredSales, filteredExpenses,
    // production metrics
    totalEggs, totalCrates, looseEggs, avgDaily, totalMortality,
    birdsLeftLatestTotal, totalFeedKg, prodDailyRows,
    // financial
    totalRevenue, totalExpensesAmount, netProfit, revenueByDate,
    // daily
    dailyEggExpenseReport, bestEggDay, highestExpenseDay,
    // insights
    salesByProduct, expensesByCategory, flockProductionSummary,
  }
}

export type PoultryDashboardData = ReturnType<typeof usePoultryDashboardData>

// -----------------------------------------------------------------------------
// Shared filter bar (search + flock + date range). Desktop inline + mobile sheet.
// -----------------------------------------------------------------------------
export function DashboardFilterBar({ data }: { data: PoultryDashboardData }) {
  const isMobile = useIsMobile()
  const [filtersOpen, setFiltersOpen] = useState(false)
  const {
    flocks, searchQuery, setSearchQuery, selectedFlock, setSelectedFlock,
    dateFrom, setDateFrom, dateTo, setDateTo, clearFilters,
  } = data

  return (
    <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded-md border border-slate-200">
      {isMobile ? (
        <>
          <div className="relative flex-1 min-w-0">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
            <Input
              placeholder="Search..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>
          <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
            <SheetTrigger asChild>
              <Button variant="outline" size="sm" className="gap-2 shrink-0">
                <Filter className="h-4 w-4" />
                Filters
              </Button>
            </SheetTrigger>
            <SheetContent side="bottom" className="rounded-t-2xl max-h-[85vh]">
              <SheetHeader>
                <SheetTitle>Filters</SheetTitle>
              </SheetHeader>
              <div className="space-y-4 pt-4">
                <div className="space-y-2">
                  <Label>Flock</Label>
                  <Select value={selectedFlock} onValueChange={setSelectedFlock}>
                    <SelectTrigger>
                      <SelectValue placeholder="All Flocks" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All Flocks</SelectItem>
                      {flocks.map((flock: any) => (
                        <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                          {flock.name}
                        </SelectItem>
                      ))}
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
                  <Button variant="outline" className="flex-1" onClick={clearFilters}>
                    Clear
                  </Button>
                  <Button className="flex-1" onClick={() => setFiltersOpen(false)}>
                    Apply
                  </Button>
                </div>
              </div>
            </SheetContent>
          </Sheet>
        </>
      ) : (
        <>
          <div className="relative w-[240px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
            <Input
              placeholder="Search..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>
          <div className="flex items-center gap-1.5">
            <Label className="text-xs text-slate-600 whitespace-nowrap">Flock</Label>
            <Select value={selectedFlock} onValueChange={setSelectedFlock}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder="Flock" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">All Flocks</SelectItem>
                {flocks.map((flock: any) => (
                  <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                    {flock.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex items-center gap-1.5">
            <Label className="text-xs text-slate-600 whitespace-nowrap">From</Label>
            <Input
              type="date"
              value={dateFrom}
              onChange={(e) => setDateFrom(e.target.value)}
              className="w-[140px]"
            />
          </div>
          <div className="flex items-center gap-1.5">
            <Label className="text-xs text-slate-600 whitespace-nowrap">To</Label>
            <Input
              type="date"
              value={dateTo}
              onChange={(e) => setDateTo(e.target.value)}
              className="w-[140px]"
            />
          </div>
          <div className="ml-auto">
            <Button variant="outline" size="sm" onClick={clearFilters}>
              <RotateCcw className="h-4 w-4 mr-2" />
              Clear
            </Button>
          </div>
        </>
      )}
    </div>
  )
}

// -----------------------------------------------------------------------------
// Shared presentational helpers — Advanced-Report-style summary cards + a titled
// card per data table (each sortable + paginated via ReportDataTable).
// -----------------------------------------------------------------------------

/** One exportable data table on a dashboard view. */
interface DashboardReportTable {
  title: string
  description?: string
  filename: string
  columns: PdfExportColumn[]
  /** React nodes shown in the cells (may be styled). */
  display: ReactNode[][]
  /** Primitive values used for sorting + export, parallel to `display`. */
  exportRows: (string | number)[][]
}

/** Renders the view's summary cards + one titled, sortable, paginated table per entry. */
function DashboardBody({ cards, tables }: { cards: SummaryCard[]; tables: DashboardReportTable[] }) {
  return (
    <>
      <PoultryReportSummaryCards cards={cards} />
      {tables.map((t) => (
        <Card key={t.filename} className="bg-white">
          <CardHeader>
            <CardTitle>{t.title}</CardTitle>
            {t.description && <CardDescription>{t.description}</CardDescription>}
          </CardHeader>
          <CardContent>
            <ReportDataTable
              columns={t.columns.map((c) => ({ header: c.header, align: c.align === "right" ? "right" : "left" }))}
              rows={t.display.map((d, i) => ({ display: d, sort: t.exportRows[i] }))}
            />
          </CardContent>
        </Card>
      ))}
    </>
  )
}

// Letterhead metadata shared by every export on a dashboard (farm, period,
// currency, who generated it). Read once per section from auth + filters.
export interface DashboardExportMeta {
  farmName?: string
  generatedBy?: string
  currencyLabel?: string
  fromDate?: string
  toDate?: string
}

function useDashboardExportMeta(data: PoultryDashboardData): DashboardExportMeta {
  const farmName = useAuthStore((s) => s.activeFarmName)
  const user = useAuthStore((s) => s.user)
  return {
    farmName: farmName ?? undefined,
    generatedBy: user?.username || user?.email || undefined,
    currencyLabel: data.currencyCode,
    fromDate: data.dateFrom || undefined,
    toDate: data.dateTo || undefined,
  }
}

// CSV / PDF / Email export buttons for a whole dashboard view. Exports every
// table on the view at once: one combined multi-table PDF, a combined CSV, or
// emails the combined PDF. Placed in the top toolbar, mirroring the advanced
// reports. Owns its own email dialog + download state.
function DashboardExportToolbar({
  viewTitle, filename, cards, tables, meta,
}: {
  viewTitle: string
  filename: string
  cards: SummaryCard[]
  tables: DashboardReportTable[]
  meta: DashboardExportMeta
}) {
  const { toast } = useToast()
  const [downloading, setDownloading] = useState(false)
  const [emailOpen, setEmailOpen] = useState(false)
  const [recipient, setRecipient] = useState("")
  const [sending, setSending] = useState(false)
  const hasData = tables.some((t) => t.exportRows.length > 0)

  const buildMultiOpts = () => ({
    title: viewTitle,
    filename,
    farmName: meta.farmName,
    fromDate: meta.fromDate,
    toDate: meta.toDate,
    generatedBy: meta.generatedBy,
    currencyLabel: meta.currencyLabel,
    summaryCards: cards,
    tables: tables.map((t) => ({ heading: t.title, columns: t.columns, rows: t.exportRows })),
  })

  const onCsv = () => {
    const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`
    const metaLine = `${esc(viewTitle)}\n${esc(`Farm: ${meta.farmName ?? "—"}`)},${esc(`Period: ${meta.fromDate ?? "All"} to ${meta.toDate ?? "All"}`)}\n`
    const blocks = tables.map((t) => {
      const header = t.columns.map((c) => esc(c.header)).join(",")
      const body = t.exportRows.map((r) => r.map(esc).join(",")).join("\n")
      return `${esc(t.title)}\n${header}\n${body}`
    })
    const csv = metaLine + "\n" + blocks.join("\n\n")
    const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `${filename}-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const onPdf = async () => {
    setDownloading(true)
    try {
      await exportMultiTablePdf(buildMultiOpts())
    } catch (e: any) {
      toast({ title: "Export failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setDownloading(false)
    }
  }

  const onEmail = () => {
    setRecipient(meta.generatedBy || "")
    setEmailOpen(true)
  }

  const sendEmail = async () => {
    const recipients = recipient.split(/[,;\n]/).map((s) => s.trim()).filter(Boolean)
    const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (recipients.length === 0 || recipients.some((e) => !emailRe.test(e))) {
      toast({ title: "Enter a valid email address", variant: "destructive" })
      return
    }
    setSending(true)
    try {
      const res = await emailMultiTableAsPdf(buildMultiOpts(), { to: recipients.join(",") })
      if (res.success) {
        toast({ title: "Report emailed", description: `Sent to ${recipients.length === 1 ? recipients[0] : `${recipients.length} recipients`}.` })
        setEmailOpen(false)
      } else {
        toast({ title: "Email failed", description: res.message ?? "Could not send.", variant: "destructive" })
      }
    } catch (e: any) {
      toast({ title: "Email failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSending(false)
    }
  }

  return (
    <>
      <PoultryReportExportButtons onCsv={onCsv} onPdf={onPdf} onEmail={onEmail} busy={downloading} disabled={!hasData} />
      <Dialog open={emailOpen} onOpenChange={(o) => { if (!sending) setEmailOpen(o) }}>
        <DialogContent>
          <DialogHeader><DialogTitle>Email “{viewTitle}”</DialogTitle></DialogHeader>
          <div className="space-y-2">
            <Label htmlFor={`dash-email-${filename}`} className="text-xs">Recipient email(s)</Label>
            <Input
              id={`dash-email-${filename}`}
              value={recipient}
              onChange={(e) => setRecipient(e.target.value)}
              placeholder="owner@example.com, accountant@example.com"
            />
            <p className="text-xs text-slate-500">Separate multiple addresses with commas. A PDF of every table on this view is generated and sent.</p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEmailOpen(false)} disabled={sending}>Cancel</Button>
            <Button onClick={sendEmail} disabled={sending}>{sending ? "Sending…" : "Send"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}

// -----------------------------------------------------------------------------
// Content builders — one per dashboard view. Each takes the shared data and
// returns Advanced-Report-style summary cards + table definitions (no charts).
// -----------------------------------------------------------------------------
type DashboardContent = { cards: SummaryCard[]; tables: DashboardReportTable[] }

function buildProductionContent(data: PoultryDashboardData): DashboardContent {
  const {
    totalEggs, totalCrates, looseEggs, avgDaily, totalMortality, totalFeedKg,
    birdsLeftLatestTotal, selectedFlock, prodDailyRows,
  } = data

  const cards: SummaryCard[] = [
    { label: "Total Eggs", value: totalEggs.toLocaleString() },
    { label: "Total Crates", value: `${totalCrates.toLocaleString()} (+${looseEggs} loose)` },
    { label: "Avg Daily Production", value: avgDaily.toLocaleString() },
    { label: "Total Deaths", value: totalMortality.toLocaleString(), accent: "rose" },
    { label: "Total Feed (kg)", value: totalFeedKg.toLocaleString() },
    {
      label: selectedFlock === "ALL" ? "Birds Left (sum per flock)" : "Birds Left (selected flock)",
      value: birdsLeftLatestTotal.toLocaleString(),
      accent: "indigo",
    },
  ]

  const columns: PdfExportColumn[] = [
    { header: "Date", align: "left" },
    { header: "Flock", align: "left" },
    { header: "9am", align: "right" },
    { header: "12pm", align: "right" },
    { header: "4pm", align: "right" },
    { header: "Total", align: "right" },
    { header: "Crates + Loose", align: "right" },
  ]
  const exportRows = prodDailyRows.map((r) => [
    r.date, r.flockName, r.m9, r.m12, r.m4, r.total, `${r.crates} + ${r.loose}`,
  ])
  const display: ReactNode[][] = prodDailyRows.map((r) => [
    r.date,
    r.flockName,
    r.m9.toLocaleString(),
    r.m12.toLocaleString(),
    r.m4.toLocaleString(),
    <span className="font-medium">{r.total.toLocaleString()}</span>,
    `${r.crates} + ${r.loose}`,
  ])

  return {
    cards,
    tables: [{
      title: "Daily Egg Production",
      description: "Eggs collected per day and flock, with collection-time breakdown.",
      filename: "poultry-production",
      columns, display, exportRows,
    }],
  }
}

function buildFinancialContent(data: PoultryDashboardData): DashboardContent {
  const {
    totalRevenue, totalExpensesAmount, netProfit, filteredSales, filteredExpenses,
    revenueByDate, currencyCode,
  } = data

  const cards: SummaryCard[] = [
    { label: `Revenue (${filteredSales.length} txn)`, value: formatCurrency(totalRevenue, currencyCode), accent: "green" },
    { label: `Expenses (${filteredExpenses.length})`, value: formatCurrency(totalExpensesAmount, currencyCode), accent: "rose" },
    { label: "Net Profit / Loss", value: formatCurrency(netProfit, currencyCode), accent: netProfit >= 0 ? "green" : "rose" },
  ]

  const columns: PdfExportColumn[] = [
    { header: "Date", align: "left" },
    { header: "Revenue", align: "right" },
    { header: "Expenses", align: "right" },
    { header: "Net", align: "right" },
  ]
  const exportRows = revenueByDate.map((r: any) => {
    const net = Number(r.revenue || 0) - Number(r.expenses || 0)
    return [
      r.date,
      formatCurrency(r.revenue, currencyCode),
      formatCurrency(r.expenses, currencyCode),
      formatCurrency(net, currencyCode),
    ]
  })
  const display: ReactNode[][] = revenueByDate.map((r: any) => {
    const net = Number(r.revenue || 0) - Number(r.expenses || 0)
    return [
      r.date,
      formatCurrency(r.revenue, currencyCode),
      formatCurrency(r.expenses, currencyCode),
      <span className={net >= 0 ? "text-emerald-700 font-medium" : "text-rose-700 font-medium"}>
        {formatCurrency(net, currencyCode)}
      </span>,
    ]
  })

  return {
    cards,
    tables: [{
      title: "Revenue vs Expenses",
      description: "Daily revenue, spending and net position.",
      filename: "poultry-financial",
      columns, display, exportRows,
    }],
  }
}

function buildDailyContent(data: PoultryDashboardData): DashboardContent {
  const {
    dailyEggExpenseReport, bestEggDay, highestExpenseDay, netProfit, currencyCode,
  } = data

  const cards: SummaryCard[] = [
    { label: "Daily Rows", value: dailyEggExpenseReport.length.toLocaleString() },
    {
      label: "Best Egg Day",
      value: bestEggDay ? `${bestEggDay.eggs.toLocaleString()} · ${format(new Date(bestEggDay.date), "MMM d")}` : "No data",
      accent: "green",
    },
    {
      label: "Highest Expense Day",
      value: highestExpenseDay ? `${formatCurrency(highestExpenseDay.expenses, currencyCode)} · ${format(new Date(highestExpenseDay.date), "MMM d")}` : "No data",
      accent: "rose",
    },
    { label: "Net Position", value: formatCurrency(netProfit, currencyCode), accent: netProfit >= 0 ? "green" : "rose" },
  ]

  const perf = (row: typeof dailyEggExpenseReport[number]) =>
    row.expenses <= 0 ? "No expense" : row.eggsPerExpenseUnit >= 1 ? "Strong day" : "Review costs"

  const columns: PdfExportColumn[] = [
    { header: "Date", align: "left" },
    { header: "Total Eggs", align: "right" },
    { header: "Crates + Loose", align: "left" },
    { header: "Daily Expenses", align: "right" },
    { header: "Performance", align: "left" },
  ]
  const exportRows = dailyEggExpenseReport.map((row) => [
    format(new Date(row.date), "MMM d, yyyy"),
    row.eggs,
    `${row.crates} crates + ${row.looseEggs} loose`,
    formatCurrency(row.expenses, currencyCode),
    perf(row),
  ])
  const display: ReactNode[][] = dailyEggExpenseReport.map((row) => [
    format(new Date(row.date), "MMM d, yyyy"),
    <span className="font-medium">{row.eggs.toLocaleString()}</span>,
    `${row.crates} crates + ${row.looseEggs} loose`,
    formatCurrency(row.expenses, currencyCode),
    row.expenses <= 0 ? (
      <span className="inline-flex items-center gap-1 text-emerald-700 font-medium">
        <TrendingUp className="w-4 h-4" /> No expense
      </span>
    ) : row.eggsPerExpenseUnit >= 1 ? (
      <span className="inline-flex items-center gap-1 text-emerald-700 font-medium">
        <TrendingUp className="w-4 h-4" /> Strong day
      </span>
    ) : (
      <span className="inline-flex items-center gap-1 text-amber-700 font-medium">
        <TrendingDown className="w-4 h-4" /> Review costs
      </span>
    ),
  ])

  return {
    cards,
    tables: [{
      title: "Daily Egg & Expense Report",
      description: "Same-day production volume and spending.",
      filename: "poultry-daily",
      columns, display, exportRows,
    }],
  }
}

function buildInsightsContent(data: PoultryDashboardData): DashboardContent {
  const { salesByProduct, expensesByCategory, flockProductionSummary, currencyCode } = data

  const cards: SummaryCard[] = [
    { label: "Sales Products", value: salesByProduct.length.toLocaleString() },
    { label: "Expense Categories", value: expensesByCategory.length.toLocaleString() },
    {
      label: "Top Product Revenue",
      value: salesByProduct[0] ? `${formatCurrency(salesByProduct[0].revenue, currencyCode)} · ${salesByProduct[0].product}` : "No data",
      accent: "green",
    },
    {
      label: "Top Expense Category",
      value: expensesByCategory[0] ? `${formatCurrency(expensesByCategory[0].total, currencyCode)} · ${expensesByCategory[0].category}` : "No data",
      accent: "rose",
    },
  ]

  const salesColumns: PdfExportColumn[] = [
    { header: "Product", align: "left" },
    { header: "Transactions", align: "right" },
    { header: "Quantity", align: "right" },
    { header: "Revenue", align: "right" },
  ]
  const salesExport = salesByProduct.map((row) => [row.product, row.salesCount, row.quantity, formatCurrency(row.revenue, currencyCode)])
  const salesDisplay: ReactNode[][] = salesByProduct.map((row) => [
    row.product, row.salesCount.toLocaleString(), row.quantity.toLocaleString(), formatCurrency(row.revenue, currencyCode),
  ])

  const expenseColumns: PdfExportColumn[] = [
    { header: "Category", align: "left" },
    { header: "Total", align: "right" },
  ]
  const expenseExport = expensesByCategory.map((row) => [row.category, formatCurrency(row.total, currencyCode)])
  const expenseDisplay: ReactNode[][] = expensesByCategory.map((row) => [row.category, formatCurrency(row.total, currencyCode)])

  const flockColumns: PdfExportColumn[] = [
    { header: "Flock", align: "left" },
    { header: "Birds Left (latest)", align: "right" },
    { header: "Total Eggs", align: "right" },
    { header: "Avg Eggs / Day", align: "right" },
    { header: "Feed (kg)", align: "right" },
    { header: "Deaths", align: "right" },
  ]
  const flockExport = flockProductionSummary.map((row) => [
    row.flockName, row.birdsLeftLatest, row.eggs, row.avgEggsPerDay, row.feedKg, row.mortality,
  ])
  const flockDisplay: ReactNode[][] = flockProductionSummary.map((row) => [
    row.flockName,
    <span className="text-indigo-800 font-medium">{row.birdsLeftLatest.toLocaleString()}</span>,
    row.eggs.toLocaleString(),
    row.avgEggsPerDay.toLocaleString(),
    row.feedKg.toLocaleString(),
    row.mortality.toLocaleString(),
  ])

  return {
    cards,
    tables: [
      {
        title: "Sales by Product Report",
        description: "Quantities and revenue split by product.",
        filename: "poultry-sales-by-product",
        columns: salesColumns, display: salesDisplay, exportRows: salesExport,
      },
      {
        title: "Expense Category Report",
        description: "Where most spending is happening.",
        filename: "poultry-expense-categories",
        columns: expenseColumns, display: expenseDisplay, exportRows: expenseExport,
      },
      {
        title: "Flock Performance Report",
        description: "Egg output, feed usage and deaths by flock.",
        filename: "poultry-flock-performance",
        columns: flockColumns, display: flockDisplay, exportRows: flockExport,
      },
    ],
  }
}

function buildDashboardContent(view: DashboardView, data: PoultryDashboardData): DashboardContent {
  if (view === "production") return buildProductionContent(data)
  if (view === "financial") return buildFinancialContent(data)
  if (view === "daily") return buildDailyContent(data)
  return buildInsightsContent(data)
}

/** Stable export filename per view. */
const dashboardFilename = (view: DashboardView) => `poultry-${view === "insights" ? "more-reports" : view}`

/**
 * Renders a single dashboard view inside the tabbed Reports pages: a top export
 * toolbar (combined CSV / PDF / Email) followed by the summary cards + tables.
 */
export function PoultryDashboardSection({ view, data }: { view: DashboardView; data: PoultryDashboardData }) {
  const meta = useDashboardExportMeta(data)
  const { cards, tables } = buildDashboardContent(view, data)
  const viewMeta = DASHBOARD_VIEW_META[view]
  return (
    <>
      <div className="flex justify-end print:hidden">
        <DashboardExportToolbar
          viewTitle={viewMeta.title}
          filename={dashboardFilename(view)}
          cards={cards}
          tables={tables}
          meta={meta}
        />
      </div>
      <DashboardBody cards={cards} tables={tables} />
    </>
  )
}

// -----------------------------------------------------------------------------
// Standalone dedicated page — used by /poultry/reports/<view>. Mirrors the
// chrome of the 20 advanced reports (sidebar + header + "back to Poultry
// reports" + titled header card), so the four dashboards behave consistently.
// -----------------------------------------------------------------------------
export function PoultryDashboardView({ view }: { view: DashboardView }) {
  const router = useRouter()
  const logout = useLogout()
  const data = usePoultryDashboardData()
  const viewMeta = DASHBOARD_VIEW_META[view]
  const exportMeta = useDashboardExportMeta(data)
  const { cards, tables } = buildDashboardContent(view, data)

  // Gate: these dashboards only exist inside a poultry company context (mirrors
  // the /poultry/reports catalogue and the 20 advanced reports).
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 min-w-0">
          {/* Top toolbar — back button + export, mirroring the advanced reports. */}
          <div className="mb-4 flex items-center justify-between gap-2 flex-wrap print:hidden">
            <Button asChild variant="outline" size="sm">
              <Link href="/poultry/reports"><ArrowLeft className="h-4 w-4 mr-1" /> Poultry reports</Link>
            </Button>
            <DashboardExportToolbar
              viewTitle={viewMeta.title}
              filename={dashboardFilename(view)}
              cards={cards}
              tables={tables}
              meta={exportMeta}
            />
          </div>

          <div className="space-y-4">
            {/* Titled header card — matches the advanced-report identity. */}
            <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
              <div className="h-1.5 bg-gradient-to-r from-amber-500 to-amber-400" />
              <div className="p-4 sm:p-6">
                <h1 className="text-2xl font-semibold text-slate-900">{viewMeta.title}</h1>
                <p className="text-sm text-slate-500 mt-1">{viewMeta.description}</p>
              </div>
            </div>

            <DashboardFilterBar data={data} />

            <DashboardBody cards={cards} tables={tables} />
          </div>
        </main>
      </div>
    </div>
  )
}

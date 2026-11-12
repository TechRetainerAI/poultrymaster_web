"use client"

export const dynamic = "force-dynamic"

/**
 * Financial Activity (Generic) — the bridge between Cash Flow and Profit & Loss.
 *
 * Deep copy of the Poultry Financial Activity page, adapted for Generic APIs.
 *
 *   Cash Flow           where money came from and went
 *   Financial Activity  what happened, and what each effect was   <- this page
 *   Profit & Loss       what was recognised, and was there profit
 */

import { Fragment, Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { PeriodSelect } from "@/components/ui/period-select"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Activity, ArrowLeftRight, BarChart3, ChevronDown, ChevronRight, Download,
  Loader2, RefreshCw,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useIsMobile } from "@/hooks/use-mobile"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { defaultReportRange, rangeToPeriod } from "@/lib/date-ranges"
import {
  getGenericFinancialActivity, genericActivitySourceLink,
  formatActivityMoment, positionLabel,
  type FinancialActivityResponse, type FinancialActivityRow,
} from "@/lib/api/generic-financial-activity"

const TIP = {
  moneyIn: "Actual money entering the company. Not the same as revenue \u2014 a loan, an owner contribution and a customer paying an old bill are all money in and none of them is income.",
  moneyOut: "Actual money leaving the company. Not the same as an expense \u2014 repaying loan principal, buying equipment and paying a supplier for last month\u2019s bill all move money without being a cost.",
  revenue: "Business income recognised for Profit & Loss, on the day of the sale \u2014 not on the day it is paid for.",
  expense: "Cost recognised for Profit & Loss. It may be recognised long after the money left, or without any money moving at all.",
  profit: "Revenue minus expense recognised by this activity. Money in and money out are never part of it.",
  runningCash: "The company\u2019s cash position after this activity. Non-cash activity leaves it unchanged.",
  positions: "Which assets, debts, receivables, payables, inventory balances, loans or owner capital changed because of this event.",
} as const

const ACTIVITY_FILTERS = [
  { value: "ALL",       label: "All activity" },
  { value: "CASH",      label: "Cash activity" },
  { value: "PL",        label: "P&L activity" },
  { value: "Operating", label: "Operating" },
  { value: "Financing", label: "Financing" },
  { value: "Owner",     label: "Owner activity" },
  { value: "Capital",   label: "Capital activity" },
  { value: "Inventory", label: "Inventory / cost recognition" },
  { value: "Transfer",  label: "Internal transfers" },
] as const

const CASH_FILTERS = [
  { value: "ALL",  label: "Cash and non-cash" },
  { value: "CASH", label: "Cash movement" },
  { value: "NON",  label: "Non-cash activity" },
] as const

const PROFIT_FILTERS = [
  { value: "ALL",  label: "Any profit impact" },
  { value: "POS",  label: "Positive" },
  { value: "NEG",  label: "Negative" },
  { value: "NONE", label: "No profit impact" },
] as const

function FinancialActivityPageInner() {
  const router = useRouter()
  const isMobile = useIsMobile()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const DEFAULT_RANGE = defaultReportRange("thisMonth")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)

  const [data, setData] = useState<FinancialActivityResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const firstLoad = useRef(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState("")

  const [search, setSearch] = useState("")
  const [activityFilter, setActivityFilter] = useState<string>("ALL")
  const [cashFilter, setCashFilter] = useState<string>("ALL")
  const [profitFilter, setProfitFilter] = useState<string>("ALL")
  const [typeFilter, setTypeFilter] = useState("ALL")
  const [categoryFilter, setCategoryFilter] = useState("ALL")

  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const toggle = (key: string) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (!next.delete(key)) next.add(key)
      return next
    })

  const load = useCallback(async () => {
    setError("")
    const res = await getGenericFinancialActivity({ fromDate, toDate })
    setData(res)
  }, [fromDate, toDate])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    if (firstLoad.current) setLoading(true)
    void load()
      .catch((e: any) => setError(e?.message ?? String(e)))
      .finally(() => { firstLoad.current = false; setLoading(false) })
  }, [activeFarmType, router, load])

  async function handleRefresh() {
    setRefreshing(true)
    try { await load() } catch (e: any) { setError(e?.message ?? String(e)) }
    setRefreshing(false)
  }

  const rows = data?.rows ?? []
  const summary = data?.summary

  const types = useMemo(
    () => Array.from(new Set(rows.map((r) => r.type).filter(Boolean))).sort(),
    [rows],
  )
  const categories = useMemo(
    () => Array.from(new Set(rows.map((r) => r.category).filter(Boolean))).sort(),
    [rows],
  )

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return rows.filter((r) => {
      if (q && !(`${r.description ?? ""} ${r.type} ${r.category} ${r.partyName ?? ""}`.toLowerCase().includes(q))) return false
      if (typeFilter !== "ALL" && r.type !== typeFilter) return false
      if (categoryFilter !== "ALL" && r.category !== categoryFilter) return false

      if (activityFilter === "CASH" && !r.isCashActivity) return false
      if (activityFilter === "PL" && r.profitImpact === 0 && r.revenue === 0 && r.expense === 0) return false
      if (!["ALL", "CASH", "PL"].includes(activityFilter) && r.activityType !== activityFilter) return false

      if (cashFilter === "CASH" && !r.isCashActivity) return false
      if (cashFilter === "NON" && r.isCashActivity) return false

      if (profitFilter === "POS" && r.profitImpact <= 0) return false
      if (profitFilter === "NEG" && r.profitImpact >= 0) return false
      if (profitFilter === "NONE" && r.profitImpact !== 0) return false
      return true
    })
  }, [rows, search, typeFilter, categoryFilter, activityFilter, cashFilter, profitFilter])

  const totals = useMemo(() => {
    let moneyIn = 0, moneyOut = 0, revenue = 0, expense = 0
    for (const r of filtered) {
      moneyIn += r.moneyIn; moneyOut += r.moneyOut
      revenue += r.revenue; expense += r.expense
    }
    return { moneyIn, moneyOut, revenue, expense, net: moneyIn - moneyOut, profit: revenue - expense }
  }, [filtered])

  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)

  const sorted = useMemo(
    () => !sortKey || !sortDir ? [...filtered].reverse() : sortData(filtered, sortKey, sortDir, (r, key) => {
      switch (key) {
        case "date": return `${r.occurredAt ?? ""}|${r.createdAt ?? ""}`
        case "description": return r.description ?? ""
        default: return (r as unknown as Record<string, unknown>)[key]
      }
    }),
    [filtered, sortKey, sortDir],
  )

  const pg = usePagination(sorted, 25)

  const handleSort = (key: string) => {
    const next = toggleSort(key, sortKey, sortDir)
    setSortKey(next.key)
    setSortDir(next.direction)
    pg.setPage(1)
  }

  const filtersActive =
    search.trim() !== "" || typeFilter !== "ALL" || categoryFilter !== "ALL" ||
    activityFilter !== "ALL" || cashFilter !== "ALL" || profitFilter !== "ALL"

  const resetFilters = () => {
    setSearch(""); setTypeFilter("ALL"); setCategoryFilter("ALL")
    setActivityFilter("ALL"); setCashFilter("ALL"); setProfitFilter("ALL")
  }

  const money = (n: number) => (n === 0 ? "\u2014" : gh(n))

  function exportCsv() {
    const head = ["Date", "Type", "Category", "Description", "Money In", "Money Out",
                  "Revenue", "Expense", "Profit Impact", "Running Cash"]
    const esc = (v: unknown) => {
      const s = String(v ?? "")
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
    }
    const lines = [head.join(",")]
    for (const r of sorted) {
      lines.push([
        formatActivityMoment(r.occurredAt, r.createdAt), r.type, r.category, r.description ?? "",
        r.moneyIn || "", r.moneyOut || "", r.revenue || "", r.expense || "",
        r.profitImpact || "", r.runningCash,
      ].map(esc).join(","))
    }
    const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `financial-activity-${fromDate}-to-${toDate}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const positionsFor = (r: FinancialActivityRow) => (
    r.positionChanges.length === 0 ? (
      <div className="px-4 py-3 text-sm text-slate-500">
        This event did not change any tracked financial position.
      </div>
    ) : (
      <div className="px-4 py-3">
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500" title={TIP.positions}>
          Financial position changes
        </div>
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Position</TableHead>
                <TableHead className="text-right">Increase</TableHead>
                <TableHead className="text-right">Decrease</TableHead>
                <TableHead>Explanation</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {r.positionChanges.map((p, i) => (
                <TableRow key={i} className="bg-white">
                  <TableCell className="whitespace-nowrap font-medium">
                    {positionLabel(p.positionType)}
                    <div className="text-[11px] font-normal text-slate-500">{p.positionName}</div>
                  </TableCell>
                  <TableCell className="text-right tabular-nums text-emerald-700">
                    {p.increaseAmount ? gh(p.increaseAmount) : "\u2014"}
                  </TableCell>
                  <TableCell className="text-right tabular-nums text-rose-700">
                    {p.decreaseAmount ? gh(p.decreaseAmount) : "\u2014"}
                  </TableCell>
                  <TableCell className="text-slate-600">{p.explanation ?? "\u2014"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
        <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-slate-500">
          {r.sourceNumber && <span>Reference {r.sourceNumber}</span>}
          {r.cashAccountName && <span>Account: {r.cashAccountName}</span>}
          {r.partyName && <span>Party: {r.partyName}</span>}
          {r.plLine && <span>P&amp;L line: {r.plLine}</span>}
          {r.status && r.status !== "Posted" && <span className="text-amber-700">Status: {r.status}</span>}
          <span>Recorded {formatActivityMoment(r.occurredAt, r.createdAt)}</span>
          {(() => {
            const link = genericActivitySourceLink(r)
            return link ? (
              <Link href={link.href} className="font-medium text-blue-600 hover:underline">{link.label} &rarr;</Link>
            ) : null
          })()}
        </div>
      </div>
    )
  )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto min-w-0 overflow-x-hidden p-4 sm:p-6 space-y-4">

          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 rounded-lg bg-indigo-100 flex items-center justify-center">
                <Activity className="w-5 h-5 text-indigo-700" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Financial Activity</h1>
                <p className="text-sm text-slate-600">
                  See how business activity affects cash, revenue, expenses, profit and financial position.
                </p>
              </div>
            </div>
            <div className="flex flex-wrap gap-2 shrink-0">
              <Button variant="outline" size="sm" asChild>
                <Link href="/generic-cash-flow"><ArrowLeftRight className="w-4 h-4 mr-1" /> Cash Flow</Link>
              </Button>
              <Button variant="outline" size="sm" asChild>
                <Link href="/generic-profit-loss"><BarChart3 className="w-4 h-4 mr-1" /> Profit &amp; Loss</Link>
              </Button>
              <Button variant="outline" size="sm" onClick={exportCsv} disabled={filtered.length === 0}>
                <Download className="w-4 h-4 mr-1" /> Export CSV
              </Button>
              <Button variant="outline" size="sm" onClick={handleRefresh} disabled={refreshing || loading}>
                <RefreshCw className={cn("w-4 h-4 mr-1", refreshing && "animate-spin")} /> Refresh
              </Button>
            </div>
          </div>

          <div className="rounded-md border border-indigo-200 bg-indigo-50 px-3 py-2 text-xs text-indigo-900">
            Financial Activity combines cash movement and profit recognition so you can see why cash flow and
            profit may differ.
          </div>

          {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

          {summary && (
            <>
              <div className="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-7 gap-3">
                <Stat label="Money In"  value={gh(summary.moneyIn)}  tip={TIP.moneyIn}  tone="emerald" />
                <Stat label="Money Out" value={gh(summary.moneyOut)} tip={TIP.moneyOut} tone="rose" />
                <Stat label="Net Cash Flow" value={gh(summary.netCashFlow)} tone={summary.netCashFlow < 0 ? "rose" : "emerald"}
                      hint={`Opening ${gh(summary.openingCash)}`} />
                <Stat label="Closing Cash" value={gh(summary.closingCash)} tip={TIP.runningCash} />
                <Stat label="Revenue"  value={gh(summary.revenue)} tip={TIP.revenue} tone="emerald" />
                <Stat label="Expenses" value={gh(summary.expense)} tip={TIP.expense} tone="rose" />
                <Stat label="Net Profit" value={gh(summary.netProfit)} tip={TIP.profit}
                      tone={summary.netProfit < 0 ? "rose" : "emerald"}
                      hint={`${summary.cashEvents} cash \u00b7 ${summary.nonCashEvents} non-cash events`} />
              </div>

              <p className="text-xs leading-relaxed text-slate-600">
                <strong>Net Cash Flow and Net Profit are different</strong> because some cash movements are not
                revenue or expenses, while some revenue or expenses may be recognised without cash moving at the
                same time.
              </p>
            </>
          )}

          <Card><CardContent className="p-3">
            <div className={cn("grid gap-2", isMobile ? "grid-cols-2" : "grid-cols-4 xl:grid-cols-7")}>
              <PeriodSelect
                label={null}
                className="w-full"
                value={rangeToPeriod(fromDate, toDate)}
                onChange={(_p, rg) => { if (rg) { setFromDate(rg.from); setToDate(rg.to) } }}
              />
              <Input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} aria-label="From date" />
              <Input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} aria-label="To date" />
              <Input placeholder="Search\u2026" value={search} onChange={(e) => setSearch(e.target.value)}
                     className={cn(isMobile && "col-span-2")} />
              <Select value={activityFilter} onValueChange={setActivityFilter}>
                <SelectTrigger><SelectValue placeholder="Activity" /></SelectTrigger>
                <SelectContent>
                  {ACTIVITY_FILTERS.map((f) => <SelectItem key={f.value} value={f.value}>{f.label}</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={cashFilter} onValueChange={setCashFilter}>
                <SelectTrigger><SelectValue placeholder="Cash" /></SelectTrigger>
                <SelectContent>
                  {CASH_FILTERS.map((f) => <SelectItem key={f.value} value={f.value}>{f.label}</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={profitFilter} onValueChange={setProfitFilter}>
                <SelectTrigger><SelectValue placeholder="Profit impact" /></SelectTrigger>
                <SelectContent>
                  {PROFIT_FILTERS.map((f) => <SelectItem key={f.value} value={f.value}>{f.label}</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={typeFilter} onValueChange={setTypeFilter}>
                <SelectTrigger><SelectValue placeholder="Type" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All types</SelectItem>
                  {types.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                <SelectTrigger><SelectValue placeholder="Category" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All categories</SelectItem>
                  {categories.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            {filtersActive && (
              <div className="pt-2">
                <Button variant="outline" size="sm" onClick={resetFilters}>Reset filters</Button>
              </div>
            )}
          </CardContent></Card>

          <Card><CardContent className="p-0 lg:p-4">
            {loading ? (
              <div className="flex items-center justify-center gap-2 py-12 text-slate-500">
                <Loader2 className="w-4 h-4 animate-spin" /> Loading financial activity...
              </div>
            ) : filtered.length === 0 ? (
              <div className="py-12 text-center text-sm text-slate-500 px-4">
                {rows.length === 0
                  ? "No financial activity in this period."
                  : "No activity matches those filters."}
              </div>
            ) : (
              <MobileCardList
                striped
                defaultOpen
                items={pg.pageItems}
                getKey={(r) => r.eventKey}
                primary={(r) => r.type}
                secondary={(r) => (
                  <span className="truncate">{formatActivityMoment(r.occurredAt, r.createdAt)} \u00b7 {r.category}</span>
                )}
                highlights={(r) => [
                  { label: "Money in",  value: money(r.moneyIn),  accent: "emerald" },
                  { label: "Money out", value: money(r.moneyOut), accent: "rose" },
                  {
                    label: "Profit impact",
                    value: r.profitImpact === 0 ? "\u2014" : gh(r.profitImpact),
                    accent: r.profitImpact > 0 ? "emerald" : r.profitImpact < 0 ? "rose" : "slate",
                    wide: true,
                  },
                ]}
                details={(r) => [
                  { label: "Description", value: r.description ?? "\u2014" },
                  { label: "Revenue", value: money(r.revenue) },
                  { label: "Expense", value: money(r.expense) },
                  { label: "Running cash", value: gh(r.runningCash) },
                ]}
                extra={(r) => positionsFor(r)}
                pagination={pg.paginationProps}
                desktopTable={
                  <div className="overflow-x-auto table-scroll-wrapper pb-2" style={{ WebkitOverflowScrolling: "touch" }}>
                    <Table className="w-full min-w-[1080px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead className="w-8" />
                          <SortableHeader label="Date" sortKey="date" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Type" sortKey="type" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Category" sortKey="category" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Description" sortKey="description" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Money In" sortKey="moneyIn" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" title={TIP.moneyIn} />
                          <SortableHeader label="Money Out" sortKey="moneyOut" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" title={TIP.moneyOut} />
                          <SortableHeader label="Revenue" sortKey="revenue" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" title={TIP.revenue} />
                          <SortableHeader label="Expense" sortKey="expense" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" title={TIP.expense} />
                          <SortableHeader label="Profit Impact" sortKey="profitImpact" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" title={TIP.profit} />
                          <SortableHeader label="Running Cash" sortKey="runningCash" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" title={TIP.runningCash} />
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((r) => {
                          const open = expanded.has(r.eventKey)
                          return (
                            <Fragment key={r.eventKey}>
                              <TableRow className="cursor-pointer" onClick={() => toggle(r.eventKey)}>
                                <TableCell className="px-1">
                                  {open ? <ChevronDown className="w-4 h-4 text-slate-400" />
                                        : <ChevronRight className="w-4 h-4 text-slate-400" />}
                                </TableCell>
                                <TableCell className="whitespace-nowrap text-sm">{formatActivityMoment(r.occurredAt, r.createdAt)}</TableCell>
                                <TableCell className="whitespace-nowrap font-medium">
                                  {r.type}
                                  {r.isInternalTransfer && (
                                    <Badge variant="outline" className="ml-1.5 text-[10px] font-normal">internal</Badge>
                                  )}
                                </TableCell>
                                <TableCell className="whitespace-nowrap text-sm text-slate-600">{r.category}</TableCell>
                                <TableCell className="max-w-[280px] truncate text-sm" title={r.description ?? ""}>
                                  {r.description ?? "\u2014"}
                                </TableCell>
                                <TableCell className="text-right tabular-nums text-emerald-700">{money(r.moneyIn)}</TableCell>
                                <TableCell className="text-right tabular-nums text-rose-700">{money(r.moneyOut)}</TableCell>
                                <TableCell className="text-right tabular-nums text-emerald-700">{money(r.revenue)}</TableCell>
                                <TableCell className="text-right tabular-nums text-rose-700">{money(r.expense)}</TableCell>
                                <TableCell className={cn("text-right tabular-nums font-medium",
                                  r.profitImpact > 0 ? "text-emerald-700" : r.profitImpact < 0 ? "text-rose-700" : "text-slate-400")}>
                                  {r.profitImpact === 0 ? "\u2014" : gh(r.profitImpact)}
                                </TableCell>
                                <TableCell className="text-right tabular-nums text-slate-700">{gh(r.runningCash)}</TableCell>
                              </TableRow>
                              {open && (
                                <TableRow>
                                  <TableCell colSpan={11} className="bg-slate-50 p-0">{positionsFor(r)}</TableCell>
                                </TableRow>
                              )}
                            </Fragment>
                          )
                        })}
                      </TableBody>
                      <TableFooter>
                        <TableRow className="bg-slate-50 hover:bg-slate-50">
                          <TableCell colSpan={5} className="font-medium text-slate-700">
                            {filtersActive ? "Filtered total" : "Period total"}
                            <span className="ml-1.5 text-xs font-normal text-slate-500">
                              ({filtered.length.toLocaleString()} {filtered.length === 1 ? "event" : "events"})
                            </span>
                          </TableCell>
                          <TableCell className="text-right font-semibold tabular-nums text-emerald-700">{money(totals.moneyIn)}</TableCell>
                          <TableCell className="text-right font-semibold tabular-nums text-rose-700">{money(totals.moneyOut)}</TableCell>
                          <TableCell className="text-right font-semibold tabular-nums text-emerald-700">{money(totals.revenue)}</TableCell>
                          <TableCell className="text-right font-semibold tabular-nums text-rose-700">{money(totals.expense)}</TableCell>
                          <TableCell className={cn("text-right font-semibold tabular-nums",
                            totals.profit > 0 ? "text-emerald-700" : totals.profit < 0 ? "text-rose-700" : "text-slate-400")}>
                            {totals.profit === 0 ? "\u2014" : gh(totals.profit)}
                          </TableCell>
                          <TableCell />
                        </TableRow>
                      </TableFooter>
                    </Table>
                  </div>
                }
              />
            )}
          </CardContent></Card>

          {!loading && filtered.length > 0 && (
            <div className="hidden lg:block">
              <DataPagination {...pg.paginationProps} />
            </div>
          )}

          <p className="text-[11px] leading-relaxed text-slate-500">
            Money In and Money Out are the same figures Cash Flow reports, and exclude transfers between the
            company&apos;s own accounts &mdash; those move money without any entering or leaving the business, and their
            account legs are in the row detail. Revenue and Expense are the same figures Profit &amp; Loss
            recognises.
          </p>
        </main>
      </div>
    </div>
  )
}

function Stat({ label, value, hint, tip, tone = "slate" }: {
  label: string; value: string; hint?: string; tip?: string
  tone?: "slate" | "emerald" | "rose"
}) {
  const toneClass = tone === "emerald" ? "text-emerald-700" : tone === "rose" ? "text-rose-700" : "text-slate-900"
  const n = value.length
  const sizeClass =
    n > 17 ? "text-sm  xl:text-xs   2xl:text-sm" :
    n > 14 ? "text-base xl:text-xs  2xl:text-sm" :
    n > 11 ? "text-lg  xl:text-sm   2xl:text-base" :
             "text-2xl xl:text-base 2xl:text-xl"

  return (
    <div className="min-w-0 overflow-hidden rounded-xl border border-slate-200 bg-white p-4 xl:p-3 2xl:p-4 shadow-sm"
         title={tip}>
      <div className="truncate text-xs font-medium uppercase tracking-wide text-slate-500">{label}</div>
      <div className={cn("mt-1 font-bold tabular-nums whitespace-nowrap", sizeClass, toneClass)}
           title={value}>
        {value}
      </div>
      {hint && <div className="mt-0.5 truncate text-xs text-slate-400" title={hint}>{hint}</div>}
    </div>
  )
}

export default function GenericFinancialActivityPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <FinancialActivityPageInner />
    </Suspense>
  )
}

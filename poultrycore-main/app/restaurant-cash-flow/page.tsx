"use client"

/**
 * Cash Flow (Restaurant) — read from the one cash ledger (migration 323).
 *
 * Every payment, refund, expense, gift-card sale, owner-money entry, loan
 * movement and till over/short posts a ledger row; this page is that ledger
 * with transfers, till floats/drops and opening balances left out (they move
 * money between the restaurant's own accounts). So "Cash at Hand" here equals
 * the sum of the account balances on Cash Accounts, by construction.
 * Operating = trading; Financing = loans and owner money.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { SortableHeader, sortData, type SortDirection } from "@/components/ui/sortable-header"
import { usePagination } from "@/hooks/use-pagination"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { useIsMobile } from "@/hooks/use-mobile"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import {
  UtensilsCrossed, TrendingUp, TrendingDown, Lightbulb, Info, ChevronDown, Wallet, Calculator, FileBarChart,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt } from "@/lib/currency"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import {
  getCashFlow, flowGroupLabel, type CashFlowRow, type CashFlowSummary,
} from "@/lib/api/cash-flow"
import { cashFlowBuckets, categoryLabel, sourceTypeLabel, withRunningBalance } from "@/lib/cash/cash-flow"
import { buildCashFlowAnalysis } from "@/lib/cash/cash-flow-analysis"
import { CashFlowInsightsDialog } from "@/components/cash/cash-flow-insights-dialog"
import { fmtDateTime, businessSortValue } from "@/lib/utils/company-datetime"

const DEFAULT = defaultReportRange()
const EMPTY_SUMMARY: CashFlowSummary = {
  moneyIn: 0, moneyOut: 0, netCashFlow: 0, openingCash: 0, closingCash: 0,
  operatingIn: 0, operatingOut: 0, financingIn: 0, financingOut: 0, movementCount: 0,
}

export default function RestaurantCashFlowPage() {
  const isMobile = useIsMobile()
  const router = useRouter()
  const logout = useLogout()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const [dateFrom, setDateFrom] = useState(DEFAULT.from)
  const [dateTo, setDateTo] = useState(DEFAULT.to)
  const [search, setSearch] = useState("")
  const [flowFilter, setFlowFilter] = useState("ALL")
  const [typeFilter, setTypeFilter] = useState("ALL")
  const [sortKey, setSortKey] = useState<string>("date")
  const [sortDir, setSortDir] = useState<SortDirection>("desc")

  const [rows, setRows] = useState<CashFlowRow[]>([])
  const [summary, setSummary] = useState<CashFlowSummary>(EMPTY_SUMMARY)
  const [prevSummary, setPrevSummary] = useState<CashFlowSummary>(EMPTY_SUMMARY)
  const [allTime, setAllTime] = useState<CashFlowSummary>(EMPTY_SUMMARY)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [insightsOpen, setInsightsOpen] = useState(false)

  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const previousRange = useMemo(() => {
    const from = new Date(dateFrom), to = new Date(dateTo)
    if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) return { from: null, to: null, days: 0 }
    const days = Math.max(1, Math.round((to.getTime() - from.getTime()) / 86_400_000) + 1)
    const prevTo = new Date(from.getTime() - 86_400_000)
    const prevFrom = new Date(prevTo.getTime() - (days - 1) * 86_400_000)
    const iso = (d: Date) => d.toISOString().split("T")[0]
    return { from: iso(prevFrom), to: iso(prevTo), days }
  }, [dateFrom, dateTo])

  const load = useCallback(async () => {
    setError("")
    const [cur, prev, all] = await Promise.allSettled([
      getCashFlow("Restaurant", { fromDate: dateFrom, toDate: dateTo }),
      previousRange.from && previousRange.to
        ? getCashFlow("Restaurant", { fromDate: previousRange.from, toDate: previousRange.to })
        : Promise.resolve(null),
      getCashFlow("Restaurant"),
    ])
    if (cur.status === "fulfilled") { setRows(cur.value.rows); setSummary(cur.value.summary) }
    else { setError(cur.reason?.message ?? String(cur.reason)); setRows([]); setSummary(EMPTY_SUMMARY) }
    setPrevSummary(prev.status === "fulfilled" ? (prev.value?.summary ?? EMPTY_SUMMARY) : EMPTY_SUMMARY)
    setAllTime(all.status === "fulfilled" ? all.value.summary : EMPTY_SUMMARY)
    setLoading(false)
  }, [dateFrom, dateTo, previousRange.from, previousRange.to])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    setLoading(true); void load()
  }, [activeFarmType, activeFarmId, router, load])

  const inBuckets = useMemo(() => cashFlowBuckets(rows, "in"), [rows])
  const outBuckets = useMemo(() => cashFlowBuckets(rows, "out"), [rows])
  const totals = useMemo(() => ({
    moneyIn: summary.moneyIn, moneyOut: summary.moneyOut, net: summary.netCashFlow,
    transferVolume: 0, transferCount: 0, entryCount: summary.movementCount,
  }), [summary])

  const analysis = useMemo(() => buildCashFlowAnalysis({
    moneyIn: summary.moneyIn, moneyOut: summary.moneyOut, netCashFlow: summary.netCashFlow,
    operatingIn: summary.operatingIn, operatingOut: summary.operatingOut,
    financingIn: summary.financingIn, financingOut: summary.financingOut,
    cashAtHand: allTime.closingCash,
    offLedgerIn: 0, offLedgerOut: 0, transferVolume: summary.transferVolume ?? 0,
    movementCount: summary.movementCount, daysInPeriod: previousRange.days,
    previousMoneyIn: prevSummary.moneyIn, previousMoneyOut: prevSummary.moneyOut,
    previousNetCashFlow: prevSummary.netCashFlow,
    moneyInByCategory: inBuckets.map((b) => ({ label: b.label, amount: b.amount, sharePercent: b.percent })),
    moneyOutByCategory: outBuckets.map((b) => ({ label: b.label, amount: b.amount, sharePercent: b.percent })),
  }, gh), [summary, prevSummary, allTime, previousRange.days, inBuckets, outBuckets, gh])

  const insights = useMemo(() => analysis.map((a) => ({
    id: a.id,
    tone: (a.tone === "good" ? "good" : a.tone === "watch" ? "warn" : "neutral") as "good" | "bad" | "warn" | "neutral",
    headline: a.title, detail: a.detail,
  })), [analysis])

  const warnings = useMemo(() => {
    const items: React.ReactNode[] = []
    if (summary.closingCash < 0) items.push(
      <Alert key="neg" className="border-rose-200 bg-rose-50 py-2">
        <Info className="h-4 w-4 text-rose-700" />
        <AlertDescription className="text-xs text-rose-900">
          <b>Closing cash is negative.</b> Spending exceeds recorded income for this period.
        </AlertDescription>
      </Alert>
    )
    return { count: items.length, node: items.length ? <>{items}</> : null }
  }, [summary.closingCash])

  const notes = useMemo(() => (
    <Alert className="border-slate-200 bg-slate-50 py-2">
      <Info className="h-4 w-4 text-slate-500" />
      <AlertDescription className="text-xs text-slate-700">
        Built from the cash ledger: order payments (tips included), refunds, expenses, gift-card
        sales, owner money, loans and till over/short. Transfers between your own accounts are left out.
      </AlertDescription>
    </Alert>
  ), [])

  // Money in and out of each account over the period (transfers excluded, as
  // everywhere on this page). Accounts come off the rows, so an account with no
  // movement in the period is simply not listed.
  const byAccount = useMemo(() => {
    const map = new Map<string, { name: string; moneyIn: number; moneyOut: number }>()
    for (const r of rows) {
      const name = r.accountName ?? "Unassigned"
      const e = map.get(name) ?? { name, moneyIn: 0, moneyOut: 0 }
      if (r.amount > 0) e.moneyIn += r.amount; else e.moneyOut += -r.amount
      map.set(name, e)
    }
    return [...map.values()].sort((a, b) => (b.moneyIn - b.moneyOut) - (a.moneyIn - a.moneyOut))
  }, [rows])

  const typeOptions = useMemo(() => {
    const seen = new Set<string>()
    for (const r of rows) seen.add(categoryLabel(r.category))
    return [...seen].sort((a, b) => a.localeCompare(b))
  }, [rows])

  const history = useMemo(() => {
    const filtered = rows
      .filter((r) => flowFilter === "ALL" || r.flowGroup === flowFilter)
      .filter((r) => typeFilter === "ALL" || categoryLabel(r.category) === typeFilter)
    const withRunning = withRunningBalance(filtered, summary.openingCash)
    return sortData(withRunning, sortKey, sortDir, (item: any, key: string) => {
      switch (key) {
        case "date": return businessSortValue(item.transactionDate, item)
        case "type": return categoryLabel(item.category)
        case "category": return flowGroupLabel(item.flowGroup)
        case "description": return item.description ?? ""
        case "in": return item.amount > 0 ? item.amount : 0
        case "out": return item.amount < 0 ? -item.amount : 0
        case "running": return item.running
        default: return item[key]
      }
    })
  }, [rows, flowFilter, typeFilter, sortKey, sortDir, summary.openingCash])

  const visible = useMemo(() => filterByDateAndSearch(history, {
    search, searchKeys: ["description", "category", "sourceType"], dateKey: "transactionDate",
  }), [history, search])
  const pg = usePagination(visible)

  if (!canView) return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">
          <Card><CardContent className="py-12 text-center text-slate-600">You do not have access to Cash Flow.</CardContent></Card>
        </main>
      </div>
    </div>
  )

  return (
    <TooltipProvider delayDuration={200}>
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">
          <div className="mb-3">
            <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
              <UtensilsCrossed className="h-5 w-5 text-rose-600" /> Cash Flow
            </h1>
            <p className="mt-1 text-xs text-slate-500">What the restaurant received and spent</p>
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button size="sm" variant="outline" asChild><Link href="/restaurant-cash-accounts"><Wallet className="h-4 w-4 mr-1" /> Cash Accounts</Link></Button>
              <Button size="sm" variant="outline" asChild><Link href="/restaurant-tills"><Calculator className="h-4 w-4 mr-1" /> Tills & Shifts</Link></Button>
              <Button size="sm" variant="outline" asChild><Link href="/restaurant-reports/cash-flow-detail"><FileBarChart className="h-4 w-4 mr-1" /> Cash Flow report</Link></Button>
              <Button size="sm" variant="outline" className="whitespace-nowrap"
                      onClick={() => setInsightsOpen(true)} disabled={loading}>
                <Lightbulb className="h-4 w-4 mr-1" /> Cash Flow Insights
                {warnings.count > 0 && <span className="ml-1.5 inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-amber-500 px-1 text-[10px] font-semibold text-white">{warnings.count}</span>}
              </Button>
            </div>
          </div>

          <Collapsible defaultOpen={!isMobile} className="group mb-3 rounded-lg border border-slate-200 bg-white">
            <CollapsibleTrigger asChild>
              <button type="button" className="flex w-full items-start justify-between gap-2 p-3 text-left">
                <span className="text-sm font-medium text-slate-900">Where your money came from and went.</span>
                <ChevronDown className="mt-0.5 h-4 w-4 shrink-0 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <p className="px-3 pb-3 text-xs leading-snug text-slate-600">
                Built from the cash ledger every till, cash box, bank and wallet posts to: order payments
                (tips included), refunds, expenses, gift-card sales, owner money, loans and till over/short.
                This is what actually entered and left the business — not what was ordered. Money moved
                between your own accounts (transfers, till floats and drops) is left out.
              </p>
            </CollapsibleContent>
          </Collapsible>

          <ListFilters search={search} setSearch={setSearch} searchPlaceholder="Search description, category…"
                       dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} />

          {error && <Alert variant="destructive" className="mb-3"><AlertDescription>{error}</AlertDescription></Alert>}

          {loading ? <Card><CardContent className="py-12 text-center text-slate-600">Loading cash flow…</CardContent></Card> : (
            <div className="space-y-3">
              <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                <Tile label="Opening Cash" value={gh(summary.openingCash)} note="Start of period" tip="Everything before this period started." />
                <Tile label="Money In" value={gh(summary.moneyIn)} note="For selected period" tone="text-emerald-700" icon={<TrendingUp className="h-3.5 w-3.5" />} tip="Order payments (tips included), gift-card sales, loans received and owner contributions." />
                <Tile label="Money Out" value={gh(summary.moneyOut)} note="For selected period" tone="text-rose-700" icon={<TrendingDown className="h-3.5 w-3.5" />} tip="Expenses, refunds, loan repayments and owner drawings." />
                <Tile label="Cash at Hand" value={gh(allTime.closingCash)} note="All accounts, today" tone={allTime.closingCash < 0 ? "text-rose-700" : undefined} tip="Every till, cash box, bank and wallet added together — the same total as Cash Accounts." />
              </div>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                <Tile label="Net Cash Flow" value={`${summary.netCashFlow > 0 ? "+" : ""}${gh(summary.netCashFlow)}`} note="For selected period" tone={summary.netCashFlow >= 0 ? "text-emerald-700" : "text-rose-700"} tip="Money In minus Money Out." />
                <Tile label="Net Cash Flow (Strictly business)" value={`${summary.operatingIn - summary.operatingOut > 0 ? "+" : ""}${gh(summary.operatingIn - summary.operatingOut)}`} note="Trading only" tone={summary.operatingIn - summary.operatingOut >= 0 ? "text-emerald-700" : "text-rose-700"} tip="What trading brought in less what it cost — loans and owner money left out. Negative means the restaurant was kept going by borrowing or the owner." />
                <Tile label="Loans & Owner Money" value={`${summary.financingIn - summary.financingOut > 0 ? "+" : ""}${gh(summary.financingIn - summary.financingOut)}`} note="Net for period" tone={summary.financingIn - summary.financingOut >= 0 ? "text-emerald-700" : "text-rose-700"} tip="Loans received and owner contributions, less loan repayments and owner drawings." />
                <Tile label="Closing Cash" value={gh(summary.closingCash)} note="End of period" tone={summary.closingCash < 0 ? "text-rose-700" : undefined} tip="Opening + In - Out for this period." />
              </div>
              <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs tabular-nums text-slate-600">
                  <span>Opening <b className="text-slate-900">{gh(summary.openingCash)}</b></span>
                  <span className="text-emerald-700">+ in <b>{gh(summary.moneyIn)}</b></span>
                  <span className="text-rose-700">- out <b>{gh(summary.moneyOut)}</b></span>
                  <span>= closing <b className="text-slate-900">{gh(summary.closingCash)}</b></span>
                  <span className="text-slate-400">· {summary.movementCount} movements</span>
                  {(summary.transferVolume ?? 0) > 0 && <span className="text-slate-400">· {gh(summary.transferVolume ?? 0)} moved between your own accounts (not counted)</span>}
                </div>
              </div>

              {byAccount.length > 0 && (
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Cash by account</CardTitle>
                    <CardDescription className="text-xs">Where this period's money came in and went out. Balances are on <Link href="/restaurant-cash-accounts" className="underline">Cash Accounts</Link>.</CardDescription>
                  </CardHeader>
                  <CardContent className="p-0 md:px-4 md:pb-4">
                    <div className="overflow-x-auto">
                      <Table><TableHeader><TableRow>
                        <TableHead>Account</TableHead><TableHead className="text-right">Money in</TableHead>
                        <TableHead className="text-right">Money out</TableHead><TableHead className="text-right">Net</TableHead>
                      </TableRow></TableHeader><TableBody>
                        {byAccount.map((a) => (
                          <TableRow key={a.name}>
                            <TableCell className="font-medium">{a.name}</TableCell>
                            <TableCell className="text-right tabular-nums text-emerald-700">{gh(a.moneyIn)}</TableCell>
                            <TableCell className="text-right tabular-nums text-rose-600">{gh(a.moneyOut)}</TableCell>
                            <TableCell className={cn("text-right tabular-nums font-medium", a.moneyIn - a.moneyOut < 0 ? "text-rose-700" : "text-emerald-700")}>{gh(a.moneyIn - a.moneyOut)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody></Table>
                    </div>
                  </CardContent>
                </Card>
              )}

              <Card>
                <CardHeader className="pb-2">
                  <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
                    <div><CardTitle className="text-base">Transaction History</CardTitle>
                      <CardDescription className="text-xs">Every cash movement in the selected period.</CardDescription></div>
                    <div className="grid grid-cols-1 gap-2 sm:flex sm:flex-wrap sm:items-center">
                      <Select value={flowFilter} onValueChange={setFlowFilter}>
                        <SelectTrigger className="h-8 w-full sm:w-[11rem]"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All categories</SelectItem>
                          <SelectItem value="OperatingIn">Operating income</SelectItem>
                          <SelectItem value="OperatingOut">Operating expense</SelectItem>
                          <SelectItem value="FinancingIn">Loans & owner money in</SelectItem>
                          <SelectItem value="FinancingOut">Loans & owner money out</SelectItem>
                          <SelectItem value="EmployeeLoanOut">Staff advances paid out</SelectItem>
                          <SelectItem value="EmployeeLoanIn">Staff advances repaid</SelectItem>
                        </SelectContent>
                      </Select>
                      <Select value={typeFilter} onValueChange={setTypeFilter}>
                        <SelectTrigger className="h-8 w-full sm:w-[11rem]"><SelectValue placeholder="All types" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All types</SelectItem>
                          {typeOptions.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="p-0 md:p-2">
                  {visible.length === 0 ? (
                    <p className="px-4 py-8 text-center text-sm text-slate-500">No cash movement in this period.</p>
                  ) : (
                    <MobileCardList defaultOpen striped stripeAccent="rose" items={pg.pageItems} pagination={pg.paginationProps}
                      getKey={(r: any) => `${r.rowSource}-${r.id}`}
                      primary={(r: any) => categoryLabel(r.category)}
                      secondary={(r: any) => `${fmtDateTime(r.transactionDate, r)} · ${flowGroupLabel(r.flowGroup)}`}
                      highlights={(r: any) => [
                        { label: r.amount < 0 ? "Money out" : "Money in", value: `${r.amount < 0 ? "-" : "+"}${gh(Math.abs(r.amount))}`, accent: r.amount < 0 ? "rose" : "emerald" },
                        { label: "Running cash", value: gh(r.running), accent: "rose" },
                      ]}
                      details={(r: any) => [
                        { label: "Category", value: flowGroupLabel(r.flowGroup) },
                        { label: "Recorded as", value: sourceTypeLabel(r.sourceType) },
                        { label: "Account", value: r.accountName ?? "—" },
                        { label: "Description", value: r.description ?? "—" },
                      ]}
                      desktopTable={
                        <div className="overflow-x-auto"><Table><TableHeader><TableRow>
                          {([["date","Date",""],["type","Type",""],["category","Category",""],["description","Description",""],
                            ["in","Money In","text-right [&>div]:justify-end"],["out","Money Out","text-right [&>div]:justify-end"],
                            ["running","Running cash","text-right [&>div]:justify-end"]] as const).map(([key,label,cls]) => (
                            <SortableHeader key={key} label={label} sortKey={key} currentSort={sortKey} currentDirection={sortDir}
                              onSort={(k) => { if (k === sortKey) setSortDir(sortDir === "asc" ? "desc" : "asc"); else { setSortKey(k); setSortDir("asc") } }} className={cls} />
                          ))}
                        </TableRow></TableHeader><TableBody>
                          {pg.pageItems.map((r: any) => (
                            <TableRow key={`${r.rowSource}-${r.id}`}>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(r.transactionDate, r)}</TableCell>
                              <TableCell className="whitespace-nowrap">{categoryLabel(r.category)}</TableCell>
                              <TableCell className="whitespace-nowrap text-slate-600">{flowGroupLabel(r.flowGroup)}<span className="block text-xs text-slate-400">{sourceTypeLabel(r.sourceType)}{r.accountName ? ` · ${r.accountName}` : ""}</span></TableCell>
                              <TableCell className="max-w-sm whitespace-normal break-words align-top">{r.description ?? "—"}</TableCell>
                              <TableCell className="text-right tabular-nums text-emerald-700">{r.amount > 0 ? gh(r.amount) : "—"}</TableCell>
                              <TableCell className="text-right tabular-nums text-rose-600">{r.amount < 0 ? gh(Math.abs(r.amount)) : "—"}</TableCell>
                              <TableCell className="text-right tabular-nums font-medium">{gh(r.running)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody></Table></div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </div>
          )}
        </main>
      </div>
      <CashFlowInsightsDialog open={insightsOpen} onOpenChange={setInsightsOpen}
        periodLabel={`${dateFrom} to ${dateTo}`} totals={totals} insights={insights}
        inBuckets={inBuckets} outBuckets={outBuckets} breakdownTotals={totals}
        warnings={warnings.node} notes={notes} fmtMoney={gh} />
    </div>
    </TooltipProvider>
  )
}

function Tile({ label, value, note, tone, tip, icon }: {
  label: string; value: string; note?: string; tone?: string; tip: string; icon?: React.ReactNode
}) {
  return (
    <Card><CardContent className="p-3">
      <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
        {icon}<span className="truncate">{label}</span>
        <Tooltip><TooltipTrigger asChild>
          <button type="button" className="ml-auto shrink-0 text-slate-400 hover:text-slate-600"><Info className="h-3.5 w-3.5" /></button>
        </TooltipTrigger><TooltipContent className="max-w-xs text-xs leading-snug">{tip}</TooltipContent></Tooltip>
      </div>
      <div className={cn("mt-1 text-lg font-semibold tabular-nums", tone ?? "text-slate-900")}>{value}</div>
      {note && <div className="text-[11px] text-slate-500">{note}</div>}
    </CardContent></Card>
  )
}

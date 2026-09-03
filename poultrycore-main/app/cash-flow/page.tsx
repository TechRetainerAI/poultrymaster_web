"use client"

/**
 * Cash Flow (Poultry) — an independent financial report.
 *
 * WHAT THIS PAGE DELIBERATELY DOES NOT READ
 * -----------------------------------------
 *   cash account balances      poultrycashaccounts
 *   the cash ledger            poultrycashtransactions
 *   internal transfers         poultrycashtransfers
 *   reconciliation, counts, reconciliation adjustments
 *
 * None of those are cash flow. A transfer is the same money in a different box.
 * A reconciliation adjustment is a correction to a record, not an event in the
 * business. And reconciliation cannot both check these figures and be their
 * source -- it exists to compare this report against what the accounts hold.
 *
 * Everything here comes from GET /api/Poultry/cash-flow, which is built on the
 * transactions that actually move money: customer receipts, expenses, and
 * capital in and out (migration 235).
 *
 * CLOSING CASH WILL NOT EQUAL THE SUM OF YOUR ACCOUNT BALANCES, and that is the
 * intended outcome. The two now come from independent sources; the gap between
 * them is exactly what reconciliation exists to explain.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { SortableHeader, sortData, type SortDirection } from "@/components/ui/sortable-header"
import { usePagination } from "@/hooks/use-pagination"
import {
  Wallet, TrendingUp, TrendingDown, Plus, Lightbulb, Info,
  ExternalLink, Users, Truck, Trash2, Pencil,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt } from "@/lib/currency"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { getUserContext } from "@/lib/api/config"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { getBalanceSummary, type BalanceSummary } from "@/lib/api/balances"
import {
  getCashFlow, flowGroupLabel, type CashFlowRow, type CashFlowSummary,
} from "@/lib/api/cash-flow"
import { categoryLabel } from "@/lib/cash/cash-flow"
import { buildCashFlowAnalysis } from "@/lib/cash/cash-flow-analysis"
import {
  createCashAdjustment, updateCashAdjustment, deleteCashAdjustment,
} from "@/lib/api/cash"
import { adjustPoultryCashAccount, listPoultryCashAccounts } from "@/lib/api/poultry-finance"
import {
  CashAdjustmentDialog, ADJUSTMENT_TYPES, adjustmentTypeFromLabel,
  type CashAdjustmentSeed,
} from "@/components/cash/cash-adjustment-dialog"
import { CashFlowInsightsDialog } from "@/components/cash/cash-flow-insights-dialog"

const DEFAULT = defaultReportRange()

const EMPTY_SUMMARY: CashFlowSummary = {
  moneyIn: 0, moneyOut: 0, netCashFlow: 0, openingCash: 0, closingCash: 0,
  operatingIn: 0, operatingOut: 0, financingIn: 0, financingOut: 0, movementCount: 0,
}

/** Adjustment types that are capital, and therefore editable from this page. */
const CAPITAL_SOURCE = "Adjustment"

export default function CashFlowPage() {
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
  const [categoryFilter, setCategoryFilter] = useState("ALL")
  const [sortKey, setSortKey] = useState<string>("date")
  const [sortDir, setSortDir] = useState<SortDirection>("desc")

  const [rows, setRows] = useState<CashFlowRow[]>([])
  const [summary, setSummary] = useState<CashFlowSummary>(EMPTY_SUMMARY)
  const [prevSummary, setPrevSummary] = useState<CashFlowSummary>(EMPTY_SUMMARY)
  const [customers, setCustomers] = useState<BalanceSummary | null>(null)
  const [suppliers, setSuppliers] = useState<BalanceSummary | null>(null)
  const [accounts, setAccounts] = useState<{ accountId: number; accountName: string; isActive: boolean }[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  const [insightsOpen, setInsightsOpen] = useState(false)
  const [adjustOpen, setAdjustOpen] = useState(false)
  const [editAdjustment, setEditAdjustment] = useState<CashAdjustmentSeed | null>(null)
  const [deleteAdjustment, setDeleteAdjustment] = useState<CashFlowRow | null>(null)

  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger
  const canAdjust = canView

  // The window immediately before this one, same length, so "better than last
  // period" is like-for-like rather than a calendar-month assumption.
  const previousRange = useMemo(() => {
    const from = new Date(dateFrom)
    const to = new Date(dateTo)
    const days = Math.max(1, Math.round((to.getTime() - from.getTime()) / 86_400_000) + 1)
    const prevTo = new Date(from.getTime() - 86_400_000)
    const prevFrom = new Date(prevTo.getTime() - (days - 1) * 86_400_000)
    const iso = (d: Date) => d.toISOString().split("T")[0]
    return { from: iso(prevFrom), to: iso(prevTo), days }
  }, [dateFrom, dateTo])

  const load = useCallback(async () => {
    setError("")
    const [cur, prev, cust, supp, accts] = await Promise.allSettled([
      getCashFlow("Poultry", { fromDate: dateFrom, toDate: dateTo }),
      getCashFlow("Poultry", { fromDate: previousRange.from, toDate: previousRange.to }),
      getBalanceSummary("poultry", "customer"),
      getBalanceSummary("poultry", "supplier"),
      // Only so the adjustment dialog can offer accounts. No figure on this page
      // is derived from them.
      listPoultryCashAccounts(),
    ])

    if (cur.status === "fulfilled") {
      setRows(cur.value.rows)
      setSummary(cur.value.summary)
    } else {
      setError(cur.reason?.message ?? String(cur.reason))
      setRows([])
      setSummary(EMPTY_SUMMARY)
    }

    setPrevSummary(prev.status === "fulfilled" ? prev.value.summary : EMPTY_SUMMARY)
    setCustomers(cust.status === "fulfilled" ? cust.value : null)
    setSuppliers(supp.status === "fulfilled" ? supp.value : null)
    setAccounts(
      accts.status === "fulfilled"
        ? (accts.value ?? []).map((a: any) => ({
            accountId: a.poultryCashAccountId,
            accountName: a.accountName,
            isActive: a.isActive,
          }))
        : [],
    )
    setLoading(false)
  }, [dateFrom, dateTo, previousRange.from, previousRange.to])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    setLoading(true)
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  // ---- derived ---------------------------------------------------------------
  /** Buckets for the breakdowns, grouped by what the money was FOR. */
  const bucketsFor = useCallback((direction: "in" | "out") => {
    const want = direction === "in" ? 1 : -1
    const acc = new Map<string, { label: string; amount: number; count: number }>()
    let total = 0
    for (const r of rows) {
      if (Math.sign(r.amount) !== want || r.amount === 0) continue
      const label = categoryLabel(r.category)
      const b = acc.get(label)
      if (b) { b.amount += Math.abs(r.amount); b.count += 1 }
      else acc.set(label, { label, amount: Math.abs(r.amount), count: 1 })
      total += Math.abs(r.amount)
    }
    return [...acc.values()]
      .sort((a, b) => b.amount - a.amount)
      .map((b) => ({
        key: b.label,
        label: b.label,
        amount: Math.round(b.amount * 100) / 100,
        count: b.count,
        percent: total === 0 ? 0 : Math.round((b.amount / total) * 1000) / 10,
      }))
  }, [rows])

  const inBuckets = useMemo(() => bucketsFor("in"), [bucketsFor])
  const outBuckets = useMemo(() => bucketsFor("out"), [bucketsFor])

  const totals = useMemo(
    () => ({
      moneyIn: summary.moneyIn,
      moneyOut: summary.moneyOut,
      net: summary.netCashFlow,
      transferVolume: 0,
      transferCount: 0,
      entryCount: summary.movementCount,
    }),
    [summary],
  )

  const analysis = useMemo(
    () => buildCashFlowAnalysis({
      moneyIn: summary.moneyIn,
      moneyOut: summary.moneyOut,
      netCashFlow: summary.netCashFlow,
      operatingIn: summary.operatingIn,
      operatingOut: summary.operatingOut,
      financingIn: summary.financingIn,
      financingOut: summary.financingOut,
      cashAtHand: summary.closingCash,
      // Retired concepts: this page no longer reads the ledger, so there is no
      // "off ledger" and no transfer to report.
      offLedgerIn: 0, offLedgerOut: 0, transferVolume: 0,
      movementCount: summary.movementCount,
      daysInPeriod: previousRange.days,
      previousMoneyIn: prevSummary.moneyIn,
      previousMoneyOut: prevSummary.moneyOut,
      previousNetCashFlow: prevSummary.netCashFlow,
      moneyInByCategory: inBuckets.map((b) => ({ label: b.label, amount: b.amount, sharePercent: b.percent })),
      moneyOutByCategory: outBuckets.map((b) => ({ label: b.label, amount: b.amount, sharePercent: b.percent })),
    }, gh),
    [summary, prevSummary, previousRange.days, inBuckets, outBuckets, gh],
  )

  /** The analysis, in the shape the shared insights dialog renders. */
  const insights = useMemo(
    () => analysis.map((a) => ({
      id: a.id,
      tone: (a.tone === "good" ? "good" : a.tone === "watch" ? "warn" : "neutral") as
        "good" | "bad" | "warn" | "neutral",
      headline: a.title,
      detail: a.detail,
    })),
    [analysis],
  )

  /**
   * Only genuine problems here. Money moving without a cash account is no
   * longer even a concept on this page -- the report reads the transaction, not
   * the account it did or did not touch.
   */
  const warnings = useMemo(() => {
    const items: React.ReactNode[] = []
    if (summary.closingCash < 0) {
      items.push(
        <Alert key="negative" className="border-rose-200 bg-rose-50 py-2">
          <Info className="h-4 w-4 text-rose-700" />
          <AlertDescription className="text-xs text-rose-900">
            <b>Closing cash is negative.</b> The recorded transactions add up to less than nothing,
            which usually means an opening balance was never entered, or spending was recorded before
            the income that funded it.
          </AlertDescription>
        </Alert>,
      )
    }
    return { count: items.length, node: items.length ? <>{items}</> : null }
  }, [summary.closingCash])

  const notes = useMemo(() => (
    <Alert className="border-slate-200 bg-slate-50 py-2">
      <Info className="h-4 w-4 text-slate-500" />
      <AlertDescription className="text-xs text-slate-700">
        These figures come from your sales, expenses and capital records — not from your cash
        account balances. Closing cash is <b>not</b> expected to match what your accounts hold;
        comparing the two is what{" "}
        <Link href="/poultry-cash-reconciliation" className="underline">reconciliation</Link> is for.
      </AlertDescription>
    </Alert>
  ), [])

  const categoryOptions = useMemo(() => {
    const seen = new Set<string>()
    for (const r of rows) seen.add(categoryLabel(r.category))
    return [...seen].sort((a, b) => a.localeCompare(b))
  }, [rows])

  // ---- transaction history ---------------------------------------------------
  const history = useMemo(() => {
    const filtered = rows
      .filter((r) => flowFilter === "ALL" || r.flowGroup === flowFilter)
      .filter((r) => categoryFilter === "ALL" || categoryLabel(r.category) === categoryFilter)

    // Running cash, in date order and BEFORE any user sort, starting from the
    // period's opening cash -- so it is a real running balance rather than a
    // within-period cumulative, and re-sorting cannot change what it means.
    const asc = [...filtered].sort((a, b) => {
      const d = (a.transactionDate ?? "").localeCompare(b.transactionDate ?? "")
      return d !== 0 ? d : a.id - b.id
    })
    let running = summary.openingCash
    const withRunning = asc.map((r) => { running += r.amount; return { ...r, running } })

    return sortData(withRunning, sortKey, sortDir, (item: any, key: string) => {
      switch (key) {
        case "date": return new Date(item.transactionDate)
        case "flow": return flowGroupLabel(item.flowGroup)
        case "category": return categoryLabel(item.category)
        case "description": return item.description ?? ""
        case "in": return item.amount > 0 ? item.amount : 0
        case "out": return item.amount < 0 ? -item.amount : 0
        case "running": return item.running
        default: return item[key]
      }
    })
  }, [rows, flowFilter, categoryFilter, sortKey, sortDir, summary.openingCash])

  const visible = useMemo(
    () => filterByDateAndSearch(history, {
      search, searchKeys: ["description", "category", "sourceType"],
      dateKey: "transactionDate",
    }),
    [history, search],
  )
  const pg = usePagination(visible)

  if (!canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-3 md:p-4">
            <Card><CardContent className="py-12 text-center text-slate-600">
              You do not have access to Cash Flow.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  return (
    <TooltipProvider delayDuration={200}>
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">

          <div className="mb-3">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Wallet className="h-5 w-5 text-emerald-600" />
                Cash Flow
              </h1>
              <p className="mt-1 text-xs text-slate-500">What the business earned and spent</p>
            </div>

            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button size="sm" variant="outline" className="whitespace-nowrap"
                      onClick={() => setInsightsOpen(true)} disabled={loading}>
                <Lightbulb className="h-4 w-4 mr-1" /> Cash Flow Insights
                {warnings.count > 0 && (
                  <span className="ml-1.5 inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-amber-500 px-1 text-[10px] font-semibold text-white">
                    {warnings.count}
                  </span>
                )}
              </Button>
              {canAdjust && (
                <Button size="sm" className="whitespace-nowrap" onClick={() => setAdjustOpen(true)}>
                  <Plus className="h-4 w-4 mr-1" /> Add Adjustment
                </Button>
              )}
              <Button asChild size="sm" variant="outline" className="whitespace-nowrap ml-auto">
                <Link href="/poultry-cash-accounts">
                  <ExternalLink className="h-4 w-4 mr-1" /> View Cash Accounts
                </Link>
              </Button>
            </div>
          </div>

          {/* Quiet panel, not an alert. It exists because the relationship
              between this page and Cash Accounts is the thing people get wrong,
              and because "closing cash does not match my accounts" is alarming
              until you know it is by design. */}
          <div className="mb-3 rounded-lg border border-slate-200 bg-white p-3">
            <p className="text-sm font-medium text-slate-900">Where your money came from and went.</p>
            <p className="mt-1 text-xs leading-snug text-slate-600">
              Built from your sales, expenses and capital records. Operating money is what the
              business earned and spent; capital is money put in or taken out by owners and lenders.
              Transfers between your own cash accounts are not cash flow and are excluded — they are
              managed in <Link href="/poultry-cash-accounts" className="underline">Cash Accounts</Link>.
              Customer and Supplier Balances show what is still owed either way.
            </p>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchPlaceholder="Search description, category…"
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
          />

          {error && <Alert variant="destructive" className="mb-3"><AlertDescription>{error}</AlertDescription></Alert>}

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">Loading cash flow…</CardContent></Card>
          ) : (
            <div className="space-y-3">

              {/* Top row IS the statement, left to right. */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                <Tile label="Opening Cash" value={gh(summary.openingCash)} note="Start of period"
                      tip="Everything recorded before this period started. Measured from your transactions, not read from an account balance." />
                <Tile label="Money In" value={gh(summary.moneyIn)} note="For selected period"
                      tone="text-emerald-700" icon={<TrendingUp className="h-3.5 w-3.5" />}
                      tip="Customer receipts plus any capital put into the business during the selected period." />
                <Tile label="Money Out" value={gh(summary.moneyOut)} note="For selected period"
                      tone="text-rose-700" icon={<TrendingDown className="h-3.5 w-3.5" />}
                      tip="Expenses paid plus any capital taken out during the selected period." />
                <Tile label="Closing Cash" value={gh(summary.closingCash)} note="End of period"
                      tone={summary.closingCash < 0 ? "text-rose-700" : undefined}
                      tip="Opening Cash plus Money In minus Money Out. This is what your records say you should hold — it is not read from your cash accounts, and comparing the two is what reconciliation is for." />
              </div>

              <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                <Tile label="Net Cash Flow"
                      value={`${summary.netCashFlow > 0 ? "+" : ""}${gh(summary.netCashFlow)}`}
                      note="For selected period"
                      tone={summary.netCashFlow >= 0 ? "text-emerald-700" : "text-rose-700"}
                      tip="Money In minus Money Out. Positive means the business ended the period with more cash than it started with." />
                <Tile label="From Trading"
                      value={`${summary.operatingIn - summary.operatingOut > 0 ? "+" : ""}${gh(summary.operatingIn - summary.operatingOut)}`}
                      note="Operating only"
                      tone={summary.operatingIn - summary.operatingOut >= 0 ? "text-emerald-700" : "text-rose-700"}
                      tip="Operating income minus operating spending, ignoring capital. This is whether the business funded itself — a healthy net figure can still hide a loss covered by an owner injection." />
                <Tile label="Customer Balances"
                      value={customers ? gh(customers.totalBalance) : "—"}
                      note={customers ? `All time · ${customers.partyCount} customers owing` : "All time"}
                      icon={<Users className="h-3.5 w-3.5" />}
                      tip="Total unpaid or partially paid customer sales. Money customers still owe you — not cash, and not counted above until it is received." />
                <Tile label="Supplier Balances"
                      value={suppliers ? gh(suppliers.totalBalance) : "—"}
                      note={suppliers ? `All time · ${suppliers.partyCount} suppliers owed` : "All time"}
                      icon={<Truck className="h-3.5 w-3.5" />}
                      tip="Total unpaid or partially paid purchases. Money you still owe suppliers — not counted above until it is paid." />
              </div>

              {/* The identity, printed. It now closes by construction, because
                  every term comes from the same transaction set -- unlike the old
                  version, which had to reconcile against account balances and
                  frequently could not. */}
              <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs tabular-nums text-slate-600">
                  <span>Opening <b className="text-slate-900">{gh(summary.openingCash)}</b></span>
                  <span className="text-emerald-700">+ in <b>{gh(summary.moneyIn)}</b></span>
                  <span className="text-rose-700">− out <b>{gh(summary.moneyOut)}</b></span>
                  <span>= closing <b className="text-slate-900">{gh(summary.closingCash)}</b></span>
                </div>
                {(summary.financingIn > 0 || summary.financingOut > 0) && (
                  <div className="mt-1 text-xs tabular-nums text-slate-500">
                    Includes
                    {summary.financingIn > 0 && <> <b>{gh(summary.financingIn)}</b> of capital in</>}
                    {summary.financingIn > 0 && summary.financingOut > 0 && " and"}
                    {summary.financingOut > 0 && <> <b>{gh(summary.financingOut)}</b> taken out</>}
                    {" "}— money put in or withdrawn by owners and lenders, not earned or spent by trading.
                  </div>
                )}
              </div>

              <Card>
                <CardHeader className="pb-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <CardTitle className="text-base">Transaction History</CardTitle>
                      <CardDescription className="text-xs">
                        Every cash movement in the selected period.
                      </CardDescription>
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                      <Select value={flowFilter} onValueChange={setFlowFilter}>
                        <SelectTrigger className="h-8 w-[11rem]"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All movement</SelectItem>
                          <SelectItem value="OperatingIn">Operating income</SelectItem>
                          <SelectItem value="OperatingOut">Operating spending</SelectItem>
                          <SelectItem value="FinancingIn">Capital received</SelectItem>
                          <SelectItem value="FinancingOut">Capital withdrawn</SelectItem>
                        </SelectContent>
                      </Select>
                      <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                        <SelectTrigger className="h-8 w-[11rem]"><SelectValue placeholder="All categories" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All categories</SelectItem>
                          {categoryOptions.map((c) => (
                            <SelectItem key={c} value={c}>{c}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                </CardHeader>
                <CardContent>
                  {visible.length === 0 ? (
                    <p className="py-8 text-center text-sm text-slate-500">
                      No cash movement in this period. Record a sale, an expense or an adjustment and
                      it appears here.
                    </p>
                  ) : (
                    <MobileCardList
                      defaultOpen
                      items={pg.pageItems}
                      pagination={pg.paginationProps}
                      getKey={(r: any) => `${r.rowSource}-${r.id}`}
                      primary={(r: any) => `${r.amount < 0 ? "−" : "+"}${gh(Math.abs(r.amount))} · ${categoryLabel(r.category)}`}
                      secondary={(r: any) => `${(r.transactionDate ?? "").split("T")[0]} · ${flowGroupLabel(r.flowGroup)}`}
                      details={(r: any) => [
                        { label: "Type", value: flowGroupLabel(r.flowGroup) },
                        { label: "Category", value: categoryLabel(r.category) },
                        { label: "Running cash", value: gh(r.running) },
                        { label: "Description", value: r.description ?? "—" },
                      ]}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                {([
                                  ["date", "Date", ""],
                                  ["flow", "Type", ""],
                                  ["category", "Category", ""],
                                  ["description", "Description", ""],
                                  ["in", "Money In", "text-right [&>div]:justify-end"],
                                  ["out", "Money Out", "text-right [&>div]:justify-end"],
                                  ["running", "Running cash", "text-right [&>div]:justify-end"],
                                ] as const).map(([key, label, cls]) => (
                                  <SortableHeader
                                    key={key}
                                    label={label}
                                    sortKey={key}
                                    currentSort={sortKey}
                                    currentDirection={sortDir}
                                    onSort={(k) => {
                                      if (k === sortKey) setSortDir(sortDir === "asc" ? "desc" : "asc")
                                      else { setSortKey(k); setSortDir("asc") }
                                    }}
                                    className={cls}
                                  />
                                ))}
                                <TableHead className="text-right">Actions</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {pg.pageItems.map((r: any) => {
                                const capital = r.flowGroup === "FinancingIn" || r.flowGroup === "FinancingOut"
                                return (
                                  <TableRow key={`${r.rowSource}-${r.id}`} className={cn(capital && "bg-slate-50")}>
                                    <TableCell className="whitespace-nowrap">
                                      {(r.transactionDate ?? "").split("T")[0]}
                                    </TableCell>
                                    <TableCell className="whitespace-nowrap">
                                      {flowGroupLabel(r.flowGroup)}
                                      {capital && (
                                        <Badge variant="outline" className="ml-2 border-0 bg-slate-100 text-slate-600"
                                               title="Money put in or taken out by owners and lenders, rather than earned or spent by trading.">
                                          capital
                                        </Badge>
                                      )}
                                    </TableCell>
                                    <TableCell className="text-slate-600">{categoryLabel(r.category)}</TableCell>
                                    <TableCell className="max-w-sm whitespace-normal break-words align-top">
                                      {r.description ?? "—"}
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums text-emerald-700">
                                      {r.amount > 0 ? gh(r.amount) : "—"}
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums text-rose-600">
                                      {r.amount < 0 ? gh(Math.abs(r.amount)) : "—"}
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums font-medium">
                                      {gh(r.running)}
                                    </TableCell>
                                    {/* Each row is owned by the module that created
                                        it. A receipt or an expense is edited where
                                        it was recorded; capital is the only thing
                                        this page owns outright. */}
                                    <TableCell className="text-right whitespace-nowrap">
                                      {r.rowSource === "Expense" && (
                                        <Button asChild size="sm" variant="ghost" title="Open this expense">
                                          <Link href={`/expenses/${r.sourceId}`}>
                                            <ExternalLink className="h-4 w-4" />
                                          </Link>
                                        </Button>
                                      )}
                                      {(r.rowSource === "Receipt" || r.rowSource === "SaleResidual") && (
                                        <Button asChild size="sm" variant="ghost" title="Open this sale">
                                          <Link href={`/sales/${r.sourceId}`}>
                                            <ExternalLink className="h-4 w-4" />
                                          </Link>
                                        </Button>
                                      )}
                                      {r.rowSource === CAPITAL_SOURCE && (
                                        <>
                                          <Button size="sm" variant="ghost" title="Edit this adjustment"
                                                  onClick={() => setEditAdjustment({
                                                    adjustmentId: Number(r.sourceId),
                                                    adjustmentType: adjustmentTypeFromLabel(r.sourceType),
                                                    adjustmentDate: r.transactionDate,
                                                    amount: r.amount,
                                                    description: r.description ?? "",
                                                  })}>
                                            <Pencil className="h-4 w-4 text-slate-600" />
                                          </Button>
                                          <Button size="sm" variant="ghost" title="Delete this adjustment"
                                                  onClick={() => setDeleteAdjustment(r)}>
                                            <Trash2 className="h-4 w-4 text-rose-600" />
                                          </Button>
                                        </>
                                      )}
                                    </TableCell>
                                  </TableRow>
                                )
                              })}
                            </TableBody>
                          </Table>
                        </div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </div>
          )}
        </main>
      </div>

      <CashFlowInsightsDialog
        open={insightsOpen}
        onOpenChange={setInsightsOpen}
        periodLabel={`${dateFrom} to ${dateTo}`}
        totals={totals}
        insights={insights}
        inBuckets={inBuckets}
        outBuckets={outBuckets}
        breakdownTotals={totals}
        warnings={warnings.node}
        notes={notes}
        fmtMoney={gh}
      />

      <ConfirmDeleteDialog
        open={!!deleteAdjustment}
        onOpenChange={(o: boolean) => { if (!o) setDeleteAdjustment(null) }}
        title="Delete this adjustment?"
        description="It stops being counted in Cash Flow. Any cash account balance it moved is not affected — correct that from Cash Accounts if you need to."
        confirmLabel="Delete adjustment"
        errorTitle="Could not delete the adjustment"
        onConfirm={async () => {
          if (!deleteAdjustment) return
          const { farmId } = getUserContext()
          const res = await deleteCashAdjustment(Number(deleteAdjustment.sourceId), farmId)
          if (!res.success) throw new Error(res.message ?? "Could not delete the adjustment.")
          setDeleteAdjustment(null)
          await load()
        }}
      />

      <CashAdjustmentDialog
        open={adjustOpen || !!editAdjustment}
        onOpenChange={(o) => { if (!o) { setAdjustOpen(false); setEditAdjustment(null) } }}
        accounts={accounts}
        fmtMoney={gh}
        editing={editAdjustment}
        onSubmit={async ({ accountId, adjustmentType, adjustmentDate, amount, description }) => {
          const { userId, farmId } = getUserContext()

          if (editAdjustment) {
            const saved = await updateCashAdjustment(editAdjustment.adjustmentId, {
              farmId, adjustmentDate, adjustmentType, amount,
              description: description || null,
            })
            if (!saved.success) throw new Error(saved.message ?? "Could not update the adjustment.")
            return
          }

          // ALWAYS record the capital event, because that is what Cash Flow
          // reads. Posting only to a cash account would move a balance while
          // leaving the injection invisible here.
          const created = await createCashAdjustment({
            userId, farmId, adjustmentDate, adjustmentType, amount,
            description: description || null,
          })
          if (!created.success) throw new Error(created.message ?? "Could not record the adjustment.")

          // If an account was named, move its balance too. Not a double count:
          // Cash Flow reads the capital record, the account balance comes from
          // the ledger, and the two are independent by design.
          if (accountId != null) {
            const label = ADJUSTMENT_TYPES.find((t) => t.value === adjustmentType)?.label ?? adjustmentType
            await adjustPoultryCashAccount(accountId, {
              amount,
              reason: description ? `${label} - ${description}` : label,
            })
          }
        }}
        onDone={() => { void load() }}
      />
    </div>
    </TooltipProvider>
  )
}

/** Compact KPI card with a tooltip on every figure. */
function Tile({
  label, value, note, tone, tip, icon,
}: {
  label: string; value: string; note?: string; tone?: string; tip: string
  icon?: React.ReactNode
}) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
          {icon}
          <span className="truncate">{label}</span>
          <Tooltip>
            <TooltipTrigger asChild>
              <button type="button" className="ml-auto shrink-0 text-slate-400 hover:text-slate-600">
                <Info className="h-3.5 w-3.5" />
              </button>
            </TooltipTrigger>
            <TooltipContent className="max-w-xs text-xs leading-snug">{tip}</TooltipContent>
          </Tooltip>
        </div>
        <div className={cn("mt-1 text-lg font-semibold tabular-nums", tone ?? "text-slate-900")}>
          {value}
        </div>
        {note && <div className="text-[11px] text-slate-500">{note}</div>}
      </CardContent>
    </Card>
  )
}

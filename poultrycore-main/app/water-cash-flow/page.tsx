"use client"

export const dynamic = "force-dynamic"

/**
 * Water Cash Flow — company-wide money movement.
 *
 * The Water twin of app/cash-flow/page.tsx. Same arithmetic, same components,
 * same shared lib/cash/cash-flow module; only the API client, the routes and two
 * genuine behavioural differences change. Keep the two in step.
 *
 * Replaces /water-reports/cash-flow, which computed inflow and outflow WITHOUT
 * excluding internal transfers — so a MoMo-to-Bank move inflated both — and
 * passed a bare toDate, which meant "today" returned nothing. Both are fixed
 * here; that report has been retired rather than left to disagree with this.
 *
 * Differs from Poultry in two places, both marked below:
 *   1. Water expenses have an approval lifecycle, so only APPROVED ones are
 *      expected to have posted cash.
 *   2. Water has a real CustomerPayment source type, so its Money In breakdown
 *      separates a sale from the cash that later settles it. Poultry collapses
 *      both into 'Sale' and cannot.
 *
 * All arithmetic lives in lib/cash/cash-flow.ts and is unit-tested. This file
 * fetches, filters and renders; it computes nothing of consequence.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import {
  Wallet, TrendingUp, TrendingDown, Scale, Lightbulb, AlertTriangle, Info,
  ExternalLink, Users, Truck,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { getBalanceSummary, type BalanceSummary } from "@/lib/api/balances"
import {
  listWaterCashTransactions, getWaterCashAccountCountStatus,
  listWaterExpenses,
  adjustWaterCashAccount, WATER_CASH_REASONS,
  type WaterCashTransaction, type WaterCashAccountCountStatus, type WaterExpense,
} from "@/lib/api/water"
import {
  buildCashFlowInsights, cashByAccount, cashFlowTotals, cashIdentity, calculatedCashAtHand,
  flowLabel, groupByFlow, isInternalTransfer, withinRange,
  type LedgerEntry,
} from "@/lib/cash/cash-flow"
import { CashFlowInsightsDialog } from "@/components/cash/cash-flow-insights-dialog"
import { RecordCashAdjustmentDialog } from "@/components/cash/record-cash-adjustment-dialog"

export default function WaterCashFlowPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const permissions = usePermissions()

  const DEFAULT = defaultReportRange("thisMonth")
  const [dateFrom, setDateFrom] = useState(DEFAULT.from)
  const [dateTo, setDateTo] = useState(DEFAULT.to)
  const [search, setSearch] = useState("")
  const [sourceFilter, setSourceFilter] = useState("ALL")
  const [directionFilter, setDirectionFilter] = useState<"ALL" | "in" | "out">("ALL")
  const [showTransfers, setShowTransfers] = useState(false)

  const [txns, setTxns] = useState<WaterCashTransaction[]>([])
  const [status, setStatus] = useState<WaterCashAccountCountStatus[]>([])
  const [customers, setCustomers] = useState<BalanceSummary | null>(null)
  const [suppliers, setSuppliers] = useState<BalanceSummary | null>(null)
  const [expenses, setExpenses] = useState<WaterExpense[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  const [insightsOpen, setInsightsOpen] = useState(false)
  const [adjustOpen, setAdjustOpen] = useState(false)

  // Nav hides this from anyone without the cash-ledger flag; this closes the
  // deep link. Same flag as /water-cash-accounts and /water-cash-reconciliation,
  // which show the same rows — see lib/utils/water-nav-access.ts.
  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger
  const canAdjust = canView

  const load = useCallback(async () => {
    setError("")

    // allSettled throughout: six independent reads, and one failing must not
    // blank the other five. A farm with no supplier module still gets its cards.
    const [txRes, stRes, custRes, suppRes, expRes] = await Promise.allSettled([
      // ALL TIME, both of them, sliced by date in the browser below.
      //
      // The breakdown cards cover every movement ever, so the range cannot be
      // applied at the API. Fetching once and slicing locally also means moving
      // the date range no longer costs a round trip — the same shape
      // /cash-flow uses on the poultry rail.
      listWaterCashTransactions(),
      getWaterCashAccountCountStatus(),
      getBalanceSummary("water", "customer"),
      getBalanceSummary("water", "supplier"),
      listWaterExpenses(),
    ])

    if (txRes.status === "fulfilled") setTxns(txRes.value ?? [])
    else setError(txRes.reason?.message ?? String(txRes.reason))

    setStatus(stRes.status === "fulfilled" ? (stRes.value ?? []) : [])
    setCustomers(custRes.status === "fulfilled" ? custRes.value : null)
    setSuppliers(suppRes.status === "fulfilled" ? suppRes.value : null)

    setExpenses(expRes.status === "fulfilled" && Array.isArray(expRes.value) ? expRes.value : [])

    setLoading(false)
    // No date dependency on purpose: every fetch above is all-time and the range
    // is applied downstream, so moving the dates re-slices what is already here
    // instead of re-reading the whole ledger.
  }, [])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    setLoading(true)
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  // ---- derived, all from the pure module -----------------------------------
  // lib/cash/cash-flow is rail-agnostic — it names the key fields `id` and
  // `accountId` so Water can share it. Mapped here rather than cast: a cast
  // would compile and then hand the module undefined ids at runtime.
  const entries: LedgerEntry[] = useMemo(() => txns.map((t) => ({
    id: t.waterCashTransactionId,
    accountId: t.waterCashAccountId,
    accountName: t.accountName,
    transactionDate: t.transactionDate,
    transactionType: t.transactionType,
    sourceType: t.sourceType,
    amount: t.amount,
    description: t.description,
  })), [txns])
  /**
   * Expenses with no cash account never reach the ledger, so Money Out
   * understates and Net Cash Flow flatters the business.
   *
   * DIFFERS FROM POULTRY: water expenses have an approval lifecycle, and only an
   * Approved one is expected to have moved cash. Flagging a Draft would be a
   * false alarm about money that has not been spent yet.
   *
   * Credit expenses are EXCLUDED, and that is the point. Water requires a cash
   * account unless the payment method is Credit (app/water-expenses/page.tsx:174),
   * so "no account" here means "bought on credit, not yet paid" — no cash has
   * moved and Money Out is right to leave it out. Counting them would report
   * correct data as a problem.
   *
   * The date range is applied HERE rather than by the API, because the fetch had
   * to go all-time for the breakdowns. Without this filter the warning would
   * count every unlinked expense the farm has ever had.
   */
  const unlinked = useMemo(() => {
    const missing = expenses.filter(
      (e) => e.status === "Approved"
        && e.waterCashAccountId == null
        && e.paymentMethod !== "Credit"
        && withinRange(e.expenseDate, dateFrom, dateTo),
    )
    return {
      count: missing.length,
      total: missing.reduce((s, e) => s + (Number(e.amount) || 0), 0),
    }
  }, [expenses, dateFrom, dateTo])

  /** The selected period. `entries` stays all-time — see the fetch above. */
  const periodEntries = useMemo(
    () => entries.filter((e) => withinRange(e.transactionDate, dateFrom, dateTo)),
    [entries, dateFrom, dateTo],
  )

  const totals = useMemo(() => cashFlowTotals(periodEntries), [periodEntries])

  /**
   * ALL TIME, unlike the figures above. Where money has come from and gone is a
   * question about the business, not about the range someone has selected; the
   * cards are labelled "all time" so the two scopes cannot be confused.
   */
  const inBuckets = useMemo(() => groupByFlow(entries, "in"), [entries])
  const outBuckets = useMemo(() => groupByFlow(entries, "out"), [entries])
  const allTimeTotals = useMemo(() => cashFlowTotals(entries), [entries])
  const accountRows = useMemo(() => cashByAccount(status.map((a) => ({
    accountId: a.waterCashAccountId,
    accountName: a.accountName,
    accountType: a.accountType,
    isActive: a.isActive,
    currentBalance: a.currentBalance,
    ledgerBalance: a.ledgerBalance,
    cacheDrift: a.cacheDrift,
    lastReconciledAt: a.lastReconciledAt,
    daysSinceReconciled: a.daysSinceReconciled,
    unclearedCount: a.unclearedCount,
  }))), [status])
  const cashAtHand = useMemo(() => calculatedCashAtHand(accountRows), [accountRows])

  // The ledger has no opening-balance row, so in-minus-out never equals cash at
  // hand on its own. currentBalance - ledger movement recovers the opening total.
  const openingTotal = useMemo(
    () => accountRows.reduce((s, a) => s + (a.ledgerBalance ?? 0), 0) - (totals.moneyIn - totals.moneyOut),
    [accountRows, totals],
  )
  const identity = useMemo(
    () => cashIdentity({ openingTotal, totals, reportedCash: cashAtHand }),
    [openingTotal, totals, cashAtHand],
  )

  const attention = accountRows.filter((a) => a.needsAttention)

  /**
   * Everything that makes the headline figures less trustworthy, composed here
   * rather than in the dialog because the links are rail-specific. `count` drives
   * the badge on the button; `node` is rendered verbatim inside Insights.
   */
  const warnings = useMemo(() => {
    const items: React.ReactNode[] = []
    if (cashAtHand < 0) {
      items.push(
        <Alert key="negative" className="border-rose-200 bg-rose-50 py-2">
          <AlertTriangle className="h-4 w-4 text-rose-700" />
          <AlertDescription className="text-xs text-rose-900">
            <b>Calculated Cash at Hand is negative.</b> That usually means opening balances were never
            entered, expenses were recorded before the cash that funded them, a wrong cash account was
            chosen, or owner contributions and collections were not recorded.{" "}
            <Link href="/water-cash-accounts" className="underline">Review cash accounts</Link>.
          </AlertDescription>
        </Alert>,
      )
    }
    if (unlinked.count > 0) {
      items.push(
        <Alert key="unlinked" className="border-amber-200 bg-amber-50 py-2">
          <AlertTriangle className="h-4 w-4 text-amber-700" />
          <AlertDescription className="text-xs text-amber-900">
            {unlinked.count} {unlinked.count === 1 ? "expense" : "expenses"} totalling{" "}
            {gh(unlinked.total)} {unlinked.count === 1 ? "was" : "were"} recorded without a cash
            account, so Money Out does not include {unlinked.count === 1 ? "it" : "them"} — your real
            net is lower than shown.{" "}
            <Link href="/water-expenses" className="underline">Open Expenses</Link> to link{" "}
            {unlinked.count === 1 ? "it" : "them"}.
          </AlertDescription>
        </Alert>,
      )
    }
    if (attention.length > 0) {
      items.push(
        <Alert key="attention" className="border-sky-200 bg-sky-50 py-2">
          <Info className="h-4 w-4 text-sky-700" />
          <AlertDescription className="text-xs text-sky-900">
            {attention.length} of {accountRows.length} cash accounts need reconciling.{" "}
            <Link href="/water-cash-reconciliation" className="underline">Reconcile cash</Link>.
          </AlertDescription>
        </Alert>,
      )
    }
    return { count: items.length, node: items.length ? <>{items}</> : null }
  }, [cashAtHand, unlinked, attention.length, accountRows.length, gh])

  const insights = useMemo(() => buildCashFlowInsights({
    periodLabel: "This period",
    periodDays: Math.max(1, daysBetween(dateFrom, dateTo)),
    totals,
    cashAtHand,
    customersOwe: customers?.totalBalance ?? 0,
    weOweSuppliers: suppliers?.totalBalance ?? 0,
    topIn: inBuckets[0] ?? null,
    topOut: outBuckets[0] ?? null,
  }, gh), [dateFrom, dateTo, totals, cashAtHand, customers, suppliers, inBuckets, outBuckets, gh])

  // ---- transaction history --------------------------------------------------
  const sourceOptions = useMemo(() => {
    const seen = new Map<string, string>()
    for (const t of periodEntries) {
      if (isInternalTransfer(t)) continue
      const { key, label } = flowLabel(t.sourceType, t.description)
      if (!seen.has(key)) seen.set(key, label)
    }
    return [...seen.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [periodEntries])

  const history = useMemo(() => {
    const rows = periodEntries
      .filter((t) => showTransfers || !isInternalTransfer(t))
      .filter((t) => directionFilter === "ALL"
        || (directionFilter === "in" ? t.amount > 0 : t.amount < 0))
      .filter((t) => sourceFilter === "ALL" || flowLabel(t.sourceType, t.description).key === sourceFilter)
      .map((t) => ({ ...t, flow: flowLabel(t.sourceType, t.description) }))

    // Calendar day then id, matching the account ledger — a correction posted
    // this afternoon must not sink beneath everything else dated today. See
    // app/water-cash-accounts/[id]/page.tsx for why.
    const asc = [...rows].sort((a, b) => {
      const d = (a.transactionDate ?? "").split("T")[0].localeCompare((b.transactionDate ?? "").split("T")[0])
      return d !== 0 ? d : a.id - b.id
    })
    let running = 0
    return asc.map((r) => { running += r.amount; return { ...r, running } }).reverse()
  }, [periodEntries, showTransfers, directionFilter, sourceFilter])

  const visible = useMemo(
    () => filterByDateAndSearch(history, {
      search, searchKeys: ["description", "accountName", "sourceType", "transactionType"],
      dateKey: "transactionDate",
    }),
    [history, search],
  )
  const pg = usePagination(visible)

  if (!permissions.isLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-6">
            <Card><CardContent className="py-12 text-center text-slate-600">
              You do not have access to the cash ledger. Ask an administrator for the
              "View cash ledger" permission.
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
            {/* Description under the title, not beside it — it names what the
                page is for, so it reads as a sentence rather than a caption. */}
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Wallet className="h-5 w-5 text-sky-600" />
                Cash Flow
              </h1>
              <p className="mt-1 text-xs text-slate-500">Company-wide money movement and cash position</p>
            </div>

            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button size="sm" variant="outline" className="whitespace-nowrap"
                      onClick={() => setInsightsOpen(true)} disabled={loading}>
                <Lightbulb className="h-4 w-4 mr-1" /> Cash Flow Insights
                {/* Without this the warnings would be genuinely hidden rather
                    than relocated — the badge is what makes moving them safe. */}
                {warnings.count > 0 && (
                  <span className="ml-1.5 inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-amber-500 px-1 text-[10px] font-semibold text-white">
                    {warnings.count}
                  </span>
                )}
              </Button>
              {canAdjust && (
                <Button size="sm" className="whitespace-nowrap" onClick={() => setAdjustOpen(true)}>
                  <Scale className="h-4 w-4 mr-1" /> Record Cash Adjustment
                </Button>
              )}
              <Button asChild size="sm" variant="outline" className="whitespace-nowrap ml-auto">
                <Link href="/water-cash-accounts">
                  <ExternalLink className="h-4 w-4 mr-1" /> View Cash Accounts
                </Link>
              </Button>
            </div>
          </div>

          {/* Purpose panel — quiet, not an alert. It exists because "cash flow"
              and "cash accounts" are easy to confuse, and because excluding
              transfers from the totals is surprising until it is explained. */}
          <div className="mb-3 rounded-lg border border-slate-200 bg-white p-3">
            <p className="text-sm font-medium text-slate-900">Company-wide money movement.</p>
            <p className="mt-1 text-xs leading-snug text-slate-600">
              Across the whole company, see how much money came in, how much went out, and whether the
              business was cash positive or cash negative. This page summarises money in and money out
              across all cash accounts, excluding internal transfers from net totals. Customer Balances
              show money customers still owe the company. Supplier Balances show money the company still
              owes suppliers.
            </p>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchPlaceholder="Search description, account, source…"
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
          />

          {error && <Alert variant="destructive" className="mb-3"><AlertDescription>{error}</AlertDescription></Alert>}

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">Loading cash flow…</CardContent></Card>
          ) : (
            <div className="space-y-3">

              <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-2">
                <Tile label="Total Money In" value={gh(totals.moneyIn)} note="For selected period"
                      tone="text-emerald-700" icon={<TrendingUp className="h-3.5 w-3.5" />}
                      tip="Total cash received during the selected date range, excluding transfers between company cash accounts." />
                <Tile label="Total Money Out" value={gh(totals.moneyOut)} note="For selected period"
                      tone="text-rose-700" icon={<TrendingDown className="h-3.5 w-3.5" />}
                      tip="Total cash paid out during the selected date range, excluding transfers between company cash accounts." />
                <Tile label="Net Cash Flow"
                      value={`${totals.net > 0 ? "+" : ""}${gh(totals.net)}`} note="For selected period"
                      tone={totals.net >= 0 ? "text-emerald-700" : "text-rose-700"}
                      tip="Money In minus Money Out for the selected date range. Positive means the business brought in more cash than it spent." />
                <Tile label="Customer Balances"
                      value={customers ? gh(customers.totalBalance) : "—"}
                      note={customers ? `All time · ${customers.partyCount} customers owing` : "All time"}
                      icon={<Users className="h-3.5 w-3.5" />}
                      tip="Total unpaid or partially paid customer sales. This is money customers still owe the company." />
                <Tile label="Supplier Balances"
                      value={suppliers ? gh(suppliers.totalBalance) : "—"}
                      note={suppliers ? `All time · ${suppliers.partyCount} suppliers owed` : "All time"}
                      icon={<Truck className="h-3.5 w-3.5" />}
                      tip="Total unpaid or partially paid purchases. This is money the company still owes suppliers." />
                <Tile label="Calculated Cash at Hand" value={gh(cashAtHand)} note="All time"
                      tone={cashAtHand < 0 ? "text-rose-700" : undefined}
                      tip="This is calculated from recorded cash-account transactions. It may be wrong if sales, expenses, owner contributions, transfers, withdrawals or reconciliations were not recorded correctly. Reconcile cash accounts regularly to confirm the real available cash." />
              </div>

              {/* The identity, printed. Money in minus money out does not equal
                  cash at hand without the opening balances, and everybody who
                  checks discovers that the hard way. */}
              <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs tabular-nums text-slate-600">
                  <span>Opening balances <b className="text-slate-900">{gh(identity.openingTotal)}</b></span>
                  <span className="text-emerald-700">+ money in <b>{gh(identity.moneyIn)}</b></span>
                  <span className="text-rose-700">− money out <b>{gh(identity.moneyOut)}</b></span>
                  <span>= <b className="text-slate-900">{gh(identity.impliedCash)}</b></span>
                  {identity.balances ? (
                    <span className="text-emerald-700">✓ matches your accounts</span>
                  ) : (
                    <span className="text-amber-700">
                      — your accounts hold {gh(identity.reportedCash)}, a difference of {gh(Math.abs(identity.discrepancy))}
                    </span>
                  )}
                </div>
              </div>

              {/* The warnings and the two breakdowns used to sit here. They moved
                  into Cash Flow Insights: on a page whose job is to state the
                  position, three alerts above the content made every visit read
                  like something was wrong. The button that opens them is the
                  first action in the header, and it carries a count when any are
                  live — so nothing is buried, it is just one click away. */}

              {/* Cash by Account moved to the cash accounts page. Per-account
                  balances belong where accounts are managed — and, more to the
                  point, next to Recalculate, which is the fix when the calculated
                  balance and the stored one disagree. This page keeps the company
                  figure; Calculated Cash at Hand above links through to the detail. */}

              {/* Internal Transfers had a table here. Removed: a transfer is not
                  cash flow — it is the same money in a different pocket, which is
                  why it is excluded from every total above. Listing it on this
                  page invited reading it as movement. It is still reachable two
                  ways: the Include transfers toggle on the history below, and
                  the cash accounts page, where transfers are actually made. */}

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
                      <Select value={directionFilter} onValueChange={(v) => setDirectionFilter(v as any)}>
                        <SelectTrigger className="h-8 w-[9rem]"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">Money in and out</SelectItem>
                          <SelectItem value="in">Money in only</SelectItem>
                          <SelectItem value="out">Money out only</SelectItem>
                        </SelectContent>
                      </Select>
                      <Select value={sourceFilter} onValueChange={setSourceFilter}>
                        <SelectTrigger className="h-8 w-[11rem]"><SelectValue placeholder="All sources" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All sources</SelectItem>
                          {sourceOptions.map(([key, label]) => (
                            <SelectItem key={key} value={key}>{label}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <div className="flex items-center gap-1.5">
                        <Switch id="show-transfers" checked={showTransfers} onCheckedChange={setShowTransfers} />
                        <Label htmlFor="show-transfers" className="text-xs text-slate-600">
                          Include transfers
                        </Label>
                      </div>
                    </div>
                  </div>
                </CardHeader>
                <CardContent>
                  {visible.length === 0 ? (
                    <p className="py-8 text-center text-sm text-slate-500">
                      No cash movement in this period. Record sales, expenses or an adjustment against a
                      cash account and it appears here.
                    </p>
                  ) : (
                    <MobileCardList
                      items={pg.pageItems}
                      pagination={pg.paginationProps}
                      getKey={(r: any) => r.id}
                      primary={(r: any) => `${r.amount < 0 ? "−" : "+"}${gh(Math.abs(r.amount))} · ${r.flow.label}`}
                      secondary={(r: any) => `${(r.transactionDate ?? "").split("T")[0]} · ${r.accountName ?? "—"}`}
                      details={(r: any) => [
                        { label: "Account", value: r.accountName ?? "—" },
                        { label: "Source", value: r.flow.label },
                        { label: "Running (period)", value: gh(r.running) },
                        { label: "Description", value: r.description ?? "—" },
                      ]}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Date</TableHead>
                                <TableHead>Source</TableHead>
                                <TableHead>Cash Account</TableHead>
                                <TableHead>Description</TableHead>
                                <TableHead className="text-right">Money In</TableHead>
                                <TableHead className="text-right">Money Out</TableHead>
                                <TableHead className="text-right">Running (period)</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {pg.pageItems.map((r: any) => (
                                <TableRow key={r.id}
                                          className={cn(isInternalTransfer(r) && "bg-slate-50")}>
                                  <TableCell className="whitespace-nowrap">
                                    {(r.transactionDate ?? "").split("T")[0]}
                                  </TableCell>
                                  <TableCell>
                                    {r.flow.label}
                                    {isInternalTransfer(r) && (
                                      <Badge variant="outline" className="ml-2 border-0 bg-slate-100 text-slate-600">
                                        excluded
                                      </Badge>
                                    )}
                                  </TableCell>
                                  <TableCell className="text-slate-600">{r.accountName ?? "—"}</TableCell>
                                  <TableCell className="max-w-sm whitespace-normal break-words align-top">
                                    {r.description ?? "—"}
                                  </TableCell>
                                  <TableCell className="text-right tabular-nums text-emerald-700">
                                    {r.amount > 0 ? gh(r.amount) : "—"}
                                  </TableCell>
                                  <TableCell className="text-right tabular-nums text-rose-600">
                                    {r.amount < 0 ? gh(Math.abs(r.amount)) : "—"}
                                  </TableCell>
                                  {/* Starts at zero for the period. A running
                                      balance ACROSS accounts is meaningless —
                                      opening balances live on the accounts, not
                                      in the ledger — so this is explicitly a
                                      within-period cumulative, not a balance. */}
                                  <TableCell className="text-right tabular-nums font-medium">
                                    {gh(r.running)}
                                  </TableCell>
                                </TableRow>
                              ))}
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
        breakdownTotals={allTimeTotals}
        breakdownScope="all-time"
        warnings={warnings.node}
        fmtMoney={gh}
      />

      <RecordCashAdjustmentDialog
        open={adjustOpen}
        onOpenChange={setAdjustOpen}
        accounts={accountRows}
        reasons={WATER_CASH_REASONS}
        fmtMoney={gh}
        reconcileHref="/water-cash-reconciliation"
        onSubmit={async ({ accountId, amount, reason }) => {
          await adjustWaterCashAccount(accountId, { amount, reason })
        }}
        onDone={() => { void load() }}
      />
    </div>
    </TooltipProvider>
  )
}

/** Compact KPI card with the tooltip the spec asks for on every figure. */
function Tile({
  label, value, note, tone, tip, href, icon,
}: {
  label: string; value: string; note?: string; tone?: string; tip: string
  href?: string; icon?: React.ReactNode
}) {
  const body = (
    <Card className={cn("h-full", href && "transition-colors hover:border-slate-400")}>
      <CardContent className="p-2.5">
        <div className="flex items-center gap-1 text-[11px] leading-tight text-slate-500">
          {icon}
          <span className="truncate">{label}</span>
          <Tooltip>
            <TooltipTrigger asChild>
              <button type="button" aria-label={`About ${label}`} className="ml-auto shrink-0">
                <Info className="h-3 w-3 text-slate-400" />
              </button>
            </TooltipTrigger>
            <TooltipContent className="max-w-xs text-xs leading-snug">{tip}</TooltipContent>
          </Tooltip>
        </div>
        <div className={cn("text-base font-semibold tabular-nums leading-snug", tone)}>{value}</div>
        {note && <div className="text-[10px] leading-tight text-slate-500">{note}</div>}
      </CardContent>
    </Card>
  )
  return href ? <Link href={href} className="block">{body}</Link> : body
}

function daysBetween(from: string, to: string): number {
  const a = new Date(`${from}T00:00:00`).getTime()
  const b = new Date(`${to}T00:00:00`).getTime()
  if (Number.isNaN(a) || Number.isNaN(b)) return 1
  return Math.max(1, Math.round((b - a) / 86_400_000) + 1)
}

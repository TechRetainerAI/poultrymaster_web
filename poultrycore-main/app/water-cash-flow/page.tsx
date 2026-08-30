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
  ArrowLeftRight, ExternalLink, Users, Truck,
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
  listWaterCashTransactions, listWaterCashTransfers, getWaterCashAccountCountStatus,
  listWaterExpenses,
  adjustWaterCashAccount, WATER_CASH_REASONS,
  type WaterCashTransaction, type WaterCashTransfer, type WaterCashAccountCountStatus,
} from "@/lib/api/water"
import {
  buildCashFlowInsights, cashByAccount, cashFlowTotals, cashIdentity, calculatedCashAtHand,
  flowLabel, groupByFlow, isInternalTransfer, summariseTransfers,
  type LedgerEntry,
} from "@/lib/cash/cash-flow"
import { FlowBreakdownCard } from "@/components/cash/flow-breakdown-card"
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
  const [transfers, setTransfers] = useState<WaterCashTransfer[]>([])
  const [customers, setCustomers] = useState<BalanceSummary | null>(null)
  const [suppliers, setSuppliers] = useState<BalanceSummary | null>(null)
  const [unlinked, setUnlinked] = useState<{ count: number; total: number }>({ count: 0, total: 0 })
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
    const [txRes, stRes, trRes, custRes, suppRes, expRes] = await Promise.allSettled([
      listWaterCashTransactions({ fromDate: dateFrom, toDate: dateTo }),
      getWaterCashAccountCountStatus(),
      listWaterCashTransfers(),
      getBalanceSummary("water", "customer"),
      getBalanceSummary("water", "supplier"),
      listWaterExpenses({ fromDate: dateFrom, toDate: dateTo }),
    ])

    if (txRes.status === "fulfilled") setTxns(txRes.value ?? [])
    else setError(txRes.reason?.message ?? String(txRes.reason))

    setStatus(stRes.status === "fulfilled" ? (stRes.value ?? []) : [])
    setTransfers(trRes.status === "fulfilled" ? (trRes.value ?? []) : [])
    setCustomers(custRes.status === "fulfilled" ? custRes.value : null)
    setSuppliers(suppRes.status === "fulfilled" ? suppRes.value : null)

    // Expenses with no cash account never reach the ledger, so Money Out
    // understates and Net Cash Flow flatters the business.
    //
    // DIFFERS FROM POULTRY: water expenses have an approval lifecycle, and only
    // an Approved one is expected to have moved cash. Flagging a Draft would be
    // a false alarm about money that has not been spent yet. The API already
    // applied the date range, so there is nothing to filter here but status.
    if (expRes.status === "fulfilled" && Array.isArray(expRes.value)) {
      const missing = expRes.value.filter(
        (e) => e.status === "Approved" && e.waterCashAccountId == null,
      )
      setUnlinked({
        count: missing.length,
        total: missing.reduce((s, e) => s + (Number(e.amount) || 0), 0),
      })
    } else {
      setUnlinked({ count: 0, total: 0 })
    }

    setLoading(false)
  }, [dateFrom, dateTo])

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
  const totals = useMemo(() => cashFlowTotals(entries), [entries])
  const inBuckets = useMemo(() => groupByFlow(entries, "in"), [entries])
  const outBuckets = useMemo(() => groupByFlow(entries, "out"), [entries])
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

  const transferSummary = useMemo(
    () => summariseTransfers(transfers.map((t) => ({
      id: t.waterCashTransferId,
      fromAccountName: t.fromAccountName,
      toAccountName: t.toAccountName,
      transferDate: t.transferDate,
      amount: t.amount,
      status: t.status,
    })), { from: dateFrom, to: dateTo }),
    [transfers, dateFrom, dateTo],
  )
  const attention = accountRows.filter((a) => a.needsAttention)

  const insights = useMemo(() => buildCashFlowInsights({
    periodLabel: "This period",
    periodDays: Math.max(1, daysBetween(dateFrom, dateTo)),
    totals,
    cashAtHand,
    customersOwe: customers?.totalBalance ?? 0,
    weOweSuppliers: suppliers?.totalBalance ?? 0,
    topIn: inBuckets[0] ?? null,
    topOut: outBuckets[0] ?? null,
    accountsNeedingAttention: attention.length,
    unlinkedExpenseCount: unlinked.count,
  }, gh), [dateFrom, dateTo, totals, cashAtHand, customers, suppliers, inBuckets, outBuckets, attention.length, unlinked.count, gh])

  // ---- transaction history --------------------------------------------------
  const sourceOptions = useMemo(() => {
    const seen = new Map<string, string>()
    for (const t of entries) {
      if (isInternalTransfer(t)) continue
      const { key, label } = flowLabel(t.sourceType, t.description)
      if (!seen.has(key)) seen.set(key, label)
    }
    return [...seen.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [entries])

  const history = useMemo(() => {
    const rows = entries
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
  }, [entries, showTransfers, directionFilter, sourceFilter])

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
                      note={customers ? `${customers.partyCount} customers owing` : "Current balance"}
                      href="/water-customer-balances" icon={<Users className="h-3.5 w-3.5" />}
                      tip="Total unpaid or partially paid customer sales. This is money customers still owe the company." />
                <Tile label="Supplier Balances"
                      value={suppliers ? gh(suppliers.totalBalance) : "—"}
                      note={suppliers ? `${suppliers.partyCount} suppliers owed` : "Current balance"}
                      href="/water-supplier-balances" icon={<Truck className="h-3.5 w-3.5" />}
                      tip="Total unpaid or partially paid purchases. This is money the company still owes suppliers." />
                <Tile label="Calculated Cash at Hand" value={gh(cashAtHand)} note="Across all cash accounts"
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

              {cashAtHand < 0 && (
                <Alert className="border-rose-200 bg-rose-50 py-2">
                  <AlertTriangle className="h-4 w-4 text-rose-700" />
                  <AlertDescription className="text-xs text-rose-900">
                    <b>Calculated Cash at Hand is negative.</b> That usually means opening balances were
                    never entered, expenses were recorded before the cash that funded them, a wrong cash
                    account was chosen, or owner contributions and collections were not recorded.{" "}
                    <Link href="/water-cash-accounts" className="underline">Review cash accounts</Link>.
                  </AlertDescription>
                </Alert>
              )}

              {unlinked.count > 0 && (
                <Alert className="border-amber-200 bg-amber-50 py-2">
                  <AlertTriangle className="h-4 w-4 text-amber-700" />
                  <AlertDescription className="text-xs text-amber-900">
                    {unlinked.count} {unlinked.count === 1 ? "expense" : "expenses"} totalling{" "}
                    {gh(unlinked.total)} {unlinked.count === 1 ? "was" : "were"} recorded without a cash
                    account, so Money Out does not include {unlinked.count === 1 ? "it" : "them"} — your
                    real net is lower than shown.{" "}
                    <Link href="/water-expenses" className="underline">Open Expenses</Link> to link{" "}
                    {unlinked.count === 1 ? "it" : "them"}.
                  </AlertDescription>
                </Alert>
              )}

              {attention.length > 0 && (
                <Alert className="border-sky-200 bg-sky-50 py-2">
                  <Info className="h-4 w-4 text-sky-700" />
                  <AlertDescription className="text-xs text-sky-900">
                    {attention.length} of {accountRows.length} cash accounts need reconciling.{" "}
                    <Link href="/water-cash-reconciliation" className="underline">Reconcile cash</Link>.
                  </AlertDescription>
                </Alert>
              )}

              <div className="grid gap-3 lg:grid-cols-2">
                <FlowBreakdownCard
                  title="Money In by Source" direction="in" buckets={inBuckets}
                  total={totals.moneyIn} fmtMoney={gh}
                  description="Where the money came from. Internal transfers excluded."
                  emptyText="No money came in during this period."
                />
                <FlowBreakdownCard
                  title="Money Out by Use" direction="out" buckets={outBuckets}
                  total={totals.moneyOut} fmtMoney={gh}
                  description="Where the money went. Internal transfers excluded."
                  emptyText="No money went out during this period."
                />
              </div>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Cash by Account</CardTitle>
                  <CardDescription className="text-xs">
                    Calculated from each account's transactions. Totals {gh(cashAtHand)}.
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  {accountRows.length === 0 ? (
                    <p className="py-6 text-center text-sm text-slate-500">
                      No cash accounts yet. <Link href="/water-cash-accounts" className="underline">Create one</Link>.
                    </p>
                  ) : (
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Account</TableHead>
                            <TableHead>Type</TableHead>
                            <TableHead className="text-right">Calculated balance</TableHead>
                            <TableHead className="text-right">Share</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {accountRows.map((a) => (
                            <TableRow key={a.accountId}>
                              <TableCell className="font-medium">
                                {a.accountName}
                                {!a.isActive && <Badge className="ml-2 bg-amber-100 text-amber-700">Inactive</Badge>}
                              </TableCell>
                              <TableCell className="text-slate-600">{a.accountType ?? "—"}</TableCell>
                              <TableCell className={cn("text-right tabular-nums font-medium",
                                                       a.ledgerBalance < 0 && "text-rose-700")}>
                                {gh(a.ledgerBalance)}
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-slate-500">{a.sharePercent}%</TableCell>
                              <TableCell className="text-xs">
                                {a.needsAttention
                                  ? <span className="text-amber-700">{a.attentionReason}</span>
                                  : <span className="text-emerald-700">Reconciled {a.daysSinceReconciled}d ago</span>}
                              </TableCell>
                              <TableCell className="text-right whitespace-nowrap">
                                <Button asChild size="sm" variant="ghost">
                                  <Link href={`/water-cash-accounts/${a.accountId}`}>View</Link>
                                </Button>
                                <Button asChild size="sm" variant="ghost">
                                  <Link href={`/water-cash-reconciliation?accountId=${a.accountId}`}>
                                    Reconcile
                                  </Link>
                                </Button>
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  )}
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base flex items-center gap-2">
                    <ArrowLeftRight className="h-4 w-4 text-slate-500" /> Internal Transfers
                  </CardTitle>
                  <CardDescription className="text-xs">
                    Transfers between company cash accounts. Excluded from Money In, Money Out and Net
                    Cash Flow, because they are not new money received or money spent outside the company.
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  {transferSummary.rows.length === 0 ? (
                    <p className="py-6 text-center text-sm text-slate-500">
                      No transfers between accounts in this period.
                    </p>
                  ) : (
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>From</TableHead>
                            <TableHead>To</TableHead>
                            <TableHead className="text-right">Amount</TableHead>
                            <TableHead>Status</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {transferSummary.rows.map((t) => (
                            <TableRow key={t.id}>
                              <TableCell className="whitespace-nowrap">{(t.transferDate ?? "").split("T")[0]}</TableCell>
                              <TableCell>{t.fromAccountName ?? "—"}</TableCell>
                              <TableCell>{t.toAccountName ?? "—"}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(t.amount)}</TableCell>
                              <TableCell><Badge variant="outline">{t.status}</Badge></TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  )}
                </CardContent>
              </Card>

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
        topIn={inBuckets.slice(0, 5)}
        topOut={outBuckets.slice(0, 5)}
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

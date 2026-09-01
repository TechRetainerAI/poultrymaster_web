"use client"

export const dynamic = "force-dynamic"

/**
 * Cash Flow — company-wide money movement.
 *
 * Answers the owner's question: across the whole company, how much came in, how
 * much went out, and were we cash positive? The per-account view lives on
 * /poultry-cash-accounts; this one deliberately never shows a single account's
 * balance as if it were the company's.
 *
 * Replaces the old /cash page, which merged sales, expenses and account-less
 * adjustments in memory and knew nothing about cash accounts. Everything here
 * reads the cash-account ledger instead, which is what makes Cash by Account,
 * Cash by Account and reconciliation status possible at all.
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
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { usePagination } from "@/hooks/use-pagination"
import { SortableHeader, sortData, type SortDirection } from "@/components/ui/sortable-header"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import {
  Wallet, TrendingUp, TrendingDown, Plus, Lightbulb, AlertTriangle, Info,
  ExternalLink, Users, Truck, Trash2, Pencil,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { getUserContext } from "@/lib/api/config"
import { getExpenses, type Expense } from "@/lib/api/expense"
import { getCashSummary, createCashAdjustment, updateCashAdjustment, deleteCashAdjustment, type CashTransaction } from "@/lib/api/cash"
import { getBalanceSummary, type BalanceSummary } from "@/lib/api/balances"
import {
  listPoultryCashTransactions, getPoultryCashAccountCountStatus,
  adjustPoultryCashAccount,
  type PoultryCashTransaction, type PoultryCashAccountCountStatus,
} from "@/lib/api/poultry-finance"
import {
  buildCashFlowInsights, cashByAccount, cashFlowTotals, cashIdentity, calculatedCashAtHand,
  flowLabel, groupByFlow, isInternalTransfer,
  type LedgerEntry,
} from "@/lib/cash/cash-flow"
import { CashFlowInsightsDialog } from "@/components/cash/cash-flow-insights-dialog"
import {
  CashAdjustmentDialog, ADJUSTMENT_TYPES, adjustmentTypeFromLabel,
  type CashAdjustmentSeed,
} from "@/components/cash/cash-adjustment-dialog"

export default function CashFlowPage() {
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
  // Date descending by default: the newest movement is what people open this
  // page to see. The running column is only meaningful in date order, so it is
  // computed before sorting and simply travels with its row.
  const [sortKey, setSortKey] = useState<string>("date")
  const [sortDir, setSortDir] = useState<SortDirection>("desc")

  const [txns, setTxns] = useState<PoultryCashTransaction[]>([])
  const [status, setStatus] = useState<PoultryCashAccountCountStatus[]>([])
  const [customers, setCustomers] = useState<BalanceSummary | null>(null)
  const [suppliers, setSuppliers] = useState<BalanceSummary | null>(null)
  /**
   * Hand-entered expenses that moved money but were never linked to a cash
   * account. They are the ONLY thing the old /cash page showed that the ledger
   * cannot: /cash read `expense` directly, this page reads
   * poultrycashtransactions, and an expense with no account never reaches it.
   *
   * Kept as rows, not just a count, so the transaction history can show them.
   */
  const [offLedger, setOffLedger] = useState<Expense[]>([])
  /**
   * Owner injections, loans received, opening balances, withdrawals and
   * corrections recorded through the old account-less /cash dialog. They live in
   * the legacy CashAdjustment table and never reached poultrycashtransactions,
   * so this page cannot see them without asking /Cash directly.
   */
  const [legacyAdj, setLegacyAdj] = useState<CashTransaction[]>([])
  const [legacyError, setLegacyError] = useState("")
  const [showOffLedger, setShowOffLedger] = useState(true)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  const [insightsOpen, setInsightsOpen] = useState(false)
  const [adjustOpen, setAdjustOpen] = useState(false)
  const [deleteAdjustment, setDeleteAdjustment] = useState<any>(null)
  // Non-null = the dialog is editing that adjustment rather than adding one.
  const [editAdjustment, setEditAdjustment] = useState<CashAdjustmentSeed | null>(null)

  // Nav already hides this page from anyone without the cash-ledger flag, but
  // the URL was reachable by hand — the old page had no gate of its own at all.
  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger
  const canAdjust = canView

  const load = useCallback(async () => {
    setError("")
    const { userId, farmId } = getUserContext()

    // allSettled throughout: six independent reads, and one failing must not
    // blank the other five. A farm with no supplier module still gets its cards.
    const [txRes, stRes, custRes, suppRes, expRes, legacyRes] = await Promise.allSettled([
      // All-time, deliberately. Cash at Hand is an as-of-now figure and the
      // dedup against migration 230's backfill has to see every ledger row,
      // not just this period's — a backfilled adjustment dated outside the
      // range would otherwise look un-backfilled and be counted twice.
      listPoultryCashTransactions(),
      getPoultryCashAccountCountStatus(),
      getBalanceSummary("poultry", "customer"),
      getBalanceSummary("poultry", "supplier"),
      getExpenses(userId ?? undefined, farmId ?? undefined),
      getCashSummary(userId ?? "", farmId ?? ""),
    ])

    if (txRes.status === "fulfilled") setTxns(txRes.value ?? [])
    else setError(txRes.reason?.message ?? String(txRes.reason))

    setStatus(stRes.status === "fulfilled" ? (stRes.value ?? []) : [])
    setCustomers(custRes.status === "fulfilled" ? custRes.value : null)
    setSuppliers(suppRes.status === "fulfilled" ? suppRes.value : null)

    // Expenses with no cash account never reach the ledger, so Money Out
    // understates and Net Cash Flow flatters the farm.
    //
    // NOT every unlinked expense belongs here. Three kinds are auto-generated by
    // something that has already accounted for the money, and including them
    // would either invent cash movement or count it twice:
    //
    //   paymentMethod 'NonCash'                  Internal Use (216:487). The money
    //                                            left when the stock was bought.
    //   'Raw Materials / Inventory Purchase'     Cash posted against the PURCHASE
    //                                            (207:122) via the purchase sync.
    //   'Flock / Bird Purchase'                  Cash posted against the supplier
    //                                            payment (224:416).
    //
    // The API does not expose expense.sourcetype, so these are the discriminators
    // available — but they are the ones the migrations actually write, not a
    // guess. What survives is a hand-entered expense whose cash nobody recorded.
    if (expRes.status === "fulfilled" && expRes.value?.data) {
      setOffLedger(expRes.value.data.filter((e) => {
        if (e.poultryCashAccountId != null) return false
        if ((e.paymentMethod ?? "") === "NonCash") return false
        if (e.category === "Raw Materials / Inventory Purchase") return false
        if (e.category === "Flock / Bird Purchase") return false
        return (Number(e.amount) || 0) > 0
      }))
    } else {
      setOffLedger([])
    }

    // Legacy adjustments from /Cash. Its rows encode provenance in sortKey:
    // sales end "_s12", expenses "_e12", and an adjustment ends in a bare
    // number — the same test the old page used to decide what it could edit.
    // Sales and expenses are dropped here because the ledger already carries
    // them; only the adjustments are invisible to it.
    //
    // NOT date-filtered here on purpose. These are historical by nature — they
    // predate the cash-account ledger — so almost all of them fall outside a
    // default "this month" range. Filtering at fetch time made them vanish with
    // no way to tell "none exist" from "none in this period". The range is
    // applied downstream, and what falls outside it is counted and reported.
    if (legacyRes.status === "fulfilled" && legacyRes.value?.success && legacyRes.value.data) {
      setLegacyAdj(legacyRes.value.data.transactions.filter((t) => {
        const suffix = (t.sortKey ?? "").split("_").pop() ?? ""
        return /^\d+$/.test(suffix)
      }))
      setLegacyError("")
    } else {
      setLegacyAdj([])
      // getCashSummary resolves with { success: false } rather than throwing, so
      // without this a broken endpoint is indistinguishable from an empty farm.
      const msg = legacyRes.status === "fulfilled"
        ? (legacyRes.value?.message ?? "")
        : String((legacyRes as PromiseRejectedResult).reason)
      setLegacyError(msg)
    }

    setLoading(false)
    // No date deps: every fetch above is all-time and the range is applied
    // downstream, so changing it re-slices rather than re-downloads.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    setLoading(true)
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  // ---- derived, all from the pure module -----------------------------------
  // lib/cash/cash-flow is rail-agnostic — it names the key fields `id` and
  // `accountId` so Water can share it. Mapped here rather than cast: a cast
  // would compile and then hand the module undefined ids at runtime.
  const entries: LedgerEntry[] = useMemo(() => txns.map((t) => ({
    id: t.poultryCashTransactionId,
    accountId: t.poultryCashAccountId,
    accountName: t.accountName,
    transactionDate: t.transactionDate,
    transactionType: t.transactionType,
    sourceType: t.sourceType,
    sourceId: t.sourceId,
    amount: t.amount,
    description: t.description,
  })), [txns])
  const accountRows = useMemo(() => cashByAccount(status.map((a) => ({
    accountId: a.poultryCashAccountId,
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
  // What the cash accounts hold between them — the ledger's own answer.
  const ledgerCash = useMemo(() => calculatedCashAtHand(accountRows), [accountRows])

  // The ledger has no opening-balance row, so in-minus-out never equals cash at
  // hand on its own. currentBalance - ledger movement recovers the opening total.
  // Closes by construction: openingTotal is derived from the same cashAtHand and
  // totals this checks against. It is still worth printing — it is the sum the
  // reader would otherwise do in their head, and it shows WHERE the figure came
  // from rather than asserting it.
  const attention = accountRows.filter((a) => a.needsAttention)

  /**
   * Money that moved but never reached a cash account, as ledger-shaped rows.
   *
   * Two sources: expenses saved without an account, and legacy /cash
   * adjustments. Both are real cash movement, so they now count in Money In and
   * Money Out — but neither is in any account balance, which is why the
   * reconciliation strip keeps a ledger-only figure alongside.
   *
   * DOUBLE-COUNT GUARD: migration 230 copies legacy adjustments into the ledger
   * as sourceType 'LegacyAdjustment' with sourceid = the adjustment id. Matching
   * PER ID rather than "has the backfill run at all" is the whole point — the
   * backfill is one-time, so an adjustment recorded AFTER it exists only in
   * CashAdjustment, and an all-or-nothing guard would suppress exactly the
   * entries that still need this source.
   */
  const backfilledIds = useMemo(
    () => new Set(
      entries
        .filter((e) => e.sourceType === "LegacyAdjustment" && e.sourceId != null)
        .map((e) => e.sourceId as number),
    ),
    [entries],
  )

  const inRange = (d?: string | null) => {
    const day = (d ?? "").split("T")[0]
    return day >= dateFrom && day <= dateTo
  }

  /** The ledger rows inside the selected period. `entries` stays all-time. */
  const periodEntries = useMemo(
    () => entries.filter((e) => inRange(e.transactionDate)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [entries, dateFrom, dateTo],
  )

  const inRangeLegacy = useMemo(
    () => legacyAdj.filter((t) => inRange(t.date)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [legacyAdj, dateFrom, dateTo],
  )
  /** Historical adjustments the selected period hides. Reported, not dropped. */
  const legacyOutsideRange = legacyAdj.length - inRangeLegacy.length

  /**
   * Off-ledger rows for whatever slice is handed in.
   *
   * Extracted so the period view and the all-time view are built by the SAME
   * code — two copies of this shaping would drift, and the breakdown cards
   * would then quietly disagree with the figures above them.
   */
  const buildOffLedger = useCallback((
    expenses: typeof offLedger,
    legacy: typeof legacyAdj,
  ) => {
    const rows: (LedgerEntry & { offLedger: true })[] = expenses.map((e) => ({
      id: -e.expenseId,
      accountId: 0,
      accountName: null,
      transactionDate: e.expenseDate,
      transactionType: "CashOut",
      sourceType: "Expense",
      // The real expense id. `id` above is negated to keep React keys distinct
      // from ledger ids, so it cannot be used to link back to the record.
      sourceId: e.expenseId,
      amount: -(Number(e.amount) || 0),
      description: e.description ?? e.category,
      offLedger: true,
    }))

    legacy.forEach((t, i) => {
      // The ledger already carries this one — skip only THIS row, not the source.
      const adjId = Number((t.sortKey ?? "").split("_").pop())
      if (Number.isFinite(adjId) && backfilledIds.has(adjId)) return
      // `in` and `out` are already split and unsigned by the /Cash endpoint.
      const amount = (Number(t.in) || 0) - (Number(t.out) || 0)
      if (amount === 0) return
      rows.push({
        id: -1_000_000 - i,
        accountId: 0,
        accountName: null,
        transactionDate: t.date,
        transactionType: amount > 0 ? "AdjustmentIn" : "AdjustmentOut",
        // t.type is the display label: "Owner injection", "Loan received",
        // "Opening Balance", "Withdrawal", "Correction".
        sourceType: t.type || "Adjustment",
        sourceId: Number.isFinite(adjId) ? adjId : null,
        amount,
        description: t.description,
        offLedger: true,
      })
    })
    return rows
  }, [backfilledIds])

  /** The period slice — feeds the headline figures and the history table. */
  const offLedgerEntries = useMemo(
    () => buildOffLedger(offLedger.filter((e) => inRange(e.expenseDate)), inRangeLegacy),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [buildOffLedger, offLedger, inRangeLegacy, dateFrom, dateTo],
  )

  /**
   * Every off-ledger movement EVER, not just this period's.
   *
   * Cash at Hand is an as-of-now figure, so it has to carry money that never
   * reached an account whenever it happened. Using the period figure here would
   * make cash at hand rise and fall as you changed the date range, which is the
   * one thing a balance must never do.
   */
  const offLedgerAllTimeNet = useMemo(() => {
    const expenses = offLedger.reduce((s, e) => s - (Number(e.amount) || 0), 0)
    const adjustments = legacyAdj.reduce((s, t) => {
      const adjId = Number((t.sortKey ?? "").split("_").pop())
      if (Number.isFinite(adjId) && backfilledIds.has(adjId)) return s
      return s + (Number(t.in) || 0) - (Number(t.out) || 0)
    }, 0)
    return Math.round((expenses + adjustments) * 100) / 100
  }, [offLedger, legacyAdj, backfilledIds])

  /**
   * Cash at hand = what the accounts hold + money that moved without ever
   * reaching one. The second term is all-time, so this figure does not move
   * when the date range does.
   */
  const cashAtHand = useMemo(
    () => Math.round((ledgerCash + offLedgerAllTimeNet) * 100) / 100,
    [ledgerCash, offLedgerAllTimeNet],
  )

  /**
   * EVERYTHING that moved in the period, off-ledger included and unconditional.
   *
   * The summary figures and the breakdowns are built from this, NOT from the
   * history table's filtered view. "Include money with no cash account" is a
   * control over what the TABLE lists; letting it move the headline totals made
   * a viewing choice look like a change in the business.
   *
   * It also fixed a real inconsistency: cashAtHand always counts off-ledger
   * money (all time), so with the toggle off the identity strip could not close
   * — opening + in - out simply did not reach the cash figure beside it.
   */
  const periodAll = useMemo(
    () => [...periodEntries, ...offLedgerEntries],
    [periodEntries, offLedgerEntries],
  )

  // The headline figures: everything that moved in the period, wherever it was
  // recorded. These follow the date range — that is what the range is for.
  const totals = useMemo(() => cashFlowTotals(periodAll), [periodAll])
  const inBuckets = useMemo(() => groupByFlow(periodAll, "in"), [periodAll])
  const outBuckets = useMemo(() => groupByFlow(periodAll, "out"), [periodAll])

  /**
   * The same thing over ALL TIME, for the two breakdown cards.
   *
   * Deliberately a different scope from the figures above them: "where has our
   * money come from and gone" is a question about the business, not about the
   * fortnight someone happens to have selected. A period breakdown answers a
   * narrower question and answers it differently every time the range moves.
   *
   * The cards say "All time" on their face, because two scopes in one dialog is
   * only safe if each one is labelled.
   */
  const allTimeEntries = useMemo(
    () => [...entries, ...buildOffLedger(offLedger, legacyAdj)],
    [entries, offLedger, legacyAdj, buildOffLedger],
  )
  const allTimeTotals = useMemo(() => cashFlowTotals(allTimeEntries), [allTimeEntries])
  const inBucketsAllTime = useMemo(() => groupByFlow(allTimeEntries, "in"), [allTimeEntries])
  const outBucketsAllTime = useMemo(() => groupByFlow(allTimeEntries, "out"), [allTimeEntries])
  const offLedgerIn = useMemo(
    () => offLedgerEntries.filter((e) => e.amount > 0).reduce((s, e) => s + e.amount, 0),
    [offLedgerEntries],
  )
  const offLedgerOut = useMemo(
    () => offLedgerEntries.filter((e) => e.amount < 0).reduce((s, e) => s - e.amount, 0),
    [offLedgerEntries],
  )

  // Opening is derived, not measured: whatever the business must have been
  // holding at the start of the period for the period's movement to land on
  // today's figure. Deriving it from the SAME total the cards show is what makes
  // the strip below close by construction rather than by luck.
  const openingTotal = useMemo(
    () => Math.round((cashAtHand - (totals.moneyIn - totals.moneyOut)) * 100) / 100,
    [cashAtHand, totals],
  )

  const identity = useMemo(
    () => cashIdentity({ openingTotal, totals, reportedCash: cashAtHand }),
    [openingTotal, totals, cashAtHand],
  )
  const unlinked = useMemo(() => ({
    count: offLedger.length,
    total: offLedger.reduce((s, e) => s + (Number(e.amount) || 0), 0),
  }), [offLedger])

  /**
   * Two lists, deliberately separated.
   *
   * `warnings` is for things that are actually WRONG — a negative cash position,
   * records that failed to load. These drive the badge on the Insights button.
   *
   * `notes` is for things that are merely TRUE and worth knowing. Money that
   * moved without a cash account is the main one: paying a vet out of pocket, or
   * an owner injection that arrives before anyone decides which account holds
   * it, is ordinary business. Dressing it in an amber warning triangle and
   * counting it in a problem badge told people to go fix something that was
   * never broken. It stays on the page — that it sits in no account balance
   * matters at reconciliation time — but it is stated, not flagged.
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
            <Link href="/poultry-cash-accounts" className="underline">Review cash accounts</Link>.
          </AlertDescription>
        </Alert>,
      )
    }
    if (legacyError) {
      items.push(
        <Alert key="legacy-error" className="border-rose-200 bg-rose-50 py-2">
          <AlertTriangle className="h-4 w-4 text-rose-700" />
          <AlertDescription className="text-xs text-rose-900">
            Could not read the older cash records, so owner injections and opening balances are not
            included in these figures. {legacyError}
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
            <Link href="/poultry-cash-reconciliation" className="underline">Reconcile cash</Link>.
          </AlertDescription>
        </Alert>,
      )
    }
    return { count: items.length, node: items.length ? <>{items}</> : null }
  }, [cashAtHand, attention.length, accountRows.length, legacyError])

  /** Neutral facts about the figures. Never counted as problems — see above. */
  const notes = useMemo(() => {
    const items: React.ReactNode[] = []
    if (unlinked.count > 0) {
      items.push(
        <Alert key="unlinked" className="border-slate-200 bg-slate-50 py-2">
          <Info className="h-4 w-4 text-slate-500" />
          <AlertDescription className="text-xs text-slate-700">
            {unlinked.count} {unlinked.count === 1 ? "expense" : "expenses"} totalling{" "}
            {gh(unlinked.total)} {unlinked.count === 1 ? "has" : "have"} no cash account.{" "}
            {/* No longer branches on the toggle: the summary always counts this
                money now, and the toggle only decides whether the history table
                lists the rows. One sentence, always true. */}
            {unlinked.count === 1 ? "It is" : "They are"} counted in Money Out, Net Cash Flow and
            Cash at Hand, but {unlinked.count === 1 ? "sits" : "sit"} in no account balance, so
            reconciliation will not see {unlinked.count === 1 ? "it" : "them"}.{" "}
            {/* Deep-link so acting on this is easy for anyone who wants to — an
                offer, not an instruction. */}
            <Link href="/expenses?cashAccount=none" className="underline">Open Expenses</Link> to link{" "}
            {unlinked.count === 1 ? "it" : "them"}.
          </AlertDescription>
        </Alert>,
      )
    }
    // Historical owner injections, loans and opening balances sit outside a
    // default "this month" range, so without this they simply are not there and
    // there is nothing on screen to explain why.
    if (legacyOutsideRange > 0) {
      items.push(
        <Alert key="legacy-range" className="border-slate-200 bg-slate-50 py-2">
          <Info className="h-4 w-4 text-slate-500" />
          <AlertDescription className="text-xs text-slate-700">
            {legacyOutsideRange} older {legacyOutsideRange === 1 ? "entry" : "entries"} recorded before
            cash accounts existed — owner injections, loans, opening balances — fall outside the
            selected period. Widen the date range to include {legacyOutsideRange === 1 ? "it" : "them"}.
          </AlertDescription>
        </Alert>,
      )
    }
    return items.length ? <>{items}</> : null
  }, [unlinked, legacyOutsideRange, gh])

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
    // The one place the toggle applies: which rows this TABLE lists. The
    // summary above is always the full period, so hiding rows here never
    // silently restates the totals.
    const rows = (showOffLedger ? periodAll : periodEntries)
      .filter((t) => showTransfers || !isInternalTransfer(t))
      .filter((t) => directionFilter === "ALL"
        || (directionFilter === "in" ? t.amount > 0 : t.amount < 0))
      .filter((t) => sourceFilter === "ALL" || flowLabel(t.sourceType, t.description).key === sourceFilter)
      .map((t: any) => ({
        ...t,
        flow: t.offLedger
          ? { key: "OffLedger", label: "Expense (no cash account)" }
          : flowLabel(t.sourceType, t.description),
      }))

    // Calendar day then id, matching the account ledger — a correction posted
    // this afternoon must not sink beneath everything else dated today. See
    // app/poultry-cash-accounts/[id]/page.tsx for why.
    const asc = [...rows].sort((a, b) => {
      const d = (a.transactionDate ?? "").split("T")[0].localeCompare((b.transactionDate ?? "").split("T")[0])
      return d !== 0 ? d : a.id - b.id
    })
    // Every shown row moves the running figure, off-ledger included — it is a
    // cumulative of what this page counts, not an account balance, and the
    // column header says "(period)" for exactly that reason.
    //
    // Computed in date order and BEFORE any user sort, so re-sorting by amount
    // or source cannot silently change what the running column means.
    let running = 0
    const withRunning = asc.map((r: any) => { running += r.amount; return { ...r, running } })

    return sortData(withRunning, sortKey, sortDir, (item: any, key: string) => {
      switch (key) {
        case "date": return new Date(item.transactionDate)
        case "source": return item.flow.label
        case "account": return item.accountName ?? ""
        case "description": return item.description ?? ""
        case "in": return item.amount > 0 ? item.amount : 0
        case "out": return item.amount < 0 ? -item.amount : 0
        case "running": return item.running
        default: return item[key]
      }
    })
  }, [periodAll, periodEntries, showOffLedger, showTransfers, directionFilter, sourceFilter, sortKey, sortDir])

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
                <Wallet className="h-5 w-5 text-emerald-600" />
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
                      tip="Your cash accounts’ balances, plus money that moved without ever being posted to one — owner injections and expenses saved with no cash account. It may still be wrong if sales, expenses, transfers or reconciliations were not recorded correctly. Reconcile regularly to confirm the real available cash." />
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
                {/* Every figure above now includes money that never reached a
                    cash account. That is what was asked for, but it means Cash at
                    Hand no longer equals the sum of the account balances — so say
                    so plainly rather than leave someone to find it by comparing
                    this page with the cash accounts page. */}
                {(offLedgerIn > 0 || offLedgerOut > 0) && (
                  <div className="mt-1 text-xs tabular-nums text-amber-700">
                    Includes
                    {offLedgerIn > 0 && <> <b>{gh(offLedgerIn)}</b> in</>}
                    {offLedgerIn > 0 && offLedgerOut > 0 && " and"}
                    {offLedgerOut > 0 && <> <b>{gh(offLedgerOut)}</b> out</>}
                    {" "}never posted to a cash account. Your cash accounts hold{" "}
                    <b>{gh(ledgerCash)}</b> between them; the difference is money the
                    system knows about but no account is holding.
                  </div>
                )}
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
                      {/* Defaults ON: parity with the old /cash page is the point
                          of having these rows at all. Affects THIS TABLE only —
                          the summary and the breakdowns always count every
                          movement, so hiding rows here cannot restate a total. */}
                      <div className="flex items-center gap-1.5">
                        <Switch id="show-offledger" checked={showOffLedger} onCheckedChange={setShowOffLedger} />
                        <Label htmlFor="show-offledger" className="text-xs text-slate-600">
                          Include money with no cash account
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
                                {([
                                  ["date", "Date", ""],
                                  ["source", "Source", ""],
                                  ["account", "Cash Account", ""],
                                  ["description", "Description", ""],
                                  ["in", "Money In", "text-right [&>div]:justify-end"],
                                  ["out", "Money Out", "text-right [&>div]:justify-end"],
                                  ["running", "Running (period)", "text-right [&>div]:justify-end"],
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
                              {pg.pageItems.map((r: any) => (
                                <TableRow key={r.id}
                                          className={cn((isInternalTransfer(r) || r.offLedger) && "bg-slate-50")}>
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
                                    {r.offLedger && (
                                      <Badge variant="outline" className="ml-2 border-0 bg-amber-100 text-amber-700"
                                             title="Counted here, but never posted to a cash account — so it is not in any account balance.">
                                        no account
                                      </Badge>
                                    )}
                                  </TableCell>
                                  <TableCell className="text-slate-600">
                                    {r.offLedger
                                      ? <span className="text-amber-700">Not linked</span>
                                      : (r.accountName ?? "—")}
                                  </TableCell>
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
                                  {/* What you can do depends on what the row IS.
                                      A ledger row belongs to an account and is
                                      append-only here — reversal lives on the
                                      account. An unlinked expense is fixed by
                                      linking it. A legacy adjustment is the only
                                      thing this page owns outright. */}
                                  <TableCell className="text-right whitespace-nowrap">
                                    {r.offLedger && r.sourceType === "Expense" && (
                                      <Button asChild size="sm" variant="ghost" title="Open this expense to link a cash account">
                                        <Link href={`/expenses/${r.sourceId}`}>Link</Link>
                                      </Button>
                                    )}
                                    {r.offLedger && r.sourceType !== "Expense" && (
                                      <>
                                        <Button size="sm" variant="ghost" title="Edit this adjustment"
                                                onClick={() => setEditAdjustment({
                                                  adjustmentId: Number(r.sourceId),
                                                  // r.sourceType holds the DISPLAY label here, not the
                                                  // stored enum, so it has to be mapped back.
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
                                    {!r.offLedger && r.accountId > 0 && (
                                      <Button asChild size="sm" variant="ghost" title="Open the account ledger">
                                        <Link href={`/poultry-cash-accounts/${r.accountId}`}>
                                          <ExternalLink className="h-4 w-4" />
                                        </Link>
                                      </Button>
                                    )}
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
        inBuckets={inBucketsAllTime}
        outBuckets={outBucketsAllTime}
        breakdownTotals={allTimeTotals}
        breakdownScope="all-time"
        warnings={warnings.node}
        notes={notes}
        fmtMoney={gh}
      />

      <ConfirmDeleteDialog
        open={!!deleteAdjustment}
        onOpenChange={(o: boolean) => { if (!o) setDeleteAdjustment(null) }}
        title="Delete this adjustment?"
        description="It has no cash account, so no account balance changes. It is counted in this page's Money In, Money Out and Cash at Hand, and deleting removes it from those."
        confirmLabel="Delete adjustment"
        errorTitle="Could not delete the adjustment"
        onConfirm={async () => {
          if (!deleteAdjustment) return
          const { farmId } = getUserContext()
          // Negative synthetic ids: legacy rows are keyed -1_000_000 - index, so
          // the real adjustment id comes from the source row, not the key.
          await deleteCashAdjustment(Number(deleteAdjustment.sourceId), farmId)
          setDeleteAdjustment(null)
          await load()
        }}
      />

      {/* One dialog for both jobs — the fields are identical and the difference
          is which call it ends in. `editAdjustment` is what decides. */}
      <CashAdjustmentDialog
        open={adjustOpen || !!editAdjustment}
        onOpenChange={(o) => { if (!o) { setAdjustOpen(false); setEditAdjustment(null) } }}
        accounts={accountRows}
        fmtMoney={gh}
        editing={editAdjustment}
        onSubmit={async ({ accountId, adjustmentType, adjustmentDate, amount, description }) => {
          const { userId, farmId } = getUserContext()
          if (editAdjustment && accountId != null) {
            // LINKING an unlinked adjustment: it moves from the legacy table into
            // the ledger. Two tables, two calls, no transaction spanning them — so
            // one of them has to be allowed to fail, and the ORDER picks which
            // failure the user gets:
            //
            //   post then delete  -> worst case a VISIBLE duplicate, deletable
            //                        from the row it came from.
            //   delete then post  -> worst case the record is GONE, silently.
            //
            // Post first. A duplicate is an annoyance; a lost adjustment is not
            // recoverable from anything this page can see.
            const label = ADJUSTMENT_TYPES.find((t) => t.value === adjustmentType)?.label ?? adjustmentType
            await adjustPoultryCashAccount(accountId, {
              amount,
              reason: description ? `${label} - ${description}` : label,
            })
            // The /Cash client returns { success: false } instead of throwing, so
            // an unchecked call here would report success while leaving the money
            // counted twice.
            const removed = await deleteCashAdjustment(editAdjustment.adjustmentId, farmId)
            if (!removed.success) {
              throw new Error(
                "Posted to the account, but the original unlinked adjustment could not be removed — " +
                "it is now counted twice. Delete it from the history below. " +
                (removed.message ?? ""),
              )
            }
          } else if (editAdjustment) {
            // Still unlinked: a plain field update in the legacy table.
            const saved = await updateCashAdjustment(editAdjustment.adjustmentId, {
              farmId,
              adjustmentDate,
              adjustmentType,
              amount,
              description: description || null,
            })
            if (!saved.success) throw new Error(saved.message ?? "Could not update the adjustment.")
          } else if (accountId != null) {
            // Linked: straight into the ledger, where it moves a real balance.
            // The type becomes the reason, which is what sppoultrycashaccount_adjust
            // stores in `description` and what the breakdown groups by.
            const label = ADJUSTMENT_TYPES.find((t) => t.value === adjustmentType)?.label ?? adjustmentType
            await adjustPoultryCashAccount(accountId, {
              amount,
              reason: description ? `${label} - ${description}` : label,
            })
          } else {
            // Unlinked: the legacy table. Cash Flow reads it and flags the row
            // "no account"; no balance moves until someone links it.
            const created = await createCashAdjustment({
              userId, farmId,
              adjustmentDate,
              adjustmentType,
              amount,
              description: description || null,
            })
            if (!created.success) throw new Error(created.message ?? "Could not record the adjustment.")
          }
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

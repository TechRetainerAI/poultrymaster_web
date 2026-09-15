"use client"

export const dynamic = "force-dynamic"

/**
 * Feed inventory tracker — the poultry counterpart to /water-inventory-tracker.
 *
 * Same shape as the water tracker: the item is the page's SUBJECT (picked at the
 * top), a hero card carries its position for the period, and a chronological
 * ledger with its own filters sits underneath. The one structural difference is
 * forced by the data — water has a single product list, poultry's feed store has
 * two halves that are read differently:
 *
 *   Feed ingredients  bought, then drawn into feed production
 *   Finished feed     produced by a feed batch (or bought in), then fed to flocks
 *
 * so a Kind toggle sits beside the item picker rather than mixing both into one
 * long list. Both halves are raw-material items (migration 167), so one ledger
 * serves them.
 *
 * WHY IT DOES NOT CALL A REPORT ENDPOINT
 * --------------------------------------
 * Water's tracker had to be a stored function because only the server could
 * normalise bags against sachets. Poultry stock is one plain identity over three
 * lists this app already fetches, so the arithmetic lives in
 * lib/utils/feed-item-ledger.ts — see that file's header for the identity and
 * for the purchase-unit trap it exists to avoid. Nothing here re-derives it.
 */

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { PeriodSelect } from "@/components/ui/period-select"
import { TRACKER_PAGE_SIZE_DEFAULT, TRACKER_PAGE_SIZE_OPTIONS } from "@/components/ui/data-pagination"
import { History, RefreshCw, AlertTriangle, Wheat } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useIsMobile } from "@/hooks/use-mobile"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { defaultReportRange, rangeToPeriod } from "@/lib/date-ranges"
import { recognizedCostNote } from "@/lib/poultry/cost-recognition"
import { CostBreakdownDialog } from "@/components/poultry/cost-breakdown-dialog"
import {
  listPoultryRawMaterialItems,
  listPoultryRawMaterialPurchases,
  listPoultryRawMaterialUsageHistory,
  listPoultryRawMaterialAdjustments,
  type PoultryRawMaterialItem,
  type PoultryRawMaterialPurchase,
  type PoultryRawMaterialUsage,
  type PoultryRawMaterialAdjustment,
} from "@/lib/api/poultry-inventory"
import {
  buildFeedItemMovements,
  buildFeedItemPositions,
  summariseFeedPositions,
  type FeedItemKind,
  type FeedItemMovement,
  type FeedItemPosition,
} from "@/lib/utils/feed-item-ledger"

const qty = (n: number) => n.toLocaleString(undefined, { maximumFractionDigits: 3 })

const KIND_LABEL: Record<FeedItemKind, string> = {
  Ingredient: "Feed ingredients",
  FinishedFeed: "Finished feed",
}

/**
 * The "All ..." row in the item picker. A string sentinel rather than a magic
 * number (0, -1) so it can never collide with a real item id.
 */
const ALL_ITEMS = "ALL_ITEMS" as const
type Selection = number | typeof ALL_ITEMS

/** A movement carries only an item id; the ledger table needs the item itself. */
type LedgerRow = FeedItemMovement & { itemName: string; unit: string }

function FeedInventoryTrackerPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const isMobile = useIsMobile()
  const fmtMoney = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)

  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [purchases, setPurchases] = useState<PoultryRawMaterialPurchase[]>([])
  const [usages, setUsages] = useState<PoultryRawMaterialUsage[]>([])
  const [adjustments, setAdjustments] = useState<PoultryRawMaterialAdjustment[]>([])

  const [kind, setKind] = useState<FeedItemKind>("Ingredient")
  /** One item id, or ALL_ITEMS for this half rolled up. Null until data lands. */
  const [selection, setSelection] = useState<Selection | null>(null)
  /** Set once from ?itemId=, then never again — reselecting must stay sticky. */
  const appliedQueryItem = useRef(false)

  const [loading, setLoading] = useState(true)
  /** Distinguishes first paint from a later refresh, so only the former blanks
   *  the page. The period is applied client-side, so it never refetches. */
  const firstLoad = useRef(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState("")

  // 288. Which production record's cost breakdown is open, if any.
  const [breakdownFor, setBreakdownFor] = useState<number | null>(null)

  // Ledger filters.
  const [typeFilter, setTypeFilter] = useState("ALL")
  const [descriptionFilter, setDescriptionFilter] = useState("")
  const [ledgerPage, setLedgerPage] = useState(1)
  const [ledgerPageSize, setLedgerPageSize] = useState(TRACKER_PAGE_SIZE_DEFAULT)
  // Newest first, on the full timestamp rather than the yyyy-mm-dd the column
  // shows, so several movements on one day still read newest-first.
  const [sortKey, setSortKey] = useState<string | null>("timestamp")
  const [sortDir, setSortDir] = useState<SortDirection>("desc")

  const load = useCallback(async () => {
    setError("")
    // The whole history, not the selected period: an opening balance is the sum
    // of everything before the window, so the window cannot be pushed down to
    // the endpoints. Same four reads the Feed tracker already does.
    const [its, ps, us, adjs] = await Promise.all([
      listPoultryRawMaterialItems(),
      listPoultryRawMaterialPurchases().catch(() => [] as PoultryRawMaterialPurchase[]),
      listPoultryRawMaterialUsageHistory().catch(() => [] as PoultryRawMaterialUsage[]),
      listPoultryRawMaterialAdjustments().catch(() => [] as PoultryRawMaterialAdjustment[]),
    ])
    setItems(its)
    setPurchases(ps as PoultryRawMaterialPurchase[])
    setUsages(us as PoultryRawMaterialUsage[])
    setAdjustments(adjs as PoultryRawMaterialAdjustment[])
    return its
  }, [])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
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

  const ledgerInput = useMemo(
    () => ({ items, purchases, usages, adjustments }),
    [items, purchases, usages, adjustments],
  )

  const movementsByItem = useMemo(() => buildFeedItemMovements(ledgerInput), [ledgerInput])

  const positions = useMemo(
    () => buildFeedItemPositions(ledgerInput, fromDate, toDate, movementsByItem),
    [ledgerInput, fromDate, toDate, movementsByItem],
  )

  const positionsOfKind = useMemo(
    () => positions.filter((p) => p.kind === kind),
    [positions, kind],
  )

  const counts = useMemo(() => ({
    Ingredient: positions.filter((p) => p.kind === "Ingredient").length,
    FinishedFeed: positions.filter((p) => p.kind === "FinishedFeed").length,
  }), [positions])

  // Preselect from ?itemId= (the Track link on Raw Materials), else the item
  // with the most movement in the period — an empty ledger is a poor landing.
  useEffect(() => {
    if (positions.length === 0) return
    if (!appliedQueryItem.current) {
      appliedQueryItem.current = true
      const wanted = Number(searchParams.get("itemId"))
      const match = positions.find((p) => p.itemId === wanted)
      if (match) { setKind(match.kind); setSelection(match.itemId); return }
    }
    setSelection((current) => {
      // "All ..." means the same thing in both halves, so it survives a kind
      // switch rather than snapping back to a single item.
      if (current === ALL_ITEMS) return current
      if (current != null && positionsOfKind.some((p) => p.itemId === current)) return current
      const busiest = [...positionsOfKind].sort((a, b) => b.movementCount - a.movementCount)[0]
      return busiest?.itemId ?? null
    })
  }, [positions, positionsOfKind, searchParams])

  const isAll = selection === ALL_ITEMS

  const selected: FeedItemPosition | null = useMemo(
    () => (typeof selection === "number" ? positions.find((p) => p.itemId === selection) ?? null : null),
    [positions, selection],
  )

  /** The "All ..." figures: one line per stocking unit, never summed across them. */
  const unitTotals = useMemo(() => summariseFeedPositions(positionsOfKind), [positionsOfKind])
  const driftItems = useMemo(() => unitTotals.reduce((n, t) => n + t.driftItems, 0), [unitTotals])

  const movements = useMemo<LedgerRow[]>(() => {
    const decorate = (p: FeedItemPosition): LedgerRow[] =>
      (movementsByItem.get(p.itemId) ?? []).map((m) => ({ ...m, itemName: p.itemName, unit: p.unit }))
    if (isAll) return positionsOfKind.flatMap(decorate)
    return selected ? decorate(selected) : []
  }, [movementsByItem, positionsOfKind, selected, isAll])

  // The window, applied to this item's movements. Same boundary rule the
  // positions use, so the last row's balance lands on the hero's closing.
  const windowRows = useMemo(
    () => movements.filter((m) => (!fromDate || m.date >= fromDate) && (!toDate || m.date <= toDate)),
    [movements, fromDate, toDate],
  )

  const distinctTypes = useMemo(
    () => Array.from(new Set(windowRows.map((m) => m.label).filter(Boolean))).sort(),
    [windowRows],
  )

  const ledgerRows = useMemo(() => {
    const q = descriptionFilter.trim().toLowerCase()
    return windowRows.filter((m) =>
      (typeFilter === "ALL" || m.label === typeFilter) &&
      (!q || m.description.toLowerCase().includes(q) || m.label.toLowerCase().includes(q)))
  }, [windowRows, typeFilter, descriptionFilter])

  const sortedRows = useMemo(
    // For ONE item, Date sorts on `seq` -- the movement's position in that item's
    // own ledger. A day's movements share one timestamp, compare equal on it, and
    // would otherwise stay oldest-first under a descending sort, showing a balance
    // that appears to run backwards. Across items `seq` is not comparable (every
    // item has its own 0), so the roll-up falls back to the timestamp.
    () => sortData(ledgerRows, sortKey, sortDir,
      (r, k) => (k === "timestamp" ? (isAll ? r.timestamp : r.seq) : (r as any)[k])),
    [ledgerRows, sortKey, sortDir, isAll],
  )

  // Totals cover the WHOLE filtered set, not the visible page — a total that
  // only covered page 1 would quietly disagree with the columns above it.
  const ledgerTotals = useMemo(() => {
    let inQty = 0, outQty = 0, cost = 0, recognized = 0
    for (const r of sortedRows) {
      inQty += r.inQty
      outQty += r.outQty
      // A reversed draw keeps its row but its money was given back; counting it
      // would double the feed bill for the period.
      if (!r.reversed) { cost += r.cost ?? 0; recognized += r.recognized ?? 0 }
    }
    return { inQty, outQty, cost, recognized }
  }, [sortedRows])

  // In and Out are quantities, and a bag is not a kilogram. When the visible rows
  // span more than one unit the columns still read correctly row by row, but their
  // total does not exist -- so it is withheld rather than invented. Money has one
  // unit, so the cost total is always safe to show.
  const ledgerUnits = useMemo(
    () => Array.from(new Set(sortedRows.map((r) => r.unit.trim()).filter(Boolean))),
    [sortedRows],
  )
  const mixedUnits = ledgerUnits.length > 1

  const totalPages = Math.max(1, Math.ceil(sortedRows.length / ledgerPageSize))
  const safePage = Math.min(ledgerPage, totalPages)
  const pageRows = useMemo(
    () => sortedRows.slice((safePage - 1) * ledgerPageSize, safePage * ledgerPageSize),
    [sortedRows, safePage, ledgerPageSize],
  )

  const handleSort = (key: string) => {
    const next = toggleSort(key, sortKey, sortDir)
    setSortKey(next.key); setSortDir(next.direction)
  }

  // Resets what you filtered BY, not what you are looking at: the item stays,
  // because clearing it would leave the page with nothing to show.
  const clearLedgerFilters = () => {
    setTypeFilter("ALL")
    setDescriptionFilter("")
    setFromDate(DEFAULT_RANGE.from)
    setToDate(DEFAULT_RANGE.to)
    setLedgerPage(1)
  }

  const unitBit = selected?.unit ? ` (${selected.unit.toLowerCase()})` : ""
  const isLow = !!selected && selected.minimumStockAlert > 0 && selected.closing <= selected.minimumStockAlert

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">

            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-amber-100 rounded-lg flex items-center justify-center">
                  <History className="w-5 h-5 text-amber-700" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Feed inventory tracker</h1>
                  <p className="text-sm text-slate-600">
                    Ledger from purchases, feed production, flock consumption and adjustments —
                    every movement behind one ingredient&apos;s or finished feed&apos;s stock figure.
                  </p>
                </div>
              </div>
              <Button
                type="button"
                variant="outline"
                className="shrink-0 gap-2"
                onClick={handleRefresh}
                disabled={refreshing || loading}
              >
                <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
                Refresh
              </Button>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center text-slate-600">Loading feed inventory…</CardContent>
              </Card>
            ) : positions.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center text-slate-600">
                  No feed items yet. Add items with category <strong>Feed Ingredient</strong> or{" "}
                  <strong>Finished Feed</strong> on{" "}
                  <Link href="/poultry-raw-materials" className="text-amber-700 underline">
                    Raw Materials &amp; Supplies
                  </Link>{" "}
                  to start tracking them.
                </CardContent>
              </Card>
            ) : (
              <>
                {/* Kind and item are the page's SUBJECT, not two of the ledger's
                    filters: every figure and every row below describes this one
                    item, so they sit above them rather than in the filter grid. */}
                <div className="flex flex-wrap items-center gap-3 rounded-lg border border-slate-200 bg-white p-3">
                  <div className="inline-flex rounded-lg border border-slate-200 p-0.5">
                    {(["Ingredient", "FinishedFeed"] as FeedItemKind[]).map((k) => (
                      <button
                        key={k}
                        type="button"
                        onClick={() => {
                          if (k === kind) return
                          setKind(k)
                          // Dropped so the effect above picks this half's busiest
                          // item; keeping it would show an empty ledger. "All ..."
                          // is kept, because it applies to either half.
                          setSelection((c) => (c === ALL_ITEMS ? c : null))
                          setLedgerPage(1)
                        }}
                        className={cn(
                          "px-3 py-1.5 text-sm font-medium rounded-md transition-colors",
                          k === kind ? "bg-amber-600 text-white" : "text-slate-600 hover:bg-slate-100",
                        )}
                      >
                        {KIND_LABEL[k]}
                        <span className={cn("ml-1.5 text-xs", k === kind ? "text-amber-100" : "text-slate-400")}>
                          {counts[k]}
                        </span>
                      </button>
                    ))}
                  </div>
                  <Select
                    value={selection != null ? String(selection) : ""}
                    onValueChange={(v) => {
                      setSelection(v === ALL_ITEMS ? ALL_ITEMS : Number(v))
                      setLedgerPage(1)
                    }}
                  >
                    <SelectTrigger className="h-10 w-full sm:w-[22rem]">
                      <SelectValue placeholder={`Pick ${kind === "Ingredient" ? "an ingredient" : "a finished feed"}`} />
                    </SelectTrigger>
                    <SelectContent>
                      {/* First, because "what do we hold in total" is the question
                          asked before any single item's. */}
                      {positionsOfKind.length > 0 && (
                        <SelectItem value={ALL_ITEMS}>
                          All {KIND_LABEL[kind].toLowerCase()} ({positionsOfKind.length})
                        </SelectItem>
                      )}
                      {positionsOfKind.map((p) => (
                        <SelectItem key={p.itemId} value={String(p.itemId)}>
                          {p.itemName}{p.isActive ? "" : " (inactive)"}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {(() => {
                    const moves = isAll
                      ? unitTotals.reduce((n, t) => n + t.movementCount, 0)
                      : selected?.movementCount
                    if (moves == null) return null
                    return (
                      <span className="text-xs text-slate-500">
                        {moves === 1 ? "1 movement in this period" : `${moves.toLocaleString()} movements in this period`}
                      </span>
                    )
                  })()}
                </div>

                {positionsOfKind.length === 0 && (
                  <Alert>
                    <AlertDescription>
                      No {KIND_LABEL[kind].toLowerCase()} on this company yet. Items are picked up from their
                      category on Raw Materials &amp; Supplies.
                    </AlertDescription>
                  </Alert>
                )}

                {/* The stored stock figure and this ledger's own arithmetic must
                    agree. When they don't, say so instead of picking one: the
                    Recalculate stock button on Raw Materials is the repair. */}
                {isAll && driftItems > 0 && (
                  <Alert className="border-amber-300 bg-amber-50">
                    <AlertTriangle className="h-4 w-4 text-amber-700" />
                    <AlertDescription className="text-amber-900">
                      {driftItems === 1
                        ? "1 of these items is recorded at a stock figure that disagrees with its own"
                        : `${driftItems} of these items are recorded at stock figures that disagree with their own`}{" "}
                      purchases, usage and adjustments, so <strong>In stock now</strong> and{" "}
                      <strong>Closing</strong> below will not meet. Pick the item to see the difference, or run{" "}
                      <strong>Recalculate stock</strong> on{" "}
                      <Link href="/poultry-raw-materials" className="underline">Raw Materials &amp; Supplies</Link>.
                    </AlertDescription>
                  </Alert>
                )}

                {selected && selected.drift !== 0 && (
                  <Alert className="border-amber-300 bg-amber-50">
                    <AlertTriangle className="h-4 w-4 text-amber-700" />
                    <AlertDescription className="text-amber-900">
                      <strong>{selected.itemName}</strong> is recorded as{" "}
                      <strong>{qty(selected.onRecord)}{selected.unit ? ` ${selected.unit}` : ""}</strong> in stock,
                      but its purchases, usage and adjustments add up to{" "}
                      <strong>{qty(selected.derivedNow)}</strong> — a difference of {qty(Math.abs(selected.drift))}.
                      Run <strong>Recalculate stock</strong> on{" "}
                      <Link href="/poultry-raw-materials" className="underline">Raw Materials &amp; Supplies</Link>{" "}
                      to bring the stored figure back in line with its own movements.
                    </AlertDescription>
                  </Alert>
                )}

                {/* --------------------------------------- hero (roll-up) */}
                {isAll ? (
                <Card className="border-amber-200 bg-amber-50/50">
                  <CardHeader className="pb-2">
                    <CardDescription>Stock for the selected period</CardDescription>
                    <CardTitle className="text-base font-semibold text-slate-800 mt-1 flex flex-wrap items-center gap-2">
                      <Wheat className="h-4 w-4 text-amber-700" />
                      All {KIND_LABEL[kind].toLowerCase()}
                      <Badge variant="outline" className="font-normal">
                        {positionsOfKind.length} {positionsOfKind.length === 1 ? "item" : "items"}
                      </Badge>
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    {unitTotals.length === 0 ? (
                      <p className="py-4 text-sm text-slate-600">Nothing to total yet.</p>
                    ) : (
                      <>
                        {/* One line per stocking unit. See FeedUnitTotals for why
                            these are never added together. */}
                        <div className="overflow-x-auto table-scroll-wrapper pb-1" style={{ WebkitOverflowScrolling: "touch" }}>
                          <Table className="w-full min-w-[620px] bg-white/60 rounded-lg">
                            <TableHeader>
                              <TableRow>
                                <TableHead>Unit</TableHead>
                                <TableHead className="text-right">Items</TableHead>
                                <TableHead className="text-right">Opening</TableHead>
                                <TableHead className="text-right">In</TableHead>
                                <TableHead className="text-right">Out</TableHead>
                                <TableHead className="text-right">Closing</TableHead>
                                <TableHead className="text-right">In stock now</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {unitTotals.map((t) => (
                                <TableRow key={t.unit || "(none)"}>
                                  <TableCell className="font-medium whitespace-nowrap">
                                    {t.unit || "No unit set"}
                                  </TableCell>
                                  <TableCell className="text-right tabular-nums text-slate-600">{t.items}</TableCell>
                                  <TableCell className="text-right tabular-nums">{qty(t.opening)}</TableCell>
                                  <TableCell className="text-right tabular-nums text-emerald-700">{qty(t.inQty)}</TableCell>
                                  <TableCell className="text-right tabular-nums text-rose-700">{qty(t.outQty)}</TableCell>
                                  <TableCell className={cn(
                                    "text-right text-base font-bold tabular-nums",
                                    t.closing < 0 ? "text-red-600" : "text-slate-900",
                                  )}>
                                    {qty(t.closing)}
                                  </TableCell>
                                  <TableCell className="text-right tabular-nums">{qty(t.onRecord)}</TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        </div>
                        {unitTotals.length > 1 && (
                          <p className="mt-3 text-[11px] leading-relaxed text-slate-600">
                            One line per stocking unit: these items are held in {unitTotals.length} different units,
                            and a bag is not a kilogram — adding the lines together would give a figure with no unit,
                            so they are kept apart.
                          </p>
                        )}
                      </>
                    )}
                  </CardContent>
                </Card>
                ) : (
                <Card className="border-amber-200 bg-amber-50/50">
                  {/* Figures only. Every control lives in the one filter row on
                      the ledger card below. */}
                  <CardHeader className="pb-2">
                    <CardDescription>Stock for the selected period</CardDescription>
                    <CardTitle className="text-base font-semibold text-slate-800 mt-1 flex flex-wrap items-center gap-2">
                      <Wheat className="h-4 w-4 text-amber-700" />
                      {selected?.itemName ?? "Pick an item"}
                      {selected && (
                        <Badge variant="outline" className="font-normal">{KIND_LABEL[selected.kind]}</Badge>
                      )}
                      {isLow && (
                        <Badge className="bg-rose-100 text-rose-800 hover:bg-rose-100">Low stock</Badge>
                      )}
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className={cn("grid gap-4", isMobile ? "grid-cols-2" : "grid-cols-5")}>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">
                          Closing{unitBit}
                        </div>
                        <div className={cn(
                          "mt-1 text-2xl font-bold tabular-nums",
                          (selected?.closing ?? 0) < 0 ? "text-red-600" : "text-slate-900",
                        )}>
                          {selected ? qty(selected.closing) : "—"}
                        </div>
                        {selected && selected.minimumStockAlert > 0 ? (
                          <div className="text-[11px] text-slate-500">alert at {qty(selected.minimumStockAlert)}</div>
                        ) : null}
                      </div>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Opening</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-slate-900">
                          {selected ? qty(selected.opening) : "—"}
                        </div>
                      </div>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">In</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-emerald-700">
                          {selected ? qty(selected.inQty) : "—"}
                        </div>
                      </div>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Out</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-rose-700">
                          {selected ? qty(selected.outQty) : "—"}
                        </div>
                      </div>
                      <div>
                        {/* Not a period figure: this is what the item holds NOW,
                            which is the number every other screen shows. Kept
                            beside the period's closing on purpose — when the two
                            differ, the period simply ended before today. */}
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">In stock now</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-slate-900">
                          {selected ? qty(selected.onRecord) : "—"}
                        </div>
                        {selected?.lastMovementDate ? (
                          <div className="text-[11px] text-slate-500">last moved {selected.lastMovementDate}</div>
                        ) : selected ? (
                          <div className="text-[11px] text-slate-500">never moved</div>
                        ) : null}
                      </div>
                    </div>
                  </CardContent>
                </Card>
                )}

                {/* ----------------------------------------------- ledger */}
                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Stock ledger</CardTitle>
                    <CardDescription>Chronological ledger; filter the table below</CardDescription>
                    {/* Item is not here — it is the page subject and sits at the
                        top. Period presets drive the two date boxes; picking
                        dates by hand flips the preset back to Custom on its own
                        via rangeToPeriod. */}
                    <div className={cn("grid gap-2 pt-3", isMobile ? "grid-cols-2" : "grid-cols-6")}>
                      <PeriodSelect
                        label={null}
                        className="w-full"
                        value={rangeToPeriod(fromDate, toDate)}
                        onChange={(_p, rg) => {
                          if (rg) { setFromDate(rg.from); setToDate(rg.to); setLedgerPage(1) }
                        }}
                      />
                      <Select value={typeFilter} onValueChange={(v) => { setTypeFilter(v); setLedgerPage(1) }}>
                        <SelectTrigger className={cn(isMobile ? "col-span-2" : "")}>
                          <SelectValue placeholder="Type" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All types</SelectItem>
                          {distinctTypes.map((t) => (
                            <SelectItem key={t} value={t}>{t}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Input
                        placeholder="Description…"
                        value={descriptionFilter}
                        onChange={(e) => { setDescriptionFilter(e.target.value); setLedgerPage(1) }}
                        className={cn(isMobile ? "col-span-2" : "")}
                      />
                      <Input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} />
                      <Input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} />
                    </div>
                    <div className="pt-2">
                      <Button type="button" variant="outline" size="sm" onClick={clearLedgerFilters}>
                        Reset ledger filters
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {selection == null ? (
                      <p className="text-slate-600 py-8 text-center text-sm">Pick an item to see its movements.</p>
                    ) : sortedRows.length === 0 ? (
                      <p className="text-slate-600 py-8 text-center text-sm">
                        {windowRows.length === 0
                          ? `No movements for ${isAll ? "these items" : "this item"} in the selected period.`
                          : "No ledger rows match those filters."}
                      </p>
                    ) : (
                      <>
                      {/* Mobile opens on scorecards (expanded by default);
                          "View table format" flips to the wide ledger table.

                          -mx-6 cancels CardContent's px-6 and flushMobile drops
                          the card stack's own p-3. Without both, these cards
                          carry 36px of gutter the same cards on
                          /poultry-daily-closing do not — that page hangs them
                          straight off <main>, so their only inset is its p-4.
                          Phone-only: the desktop table keeps the card padding. */}
                      <div className="-mx-6 lg:mx-0">
                      <MobileCardList
                        striped
                        defaultOpen
                        flushMobile
                        items={pageRows}
                        getKey={(row) => row.key}
                        primary={(row) => row.date || "—"}
                        secondary={(row) => (
                          <span className="truncate">
                            {isAll ? `${row.itemName} · ${row.label}` : row.label}
                          </span>
                        )}
                        trailing={(row) => (
                          <span className="text-sm font-semibold tabular-nums text-slate-900">{qty(row.balance)}</span>
                        )}
                        highlights={(row) => [
                          { label: "In", value: row.inQty > 0 ? qty(row.inQty) : "—", accent: "emerald" },
                          { label: "Out", value: row.outQty > 0 ? qty(row.outQty) : "—", accent: "rose" },
                          { label: "Balance", value: qty(row.balance), accent: "violet", wide: true },
                        ]}
                        details={(row) => [
                          { label: "Description", value: row.description },
                          ...(row.cost != null
                            ? [{ label: "Cost", value: `${fmtMoney(row.cost)}${row.reversed ? " (reversed)" : ""}` }]
                            : []),
                        ]}
                        desktopTable={
                      <div className="overflow-x-auto table-scroll-wrapper pb-2" style={{ WebkitOverflowScrolling: "touch" }}>
                        <Table className="w-full min-w-[760px]">
                          <TableHeader>
                            <TableRow>
                              <SortableHeader label="Date"        sortKey="timestamp"   currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                              {/* Only in the roll-up: with one item selected the
                                  column would repeat the same name on every row. */}
                              {isAll && (
                                <SortableHeader label="Item"      sortKey="itemName"    currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                              )}
                              <SortableHeader label="Type"        sortKey="label"       currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                              <SortableHeader label="Description" sortKey="description" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                              <SortableHeader label="In"          sortKey="inQty"       currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" />
                              <SortableHeader label="Out"         sortKey="outQty"      currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" />
                              <TableHead className="text-right" title={isAll ? "Running balance of that row's own item" : undefined}>
                                {isAll ? "Item balance" : "Balance"}
                              </TableHead>
                              {/* Migration 268. Cost is what the stock drawn was
                                  worth; the dash on an IN row is not a zero, it
                                  is "this question does not apply here". */}
                              <SortableHeader label="Cost"        sortKey="cost"        currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pageRows.map((row) => (
                              <TableRow key={row.key}>
                                <TableCell className="font-medium whitespace-nowrap">{row.date || "—"}</TableCell>
                                {isAll && (
                                  <TableCell className="max-w-[160px] truncate" title={row.itemName}>
                                    {row.itemName}
                                  </TableCell>
                                )}
                                <TableCell className="whitespace-nowrap">{row.label}</TableCell>
                                <TableCell className="max-w-[280px] truncate" title={row.description}>
                                  {row.description}
                                </TableCell>
                                <TableCell className="text-right text-emerald-600 tabular-nums">
                                  {row.inQty > 0 ? qty(row.inQty) : "—"}
                                </TableCell>
                                <TableCell className="text-right text-red-600 tabular-nums">
                                  {row.outQty > 0 ? qty(row.outQty) : "—"}
                                </TableCell>
                                <TableCell className="text-right font-medium tabular-nums">
                                  {qty(row.balance)}
                                </TableCell>
                                <TableCell className="text-right tabular-nums">
                                  {row.cost == null ? "—" : (
                                    <span className={cn(row.reversed && "text-slate-400 line-through")}>
                                      {row.productionRecordId ? (
                                        <button
                                          type="button"
                                          className="underline decoration-dotted hover:text-amber-700"
                                          title={recognizedCostNote(row.recognized ?? 0, row.cost)}
                                          onClick={() => setBreakdownFor(row.productionRecordId ?? null)}
                                        >
                                          {fmtMoney(row.cost)}
                                        </button>
                                      ) : fmtMoney(row.cost)}
                                    </span>
                                  )}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                          {/* Totals cover every filtered row, not just this
                              page, and move with the filters above. */}
                          <TableFooter>
                            <TableRow className="bg-slate-50 hover:bg-slate-50">
                              <TableCell colSpan={isAll ? 4 : 3} className="font-medium text-slate-700">
                                Totals
                                <span className="ml-1.5 font-normal text-xs text-slate-500">
                                  ({sortedRows.length.toLocaleString()}
                                  {sortedRows.length === 1 ? " movement" : " movements"}
                                  {mixedUnits ? ` · ${ledgerUnits.join(", ")} — not totalled` : ""})
                                </span>
                              </TableCell>
                              <TableCell className="text-right font-semibold tabular-nums text-emerald-700">
                                {mixedUnits ? "—" : ledgerTotals.inQty > 0 ? qty(ledgerTotals.inQty) : "—"}
                              </TableCell>
                              <TableCell className="text-right font-semibold tabular-nums text-red-600">
                                {mixedUnits ? "—" : ledgerTotals.outQty > 0 ? qty(ledgerTotals.outQty) : "—"}
                              </TableCell>
                              {/* Balance is a running position, not a quantity:
                                  summing it would add the item's stock level to
                                  itself once per row. Left blank on purpose. */}
                              <TableCell />
                              <TableCell className="text-right font-semibold tabular-nums text-slate-900">
                                {ledgerTotals.cost > 0 ? fmtMoney(ledgerTotals.cost) : "—"}
                              </TableCell>
                            </TableRow>
                          </TableFooter>
                        </Table>
                      </div>
                        }
                      />

                      {/* The footer totals live in the table, which mobile does
                          not show, so repeat them as a strip under the cards. */}
                      <div className="lg:hidden mb-2 flex items-center justify-between gap-2 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-xs">
                        <span className="text-slate-600">
                          Totals ({sortedRows.length.toLocaleString()}{sortedRows.length === 1 ? " movement" : " movements"})
                        </span>
                        {mixedUnits ? (
                          <span className="text-slate-500">{ledgerUnits.join(", ")} — not totalled</span>
                        ) : (
                          <span className="flex items-center gap-3 tabular-nums">
                            <span className="font-semibold text-emerald-700">In {ledgerTotals.inQty > 0 ? qty(ledgerTotals.inQty) : "—"}</span>
                            <span className="font-semibold text-red-600">Out {ledgerTotals.outQty > 0 ? qty(ledgerTotals.outQty) : "—"}</span>
                          </span>
                        )}
                      </div>
                      </div>

                        <div className="flex flex-wrap items-center justify-center gap-2 pt-3">
                          <Select
                            value={String(ledgerPageSize)}
                            onValueChange={(v) => {
                              setLedgerPageSize(Number(v))
                              // Page 4 of 8 is nowhere once the pages get bigger.
                              setLedgerPage(1)
                            }}
                          >
                            <SelectTrigger className="h-8 w-[110px]" aria-label="Rows per page">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {TRACKER_PAGE_SIZE_OPTIONS.map((n) => (
                                <SelectItem key={n} value={String(n)}>{n} / page</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                          <Button
                            type="button" variant="outline" size="sm"
                            disabled={safePage <= 1}
                            onClick={() => setLedgerPage((p) => Math.max(1, p - 1))}
                          >
                            Previous
                          </Button>
                          <span className="text-xs text-slate-600 whitespace-nowrap">
                            Page {safePage} of {totalPages}
                          </span>
                          <Button
                            type="button" variant="outline" size="sm"
                            disabled={safePage >= totalPages}
                            onClick={() => setLedgerPage((p) => Math.min(totalPages, p + 1))}
                          >
                            Next
                          </Button>
                        </div>
                      </>
                    )}

                    {/* Say what the ledger does not contain, rather than letting
                        the numbers imply it is complete. */}
                    <p className="mt-4 text-[11px] leading-relaxed text-slate-500">
                      In covers purchases and feed produced by a feed-production batch; Out covers feed fed to
                      flocks and ingredients drawn into feed production. Reversed draws keep their row and are
                      matched by a reversal adjustment, so the pair nets to zero. Cost is shown on Out rows only,
                      and the total excludes reversed draws.
                      {isAll ? " Across all items, Item balance is each row's OWN item running balance, not a" +
                        " combined one — consecutive rows can belong to different items." : ""}
                      {mixedUnits ? " These rows span more than one stocking unit, so the In and Out columns are" +
                        " not totalled; pick a single item, or filter, to get a total that means something." : ""}
                    </p>
                  </CardContent>
                </Card>
              </>
            )}
          </div>
        </main>
      </div>

      <CostBreakdownDialog
        productionRecordId={breakdownFor}
        title="Feed cost breakdown"
        onClose={() => setBreakdownFor(null)}
      />
    </div>
  )
}

// useSearchParams needs a Suspense boundary to prerender; the house pattern
// pairs it with the force-dynamic above (see app/water-inventory-tracker/page.tsx).
export default function FeedInventoryTrackerPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <FeedInventoryTrackerPageInner />
    </Suspense>
  )
}

"use client"

export const dynamic = "force-dynamic"

/**
 * Inventory tracker — the water counterpart to the poultry Egg tracker.
 *
 * Same shape as /egg-tracker: a hero card carrying the on-hand figure, then a
 * chronological ledger with its own filters underneath. The one structural
 * difference is forced by the data — poultry tracks a single commodity (eggs),
 * water has many products, so a product picker sits where the egg tracker has
 * nothing. Arriving from Inventory with ?productId= preselects it.
 *
 * Quantities are in BASE units (sachets for a sachet product) because that is
 * the only unit the ledger sums correctly: five of the seven movement types
 * leave `basequantity` NULL and carry bags in a rounded INT instead. The server
 * normalises (migration 221); this page never does unit maths of its own.
 */

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { History, RefreshCw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"
import {
  getWaterInventoryTracker,
  getWaterInventoryTrackerMovements,
  type WaterInventoryTrackerRow,
  type WaterInventoryTrackerMovement,
} from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { PeriodSelect } from "@/components/ui/period-select"
import { defaultReportRange, rangeToPeriod } from "@/lib/date-ranges"

const LEDGER_PAGE_SIZE = 15
const qty = (n: number) => n.toLocaleString(undefined, { maximumFractionDigits: 2 })

function WaterInventoryTrackerPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const isMobile = useIsMobile()
  const fmtMoney = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)

  const [rows, setRows] = useState<WaterInventoryTrackerRow[]>([])
  const [productId, setProductId] = useState<number | null>(null)
  const [moves, setMoves] = useState<WaterInventoryTrackerMovement[]>([])
  const [loading, setLoading] = useState(true)
  /** Distinguishes "first paint" from "the period changed", so only the former
   *  is allowed to replace the page with a loading card. */
  const firstLoad = useRef(true)
  const [movesLoading, setMovesLoading] = useState(false)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState("")

  // Ledger filters, mirroring the egg tracker's ledger card.
  const [typeFilter, setTypeFilter] = useState("ALL")
  const [descriptionFilter, setDescriptionFilter] = useState("")
  const [ledgerPage, setLedgerPage] = useState(1)
  // Newest first. Sorted on the full createdDate timestamp rather than the
  // yyyy-mm-dd string the column displays, so several movements on the same day
  // still read newest-first instead of falling back to insertion order.
  const [sortKey, setSortKey] = useState<string | null>("createdDate")
  const [sortDir, setSortDir] = useState<SortDirection>("desc")

  const loadPositions = useCallback(async () => {
    setError("")
    try {
      const data = await getWaterInventoryTracker(fromDate, toDate) ?? []
      setRows(data)
      return data
    } catch (e: any) {
      setError(e?.message ?? String(e))
      return []
    }
  }, [fromDate, toDate])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    // Only the FIRST load blanks the page. Changing the period re-runs this
    // effect (loadPositions closes over the dates), and setting `loading` there
    // tore the whole page down and rebuilt it for every preset click. Later
    // fetches happen underneath the figures; the ledger card shows its own
    // "Loading ledger…" for the part that is genuinely changing.
    if (firstLoad.current) setLoading(true)
    void loadPositions().then((data) => {
      // Preselect from ?productId= (the Track link on /water-inventory), else
      // the product with the most movement — an empty ledger is a poor landing.
      setProductId((current) => {
        if (current != null) return current
        const wanted = Number(searchParams.get("productId"))
        if (wanted && data.some((r) => r.waterProductId === wanted)) return wanted
        const busiest = [...data].sort((a, b) => b.movementCount - a.movementCount)[0]
        return busiest?.waterProductId ?? null
      })
    }).finally(() => { firstLoad.current = false; setLoading(false) })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, loadPositions])

  // Ledger for the selected product.
  useEffect(() => {
    if (productId == null) { setMoves([]); return }
    let cancelled = false
    setMovesLoading(true)
    getWaterInventoryTrackerMovements(productId, fromDate, toDate)
      .then((m) => { if (!cancelled) { setMoves(m ?? []); setLedgerPage(1) } })
      .catch((e) => { if (!cancelled) setError(e?.message ?? String(e)) })
      .finally(() => { if (!cancelled) setMovesLoading(false) })
    return () => { cancelled = true }
  }, [productId, fromDate, toDate])

  async function handleRefresh() {
    setRefreshing(true)
    await loadPositions()
    if (productId != null) {
      try { setMoves(await getWaterInventoryTrackerMovements(productId, fromDate, toDate) ?? []) }
      catch (e: any) { setError(e?.message ?? String(e)) }
    }
    setRefreshing(false)
  }

  const selected = useMemo(
    () => rows.find((r) => r.waterProductId === productId) ?? null,
    [rows, productId],
  )

  const distinctTypes = useMemo(
    () => Array.from(new Set(moves.map((m) => m.movementLabel).filter(Boolean))).sort(),
    [moves],
  )

  // In / Out are split from the signed base quantity so the ledger reads like
  // the egg tracker's, which has a column each rather than one signed number.
  const ledgerRows = useMemo(() => {
    const q = descriptionFilter.trim().toLowerCase()
    return moves
      .filter((m) => typeFilter === "ALL" || m.movementLabel === typeFilter)
      .filter((m) => !q || (m.note ?? "").toLowerCase().includes(q))
      .map((m) => ({
        ...m,
        date: (m.createdDate ?? "").split("T")[0],
        description: m.note ?? "—",
        inQty: m.baseQuantity > 0 ? m.baseQuantity : 0,
        outQty: m.baseQuantity < 0 ? -m.baseQuantity : 0,
      }))
  }, [moves, typeFilter, descriptionFilter])

  const sortedRows = useMemo(
    () => sortData(ledgerRows, sortKey, sortDir),
    [ledgerRows, sortKey, sortDir],
  )

  // Totals for the WHOLE filtered set, not the visible page — a total that only
  // covered page 1 would quietly disagree with the columns above it.
  const ledgerTotals = useMemo(() => {
    const inQty = sortedRows.reduce((s, r) => s + r.inQty, 0)
    const outQty = sortedRows.reduce((s, r) => s + r.outQty, 0)
    return { inQty, outQty, net: inQty - outQty }
  }, [sortedRows])

  const totalPages = Math.max(1, Math.ceil(sortedRows.length / LEDGER_PAGE_SIZE))
  const safePage = Math.min(ledgerPage, totalPages)
  const pageRows = useMemo(
    () => sortedRows.slice((safePage - 1) * LEDGER_PAGE_SIZE, safePage * LEDGER_PAGE_SIZE),
    [sortedRows, safePage],
  )

  const handleSort = (key: string) => {
    const next = toggleSort(key, sortKey, sortDir)
    setSortKey(next.key); setSortDir(next.direction)
  }

  // Resets what you filtered BY, not what you are looking at: the product stays,
  // because clearing it would leave the page with nothing to show.
  const clearLedgerFilters = () => {
    setTypeFilter("ALL")
    setDescriptionFilter("")
    setFromDate(DEFAULT_RANGE.from)
    setToDate(DEFAULT_RANGE.to)
    setLedgerPage(1)
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">

            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-sky-100 rounded-lg flex items-center justify-center">
                  <History className="w-5 h-5 text-sky-700" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Inventory tracker</h1>
                  <p className="text-sm text-slate-600">
                    Ledger from production, sales, vehicle loadings, internal use and adjustments —
                    every movement behind a product&apos;s stock figure.
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
                <CardContent className="py-12 text-center text-slate-600">Loading inventory tracker…</CardContent>
              </Card>
            ) : rows.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center text-slate-600">
                  No water products yet. Add one under Products to start tracking stock.
                </CardContent>
              </Card>
            ) : (
              <>
                {/* Product is the page's SUBJECT, not one of the ledger's
                    filters: every figure and every row below describes this one
                    product, so it sits above them on its own rather than as the
                    first cell of a filter grid. */}
                <div className="flex flex-wrap items-center gap-3 rounded-lg border border-slate-200 bg-white p-3">
                  <label className="text-sm font-medium text-slate-700">Product</label>
                  <Select
                    value={productId != null ? String(productId) : ""}
                    onValueChange={(v) => { setProductId(Number(v)); setLedgerPage(1) }}
                  >
                    <SelectTrigger className="h-10 w-full sm:w-[22rem]">
                      <SelectValue placeholder="Pick a product" />
                    </SelectTrigger>
                    <SelectContent>
                      {rows.map((r) => (
                        <SelectItem key={r.waterProductId} value={String(r.waterProductId)}>
                          {r.productName}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {selected ? (
                    <span className="text-xs text-slate-500">
                      {selected.movementCount === 1
                        ? "1 movement in this period"
                        : `${selected.movementCount.toLocaleString()} movements in this period`}
                    </span>
                  ) : null}
                </div>

                {/* ------------------------------------------------- hero */}
                <Card className="border-sky-200 bg-sky-50/50">
                  {/* Figures only. Every control lives in the one filter row on
                      the ledger card below — the dates used to sit here as well,
                      which meant two date pickers on one page. */}
                  <CardHeader className="pb-2">
                    <CardDescription>Stock on hand</CardDescription>
                    <CardTitle className="text-base font-semibold text-slate-800 mt-1">
                      {selected?.productName ?? "Pick a product"}
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className={cn("grid gap-4", isMobile ? "grid-cols-2" : "grid-cols-5")}>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">
                          On hand{selected?.baseUnit ? ` (${selected.baseUnit.toLowerCase()}s)` : ""}
                        </div>
                        <div className={cn(
                          "mt-1 text-2xl font-bold tabular-nums",
                          (selected?.closingBase ?? 0) < 0 ? "text-red-600" : "text-slate-900",
                        )}>
                          {selected ? qty(selected.closingBase) : "—"}
                        </div>
                        {selected?.isSachetProduct && selected.sachetsPerBag > 1 ? (
                          <div className="text-[11px] text-slate-500">{qty(selected.closingBags)} bags</div>
                        ) : null}
                      </div>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Opening</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-slate-900">
                          {selected ? qty(selected.openingBase) : "—"}
                        </div>
                      </div>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">In</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-emerald-700">
                          {selected ? qty(selected.stockInBase) : "—"}
                        </div>
                      </div>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Out</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-rose-700">
                          {selected ? qty(selected.stockOutBase) : "—"}
                        </div>
                      </div>
                      <div>
                        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Stock value</div>
                        <div className="mt-1 text-2xl font-bold tabular-nums text-slate-900">
                          {selected ? fmtMoney(selected.closingValue) : "—"}
                        </div>
                      </div>
                    </div>
                  </CardContent>
                </Card>

                {/* ----------------------------------------------- ledger */}
                <Card className="bg-white">
                  <CardHeader>
                    <CardTitle>Stock ledger</CardTitle>
                    <CardDescription>Chronological ledger; filter the table below</CardDescription>
                    {/* Ledger filters. Product is not here — it is the page
                        subject and sits at the top. Period presets drive the
                        two date boxes; picking dates by hand flips the preset
                        back to Custom on its own via rangeToPeriod. */}
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
                    {movesLoading ? (
                      <p className="text-slate-600 py-8 text-center text-sm">Loading ledger…</p>
                    ) : sortedRows.length === 0 ? (
                      <p className="text-slate-600 py-8 text-center text-sm">
                        {moves.length === 0
                          ? "No movements for this product in the selected period."
                          : "No ledger rows match those filters."}
                      </p>
                    ) : (
                      <>
                      {/* Mobile opens on scorecards (expanded by default);
                          "View table format" flips to the wide ledger table. */}
                      <MobileCardList
                        striped
                        defaultOpen
                        items={pageRows}
                        getKey={(row) => row.stockTxnId}
                        primary={(row) => row.date || "—"}
                        secondary={(row) => <span className="truncate">{row.movementLabel}</span>}
                        trailing={(row) => (
                          <span className="text-sm font-semibold tabular-nums text-slate-900">{qty(row.runningBase)}</span>
                        )}
                        highlights={(row) => [
                          { label: "In", value: row.inQty > 0 ? qty(row.inQty) : "—", accent: "emerald" },
                          { label: "Out", value: row.outQty > 0 ? qty(row.outQty) : "—", accent: "rose" },
                          { label: "Balance", value: qty(row.runningBase), accent: "violet", wide: true },
                        ]}
                        details={(row) => [
                          { label: "Description", value: row.description },
                        ]}
                        desktopTable={
                      <div className="overflow-x-auto table-scroll-wrapper pb-2" style={{ WebkitOverflowScrolling: "touch" }}>
                        <Table className="w-full min-w-[620px]">
                          <TableHeader>
                            <TableRow>
                              <SortableHeader label="Date"        sortKey="createdDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                              <SortableHeader label="Type"        sortKey="movementLabel" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                              <SortableHeader label="Description" sortKey="description" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                              <SortableHeader label="In"          sortKey="inQty"       currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" />
                              <SortableHeader label="Out"         sortKey="outQty"      currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" />
                              <TableHead className="text-right">Balance</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pageRows.map((row) => (
                              <TableRow key={row.stockTxnId}>
                                <TableCell className="font-medium whitespace-nowrap">{row.date || "—"}</TableCell>
                                <TableCell>{row.movementLabel}</TableCell>
                                <TableCell className="max-w-[220px] truncate" title={row.description}>
                                  {row.description}
                                </TableCell>
                                <TableCell className="text-right text-emerald-600 tabular-nums">
                                  {row.inQty > 0 ? qty(row.inQty) : "—"}
                                </TableCell>
                                <TableCell className="text-right text-red-600 tabular-nums">
                                  {row.outQty > 0 ? qty(row.outQty) : "—"}
                                </TableCell>
                                <TableCell className="text-right font-medium tabular-nums">
                                  {qty(row.runningBase)}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                          {/* Totals cover every filtered row, not just this
                              page, and move with the filters above. */}
                          <TableFooter>
                            <TableRow className="bg-slate-50 hover:bg-slate-50">
                              <TableCell colSpan={3} className="font-medium text-slate-700">
                                Totals
                                <span className="ml-1.5 font-normal text-xs text-slate-500">
                                  ({sortedRows.length.toLocaleString()}
                                  {sortedRows.length === 1 ? " movement" : " movements"})
                                </span>
                              </TableCell>
                              <TableCell className="text-right font-semibold tabular-nums text-emerald-700">
                                {ledgerTotals.inQty > 0 ? qty(ledgerTotals.inQty) : "—"}
                              </TableCell>
                              <TableCell className="text-right font-semibold tabular-nums text-red-600">
                                {ledgerTotals.outQty > 0 ? qty(ledgerTotals.outQty) : "—"}
                              </TableCell>
                              {/* Balance is a running position, not a quantity:
                                  summing it would add a product's stock level to
                                  itself once per row and mean nothing. Left
                                  blank on purpose. */}
                              <TableCell />
                            </TableRow>
                          </TableFooter>
                        </Table>
                      </div>
                        }
                      />

                      {/* The footer totals live in the table, which mobile does
                          not show, so repeat them as a strip under the cards. */}
                      <div className="lg:hidden mx-3 mb-2 flex items-center justify-between gap-2 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-xs">
                        <span className="text-slate-600">
                          Totals ({sortedRows.length.toLocaleString()}{sortedRows.length === 1 ? " movement" : " movements"})
                        </span>
                        <span className="flex items-center gap-3 tabular-nums">
                          <span className="font-semibold text-emerald-700">In {ledgerTotals.inQty > 0 ? qty(ledgerTotals.inQty) : "—"}</span>
                          <span className="font-semibold text-red-600">Out {ledgerTotals.outQty > 0 ? qty(ledgerTotals.outQty) : "—"}</span>
                        </span>
                      </div>

                        <div className="flex items-center justify-center gap-2 pt-3">
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
                      Out covers sales, vehicle loadings and internal use. Damage and loss records do not
                      post to the stock ledger, so stock written off through Loss Records will not appear here.
                    </p>
                  </CardContent>
                </Card>
              </>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

// useSearchParams needs a Suspense boundary to prerender; the house pattern
// pairs it with the force-dynamic above (see app/generic-expenses/page.tsx).
export default function WaterInventoryTrackerPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <WaterInventoryTrackerPageInner />
    </Suspense>
  )
}

"use client"

// Water Company "Owner Intelligence" dashboard section.
// Covers the four spec §17 questions that weren't surfaced before:
//   - "Where did my money go?"  → ExpenseBreakdownCard (top 5 categories MTD)
//   - "Which route is winning?"  → BestWorstRouteCard
//   - "Who are my top customers / biggest debtors?" → TopCustomersCard
//   - "How much profit per bag?" → ProfitPerBagCard
//
// All cards fetch in parallel; partial failures are isolated per card so one
// missing endpoint doesn't blank the whole section. Date range defaults to
// "this month" (first day → today) which matches the dashboard's existing
// "this month" headline tiles.

import { useEffect, useMemo, useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Activity, AlertTriangle, Award, Loader2, PieChart, Receipt, Route as RouteIcon, TrendingDown, TrendingUp, Users,
} from "lucide-react"
import {
  getWaterExpenseByCategory, getWaterPeriodPnL, getWaterRouteProfitability,
  getWaterTopCustomers,
  type WaterExpenseByCategoryRow, type WaterPeriodPnL, type WaterRouteProfitabilityRow, type WaterTopCustomerRow,
} from "@/lib/api/water"

// "GHC 1,234.56" — matches water-dashboard's fmtMoney. ISO code is GHS but
// the platform's user-facing label is GHC, so format the number and prefix.
function gh(n: number | null | undefined): string {
  const v = Number.isFinite(Number(n)) ? Number(n) : 0
  return `GHC ${new Intl.NumberFormat(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(v)}`
}

function ghShort(n: number | null | undefined): string {
  // Compact form for small tiles: "GHC 12.3K" / "GHC 1.2M"
  const v = Number.isFinite(Number(n)) ? Number(n) : 0
  if (Math.abs(v) >= 1_000_000) return `GHC ${(v / 1_000_000).toFixed(1)}M`
  if (Math.abs(v) >= 1_000)     return `GHC ${(v / 1_000).toFixed(1)}K`
  return `GHC ${v.toFixed(2)}`
}

function firstOfMonthIso(): string {
  const d = new Date(); d.setDate(1); d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
  return d.toISOString().slice(0, 10)
}
function todayIso(): string {
  const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
  return d.toISOString().slice(0, 10)
}

interface SectionProps {
  /** Optional override; defaults to "first of this month" → today. */
  fromDate?: string
  toDate?: string
}

// ---------------------------------------------------------------------------
// Top-level section
// ---------------------------------------------------------------------------
export function WaterIntelligenceSection({ fromDate, toDate }: SectionProps) {
  const from = fromDate ?? firstOfMonthIso()
  const to   = toDate   ?? todayIso()

  return (
    <section aria-label="Owner intelligence">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-lg font-semibold text-slate-800 flex items-center gap-2">
          <Activity className="h-5 w-5 text-emerald-600" />
          Owner intelligence
        </h2>
        <span className="text-xs text-slate-500">
          Period: {from} → {to}
        </span>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <ExpenseBreakdownCard fromDate={from} toDate={to} />
        <ProfitPerBagCard     fromDate={from} toDate={to} />
        <BestWorstRouteCard   fromDate={from} toDate={to} />
        <TopCustomersCard     fromDate={from} toDate={to} />
      </div>
    </section>
  )
}

// ---------------------------------------------------------------------------
// Card 1 — Where did my money go?  (top 5 expense categories with % bars)
// ---------------------------------------------------------------------------
function ExpenseBreakdownCard({ fromDate, toDate }: { fromDate: string; toDate: string }) {
  const [rows, setRows] = useState<WaterExpenseByCategoryRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setRows(null); setError(null)
    getWaterExpenseByCategory(fromDate, toDate)
      .then(setRows)
      .catch((e) => setError(e?.message ?? String(e)))
  }, [fromDate, toDate])

  const total = useMemo(
    () => (rows ?? []).reduce((s, r) => s + (Number(r.totalAmount) || 0), 0),
    [rows]
  )
  const top = (rows ?? []).slice(0, 5)

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <PieChart className="h-4 w-4 text-slate-500" />
          Where did the money go?
        </CardTitle>
      </CardHeader>
      <CardContent>
        {rows === null && !error && (
          <div className="flex items-center gap-2 text-slate-500 text-sm">
            <Loader2 className="h-3 w-3 animate-spin" /> Loading…
          </div>
        )}
        {error && <div className="text-sm text-rose-600">Could not load: {error}</div>}
        {rows && rows.length === 0 && (
          <div className="text-sm text-slate-500">No approved expenses in this period.</div>
        )}
        {top.length > 0 && (
          <div className="space-y-2">
            {top.map((r) => {
              const pct = total > 0 ? (Number(r.totalAmount) / total) * 100 : 0
              return (
                <div key={r.waterExpenseCategoryId}>
                  <div className="flex items-center justify-between text-sm mb-1">
                    <span className="font-medium text-slate-700 truncate pr-2">{r.categoryName}</span>
                    <span className="text-slate-500 tabular-nums whitespace-nowrap">
                      {gh(r.totalAmount)}{" "}
                      <span className="text-xs text-slate-400">({pct.toFixed(1)}%)</span>
                    </span>
                  </div>
                  <div className="h-1.5 bg-slate-100 rounded overflow-hidden">
                    <div className="h-full bg-emerald-500" style={{ width: `${Math.max(2, pct)}%` }} />
                  </div>
                </div>
              )
            })}
            {rows && rows.length > 5 && (
              <div className="text-xs text-slate-400 pt-1">
                + {rows.length - 5} more categor{rows.length - 5 === 1 ? "y" : "ies"}, total {gh(total)}
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Card 2 — Profit per bag  (single big metric + bags context)
// ---------------------------------------------------------------------------
function ProfitPerBagCard({ fromDate, toDate }: { fromDate: string; toDate: string }) {
  const [pnl, setPnl] = useState<WaterPeriodPnL | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setPnl(null); setError(null)
    getWaterPeriodPnL(fromDate, toDate)
      .then(setPnl)
      .catch((e) => setError(e?.message ?? String(e)))
  }, [fromDate, toDate])

  const ppb = Number(pnl?.avgProfitPerBag ?? 0)
  const isProfit = ppb >= 0
  const accentClass = isProfit ? "text-emerald-700" : "text-rose-700"
  const Icon = isProfit ? TrendingUp : TrendingDown

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Award className="h-4 w-4 text-slate-500" />
          Profit per bag
        </CardTitle>
      </CardHeader>
      <CardContent>
        {pnl === null && !error && (
          <div className="flex items-center gap-2 text-slate-500 text-sm">
            <Loader2 className="h-3 w-3 animate-spin" /> Loading…
          </div>
        )}
        {error && <div className="text-sm text-rose-600">Could not load: {error}</div>}
        {pnl && (
          <>
            <div className={`text-3xl font-bold tabular-nums ${accentClass} flex items-center gap-2`}>
              <Icon className="h-6 w-6" />
              {gh(ppb)}
            </div>
            <div className="mt-3 grid grid-cols-3 gap-3 text-sm">
              <div>
                <div className="text-slate-500 text-xs">Bags produced</div>
                <div className="font-semibold">{pnl.bagsProduced.toLocaleString()}</div>
              </div>
              <div>
                <div className="text-slate-500 text-xs">Bags sold</div>
                <div className="font-semibold">{pnl.bagsSold.toLocaleString()}</div>
              </div>
              <div>
                <div className="text-slate-500 text-xs">Margin</div>
                <div className={`font-semibold ${(pnl.profitMarginPct ?? 0) >= 0 ? "text-emerald-700" : "text-rose-700"}`}>
                  {(pnl.profitMarginPct ?? 0).toFixed(1)}%
                </div>
              </div>
            </div>
            {pnl.bagsProduced > 0 && pnl.bagsSold < pnl.bagsProduced && (
              <p className="text-xs text-amber-700 mt-3 flex items-start gap-1">
                <AlertTriangle className="h-3 w-3 mt-0.5 shrink-0" />
                {(pnl.bagsProduced - pnl.bagsSold).toLocaleString()} bag(s) produced this period haven't been sold yet.
              </p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Card 3 — Best / worst route
// ---------------------------------------------------------------------------
function BestWorstRouteCard({ fromDate, toDate }: { fromDate: string; toDate: string }) {
  const [rows, setRows] = useState<WaterRouteProfitabilityRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setRows(null); setError(null)
    getWaterRouteProfitability(fromDate, toDate)
      .then(setRows)
      .catch((e) => setError(e?.message ?? String(e)))
  }, [fromDate, toDate])

  // SP already orders by NetRouteIncome DESC — first = best, last = worst.
  const best  = rows && rows.length > 0 ? rows[0] : null
  const worst = rows && rows.length > 1 ? rows[rows.length - 1] : null

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <RouteIcon className="h-4 w-4 text-slate-500" />
          Routes
        </CardTitle>
      </CardHeader>
      <CardContent>
        {rows === null && !error && (
          <div className="flex items-center gap-2 text-slate-500 text-sm">
            <Loader2 className="h-3 w-3 animate-spin" /> Loading…
          </div>
        )}
        {error && <div className="text-sm text-rose-600">Could not load: {error}</div>}
        {rows && rows.length === 0 && (
          <div className="text-sm text-slate-500">No route activity in this period.</div>
        )}
        {best && (
          <div className="space-y-3">
            <div>
              <div className="flex items-center gap-2 text-xs text-emerald-700 font-medium uppercase tracking-wide">
                <TrendingUp className="h-3 w-3" /> Best route
              </div>
              <div className="mt-1 flex items-center justify-between">
                <div>
                  <div className="font-semibold">{best.routeName}</div>
                  <div className="text-xs text-slate-500">
                    {Number(best.totalBagsSold).toLocaleString()} bags · shortages {gh(best.totalShortages)}
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-lg font-bold text-emerald-700 tabular-nums">{ghShort(best.netRouteIncome)}</div>
                  <div className="text-xs text-slate-400">net income</div>
                </div>
              </div>
            </div>

            {worst && worst.waterRouteId !== best.waterRouteId && (
              <div className="pt-3 border-t border-slate-100">
                <div className="flex items-center gap-2 text-xs text-rose-700 font-medium uppercase tracking-wide">
                  <TrendingDown className="h-3 w-3" /> Worst route
                </div>
                <div className="mt-1 flex items-center justify-between">
                  <div>
                    <div className="font-semibold">{worst.routeName}</div>
                    <div className="text-xs text-slate-500">
                      {Number(worst.totalBagsSold).toLocaleString()} bags · shortages {gh(worst.totalShortages)}
                    </div>
                  </div>
                  <div className="text-right">
                    <div className={`text-lg font-bold tabular-nums ${Number(worst.netRouteIncome) < 0 ? "text-rose-700" : "text-slate-700"}`}>
                      {ghShort(worst.netRouteIncome)}
                    </div>
                    <div className="text-xs text-slate-400">net income</div>
                  </div>
                </div>
              </div>
            )}

            {rows && rows.length > 0 && (
              <div className="text-xs text-slate-400 pt-1">{rows.length} route(s) active this period.</div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Card 4 — Top customers (by sales) + biggest debtor
// ---------------------------------------------------------------------------
function TopCustomersCard({ fromDate, toDate }: { fromDate: string; toDate: string }) {
  const [rows, setRows] = useState<WaterTopCustomerRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setRows(null); setError(null)
    getWaterTopCustomers(fromDate, toDate, 10)
      .then(setRows)
      .catch((e) => setError(e?.message ?? String(e)))
  }, [fromDate, toDate])

  // SP orders by TotalSales DESC. Compute biggest debtor client-side from same set.
  const topBySales = (rows ?? []).slice(0, 3)
  const biggestDebtor = useMemo(() => {
    if (!rows || rows.length === 0) return null
    const debtors = [...rows].sort((a, b) => Number(b.outstandingBalance) - Number(a.outstandingBalance))
    const c = debtors[0]
    return Number(c.outstandingBalance) > 0 ? c : null
  }, [rows])

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Users className="h-4 w-4 text-slate-500" />
          Customers
        </CardTitle>
      </CardHeader>
      <CardContent>
        {rows === null && !error && (
          <div className="flex items-center gap-2 text-slate-500 text-sm">
            <Loader2 className="h-3 w-3 animate-spin" /> Loading…
          </div>
        )}
        {error && <div className="text-sm text-rose-600">Could not load: {error}</div>}
        {rows && rows.length === 0 && (
          <div className="text-sm text-slate-500">No customer sales in this period.</div>
        )}
        {topBySales.length > 0 && (
          <div className="space-y-3">
            <div>
              <div className="flex items-center gap-2 text-xs text-emerald-700 font-medium uppercase tracking-wide">
                <Award className="h-3 w-3" /> Top by sales
              </div>
              <div className="mt-2 space-y-1.5">
                {topBySales.map((c, i) => (
                  <div key={c.waterCustomerId} className="flex items-center justify-between text-sm">
                    <span className="truncate pr-2">
                      <span className="text-slate-400 mr-1">{i + 1}.</span>
                      <span className="font-medium">{c.customerName}</span>
                      <span className="text-slate-400 text-xs ml-2">{c.salesCount}× sales</span>
                    </span>
                    <span className="tabular-nums font-semibold text-slate-700 whitespace-nowrap">{gh(c.totalSales)}</span>
                  </div>
                ))}
              </div>
            </div>

            {biggestDebtor && (
              <div className="pt-3 border-t border-slate-100">
                <div className="flex items-center gap-2 text-xs text-rose-700 font-medium uppercase tracking-wide">
                  <Receipt className="h-3 w-3" /> Biggest debtor
                </div>
                <div className="mt-1 flex items-center justify-between">
                  <div>
                    <div className="font-semibold">{biggestDebtor.customerName}</div>
                    {biggestDebtor.phoneNumber && (
                      <div className="text-xs text-slate-500">{biggestDebtor.phoneNumber}</div>
                    )}
                  </div>
                  <div className="text-right">
                    <div className="text-lg font-bold text-rose-700 tabular-nums">{ghShort(biggestDebtor.outstandingBalance)}</div>
                    <Badge variant="outline" className="text-xs">owes</Badge>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

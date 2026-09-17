"use client"

/**
 * Every Restaurant report, defined as data.
 *
 * Each entry says what to fetch, what the columns are, and optionally what KPI
 * tiles and chart to show. The shell and the table primitive do the rest, so a
 * report cannot ship without a date control, without an export, or with a CSV
 * that disagrees with what is on screen -- the three things that went wrong on
 * the page this replaces.
 *
 * Adding a report is one entry here plus one line in restaurant-reports-config.
 */

import type { ReactNode } from "react"
import {
  BarChart, Bar, LineChart, Line, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from "recharts"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { ToneBadge } from "@/components/reports/report-table"
import type { ColumnDef, Fmt, ReportDefinition } from "@/components/reports/report-table"
import {
  // migration 223
  getDailySalesReport, getSalesByItem, getSalesByCategory, getSalesByHour,
  getRevenueTrend, getFoodCostReport, getServerPerformance,
  // migration 298
  getPnlSummary, getPnlExpenses, getSalesSummary, getPaymentMethods,
  getKitchenPerformance, getTableTurnover, getTipsReport, getDeliveryPerformance,
  getDiscountsReport, getVoidsReport, getStockOnHand, getWasteDetail,
  getExpenseReport, getMenuEngineering, getCustomerRetention, getChannelReport,
  getEventsReport, getFeedbackReport,
} from "@/lib/api/restaurant"
import type {
  SalesSummaryReport, PnlSummary, CustomerRetentionReport, DailySalesReport,
} from "@/lib/api/restaurant"

const ROSE = "#e11d48"
const ROSE_LIGHT = "#fda4af"
const PIE_COLORS = ["#e11d48", "#f43f5e", "#fb7185", "#fda4af", "#fecdd3", "#9f1239", "#be123c", "#881337"]

/** A label/value pair, for the reports whose answer is a set of figures. */
interface MetricRow { metric: string; value: string }

const METRIC_COLUMNS: ColumnDef<MetricRow>[] = [
  { key: "metric", label: "Metric", value: (r) => r.metric },
  { key: "value", label: "Value", value: (r) => r.value, numeric: true },
]

function chartCard(title: string, hint: string, body: ReactNode) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">{title}</CardTitle>
        <CardDescription>{hint}</CardDescription>
      </CardHeader>
      <CardContent>{body}</CardContent>
    </Card>
  )
}

// ===========================================================================
// MONEY
// ===========================================================================

const pnl: ReportDefinition<{ expenseCategory: string; entryCount: number; expenseTotal: number; sharePct: number }, PnlSummary> = {
  load: async (r) => {
    const [summary, rows] = await Promise.all([
      getPnlSummary(r.from, r.to),
      getPnlExpenses(r.from, r.to),
    ])
    return { rows, meta: summary }
  },
  summary: (r, f) => {
    const m = r.meta
    if (!m) return []
    return [
      { label: "Revenue", value: f.money(m.revenue) },
      { label: "Cost of goods", value: f.money(m.cogs) },
      { label: "Gross profit", value: `${f.money(m.grossProfit)} (${f.pct(m.grossMarginPct)})` },
      { label: "Net profit", value: `${f.money(m.netProfit)} (${f.pct(m.netMarginPct)})` },
    ]
  },
  panel: (r, f) => {
    const m = r.meta
    if (!m) return null
    // The waterfall as plain rows rather than a chart: a P&L is read down a
    // column, and four bars would say less than four lines do.
    const lines: { label: string; value: string; strong?: boolean; negative?: boolean }[] = [
      { label: "Revenue (net of tax and service charge)", value: f.money(m.revenue) },
      { label: "Less cost of goods sold", value: `- ${f.money(m.cogs)}`, negative: true },
      { label: "Gross profit", value: f.money(m.grossProfit), strong: true },
      { label: "Less operating expenses", value: `- ${f.money(m.expensesTotal)}`, negative: true },
      { label: "Net profit", value: f.money(m.netProfit), strong: true },
    ]
    return (
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Profit &amp; loss</CardTitle></CardHeader>
          <CardContent>
            {lines.map((l) => (
              <div
                key={l.label}
                className={`flex justify-between gap-3 py-2 border-b last:border-0 ${l.strong ? "font-semibold" : ""}`}
              >
                <span className="text-sm">{l.label}</span>
                <span className={`tabular-nums text-sm ${l.negative ? "text-red-600" : ""} ${
                  l.strong && m.netProfit < 0 && l.label.startsWith("Net") ? "text-red-700" : ""
                }`}>
                  {l.value}
                </span>
              </div>
            ))}
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Ratios</CardTitle></CardHeader>
          <CardContent>
            {[
              ["Food cost", f.pct(m.foodCostPct), m.foodCostPct > 35 ? "bad" : m.foodCostPct > 30 ? "warn" : "good"],
              ["Gross margin", f.pct(m.grossMarginPct), m.grossMarginPct >= 60 ? "good" : "warn"],
              ["Net margin", f.pct(m.netMarginPct), m.netMarginPct >= 10 ? "good" : m.netMarginPct >= 0 ? "warn" : "bad"],
              ["Orders in period", f.int(m.orderCount), "muted"],
              ["Tips collected", f.money(m.tipsTotal), "muted"],
            ].map(([label, value, tone]) => (
              <div key={String(label)} className="flex justify-between items-center gap-3 py-2 border-b last:border-0">
                <span className="text-sm">{label}</span>
                <ToneBadge text={String(value)} tone={tone as "good" | "warn" | "bad" | "muted"} />
              </div>
            ))}
          </CardContent>
        </Card>
      </div>
    )
  },
  columns: [
    { key: "cat", label: "Expense category", value: (r) => r.expenseCategory },
    { key: "n", label: "Entries", value: (r, f) => f.int(r.entryCount), numeric: true, secondary: true },
    { key: "total", label: "Total", value: (r, f) => f.money(r.expenseTotal), numeric: true },
    { key: "share", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Operating expenses by category",
  emptyText: "No expenses recorded in this period. The profit figures above are still correct — they simply have nothing to deduct.",
}

const salesSummary: ReportDefinition<MetricRow, SalesSummaryReport> = {
  load: async (r) => {
    const s = await getSalesSummary(r.from, r.to)
    return { rows: [], meta: s }
  },
  summary: (r, f) => {
    const s = r.meta
    if (!s) return []
    return [
      { label: "Gross revenue", value: f.money(s.grossRevenue) },
      { label: "Completed orders", value: `${f.int(s.completedOrders)} of ${f.int(s.totalOrders)}` },
      { label: "Average ticket", value: f.money(s.avgTicket) },
      { label: "Covers", value: f.int(s.coversTotal) },
    ]
  },
  columns: METRIC_COLUMNS,
  tableTitle: "Every figure for this period",
  emptyText: "No orders in this period.",
}

const paymentMethods: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getPaymentMethods(r.from, r.to) }),
  summary: (r, f) => {
    const total = r.rows.reduce((s: number, x: any) => s + x.amountTotal, 0)
    const tips = r.rows.reduce((s: number, x: any) => s + x.tipsTotal, 0)
    return [
      { label: "Total taken", value: f.money(total) },
      { label: "Tips included", value: f.money(tips) },
      { label: "Methods used", value: f.int(r.rows.length) },
      { label: "Transactions", value: f.int(r.rows.reduce((s: number, x: any) => s + x.txnCount, 0)) },
    ]
  },
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("Share of take", "Which methods the money arrives by",
      <ResponsiveContainer width="100%" height={260}>
        <PieChart>
          <Pie data={r.rows} dataKey="amountTotal" nameKey="methodName" cx="50%" cy="50%" outerRadius={90}
               label={({ methodName, percent }: any) => `${methodName} ${(percent * 100).toFixed(0)}%`} labelLine={false}>
            {r.rows.map((_: any, i: number) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
          </Pie>
          <Tooltip formatter={(v: number) => v.toFixed(2)} />
        </PieChart>
      </ResponsiveContainer>),
  columns: [
    { key: "m", label: "Method", value: (r) => r.methodName },
    { key: "n", label: "Transactions", value: (r, f) => f.int(r.txnCount), numeric: true },
    { key: "amt", label: "Amount", value: (r, f) => f.money(r.amountTotal), numeric: true },
    { key: "tips", label: "Tips", value: (r, f) => f.money(r.tipsTotal), numeric: true, secondary: true },
    { key: "avg", label: "Average", value: (r, f) => f.money(r.avgTxn), numeric: true, secondary: true },
    { key: "share", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Payments by method",
  emptyText: "No completed payments in this period.",
}

const expenses: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getExpenseReport(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Total spend", value: f.money(r.rows.reduce((s: number, x: any) => s + x.expenseTotal, 0)) },
    { label: "Entries", value: f.int(r.rows.reduce((s: number, x: any) => s + x.entryCount, 0)) },
    { label: "Categories", value: f.int(new Set(r.rows.map((x: any) => x.expenseCategory)).size) },
    { label: "Suppliers", value: f.int(new Set(r.rows.map((x: any) => x.supplierLabel)).size) },
  ],
  columns: [
    { key: "cat", label: "Category", value: (r) => r.expenseCategory },
    { key: "sup", label: "Supplier", value: (r) => r.supplierLabel, secondary: true },
    { key: "pm", label: "Paid by", value: (r) => r.methodLabel, secondary: true },
    { key: "n", label: "Entries", value: (r, f) => f.int(r.entryCount), numeric: true, secondary: true },
    { key: "amt", label: "Total", value: (r, f) => f.money(r.expenseTotal), numeric: true },
    { key: "share", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Expenses",
  emptyText: "No expenses recorded in this period.",
}

const discounts: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getDiscountsReport(r.from, r.to) }),
  summary: (r, f) => {
    const given = r.rows.reduce((s: number, x: any) => s + x.discountTotal, 0)
    const gross = r.rows.reduce((s: number, x: any) => s + x.grossOnDiscounted, 0)
    return [
      { label: "Given away", value: f.money(given) },
      { label: "On sales of", value: f.money(gross) },
      { label: "Effective rate", value: gross > 0 ? f.pct((given / gross) * 100) : f.pct(0) },
      { label: "Distinct discounts", value: f.int(r.rows.length) },
    ]
  },
  columns: [
    { key: "d", label: "Discount", value: (r) => r.discountLabel },
    { key: "k", label: "Type", value: (r) => r.discountKind, secondary: true },
    { key: "n", label: "Times used", value: (r, f) => f.int(r.timesApplied), numeric: true },
    { key: "o", label: "Orders", value: (r, f) => f.int(r.ordersAffected), numeric: true, secondary: true },
    { key: "t", label: "Given away", value: (r, f) => f.money(r.discountTotal), numeric: true },
    { key: "a", label: "Average", value: (r, f) => f.money(r.avgDiscount), numeric: true, secondary: true },
    { key: "e", label: "Effective rate", value: (r, f) => f.pct(r.effectivePct), numeric: true },
  ],
  tableTitle: "Discounts applied",
  tableHint: "Effective rate is what was actually given away against the value of the orders it was given on.",
  emptyText: "No discounts were applied to completed orders in this period.",
}

// ===========================================================================
// SALES
// ===========================================================================

const dailySales: ReportDefinition<MetricRow, DailySalesReport> = {
  load: async (r) => {
    const d = await getDailySalesReport(r.date)
    return { rows: [], meta: d }
  },
  summary: (r, f) => {
    const d = r.meta
    if (!d) return []
    return [
      { label: "Revenue", value: f.money(d.totalRevenue) },
      { label: "Orders", value: `${f.int(d.completedOrders)} of ${f.int(d.totalOrders)}` },
      { label: "Average ticket", value: f.money(d.avgTicket) },
      { label: "Covers", value: f.int(d.totalCovers) },
    ]
  },
  columns: METRIC_COLUMNS,
  tableTitle: "The day in full",
  emptyText: "No orders on this date.",
}

const revenueTrend: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getRevenueTrend(r.from, r.to) }),
  summary: (r, f) => {
    const rev = r.rows.reduce((s: number, x: any) => s + x.totalRevenue, 0)
    const ord = r.rows.reduce((s: number, x: any) => s + x.orderCount, 0)
    const best = r.rows.reduce((b: any, x: any) => (!b || x.totalRevenue > b.totalRevenue ? x : b), null as any)
    return [
      { label: "Revenue", value: f.money(rev) },
      { label: "Orders", value: f.int(ord) },
      { label: "Trading days", value: f.int(r.rows.length) },
      { label: "Best day", value: best ? `${String(best.reportDate).slice(0, 10)} — ${f.money(best.totalRevenue)}` : "—" },
    ]
  },
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("Revenue and orders by day", "Revenue on the left axis, order count on the right",
      <ResponsiveContainer width="100%" height={320}>
        <LineChart data={r.rows.map((x: any) => ({ ...x, day: String(x.reportDate).slice(0, 10) }))}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
          <XAxis dataKey="day" tick={{ fontSize: 11 }} />
          <YAxis yAxisId="l" tick={{ fontSize: 11 }} />
          <YAxis yAxisId="r" orientation="right" tick={{ fontSize: 11 }} />
          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
          <Legend />
          <Line yAxisId="l" type="monotone" dataKey="totalRevenue" name="Revenue" stroke={ROSE} strokeWidth={2} dot={{ r: 3 }} />
          <Line yAxisId="r" type="monotone" dataKey="orderCount" name="Orders" stroke="#64748b" strokeWidth={2} strokeDasharray="5 5" dot={false} />
        </LineChart>
      </ResponsiveContainer>),
  columns: [
    { key: "d", label: "Date", value: (r) => String(r.reportDate).slice(0, 10) },
    { key: "n", label: "Orders", value: (r, f) => f.int(r.orderCount), numeric: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.totalRevenue), numeric: true },
    { key: "avg", label: "Average ticket", value: (r, f) => f.money(r.avgTicket), numeric: true },
  ],
  tableTitle: "Day by day",
  emptyText: "No completed orders in this period.",
}

const topItems: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getSalesByItem(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Items sold", value: f.int(r.rows.reduce((s: number, x: any) => s + x.quantitySold, 0)) },
    { label: "Revenue", value: f.money(r.rows.reduce((s: number, x: any) => s + x.totalRevenue, 0)) },
    { label: "Distinct items", value: f.int(r.rows.length) },
    { label: "Best seller", value: r.rows[0]?.itemName ?? "—" },
  ],
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("Top ten by revenue", "The items carrying the period",
      <ResponsiveContainer width="100%" height={320}>
        <BarChart data={r.rows.slice(0, 10)} layout="vertical" margin={{ left: 20 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
          <XAxis type="number" tick={{ fontSize: 11 }} />
          <YAxis type="category" dataKey="itemName" width={130} tick={{ fontSize: 11 }} />
          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
          <Bar dataKey="totalRevenue" name="Revenue" fill={ROSE} radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>),
  columns: [
    { key: "i", label: "Item", value: (r) => r.itemName },
    { key: "q", label: "Qty sold", value: (r, f) => f.int(r.quantitySold), numeric: true },
    { key: "o", label: "Orders", value: (r, f) => f.int(r.orderCount), numeric: true, secondary: true },
    { key: "p", label: "Avg price", value: (r, f) => f.money(r.avgPrice), numeric: true, secondary: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.totalRevenue), numeric: true },
  ],
  tableTitle: "All items sold",
  emptyText: "Nothing was sold in this period.",
}

const salesByCategory: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getSalesByCategory(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Revenue", value: f.money(r.rows.reduce((s: number, x: any) => s + x.totalRevenue, 0)) },
    { label: "Items sold", value: f.int(r.rows.reduce((s: number, x: any) => s + x.quantitySold, 0)) },
    { label: "Categories", value: f.int(r.rows.length) },
    { label: "Largest", value: r.rows[0]?.categoryName ?? "—" },
  ],
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("Revenue by category", "Where the money comes from on the menu",
      <ResponsiveContainer width="100%" height={300}>
        <PieChart>
          <Pie data={r.rows} dataKey="totalRevenue" nameKey="categoryName" cx="50%" cy="50%" outerRadius={100}
               label={({ categoryName, percent }: any) => `${categoryName} ${(percent * 100).toFixed(0)}%`} labelLine={false}>
            {r.rows.map((_: any, i: number) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
          </Pie>
          <Tooltip formatter={(v: number) => v.toFixed(2)} />
        </PieChart>
      </ResponsiveContainer>),
  columns: [
    { key: "c", label: "Category", value: (r) => r.categoryName },
    { key: "i", label: "Distinct items", value: (r, f) => f.int(r.itemCount), numeric: true, secondary: true },
    { key: "q", label: "Qty sold", value: (r, f) => f.int(r.quantitySold), numeric: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.totalRevenue), numeric: true },
  ],
  tableTitle: "Categories",
  emptyText: "Nothing was sold in this period.",
}

const peakHours: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getSalesByHour(r.date) }),
  summary: (r, f) => {
    const busiest = r.rows.reduce((b: any, x: any) => (!b || x.orderCount > b.orderCount ? x : b), null as any)
    const richest = r.rows.reduce((b: any, x: any) => (!b || x.totalRevenue > b.totalRevenue ? x : b), null as any)
    return [
      { label: "Orders", value: f.int(r.rows.reduce((s: number, x: any) => s + x.orderCount, 0)) },
      { label: "Revenue", value: f.money(r.rows.reduce((s: number, x: any) => s + x.totalRevenue, 0)) },
      { label: "Busiest hour", value: busiest ? `${String(busiest.hourOfDay).padStart(2, "0")}:00` : "—" },
      { label: "Best hour by revenue", value: richest ? `${String(richest.hourOfDay).padStart(2, "0")}:00` : "—" },
    ]
  },
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("Orders and revenue by hour", "Where to put the staff",
      <ResponsiveContainer width="100%" height={320}>
        <BarChart data={r.rows.map((x: any) => ({ ...x, hour: `${String(x.hourOfDay).padStart(2, "0")}:00` }))}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
          <XAxis dataKey="hour" tick={{ fontSize: 11 }} />
          <YAxis yAxisId="l" tick={{ fontSize: 11 }} />
          <YAxis yAxisId="r" orientation="right" tick={{ fontSize: 11 }} />
          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
          <Legend />
          <Bar yAxisId="l" dataKey="totalRevenue" name="Revenue" fill={ROSE} radius={[4, 4, 0, 0]} />
          <Bar yAxisId="r" dataKey="orderCount" name="Orders" fill={ROSE_LIGHT} radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>),
  columns: [
    { key: "h", label: "Hour", value: (r) => `${String(r.hourOfDay).padStart(2, "0")}:00` },
    { key: "n", label: "Orders", value: (r, f) => f.int(r.orderCount), numeric: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.totalRevenue), numeric: true },
    { key: "avg", label: "Average ticket", value: (r, f) => f.money(r.avgTicket), numeric: true },
  ],
  tableTitle: "Hour by hour",
  emptyText: "No completed orders on this date.",
}

// ===========================================================================
// MENU & FOOD
// ===========================================================================

function classTone(c: string): "good" | "warn" | "bad" | "muted" {
  if (c === "Star") return "good"
  if (c === "Plowhorse" || c === "Puzzle") return "warn"
  if (c === "Dog") return "bad"
  return "muted"
}

const menuEngineering: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getMenuEngineering(r.from, r.to) }),
  summary: (r, f) => {
    const count = (c: string) => r.rows.filter((x: any) => x.menuClass === c).length
    return [
      { label: "Stars (keep)", value: f.int(count("Star")) },
      { label: "Plowhorses (reprice)", value: f.int(count("Plowhorse")) },
      { label: "Puzzles (promote)", value: f.int(count("Puzzle")) },
      { label: "Dogs (consider cutting)", value: f.int(count("Dog")) },
    ]
  },
  panel: () => (
    <Card>
      <CardContent className="py-3 text-sm text-slate-600 space-y-1">
        <p><strong>Star</strong> — sells well and earns well. Protect it; never discount it.</p>
        <p><strong>Plowhorse</strong> — sells well, earns little. Reprice it or re-cost the recipe.</p>
        <p><strong>Puzzle</strong> — earns well, sells little. Promote it or move it up the menu.</p>
        <p><strong>Dog</strong> — neither. A candidate to take off.</p>
        <p className="text-xs text-slate-500 pt-1">
          Items are compared against this period&apos;s own averages, so the classification stays
          meaningful whatever the restaurant sells. An item with no costed recipe is shown as
          <span className="font-medium"> No recipe</span> rather than being guessed at.
        </p>
      </CardContent>
    </Card>
  ),
  columns: [
    { key: "i", label: "Item", value: (r) => r.itemLabel },
    { key: "c", label: "Category", value: (r) => r.categoryLabel, secondary: true },
    { key: "q", label: "Qty sold", value: (r, f) => f.int(r.qtySold), numeric: true },
    { key: "pop", label: "Popularity", value: (r, f) => f.pct(r.popularityPct), numeric: true, secondary: true },
    { key: "cost", label: "Unit cost", value: (r, f) => f.money(r.unitCost), numeric: true, secondary: true },
    { key: "m", label: "Unit margin", value: (r, f) => f.money(r.unitMargin), numeric: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.revenueTotal), numeric: true },
    {
      key: "class", label: "Class", value: (r) => r.menuClass,
      render: (r) => <ToneBadge text={r.menuClass} tone={classTone(r.menuClass)} />,
    },
  ],
  tableTitle: "Every item sold, classified",
  emptyText: "Nothing was sold in this period.",
}

const foodCost: ReportDefinition<any> = {
  load: async () => ({ rows: await getFoodCostReport() }),
  summary: (r, f) => {
    const withCost = r.rows.filter((x: any) => x.recipeCost > 0)
    const avg = withCost.length ? withCost.reduce((s: number, x: any) => s + x.foodCostPercent, 0) / withCost.length : 0
    const worst = withCost.reduce((b: any, x: any) => (!b || x.foodCostPercent > b.foodCostPercent ? x : b), null as any)
    return [
      { label: "Average food cost", value: f.pct(avg) },
      { label: "Items with a recipe", value: `${f.int(withCost.length)} of ${f.int(r.rows.length)}` },
      { label: "Highest food cost", value: worst ? `${worst.itemName} (${f.pct(worst.foodCostPercent)})` : "—" },
      { label: "Over 35%", value: f.int(withCost.filter((x: any) => x.foodCostPercent > 35).length) },
    ]
  },
  columns: [
    { key: "i", label: "Item", value: (r) => r.itemName },
    { key: "c", label: "Category", value: (r) => r.categoryName, secondary: true },
    { key: "p", label: "Selling price", value: (r, f) => f.money(r.sellingPrice), numeric: true },
    { key: "rc", label: "Recipe cost", value: (r, f) => f.money(r.recipeCost), numeric: true },
    {
      key: "fc", label: "Food cost", value: (r, f) => f.pct(r.foodCostPercent), numeric: true,
      render: (r, f) => (
        <span className={r.foodCostPercent > 35 ? "text-red-700 font-semibold"
          : r.foodCostPercent > 30 ? "text-amber-700 font-semibold" : "text-emerald-700"}>
          {f.pct(r.foodCostPercent)}
        </span>
      ),
    },
    { key: "m", label: "Margin", value: (r, f) => f.money(r.margin), numeric: true },
  ],
  tableTitle: "Food cost by menu item",
  tableHint: "Current recipe costs against current prices — a position, not a period.",
  emptyText: "No menu items yet. Add recipes to menu items to see food cost analysis.",
}

const waste: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getWasteDetail(r.from, r.to) }),
  summary: (r, f) => {
    const cost = r.rows.reduce((s: number, x: any) => s + x.costTotal, 0)
    const worst = r.rows.reduce((b: any, x: any) => (!b || x.costTotal > b.costTotal ? x : b), null as any)
    return [
      { label: "Waste cost", value: f.money(cost) },
      { label: "Entries logged", value: f.int(r.rows.reduce((s: number, x: any) => s + x.entryCount, 0)) },
      { label: "Distinct reasons", value: f.int(new Set(r.rows.map((x: any) => x.wasteReason)).size) },
      { label: "Biggest single loss", value: worst ? `${worst.itemLabel} — ${f.money(worst.costTotal)}` : "—" },
    ]
  },
  columns: [
    { key: "r", label: "Reason", value: (r) => r.wasteReason },
    { key: "i", label: "Item", value: (r) => r.itemLabel },
    { key: "q", label: "Quantity", value: (r, f) => `${f.num(r.qtyTotal)} ${r.wasteUnit}`, numeric: true },
    { key: "n", label: "Entries", value: (r, f) => f.int(r.entryCount), numeric: true, secondary: true },
    { key: "c", label: "Cost", value: (r, f) => f.money(r.costTotal), numeric: true },
    { key: "s", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Waste logged",
  emptyText: "No waste was logged in this period.",
}

// ===========================================================================
// OPERATIONS
// ===========================================================================

const kitchenPerformance: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getKitchenPerformance(r.from, r.to) }),
  summary: (r, f) => {
    const made = r.rows.reduce((s: number, x: any) => s + x.itemsMade, 0)
    const over = r.rows.reduce((s: number, x: any) => s + x.overTargetCount, 0)
    const slowest = r.rows.reduce((b: any, x: any) => (!b || x.avgTicketMins > b.avgTicketMins ? x : b), null as any)
    const weighted = made > 0
      ? r.rows.reduce((s: number, x: any) => s + x.avgTicketMins * x.itemsMade, 0) / made
      : 0
    return [
      { label: "Items made", value: f.int(made) },
      { label: "Average ticket time", value: f.mins(weighted) },
      { label: "Over 15 minutes", value: `${f.int(over)} (${made > 0 ? f.pct((over / made) * 100) : "0.0%"})` },
      { label: "Slowest station", value: slowest ? `${slowest.stationName} — ${f.mins(slowest.avgTicketMins)}` : "—" },
    ]
  },
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("Queue against cook time, per station",
      "Queue time is how long the ticket waited before anyone started it; prep time is the cooking itself. They have different fixes.",
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={r.rows}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
          <XAxis dataKey="stationName" tick={{ fontSize: 11 }} />
          <YAxis tick={{ fontSize: 11 }} unit="m" />
          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
          <Legend />
          <Bar dataKey="avgQueueMins" name="Queue (min)" stackId="a" fill={ROSE_LIGHT} />
          <Bar dataKey="avgPrepMins" name="Prep (min)" stackId="a" fill={ROSE} radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>),
  columns: [
    { key: "s", label: "Station", value: (r) => r.stationName },
    { key: "n", label: "Items", value: (r, f) => f.int(r.itemsMade), numeric: true },
    { key: "q", label: "Avg queue", value: (r, f) => f.mins(r.avgQueueMins), numeric: true },
    { key: "p", label: "Avg prep", value: (r, f) => f.mins(r.avgPrepMins), numeric: true },
    {
      key: "t", label: "Avg ticket", value: (r, f) => f.mins(r.avgTicketMins), numeric: true,
      render: (r, f) => (
        <span className={r.avgTicketMins > 15 ? "text-red-700 font-semibold" : "text-emerald-700"}>
          {f.mins(r.avgTicketMins)}
        </span>
      ),
    },
    { key: "mx", label: "Worst ticket", value: (r, f) => f.mins(r.maxTicketMins), numeric: true, secondary: true },
    { key: "o", label: "Over 15m", value: (r, f) => f.int(r.overTargetCount), numeric: true, secondary: true },
    { key: "si", label: "Slowest item", value: (r) => r.slowestItem, secondary: true },
  ],
  tableTitle: "Kitchen stations",
  tableHint: "Only items with both a sent-to-kitchen and a ready timestamp are counted.",
  emptyText: "No timed kitchen tickets in this period. Items are timed when they are sent to the kitchen and bumped on the KDS.",
}

const tableTurnover: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getTableTurnover(r.from, r.to) }),
  summary: (r, f) => {
    const covers = r.rows.reduce((s: number, x: any) => s + x.coversServed, 0)
    const rev = r.rows.reduce((s: number, x: any) => s + x.revenueTotal, 0)
    const best = r.rows.reduce((b: any, x: any) => (!b || x.revenueTotal > b.revenueTotal ? x : b), null as any)
    const orders = r.rows.reduce((s: number, x: any) => s + x.orderCount, 0)
    const dwell = orders > 0
      ? r.rows.reduce((s: number, x: any) => s + x.avgDwellMins * x.orderCount, 0) / orders
      : 0
    return [
      { label: "Dine-in revenue", value: f.money(rev) },
      { label: "Covers served", value: f.int(covers) },
      { label: "Average dwell", value: f.mins(dwell) },
      { label: "Best table", value: best ? `${best.tableLabel} — ${f.money(best.revenueTotal)}` : "—" },
    ]
  },
  columns: [
    { key: "t", label: "Table", value: (r) => r.tableLabel },
    { key: "cap", label: "Seats", value: (r, f) => f.int(r.seatCapacity), numeric: true, secondary: true },
    { key: "n", label: "Orders", value: (r, f) => f.int(r.orderCount), numeric: true },
    { key: "c", label: "Covers", value: (r, f) => f.int(r.coversServed), numeric: true, secondary: true },
    { key: "d", label: "Avg dwell", value: (r, f) => f.mins(r.avgDwellMins), numeric: true },
    { key: "tp", label: "Turns / day", value: (r, f) => f.num(r.turnsPerDay), numeric: true },
    { key: "rpc", label: "Revenue / cover", value: (r, f) => f.money(r.revenuePerCover), numeric: true, secondary: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.revenueTotal), numeric: true },
  ],
  tableTitle: "Dine-in tables",
  tableHint: "Turns per day divides by the days that table actually took an order, not calendar days.",
  emptyText: "No completed dine-in orders in this period.",
}

const waiterPerformance: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getServerPerformance(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Revenue served", value: f.money(r.rows.reduce((s: number, x: any) => s + x.totalRevenue, 0)) },
    { label: "Orders", value: f.int(r.rows.reduce((s: number, x: any) => s + x.orderCount, 0)) },
    { label: "Covers", value: f.int(r.rows.reduce((s: number, x: any) => s + x.totalCovers, 0)) },
    { label: "Waiters", value: f.int(r.rows.length) },
  ],
  columns: [
    { key: "w", label: "Waiter", value: (r) => r.servedBy },
    { key: "n", label: "Orders", value: (r, f) => f.int(r.orderCount), numeric: true },
    { key: "c", label: "Covers", value: (r, f) => f.int(r.totalCovers), numeric: true },
    { key: "a", label: "Average ticket", value: (r, f) => f.money(r.avgTicket), numeric: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.totalRevenue), numeric: true },
  ],
  tableTitle: "Waiters",
  emptyText: "No completed orders in this period.",
}

const tips: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getTipsReport(r.from, r.to) }),
  summary: (r, f) => {
    const t = r.rows.reduce((s: number, x: any) => s + x.tipsTotal, 0)
    const rev = r.rows.reduce((s: number, x: any) => s + x.revenueTotal, 0)
    const best = r.rows.reduce((b: any, x: any) => (!b || x.tipPct > b.tipPct ? x : b), null as any)
    return [
      { label: "Tips collected", value: f.money(t) },
      { label: "On sales of", value: f.money(rev) },
      { label: "Overall tip rate", value: rev > 0 ? f.pct((t / rev) * 100) : f.pct(0) },
      { label: "Best tip rate", value: best && best.tipPct > 0 ? `${best.waiterName} — ${f.pct(best.tipPct)}` : "—" },
    ]
  },
  columns: [
    { key: "w", label: "Waiter", value: (r) => r.waiterName },
    { key: "n", label: "Orders", value: (r, f) => f.int(r.orderCount), numeric: true },
    { key: "tp", label: "Tipped orders", value: (r, f) => f.int(r.tippedOrders), numeric: true, secondary: true },
    { key: "rev", label: "Revenue served", value: (r, f) => f.money(r.revenueTotal), numeric: true, secondary: true },
    { key: "t", label: "Tips", value: (r, f) => f.money(r.tipsTotal), numeric: true },
    { key: "a", label: "Average tip", value: (r, f) => f.money(r.avgTip), numeric: true, secondary: true },
    { key: "pct", label: "Tip rate", value: (r, f) => f.pct(r.tipPct), numeric: true },
  ],
  tableTitle: "Tips by waiter",
  tableHint: "Tip rate is tips against the revenue that waiter served, so it compares fairly across sections.",
  emptyText: "No tips were recorded in this period.",
}

const voids: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getVoidsReport(r.from, r.to) }),
  summary: (r, f) => {
    const lost = r.rows.reduce((s: number, x: any) => s + x.valueLost, 0)
    const n = r.rows.reduce((s: number, x: any) => s + x.voidCount, 0)
    const worst = r.rows.reduce((b: any, x: any) => (!b || x.valueLost > b.valueLost ? x : b), null as any)
    return [
      { label: "Value lost", value: f.money(lost) },
      { label: "Orders affected", value: f.int(n) },
      { label: "Covers lost", value: f.int(r.rows.reduce((s: number, x: any) => s + x.coversLost, 0)) },
      { label: "Biggest reason", value: worst ? `${worst.voidReason} — ${f.money(worst.valueLost)}` : "—" },
    ]
  },
  columns: [
    { key: "k", label: "Kind", value: (r) => r.voidKind,
      render: (r) => <ToneBadge text={r.voidKind} tone={r.voidKind === "Refunded" ? "warn" : "bad"} /> },
    { key: "r", label: "Reason", value: (r) => r.voidReason },
    { key: "n", label: "Orders", value: (r, f) => f.int(r.voidCount), numeric: true },
    { key: "c", label: "Covers", value: (r, f) => f.int(r.coversLost), numeric: true, secondary: true },
    { key: "v", label: "Value lost", value: (r, f) => f.money(r.valueLost), numeric: true },
    { key: "s", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Cancellations and refunds",
  emptyText: "Nothing was cancelled or refunded in this period.",
}

function stockTone(s: string): "good" | "warn" | "bad" | "muted" {
  if (s === "Out of stock") return "bad"
  if (s === "Reorder now") return "bad"
  if (s === "Below par") return "warn"
  return "good"
}

const stockOnHand: ReportDefinition<any> = {
  load: async () => ({ rows: await getStockOnHand() }),
  summary: (r, f) => [
    { label: "Stock value", value: f.money(r.rows.reduce((s: number, x: any) => s + x.stockValue, 0)) },
    { label: "Out of stock", value: f.int(r.rows.filter((x: any) => x.stockStatus === "Out of stock").length) },
    { label: "Reorder now", value: f.int(r.rows.filter((x: any) => x.stockStatus === "Reorder now").length) },
    { label: "Ingredients tracked", value: f.int(r.rows.length) },
  ],
  columns: [
    { key: "i", label: "Ingredient", value: (r) => r.ingredientName },
    { key: "c", label: "Category", value: (r) => r.ingredientCategory, secondary: true },
    { key: "oh", label: "On hand", value: (r, f) => `${f.num(r.onHand, 2)} ${r.stockUnit}`, numeric: true },
    { key: "par", label: "Par", value: (r, f) => f.num(r.parLevel, 2), numeric: true, secondary: true },
    { key: "rp", label: "Reorder at", value: (r, f) => f.num(r.reorderPoint, 2), numeric: true, secondary: true },
    { key: "v", label: "Value", value: (r, f) => f.money(r.stockValue), numeric: true },
    { key: "sup", label: "Supplier", value: (r) => r.supplierLabel, secondary: true },
    {
      key: "st", label: "Status", value: (r) => r.stockStatus,
      render: (r) => <ToneBadge text={r.stockStatus} tone={stockTone(r.stockStatus)} />,
    },
  ],
  tableTitle: "Ingredients, worst first",
  tableHint: "Sorted so anything needing action is at the top.",
  emptyText: "No active ingredients. Add ingredients under Inventory to track stock.",
}

// ===========================================================================
// GUESTS & CHANNELS
// ===========================================================================

const customerRetention: ReportDefinition<MetricRow, CustomerRetentionReport> = {
  load: async (r) => {
    const s = await getCustomerRetention(r.from, r.to)
    return { rows: [], meta: s }
  },
  summary: (r, f) => {
    const s = r.meta
    if (!s) return []
    return [
      { label: "Identified guests", value: f.int(s.identifiedCustomers) },
      { label: "Returning", value: f.int(s.returningCustomers) },
      { label: "Repeat rate", value: f.pct(s.repeatRatePct) },
      { label: "Average spend", value: f.money(s.avgSpend) },
    ]
  },
  columns: METRIC_COLUMNS,
  tableTitle: "Retention",
  tableHint: "Walk-in orders carry no customer record, so they are counted separately rather than dragging the ratios down.",
  emptyText: "No completed orders in this period.",
}

const feedback: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getFeedbackReport(r.from, r.to) }),
  summary: (r, f) => {
    const n = r.rows.reduce((s: number, x: any) => s + x.responseCount, 0)
    const weighted = n > 0 ? r.rows.reduce((s: number, x: any) => s + x.avgOverall * x.responseCount, 0) / n : 0
    const prom = r.rows.reduce((s: number, x: any) => s + x.promoterCount, 0)
    const det = r.rows.reduce((s: number, x: any) => s + x.detractorCount, 0)
    return [
      { label: "Responses", value: f.int(n) },
      { label: "Average rating", value: n > 0 ? `${f.num(weighted, 2)} / 5` : "—" },
      { label: "4 stars and up", value: `${f.int(prom)}${n > 0 ? ` (${f.pct((prom / n) * 100)})` : ""}` },
      { label: "2 stars and under", value: `${f.int(det)}${n > 0 ? ` (${f.pct((det / n) * 100)})` : ""}` },
    ]
  },
  columns: [
    { key: "s", label: "Source", value: (r) => r.sourceLabel },
    { key: "n", label: "Responses", value: (r, f) => f.int(r.responseCount), numeric: true },
    { key: "o", label: "Overall", value: (r, f) => f.num(r.avgOverall, 2), numeric: true },
    { key: "f", label: "Food", value: (r, f) => f.num(r.avgFood, 2), numeric: true, secondary: true },
    { key: "sv", label: "Service", value: (r, f) => f.num(r.avgService, 2), numeric: true, secondary: true },
    { key: "a", label: "Ambience", value: (r, f) => f.num(r.avgAmbience, 2), numeric: true, secondary: true },
    { key: "p", label: "4+", value: (r, f) => f.int(r.promoterCount), numeric: true, secondary: true },
    { key: "d", label: "2-", value: (r, f) => f.int(r.detractorCount), numeric: true, secondary: true },
    { key: "u", label: "Unanswered", value: (r, f) => f.int(r.unansweredCount), numeric: true },
  ],
  tableTitle: "Ratings by source",
  tableHint: "QR is what guests left themselves from the table; InStore is what staff logged.",
  emptyText: "No feedback was left in this period.",
}

const deliveryPerformance: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getDeliveryPerformance(r.from, r.to) }),
  summary: (r, f) => {
    const n = r.rows.reduce((s: number, x: any) => s + x.assignmentCount, 0)
    const measured = r.rows.reduce((s: number, x: any) => s + x.measuredCount, 0)
    const onTime = r.rows.reduce((s: number, x: any) => s + (x.onTimePct / 100) * x.measuredCount, 0)
    const failed = r.rows.reduce((s: number, x: any) => s + x.failedCount, 0)
    return [
      { label: "Deliveries", value: f.int(n) },
      { label: "On time", value: measured > 0 ? `${f.pct((onTime / measured) * 100)} of ${f.int(measured)}` : "not measured" },
      { label: "Failed", value: f.int(failed) },
      { label: "Delivery fees", value: f.money(r.rows.reduce((s: number, x: any) => s + x.feesTotal, 0)) },
    ]
  },
  columns: [
    { key: "d", label: "Driver", value: (r) => r.driverLabel },
    { key: "n", label: "Assigned", value: (r, f) => f.int(r.assignmentCount), numeric: true },
    { key: "ok", label: "Delivered", value: (r, f) => f.int(r.deliveredCount), numeric: true },
    { key: "x", label: "Failed", value: (r, f) => f.int(r.failedCount), numeric: true, secondary: true },
    { key: "act", label: "Avg actual", value: (r, f) => f.mins(r.avgActualMins), numeric: true },
    { key: "est", label: "Avg promised", value: (r, f) => f.mins(r.avgEstimatedMins), numeric: true, secondary: true },
    {
      key: "ot", label: "On time",
      // The sample size travels with the percentage. A driver with one measured
      // run at 100% is not better than one at 92% over fifty.
      value: (r, f) => (r.measuredCount > 0 ? `${f.pct(r.onTimePct)} of ${f.int(r.measuredCount)}` : "not measured"),
      numeric: true,
    },
    { key: "km", label: "Distance", value: (r, f) => `${f.num(r.totalDistanceKm, 1)} km`, numeric: true, secondary: true },
    { key: "rt", label: "Rating", value: (r, f) => (r.avgRating > 0 ? f.num(r.avgRating, 2) : "—"), numeric: true, secondary: true },
  ],
  tableTitle: "Drivers",
  tableHint: "On-time counts only deliveries that have both a promised and an actual time.",
  emptyText: "No delivery assignments in this period.",
}

const channel: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getChannelReport(r.from, r.to) }),
  summary: (r, f) => {
    const gross = r.rows.reduce((s: number, x: any) => s + x.grossTotal, 0)
    const comm = r.rows.reduce((s: number, x: any) => s + x.commissionTotal, 0)
    const fee = r.rows.reduce((s: number, x: any) => s + x.platformFeeTotal, 0)
    return [
      { label: "Gross through platforms", value: f.money(gross) },
      { label: "Commission kept", value: f.money(comm) },
      { label: "Platform fees", value: f.money(fee) },
      { label: "You received", value: f.money(r.rows.reduce((s: number, x: any) => s + x.netTotal, 0)) },
    ]
  },
  columns: [
    { key: "p", label: "Platform", value: (r) => r.platformLabel },
    { key: "n", label: "Orders", value: (r, f) => f.int(r.orderCount), numeric: true },
    { key: "rj", label: "Rejected", value: (r, f) => f.int(r.rejectedCount), numeric: true, secondary: true },
    { key: "g", label: "Gross", value: (r, f) => f.money(r.grossTotal), numeric: true },
    { key: "c", label: "Commission", value: (r, f) => f.money(r.commissionTotal), numeric: true },
    { key: "pf", label: "Platform fee", value: (r, f) => f.money(r.platformFeeTotal), numeric: true, secondary: true },
    {
      key: "cp", label: "Commission rate", value: (r, f) => f.pct(r.commissionPct), numeric: true,
      render: (r, f) => (
        <span className={r.commissionPct > 25 ? "text-red-700 font-semibold" : r.commissionPct > 15 ? "text-amber-700" : ""}>
          {f.pct(r.commissionPct)}
        </span>
      ),
    },
    { key: "net", label: "Net to you", value: (r, f) => f.money(r.netTotal), numeric: true },
  ],
  tableTitle: "Third-party platforms",
  emptyText: "No third-party platform orders in this period.",
}

const events: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getEventsReport(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Contracted value", value: f.money(r.rows.reduce((s: number, x: any) => s + x.contractedTotal, 0)) },
    { label: "Deposits received", value: f.money(r.rows.reduce((s: number, x: any) => s + x.depositPaidTotal, 0)) },
    { label: "Balance outstanding", value: f.money(r.rows.reduce((s: number, x: any) => s + x.balanceTotal, 0)) },
    { label: "Guests booked", value: f.int(r.rows.reduce((s: number, x: any) => s + x.guestTotal, 0)) },
  ],
  columns: [
    { key: "s", label: "Status", value: (r) => r.eventStatus },
    { key: "n", label: "Events", value: (r, f) => f.int(r.eventCount), numeric: true },
    { key: "g", label: "Guests", value: (r, f) => f.int(r.guestTotal), numeric: true },
    { key: "c", label: "Contracted", value: (r, f) => f.money(r.contractedTotal), numeric: true },
    { key: "dp", label: "Deposit paid", value: (r, f) => f.money(r.depositPaidTotal), numeric: true, secondary: true },
    { key: "b", label: "Balance due", value: (r, f) => f.money(r.balanceTotal), numeric: true },
    { key: "ph", label: "Per head", value: (r, f) => f.money(r.avgPerHead), numeric: true, secondary: true },
  ],
  tableTitle: "Events by status",
  emptyText: "No events fall in this period.",
}

// ===========================================================================
// The registry the router reads.
// ===========================================================================

export const REPORT_REGISTRY: Record<string, ReportDefinition<any, any>> = {
  "pnl": pnl,
  "sales-summary": salesSummary,
  "payment-methods": paymentMethods,
  "expenses": expenses,
  "discounts": discounts,
  "daily-sales": dailySales,
  "revenue-trend": revenueTrend,
  "top-items": topItems,
  "sales-by-category": salesByCategory,
  "peak-hours": peakHours,
  "menu-engineering": menuEngineering,
  "food-cost": foodCost,
  "waste": waste,
  "kitchen-performance": kitchenPerformance,
  "table-turnover": tableTurnover,
  "waiter-performance": waiterPerformance,
  "tips": tips,
  "voids": voids,
  "stock-on-hand": stockOnHand,
  "customer-retention": customerRetention,
  "feedback": feedback,
  "delivery-performance": deliveryPerformance,
  "channel": channel,
  "events": events,
}

/**
 * The three reports whose answer is a single object rather than a list build
 * their table rows here, after the fetch, because the rows are just a
 * presentation of the same object the KPI tiles use. Doing it in `load` would
 * have meant formatting money before the currency was known.
 */
export function deriveMetricRows(slug: string, meta: any, fmt: Fmt): MetricRow[] {
  if (!meta) return []
  if (slug === "sales-summary") {
    const s = meta as SalesSummaryReport
    if (s.totalOrders === 0) return []
    return [
      { metric: "Gross revenue", value: fmt.money(s.grossRevenue) },
      { metric: "Net revenue (excl. tax and service charge)", value: fmt.money(s.netRevenue) },
      { metric: "Discounts given", value: fmt.money(s.discountTotal) },
      { metric: "Tax collected", value: fmt.money(s.taxTotal) },
      { metric: "Service charge collected", value: fmt.money(s.serviceChargeTotal) },
      { metric: "Tips collected", value: fmt.money(s.tipsTotal) },
      { metric: "Total orders", value: fmt.int(s.totalOrders) },
      { metric: "Completed orders", value: fmt.int(s.completedOrders) },
      { metric: "Cancelled orders", value: fmt.int(s.cancelledOrders) },
      { metric: "Average ticket", value: fmt.money(s.avgTicket) },
      { metric: "Covers", value: fmt.int(s.coversTotal) },
      { metric: "Revenue per cover", value: fmt.money(s.revenuePerCover) },
      { metric: "Dine-in orders", value: `${fmt.int(s.dineInCount)} — ${fmt.money(s.dineInRevenue)}` },
      { metric: "Takeaway orders", value: `${fmt.int(s.takeawayCount)} — ${fmt.money(s.takeawayRevenue)}` },
      { metric: "Delivery orders", value: `${fmt.int(s.deliveryCount)} — ${fmt.money(s.deliveryRevenue)}` },
      { metric: "Trading days", value: fmt.int(s.activeDays) },
      { metric: "Average daily revenue", value: fmt.money(s.avgDailyRevenue) },
    ]
  }
  if (slug === "daily-sales") {
    const d = meta as DailySalesReport
    if (d.totalOrders === 0) return []
    return [
      { metric: "Total revenue", value: fmt.money(d.totalRevenue) },
      { metric: "Net revenue", value: fmt.money(d.netRevenue) },
      { metric: "Discounts", value: fmt.money(d.totalDiscount) },
      { metric: "Tax", value: fmt.money(d.totalTax) },
      { metric: "Service charge", value: fmt.money(d.totalServiceCharge) },
      { metric: "Total orders", value: fmt.int(d.totalOrders) },
      { metric: "Completed orders", value: fmt.int(d.completedOrders) },
      { metric: "Cancelled orders", value: fmt.int(d.cancelledOrders) },
      { metric: "Average ticket", value: fmt.money(d.avgTicket) },
      { metric: "Covers", value: fmt.int(d.totalCovers) },
      { metric: "Dine-in", value: `${fmt.int(d.dineInCount)} — ${fmt.money(d.dineInRevenue)}` },
      { metric: "Takeaway", value: `${fmt.int(d.takeawayCount)} — ${fmt.money(d.takeawayRevenue)}` },
      { metric: "Delivery", value: `${fmt.int(d.deliveryCount)} — ${fmt.money(d.deliveryRevenue)}` },
      { metric: "Cash", value: fmt.money(d.cashAmount) },
      { metric: "Card", value: fmt.money(d.cardAmount) },
      { metric: "Mobile money", value: fmt.money(d.mobileAmount) },
      { metric: "Other", value: fmt.money(d.otherAmount) },
    ]
  }
  if (slug === "customer-retention") {
    const c = meta as CustomerRetentionReport
    return [
      { metric: "Identified guests in period", value: fmt.int(c.identifiedCustomers) },
      { metric: "Walk-in orders (no guest record)", value: fmt.int(c.walkinOrders) },
      { metric: "First-time guests", value: fmt.int(c.newCustomers) },
      { metric: "Returning guests", value: fmt.int(c.returningCustomers) },
      { metric: "Repeat rate", value: fmt.pct(c.repeatRatePct) },
      { metric: "Average visits in period", value: fmt.num(c.avgVisits) },
      { metric: "Average spend in period", value: fmt.money(c.avgSpend) },
      { metric: "Highest single-guest spend", value: fmt.money(c.topSpend) },
      { metric: "Guests marked VIP (all time)", value: fmt.int(c.vipCustomers) },
      { metric: "Guests marked Lapsed (all time)", value: fmt.int(c.lapsedCustomers) },
    ]
  }
  return []
}

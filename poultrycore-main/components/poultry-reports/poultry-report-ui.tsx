"use client"

// =============================================================================
// Shared UI building blocks for the Advanced Poultry Reports. Poultry-specific,
// additive, and composed from the existing shadcn primitives in components/ui.
// =============================================================================

import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { ReportDataTable, type ReportTableColumn, type ReportTableRow } from "@/components/poultry-reports/report-data-table"
import { AlertCircle, Loader2, Inbox, Download, Printer, FileSpreadsheet, Mail } from "lucide-react"
import type { Accent, BreakdownGroup, ColumnDef, FmtCtx } from "@/lib/reports/poultry-report-defs"

// --- Status badge ------------------------------------------------------------
const GOOD = ["good", "profit", "paid", "complete", "in stock", "ok", "settled", "balanced", "active", "completed"]
const WARN = ["watch", "owing", "incomplete", "low", "minor variance", "not itemised", "n/a"]
const BAD = ["critical", "loss", "unpaid", "high", "out of stock", "check count", "empty", "closed", "overdue"]

export function PoultryReportStatusBadge({ status }: { status: string }) {
  const s = (status || "").toLowerCase()
  let cls = "bg-slate-100 text-slate-700 border-slate-200"
  if (GOOD.includes(s)) cls = "bg-emerald-100 text-emerald-800 border-emerald-200"
  else if (BAD.includes(s)) cls = "bg-rose-100 text-rose-800 border-rose-200"
  else if (WARN.includes(s)) cls = "bg-amber-100 text-amber-800 border-amber-200"
  return <Badge variant="outline" className={`font-medium ${cls}`}>{status || "—"}</Badge>
}

// --- States ------------------------------------------------------------------
export function PoultryReportLoadingState() {
  return (
    <div className="space-y-4 animate-pulse" aria-busy="true">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {Array.from({ length: 4 }).map((_, i) => <div key={i} className="h-20 rounded-lg bg-slate-100" />)}
      </div>
      <div className="space-y-2">
        <div className="h-9 rounded bg-slate-100" />
        {Array.from({ length: 6 }).map((_, i) => <div key={i} className="h-7 rounded bg-slate-50" />)}
      </div>
      <div className="flex items-center gap-2 text-slate-400 text-sm">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading report…
      </div>
    </div>
  )
}

export function PoultryReportEmptyState({ message }: { message?: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center text-slate-500">
      <Inbox className="h-10 w-10 mb-3 text-slate-300" />
      <p className="font-medium text-slate-700">No data for this selection</p>
      <p className="text-sm mt-1">{message ?? "Try a different date range or clear the filters."}</p>
    </div>
  )
}

export function PoultryReportErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="rounded-md bg-rose-50 border border-rose-200 px-4 py-3 text-sm text-rose-800 flex items-start gap-2">
      <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
      <div className="min-w-0 break-words flex-1">{message}</div>
      {onRetry && (
        <button onClick={onRetry} className="text-rose-600 hover:text-rose-800 text-xs font-medium ml-auto shrink-0">
          Retry
        </button>
      )}
    </div>
  )
}

// --- Summary cards -----------------------------------------------------------
export interface SummaryCard { label: string; value: string; accent?: Accent }

export function PoultryReportSummaryCards({ cards }: { cards: SummaryCard[] }) {
  if (!cards.length) return null
  return (
    <div className="mb-4 grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3 print:gap-2">
      {cards.map((card) => {
        const valueCls =
          card.accent === "green" ? "text-emerald-700" :
          card.accent === "rose" ? "text-rose-700" :
          card.accent === "indigo" ? "text-indigo-700" : "text-slate-900"
        const barCls =
          card.accent === "green" ? "bg-emerald-500" :
          card.accent === "rose" ? "bg-rose-500" :
          card.accent === "indigo" ? "bg-indigo-500" : "bg-amber-400"
        return (
          <Card key={card.label} className="relative overflow-hidden border-slate-200 shadow-sm print:border print:shadow-none">
            <div className={`absolute inset-y-0 left-0 w-1 ${barCls}`} />
            <CardContent className="p-4 pl-5 print:p-3">
              <div className="text-xs uppercase tracking-wider text-slate-500">{card.label}</div>
              <div className={`text-lg sm:text-xl font-semibold tabular-nums mt-1 break-words ${valueCls}`}>{card.value}</div>
            </CardContent>
          </Card>
        )
      })}
    </div>
  )
}

// --- Detail table ------------------------------------------------------------
// Delegates to the shared ReportDataTable so the 20 advanced reports get
// click-to-sort headers + pagination. Cells stay formatted via the column
// `cell()` fns; the raw formatted string doubles as the sort value.
export function PoultryReportTable({
  columns, rows, ctx,
}: { columns: ColumnDef[]; rows: any[]; ctx: FmtCtx }) {
  const cols: ReportTableColumn[] = columns.map((c) => ({
    header: c.header,
    align: c.align === "right" ? "right" : "left",
  }))
  const tableRows: ReportTableRow[] = rows.map((row) => {
    const values = columns.map((c) => c.cell(row, ctx))
    return {
      display: values.map((value, i) => (columns[i].badge ? <PoultryReportStatusBadge status={value} /> : value)),
      sort: values,
    }
  })
  return <ReportDataTable columns={cols} rows={tableRows} empty="No rows for this selection." />
}

// --- Breakdown section (rendered below the detail table) ---------------------
// Grouped horizontal bars — e.g. "Revenue breakdown" / "Expense breakdown" —
// showing each category's amount and share of its group total.
export function PoultryReportBreakdown({
  groups, summary, ctx,
}: { groups: BreakdownGroup[]; summary: any; ctx: FmtCtx }) {
  if (!groups.length) return null
  return (
    <div className="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-4 print:grid-cols-2">
      {groups.map((g) => {
        const barCls = g.accent === "green" ? "bg-emerald-500" : "bg-rose-500"
        return (
          <div key={g.title} className="rounded-lg border border-slate-200 p-4 print:border">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-slate-800">{g.title}</h3>
              {g.total && <span className="text-sm font-semibold tabular-nums text-slate-900">{g.total(summary, ctx)}</span>}
            </div>
            <div className="space-y-3">
              {g.items.map((it) => {
                const pct = it.percent(summary)
                const width = pct == null ? 0 : Math.min(100, Math.max(0, pct))
                return (
                  <div key={it.label}>
                    <div className="flex items-center justify-between text-xs mb-1">
                      <span className="text-slate-600">{it.label}</span>
                      <span className="tabular-nums text-slate-800">
                        {it.value(summary, ctx)}
                        {pct != null && <span className="text-slate-400 ml-1">({pct.toFixed(1)}%)</span>}
                      </span>
                    </div>
                    <div className="h-2 rounded-full bg-slate-100 overflow-hidden">
                      <div className={`h-full ${barCls} rounded-full`} style={{ width: `${width}%` }} />
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        )
      })}
    </div>
  )
}

// --- Export buttons ----------------------------------------------------------
export function PoultryReportExportButtons({
  onCsv, onPdf, onEmail, busy, disabled,
}: { onCsv: () => void; onPdf: () => void; onEmail: () => void; busy?: boolean; disabled?: boolean }) {
  return (
    <div className="flex items-center gap-2 flex-wrap print:hidden">
      <Button size="sm" variant="outline" onClick={onCsv} disabled={disabled} className="gap-1" title="Download CSV">
        <FileSpreadsheet className="h-4 w-4" /> CSV
      </Button>
      <Button size="sm" variant="outline" onClick={onEmail} disabled={disabled} className="gap-1" title="Email this report as a PDF">
        <Mail className="h-4 w-4" /> Email
      </Button>
      <Button size="sm" onClick={onPdf} disabled={disabled || busy} className="gap-1" title="Download PDF">
        {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Printer className="h-4 w-4" />} PDF
      </Button>
    </div>
  )
}

export { Download }

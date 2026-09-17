"use client"

/**
 * The table primitive every Restaurant report renders through, plus the column
 * contract that makes the exports trustworthy.
 *
 * THE ONE IDEA HERE
 * A column defines its cell ONCE, in `value`. The on-screen table, the PDF and
 * the CSV are all built from that same function, so they cannot drift apart. A
 * column may additionally supply `render` for something richer on screen -- a
 * coloured badge, a warning tint -- but that is presentation only and never
 * feeds an export. Nobody can "fix" a number in the table and leave the
 * downloaded copy saying something else.
 *
 * Tables are also responsive by construction: on a phone each row becomes a
 * stacked label/value card. The plan.md entry for 2026-09-16 records the food
 * cost table being fixed for exactly this by hand; doing it in the primitive
 * means the next twenty reports never need that fix.
 */

import type { ReactNode } from "react"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { FileX2 } from "lucide-react"
import type { ReportRange, ReportExport } from "@/components/reports/module-report-shell"

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

/**
 * Formatters handed to every report. Currency comes from the restaurant
 * profile, so a Ghanaian restaurant reads GHS and nobody has to guess what a
 * bare "1,240.00" is denominated in -- the old page printed exactly that.
 */
export interface Fmt {
  currency: string
  /** 1240.5 -> "GHS 1,240.50" */
  money: (n: number | null | undefined) => string
  /** 1240.5 -> "1,240.50", for table cells where the column header says the unit. */
  num: (n: number | null | undefined, dp?: number) => string
  /** 12.5 -> "12.5%" */
  pct: (n: number | null | undefined, dp?: number) => string
  /** 42.4 -> "42m", 95 -> "1h 35m" */
  mins: (n: number | null | undefined) => string
  int: (n: number | null | undefined) => string
}

export function makeFmt(currency: string): Fmt {
  const group = (n: number, dp: number) =>
    n.toLocaleString(undefined, { minimumFractionDigits: dp, maximumFractionDigits: dp })
  return {
    currency,
    money: (n) => `${currency} ${group(Number(n ?? 0), 2)}`,
    num: (n, dp = 2) => group(Number(n ?? 0), dp),
    pct: (n, dp = 1) => `${group(Number(n ?? 0), dp)}%`,
    mins: (n) => {
      const v = Math.round(Number(n ?? 0))
      if (v < 60) return `${v}m`
      return `${Math.floor(v / 60)}h ${v % 60}m`
    },
    int: (n) => group(Number(n ?? 0), 0),
  }
}

// ---------------------------------------------------------------------------
// Columns and report definitions
// ---------------------------------------------------------------------------

export interface ColumnDef<T> {
  key: string
  label: string
  /** The cell's text. Screen, PDF and CSV all come from this. */
  value: (row: T, fmt: Fmt) => string
  /** Screen-only enrichment. Falls back to `value` when absent. */
  render?: (row: T, fmt: Fmt) => ReactNode
  /** Right-align on screen. Numbers read better that way. */
  numeric?: boolean
  /** Dropped from the phone layout when the column is secondary detail. */
  secondary?: boolean
}

/** What a report's loader returns: its rows, plus anything the panels need. */
export interface LoadResult<T, M = unknown> {
  rows: T[]
  meta?: M
}

export interface ReportDefinition<T = any, M = any> {
  load: (range: ReportRange) => Promise<LoadResult<T, M>>
  columns: ColumnDef<T>[]
  /** KPI tiles above the table. Also reproduced in the PDF and the CSV. */
  summary?: (r: LoadResult<T, M>, fmt: Fmt) => { label: string; value: string }[]
  /** A chart or extra panel between the tiles and the table. */
  panel?: (r: LoadResult<T, M>, fmt: Fmt) => ReactNode
  /** Heading for the table card. */
  tableTitle?: string
  tableHint?: string
  emptyText?: string
}

/**
 * Turn a loaded report into the flat table the shell exports. Derived from the
 * same columns the screen uses, which is the whole point.
 */
export function buildExport<T, M>(
  def: ReportDefinition<T, M>,
  result: LoadResult<T, M>,
  fmt: Fmt,
): ReportExport {
  return {
    headers: def.columns.map((c) => c.label),
    rows: result.rows.map((row) => def.columns.map((c) => c.value(row, fmt))),
    summaryCards: def.summary?.(result, fmt),
  }
}

// ---------------------------------------------------------------------------
// Presentation
// ---------------------------------------------------------------------------

export function StatGrid({ cards }: { cards: { label: string; value: string; tone?: string }[] }) {
  if (!cards.length) return null
  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
      {cards.map((c, i) => (
        <Card key={c.label} className={`border-l-4 ${c.tone ?? TONES[i % TONES.length]}`}>
          <CardContent className="py-3 px-4">
            <div className="text-lg sm:text-2xl font-bold text-slate-900 tabular-nums break-words">{c.value}</div>
            <div className="text-xs text-slate-500 mt-0.5">{c.label}</div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

const TONES = ["border-l-emerald-500", "border-l-rose-500", "border-l-indigo-500", "border-l-amber-500"]

export function ReportEmpty({ text }: { text: string }) {
  return (
    <div className="py-12 text-center">
      <FileX2 className="h-8 w-8 mx-auto text-slate-300" />
      <p className="mt-2 text-sm text-slate-500 max-w-md mx-auto">{text}</p>
    </div>
  )
}

export function ReportTable<T, M>({
  def, result, fmt,
}: { def: ReportDefinition<T, M>; result: LoadResult<T, M>; fmt: Fmt }) {
  const cols = def.columns
  const rows = result.rows

  return (
    <Card>
      {(def.tableTitle || def.tableHint) && (
        <CardHeader className="pb-2">
          {def.tableTitle && <CardTitle className="text-base">{def.tableTitle}</CardTitle>}
          {def.tableHint && <CardDescription>{def.tableHint}</CardDescription>}
        </CardHeader>
      )}
      <CardContent className={def.tableTitle ? "" : "pt-6"}>
        {rows.length === 0 ? (
          <ReportEmpty text={def.emptyText ?? "No data for this period."} />
        ) : (
          <>
            {/* Desktop: a real table. */}
            <div className="hidden md:block overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    {cols.map((c) => (
                      <th
                        key={c.key}
                        className={`py-2 px-2 text-xs font-semibold uppercase tracking-wide text-slate-500 ${
                          c.numeric ? "text-right" : "text-left"
                        }`}
                      >
                        {c.label}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row, i) => (
                    <tr key={i} className="border-b last:border-0 hover:bg-slate-50">
                      {cols.map((c) => (
                        <td
                          key={c.key}
                          className={`py-2 px-2 ${c.numeric ? "text-right tabular-nums" : ""}`}
                        >
                          {c.render ? c.render(row, fmt) : c.value(row, fmt)}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Phone: one card per row, first column as the heading. Secondary
                columns are dropped rather than wrapped into illegibility.
                Every cell is min-w-0 + break-words: a money value carrying a
                currency code ("GHS 1,234,567.00") is wider than half a 360px
                screen, and without these it pushes the card -- and with it the
                page -- into a horizontal scroll. */}
            <div className="md:hidden space-y-2">
              {rows.map((row, i) => (
                <div key={i} className="rounded-lg border p-3">
                  <div className="font-medium text-sm mb-1.5 break-words">
                    {cols[0].render ? cols[0].render(row, fmt) : cols[0].value(row, fmt)}
                  </div>
                  <div className="grid grid-cols-2 gap-x-3 gap-y-1">
                    {cols.slice(1).filter((c) => !c.secondary).map((c) => (
                      <div key={c.key} className="flex justify-between gap-1.5 text-xs min-w-0">
                        <span className="text-slate-500 shrink-0">{c.label}</span>
                        <span className="font-medium tabular-nums text-right min-w-0 break-words">
                          {c.render ? c.render(row, fmt) : c.value(row, fmt)}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}

/** Colour-coded pill used by the classification and status columns. */
export function ToneBadge({ text, tone }: { text: string; tone: "good" | "warn" | "bad" | "muted" }) {
  const cls = {
    good: "bg-emerald-50 text-emerald-700 border-emerald-200",
    warn: "bg-amber-50 text-amber-700 border-amber-200",
    bad: "bg-red-50 text-red-700 border-red-200",
    muted: "bg-slate-50 text-slate-600 border-slate-200",
  }[tone]
  return <Badge variant="outline" className={`${cls} font-medium`}>{text}</Badge>
}

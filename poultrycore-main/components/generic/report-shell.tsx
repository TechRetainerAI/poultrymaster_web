"use client"

// The frame every Generic report page draws inside: sidebar, header, back
// link, title, and the date-range filter.
//
// Written for the seven reports migration 250 adds rather than retro-fitted to
// the six that already existed -- rewriting working pages to adopt a shell is
// churn, and the shell would have had to grow options for each of their
// differences. New pages share it; old pages keep what they have.

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ArrowLeft, Loader2 } from "lucide-react"
import { useAuthStore as useAuthStoreShell } from "@/lib/store/auth-store"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod } from "@/lib/date-ranges"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"

export interface DateRange {
  fromDate: string
  toDate: string
}

/** This month, which is what a report opens on unless it says otherwise. */
export function currentMonthRange(): DateRange {
  const now = new Date()
  return {
    fromDate: new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10),
    toDate: now.toISOString().slice(0, 10),
  }
}

/**
 * The last `months` months, starting at a month BOUNDARY. Month-grained
 * reports open on this: starting "a year ago today" would cut the first month
 * in half and make the first bar of every trend meaningless.
 */
export function trailingMonthsRange(months = 12): DateRange {
  const now = new Date()
  return {
    fromDate: new Date(now.getFullYear(), now.getMonth() - (months - 1), 1).toISOString().slice(0, 10),
    toDate: now.toISOString().slice(0, 10),
  }
}

export function GenericReportShell({
  title,
  description,
  icon: Icon,
  range,
  onRangeChange,
  onRun,
  loading,
  extraFilters,
  exportButtons,
  children,
}: {
  title: string
  description?: string
  icon: any
  range: DateRange
  onRangeChange: (r: DateRange) => void
  onRun: () => void
  loading: boolean
  /** Report-specific controls that sit next to the dates. */
  extraFilters?: React.ReactNode
  /** CSV / Email / PDF export buttons — rendered beside the title. */
  exportButtons?: React.ReactNode
  children: React.ReactNode
}) {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center justify-between flex-wrap gap-2 mb-2">
            <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700">
              <ArrowLeft className="h-3 w-3 mr-1" /> Reports
            </Link>
            {exportButtons}
          </div>

          <Card className="mb-4 border-t-4 border-t-amber-500">
            <CardContent className="pt-6">
              <div className="text-xs font-bold uppercase tracking-wider text-amber-600 mb-1">{useAuthStoreShell.getState().activeFarmName ?? "Company"}</div>
              <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
                <Icon className="h-6 w-6 text-emerald-600" /> {title}
              </h1>
              {description && <p className="text-sm text-slate-500 mt-1">{description}</p>}
              <div className="flex flex-wrap gap-x-8 gap-y-1 mt-3 text-sm text-slate-600">
                <div><span className="text-slate-400">Period:</span> {range.fromDate} → {range.toDate}</div>
                <div><span className="text-slate-400">Currency:</span> GHS (GHC)</div>
              </div>

              <div className="flex flex-wrap items-end gap-3 mt-4 pt-4 border-t border-slate-100">
                <PeriodSelect
                  value={rangeToPeriod(range.fromDate, range.toDate)}
                  onChange={(_p, rg) => { if (rg) onRangeChange({ fromDate: rg.from, toDate: rg.to }) }}
                />
                <div>
                  <Label className="text-xs text-slate-500">From</Label>
                  <Input type="date" value={range.fromDate}
                         onChange={(e) => onRangeChange({ ...range, fromDate: e.target.value })} />
                </div>
                <div>
                  <Label className="text-xs text-slate-500">To</Label>
                  <Input type="date" value={range.toDate}
                         onChange={(e) => onRangeChange({ ...range, toDate: e.target.value })} />
                </div>
                {extraFilters}
                <Button onClick={onRun} disabled={loading}>
                  {loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Run
                </Button>
              </div>
            </CardContent>
          </Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : (
            children
          )}
        </main>
      </div>
    </div>
  )
}

/** A KPI tile. Same look as the dashboard's, without its icon box. */
export function ReportStat({
  title, value, hint, accent = "slate",
}: {
  title: string
  value: React.ReactNode
  hint?: React.ReactNode
  accent?: "slate" | "emerald" | "rose" | "amber"
}) {
  const colour = {
    slate: "text-slate-900",
    emerald: "text-emerald-700",
    rose: "text-rose-600",
    amber: "text-amber-600",
  }[accent]
  return (
    <Card>
      <CardHeader className="pb-1">
        <CardTitle className="text-xs uppercase tracking-wide text-slate-500">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <div className={`text-2xl font-semibold ${colour}`}>{value}</div>
        {hint && <div className="text-xs text-slate-500 mt-1">{hint}</div>}
      </CardContent>
    </Card>
  )
}

export interface ReportColumn<T> {
  key: string
  header: string
  align?: "left" | "right"
  render: (row: T) => React.ReactNode
  className?: string
}

/**
 * A read-only table in a card. Wide tables scroll INSIDE their own container --
 * a report with twelve columns must not make the whole page scroll sideways on
 * a phone.
 */
export function ReportTable<T>({
  title, columns, rows, empty, footer,
}: {
  title?: string
  columns: ReportColumn<T>[]
  rows: T[]
  empty: string
  footer?: React.ReactNode
}) {
  return (
    <Card>
      {title && (
        <CardHeader className="pb-2">
          <CardTitle className="text-xs uppercase tracking-wide text-slate-500">{title}</CardTitle>
        </CardHeader>
      )}
      <CardContent>
        {rows.length === 0 ? (
          <p className="text-sm text-slate-500">{empty}</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-xs uppercase tracking-wide text-slate-500">
                  {columns.map((c) => (
                    <th key={c.key} className={`py-1 pr-3 ${c.align === "right" ? "text-right" : "text-left"}`}>
                      {c.header}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((row, i) => (
                  <tr key={i}>
                    {columns.map((c) => (
                      <td key={c.key}
                          className={`py-1.5 pr-3 ${c.align === "right" ? "text-right" : ""} ${c.className ?? ""}`}>
                        {c.render(row)}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
              {footer && <tfoot className="border-t">{footer}</tfoot>}
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

/** Shared formatters. Every report shows money and months the same way. */
export function fmtMoney(n: number) {
  return new Intl.NumberFormat(undefined, {
    style: "currency", currency: "GHS", maximumFractionDigits: 2,
  }).format(n)
}

export function fmtMonth(d: string) {
  return new Date(d).toLocaleDateString(undefined, { month: "short", year: "numeric" })
}

export function fmtDate(d?: string | null) {
  if (!d) return "—"
  return new Date(d).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })
}

export function fmtPct(n: number) {
  return `${n.toFixed(1)}%`
}

/** A hook the report pages share: hold a range, run a loader, surface errors. */
export function useReport<T>(
  loader: (range: DateRange) => Promise<T>,
  initial: DateRange,
  onError: (message: string) => void,
) {
  const [range, setRange] = useState<DateRange>(initial)
  const [data, setData] = useState<T | null>(null)
  const [loading, setLoading] = useState(true)

  const run = async (r: DateRange = range) => {
    setLoading(true)
    try {
      setData(await loader(r))
    } catch (e: any) {
      onError(e?.message ?? String(e))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void run(initial)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return { range, setRange, data, loading, run }
}

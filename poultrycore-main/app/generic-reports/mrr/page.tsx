"use client"

// Report 2: monthly recurring revenue.
//
// The one thing this page has to make obvious is that the columns reconcile:
//
//   last month's active - what it lost + what this month gained = this month's active
//
// A subscription counts in the month it was cancelled -- the money was earned
// -- and drops out of the next, which is the month its loss is reported in.
//
// Expansion and contraction are shown as "not tracked" rather than as 0.00.
// There is no history of what a subscription used to cost, so the honest answer
// is that the system cannot tell, not that the number happens to be zero.

import { TrendingUp } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { getMrrReport, type GenericMrrRow } from "@/lib/api/generic-reports"
import {
  GenericReportShell, ReportStat, ReportTable, fmtMonth, fmtMoney,
  trailingMonthsRange, useReport,
} from "@/components/generic/report-shell"

export default function MrrReportPage() {
  const { toast } = useToast()
  const { labels } = useGenericModules()

  const { range, setRange, data, loading, run } = useReport<GenericMrrRow[]>(
    (r) => getMrrReport(r.fromDate, r.toDate),
    trailingMonthsRange(12),
    (message) => toast({ title: "Could not load report", description: message, variant: "destructive" }),
  )

  const rows = data ?? []
  const latest = rows.length ? rows[rows.length - 1] : null
  const first = rows.length ? rows[0] : null
  const growth = latest && first && first.activeMrr > 0
    ? ((latest.activeMrr - first.activeMrr) / first.activeMrr) * 100
    : null

  return (
    <GenericReportShell
      title="Monthly recurring revenue"
      description="Active, new and lost MRR month by month. Every figure is the same month grid the dashboard's MRR card uses."
      icon={TrendingUp}
      range={range}
      onRangeChange={setRange}
      onRun={() => run()}
      loading={loading}
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        <ReportStat title="MRR now" value={fmtMoney(latest?.activeMrr ?? 0)} hint={latest ? fmtMonth(latest.monthStart) : undefined} accent="emerald" />
        <ReportStat title={`Active ${labels.subscriptionPlural.toLowerCase()}`} value={latest?.activeCount ?? 0} />
        <ReportStat title="New this month" value={fmtMoney(latest?.newMrr ?? 0)} hint={`${latest?.newCount ?? 0} added`} />
        <ReportStat
          title="Lost this month"
          value={fmtMoney(latest?.lostMrr ?? 0)}
          hint={`${latest?.lostCount ?? 0} ended`}
          accent={(latest?.lostMrr ?? 0) > 0 ? "rose" : "slate"}
        />
      </div>

      {growth !== null && (
        <p className="text-sm text-slate-500 mb-4">
          MRR moved from {fmtMoney(first!.activeMrr)} in {fmtMonth(first!.monthStart)} to{" "}
          {fmtMoney(latest!.activeMrr)} in {fmtMonth(latest!.monthStart)} —{" "}
          <span className={growth >= 0 ? "text-emerald-700" : "text-rose-600"}>
            {growth >= 0 ? "+" : ""}{growth.toFixed(1)}%
          </span>.
        </p>
      )}

      <ReportTable
        rows={rows}
        empty="No months in this range."
        columns={[
          { key: "m", header: "Month", render: (r) => fmtMonth(r.monthStart) },
          { key: "a", header: "Active MRR", align: "right", render: (r) => fmtMoney(r.activeMrr) },
          { key: "ac", header: "Active", align: "right", render: (r) => r.activeCount },
          { key: "n", header: "New MRR", align: "right", className: "text-emerald-700", render: (r) => (r.newMrr ? `+${fmtMoney(r.newMrr)}` : "—") },
          { key: "l", header: "Lost MRR", align: "right", className: "text-rose-600", render: (r) => (r.lostMrr ? `-${fmtMoney(r.lostMrr)}` : "—") },
          {
            key: "net", header: "Net change", align: "right",
            render: (r) => (
              <span className={r.netMrrChange > 0 ? "text-emerald-700" : r.netMrrChange < 0 ? "text-rose-600" : ""}>
                {r.netMrrChange > 0 ? "+" : ""}{fmtMoney(r.netMrrChange)}
              </span>
            ),
          },
          { key: "e", header: "Expansion", align: "right", className: "text-slate-400", render: () => "not tracked" },
          { key: "c", header: "Contraction", align: "right", className: "text-slate-400", render: () => "not tracked" },
        ]}
      />

      <p className="text-xs text-slate-500 mt-3 max-w-3xl">
        Expansion and contraction MRR need a history of what each {labels.subscription.toLowerCase()} used to
        cost. This system keeps one current amount per {labels.subscription.toLowerCase()} and overwrites it, so a plan
        that went from 50 to 80 in March cannot be told apart from one that was always 80. The columns are
        left blank rather than filled with a guess.
      </p>
    </GenericReportShell>
  )
}

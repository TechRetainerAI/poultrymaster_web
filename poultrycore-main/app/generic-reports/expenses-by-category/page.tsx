"use client"

// Report 5: the expense report.
//
// This page used to show only the category cut. The spec asks for three --
// by category, by supplier, and the monthly trend -- so it now shows all three
// from one request. The ROUTE is unchanged on purpose: it is linked from the
// dashboard, from the reports hub and from anywhere anyone has bookmarked it,
// and a second "expense report" page next to this one would have meant two
// answers to "what did we spend".
//
// The category cut still comes from spgenericreport_expensesbycategory (037),
// the same function it always did.

import { BarChart3 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { getExpenseReport, type GenericExpenseReport } from "@/lib/api/generic-reports"
import {
  GenericReportShell, ReportStat, ReportTable, currentMonthRange, fmtMonth, fmtMoney, fmtPct, useReport,
} from "@/components/generic/report-shell"

export default function ExpenseReportPage() {
  const { toast } = useToast()

  const { range, setRange, data, loading, run } = useReport<GenericExpenseReport>(
    (r) => getExpenseReport(r.fromDate, r.toDate),
    currentMonthRange(),
    (message) => toast({ title: "Could not load report", description: message, variant: "destructive" }),
  )

  const byCategory = data?.byCategory ?? []
  const bySupplier = data?.bySupplier ?? []
  const trend = data?.trend ?? []
  const total = byCategory.reduce((s, r) => s + r.totalAmount, 0)
  const count = byCategory.reduce((s, r) => s + r.expenseCount, 0)
  const outstanding = bySupplier.reduce((s, r) => s + r.outstanding, 0)
  const recurring = trend.reduce((s, r) => s + r.recurringAmount, 0)

  return (
    <GenericReportShell
      title="Expense report"
      description="Where the money went — by category, by supplier, and month by month."
      icon={BarChart3}
      range={range}
      onRangeChange={setRange}
      onRun={() => run()}
      loading={loading}
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        <ReportStat title="Total spent" value={fmtMoney(total)} hint={`${count} expense(s)`} />
        <ReportStat title="Still unpaid" value={fmtMoney(outstanding)} accent={outstanding > 0 ? "rose" : "slate"} hint="Bills with a balance" />
        <ReportStat title="From recurring bills" value={fmtMoney(recurring)} hint={total > 0 ? fmtPct((recurring * 100) / total) + " of spend" : undefined} />
        <ReportStat title="Categories used" value={byCategory.length} />
      </div>

      <div className="space-y-4">
        <ReportTable
          title="By category"
          rows={byCategory}
          empty="No expenses in this period."
          columns={[
            { key: "c", header: "Category", render: (r) => r.categoryName },
            { key: "n", header: "Count", align: "right", render: (r) => r.expenseCount },
            { key: "t", header: "Amount", align: "right", className: "font-medium", render: (r) => fmtMoney(r.totalAmount) },
            {
              key: "p", header: "Share", align: "right",
              render: (r) => (
                <span className="inline-flex items-center gap-2 justify-end">
                  <span className="hidden sm:block h-1.5 w-16 bg-slate-100 rounded">
                    <span className="block h-1.5 bg-amber-500 rounded"
                          style={{ width: `${total > 0 ? Math.min((r.totalAmount * 100) / total, 100) : 0}%` }} />
                  </span>
                  {total > 0 ? fmtPct((r.totalAmount * 100) / total) : "—"}
                </span>
              ),
            },
          ]}
        />

        <ReportTable
          title="By supplier"
          rows={bySupplier}
          // Expenses with no supplier -- petrol, tips, one-off cash costs --
          // are a real category and get their own row rather than vanishing.
          empty="No expenses in this period."
          columns={[
            { key: "s", header: "Supplier", render: (r) => (r.genericSupplierId ? r.supplierName : <span className="text-slate-500">{r.supplierName}</span>) },
            { key: "n", header: "Count", align: "right", render: (r) => r.expenseCount },
            { key: "t", header: "Billed", align: "right", render: (r) => fmtMoney(r.totalAmount) },
            { key: "p", header: "Paid", align: "right", render: (r) => fmtMoney(r.amountPaid) },
            {
              key: "o", header: "Outstanding", align: "right", className: "text-rose-600",
              render: (r) => (r.outstanding > 0 ? fmtMoney(r.outstanding) : "—"),
            },
          ]}
        />

        <ReportTable
          title="Month by month"
          rows={trend}
          empty="No months in this range."
          columns={[
            { key: "m", header: "Month", render: (r) => fmtMonth(r.monthStart) },
            { key: "n", header: "Expenses", align: "right", render: (r) => r.expenseCount },
            { key: "t", header: "Total", align: "right", className: "font-medium", render: (r) => fmtMoney(r.totalAmount) },
            { key: "r", header: "Of which recurring", align: "right", render: (r) => (r.recurringAmount ? fmtMoney(r.recurringAmount) : "—") },
            // Staff payments post their own expense, so this column is a
            // breakdown of the same money, not an addition to it.
            { key: "s", header: "Paid to people", align: "right", render: (r) => (r.staffAmount ? fmtMoney(r.staffAmount) : "—") },
          ]}
        />
      </div>
    </GenericReportShell>
  )
}

"use client"

// Report 1: subscription / membership / contract revenue.
//
// Three cuts of the same window -- by month, by plan, by customer -- from one
// request, because they are three result sets of one command.
//
// INVOICED is what was billed in the month. COLLECTED is what has been paid
// against those invoices as of now, not cash received in that month: an invoice
// raised in March and paid in May is March revenue, and filing the payment
// under May would leave the month unable to reconcile with its own invoices.
// Cash by month is the Payments report.

import { Repeat } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { getSubscriptionRevenue, type GenericSubRevenueReport } from "@/lib/api/generic-reports"
import {
  GenericReportShell, ReportStat, ReportTable, fmtDate, fmtMonth, fmtMoney,
  trailingMonthsRange, useReport,
} from "@/components/generic/report-shell"

export default function SubscriptionRevenuePage() {
  const { toast } = useToast()
  const { labels } = useGenericModules()

  const { range, setRange, data, loading, run } = useReport<GenericSubRevenueReport>(
    (r) => getSubscriptionRevenue(r.fromDate, r.toDate),
    trailingMonthsRange(12),
    (message) => toast({ title: "Could not load report", description: message, variant: "destructive" }),
  )

  const months = data?.byMonth ?? []
  const invoiced = months.reduce((s, m) => s + m.invoicedAmount, 0)
  const collected = months.reduce((s, m) => s + m.collectedAmount, 0)
  const outstanding = months.reduce((s, m) => s + m.outstanding, 0)
  const latestMrr = months.length ? months[months.length - 1].activeMrr : 0

  return (
    <GenericReportShell
      title={`${labels.subscription} revenue`}
      description={`What was billed, what has been collected, and how it splits by ${labels.plan.toLowerCase()} and by ${labels.customer.toLowerCase()}.`}
      icon={Repeat}
      range={range}
      onRangeChange={setRange}
      onRun={() => run()}
      loading={loading}
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        <ReportStat title="Invoiced" value={fmtMoney(invoiced)} hint={`${months.reduce((s, m) => s + m.invoiceCount, 0)} ${labels.invoicePlural.toLowerCase()}`} />
        <ReportStat title="Collected" value={fmtMoney(collected)} accent="emerald" />
        <ReportStat title="Still owed" value={fmtMoney(outstanding)} accent={outstanding > 0 ? "rose" : "slate"} />
        <ReportStat title="MRR now" value={fmtMoney(latestMrr)} hint="Latest month in range" />
      </div>

      <div className="space-y-4">
        <ReportTable
          title="By month"
          rows={months}
          empty="No months in this range."
          columns={[
            { key: "m", header: "Month", render: (r) => fmtMonth(r.monthStart) },
            { key: "n", header: labels.invoicePlural, align: "right", render: (r) => r.invoiceCount },
            { key: "inv", header: "Invoiced", align: "right", render: (r) => fmtMoney(r.invoicedAmount) },
            { key: "col", header: "Collected", align: "right", render: (r) => fmtMoney(r.collectedAmount) },
            { key: "out", header: "Outstanding", align: "right", className: "text-rose-600", render: (r) => (r.outstanding > 0 ? fmtMoney(r.outstanding) : "—") },
            { key: "mrr", header: "Active MRR", align: "right", render: (r) => fmtMoney(r.activeMrr) },
            { key: "new", header: "New", align: "right", render: (r) => (r.newCount ? `+${r.newCount}` : "—") },
            { key: "lost", header: "Lost", align: "right", render: (r) => (r.lostCount ? `-${r.lostCount}` : "—") },
          ]}
        />

        <ReportTable
          title={`By ${labels.plan.toLowerCase()}`}
          rows={data?.byPlan ?? []}
          // A plan with live subscriptions and no invoices still appears --
          // that row is usually the reason someone opened this report.
          empty={`No ${labels.planPlural.toLowerCase()} yet.`}
          columns={[
            { key: "p", header: labels.plan, render: (r) => r.serviceName },
            { key: "f", header: "Billing", render: (r) => r.billingFrequency || "—" },
            { key: "a", header: "Active", align: "right", render: (r) => r.activeSubscriptions },
            { key: "mrr", header: "MRR", align: "right", render: (r) => fmtMoney(r.activeMrr) },
            { key: "inv", header: "Invoiced", align: "right", render: (r) => fmtMoney(r.invoicedAmount) },
            { key: "col", header: "Collected", align: "right", render: (r) => fmtMoney(r.collectedAmount) },
            { key: "out", header: "Outstanding", align: "right", className: "text-rose-600", render: (r) => (r.outstanding > 0 ? fmtMoney(r.outstanding) : "—") },
          ]}
        />

        <ReportTable
          title={`By ${labels.customer.toLowerCase()}`}
          rows={data?.byCustomer ?? []}
          empty={`No ${labels.customerPlural.toLowerCase()} billed in this range.`}
          columns={[
            { key: "c", header: labels.customer, render: (r) => r.customerName },
            { key: "a", header: "Active", align: "right", render: (r) => r.activeSubscriptions },
            { key: "mrr", header: "MRR", align: "right", render: (r) => fmtMoney(r.activeMrr) },
            { key: "inv", header: "Invoiced", align: "right", render: (r) => fmtMoney(r.invoicedAmount) },
            { key: "col", header: "Collected", align: "right", render: (r) => fmtMoney(r.collectedAmount) },
            { key: "out", header: "Outstanding", align: "right", className: "text-rose-600", render: (r) => (r.outstanding > 0 ? fmtMoney(r.outstanding) : "—") },
            { key: "last", header: "Last payment", render: (r) => fmtDate(r.lastPaymentDate) },
          ]}
        />
      </div>
    </GenericReportShell>
  )
}

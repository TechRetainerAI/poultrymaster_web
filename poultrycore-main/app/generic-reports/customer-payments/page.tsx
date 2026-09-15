"use client"

// Report 3: customer / member payments received.
//
// No new endpoint. spgenericcustomerpayment_history (migration 244) already
// answers this, and lib/api/balances speaks it for all three company types, so
// this page is a view over the same data the Customer Balances page shows.
// A "reports" copy of the same query would have been a second definition of
// money received.

import { CreditCard } from "lucide-react"
import Link from "next/link"
import { useToast } from "@/hooks/use-toast"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { listPayments, type PaymentHistoryRow } from "@/lib/api/balances"
import {
  GenericReportShell, ReportStat, ReportTable, currentMonthRange, fmtDate, fmtMoney, useReport,
} from "@/components/generic/report-shell"
import { Badge } from "@/components/ui/badge"

export default function CustomerPaymentsReportPage() {
  const { toast } = useToast()
  const { labels } = useGenericModules()

  const { range, setRange, data, loading, run } = useReport<PaymentHistoryRow[]>(
    (r) => listPayments("generic", "customer", { from: r.fromDate, to: r.toDate }),
    currentMonthRange(),
    (message) => toast({ title: "Could not load report", description: message, variant: "destructive" }),
  )

  const rows = data ?? []
  // A reversed payment is still shown -- it happened -- but it is not money
  // the business kept, so the totals exclude it.
  const live = rows.filter((r) => r.status !== "Reversed")
  const total = live.reduce((s, r) => s + r.totalAmount, 0)
  const byMethod = new Map<string, number>()
  live.forEach((r) => {
    const m = r.paymentMethod || "Unspecified"
    byMethod.set(m, (byMethod.get(m) ?? 0) + r.totalAmount)
  })
  const topMethod = [...byMethod.entries()].sort((a, b) => b[1] - a[1])[0]

  return (
    <GenericReportShell
      title={`${labels.customer} payments`}
      description={`Every payment received in the period, what it was paid by, and how many ${labels.invoicePlural.toLowerCase()} it settled.`}
      icon={CreditCard}
      range={range}
      onRangeChange={setRange}
      onRun={() => run()}
      loading={loading}
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        <ReportStat title="Received" value={fmtMoney(total)} accent="emerald" hint={`${live.length} payment(s)`} />
        <ReportStat title="Reversed" value={rows.length - live.length} hint="Excluded from the total" accent={rows.length - live.length > 0 ? "rose" : "slate"} />
        <ReportStat title="Most used" value={topMethod ? topMethod[0] : "—"} hint={topMethod ? fmtMoney(topMethod[1]) : undefined} />
        <ReportStat title="Average" value={fmtMoney(live.length ? total / live.length : 0)} />
      </div>

      <ReportTable
        rows={rows}
        empty="No payments in this period."
        columns={[
          { key: "d", header: "Date", render: (r) => fmtDate(r.paymentDate) },
          { key: "ref", header: "Payment", render: (r) => r.paymentNumber ?? String(r.paymentId) },
          {
            key: "who", header: labels.customer,
            render: (r) => (r.partyId
              ? <Link href={`/generic-customer-balances?customerId=${r.partyId}`} className="text-emerald-700 hover:underline">{r.partyName ?? `#${r.partyId}`}</Link>
              : (r.partyName ?? "—")),
          },
          { key: "m", header: "Method", render: (r) => r.paymentMethod ?? "—" },
          { key: "r", header: "Reference", render: (r) => r.reference ?? "—" },
          { key: "n", header: "Applied to", align: "right", render: (r) => `${r.allocationCount} ${labels.invoicePlural.toLowerCase()}` },
          {
            key: "amt", header: "Amount", align: "right",
            render: (r) => (
              <span className={r.status === "Reversed" ? "line-through text-slate-400" : "font-medium"}>
                {fmtMoney(r.totalAmount)}
              </span>
            ),
          },
          {
            key: "s", header: "Status",
            render: (r) => <Badge variant={r.status === "Reversed" ? "outline" : "secondary"}>{r.status}</Badge>,
          },
        ]}
      />
    </GenericReportShell>
  )
}

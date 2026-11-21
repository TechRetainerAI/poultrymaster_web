"use client"

// Sales report: what sold, at what average price, to whom, and day by day.

import Link from "next/link"
import { ShoppingBag } from "lucide-react"
import { getSalesReport } from "@/lib/api/livestock"
import { PeriodPicker } from "@/components/livestock/money-bits"
import { ReportTable, REPORTS_BACK, usePeriodReport } from "@/components/livestock/report-bits"
import { LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum } from "@/components/livestock/livestock-page"

export default function LivestockSalesReportPage() {
  const r = usePeriodReport(getSalesReport)
  return (
    <LivestockPage title="Sales" description="What sold, at what price, and to whom." icon={ShoppingBag} back={REPORTS_BACK}>
      <PeriodPicker from={r.from} to={r.to} onChange={r.setPeriod} />
      {r.error ? <LoadError message={r.error} onRetry={r.load} /> : !r.data ? <Loading /> : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard label="Sold" value={fmtMoney(r.data.total)} tone="amber" hint={`${r.data.sales} sale(s)`} />
            <StatCard label="Received" value={fmtMoney(r.data.received)} />
            <StatCard label="Still owed" value={fmtMoney(r.data.total - r.data.received)} tone={r.data.total > r.data.received ? "rose" : "stone"} />
          </div>
          <ReportTable title="What sold" rows={r.data.byWhat} rowKey={(w, i) => `${w.kind}-${w.what}-${i}`} cols={[
            { label: "What", cell: (w) => w.what ?? "—" },
            { label: "Kind", cell: (w) => (w.kind === "Animals" ? "Animals" : "Produce & stock") },
            { label: "Quantity", right: true, cell: (w) => `${fmtNum(w.quantity)} ${w.unit}` },
            { label: "Average price", right: true, cell: (w) => fmtMoney(w.averagePrice) },
            { label: "Amount", right: true, cell: (w) => fmtMoney(w.amount) },
          ]} />
          <ReportTable title="By customer" rows={r.data.byCustomer} rowKey={(c, i) => c.customerId ?? `walkin-${i}`} cols={[
            { label: "Customer", cell: (c) => c.customerId ? <Link className="text-amber-800 hover:underline" href={`/livestock-customer-balances?customerId=${c.customerId}`}>{c.name}</Link> : c.name },
            { label: "Sales", right: true, cell: (c) => fmtNum(c.sales) },
            { label: "Amount", right: true, cell: (c) => fmtMoney(c.amount) },
            { label: "Owes now", right: true, cell: (c) => (c.owes > 0 ? <span className="text-rose-700">{fmtMoney(c.owes)}</span> : "—") },
          ]} />
          <ReportTable title="Day by day" rows={r.data.daily} rowKey={(d) => d.date} cols={[
            { label: "Date", cell: (d) => fmtDate(d.date) },
            { label: "Amount", right: true, cell: (d) => fmtMoney(d.amount) },
          ]} />
        </>
      )}
    </LivestockPage>
  )
}

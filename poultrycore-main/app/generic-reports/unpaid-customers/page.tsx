"use client"

// Report 4: who owes money and how old it is.
//
// No new endpoint: spgenericcustomerbalances (migration 244) already returns
// the balance, the overdue part, the oldest open document and the last payment
// date. The Customer Balances PAGE is for working the list -- take a payment,
// open a statement. This is the report: aged, printable, sorted worst first.

import { AlertTriangle, Phone } from "lucide-react"
import Link from "next/link"
import { useState } from "react"
import { useToast } from "@/hooks/use-toast"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { listBalances, type PartyBalanceRow, type BalanceStatusFilter } from "@/lib/api/balances"
import {
  GenericReportShell, ReportStat, ReportTable, currentMonthRange, fmtDate, fmtMoney, useReport,
} from "@/components/generic/report-shell"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"

/** Days since the oldest open document — the age of the debt, not of the party. */
function ageDays(oldest?: string | null): number | null {
  if (!oldest) return null
  const ms = Date.now() - new Date(oldest).getTime()
  return Math.max(0, Math.floor(ms / 86_400_000))
}

export default function UnpaidCustomersReportPage() {
  const { toast } = useToast()
  const { labels } = useGenericModules()
  const [status, setStatus] = useState<BalanceStatusFilter>("Overdue")

  const { range, setRange, data, loading, run } = useReport<PartyBalanceRow[]>(
    (r) => listBalances("generic", "customer", { from: r.fromDate, to: r.toDate, status }),
    // Balances are a position, not a period: the default asks for everything
    // open, and the date range narrows which documents count.
    { fromDate: "", toDate: "" },
    (message) => toast({ title: "Could not load report", description: message, variant: "destructive" }),
  )

  const rows = data ?? []
  const totalOwed = rows.reduce((s, r) => s + r.totalBalance, 0)
  const totalOverdue = rows.reduce((s, r) => s + r.overdueAmount, 0)
  const oldest = rows.reduce<number | null>((worst, r) => {
    const a = ageDays(r.oldestDocumentDate)
    return a !== null && (worst === null || a > worst) ? a : worst
  }, null)

  return (
    <GenericReportShell
      title={`Unpaid ${labels.customerPlural.toLowerCase()}`}
      description={`Open ${labels.invoicePlural.toLowerCase()}, what is already late, and how to reach whoever owes it.`}
      icon={AlertTriangle}
      range={range}
      onRangeChange={setRange}
      onRun={() => run()}
      loading={loading}
      extraFilters={
        <div>
          <Label>Show</Label>
          <Select value={status} onValueChange={(v) => setStatus(v as BalanceStatusFilter)}>
            <SelectTrigger className="w-[10rem]"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="Overdue">Overdue only</SelectItem>
              <SelectItem value="All">Everything open</SelectItem>
              <SelectItem value="Unpaid">Not paid at all</SelectItem>
              <SelectItem value="Partial">Part paid</SelectItem>
            </SelectContent>
          </Select>
        </div>
      }
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        <ReportStat title={`${labels.customerPlural} owing`} value={rows.length} />
        <ReportStat title="Total owed" value={fmtMoney(totalOwed)} />
        <ReportStat title="Already overdue" value={fmtMoney(totalOverdue)} accent={totalOverdue > 0 ? "rose" : "slate"} />
        <ReportStat title="Oldest debt" value={oldest === null ? "—" : `${oldest} days`} />
      </div>

      <ReportTable
        rows={rows}
        empty={`Nothing outstanding. Every ${labels.invoice.toLowerCase()} in this range is settled.`}
        columns={[
          {
            key: "c", header: labels.customer,
            render: (r) => (
              <Link href={`/generic-customer-balances?customerId=${r.partyId}`} className="text-emerald-700 hover:underline">
                {r.partyName}
              </Link>
            ),
          },
          {
            key: "phone", header: "Contact",
            render: (r) => r.contactPhone
              ? <a href={`tel:${r.contactPhone}`} className="inline-flex items-center gap-1 text-slate-600 hover:text-slate-900">
                  <Phone className="h-3 w-3" />{r.contactPhone}
                </a>
              : (r.contactEmail ?? "—"),
          },
          { key: "open", header: "Open", align: "right", render: (r) => r.openDocumentCount },
          { key: "bal", header: "Owed", align: "right", render: (r) => fmtMoney(r.totalBalance) },
          {
            key: "od", header: "Overdue", align: "right", className: "text-rose-600",
            render: (r) => (r.overdueAmount > 0 ? fmtMoney(r.overdueAmount) : "—"),
          },
          {
            key: "age", header: "Age", align: "right",
            render: (r) => { const a = ageDays(r.oldestDocumentDate); return a === null ? "—" : `${a}d` },
          },
          { key: "last", header: "Last payment", render: (r) => fmtDate(r.lastPaymentDate) },
          { key: "terms", header: "Terms", align: "right", render: (r) => (r.paymentTermsDays ? `${r.paymentTermsDays}d` : "—") },
        ]}
      />
    </GenericReportShell>
  )
}

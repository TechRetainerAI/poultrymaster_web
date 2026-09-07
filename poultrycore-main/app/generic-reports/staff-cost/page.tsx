"use client"

// Report 7: what people cost.
//
// Counts BOTH ways this system pays a person: a staff payment (migration 249,
// for a contractor or a one-off) and a paid payroll run. A business that uses
// one for contractors and the other for employees would otherwise see half its
// wage bill. The two cannot double count -- they are different tables and
// neither writes the other.

import { Users2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { getStaffCostReport, type GenericStaffCostReport } from "@/lib/api/generic-reports"
import {
  GenericReportShell, ReportStat, ReportTable, fmtDate, fmtMonth, fmtMoney, fmtPct,
  trailingMonthsRange, useReport,
} from "@/components/generic/report-shell"

export default function StaffCostReportPage() {
  const { toast } = useToast()

  const { range, setRange, data, loading, run } = useReport<GenericStaffCostReport>(
    (r) => getStaffCostReport(r.fromDate, r.toDate),
    trailingMonthsRange(6),
    (message) => toast({ title: "Could not load report", description: message, variant: "destructive" }),
  )

  const people = data?.byPerson ?? []
  const months = data?.byMonth ?? []
  const total = people.reduce((s, p) => s + p.totalPaid, 0)
  const staffPayments = people.reduce((s, p) => s + p.staffPayments, 0)
  const payroll = people.reduce((s, p) => s + p.payrollPay, 0)
  const monthsWithPay = months.filter((m) => m.totalPaid > 0).length

  return (
    <GenericReportShell
      title="Staff &amp; contractor cost"
      description="Everything paid to people in the period — staff payments and payroll together — by person, by month and by role."
      icon={Users2}
      range={range}
      onRangeChange={setRange}
      onRun={() => run()}
      loading={loading}
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        <ReportStat title="Total paid" value={fmtMoney(total)} hint={`${people.length} person(s)`} />
        <ReportStat title="Staff payments" value={fmtMoney(staffPayments)} />
        <ReportStat title="Payroll" value={fmtMoney(payroll)} />
        <ReportStat title="Average a month" value={fmtMoney(monthsWithPay ? total / monthsWithPay : 0)} hint={`${monthsWithPay} month(s) with pay`} />
      </div>

      <div className="space-y-4">
        <ReportTable
          title="By person"
          rows={people}
          empty="Nobody was paid in this period."
          columns={[
            { key: "n", header: "Person", render: (r) => r.staffName },
            { key: "r", header: "Role", render: (r) => r.staffRole ?? "—" },
            { key: "w", header: "Engaged as", render: (r) => r.workerType ?? "—" },
            { key: "c", header: "Payments", align: "right", render: (r) => r.paymentCount },
            { key: "sp", header: "Staff payments", align: "right", render: (r) => fmtMoney(r.staffPayments) },
            { key: "pp", header: "Payroll", align: "right", render: (r) => fmtMoney(r.payrollPay) },
            { key: "t", header: "Total", align: "right", className: "font-medium", render: (r) => fmtMoney(r.totalPaid) },
            { key: "l", header: "Last paid", render: (r) => fmtDate(r.lastPaymentDate) },
          ]}
        />

        <ReportTable
          title="By month"
          rows={months}
          empty="No months in this range."
          columns={[
            { key: "m", header: "Month", render: (r) => fmtMonth(r.monthStart) },
            { key: "p", header: "People paid", align: "right", render: (r) => r.peoplePaid },
            { key: "sp", header: "Staff payments", align: "right", render: (r) => fmtMoney(r.staffPayments) },
            { key: "pp", header: "Payroll", align: "right", render: (r) => fmtMoney(r.payrollPay) },
            { key: "t", header: "Total", align: "right", className: "font-medium", render: (r) => fmtMoney(r.totalPaid) },
          ]}
        />

        <ReportTable
          title="By role"
          rows={data?.byRole ?? []}
          empty="No roles to group by."
          columns={[
            { key: "r", header: "Role", render: (r) => r.staffRole },
            { key: "n", header: "People", align: "right", render: (r) => r.peopleCount },
            { key: "t", header: "Paid", align: "right", render: (r) => fmtMoney(r.totalPaid) },
            {
              key: "p", header: "Share", align: "right",
              render: (r) => (
                <span className="inline-flex items-center gap-2 justify-end">
                  <span className="hidden sm:block h-1.5 w-16 bg-slate-100 rounded">
                    <span className="block h-1.5 bg-sky-500 rounded" style={{ width: `${Math.min(r.pctOfTotal, 100)}%` }} />
                  </span>
                  {fmtPct(r.pctOfTotal)}
                </span>
              ),
            },
          ]}
        />
      </div>
    </GenericReportShell>
  )
}

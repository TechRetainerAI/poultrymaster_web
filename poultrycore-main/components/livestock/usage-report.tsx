"use client"

// One page body for "Feed used" and "Medicine used": both read stock that left
// the store for daily records, treatments and health records.

import Link from "next/link"
import type { ComponentType } from "react"
import type { UsageReport } from "@/lib/api/livestock"
import { PeriodPicker } from "@/components/livestock/money-bits"
import { ReportTable, REPORTS_BACK, usePeriodReport } from "@/components/livestock/report-bits"
import { LivestockPage, LoadError, Loading, StatCard, fmtMoney, fmtNum } from "@/components/livestock/livestock-page"

const SOURCE: Record<string, string> = { ProductionRecord: "Daily records", TreatmentDay: "Treatments", HealthRecord: "Health records" }

export function UsageReportPage({ title, description, icon, fetcher, medicine }: {
  title: string; description: string; icon: ComponentType<{ className?: string }>
  fetcher: (from: string, to: string) => Promise<UsageReport>; medicine?: boolean
}) {
  const r = usePeriodReport(fetcher)
  return (
    <LivestockPage title={title} description={description} icon={icon} back={REPORTS_BACK}>
      <PeriodPicker from={r.from} to={r.to} onChange={r.setPeriod} />
      {r.error ? <LoadError message={r.error} onRetry={r.load} /> : !r.data ? <Loading /> : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard label="Cost" value={fmtMoney(r.data.totalCost)} tone="amber" />
            {Object.entries(r.data.bySource).map(([k, v]) => <StatCard key={k} label={SOURCE[k] ?? k} value={fmtMoney(v)} />)}
            {medicine && <StatCard label="Treatments" value={fmtNum(r.data.treatments)} />}
            {medicine && <StatCard label="Health records" value={fmtNum(r.data.healthRecords)} />}
          </div>
          <ReportTable title="By item" rows={r.data.byItem} rowKey={(i) => i.itemId} cols={[
            { label: "Item", cell: (i) => <Link className="text-amber-800 hover:underline" href={`/livestock-items/${i.itemId}`}>{i.name}</Link> },
            { label: "Used", right: true, cell: (i) => `${fmtNum(i.quantity)} ${i.unit}` },
            ...(medicine ? [] : [{ label: "kg", right: true, cell: (i: UsageReport["byItem"][number]) => fmtNum(i.kg) }]),
            { label: "Cost", right: true, cell: (i) => fmtMoney(i.cost) },
          ]} />
          <ReportTable title="By group" rows={r.data.byGroup} rowKey={(g) => g.groupId} cols={[
            { label: "Group", cell: (g) => <Link className="text-amber-800 hover:underline" href={`/livestock-groups/${g.groupId}`}>{g.name}</Link> },
            { label: "Animals now", right: true, cell: (g) => fmtNum(g.head) },
            ...(medicine ? [] : [{ label: "kg", right: true, cell: (g: UsageReport["byGroup"][number]) => fmtNum(g.kg) }]),
            { label: "Cost", right: true, cell: (g) => fmtMoney(g.cost) },
            { label: "Cost per animal", right: true, cell: (g) => (g.head > 0 ? fmtMoney(g.cost / g.head) : "—") },
          ]} />
          {medicine && (
            <ReportTable title="Illnesses seen" rows={r.data.illnesses ?? []} rowKey={(x) => x.diagnosis} empty="No illness recorded in these dates." cols={[
              { label: "Illness", cell: (x) => x.diagnosis },
              { label: "Times", right: true, cell: (x) => fmtNum(x.cases) },
              { label: "Animals affected", right: true, cell: (x) => fmtNum(x.affected) },
            ]} />
          )}
        </>
      )}
    </LivestockPage>
  )
}

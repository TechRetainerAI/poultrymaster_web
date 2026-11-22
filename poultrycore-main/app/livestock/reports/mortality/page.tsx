"use client"

// Deaths & culls: by group, with the share of the group lost, and the causes.

import Link from "next/link"
import { Skull } from "lucide-react"
import { getMortalityReport } from "@/lib/api/livestock"
import { PeriodPicker } from "@/components/livestock/money-bits"
import { ReportTable, REPORTS_BACK, pct, usePeriodReport } from "@/components/livestock/report-bits"
import { LivestockPage, LoadError, Loading, StatCard, fmtNum } from "@/components/livestock/livestock-page"

export default function LivestockMortalityReportPage() {
  const r = usePeriodReport(getMortalityReport)
  return (
    <LivestockPage title="Deaths & culls" description="Deaths by group and what caused them." icon={Skull} back={REPORTS_BACK}>
      <PeriodPicker from={r.from} to={r.to} onChange={r.setPeriod} />
      {r.error ? <LoadError message={r.error} onRetry={r.load} /> : !r.data ? <Loading /> : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard label="Died" value={fmtNum(r.data.deaths)} tone={r.data.deaths ? "rose" : "stone"} />
            <StatCard label="Culled" value={fmtNum(r.data.culls)} />
          </div>
          <ReportTable title="By group" rows={r.data.byGroup} rowKey={(g) => g.groupId} empty="No deaths or culls in these dates." cols={[
            { label: "Group", cell: (g) => <Link className="text-amber-800 hover:underline" href={`/livestock-groups/${g.groupId}`}>{g.name}</Link> },
            { label: "Kind", cell: (g) => g.speciesName },
            { label: "At start", right: true, cell: (g) => fmtNum(g.headStart) },
            { label: "Died", right: true, cell: (g) => fmtNum(g.deaths) },
            { label: "Deaths %", right: true, cell: (g) => pct(g.mortalityPct) },
            { label: "Culled", right: true, cell: (g) => fmtNum(g.culls) },
          ]} />
          <ReportTable title="Causes" rows={r.data.causes} rowKey={(c) => c.cause} empty="No deaths in these dates." cols={[
            { label: "Cause", cell: (c) => c.cause },
            { label: "Died", right: true, cell: (c) => fmtNum(c.deaths) },
            { label: "Share", right: true, cell: (c) => (r.data!.deaths ? `${Math.round((c.deaths * 100) / r.data!.deaths)}%` : "—") },
          ]} />
        </>
      )}
    </LivestockPage>
  )
}

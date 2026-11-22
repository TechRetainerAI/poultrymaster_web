"use client"

// Births & litters: matings, births, litter sizes and survival per kind of
// animal, and each mother's record.

import Link from "next/link"
import { Baby } from "lucide-react"
import { getBreedingReport } from "@/lib/api/livestock"
import { PeriodPicker } from "@/components/livestock/money-bits"
import { ReportTable, REPORTS_BACK, pct, usePeriodReport } from "@/components/livestock/report-bits"
import { LivestockPage, LoadError, Loading, fmtNum } from "@/components/livestock/livestock-page"

export default function LivestockBreedingReportPage() {
  const r = usePeriodReport(getBreedingReport)
  return (
    <LivestockPage title="Births & litters" description="Births, litter sizes and the best mothers." icon={Baby} back={REPORTS_BACK}>
      <PeriodPicker from={r.from} to={r.to} onChange={r.setPeriod} />
      {r.error ? <LoadError message={r.error} onRetry={r.load} /> : !r.data ? <Loading /> : (
        <>
          <ReportTable title="By kind of animal" rows={r.data.bySpecies} rowKey={(s) => s.speciesName} empty="No breeding recorded in these dates." cols={[
            { label: "Kind", cell: (s) => s.speciesName },
            { label: "Matings", right: true, cell: (s) => fmtNum(s.matings) },
            { label: "Births", right: true, cell: (s) => fmtNum(s.births) },
            { label: "Born alive", right: true, cell: (s) => fmtNum(s.bornAlive) },
            { label: "Born dead", right: true, cell: (s) => fmtNum(s.bornDead) },
            { label: "Average litter", right: true, cell: (s) => fmtNum(s.averageLitter) },
            { label: "Born alive %", right: true, cell: (s) => pct(s.survivalPct) },
            { label: "Weaned", right: true, cell: (s) => fmtNum(s.weaned) },
            { label: "Pregnancies lost", right: true, cell: (s) => fmtNum(s.lost) },
          ]} />
          <ReportTable title="Mothers" rows={r.data.byMother} rowKey={(m) => m.animalId} empty="No births by a tagged mother in these dates." cols={[
            { label: "Mother", cell: (m) => <Link className="text-amber-800 hover:underline" href={`/livestock-animals/${m.animalId}`}>{m.tagNumber}</Link> },
            { label: "Births", right: true, cell: (m) => fmtNum(m.births) },
            { label: "Born alive", right: true, cell: (m) => fmtNum(m.bornAlive) },
            { label: "Average litter", right: true, cell: (m) => fmtNum(m.averageLitter) },
          ]} />
        </>
      )}
    </LivestockPage>
  )
}

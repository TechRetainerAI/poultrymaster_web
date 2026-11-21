"use client"

// Production report: per group, head, deaths, eggs and lay rate, milk per
// animal, feed per animal. Rates use the head at the start of each day.

import { useState } from "react"
import Link from "next/link"
import { ClipboardList } from "lucide-react"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { getProductionReport } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { PeriodPicker } from "@/components/livestock/money-bits"
import { ReportTable, REPORTS_BACK, pct, usePeriodReport } from "@/components/livestock/report-bits"
import { LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtNum } from "@/components/livestock/livestock-page"

const ALL = "__all"

export default function LivestockProductionReportPage() {
  const { kept } = useLivestockSpecies()
  const [species, setSpecies] = useState(ALL)
  const r = usePeriodReport((from, to) => getProductionReport(from, to, species === ALL ? undefined : species), [species])
  const groups = r.data?.groups ?? []
  const eggs = groups.some((g) => g.producesEggs)
  const milk = groups.some((g) => g.producesMilk)
  const sum = (k: "eggs" | "milk" | "deaths") => groups.reduce((s, g) => s + (Number(g[k]) || 0), 0)

  return (
    <LivestockPage title="Production" description="Eggs, milk, deaths and feed for each group." icon={ClipboardList} back={REPORTS_BACK}>
      <div className="flex gap-2 flex-wrap items-center">
        <PeriodPicker from={r.from} to={r.to} onChange={r.setPeriod} />
        <Select value={species} onValueChange={setSpecies}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All animals</SelectItem>
            {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {r.error ? <LoadError message={r.error} onRetry={r.load} /> : !r.data ? <Loading /> : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard label="Died" value={fmtNum(sum("deaths"))} tone={sum("deaths") ? "rose" : "stone"} />
            {eggs && <StatCard label="Eggs" value={fmtNum(sum("eggs"))} tone="amber" />}
            {milk && <StatCard label="Milk (L)" value={fmtNum(sum("milk"))} tone="amber" />}
            <StatCard label="Daily records" value={fmtNum(groups.reduce((s, g) => s + g.records, 0))} />
          </div>
          <ReportTable title="By group" rows={groups} rowKey={(g) => g.groupId} cols={[
            { label: "Group", cell: (g) => <Link className="text-amber-800 hover:underline" href={`/livestock-groups/${g.groupId}`}>{g.name}</Link> },
            { label: "Kind", cell: (g) => g.speciesName },
            { label: "Start", right: true, cell: (g) => fmtNum(g.headStart) },
            { label: "End", right: true, cell: (g) => fmtNum(g.headEnd) },
            { label: "Died", right: true, cell: (g) => fmtNum(g.deaths) },
            { label: "Deaths %", right: true, cell: (g) => pct(g.mortalityPct) },
            ...(eggs ? [
              { label: "Eggs", right: true, cell: (g: typeof groups[number]) => g.producesEggs ? fmtNum(g.eggs) : "" },
              { label: "Lay rate", right: true, cell: (g: typeof groups[number]) => g.producesEggs ? pct(g.layRatePct) : "" },
            ] : []),
            ...(milk ? [
              { label: "Milk (L)", right: true, cell: (g: typeof groups[number]) => g.producesMilk ? fmtNum(g.milk) : "" },
              { label: "L per animal a day", right: true, cell: (g: typeof groups[number]) => g.producesMilk ? fmtNum(g.milkPerAnimalDay) : "" },
            ] : []),
            { label: "Feed (kg)", right: true, cell: (g) => fmtNum(g.feedKg) },
            { label: "kg per animal a day", right: true, cell: (g) => fmtNum(g.feedPerAnimalDayKg) },
          ]} />
          <ReportTable title="Day by day" rows={r.data.daily} rowKey={(d) => d.date} cols={[
            { label: "Date", cell: (d) => fmtDate(d.date) },
            { label: "Died", right: true, cell: (d) => d.deaths || "" },
            ...(eggs ? [{ label: "Eggs", right: true, cell: (d: typeof r.data.daily[number]) => fmtNum(d.eggs) }] : []),
            ...(milk ? [{ label: "Milk (L)", right: true, cell: (d: typeof r.data.daily[number]) => fmtNum(d.milk) }] : []),
          ]} />
        </>
      )}
    </LivestockPage>
  )
}

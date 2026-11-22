"use client"

// Group summary: one group's whole life -- animals in and out, produce, feed,
// latest weight, and its profit -- the poultry flock closeout view.

import { Suspense, useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { Layers } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { getGroupSummary, listGroups, type GroupSummary, type LivestockGroup } from "@/lib/api/livestock"
import { MOVEMENT_LABEL } from "@/components/livestock/labels"
import { REPORTS_BACK } from "@/components/livestock/report-bits"
import { EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum } from "@/components/livestock/livestock-page"

export default function LivestockGroupSummaryPage() {
  return <Suspense fallback={<Loading />}><GroupSummaryInner /></Suspense>
}

function GroupSummaryInner() {
  const params = useSearchParams()
  const router = useRouter()
  const groupId = Number(params.get("groupId")) || null
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [s, setS] = useState<GroupSummary | null>(null)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => { listGroups(true).then(setGroups).catch(() => setGroups([])) }, [])
  const load = useCallback(async () => {
    if (!groupId) return
    setError(null); setS(null)
    try { setS(await getGroupSummary(groupId)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [groupId])
  useEffect(() => { load() }, [load])
  const pl = s?.profitLoss

  return (
    <LivestockPage title="Group summary" description="One group's whole life on one page." icon={Layers} back={REPORTS_BACK}>
      <Select value={groupId ? String(groupId) : ""} onValueChange={(v) => router.replace(`/livestock/reports/group-summary?groupId=${v}`)}>
        <SelectTrigger className="w-72"><SelectValue placeholder="Choose a group" /></SelectTrigger>
        <SelectContent>{groups.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.speciesName}{g.status !== "Active" ? " (closed)" : ""}</SelectItem>)}</SelectContent>
      </Select>
      {!groupId ? <EmptyState title="Choose a group">Pick a group to see its whole life.</EmptyState>
        : error ? <LoadError message={error} onRetry={load} /> : !s || !pl ? <Loading /> : (
        <>
          <p className="text-sm text-stone-600">
            <Link className="text-amber-800 hover:underline" href={`/livestock-groups/${s.groupId}`}>{s.name}</Link> · {s.speciesName} · started {fmtDate(s.startDate)}
            {s.closedDate ? ` · closed ${fmtDate(s.closedDate)}` : ""} · {fmtNum(s.lifeDays)} days
          </p>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard label="Animals now" value={fmtNum(s.head)} tone="amber" />
            <StatCard label="Profit" value={fmtMoney(pl.profit)} tone={pl.profit < 0 ? "rose" : "stone"} />
            <StatCard label="Feed used (kg)" value={fmtNum(s.feedKg)} />
            <StatCard label="Latest average weight" value={s.latestWeightKg != null ? `${s.latestWeightKg} kg` : "—"} />
            {s.eggs != null && <StatCard label="Eggs" value={fmtNum(s.eggs)} />}
            {s.milk != null && <StatCard label="Milk (L)" value={fmtNum(s.milk)} />}
            <StatCard label="Daily records" value={fmtNum(s.records)} />
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Animals in and out</CardTitle></CardHeader>
              <CardContent className="text-sm divide-y">
                {Object.entries(s.movements).map(([k, n]) => (
                  <div key={k} className="flex justify-between py-1.5"><span>{(MOVEMENT_LABEL as Record<string, string>)[k] ?? k}</span><span>{fmtNum(n)}</span></div>
                ))}
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Money</CardTitle></CardHeader>
              <CardContent className="text-sm divide-y">
                {([
                  ["Animals sold", pl.income.animals], ["Produce sold", pl.income.produce], ["Other sales", pl.income.otherStock],
                  ["Animals bought", -pl.costs.animalsBought], ["Feed", -pl.costs.feed], ["Medicine", -pl.costs.medicine],
                  ["Other stock used", -pl.costs.otherStock], ["Stock sold (cost)", -pl.costs.stockSold], ["Expenses", -pl.costs.expensesTotal],
                ] as [string, number][]).filter(([, v]) => v).map(([k, v]) => (
                  <div key={k} className="flex justify-between py-1.5"><span>{k}</span><span className={v < 0 ? "text-rose-700" : "text-emerald-700"}>{fmtMoney(v)}</span></div>
                ))}
                <div className="flex justify-between py-1.5 font-semibold"><span>Profit</span><span>{fmtMoney(pl.profit)}</span></div>
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </LivestockPage>
  )
}

"use client"

// Daily Records -- the poultry Production Records page for livestock: each
// group's day, newest first, with deaths, produce and what was fed.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { ClipboardList, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listGroups, listProductionRecords, type LivestockGroup, type ProductionRecord } from "@/lib/api/livestock"
import { useLivestockFeatures } from "@/hooks/use-livestock-species"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum, todayIso,
} from "@/components/livestock/livestock-page"

const ALL = "__all"
const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return d.toISOString().slice(0, 10) }

export default function LivestockProductionRecordsPage() {
  const router = useRouter()
  const features = useLivestockFeatures()
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [records, setRecords] = useState<ProductionRecord[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [groupId, setGroupId] = useState(ALL)
  const [from, setFrom] = useState(daysAgo(30))
  const [to, setTo] = useState(todayIso())

  useEffect(() => { listGroups(true).then(setGroups).catch(() => setGroups([])) }, [])
  const load = useCallback(async () => {
    setError(null)
    try {
      setRecords(await listProductionRecords({ groupId: groupId === ALL ? undefined : Number(groupId), from, to }))
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [groupId, from, to])
  useEffect(() => { load() }, [load])

  const totals = useMemo(() => {
    const rs = records ?? []
    return {
      deaths: rs.reduce((s, r) => s + r.deaths + r.culls, 0),
      eggs: rs.reduce((s, r) => s + (r.eggsCollected ?? 0), 0),
      milk: rs.reduce((s, r) => s + (r.milkLitres ?? 0), 0),
      cost: rs.reduce((s, r) => s + r.feedCost + r.medicationCost, 0),
    }
  }, [records])

  // Groups with no record today, so the morning's work is one click away.
  const missingToday = useMemo(() => {
    const done = new Set((records ?? []).filter((r) => r.date === todayIso()).map((r) => r.groupId))
    return groups.filter((g) => g.status === "Active" && !done.has(g.groupId))
  }, [groups, records])

  return (
    <LivestockPage
      title="Daily records"
      description="Each group's day: deaths, produce, and the feed and medicine used."
      icon={ClipboardList}
      actions={<Button asChild className={AMBER_BUTTON}><Link href="/livestock-production-records/new"><Plus className="h-4 w-4 mr-1" /> New record</Link></Button>}
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <StatCard label="Deaths & culls" value={fmtNum(totals.deaths)} tone={totals.deaths ? "rose" : "stone"} />
        {features.eggs && <StatCard label="Eggs collected" value={fmtNum(totals.eggs)} />}
        {features.milk && <StatCard label="Milk (litres)" value={fmtNum(Math.round(totals.milk * 10) / 10)} />}
        <StatCard label="Feed & medicine cost" value={fmtMoney(totals.cost)} tone="amber" />
      </div>

      {to === todayIso() && missingToday.length > 0 && (
        <div className="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          No record yet today for{" "}
          {missingToday.map((g, i) => (
            <span key={g.groupId}>{i > 0 && ", "}
              <Link className="underline font-medium" href={`/livestock-production-records/new?groupId=${g.groupId}`}>{g.name}</Link>
            </span>
          ))}.
        </div>
      )}

      <div className="flex items-center gap-3 flex-wrap">
        <Select value={groupId} onValueChange={setGroupId}>
          <SelectTrigger className="w-52"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All groups</SelectItem>
            {groups.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name}</SelectItem>)}
          </SelectContent>
        </Select>
        <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
        <span className="text-stone-500 text-sm">to</span>
        <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !records ? <Loading /> : records.length === 0 ? (
        <EmptyState title="No records in these dates">Record each group's day: deaths, eggs or milk, and the feed it ate.</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead>
                <TableHead>Group</TableHead>
                <TableHead className="text-right">Animals</TableHead>
                <TableHead className="text-right">Died</TableHead>
                <TableHead className="text-right">Culled</TableHead>
                {features.eggs && <TableHead className="text-right">Eggs</TableHead>}
                {features.milk && <TableHead className="text-right">Milk (L)</TableHead>}
                <TableHead className="text-right">Feed</TableHead>
                <TableHead className="text-right">Cost</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {records.map((r) => (
                <TableRow key={r.recordId} className="cursor-pointer hover:bg-amber-50/60" onClick={() => router.push(`/livestock-production-records/${r.recordId}`)}>
                  <TableCell className="whitespace-nowrap">{fmtDate(r.date)}</TableCell>
                  <TableCell className="font-medium">{r.groupName}<div className="text-xs text-stone-500">{r.speciesName}</div></TableCell>
                  <TableCell className="text-right">{fmtNum(r.headEndOfDay)}</TableCell>
                  <TableCell className={`text-right ${r.deaths ? "text-rose-700" : ""}`}>{fmtNum(r.deaths)}</TableCell>
                  <TableCell className="text-right">{fmtNum(r.culls)}</TableCell>
                  {features.eggs && <TableCell className="text-right">{r.eggsCollected == null ? "—" : fmtNum(r.eggsCollected)}</TableCell>}
                  {features.milk && <TableCell className="text-right">{r.milkLitres == null ? "—" : fmtNum(r.milkLitres)}</TableCell>}
                  <TableCell className="text-right">{r.feedKg != null ? `${fmtNum(r.feedKg)} kg` : r.feedQuantity ? fmtNum(r.feedQuantity) : "—"}</TableCell>
                  <TableCell className="text-right">{fmtMoney(r.feedCost + r.medicationCost)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </LivestockPage>
  )
}

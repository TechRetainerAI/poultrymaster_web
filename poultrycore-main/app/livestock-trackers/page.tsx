"use client"

// Monthly trackers -- the poultry trackers for livestock: a month as a grid of
// days down and groups across, for deaths, eggs, milk, feed or head count.
// Egg and milk tabs only show when the farm keeps an animal that gives them.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { CalendarDays } from "lucide-react"
import { Input } from "@/components/ui/input"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { getTracker, type Tracker, type TrackerKind } from "@/lib/api/livestock"
import { useLivestockFeatures } from "@/hooks/use-livestock-species"
import { EmptyState, LivestockPage, LoadError, Loading, fmtNum, todayIso } from "@/components/livestock/livestock-page"

const KINDS: { kind: TrackerKind; label: string; needs?: "eggs" | "milk" }[] = [
  { kind: "Deaths", label: "Deaths" },
  { kind: "Eggs", label: "Eggs", needs: "eggs" },
  { kind: "Milk", label: "Milk (L)", needs: "milk" },
  { kind: "Feed", label: "Feed (kg)" },
  { kind: "Head", label: "Animals" },
]

export default function LivestockTrackersPage() {
  const features = useLivestockFeatures()
  const kinds = KINDS.filter((k) => !k.needs || features[k.needs])
  const [kind, setKind] = useState<TrackerKind>("Deaths")
  const [month, setMonth] = useState(todayIso().slice(0, 7))
  const [t, setT] = useState<Tracker | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setError(null); setT(null)
    try { setT(await getTracker(`${month}-01`, kind)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [month, kind])
  useEffect(() => { load() }, [load])

  // Head is a level, not a flow: its total is the last day, not the sum.
  const totals = useMemo(() => {
    if (!t) return {}
    const out: Record<string, number> = {}
    for (const g of t.groups) {
      const k = String(g.groupId)
      out[k] = kind === "Head"
        ? (t.days.length ? t.days[t.days.length - 1].values[k] ?? 0 : 0)
        : t.days.reduce((s, d) => s + (d.values[k] ?? 0), 0)
    }
    return out
  }, [t, kind])

  return (
    <LivestockPage title="Monthly trackers" description="A month at a glance, day by day for each group." icon={CalendarDays}>
      <div className="flex gap-2 flex-wrap items-center">
        <Tabs value={kind} onValueChange={(v) => setKind(v as TrackerKind)}>
          <TabsList>{kinds.map((k) => <TabsTrigger key={k.kind} value={k.kind}>{k.label}</TabsTrigger>)}</TabsList>
        </Tabs>
        <Input type="month" className="w-44" value={month} max={todayIso().slice(0, 7)} onChange={(e) => e.target.value && setMonth(e.target.value)} aria-label="Month" />
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !t ? <Loading /> : t.groups.length === 0 ? (
        <EmptyState title="No groups this month">No group had animals in this month{kind === "Eggs" ? " that lay eggs" : kind === "Milk" ? " that give milk" : ""}.</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="sticky left-0 bg-white">Day</TableHead>
                {t.groups.map((g) => <TableHead key={g.groupId} className="text-right whitespace-nowrap"><Link className="hover:underline" href={`/livestock-groups/${g.groupId}`}>{g.name}</Link></TableHead>)}
                {kind !== "Head" && <TableHead className="text-right">Farm</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {t.days.map((d) => {
                const rowTotal = Object.values(d.values).reduce((s, v) => s + v, 0)
                return (
                  <TableRow key={d.date}>
                    <TableCell className="sticky left-0 bg-white whitespace-nowrap">{new Date(d.date + "T00:00:00").toLocaleDateString(undefined, { weekday: "short", day: "2-digit" })}</TableCell>
                    {t.groups.map((g) => {
                      const v = d.values[String(g.groupId)]
                      return <TableCell key={g.groupId} className={`text-right ${kind === "Deaths" && v ? "text-rose-700 font-medium" : ""}`}>{v != null ? fmtNum(v) : ""}</TableCell>
                    })}
                    {kind !== "Head" && <TableCell className="text-right font-medium">{rowTotal ? fmtNum(Math.round(rowTotal * 10) / 10) : ""}</TableCell>}
                  </TableRow>
                )
              })}
              <TableRow className="bg-stone-50 font-semibold">
                <TableCell className="sticky left-0 bg-stone-50">{kind === "Head" ? "Month end" : "Month"}</TableCell>
                {t.groups.map((g) => <TableCell key={g.groupId} className="text-right">{fmtNum(Math.round((totals[String(g.groupId)] ?? 0) * 10) / 10)}</TableCell>)}
                {kind !== "Head" && <TableCell className="text-right">{fmtNum(Math.round(Object.values(totals).reduce((s, v) => s + v, 0) * 10) / 10)}</TableCell>}
              </TableRow>
            </TableBody>
          </Table>
        </div>
      )}
    </LivestockPage>
  )
}

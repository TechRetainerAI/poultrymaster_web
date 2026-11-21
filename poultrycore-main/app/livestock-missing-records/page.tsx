"use client"

// Missing Records -- the poultry Missing Activity check for livestock: days
// each group with animals has no daily record, with a link to fill each one.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { CalendarX } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { getMissingRecords, type MissingRecords } from "@/lib/api/livestock"
import { PeriodPicker, daysAgo } from "@/components/livestock/money-bits"
import { EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtNum, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockMissingRecordsPage() {
  const [from, setFrom] = useState(daysAgo(13))
  const [to, setTo] = useState(todayIso())
  const [rows, setRows] = useState<MissingRecords[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setError(null); setRows(null)
    try { setRows(await getMissingRecords(from, to)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [from, to])
  useEffect(() => { load() }, [load])
  const total = (rows ?? []).reduce((s, r) => s + r.missing, 0)

  return (
    <LivestockPage title="Missing records" description="Days a group with animals has no daily record." icon={CalendarX}>
      <PeriodPicker from={from} to={to} onChange={(a, b) => { setFrom(a); setTo(b) }} />
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? (
        <EmptyState title="Nothing missing">Every group has a record for every day in these dates.</EmptyState>
      ) : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
            <StatCard label="Days missing" value={fmtNum(total)} tone="rose" />
            <StatCard label="Groups behind" value={fmtNum(rows.length)} />
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
            {rows.map((r) => (
              <Card key={r.groupId}>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base"><Link className="hover:underline" href={`/livestock-groups/${r.groupId}`}>{r.name}</Link> <span className="text-sm font-normal text-stone-500">{r.speciesName} · {r.missing} day(s) · last record {fmtDate(r.lastRecord)}</span></CardTitle>
                </CardHeader>
                <CardContent className="flex flex-wrap gap-1.5">
                  {r.days.slice(0, 31).map((d) => (
                    <Link key={d} href={`/livestock-production-records/new?groupId=${r.groupId}&date=${d.slice(0, 10)}`}
                      className="rounded border border-rose-200 bg-rose-50 px-2 py-0.5 text-xs text-rose-800 hover:bg-rose-100">
                      {new Date(d.slice(0, 10) + "T00:00:00").toLocaleDateString(undefined, { day: "2-digit", month: "short" })}
                    </Link>
                  ))}
                </CardContent>
              </Card>
            ))}
          </div>
        </>
      )}
    </LivestockPage>
  )
}

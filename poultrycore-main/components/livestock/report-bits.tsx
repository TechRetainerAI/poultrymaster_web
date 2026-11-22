"use client"

// Shared pieces for the livestock report pages: a period-driven loader and a
// plain table that takes column definitions.

import { useCallback, useEffect, useState, type ReactNode } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { firstOfMonth } from "@/components/livestock/money-bits"
import { todayIso } from "@/components/livestock/livestock-page"

/** Loads a report for a date range; reloads when the range changes. */
export function usePeriodReport<T>(fetcher: (from: string, to: string) => Promise<T>, deps: unknown[] = []) {
  const [from, setFrom] = useState(firstOfMonth())
  const [to, setTo] = useState(todayIso())
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setError(null); setData(null)
    try { setData(await fetcher(from, to)) } catch (e: any) { setError(e?.message ?? String(e)) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [from, to, ...deps])
  useEffect(() => { load() }, [load])
  return { from, to, setPeriod: (a: string, b: string) => { setFrom(a); setTo(b) }, data, error, load }
}

export interface Col<R> { label: string; cell: (r: R) => ReactNode; right?: boolean }

export function ReportTable<R>({ title, rows, cols, rowKey, empty = "Nothing in these dates." }: {
  title?: string; rows: R[]; cols: Col<R>[]; rowKey: (r: R, i: number) => string | number; empty?: string
}) {
  const body = rows.length === 0 ? <p className="text-sm text-stone-500">{empty}</p> : (
    <div className="overflow-x-auto">
      <Table>
        <TableHeader><TableRow>{cols.map((c) => <TableHead key={c.label} className={c.right ? "text-right" : undefined}>{c.label}</TableHead>)}</TableRow></TableHeader>
        <TableBody>
          {rows.map((r, i) => (
            <TableRow key={rowKey(r, i)}>
              {cols.map((c) => <TableCell key={c.label} className={c.right ? "text-right" : undefined}>{c.cell(r)}</TableCell>)}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
  if (!title) return <div className="rounded-md border bg-white p-3">{body}</div>
  return (
    <Card>
      <CardHeader className="pb-2"><CardTitle className="text-base">{title}</CardTitle></CardHeader>
      <CardContent>{body}</CardContent>
    </Card>
  )
}

export const pct = (n: number | null | undefined) => (n == null ? "—" : `${n}%`)
export const REPORTS_BACK = { href: "/livestock/reports", label: "All reports" }

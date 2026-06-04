"use client"

/** Route Performance Report (Prompt 2 §16.13). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterVehicleLoadings, listWaterDriverReturns, listWaterRoutes } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

type Row = {
  routeId: number
  routeName: string
  runs: number
  sold: number
  cash: number
  shortage: number
}

export default function RoutePerformanceReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<Row[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [loadings, returns, routes] = await Promise.all([
        listWaterVehicleLoadings({ fromDate, toDate }),
        listWaterDriverReturns({ fromDate, toDate }),
        listWaterRoutes().catch(() => []),
      ])
      const map = new Map<number, Row>()
      for (const r of routes ?? []) {
        map.set(r.waterRouteId, { routeId: r.waterRouteId, routeName: r.routeName, runs: 0, sold: 0, cash: 0, shortage: 0 })
      }
      for (const l of loadings ?? []) {
        if (l.waterRouteId == null) continue
        const row = map.get(l.waterRouteId); if (!row) continue
        row.runs += 1
      }
      for (const ret of returns ?? []) {
        const parent = (loadings ?? []).find((l: any) => l.waterVehicleLoadingId === ret.waterVehicleLoadingId)
        if (!parent?.waterRouteId) continue
        const row = map.get(parent.waterRouteId); if (!row) continue
        row.sold += (ret.bagsSold ?? 0)
        row.cash += (ret.cashCollected ?? 0) + (ret.moMoCollected ?? 0) + (ret.bankCollected ?? 0)
        row.shortage += (ret.shortageAmount ?? 0)
      }
      setRows(Array.from(map.values()).filter(r => r.runs > 0).sort((a, b) => b.cash - a.cash))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    routes: rows.length,
    runs: rows.reduce((s, r) => s + r.runs, 0),
    cash: rows.reduce((s, r) => s + r.cash, 0),
  }), [rows])

  return (
    <ReportShell
      title="Route Performance"
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      summary={<>
        <SumTile label="Active routes" value={String(totals.routes)} />
        <SumTile label="Total runs" value={totals.runs.toLocaleString()} />
        <SumTile label="Total cash" value={fmtMoney(totals.cash)} accent="green" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Route</TableHead>
              <TableHead className="text-right">Runs</TableHead>
              <TableHead className="text-right">Bags sold</TableHead>
              <TableHead className="text-right">Cash</TableHead>
              <TableHead className="text-right">Shortage</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={5} className="text-slate-500 text-center p-4">No route activity in this period.</TableCell></TableRow>
            ) : rows.map((r) => (
              <TableRow key={r.routeId}>
                <TableCell className="font-medium">{r.routeName}</TableCell>
                <TableCell className="text-right tabular-nums">{r.runs}</TableCell>
                <TableCell className="text-right tabular-nums">{r.sold.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.cash)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${r.shortage > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.shortage)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

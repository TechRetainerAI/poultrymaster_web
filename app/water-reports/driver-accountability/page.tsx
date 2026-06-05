"use client"

/** Driver Accountability Report (Prompt 2 §16.12). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterVehicleLoadings, listWaterDriverReturns, listWaterDrivers } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

type Row = {
  driverId: number
  driverName: string
  runs: number
  loaded: number
  sold: number
  returned: number
  damaged: number
  cash: number
  shortage: number
}

export default function DriverAccountabilityReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<Row[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [loadings, returns, drivers] = await Promise.all([
        listWaterVehicleLoadings({ fromDate, toDate }),
        listWaterDriverReturns({ fromDate, toDate }),
        listWaterDrivers().catch(() => []),
      ])

      const map = new Map<number, Row>()
      for (const d of drivers ?? []) {
        map.set(d.waterDriverId, {
          driverId: d.waterDriverId, driverName: d.driverName,
          runs: 0, loaded: 0, sold: 0, returned: 0, damaged: 0, cash: 0, shortage: 0,
        })
      }
      for (const l of loadings ?? []) {
        if (l.waterDriverId == null) continue
        const r = map.get(l.waterDriverId)
        if (!r) continue
        r.runs += 1
        r.loaded += (l.bagsLoaded ?? 0)
      }
      for (const ret of returns ?? []) {
        const parent = (loadings ?? []).find((l: any) => l.waterVehicleLoadingId === ret.waterVehicleLoadingId)
        if (!parent || parent.waterDriverId == null) continue
        const r = map.get(parent.waterDriverId)
        if (!r) continue
        r.sold += (ret.bagsSold ?? 0)
        r.returned += (ret.bagsReturned ?? 0)
        r.damaged += (ret.bagsDamaged ?? 0)
        r.cash += (ret.cashCollected ?? 0) + (ret.moMoCollected ?? 0) + (ret.bankCollected ?? 0)
        r.shortage += (ret.shortageAmount ?? 0)
      }

      setRows(Array.from(map.values())
        .filter(r => r.runs > 0)
        .sort((a, b) => b.runs - a.runs))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    drivers: rows.length,
    runs: rows.reduce((s, r) => s + r.runs, 0),
    cash: rows.reduce((s, r) => s + r.cash, 0),
    shortage: rows.reduce((s, r) => s + r.shortage, 0),
  }), [rows])

  return (
    <ReportShell
      title="Driver Accountability"
      description="Per-driver runs, loads, sales, damages, shortages."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      summary={<>
        <SumTile label="Active drivers" value={String(totals.drivers)} />
        <SumTile label="Total runs" value={totals.runs.toLocaleString()} />
        <SumTile label="Cash collected" value={fmtMoney(totals.cash)} accent="green" />
        <SumTile label="Total shortages" value={fmtMoney(totals.shortage)} accent="rose" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Driver</TableHead>
              <TableHead className="text-right">Runs</TableHead>
              <TableHead className="text-right">Loaded</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Returned</TableHead>
              <TableHead className="text-right">Damaged</TableHead>
              <TableHead className="text-right">Cash collected</TableHead>
              <TableHead className="text-right">Shortage</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-slate-500 text-center p-4">No driver activity in this period.</TableCell></TableRow>
            ) : rows.map((r) => (
              <TableRow key={r.driverId}>
                <TableCell className="font-medium">{r.driverName}</TableCell>
                <TableCell className="text-right tabular-nums">{r.runs}</TableCell>
                <TableCell className="text-right tabular-nums">{r.loaded.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{r.sold.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{r.returned.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{r.damaged.toLocaleString()}</TableCell>
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

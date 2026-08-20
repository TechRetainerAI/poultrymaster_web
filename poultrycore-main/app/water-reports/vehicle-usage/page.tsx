"use client"

/** Vehicle Usage Report (Prompt 2 §16.14). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listWaterVehicleLoadings, listWaterDriverReturns, listWaterVehicles } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

type Row = {
  vehicleId: number
  vehicleName: string
  vehicleType: string
  runs: number
  loaded: number
  sold: number
  damaged: number
  shortage: number
}

export default function VehicleUsageReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<Row[]>([])
  const pg = usePagination(rows)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [loadings, returns, vehicles] = await Promise.all([
        listWaterVehicleLoadings({ fromDate, toDate }),
        listWaterDriverReturns({ fromDate, toDate }),
        listWaterVehicles().catch(() => []),
      ])
      const map = new Map<number, Row>()
      for (const v of vehicles ?? []) {
        map.set(v.waterVehicleId, {
          vehicleId: v.waterVehicleId, vehicleName: v.vehicleName, vehicleType: v.vehicleType,
          runs: 0, loaded: 0, sold: 0, damaged: 0, shortage: 0,
        })
      }
      for (const l of loadings ?? []) {
        const row = map.get(l.waterVehicleId); if (!row) continue
        row.runs += 1
        row.loaded += (l.bagsLoaded ?? 0)
      }
      for (const ret of returns ?? []) {
        const parent = (loadings ?? []).find((l: any) => l.waterVehicleLoadingId === ret.waterVehicleLoadingId)
        if (!parent) continue
        const row = map.get(parent.waterVehicleId); if (!row) continue
        row.sold += (ret.bagsSold ?? 0)
        row.damaged += (ret.bagsDamaged ?? 0)
        row.shortage += (ret.shortageAmount ?? 0)
      }
      setRows(Array.from(map.values()).filter(r => r.runs > 0).sort((a, b) => b.runs - a.runs))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    vehicles: rows.length,
    runs: rows.reduce((s, r) => s + r.runs, 0),
    loaded: rows.reduce((s, r) => s + r.loaded, 0),
  }), [rows])

  return (
    <ReportShell
      title="Vehicle Usage"
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Vehicle Usage",
        filename: "water-vehicle-usage",
        summaryLines: [
          `Active vehicles: ${totals.vehicles}`,
          `Total runs: ${totals.runs.toLocaleString()}`,
          `Total loaded: ${totals.loaded.toLocaleString()}`,
        ],
        columns: [
          { header: "Vehicle" },
          { header: "Type" },
          { header: "Runs", align: "right" },
          { header: "Loaded", align: "right" },
          { header: "Sold", align: "right" },
          { header: "Damaged", align: "right" },
          { header: "Shortage", align: "right" },
        ],
        rows: rows.map((r) => [
          r.vehicleName,
          r.vehicleType,
          r.runs,
          r.loaded.toLocaleString(),
          r.sold.toLocaleString(),
          r.damaged.toLocaleString(),
          fmtMoney(r.shortage),
        ]),
      }}
      summary={<>
        <SumTile label="Active vehicles" value={String(totals.vehicles)} />
        <SumTile label="Total runs" value={totals.runs.toLocaleString()} />
        <SumTile label="Total loaded" value={totals.loaded.toLocaleString()} />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Vehicle</TableHead>
              <TableHead>Type</TableHead>
              <TableHead className="text-right">Runs</TableHead>
              <TableHead className="text-right">Loaded</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Damaged</TableHead>
              <TableHead className="text-right">Shortage</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={7} className="text-slate-500 text-center p-4">No vehicle activity in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={r.vehicleId}>
                <TableCell className="font-medium">{r.vehicleName}</TableCell>
                <TableCell>{r.vehicleType}</TableCell>
                <TableCell className="text-right tabular-nums">{r.runs}</TableCell>
                <TableCell className="text-right tabular-nums">{r.loaded.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{r.sold.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{r.damaged.toLocaleString()}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${r.shortage > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.shortage)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />
    </ReportShell>
  )
}

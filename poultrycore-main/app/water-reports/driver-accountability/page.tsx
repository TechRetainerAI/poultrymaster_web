"use client"

/** Driver Accountability Report (Prompt 2 §16.12). Data is the authoritative
 *  server-side report SP (spWaterReport_DriverReconciliation) so the on-screen
 *  table matches the emailed PDF. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { getWaterDriverReconciliation, type WaterDriverReconciliationRow } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function DriverAccountabilityReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<WaterDriverReconciliationRow[]>([])
  const pg = usePagination(rows)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try { setRows((await getWaterDriverReconciliation(fromDate, toDate)) ?? []) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    drivers: rows.length,
    expected: rows.reduce((s, r) => s + (r.expectedRevenue ?? 0), 0),
    accounted: rows.reduce((s, r) => s + (r.actualAccountedFor ?? 0), 0),
    shortages: rows.reduce((s, r) => s + (r.totalShortages ?? 0), 0),
  }), [rows])

  return (
    <ReportShell
      title="Driver Accountability"
      description="Per-driver bags loaded/sold/returned, expected vs accounted revenue, and shortages."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Driver Accountability",
        filename: "water-driver-accountability",
        orientation: "landscape",
        summaryLines: [
          `Drivers: ${totals.drivers}`,
          `Expected revenue: ${fmtMoney(totals.expected)}`,
          `Accounted for: ${fmtMoney(totals.accounted)}`,
          `Total shortages: ${fmtMoney(totals.shortages)}`,
        ],
        columns: [
          { header: "Driver" }, { header: "Loaded", align: "right" }, { header: "Sold", align: "right" },
          { header: "Returned", align: "right" }, { header: "Lost", align: "right" },
          { header: "Expected", align: "right" }, { header: "Accounted", align: "right" },
          { header: "Shortages", align: "right" }, { header: "Occurrences", align: "right" },
        ],
        rows: rows.map((r) => [
          r.driverName,
          (r.totalBagsLoaded ?? 0).toLocaleString(), (r.totalBagsSold ?? 0).toLocaleString(),
          (r.totalBagsReturned ?? 0).toLocaleString(), (r.totalBagsLost ?? 0).toLocaleString(),
          fmtMoney(r.expectedRevenue ?? 0), fmtMoney(r.actualAccountedFor ?? 0),
          fmtMoney(r.totalShortages ?? 0), r.shortageOccurrences ?? 0,
        ]),
      }}
      summary={<>
        <SumTile label="Drivers" value={String(totals.drivers)} />
        <SumTile label="Expected revenue" value={fmtMoney(totals.expected)} />
        <SumTile label="Accounted for" value={fmtMoney(totals.accounted)} accent="green" />
        <SumTile label="Total shortages" value={fmtMoney(totals.shortages)} accent="rose" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Driver</TableHead>
              <TableHead className="text-right">Loaded</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Returned</TableHead>
              <TableHead className="text-right">Lost</TableHead>
              <TableHead className="text-right">Expected</TableHead>
              <TableHead className="text-right">Accounted</TableHead>
              <TableHead className="text-right">Shortages</TableHead>
              <TableHead className="text-right">Occurrences</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No driver activity in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={r.waterDriverId}>
                <TableCell className="font-medium">{r.driverName}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalBagsLoaded ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalBagsSold ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalBagsReturned ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalBagsLost ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.expectedRevenue ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.actualAccountedFor ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${(r.totalShortages ?? 0) > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.totalShortages ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums">{r.shortageOccurrences ?? 0}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />
    </ReportShell>
  )
}

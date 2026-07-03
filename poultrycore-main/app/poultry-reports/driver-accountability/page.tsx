"use client"

/** Poultry Driver Accountability Report. Data is the authoritative server-side
 *  report SP so the on-screen table matches the emailed PDF. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { getPoultryDriverReconciliation, type PoultryDriverReconciliationRow } from "@/lib/api/poultry-distribution"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

export default function PoultryDriverAccountabilityReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<PoultryDriverReconciliationRow[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try { setRows((await getPoultryDriverReconciliation(fromDate, toDate)) ?? []) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    drivers: rows.length,
    expected: rows.reduce((s, r) => s + (r.expectedRevenue ?? 0), 0),
    accounted: rows.reduce((s, r) => s + (r.accountedRevenue ?? 0), 0),
    shortages: rows.reduce((s, r) => s + (r.totalShortage ?? 0), 0),
  }), [rows])

  return (
    <ReportShell
      backHref="/poultry-reports"
      title="Driver Accountability"
      description="Per-driver crates loaded/sold/returned, expected vs accounted revenue, and shortages."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Driver Accountability",
        filename: "poultry-driver-accountability",
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
          { header: "Shortage", align: "right" }, { header: "Overage", align: "right" },
        ],
        rows: rows.map((r) => [
          r.driverName ?? "—",
          (r.totalCratesLoaded ?? 0).toLocaleString(), (r.totalCratesSold ?? 0).toLocaleString(),
          (r.totalCratesReturned ?? 0).toLocaleString(), (r.totalCratesLost ?? 0).toLocaleString(),
          fmtMoney(r.expectedRevenue ?? 0), fmtMoney(r.accountedRevenue ?? 0),
          fmtMoney(r.totalShortage ?? 0), fmtMoney(r.totalOverage ?? 0),
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
              <TableHead className="text-right">Shortage</TableHead>
              <TableHead className="text-right">Overage</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No driver activity in this period.</TableCell></TableRow>
            ) : rows.map((r, i) => (
              <TableRow key={r.poultryDriverId ?? `r-${i}`}>
                <TableCell className="font-medium">{r.driverName ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalCratesLoaded ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalCratesSold ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalCratesReturned ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalCratesLost ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.expectedRevenue ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.accountedRevenue ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${(r.totalShortage ?? 0) > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.totalShortage ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${(r.totalOverage ?? 0) > 0 ? "text-emerald-700" : ""}`}>{fmtMoney(r.totalOverage ?? 0)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

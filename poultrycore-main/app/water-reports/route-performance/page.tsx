"use client"

/** Route Performance Report (Prompt 2 §16.13). Data is the authoritative
 *  server-side report SP (spWaterReport_RouteProfitability) so the on-screen
 *  table matches the emailed PDF. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { getWaterRouteProfitability, type WaterRouteProfitabilityRow } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function RoutePerformanceReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<WaterRouteProfitabilityRow[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try { setRows((await getWaterRouteProfitability(fromDate, toDate)) ?? []) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    routes: rows.length,
    revenue: rows.reduce((s, r) => s + (r.totalRevenue ?? 0), 0),
    net: rows.reduce((s, r) => s + (r.netRouteIncome ?? 0), 0),
    shortages: rows.reduce((s, r) => s + (r.totalShortages ?? 0), 0),
  }), [rows])

  return (
    <ReportShell
      title="Route Performance"
      description="Per-route bags, revenue, shortages/overages and net income."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Route Performance",
        filename: "water-route-performance",
        orientation: "landscape",
        summaryLines: [
          `Routes: ${totals.routes}`,
          `Revenue: ${fmtMoney(totals.revenue)}`,
          `Net income: ${fmtMoney(totals.net)}`,
          `Shortages: ${fmtMoney(totals.shortages)}`,
        ],
        columns: [
          { header: "Route" }, { header: "Loaded", align: "right" }, { header: "Sold", align: "right" },
          { header: "Returned", align: "right" }, { header: "Lost", align: "right" },
          { header: "Revenue", align: "right" }, { header: "Shortages", align: "right" },
          { header: "Overages", align: "right" }, { header: "Net income", align: "right" },
        ],
        rows: rows.map((r) => [
          r.routeName,
          (r.totalBagsLoaded ?? 0).toLocaleString(), (r.totalBagsSold ?? 0).toLocaleString(),
          (r.totalBagsReturned ?? 0).toLocaleString(), (r.totalBagsLost ?? 0).toLocaleString(),
          fmtMoney(r.totalRevenue ?? 0), fmtMoney(r.totalShortages ?? 0),
          fmtMoney(r.totalOverages ?? 0), fmtMoney(r.netRouteIncome ?? 0),
        ]),
      }}
      summary={<>
        <SumTile label="Routes" value={String(totals.routes)} />
        <SumTile label="Revenue" value={fmtMoney(totals.revenue)} accent="green" />
        <SumTile label="Net income" value={fmtMoney(totals.net)} accent={totals.net >= 0 ? "green" : "rose"} />
        <SumTile label="Shortages" value={fmtMoney(totals.shortages)} accent="rose" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Route</TableHead>
              <TableHead className="text-right">Loaded</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Returned</TableHead>
              <TableHead className="text-right">Lost</TableHead>
              <TableHead className="text-right">Revenue</TableHead>
              <TableHead className="text-right">Shortages</TableHead>
              <TableHead className="text-right">Overages</TableHead>
              <TableHead className="text-right">Net income</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No route activity in this period.</TableCell></TableRow>
            ) : rows.map((r) => (
              <TableRow key={r.waterRouteId}>
                <TableCell className="font-medium">{r.routeName}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalBagsLoaded ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalBagsSold ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalBagsReturned ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.totalBagsLost ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.totalRevenue ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${(r.totalShortages ?? 0) > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.totalShortages ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.totalOverages ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap font-semibold ${(r.netRouteIncome ?? 0) >= 0 ? "text-green-700" : "text-rose-700"}`}>{fmtMoney(r.netRouteIncome ?? 0)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

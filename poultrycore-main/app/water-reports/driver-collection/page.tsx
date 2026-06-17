"use client"

/** Driver Collection Report (Prompt 2 #16, migration 066). Server-side report
 *  SP (spWaterReport_DriverCollection) — per-driver totals + per-driver
 *  per-product detail. The on-screen tables match the emailed PDF. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Label } from "@/components/ui/label"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import {
  getWaterDriverCollection, listWaterDrivers,
  type WaterDriverCollectionReport, type WaterDriver,
} from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function DriverCollectionReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [driverId, setDriverId] = useState<number | undefined>(undefined)
  const [drivers, setDrivers] = useState<WaterDriver[]>([])
  const [report, setReport] = useState<WaterDriverCollectionReport>({ detail: [], totals: [] })
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Driver list for the filter — loaded once.
  useEffect(() => { listWaterDrivers().then(setDrivers).catch(() => setDrivers([])) }, [])

  async function load() {
    setBusy(true); setError(null)
    try { setReport((await getWaterDriverCollection(fromDate, toDate, driverId)) ?? { detail: [], totals: [] }) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate, driverId])

  const totals = useMemo(() => ({
    drivers: report.totals.length,
    cash: report.totals.reduce((s, t) => s + (t.cashCollected ?? 0) + (t.moMoCollected ?? 0) + (t.bankCollected ?? 0), 0),
    credit: report.totals.reduce((s, t) => s + (t.creditSales ?? 0), 0),
    shortage: report.totals.reduce((s, t) => s + (t.shortage ?? 0), 0),
  }), [report])

  const driverName = driverId ? (drivers.find((d) => d.waterDriverId === driverId)?.driverName ?? `#${driverId}`) : "All drivers"

  return (
    <ReportShell
      title="Driver Collection"
      description="Per-driver cash/MoMo/bank collections, credit, shortages, plus per-product detail."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      filterSummary={{ Driver: driverName }}
      pdf={{
        // PDF uses the per-driver totals table (the per-product detail is supplementary).
        title: "Driver Collection",
        filename: "water-driver-collection",
        subtitle: `Driver: ${driverName}`,
        orientation: "landscape",
        summaryLines: [
          `Drivers: ${totals.drivers}`,
          `Collected: ${fmtMoney(totals.cash)}`,
          `Credit sales: ${fmtMoney(totals.credit)}`,
          `Shortages: ${fmtMoney(totals.shortage)}`,
        ],
        columns: [
          { header: "Driver" }, { header: "Runs", align: "right" }, { header: "Reconciled", align: "right" },
          { header: "Cash", align: "right" }, { header: "MoMo", align: "right" }, { header: "Bank", align: "right" },
          { header: "Credit", align: "right" }, { header: "Shortage", align: "right" }, { header: "Overage", align: "right" },
        ],
        rows: report.totals.map((t) => [
          t.driverName ?? "—", t.deliveryRuns ?? 0, t.reconciledRuns ?? 0,
          fmtMoney(t.cashCollected ?? 0), fmtMoney(t.moMoCollected ?? 0), fmtMoney(t.bankCollected ?? 0),
          fmtMoney(t.creditSales ?? 0), fmtMoney(t.shortage ?? 0), fmtMoney(t.overage ?? 0),
        ]),
      }}
      filters={
        <div>
          <Label className="text-xs">Driver</Label>
          <Select value={driverId ? String(driverId) : "all"} onValueChange={(v) => setDriverId(v === "all" ? undefined : Number(v))}>
            <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All drivers</SelectItem>
              {drivers.map((d) => <SelectItem key={d.waterDriverId} value={String(d.waterDriverId)}>{d.driverName}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      }
      summary={<>
        <SumTile label="Drivers" value={String(totals.drivers)} />
        <SumTile label="Collected" value={fmtMoney(totals.cash)} accent="green" />
        <SumTile label="Credit sales" value={fmtMoney(totals.credit)} />
        <SumTile label="Shortages" value={fmtMoney(totals.shortage)} accent="rose" />
      </>}
    >
      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">Totals by driver</h2>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Driver</TableHead>
              <TableHead className="text-right">Runs</TableHead>
              <TableHead className="text-right">Reconciled</TableHead>
              <TableHead className="text-right">Cash</TableHead>
              <TableHead className="text-right">MoMo</TableHead>
              <TableHead className="text-right">Bank</TableHead>
              <TableHead className="text-right">Credit</TableHead>
              <TableHead className="text-right">Shortage</TableHead>
              <TableHead className="text-right">Overage</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {report.totals.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No collections in this period.</TableCell></TableRow>
            ) : report.totals.map((t, i) => (
              <TableRow key={t.waterDriverId ?? `t-${i}`}>
                <TableCell className="font-medium">{t.driverName ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{t.deliveryRuns ?? 0}</TableCell>
                <TableCell className="text-right tabular-nums">{t.reconciledRuns ?? 0}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(t.cashCollected ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(t.moMoCollected ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(t.bankCollected ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(t.creditSales ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${(t.shortage ?? 0) > 0 ? "text-rose-700" : ""}`}>{fmtMoney(t.shortage ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(t.overage ?? 0)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mt-4 mb-2">Detail by product</h2>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Driver</TableHead>
              <TableHead>Product</TableHead>
              <TableHead className="text-right">Loaded</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Returned</TableHead>
              <TableHead className="text-right">Damaged</TableHead>
              <TableHead className="text-right">Expected cash</TableHead>
              <TableHead className="text-right">Sales value</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {report.detail.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-slate-500 text-center p-4">No detail rows.</TableCell></TableRow>
            ) : report.detail.map((d, i) => (
              <TableRow key={`${d.waterDriverId ?? "x"}-${d.waterProductId}-${i}`}>
                <TableCell className="font-medium">{d.driverName ?? "—"}</TableCell>
                <TableCell>{d.productName ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{(d.bagsLoaded ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(d.bagsSold ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(d.bagsReturned ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(d.bagsDamaged ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(d.expectedCash ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(d.salesValue ?? 0)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

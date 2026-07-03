"use client"

/** Poultry Driver Collection Report. Server-side report SP — per-driver totals
 *  + per-driver per-product detail. The on-screen tables match the emailed PDF. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Label } from "@/components/ui/label"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import {
  getPoultryDriverCollection, listPoultryDrivers,
  type PoultryDriverCollectionReport, type PoultryDriver,
} from "@/lib/api/poultry-distribution"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

export default function PoultryDriverCollectionReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [driverId, setDriverId] = useState<number | undefined>(undefined)
  const [drivers, setDrivers] = useState<PoultryDriver[]>([])
  const [report, setReport] = useState<PoultryDriverCollectionReport>({ detail: [], totals: [] })
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Driver list for the filter — loaded once.
  useEffect(() => { listPoultryDrivers().then(setDrivers).catch(() => setDrivers([])) }, [])

  async function load() {
    setBusy(true); setError(null)
    try { setReport((await getPoultryDriverCollection({ fromDate, toDate, poultryDriverId: driverId })) ?? { detail: [], totals: [] }) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate, driverId])

  const totals = useMemo(() => ({
    drivers: report.totals.length,
    collected: report.totals.reduce((s, t) => s + (t.totalCollected ?? 0), 0),
    expected: report.totals.reduce((s, t) => s + (t.totalExpected ?? 0), 0),
    shortage: report.totals.reduce((s, t) => s + (t.totalShortage ?? 0), 0),
  }), [report])

  const driverName = driverId ? (drivers.find((d) => d.poultryDriverId === driverId)?.driverName ?? `#${driverId}`) : "All drivers"

  return (
    <ReportShell
      backHref="/poultry-reports"
      title="Driver Collection"
      description="Per-driver crates loaded/sold, expected vs collected cash, shortages, plus per-product detail."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      filterSummary={{ Driver: driverName }}
      pdf={{
        // PDF uses the per-driver totals table (the per-product detail is supplementary).
        title: "Driver Collection",
        filename: "poultry-driver-collection",
        subtitle: `Driver: ${driverName}`,
        orientation: "landscape",
        summaryLines: [
          `Drivers: ${totals.drivers}`,
          `Expected: ${fmtMoney(totals.expected)}`,
          `Collected: ${fmtMoney(totals.collected)}`,
          `Shortages: ${fmtMoney(totals.shortage)}`,
        ],
        columns: [
          { header: "Driver" }, { header: "Runs", align: "right" },
          { header: "Loaded", align: "right" }, { header: "Sold", align: "right" },
          { header: "Returned", align: "right" }, { header: "Lost", align: "right" },
          { header: "Expected", align: "right" }, { header: "Collected", align: "right" }, { header: "Shortage", align: "right" },
        ],
        rows: report.totals.map((t) => [
          t.driverName ?? "—", t.deliveryRuns ?? 0,
          (t.totalCratesLoaded ?? 0).toLocaleString(), (t.totalCratesSold ?? 0).toLocaleString(),
          (t.totalCratesReturned ?? 0).toLocaleString(), (t.totalCratesLost ?? 0).toLocaleString(),
          fmtMoney(t.totalExpected ?? 0), fmtMoney(t.totalCollected ?? 0), fmtMoney(t.totalShortage ?? 0),
        ]),
      }}
      filters={
        <div>
          <Label className="text-xs">Driver</Label>
          <Select value={driverId ? String(driverId) : "all"} onValueChange={(v) => setDriverId(v === "all" ? undefined : Number(v))}>
            <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All drivers</SelectItem>
              {drivers.map((d) => <SelectItem key={d.poultryDriverId} value={String(d.poultryDriverId)}>{d.driverName}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      }
      summary={<>
        <SumTile label="Drivers" value={String(totals.drivers)} />
        <SumTile label="Collected" value={fmtMoney(totals.collected)} accent="green" />
        <SumTile label="Expected" value={fmtMoney(totals.expected)} />
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
              <TableHead className="text-right">Loaded</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Returned</TableHead>
              <TableHead className="text-right">Lost</TableHead>
              <TableHead className="text-right">Expected</TableHead>
              <TableHead className="text-right">Collected</TableHead>
              <TableHead className="text-right">Shortage</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {report.totals.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No collections in this period.</TableCell></TableRow>
            ) : report.totals.map((t, i) => (
              <TableRow key={t.poultryDriverId ?? `t-${i}`}>
                <TableCell className="font-medium">{t.driverName ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{t.deliveryRuns ?? 0}</TableCell>
                <TableCell className="text-right tabular-nums">{(t.totalCratesLoaded ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(t.totalCratesSold ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(t.totalCratesReturned ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(t.totalCratesLost ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(t.totalExpected ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(t.totalCollected ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${(t.totalShortage ?? 0) > 0 ? "text-rose-700" : ""}`}>{fmtMoney(t.totalShortage ?? 0)}</TableCell>
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
              <TableHead>Date</TableHead>
              <TableHead>Product</TableHead>
              <TableHead className="text-right">Loaded</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Returned</TableHead>
              <TableHead className="text-right">Damaged</TableHead>
              <TableHead className="text-right">Expected</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {report.detail.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-slate-500 text-center p-4">No detail rows.</TableCell></TableRow>
            ) : report.detail.map((d, i) => (
              <TableRow key={`${d.poultryDriverReturnId}-${d.productName ?? "x"}-${i}`}>
                <TableCell className="font-medium">{d.driverName ?? "—"}</TableCell>
                <TableCell className="whitespace-nowrap">{(d.returnDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{d.productName ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{(d.cratesLoaded ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(d.cratesSold ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(d.cratesReturned ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(d.cratesDamaged ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(d.expectedAmount ?? 0)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

"use client"

/** Poultry Delivery Run Report. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listPoultryVehicleLoadings, listPoultryDriverReturns } from "@/lib/api/poultry-distribution"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

export default function PoultryDeliveryRunReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [loadings, setLoadings] = useState<any[]>([])
  const [returns, setReturns] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [l, r] = await Promise.all([
        listPoultryVehicleLoadings({ fromDate, toDate }),
        listPoultryDriverReturns({ fromDate, toDate }),
      ])
      setLoadings(l ?? []); setReturns(r ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const reconciled = loadings.filter(l => l.status === "Reconciled").length
    const sold = returns.reduce((s, r) => s + (r.cratesSold ?? 0), 0)
    const returned = returns.reduce((s, r) => s + (r.cratesReturned ?? 0), 0)
    const cash = returns.reduce((s, r) => s + (r.cashCollected ?? 0) + (r.moMoCollected ?? 0) + (r.bankCollected ?? 0), 0)
    const shortage = returns.reduce((s, r) => s + (r.shortageAmount ?? 0), 0)
    return { runs: loadings.length, reconciled, sold, returned, cash, shortage }
  }, [loadings, returns])

  return (
    <ReportShell
      backHref="/poultry-reports"
      title="Delivery Run Report"
      description="Vehicle loadings + their reconciliation status."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Delivery Run Report",
        filename: "poultry-driver-delivery-run-report",
        orientation: "landscape",
        summaryLines: [
          `Runs (reconciled / total): ${totals.reconciled} / ${totals.runs}`,
          `Crates sold: ${totals.sold.toLocaleString()}`,
          `Crates returned: ${totals.returned.toLocaleString()}`,
          `Cash collected: ${fmtMoney(totals.cash)}`,
        ],
        columns: [
          { header: "Date" },
          { header: "Driver" },
          { header: "Vehicle" },
          { header: "Route" },
          { header: "Loaded", align: "right" },
          { header: "Sold", align: "right" },
          { header: "Returned", align: "right" },
          { header: "Damaged", align: "right" },
          { header: "Expected", align: "right" },
          { header: "Shortage", align: "right" },
          { header: "Status" },
        ],
        rows: loadings.map((l: any) => {
          const r = returns.find((x: any) => x.poultryVehicleLoadingId === l.poultryVehicleLoadingId)
          return [
            (l.loadDate ?? "").slice(0, 10),
            l.driverName ?? "—",
            l.vehicleName ?? "—",
            l.routeName ?? "—",
            (l.cratesLoaded ?? 0).toLocaleString(),
            (r?.cratesSold ?? 0).toLocaleString(),
            (r?.cratesReturned ?? 0).toLocaleString(),
            (r?.cratesDamaged ?? 0).toLocaleString(),
            fmtMoney(l.expectedCash ?? 0),
            fmtMoney(r?.shortageAmount ?? 0),
            l.status,
          ]
        }),
      }}
      summary={<>
        <SumTile label="Runs" value={`${totals.reconciled} / ${totals.runs}`} />
        <SumTile label="Crates sold" value={totals.sold.toLocaleString()} accent="green" />
        <SumTile label="Crates returned" value={totals.returned.toLocaleString()} />
        <SumTile label="Cash collected" value={fmtMoney(totals.cash)} accent="green" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Driver</TableHead>
              <TableHead>Vehicle</TableHead>
              <TableHead>Route</TableHead>
              <TableHead className="text-right">Loaded</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Returned</TableHead>
              <TableHead className="text-right">Damaged</TableHead>
              <TableHead className="text-right">Expected</TableHead>
              <TableHead className="text-right">Shortage</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {loadings.length === 0 ? (
              <TableRow><TableCell colSpan={11} className="text-slate-500 text-center p-4">No runs in this period.</TableCell></TableRow>
            ) : loadings.map((l: any) => {
              const r = returns.find((x: any) => x.poultryVehicleLoadingId === l.poultryVehicleLoadingId)
              return (
                <TableRow key={l.poultryVehicleLoadingId}>
                  <TableCell className="whitespace-nowrap">{(l.loadDate ?? "").slice(0, 10)}</TableCell>
                  <TableCell>{l.driverName ?? "—"}</TableCell>
                  <TableCell>{l.vehicleName ?? "—"}</TableCell>
                  <TableCell>{l.routeName ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{(l.cratesLoaded ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums">{(r?.cratesSold ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums">{(r?.cratesReturned ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums">{(r?.cratesDamaged ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(l.expectedCash ?? 0)}</TableCell>
                  <TableCell className={`text-right tabular-nums whitespace-nowrap ${(r?.shortageAmount ?? 0) > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r?.shortageAmount ?? 0)}</TableCell>
                  <TableCell>{l.status}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

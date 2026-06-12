"use client"

/** Delivery Run Report (Prompt 2 §16.11). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterVehicleLoadings, listWaterDriverReturns } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function DeliveryRunReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [loadings, setLoadings] = useState<any[]>([])
  const [returns, setReturns] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [l, r] = await Promise.all([
        listWaterVehicleLoadings({ fromDate, toDate }),
        listWaterDriverReturns({ fromDate, toDate }),
      ])
      setLoadings(l ?? []); setReturns(r ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const reconciled = loadings.filter(l => l.status === "Reconciled").length
    const sold = returns.reduce((s, r) => s + (r.bagsSold ?? 0), 0)
    const returned = returns.reduce((s, r) => s + (r.bagsReturned ?? 0), 0)
    const cash = returns.reduce((s, r) => s + (r.cashCollected ?? 0) + (r.moMoCollected ?? 0) + (r.bankCollected ?? 0), 0)
    const shortage = returns.reduce((s, r) => s + (r.shortageAmount ?? 0), 0)
    return { runs: loadings.length, reconciled, sold, returned, cash, shortage }
  }, [loadings, returns])

  return (
    <ReportShell
      title="Delivery Run Report"
      description="Vehicle loadings + their reconciliation status."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      summary={<>
        <SumTile label="Runs" value={`${totals.reconciled} / ${totals.runs}`} />
        <SumTile label="Bags sold" value={totals.sold.toLocaleString()} accent="green" />
        <SumTile label="Bags returned" value={totals.returned.toLocaleString()} />
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
              const r = returns.find((x: any) => x.waterVehicleLoadingId === l.waterVehicleLoadingId)
              return (
                <TableRow key={l.waterVehicleLoadingId}>
                  <TableCell className="whitespace-nowrap">{(l.loadDate ?? "").slice(0, 10)}</TableCell>
                  <TableCell>{l.driverName ?? "—"}</TableCell>
                  <TableCell>{l.vehicleName ?? "—"}</TableCell>
                  <TableCell>{l.routeName ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{(l.bagsLoaded ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums">{(r?.bagsSold ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums">{(r?.bagsReturned ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums">{(r?.bagsDamaged ?? 0).toLocaleString()}</TableCell>
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

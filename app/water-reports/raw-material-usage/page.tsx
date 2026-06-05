"use client"

/** Raw Material Usage Report (Prompt 2 §16.7). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterRawMaterialUsageHistory } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function RawMaterialUsageReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await listWaterRawMaterialUsageHistory({ fromDate, toDate })
      setRows(all ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const total = rows.reduce((s, r) => s + (r.totalCost ?? 0), 0)
    const qty = rows.reduce((s, r) => s + (r.quantityUsed ?? 0), 0)
    const variance = rows.reduce((s, r) => s + Math.abs(r.variance ?? 0), 0)
    return { count: rows.length, total, qty, variance }
  }, [rows])

  return (
    <ReportShell
      title="Raw Material Usage"
      description="Expected vs actual raw material consumption with variance."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      summary={<>
        <SumTile label="Usage rows" value={totals.count.toLocaleString()} />
        <SumTile label="Total quantity" value={totals.qty.toLocaleString(undefined, { maximumFractionDigits: 3 })} />
        <SumTile label="Total cost" value={fmtMoney(totals.total)} />
        <SumTile label="Abs variance" value={totals.variance.toLocaleString(undefined, { maximumFractionDigits: 3 })} accent="rose" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Batch</TableHead>
              <TableHead>Material</TableHead>
              <TableHead className="text-right">Expected</TableHead>
              <TableHead className="text-right">Actual</TableHead>
              <TableHead className="text-right">Variance</TableHead>
              <TableHead className="text-right">Unit cost</TableHead>
              <TableHead className="text-right">Total cost</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-slate-500 text-center p-4">No usage rows.</TableCell></TableRow>
            ) : rows.map((r: any) => (
              <TableRow key={r.waterRawMaterialUsageId}>
                <TableCell className="whitespace-nowrap">{(r.usedDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{r.batchNumber ?? "—"}</TableCell>
                <TableCell className="max-w-[180px] truncate">{r.itemName ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.expectedQuantityUsed ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 })}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.quantityUsed ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 })}</TableCell>
                <TableCell className={`text-right tabular-nums ${Math.abs(r.variance ?? 0) > 0 ? "text-amber-700" : ""}`}>{(r.variance ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 })}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{r.unitCost ? fmtMoney(r.unitCost) : "—"}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{r.totalCost ? fmtMoney(r.totalCost) : "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

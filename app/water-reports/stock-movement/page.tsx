"use client"

/** Stock Movement Report (Prompt 2 §16.10). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterStockTransactions } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function StockMovementReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await listWaterStockTransactions()
      setRows((all ?? []).filter((t: any) => {
        const d = (t.createdDate ?? "").slice(0, 10)
        return d >= fromDate && d <= toDate
      }))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const inflow = rows.filter(r => (r.quantity ?? 0) > 0).reduce((s, r) => s + r.quantity, 0)
    const outflow = rows.filter(r => (r.quantity ?? 0) < 0).reduce((s, r) => s + r.quantity, 0)
    return { count: rows.length, inflow, outflow, net: inflow + outflow }
  }, [rows])

  return (
    <ReportShell
      title="Stock Movement"
      description="Inventory transactions for finished products in the selected period."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      summary={<>
        <SumTile label="Movements" value={totals.count.toLocaleString()} />
        <SumTile label="In" value={totals.inflow.toLocaleString()} accent="green" />
        <SumTile label="Out" value={Math.abs(totals.outflow).toLocaleString()} accent="rose" />
        <SumTile label="Net change" value={totals.net.toLocaleString()} accent={totals.net >= 0 ? "green" : "rose"} />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Product</TableHead>
              <TableHead>Type</TableHead>
              <TableHead className="text-right">Quantity</TableHead>
              <TableHead className="text-right">Unit cost</TableHead>
              <TableHead>Note</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={6} className="text-slate-500 text-center p-4">No stock movements in this period.</TableCell></TableRow>
            ) : rows.map((r: any) => (
              <TableRow key={r.stockTxnId}>
                <TableCell className="whitespace-nowrap">{(r.createdDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{r.productName ?? `#${r.waterProductId}`}</TableCell>
                <TableCell>{r.txnType ?? "—"}</TableCell>
                <TableCell className={`text-right tabular-nums ${r.quantity < 0 ? "text-rose-700" : "text-emerald-700"}`}>{r.quantity.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{r.unitCost != null ? fmtMoney(r.unitCost) : "—"}</TableCell>
                <TableCell className="max-w-[260px] truncate">{r.note ?? "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

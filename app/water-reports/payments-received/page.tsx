"use client"

/** Payments Received Report (Prompt 2 §16.4). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterPayments } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function PaymentsReceivedReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await listWaterPayments()
      setRows((all ?? []).filter((p: any) => {
        const d = (p.paymentDate ?? "").slice(0, 10)
        return d >= fromDate && d <= toDate
      }))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const total = rows.reduce((s, r) => s + (r.amount ?? 0), 0)
    const byMethod: Record<string, number> = {}
    for (const r of rows) byMethod[r.paymentMethod ?? "Other"] = (byMethod[r.paymentMethod ?? "Other"] ?? 0) + (r.amount ?? 0)
    return { total, byMethod }
  }, [rows])

  return (
    <ReportShell
      title="Payments Received"
      description="Customer collections by date, method and source."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      summary={<>
        <SumTile label="Payments count" value={rows.length.toLocaleString()} />
        <SumTile label="Total collected" value={fmtMoney(totals.total)} accent="green" />
        <SumTile label="Methods used" value={String(Object.keys(totals.byMethod).length)} />
      </>}
    >
      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">By method</h2>
      <Table>
        <TableHeader><TableRow><TableHead>Method</TableHead><TableHead className="text-right">Total</TableHead></TableRow></TableHeader>
        <TableBody>
          {Object.entries(totals.byMethod).length === 0 ? (
            <TableRow><TableCell colSpan={2} className="text-slate-500 text-center p-4">No payments.</TableCell></TableRow>
          ) : Object.entries(totals.byMethod).sort(([, a], [, b]) => b - a).map(([m, v]) => (
            <TableRow key={m}><TableCell>{m}</TableCell><TableCell className="text-right tabular-nums">{fmtMoney(v)}</TableCell></TableRow>
          ))}
        </TableBody>
      </Table>

      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mt-4 mb-2">Details</h2>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Sale #</TableHead>
              <TableHead>Customer</TableHead>
              <TableHead>Method</TableHead>
              <TableHead>Reference</TableHead>
              <TableHead className="text-right">Amount</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={6} className="text-slate-500 text-center p-4">No payments in this period.</TableCell></TableRow>
            ) : rows.map((r: any) => (
              <TableRow key={r.waterPaymentId}>
                <TableCell className="whitespace-nowrap">{(r.paymentDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{r.waterSaleId ?? "—"}</TableCell>
                <TableCell>{r.customerName ?? r.waterCustomerId ?? "—"}</TableCell>
                <TableCell>{r.paymentMethod ?? "—"}</TableCell>
                <TableCell className="max-w-[240px] truncate">{r.reference ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(r.amount ?? 0)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

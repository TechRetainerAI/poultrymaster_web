"use client"

/**
 * Payments Received Report (Prompt 2 §16.4).
 *
 * ONE ROW PER PAYMENT. This read `waterpayments` directly, and that table holds
 * one row per SALE — so a customer who settled three invoices with one transfer
 * appeared here three times and "Payments count" counted invoices, not
 * payments. Migration 227 groups those rows under a paymentgroupid; this report
 * reads the grouped view, and says how many sales each payment covered.
 */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile, ReportTableCards } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listPayments, type PaymentHistoryRow } from "@/lib/api/balances"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function PaymentsReceivedReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<PaymentHistoryRow[]>([])
  // Paging for the payment detail list. The by-method roll-up above it has one
  // row per payment method, so it stays whole.
  const pg = usePagination(rows)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      // Reversed payments are money that never stayed, so a "collections"
      // report leaves them out rather than quietly netting them off.
      const all = await listPayments("water", "customer", { from: fromDate, to: toDate })
      setRows((all ?? []).filter((r) => (r.status ?? "Posted") !== "Reversed"))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const total = rows.reduce((s, r) => s + (Number(r.totalAmount) || 0), 0)
    const byMethod: Record<string, number> = {}
    for (const r of rows) {
      const k = r.paymentMethod ?? "Other"
      byMethod[k] = (byMethod[k] ?? 0) + (Number(r.totalAmount) || 0)
    }
    // Payments and the sales they settled are different counts the moment
    // anyone pays for more than one invoice, so the report reports both.
    const sales = rows.reduce((s, r) => s + (r.allocationCount || 0), 0)
    return { total, byMethod, sales }
  }, [rows])

  // One description of the Details table, used by the PDF and by the phone
  // scorecards alike so the two can never drift apart.
  const detailColumns = [
    { header: "Date" },
    { header: "Payment" },
    { header: "Customer" },
    { header: "Applied to" },
    { header: "Method" },
    { header: "Reference" },
    { header: "Amount", align: "right" as const },
  ]
  // A payment event has no single sale number, so the column says how many
  // sales it settled instead of naming one and hiding the rest.
  const appliedTo = (r: PaymentHistoryRow) =>
    `${r.allocationCount ?? 1} sale${(r.allocationCount ?? 1) === 1 ? "" : "s"}`
  const paymentRef = (r: PaymentHistoryRow) =>
    r.paymentNumber?.trim() || `#${String(r.paymentId).slice(0, 8)}`
  const detailRows = rows.map((r) => [
    (r.paymentDate ?? "").slice(0, 10),
    paymentRef(r),
    r.partyName ?? "—",
    appliedTo(r),
    r.paymentMethod ?? "—",
    r.reference ?? "—",
    fmtMoney(r.totalAmount ?? 0),
  ])

  return (
    <ReportShell
      title="Payments Received"
      description="Customer collections by date, method and source."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      // Primary table = the "Details" list (the "By method" table is a summary).
      // That summary is two columns and reads fine on a phone, so it stays put
      // and only the Details list becomes scorecards (below).
      mobileCards={false}
      pdf={{
        title: "Payments Received",
        filename: "water-payments-received",
        summaryLines: [
          `Payments: ${rows.length.toLocaleString()}`,
          `Total collected: ${fmtMoney(totals.total)}`,
          `Sales settled: ${totals.sales.toLocaleString()}`,
          `Methods used: ${Object.keys(totals.byMethod).length}`,
        ],
        columns: detailColumns,
        rows: detailRows,
      }}
      summary={<>
        <SumTile label="Payments" value={rows.length.toLocaleString()} />
        <SumTile label="Total collected" value={fmtMoney(totals.total)} accent="green" />
        <SumTile label="Sales settled" value={totals.sales.toLocaleString()} />
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
      <ReportTableCards columns={detailColumns} rows={detailRows}>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Payment</TableHead>
              <TableHead>Customer</TableHead>
              <TableHead>Applied to</TableHead>
              <TableHead>Method</TableHead>
              <TableHead>Reference</TableHead>
              <TableHead className="text-right">Amount</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={7} className="text-slate-500 text-center p-4">No payments in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={r.paymentId}>
                <TableCell className="whitespace-nowrap">{(r.paymentDate ?? "").slice(0, 10)}</TableCell>
                <TableCell className="whitespace-nowrap font-medium" title={r.paymentId}>{paymentRef(r)}</TableCell>
                <TableCell>{r.partyName ?? "—"}</TableCell>
                <TableCell className="whitespace-nowrap text-slate-600">{appliedTo(r)}</TableCell>
                <TableCell>{r.paymentMethod ?? "—"}</TableCell>
                <TableCell className="max-w-[240px] truncate">{r.reference ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(r.totalAmount ?? 0)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />
      </ReportTableCards>
    </ReportShell>
  )
}

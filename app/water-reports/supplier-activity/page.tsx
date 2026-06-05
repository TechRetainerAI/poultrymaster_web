"use client"

/** Supplier Activity Report — spec §10 (Supplier Report).
 *  Per-supplier purchases, expenses paid, outstanding balance, last activity. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { getWaterSupplierActivity, type WaterSupplierActivityRow } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function SupplierActivityReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate]     = useState(defaultTo())
  const [rows, setRows] = useState<WaterSupplierActivityRow[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try { setRows(await getWaterSupplierActivity({ fromDate, toDate })) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    supplierCount:     rows.length,
    activeSuppliers:   rows.filter(r => r.purchaseCount > 0 || r.expenseCount > 0).length,
    totalPurchases:    rows.reduce((s, r) => s + (r.totalPurchaseAmount ?? 0), 0),
    totalExpensesPaid: rows.reduce((s, r) => s + (r.totalExpenseAmount  ?? 0), 0),
    totalOutstanding:  rows.reduce((s, r) => s + (r.outstandingBalance  ?? 0), 0),
  }), [rows])

  return (
    <ReportShell
      title="Supplier Activity Report"
      description="Purchases, expenses paid, outstanding balances, and last activity per supplier."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      summaryTiles={
        <>
          <SumTile label="Suppliers"          value={String(totals.supplierCount)} />
          <SumTile label="Active (in range)"  value={String(totals.activeSuppliers)} />
          <SumTile label="Total purchases"    value={fmtMoney(totals.totalPurchases)} />
          <SumTile label="Total paid"         value={fmtMoney(totals.totalExpensesPaid)} />
          <SumTile label="Outstanding"        value={fmtMoney(totals.totalOutstanding)} accent="rose" />
        </>
      }
    >
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Supplier</TableHead>
            <TableHead>Type</TableHead>
            <TableHead>Phone</TableHead>
            <TableHead className="text-right">Purchases</TableHead>
            <TableHead className="text-right">Purchase total</TableHead>
            <TableHead className="text-right">Expenses paid</TableHead>
            <TableHead className="text-right">Outstanding</TableHead>
            <TableHead>Last purchase</TableHead>
            <TableHead>Last expense</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((r) => (
            <TableRow key={r.waterSupplierId}>
              <TableCell className="font-medium">{r.supplierName}</TableCell>
              <TableCell>{r.supplierType ?? "—"}</TableCell>
              <TableCell>{r.phone ?? "—"}</TableCell>
              <TableCell className="text-right tabular-nums">{r.purchaseCount}</TableCell>
              <TableCell className="text-right tabular-nums">{fmtMoney(r.totalPurchaseAmount)}</TableCell>
              <TableCell className="text-right tabular-nums">{fmtMoney(r.totalExpenseAmount)}</TableCell>
              <TableCell className={`text-right tabular-nums ${(r.outstandingBalance ?? 0) > 0 ? "text-rose-600" : ""}`}>
                {fmtMoney(r.outstandingBalance)}
              </TableCell>
              <TableCell>{r.lastPurchaseDate ? r.lastPurchaseDate.split("T")[0] : "—"}</TableCell>
              <TableCell>{r.lastExpenseDate  ? r.lastExpenseDate.split("T")[0]  : "—"}</TableCell>
            </TableRow>
          ))}
          {rows.length === 0 && !busy && (
            <TableRow>
              <TableCell colSpan={9} className="text-center text-slate-500 py-8">
                No suppliers yet. Add some from the Suppliers page or Setup &gt; Suppliers tab.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
    </ReportShell>
  )
}

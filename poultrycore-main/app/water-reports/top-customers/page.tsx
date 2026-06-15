"use client"

/** Top Customers Report. Server-side report SP (spWaterReport_TopCustomers);
 *  the on-screen table matches the emailed PDF. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Label } from "@/components/ui/label"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { getWaterTopCustomers, type WaterTopCustomerRow } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

const TOP_N_OPTIONS = [5, 10, 20, 50]

export default function TopCustomersReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [topN, setTopN] = useState(10)
  const [rows, setRows] = useState<WaterTopCustomerRow[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try { setRows((await getWaterTopCustomers(fromDate, toDate, topN)) ?? []) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate, topN])

  const totals = useMemo(() => ({
    customers: rows.length,
    sales: rows.reduce((s, r) => s + (r.totalSales ?? 0), 0),
    paid: rows.reduce((s, r) => s + (r.totalPaid ?? 0), 0),
    outstanding: rows.reduce((s, r) => s + (r.outstandingBalance ?? 0), 0),
  }), [rows])

  return (
    <ReportShell
      title="Top Customers"
      description="Highest-value customers by total sales for the period."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      filterSummary={{ "Top N": topN }}
      pdf={{
        title: "Top Customers",
        filename: "water-top-customers",
        subtitle: `Top ${topN}`,
        summaryLines: [
          `Customers: ${totals.customers}`,
          `Total sales: ${fmtMoney(totals.sales)}`,
          `Total paid: ${fmtMoney(totals.paid)}`,
          `Outstanding: ${fmtMoney(totals.outstanding)}`,
        ],
        columns: [
          { header: "Customer" }, { header: "Phone" }, { header: "Sales", align: "right" },
          { header: "Total sales", align: "right" }, { header: "Paid", align: "right" },
          { header: "Outstanding", align: "right" },
        ],
        rows: rows.map((r) => [
          r.customerName, r.phoneNumber ?? "—", (r.salesCount ?? 0).toLocaleString(),
          fmtMoney(r.totalSales ?? 0), fmtMoney(r.totalPaid ?? 0), fmtMoney(r.outstandingBalance ?? 0),
        ]),
      }}
      filters={
        <div>
          <Label className="text-xs">Show</Label>
          <Select value={String(topN)} onValueChange={(v) => setTopN(Number(v))}>
            <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
            <SelectContent>
              {TOP_N_OPTIONS.map((n) => <SelectItem key={n} value={String(n)}>Top {n}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      }
      summary={<>
        <SumTile label="Customers" value={String(totals.customers)} />
        <SumTile label="Total sales" value={fmtMoney(totals.sales)} accent="green" />
        <SumTile label="Total paid" value={fmtMoney(totals.paid)} accent="green" />
        <SumTile label="Outstanding" value={fmtMoney(totals.outstanding)} accent="rose" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Customer</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead className="text-right">Sales</TableHead>
              <TableHead className="text-right">Total sales</TableHead>
              <TableHead className="text-right">Paid</TableHead>
              <TableHead className="text-right">Outstanding</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={6} className="text-slate-500 text-center p-4">No customer sales in this period.</TableCell></TableRow>
            ) : rows.map((r) => (
              <TableRow key={r.waterCustomerId}>
                <TableCell className="font-medium">{r.customerName}</TableCell>
                <TableCell>{r.phoneNumber ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{(r.salesCount ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.totalSales ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.totalPaid ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${(r.outstandingBalance ?? 0) > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.outstandingBalance ?? 0)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

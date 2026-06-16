"use client"

/** Customer Balances Report (Prompt 2 §16.5). Aggregates sales − payments per customer. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterCustomers, listWaterSales, listWaterPayments } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

type Row = {
  customerId: number
  name: string
  totalSales: number
  totalPaid: number
  outstanding: number
  lastSale?: string
  lastPayment?: string
}

export default function CustomerBalancesReportPage() {
  const fmtMoney = useFmt()
  const [rows, setRows] = useState<Row[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [customers, sales, payments] = await Promise.all([
        listWaterCustomers().catch(() => []),
        listWaterSales().catch(() => []),
        listWaterPayments().catch(() => []),
      ])

      const byCustomer = new Map<number, Row>()
      for (const c of customers ?? []) {
        byCustomer.set(c.waterCustomerId, {
          customerId: c.waterCustomerId,
          name: c.name ?? `#${c.waterCustomerId}`,
          totalSales: 0, totalPaid: 0, outstanding: 0,
        })
      }
      // Build a sale → customer lookup so we can attribute payments correctly
      // (WaterPayment carries waterSaleId, not waterCustomerId).
      const saleToCustomer = new Map<number, number>()
      for (const s of sales ?? []) {
        if (s.status === "Cancelled") continue
        const cid = s.waterCustomerId as number | undefined
        if (cid == null) continue
        saleToCustomer.set(s.waterSaleId, cid)
        const r = byCustomer.get(cid)
        if (!r) continue
        r.totalSales += (s.totalAmount ?? 0)
        r.totalPaid += (s.amountPaid ?? 0)
        const d = (s.saleDate ?? "").slice(0, 10)
        if (!r.lastSale || d > r.lastSale) r.lastSale = d
      }
      for (const p of payments ?? []) {
        const cid = saleToCustomer.get(p.waterSaleId)
        if (cid == null) continue
        const r = byCustomer.get(cid)
        if (!r) continue
        const d = (p.paymentDate ?? "").slice(0, 10)
        if (!r.lastPayment || d > r.lastPayment) r.lastPayment = d
      }
      for (const r of byCustomer.values()) r.outstanding = r.totalSales - r.totalPaid

      setRows(Array.from(byCustomer.values())
        .filter(r => r.totalSales !== 0 || r.outstanding !== 0)
        .sort((a, b) => b.outstanding - a.outstanding))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() }, [])

  const totals = useMemo(() => {
    return {
      customers: rows.length,
      owing: rows.filter(r => r.outstanding > 0).length,
      totalOutstanding: rows.reduce((s, r) => s + Math.max(r.outstanding, 0), 0),
      totalSales: rows.reduce((s, r) => s + r.totalSales, 0),
    }
  }, [rows])

  return (
    <ReportShell
      title="Customer Balances / Receivables"
      description="Sales − payments per customer, with the most-owing at the top."
      busy={busy} error={error} onClearError={() => setError(null)}
      onRefresh={load}
      pdf={{
        title: "Customer Balances / Receivables",
        filename: "water-customer-balances",
        summaryLines: [
          `Customers: ${totals.customers}`,
          `Customers owing: ${totals.owing}`,
          `Total outstanding: ${fmtMoney(totals.totalOutstanding)}`,
          `Total sales: ${fmtMoney(totals.totalSales)}`,
        ],
        columns: [
          { header: "Customer" },
          { header: "Total sales", align: "right" },
          { header: "Total paid", align: "right" },
          { header: "Outstanding", align: "right" },
          { header: "Last sale" },
          { header: "Last payment" },
        ],
        rows: rows.map((r) => [
          r.name,
          fmtMoney(r.totalSales),
          fmtMoney(r.totalPaid),
          fmtMoney(r.outstanding),
          r.lastSale ?? "—",
          r.lastPayment ?? "—",
        ]),
      }}
      summary={<>
        <SumTile label="Customers" value={String(totals.customers)} />
        <SumTile label="Customers owing" value={String(totals.owing)} accent="rose" />
        <SumTile label="Total outstanding" value={fmtMoney(totals.totalOutstanding)} accent="rose" />
        <SumTile label="Total sales" value={fmtMoney(totals.totalSales)} />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Customer</TableHead>
              <TableHead className="text-right">Total sales</TableHead>
              <TableHead className="text-right">Total paid</TableHead>
              <TableHead className="text-right">Outstanding</TableHead>
              <TableHead>Last sale</TableHead>
              <TableHead>Last payment</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={6} className="text-slate-500 text-center p-4">No customer activity yet.</TableCell></TableRow>
            ) : rows.map((r) => (
              <TableRow key={r.customerId}>
                <TableCell className="font-medium">{r.name}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.totalSales)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.totalPaid)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${r.outstanding > 0 ? "text-rose-700 font-medium" : ""}`}>{fmtMoney(r.outstanding)}</TableCell>
                <TableCell className="whitespace-nowrap">{r.lastSale ?? "—"}</TableCell>
                <TableCell className="whitespace-nowrap">{r.lastPayment ?? "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

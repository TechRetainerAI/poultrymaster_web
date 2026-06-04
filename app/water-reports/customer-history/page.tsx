"use client"

/** Customer Sales History (Prompt 2 §16.19). Per-customer sales + payments timeline. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterCustomers, listWaterSales, listWaterPaymentsBySale } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 90); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

type SaleRow = {
  saleId: number
  date: string
  total: number
  paid: number
  balance: number
  status: string
  payments: Array<{ date: string; amount: number; method: string }>
}

export default function CustomerHistoryReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [customers, setCustomers] = useState<any[]>([])
  const [customerId, setCustomerId] = useState<string>("ALL")
  const [sales, setSales] = useState<SaleRow[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    void (async () => {
      try { setCustomers(await listWaterCustomers()) }
      catch (e: any) { setError(e?.message ?? String(e)) }
    })()
  }, [])

  async function load() {
    if (customerId === "ALL") { setSales([]); setBusy(false); return }
    setBusy(true); setError(null)
    try {
      const allSales = await listWaterSales()
      const inScope = (allSales ?? []).filter((s: any) => {
        const d = (s.saleDate ?? "").slice(0, 10)
        return s.waterCustomerId === Number(customerId) && d >= fromDate && d <= toDate
      })
      const enriched: SaleRow[] = await Promise.all(inScope.map(async (s: any) => {
        const payments = await listWaterPaymentsBySale(s.waterSaleId).catch(() => [])
        return {
          saleId: s.waterSaleId,
          date: (s.saleDate ?? "").slice(0, 10),
          total: s.totalAmount ?? 0,
          paid: s.amountPaid ?? 0,
          balance: (s.totalAmount ?? 0) - (s.amountPaid ?? 0),
          status: s.status ?? "—",
          payments: (payments ?? []).map((p: any) => ({
            date: (p.paymentDate ?? "").slice(0, 10),
            amount: p.amount ?? 0,
            method: p.paymentMethod ?? "—",
          })),
        }
      }))
      enriched.sort((a, b) => b.date.localeCompare(a.date))
      setSales(enriched)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate, customerId])

  const totals = useMemo(() => ({
    sales: sales.length,
    revenue: sales.reduce((s, r) => s + r.total, 0),
    paid: sales.reduce((s, r) => s + r.paid, 0),
    balance: sales.reduce((s, r) => s + r.balance, 0),
  }), [sales])

  const selectedCustomer = customers.find(c => String(c.waterCustomerId) === customerId)

  return (
    <ReportShell
      title="Customer Sales History"
      description="Pick a customer to see their sales + payment timeline."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      filterSummary={{
        Customer: selectedCustomer?.name,
      }}
      filters={(
        <div>
          <Select value={customerId} onValueChange={setCustomerId}>
            <SelectTrigger className="w-56 h-9 text-xs"><SelectValue placeholder="Pick customer" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="ALL">Pick customer…</SelectItem>
              {customers.map((c) => (
                <SelectItem key={c.waterCustomerId} value={String(c.waterCustomerId)}>{c.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      )}
      summary={customerId !== "ALL" ? (<>
        <SumTile label="Sales count" value={String(totals.sales)} />
        <SumTile label="Revenue" value={fmtMoney(totals.revenue)} />
        <SumTile label="Paid" value={fmtMoney(totals.paid)} accent="green" />
        <SumTile label="Balance" value={fmtMoney(totals.balance)} accent={totals.balance > 0 ? "rose" : "green"} />
      </>) : undefined}
    >
      {customerId === "ALL" ? (
        <p className="text-slate-500 text-sm">Pick a customer above to load their history.</p>
      ) : (
        <>
          <div className="mb-2 text-sm text-slate-600">Customer: <span className="font-medium">{selectedCustomer?.name ?? "—"}</span></div>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Sale date</TableHead>
                  <TableHead>Sale #</TableHead>
                  <TableHead className="text-right">Total</TableHead>
                  <TableHead className="text-right">Paid</TableHead>
                  <TableHead className="text-right">Balance</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Payments</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sales.length === 0 ? (
                  <TableRow><TableCell colSpan={7} className="text-slate-500 text-center p-4">No sales for this customer in the selected period.</TableCell></TableRow>
                ) : sales.map((r) => (
                  <TableRow key={r.saleId}>
                    <TableCell className="whitespace-nowrap">{r.date}</TableCell>
                    <TableCell>{r.saleId}</TableCell>
                    <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.total)}</TableCell>
                    <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.paid)}</TableCell>
                    <TableCell className={`text-right tabular-nums whitespace-nowrap ${r.balance > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.balance)}</TableCell>
                    <TableCell>{r.status}</TableCell>
                    <TableCell className="text-xs text-slate-600">
                      {r.payments.length === 0 ? "—" : r.payments.map((p, i) => (
                        <span key={i} className="inline-block mr-2">{p.date} · {p.method} · {fmtMoney(p.amount)}</span>
                      ))}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </>
      )}
    </ReportShell>
  )
}

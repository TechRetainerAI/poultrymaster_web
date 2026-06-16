"use client"

/** Cash Flow Report (Prompt 2 §16.18). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterCashTransactions, listWaterCashAccounts } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function CashFlowReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [txns, setTxns] = useState<any[]>([])
  const [accounts, setAccounts] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [t, a] = await Promise.all([
        listWaterCashTransactions({ fromDate, toDate }),
        listWaterCashAccounts().catch(() => []),
      ])
      setTxns(t ?? []); setAccounts(a ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const inflow  = txns.filter(t => (t.amount ?? 0) > 0).reduce((s, t) => s + t.amount, 0)
    const outflow = txns.filter(t => (t.amount ?? 0) < 0).reduce((s, t) => s + t.amount, 0)
    const net = inflow + outflow
    const currentCash = accounts.reduce((s, a) => s + (a.currentBalance ?? 0), 0)
    return { inflow, outflow, net, currentCash }
  }, [txns, accounts])

  return (
    <ReportShell
      title="Cash Flow"
      description="Inflows + outflows from cash accounts during the period."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Cash Flow",
        filename: "water-cash-flow",
        summaryLines: [
          `Cash in: ${fmtMoney(totals.inflow)}`,
          `Cash out: ${fmtMoney(Math.abs(totals.outflow))}`,
          `Net change: ${fmtMoney(totals.net)}`,
          `Current cash: ${fmtMoney(totals.currentCash)}`,
        ],
        columns: [
          { header: "Date" },
          { header: "Account" },
          { header: "Type" },
          { header: "Source" },
          { header: "Description" },
          { header: "Amount", align: "right" },
        ],
        rows: txns.map((t: any) => [
          (t.transactionDate ?? "").slice(0, 10),
          accounts.find(a => a.waterCashAccountId === t.waterCashAccountId)?.accountName ?? `#${t.waterCashAccountId}`,
          t.transactionType ?? "—",
          t.sourceType ?? "—",
          t.description ?? "—",
          fmtMoney(t.amount),
        ]),
      }}
      summary={<>
        <SumTile label="Cash in"  value={fmtMoney(totals.inflow)}  accent="green" />
        <SumTile label="Cash out" value={fmtMoney(Math.abs(totals.outflow))} accent="rose" />
        <SumTile label="Net change" value={fmtMoney(totals.net)} accent={totals.net >= 0 ? "green" : "rose"} />
        <SumTile label="Current cash" value={fmtMoney(totals.currentCash)} />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Source</TableHead>
              <TableHead>Description</TableHead>
              <TableHead className="text-right">Amount</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {txns.length === 0 ? (
              <TableRow><TableCell colSpan={6} className="text-slate-500 text-center p-4">No cash transactions in this period.</TableCell></TableRow>
            ) : txns.map((t: any) => (
              <TableRow key={t.waterCashTransactionId}>
                <TableCell className="whitespace-nowrap">{(t.transactionDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{accounts.find(a => a.waterCashAccountId === t.waterCashAccountId)?.accountName ?? `#${t.waterCashAccountId}`}</TableCell>
                <TableCell>{t.transactionType ?? "—"}</TableCell>
                <TableCell>{t.sourceType ?? "—"}</TableCell>
                <TableCell className="max-w-[260px] truncate">{t.description ?? "—"}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${t.amount < 0 ? "text-rose-700" : "text-emerald-700"}`}>{fmtMoney(t.amount)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

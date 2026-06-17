"use client"

/** Profit & Loss Report (Prompt 2 §16.2). Reuses the existing Period P&L SP. */

import { useEffect, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { getWaterPeriodPnL } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function ProfitLossReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [pnl, setPnl] = useState<any | null>(null)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const res = await getWaterPeriodPnL(fromDate, toDate)
      setPnl(res)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  // Field names must match the SP result (productionCost / rawMaterialCost /
  // totalExpenses=operating / totalLosses). The old code read totalProductionCost
  // & totalRawMaterialCost which don't exist, so gross showed full income.
  const gross = pnl ? (pnl.totalIncome ?? 0) - (pnl.productionCost ?? 0) - (pnl.rawMaterialCost ?? 0) : 0
  const net = pnl ? gross - (pnl.totalExpenses ?? 0) - (pnl.totalLosses ?? 0) : 0

  return (
    <ReportShell
      title="Profit & Loss"
      description="Income − cost of production / materials − operating expenses − losses."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Profit & Loss",
        filename: "water-profit-loss",
        columns: [{ header: "Line" }, { header: "Amount", align: "right" }],
        rows: pnl ? [
          ["Total income (sales)", fmtMoney(pnl.totalIncome ?? 0)],
          ["Less: production cost", `(${fmtMoney(pnl.productionCost ?? 0)})`],
          ["Less: raw material cost (paid)", `(${fmtMoney(pnl.rawMaterialCost ?? 0)})`],
          ["Gross profit", fmtMoney(gross)],
          ["Less: operating expenses", `(${fmtMoney(pnl.totalExpenses ?? 0)})`],
          ["Less: losses", `(${fmtMoney(pnl.totalLosses ?? 0)})`],
          ["Net profit", fmtMoney(net)],
        ] : [],
      }}
      summary={pnl ? (<>
        <SumTile label="Income" value={fmtMoney(pnl.totalIncome ?? 0)} accent="green" />
        <SumTile label="Gross profit" value={fmtMoney(gross)} accent={gross >= 0 ? "green" : "rose"} />
        <SumTile label="Expenses + losses" value={fmtMoney((pnl.totalExpenses ?? 0) + (pnl.totalLosses ?? 0))} accent="rose" />
        <SumTile label="Net profit" value={fmtMoney(net)} accent={net >= 0 ? "green" : "rose"} />
      </>) : undefined}
    >
      {!pnl ? (
        <p className="text-slate-500 text-sm">No P&L data for this period.</p>
      ) : (
        <Table>
          <TableHeader><TableRow><TableHead>Line</TableHead><TableHead className="text-right">Amount</TableHead></TableRow></TableHeader>
          <TableBody>
            <TableRow><TableCell>Total income (sales)</TableCell><TableCell className="text-right tabular-nums">{fmtMoney(pnl.totalIncome ?? 0)}</TableCell></TableRow>
            <TableRow><TableCell>Less: production cost</TableCell><TableCell className="text-right tabular-nums">({fmtMoney(pnl.productionCost ?? 0)})</TableCell></TableRow>
            <TableRow><TableCell>Less: raw material cost (paid)</TableCell><TableCell className="text-right tabular-nums">({fmtMoney(pnl.rawMaterialCost ?? 0)})</TableCell></TableRow>
            <TableRow className="font-semibold"><TableCell>Gross profit</TableCell><TableCell className="text-right tabular-nums">{fmtMoney(gross)}</TableCell></TableRow>
            <TableRow><TableCell>Less: operating expenses</TableCell><TableCell className="text-right tabular-nums">({fmtMoney(pnl.totalExpenses ?? 0)})</TableCell></TableRow>
            <TableRow><TableCell>Less: losses</TableCell><TableCell className="text-right tabular-nums">({fmtMoney(pnl.totalLosses ?? 0)})</TableCell></TableRow>
            <TableRow className="font-semibold bg-slate-50"><TableCell>Net profit</TableCell><TableCell className="text-right tabular-nums">{fmtMoney(net)}</TableCell></TableRow>
          </TableBody>
        </Table>
      )}
    </ReportShell>
  )
}

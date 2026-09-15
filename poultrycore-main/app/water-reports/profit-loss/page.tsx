"use client"

/** Profit & Loss Report (Prompt 2 §16.2). Reuses the existing Period P&L SP. */

import { useEffect, useState } from "react"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { StatementPanel } from "@/components/reports/statement-sections"
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
      // The body is a sectioned statement, not a table, so the shell must not
      // try to card it up on a phone — the panels are already phone-shaped and
      // stack into one column of their own accord.
      mobileCards={false}
      pdf={{
        title: "Profit & Loss",
        filename: "water-profit-loss",
        summaryCards: pnl ? [
          { label: "Income", value: fmtMoney(pnl.totalIncome ?? 0), accent: "green" },
          { label: "Gross profit", value: fmtMoney(gross), accent: gross >= 0 ? "green" : "rose" },
          { label: "Expenses + losses", value: fmtMoney((pnl.totalExpenses ?? 0) + (pnl.totalLosses ?? 0)), accent: "rose" },
          { label: "Net profit", value: fmtMoney(net), accent: net >= 0 ? "green" : "rose" },
        ] : undefined,
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
        // The same sectioned statement the poultry P&L uses, in the same
        // colours: where money came IN, and the three places it goes OUT. On a
        // desktop the sections stand side by side so the whole statement is on
        // one line of the page — Income and Losses share the first column,
        // since a section of one line beside a wall of them reads as a stub.
        // Gross and Net profit are not repeated here: the tiles above carry
        // them, and the arithmetic between the sections is what the tiles say.
        <div className="grid items-start gap-3 lg:grid-cols-3">
          <div className="flex flex-col gap-3">
            <StatementPanel
              title="Income" totalLabel="Total income" total={pnl.totalIncome ?? 0} gh={fmtMoney} tone="emerald"
              lines={[{ id: "sales", label: "Sales", amount: pnl.totalIncome ?? 0 }]}
            />
            <StatementPanel
              title="Losses" totalLabel="Total losses" total={pnl.totalLosses ?? 0} gh={fmtMoney} negative tone="violet"
              lines={(pnl.totalLosses ?? 0) === 0 ? [] : [{ id: "losses", label: "Stock and production losses", amount: pnl.totalLosses ?? 0 }]}
            />
          </div>
          <StatementPanel
            title="Direct Production Costs" totalLabel="Total direct production costs"
            total={(pnl.productionCost ?? 0) + (pnl.rawMaterialCost ?? 0)} gh={fmtMoney} negative tone="rose"
            lines={[
              { id: "production", label: "Production cost", amount: pnl.productionCost ?? 0 },
              { id: "materials", label: "Raw material cost (paid)", amount: pnl.rawMaterialCost ?? 0 },
            ]}
          />
          <StatementPanel
            title="Operating Expenses" totalLabel="Total operating expenses"
            total={pnl.totalExpenses ?? 0} gh={fmtMoney} negative tone="amber"
            lines={(pnl.totalExpenses ?? 0) === 0 ? [] : [{ id: "opex", label: "Operating expenses", amount: pnl.totalExpenses ?? 0 }]}
          />
        </div>
      )}
    </ReportShell>
  )
}

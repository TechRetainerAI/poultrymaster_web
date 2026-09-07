"use client"

/**
 * Water Cash Movement Report — the Water twin of /poultry/reports/cash-movement.
 *
 * WHAT IT READS
 * -------------
 * GET /api/Water/cash-flow only, which is spwatercashflow_detail / _summary
 * (migration 236): customer receipts, the part of a sale paid on the spot,
 * approved non-credit expenses, and capital in and out.
 *
 * WHY THERE IS NO NEW ENDPOINT
 * ----------------------------
 * The poultry report has its own SPs because it predates 235/237 and had a
 * ledger-reading version to replace. Water's functions already return every
 * column this report prints; the running balance and the totals are arithmetic
 * over rows we already hold. A second server-side copy of that arithmetic would
 * be a second place for it to disagree with the Cash Flow page.
 *
 * NOT the retired /water-reports/cash-flow. That one read the ledger, counted an
 * internal MoMo-to-Bank transfer as both an inflow and an outflow, and excluded
 * the final day of its own range. This reads neither the ledger nor transfers,
 * and the end date covers the whole day.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile, ReportTableCards } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { getCashFlow, flowGroupLabel, type CashFlowRow, type CashFlowSummary } from "@/lib/api/cash-flow"
import { categoryLabel, withRunningBalance } from "@/lib/cash/cash-flow"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

const EMPTY_SUMMARY: CashFlowSummary = {
  moneyIn: 0, moneyOut: 0, netCashFlow: 0, openingCash: 0, closingCash: 0,
  operatingIn: 0, operatingOut: 0, financingIn: 0, financingOut: 0, movementCount: 0,
}

/** The document behind a row, so a figure can be traced back to what caused it. */
function reference(r: CashFlowRow): string {
  if (r.sourceId == null) return "—"
  switch (r.rowSource) {
    case "Receipt": return `Payment · sale #${r.sourceId}`
    case "SaleResidual": return `Sale #${r.sourceId}`
    case "Expense": return `Expense #${r.sourceId}`
    case "Adjustment": return `Adjustment #${r.sourceId}`
    default: return `#${r.sourceId}`
  }
}

export default function WaterCashMovementReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT = defaultReportRange()
  const [fromDate, setFromDate] = useState(DEFAULT.from)
  const [toDate, setToDate] = useState(DEFAULT.to)
  const [rows, setRows] = useState<CashFlowRow[]>([])
  const [summary, setSummary] = useState<CashFlowSummary>(EMPTY_SUMMARY)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setBusy(true); setError(null)
    try {
      const res = await getCashFlow("Water", { fromDate, toDate })
      setRows(res.rows)
      setSummary(res.summary)
    } catch (e: any) {
      setError(e?.message ?? String(e))
      setRows([]); setSummary(EMPTY_SUMMARY)
    } finally { setBusy(false) }
  }, [fromDate, toDate])

  useEffect(() => { void load() }, [load])

  // Company-wide cash after each row, accumulated from the period's opening
  // figure. The rows span several accounts plus money that reached none, so this
  // is not any one account's balance.
  const withRunning = useMemo(
    () => withRunningBalance(rows, summary.openingCash),
    [rows, summary.openingCash],
  )

  // Newest first for reading; the running balance was accumulated oldest-first
  // and travels with its row, so reversing here does not disturb it.
  const visible = useMemo(() => [...withRunning].reverse(), [withRunning])

  const pg = usePagination(visible)

  // Straight from the server summary. Deliberately NOT recomputed from the rows
  // on screen and deliberately not filterable: this is a statement of the
  // period, and a total that moves when you narrow the view is not one. The
  // Cash Flow page is where you slice the same rows by type and category.
  const totals = useMemo(() => ({
    opening: summary.openingCash,
    inflow: summary.moneyIn,
    outflow: summary.moneyOut,
    net: summary.netCashFlow,
    closing: summary.closingCash,
  }), [summary])

  const pdfRows = useMemo(
    () => visible.map((r) => [
      (r.transactionDate ?? "").slice(0, 10),
      flowGroupLabel(r.flowGroup),
      categoryLabel(r.category),
      r.sourceType || "—",
      reference(r),
      r.description ?? "—",
      r.amount > 0 ? fmtMoney(r.amount) : "—",
      r.amount < 0 ? fmtMoney(-r.amount) : "—",
      fmtMoney(r.running),
    ]),
    [visible, fmtMoney],
  )

  // One column description, shared by the PDF and the phone scorecards.
  const pdfColumns = [
    { header: "Date" }, { header: "Type" }, { header: "Category" }, { header: "Source" },
    { header: "Reference" }, { header: "Description" },
    { header: "Inflow", align: "right" as const }, { header: "Outflow", align: "right" as const },
    { header: "Balance", align: "right" as const },
  ]

  return (
    <ReportShell
      title="Cash Movement"
      description="Every movement of cash in the period, oldest balance forward. Built from sales, customer payments, approved expenses and capital — not from cash account balances."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      // The standing note above the table has to stay on screen at every width,
      // so the table alone is carded (below) rather than the whole slot.
      mobileCards={false}
      pdf={{
        title: "Water Cash Movement Report",
        filename: "water-cash-movement",
        orientation: "landscape",
        summaryCards: [
          { label: "Opening cash balance", value: fmtMoney(totals.opening) },
          { label: "Total inflows", value: fmtMoney(totals.inflow), accent: "green" },
          { label: "Total outflows", value: fmtMoney(totals.outflow), accent: "rose" },
          { label: "Net cash movement", value: fmtMoney(totals.net), accent: totals.net >= 0 ? "green" : "rose" },
          { label: "Closing cash", value: fmtMoney(totals.closing), note: "Not your account balances" },
        ],
        columns: pdfColumns,
        rows: pdfRows,
      }}
      summary={<>
        <SumTile label="Opening cash balance" value={fmtMoney(totals.opening)} />
        <SumTile label="Total inflows" value={fmtMoney(totals.inflow)} accent="green" />
        <SumTile label="Total outflows" value={fmtMoney(totals.outflow)} accent="rose" />
        <SumTile label="Net cash movement" value={fmtMoney(totals.net)} accent={totals.net >= 0 ? "green" : "rose"} />
        <SumTile label="Closing cash" value={fmtMoney(totals.closing)} accent="indigo" />
      </>}
    >
      {/* Said once, on every run: the same sentence the poultry report carries,
          because "closing cash does not match my accounts" is alarming until you
          know the two are measured from different things on purpose. */}
      <p className="mb-3 rounded-md border border-slate-200 bg-slate-50 p-2 text-xs leading-snug text-slate-600">
        These figures come from sales, payments, approved expenses and capital records, not from cash
        account balances. Closing cash is not expected to match what the accounts hold — comparing
        the two is what reconciliation is for. Transfers between your own accounts are excluded: they
        move money without the business earning or spending any.
      </p>

      <ReportTableCards columns={pdfColumns} rows={pdfRows}>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Category</TableHead>
              <TableHead>Source</TableHead>
              <TableHead>Reference</TableHead>
              <TableHead>Description</TableHead>
              <TableHead className="text-right">Inflow</TableHead>
              <TableHead className="text-right">Outflow</TableHead>
              <TableHead className="text-right">Balance</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.length === 0 ? (
              <TableRow>
                <TableCell colSpan={9} className="text-slate-500 text-center p-4">
                  No cash moved in this period.
                </TableCell>
              </TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={`${r.rowSource}-${r.id}`}>
                <TableCell className="whitespace-nowrap">{(r.transactionDate ?? "").slice(0, 10)}</TableCell>
                <TableCell className="whitespace-nowrap">{flowGroupLabel(r.flowGroup)}</TableCell>
                <TableCell>{categoryLabel(r.category)}</TableCell>
                <TableCell>{r.sourceType || "—"}</TableCell>
                <TableCell className="whitespace-nowrap">{reference(r)}</TableCell>
                <TableCell className="max-w-[260px] truncate" title={r.description ?? ""}>{r.description ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-emerald-700">
                  {r.amount > 0 ? fmtMoney(r.amount) : "—"}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-rose-700">
                  {r.amount < 0 ? fmtMoney(-r.amount) : "—"}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap font-medium">
                  {fmtMoney(r.running)}
                </TableCell>
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

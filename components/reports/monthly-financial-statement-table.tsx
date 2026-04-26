"use client"

import { useMemo, useState } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import {
  buildMonthlyFinancialStatement,
  financialStatementToCsv,
  downloadFinancialStatementPdf,
  formatAccountingCell,
  formatPercentCell,
  statementRowTotals,
  type MonthlyFinancialStatement,
  type FinancialStatementRow,
} from "@/lib/reports/monthly-financial-statement"
import { FileDown, FileText, Loader2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"

function RowCells({
  row,
  statement,
}: {
  row: FinancialStatementRow
  statement: MonthlyFinancialStatement
}) {
  const { months, currencyCode } = statement
  const totals = statementRowTotals(row)

  if (row.kind === "section") {
    return (
      <td colSpan={months.length + 3} className="px-3 py-2 font-bold text-slate-800 bg-slate-200 border border-slate-300">
        {row.label}
      </td>
    )
  }

  return (
    <>
      <td
        className={cn(
          "px-3 py-2 border border-slate-200 text-slate-900",
          row.kind === "subtotal" && "font-semibold bg-slate-50",
          row.kind === "highlight" && "font-semibold bg-emerald-50",
        )}
      >
        {row.label}
      </td>
      <td className="px-3 py-2 border border-slate-200 text-xs text-slate-600 whitespace-nowrap">{`[${currencyCode}]`}</td>
      {row.values.map((v, i) => (
        <td
          key={months[i]?.key ?? i}
          className={cn(
            "px-2 py-2 border border-slate-200 text-right tabular-nums whitespace-nowrap",
            row.kind === "subtotal" && "font-semibold bg-slate-50",
            row.kind === "highlight" && "font-semibold bg-emerald-50",
          )}
        >
          {row.isPercent ? formatPercentCell(v) : formatAccountingCell(v, currencyCode)}
        </td>
      ))}
      <td
        className={cn(
          "px-2 py-2 border border-slate-200 text-right tabular-nums font-medium whitespace-nowrap",
          row.kind === "subtotal" && "bg-slate-50",
          row.kind === "highlight" && "bg-emerald-50",
        )}
      >
        {row.isPercent ? formatPercentCell(totals) : formatAccountingCell(totals, currencyCode)}
      </td>
    </>
  )
}

export function MonthlyFinancialStatementTable({
  sales,
  expenses,
  dateFrom,
  dateTo,
  currencyCode,
}: {
  sales: Record<string, unknown>[]
  expenses: Record<string, unknown>[]
  dateFrom: string
  dateTo: string
  currencyCode: string
}) {
  const { toast } = useToast()
  const [pdfLoading, setPdfLoading] = useState(false)

  const statement = useMemo(
    () => buildMonthlyFinancialStatement(sales, expenses, dateFrom, dateTo, currencyCode),
    [sales, expenses, dateFrom, dateTo, currencyCode],
  )

  const farmName = typeof window !== "undefined" ? localStorage.getItem("farmName") || undefined : undefined

  const csvDownload = () => {
    const csv = financialStatementToCsv(statement, farmName)
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `monthly-financial-statement-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
    toast({ title: "CSV downloaded", description: "Open in Excel or Google Sheets." })
  }

  const pdfDownload = async () => {
    setPdfLoading(true)
    try {
      await downloadFinancialStatementPdf(statement, farmName)
      toast({ title: "PDF downloaded", description: "Monthly financial statement." })
    } catch (e) {
      toast({
        variant: "destructive",
        title: "PDF export failed",
        description: e instanceof Error ? e.message : "Unknown error",
      })
    } finally {
      setPdfLoading(false)
    }
  }

  const { months, rows, periodLabel } = statement

  return (
    <Card className="bg-white border-slate-200 shadow-sm">
      <CardHeader className="space-y-1 border-b border-slate-100 pb-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <CardTitle className="text-lg">Monthly financial statement</CardTitle>
            <CardDescription>
              P&amp;L-style view by calendar month (COGS uses category keywords: feed, transport, vet, batch, etc.).{" "}
              <span className="text-slate-600">{periodLabel}</span>
            </CardDescription>
          </div>
          <div className="flex flex-wrap gap-2 shrink-0">
            <Button type="button" variant="outline" size="sm" className="gap-2" onClick={csvDownload}>
              <FileText className="h-4 w-4" />
              CSV
            </Button>
            <Button type="button" variant="outline" size="sm" className="gap-2" onClick={pdfDownload} disabled={pdfLoading}>
              {pdfLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileDown className="h-4 w-4" />}
              PDF
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent className="pt-4 p-0 sm:p-6 sm:pt-4">
        {months.length === 0 ? (
          <p className="text-sm text-slate-500 px-4 pb-4">No months in range.</p>
        ) : (
          <div className="overflow-x-auto border-t border-slate-200">
            <table className="w-full min-w-[720px] text-sm border-collapse">
              <thead>
                <tr className="bg-sky-100 text-slate-800">
                  <th
                    rowSpan={2}
                    className="text-left px-3 py-2 border border-slate-300 font-semibold sticky left-0 z-20 bg-sky-100 min-w-[160px]"
                  >
                    Line item
                  </th>
                  <th
                    rowSpan={2}
                    className="text-left px-3 py-2 border border-slate-300 font-semibold sticky left-[160px] z-20 bg-sky-100 min-w-[56px]"
                  >
                    Unit
                  </th>
                  {months.map((m) => (
                    <th
                      key={m.key}
                      colSpan={1}
                      className="px-2 py-2 border border-slate-300 text-center font-semibold whitespace-nowrap min-w-[88px]"
                    >
                      {m.calendarYear}
                    </th>
                  ))}
                  <th
                    rowSpan={2}
                    className="px-2 py-2 border border-slate-300 text-center font-semibold whitespace-nowrap bg-sky-200 min-w-[100px]"
                  >
                    Total
                  </th>
                </tr>
                <tr className="bg-sky-50 text-slate-800">
                  {months.map((m) => (
                    <th key={`${m.key}-m`} className="px-2 py-1.5 border border-slate-300 text-center text-xs font-semibold whitespace-nowrap">
                      {m.labelRow1}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row, idx) => (
                  <tr key={`${row.kind}-${row.label}-${idx}`} className="bg-white">
                    <RowCells row={row} statement={statement} />
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

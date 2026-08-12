"use client"

/** Raw Material Purchases Report (Prompt 2 §16.8). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listWaterRawMaterialPurchases } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function RawMaterialPurchaseReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<any[]>([])
  const pg = usePagination(rows)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await listWaterRawMaterialPurchases({ fromDate, toDate })
      setRows(all ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const total = rows.reduce((s, p) => s + ((p.totalCost ?? ((p.quantity ?? 0) * (p.unitCost ?? 0))) ?? 0), 0)
    const paid = rows.reduce((s, p) => s + (p.amountPaid ?? 0), 0)
    const balance = total - paid
    return { count: rows.length, total, paid, balance }
  }, [rows])

  return (
    <ReportShell
      title="Raw Material Purchases"
      description="Stock-in receipts with supplier, quantity, cost and payment status."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Raw Material Purchases",
        filename: "water-raw-material-purchase",
        columns: [
          { header: "Date" },
          { header: "Material" },
          { header: "Supplier" },
          { header: "Quantity", align: "right" },
          { header: "Unit cost", align: "right" },
          { header: "Total cost", align: "right" },
          { header: "Paid", align: "right" },
          { header: "Balance", align: "right" },
          { header: "Method" },
        ],
        rows: rows.map((p: any) => {
          const total = p.totalCost ?? ((p.quantity ?? 0) * (p.unitCost ?? 0))
          const balance = total - (p.amountPaid ?? 0)
          return [
            (p.purchaseDate ?? "").slice(0, 10),
            p.itemName ?? p.waterRawMaterialItemId,
            p.supplierName ?? "—",
            (p.quantity ?? 0).toLocaleString(),
            fmtMoney(p.unitCost ?? 0),
            fmtMoney(total),
            fmtMoney(p.amountPaid ?? 0),
            fmtMoney(balance),
            p.paymentMethod ?? "—",
          ]
        }),
        summaryLines: [
          `Purchases: ${totals.count.toLocaleString()}`,
          `Total cost: ${fmtMoney(totals.total)}`,
          `Paid: ${fmtMoney(totals.paid)}`,
          `Outstanding: ${fmtMoney(totals.balance)}`,
        ],
      }}
      summary={<>
        <SumTile label="Purchases" value={totals.count.toLocaleString()} />
        <SumTile label="Total cost" value={fmtMoney(totals.total)} />
        <SumTile label="Paid" value={fmtMoney(totals.paid)} accent="green" />
        <SumTile label="Outstanding" value={fmtMoney(totals.balance)} accent="rose" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Material</TableHead>
              <TableHead>Supplier</TableHead>
              <TableHead className="text-right">Quantity</TableHead>
              <TableHead className="text-right">Unit cost</TableHead>
              <TableHead className="text-right">Total cost</TableHead>
              <TableHead className="text-right">Paid</TableHead>
              <TableHead className="text-right">Balance</TableHead>
              <TableHead>Method</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No purchases in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((p: any) => {
              const total = p.totalCost ?? ((p.quantity ?? 0) * (p.unitCost ?? 0))
              const balance = total - (p.amountPaid ?? 0)
              return (
                <TableRow key={p.waterRawMaterialPurchaseId}>
                  <TableCell className="whitespace-nowrap">{(p.purchaseDate ?? "").slice(0, 10)}</TableCell>
                  <TableCell className="max-w-[180px] truncate">{p.itemName ?? p.waterRawMaterialItemId}</TableCell>
                  <TableCell className="max-w-[180px] truncate">{p.supplierName ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{(p.quantity ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(p.unitCost ?? 0)}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(total)}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(p.amountPaid ?? 0)}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(balance)}</TableCell>
                  <TableCell>{p.paymentMethod ?? "—"}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />
    </ReportShell>
  )
}

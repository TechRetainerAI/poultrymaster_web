"use client"

/** Loss Report (Prompt 2 §16.16). Combines production-side losses (auto from batch approval) and manual loss records. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listWaterLossRecords, listWaterProductionLosses } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

type Row = {
  source: string
  date: string
  type: string
  product: string
  bags: number
  sachets: number
  value: number
  reason: string
  status: string
}

export default function LossReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<Row[]>([])
  const pg = usePagination(rows)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [manual, production] = await Promise.all([
        listWaterLossRecords({ fromDate, toDate }).catch(() => []),
        listWaterProductionLosses({ fromDate, toDate }).catch(() => []),
      ])
      const merged: Row[] = [
        ...(manual ?? []).map((r: any) => ({
          source: "Manual",
          date: (r.lossDate ?? "").slice(0, 10),
          type: r.lossType ?? "—",
          product: r.productName ?? "—",
          bags: Number(r.quantityBags ?? 0),
          sachets: Number(r.quantitySachets ?? 0),
          value: Number(r.estimatedValue ?? 0),
          reason: r.reason ?? "—",
          status: r.status ?? "—",
        })),
        ...(production ?? []).map((r: any) => ({
          source: "Production",
          date: (r.lossDate ?? "").slice(0, 10),
          type: r.lossType ?? "ProductionDamage",
          product: r.productName ?? "—",
          bags: r.bagsLost ?? 0,
          sachets: r.sachetsLost ?? 0,
          value: r.totalValue ?? 0,
          reason: r.reason ?? r.batchNumber ?? "—",
          status: r.status ?? "Approved",
        })),
      ].sort((a, b) => b.date.localeCompare(a.date))
      setRows(merged)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const approved = rows.filter(r => r.status === "Approved")
    return {
      count: rows.length,
      approved: approved.length,
      bags: approved.reduce((s, r) => s + r.bags, 0),
      sachets: approved.reduce((s, r) => s + r.sachets, 0),
      value: approved.reduce((s, r) => s + r.value, 0),
    }
  }, [rows])

  return (
    <ReportShell
      title="Loss Report"
      description="Damaged bags, rejected sachets, manual losses. Only Approved records count toward totals."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Loss Report",
        filename: "water-loss-report",
        columns: [
          { header: "Date" },
          { header: "Source" },
          { header: "Type" },
          { header: "Product" },
          { header: "Bags", align: "right" },
          { header: "Sachets", align: "right" },
          { header: "Value", align: "right" },
          { header: "Reason" },
          { header: "Status" },
        ],
        rows: rows.map((r) => [
          r.date,
          r.source,
          r.type,
          r.product,
          r.bags.toLocaleString(),
          r.sachets.toLocaleString(),
          fmtMoney(r.value),
          r.reason,
          r.status,
        ]),
        summaryLines: [
          `Records: ${totals.approved} / ${totals.count}`,
          `Bags lost: ${totals.bags.toLocaleString()}`,
          `Sachets lost: ${totals.sachets.toLocaleString()}`,
          `Total value: ${fmtMoney(totals.value)}`,
        ],
      }}
      summary={<>
        <SumTile label="Records" value={`${totals.approved} / ${totals.count}`} />
        <SumTile label="Bags lost" value={totals.bags.toLocaleString()} accent="rose" />
        <SumTile label="Sachets lost" value={totals.sachets.toLocaleString()} accent="rose" />
        <SumTile label="Total value" value={fmtMoney(totals.value)} accent="rose" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Source</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Product</TableHead>
              <TableHead className="text-right">Bags</TableHead>
              <TableHead className="text-right">Sachets</TableHead>
              <TableHead className="text-right">Value</TableHead>
              <TableHead>Reason</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No losses in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((r, i) => (
              <TableRow key={i}>
                <TableCell className="whitespace-nowrap">{r.date}</TableCell>
                <TableCell>{r.source}</TableCell>
                <TableCell>{r.type}</TableCell>
                <TableCell className="max-w-[180px] truncate">{r.product}</TableCell>
                <TableCell className="text-right tabular-nums">{r.bags.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{r.sachets.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.value)}</TableCell>
                <TableCell className="max-w-[260px] truncate">{r.reason}</TableCell>
                <TableCell>{r.status}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />
    </ReportShell>
  )
}

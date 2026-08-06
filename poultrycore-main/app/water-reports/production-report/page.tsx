"use client"

/** Production Report (Prompt 2 §16.6). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterProductionBatches } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function ProductionReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await listWaterProductionBatches({ fromDate, toDate })
      setRows(all ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const approved = rows.filter((b: any) => b.status === "Approved")
    const goodBags = approved.reduce((s, b) => s + (b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0))), 0)
    const damaged = approved.reduce((s, b) => s + (b.damagedBags ?? 0), 0)
    const cost = approved.reduce((s, b) => s + (b.allInCost ?? ((b.totalProductionCost ?? 0) + (b.rawMaterialCost ?? 0))), 0)
    const avgCpb = goodBags > 0 ? cost / goodBags : 0
    return { batches: rows.length, approved: approved.length, goodBags, damaged, cost, avgCpb }
  }, [rows])

  return (
    <ReportShell
      title="Production Report"
      description="Production records, output and cost analysis. Only Approved records count toward totals."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Production Report",
        filename: "water-production-report",
        columns: [
          { header: "Date" },
          { header: "Production" },
          { header: "Machine" },
          { header: "Product" },
          { header: "Produced", align: "right" },
          { header: "Good", align: "right" },
          { header: "Damaged", align: "right" },
          { header: "Total cost", align: "right" },
          { header: "Cost/bag", align: "right" },
          { header: "Status" },
        ],
        rows: rows.map((b: any) => {
          const good = b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0))
          const cost = b.allInCost ?? ((b.totalProductionCost ?? 0) + (b.rawMaterialCost ?? 0))
          return [
            (b.productionDate ?? "").slice(0, 10),
            b.batchNumber ?? `#${b.waterProductionBatchId}`,
            b.machineScope === "AllMachines" ? "All / Combined" : (b.machineName ?? "—"),
            b.productName ?? "—",
            b.bagsProduced.toLocaleString(),
            good.toLocaleString(),
            (b.damagedBags ?? 0).toLocaleString(),
            fmtMoney(cost),
            fmtMoney(b.costPerBag ?? 0),
            b.status,
          ]
        }),
        summaryLines: [
          `Production records: ${totals.approved} / ${totals.batches}`,
          `Good bags: ${totals.goodBags.toLocaleString()}`,
          `Damaged: ${totals.damaged.toLocaleString()}`,
          `Avg cost/bag: ${fmtMoney(totals.avgCpb)}`,
        ],
      }}
      summary={<>
        <SumTile label="Records"  value={`${totals.approved} / ${totals.batches}`} />
        <SumTile label="Good bags" value={totals.goodBags.toLocaleString()} accent="green" />
        <SumTile label="Damaged" value={totals.damaged.toLocaleString()} accent="rose" />
        <SumTile label="Avg cost/bag" value={fmtMoney(totals.avgCpb)} />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Production</TableHead>
              <TableHead>Machine</TableHead>
              <TableHead>Product</TableHead>
              <TableHead className="text-right">Produced</TableHead>
              <TableHead className="text-right">Good</TableHead>
              <TableHead className="text-right">Damaged</TableHead>
              <TableHead className="text-right">Total cost</TableHead>
              <TableHead className="text-right">Cost/bag</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={10} className="text-slate-500 text-center p-4">No production records in this period.</TableCell></TableRow>
            ) : rows.map((b: any) => {
              const good = b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0))
              const cost = b.allInCost ?? ((b.totalProductionCost ?? 0) + (b.rawMaterialCost ?? 0))
              return (
                <TableRow key={b.waterProductionBatchId}>
                  <TableCell className="whitespace-nowrap">{(b.productionDate ?? "").slice(0, 10)}</TableCell>
                  <TableCell>{b.batchNumber ?? `#${b.waterProductionBatchId}`}</TableCell>
                  <TableCell>{b.machineScope === "AllMachines" ? "All / Combined" : (b.machineName ?? "—")}</TableCell>
                  <TableCell className="max-w-[180px] truncate">{b.productName ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{b.bagsProduced.toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums font-medium">{good.toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums">{(b.damagedBags ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(cost)}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(b.costPerBag ?? 0)}</TableCell>
                  <TableCell>{b.status}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

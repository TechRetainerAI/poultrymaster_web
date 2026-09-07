"use client"

/** Raw Material Usage Report (Prompt 2 §16.7). The per-material variance rollup
 *  is the authoritative server-side report SP (spWaterReport_RawMaterialVariance)
 *  — this is what the emailed PDF contains. The per-usage detail list below is
 *  supplementary. */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile, ReportTableCards } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listWaterRawMaterialUsageHistory, getWaterRawMaterialVariance, type WaterRawMaterialVarianceRow } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }
function num(n: number | null | undefined) { return (n ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 }) }

export default function RawMaterialUsageReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [variance, setVariance] = useState<WaterRawMaterialVarianceRow[]>([])
  const pg = usePagination(variance)
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [v, all] = await Promise.all([
        getWaterRawMaterialVariance(fromDate, toDate),
        listWaterRawMaterialUsageHistory({ fromDate, toDate }),
      ])
      setVariance(v ?? [])
      setRows(all ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    items: variance.length,
    expected: variance.reduce((s, v) => s + (v.totalExpected ?? 0), 0),
    actual: variance.reduce((s, v) => s + (v.totalActual ?? 0), 0),
    absVariance: variance.reduce((s, v) => s + Math.abs(v.totalVariance ?? 0), 0),
  }), [variance])

  // Both tables on this page are too wide for a phone, so each gets its own
  // scorecard rendering. The rollup's description is shared with the PDF.
  const materialColumns = [
    { header: "Material" }, { header: "Category" }, { header: "Unit" },
    { header: "Expected", align: "right" as const }, { header: "Actual", align: "right" as const },
    { header: "Variance", align: "right" as const }, { header: "Usage count", align: "right" as const },
  ]
  const materialRows = variance.map((v) => [
    v.itemName, v.category, v.unitOfMeasure ?? "—",
    num(v.totalExpected), num(v.totalActual), num(v.totalVariance),
    (v.usageCount ?? 0).toLocaleString(),
  ])
  const usageColumns = [
    { header: "Date" }, { header: "Batch" }, { header: "Material" },
    { header: "Expected", align: "right" as const }, { header: "Actual", align: "right" as const },
    { header: "Variance", align: "right" as const }, { header: "Unit cost", align: "right" as const },
    { header: "Total cost", align: "right" as const },
  ]
  const usageRows = rows.map((r: any) => [
    (r.usedDate ?? "").slice(0, 10),
    r.batchNumber ?? "—",
    r.itemName ?? "—",
    num(r.expectedQuantityUsed),
    num(r.quantityUsed),
    num(r.variance),
    r.unitCost ? fmtMoney(r.unitCost) : "—",
    r.totalCost ? fmtMoney(r.totalCost) : "—",
  ])

  return (
    <ReportShell
      title="Raw Material Usage"
      description="Expected vs actual raw material consumption with variance, per material. The usage detail below is supplementary."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      // Two wide tables, each with its own <ReportTableCards> below — the
      // shell's automatic phone view would show only the one `pdf` describes.
      mobileCards={false}
      pdf={{
        // PDF uses the authoritative per-material variance rollup (usage detail is supplementary).
        title: "Raw Material Usage",
        filename: "water-raw-material-usage",
        summaryLines: [
          `Materials: ${totals.items}`,
          `Expected qty: ${num(totals.expected)}`,
          `Actual qty: ${num(totals.actual)}`,
          `Abs variance: ${num(totals.absVariance)}`,
        ],
        columns: materialColumns,
        rows: materialRows,
      }}
      summary={<>
        <SumTile label="Materials" value={String(totals.items)} />
        <SumTile label="Expected qty" value={num(totals.expected)} />
        <SumTile label="Actual qty" value={num(totals.actual)} />
        <SumTile label="Abs variance" value={num(totals.absVariance)} accent="rose" />
      </>}
    >
      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">By material</h2>
      <ReportTableCards columns={materialColumns} rows={materialRows}>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Material</TableHead>
              <TableHead>Category</TableHead>
              <TableHead>Unit</TableHead>
              <TableHead className="text-right">Expected</TableHead>
              <TableHead className="text-right">Actual</TableHead>
              <TableHead className="text-right">Variance</TableHead>
              <TableHead className="text-right">Usage count</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {variance.length === 0 ? (
              <TableRow><TableCell colSpan={7} className="text-slate-500 text-center p-4">No usage in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((v) => (
              <TableRow key={v.waterRawMaterialItemId}>
                <TableCell className="font-medium max-w-[180px] truncate">{v.itemName}</TableCell>
                <TableCell>{v.category}</TableCell>
                <TableCell>{v.unitOfMeasure ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{num(v.totalExpected)}</TableCell>
                <TableCell className="text-right tabular-nums">{num(v.totalActual)}</TableCell>
                <TableCell className={`text-right tabular-nums ${Math.abs(v.totalVariance ?? 0) > 0 ? "text-amber-700" : ""}`}>{num(v.totalVariance)}</TableCell>
                <TableCell className="text-right tabular-nums">{(v.usageCount ?? 0).toLocaleString()}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      </ReportTableCards>

      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mt-4 mb-2 print:hidden">Usage detail</h2>
      <ReportTableCards columns={usageColumns} rows={usageRows}>
      <div className="overflow-x-auto print:hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Batch</TableHead>
              <TableHead>Material</TableHead>
              <TableHead className="text-right">Expected</TableHead>
              <TableHead className="text-right">Actual</TableHead>
              <TableHead className="text-right">Variance</TableHead>
              <TableHead className="text-right">Unit cost</TableHead>
              <TableHead className="text-right">Total cost</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-slate-500 text-center p-4">No usage rows.</TableCell></TableRow>
            ) : rows.map((r: any) => (
              <TableRow key={r.waterRawMaterialUsageId}>
                <TableCell className="whitespace-nowrap">{(r.usedDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{r.batchNumber ?? "—"}</TableCell>
                <TableCell className="max-w-[180px] truncate">{r.itemName ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{num(r.expectedQuantityUsed)}</TableCell>
                <TableCell className="text-right tabular-nums">{num(r.quantityUsed)}</TableCell>
                <TableCell className={`text-right tabular-nums ${Math.abs(r.variance ?? 0) > 0 ? "text-amber-700" : ""}`}>{num(r.variance)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{r.unitCost ? fmtMoney(r.unitCost) : "—"}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{r.totalCost ? fmtMoney(r.totalCost) : "—"}</TableCell>
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

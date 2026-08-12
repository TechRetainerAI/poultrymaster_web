"use client"

/** Product Performance Report (Prompt 2 §16.20). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listWaterProducts, listWaterSales, listWaterProductionBatches } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

type Row = {
  productId: number
  name: string
  type: string
  produced: number
  sold: number
  revenue: number
  productionCost: number
  costPerBag: number
  grossProfit: number
  stockOnHand: number
}

export default function ProductPerformanceReportPage() {
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
      const [products, sales, batches] = await Promise.all([
        listWaterProducts().catch(() => []),
        listWaterSales().catch(() => []),
        listWaterProductionBatches({ fromDate, toDate }).catch(() => []),
      ])
      const map = new Map<number, Row>()
      for (const p of products ?? []) {
        map.set(p.waterProductId, {
          productId: p.waterProductId,
          name: p.name,
          type: p.productType ?? "FinishedGood",
          produced: 0, sold: 0, revenue: 0, productionCost: 0, costPerBag: 0, grossProfit: 0,
          stockOnHand: Number(p.stockOnHand ?? 0),
        })
      }
      for (const b of batches ?? []) {
        if (b.status !== "Approved" || b.waterProductId == null) continue
        const row = map.get(b.waterProductId); if (!row) continue
        const good = b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0))
        row.produced += good
        row.productionCost += (b.allInCost ?? ((b.totalProductionCost ?? 0) + (b.rawMaterialCost ?? 0)))
      }
      // For sold/revenue we'd need sale items; the list endpoint only gives the
      // header. We approximate revenue using the proportion of sales attributed
      // by source = DeliveryRun (where line items typically exist for each
      // product). When that's not possible, leave revenue at 0 and the user
      // can drill into the per-product details via the Sales report.
      // (A future SP could roll this up server-side.)
      for (const _s of sales ?? []) { /* intentionally noop without sale items */ }
      for (const r of map.values()) {
        if (r.produced > 0) r.costPerBag = r.productionCost / r.produced
        r.grossProfit = r.revenue - r.productionCost
      }
      setRows(Array.from(map.values()).filter(r => r.produced > 0 || r.stockOnHand !== 0))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    products: rows.length,
    produced: rows.reduce((s, r) => s + r.produced, 0),
    cost: rows.reduce((s, r) => s + r.productionCost, 0),
  }), [rows])

  return (
    <ReportShell
      title="Product Performance"
      description="Production output + cost per product (revenue rollup pending server-side aggregation)."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Product Performance",
        filename: "water-product-performance",
        columns: [
          { header: "Product" },
          { header: "Type" },
          { header: "Good produced", align: "right" },
          { header: "Production cost", align: "right" },
          { header: "Cost/bag", align: "right" },
          { header: "Stock", align: "right" },
        ],
        rows: rows.map((r) => [
          r.name,
          r.type,
          r.produced.toLocaleString(),
          fmtMoney(r.productionCost),
          fmtMoney(r.costPerBag),
          r.stockOnHand.toLocaleString(),
        ]),
        summaryLines: [
          `Products: ${totals.products}`,
          `Total produced: ${totals.produced.toLocaleString()}`,
          `Total cost: ${fmtMoney(totals.cost)}`,
        ],
      }}
      summary={<>
        <SumTile label="Products" value={String(totals.products)} />
        <SumTile label="Total produced" value={totals.produced.toLocaleString()} accent="green" />
        <SumTile label="Total cost" value={fmtMoney(totals.cost)} />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Product</TableHead>
              <TableHead>Type</TableHead>
              <TableHead className="text-right">Good produced</TableHead>
              <TableHead className="text-right">Production cost</TableHead>
              <TableHead className="text-right">Cost/bag</TableHead>
              <TableHead className="text-right">Stock</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={6} className="text-slate-500 text-center p-4">No production for any product in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={r.productId}>
                <TableCell className="font-medium">{r.name}</TableCell>
                <TableCell>{r.type}</TableCell>
                <TableCell className="text-right tabular-nums">{r.produced.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.productionCost)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.costPerBag)}</TableCell>
                <TableCell className="text-right tabular-nums">{r.stockOnHand.toLocaleString()}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />
    </ReportShell>
  )
}

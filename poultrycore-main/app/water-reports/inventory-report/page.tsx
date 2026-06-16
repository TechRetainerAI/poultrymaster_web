"use client"

/** Inventory / Stock Report (Prompt 2 §16.9). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterProducts, listWaterRawMaterialItems } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

type Row = {
  name: string
  type: string
  unit: string
  stock: number
  minAlert: number | null
  unitCost: number | null
  status: "OK" | "Low" | "Out"
}

export default function InventoryReportPage() {
  const fmtMoney = useFmt()
  const [rows, setRows] = useState<Row[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [products, raws] = await Promise.all([
        listWaterProducts().catch(() => []),
        listWaterRawMaterialItems().catch(() => []),
      ])

      const rowsP: Row[] = (products ?? []).map((p: any) => {
        const stock = Number(p.stockOnHand ?? 0)
        return {
          name: p.name,
          type: p.productType ?? "FinishedGood",
          unit: p.unit ?? "bag",
          stock,
          minAlert: null,
          unitCost: p.unitPrice ?? null,
          status: stock <= 0 ? "Out" : "OK",
        }
      })

      const rowsR: Row[] = (raws ?? []).map((r: any) => {
        const stock = Number(r.currentQuantity ?? 0)
        const min = r.minimumStockAlert != null ? Number(r.minimumStockAlert) : null
        const status: Row["status"] =
          stock <= 0 ? "Out" :
          (min != null && stock <= min) ? "Low" : "OK"
        return {
          name: r.itemName,
          type: "RawMaterial",
          unit: r.unitOfMeasure ?? "—",
          stock,
          minAlert: min,
          unitCost: r.lastUnitCost ?? null,
          status,
        }
      })

      setRows([...rowsP, ...rowsR].sort((a, b) => a.name.localeCompare(b.name)))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() }, [])

  const totals = useMemo(() => {
    const value = rows.reduce((s, r) => s + (r.unitCost != null ? r.stock * r.unitCost : 0), 0)
    return {
      total: rows.length,
      out: rows.filter(r => r.status === "Out").length,
      low: rows.filter(r => r.status === "Low").length,
      value,
    }
  }, [rows])

  return (
    <ReportShell
      title="Inventory / Stock"
      description="Current stock position for finished products and raw materials."
      busy={busy} error={error} onClearError={() => setError(null)}
      onRefresh={load}
      pdf={{
        title: "Inventory / Stock",
        filename: "water-inventory-report",
        columns: [
          { header: "Item" },
          { header: "Type" },
          { header: "Unit" },
          { header: "Stock", align: "right" },
          { header: "Min alert", align: "right" },
          { header: "Unit cost", align: "right" },
          { header: "Stock value", align: "right" },
          { header: "Status" },
        ],
        rows: rows.map((r) => [
          r.name,
          r.type,
          r.unit,
          r.stock.toLocaleString(),
          r.minAlert ?? "—",
          r.unitCost != null ? fmtMoney(r.unitCost) : "—",
          r.unitCost != null ? fmtMoney(r.stock * r.unitCost) : "—",
          r.status,
        ]),
        summaryLines: [
          `Items: ${totals.total.toLocaleString()}`,
          `Low stock: ${totals.low}`,
          `Out of stock: ${totals.out}`,
          `Stock value: ${fmtMoney(totals.value)}`,
        ],
      }}
      summary={<>
        <SumTile label="Items" value={totals.total.toLocaleString()} />
        <SumTile label="Low stock" value={String(totals.low)} accent="rose" />
        <SumTile label="Out of stock" value={String(totals.out)} accent="rose" />
        <SumTile label="Stock value" value={fmtMoney(totals.value)} />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Item</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Unit</TableHead>
              <TableHead className="text-right">Stock</TableHead>
              <TableHead className="text-right">Min alert</TableHead>
              <TableHead className="text-right">Unit cost</TableHead>
              <TableHead className="text-right">Stock value</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-slate-500 text-center p-4">No inventory rows yet.</TableCell></TableRow>
            ) : rows.map((r, i) => (
              <TableRow key={i}>
                <TableCell className="font-medium">{r.name}</TableCell>
                <TableCell>{r.type}</TableCell>
                <TableCell>{r.unit}</TableCell>
                <TableCell className="text-right tabular-nums">{r.stock.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{r.minAlert ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{r.unitCost != null ? fmtMoney(r.unitCost) : "—"}</TableCell>
                <TableCell className="text-right tabular-nums">{r.unitCost != null ? fmtMoney(r.stock * r.unitCost) : "—"}</TableCell>
                <TableCell className={r.status === "OK" ? "" : "text-rose-700 font-medium"}>{r.status}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}

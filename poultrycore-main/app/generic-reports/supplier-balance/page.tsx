"use client"

// Supplier Balance Report — uses ReportShell for professional design.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Truck } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { getSuppliers, type GenericSupplier } from "@/lib/api/generic"
import { cn } from "@/lib/utils"

export default function SupplierBalanceReportPage() {
  const fmtMoney = useFmt()
  const [rows, setRows] = useState<GenericSupplier[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState("")
  const [filter, setFilter] = useState<"all" | "owed" | "credit">("all")

  async function load() {
    setBusy(true); setError(null)
    try { setRows(await getSuppliers()) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() }, [])

  const filtered = useMemo(() => {
    let data = rows.filter((r) => r.isActive)
    if (filter === "owed") data = data.filter((r) => r.currentBalance > 0)
    else if (filter === "credit") data = data.filter((r) => r.currentBalance < 0)
    return filterByDateAndSearch(data, { search, searchKeys: ["supplierName", "supplierType", "phoneNumber"] })
  }, [rows, search, filter])

  const pg = usePagination(filtered)

  const totals = useMemo(() => {
    const active = rows.filter((r) => r.isActive)
    const owed = active.filter((r) => r.currentBalance > 0)
    const credit = active.filter((r) => r.currentBalance < 0)
    return {
      totalOwed: owed.reduce((s, r) => s + r.currentBalance, 0),
      owedCount: owed.length,
      totalCredit: Math.abs(credit.reduce((s, r) => s + r.currentBalance, 0)),
      creditCount: credit.length,
      totalSuppliers: active.length,
    }
  }, [rows])

  return (
    <ReportShell
      title="Supplier Balance Report"
      description="What is owed to suppliers, any advances paid, and net payable position."
      backHref="/generic-reports"
      pageIcon={Truck}
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate="" toDate=""
      onFromDateChange={() => {}} onToDateChange={() => {}}
      pdf={{
        title: "Supplier Balance Report",
        filename: "supplier-balances",
        columns: [
          { header: "Supplier", key: "supplierName" },
          { header: "Type", key: "supplierType" },
          { header: "Phone", key: "phoneNumber" },
          { header: "Balance", align: "right", format: "currency" },
          { header: "Status" },
        ],
        rows: filtered.map((r) => [
          r.supplierName, r.supplierType, r.phoneNumber ?? "–",
          fmtMoney(r.currentBalance),
          r.currentBalance > 0 ? "We owe" : r.currentBalance < 0 ? "Advance" : "Clear",
        ]),
        summaryLines: [
          `Total owed: ${fmtMoney(totals.totalOwed)} (${totals.owedCount} supplier(s))`,
          `Total advances: ${fmtMoney(totals.totalCredit)} (${totals.creditCount} supplier(s))`,
          `Net payable: ${fmtMoney(totals.totalOwed - totals.totalCredit)}`,
          `Active suppliers: ${totals.totalSuppliers}`,
        ],
      }}
      summary={<>
        <SumTile label="Total owed" value={fmtMoney(totals.totalOwed)} accent="rose" />
        <SumTile label="Total advances" value={fmtMoney(totals.totalCredit)} accent="green" />
        <SumTile label="Net payable" value={fmtMoney(totals.totalOwed - totals.totalCredit)} accent={totals.totalOwed > totals.totalCredit ? "rose" : "green"} />
        <SumTile label="Active suppliers" value={String(totals.totalSuppliers)} />
        <SumTile label="We owe" value={String(totals.owedCount)} accent="rose" />
      </>}
      filters={<>
        <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search supplier, type, phone..." />
        <div className="flex gap-2 mt-2">
          {(["all", "owed", "credit"] as const).map((f) => (
            <Button key={f} size="sm" variant={filter === f ? "default" : "outline"}
              onClick={() => setFilter(f)}>{f === "all" ? "All" : f === "owed" ? "We Owe" : "Advance Paid"}</Button>
          ))}
        </div>
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Supplier</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead className="text-right">Balance</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow><TableCell colSpan={5} className="text-slate-500 text-center p-4">No suppliers match.</TableCell></TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={r.genericSupplierId}>
                <TableCell className="font-medium">
                  <Link href={`/generic-suppliers/${r.genericSupplierId}/ledger`} className="text-blue-600 hover:underline">
                    {r.supplierName}
                  </Link>
                </TableCell>
                <TableCell>{r.supplierType}</TableCell>
                <TableCell>{r.phoneNumber ?? "–"}</TableCell>
                <TableCell className={cn("text-right tabular-nums font-medium",
                  r.currentBalance > 0 ? "text-orange-600" : r.currentBalance < 0 ? "text-emerald-700" : "text-slate-500")}>
                  {fmtMoney(r.currentBalance)}
                </TableCell>
                <TableCell>
                  <Badge className={r.currentBalance > 0
                    ? "bg-orange-100 text-orange-800 hover:bg-orange-100"
                    : r.currentBalance < 0 ? "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
                    : "bg-slate-100 text-slate-700 hover:bg-slate-100"}>
                    {r.currentBalance > 0 ? "We owe" : r.currentBalance < 0 ? "Advance" : "Clear"}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {filtered.length > 0 && <DataPagination {...pg.paginationProps} />}
      </div>
    </ReportShell>
  )
}

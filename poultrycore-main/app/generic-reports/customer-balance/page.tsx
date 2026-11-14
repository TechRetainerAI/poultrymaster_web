"use client"

// Customer Balance Report — uses ReportShell for professional design.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Users } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { getCustomers, type GenericCustomer } from "@/lib/api/generic"
import { cn } from "@/lib/utils"

export default function CustomerBalanceReportPage() {
  const fmtMoney = useFmt()
  const [rows, setRows] = useState<GenericCustomer[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState("")
  const [filter, setFilter] = useState<"all" | "owing" | "credit">("all")

  async function load() {
    setBusy(true); setError(null)
    try { setRows(await getCustomers()) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() }, [])

  const filtered = useMemo(() => {
    let data = rows.filter((r) => r.isActive)
    if (filter === "owing") data = data.filter((r) => r.currentBalance > 0)
    else if (filter === "credit") data = data.filter((r) => r.currentBalance < 0)
    return filterByDateAndSearch(data, { search, searchKeys: ["customerName", "customerType", "phoneNumber"] })
  }, [rows, search, filter])

  const pg = usePagination(filtered)

  const totals = useMemo(() => {
    const active = rows.filter((r) => r.isActive)
    const owing = active.filter((r) => r.currentBalance > 0)
    const credit = active.filter((r) => r.currentBalance < 0)
    return {
      totalOwing: owing.reduce((s, r) => s + r.currentBalance, 0),
      owingCount: owing.length,
      totalCredit: Math.abs(credit.reduce((s, r) => s + r.currentBalance, 0)),
      creditCount: credit.length,
      totalCustomers: active.length,
    }
  }, [rows])

  return (
    <ReportShell
      title="Customer Balance Report"
      description="Who owes what, who has credit on account, and which customers are over their limit."
      backHref="/generic-reports"
      pageIcon={Users}
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate="" toDate=""
      onFromDateChange={() => {}} onToDateChange={() => {}}
      pdf={{
        title: "Customer Balance Report",
        filename: "customer-balances",
        columns: [
          { header: "Customer", key: "customerName" },
          { header: "Type", key: "customerType" },
          { header: "Phone", key: "phoneNumber" },
          { header: "Balance", align: "right", format: "currency" },
          { header: "Credit Limit", align: "right", format: "currency" },
          { header: "Status" },
        ],
        rows: filtered.map((r) => [
          r.customerName, r.customerType, r.phoneNumber ?? "–",
          fmtMoney(r.currentBalance), fmtMoney(r.creditLimit),
          r.currentBalance > 0 ? "Owing" : r.currentBalance < 0 ? "Credit" : "Clear",
        ]),
        summaryLines: [
          `Total owing: ${fmtMoney(totals.totalOwing)} (${totals.owingCount} customer(s))`,
          `Total credit: ${fmtMoney(totals.totalCredit)} (${totals.creditCount} customer(s))`,
          `Net receivable: ${fmtMoney(totals.totalOwing - totals.totalCredit)}`,
          `Active customers: ${totals.totalCustomers}`,
        ],
      }}
      summary={<>
        <SumTile label="Total owing" value={fmtMoney(totals.totalOwing)} accent="rose" />
        <SumTile label="Total credit" value={fmtMoney(totals.totalCredit)} accent="green" />
        <SumTile label="Net receivable" value={fmtMoney(totals.totalOwing - totals.totalCredit)} accent={totals.totalOwing > totals.totalCredit ? "rose" : "green"} />
        <SumTile label="Active customers" value={String(totals.totalCustomers)} />
        <SumTile label="Owing" value={String(totals.owingCount)} accent="rose" />
      </>}
      filters={<>
        <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search customer, type, phone..." />
        <div className="flex gap-2 mt-2">
          {(["all", "owing", "credit"] as const).map((f) => (
            <Button key={f} size="sm" variant={filter === f ? "default" : "outline"}
              onClick={() => setFilter(f)}>{f === "all" ? "All" : f === "owing" ? "Owing" : "In Credit"}</Button>
          ))}
        </div>
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Customer</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead className="text-right">Balance</TableHead>
              <TableHead className="text-right">Credit Limit</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow><TableCell colSpan={6} className="text-slate-500 text-center p-4">No customers match.</TableCell></TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={r.genericCustomerId}>
                <TableCell className="font-medium">
                  <Link href={`/generic-customers/${r.genericCustomerId}/ledger`} className="text-blue-600 hover:underline">
                    {r.customerName}
                  </Link>
                </TableCell>
                <TableCell>{r.customerType}</TableCell>
                <TableCell>{r.phoneNumber ?? "–"}</TableCell>
                <TableCell className={cn("text-right tabular-nums font-medium",
                  r.currentBalance > 0 ? "text-red-600" : r.currentBalance < 0 ? "text-emerald-700" : "text-slate-500")}>
                  {fmtMoney(r.currentBalance)}
                </TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(r.creditLimit)}</TableCell>
                <TableCell>
                  <Badge className={r.currentBalance > r.creditLimit && r.creditLimit > 0
                    ? "bg-red-100 text-red-800 hover:bg-red-100" : r.currentBalance > 0 ? "bg-amber-100 text-amber-800 hover:bg-amber-100" : r.currentBalance < 0 ? "bg-emerald-100 text-emerald-800 hover:bg-emerald-100" : "bg-slate-100 text-slate-700 hover:bg-slate-100"}>
                    {r.currentBalance > r.creditLimit && r.creditLimit > 0 ? "Over limit" : r.currentBalance > 0 ? "Owing" : r.currentBalance < 0 ? "Credit" : "Clear"}
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

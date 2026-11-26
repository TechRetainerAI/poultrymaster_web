"use client"

// Collections Report — invoiced vs collected vs outstanding by customer.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { FileText } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { getInvoiceDocuments, type InvoiceDocumentRow } from "@/lib/api/generic-invoice-documents"
import { cn } from "@/lib/utils"

interface CustomerSummary {
  customerName: string
  invoiceCount: number
  totalInvoiced: number
  totalCollected: number
  totalOutstanding: number
  overdueAmount: number
  hasOverdue: boolean
}

export default function CollectionsReportPage() {
  const fmt = useFmt()
  const [rows, setRows] = useState<InvoiceDocumentRow[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState("")

  async function load() {
    setBusy(true); setError(null)
    try {
      // All non-voided invoices
      const all = await getInvoiceDocuments()
      setRows(all.filter((r) => r.documentStatus !== "Voided"))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() }, [])

  // Group by customer
  const customers = useMemo(() => {
    const map = new Map<string, CustomerSummary>()
    for (const r of rows) {
      const name = r.customerBillingName || "Walk-in"
      const existing = map.get(name) ?? {
        customerName: name, invoiceCount: 0,
        totalInvoiced: 0, totalCollected: 0, totalOutstanding: 0,
        overdueAmount: 0, hasOverdue: false,
      }
      existing.invoiceCount++
      existing.totalInvoiced += r.totalAmount
      existing.totalCollected += r.amountPaid
      existing.totalOutstanding += r.balance
      if (r.isOverdue) { existing.overdueAmount += r.balance; existing.hasOverdue = true }
      map.set(name, existing)
    }
    return Array.from(map.values()).sort((a, b) => b.totalOutstanding - a.totalOutstanding)
  }, [rows])

  const filtered = useMemo(
    () => filterByDateAndSearch(customers, { search, searchKeys: ["customerName"] }),
    [customers, search],
  )
  const pg = usePagination(filtered)

  const totals = useMemo(() => ({
    invoiced: rows.reduce((s, r) => s + r.totalAmount, 0),
    collected: rows.reduce((s, r) => s + r.amountPaid, 0),
    outstanding: rows.reduce((s, r) => s + r.balance, 0),
    overdue: rows.filter((r) => r.isOverdue).reduce((s, r) => s + r.balance, 0),
    invoiceCount: rows.length,
    customerCount: customers.length,
  }), [rows, customers])

  const collectionRate = totals.invoiced > 0 ? Math.round((totals.collected / totals.invoiced) * 100) : 0

  return (
    <ReportShell
      title="Collections Report"
      description="How much has been invoiced, collected, and what remains outstanding — by customer."
      backHref="/generic-reports"
      pageIcon={<FileText className="h-5 w-5" />}
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate="" toDate=""
      onFromDateChange={() => {}} onToDateChange={() => {}}
      pdf={{
        title: "Collections Report",
        filename: "collections",
        columns: [
          { header: "Customer", key: "customerName" },
          { header: "Invoices", key: "invoiceCount", align: "right" },
          { header: "Invoiced", align: "right", format: "currency" },
          { header: "Collected", align: "right", format: "currency" },
          { header: "Outstanding", align: "right", format: "currency" },
          { header: "Overdue", align: "right", format: "currency" },
        ],
        rows: filtered.map((r) => [
          r.customerName, String(r.invoiceCount),
          fmt(r.totalInvoiced), fmt(r.totalCollected),
          fmt(r.totalOutstanding), fmt(r.overdueAmount),
        ]),
        summaryLines: [
          `Total invoiced: ${fmt(totals.invoiced)} (${totals.invoiceCount} invoices)`,
          `Total collected: ${fmt(totals.collected)} (${collectionRate}%)`,
          `Total outstanding: ${fmt(totals.outstanding)}`,
          `Total overdue: ${fmt(totals.overdue)}`,
          `Customers: ${totals.customerCount}`,
        ],
      }}
      summary={<>
        <SumTile label="Total invoiced" value={fmt(totals.invoiced)} />
        <SumTile label="Collected" value={`${fmt(totals.collected)} (${collectionRate}%)`} accent="green" />
        <SumTile label="Outstanding" value={fmt(totals.outstanding)} accent={totals.outstanding > 0 ? "rose" : "green"} />
        <SumTile label="Overdue" value={fmt(totals.overdue)} accent={totals.overdue > 0 ? "rose" : undefined} />
        <SumTile label="Invoices" value={String(totals.invoiceCount)} />
        <SumTile label="Customers" value={String(totals.customerCount)} />
      </>}
      filters={
        <ListFilters search={search} setSearch={setSearch} searchOnly
          searchPlaceholder="Search customer..." />
      }
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Customer</TableHead>
              <TableHead className="text-right">Invoices</TableHead>
              <TableHead className="text-right">Invoiced</TableHead>
              <TableHead className="text-right">Collected</TableHead>
              <TableHead className="text-right">Outstanding</TableHead>
              <TableHead className="text-right">Overdue</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow><TableCell colSpan={7} className="text-slate-500 text-center p-4">No invoice data.</TableCell></TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={r.customerName}>
                <TableCell className="font-medium">{r.customerName}</TableCell>
                <TableCell className="text-right">{r.invoiceCount}</TableCell>
                <TableCell className="text-right tabular-nums">{fmt(r.totalInvoiced)}</TableCell>
                <TableCell className="text-right tabular-nums text-emerald-700">{fmt(r.totalCollected)}</TableCell>
                <TableCell className={cn("text-right tabular-nums font-semibold", r.totalOutstanding > 0 ? "text-rose-700" : "")}>
                  {fmt(r.totalOutstanding)}
                </TableCell>
                <TableCell className={cn("text-right tabular-nums", r.overdueAmount > 0 ? "text-rose-700" : "")}>
                  {fmt(r.overdueAmount)}
                </TableCell>
                <TableCell>
                  <Badge className={
                    r.totalOutstanding <= 0 ? "bg-emerald-100 text-emerald-800"
                    : r.hasOverdue ? "bg-rose-100 text-rose-800"
                    : "bg-amber-100 text-amber-800"
                  }>
                    {r.totalOutstanding <= 0 ? "Collected" : r.hasOverdue ? "Overdue" : "Owing"}
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

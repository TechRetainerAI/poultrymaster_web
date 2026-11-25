"use client"

// Invoice Aging Report — outstanding balances grouped by overdue period.

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

type AgingBucket = "notDue" | "1-30" | "31-60" | "61-90" | "90+"

function bucket(daysUntilDue: number | null): AgingBucket {
  if (daysUntilDue === null) return "notDue"
  if (daysUntilDue >= 0) return "notDue"
  const overdue = Math.abs(daysUntilDue)
  if (overdue <= 30) return "1-30"
  if (overdue <= 60) return "31-60"
  if (overdue <= 90) return "61-90"
  return "90+"
}

const BUCKET_LABELS: Record<AgingBucket, string> = {
  "notDue": "Not yet due",
  "1-30": "1–30 days",
  "31-60": "31–60 days",
  "61-90": "61–90 days",
  "90+": "Over 90 days",
}

const BUCKET_COLORS: Record<AgingBucket, string> = {
  "notDue": "bg-emerald-100 text-emerald-800",
  "1-30": "bg-amber-100 text-amber-800",
  "31-60": "bg-orange-100 text-orange-800",
  "61-90": "bg-rose-100 text-rose-800",
  "90+": "bg-red-100 text-red-900",
}

export default function InvoiceAgingReportPage() {
  const fmt = useFmt()
  const [rows, setRows] = useState<InvoiceDocumentRow[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState("")

  async function load() {
    setBusy(true); setError(null)
    try {
      // Only Issued invoices with outstanding balance matter for aging
      const all = await getInvoiceDocuments({ documentStatus: "Issued" })
      setRows(all.filter((r) => r.balance > 0))
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() }, [])

  const filtered = useMemo(
    () => filterByDateAndSearch(rows, { search, searchKeys: ["invoiceNumber", "customerBillingName", "projectName"] }),
    [rows, search],
  )
  const pg = usePagination(filtered)

  const buckets = useMemo(() => {
    const totals: Record<AgingBucket, number> = { "notDue": 0, "1-30": 0, "31-60": 0, "61-90": 0, "90+": 0 }
    const counts: Record<AgingBucket, number> = { "notDue": 0, "1-30": 0, "31-60": 0, "61-90": 0, "90+": 0 }
    for (const r of rows) {
      const b = bucket(r.daysUntilDue)
      totals[b] += r.balance
      counts[b]++
    }
    return { totals, counts, totalOutstanding: rows.reduce((s, r) => s + r.balance, 0), count: rows.length }
  }, [rows])

  return (
    <ReportShell
      title="Invoice Aging Report"
      description="Outstanding invoice balances grouped by how long they have been overdue."
      backHref="/generic-reports"
      pageIcon={<FileText className="h-5 w-5" />}
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate="" toDate=""
      onFromDateChange={() => {}} onToDateChange={() => {}}
      pdf={{
        title: "Invoice Aging Report",
        filename: "invoice-aging",
        columns: [
          { header: "Invoice #", key: "invoiceNumber" },
          { header: "Customer", key: "customer" },
          { header: "Issue Date", key: "issueDate" },
          { header: "Due Date", key: "dueDate" },
          { header: "Total", align: "right", format: "currency" },
          { header: "Outstanding", align: "right", format: "currency" },
          { header: "Aging", key: "aging" },
        ],
        rows: filtered.map((r) => [
          r.invoiceNumber, r.customerBillingName ?? "—",
          r.issueDate, r.dueDate ?? "—",
          fmt(r.totalAmount), fmt(r.balance),
          BUCKET_LABELS[bucket(r.daysUntilDue)],
        ]),
        summaryLines: [
          `Total outstanding: ${fmt(buckets.totalOutstanding)} (${buckets.count} invoices)`,
          ...Object.entries(buckets.totals).filter(([, v]) => v > 0).map(
            ([k, v]) => `${BUCKET_LABELS[k as AgingBucket]}: ${fmt(v)} (${buckets.counts[k as AgingBucket]})`
          ),
        ],
      }}
      summary={<>
        <SumTile label="Total outstanding" value={fmt(buckets.totalOutstanding)} accent="rose" />
        <SumTile label="Not yet due" value={fmt(buckets.totals.notDue)} accent="green" />
        <SumTile label="1–30 days" value={fmt(buckets.totals["1-30"])} accent={buckets.totals["1-30"] > 0 ? "rose" : undefined} />
        <SumTile label="31–60 days" value={fmt(buckets.totals["31-60"])} accent={buckets.totals["31-60"] > 0 ? "rose" : undefined} />
        <SumTile label="61–90 days" value={fmt(buckets.totals["61-90"])} accent={buckets.totals["61-90"] > 0 ? "rose" : undefined} />
        <SumTile label="Over 90 days" value={fmt(buckets.totals["90+"])} accent={buckets.totals["90+"] > 0 ? "rose" : undefined} />
      </>}
      filters={
        <ListFilters search={search} setSearch={setSearch} searchOnly
          searchPlaceholder="Search invoice #, customer, project..." />
      }
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Invoice #</TableHead>
              <TableHead>Customer</TableHead>
              <TableHead>Project</TableHead>
              <TableHead>Issue Date</TableHead>
              <TableHead>Due Date</TableHead>
              <TableHead className="text-right">Total</TableHead>
              <TableHead className="text-right">Outstanding</TableHead>
              <TableHead>Aging</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-slate-500 text-center p-4">No outstanding invoices.</TableCell></TableRow>
            ) : pg.pageItems.map((r) => {
              const b = bucket(r.daysUntilDue)
              return (
                <TableRow key={r.genericInvoiceDocumentId}>
                  <TableCell>
                    <Link href={`/generic-invoice-documents/${r.genericInvoiceDocumentId}`} className="text-indigo-700 hover:underline font-mono text-xs">
                      {r.invoiceNumber}
                    </Link>
                  </TableCell>
                  <TableCell className="font-medium">{r.customerBillingName ?? "—"}</TableCell>
                  <TableCell className="text-xs text-slate-500">{r.projectName ?? "—"}</TableCell>
                  <TableCell>{r.issueDate}</TableCell>
                  <TableCell className={r.isOverdue ? "text-rose-700 font-medium" : ""}>{r.dueDate ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{fmt(r.totalAmount)}</TableCell>
                  <TableCell className={cn("text-right tabular-nums font-semibold", r.isOverdue ? "text-rose-700" : "")}>
                    {fmt(r.balance)}
                  </TableCell>
                  <TableCell><Badge className={BUCKET_COLORS[b]}>{BUCKET_LABELS[b]}</Badge></TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
        {filtered.length > 0 && <DataPagination {...pg.paginationProps} />}
      </div>
    </ReportShell>
  )
}

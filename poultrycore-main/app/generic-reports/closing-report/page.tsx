"use client"

// Closing Report — every daily closing with cash reconciliation and approval status.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import { ArrowLeft, FileText, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getDailyClosings, type GenericDailyClosing } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { cn } from "@/lib/utils"
import { exportTableToPdf } from "@/lib/utils/pdf-export"

export default function ClosingReportPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericDailyClosing[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try { setRows(await getDailyClosings()) }
    catch (e: any) { toast({ title: "Could not load closings", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const filtered = useMemo(() =>
    filterByDateAndSearch(rows, { search, searchKeys: ["status", "managerNotes", "differenceReason"], dateFrom, dateTo, dateKey: "closingDate" }),
    [rows, search, dateFrom, dateTo])

  const pg = usePagination(filtered)

  const totals = useMemo(() => {
    const approved = rows.filter((r) => r.status === "Approved")
    return {
      count: rows.length,
      approvedCount: approved.length,
      totalSales: approved.reduce((s, r) => s + r.totalSales, 0),
      totalExpenses: approved.reduce((s, r) => s + r.totalExpenses, 0),
      totalDifference: approved.reduce((s, r) => s + r.cashDifference, 0),
    }
  }, [rows])

  const statusBadge = (s: string) => {
    const cls = s === "Approved" ? "bg-emerald-100 text-emerald-800" : s === "Submitted" ? "bg-blue-100 text-blue-800" : s === "Rejected" ? "bg-red-100 text-red-800" : "bg-slate-100 text-slate-700"
    return <Badge className={`${cls} hover:${cls}`}>{s}</Badge>
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 min-w-0 space-y-4">
          <div className="mx-auto w-full max-w-7xl">
            <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
              <ArrowLeft className="h-3 w-3 mr-1" /> Back to reports
            </Link>
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <FileText className="h-6 w-6 text-emerald-600" /> Closing Report
            </h1>
            <p className="text-sm text-slate-500 mb-4">Every daily closing with cash reconciliation and approval status.</p>

            <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
              <Tile label="Total closings" value={String(totals.count)} />
              <Tile label="Approved" value={String(totals.approvedCount)} accent="emerald" />
              <Tile label="Total sales" value={fmt(totals.totalSales)} accent="emerald" />
              <Tile label="Total expenses" value={fmt(totals.totalExpenses)} accent="red" />
              <Tile label="Cash difference" value={fmt(totals.totalDifference)} accent={totals.totalDifference >= 0 ? "emerald" : "red"} />
            </div>

            <Card className="mb-4">
              <CardContent className="pt-6">
                <ListFilters search={search} setSearch={setSearch} searchPlaceholder="Search status, notes..."
                  dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} />
              </CardContent>
            </Card>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : filtered.length === 0 ? (
              <Card><CardContent className="py-8 text-center text-slate-500">No daily closings found.</CardContent></Card>
            ) : (
              <Card>
                <CardContent className="p-0 md:p-2">
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Date</TableHead>
                          <TableHead className="text-right">Opening Cash</TableHead>
                          <TableHead className="text-right">Sales</TableHead>
                          <TableHead className="text-right">Expenses</TableHead>
                          <TableHead className="text-right">Cash In</TableHead>
                          <TableHead className="text-right">Cash Out</TableHead>
                          <TableHead className="text-right">Expected</TableHead>
                          <TableHead className="text-right">Actual</TableHead>
                          <TableHead className="text-right">Difference</TableHead>
                          <TableHead>Status</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((r) => (
                          <TableRow key={r.genericDailyClosingId}>
                            <TableCell className="whitespace-nowrap font-medium">{r.closingDate.slice(0, 10)}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(r.openingCash)}</TableCell>
                            <TableCell className="text-right tabular-nums text-emerald-700">{fmt(r.totalSales)}</TableCell>
                            <TableCell className="text-right tabular-nums text-red-600">{fmt(r.totalExpenses)}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(r.totalCashIn)}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(r.totalCashOut)}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(r.expectedCash)}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(r.actualCashCounted)}</TableCell>
                            <TableCell className={cn("text-right tabular-nums font-medium", r.cashDifference >= 0 ? "text-emerald-700" : "text-red-600")}>
                              {r.cashDifference >= 0 ? "+" : ""}{fmt(r.cashDifference)}
                            </TableCell>
                            <TableCell>{statusBadge(r.status)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

function Tile({ label, value, accent }: { label: string; value: string; accent?: string }) {
  const color = { emerald: "text-emerald-700", red: "text-red-600", blue: "text-blue-700" }[accent ?? ""] ?? "text-slate-900"
  return (
    <Card><CardContent className="p-3">
      <div className="text-xs uppercase tracking-wide text-slate-500 truncate">{label}</div>
      <div className={cn("text-lg font-bold mt-1 truncate", color)}>{value}</div>
    </CardContent></Card>
  )
}

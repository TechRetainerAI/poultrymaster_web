"use client"

// Customer Balance Report — who owes what, aged by how long.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import { ArrowLeft, Loader2, Users } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getCustomers, type GenericCustomer } from "@/lib/api/generic"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { ReportExportButtons } from "@/components/reports/report-export-buttons"

export default function CustomerBalanceReportPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericCustomer[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [filter, setFilter] = useState<"all" | "owing" | "credit">("all")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try { setRows(await getCustomers()) }
    catch (e: any) { toast({ title: "Could not load customers", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

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

  const pdfOpts = useMemo(() => ({
    title: "Customer Balance Report",
    columns: [
      { header: "Customer", key: "customerName", width: 120 },
      { header: "Type", key: "customerType", width: 80 },
      { header: "Phone", key: "phoneNumber", width: 80 },
      { header: "Balance", key: "balance", width: 80, align: "right" as const, format: "currency" as const },
      { header: "Credit Limit", key: "creditLimit", width: 80, align: "right" as const, format: "currency" as const },
    ],
    rows: filtered.map((r) => ({ ...r, balance: r.currentBalance })),
  }), [filtered])

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
            <div className="flex items-center justify-between flex-wrap gap-2">
              <div>
                <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                  <Users className="h-6 w-6 text-cyan-600" /> Customer Balance Report
                </h1>
                <p className="text-sm text-slate-500">Who owes what, and who has credit on account.</p>
              </div>
              <ReportExportButtons pdf={pdfOpts} disabled={loading} csvFilename="customer-balances" />
            </div>

            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 my-4">
              <Tile label="Total owing" value={fmt(totals.totalOwing)} sub={`${totals.owingCount} customer(s)`} accent="red" />
              <Tile label="Total credit" value={fmt(totals.totalCredit)} sub={`${totals.creditCount} customer(s)`} accent="emerald" />
              <Tile label="Net receivable" value={fmt(totals.totalOwing - totals.totalCredit)} accent={totals.totalOwing - totals.totalCredit > 0 ? "amber" : "emerald"} />
              <Tile label="Active customers" value={String(totals.totalCustomers)} />
            </div>

            <Card className="mb-4">
              <CardContent className="pt-6">
                <ListFilters search={search} setSearch={setSearch} searchPlaceholder="Search customer, type, phone..." />
                <div className="flex gap-2 mt-3">
                  {(["all", "owing", "credit"] as const).map((f) => (
                    <Button key={f} size="sm" variant={filter === f ? "default" : "outline"}
                      onClick={() => setFilter(f)}>{f === "all" ? "All" : f === "owing" ? "Owing" : "In Credit"}</Button>
                  ))}
                </div>
              </CardContent>
            </Card>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : filtered.length === 0 ? (
              <Card><CardContent className="py-8 text-center text-slate-500">No customers match.</CardContent></Card>
            ) : (
              <Card>
                <CardContent className="p-0 md:p-2">
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
                        {pg.pageItems.map((r) => (
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
                              {fmt(r.currentBalance)}
                            </TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(r.creditLimit)}</TableCell>
                            <TableCell>
                              <Badge className={r.currentBalance > r.creditLimit && r.creditLimit > 0
                                ? "bg-red-100 text-red-800 hover:bg-red-100" : "bg-slate-100 text-slate-700 hover:bg-slate-100"}>
                                {r.currentBalance > r.creditLimit && r.creditLimit > 0 ? "Over limit" : r.currentBalance > 0 ? "Owing" : r.currentBalance < 0 ? "Credit" : "Clear"}
                              </Badge>
                            </TableCell>
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

function Tile({ label, value, sub, accent }: { label: string; value: string; sub?: string; accent?: string }) {
  const color = { emerald: "text-emerald-700", red: "text-red-600", amber: "text-amber-700" }[accent ?? ""] ?? "text-slate-900"
  return (
    <Card><CardContent className="p-3">
      <div className="text-xs uppercase tracking-wide text-slate-500 truncate">{label}</div>
      <div className={cn("text-lg font-bold mt-1 truncate", color)}>{value}</div>
      {sub && <div className="text-xs text-slate-400">{sub}</div>}
    </CardContent></Card>
  )
}

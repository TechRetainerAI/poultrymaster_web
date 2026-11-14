"use client"

// Supplier Balance Report — what is owed to suppliers, aged.

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
import { ArrowLeft, Loader2, Truck } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getSuppliers, type GenericSupplier } from "@/lib/api/generic"
import { cn } from "@/lib/utils"
import { ReportExportButtons } from "@/components/reports/report-export-buttons"
import { ReportPageHeader, RichCard } from "@/components/reports/report-header"

export default function SupplierBalanceReportPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericSupplier[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [filter, setFilter] = useState<"all" | "owed" | "credit">("all")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try { setRows(await getSuppliers()) }
    catch (e: any) { toast({ title: "Could not load suppliers", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

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

  const pdfOpts = useMemo(() => ({
    title: "Supplier Balance Report",
    columns: [
      { header: "Supplier", key: "supplierName", width: 120 },
      { header: "Type", key: "supplierType", width: 80 },
      { header: "Phone", key: "phoneNumber", width: 80 },
      { header: "Balance", key: "balance", width: 80, align: "right" as const, format: "currency" as const },
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
            <div className="flex items-center justify-between flex-wrap gap-2 mb-2">
              <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700">
                <ArrowLeft className="h-3 w-3 mr-1" /> Reports
              </Link>
              <ReportExportButtons pdf={pdfOpts} disabled={loading} csvFilename="supplier-balances" />
            </div>
            <ReportPageHeader title="Supplier Balance Report" description="What is owed to suppliers, and any advances paid." />

            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 my-4">
              <RichCard label="Total Owed" value={fmt(totals.totalOwed)} accent="orange" lines={[`${totals.owedCount} supplier(s)`]} />
              <RichCard label="Total Advances" value={fmt(totals.totalCredit)} accent="emerald" lines={[`${totals.creditCount} supplier(s)`]} />
              <RichCard label="Net Payable" value={fmt(totals.totalOwed - totals.totalCredit)} accent="orange" lines={["Owed minus advances"]} />
              <RichCard label="Active Suppliers" value={String(totals.totalSuppliers)} lines={["With balances tracked"]} />
            </div>

            <Card className="mb-4">
              <CardContent className="pt-6">
                <ListFilters search={search} setSearch={setSearch} searchPlaceholder="Search supplier, type, phone..." />
                <div className="flex gap-2 mt-3">
                  {(["all", "owed", "credit"] as const).map((f) => (
                    <Button key={f} size="sm" variant={filter === f ? "default" : "outline"}
                      onClick={() => setFilter(f)}>{f === "all" ? "All" : f === "owed" ? "We Owe" : "Advance Paid"}</Button>
                  ))}
                </div>
              </CardContent>
            </Card>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : filtered.length === 0 ? (
              <Card><CardContent className="py-8 text-center text-slate-500">No suppliers match.</CardContent></Card>
            ) : (
              <Card>
                <CardContent className="p-0 md:p-2">
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
                        {pg.pageItems.map((r) => (
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
                              {fmt(r.currentBalance)}
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
  const color = { emerald: "text-emerald-700", orange: "text-orange-700", red: "text-red-600" }[accent ?? ""] ?? "text-slate-900"
  return (
    <Card><CardContent className="p-3">
      <div className="text-xs uppercase tracking-wide text-slate-500 truncate">{label}</div>
      <div className={cn("text-lg font-bold mt-1 truncate", color)}>{value}</div>
      {sub && <div className="text-xs text-slate-400">{sub}</div>}
    </CardContent></Card>
  )
}

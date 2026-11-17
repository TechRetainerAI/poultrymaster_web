"use client"

// Cash Movement — every cash inflow and outflow, by account and source type.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import { ArrowLeft, Loader2, TrendingDown, TrendingUp, Wallet } from "lucide-react"
import { ReportExportButtons } from "@/components/reports/report-export-buttons"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { listCashTransactions, getCashAccounts, type GenericCashTransaction } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { ReportPageHeader, RichCard } from "@/components/reports/report-header"

const DEFAULT = defaultReportRange()

export default function CashMovementReportPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericCashTransaction[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState(DEFAULT.from)
  const [dateTo, setDateTo] = useState(DEFAULT.to)
  const [accountFilter, setAccountFilter] = useState("ALL")
  const [directionFilter, setDirectionFilter] = useState("ALL")
  const [accounts, setAccounts] = useState<{ id: number; name: string }[]>([])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [txns, accts] = await Promise.all([
        listCashTransactions(),
        getCashAccounts().catch(() => []),
      ])
      setRows(txns)
      setAccounts(accts.map((a) => ({ id: a.genericCashAccountId, name: a.accountName })))
    } catch (e: any) {
      toast({ title: "Could not load cash movements", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  const filtered = useMemo(() => {
    let data = rows
    // Date filter
    if (dateFrom) data = data.filter((r) => r.transactionDate.slice(0, 10) >= dateFrom)
    if (dateTo) data = data.filter((r) => r.transactionDate.slice(0, 10) <= dateTo)
    // Account filter
    if (accountFilter !== "ALL") data = data.filter((r) => String(r.genericCashAccountId) === accountFilter)
    // Direction filter
    if (directionFilter === "IN") data = data.filter((r) => r.amount > 0)
    else if (directionFilter === "OUT") data = data.filter((r) => r.amount < 0)
    // Search
    return filterByDateAndSearch(data, { search, searchKeys: ["transactionType", "description", "accountName"] })
  }, [rows, dateFrom, dateTo, accountFilter, directionFilter, search])

  const pg = usePagination(filtered)

  const totals = useMemo(() => {
    let cashIn = 0, cashOut = 0
    for (const r of filtered) {
      if (r.amount > 0) cashIn += r.amount
      else cashOut += Math.abs(r.amount)
    }
    return { cashIn, cashOut, net: cashIn - cashOut, count: filtered.length }
  }, [filtered])

  const pdfOpts = useMemo(() => ({
    title: "Cash Movement Report",
    subtitle: `${dateFrom} to ${dateTo}`,
    columns: [
      { header: "Date", key: "date", width: 70 },
      { header: "Account", key: "accountName", width: 100 },
      { header: "Type", key: "transactionType", width: 80 },
      { header: "In", key: "inAmt", width: 70, align: "right" as const, format: "currency" as const },
      { header: "Out", key: "outAmt", width: 70, align: "right" as const, format: "currency" as const },
      { header: "Description", key: "description", width: 120 },
    ],
    rows: filtered.map((r) => ({
      date: fmtDateTime(r.transactionDate, r),
      accountName: r.accountName ?? "–",
      transactionType: r.transactionType,
      inAmt: r.amount > 0 ? r.amount : "",
      outAmt: r.amount < 0 ? Math.abs(r.amount) : "",
      description: r.description ?? "–",
    })),
  }), [filtered, dateFrom, dateTo])

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
              <ReportExportButtons pdf={pdfOpts} disabled={loading} csvFilename="cash-movement" />
            </div>
            <button onClick={() => router.back()} className="rounded-full p-1 hover:bg-slate-200 transition" title="Go back"><ArrowLeft className="w-5 h-5 text-slate-600" /></button>
            <ReportPageHeader title="Cash Movement" description="Every cash inflow and outflow across all accounts." period={{ from: dateFrom, to: dateTo }} />

            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 my-4">
              <RichCard label="Cash In" value={fmt(totals.cashIn)} accent="emerald" lines={["All money received"]} />
              <RichCard label="Cash Out" value={fmt(totals.cashOut)} accent="red" lines={["All money paid out"]} />
              <RichCard label="Net Movement" value={fmt(totals.net)} accent={totals.net >= 0 ? "emerald" : "red"} lines={[`In (${fmt(totals.cashIn)}) − Out (${fmt(totals.cashOut)})`]} />
              <RichCard label="Transactions" value={String(totals.count)} lines={["In this period"]} />
            </div>

            <Card className="mb-4">
              <CardContent className="pt-6 space-y-3">
                <ListFilters search={search} setSearch={setSearch} searchPlaceholder="Search type, description..."
                  dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} />
                <div className="flex flex-wrap gap-2">
                  <Select value={accountFilter} onValueChange={setAccountFilter}>
                    <SelectTrigger className="w-[200px]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All accounts</SelectItem>
                      {accounts.map((a) => <SelectItem key={a.id} value={String(a.id)}>{a.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Select value={directionFilter} onValueChange={setDirectionFilter}>
                    <SelectTrigger className="w-[150px]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All directions</SelectItem>
                      <SelectItem value="IN">Money In</SelectItem>
                      <SelectItem value="OUT">Money Out</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </CardContent>
            </Card>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : filtered.length === 0 ? (
              <Card><CardContent className="py-8 text-center text-slate-500">No cash movements found.</CardContent></Card>
            ) : (
              <Card>
                <CardContent className="p-0 md:p-2">
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Date</TableHead>
                          <TableHead>Account</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead className="text-right">In</TableHead>
                          <TableHead className="text-right">Out</TableHead>
                          <TableHead>Description</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((r) => (
                          <TableRow key={r.genericCashTransactionId}>
                            <TableCell className="whitespace-nowrap">{fmtDateTime(r.transactionDate, r)}</TableCell>
                            <TableCell>{r.accountName ?? "–"}</TableCell>
                            <TableCell>
                              <Badge className={r.amount > 0 ? "bg-emerald-100 text-emerald-800 hover:bg-emerald-100" : "bg-red-100 text-red-800 hover:bg-red-100"}>
                                {r.transactionType}
                              </Badge>
                            </TableCell>
                            <TableCell className="text-right tabular-nums text-emerald-700 font-medium">
                              {r.amount > 0 ? fmt(r.amount) : ""}
                            </TableCell>
                            <TableCell className="text-right tabular-nums text-red-600 font-medium">
                              {r.amount < 0 ? fmt(Math.abs(r.amount)) : ""}
                            </TableCell>
                            <TableCell className="max-w-xs truncate text-slate-600">{r.description ?? "–"}</TableCell>
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

function Tile({ icon: Icon, label, value, accent }: { icon: any; label: string; value: string; accent?: string }) {
  const color = { emerald: "text-emerald-700", red: "text-red-600" }[accent ?? ""] ?? "text-slate-900"
  return (
    <Card><CardContent className="p-3">
      <div className="flex items-center gap-1 text-xs uppercase tracking-wide text-slate-500"><Icon className="h-3.5 w-3.5" /> {label}</div>
      <div className={cn("text-lg font-bold mt-1 truncate", color)}>{value}</div>
    </CardContent></Card>
  )
}

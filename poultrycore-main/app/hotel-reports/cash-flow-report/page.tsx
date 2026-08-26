"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Loader2, ArrowLeft, Landmark, ArrowUpRight, ArrowDownLeft, TrendingUp, TrendingDown, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelCashAccounts, listCashTransactions, getHotelProfile,
  type HotelCashAccount, type HotelCashTransaction,
} from "@/lib/api/hotel"
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts"

export default function CashFlowReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [accounts, setAccounts] = useState<HotelCashAccount[]>([])
  const [transactions, setTransactions] = useState<HotelCashTransaction[]>([])
  const [loading, setLoading] = useState(true)
  const [pdfPreviewOpen, setPdfPreviewOpen] = useState(false)
  const [hotelName, setHotelName] = useState("Hotel")

  const today = new Date()
  const thirtyAgo = new Date(today); thirtyAgo.setDate(thirtyAgo.getDate() - 30)
  const [dateFrom, setDateFrom] = useState(thirtyAgo.toISOString().slice(0, 10))
  const [dateTo, setDateTo] = useState(today.toISOString().slice(0, 10))
  const [filterAccount, setFilterAccount] = useState("all")
  const [filterSource, setFilterSource] = useState("all")

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [accts, txns, profile] = await Promise.all([
        listHotelCashAccounts(),
        listCashTransactions(),
        getHotelProfile().catch(() => null),
      ])
      setAccounts(accts)
      setTransactions(txns)
      if (profile) setHotelName((profile as any).hotelName ?? (profile as any).hotelname ?? "Hotel")
    } catch (e: any) {
      toast({ title: "Failed to load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  // Filter transactions
  const filtered = transactions.filter((t) => {
    const txnDate = (t.txndate ?? "").slice(0, 10)
    if (txnDate < dateFrom || txnDate > dateTo) return false
    if (filterAccount !== "all" && String(t.hotelcashaccountid) !== filterAccount) return false
    if (filterSource !== "all" && (t.sourcetype ?? "") !== filterSource) return false
    return true
  })

  const totalCredits = filtered.filter(t => t.txntype === "Credit").reduce((s, t) => s + Number(t.amount), 0)
  const totalDebits = filtered.filter(t => t.txntype === "Debit").reduce((s, t) => s + Number(t.amount), 0)
  const netFlow = totalCredits - totalDebits
  const txnCount = filtered.length

  // Chart data: group by date
  const chartData = (() => {
    const map = new Map<string, { date: string; credits: number; debits: number }>()
    filtered.forEach((t) => {
      const d = (t.txndate ?? "").slice(0, 10)
      if (!map.has(d)) map.set(d, { date: d, credits: 0, debits: 0 })
      const entry = map.get(d)!
      if (t.txntype === "Credit") entry.credits += Number(t.amount)
      else entry.debits += Number(t.amount)
    })
    return Array.from(map.values()).sort((a, b) => a.date.localeCompare(b.date))
  })()

  // Per-account summary
  const accountSummary = accounts.map((a: any) => {
    const acctId = a.hotelCashAccountId ?? a.hotelcashaccountid
    const acctTxns = filtered.filter(t => t.hotelcashaccountid === acctId)
    const credits = acctTxns.filter(t => t.txntype === "Credit").reduce((s, t) => s + Number(t.amount), 0)
    const debits = acctTxns.filter(t => t.txntype === "Debit").reduce((s, t) => s + Number(t.amount), 0)
    return {
      name: a.accountName ?? a.accountname,
      purpose: a.purpose ?? null,
      balance: Number(a.currentBalance ?? a.currentbalance ?? 0),
      credits, debits, net: credits - debits, count: acctTxns.length,
    }
  }).filter(a => a.count > 0)

  // Source type breakdown
  const sources = ["Payment", "Expense", "Order", "Payroll"]
  const sourceBreakdown = sources.map(src => {
    const srcTxns = filtered.filter(t => t.sourcetype === src)
    const total = srcTxns.reduce((s, t) => s + Number(t.amount), 0)
    return { source: src, count: srcTxns.length, total }
  }).filter(s => s.count > 0)

  // Export data
  const csvHeaders = ["Date", "Account", "Type", "Amount", "Balance After", "Description", "Source", "Reference", "By"]
  const csvRows = filtered.map(t => [
    (t.txndate ?? "").slice(0, 10),
    t.accountname ?? "",
    t.txntype,
    Number(t.amount).toFixed(2),
    Number(t.balanceafter).toFixed(2),
    t.description ?? "",
    t.sourcetype ?? "",
    t.reference ?? "",
    t.createdby ?? "",
  ])

  const pdfConfig: PdfReportConfig = {
    title: "Cash Flow Report",
    hotelName, hotelAddress: "", hotelPhone: "", hotelEmail: "",
    dateRange: `${dateFrom} to ${dateTo}`,
    columns: csvHeaders,
    rows: csvRows,
    summary: [
      { label: "Total Inflow (Credits)", value: totalCredits.toFixed(2) },
      { label: "Total Outflow (Debits)", value: totalDebits.toFixed(2) },
      { label: "Net Cash Flow", value: netFlow.toFixed(2) },
      { label: "Transactions", value: String(txnCount) },
    ],
  }

  const printConfig: PrintReportConfig = {
    title: "Cash Flow Report",
    hotelName,
    dateRange: `${dateFrom} to ${dateTo}`,
    columns: csvHeaders,
    rows: csvRows,
    summary: pdfConfig.summary,
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Header */}
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-3">
              <Link href="/hotel-reports"><Button variant="ghost" size="icon"><ArrowLeft className="h-5 w-5" /></Button></Link>
              <Landmark className="h-6 w-6 text-violet-600" />
              <h1 className="text-2xl font-bold">Cash Flow Report</h1>
            </div>
            <div className="flex items-center gap-2">
              <Button variant="outline" size="sm" onClick={() => downloadCsv(csvHeaders, csvRows, "cash-flow-report")}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => printReport(printConfig)}><Printer className="h-4 w-4 mr-1" />Print</Button>
            </div>
          </div>

          {/* Filters */}
          <div className="flex gap-3 flex-wrap mb-4">
            <div><Label className="text-xs">From</Label><Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-40" /></div>
            <div><Label className="text-xs">To</Label><Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-40" /></div>
            <div>
              <Label className="text-xs">Account</Label>
              <Select value={filterAccount} onValueChange={setFilterAccount}>
                <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Accounts</SelectItem>
                  {accounts.map((a: any) => (
                    <SelectItem key={a.hotelCashAccountId ?? a.hotelcashaccountid} value={String(a.hotelCashAccountId ?? a.hotelcashaccountid)}>
                      {a.accountName ?? a.accountname}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label className="text-xs">Source</Label>
              <Select value={filterSource} onValueChange={setFilterSource}>
                <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Sources</SelectItem>
                  <SelectItem value="Payment">Payments</SelectItem>
                  <SelectItem value="Expense">Expenses</SelectItem>
                  <SelectItem value="Order">Restaurant</SelectItem>
                  <SelectItem value="Payroll">Payroll</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
            <>
              {/* Summary Cards */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center">
                  <TrendingUp className="h-5 w-5 mx-auto mb-1 text-emerald-600" />
                  <div className="text-2xl font-bold text-emerald-700">{totalCredits.toFixed(2)}</div>
                  <div className="text-xs text-slate-500">Total Inflow</div>
                </CardContent></Card>
                <Card><CardContent className="p-4 text-center">
                  <TrendingDown className="h-5 w-5 mx-auto mb-1 text-red-600" />
                  <div className="text-2xl font-bold text-red-700">{totalDebits.toFixed(2)}</div>
                  <div className="text-xs text-slate-500">Total Outflow</div>
                </CardContent></Card>
                <Card><CardContent className="p-4 text-center">
                  <Landmark className="h-5 w-5 mx-auto mb-1 text-violet-600" />
                  <div className={`text-2xl font-bold ${netFlow >= 0 ? "text-emerald-700" : "text-red-700"}`}>{netFlow.toFixed(2)}</div>
                  <div className="text-xs text-slate-500">Net Cash Flow</div>
                </CardContent></Card>
                <Card><CardContent className="p-4 text-center">
                  <div className="text-2xl font-bold text-slate-700">{txnCount}</div>
                  <div className="text-xs text-slate-500">Transactions</div>
                </CardContent></Card>
              </div>

              {/* Chart */}
              {chartData.length > 1 && (
                <Card className="mb-6">
                  <CardHeader className="pb-2"><CardTitle className="text-sm">Daily Cash Flow</CardTitle></CardHeader>
                  <CardContent>
                    <ResponsiveContainer width="100%" height={250}>
                      <BarChart data={chartData}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                        <YAxis tick={{ fontSize: 11 }} />
                        <Tooltip />
                        <Legend />
                        <Bar dataKey="credits" name="Inflow" fill="#059669" radius={[4,4,0,0]} />
                        <Bar dataKey="debits" name="Outflow" fill="#dc2626" radius={[4,4,0,0]} />
                      </BarChart>
                    </ResponsiveContainer>
                  </CardContent>
                </Card>
              )}

              {/* Account Summary + Source Breakdown */}
              <div className="grid md:grid-cols-2 gap-4 mb-6">
                {accountSummary.length > 0 && (
                  <Card>
                    <CardHeader className="pb-2"><CardTitle className="text-sm">By Account</CardTitle></CardHeader>
                    <CardContent className="p-0">
                      <table className="w-full text-sm">
                        <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Account</th><th className="text-right p-3 text-emerald-700">In</th><th className="text-right p-3 text-red-700">Out</th><th className="text-right p-3">Net</th><th className="text-right p-3">Balance</th></tr></thead>
                        <tbody>
                          {accountSummary.map((a, i) => (
                            <tr key={i} className="border-b">
                              <td className="p-3 font-medium">{a.name}{a.purpose && <Badge variant="outline" className="ml-1 text-[10px]">{a.purpose}</Badge>}</td>
                              <td className="p-3 text-right text-emerald-700">{a.credits.toFixed(2)}</td>
                              <td className="p-3 text-right text-red-700">{a.debits.toFixed(2)}</td>
                              <td className={`p-3 text-right font-semibold ${a.net >= 0 ? "text-emerald-700" : "text-red-700"}`}>{a.net.toFixed(2)}</td>
                              <td className="p-3 text-right font-bold text-violet-700">{a.balance.toFixed(2)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                )}
                {sourceBreakdown.length > 0 && (
                  <Card>
                    <CardHeader className="pb-2"><CardTitle className="text-sm">By Source</CardTitle></CardHeader>
                    <CardContent className="p-0">
                      <table className="w-full text-sm">
                        <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Source</th><th className="text-right p-3">Count</th><th className="text-right p-3">Total</th></tr></thead>
                        <tbody>
                          {sourceBreakdown.map((s, i) => (
                            <tr key={i} className="border-b"><td className="p-3 font-medium">{s.source}</td><td className="p-3 text-right">{s.count}</td><td className="p-3 text-right font-semibold">{s.total.toFixed(2)}</td></tr>
                          ))}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                )}
              </div>

              {/* Full Transaction Log */}
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-sm">Transaction Log ({filtered.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b">
                      <tr>
                        <th className="text-left p-3">Date</th>
                        <th className="text-left p-3">Account</th>
                        <th className="text-left p-3">Type</th>
                        <th className="text-left p-3">Description</th>
                        <th className="text-left p-3">Source</th>
                        <th className="text-left p-3">Reference</th>
                        <th className="text-right p-3">Amount</th>
                        <th className="text-right p-3">Balance</th>
                        <th className="text-left p-3">By</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filtered.map((t, idx) => (
                        <tr key={t.hotelcashtxnid ?? idx} className="border-b hover:bg-slate-50">
                          <td className="p-3 text-xs">{(t.txndate ?? "").slice(0, 10)}</td>
                          <td className="p-3 text-xs font-medium">{t.accountname ?? "—"}</td>
                          <td className="p-3">
                            {t.txntype === "Credit" ? (
                              <Badge variant="outline" className="bg-emerald-100 text-emerald-700 text-xs"><ArrowDownLeft className="h-3 w-3 mr-1" />In</Badge>
                            ) : (
                              <Badge variant="outline" className="bg-red-100 text-red-700 text-xs"><ArrowUpRight className="h-3 w-3 mr-1" />Out</Badge>
                            )}
                          </td>
                          <td className="p-3 max-w-[180px] truncate text-xs" title={t.description ?? ""}>{t.description ?? "—"}</td>
                          <td className="p-3"><Badge variant="outline" className="text-xs">{t.sourcetype ?? "—"}</Badge></td>
                          <td className="p-3 font-mono text-xs">{t.reference ?? "—"}</td>
                          <td className={`p-3 text-right font-semibold ${t.txntype === "Credit" ? "text-emerald-700" : "text-red-700"}`}>
                            {t.txntype === "Credit" ? "+" : "-"}{Number(t.amount).toFixed(2)}
                          </td>
                          <td className="p-3 text-right text-slate-600">{Number(t.balanceafter).toFixed(2)}</td>
                          <td className="p-3 text-xs text-slate-500">{t.createdby ?? "System"}</td>
                        </tr>
                      ))}
                      {filtered.length === 0 && <tr><td colSpan={9} className="p-8 text-center text-slate-400">No transactions found for the selected filters.</td></tr>}
                    </tbody>
                  </table>
                </CardContent>
              </Card>
            </>
          )}

          <PdfPreviewDialog open={pdfPreviewOpen} onOpenChange={setPdfPreviewOpen} config={pdfConfig} onDownload={() => downloadPdf(pdfConfig)} />
        </main>
      </div>
    </div>
  )
}

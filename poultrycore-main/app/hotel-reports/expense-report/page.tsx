"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, Receipt, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelExpenses, getHotelProfile } from "@/lib/api/hotel"

export default function ExpenseReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [data, setData] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [pdfPreviewOpen, setPdfPreviewOpen] = useState(false)
  const [hotelName, setHotelName] = useState("Hotel")
  const [hotelAddress, setHotelAddress] = useState("")
  const [hotelPhone, setHotelPhone] = useState("")
  const [hotelEmail, setHotelEmail] = useState("")

  const today = new Date()
  const thirtyAgo = new Date(today)
  thirtyAgo.setDate(thirtyAgo.getDate() - 30)
  const [dateFrom, setDateFrom] = useState(thirtyAgo.toISOString().slice(0, 10))
  const [dateTo, setDateTo] = useState(today.toISOString().slice(0, 10))

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const res = await listHotelExpenses()
      setData(res)
      try {
        const profile = await getHotelProfile()
        setHotelName(profile.hotelName ?? profile.hotelname ?? "Hotel")
        setHotelAddress(profile.address ?? profile.city ?? "")
        setHotelPhone(profile.phone ?? "")
        setHotelEmail(profile.email ?? "")
      } catch {}
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  const filtered = data.filter((x: any) => {
    const d = (x.expenseDate ?? x.expensedate ?? "").slice(0, 10)
    return d >= dateFrom && d <= dateTo
  })

  const totalExpenses = filtered.reduce((s: number, x: any) => s + Number(x.amount ?? 0), 0)
  const avgPerExpense = filtered.length > 0 ? totalExpenses / filtered.length : 0

  // Group by category
  const categoryMap: Record<string, { count: number; total: number }> = {}
  filtered.forEach((x: any) => {
    const cat = x.category ?? "Uncategorized"
    if (!categoryMap[cat]) categoryMap[cat] = { count: 0, total: 0 }
    categoryMap[cat].count += 1
    categoryMap[cat].total += Number(x.amount ?? 0)
  })
  const categories = Object.entries(categoryMap).sort((a, b) => b[1].total - a[1].total)

  function handleDownload() {
    const headers = ["Date", "Category", "Description", "Vendor", "Amount"]
    const rows = filtered.map((x: any) => [
      (x.expenseDate ?? x.expensedate ?? "").slice(0, 10),
      x.category ?? "",
      x.description ?? "",
      x.vendor ?? "",
      Number(x.amount ?? 0).toFixed(2),
    ])
    downloadCsv("expense-report", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Date", "Category", "Description", "Vendor", "Amount"]
    const rows = filtered.map((x: any) => [
      (x.expenseDate ?? x.expensedate ?? "").slice(0, 10),
      x.category ?? "",
      x.description ?? "",
      x.vendor ?? "",
      Number(x.amount ?? 0).toFixed(2),
    ])
    return {
      title: "Expense Report",
      subtitle: "Hotel Management Report",
      filename: "expense-report",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Expenses", value: `GH\u20B5${totalExpenses.toFixed(2)}` },
        { label: "Categories", value: `${categories.length}` },
        { label: "Avg per Expense", value: `GH\u20B5${avgPerExpense.toFixed(2)}` },
      ],
      dateRange: { from: dateFrom, to: dateTo },
      currency: "GH\u20B5",
    }
  }

  const sortedFiltered = [...filtered].sort((a: any, b: any) => Number(b.amount ?? 0) - Number(a.amount ?? 0))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <Receipt className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Expense Report</h1>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={handleDownload}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => downloadPdf(getPdfConfig())}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />Preview</Button>
              <Button variant="outline" size="sm" onClick={() => { const c = getPdfConfig(); printReport({ hotelName, hotelAddress, hotelPhone, hotelEmail, title: c.title, dateRange: c.dateRange, summaryCards: c.summaryCards, headers: c.headers, rows: c.rows, currency: "" }) }}><Printer className="h-4 w-4 mr-1" />Print</Button>
            </div>
          </div>

          {/* Date Range Filter */}
          <div className="flex flex-wrap items-center gap-3 mb-6">
            <label className="text-sm font-medium text-slate-600">From</label>
            <input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="border rounded px-3 py-1.5 text-sm" />
            <label className="text-sm font-medium text-slate-600">To</label>
            <input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="border rounded px-3 py-1.5 text-sm" />
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <>
              {/* Summary Cards */}
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">{totalExpenses.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Expenses</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{categories.length}</div><div className="text-xs text-slate-500 mt-1">Categories</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-amber-600">{avgPerExpense.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Avg per Expense</div></CardContent></Card>
              </div>

              {/* Category Summary */}
              {categories.length > 0 && (
                <Card className="mb-6">
                  <CardHeader><CardTitle className="text-base">By Category</CardTitle></CardHeader>
                  <CardContent className="p-0">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Category</th>
                          <th className="text-right p-3">Count</th>
                          <th className="text-right p-3">Total Amount</th>
                        </tr>
                      </thead>
                      <tbody>
                        {categories.map(([cat, info]) => (
                          <tr key={cat} className="border-b hover:bg-slate-50">
                            <td className="p-3 font-medium">{cat}</td>
                            <td className="p-3 text-right">{info.count}</td>
                            <td className="p-3 text-right text-red-600">{info.total.toFixed(2)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </CardContent>
                </Card>
              )}

              {/* Detail Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Expense Details ({filtered.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Date</th>
                          <th className="text-left p-3">Category</th>
                          <th className="text-left p-3">Description</th>
                          <th className="text-left p-3">Vendor</th>
                          <th className="text-right p-3">Amount</th>
                        </tr>
                      </thead>
                      <tbody>
                        {sortedFiltered.map((x: any, idx: number) => (
                          <tr key={x.hotelExpenseId ?? x.hotelexpenseid ?? `exp-${idx}`} className="border-b hover:bg-slate-50">
                            <td className="p-3">{(x.expenseDate ?? x.expensedate ?? "").slice(0, 10)}</td>
                            <td className="p-3">{x.category ?? ""}</td>
                            <td className="p-3">{x.description ?? ""}</td>
                            <td className="p-3">{x.vendor ?? "-"}</td>
                            <td className="p-3 text-right text-red-600 font-medium">{Number(x.amount ?? 0).toFixed(2)}</td>
                          </tr>
                        ))}
                        {filtered.length === 0 && (
                          <tr><td colSpan={5} className="p-8 text-center text-slate-400">No expenses found for this period.</td></tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>
      <PdfPreviewDialog open={pdfPreviewOpen} onOpenChange={setPdfPreviewOpen} config={pdfPreviewOpen ? getPdfConfig() : null} />
    </div>
  )
}

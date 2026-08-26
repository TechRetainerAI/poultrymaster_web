"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, TrendingUp, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listDailyClosings, getHotelProfile } from "@/lib/api/hotel"
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts"

export default function RevenueSummaryPage() {
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
      const res = await listDailyClosings()
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

  const filtered = data.filter((c: any) => {
    const d = (c.closingDate ?? c.closingdate ?? "").slice(0, 10)
    return d >= dateFrom && d <= dateTo
  })

  const totalRevenue = filtered.reduce((s: number, c: any) => s + Number(c.totalRevenue ?? c.totalrevenue ?? 0), 0)
  const totalExpenses = filtered.reduce((s: number, c: any) => s + Number(c.totalExpenses ?? c.totalexpenses ?? 0), 0)
  const netProfit = totalRevenue - totalExpenses
  const avgOccupancy = filtered.length > 0
    ? filtered.reduce((s: number, c: any) => s + Number(c.occupancyRate ?? c.occupancyrate ?? 0), 0) / filtered.length
    : 0

  function handleDownload() {
    const headers = ["Date", "Revenue", "Expenses", "Net", "Occupancy %", "Rooms Occupied", "ADR", "RevPAR"]
    const rows = filtered.map((c: any) => {
      const rev = Number(c.totalRevenue ?? c.totalrevenue ?? 0)
      const exp = Number(c.totalExpenses ?? c.totalexpenses ?? 0)
      return [
        (c.closingDate ?? c.closingdate ?? "").slice(0, 10),
        rev.toFixed(2),
        exp.toFixed(2),
        (rev - exp).toFixed(2),
        Number(c.occupancyRate ?? c.occupancyrate ?? 0).toFixed(1),
        `${c.roomsOccupied ?? c.roomsoccupied ?? 0}/${c.totalRooms ?? c.totalrooms ?? 0}`,
        Number(c.adr ?? 0).toFixed(2),
        Number(c.revPar ?? c.revpar ?? 0).toFixed(2),
      ]
    })
    downloadCsv("revenue-summary", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Date", "Revenue", "Expenses", "Net", "Occupancy %", "Rooms Occupied", "ADR", "RevPAR"]
    const rows = filtered.map((c: any) => {
      const rev = Number(c.totalRevenue ?? c.totalrevenue ?? 0)
      const exp = Number(c.totalExpenses ?? c.totalexpenses ?? 0)
      return [
        (c.closingDate ?? c.closingdate ?? "").slice(0, 10),
        rev.toFixed(2),
        exp.toFixed(2),
        (rev - exp).toFixed(2),
        Number(c.occupancyRate ?? c.occupancyrate ?? 0).toFixed(1),
        `${c.roomsOccupied ?? c.roomsoccupied ?? 0}/${c.totalRooms ?? c.totalrooms ?? 0}`,
        Number(c.adr ?? 0).toFixed(2),
        Number(c.revPar ?? c.revpar ?? 0).toFixed(2),
      ]
    })
    return {
      title: "Revenue Summary",
      subtitle: "Hotel Management Report",
      filename: "revenue-summary",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Revenue", value: `GH\u20B5${totalRevenue.toFixed(2)}` },
        { label: "Total Expenses", value: `GH\u20B5${totalExpenses.toFixed(2)}` },
        { label: "Net Profit", value: `GH\u20B5${netProfit.toFixed(2)}` },
        { label: "Avg Occupancy", value: `${avgOccupancy.toFixed(1)}%` },
      ],
      dateRange: { from: dateFrom, to: dateTo },
      currency: "GH\u20B5",
    }
  }

  const chartData = filtered
    .sort((a: any, b: any) => {
      const da = (a.closingDate ?? a.closingdate ?? "").slice(0, 10)
      const db = (b.closingDate ?? b.closingdate ?? "").slice(0, 10)
      return da.localeCompare(db)
    })
    .map((c: any) => ({
      date: (c.closingDate ?? c.closingdate ?? "").slice(5, 10),
      revenue: Number(c.totalRevenue ?? c.totalrevenue ?? 0),
      expenses: Number(c.totalExpenses ?? c.totalexpenses ?? 0),
    }))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <TrendingUp className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Revenue Summary</h1>
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
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{totalRevenue.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Revenue</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">{totalExpenses.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Expenses</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className={`text-2xl font-bold ${netProfit >= 0 ? "text-emerald-700" : "text-red-700"}`}>{netProfit.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Net Profit</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{avgOccupancy.toFixed(1)}%</div><div className="text-xs text-slate-500 mt-1">Avg Occupancy</div></CardContent></Card>
              </div>

              {/* Bar Chart */}
              {chartData.length > 0 && (
                <Card className="mb-6">
                  <CardHeader><CardTitle className="text-base">Revenue vs Expenses</CardTitle></CardHeader>
                  <CardContent>
                    <ResponsiveContainer width="100%" height={300}>
                      <BarChart data={chartData}>
                        <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                        <XAxis dataKey="date" tick={{ fontSize: 12 }} />
                        <YAxis tick={{ fontSize: 12 }} />
                        <Tooltip formatter={(val: number) => `GH\u20B5${val.toFixed(2)}`} />
                        <Legend />
                        <Bar dataKey="revenue" name="Revenue" fill="#7c3aed" radius={[4, 4, 0, 0]} />
                        <Bar dataKey="expenses" name="Expenses" fill="#ef4444" radius={[4, 4, 0, 0]} />
                      </BarChart>
                    </ResponsiveContainer>
                  </CardContent>
                </Card>
              )}

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Daily Closings ({filtered.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Date</th>
                          <th className="text-right p-3">Revenue</th>
                          <th className="text-right p-3">Expenses</th>
                          <th className="text-right p-3">Net</th>
                          <th className="text-right p-3">Occupancy %</th>
                          <th className="text-right p-3">Rooms Occupied</th>
                          <th className="text-right p-3">ADR</th>
                          <th className="text-right p-3">RevPAR</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filtered
                          .sort((a: any, b: any) => {
                            const da = (a.closingDate ?? a.closingdate ?? "").slice(0, 10)
                            const db = (b.closingDate ?? b.closingdate ?? "").slice(0, 10)
                            return db.localeCompare(da)
                          })
                          .map((c: any, idx: number) => {
                            const rev = Number(c.totalRevenue ?? c.totalrevenue ?? 0)
                            const exp = Number(c.totalExpenses ?? c.totalexpenses ?? 0)
                            const net = rev - exp
                            return (
                              <tr key={c.hotelDailyClosingId ?? c.hoteldailyclosingid ?? `dc-${idx}`} className="border-b hover:bg-slate-50">
                                <td className="p-3 font-medium">{(c.closingDate ?? c.closingdate ?? "").slice(0, 10)}</td>
                                <td className="p-3 text-right text-emerald-700">{rev.toFixed(2)}</td>
                                <td className="p-3 text-right text-red-600">{exp.toFixed(2)}</td>
                                <td className={`p-3 text-right font-bold ${net >= 0 ? "text-emerald-700" : "text-red-700"}`}>{net.toFixed(2)}</td>
                                <td className="p-3 text-right">{Number(c.occupancyRate ?? c.occupancyrate ?? 0).toFixed(1)}%</td>
                                <td className="p-3 text-right">{c.roomsOccupied ?? c.roomsoccupied ?? 0}/{c.totalRooms ?? c.totalrooms ?? 0}</td>
                                <td className="p-3 text-right">{Number(c.adr ?? 0).toFixed(2)}</td>
                                <td className="p-3 text-right">{Number(c.revPar ?? c.revpar ?? 0).toFixed(2)}</td>
                              </tr>
                            )
                          })}
                        {filtered.length === 0 && (
                          <tr><td colSpan={8} className="p-8 text-center text-slate-400">No closings found for this period.</td></tr>
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

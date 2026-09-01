"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, Calendar, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelBookings, listHotelPayments, listHotelExpenses, listDailyClosings, getHotelProfile } from "@/lib/api/hotel"

function getMonday(d: Date): Date {
  const day = d.getDay()
  const diff = d.getDate() - day + (day === 0 ? -6 : 1)
  const m = new Date(d)
  m.setDate(diff)
  return m
}

function addDays(d: string, n: number): string {
  const dt = new Date(d + "T00:00:00")
  dt.setDate(dt.getDate() + n)
  return dt.toISOString().slice(0, 10)
}

export default function WeeklyReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [bookings, setBookings] = useState<any[]>([])
  const [payments, setPayments] = useState<any[]>([])
  const [expenses, setExpenses] = useState<any[]>([])
  const [closings, setClosings] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [pdfPreviewOpen, setPdfPreviewOpen] = useState(false)
  const [hotelName, setHotelName] = useState("Hotel")
  const [hotelAddress, setHotelAddress] = useState("")
  const [hotelPhone, setHotelPhone] = useState("")
  const [hotelEmail, setHotelEmail] = useState("")

  const [weekStart, setWeekStart] = useState(getMonday(new Date()).toISOString().slice(0, 10))
  const weekEnd = addDays(weekStart, 6)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [b, p, e, c] = await Promise.all([
        listHotelBookings(),
        listHotelPayments(),
        listHotelExpenses(),
        listDailyClosings(),
      ])
      setBookings(b)
      setPayments(p)
      setExpenses(e)
      setClosings(c)
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

  // Build 7-day rows
  const dayRows: { date: string; revenue: number; expenses: number; checkIns: number; checkOuts: number; paymentsTotal: number }[] = []
  for (let i = 0; i < 7; i++) {
    const d = addDays(weekStart, i)
    const closing = closings.find((c: any) => (c.closingDate ?? c.closingdate ?? "").slice(0, 10) === d)
    const dayRev = closing ? Number(closing.totalRevenue ?? closing.totalrevenue ?? 0) : payments.filter((p: any) => (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10) === d).reduce((s: number, p: any) => s + Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0), 0)
    const dayExp = closing ? Number(closing.totalExpenses ?? closing.totalexpenses ?? 0) : expenses.filter((x: any) => (x.expenseDate ?? x.expensedate ?? "").slice(0, 10) === d).reduce((s: number, x: any) => s + Number(x.amount ?? 0), 0)
    const ci = bookings.filter((b: any) => (b.checkInDate ?? b.checkindate ?? "").slice(0, 10) === d).length
    const co = bookings.filter((b: any) => (b.checkOutDate ?? b.checkoutdate ?? "").slice(0, 10) === d).length
    const pt = payments.filter((p: any) => (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10) === d).reduce((s: number, p: any) => s + Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0), 0)
    dayRows.push({ date: d, revenue: dayRev, expenses: dayExp, checkIns: ci, checkOuts: co, paymentsTotal: pt })
  }

  const totalRevenue = dayRows.reduce((s, r) => s + r.revenue, 0)
  const totalExpenses = dayRows.reduce((s, r) => s + r.expenses, 0)
  const netProfit = totalRevenue - totalExpenses
  const totalBookings = bookings.filter((b: any) => {
    const ci = (b.checkInDate ?? b.checkindate ?? "").slice(0, 10)
    return ci >= weekStart && ci <= weekEnd
  }).length

  function handleDownload() {
    const headers = ["Date", "Revenue", "Expenses", "Check-ins", "Check-outs", "Payments Total"]
    const rows = dayRows.map((r) => [
      r.date,
      r.revenue.toFixed(2),
      r.expenses.toFixed(2),
      r.checkIns,
      r.checkOuts,
      r.paymentsTotal.toFixed(2),
    ])
    downloadCsv(`weekly-report-${weekStart}`, headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Date", "Revenue", "Expenses", "Check-ins", "Check-outs", "Payments Total"]
    const rows = dayRows.map((r) => [
      r.date,
      r.revenue.toFixed(2),
      r.expenses.toFixed(2),
      r.checkIns,
      r.checkOuts,
      r.paymentsTotal.toFixed(2),
    ])
    return {
      title: "Weekly Report",
      subtitle: "Hotel Management Report",
      filename: `weekly-report-${weekStart}`,
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Revenue", value: `GH\u20B5${totalRevenue.toFixed(2)}` },
        { label: "Total Expenses", value: `GH\u20B5${totalExpenses.toFixed(2)}` },
        { label: "Net Profit", value: `GH\u20B5${netProfit.toFixed(2)}` },
        { label: "Bookings", value: `${totalBookings}` },
      ],
      dateRange: { from: weekStart, to: weekEnd },
      currency: "GH\u20B5",
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <Calendar className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Weekly Report</h1>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={handleDownload}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => downloadPdf(getPdfConfig())}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />Preview</Button>
              <Button variant="outline" size="sm" onClick={() => { const c = getPdfConfig(); printReport({ hotelName, hotelAddress, hotelPhone, hotelEmail, title: c.title, dateRange: c.dateRange, summaryCards: c.summaryCards, headers: c.headers, rows: c.rows, currency: "GH\u20B5" }) }}><Printer className="h-4 w-4 mr-1" />Print</Button>
            </div>
          </div>

          {/* Week Start Picker */}
          <div className="flex flex-wrap items-center gap-3 mb-6">
            <label className="text-sm font-medium text-slate-600">Week Start</label>
            <input type="date" value={weekStart} onChange={(e) => setWeekStart(e.target.value)} className="border rounded px-3 py-1.5 text-sm" />
            <span className="text-sm text-slate-500">to {weekEnd}</span>
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
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalBookings}</div><div className="text-xs text-slate-500 mt-1">Bookings</div></CardContent></Card>
              </div>

              {/* Day-by-day Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Daily Breakdown</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Date</th>
                          <th className="text-right p-3">Revenue</th>
                          <th className="text-right p-3">Expenses</th>
                          <th className="text-right p-3">Check-ins</th>
                          <th className="text-right p-3">Check-outs</th>
                          <th className="text-right p-3">Payments Total</th>
                        </tr>
                      </thead>
                      <tbody>
                        {dayRows.map((r) => (
                          <tr key={r.date} className="border-b hover:bg-slate-50">
                            <td className="p-3 font-medium">{r.date}</td>
                            <td className="p-3 text-right text-emerald-700">{r.revenue.toFixed(2)}</td>
                            <td className="p-3 text-right text-red-600">{r.expenses.toFixed(2)}</td>
                            <td className="p-3 text-right">{r.checkIns}</td>
                            <td className="p-3 text-right">{r.checkOuts}</td>
                            <td className="p-3 text-right text-emerald-700 font-medium">{r.paymentsTotal.toFixed(2)}</td>
                          </tr>
                        ))}
                        <tr className="bg-slate-100 font-bold">
                          <td className="p-3">Total</td>
                          <td className="p-3 text-right text-emerald-700">{totalRevenue.toFixed(2)}</td>
                          <td className="p-3 text-right text-red-600">{totalExpenses.toFixed(2)}</td>
                          <td className="p-3 text-right">{dayRows.reduce((s, r) => s + r.checkIns, 0)}</td>
                          <td className="p-3 text-right">{dayRows.reduce((s, r) => s + r.checkOuts, 0)}</td>
                          <td className="p-3 text-right text-emerald-700">{dayRows.reduce((s, r) => s + r.paymentsTotal, 0).toFixed(2)}</td>
                        </tr>
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

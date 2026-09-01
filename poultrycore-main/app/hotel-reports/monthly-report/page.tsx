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
import { listHotelBookings, listHotelPayments, listHotelExpenses, listDailyClosings, listHotelStaff, getHotelProfile } from "@/lib/api/hotel"

const MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

function getWeekNumber(dateStr: string, monthStart: string): number {
  const d = new Date(dateStr + "T00:00:00")
  const ms = new Date(monthStart + "T00:00:00")
  const diff = Math.floor((d.getTime() - ms.getTime()) / (1000 * 60 * 60 * 24))
  return Math.floor(diff / 7) + 1
}

export default function MonthlyReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [bookings, setBookings] = useState<any[]>([])
  const [payments, setPayments] = useState<any[]>([])
  const [expenses, setExpenses] = useState<any[]>([])
  const [closings, setClosings] = useState<any[]>([])
  const [staff, setStaff] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [pdfPreviewOpen, setPdfPreviewOpen] = useState(false)
  const [hotelName, setHotelName] = useState("Hotel")
  const [hotelAddress, setHotelAddress] = useState("")
  const [hotelPhone, setHotelPhone] = useState("")
  const [hotelEmail, setHotelEmail] = useState("")

  const now = new Date()
  const [selMonth, setSelMonth] = useState(now.getMonth())
  const [selYear, setSelYear] = useState(now.getFullYear())

  const monthStart = `${selYear}-${String(selMonth + 1).padStart(2, "0")}-01`
  const nextMonth = selMonth === 11 ? `${selYear + 1}-01-01` : `${selYear}-${String(selMonth + 2).padStart(2, "0")}-01`
  const lastDay = new Date(new Date(nextMonth + "T00:00:00").getTime() - 86400000).toISOString().slice(0, 10)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [b, p, e, c, s] = await Promise.all([
        listHotelBookings(),
        listHotelPayments(),
        listHotelExpenses(),
        listDailyClosings(),
        listHotelStaff(),
      ])
      setBookings(b)
      setPayments(p)
      setExpenses(e)
      setClosings(c)
      setStaff(s)
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

  // Filter to selected month
  const monthClosings = closings.filter((c: any) => {
    const d = (c.closingDate ?? c.closingdate ?? "").slice(0, 10)
    return d >= monthStart && d <= lastDay
  })
  const monthBookings = bookings.filter((b: any) => {
    const ci = (b.checkInDate ?? b.checkindate ?? "").slice(0, 10)
    return ci >= monthStart && ci <= lastDay
  })
  const monthPayments = payments.filter((p: any) => {
    const d = (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10)
    return d >= monthStart && d <= lastDay
  })
  const monthExpenses = expenses.filter((x: any) => {
    const d = (x.expenseDate ?? x.expensedate ?? "").slice(0, 10)
    return d >= monthStart && d <= lastDay
  })

  const totalRevenue = monthClosings.length > 0
    ? monthClosings.reduce((s: number, c: any) => s + Number(c.totalRevenue ?? c.totalrevenue ?? 0), 0)
    : monthPayments.reduce((s: number, p: any) => s + Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0), 0)
  const totalExpenses = monthClosings.length > 0
    ? monthClosings.reduce((s: number, c: any) => s + Number(c.totalExpenses ?? c.totalexpenses ?? 0), 0)
    : monthExpenses.reduce((s: number, x: any) => s + Number(x.amount ?? 0), 0)
  const netProfit = totalRevenue - totalExpenses
  const totalBookingsCount = monthBookings.length
  const staffCount = staff.length

  // Week-by-week breakdown (from closings)
  const weekMap: Record<number, { revenue: number; expenses: number; bookings: number; payments: number }> = {}
  monthClosings.forEach((c: any) => {
    const d = (c.closingDate ?? c.closingdate ?? "").slice(0, 10)
    const wk = getWeekNumber(d, monthStart)
    if (!weekMap[wk]) weekMap[wk] = { revenue: 0, expenses: 0, bookings: 0, payments: 0 }
    weekMap[wk].revenue += Number(c.totalRevenue ?? c.totalrevenue ?? 0)
    weekMap[wk].expenses += Number(c.totalExpenses ?? c.totalexpenses ?? 0)
  })
  monthBookings.forEach((b: any) => {
    const d = (b.checkInDate ?? b.checkindate ?? "").slice(0, 10)
    const wk = getWeekNumber(d, monthStart)
    if (!weekMap[wk]) weekMap[wk] = { revenue: 0, expenses: 0, bookings: 0, payments: 0 }
    weekMap[wk].bookings += 1
  })
  monthPayments.forEach((p: any) => {
    const d = (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10)
    const wk = getWeekNumber(d, monthStart)
    if (!weekMap[wk]) weekMap[wk] = { revenue: 0, expenses: 0, bookings: 0, payments: 0 }
    weekMap[wk].payments += Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0)
  })
  const weekRows = Object.entries(weekMap).sort((a, b) => Number(a[0]) - Number(b[0]))

  function handleDownload() {
    if (weekRows.length > 0) {
      const headers = ["Week", "Revenue", "Expenses", "Bookings", "Payments"]
      const rows = weekRows.map(([wk, info]) => [
        `Week ${wk}`,
        info.revenue.toFixed(2),
        info.expenses.toFixed(2),
        info.bookings,
        info.payments.toFixed(2),
      ])
      downloadCsv(`monthly-report-${monthStart.slice(0, 7)}`, headers, rows)
    } else {
      const headers = ["Metric", "Value"]
      const rows = [
        ["Total Revenue", totalRevenue.toFixed(2)],
        ["Total Expenses", totalExpenses.toFixed(2)],
        ["Net Profit", netProfit.toFixed(2)],
        ["Total Bookings", totalBookingsCount],
        ["Staff Count", staffCount],
      ]
      downloadCsv(`monthly-report-${monthStart.slice(0, 7)}`, headers, rows)
    }
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = weekRows.length > 0
      ? ["Week", "Revenue", "Expenses", "Bookings", "Payments"]
      : ["Metric", "Value"]
    const rows = weekRows.length > 0
      ? weekRows.map(([wk, info]) => [`Week ${wk}`, info.revenue.toFixed(2), info.expenses.toFixed(2), info.bookings, info.payments.toFixed(2)])
      : [["Total Revenue", `GH\u20B5${totalRevenue.toFixed(2)}`], ["Total Expenses", `GH\u20B5${totalExpenses.toFixed(2)}`], ["Net Profit", `GH\u20B5${netProfit.toFixed(2)}`], ["Total Bookings", `${totalBookingsCount}`], ["Staff Count", `${staffCount}`]]
    return {
      title: `Monthly Report - ${MONTH_NAMES[selMonth]} ${selYear}`,
      subtitle: "Hotel Management Report",
      filename: `monthly-report-${monthStart.slice(0, 7)}`,
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Revenue", value: `GH\u20B5${totalRevenue.toFixed(2)}` },
        { label: "Total Expenses", value: `GH\u20B5${totalExpenses.toFixed(2)}` },
        { label: "Net Profit", value: `GH\u20B5${netProfit.toFixed(2)}` },
        { label: "Bookings", value: `${totalBookingsCount}` },
      ],
      dateRange: { from: monthStart, to: lastDay },
      currency: "GH\u20B5",
    }
  }

  const years: number[] = []
  for (let y = now.getFullYear() - 5; y <= now.getFullYear() + 1; y++) years.push(y)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <Calendar className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Monthly Report</h1>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={handleDownload}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => downloadPdf(getPdfConfig())}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />Preview</Button>
              <Button variant="outline" size="sm" onClick={() => { const c = getPdfConfig(); printReport({ hotelName, hotelAddress, hotelPhone, hotelEmail, title: c.title, dateRange: c.dateRange, summaryCards: c.summaryCards, headers: c.headers, rows: c.rows, currency: "GH\u20B5" }) }}><Printer className="h-4 w-4 mr-1" />Print</Button>
            </div>
          </div>

          {/* Month Selector */}
          <div className="flex flex-wrap items-center gap-3 mb-6">
            <label className="text-sm font-medium text-slate-600">Month</label>
            <select value={selMonth} onChange={(e) => setSelMonth(Number(e.target.value))} className="border rounded px-3 py-1.5 text-sm">
              {MONTH_NAMES.map((m, i) => <option key={i} value={i}>{m}</option>)}
            </select>
            <label className="text-sm font-medium text-slate-600">Year</label>
            <select value={selYear} onChange={(e) => setSelYear(Number(e.target.value))} className="border rounded px-3 py-1.5 text-sm">
              {years.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <>
              {/* Summary Cards */}
              <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{totalRevenue.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Revenue</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">{totalExpenses.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Expenses</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className={`text-2xl font-bold ${netProfit >= 0 ? "text-emerald-700" : "text-red-700"}`}>{netProfit.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Net Profit</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalBookingsCount}</div><div className="text-xs text-slate-500 mt-1">Total Bookings</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-blue-600">{staffCount}</div><div className="text-xs text-slate-500 mt-1">Staff Count</div></CardContent></Card>
              </div>

              {/* Week-by-week or Totals Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">{weekRows.length > 0 ? "Week-by-Week Breakdown" : "Monthly Totals"}</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    {weekRows.length > 0 ? (
                      <table className="w-full text-sm">
                        <thead className="bg-slate-50 border-b">
                          <tr>
                            <th className="text-left p-3">Week</th>
                            <th className="text-right p-3">Revenue</th>
                            <th className="text-right p-3">Expenses</th>
                            <th className="text-right p-3">Bookings</th>
                            <th className="text-right p-3">Payments</th>
                          </tr>
                        </thead>
                        <tbody>
                          {weekRows.map(([wk, info]) => (
                            <tr key={wk} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">Week {wk}</td>
                              <td className="p-3 text-right text-emerald-700">{info.revenue.toFixed(2)}</td>
                              <td className="p-3 text-right text-red-600">{info.expenses.toFixed(2)}</td>
                              <td className="p-3 text-right">{info.bookings}</td>
                              <td className="p-3 text-right text-emerald-700">{info.payments.toFixed(2)}</td>
                            </tr>
                          ))}
                          <tr className="bg-slate-100 font-bold">
                            <td className="p-3">Total</td>
                            <td className="p-3 text-right text-emerald-700">{totalRevenue.toFixed(2)}</td>
                            <td className="p-3 text-right text-red-600">{totalExpenses.toFixed(2)}</td>
                            <td className="p-3 text-right">{totalBookingsCount}</td>
                            <td className="p-3 text-right text-emerald-700">{monthPayments.reduce((s: number, p: any) => s + Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0), 0).toFixed(2)}</td>
                          </tr>
                        </tbody>
                      </table>
                    ) : (
                      <table className="w-full text-sm">
                        <thead className="bg-slate-50 border-b">
                          <tr>
                            <th className="text-left p-3">Metric</th>
                            <th className="text-right p-3">Value</th>
                          </tr>
                        </thead>
                        <tbody>
                          <tr className="border-b hover:bg-slate-50"><td className="p-3 font-medium">Total Revenue</td><td className="p-3 text-right text-emerald-700">{totalRevenue.toFixed(2)}</td></tr>
                          <tr className="border-b hover:bg-slate-50"><td className="p-3 font-medium">Total Expenses</td><td className="p-3 text-right text-red-600">{totalExpenses.toFixed(2)}</td></tr>
                          <tr className="border-b hover:bg-slate-50"><td className="p-3 font-medium">Net Profit</td><td className={`p-3 text-right font-bold ${netProfit >= 0 ? "text-emerald-700" : "text-red-700"}`}>{netProfit.toFixed(2)}</td></tr>
                          <tr className="border-b hover:bg-slate-50"><td className="p-3 font-medium">Total Bookings</td><td className="p-3 text-right">{totalBookingsCount}</td></tr>
                          <tr className="border-b hover:bg-slate-50"><td className="p-3 font-medium">Staff Count</td><td className="p-3 text-right">{staffCount}</td></tr>
                          {monthBookings.length === 0 && monthPayments.length === 0 && monthExpenses.length === 0 && (
                            <tr><td colSpan={2} className="p-8 text-center text-slate-400">No data found for this month.</td></tr>
                          )}
                        </tbody>
                      </table>
                    )}
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

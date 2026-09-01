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

export default function DailyReportPage() {
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

  const [selectedDate, setSelectedDate] = useState(new Date().toISOString().slice(0, 10))

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

  const checkIns = bookings.filter((b: any) => (b.checkInDate ?? b.checkindate ?? "").slice(0, 10) === selectedDate)
  const checkOuts = bookings.filter((b: any) => (b.checkOutDate ?? b.checkoutdate ?? "").slice(0, 10) === selectedDate)
  const dayPayments = payments.filter((p: any) => (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10) === selectedDate)
  const dayExpenses = expenses.filter((x: any) => (x.expenseDate ?? x.expensedate ?? "").slice(0, 10) === selectedDate)
  const dayClosing = closings.find((c: any) => (c.closingDate ?? c.closingdate ?? "").slice(0, 10) === selectedDate)

  const revenue = dayClosing ? Number(dayClosing.totalRevenue ?? dayClosing.totalrevenue ?? 0) : dayPayments.reduce((s: number, p: any) => s + Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0), 0)
  const expenseTotal = dayClosing ? Number(dayClosing.totalExpenses ?? dayClosing.totalexpenses ?? 0) : dayExpenses.reduce((s: number, x: any) => s + Number(x.amount ?? 0), 0)
  const net = revenue - expenseTotal

  function handleDownload() {
    const headers = ["Section", "Detail", "Room", "Amount", "Method"]
    const rows: any[] = []
    checkIns.forEach((b: any) => {
      const guest = `${b.guestFirstName ?? b.guestfirstname ?? b.firstName ?? b.firstname ?? ""} ${b.guestLastName ?? b.guestlastname ?? b.lastName ?? b.lastname ?? ""}`.trim()
      rows.push(["Check-In", guest, b.roomNumber ?? b.roomnumber ?? "-", Number(b.totalAmount ?? b.totalamount ?? b.ratePerNight ?? b.ratepernight ?? 0).toFixed(2), ""])
    })
    checkOuts.forEach((b: any) => {
      const guest = `${b.guestFirstName ?? b.guestfirstname ?? b.firstName ?? b.firstname ?? ""} ${b.guestLastName ?? b.guestlastname ?? b.lastName ?? b.lastname ?? ""}`.trim()
      rows.push(["Check-Out", guest, b.roomNumber ?? b.roomnumber ?? "-", "", ""])
    })
    dayPayments.forEach((p: any) => {
      const guest = `${p.guestFirstName ?? p.guestfirstname ?? p.firstName ?? p.firstname ?? ""} ${p.guestLastName ?? p.guestlastname ?? p.lastName ?? p.lastname ?? ""}`.trim()
      rows.push(["Payment", guest || "-", "", Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0).toFixed(2), p.paymentMethod ?? p.paymentmethod ?? "-"])
    })
    downloadCsv(`daily-report-${selectedDate}`, headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Section", "Detail", "Room", "Amount", "Method"]
    const rows: any[] = []
    checkIns.forEach((b: any) => {
      const guest = `${b.guestFirstName ?? b.guestfirstname ?? b.firstName ?? b.firstname ?? ""} ${b.guestLastName ?? b.guestlastname ?? b.lastName ?? b.lastname ?? ""}`.trim()
      rows.push(["Check-In", guest, b.roomNumber ?? b.roomnumber ?? "-", Number(b.totalAmount ?? b.totalamount ?? b.ratePerNight ?? b.ratepernight ?? 0).toFixed(2), ""])
    })
    checkOuts.forEach((b: any) => {
      const guest = `${b.guestFirstName ?? b.guestfirstname ?? b.firstName ?? b.firstname ?? ""} ${b.guestLastName ?? b.guestlastname ?? b.lastName ?? b.lastname ?? ""}`.trim()
      rows.push(["Check-Out", guest, b.roomNumber ?? b.roomnumber ?? "-", "", ""])
    })
    dayPayments.forEach((p: any) => {
      const guest = `${p.guestFirstName ?? p.guestfirstname ?? p.firstName ?? p.firstname ?? ""} ${p.guestLastName ?? p.guestlastname ?? p.lastName ?? p.lastname ?? ""}`.trim()
      rows.push(["Payment", guest || "-", "", Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0).toFixed(2), p.paymentMethod ?? p.paymentmethod ?? "-"])
    })
    return {
      title: `Daily Report - ${selectedDate}`,
      subtitle: "Hotel Management Report",
      filename: `daily-report-${selectedDate}`,
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Revenue", value: `GH\u20B5${revenue.toFixed(2)}` },
        { label: "Expenses", value: `GH\u20B5${expenseTotal.toFixed(2)}` },
        { label: "Net", value: `GH\u20B5${net.toFixed(2)}` },
        { label: "Check-ins", value: `${checkIns.length}` },
      ],
      dateRange: { from: selectedDate, to: selectedDate },
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
            <h1 className="text-2xl font-bold">Daily Report</h1>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={handleDownload}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => downloadPdf(getPdfConfig())}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />Preview</Button>
              <Button variant="outline" size="sm" onClick={() => { const c = getPdfConfig(); printReport({ hotelName, hotelAddress, hotelPhone, hotelEmail, title: c.title, dateRange: c.dateRange, summaryCards: c.summaryCards, headers: c.headers, rows: c.rows, currency: "GH\u20B5" }) }}><Printer className="h-4 w-4 mr-1" />Print</Button>
            </div>
          </div>

          {/* Date Picker */}
          <div className="flex flex-wrap items-center gap-3 mb-6">
            <label className="text-sm font-medium text-slate-600">Date</label>
            <input type="date" value={selectedDate} onChange={(e) => setSelectedDate(e.target.value)} className="border rounded px-3 py-1.5 text-sm" />
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <>
              {/* Summary Cards */}
              <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{revenue.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Revenue</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">{expenseTotal.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Expenses</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className={`text-2xl font-bold ${net >= 0 ? "text-emerald-700" : "text-red-700"}`}>{net.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Net</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-blue-600">{checkIns.length}</div><div className="text-xs text-slate-500 mt-1">Check-ins</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{checkOuts.length}</div><div className="text-xs text-slate-500 mt-1">Check-outs</div></CardContent></Card>
              </div>

              {/* Check-ins Table */}
              <Card className="mb-6">
                <CardHeader><CardTitle className="text-base">Check-ins ({checkIns.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Guest</th>
                          <th className="text-left p-3">Room</th>
                          <th className="text-right p-3">Rate</th>
                        </tr>
                      </thead>
                      <tbody>
                        {checkIns.map((b: any, idx: number) => {
                          const guest = `${b.guestFirstName ?? b.guestfirstname ?? b.firstName ?? b.firstname ?? ""} ${b.guestLastName ?? b.guestlastname ?? b.lastName ?? b.lastname ?? ""}`.trim() || "-"
                          return (
                            <tr key={b.hotelBookingId ?? b.hotelbookingid ?? `ci-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">{guest}</td>
                              <td className="p-3">{b.roomNumber ?? b.roomnumber ?? "-"}</td>
                              <td className="p-3 text-right text-emerald-700">{Number(b.totalAmount ?? b.totalamount ?? b.ratePerNight ?? b.ratepernight ?? 0).toFixed(2)}</td>
                            </tr>
                          )
                        })}
                        {checkIns.length === 0 && (
                          <tr><td colSpan={3} className="p-8 text-center text-slate-400">No check-ins for this date.</td></tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>

              {/* Check-outs Table */}
              <Card className="mb-6">
                <CardHeader><CardTitle className="text-base">Check-outs ({checkOuts.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Guest</th>
                          <th className="text-left p-3">Room</th>
                        </tr>
                      </thead>
                      <tbody>
                        {checkOuts.map((b: any, idx: number) => {
                          const guest = `${b.guestFirstName ?? b.guestfirstname ?? b.firstName ?? b.firstname ?? ""} ${b.guestLastName ?? b.guestlastname ?? b.lastName ?? b.lastname ?? ""}`.trim() || "-"
                          return (
                            <tr key={b.hotelBookingId ?? b.hotelbookingid ?? `co-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">{guest}</td>
                              <td className="p-3">{b.roomNumber ?? b.roomnumber ?? "-"}</td>
                            </tr>
                          )
                        })}
                        {checkOuts.length === 0 && (
                          <tr><td colSpan={2} className="p-8 text-center text-slate-400">No check-outs for this date.</td></tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>

              {/* Payments Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Payments ({dayPayments.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Guest</th>
                          <th className="text-right p-3">Amount</th>
                          <th className="text-left p-3">Method</th>
                        </tr>
                      </thead>
                      <tbody>
                        {dayPayments.map((p: any, idx: number) => {
                          const guest = `${p.guestFirstName ?? p.guestfirstname ?? p.firstName ?? p.firstname ?? ""} ${p.guestLastName ?? p.guestlastname ?? p.lastName ?? p.lastname ?? ""}`.trim() || "-"
                          return (
                            <tr key={p.hotelPaymentId ?? p.hotelpaymentid ?? `pay-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">{guest}</td>
                              <td className="p-3 text-right text-emerald-700 font-medium">{Number(p.amount ?? p.totalAmount ?? p.totalamount ?? 0).toFixed(2)}</td>
                              <td className="p-3">{p.paymentMethod ?? p.paymentmethod ?? "-"}</td>
                            </tr>
                          )
                        })}
                        {dayPayments.length === 0 && (
                          <tr><td colSpan={3} className="p-8 text-center text-slate-400">No payments for this date.</td></tr>
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

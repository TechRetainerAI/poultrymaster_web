"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, CreditCard, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelPayments, listHotelBookings, getHotelProfile } from "@/lib/api/hotel"

export default function BillingReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [payments, setPayments] = useState<any[]>([])
  const [bookings, setBookings] = useState<any[]>([])
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
      const [p, b] = await Promise.all([listHotelPayments(), listHotelBookings()])
      setPayments(p)
      setBookings(b)
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

  const bookingMap: Record<number, any> = {}
  bookings.forEach((b: any) => {
    const id = b.hotelBookingId ?? b.hotelbookingid
    if (id) bookingMap[id] = b
  })

  const filtered = payments.filter((x: any) => {
    const d = (x.paymentDate ?? x.paymentdate ?? "").slice(0, 10)
    return d >= dateFrom && d <= dateTo
  })

  function handleDownload() {
    const headers = ["Date", "Booking Ref", "Guest", "Amount", "Method", "Reference", "Received By"]
    const rows = filtered.map((x: any) => {
      const bkId = x.hotelBookingId ?? x.hotelbookingid
      const bk = bkId ? bookingMap[bkId] : null
      const guestName = bk ? `${bk.guestFirstName ?? bk.guestfirstname ?? ""} ${bk.guestLastName ?? bk.guestlastname ?? ""}`.trim() : ""
      const bookingRef = bk ? (bk.bookingRef ?? bk.bookingref ?? "") : ""
      return [
        (x.paymentDate ?? x.paymentdate ?? "").slice(0, 10),
        bookingRef,
        guestName,
        Number(x.amount ?? 0).toFixed(2),
        x.paymentMethod ?? x.paymentmethod ?? "",
        x.reference ?? "",
        x.receivedBy ?? x.receivedby ?? "",
      ]
    })
    downloadCsv("billing-report", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Date", "Booking Ref", "Guest", "Amount", "Method", "Reference", "Received By"]
    const rows = filtered.map((x: any) => {
      const bkId = x.hotelBookingId ?? x.hotelbookingid
      const bk = bkId ? bookingMap[bkId] : null
      const guestName = bk ? `${bk.guestFirstName ?? bk.guestfirstname ?? ""} ${bk.guestLastName ?? bk.guestlastname ?? ""}`.trim() : ""
      const bookingRef = bk ? (bk.bookingRef ?? bk.bookingref ?? "") : ""
      return [
        (x.paymentDate ?? x.paymentdate ?? "").slice(0, 10),
        bookingRef,
        guestName,
        Number(x.amount ?? 0).toFixed(2),
        x.paymentMethod ?? x.paymentmethod ?? "",
        x.reference ?? "",
        x.receivedBy ?? x.receivedby ?? "",
      ]
    })
    return {
      title: "Billing & Payments",
      subtitle: "Hotel Management Report",
      filename: "billing-report",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Payments", value: `GH\u20B5${totalPayments.toFixed(2)}` },
        { label: "Cash", value: `GH\u20B5${cashTotal.toFixed(2)}` },
        { label: "MoMo", value: `GH\u20B5${momoTotal.toFixed(2)}` },
        { label: "Bank", value: `GH\u20B5${bankTotal.toFixed(2)}` },
      ],
      dateRange: { from: dateFrom, to: dateTo },
      currency: "GH\u20B5",
    }
  }

  const totalPayments = filtered.reduce((s: number, x: any) => s + Number(x.amount ?? 0), 0)

  // Group by payment method
  const methodMap: Record<string, number> = {}
  filtered.forEach((x: any) => {
    const m = (x.paymentMethod ?? x.paymentmethod ?? "Other").toString()
    methodMap[m] = (methodMap[m] ?? 0) + Number(x.amount ?? 0)
  })
  const cashTotal = methodMap["Cash"] ?? 0
  const momoTotal = methodMap["MoMo"] ?? methodMap["Mobile Money"] ?? methodMap["momo"] ?? 0
  const bankTotal = methodMap["Bank"] ?? methodMap["Bank Transfer"] ?? methodMap["bank"] ?? 0

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <CreditCard className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Billing &amp; Payments</h1>
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
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{totalPayments.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Payments</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{cashTotal.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Cash</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-amber-600">{momoTotal.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">MoMo</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-blue-600">{bankTotal.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Bank</div></CardContent></Card>
              </div>

              {/* Payment Method Breakdown */}
              {Object.keys(methodMap).length > 0 && (
                <Card className="mb-6">
                  <CardHeader><CardTitle className="text-base">By Payment Method</CardTitle></CardHeader>
                  <CardContent className="p-0">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Method</th>
                          <th className="text-right p-3">Total</th>
                        </tr>
                      </thead>
                      <tbody>
                        {Object.entries(methodMap).sort((a, b) => b[1] - a[1]).map(([method, total]) => (
                          <tr key={method} className="border-b hover:bg-slate-50">
                            <td className="p-3 font-medium">{method}</td>
                            <td className="p-3 text-right text-emerald-700 font-medium">{total.toFixed(2)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </CardContent>
                </Card>
              )}

              {/* Detail Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Payment Details ({filtered.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Date</th>
                          <th className="text-left p-3">Booking Ref</th>
                          <th className="text-left p-3">Guest</th>
                          <th className="text-right p-3">Amount</th>
                          <th className="text-left p-3">Method</th>
                          <th className="text-left p-3">Reference</th>
                          <th className="text-left p-3">Received By</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filtered
                          .sort((a: any, b: any) => {
                            const da = (a.paymentDate ?? a.paymentdate ?? "").slice(0, 10)
                            const db = (b.paymentDate ?? b.paymentdate ?? "").slice(0, 10)
                            return db.localeCompare(da)
                          })
                          .map((x: any, idx: number) => {
                            const bkId = x.hotelBookingId ?? x.hotelbookingid
                            const bk = bkId ? bookingMap[bkId] : null
                            const guestName = bk ? `${bk.guestFirstName ?? bk.guestfirstname ?? ""} ${bk.guestLastName ?? bk.guestlastname ?? ""}`.trim() : "-"
                            const bookingRef = bk ? (bk.bookingRef ?? bk.bookingref ?? "-") : "-"
                            return (
                              <tr key={x.hotelPaymentId ?? x.hotelpaymentid ?? `pay-${idx}`} className="border-b hover:bg-slate-50">
                                <td className="p-3">{(x.paymentDate ?? x.paymentdate ?? "").slice(0, 10)}</td>
                                <td className="p-3 font-mono text-xs">{bookingRef}</td>
                                <td className="p-3">{guestName}</td>
                                <td className="p-3 text-right text-emerald-700 font-medium">{Number(x.amount ?? 0).toFixed(2)}</td>
                                <td className="p-3">{x.paymentMethod ?? x.paymentmethod ?? "-"}</td>
                                <td className="p-3 text-xs">{x.reference ?? "-"}</td>
                                <td className="p-3">{x.receivedBy ?? x.receivedby ?? "-"}</td>
                              </tr>
                            )
                          })}
                        {filtered.length === 0 && (
                          <tr><td colSpan={7} className="p-8 text-center text-slate-400">No payments found for this period.</td></tr>
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

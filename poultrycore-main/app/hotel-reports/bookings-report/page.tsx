"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, CalendarDays, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelBookings, getHotelProfile } from "@/lib/api/hotel"

function statusBadge(status: string) {
  const s = (status ?? "").toLowerCase()
  if (s === "confirmed") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">Confirmed</span>
  if (s === "checkedin") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">Checked In</span>
  if (s === "checkedout") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-700">Checked Out</span>
  if (s === "cancelled") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">Cancelled</span>
  if (s === "pending") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-700">Pending</span>
  return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-600">{status}</span>
}

export default function BookingsReportPage() {
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
      const res = await listHotelBookings()
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
    const d = (x.checkInDate ?? x.checkindate ?? "").slice(0, 10)
    return d >= dateFrom && d <= dateTo
  })

  function handleDownload() {
    const headers = ["Booking Ref", "Guest", "Room", "Check-in", "Check-out", "Nights", "Rate", "Total", "Status"]
    const rows = filtered.map((x: any) => {
      const ciDate = (x.checkInDate ?? x.checkindate ?? "").slice(0, 10)
      const coDate = (x.checkOutDate ?? x.checkoutdate ?? "").slice(0, 10)
      const ci = new Date(ciDate)
      const co = new Date(coDate)
      const nights = Math.max(1, Math.round((co.getTime() - ci.getTime()) / (1000 * 60 * 60 * 24)))
      const guestName = `${x.guestFirstName ?? x.guestfirstname ?? ""} ${x.guestLastName ?? x.guestlastname ?? ""}`.trim()
      return [
        x.bookingRef ?? x.bookingref ?? "",
        guestName,
        x.roomNumber ?? x.roomnumber ?? "",
        ciDate,
        coDate,
        nights,
        Number(x.nightlyRate ?? x.nightlyrate ?? 0).toFixed(2),
        Number(x.totalAmount ?? x.totalamount ?? 0).toFixed(2),
        x.status ?? "",
      ]
    })
    downloadCsv("bookings-report", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Booking Ref", "Guest", "Room", "Check-in", "Check-out", "Nights", "Rate", "Total", "Status"]
    const rows = filtered.map((x: any) => {
      const ciDate = (x.checkInDate ?? x.checkindate ?? "").slice(0, 10)
      const coDate = (x.checkOutDate ?? x.checkoutdate ?? "").slice(0, 10)
      const ci = new Date(ciDate)
      const co = new Date(coDate)
      const nights = Math.max(1, Math.round((co.getTime() - ci.getTime()) / (1000 * 60 * 60 * 24)))
      const guestName = `${x.guestFirstName ?? x.guestfirstname ?? ""} ${x.guestLastName ?? x.guestlastname ?? ""}`.trim()
      return [
        x.bookingRef ?? x.bookingref ?? "",
        guestName,
        x.roomNumber ?? x.roomnumber ?? "",
        ciDate,
        coDate,
        nights,
        Number(x.nightlyRate ?? x.nightlyrate ?? 0).toFixed(2),
        Number(x.totalAmount ?? x.totalamount ?? 0).toFixed(2),
        x.status ?? "",
      ]
    })
    return {
      title: "Bookings Report",
      subtitle: "Hotel Management Report",
      filename: "bookings-report",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Bookings", value: `${totalBookings}` },
        { label: "Confirmed", value: `${confirmed}` },
        { label: "Checked In", value: `${checkedIn}` },
        { label: "Total Revenue", value: `GH\u20B5${totalRevenue.toFixed(2)}` },
      ],
      dateRange: { from: dateFrom, to: dateTo },
      currency: "GH\u20B5",
    }
  }

  const totalBookings = filtered.length
  const confirmed = filtered.filter((x: any) => (x.status ?? "").toLowerCase() === "confirmed").length
  const checkedIn = filtered.filter((x: any) => (x.status ?? "").toLowerCase() === "checkedin").length
  const cancelled = filtered.filter((x: any) => (x.status ?? "").toLowerCase() === "cancelled").length
  const totalRevenue = filtered.reduce((s: number, x: any) => s + Number(x.totalAmount ?? x.totalamount ?? 0), 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <CalendarDays className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Bookings Report</h1>
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
              <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalBookings}</div><div className="text-xs text-slate-500 mt-1">Total Bookings</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-blue-600">{confirmed}</div><div className="text-xs text-slate-500 mt-1">Confirmed</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-green-600">{checkedIn}</div><div className="text-xs text-slate-500 mt-1">Checked In</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">{cancelled}</div><div className="text-xs text-slate-500 mt-1">Cancelled</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{totalRevenue.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Revenue</div></CardContent></Card>
              </div>

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Bookings ({filtered.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Booking Ref</th>
                          <th className="text-left p-3">Guest</th>
                          <th className="text-left p-3">Room</th>
                          <th className="text-left p-3">Check-in</th>
                          <th className="text-left p-3">Check-out</th>
                          <th className="text-right p-3">Nights</th>
                          <th className="text-right p-3">Rate</th>
                          <th className="text-right p-3">Total</th>
                          <th className="text-center p-3">Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filtered
                          .sort((a: any, b: any) => {
                            const da = (a.checkInDate ?? a.checkindate ?? "").slice(0, 10)
                            const db = (b.checkInDate ?? b.checkindate ?? "").slice(0, 10)
                            return db.localeCompare(da)
                          })
                          .map((x: any, idx: number) => {
                            const ciDate = (x.checkInDate ?? x.checkindate ?? "").slice(0, 10)
                            const coDate = (x.checkOutDate ?? x.checkoutdate ?? "").slice(0, 10)
                            const ci = new Date(ciDate)
                            const co = new Date(coDate)
                            const nights = Math.max(1, Math.round((co.getTime() - ci.getTime()) / (1000 * 60 * 60 * 24)))
                            const guestName = `${x.guestFirstName ?? x.guestfirstname ?? ""} ${x.guestLastName ?? x.guestlastname ?? ""}`.trim() || "-"
                            return (
                              <tr key={x.hotelBookingId ?? x.hotelbookingid ?? `bk-${idx}`} className="border-b hover:bg-slate-50">
                                <td className="p-3 font-mono text-xs">{x.bookingRef ?? x.bookingref ?? "-"}</td>
                                <td className="p-3">{guestName}</td>
                                <td className="p-3">{x.roomNumber ?? x.roomnumber ?? "-"}</td>
                                <td className="p-3">{ciDate}</td>
                                <td className="p-3">{coDate}</td>
                                <td className="p-3 text-right">{nights}</td>
                                <td className="p-3 text-right">{Number(x.nightlyRate ?? x.nightlyrate ?? 0).toFixed(2)}</td>
                                <td className="p-3 text-right font-medium text-emerald-700">{Number(x.totalAmount ?? x.totalamount ?? 0).toFixed(2)}</td>
                                <td className="p-3 text-center">{statusBadge(x.status ?? "")}</td>
                              </tr>
                            )
                          })}
                        {filtered.length === 0 && (
                          <tr><td colSpan={9} className="p-8 text-center text-slate-400">No bookings found for this period.</td></tr>
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

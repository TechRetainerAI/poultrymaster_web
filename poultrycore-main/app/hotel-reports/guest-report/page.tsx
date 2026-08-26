"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, Users, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelGuests, listHotelBookings, getHotelProfile } from "@/lib/api/hotel"

export default function GuestReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [guests, setGuests] = useState<any[]>([])
  const [bookings, setBookings] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [pdfPreviewOpen, setPdfPreviewOpen] = useState(false)
  const [hotelName, setHotelName] = useState("Hotel")
  const [hotelAddress, setHotelAddress] = useState("")
  const [hotelPhone, setHotelPhone] = useState("")
  const [hotelEmail, setHotelEmail] = useState("")

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [g, b] = await Promise.all([listHotelGuests(), listHotelBookings()])
      setGuests(g)
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

  // Count bookings per guest
  const guestBookings: Record<number, { count: number; totalSpent: number; lastStay: string }> = {}
  bookings.forEach((b: any) => {
    const gid = b.hotelGuestId ?? b.hotelguestid
    if (!gid) return
    if (!guestBookings[gid]) guestBookings[gid] = { count: 0, totalSpent: 0, lastStay: "" }
    guestBookings[gid].count += 1
    guestBookings[gid].totalSpent += Number(b.totalAmount ?? b.totalamount ?? 0)
    const ci = (b.checkInDate ?? b.checkindate ?? "").slice(0, 10)
    if (ci > guestBookings[gid].lastStay) guestBookings[gid].lastStay = ci
  })

  const enrichedGuests = guests.map((g: any) => {
    const gid = g.hotelGuestId ?? g.hotelguestid
    const info = guestBookings[gid] ?? { count: 0, totalSpent: 0, lastStay: "" }
    return { ...g, bookingsCount: info.count, totalSpent: info.totalSpent, lastStay: info.lastStay || (g.lastStayDate ?? g.laststaydate ?? "-") }
  }).sort((a: any, b: any) => b.bookingsCount - a.bookingsCount)

  function handleDownload() {
    const headers = ["Name", "Email", "Phone", "VIP", "Bookings", "Last Stay", "Total Spent"]
    const rows = enrichedGuests.map((g: any) => {
      const name = `${g.firstName ?? g.firstname ?? ""} ${g.lastName ?? g.lastname ?? ""}`.trim()
      const isVip = g.isVIP ?? g.isvip
      return [
        name,
        g.email ?? "",
        g.phone ?? "",
        isVip ? "Yes" : "No",
        g.bookingsCount,
        g.lastStay ? (typeof g.lastStay === "string" ? g.lastStay.slice(0, 10) : "") : "",
        Number(g.totalSpent ?? 0).toFixed(2),
      ]
    })
    downloadCsv("guest-report", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Name", "Email", "Phone", "VIP", "Bookings", "Last Stay", "Total Spent"]
    const rows = enrichedGuests.map((g: any) => {
      const name = `${g.firstName ?? g.firstname ?? ""} ${g.lastName ?? g.lastname ?? ""}`.trim()
      const isVip = g.isVIP ?? g.isvip
      return [
        name,
        g.email ?? "",
        g.phone ?? "",
        isVip ? "Yes" : "No",
        g.bookingsCount,
        g.lastStay ? (typeof g.lastStay === "string" ? g.lastStay.slice(0, 10) : "") : "",
        Number(g.totalSpent ?? 0).toFixed(2),
      ]
    })
    return {
      title: "Guest Report",
      subtitle: "Hotel Management Report",
      filename: "guest-report",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Guests", value: `${totalGuests}` },
        { label: "VIP", value: `${vipGuests}` },
        { label: "Repeat", value: `${repeatGuests}` },
        { label: "New", value: `${newGuests}` },
      ],
      currency: "GH\u20B5",
    }
  }

  const totalGuests = guests.length
  const vipGuests = guests.filter((g: any) => g.isVIP ?? g.isvip).length
  const repeatGuests = enrichedGuests.filter((g: any) => g.bookingsCount > 1).length
  const newGuests = totalGuests - repeatGuests

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <Users className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Guest Report</h1>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={handleDownload}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => downloadPdf(getPdfConfig())}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />Preview</Button>
              <Button variant="outline" size="sm" onClick={() => { const c = getPdfConfig(); printReport({ hotelName, hotelAddress, hotelPhone, hotelEmail, title: c.title, dateRange: c.dateRange, summaryCards: c.summaryCards, headers: c.headers, rows: c.rows, currency: "GH₵" }) }}><Printer className="h-4 w-4 mr-1" />Print</Button>
            </div>
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <>
              {/* Summary Cards */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalGuests}</div><div className="text-xs text-slate-500 mt-1">Total Guests</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-amber-600">{vipGuests}</div><div className="text-xs text-slate-500 mt-1">VIP Guests</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{repeatGuests}</div><div className="text-xs text-slate-500 mt-1">Repeat Guests</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-blue-600">{newGuests}</div><div className="text-xs text-slate-500 mt-1">New Guests</div></CardContent></Card>
              </div>

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Guest List ({enrichedGuests.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Name</th>
                          <th className="text-left p-3">Email</th>
                          <th className="text-left p-3">Phone</th>
                          <th className="text-center p-3">VIP</th>
                          <th className="text-right p-3">Bookings</th>
                          <th className="text-left p-3">Last Stay</th>
                          <th className="text-right p-3">Total Spent</th>
                        </tr>
                      </thead>
                      <tbody>
                        {enrichedGuests.map((g: any, idx: number) => {
                          const name = `${g.firstName ?? g.firstname ?? ""} ${g.lastName ?? g.lastname ?? ""}`.trim() || "-"
                          const isVip = g.isVIP ?? g.isvip
                          return (
                            <tr key={g.hotelGuestId ?? g.hotelguestid ?? `g-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">{name}</td>
                              <td className="p-3 text-xs">{g.email ?? "-"}</td>
                              <td className="p-3">{g.phone ?? "-"}</td>
                              <td className="p-3 text-center">
                                {isVip ? <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-700">VIP</span> : "-"}
                              </td>
                              <td className="p-3 text-right font-medium">{g.bookingsCount}</td>
                              <td className="p-3">{g.lastStay ? (typeof g.lastStay === "string" ? g.lastStay.slice(0, 10) : "-") : "-"}</td>
                              <td className="p-3 text-right text-emerald-700 font-medium">GH&#8373;{Number(g.totalSpent ?? 0).toFixed(2)}</td>
                            </tr>
                          )
                        })}
                        {enrichedGuests.length === 0 && (
                          <tr><td colSpan={7} className="p-8 text-center text-slate-400">No guests found.</td></tr>
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

"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, Wrench, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listMaintenanceRequests, getHotelProfile } from "@/lib/api/hotel"

function priorityBadge(priority: string) {
  const p = (priority ?? "").toLowerCase()
  if (p === "high" || p === "urgent") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">{priority}</span>
  if (p === "medium" || p === "normal") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-700">{priority}</span>
  if (p === "low") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">{priority}</span>
  return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-600">{priority}</span>
}

function mStatusBadge(status: string) {
  const s = (status ?? "").toLowerCase()
  if (s === "open") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">Open</span>
  if (s === "inprogress") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-700">In Progress</span>
  if (s === "completed") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">Completed</span>
  return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-600">{status}</span>
}

export default function MaintenanceReportPage() {
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
      const res = await listMaintenanceRequests()
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
    const d = (x.createdAt ?? x.createdat ?? "").slice(0, 10)
    return d >= dateFrom && d <= dateTo
  })

  function handleDownload() {
    const headers = ["Date", "Room", "Asset", "Issue", "Priority", "Status", "Est. Cost", "Completed"]
    const rows = filtered.map((x: any) => [
      (x.createdAt ?? x.createdat ?? "").slice(0, 10),
      x.roomNumber ?? x.roomnumber ?? "",
      x.assetDescription ?? x.assetdescription ?? "",
      x.issueDescription ?? x.issuedescription ?? "",
      x.priority ?? "",
      x.status ?? "",
      Number(x.estimatedCost ?? x.estimatedcost ?? 0).toFixed(2),
      (x.completedAt ?? x.completedat ?? "").slice?.(0, 10) ?? "",
    ])
    downloadCsv("maintenance-report", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Date", "Room", "Asset", "Issue", "Priority", "Status", "Est. Cost", "Completed"]
    const rows = filtered.map((x: any) => [
      (x.createdAt ?? x.createdat ?? "").slice(0, 10),
      x.roomNumber ?? x.roomnumber ?? "",
      x.assetDescription ?? x.assetdescription ?? "",
      x.issueDescription ?? x.issuedescription ?? "",
      x.priority ?? "",
      x.status ?? "",
      Number(x.estimatedCost ?? x.estimatedcost ?? 0).toFixed(2),
      (x.completedAt ?? x.completedat ?? "").slice?.(0, 10) ?? "",
    ])
    return {
      title: "Maintenance Report",
      subtitle: "Hotel Management Report",
      filename: "maintenance-report",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Requests", value: `${totalRequests}` },
        { label: "Open", value: `${openCount}` },
        { label: "In Progress", value: `${inProgressCount}` },
        { label: "Completed", value: `${completedCount}` },
      ],
      dateRange: { from: dateFrom, to: dateTo },
      currency: "GH\u20B5",
    }
  }

  const totalRequests = filtered.length
  const openCount = filtered.filter((x: any) => (x.status ?? "").toLowerCase() === "open").length
  const inProgressCount = filtered.filter((x: any) => (x.status ?? "").toLowerCase() === "inprogress").length
  const completedCount = filtered.filter((x: any) => (x.status ?? "").toLowerCase() === "completed").length
  const estCostTotal = filtered.reduce((s: number, x: any) => s + Number(x.estimatedCost ?? x.estimatedcost ?? 0), 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <Wrench className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Maintenance Report</h1>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={handleDownload}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => downloadPdf(getPdfConfig())}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />Preview</Button>
              <Button variant="outline" size="sm" onClick={() => { const c = getPdfConfig(); printReport({ hotelName, hotelAddress, hotelPhone, hotelEmail, title: c.title, dateRange: c.dateRange, summaryCards: c.summaryCards, headers: c.headers, rows: c.rows, currency: "GH₵" }) }}><Printer className="h-4 w-4 mr-1" />Print</Button>
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
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalRequests}</div><div className="text-xs text-slate-500 mt-1">Total Requests</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">{openCount}</div><div className="text-xs text-slate-500 mt-1">Open</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-amber-600">{inProgressCount}</div><div className="text-xs text-slate-500 mt-1">In Progress</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-green-600">{completedCount}</div><div className="text-xs text-slate-500 mt-1">Completed</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-slate-700">GH&#8373;{estCostTotal.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Est. Cost Total</div></CardContent></Card>
              </div>

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Maintenance Requests ({filtered.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Date</th>
                          <th className="text-left p-3">Room</th>
                          <th className="text-left p-3">Asset</th>
                          <th className="text-left p-3">Issue</th>
                          <th className="text-center p-3">Priority</th>
                          <th className="text-center p-3">Status</th>
                          <th className="text-right p-3">Est. Cost</th>
                          <th className="text-left p-3">Completed</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filtered
                          .sort((a: any, b: any) => {
                            const da = (a.createdAt ?? a.createdat ?? "").slice(0, 10)
                            const db = (b.createdAt ?? b.createdat ?? "").slice(0, 10)
                            return db.localeCompare(da)
                          })
                          .map((x: any, idx: number) => (
                            <tr key={x.hotelMaintenanceRequestId ?? x.hotelmaintenancerequestid ?? `m-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3">{(x.createdAt ?? x.createdat ?? "").slice(0, 10)}</td>
                              <td className="p-3">{x.roomNumber ?? x.roomnumber ?? "-"}</td>
                              <td className="p-3">{x.assetDescription ?? x.assetdescription ?? "-"}</td>
                              <td className="p-3 max-w-[200px] truncate">{x.issueDescription ?? x.issuedescription ?? "-"}</td>
                              <td className="p-3 text-center">{priorityBadge(x.priority ?? "")}</td>
                              <td className="p-3 text-center">{mStatusBadge(x.status ?? "")}</td>
                              <td className="p-3 text-right">GH&#8373;{Number(x.estimatedCost ?? x.estimatedcost ?? 0).toFixed(2)}</td>
                              <td className="p-3">{(x.completedAt ?? x.completedat ?? "-").slice?.(0, 10) ?? "-"}</td>
                            </tr>
                          ))}
                        {filtered.length === 0 && (
                          <tr><td colSpan={8} className="p-8 text-center text-slate-400">No maintenance requests found for this period.</td></tr>
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

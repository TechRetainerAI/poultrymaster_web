"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, ClipboardCheck, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHousekeepingTasks, getHotelProfile } from "@/lib/api/hotel"

export default function HousekeepingReportPage() {
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
      const res = await listHousekeepingTasks()
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

  const filtered = data.filter((t: any) => {
    const d = (t.createdAt ?? t.createdat ?? "").slice(0, 10)
    return d >= dateFrom && d <= dateTo
  })

  const totalTasks = filtered.length
  const pending = filtered.filter((t: any) => (t.status ?? "").toLowerCase() === "pending").length
  const inProgress = filtered.filter((t: any) => (t.status ?? "").toLowerCase() === "inprogress").length
  const completed = filtered.filter((t: any) => (t.status ?? "").toLowerCase() === "completed").length

  function statusBadge(status: string) {
    const s = (status ?? "").toLowerCase()
    if (s === "pending") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-700">Pending</span>
    if (s === "inprogress") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">InProgress</span>
    if (s === "completed") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">Completed</span>
    if (s === "inspected") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-indigo-100 text-indigo-700">Inspected</span>
    return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-700">{status}</span>
  }

  function handleDownload() {
    const headers = ["Room", "Type/Description", "Assigned To", "Status", "Priority", "Notes", "Created"]
    const rows = filtered.map((t: any) => [
      t.roomNumber ?? t.roomnumber ?? "-",
      t.taskType ?? t.tasktype ?? t.description ?? "",
      t.assignedTo ?? t.assignedto ?? "-",
      t.status ?? "",
      t.priority ?? "",
      t.notes ?? "",
      (t.createdAt ?? t.createdat ?? "").slice(0, 10),
    ])
    downloadCsv("housekeeping-report", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Room", "Type/Description", "Assigned To", "Status", "Priority", "Notes", "Created"]
    const rows = filtered.map((t: any) => [
      t.roomNumber ?? t.roomnumber ?? "-",
      t.taskType ?? t.tasktype ?? t.description ?? "",
      t.assignedTo ?? t.assignedto ?? "-",
      t.status ?? "",
      t.priority ?? "",
      t.notes ?? "",
      (t.createdAt ?? t.createdat ?? "").slice(0, 10),
    ])
    return {
      title: "Housekeeping Report",
      subtitle: "Hotel Management Report",
      filename: "housekeeping-report",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Tasks", value: `${totalTasks}` },
        { label: "Pending", value: `${pending}` },
        { label: "InProgress", value: `${inProgress}` },
        { label: "Completed", value: `${completed}` },
      ],
      dateRange: { from: dateFrom, to: dateTo },
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
            <ClipboardCheck className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Housekeeping Report</h1>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={handleDownload}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => downloadPdf(getPdfConfig())}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />Preview</Button>
              <Button variant="outline" size="sm" onClick={() => { const c = getPdfConfig(); printReport({ hotelName, hotelAddress, hotelPhone, hotelEmail, title: c.title, dateRange: c.dateRange, summaryCards: c.summaryCards, headers: c.headers, rows: c.rows, currency: "GH\u20B5" }) }}><Printer className="h-4 w-4 mr-1" />Print</Button>
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
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalTasks}</div><div className="text-xs text-slate-500 mt-1">Total Tasks</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-amber-600">{pending}</div><div className="text-xs text-slate-500 mt-1">Pending</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-blue-600">{inProgress}</div><div className="text-xs text-slate-500 mt-1">InProgress</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{completed}</div><div className="text-xs text-slate-500 mt-1">Completed</div></CardContent></Card>
              </div>

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Housekeeping Tasks ({filtered.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Room</th>
                          <th className="text-left p-3">Type/Description</th>
                          <th className="text-left p-3">Assigned To</th>
                          <th className="text-center p-3">Status</th>
                          <th className="text-left p-3">Priority</th>
                          <th className="text-left p-3">Notes</th>
                          <th className="text-left p-3">Created</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filtered.map((t: any, idx: number) => (
                          <tr key={t.hotelHousekeepingTaskId ?? t.hotelhousekeepingtaskid ?? `hk-${idx}`} className="border-b hover:bg-slate-50">
                            <td className="p-3 font-medium">{t.roomNumber ?? t.roomnumber ?? "-"}</td>
                            <td className="p-3">{t.taskType ?? t.tasktype ?? t.description ?? "-"}</td>
                            <td className="p-3">{t.assignedTo ?? t.assignedto ?? "-"}</td>
                            <td className="p-3 text-center">{statusBadge(t.status ?? "")}</td>
                            <td className="p-3">{t.priority ?? "-"}</td>
                            <td className="p-3 text-xs max-w-[200px] truncate">{t.notes ?? "-"}</td>
                            <td className="p-3">{(t.createdAt ?? t.createdat ?? "").slice(0, 10)}</td>
                          </tr>
                        ))}
                        {filtered.length === 0 && (
                          <tr><td colSpan={7} className="p-8 text-center text-slate-400">No housekeeping tasks found for this period.</td></tr>
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

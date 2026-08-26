"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, Wallet, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelPayrollRuns, getHotelProfile } from "@/lib/api/hotel"

export default function PayrollReportPage() {
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

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const res = await listHotelPayrollRuns()
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

  const totalRuns = data.length
  const totalGross = data.reduce((s: number, r: any) => s + Number(r.totalGross ?? r.totalgross ?? 0), 0)
  const totalDeductions = data.reduce((s: number, r: any) => s + Number(r.totalDeductions ?? r.totaldeductions ?? 0), 0)
  const totalNet = data.reduce((s: number, r: any) => s + Number(r.totalNet ?? r.totalnet ?? 0), 0)

  function statusBadge(status: string) {
    const s = (status ?? "").toLowerCase()
    if (s === "approved") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">Approved</span>
    if (s === "paid") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">Paid</span>
    if (s === "cancelled") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">Cancelled</span>
    return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-700">{status ?? "Draft"}</span>
  }

  function handleDownload() {
    const headers = ["Period", "Status", "Gross", "Deductions", "Net", "Cash Account", "Created By", "Approved By"]
    const rows = data.map((r: any) => [
      `${(r.periodStart ?? r.periodstart ?? "").slice(0, 10)} - ${(r.periodEnd ?? r.periodend ?? "").slice(0, 10)}`,
      r.status ?? "Draft",
      Number(r.totalGross ?? r.totalgross ?? 0).toFixed(2),
      Number(r.totalDeductions ?? r.totaldeductions ?? 0).toFixed(2),
      Number(r.totalNet ?? r.totalnet ?? 0).toFixed(2),
      r.cashAccountName ?? r.cashaccountname ?? "-",
      r.createdBy ?? r.createdby ?? "-",
      r.approvedBy ?? r.approvedby ?? "-",
    ])
    downloadCsv("payroll-report", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Period", "Status", "Gross", "Deductions", "Net", "Cash Account", "Created By", "Approved By"]
    const rows = data.map((r: any) => [
      `${(r.periodStart ?? r.periodstart ?? "").slice(0, 10)} - ${(r.periodEnd ?? r.periodend ?? "").slice(0, 10)}`,
      r.status ?? "Draft",
      Number(r.totalGross ?? r.totalgross ?? 0).toFixed(2),
      Number(r.totalDeductions ?? r.totaldeductions ?? 0).toFixed(2),
      Number(r.totalNet ?? r.totalnet ?? 0).toFixed(2),
      r.cashAccountName ?? r.cashaccountname ?? "-",
      r.createdBy ?? r.createdby ?? "-",
      r.approvedBy ?? r.approvedby ?? "-",
    ])
    return {
      title: "Payroll Report",
      subtitle: "Hotel Management Report",
      filename: "payroll-report",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Runs", value: `${totalRuns}` },
        { label: "Total Gross", value: `GH\u20B5${totalGross.toFixed(2)}` },
        { label: "Total Deductions", value: `GH\u20B5${totalDeductions.toFixed(2)}` },
        { label: "Total Net", value: `GH\u20B5${totalNet.toFixed(2)}` },
      ],
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
            <Wallet className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Payroll Report</h1>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={handleDownload}><Download className="h-4 w-4 mr-1" />CSV</Button>
              <Button variant="outline" size="sm" onClick={() => downloadPdf(getPdfConfig())}><FileText className="h-4 w-4 mr-1" />PDF</Button>
              <Button variant="outline" size="sm" onClick={() => setPdfPreviewOpen(true)}><FileText className="h-4 w-4 mr-1" />Preview</Button>
              <Button variant="outline" size="sm" onClick={() => { const c = getPdfConfig(); printReport({ hotelName, hotelAddress, hotelPhone, hotelEmail, title: c.title, dateRange: c.dateRange, summaryCards: c.summaryCards, headers: c.headers, rows: c.rows, currency: "GH\u20B5" }) }}><Printer className="h-4 w-4 mr-1" />Print</Button>
            </div>
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <>
              {/* Summary Cards */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalRuns}</div><div className="text-xs text-slate-500 mt-1">Total Runs</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">GH&#8373;{totalGross.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Gross</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">GH&#8373;{totalDeductions.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Deductions</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-blue-600">GH&#8373;{totalNet.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Net</div></CardContent></Card>
              </div>

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Payroll Runs ({data.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Period</th>
                          <th className="text-center p-3">Status</th>
                          <th className="text-right p-3">Gross</th>
                          <th className="text-right p-3">Deductions</th>
                          <th className="text-right p-3">Net</th>
                          <th className="text-left p-3">Cash Account</th>
                          <th className="text-left p-3">Created By</th>
                          <th className="text-left p-3">Approved By</th>
                        </tr>
                      </thead>
                      <tbody>
                        {data.map((r: any, idx: number) => (
                          <tr key={r.hotelPayrollRunId ?? r.hotelpayrollrunid ?? `pr-${idx}`} className="border-b hover:bg-slate-50">
                            <td className="p-3 font-medium">{(r.periodStart ?? r.periodstart ?? "").slice(0, 10)} &mdash; {(r.periodEnd ?? r.periodend ?? "").slice(0, 10)}</td>
                            <td className="p-3 text-center">{statusBadge(r.status)}</td>
                            <td className="p-3 text-right text-emerald-700">GH&#8373;{Number(r.totalGross ?? r.totalgross ?? 0).toFixed(2)}</td>
                            <td className="p-3 text-right text-red-600">GH&#8373;{Number(r.totalDeductions ?? r.totaldeductions ?? 0).toFixed(2)}</td>
                            <td className="p-3 text-right font-bold text-blue-700">GH&#8373;{Number(r.totalNet ?? r.totalnet ?? 0).toFixed(2)}</td>
                            <td className="p-3">{r.cashAccountName ?? r.cashaccountname ?? "-"}</td>
                            <td className="p-3">{r.createdBy ?? r.createdby ?? "-"}</td>
                            <td className="p-3">{r.approvedBy ?? r.approvedby ?? "-"}</td>
                          </tr>
                        ))}
                        {data.length === 0 && (
                          <tr><td colSpan={8} className="p-8 text-center text-slate-400">No payroll runs found.</td></tr>
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

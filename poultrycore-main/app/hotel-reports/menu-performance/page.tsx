"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, UtensilsCrossed, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listMenuItems, getHotelProfile } from "@/lib/api/hotel"

export default function MenuPerformancePage() {
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
      const res = await listMenuItems()
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

  const sorted = [...data].sort((a: any, b: any) => {
    const catA = (a.category ?? a.categoryName ?? a.categoryname ?? "").toLowerCase()
    const catB = (b.category ?? b.categoryName ?? b.categoryname ?? "").toLowerCase()
    if (catA !== catB) return catA.localeCompare(catB)
    const nameA = (a.name ?? a.itemName ?? a.itemname ?? "").toLowerCase()
    const nameB = (b.name ?? b.itemName ?? b.itemname ?? "").toLowerCase()
    return nameA.localeCompare(nameB)
  })

  const totalItems = data.length
  const availableCount = data.filter((m: any) => m.isAvailable ?? m.isavailable ?? true).length
  const unavailableCount = totalItems - availableCount
  const avgPrice = totalItems > 0 ? data.reduce((s: number, m: any) => s + Number(m.price ?? 0), 0) / totalItems : 0

  function handleDownload() {
    const headers = ["Name", "Category", "Price", "Available"]
    const rows = sorted.map((m: any) => [
      m.name ?? m.itemName ?? m.itemname ?? "",
      m.category ?? m.categoryName ?? m.categoryname ?? "",
      Number(m.price ?? 0).toFixed(2),
      (m.isAvailable ?? m.isavailable ?? true) ? "Yes" : "No",
    ])
    downloadCsv("menu-performance", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Name", "Category", "Price", "Available"]
    const rows = sorted.map((m: any) => [
      m.name ?? m.itemName ?? m.itemname ?? "",
      m.category ?? m.categoryName ?? m.categoryname ?? "",
      Number(m.price ?? 0).toFixed(2),
      (m.isAvailable ?? m.isavailable ?? true) ? "Yes" : "No",
    ])
    return {
      title: "Menu Performance",
      subtitle: "Hotel Management Report",
      filename: "menu-performance",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Items", value: `${totalItems}` },
        { label: "Available", value: `${availableCount}` },
        { label: "Unavailable", value: `${unavailableCount}` },
        { label: "Avg Price", value: `GH\u20B5${avgPrice.toFixed(2)}` },
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
            <UtensilsCrossed className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Menu Performance</h1>
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
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalItems}</div><div className="text-xs text-slate-500 mt-1">Total Items</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{availableCount}</div><div className="text-xs text-slate-500 mt-1">Available</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">{unavailableCount}</div><div className="text-xs text-slate-500 mt-1">Unavailable</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-amber-600">GH&#8373;{avgPrice.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Avg Price</div></CardContent></Card>
              </div>

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Menu Items ({sorted.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Name</th>
                          <th className="text-left p-3">Category</th>
                          <th className="text-right p-3">Price (GH&#8373;)</th>
                          <th className="text-center p-3">Available</th>
                        </tr>
                      </thead>
                      <tbody>
                        {sorted.map((m: any, idx: number) => {
                          const avail = m.isAvailable ?? m.isavailable ?? true
                          return (
                            <tr key={m.hotelMenuItemId ?? m.hotelmenuitemid ?? `mi-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">{m.name ?? m.itemName ?? m.itemname ?? "-"}</td>
                              <td className="p-3">{m.category ?? m.categoryName ?? m.categoryname ?? "-"}</td>
                              <td className="p-3 text-right text-emerald-700 font-medium">GH&#8373;{Number(m.price ?? 0).toFixed(2)}</td>
                              <td className="p-3 text-center">
                                {avail
                                  ? <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">Yes</span>
                                  : <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">No</span>
                                }
                              </td>
                            </tr>
                          )
                        })}
                        {sorted.length === 0 && (
                          <tr><td colSpan={4} className="p-8 text-center text-slate-400">No menu items found.</td></tr>
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

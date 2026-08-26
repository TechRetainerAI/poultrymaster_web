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
import { listRestaurantOrders, getHotelProfile } from "@/lib/api/hotel"
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts"

function orderStatusBadge(status: string) {
  const s = (status ?? "").toLowerCase()
  if (s === "placed") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-700">Placed</span>
  if (s === "preparing") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">Preparing</span>
  if (s === "ready") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-indigo-100 text-indigo-700">Ready</span>
  if (s === "served") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">Served</span>
  if (s === "cancelled") return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">Cancelled</span>
  return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-600">{status}</span>
}

export default function RestaurantSalesPage() {
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
      const res = await listRestaurantOrders()
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
    const d = (x.orderTime ?? x.ordertime ?? "").slice(0, 10)
    return d >= dateFrom && d <= dateTo
  })

  function handleDownload() {
    const headers = ["Date", "Order #", "Table", "Server", "Subtotal", "Total", "Status"]
    const rows = filtered.map((x: any) => [
      (x.orderTime ?? x.ordertime ?? "").slice(0, 10),
      x.hotelRestaurantOrderId ?? x.hotelrestaurantorderid ?? "",
      x.tableNumber ?? x.tablenumber ?? "",
      x.serverName ?? x.servername ?? "",
      Number(x.subTotal ?? x.subtotal ?? 0).toFixed(2),
      Number(x.totalAmount ?? x.totalamount ?? 0).toFixed(2),
      x.status ?? "",
    ])
    downloadCsv("restaurant-sales", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Date", "Order #", "Table", "Server", "Subtotal", "Total", "Status"]
    const rows = filtered.map((x: any) => [
      (x.orderTime ?? x.ordertime ?? "").slice(0, 10),
      x.hotelRestaurantOrderId ?? x.hotelrestaurantorderid ?? "",
      x.tableNumber ?? x.tablenumber ?? "",
      x.serverName ?? x.servername ?? "",
      Number(x.subTotal ?? x.subtotal ?? 0).toFixed(2),
      Number(x.totalAmount ?? x.totalamount ?? 0).toFixed(2),
      x.status ?? "",
    ])
    return {
      title: "Restaurant Sales",
      subtitle: "Hotel Management Report",
      filename: "restaurant-sales",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Orders", value: `${totalOrders}` },
        { label: "Total Revenue", value: `GH\u20B5${totalRevenue.toFixed(2)}` },
        { label: "Avg Order", value: `GH\u20B5${avgOrderValue.toFixed(2)}` },
        { label: "Served", value: `${servedCount}` },
      ],
      dateRange: { from: dateFrom, to: dateTo },
      currency: "GH\u20B5",
    }
  }

  const totalOrders = filtered.length
  const totalRevenue = filtered.reduce((s: number, x: any) => s + Number(x.totalAmount ?? x.totalamount ?? 0), 0)
  const avgOrderValue = totalOrders > 0 ? totalRevenue / totalOrders : 0
  const servedCount = filtered.filter((x: any) => (x.status ?? "").toLowerCase() === "served").length

  // Daily chart data
  const dailyMap: Record<string, number> = {}
  filtered.forEach((x: any) => {
    const d = (x.orderTime ?? x.ordertime ?? "").slice(0, 10)
    dailyMap[d] = (dailyMap[d] ?? 0) + Number(x.totalAmount ?? x.totalamount ?? 0)
  })
  const chartData = Object.entries(dailyMap)
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([date, total]) => ({ date: date.slice(5, 10), total }))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center gap-3 mb-6">
            <Link href="/hotel-reports" className="text-violet-600 hover:text-violet-800"><ArrowLeft className="h-5 w-5" /></Link>
            <UtensilsCrossed className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Restaurant Sales</h1>
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
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-violet-700">{totalOrders}</div><div className="text-xs text-slate-500 mt-1">Total Orders</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">GH&#8373;{totalRevenue.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Revenue</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-amber-600">GH&#8373;{avgOrderValue.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Avg Order Value</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-green-600">{servedCount}</div><div className="text-xs text-slate-500 mt-1">Served</div></CardContent></Card>
              </div>

              {/* Bar Chart */}
              {chartData.length > 0 && (
                <Card className="mb-6">
                  <CardHeader><CardTitle className="text-base">Daily Order Totals</CardTitle></CardHeader>
                  <CardContent>
                    <ResponsiveContainer width="100%" height={300}>
                      <BarChart data={chartData}>
                        <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                        <XAxis dataKey="date" tick={{ fontSize: 12 }} />
                        <YAxis tick={{ fontSize: 12 }} />
                        <Tooltip formatter={(val: number) => `GH\u20B5${val.toFixed(2)}`} />
                        <Legend />
                        <Bar dataKey="total" name="Revenue" fill="#7c3aed" radius={[4, 4, 0, 0]} />
                      </BarChart>
                    </ResponsiveContainer>
                  </CardContent>
                </Card>
              )}

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Orders ({filtered.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Date</th>
                          <th className="text-left p-3">Order #</th>
                          <th className="text-left p-3">Table</th>
                          <th className="text-left p-3">Server</th>
                          <th className="text-right p-3">Sub Total</th>
                          <th className="text-right p-3">Total</th>
                          <th className="text-center p-3">Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filtered
                          .sort((a: any, b: any) => {
                            const da = (a.orderTime ?? a.ordertime ?? "")
                            const db = (b.orderTime ?? b.ordertime ?? "")
                            return db.localeCompare(da)
                          })
                          .map((x: any, idx: number) => (
                            <tr key={x.hotelRestaurantOrderId ?? x.hotelrestaurantorderid ?? `ro-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3">{(x.orderTime ?? x.ordertime ?? "").slice(0, 10)}</td>
                              <td className="p-3 font-mono text-xs">#{x.hotelRestaurantOrderId ?? x.hotelrestaurantorderid ?? idx}</td>
                              <td className="p-3">{x.tableNumber ?? x.tablenumber ?? "-"}</td>
                              <td className="p-3">{x.serverName ?? x.servername ?? "-"}</td>
                              <td className="p-3 text-right">GH&#8373;{Number(x.subTotal ?? x.subtotal ?? 0).toFixed(2)}</td>
                              <td className="p-3 text-right font-medium text-emerald-700">GH&#8373;{Number(x.totalAmount ?? x.totalamount ?? 0).toFixed(2)}</td>
                              <td className="p-3 text-center">{orderStatusBadge(x.status ?? "")}</td>
                            </tr>
                          ))}
                        {filtered.length === 0 && (
                          <tr><td colSpan={7} className="p-8 text-center text-slate-400">No orders found for this period.</td></tr>
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

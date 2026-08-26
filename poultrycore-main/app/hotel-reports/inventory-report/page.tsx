"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, ArrowLeft, Package, Download, Printer, FileText } from "lucide-react"
import { Button } from "@/components/ui/button"
import { downloadCsv } from "@/lib/utils/download-csv"
import { downloadPdf, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { printReport, type PrintReportConfig } from "@/lib/utils/print-report"
import { PdfPreviewDialog } from "@/components/reports/pdf-preview-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelInventory, getHotelProfile } from "@/lib/api/hotel"

export default function InventoryReportPage() {
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
      const res = await listHotelInventory()
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

  const totalItems = data.length
  const lowStock = data.filter((i: any) => {
    const stock = Number(i.stockOnHand ?? i.stockonhand ?? 0)
    const reorder = Number(i.reorderLevel ?? i.reorderlevel ?? 0)
    return stock <= reorder
  }).length
  const totalValue = data.reduce((s: number, i: any) => {
    const stock = Number(i.stockOnHand ?? i.stockonhand ?? 0)
    const cost = Number(i.unitCost ?? i.unitcost ?? 0)
    return s + stock * cost
  }, 0)
  const categoriesSet = new Set(data.map((i: any) => i.category ?? i.categoryName ?? i.categoryname ?? "Uncategorized"))
  const categoriesCount = categoriesSet.size

  function handleDownload() {
    const headers = ["Name", "Category", "Unit", "Stock", "Reorder Level", "Unit Cost", "Value"]
    const rows = data.map((i: any) => {
      const stock = Number(i.stockOnHand ?? i.stockonhand ?? 0)
      const cost = Number(i.unitCost ?? i.unitcost ?? 0)
      return [
        i.name ?? i.itemName ?? i.itemname ?? "",
        i.category ?? i.categoryName ?? i.categoryname ?? "",
        i.unit ?? i.unitOfMeasure ?? i.unitofmeasure ?? "",
        stock,
        Number(i.reorderLevel ?? i.reorderlevel ?? 0),
        cost.toFixed(2),
        (stock * cost).toFixed(2),
      ]
    })
    downloadCsv("inventory-report", headers, rows)
  }

  function getPdfConfig(): PdfReportConfig {
    const headers = ["Name", "Category", "Unit", "Stock", "Reorder Level", "Unit Cost", "Value"]
    const rows = data.map((i: any) => {
      const stock = Number(i.stockOnHand ?? i.stockonhand ?? 0)
      const cost = Number(i.unitCost ?? i.unitcost ?? 0)
      return [
        i.name ?? i.itemName ?? i.itemname ?? "",
        i.category ?? i.categoryName ?? i.categoryname ?? "",
        i.unit ?? i.unitOfMeasure ?? i.unitofmeasure ?? "",
        stock,
        Number(i.reorderLevel ?? i.reorderlevel ?? 0),
        cost.toFixed(2),
        (stock * cost).toFixed(2),
      ]
    })
    return {
      title: "Inventory Report",
      subtitle: "Hotel Management Report",
      filename: "inventory-report",
      hotelName,
      hotelAddress,
      hotelPhone,
      headers,
      rows,
      summaryCards: [
        { label: "Total Items", value: `${totalItems}` },
        { label: "Low Stock", value: `${lowStock}` },
        { label: "Total Value", value: `GH\u20B5${totalValue.toFixed(2)}` },
        { label: "Categories", value: `${categoriesCount}` },
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
            <Package className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Inventory Report</h1>
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
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-red-600">{lowStock}</div><div className="text-xs text-slate-500 mt-1">Low Stock</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-emerald-700">{totalValue.toFixed(2)}</div><div className="text-xs text-slate-500 mt-1">Total Value</div></CardContent></Card>
                <Card><CardContent className="p-4 text-center"><div className="text-2xl font-bold text-blue-600">{categoriesCount}</div><div className="text-xs text-slate-500 mt-1">Categories</div></CardContent></Card>
              </div>

              {/* Data Table */}
              <Card>
                <CardHeader><CardTitle className="text-base">Inventory Items ({data.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-slate-50 border-b">
                        <tr>
                          <th className="text-left p-3">Name</th>
                          <th className="text-left p-3">Category</th>
                          <th className="text-left p-3">Unit</th>
                          <th className="text-right p-3">Stock</th>
                          <th className="text-right p-3">Reorder Level</th>
                          <th className="text-right p-3">Unit Cost ()</th>
                          <th className="text-right p-3">Value ()</th>
                        </tr>
                      </thead>
                      <tbody>
                        {data.map((i: any, idx: number) => {
                          const stock = Number(i.stockOnHand ?? i.stockonhand ?? 0)
                          const reorder = Number(i.reorderLevel ?? i.reorderlevel ?? 0)
                          const cost = Number(i.unitCost ?? i.unitcost ?? 0)
                          const isLow = stock <= reorder
                          return (
                            <tr key={i.hotelInventoryItemId ?? i.hotelinventoryitemid ?? `inv-${idx}`} className="border-b hover:bg-slate-50">
                              <td className="p-3 font-medium">{i.name ?? i.itemName ?? i.itemname ?? "-"}</td>
                              <td className="p-3">{i.category ?? i.categoryName ?? i.categoryname ?? "-"}</td>
                              <td className="p-3">{i.unit ?? i.unitOfMeasure ?? i.unitofmeasure ?? "-"}</td>
                              <td className={`p-3 text-right font-medium ${isLow ? "text-red-600" : ""}`}>{stock}</td>
                              <td className="p-3 text-right">{reorder}</td>
                              <td className="p-3 text-right">{cost.toFixed(2)}</td>
                              <td className="p-3 text-right text-emerald-700 font-medium">{(stock * cost).toFixed(2)}</td>
                            </tr>
                          )
                        })}
                        {data.length === 0 && (
                          <tr><td colSpan={7} className="p-8 text-center text-slate-400">No inventory items found.</td></tr>
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

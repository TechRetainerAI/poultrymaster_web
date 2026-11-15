"use client"

// Closing by Category — period totals from daily closings grouped into
// colored category sections, matching the poultry closing-report design.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { ArrowLeft, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getDailyClosings, type GenericDailyClosing } from "@/lib/api/generic"
import { ReportExportButtons } from "@/components/reports/report-export-buttons"
import { ReportPageHeader } from "@/components/reports/report-header"

function monthStart() {
  const n = new Date()
  return new Date(n.getFullYear(), n.getMonth(), 1).toISOString().slice(0, 10)
}
function today() { return new Date().toISOString().slice(0, 10) }

type SectionDef = {
  title: string
  color: string
  rows: { label: string; value: number | string; money?: boolean }[]
}

export default function ClosingByCategoryPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericDailyClosing[]>([])
  const [loading, setLoading] = useState(true)
  const [from, setFrom] = useState(monthStart())
  const [to, setTo] = useState(today())

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try { setRows(await getDailyClosings()) }
    catch (e: any) { toast({ title: "Could not load closings", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const inRange = useMemo(() => {
    return rows.filter((r) => {
      const d = r.closingDate.slice(0, 10)
      return (!from || d >= from) && (!to || d <= to)
    }).filter((r) => r.status === "Approved")
  }, [rows, from, to])

  // Build the category sections — matching poultry's colored section cards
  const sections: SectionDef[] = useMemo(() => {
    const sum = (fn: (r: GenericDailyClosing) => number) => inRange.reduce((s, r) => s + fn(r), 0)
    const latest = inRange.length > 0 ? inRange[inRange.length - 1] : null

    return [
      {
        title: "Financial Summary",
        color: "bg-blue-600",
        rows: [
          { label: "Total Sales / Income", value: sum((r) => r.totalSales), money: true },
          { label: "Total Expenses", value: sum((r) => r.totalExpenses), money: true },
          { label: "Purchases Paid", value: sum((r) => r.totalPurchasesPaid), money: true },
          { label: "Net Profit / Loss", value: sum((r) => r.totalSales) - sum((r) => r.totalExpenses), money: true },
          { label: "Amount Owed by Customers", value: latest?.customerDebtTotal ?? 0, money: true },
          { label: "Amount Owed to Suppliers", value: latest?.supplierDebtTotal ?? 0, money: true },
        ],
      },
      {
        title: "Cash Summary",
        color: "bg-emerald-600",
        rows: [
          { label: "Total Cash In", value: sum((r) => r.totalCashIn), money: true },
          { label: "Total Cash Out", value: sum((r) => r.totalCashOut), money: true },
          { label: "Total Customer Payments", value: sum((r) => r.totalCustomerPayments), money: true },
          { label: "Total Supplier Payments", value: sum((r) => r.totalSupplierPayments), money: true },
          { label: "Average Opening Cash", value: inRange.length > 0 ? sum((r) => r.openingCash) / inRange.length : 0, money: true },
        ],
      },
      {
        title: "Cash Reconciliation",
        color: "bg-indigo-600",
        rows: [
          { label: "Average Expected Cash", value: inRange.length > 0 ? sum((r) => r.expectedCash) / inRange.length : 0, money: true },
          { label: "Average Actual Cash Counted", value: inRange.length > 0 ? sum((r) => r.actualCashCounted) / inRange.length : 0, money: true },
          { label: "Total Cash Difference", value: sum((r) => r.cashDifference), money: true },
          { label: "Credit Sales", value: sum((r) => r.creditSales), money: true },
        ],
      },
      {
        title: "Inventory & Adjustments",
        color: "bg-amber-600",
        rows: [
          { label: "Stock Adjustments", value: sum((r) => r.inventoryAdjustmentsCount) },
          { label: "Closings in Period", value: inRange.length },
          { label: "Approved Closings", value: inRange.length },
        ],
      },
    ]
  }, [inRange])

  const netProfit = useMemo(() => {
    const sales = inRange.reduce((s, r) => s + r.totalSales, 0)
    const expenses = inRange.reduce((s, r) => s + r.totalExpenses, 0)
    return sales - expenses
  }, [inRange])

  const pdfOpts = useMemo(() => ({
    title: "Closing by Category",
    subtitle: `${from} to ${to}`,
    columns: [
      { header: "Category", key: "category", width: 120 },
      { header: "Item", key: "item", width: 180 },
      { header: "Value", key: "value", width: 100, align: "right" as const },
    ],
    rows: sections.flatMap((s) =>
      s.rows.map((r) => ({
        category: s.title,
        item: r.label,
        value: typeof r.value === "number" ? (r.money ? r.value : r.value) : r.value,
      }))
    ),
  }), [sections, from, to])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mx-auto w-full max-w-6xl">
            <div className="flex items-center justify-between flex-wrap gap-2 mb-2">
              <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700">
                <ArrowLeft className="h-3 w-3 mr-1" /> Reports
              </Link>
              <ReportExportButtons pdf={pdfOpts} disabled={loading || inRange.length === 0} csvFilename="closing-by-category" />
            </div>

            <button onClick={() => router.back()} className="rounded-full p-1 hover:bg-slate-200 transition" title="Go back"><ArrowLeft className="w-5 h-5 text-slate-600" /></button>
            <ReportPageHeader title="Closing by Category" description="Period totals from approved daily closings, grouped into financial categories." period={{ from, to }} />

            <Card className="mb-4">
              <CardContent className="p-4 flex flex-wrap items-end gap-3">
                <div><label className="text-xs text-slate-500 block mb-1">From</label><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="w-40" /></div>
                <div><label className="text-xs text-slate-500 block mb-1">To</label><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="w-40" /></div>
                <Button onClick={load} disabled={loading}>{loading ? <Loader2 className="w-4 h-4 animate-spin" /> : "Run report"}</Button>
                <span className="text-sm text-slate-500">{inRange.length} approved closing(s) in period</span>
              </CardContent>
            </Card>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
            ) : inRange.length === 0 ? (
              <Card><CardContent className="py-8 text-center text-slate-500">No approved closings in this period.</CardContent></Card>
            ) : (
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                {sections.map((s) => (
                  <Card key={s.title} className="overflow-hidden">
                    <div className={`${s.color} text-white px-4 py-2.5 font-semibold text-sm`}>{s.title}</div>
                    <CardContent className="p-0">
                      <table className="w-full text-sm">
                        <tbody>
                          {s.rows.map((r) => (
                            <tr key={r.label} className="border-b last:border-0">
                              <td className="px-4 py-2.5 text-slate-600">{r.label}</td>
                              <td className="px-4 py-2.5 text-right font-medium tabular-nums text-slate-900">
                                {typeof r.value === "number"
                                  ? (r.money ? fmt(r.value) : r.value.toLocaleString())
                                  : r.value}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

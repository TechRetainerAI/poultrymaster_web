"use client"

// Closing by Category — period totals from daily closings grouped into
// financial categories: sales, expenses, cash, purchases, and balances.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, BarChart3, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getDailyClosings, type GenericDailyClosing } from "@/lib/api/generic"
import { cn } from "@/lib/utils"
import { ReportExportButtons } from "@/components/reports/report-export-buttons"
import { ReportPageHeader, RichCard } from "@/components/reports/report-header"

function monthStart() {
  const n = new Date()
  return new Date(n.getFullYear(), n.getMonth(), 1).toISOString().slice(0, 10)
}
function today() { return new Date().toISOString().slice(0, 10) }

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

  const categories = useMemo(() => {
    const sum = (fn: (r: GenericDailyClosing) => number) => inRange.reduce((s, r) => s + fn(r), 0)
    return [
      { category: "Sales", subcategories: [
        { label: "Total Sales", value: sum((r) => r.totalSales), accent: "emerald" },
        { label: "Credit Sales", value: sum((r) => r.creditSales), accent: "amber" },
        { label: "Customer Payments Received", value: sum((r) => r.totalCustomerPayments), accent: "emerald" },
      ]},
      { category: "Expenses & Purchases", subcategories: [
        { label: "Total Expenses", value: sum((r) => r.totalExpenses), accent: "red" },
        { label: "Purchases Paid", value: sum((r) => r.totalPurchasesPaid), accent: "orange" },
        { label: "Supplier Payments", value: sum((r) => r.totalSupplierPayments), accent: "orange" },
      ]},
      { category: "Cash", subcategories: [
        { label: "Total Cash In", value: sum((r) => r.totalCashIn), accent: "emerald" },
        { label: "Total Cash Out", value: sum((r) => r.totalCashOut), accent: "red" },
        { label: "Average Opening Cash", value: inRange.length > 0 ? sum((r) => r.openingCash) / inRange.length : 0, accent: "blue" },
        { label: "Average Cash Difference", value: inRange.length > 0 ? sum((r) => r.cashDifference) / inRange.length : 0 },
      ]},
      { category: "Balances", subcategories: [
        { label: "Customer Debt (latest)", value: inRange.length > 0 ? inRange[inRange.length - 1].customerDebtTotal : 0, accent: "amber" },
        { label: "Supplier Debt (latest)", value: inRange.length > 0 ? inRange[inRange.length - 1].supplierDebtTotal : 0, accent: "orange" },
        { label: "Stock Adjustments", value: sum((r) => r.inventoryAdjustmentsCount) },
      ]},
    ]
  }, [inRange])

  const netProfit = useMemo(() => {
    const sales = inRange.reduce((s, r) => s + r.totalSales, 0)
    const expenses = inRange.reduce((s, r) => s + r.totalExpenses, 0)
    return sales - expenses
  }, [inRange])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 min-w-0 space-y-4">
          <div className="mx-auto w-full max-w-7xl">
            <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
              <ArrowLeft className="h-3 w-3 mr-1" /> Reports
            </Link>
            <ReportPageHeader title="Closing by Category" description="Period totals from approved daily closings, grouped by financial category." period={{ from, to }} />

            <Card className="mb-4">
              <CardContent className="flex flex-wrap items-end gap-3 pt-6">
                <div><Label>From</Label><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
                <div><Label>To</Label><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
                <Button variant="outline" onClick={load} disabled={loading}>
                  {loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Refresh
                </Button>
                <div className="text-sm text-slate-500">{inRange.length} approved closing(s) in period</div>
                <ReportExportButtons disabled={loading || inRange.length === 0} csvFilename="closing-by-category" pdf={{
                  title: "Closing by Category",
                  subtitle: `${from} to ${to}`,
                  columns: [
                    { header: "Category", key: "category", width: 120 },
                    { header: "Item", key: "item", width: 150 },
                    { header: "Amount", key: "amount", width: 100, align: "right" as const, format: "currency" as const },
                  ],
                  rows: categories.flatMap((cat) => cat.subcategories.map((sub) => ({ category: cat.category, item: sub.label, amount: sub.value }))),
                }} />
              </CardContent>
            </Card>

            <div className="grid grid-cols-2 lg:grid-cols-3 gap-3 mb-4">
              <RichCard label="Total Sales" value={fmt(inRange.reduce((s, r) => s + r.totalSales, 0))} accent="emerald" lines={["From approved closings"]} />
              <RichCard label="Total Expenses" value={fmt(inRange.reduce((s, r) => s + r.totalExpenses, 0))} accent="red" lines={["From approved closings"]} />
              <RichCard label="Net Profit" value={fmt(netProfit)} accent={netProfit >= 0 ? "emerald" : "red"} lines={["Sales minus expenses"]} />
            </div>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : inRange.length === 0 ? (
              <Card><CardContent className="py-8 text-center text-slate-500">No approved closings in this period.</CardContent></Card>
            ) : (
              <div className="space-y-4">
                {categories.map((cat) => (
                  <Card key={cat.category}>
                    <CardContent className="pt-6">
                      <h2 className="text-lg font-semibold text-slate-900 mb-3">{cat.category}</h2>
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Item</TableHead>
                            <TableHead className="text-right">Amount</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {cat.subcategories.map((sub) => (
                            <TableRow key={sub.label}>
                              <TableCell className="font-medium">{sub.label}</TableCell>
                              <TableCell className={cn("text-right tabular-nums font-medium", {
                                emerald: "text-emerald-700", red: "text-red-600", amber: "text-amber-700",
                                orange: "text-orange-700", blue: "text-blue-700",
                              }[sub.accent ?? ""] ?? "text-slate-900")}>
                                {fmt(sub.value)}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
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

function Tile({ label, value, accent }: { label: string; value: string; accent?: string }) {
  const color = { emerald: "text-emerald-700", red: "text-red-600" }[accent ?? ""] ?? "text-slate-900"
  return (
    <Card><CardContent className="p-3">
      <div className="text-xs uppercase tracking-wide text-slate-500 truncate">{label}</div>
      <div className={cn("text-lg font-bold mt-1 truncate", color)}>{value}</div>
    </CardContent></Card>
  )
}

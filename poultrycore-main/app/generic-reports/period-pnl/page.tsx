"use client"

// Profit & Loss (Company) — the most important financial report.
// Shows income, expenses, COGS, gross profit and net profit for any period,
// with a proper P&L statement layout, summary cards, and CSV/Email/PDF export.

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
import { ArrowLeft, DollarSign, Loader2, TrendingUp, TrendingDown } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getPeriodPnL, type GenericPeriodPnL } from "@/lib/api/generic"
import { getIncomeSplit, type GenericIncomeSplit } from "@/lib/api/generic-reports"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod } from "@/lib/date-ranges"
import { ReportExportButtons } from "@/components/reports/report-export-buttons"
import { cn } from "@/lib/utils"

function defaultMonthRange() {
  const now = new Date()
  const start = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10)
  const end = now.toISOString().slice(0, 10)
  return { fromDate: start, toDate: end }
}

export default function PeriodPnLPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const { labels, isSubscriptionBusiness } = useGenericModules()

  const [range, setRange] = useState(defaultMonthRange())
  const [data, setData] = useState<GenericPeriodPnL | null>(null)
  const [split, setSplit] = useState<GenericIncomeSplit | null>(null)
  const [loading, setLoading] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      const [pnl, sp] = await Promise.all([
        getPeriodPnL(range.fromDate, range.toDate),
        getIncomeSplit(range.fromDate, range.toDate).catch(() => null),
      ])
      setData(pnl)
      setSplit(sp)
    } catch (e: any) {
      toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  // Build the P&L statement rows for display and export
  const statementRows = useMemo(() => {
    if (!data) return []
    const rows: { label: string; value: number; bold?: boolean; indent?: boolean; separator?: boolean }[] = [
      { label: "Revenue / Sales", value: data.totalIncome, bold: true },
      ...(split && isSubscriptionBusiness ? [
        { label: `${labels.subscription} income`, value: split.subscriptionIncome, indent: true },
        { label: "Other income", value: split.otherIncome, indent: true },
      ] : []),
      { label: "", value: 0, separator: true },
      { label: "Cost of Goods Sold (COGS)", value: -data.costOfGoodsSold },
      { label: "Gross Profit", value: data.grossProfit, bold: true },
      { label: "", value: 0, separator: true },
      { label: "Operating Expenses", value: -data.totalExpenses },
      { label: "Purchases Paid", value: -data.totalPurchasesPaid, indent: true },
      { label: "", value: 0, separator: true },
      { label: "Net Profit / (Loss)", value: data.netProfit, bold: true },
    ]
    return rows
  }, [data, split, isSubscriptionBusiness, labels])

  const pdfOpts = useMemo(() => ({
    title: "Profit & Loss Statement",
    subtitle: `${range.fromDate} to ${range.toDate}`,
    columns: [
      { header: "Item", key: "label", width: 200 },
      { header: "Amount", key: "amount", width: 100, align: "right" as const, format: "currency" as const },
    ],
    rows: statementRows.filter((r) => !r.separator).map((r) => ({
      label: (r.indent ? "  " : "") + r.label,
      amount: r.value,
    })),
  }), [statementRows, range])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mx-auto w-full max-w-5xl">
            <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
              <ArrowLeft className="h-3 w-3 mr-1" /> Back to reports
            </Link>
            <div className="flex items-center justify-between flex-wrap gap-2 mb-4">
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <DollarSign className="h-6 w-6 text-emerald-600" /> Profit & Loss
              </h1>
              <ReportExportButtons pdf={pdfOpts} disabled={loading || !data} csvFilename="profit-and-loss" />
            </div>

            <Card className="mb-4">
              <CardContent className="flex flex-wrap items-end gap-3 pt-6">
                <PeriodSelect value={rangeToPeriod(range.fromDate, range.toDate)}
                  onChange={(_p, rg) => { if (rg) setRange({ fromDate: rg.from, toDate: rg.to }) }} />
                <div><Label>From</Label><Input type="date" value={range.fromDate} onChange={(e) => setRange((r) => ({ ...r, fromDate: e.target.value }))} /></div>
                <div><Label>To</Label><Input type="date" value={range.toDate} onChange={(e) => setRange((r) => ({ ...r, toDate: e.target.value }))} /></div>
                <Button onClick={load} disabled={loading}>{loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Run</Button>
              </CardContent>
            </Card>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : !data ? null : (
              <>
                {/* Summary cards */}
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
                  <Tile icon={TrendingUp} label="Total Income" value={fmt(data.totalIncome)} accent="emerald" />
                  <Tile icon={TrendingDown} label="Total Expenses" value={fmt(data.totalExpenses)} accent="red" />
                  <Tile icon={DollarSign} label="Gross Profit" value={fmt(data.grossProfit)}
                    accent={data.grossProfit >= 0 ? "emerald" : "red"} />
                  <Tile icon={DollarSign} label="Net Profit" value={fmt(data.netProfit)}
                    accent={data.netProfit >= 0 ? "emerald" : "red"}
                    sub={`Margin: ${data.profitMarginPct.toFixed(1)}%`} />
                </div>

                {/* P&L Statement */}
                <Card>
                  <CardContent className="pt-6">
                    <h2 className="text-lg font-semibold text-slate-900 mb-3">Profit & Loss Statement</h2>
                    <p className="text-xs text-slate-500 mb-4">{range.fromDate} to {range.toDate} · {data.salesCount} sale(s)</p>
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead className="w-[70%]">Item</TableHead>
                            <TableHead className="text-right">Amount</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {statementRows.map((row, i) => row.separator ? (
                            <TableRow key={i}><TableCell colSpan={2} className="py-1"><hr className="border-slate-200" /></TableCell></TableRow>
                          ) : (
                            <TableRow key={i}>
                              <TableCell className={cn(row.bold ? "font-semibold" : "", row.indent ? "pl-8 text-slate-600" : "")}>
                                {row.label}
                              </TableCell>
                              <TableCell className={cn(
                                "text-right tabular-nums",
                                row.bold ? "font-semibold" : "",
                                row.value > 0 ? "text-emerald-700" : row.value < 0 ? "text-red-600" : "text-slate-500",
                              )}>
                                {fmt(row.value)}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  </CardContent>
                </Card>
              </>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

function Tile({ icon: Icon, label, value, accent, sub }: {
  icon: any; label: string; value: string; accent?: string; sub?: string
}) {
  const color = { emerald: "text-emerald-700", red: "text-red-600" }[accent ?? ""] ?? "text-slate-900"
  return (
    <Card><CardContent className="p-4">
      <div className="flex items-center gap-1 text-xs uppercase tracking-wide text-slate-500">
        <Icon className="h-3.5 w-3.5" /> {label}
      </div>
      <div className={cn("text-xl font-bold mt-1 truncate", color)}>{value}</div>
      {sub && <div className="text-xs text-slate-400 mt-0.5">{sub}</div>}
    </CardContent></Card>
  )
}

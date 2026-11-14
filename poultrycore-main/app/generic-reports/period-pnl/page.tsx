"use client"

// Profit & Loss (Company) — deep copy of the poultry P&L report visual style.
// Rich summary cards with formulas, color-coded borders, company name, period
// and generated timestamps, and proper P&L statement table.

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
import { ArrowLeft, Loader2 } from "lucide-react"
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

function fmtTimestamp() {
  return new Intl.DateTimeFormat(undefined, {
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "numeric", minute: "2-digit", second: "2-digit",
  }).format(new Date())
}

export default function PeriodPnLPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const farmName = useAuthStore((s) => s.activeFarmName)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const { labels, isSubscriptionBusiness } = useGenericModules()

  const [range, setRange] = useState(defaultMonthRange())
  const [data, setData] = useState<GenericPeriodPnL | null>(null)
  const [split, setSplit] = useState<GenericIncomeSplit | null>(null)
  const [loading, setLoading] = useState(false)
  const [generated, setGenerated] = useState("")

  const load = async () => {
    setLoading(true)
    try {
      const [pnl, sp] = await Promise.all([
        getPeriodPnL(range.fromDate, range.toDate),
        getIncomeSplit(range.fromDate, range.toDate).catch(() => null),
      ])
      setData(pnl)
      setSplit(sp)
      setGenerated(fmtTimestamp())
    } catch (e: any) {
      toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const statementRows = useMemo(() => {
    if (!data) return []
    return [
      { label: "Revenue / Sales", value: data.totalIncome, bold: true },
      ...(split && isSubscriptionBusiness ? [
        { label: `  ${labels.subscription} income`, value: split.subscriptionIncome, indent: true },
        { label: "  Other income", value: split.otherIncome, indent: true },
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
  }, [data, split, isSubscriptionBusiness, labels])

  const pdfOpts = useMemo(() => ({
    title: "Profit & Loss Statement",
    subtitle: `${range.fromDate} to ${range.toDate}`,
    columns: [
      { header: "Item", key: "label", width: 200 },
      { header: "Amount", key: "amount", width: 100, align: "right" as const, format: "currency" as const },
    ],
    rows: statementRows.filter((r) => !r.separator).map((r) => ({
      label: r.label, amount: r.value,
    })),
  }), [statementRows, range])

  const d = data
  const grossProfit = d?.grossProfit ?? 0
  const netProfit = d?.netProfit ?? 0
  const operatingProfit = grossProfit - (d?.totalExpenses ?? 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mx-auto w-full max-w-6xl">
            <div className="flex items-center justify-between flex-wrap gap-2 mb-4">
              <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700">
                <ArrowLeft className="h-3 w-3 mr-1" /> Reports
              </Link>
              <ReportExportButtons pdf={pdfOpts} disabled={loading || !data} csvFilename="profit-and-loss" />
            </div>

            {/* Report header card — matches poultry style */}
            <Card className="mb-4 border-t-4 border-t-amber-500">
              <CardContent className="pt-6">
                <div className="text-xs font-bold uppercase tracking-wider text-amber-600 mb-1">{farmName ?? "Company"}</div>
                <h1 className="text-2xl font-bold text-slate-900">Profit & Loss</h1>
                <p className="text-sm text-slate-500 mt-1">Did the business make money from its operations this period?</p>
                <div className="flex flex-wrap gap-x-8 gap-y-1 mt-3 text-sm text-slate-600">
                  <div><span className="text-slate-400">Period:</span> {range.fromDate} → {range.toDate}</div>
                  {generated && <div><span className="text-slate-400">Generated:</span> {generated}</div>}
                  <div><span className="text-slate-400">Currency:</span> GHS (GHC)</div>
                </div>

                {/* Period selector */}
                <div className="flex flex-wrap items-end gap-3 mt-4 pt-4 border-t border-slate-100">
                  <div><Label className="text-xs text-slate-500">Period</Label>
                    <PeriodSelect value={rangeToPeriod(range.fromDate, range.toDate)}
                      onChange={(_p, rg) => { if (rg) setRange({ fromDate: rg.from, toDate: rg.to }) }} />
                  </div>
                  <div><Label className="text-xs text-slate-500">From</Label>
                    <Input type="date" value={range.fromDate} onChange={(e) => setRange((r) => ({ ...r, fromDate: e.target.value }))} />
                  </div>
                  <div><Label className="text-xs text-slate-500">To</Label>
                    <Input type="date" value={range.toDate} onChange={(e) => setRange((r) => ({ ...r, toDate: e.target.value }))} />
                  </div>
                  <Button variant="outline" onClick={() => setRange(defaultMonthRange())}>Clear</Button>
                  <Button onClick={load} disabled={loading}>
                    {loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Run
                  </Button>
                </div>
              </CardContent>
            </Card>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : !d ? null : (
              <>
                {/* 5 rich summary cards — matching poultry style */}
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
                  <RichCard
                    label="Total Revenue"
                    value={fmt(d.totalIncome)}
                    accent="slate"
                    lines={[
                      "Everything sold this period",
                      `${d.salesCount} sale(s)`,
                    ]}
                  />
                  <RichCard
                    label="Total Expenses"
                    value={fmt(d.totalExpenses + d.costOfGoodsSold)}
                    accent={d.totalExpenses > 0 ? "red" : "slate"}
                    lines={[
                      `Direct costs + Operating expenses`,
                      `${fmt(d.costOfGoodsSold)} + ${fmt(d.totalExpenses)}`,
                      d.totalIncome === 0 ? "" : "Everything taken off revenue",
                    ]}
                  />
                  <RichCard
                    label="Gross Profit"
                    value={fmt(grossProfit)}
                    accent={grossProfit >= 0 ? "emerald" : "red"}
                    lines={[
                      "Revenue − Direct costs",
                      `${fmt(d.totalIncome)} − ${fmt(d.costOfGoodsSold)}`,
                      grossProfit < 0 ? "No sales this period" : "",
                    ]}
                  />
                  <RichCard
                    label="Operating Profit"
                    value={fmt(operatingProfit)}
                    accent={operatingProfit >= 0 ? "emerald" : "red"}
                    lines={[
                      "Gross profit − Operating expenses",
                      `(${fmt(grossProfit)}) − ${fmt(d.totalExpenses)}`,
                      "Before depreciation and financing",
                    ]}
                  />
                  <RichCard
                    label={netProfit >= 0 ? "Net Profit" : "Net Loss"}
                    value={fmt(netProfit)}
                    accent={netProfit >= 0 ? "emerald" : "red"}
                    lines={[
                      "Operating profit − Depreciation & financing",
                      `(${fmt(operatingProfit)}) − ${fmt(0)}`,
                      netProfit >= 0 ? `Margin: ${d.profitMarginPct.toFixed(1)}%` : "Loss",
                    ]}
                  />
                </div>

                {/* P&L Statement table */}
                <Card>
                  <CardContent className="pt-6">
                    <h2 className="text-lg font-semibold text-slate-900 mb-1">Profit & Loss Statement</h2>
                    <p className="text-xs text-slate-500 mb-4">{range.fromDate} to {range.toDate} · {d.salesCount} sale(s)</p>
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow className="bg-slate-50">
                            <TableHead className="w-[70%] font-semibold">Item</TableHead>
                            <TableHead className="text-right font-semibold">Amount</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {statementRows.map((row, i) => row.separator ? (
                            <TableRow key={i}><TableCell colSpan={2} className="py-0.5 border-0" /></TableRow>
                          ) : (
                            <TableRow key={i} className={row.bold ? "bg-slate-50" : ""}>
                              <TableCell className={cn(
                                row.bold ? "font-bold text-slate-900" : "",
                                row.indent ? "pl-8 text-slate-500 text-sm" : "",
                              )}>
                                {row.label}
                              </TableCell>
                              <TableCell className={cn(
                                "text-right tabular-nums",
                                row.bold ? "font-bold" : "",
                                row.value > 0 ? "text-emerald-700" : row.value < 0 ? "text-red-600" : "text-slate-400",
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

                {/* Subscription income split */}
                {split && isSubscriptionBusiness && (
                  <Card className="mt-4">
                    <CardContent className="pt-6">
                      <h2 className="text-lg font-semibold text-slate-900 mb-3">Income Breakdown</h2>
                      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                        <RichCard label={`${labels.subscription} Income`} value={fmt(split.subscriptionIncome)} accent="emerald" lines={["Recurring revenue"]} />
                        <RichCard label="Other Income" value={fmt(split.otherIncome)} accent="slate" lines={["Non-recurring"]} />
                        <RichCard
                          label="Recurring Share"
                          value={split.totalIncome > 0 ? `${((split.subscriptionIncome * 100) / split.totalIncome).toFixed(1)}%` : "—"}
                          accent="amber"
                          lines={["Of total income"]}
                        />
                      </div>
                    </CardContent>
                  </Card>
                )}
              </>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

/** Rich summary card matching the poultry report style — colored left border, formula lines. */
function RichCard({ label, value, accent, lines }: {
  label: string; value: string; accent: "slate" | "emerald" | "red" | "amber"
  lines: string[]
}) {
  const borderColor = {
    slate: "border-l-slate-300",
    emerald: "border-l-emerald-500",
    red: "border-l-red-500",
    amber: "border-l-amber-500",
  }[accent]
  const valueColor = {
    slate: "text-slate-900",
    emerald: "text-emerald-700",
    red: "text-red-600",
    amber: "text-amber-700",
  }[accent]
  const labelColor = {
    slate: "text-slate-500",
    emerald: "text-emerald-600",
    red: "text-red-500",
    amber: "text-amber-600",
  }[accent]

  return (
    <Card className={cn("border-l-4", borderColor)}>
      <CardContent className="p-4">
        <div className={cn("text-[11px] font-semibold uppercase tracking-wider mb-1", labelColor)}>{label}</div>
        <div className={cn("text-xl font-bold tabular-nums", valueColor)}>{value}</div>
        <div className="mt-2 space-y-0.5">
          {lines.filter(Boolean).map((line, i) => (
            <div key={i} className="text-xs text-slate-500">{line}</div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

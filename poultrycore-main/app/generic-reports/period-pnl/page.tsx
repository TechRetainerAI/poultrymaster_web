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
import { ArrowLeft, Banknote, Building2, Info, Loader2, Wallet } from "lucide-react"
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
import { RichCard } from "@/components/reports/report-header"
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
                <button onClick={() => router.back()} className="rounded-full p-1 hover:bg-slate-200 transition" title="Go back"><ArrowLeft className="w-5 h-5 text-slate-600" /></button>
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

                {/* 4 breakdown columns — matching poultry layout */}
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
                  <Card className="border-t-[3px] border-t-emerald-400">
                    <CardContent className="p-4">
                      <div className="text-xs font-bold uppercase tracking-wider text-emerald-600 mb-3">Revenue</div>
                      {d.totalIncome > 0 ? (
                        <div className="text-sm text-slate-600 mb-3">
                          Sales · {d.salesCount} transaction(s)
                        </div>
                      ) : (
                        <div className="text-sm text-slate-400 mb-3">None this period</div>
                      )}
                      <div className="border-t border-emerald-200 pt-2 flex justify-between font-semibold text-sm">
                        <span>Total Revenue</span>
                        <span>{fmt(d.totalIncome)}</span>
                      </div>
                    </CardContent>
                  </Card>

                  <Card className="border-t-[3px] border-t-red-400">
                    <CardContent className="p-4">
                      <div className="text-xs font-bold uppercase tracking-wider text-red-500 mb-3">Direct Production Costs</div>
                      {d.costOfGoodsSold > 0 ? (
                        <div className="text-sm text-slate-600 mb-3">Cost of goods sold</div>
                      ) : (
                        <div className="text-sm text-slate-400 mb-3">None this period</div>
                      )}
                      <div className="border-t border-red-200 pt-2 flex justify-between font-semibold text-sm">
                        <span>Total Direct Costs</span>
                        <span>({fmt(d.costOfGoodsSold)})</span>
                      </div>
                    </CardContent>
                  </Card>

                  <Card className="border-t-[3px] border-t-amber-400">
                    <CardContent className="p-4">
                      <div className="text-xs font-bold uppercase tracking-wider text-amber-600 mb-3">Operating Expenses</div>
                      {d.totalExpenses > 0 ? (
                        <div className="text-sm text-slate-600 mb-3">Business operating costs</div>
                      ) : (
                        <div className="text-sm text-slate-400 mb-3">None this period</div>
                      )}
                      <div className="border-t border-amber-200 pt-2 flex justify-between font-semibold text-sm">
                        <span>Total Operating Expenses</span>
                        <span>({fmt(d.totalExpenses)})</span>
                      </div>
                    </CardContent>
                  </Card>

                  <Card className="border-t-[3px] border-t-yellow-400">
                    <CardContent className="p-4">
                      <div className="text-xs font-bold uppercase tracking-wider text-yellow-600 mb-3">Depreciation & Financing Costs</div>
                      <div className="text-sm text-slate-400 mb-3">None this period</div>
                      <div className="border-t border-yellow-200 pt-2 flex justify-between font-semibold text-sm">
                        <span>Total Depreciation & Financing</span>
                        <span>({fmt(0)})</span>
                      </div>
                    </CardContent>
                  </Card>
                </div>

                {/* 3 "Excluded from profit" cards — matching poultry */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-3 mb-4">
                  <Card>
                    <CardContent className="p-5">
                      <div className="flex items-center gap-2 mb-1">
                        <Wallet className="h-4 w-4 text-slate-600" />
                        <span className="font-semibold text-slate-900">Owner Contributions & Draws</span>
                      </div>
                      <div className="text-[11px] font-bold uppercase tracking-wider text-amber-600 mb-2">Excluded from profit</div>
                      <p className="text-sm text-slate-600 mb-3">
                        Money the owner puts in or takes out. It changes company cash but is never profit:{" "}
                        <span className="bg-amber-50 text-amber-800 px-1 rounded font-medium">putting money in is not income, and taking it out is not an expense.</span>
                      </p>
                      <div className="text-sm text-slate-500 mb-1">Net owner funding <span className="font-bold text-slate-900">{fmt(0)}</span></div>
                      <div className="flex gap-3 mt-3">
                        <Link href="/generic-owner-money" className="text-sm text-blue-600 hover:underline">View Owner Money</Link>
                        <Link href="/generic-cash-flow" className="text-sm text-blue-600 hover:underline">View Cash Flow</Link>
                      </div>
                    </CardContent>
                  </Card>

                  <Card>
                    <CardContent className="p-5">
                      <div className="flex items-center gap-2 mb-1">
                        <Banknote className="h-4 w-4 text-slate-600" />
                        <span className="font-semibold text-slate-900">Loans (Financing)</span>
                      </div>
                      <div className="text-[11px] font-bold uppercase tracking-wider text-amber-600 mb-2">Excluded from profit</div>
                      <p className="text-sm text-slate-600 mb-3">
                        Money borrowed and principal repaid.{" "}
                        <span className="bg-red-50 text-red-700 px-1 rounded font-medium">Borrowing is not income and repaying principal is not an expense</span>
                        {" "}— only the interest and fees are a cost of borrowing.
                      </p>
                      <div className="text-sm text-slate-500 mb-1">Net borrowing <span className="font-bold text-slate-900">{fmt(0)}</span></div>
                      <div className="flex gap-3 mt-3">
                        <Link href="/generic-loans" className="text-sm text-blue-600 hover:underline">View Loans</Link>
                        <Link href="/generic-cash-flow" className="text-sm text-blue-600 hover:underline">View Cash Flow</Link>
                      </div>
                    </CardContent>
                  </Card>

                  <Card>
                    <CardContent className="p-5">
                      <div className="flex items-center gap-2 mb-1">
                        <Building2 className="h-4 w-4 text-slate-600" />
                        <span className="font-semibold text-slate-900">Capital Investments</span>
                      </div>
                      <div className="text-[11px] font-bold uppercase tracking-wider text-violet-600 mb-2">Excluded from immediate operating expenses</div>
                      <p className="text-sm text-slate-600 mb-3">
                        Capital investments affect cash but are not charged against profit in the period they are bought.{" "}
                        <span className="bg-violet-50 text-violet-700 px-1 rounded font-medium">Their cost is recognised over time through depreciation.</span>
                      </p>
                      <div className="text-sm text-slate-500 mb-1">Total capital investments <span className="font-bold text-slate-900">{fmt(0)}</span></div>
                      <div className="flex gap-3 mt-3">
                        <Link href="/generic-assets" className="text-sm text-blue-600 hover:underline">View Capital Investments/Assets</Link>
                      </div>
                    </CardContent>
                  </Card>
                </div>

                {/* "Profit is not the same as cash flow" educational section */}
                <Card className="mb-4 bg-blue-50/50 border-blue-100">
                  <CardContent className="p-6">
                    <div className="flex items-start gap-2 mb-3">
                      <Info className="h-5 w-5 text-blue-600 mt-0.5 shrink-0" />
                      <div>
                        <h3 className="font-semibold text-slate-900">Profit is not the same as cash flow</h3>
                        <p className="text-sm text-slate-600 mt-1">
                          Profit measures the revenue and costs that belong to the selected period.
                          Cash Flow measures the money that actually entered and left the company.
                          They are both right, and they can differ.
                        </p>
                      </div>
                    </div>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mt-4">
                      <div>
                        <h4 className="font-semibold text-sm text-slate-900 mb-2">Cash out that is not this period's cost</h4>
                        <ul className="list-disc pl-5 text-sm text-slate-600 space-y-1">
                          <li>Buying stock you will use later — the cash leaves now, the cost lands as you use it</li>
                          <li>Buying a building or machine — the cash leaves now, the cost spreads over its useful life</li>
                          <li>Repaying loan principal — money you are giving back, not a cost</li>
                          <li>Owner draws — the owner taking money out, not a business cost</li>
                        </ul>
                      </div>
                      <div>
                        <h4 className="font-semibold text-sm text-slate-900 mb-2">Costs that did not move cash this period</h4>
                        <ul className="list-disc pl-5 text-sm text-slate-600 space-y-1">
                          <li>Depreciation — a real cost of this period that moves no money</li>
                          <li>Stock bought earlier and used now — the cost lands now, the cash left months ago</li>
                          <li>A bill you have received but not yet paid — the cost is yours the day it is incurred</li>
                        </ul>
                      </div>
                    </div>
                    <div className="mt-4">
                      <Link href="/generic-cash-flow" className="text-sm text-blue-600 hover:underline">View Cash Flow</Link>
                    </div>
                  </CardContent>
                </Card>

                {/* Footer note */}
                <div className="text-xs text-slate-400 mb-4">
                  Profit & Loss uses structured revenue, expense, inventory-cost, depreciation and financing classifications.
                  Cash movements such as owner funding, loan principal, inventory bought under consumption costing, and capital
                  investments may affect Cash Flow without affecting profit.
                </div>

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

// RichCard imported from @/components/reports/report-header

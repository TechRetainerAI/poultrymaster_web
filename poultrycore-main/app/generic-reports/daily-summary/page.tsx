"use client"

// Daily Business Summary — a snapshot of today and this week.
// Uses the dashboard API to show sales, expenses, profit, cash, inventory
// and outstanding balances in a report-style layout.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import {
  ArrowLeft, BarChart3, DollarSign, Loader2, ShoppingCart, TrendingDown,
  TrendingUp, Wallet, AlertTriangle, Users, Truck, Boxes,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getDashboard, type GenericDashboard } from "@/lib/api/generic"
import { cn } from "@/lib/utils"
import { ReportExportButtons } from "@/components/reports/report-export-buttons"

export default function DailyBusinessSummaryPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [data, setData] = useState<GenericDashboard | null>(null)
  const [loading, setLoading] = useState(true)

  const load = async () => {
    setLoading(true)
    try {
      setData(await getDashboard())
    } catch (e: any) {
      toast({ title: "Could not load summary", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const t = data?.today
  const w = data?.week
  const a = data?.alerts
  const accts = data?.cashAccounts ?? []

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="mx-auto w-full max-w-7xl">
            <Link href="/generic-reports"
                  className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
              <ArrowLeft className="h-3 w-3 mr-1" /> Back to reports
            </Link>
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <BarChart3 className="h-6 w-6 text-emerald-600" /> Daily Business Summary
            </h1>
            <p className="text-sm text-slate-500 mb-4">
              Today's snapshot and this week's performance at a glance.
            </p>

            <div className="flex gap-2 mb-4 flex-wrap">
              <Button variant="outline" onClick={load} disabled={loading}>
                {loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Refresh
              </Button>
              <ReportExportButtons disabled={loading || !data} pdf={{
                title: "Daily Business Summary",
                columns: [
                  { header: "Metric", key: "metric", width: 150 },
                  { header: "Value", key: "value", width: 100, align: "right" },
                ],
                rows: t ? [
                  { metric: "Today Sales", value: t.todaySales },
                  { metric: "Today Expenses", value: t.todayExpenses },
                  { metric: "Today Gross Profit", value: t.todayGrossProfit },
                  { metric: "Cash at Hand", value: t.cashAtHand },
                  { metric: "Inventory Value", value: t.inventoryValue },
                  { metric: "Customer Debt", value: t.customerDebt },
                  { metric: "Supplier Debt", value: t.supplierDebt },
                  { metric: "Week Sales", value: w?.weekSales ?? 0 },
                  { metric: "Week Expenses", value: w?.weekExpenses ?? 0 },
                  { metric: "Week Gross Profit", value: w?.weekGrossProfit ?? 0 },
                ] : [],
              }} csvFilename="daily-summary" />
            </div>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading…
              </div>
            ) : !data ? (
              <Card><CardContent className="py-8 text-center text-slate-500">No data available.</CardContent></Card>
            ) : (
              <div className="space-y-6">
                {/* ---- Today ---- */}
                <Card>
                  <CardContent className="pt-6">
                    <h2 className="text-lg font-semibold text-slate-900 mb-3 flex items-center gap-2">
                      <DollarSign className="h-5 w-5 text-emerald-600" /> Today
                    </h2>
                    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                      <Tile icon={ShoppingCart} label="Sales" value={fmt(t?.todaySales ?? 0)} accent="emerald"
                            sub={`vs ${fmt(t?.yesterdaySales ?? 0)} yesterday`} />
                      <Tile icon={TrendingDown} label="Expenses" value={fmt(t?.todayExpenses ?? 0)} accent="red" />
                      <Tile icon={TrendingUp} label="Gross Profit" value={fmt(t?.todayGrossProfit ?? 0)}
                            accent={(t?.todayGrossProfit ?? 0) >= 0 ? "emerald" : "red"} />
                      <Tile icon={Wallet} label="Cash at Hand" value={fmt(t?.cashAtHand ?? 0)} accent="blue" />
                    </div>
                    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mt-3">
                      <Tile icon={Boxes} label="Inventory Value" value={fmt(t?.inventoryValue ?? 0)} />
                      <Tile icon={Users} label="Customer Debt" value={fmt(t?.customerDebt ?? 0)} accent="amber" />
                      <Tile icon={Truck} label="Supplier Debt" value={fmt(t?.supplierDebt ?? 0)} accent="orange" />
                      <Tile icon={ShoppingCart} label="Purchases Paid" value={fmt(t?.todayPurchasesPaid ?? 0)} />
                    </div>
                  </CardContent>
                </Card>

                {/* ---- This Week ---- */}
                <Card>
                  <CardContent className="pt-6">
                    <h2 className="text-lg font-semibold text-slate-900 mb-3 flex items-center gap-2">
                      <BarChart3 className="h-5 w-5 text-blue-600" /> This Week (Last 7 Days)
                    </h2>
                    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                      <Tile icon={ShoppingCart} label="Sales" value={fmt(w?.weekSales ?? 0)} accent="emerald" />
                      <Tile icon={TrendingDown} label="Expenses" value={fmt(w?.weekExpenses ?? 0)} accent="red" />
                      <Tile icon={TrendingUp} label="Gross Profit" value={fmt(w?.weekGrossProfit ?? 0)}
                            accent={(w?.weekGrossProfit ?? 0) >= 0 ? "emerald" : "red"} />
                      <Tile icon={ShoppingCart} label="Purchases Paid" value={fmt(w?.weekPurchasesPaid ?? 0)} />
                    </div>
                    {(w?.topSellingItem || w?.topExpenseCategory) && (
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-3">
                        {w?.topSellingItem && (
                          <div className="rounded-md border bg-emerald-50 p-3">
                            <div className="text-xs uppercase tracking-wide text-emerald-600">Top Selling Item</div>
                            <div className="text-base font-bold text-emerald-800 mt-1">{w.topSellingItem}</div>
                            <div className="text-xs text-emerald-600">{w.topSellingQuantity} units sold</div>
                          </div>
                        )}
                        {w?.topExpenseCategory && (
                          <div className="rounded-md border bg-amber-50 p-3">
                            <div className="text-xs uppercase tracking-wide text-amber-600">Top Expense Category</div>
                            <div className="text-base font-bold text-amber-800 mt-1">{w.topExpenseCategory}</div>
                            <div className="text-xs text-amber-600">{fmt(w.topExpenseAmount)}</div>
                          </div>
                        )}
                      </div>
                    )}
                  </CardContent>
                </Card>

                {/* ---- Cash Accounts ---- */}
                {accts.length > 0 && (
                  <Card>
                    <CardContent className="pt-6">
                      <h2 className="text-lg font-semibold text-slate-900 mb-3 flex items-center gap-2">
                        <Wallet className="h-5 w-5 text-slate-600" /> Cash Accounts
                      </h2>
                      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                        {accts.filter((a) => a.isActive).map((a) => (
                          <div key={a.genericCashAccountId} className="rounded-md border bg-white p-3">
                            <div className="text-xs text-slate-500">{a.accountName} ({a.accountType})</div>
                            <div className="text-lg font-bold text-slate-900 mt-1">{fmt(a.currentBalance)}</div>
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                )}

                {/* ---- Alerts ---- */}
                {a && (a.lowStockCount > 0 || a.customersOwingCount > 0 || a.suppliersOwedCount > 0 || a.pendingClosingsCount > 0) && (
                  <Card>
                    <CardContent className="pt-6">
                      <h2 className="text-lg font-semibold text-slate-900 mb-3 flex items-center gap-2">
                        <AlertTriangle className="h-5 w-5 text-amber-600" /> Alerts
                      </h2>
                      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                        {a.lowStockCount > 0 && <Tile icon={AlertTriangle} label="Low Stock Items" value={String(a.lowStockCount)} accent="amber" />}
                        {a.customersOwingCount > 0 && <Tile icon={Users} label="Customers Owing" value={String(a.customersOwingCount)} accent="red" />}
                        {a.suppliersOwedCount > 0 && <Tile icon={Truck} label="Suppliers Owed" value={String(a.suppliersOwedCount)} accent="orange" />}
                        {a.pendingClosingsCount > 0 && <Tile icon={BarChart3} label="Pending Closings" value={String(a.pendingClosingsCount)} accent="blue" />}
                        {a.draftSalesCount > 0 && <Tile icon={ShoppingCart} label="Draft Sales" value={String(a.draftSalesCount)} />}
                        {a.draftExpensesCount > 0 && <Tile icon={DollarSign} label="Draft Expenses" value={String(a.draftExpensesCount)} />}
                      </div>
                    </CardContent>
                  </Card>
                )}
              </div>
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
  const color = {
    emerald: "text-emerald-700",
    red: "text-red-600",
    blue: "text-blue-700",
    amber: "text-amber-700",
    orange: "text-orange-700",
  }[accent ?? ""] ?? "text-slate-900"

  return (
    <div className="rounded-md border bg-slate-50 p-3">
      <div className="flex items-center gap-1 text-xs uppercase tracking-wide text-slate-500">
        <Icon className="h-3.5 w-3.5" /> {label}
      </div>
      <div className={cn("text-lg font-bold mt-1 truncate", color)}>{value}</div>
      {sub && <div className="text-xs text-slate-400 truncate">{sub}</div>}
    </div>
  )
}

"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  TrendingUp, TrendingDown, ShoppingCart, Wallet, Boxes, Users, Truck,
  AlertTriangle, Loader2, ShoppingBag, FileText, Plus,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getDashboard, type GenericDashboard } from "@/lib/api/generic"

function fmtMoney(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

export default function GenericDashboardPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const logout = useLogout()
  const { toast } = useToast()
  const [data, setData] = useState<GenericDashboard | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    // activeFarmType is null on first render before Zustand persist rehydrates.
    // Firing the API call during that window pulls farmId from localStorage —
    // which may belong to a Water/Poultry company — causing a 409 "Farm '...'
    // is not a Generic company" toast right before the redirect below kicks in.
    // Wait until hydration completes.
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    let cancelled = false
    ;(async () => {
      try {
        const d = await getDashboard()
        if (!cancelled) setData(d)
      } catch (e: any) {
        if (!cancelled) {
          toast({ title: "Could not load dashboard", description: e?.message ?? String(e), variant: "destructive" })
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const today = data?.today
  const week  = data?.week
  const cash  = data?.cashAccounts ?? []
  const alerts = data?.alerts
  const yesterdayDelta = today ? today.todaySales - today.yesterdaySales : 0

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-6 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <ShoppingBag className="h-6 w-6 text-emerald-600" />
                {activeFarmName ?? "Business"} dashboard
              </h1>
              <p className="text-sm text-slate-500">Today, this week and what needs your attention.</p>
            </div>
            <div className="flex gap-2 flex-wrap">
              <Button asChild size="sm"><Link href="/generic-sales/new"><Plus className="h-4 w-4 mr-1" />New sale</Link></Button>
              <Button asChild size="sm" variant="outline"><Link href="/generic-daily-closings"><FileText className="h-4 w-4 mr-1" />Daily closing</Link></Button>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !data ? (
            <p className="text-slate-500">No data yet.</p>
          ) : (
            <>
              {/* Headline cards */}
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
                <MetricCard
                  title="Today's sales"
                  value={fmtMoney(today!.todaySales)}
                  hint={
                    <span className="flex items-center gap-1">
                      {yesterdayDelta >= 0 ? <TrendingUp className="h-3 w-3 text-emerald-600" /> : <TrendingDown className="h-3 w-3 text-rose-600" />}
                      vs {fmtMoney(today!.yesterdaySales)} yesterday
                    </span>
                  }
                  accent="emerald"
                />
                <MetricCard title="Today's expenses"   value={fmtMoney(today!.todayExpenses)}      hint={`Purchases paid: ${fmtMoney(today!.todayPurchasesPaid)}`} accent="amber" />
                <MetricCard title="Today's profit"      value={fmtMoney(today!.todayGrossProfit)}   hint="Sales − expenses (gross)" accent="sky" />
                <MetricCard title="Cash at hand"        value={fmtMoney(today!.cashAtHand)}         hint={`${cash.filter((a) => a.isActive).length} active account(s)`} accent="slate" />
              </div>

              <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
                <MetricCard title="Inventory value" value={fmtMoney(today!.inventoryValue)} hint="At cost price" accent="cyan" icon={Boxes} />
                <MetricCard title="Customer debt"   value={fmtMoney(today!.customerDebt)}   hint={`${alerts!.customersOwingCount} customer(s) owing`} accent="rose"  icon={Users}  />
                <MetricCard title="Supplier debt"   value={fmtMoney(today!.supplierDebt)}   hint={`${alerts!.suppliersOwedCount} supplier(s) owed`}  accent="orange" icon={Truck}  />
                <MetricCard
                  title="Low stock"
                  value={`${alerts!.lowStockCount}`}
                  hint="Products at/below minimum"
                  accent={alerts!.lowStockCount > 0 ? "rose" : "emerald"}
                  icon={AlertTriangle}
                />
              </div>

              {/* This week + cash accounts */}
              <div className="grid grid-cols-1 lg:grid-cols-7 gap-4 mb-4">
                <Card className="lg:col-span-4">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-xs uppercase tracking-wide text-slate-500">This week (last 7 days)</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                      <KV label="Sales"           value={fmtMoney(week!.weekSales)} />
                      <KV label="Expenses"        value={fmtMoney(week!.weekExpenses)} />
                      <KV label="Purchases paid"  value={fmtMoney(week!.weekPurchasesPaid)} />
                      <KV label="Gross profit"    value={fmtMoney(week!.weekGrossProfit)} valueClass="text-emerald-700" />
                    </div>
                    <hr className="my-4" />
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div>
                        <div className="text-xs text-slate-500">Top selling</div>
                        <div>
                          {week!.topSellingItem ? (
                            <>
                              <span className="font-medium">{week!.topSellingItem}</span>
                              <span className="text-slate-500"> — {week!.topSellingQuantity} sold</span>
                            </>
                          ) : (
                            <span className="text-slate-500">No sales this week.</span>
                          )}
                        </div>
                      </div>
                      <div>
                        <div className="text-xs text-slate-500">Top expense</div>
                        <div>
                          {week!.topExpenseCategory ? (
                            <>
                              <span className="font-medium">{week!.topExpenseCategory}</span>
                              <span className="text-slate-500"> — {fmtMoney(week!.topExpenseAmount)}</span>
                            </>
                          ) : (
                            <span className="text-slate-500">No expenses this week.</span>
                          )}
                        </div>
                      </div>
                    </div>
                  </CardContent>
                </Card>

                <Card className="lg:col-span-3">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-xs uppercase tracking-wide text-slate-500 flex items-center gap-2">
                      <Wallet className="h-4 w-4" /> Cash accounts
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    {cash.length === 0 ? (
                      <p className="text-slate-500 text-sm">No cash accounts. Run setup.</p>
                    ) : (
                      <ul className="space-y-2">
                        {cash.map((a) => (
                          <li key={a.genericCashAccountId} className="flex items-center justify-between text-sm">
                            <span>
                              {a.accountName} <span className="text-xs text-slate-400">({a.accountType})</span>
                              {!a.isActive && <Badge variant="outline" className="ml-2">Inactive</Badge>}
                            </span>
                            <span className={`font-semibold ${a.currentBalance < 0 ? "text-rose-600" : ""}`}>
                              {fmtMoney(a.currentBalance)}
                            </span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </CardContent>
                </Card>
              </div>

              {/* Quick links */}
              <div className="flex flex-wrap gap-2">
                {alerts!.pendingClosingsCount > 0 && (
                  <Button asChild size="sm" variant="secondary">
                    <Link href="/generic-daily-closings">
                      {alerts!.pendingClosingsCount} pending closing(s) →
                    </Link>
                  </Button>
                )}
                {alerts!.draftSalesCount > 0 && (
                  <Button asChild size="sm" variant="outline">
                    <Link href="/generic-sales?status=Draft">{alerts!.draftSalesCount} draft sale(s) →</Link>
                  </Button>
                )}
                {alerts!.draftExpensesCount > 0 && (
                  <Button asChild size="sm" variant="outline">
                    <Link href="/generic-expenses?status=Draft">{alerts!.draftExpensesCount} draft expense(s) →</Link>
                  </Button>
                )}
                {alerts!.lowStockCount > 0 && (
                  <Button asChild size="sm" variant="outline">
                    <Link href="/generic-products">{alerts!.lowStockCount} low-stock product(s) →</Link>
                  </Button>
                )}
              </div>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

function KV({ label, value, valueClass = "" }: { label: string; value: string; valueClass?: string }) {
  return (
    <div>
      <div className="text-xs text-slate-500">{label}</div>
      <div className={`text-lg font-semibold ${valueClass}`}>{value}</div>
    </div>
  )
}

function MetricCard({
  title, value, hint, accent, icon: Icon = ShoppingCart,
}: {
  title: string
  value: React.ReactNode
  hint?: React.ReactNode
  accent: "emerald" | "amber" | "sky" | "slate" | "cyan" | "rose" | "orange"
  icon?: any
}) {
  // Solid-colour icon box with white icon — matches the farm dashboard
  // (see components/dashboard/metrics-cards.tsx). The Generic + Water + Farm
  // dashboards now share one visual language.
  const iconBg: Record<string, string> = {
    emerald: "bg-emerald-600",
    amber:   "bg-amber-500",
    sky:     "bg-sky-600",
    slate:   "bg-slate-600",
    cyan:    "bg-cyan-600",
    rose:    "bg-rose-600",
    orange:  "bg-orange-500",
  }
  return (
    <Card className="bg-white rounded-xl border border-slate-200 shadow-sm">
      <CardContent className="p-4">
        {/* #4a: icon on the title row so the value gets full card width. */}
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs font-medium text-slate-500 uppercase tracking-wider truncate">{title}</p>
          <div className={`w-8 h-8 rounded-lg ${iconBg[accent]} flex items-center justify-center shrink-0`}>
            <Icon className="w-4 h-4 text-white" />
          </div>
        </div>
        <div className="text-xl sm:text-2xl font-bold text-slate-900 mt-2 leading-tight truncate">{value}</div>
        {hint && <div className="text-xs text-slate-500 mt-1 truncate">{hint}</div>}
      </CardContent>
    </Card>
  )
}

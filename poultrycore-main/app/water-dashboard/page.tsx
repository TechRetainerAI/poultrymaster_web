"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Droplets, Package, Users, ShoppingCart, Wallet, AlertCircle, Loader2,
  Receipt, Banknote, Wrench, Building2, TrendingUp,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getWaterDashboardSummary, listWaterExpenses, listWaterCashAccounts,
  listWaterPayrollRuns, listWaterMaintenanceDueAlerts, getWaterCompanyProfile,
  type WaterDashboardSummary, type WaterExpense, type WaterCashAccount,
  type WaterPayrollRun, type WaterMaintenanceAlert, type WaterCompanyProfile,
} from "@/lib/api/water"
import { WaterIntelligenceSection } from "@/components/dashboard/water-intelligence"
import { useFmt } from "@/lib/currency"

function todayKey() {
  // YYYY-MM-DD in the user's local zone — matches the way ExpenseDate is rendered elsewhere
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

// Sum approved expenses for a single ISO date (matches by leading YYYY-MM-DD)
function sumApprovedOn(expenses: WaterExpense[], dateKey: string): number {
  return expenses
    .filter(e => e.status === "Approved" && e.expenseDate.startsWith(dateKey))
    .reduce((s, e) => s + e.amount, 0)
}

const SEVERITY_BG: Record<string, string> = {
  Overdue: "bg-rose-100 text-rose-700 border-rose-200",
  DueSoon: "bg-amber-100 text-amber-700 border-amber-200",
  Upcoming: "bg-blue-100 text-blue-700 border-blue-200",
}

export default function WaterDashboardPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const logout = useLogout()
  // Subscribes to currency settings so the toggle drives this page too.
  const fmtMoney = useFmt()

  const [summary, setSummary] = useState<WaterDashboardSummary | null>(null)
  const [expenses, setExpenses] = useState<WaterExpense[]>([])
  const [cashAccounts, setCashAccounts] = useState<WaterCashAccount[]>([])
  const [payrollRuns, setPayrollRuns] = useState<WaterPayrollRun[]>([])
  const [alerts, setAlerts] = useState<WaterMaintenanceAlert[]>([])
  const [profile, setProfile] = useState<WaterCompanyProfile | null>(null)

  const [loading, setLoading] = useState(true)

  useEffect(() => {
    // Wait for Zustand persist to rehydrate before firing the API call —
    // otherwise the request goes out with whatever farmId is in localStorage,
    // which may belong to a different company type, triggering a 409 toast
    // right before the redirect below.
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Water") {
      router.replace("/dashboard")
      return
    }
    let cancelled = false
    ;(async () => {
      // Each fetch is independent — capture failures per-call so one broken
      // endpoint doesn't blank out the whole dashboard.
      const [
        summaryRes,
        expensesRes,
        cashRes,
        payrollRes,
        alertsRes,
        profileRes,
      ] = await Promise.allSettled([
        getWaterDashboardSummary(),
        listWaterExpenses(),
        listWaterCashAccounts(),
        listWaterPayrollRuns(),
        listWaterMaintenanceDueAlerts(),
        getWaterCompanyProfile().catch(() => null),
      ])

      if (cancelled) return

      if (summaryRes.status === "fulfilled") setSummary(summaryRes.value)
      if (expensesRes.status === "fulfilled") setExpenses(expensesRes.value)
      if (cashRes.status === "fulfilled") setCashAccounts(cashRes.value)
      if (payrollRes.status === "fulfilled") setPayrollRuns(payrollRes.value)
      if (alertsRes.status === "fulfilled") setAlerts(alertsRes.value)
      if (profileRes.status === "fulfilled") setProfile(profileRes.value)

      // Only surface a top-level error when the core summary fails — secondary
      // data missing just leaves its tile at 0.
      if (summaryRes.status === "rejected") {
        toast({ title: "Could not load dashboard", description: (summaryRes.reason as any)?.message ?? "Failed to load dashboard", variant: "destructive" })
      }
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router])

  // ----- Derived tile values
  const today = todayKey()
  const todayExpenses = sumApprovedOn(expenses, today)
  const monthExpenses = (() => {
    const prefix = today.slice(0, 7) // YYYY-MM
    return expenses.filter(e => e.status === "Approved" && e.expenseDate.startsWith(prefix)).reduce((s, e) => s + e.amount, 0)
  })()
  const cashAtHand = cashAccounts.filter(a => a.isActive).reduce((s, a) => s + a.currentBalance, 0)
  const pendingPayroll = payrollRuns.filter(r => r.status === "Draft" || r.status === "Approved")
  const unpaidPayrollNet = pendingPayroll.reduce((s, r) => s + r.totalNetPay, 0)
  const overdueAlerts = alerts.filter(a => a.severity === "Overdue")
  const dueSoonAlerts = alerts.filter(a => a.severity === "DueSoon")
  const todayProfit = (summary?.salesToday ?? 0) - todayExpenses

  // First-time visitor (no profile row) → nudge to setup. The endpoint already
  // returns 404 in that case and we catch it above, so profile === null here.
  const needsSetup = !loading && profile === null

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-6 flex items-center justify-between gap-2 flex-wrap">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Droplets className="h-6 w-6 text-sky-600" />
                {profile?.brandName ?? activeFarmName ?? "Water company"} dashboard
              </h1>
              <p className="text-sm text-slate-500">Production, sales, money, people, maintenance — at a glance.</p>
            </div>
            {needsSetup && (
              <Link href="/water-company-setup" className="text-sm font-medium text-sky-700 underline">
                Set up your company →
              </Link>
            )}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <div className="space-y-6">
              {/* Maintenance alert banner — only when something is overdue or due soon. */}
              {(overdueAlerts.length > 0 || dueSoonAlerts.length > 0) && (
                <Card className={overdueAlerts.length > 0 ? "border-rose-200 bg-rose-50" : "border-amber-200 bg-amber-50"}>
                  <CardContent className="p-3 md:p-4">
                    <div className="flex items-center justify-between gap-2 mb-2">
                      <div className="font-medium text-slate-900 flex items-center gap-2">
                        <AlertCircle className={`h-4 w-4 ${overdueAlerts.length > 0 ? "text-rose-600" : "text-amber-600"}`} />
                        Maintenance attention needed
                      </div>
                      <Link href="/water-maintenance" className="text-xs font-medium underline text-slate-700">View all →</Link>
                    </div>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
                      {[...overdueAlerts, ...dueSoonAlerts].slice(0, 6).map((a, i) => (
                        <div key={`${a.assetType}-${a.assetId}-${i}`} className={`rounded border bg-white p-2 text-sm flex items-center justify-between ${SEVERITY_BG[a.severity] ?? ""}`}>
                          <div>
                            <div className="font-medium text-slate-900 truncate">{a.assetLabel}</div>
                            <div className="text-xs text-slate-500">
                              {a.assetType} · Due {a.nextDueDate.split("T")[0]} · {a.daysUntilDue >= 0 ? `in ${a.daysUntilDue}d` : `${Math.abs(a.daysUntilDue)}d ago`}
                            </div>
                          </div>
                          <Badge className={SEVERITY_BG[a.severity] ?? ""}>{a.severity}</Badge>
                        </div>
                      ))}
                    </div>
                  </CardContent>
                </Card>
              )}

              {/* Money row — the daily-question tiles from the Water spec §15 */}
              <section>
                <div className="mb-2 text-xs uppercase tracking-wide text-slate-500 font-medium">Money today</div>
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                  <StatLink href="/water-sales" icon={ShoppingCart} title="Today's sales" value={fmtMoney(summary?.salesToday ?? 0)} accent="emerald" />
                  <StatLink href="/water-expenses" icon={Receipt} title="Today's expenses" value={fmtMoney(todayExpenses)} accent="orange" />
                  <StatLink href="/water-sales" icon={TrendingUp} title="Today's profit (rough)" value={fmtMoney(todayProfit)} accent={todayProfit >= 0 ? "emerald" : "rose"} subtitle="Sales − approved expenses" />
                  <StatLink href="/water-cash-accounts" icon={Wallet} title="Cash at hand" value={fmtMoney(cashAtHand)} accent="sky" subtitle={`${cashAccounts.filter(a => a.isActive).length} active accounts`} />
                </div>
              </section>

              {/* Month / receivables row */}
              <section>
                <div className="mb-2 text-xs uppercase tracking-wide text-slate-500 font-medium">This month</div>
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                  <StatLink href="/water-sales" icon={ShoppingCart} title="Sales this month" value={fmtMoney(summary?.salesThisMonth ?? 0)} accent="amber" />
                  <StatLink href="/water-expenses" icon={Receipt} title="Expenses this month" value={fmtMoney(monthExpenses)} accent="orange" />
                  <StatLink href="/water-customers" icon={Wallet} title="Outstanding receivables" value={fmtMoney(summary?.outstandingReceivables ?? 0)} accent="rose" />
                  <StatLink href="/water-payroll" icon={Banknote} title="Pending payroll" value={fmtMoney(unpaidPayrollNet)} accent={pendingPayroll.length > 0 ? "amber" : "sky"} subtitle={`${pendingPayroll.length} run${pendingPayroll.length === 1 ? "" : "s"} not paid`} />
                </div>
              </section>

              {/* Operations row — what existed before, slightly refactored */}
              <section>
                <div className="mb-2 text-xs uppercase tracking-wide text-slate-500 font-medium">Operations</div>
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                  <StatLink href="/water-products" icon={Package}   title="Active products"  value={summary?.activeProducts ?? 0} accent="sky" />
                  <StatLink href="/water-customers" icon={Users}    title="Customers"        value={summary?.totalCustomers ?? 0} accent="emerald" />
                  <StatLink href="/water-stock"    icon={Droplets} title="Stock on hand"    value={summary?.totalStockOnHand ?? 0} suffix="units" accent="cyan" />
                  <StatLink href="/water-maintenance" icon={Wrench} title="Maintenance alerts" value={alerts.length} accent={overdueAlerts.length > 0 ? "rose" : dueSoonAlerts.length > 0 ? "amber" : "sky"} subtitle={`${overdueAlerts.length} overdue · ${dueSoonAlerts.length} due soon`} />
                </div>
              </section>

              {/* Owner intelligence — spec §17, gap #7. Period defaults to this month. */}
              <WaterIntelligenceSection />

              {/* Profile shortcut — small text card so the user can find setup without hunting */}
              {profile && (
                <Card>
                  <CardContent className="p-4 flex items-center justify-between gap-2 flex-wrap">
                    <div className="flex items-center gap-3">
                      <div className="rounded-md p-2 bg-sky-50 text-sky-600"><Building2 className="h-4 w-4" /></div>
                      <div>
                        <div className="text-sm font-medium text-slate-900">{profile.brandName ?? "Water Company"}</div>
                        <div className="text-xs text-slate-500">
                          {profile.businessType} · Source: {profile.waterSourceType} · {profile.defaultBagSachetCount} sachets/bag · {profile.defaultCurrency}
                        </div>
                      </div>
                    </div>
                    <Link href="/water-company-setup" className="text-xs font-medium text-sky-700 underline">Edit setup →</Link>
                  </CardContent>
                </Card>
              )}
            </div>
          )}
        </main>
      </div>
    </div>
  )
}

type Accent = "sky" | "emerald" | "cyan" | "orange" | "amber" | "rose"

/**
 * Stat tile in the farm-dashboard pattern (see components/dashboard/metrics-cards.tsx):
 * white card · uppercase tracked title · bold value · solid-colour rounded
 * icon box with a white icon. Same `accent` palette keys we had before;
 * the icon box bg is now solid (bg-{color}-600) so the company-dashboards
 * read identically to the farm dashboard.
 */
function StatLink({
  href, icon: Icon, title, value, suffix, accent, subtitle,
}: {
  href: string
  icon: any
  title: string
  value: string | number
  suffix?: string
  accent: Accent
  subtitle?: string
}) {
  const iconBg: Record<Accent, string> = {
    sky:     "bg-sky-600",
    emerald: "bg-emerald-600",
    cyan:    "bg-cyan-600",
    orange:  "bg-orange-500",
    amber:   "bg-amber-500",
    rose:    "bg-rose-600",
  }
  return (
    <Link href={href} className="block focus:outline-none">
      <Card className="bg-white rounded-xl border border-slate-200 shadow-sm transition-shadow hover:shadow-md focus-visible:ring-2 focus-visible:ring-sky-300">
        <CardContent className="p-4">
          {/* #4a: icon sits on the TITLE row (top-right) so the value below gets
              the full card width — no longer squeezed beside the icon. */}
          <div className="flex items-center justify-between gap-2">
            <p className="text-xs font-medium text-slate-500 uppercase tracking-wider truncate">{title}</p>
            <div className={`w-8 h-8 rounded-lg ${iconBg[accent]} flex items-center justify-center shrink-0`}>
              <Icon className="w-4 h-4 text-white" />
            </div>
          </div>
          <p className="text-xl sm:text-2xl font-bold text-slate-900 mt-2 leading-tight truncate">
            {value}
            {suffix ? <span className="text-sm font-medium text-slate-500 ml-1">{suffix}</span> : null}
          </p>
          {subtitle ? <p className="text-xs text-slate-500 mt-1 truncate">{subtitle}</p> : null}
        </CardContent>
      </Card>
    </Link>
  )
}

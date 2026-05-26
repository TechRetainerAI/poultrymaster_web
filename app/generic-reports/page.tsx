"use client"

import Link from "next/link"
import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { BarChart3, DollarSign, ShoppingCart, Users, Boxes, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"

const REPORTS = [
  { href: "/generic-reports/period-pnl",          title: "Period P&L",            description: "Income, expenses, cost-of-goods-sold and profit for any date range.", icon: DollarSign, accent: "emerald" as const },
  { href: "/generic-reports/sales-by-product",    title: "Sales by product",      description: "Which products generated the most revenue this period.",               icon: ShoppingCart, accent: "sky" as const },
  { href: "/generic-reports/sales-by-customer",   title: "Sales by customer",     description: "Top customers by revenue, including outstanding balances.",            icon: Users, accent: "cyan" as const },
  { href: "/generic-reports/expenses-by-category",title: "Expenses by category",  description: "Where your money went, grouped by expense category.",                  icon: BarChart3, accent: "amber" as const },
  { href: "/generic-reports/inventory-value",     title: "Inventory value",       description: "Stock value at cost and at retail, with a per-category breakdown.",    icon: Boxes, accent: "orange" as const },
  { href: "/generic-reports/cash-summary",        title: "Cash summary",          description: "Period cash-in / cash-out and current balance per account.",           icon: Wallet, accent: "slate" as const },
]

const accents: Record<string, string> = {
  emerald: "text-emerald-600 bg-emerald-50",
  sky:     "text-sky-600 bg-sky-50",
  cyan:    "text-cyan-600 bg-cyan-50",
  amber:   "text-amber-600 bg-amber-50",
  orange:  "text-orange-600 bg-orange-50",
  slate:   "text-slate-600 bg-slate-100",
}

export default function GenericReportsHubPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <BarChart3 className="h-6 w-6 text-slate-700" /> Reports
            </h1>
            <p className="text-sm text-slate-500">Aggregations over the immutable sales / purchases / expenses / cash / ledger tables.</p>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {REPORTS.map((r) => (
              <Link key={r.href} href={r.href}>
                <Card className="hover:shadow-md transition-shadow cursor-pointer h-full">
                  <CardHeader className="flex flex-row items-start gap-3">
                    <div className={`rounded-md p-2 ${accents[r.accent]}`}><r.icon className="h-5 w-5" /></div>
                    <div>
                      <CardTitle className="text-base">{r.title}</CardTitle>
                      <CardDescription className="text-xs mt-1">{r.description}</CardDescription>
                    </div>
                  </CardHeader>
                  <CardContent />
                </Card>
              </Link>
            ))}
          </div>
        </main>
      </div>
    </div>
  )
}

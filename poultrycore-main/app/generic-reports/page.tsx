"use client"

// The reports hub.
//
// Twelve reports for a subscription business, six for everyone else. The
// subscription set is HIDDEN rather than shown-and-empty for a shop: a report
// that can only ever say "no data" is noise on the page that is meant to help
// you find things.
//
// Several cards point at pages that already existed -- cash summary, P&L,
// customer and supplier balances. They are reports, they answer the question
// the spec asks, and pointing at them beats building a second page that reads
// the same rows.

import Link from "next/link"
import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import {
  BarChart3, Boxes, CreditCard, DollarSign, Repeat, Scale, ShoppingCart,
  TrendingUp, Truck, Users, Users2, Wallet, AlertTriangle, Cloud,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useGenericModules } from "@/hooks/use-generic-modules"
import type { TemplateLabels } from "@/lib/generic/template-labels"

type Accent = "emerald" | "sky" | "cyan" | "amber" | "orange" | "slate" | "rose" | "violet"

interface ReportCard {
  href: string
  title: string
  description: string
  icon: any
  accent: Accent
}

/** The reports every Generic company gets. */
function coreReports(l: TemplateLabels): ReportCard[] {
  return [
    { href: "/generic-reports/period-pnl", title: "Profit & loss", description: "Income, expenses, cost-of-goods-sold and profit for any date range.", icon: DollarSign, accent: "emerald" },
    { href: "/generic-reports/cash-summary", title: "Cash flow", description: "Money in, money out and the closing balance of every cash account.", icon: Wallet, accent: "slate" },
    { href: "/generic-reports/expenses-by-category", title: "Expense report", description: "Where the money went — by category, by supplier, and month by month.", icon: BarChart3, accent: "amber" },
    { href: "/generic-customer-balances", title: `${l.customerBalance} report`, description: `Who owes what, how old it is, and every open ${l.invoice.toLowerCase()} behind it.`, icon: Scale, accent: "cyan" },
    { href: "/generic-supplier-balances", title: "Supplier balances", description: "What is owed to suppliers, aged, with the bills behind each balance.", icon: Truck, accent: "orange" },
    { href: "/generic-reports/staff-cost", title: "Staff & contractor cost", description: "Everything paid to people — staff payments and payroll — by person, month and role.", icon: Users2, accent: "violet" },
  ]
}

/** Only for a business that bills on a schedule. */
function subscriptionReports(l: TemplateLabels): ReportCard[] {
  return [
    { href: "/generic-reports/subscription-revenue", title: `${l.subscription} revenue`, description: `What was billed and collected, split by month, by ${l.plan.toLowerCase()} and by ${l.customer.toLowerCase()}.`, icon: Repeat, accent: "emerald" },
    { href: "/generic-reports/mrr", title: "Monthly recurring revenue", description: "Active, new and lost MRR month by month.", icon: TrendingUp, accent: "sky" },
    { href: "/generic-reports/customer-payments", title: `${l.customer} payments`, description: "Every payment received, how it was paid, and what it settled.", icon: CreditCard, accent: "cyan" },
    { href: "/generic-reports/unpaid-customers", title: `Unpaid ${l.customerPlural.toLowerCase()}`, description: `Who is late, by how much, for how long, and how to reach them.`, icon: AlertTriangle, accent: "rose" },
    { href: "/generic-reports/hosting-cost", title: "Hosting & cloud cost", description: "What infrastructure costs each month, and what share of revenue it eats.", icon: Cloud, accent: "violet" },
    { href: "/generic-reports/break-even", title: "Break-even", description: `How many paying ${l.customerPlural.toLowerCase()} it takes to cover a month.`, icon: Scale, accent: "amber" },
  ]
}

/** Stock and product reports: only meaningful when the company sells things. */
function retailReports(): ReportCard[] {
  return [
    { href: "/generic-reports/sales-by-product", title: "Sales by product", description: "Which products generated the most revenue this period.", icon: ShoppingCart, accent: "sky" },
    { href: "/generic-reports/sales-by-customer", title: "Sales by customer", description: "Top customers by revenue, including outstanding balances.", icon: Users, accent: "cyan" },
    { href: "/generic-reports/inventory-value", title: "Inventory value", description: "Stock value at cost and at retail, with a per-category breakdown.", icon: Boxes, accent: "orange" },
  ]
}

const accents: Record<Accent, string> = {
  emerald: "text-emerald-600 bg-emerald-50",
  sky: "text-sky-600 bg-sky-50",
  cyan: "text-cyan-600 bg-cyan-50",
  amber: "text-amber-600 bg-amber-50",
  orange: "text-orange-600 bg-orange-50",
  slate: "text-slate-600 bg-slate-100",
  rose: "text-rose-600 bg-rose-50",
  violet: "text-violet-600 bg-violet-50",
}

export default function GenericReportsHubPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { labels, isSubscriptionBusiness, settings } = useGenericModules()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") router.replace("/dashboard")
  }, [activeFarmType, router])

  // Products off means the stock reports have nothing to report. Default to
  // showing them: a company with no settings row keeps everything it has today.
  const showRetail = settings ? settings.enableProducts : true

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
            <p className="text-sm text-slate-500">
              Aggregations over the immutable sales / purchases / expenses / cash / ledger tables.
            </p>
          </div>

          {isSubscriptionBusiness && (
            <Section title={`${labels.subscription} reports`} cards={subscriptionReports(labels)} />
          )}
          <Section title="Money" cards={coreReports(labels)} />
          {showRetail && <Section title="Products & stock" cards={retailReports()} />}
        </main>
      </div>
    </div>
  )
}

function Section({ title, cards }: { title: string; cards: ReportCard[] }) {
  return (
    <section className="mb-6">
      <h2 className="text-xs uppercase tracking-wide text-slate-500 mb-2">{title}</h2>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {cards.map((r) => (
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
    </section>
  )
}

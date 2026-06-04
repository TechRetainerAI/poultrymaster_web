"use client"

/**
 * Catch-all for /water-reports/<slug> when we haven't shipped that specific
 * report yet (Prompt 2 §16.x). The catalog on /water-reports labels these
 * cards with a "Soon" badge; landing here keeps the route shape valid and
 * tells the user exactly what to expect.
 *
 * As individual reports are implemented, they should live in their own
 * subdirectory (e.g. /water-reports/sales-report/page.tsx) which Next.js
 * will resolve before this catch-all.
 */

import Link from "next/link"
import { useParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft, BarChart3 } from "lucide-react"
import { useLogout } from "@/hooks/use-logout"

const TITLES: Record<string, string> = {
  "profit-loss":            "Profit & Loss",
  "cash-flow":              "Cash Flow",
  "expense-report":         "Expense Report",
  "closing-report":         "Closing Report",
  "sales-report":           "Sales Report",
  "payments-received":      "Payments Received",
  "customer-balances":      "Customer Balances",
  "customer-history":       "Customer Sales History",
  "production-report":      "Production Report",
  "raw-material-usage":     "Raw Material Usage",
  "raw-material-purchase":  "Raw Material Purchases",
  "inventory-report":       "Inventory / Stock",
  "stock-movement":         "Stock Movement",
  "product-performance":    "Product Performance",
  "delivery-run-report":    "Delivery Run Report",
  "driver-accountability":  "Driver Accountability",
  "route-performance":      "Route Performance",
  "vehicle-usage":          "Vehicle Usage",
  "loss-report":            "Loss Report",
}

export default function ReportComingSoonPage() {
  const params = useParams<{ slug: string }>()
  const slug = params?.slug ?? ""
  const title = TITLES[slug] ?? slug
  const logout = useLogout()

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 min-w-0">
          <div className="mb-4">
            <Button asChild variant="outline" size="sm">
              <Link href="/water-reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
            </Button>
          </div>

          <Card>
            <CardContent className="p-6 space-y-3">
              <div className="flex items-center gap-3">
                <div className="rounded-lg bg-sky-100 p-2"><BarChart3 className="h-6 w-6 text-sky-700" /></div>
                <div>
                  <h1 className="text-xl font-semibold text-slate-900">{title}</h1>
                  <Badge variant="outline" className="text-[10px] uppercase mt-1">Coming soon</Badge>
                </div>
              </div>
              <p className="text-sm text-slate-600 max-w-prose">
                This report is in the catalog (Prompt 2 §16) but hasn't been built out yet. The Reports
                index lists it as <span className="font-medium">"Soon"</span>. Once we ship it, the page at
                <span className="font-mono"> /water-reports/{slug}</span> will replace this stub automatically.
              </p>
              <p className="text-sm text-slate-600 max-w-prose">
                In the meantime, the <Link href="/water-reports/daily-summary" className="text-indigo-600 hover:underline">Daily Business Summary</Link> and
                <Link href="/water-reports/operational" className="text-indigo-600 hover:underline"> Operational dashboard</Link> are available with PDF export.
              </p>
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}

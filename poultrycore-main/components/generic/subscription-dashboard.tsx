"use client"

// The dashboard a subscription / membership / retainer business opens.
//
// Deliberately NOT the retail dashboard with different numbers. A gym owner
// does not care what their top selling product was; they care how many members
// are paying, who is late, what leaves the account every month and how many
// members it takes to cover it. Those are different questions, so this is a
// different page -- exactly what section 7 of the spec asks for.
//
// Every label that names a person or a plan comes from templateLabels, so the
// same component reads "Members" for a gym, "Students" for a school and
// "Clients" for a cleaning firm without a second copy of the file.
//
// One request. The nine panels below are nine result sets of one command
// (spgenericsubdashboard_rs1..rs8 plus the existing cash summary), so opening
// the page is one round trip, not nine.

import { useEffect, useState } from "react"
import Link from "next/link"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  AlertTriangle, ArrowRight, BarChart3, CalendarClock, CreditCard, DollarSign,
  Loader2, Receipt, Repeat, Scale, TrendingDown, TrendingUp, Users, Wallet,
} from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { getSubscriptionDashboard, type GenericSubDashboard } from "@/lib/api/generic-reports"

function fmtMoney(n: number) {
  return new Intl.NumberFormat(undefined, {
    style: "currency", currency: "GHS", maximumFractionDigits: 2,
  }).format(n)
}

function fmtDate(d?: string | null) {
  if (!d) return "—"
  return new Date(d).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })
}

/** "in 4 days" / "5 days late" / "today" — a count of days is not a sentence. */
function whenText(days: number) {
  if (days === 0) return "today"
  return days > 0 ? `in ${days} day${days === 1 ? "" : "s"}` : `${-days} day${days === -1 ? "" : "s"} late`
}

export function GenericSubscriptionDashboard({ companyName }: { companyName?: string | null }) {
  const { toast } = useToast()
  // showCard defaults TRUE while the settings load, so a card a company
  // already sees never flickers out on a slow request.
  const { labels, showCard } = useGenericModules()

  const [data, setData] = useState<GenericSubDashboard | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const d = await getSubscriptionDashboard()
        if (!cancelled) setData(d)
      } catch (e: any) {
        if (!cancelled) {
          toast({
            title: "Could not load dashboard",
            description: e?.message ?? String(e),
            variant: "destructive",
          })
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
  }, [toast])

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-slate-500">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading…
      </div>
    )
  }
  if (!data) return <p className="text-slate-500">No data yet.</p>

  const k = data.kpis
  const a = data.alerts
  const monthLabel = new Date(k.monthStart).toLocaleDateString(undefined, { month: "long", year: "numeric" })

  return (
    <>
      <div className="mb-6 flex items-end justify-between flex-wrap gap-2">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
            <Repeat className="h-6 w-6 text-emerald-600" />
            {companyName ?? "Business"} dashboard
          </h1>
          <p className="text-sm text-slate-500">{monthLabel} — what recurs, what came in, what needs doing.</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Button asChild size="sm"><Link href="/generic-billing-runs"><Receipt className="h-4 w-4 mr-1" />Run billing</Link></Button>
          <Button asChild size="sm" variant="outline"><Link href="/generic-reports"><BarChart3 className="h-4 w-4 mr-1" />Reports</Link></Button>
        </div>
      </div>

      {/* What recurs */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        {showCard("showMrr") && (
          <Metric
            title="Monthly recurring revenue"
            value={fmtMoney(k.monthlyRecurringRevenue)}
            hint={`${k.activeSubscriptions} active ${k.activeSubscriptions === 1 ? labels.subscription.toLowerCase() : labels.subscriptionPlural.toLowerCase()}`}
            accent="emerald"
            icon={Repeat}
          />
        )}
        <Metric
          title="Collected this month"
          value={fmtMoney(k.paymentsCollected)}
          hint={`Invoiced ${fmtMoney(k.invoicedThisMonth)}`}
          accent="sky"
          icon={CreditCard}
        />
        {/* The burn rate rides on the spend card rather than taking one of its
            own, so turning it off leaves no hole in the row. */}
        <Metric
          title="Spent this month"
          value={fmtMoney(k.expensesPaid)}
          hint={showCard("showBurnRate") ? `Burn rate ${fmtMoney(k.monthlyBurnRate)} / month` : undefined}
          accent="amber"
          icon={DollarSign}
        />
        <Metric
          title="Net cash flow"
          value={fmtMoney(k.netCashFlow)}
          hint={
            <span className="flex items-center gap-1">
              {k.netCashFlow >= 0
                ? <TrendingUp className="h-3 w-3 text-emerald-600" />
                : <TrendingDown className="h-3 w-3 text-rose-600" />}
              money in less money out
            </span>
          }
          accent={k.netCashFlow >= 0 ? "emerald" : "rose"}
          icon={Wallet}
        />
      </div>

      {/* Row two is entirely optional: a company that turns all four off gets
          no empty grid, because the row itself disappears with them. */}
      {(showCard("showCalculatedCashAtHand") || showCard("showCustomerBalances")
        || showCard("showSupplierBalances") || showCard("showBreakEvenCustomers")) && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
          {showCard("showCalculatedCashAtHand") && (
            <Metric title="Cash at hand" value={fmtMoney(k.cashAtHand)} hint={`${data.cashAccounts.filter((c) => c.isActive).length} active account(s)`} accent="slate" icon={Wallet} />
          )}
          {showCard("showCustomerBalances") && (
            <Metric title={`${labels.customerBalance}`} value={fmtMoney(k.customerBalances)} hint={`${k.overdueCustomers} overdue — ${fmtMoney(k.overdueAmount)}`} accent={k.overdueAmount > 0 ? "rose" : "cyan"} icon={Scale} />
          )}
          {showCard("showSupplierBalances") && (
            <Metric title="Supplier balances" value={fmtMoney(k.supplierBalances)} hint="Unpaid bills and purchases" accent="orange" icon={Scale} />
          )}
          {showCard("showBreakEvenCustomers") && (
            <Metric
              title={`Break-even ${labels.customerPlural.toLowerCase()}`}
              value={`${k.breakEvenCustomers}`}
              hint={
                k.breakEvenCustomers === 0
                  ? "Not enough data yet"
                  : `${k.activeCustomers} paying — ${k.activeCustomers >= k.breakEvenCustomers ? "covered" : `${k.breakEvenCustomers - k.activeCustomers} short`}`
              }
              accent={k.activeCustomers >= k.breakEvenCustomers && k.breakEvenCustomers > 0 ? "emerald" : "rose"}
              icon={Users}
            />
          )}
        </div>
      )}

      {/* Alerts. Everything here is something a person has to DO. */}
      {(a.dueToBillCount > 0 || a.draftInvoiceCount > 0 || a.recurringDueCount > 0
        || a.overdueCustomerCount > 0 || a.endingSoonCount > 0 || a.negativeAccountCount > 0) && (
        <div className="flex flex-wrap gap-2 mb-4">
          {a.dueToBillCount > 0 && (
            <Button asChild size="sm" variant="secondary">
              <Link href="/generic-billing-runs">
                {a.dueToBillCount} {labels.subscriptionPlural.toLowerCase()} due to bill — {fmtMoney(a.dueToBillAmount)} <ArrowRight className="h-3 w-3 ml-1" />
              </Link>
            </Button>
          )}
          {a.draftInvoiceCount > 0 && (
            <Button asChild size="sm" variant="outline">
              <Link href="/generic-invoices?status=Draft">
                {a.draftInvoiceCount} draft {labels.invoicePlural.toLowerCase()} to approve — {fmtMoney(a.draftInvoiceAmount)}
              </Link>
            </Button>
          )}
          {a.overdueCustomerCount > 0 && (
            <Button asChild size="sm" variant="outline">
              <Link href="/generic-customer-balances">
                {a.overdueCustomerCount} overdue {labels.customerPlural.toLowerCase()} — {fmtMoney(a.overdueCustomerAmount)}
              </Link>
            </Button>
          )}
          {a.recurringDueCount > 0 && (
            <Button asChild size="sm" variant="outline">
              <Link href="/generic-recurring-expenses">
                {a.recurringDueCount} recurring expense(s) due — {fmtMoney(a.recurringDueAmount)}
              </Link>
            </Button>
          )}
          {a.endingSoonCount > 0 && (
            <Button asChild size="sm" variant="outline">
              <Link href="/generic-subscriptions">{a.endingSoonCount} ending within 30 days</Link>
            </Button>
          )}
          {a.negativeAccountCount > 0 && (
            <Button asChild size="sm" variant="destructive">
              <Link href="/generic-cash">{a.negativeAccountCount} account(s) overdrawn</Link>
            </Button>
          )}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        {/* Upcoming renewals */}
        <Panel title={`Upcoming ${labels.subscriptionPlural.toLowerCase()} to bill`} icon={CalendarClock} href="/generic-subscriptions">
          {data.renewals.length === 0 ? (
            <Empty>Nothing falls due in the next 30 days.</Empty>
          ) : (
            <ul className="divide-y">
              {data.renewals.slice(0, 8).map((r) => (
                <li key={r.genericSubscriptionId} className="py-2 flex items-center justify-between gap-2 text-sm">
                  <div className="min-w-0">
                    <div className="font-medium truncate">{r.customerName}</div>
                    <div className="text-xs text-slate-500 truncate">
                      {r.serviceName ?? "—"} · {fmtDate(r.nextBillingDate)}
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    <div className="font-semibold">{fmtMoney(r.totalBillingAmount)}</div>
                    <div className={`text-xs ${r.daysUntil < 0 ? "text-rose-600" : "text-slate-500"}`}>
                      {whenText(r.daysUntil)}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Panel>

        {/* Who is late */}
        <Panel title={`Overdue ${labels.customerPlural.toLowerCase()}`} icon={AlertTriangle} href="/generic-customer-balances">
          {data.overdueCustomers.length === 0 ? (
            <Empty>Nobody is late. </Empty>
          ) : (
            <ul className="divide-y">
              {data.overdueCustomers.map((c) => (
                <li key={c.partyId} className="py-2 flex items-center justify-between gap-2 text-sm">
                  <div className="min-w-0">
                    <div className="font-medium truncate">{c.partyName}</div>
                    <div className="text-xs text-slate-500 truncate">
                      {c.openDocumentCount} open · oldest {fmtDate(c.oldestDocumentDate)}
                      {c.contactPhone ? ` · ${c.contactPhone}` : ""}
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    <div className="font-semibold text-rose-600">{fmtMoney(c.overdueAmount)}</div>
                    <div className="text-xs text-slate-500">of {fmtMoney(c.totalBalance)}</div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Panel>

        {/* Where the money went */}
        <Panel title="Expenses this month" icon={BarChart3} href="/generic-reports/expenses-by-category">
          {data.expenseBreakdown.length === 0 ? (
            <Empty>No expenses recorded this month.</Empty>
          ) : (
            <ul className="space-y-2">
              {data.expenseBreakdown.slice(0, 6).map((e) => (
                <li key={e.genericExpenseCategoryId}>
                  <div className="flex items-center justify-between text-sm">
                    <span className="truncate">{e.categoryName}</span>
                    <span className="font-medium shrink-0">{fmtMoney(e.totalAmount)}</span>
                  </div>
                  <div className="h-1.5 bg-slate-100 rounded mt-1">
                    <div className="h-1.5 bg-amber-500 rounded" style={{ width: `${Math.min(e.pctOfTotal, 100)}%` }} />
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Panel>

        {/* What leaves next */}
        <Panel title="Recurring expenses due" icon={Repeat} href="/generic-recurring-expenses">
          {data.recurringDue.length === 0 ? (
            <Empty>Nothing due in the next 30 days.</Empty>
          ) : (
            <ul className="divide-y">
              {data.recurringDue.slice(0, 8).map((r) => (
                <li key={r.genericRecurringExpenseId} className="py-2 flex items-center justify-between gap-2 text-sm">
                  <div className="min-w-0">
                    <div className="font-medium truncate">{r.expenseName}</div>
                    <div className="text-xs text-slate-500 truncate">
                      {r.supplierName ?? r.categoryName ?? r.frequency} · {fmtDate(r.nextDueDate)}
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    <div className="font-semibold">{fmtMoney(r.amount)}</div>
                    <div className={`text-xs ${r.daysUntil < 0 ? "text-rose-600" : "text-slate-500"}`}>
                      {whenText(r.daysUntil)}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Panel>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-4">
        {/* Cash by account */}
        <Panel title="Cash by account" icon={Wallet} href="/generic-cash">
          {data.cashAccounts.length === 0 ? (
            <Empty>No cash accounts. Run setup.</Empty>
          ) : (
            <ul className="space-y-2">
              {data.cashAccounts.map((c) => (
                <li key={c.genericCashAccountId} className="flex items-center justify-between text-sm">
                  <span className="truncate">
                    {c.accountName} <span className="text-xs text-slate-400">({c.accountType})</span>
                    {!c.isActive && <Badge variant="outline" className="ml-2">Inactive</Badge>}
                  </span>
                  <span className={`font-semibold shrink-0 ${c.currentBalance < 0 ? "text-rose-600" : ""}`}>
                    {fmtMoney(c.currentBalance)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Panel>

        {/* Team cost */}
        <Panel title="Paid to people this month" icon={Users} href="/generic-reports/staff-cost">
          {data.staffSummary.totalPaid === 0 ? (
            <Empty>Nobody has been paid this month.</Empty>
          ) : (
            <div className="space-y-2 text-sm">
              <Row label="Total" value={fmtMoney(data.staffSummary.totalPaid)} strong />
              <Row label="Staff payments" value={fmtMoney(data.staffSummary.staffPaymentTotal)} />
              <Row label="Payroll" value={fmtMoney(data.staffSummary.payrollTotal)} />
              <Row label="People paid" value={String(data.staffSummary.peoplePaid)} />
              {data.staffSummary.topPersonName && (
                <Row label="Largest" value={`${data.staffSummary.topPersonName} — ${fmtMoney(data.staffSummary.topPersonAmount)}`} />
              )}
            </div>
          )}
        </Panel>

        {/* This month at a glance */}
        <Panel title={`${labels.subscriptionPlural} this month`} icon={Repeat} href="/generic-reports/subscription-revenue">
          <div className="space-y-2 text-sm">
            <Row label="Active" value={String(k.activeSubscriptions)} strong />
            <Row label="New" value={`+${k.newSubscriptions}`} />
            <Row label="Cancelled" value={`-${k.cancelledSubscriptions}`} />
            <Row label={`Paying ${labels.customerPlural.toLowerCase()}`} value={String(k.activeCustomers)} />
            <Row
              label="Average each"
              value={fmtMoney(k.activeCustomers > 0 ? k.monthlyRecurringRevenue / k.activeCustomers : 0)}
            />
          </div>
        </Panel>
      </div>

      {/* Recent activity */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-xs uppercase tracking-wide text-slate-500">Recent activity</CardTitle>
        </CardHeader>
        <CardContent>
          {data.recentActivity.length === 0 ? (
            <Empty>Nothing recorded yet.</Empty>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs uppercase tracking-wide text-slate-500">
                    <th className="py-1 pr-3">When</th>
                    <th className="py-1 pr-3">What</th>
                    <th className="py-1 pr-3">Who</th>
                    <th className="py-1 pr-3">Reference</th>
                    <th className="py-1 pr-3 text-right">Amount</th>
                    <th className="py-1">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {data.recentActivity.map((r, i) => (
                    <tr key={`${r.activityType}-${r.reference}-${i}`}>
                      <td className="py-1.5 pr-3 whitespace-nowrap text-slate-500">{fmtDate(r.activityAt)}</td>
                      <td className="py-1.5 pr-3 whitespace-nowrap">{r.activityType}</td>
                      <td className="py-1.5 pr-3 truncate max-w-[14rem]">{r.party ?? "—"}</td>
                      <td className="py-1.5 pr-3 text-slate-500">{r.reference ?? "—"}</td>
                      <td className={`py-1.5 pr-3 text-right font-medium ${r.amount < 0 ? "text-rose-600" : "text-emerald-700"}`}>
                        {fmtMoney(r.amount)}
                      </td>
                      <td className="py-1.5">
                        <Badge variant={r.status === "Reversed" || r.status === "Cancelled" ? "outline" : "secondary"}>
                          {r.status}
                        </Badge>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </>
  )
}

function Row({ label, value, strong = false }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-slate-500">{label}</span>
      <span className={strong ? "font-semibold" : ""}>{value}</span>
    </div>
  )
}

function Empty({ children }: { children: React.ReactNode }) {
  return <p className="text-sm text-slate-500">{children}</p>
}

function Panel({
  title, icon: Icon, href, children,
}: {
  title: string
  icon: any
  href?: string
  children: React.ReactNode
}) {
  return (
    <Card className="h-full">
      <CardHeader className="pb-2 flex flex-row items-center justify-between gap-2">
        <CardTitle className="text-xs uppercase tracking-wide text-slate-500 flex items-center gap-2">
          <Icon className="h-4 w-4" /> {title}
        </CardTitle>
        {href && (
          <Link href={href} className="text-xs text-slate-500 hover:text-slate-800 shrink-0">
            View all →
          </Link>
        )}
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  )
}

function Metric({
  title, value, hint, accent, icon: Icon,
}: {
  title: string
  value: React.ReactNode
  hint?: React.ReactNode
  accent: "emerald" | "amber" | "sky" | "slate" | "cyan" | "rose" | "orange"
  icon: any
}) {
  // Same solid-colour icon box as the farm, water and retail dashboards. One
  // visual language across all four.
  const iconBg: Record<string, string> = {
    emerald: "bg-emerald-600",
    amber: "bg-amber-500",
    sky: "bg-sky-600",
    slate: "bg-slate-600",
    cyan: "bg-cyan-600",
    rose: "bg-rose-600",
    orange: "bg-orange-500",
  }
  return (
    <Card className="bg-white rounded-xl border border-slate-200 shadow-sm">
      <CardContent className="p-4">
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

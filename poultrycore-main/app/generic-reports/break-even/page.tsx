"use client"

// Report 10: break-even.
//
//   customers needed = monthly fixed costs / average monthly revenue per customer
//
// The page shows the arithmetic rather than only the answer. A number like
// "36 members" is only trustworthy if you can see the 1,800 and the 50 it came
// from, and see which months were averaged.
//
// Two things it is careful to say out loud:
//   - The current month is NOT in the average. On the 2nd it holds two days of
//     costs, which would halve the answer.
//   - "Fixed" means total operating expenses. There is no fixed/variable flag
//     on an expense in this system, and inventing one from category names would
//     be a guess the owner cannot see.

import { useState } from "react"
import Link from "next/link"
import { Scale } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { getBreakEven, type GenericBreakEven } from "@/lib/api/generic-reports"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { useLogout } from "@/hooks/use-logout"
import { ArrowLeft, Loader2 } from "lucide-react"
import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { useAuthStore } from "@/lib/store/auth-store"
import { ReportStat, fmtDate, fmtMoney } from "@/components/generic/report-shell"

export default function BreakEvenReportPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const { labels } = useGenericModules()

  const [months, setMonths] = useState(3)
  const [data, setData] = useState<GenericBreakEven | null>(null)
  const [loading, setLoading] = useState(true)

  const load = async (m: number = months) => {
    setLoading(true)
    try { setData(await getBreakEven(null, m)) }
    catch (e: any) { toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load(3)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const covered = data ? data.customerSurplus >= 0 && data.breakEvenCustomers > 0 : false
  const short = data ? Math.max(0, -data.customerSurplus) : 0

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to reports
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
            <Scale className="h-6 w-6 text-emerald-600" /> Break-even
          </h1>
          <p className="text-sm text-slate-500 mb-4">
            How many paying {labels.customerPlural.toLowerCase()} it takes to cover a month.
          </p>

          <Card className="mb-4">
            <CardContent className="flex flex-wrap items-end gap-3 pt-6">
              <div>
                <Label>Average costs over</Label>
                <Select value={String(months)} onValueChange={(v) => setMonths(Number(v))}>
                  <SelectTrigger className="w-[12rem]"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="1">The last complete month</SelectItem>
                    <SelectItem value="3">The last 3 complete months</SelectItem>
                    <SelectItem value="6">The last 6 complete months</SelectItem>
                    <SelectItem value="12">The last 12 complete months</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <Button onClick={() => load()} disabled={loading}>
                {loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Run
              </Button>
            </CardContent>
          </Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !data ? null : (
            <>
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
                <ReportStat
                  title={`${labels.customerPlural} needed`}
                  value={data.breakEvenCustomers === 0 ? "—" : data.breakEvenCustomers}
                  hint={data.breakEvenCustomers === 0 ? "Not enough data yet" : "To cover a month"}
                />
                <ReportStat title={`Paying now`} value={data.activeCustomers} hint={`${data.activeSubscriptions} ${labels.subscriptionPlural.toLowerCase()}`} />
                <ReportStat
                  title={covered ? "Surplus" : "Short by"}
                  value={covered ? data.customerSurplus : short}
                  accent={covered ? "emerald" : "rose"}
                  hint={covered ? `${labels.customerPlural.toLowerCase()} above break-even` : `more ${labels.customerPlural.toLowerCase()} needed`}
                />
                <ReportStat
                  title="Monthly surplus"
                  value={fmtMoney(data.monthlySurplus)}
                  accent={data.monthlySurplus >= 0 ? "emerald" : "rose"}
                  hint="MRR less monthly costs"
                />
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-xs uppercase tracking-wide text-slate-500">The arithmetic</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <dl className="space-y-2 text-sm">
                      <Line label="Monthly costs" value={fmtMoney(data.monthlyFixedCosts)}
                            note={`Averaged over ${data.monthsAveraged} month(s): ${fmtDate(data.periodStart)} – ${fmtDate(data.periodEnd)}`} />
                      <Line label="Monthly recurring revenue" value={fmtMoney(data.monthlyRecurringRevenue)}
                            note={`${data.activeSubscriptions} active ${labels.subscriptionPlural.toLowerCase()}`} />
                      <Line label={`Average per ${labels.customer.toLowerCase()}`} value={fmtMoney(data.avgRevenuePerCustomer)}
                            note={`MRR ÷ ${data.activeCustomers} paying ${labels.customerPlural.toLowerCase()}`} />
                      <div className="border-t pt-2 flex items-baseline justify-between">
                        <span className="font-medium">
                          {fmtMoney(data.monthlyFixedCosts)} ÷ {fmtMoney(data.avgRevenuePerCustomer)}
                        </span>
                        <span className="text-lg font-semibold">
                          {data.breakEvenCustomers === 0 ? "—" : `${data.breakEvenCustomers} ${labels.customerPlural.toLowerCase()}`}
                        </span>
                      </div>
                    </dl>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-xs uppercase tracking-wide text-slate-500">What this does and does not count</CardTitle>
                  </CardHeader>
                  <CardContent className="text-sm text-slate-600 space-y-3">
                    <p>
                      <strong>The current month is excluded.</strong> Costs are averaged over complete months only —
                      a part-finished month would understate the average and make break-even look closer than it is.
                    </p>
                    <p>
                      <strong>“Costs” means every approved operating expense</strong>, including recurring bills and
                      anything paid to staff through an expense. There is no fixed/variable flag on an expense here,
                      and guessing one from category names would be a number you could not check.
                    </p>
                    <p>
                      <strong>Only recurring revenue counts.</strong> One-off fees are real income but they do not
                      repeat, so including them would make next month look covered when it is not. See the{" "}
                      <Link href="/generic-reports/mrr" className="text-emerald-700 hover:underline">MRR report</Link>.
                    </p>
                    {data.breakEvenCustomers === 0 && (
                      <p className="text-amber-700">
                        There is no answer yet: it needs at least one active {labels.subscription.toLowerCase()} with a
                        recurring price. Add one and this fills in.
                      </p>
                    )}
                  </CardContent>
                </Card>
              </div>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

function Line({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <div className="min-w-0">
        <dt className="text-slate-700">{label}</dt>
        {note && <dd className="text-xs text-slate-500">{note}</dd>}
      </div>
      <dd className="font-semibold shrink-0">{value}</dd>
    </div>
  )
}

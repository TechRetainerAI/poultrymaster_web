"use client"

// Broiler Performance (migration 402) -- broilers, phase 4.
//
// Every broiler flock side by side on the figures a meat flock is judged by:
// liveability, average weight, FCR, EPEF, kg produced and cost / revenue /
// profit per kg. Each row comes from fnflock_broilerkpis, which is built on
// the flock summary, so the money agrees with it. Farm totals add the
// quantities underneath (lib/poultry/broiler-kpis.ts), never averages of ratios.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Drumstick, Info, Loader2 } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { useLogout } from "@/hooks/use-logout"
import { formatCurrency } from "@/lib/utils/currency"
import { getUserContext } from "@/lib/utils/user-context"
import { getFlockBroilerKpis, type FlockBroilerKpis } from "@/lib/api/flock-closeout"
import { broilerTotals, fmtFcr, fmtKgEach, fmtKgTotal } from "@/lib/poultry/broiler-kpis"
import { cn } from "@/lib/utils"

type Show = "all" | "open" | "closed"

const money = (v: number | null | undefined) => (v == null ? "—" : formatCurrency(Number(v)))
const pct = (v: number | null | undefined) => (v == null ? "—" : `${Number(v).toFixed(2)}%`)

export default function BroilerPerformancePage() {
  const logout = useLogout()
  const [rows, setRows] = useState<FlockBroilerKpis[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [show, setShow] = useState<Show>("all")

  useEffect(() => {
    const { farmId } = getUserContext()
    if (!farmId) { setLoading(false); return }
    getFlockBroilerKpis(farmId, { broilersOnly: true })
      .then((res) => {
        if (res.success) setRows(res.data ?? [])
        else setError(res.message || "Could not load the broiler figures.")
      })
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => setLoading(false))
  }, [])

  const shown = useMemo(
    () => rows.filter((r) => show === "all" || (show === "closed" ? !!r.closedDate : !r.closedDate)),
    [rows, show],
  )
  const t = useMemo(() => broilerTotals(shown), [shown])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-x-hidden p-4 pb-6 sm:p-6">
          <div className="space-y-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-orange-100">
                  <Drumstick className="h-5 w-5 text-orange-700" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-2xl font-bold text-slate-900">Broiler performance</h1>
                  <p className="text-sm text-slate-600">Liveability, weight, feed conversion and cost per kg for every broiler flock.</p>
                </div>
              </div>
              <div role="radiogroup" aria-label="Which flocks" className="flex rounded-md border border-slate-200 bg-white p-0.5 text-sm">
                {(["all", "open", "closed"] as const).map((v) => (
                  <button key={v} type="button" role="radio" aria-checked={show === v} onClick={() => setShow(v)}
                    className={cn("rounded px-3 py-1 font-medium", show === v ? "bg-orange-500 text-white" : "text-slate-600 hover:bg-slate-50")}>
                    {v === "all" ? "All" : v === "open" ? "Running" : "Closed"}
                  </button>
                ))}
              </div>
            </div>

            {error && <p className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              <Tile label="FCR" value={fmtFcr(t.fcr)}
                sub={t.flocksWithKg < t.flocks ? `${t.flocksWithKg} of ${t.flocks} flocks have a known kg` : "kg feed per kg live weight"} />
              <Tile label="Liveability" value={pct(t.liveabilityPct)} sub={`${t.deaths.toLocaleString()} died of ${t.birdsStarted.toLocaleString()}`} />
              <Tile label="Kg produced" value={fmtKgTotal(t.kgProduced)} sub={t.kgIsEstimated ? "Partly estimated" : "From sales and weigh-ins"} />
              <Tile label="Cost per kg" value={money(t.costPerKg)} sub="Chick cost included" />
            </div>

            <Card>
              <CardContent className="p-0">
                {loading ? (
                  <div className="flex h-40 items-center justify-center text-slate-500"><Loader2 className="h-5 w-5 animate-spin" /></div>
                ) : shown.length === 0 ? (
                  <div className="p-6 text-center text-sm text-slate-500">
                    No broiler flocks{show === "all" ? "" : show === "open" ? " running" : " closed"} yet. A flock is a broiler
                    flock when it is set to Broilers on the Flocks page.
                  </div>
                ) : (
                  <>
                    <div className="hidden overflow-x-auto md:block">
                      <table className="w-full text-sm">
                        <thead className="bg-slate-50 text-left text-xs uppercase text-slate-500">
                          <tr>
                            <th className="px-4 py-2">Flock</th>
                            <th className="px-3 py-2 text-right">Age</th>
                            <th className="px-3 py-2 text-right">Liveability</th>
                            <th className="px-3 py-2 text-right">Avg weight</th>
                            <th className="px-3 py-2 text-right">FCR</th>
                            <th className="px-3 py-2 text-right">EPEF</th>
                            <th className="px-3 py-2 text-right">Kg produced</th>
                            <th className="px-3 py-2 text-right">Cost / kg</th>
                            <th className="px-3 py-2 text-right">Revenue / kg</th>
                            <th className="px-3 py-2 text-right">Profit / kg</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y">
                          {shown.map((r) => (
                            <tr key={r.flockId} className="align-top hover:bg-slate-50">
                              <td className="px-4 py-2">
                                <Link href={`/flock-closeout/${r.flockId}`} className="font-medium text-slate-900 hover:underline">{r.flockName}</Link>
                                <div className="flex flex-wrap items-center gap-1.5 text-xs text-slate-500">
                                  <span>{r.closedDate ? `Closed ${r.closedDate.slice(0, 10)}` : "Running"}</span>
                                  {r.breed && <span>· {r.breed}</span>}
                                  {r.kgIsEstimated && <Badge variant="secondary" className="px-1.5 py-0 text-[10px]">kg estimated</Badge>}
                                </div>
                                {r.missing && <div className="mt-0.5 flex items-start gap-1 text-xs text-amber-700"><Info className="mt-0.5 h-3 w-3 shrink-0" />{r.missing}</div>}
                              </td>
                              <td className="px-3 py-2 text-right tabular-nums">{r.ageInDays} d</td>
                              <td className="px-3 py-2 text-right tabular-nums">{pct(r.liveabilityPct)}</td>
                              <td className="px-3 py-2 text-right tabular-nums">{fmtKgEach(r.avgLiveWeightKg)}</td>
                              <td className="px-3 py-2 text-right font-medium tabular-nums">{fmtFcr(r.fcr)}</td>
                              <td className="px-3 py-2 text-right tabular-nums">{r.epef == null ? "—" : Math.round(Number(r.epef)).toLocaleString()}</td>
                              <td className="px-3 py-2 text-right tabular-nums">{fmtKgTotal(r.kgProduced)}</td>
                              <td className="px-3 py-2 text-right tabular-nums">{money(r.costPerKg)}</td>
                              <td className="px-3 py-2 text-right tabular-nums">{money(r.revenuePerKg)}</td>
                              <td className={cn("px-3 py-2 text-right tabular-nums",
                                r.profitPerKg == null ? "" : r.profitPerKg >= 0 ? "text-emerald-700" : "text-rose-700")}>{money(r.profitPerKg)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                    {/* Phone: a card per flock. */}
                    <div className="divide-y md:hidden">
                      {shown.map((r) => (
                        <Link key={r.flockId} href={`/flock-closeout/${r.flockId}`} className="block space-y-1.5 p-4 hover:bg-slate-50">
                          <div className="flex items-center justify-between gap-2">
                            <span className="font-semibold text-slate-900">{r.flockName}</span>
                            <span className="text-xs text-slate-500">{r.closedDate ? "Closed" : "Running"} · {r.ageInDays} d</span>
                          </div>
                          <div className="grid grid-cols-3 gap-2 text-xs">
                            <Mini label="FCR" value={fmtFcr(r.fcr)} />
                            <Mini label="Liveability" value={pct(r.liveabilityPct)} />
                            <Mini label="Avg weight" value={fmtKgEach(r.avgLiveWeightKg)} />
                            <Mini label="EPEF" value={r.epef == null ? "—" : Math.round(Number(r.epef)).toLocaleString()} />
                            <Mini label="Cost / kg" value={money(r.costPerKg)} />
                            <Mini label="Profit / kg" value={money(r.profitPerKg)} />
                          </div>
                          {r.missing && <p className="text-xs text-amber-700">{r.missing}</p>}
                        </Link>
                      ))}
                    </div>
                  </>
                )}
              </CardContent>
            </Card>

            <p className="text-xs text-slate-500">
              FCR is feed kg over live kg produced. Kg produced is the weight on bird sales, plus an estimate for birds sold
              without a weight (at the average sale weight) and for birds still in the house (at the latest weigh-in).
              EPEF = liveability % × average weight kg ÷ (age days × FCR) × 100. Cost per kg includes the chick cost.
            </p>
          </div>
        </main>
      </div>
    </div>
  )
}

function Tile({ label, value, sub }: { label: string; value: string; sub: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">{label}</div>
        <div className="mt-1 text-2xl font-semibold tabular-nums text-slate-900">{value}</div>
        <div className="mt-0.5 text-xs text-slate-500">{sub}</div>
      </CardContent>
    </Card>
  )
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-slate-500">{label}</div>
      <div className="font-semibold tabular-nums text-slate-900">{value}</div>
    </div>
  )
}

"use client"

// Generic Cash Flow — shows cash in/out by account for a date range.
// Uses the existing getCashSummaryReport API.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Loader2, Wallet, TrendingUp, TrendingDown, DollarSign } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { getCashSummaryReport, type GenericCashSummaryReport } from "@/lib/api/generic"

function defaultRange() {
  const now = new Date()
  const y = now.getFullYear(), m = now.getMonth()
  return {
    from: new Date(y, m, 1).toISOString().slice(0, 10),
    to: now.toISOString().slice(0, 10),
  }
}

function Kpi({ icon, label, value, tone }: { icon: React.ReactNode; label: string; value: React.ReactNode; tone?: "good" | "bad" }) {
  return (
    <div className={cn("rounded-xl border bg-white p-3 shadow-sm sm:p-4", tone === "bad" ? "border-red-200" : "border-slate-200")}>
      <div className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-slate-500">{icon} {label}</div>
      <div className={cn("mt-1 text-xl font-bold tabular-nums sm:text-2xl",
        tone === "good" ? "text-emerald-700" : tone === "bad" ? "text-red-600" : "text-slate-900")}>{value}</div>
    </div>
  )
}

export default function GenericCashFlowPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [loading, setLoading] = useState(true)
  const [report, setReport] = useState<GenericCashSummaryReport | null>(null)
  const [range, setRange] = useState(defaultRange)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const data = await getCashSummaryReport(range.from, range.to)
      setReport(data)
    } catch (e: any) {
      toast({ title: "Could not load cash flow", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  const totals = useMemo(() => {
    if (!report) return { cashIn: 0, cashOut: 0, net: 0 }
    const cashIn = report.accounts.reduce((s, a) => s + a.periodCashIn, 0)
    const cashOut = report.accounts.reduce((s, a) => s + a.periodCashOut, 0)
    return { cashIn, cashOut, net: cashIn - cashOut }
  }, [report])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div>
            <h1 className="text-2xl font-bold text-slate-900">Cash Flow</h1>
            <p className="text-sm text-slate-500">Money in and out across all cash accounts.</p>
          </div>

          <div className="flex flex-wrap items-end gap-3">
            <div>
              <Label className="text-xs text-slate-500">From</Label>
              <Input type="date" value={range.from} onChange={(e) => setRange((r) => ({ ...r, from: e.target.value }))} className="w-40" />
            </div>
            <div>
              <Label className="text-xs text-slate-500">To</Label>
              <Input type="date" value={range.to} onChange={(e) => setRange((r) => ({ ...r, to: e.target.value }))} className="w-40" />
            </div>
            <button type="button" onClick={load} className="rounded-md bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700">
              Update
            </button>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : report && (
            <>
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <Kpi icon={<Wallet className="w-4 h-4 text-blue-600" />} label="Cash at hand" value={gh(report.totalCashAtHand)} />
                <Kpi icon={<TrendingUp className="w-4 h-4 text-emerald-600" />} label="Cash in" value={gh(totals.cashIn)} tone="good" />
                <Kpi icon={<TrendingDown className="w-4 h-4 text-red-600" />} label="Cash out" value={gh(totals.cashOut)} tone="bad" />
                <Kpi icon={<DollarSign className="w-4 h-4 text-blue-600" />} label="Net cash flow" value={gh(totals.net)} tone={totals.net >= 0 ? "good" : "bad"} />
              </div>

              <Card>
                <CardContent className="p-0">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Account</TableHead>
                        <TableHead>Type</TableHead>
                        <TableHead className="text-right">Cash in</TableHead>
                        <TableHead className="text-right">Cash out</TableHead>
                        <TableHead className="text-right">Net</TableHead>
                        <TableHead className="text-right">Balance</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {report.accounts.length === 0 ? (
                        <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-8">No cash accounts found.</TableCell></TableRow>
                      ) : report.accounts.map((a) => (
                        <TableRow key={a.genericCashAccountId}>
                          <TableCell className="font-medium">{a.accountName}</TableCell>
                          <TableCell className="text-sm text-slate-500">{a.accountType}</TableCell>
                          <TableCell className="text-right tabular-nums text-emerald-700">{gh(a.periodCashIn)}</TableCell>
                          <TableCell className="text-right tabular-nums text-red-600">{gh(a.periodCashOut)}</TableCell>
                          <TableCell className={cn("text-right tabular-nums font-medium", a.periodCashIn - a.periodCashOut >= 0 ? "text-emerald-700" : "text-red-600")}>
                            {gh(a.periodCashIn - a.periodCashOut)}
                          </TableCell>
                          <TableCell className="text-right tabular-nums font-semibold">{gh(a.currentBalance)}</TableCell>
                          <TableCell>
                            <Badge className={a.isActive ? "bg-emerald-100 text-emerald-800" : "bg-slate-100 text-slate-600"}>
                              {a.isActive ? "Active" : "Inactive"}
                            </Badge>
                          </TableCell>
                        </TableRow>
                      ))}
                      {report.accounts.length > 0 && (
                        <TableRow className="bg-slate-50 font-semibold">
                          <TableCell colSpan={2}>Total</TableCell>
                          <TableCell className="text-right tabular-nums text-emerald-700">{gh(totals.cashIn)}</TableCell>
                          <TableCell className="text-right tabular-nums text-red-600">{gh(totals.cashOut)}</TableCell>
                          <TableCell className={cn("text-right tabular-nums", totals.net >= 0 ? "text-emerald-700" : "text-red-600")}>{gh(totals.net)}</TableCell>
                          <TableCell className="text-right tabular-nums">{gh(report.totalCashAtHand)}</TableCell>
                          <TableCell></TableCell>
                        </TableRow>
                      )}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

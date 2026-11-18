"use client"

import { useEffect, useState } from "react"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod } from "@/lib/date-ranges"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, Loader2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getCashSummaryReport, type GenericCashSummaryReport } from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function defaultMonthRange() {
  const now = new Date()
  return {
    fromDate: new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10),
    toDate: now.toISOString().slice(0, 10),
  }
}

export default function CashSummaryPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [range, setRange] = useState(defaultMonthRange())
  const [report, setReport] = useState<GenericCashSummaryReport | null>(null)
  const [loading, setLoading] = useState(false)

  const load = async () => {
    setLoading(true)
    try { setReport(await getCashSummaryReport(range.fromDate, range.toDate)) }
    catch (e: any) { toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to reports
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2 mb-4">
            <Wallet className="h-6 w-6 text-slate-700" /> Cash summary
          </h1>

          <Card className="mb-4">
            <CardContent className="flex flex-wrap items-end gap-3 pt-6">
              <PeriodSelect value={rangeToPeriod(range.fromDate, range.toDate)} onChange={(_p, rg) => { if (rg) setRange({ fromDate: rg.from, toDate: rg.to }) }} />
              <div><Label>From</Label><Input type="date" value={range.fromDate} onChange={(e) => setRange((r) => ({ ...r, fromDate: e.target.value }))} /></div>
              <div><Label>To</Label><Input type="date" value={range.toDate} onChange={(e) => setRange((r) => ({ ...r, toDate: e.target.value }))} /></div>
              <Button onClick={load} disabled={loading}>{loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Run</Button>
            </CardContent>
          </Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !report ? null : (
            <>
              <Card className="mb-4 max-w-sm">
                <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">Total cash at hand (now)</CardTitle></CardHeader>
                <CardContent><div className="text-3xl font-semibold text-slate-900">{fmt(report.totalCashAtHand)}</div></CardContent>
              </Card>

              <Card>
                <CardContent className="p-0">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Account</TableHead>
                        <TableHead>Type</TableHead>
                        <TableHead className="text-right">Cash in (period)</TableHead>
                        <TableHead className="text-right">Cash out (period)</TableHead>
                        <TableHead className="text-right">Net (period)</TableHead>
                        <TableHead className="text-right">Current balance</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {report.accounts.map((a) => (
                        <TableRow key={a.genericCashAccountId}>
                          <TableCell className="font-medium">{a.accountName}</TableCell>
                          <TableCell className="text-xs text-slate-500">{a.accountType}</TableCell>
                          <TableCell className="text-right text-emerald-700">{fmt(a.periodCashIn)}</TableCell>
                          <TableCell className="text-right text-rose-700">{fmt(a.periodCashOut)}</TableCell>
                          <TableCell className="text-right font-semibold">{fmt(a.periodCashIn - a.periodCashOut)}</TableCell>
                          <TableCell className={`text-right font-semibold ${a.currentBalance < 0 ? "text-rose-700" : ""}`}>{fmt(a.currentBalance)}</TableCell>
                          <TableCell>{a.isActive ? <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Active</Badge> : <Badge variant="secondary">Inactive</Badge>}</TableCell>
                        </TableRow>
                      ))}
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

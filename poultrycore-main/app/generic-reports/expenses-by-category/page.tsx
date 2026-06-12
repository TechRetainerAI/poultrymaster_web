"use client"

import { useEffect, useState } from "react"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod } from "@/lib/date-ranges"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, BarChart3, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getExpensesByCategoryReport, type GenericExpenseByCategoryRow } from "@/lib/api/generic"

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

export default function ExpensesByCategoryPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [range, setRange] = useState(defaultMonthRange())
  const [rows, setRows] = useState<GenericExpenseByCategoryRow[]>([])
  const [loading, setLoading] = useState(false)

  const load = async () => {
    setLoading(true)
    try { setRows(await getExpensesByCategoryReport(range.fromDate, range.toDate)) }
    catch (e: any) { toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const total = rows.reduce((s, r) => s + r.totalAmount, 0)

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
            <BarChart3 className="h-6 w-6 text-amber-600" /> Expenses by category
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
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No data for this range.</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Category</TableHead>
                      <TableHead className="text-right">Count</TableHead>
                      <TableHead className="text-right">Amount</TableHead>
                      <TableHead className="text-right">% of total</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((r) => (
                      <TableRow key={r.genericExpenseCategoryId}>
                        <TableCell className="font-medium">{r.categoryName}</TableCell>
                        <TableCell className="text-right">{r.expenseCount}</TableCell>
                        <TableCell className="text-right font-semibold">{fmt(r.totalAmount)}</TableCell>
                        <TableCell className="text-right">{total > 0 ? `${((r.totalAmount / total) * 100).toFixed(1)}%` : "—"}</TableCell>
                      </TableRow>
                    ))}
                    <TableRow className="font-semibold bg-slate-50">
                      <TableCell>Total</TableCell>
                      <TableCell className="text-right">{rows.reduce((s, r) => s + r.expenseCount, 0)}</TableCell>
                      <TableCell className="text-right">{fmt(total)}</TableCell>
                      <TableCell></TableCell>
                    </TableRow>
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

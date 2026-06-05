"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, Loader2, Users } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getSalesByCustomerReport, type GenericSalesByCustomerRow } from "@/lib/api/generic"

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

export default function SalesByCustomerPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [range, setRange] = useState(defaultMonthRange())
  const [rows, setRows] = useState<GenericSalesByCustomerRow[]>([])
  const [loading, setLoading] = useState(false)

  const load = async () => {
    setLoading(true)
    try { setRows(await getSalesByCustomerReport(range.fromDate, range.toDate)) }
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
            <Users className="h-6 w-6 text-cyan-600" /> Sales by customer
          </h1>

          <Card className="mb-4">
            <CardContent className="flex flex-wrap items-end gap-3 pt-6">
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
                      <TableHead>Customer</TableHead>
                      <TableHead>Phone</TableHead>
                      <TableHead className="text-right">Sales</TableHead>
                      <TableHead className="text-right">Revenue</TableHead>
                      <TableHead className="text-right">Paid</TableHead>
                      <TableHead className="text-right">Outstanding</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((r, i) => (
                      <TableRow key={r.genericCustomerId ?? `row-${i}`}>
                        <TableCell className="font-medium">{r.customerName}</TableCell>
                        <TableCell>{r.phoneNumber ?? "—"}</TableCell>
                        <TableCell className="text-right">{r.salesCount}</TableCell>
                        <TableCell className="text-right">{fmt(r.totalRevenue)}</TableCell>
                        <TableCell className="text-right">{fmt(r.totalPaid)}</TableCell>
                        <TableCell className={`text-right ${r.totalOutstanding > 0 ? "text-rose-700 font-semibold" : ""}`}>{fmt(r.totalOutstanding)}</TableCell>
                      </TableRow>
                    ))}
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

"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, Plus, ShoppingCart } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getSales, type GenericSale } from "@/lib/api/generic"

const STATUS_FILTERS = ["All", "Draft", "Approved", "Refunded", "Cancelled"] as const

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function statusBadgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Refunded":  return "bg-amber-100 text-amber-800 hover:bg-amber-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

function GenericSalesPageInner() {
  const router = useRouter()
  const search = useSearchParams()
  const status = search.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericSale[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const data = await getSales(status === "All" ? null : status)
        if (!cancelled) setRows(data)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load sales", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, status, toast])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <ShoppingCart className="h-6 w-6 text-emerald-600" /> Sales
              </h1>
              <p className="text-sm text-slate-500">{rows.length} {status === "All" ? "" : status.toLowerCase()} sale(s)</p>
            </div>
            <Button asChild>
              <Link href="/generic-sales/new"><Plus className="h-4 w-4 mr-1" />New sale</Link>
            </Button>
          </div>

          <div className="flex gap-1 mb-3 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button
                key={s}
                size="sm"
                variant={s === status ? "default" : "outline"}
                onClick={() => router.replace(s === "All" ? "/generic-sales" : `/generic-sales?status=${s}`)}
              >
                {s}
              </Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No sales yet. <Link href="/generic-sales/new" className="text-emerald-700 underline">Record your first one â†’</Link></CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>#</TableHead>
                      <TableHead>Date</TableHead>
                      <TableHead>Customer</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead className="text-right">Total</TableHead>
                      <TableHead className="text-right">Paid</TableHead>
                      <TableHead className="text-right">Balance</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((s) => (
                      <TableRow key={s.genericSaleId}>
                        <TableCell><Link href={`/generic-sales/${s.genericSaleId}`} className="text-emerald-700 underline">#{s.genericSaleId}</Link></TableCell>
                        <TableCell>{new Date(s.saleDate).toLocaleDateString()}</TableCell>
                        <TableCell>{s.customerName ?? <span className="text-slate-500">Walk-in</span>}</TableCell>
                        <TableCell className="text-xs text-slate-500">{s.salesType}</TableCell>
                        <TableCell className="text-right">{fmt(s.totalAmount)}</TableCell>
                        <TableCell className="text-right">{fmt(s.amountPaid)}</TableCell>
                        <TableCell className={`text-right ${s.balance > 0 ? "text-rose-700 font-semibold" : ""}`}>{fmt(s.balance)}</TableCell>
                        <TableCell><Badge className={statusBadgeClass(s.status)}>{s.status}</Badge></TableCell>
                        <TableCell><Button asChild size="sm" variant="ghost"><Link href={`/generic-sales/${s.genericSaleId}`}>Details</Link></Button></TableCell>
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

export default function GenericSalesPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericSalesPageInner />
    </Suspense>
  )
}

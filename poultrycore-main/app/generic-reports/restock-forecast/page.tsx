"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft, TrendingUp, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getRestockForecast, type GenericRestockForecastRow } from "@/lib/api/generic"

const URGENCY_COLORS: Record<string, string> = {
  Critical: "bg-red-100 text-red-800",
  Urgent: "bg-rose-100 text-rose-800",
  Warning: "bg-amber-100 text-amber-800",
  OK: "bg-emerald-100 text-emerald-800",
}

export default function RestockForecastPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericRestockForecastRow[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      setLoading(true)
      try {
        const data = await getRestockForecast(30)
        if (!cancelled) setRows(data)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load forecast", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const filtered = useMemo(() => {
    if (!search.trim()) return rows
    const s = search.toLowerCase()
    return rows.filter((r) => r.productName.toLowerCase().includes(s))
  }, [rows, search])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to reports
          </Link>
          <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2 mb-1">
            <TrendingUp className="h-6 w-6 text-blue-600" /> Restock Forecast
          </h1>
          <p className="text-sm text-slate-500 mb-4">Projected stockout dates based on all consumption (sales, internal use, damage). Last 30 days of history.</p>

          <Input className="max-w-xs mb-4" placeholder="Search item" value={search} onChange={(e) => setSearch(e.target.value)} />

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <Card>
              <CardContent className="p-0 overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Item</TableHead>
                      <TableHead className="text-right">Stock</TableHead>
                      <TableHead className="text-right">Avg Daily Sales</TableHead>
                      <TableHead className="text-right">Avg Daily Internal</TableHead>
                      <TableHead className="text-right">Total Daily Out</TableHead>
                      <TableHead className="text-right">Days to Stockout</TableHead>
                      <TableHead className="text-right">Reorder Qty</TableHead>
                      <TableHead>Urgency</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.map((r) => (
                      <TableRow key={r.genericProductId}>
                        <TableCell>
                          <div className="font-medium">{r.productName}</div>
                          {r.unitOfMeasure && <div className="text-xs text-slate-500">{r.unitOfMeasure}</div>}
                        </TableCell>
                        <TableCell className="text-right">{r.currentStock.toLocaleString(undefined, { maximumFractionDigits: 1 })}</TableCell>
                        <TableCell className="text-right">{r.avgDailySales.toFixed(2)}</TableCell>
                        <TableCell className="text-right">{r.avgDailyInternalUse.toFixed(2)}</TableCell>
                        <TableCell className="text-right font-medium">{r.avgDailyTotalOut.toFixed(2)}</TableCell>
                        <TableCell className="text-right">{r.daysUntilStockout >= 9999 ? "—" : Math.round(r.daysUntilStockout)}</TableCell>
                        <TableCell className="text-right">{r.suggestedReorderQty > 0 ? r.suggestedReorderQty.toLocaleString(undefined, { maximumFractionDigits: 0 }) : "—"}</TableCell>
                        <TableCell><Badge className={`${URGENCY_COLORS[r.urgencyLevel] ?? "bg-slate-100"} hover:${URGENCY_COLORS[r.urgencyLevel]}`}>{r.urgencyLevel}</Badge></TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                {filtered.length === 0 && <p className="text-center text-slate-500 py-8">No items to forecast.</p>}
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

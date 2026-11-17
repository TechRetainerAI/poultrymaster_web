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
import { ArrowLeft, PackageMinus, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getInternalConsumption, getConsumptionSummary, type GenericConsumptionRow, type GenericConsumptionSummary } from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

export default function InternalConsumptionPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericConsumptionRow[]>([])
  const [summary, setSummary] = useState<GenericConsumptionSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")

  const now = new Date()
  const [fromDate, setFromDate] = useState(() => new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10))
  const [toDate, setToDate] = useState(() => now.toISOString().slice(0, 10))

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      setLoading(true)
      try {
        const [data, sum] = await Promise.all([
          getInternalConsumption(fromDate, toDate),
          getConsumptionSummary(fromDate, toDate),
        ])
        if (!cancelled) { setRows(data); setSummary(sum) }
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast, fromDate, toDate])

  const filtered = useMemo(() => {
    if (!search.trim()) return rows
    const s = search.toLowerCase()
    return rows.filter((r) => r.productName.toLowerCase().includes(s) || (r.expenseCategory ?? "").toLowerCase().includes(s) || (r.reason ?? "").toLowerCase().includes(s))
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
            <PackageMinus className="h-6 w-6 text-purple-600" /> Internal Inventory Consumption
          </h1>
          <p className="text-sm text-slate-500 mb-4">Stock consumed internally (staff welfare, cleaning, samples, etc.) — not sold.</p>

          {/* Summary cards */}
          {summary && !loading && (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
              <div className="rounded-lg bg-purple-50 p-3">
                <div className="text-xs text-purple-600 font-medium">Total Cost</div>
                <div className="text-lg font-bold text-purple-800">{fmt(summary.totalConsumptionCost)}</div>
              </div>
              <div className="rounded-lg bg-blue-50 p-3">
                <div className="text-xs text-blue-600 font-medium">Items Consumed</div>
                <div className="text-lg font-bold text-blue-800">{summary.totalItemsConsumed}</div>
              </div>
              <div className="rounded-lg bg-slate-50 border p-3">
                <div className="text-xs text-slate-600 font-medium">Records</div>
                <div className="text-lg font-bold text-slate-800">{summary.totalRecords}</div>
              </div>
              {summary.topItemName && (
                <div className="rounded-lg bg-amber-50 p-3">
                  <div className="text-xs text-amber-600 font-medium">Most Consumed</div>
                  <div className="text-sm font-bold text-amber-800 truncate">{summary.topItemName}</div>
                  <div className="text-xs text-amber-600">{fmt(summary.topItemCost)}</div>
                </div>
              )}
            </div>
          )}

          <div className="flex flex-wrap gap-2 mb-4">
            <Input type="date" className="w-auto" value={fromDate} onChange={(e) => setFromDate(e.target.value)} />
            <Input type="date" className="w-auto" value={toDate} onChange={(e) => setToDate(e.target.value)} />
            <Input className="max-w-xs" placeholder="Search item, category or reason" value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <Card>
              <CardContent className="p-0 overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Item</TableHead>
                      <TableHead className="text-right">Qty Used</TableHead>
                      <TableHead>Unit</TableHead>
                      <TableHead className="text-right">Unit Cost</TableHead>
                      <TableHead className="text-right">Total Cost</TableHead>
                      <TableHead>Expense Category</TableHead>
                      <TableHead>Reason</TableHead>
                      <TableHead>Ref</TableHead>
                      <TableHead>Recorded By</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.map((r, i) => (
                      <TableRow key={`${r.genericInternalUsageId}-${i}`}>
                        <TableCell className="whitespace-nowrap">{new Date(r.usageDate).toLocaleDateString()}</TableCell>
                        <TableCell className="font-medium">{r.productName}</TableCell>
                        <TableCell className="text-right">{r.quantityUsed.toLocaleString(undefined, { maximumFractionDigits: 3 })}</TableCell>
                        <TableCell className="text-sm">{r.unitOfMeasure ?? "—"}</TableCell>
                        <TableCell className="text-right">{fmt(r.unitCost)}</TableCell>
                        <TableCell className="text-right font-medium">{fmt(r.totalCost)}</TableCell>
                        <TableCell><Badge variant="outline" className="text-xs">{r.expenseCategory ?? "—"}</Badge></TableCell>
                        <TableCell className="text-sm text-slate-600 max-w-[150px] truncate">{r.reason ?? "—"}</TableCell>
                        <TableCell className="text-xs font-mono">{r.referenceNumber ?? "—"}</TableCell>
                        <TableCell className="text-sm">{r.recordedBy ?? "—"}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                {filtered.length === 0 && <p className="text-center text-slate-500 py-8">No internal consumption records found.</p>}
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

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
import { ArrowLeft, Boxes, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getInventoryBalance, type GenericInventoryBalanceRow } from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}
function fmtQty(n: number) { return n.toLocaleString(undefined, { maximumFractionDigits: 3 }) }

export default function InventoryBalancePage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericInventoryBalanceRow[]>([])
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
        const data = await getInventoryBalance(fromDate, toDate)
        if (!cancelled) setRows(data)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast, fromDate, toDate])

  const filtered = useMemo(() => {
    if (!search.trim()) return rows
    const s = search.toLowerCase()
    return rows.filter((r) => r.productName.toLowerCase().includes(s) || (r.categoryName ?? "").toLowerCase().includes(s))
  }, [rows, search])

  const totals = useMemo(() => ({
    value: filtered.reduce((s, r) => s + r.inventoryValue, 0),
  }), [filtered])

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
            <Boxes className="h-6 w-6 text-blue-600" /> Inventory Balance
          </h1>
          <p className="text-sm text-slate-500 mb-4">Opening, movements, and closing stock for every tracked item.</p>

          <div className="flex flex-wrap gap-2 mb-4">
            <Input type="date" className="w-auto" value={fromDate} onChange={(e) => setFromDate(e.target.value)} />
            <Input type="date" className="w-auto" value={toDate} onChange={(e) => setToDate(e.target.value)} />
            <Input className="max-w-xs" placeholder="Search item or category" value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <Card>
              <CardContent className="p-0 overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Item</TableHead>
                      <TableHead>Category</TableHead>
                      <TableHead>Purpose</TableHead>
                      <TableHead className="text-right">Opening</TableHead>
                      <TableHead className="text-right">Purchases</TableHead>
                      <TableHead className="text-right">Sales</TableHead>
                      <TableHead className="text-right">Internal Use</TableHead>
                      <TableHead className="text-right">Other</TableHead>
                      <TableHead className="text-right">Closing</TableHead>
                      <TableHead>Unit</TableHead>
                      <TableHead className="text-right">Value</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.map((r) => (
                      <TableRow key={r.genericProductId}>
                        <TableCell className="font-medium">{r.productName}</TableCell>
                        <TableCell className="text-sm">{r.categoryName ?? "—"}</TableCell>
                        <TableCell><span className="text-xs">{r.purpose}</span></TableCell>
                        <TableCell className="text-right">{fmtQty(r.openingQty)}</TableCell>
                        <TableCell className="text-right text-emerald-700">+{fmtQty(r.purchasesQty + r.productionInQty + r.returnsInQty)}</TableCell>
                        <TableCell className="text-right text-rose-700">-{fmtQty(r.salesQty)}</TableCell>
                        <TableCell className="text-right text-purple-700">-{fmtQty(r.internalUseQty)}</TableCell>
                        <TableCell className="text-right">{fmtQty(r.damageQty + r.adjustmentQty + r.otherQty)}</TableCell>
                        <TableCell className="text-right font-bold">{fmtQty(r.closingQty)}</TableCell>
                        <TableCell className="text-sm">{r.unitOfMeasure ?? "—"}</TableCell>
                        <TableCell className="text-right">{fmt(r.inventoryValue)}</TableCell>
                      </TableRow>
                    ))}
                    {filtered.length > 0 && (
                      <TableRow className="bg-slate-50 font-semibold">
                        <TableCell colSpan={10} className="text-right">Total Inventory Value</TableCell>
                        <TableCell className="text-right">{fmt(totals.value)}</TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
                {filtered.length === 0 && <p className="text-center text-slate-500 py-8">No inventory items found.</p>}
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft, CheckCircle2, AlertTriangle, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getInventoryReconciliation, type GenericReconciliationRow } from "@/lib/api/generic"

export default function InventoryReconciliationPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericReconciliationRow[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      setLoading(true)
      try {
        const data = await getInventoryReconciliation()
        if (!cancelled) setRows(data)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load reconciliation", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const driftCount = rows.filter((r) => !r.isReconciled).length
  const totalCount = rows.length

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
            <CheckCircle2 className="h-6 w-6 text-blue-600" /> Inventory Reconciliation
          </h1>
          <p className="text-sm text-slate-500 mb-4">Compares cached stock (CurrentStock) against the authoritative ledger (SUM of stock movements).</p>

          {!loading && (
            <div className="flex gap-3 mb-4">
              <div className={`rounded-lg p-3 ${driftCount === 0 ? "bg-emerald-50" : "bg-amber-50"}`}>
                <div className={`text-xs font-medium ${driftCount === 0 ? "text-emerald-600" : "text-amber-600"}`}>Status</div>
                <div className={`text-lg font-bold ${driftCount === 0 ? "text-emerald-800" : "text-amber-800"}`}>
                  {driftCount === 0 ? "All Reconciled" : `${driftCount} item(s) with drift`}
                </div>
                <div className="text-xs text-slate-500">{totalCount} tracked items</div>
              </div>
            </div>
          )}

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <Card>
              <CardContent className="p-0 overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Item</TableHead>
                      <TableHead className="text-right">Ledger Total</TableHead>
                      <TableHead className="text-right">Cached Stock</TableHead>
                      <TableHead className="text-right">Drift</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((r) => (
                      <TableRow key={r.genericProductId} className={r.isReconciled ? "" : "bg-amber-50"}>
                        <TableCell className="font-medium">{r.productName}</TableCell>
                        <TableCell className="text-right font-mono">{r.ledgerTotal.toLocaleString(undefined, { maximumFractionDigits: 3 })}</TableCell>
                        <TableCell className="text-right font-mono">{r.cachedStock.toLocaleString(undefined, { maximumFractionDigits: 3 })}</TableCell>
                        <TableCell className={`text-right font-mono ${r.drift !== 0 ? "text-amber-700 font-bold" : ""}`}>
                          {r.drift !== 0 ? r.drift.toLocaleString(undefined, { maximumFractionDigits: 3 }) : "0"}
                        </TableCell>
                        <TableCell>
                          {r.isReconciled
                            ? <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100"><CheckCircle2 className="h-3 w-3 mr-1" />OK</Badge>
                            : <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100"><AlertTriangle className="h-3 w-3 mr-1" />Drift</Badge>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                {rows.length === 0 && <p className="text-center text-slate-500 py-8">No tracked items.</p>}
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

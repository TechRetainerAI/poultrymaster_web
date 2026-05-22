"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, Wallet, AlertCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { listWaterPayments, type WaterPayment } from "@/lib/api/water"

export default function WaterPaymentsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const [items, setItems] = useState<WaterPayment[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try { const list = await listWaterPayments(); if (!cancelled) setItems(list) }
      catch (e: any) { if (!cancelled) setError(e?.message ?? String(e)) }
      finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2 mb-4">
            <Wallet className="h-6 w-6 text-sky-600" /> Payments received
          </h1>
          <p className="text-sm text-slate-500 mb-4">Record payments from the Sales page → Details. This view lists every payment captured.</p>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700">
                <AlertCircle className="h-4 w-4" /> {error}
              </CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No payments yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Sale #</TableHead>
                      <TableHead>Customer</TableHead>
                      <TableHead className="text-right">Amount</TableHead>
                      <TableHead>Method</TableHead>
                      <TableHead>Reference</TableHead>
                      <TableHead>Note</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {items.map((p) => (
                      <TableRow key={p.waterPaymentId}>
                        <TableCell>{new Date(p.paymentDate).toLocaleString()}</TableCell>
                        <TableCell>#{p.waterSaleId}</TableCell>
                        <TableCell>{p.customerName ?? "Walk-in"}</TableCell>
                        <TableCell className="text-right tabular-nums">{p.amount.toFixed(2)}</TableCell>
                        <TableCell>{p.paymentMethod ?? "—"}</TableCell>
                        <TableCell className="text-slate-500">{p.reference ?? "—"}</TableCell>
                        <TableCell className="text-slate-500">{p.note ?? "—"}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}

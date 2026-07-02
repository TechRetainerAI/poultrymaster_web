"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { listPoultryProductionLosses, type PoultryProductionLoss } from "@/lib/api/poultry-inventory"

export default function PoultryProductionLossesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [rows, setRows] = useState<PoultryProductionLoss[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    ;(async () => {
      try { setRows(await listPoultryProductionLosses()) }
      catch (e: any) { toast({ title: "Could not load production losses", description: e?.message, variant: "destructive" }) }
      finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div><h1 className="text-2xl font-bold">Production Losses</h1><p className="text-sm text-slate-500">Auto-recorded when a production batch reports damaged output.</p></div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Product</TableHead><TableHead>Source</TableHead><TableHead className="text-right">Qty lost</TableHead><TableHead className="text-right">Value</TableHead><TableHead>Reason</TableHead></TableRow></TableHeader>
                <TableBody>
                  {rows.length === 0 ? <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-6">No production losses recorded.</TableCell></TableRow>
                    : rows.map((l) => (
                      <TableRow key={l.poultryProductionLossId}>
                        <TableCell>{(l.lossDate || "").split("T")[0]}</TableCell>
                        <TableCell className="font-medium">{l.productName ?? "—"}</TableCell>
                        <TableCell>{l.sourceType}{l.sourceId ? ` #${l.sourceId}` : ""}</TableCell>
                        <TableCell className="text-right">{l.quantityLost.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{l.estimatedValue != null ? gh(l.estimatedValue) : "—"}</TableCell>
                        <TableCell className="text-slate-500">{l.reason ?? "—"}</TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table>
            )}
          </CardContent></Card>
        </main>
      </div>
    </div>
  )
}

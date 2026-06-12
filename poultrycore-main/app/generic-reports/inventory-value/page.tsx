"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, Boxes, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getInventoryValueReport, type GenericInventoryValueReport } from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

export default function InventoryValuePage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [report, setReport] = useState<GenericInventoryValueReport | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const data = await getInventoryValueReport()
        if (!cancelled) setReport(data)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

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
            <Boxes className="h-6 w-6 text-orange-600" /> Inventory value
          </h1>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !report ? null : (
            <>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-4">
                <Stat title="Total cost value"   value={fmt(report.totalCostValue)} />
                <Stat title="Total retail value" value={fmt(report.totalRetailValue)} accent="emerald" />
                <Stat title="Products"           value={report.productCount.toString()} />
              </div>

              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-base">By category</CardTitle></CardHeader>
                <CardContent className="p-0">
                  {report.byCategory.length === 0 ? (
                    <p className="text-slate-500 text-sm p-4">No tracked products.</p>
                  ) : (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Category</TableHead>
                          <TableHead className="text-right">Products</TableHead>
                          <TableHead className="text-right">Units</TableHead>
                          <TableHead className="text-right">Cost value</TableHead>
                          <TableHead className="text-right">Retail value</TableHead>
                          <TableHead className="text-right">Potential margin</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {report.byCategory.map((r, i) => (
                          <TableRow key={r.genericProductCategoryId ?? `row-${i}`}>
                            <TableCell className="font-medium">{r.categoryName}</TableCell>
                            <TableCell className="text-right">{r.productCount}</TableCell>
                            <TableCell className="text-right">{r.totalUnits}</TableCell>
                            <TableCell className="text-right">{fmt(r.totalCostValue)}</TableCell>
                            <TableCell className="text-right">{fmt(r.totalRetailValue)}</TableCell>
                            <TableCell className="text-right text-emerald-700 font-semibold">{fmt(r.totalRetailValue - r.totalCostValue)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  )}
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

function Stat({ title, value, accent = "slate" }: { title: string; value: string; accent?: "slate" | "emerald" }) {
  return (
    <Card>
      <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">{title}</CardTitle></CardHeader>
      <CardContent><div className={`text-2xl font-semibold ${accent === "emerald" ? "text-emerald-700" : "text-slate-900"}`}>{value}</div></CardContent>
    </Card>
  )
}

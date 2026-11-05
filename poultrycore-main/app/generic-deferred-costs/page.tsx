"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { useIsMobile } from "@/hooks/use-mobile"
import { Timer, Loader2, ChevronDown, Package, TrendingUp, TrendingDown } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { getDeferredCosts, type GenericDeferredCost } from "@/lib/api/generic"

export default function GenericDeferredCostsPage() {
  const isMobile = useIsMobile()
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [rows, setRows] = useState<GenericDeferredCost[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setRows(await getDeferredCosts()) }
    catch (e: any) { toast({ title: "Could not load", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const totals = useMemo(() => {
    let purchased = 0, sold = 0, deferred = 0
    for (const r of rows) { purchased += r.totalPurchased; sold += r.totalSoldCost; deferred += r.deferredBalance }
    return { purchased, sold, deferred, count: rows.length }
  }, [rows])

  function pct(row: GenericDeferredCost) {
    if (row.totalPurchased === 0) return 0
    return Math.min(100, Math.round((row.totalSoldCost / row.totalPurchased) * 100))
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div>
            <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
              <Timer className="h-5 w-5 text-emerald-600" /> Deferred Inventory Cost
            </h1>
            <p className="text-xs text-slate-500">
              Purchase costs held on the balance sheet until the product is sold.
            </p>
          </div>

          <Collapsible defaultOpen={!isMobile} className="group rounded-lg border border-slate-200 bg-white">
            <CollapsibleTrigger asChild>
              <button type="button" className="flex w-full items-start justify-between gap-2 p-3 text-left">
                <span className="text-sm font-medium text-slate-900">What is deferred inventory cost?</span>
                <ChevronDown className="mt-0.5 h-4 w-4 shrink-0 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <p className="px-3 pb-3 text-xs leading-snug text-slate-600">
                When you buy inventory, the cost is not immediately an expense — it sits on your balance
                sheet as an asset. As you sell the product, the cost moves to your{" "}
                <Link href="/generic-profit-loss" className="underline">Profit &amp; Loss</Link> as
                &ldquo;Cost of Goods Sold&rdquo;. The deferred balance is what you have bought but not yet sold.
              </p>
            </CollapsibleContent>
          </Collapsible>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><TrendingUp className="h-3.5 w-3.5" /> Total Purchased</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{gh(totals.purchased)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><TrendingDown className="h-3.5 w-3.5" /> Cost Recognised</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{gh(totals.sold)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><Timer className="h-3.5 w-3.5" /> Deferred Balance</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-amber-700">{gh(totals.deferred)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500"><Package className="h-3.5 w-3.5" /> Products</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{totals.count}</div>
            </CardContent></Card>
          </div>

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600"><Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading…</CardContent></Card>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-slate-500">No deferred costs — no inventory purchases with cost tracking found.</CardContent></Card>
          ) : (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">By Product</CardTitle>
                <CardDescription className="text-xs">Sorted by deferred balance, highest first.</CardDescription>
              </CardHeader>
              <CardContent className="p-0 md:p-2">
                <MobileCardList defaultOpen striped stripeAccent="blue"
                  items={rows}
                  getKey={(r: any) => r.genericProductId}
                  primary={(r: any) => r.productName}
                  secondary={(r: any) => `${pct(r)}% recognised`}
                  highlights={(r: any) => [
                    { label: "Purchased", value: gh(r.totalPurchased), accent: "blue" },
                    { label: "Deferred", value: gh(r.deferredBalance), accent: r.deferredBalance > 0 ? "rose" : "emerald" },
                  ]}
                  details={(r: any) => [
                    { label: "Sold cost", value: gh(r.totalSoldCost) },
                    { label: "Stock", value: String(r.currentStock) },
                    { label: "Recognition", value: `${pct(r)}%` },
                  ]}
                  desktopTable={
                    <div className="overflow-x-auto"><Table>
                      <TableHeader><TableRow>
                        <TableHead>Product</TableHead>
                        <TableHead className="text-right">Total Purchased</TableHead>
                        <TableHead className="text-right">Cost Recognised</TableHead>
                        <TableHead className="text-right">Deferred Balance</TableHead>
                        <TableHead className="text-right">Stock</TableHead>
                        <TableHead>Recognition</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {rows.map((r) => {
                          const p = pct(r)
                          return (
                            <TableRow key={r.genericProductId}>
                              <TableCell className="font-medium">{r.productName}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.totalPurchased)}</TableCell>
                              <TableCell className="text-right tabular-nums text-emerald-700">{gh(r.totalSoldCost)}</TableCell>
                              <TableCell className={cn("text-right tabular-nums font-semibold", r.deferredBalance > 0 ? "text-amber-700" : "text-emerald-700")}>{gh(r.deferredBalance)}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.currentStock}</TableCell>
                              <TableCell>
                                <div className="flex items-center gap-2">
                                  <div className="h-2 flex-1 rounded-full bg-slate-100 overflow-hidden">
                                    <div className={cn("h-full rounded-full", p >= 80 ? "bg-emerald-500" : p >= 40 ? "bg-amber-400" : "bg-red-400")} style={{ width: `${p}%` }} />
                                  </div>
                                  <span className="text-xs tabular-nums text-slate-500 w-8 text-right">{p}%</span>
                                </div>
                              </TableCell>
                            </TableRow>
                          )
                        })}
                        <TableRow className="bg-slate-50 font-semibold">
                          <TableCell>Total</TableCell>
                          <TableCell className="text-right tabular-nums">{gh(totals.purchased)}</TableCell>
                          <TableCell className="text-right tabular-nums text-emerald-700">{gh(totals.sold)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{gh(totals.deferred)}</TableCell>
                          <TableCell></TableCell><TableCell></TableCell>
                        </TableRow>
                      </TableBody>
                    </Table></div>
                  }
                />
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

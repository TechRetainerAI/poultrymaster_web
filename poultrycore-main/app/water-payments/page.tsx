"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Loader2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listWaterPayments, type WaterPayment } from "@/lib/api/water"

export default function WaterPaymentsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const [items, setItems] = useState<WaterPayment[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleItems = useMemo(
    () => filterByDateAndSearch(items, {
      search, dateFrom, dateTo,
      searchKeys: ["customerName", "paymentMethod", "reference", "note"],
      dateKey: "paymentDate",
    }),
    [items, search, dateFrom, dateTo],
  )

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try { const list = await listWaterPayments(); if (!cancelled) setItems(list) }
      catch (e: any) { if (!cancelled) toast({ title: "Could not load payments", description: e?.message ?? String(e), variant: "destructive" }) }
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

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search customer, method, reference or note"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No payments yet.</div>
              ) : (
                <MobileCardList
                  items={visibleItems}
                  getKey={(p) => p.waterPaymentId}
                  primary={(p) => `${p.customerName ?? "Walk-in"} · ${p.amount.toFixed(2)}`}
                  secondary={(p) => (
                    <>
                      <span>{new Date(p.paymentDate).toLocaleString()}</span>
                      <span>·</span>
                      <span>Sale #{p.waterSaleId}</span>
                    </>
                  )}
                  details={(p) => [
                    { label: "Date", value: new Date(p.paymentDate).toLocaleString() },
                    { label: "Sale #", value: `#${p.waterSaleId}` },
                    { label: "Customer", value: p.customerName ?? "Walk-in" },
                    { label: "Amount", value: p.amount.toFixed(2) },
                    { label: "Method", value: p.paymentMethod ?? "—" },
                    { label: "Reference", value: p.reference ?? "—" },
                    { label: "Note", value: p.note ?? "—" },
                  ]}
                  desktopTable={
                    <div className="overflow-x-auto">
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
                        {visibleItems.map((p) => (
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
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}

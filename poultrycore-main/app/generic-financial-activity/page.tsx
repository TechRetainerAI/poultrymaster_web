"use client"

// Generic Financial Activity — combined view of sales, expenses, and purchases
// for a period. Shows a timeline of all financial events.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Loader2, Activity, ShoppingCart, DollarSign, Package } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  getSales, getExpenses, getPurchases,
  type GenericSale, type GenericExpense, type GenericPurchase,
} from "@/lib/api/generic"

interface FinancialEvent {
  id: string
  date: string
  type: "Sale" | "Expense" | "Purchase"
  description: string
  amount: number
  status: string
  direction: "in" | "out"
}

function defaultRange() {
  const now = new Date()
  const y = now.getFullYear(), m = now.getMonth()
  return {
    from: new Date(y, m, 1).toISOString().slice(0, 10),
    to: now.toISOString().slice(0, 10),
  }
}

export default function GenericFinancialActivityPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [loading, setLoading] = useState(true)
  const [events, setEvents] = useState<FinancialEvent[]>([])
  const [search, setSearch] = useState("")
  const [range, setRange] = useState(defaultRange)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [sales, expenses, purchases] = await Promise.all([
        getSales(null).catch(() => []),
        getExpenses(null).catch(() => []),
        getPurchases(null).catch(() => []),
      ])

      const all: FinancialEvent[] = [
        ...sales.map((s: GenericSale) => ({
          id: `sale-${s.genericSaleId}`,
          date: s.saleDate,
          type: "Sale" as const,
          description: `Sale #${s.genericSaleId} · ${s.customerName ?? "Walk-in"}`,
          amount: s.totalAmount,
          status: s.status,
          direction: "in" as const,
        })),
        ...expenses.map((e: GenericExpense) => ({
          id: `exp-${e.genericExpenseId}`,
          date: e.expenseDate,
          type: "Expense" as const,
          description: `${e.categoryName ?? "Expense"} · ${e.description ?? ""}`.trim(),
          amount: e.amount,
          status: e.status,
          direction: "out" as const,
        })),
        ...purchases.map((p: GenericPurchase) => ({
          id: `pur-${p.genericPurchaseId}`,
          date: p.purchaseDate,
          type: "Purchase" as const,
          description: `Purchase #${p.genericPurchaseId} · ${p.supplierName ?? "No supplier"}`,
          amount: p.totalAmount,
          status: p.status,
          direction: "out" as const,
        })),
      ]

      // Sort by date descending
      all.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
      setEvents(all)
    } catch (e: any) {
      toast({ title: "Could not load activity", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  const filtered = useMemo(() => {
    return filterByDateAndSearch(events, {
      search, dateFrom: range.from, dateTo: range.to,
      searchKeys: ["description", "type", "status"],
      dateKey: "date",
    })
  }, [events, search, range.from, range.to])

  const pg = usePagination(filtered)

  const totals = useMemo(() => {
    const inAmt = filtered.filter((e) => e.direction === "in" && e.status === "Approved").reduce((s, e) => s + e.amount, 0)
    const outAmt = filtered.filter((e) => e.direction === "out" && e.status === "Approved").reduce((s, e) => s + e.amount, 0)
    return { in: inAmt, out: outAmt, net: inAmt - outAmt, count: filtered.length }
  }, [filtered])

  const typeBadge = (type: string) => {
    switch (type) {
      case "Sale": return <Badge className="bg-emerald-100 text-emerald-800"><ShoppingCart className="w-3 h-3 mr-1" />Sale</Badge>
      case "Expense": return <Badge className="bg-red-100 text-red-800"><DollarSign className="w-3 h-3 mr-1" />Expense</Badge>
      case "Purchase": return <Badge className="bg-orange-100 text-orange-800"><Package className="w-3 h-3 mr-1" />Purchase</Badge>
      default: return <Badge>{type}</Badge>
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div>
            <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
              <Activity className="h-6 w-6 text-emerald-600" /> Financial Activity
            </h1>
            <p className="text-sm text-slate-500">All sales, expenses, and purchases in one timeline.</p>
          </div>

          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <div className="rounded-xl border bg-white p-3 shadow-sm">
              <div className="text-[11px] font-medium uppercase text-slate-500">Transactions</div>
              <div className="mt-1 text-xl font-bold">{totals.count}</div>
            </div>
            <div className="rounded-xl border bg-white p-3 shadow-sm">
              <div className="text-[11px] font-medium uppercase text-slate-500">Money in</div>
              <div className="mt-1 text-xl font-bold text-emerald-700 tabular-nums">{gh(totals.in)}</div>
            </div>
            <div className="rounded-xl border bg-white p-3 shadow-sm">
              <div className="text-[11px] font-medium uppercase text-slate-500">Money out</div>
              <div className="mt-1 text-xl font-bold text-red-600 tabular-nums">{gh(totals.out)}</div>
            </div>
            <div className={cn("rounded-xl border bg-white p-3 shadow-sm", totals.net >= 0 ? "border-emerald-200" : "border-red-200")}>
              <div className="text-[11px] font-medium uppercase text-slate-500">Net</div>
              <div className={cn("mt-1 text-xl font-bold tabular-nums", totals.net >= 0 ? "text-emerald-700" : "text-red-600")}>{gh(totals.net)}</div>
            </div>
          </div>

          <ListFilters search={search} setSearch={setSearch}
            dateFrom={range.from} setDateFrom={(v) => setRange((r) => ({ ...r, from: v }))}
            dateTo={range.to} setDateTo={(v) => setRange((r) => ({ ...r, to: v }))}
            searchPlaceholder="Search description, type or status" />

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead>Description</TableHead>
                      <TableHead className="text-right">Amount</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.length === 0 ? (
                      <TableRow><TableCell colSpan={5} className="text-center text-slate-500 py-8">No financial activity found.</TableCell></TableRow>
                    ) : pg.pageItems.map((e) => (
                      <TableRow key={e.id}>
                        <TableCell className="whitespace-nowrap text-sm">{fmtDateTime(e.date, e)}</TableCell>
                        <TableCell>{typeBadge(e.type)}</TableCell>
                        <TableCell className="text-sm">{e.description}</TableCell>
                        <TableCell className={cn("text-right tabular-nums font-medium", e.direction === "in" ? "text-emerald-700" : "text-red-600")}>
                          {e.direction === "in" ? "+" : "-"}{gh(e.amount)}
                        </TableCell>
                        <TableCell>
                          <Badge className={e.status === "Approved" ? "bg-emerald-100 text-emerald-800" : e.status === "Cancelled" ? "bg-rose-100 text-rose-800" : "bg-slate-100 text-slate-800"}>
                            {e.status}
                          </Badge>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
          <DataPagination {...pg.paginationProps} />
        </main>
      </div>
    </div>
  )
}

"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Check, DollarSign, Loader2, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { approveExpense, getExpenses, type GenericExpense } from "@/lib/api/generic"

const STATUS_FILTERS = ["All", "Draft", "Approved", "Rejected"] as const

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function badgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Rejected":  return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Submitted": return "bg-sky-100 text-sky-800 hover:bg-sky-100"
    case "Cancelled": return "bg-slate-100 text-slate-700 hover:bg-slate-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

function GenericExpensesPageInner() {
  const router = useRouter()
  const search = useSearchParams()
  const status = search.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericExpense[]>([])
  const [loading, setLoading] = useState(true)

  const load = async () => {
    setLoading(true)
    try { setRows(await getExpenses(status === "All" ? null : status)) }
    catch (e: any) { toast({ title: "Could not load expenses", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, status])

  const onApprove = async (id: number) => {
    try {
      await approveExpense(id)
      toast({ title: `Expense #${id} approved.` })
      await load()
    } catch (e: any) {
      toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <DollarSign className="h-6 w-6 text-amber-600" /> Expenses
              </h1>
              <p className="text-sm text-slate-500">{rows.length} expense(s)</p>
            </div>
            <Button asChild><Link href="/generic-expenses/new"><Plus className="h-4 w-4 mr-1" />New expense</Link></Button>
          </div>

          <div className="flex gap-1 mb-3 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={s === status ? "default" : "outline"}
                onClick={() => router.replace(s === "All" ? "/generic-expenses" : `/generic-expenses?status=${s}`)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No expenses yet.</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>#</TableHead>
                      <TableHead>Date</TableHead>
                      <TableHead>Category</TableHead>
                      <TableHead>Description</TableHead>
                      <TableHead>Supplier</TableHead>
                      <TableHead>Paid via</TableHead>
                      <TableHead className="text-right">Amount</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((e) => (
                      <TableRow key={e.genericExpenseId}>
                        <TableCell>#{e.genericExpenseId}</TableCell>
                        <TableCell>{new Date(e.expenseDate).toLocaleDateString()}</TableCell>
                        <TableCell>{e.categoryName ?? "–"}</TableCell>
                        <TableCell>{e.description ?? "–"}</TableCell>
                        <TableCell>{e.supplierName ?? "–"}</TableCell>
                        <TableCell className="text-xs text-slate-500">{e.paymentMethod}</TableCell>
                        <TableCell className="text-right">{fmt(e.amount)}</TableCell>
                        <TableCell><Badge className={badgeClass(e.status)}>{e.status}</Badge></TableCell>
                        <TableCell>
                          {(e.status === "Draft" || e.status === "Submitted") && (
                            <Button size="sm" variant="default" className="bg-emerald-600 hover:bg-emerald-700" onClick={() => onApprove(e.genericExpenseId)}>
                              <Check className="h-3 w-3 mr-1" />Approve
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

export default function GenericExpensesPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericExpensesPageInner />
    </Suspense>
  )
}

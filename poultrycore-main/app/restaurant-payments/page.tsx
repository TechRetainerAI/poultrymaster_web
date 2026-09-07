"use client"

import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Loader2, DollarSign, TrendingUp, TrendingDown, ArrowUpDown, Search } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listOrders, listExpenses, type Order, type RestaurantExpense } from "@/lib/api/restaurant"

export default function RestaurantPaymentsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [loading, setLoading] = useState(true)
  const [orders, setOrders] = useState<Order[]>([])
  const [expenses, setExpenses] = useState<RestaurantExpense[]>([])
  const [fromDate, setFromDate] = useState(new Date(new Date().setDate(1)).toISOString().slice(0, 10))
  const [toDate, setToDate] = useState(new Date().toISOString().slice(0, 10))
  const [search, setSearch] = useState("")

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [o, e] = await Promise.all([
        listOrders(undefined, undefined, fromDate, toDate),
        listExpenses(fromDate, toDate),
      ])
      setOrders(o); setExpenses(e)
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  const paidOrders = useMemo(() => orders.filter(o => o.paymentStatus === "Paid" && o.status !== "Cancelled" && o.status !== "Refunded"), [orders])
  const totalIncome = paidOrders.reduce((s, o) => s + o.totalAmount, 0)
  const totalTips = paidOrders.reduce((s, o) => s + (o.paidAmount - o.totalAmount > 0 ? o.paidAmount - o.totalAmount : 0), 0)
  const totalExpenses = expenses.reduce((s, e) => s + (e.amount ?? 0), 0)
  const netProfit = totalIncome - totalExpenses

  const filteredOrders = useMemo(() => {
    if (!search) return paidOrders
    const q = search.toLowerCase()
    return paidOrders.filter(o => o.orderNumber.toLowerCase().includes(q) || (o.customerName ?? "").toLowerCase().includes(q))
  }, [paidOrders, search])

  const filteredExpenses = useMemo(() => {
    if (!search) return expenses
    const q = search.toLowerCase()
    return expenses.filter(e => (e.description ?? "").toLowerCase().includes(q) || (e.supplierName ?? "").toLowerCase().includes(q) || (e.categoryName ?? "").toLowerCase().includes(q))
  }, [expenses, search])

  // Group income by payment method
  const byMethod = useMemo(() => {
    const map: Record<string, number> = {}
    paidOrders.forEach(o => {
      const method = "Orders"
      map[method] = (map[method] || 0) + o.totalAmount
    })
    return map
  }, [paidOrders])

  // Group expenses by category
  const byCategory = useMemo(() => {
    const map: Record<string, number> = {}
    expenses.forEach(e => {
      const cat = e.categoryName || "Uncategorized"
      map[cat] = (map[cat] || 0) + (e.amount ?? 0)
    })
    return map
  }, [expenses])

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center"><DollarSign className="h-5 w-5 text-rose-600" /></div>
              <div>
                <h1 className="text-2xl font-bold text-gray-900">Income & Expenses</h1>
                <p className="text-sm text-muted-foreground">Financial overview — where money comes in and goes out</p>
              </div>
            </div>
          </div>

          {/* Date Range */}
          <div className="flex gap-3 items-end mb-4 flex-wrap">
            <div><Label className="text-xs">From</Label><Input type="date" value={fromDate} onChange={e => setFromDate(e.target.value)} className="w-40" /></div>
            <div><Label className="text-xs">To</Label><Input type="date" value={toDate} onChange={e => setToDate(e.target.value)} className="w-40" /></div>
            <Button onClick={load} className="bg-rose-600 hover:bg-rose-700">Apply</Button>
            <div className="relative ml-auto"><Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" /><Input placeholder="Search..." className="pl-8 w-[200px]" value={search} onChange={e => setSearch(e.target.value)} /></div>
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-rose-600" /></div>
          ) : (
            <>
              {/* Summary Cards */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <Card className="border-green-200">
                  <CardContent className="p-4 text-center">
                    <TrendingUp className="h-5 w-5 text-green-600 mx-auto mb-1" />
                    <div className="text-2xl font-bold text-green-700">{totalIncome.toFixed(2)}</div>
                    <div className="text-xs text-muted-foreground">Total Income</div>
                    <div className="text-xs text-green-600">{paidOrders.length} paid orders</div>
                  </CardContent>
                </Card>
                <Card className="border-red-200">
                  <CardContent className="p-4 text-center">
                    <TrendingDown className="h-5 w-5 text-red-600 mx-auto mb-1" />
                    <div className="text-2xl font-bold text-red-700">{totalExpenses.toFixed(2)}</div>
                    <div className="text-xs text-muted-foreground">Total Expenses</div>
                    <div className="text-xs text-red-600">{expenses.length} entries</div>
                  </CardContent>
                </Card>
                <Card className={netProfit >= 0 ? "border-emerald-200" : "border-red-200"}>
                  <CardContent className="p-4 text-center">
                    <ArrowUpDown className={`h-5 w-5 mx-auto mb-1 ${netProfit >= 0 ? "text-emerald-600" : "text-red-600"}`} />
                    <div className={`text-2xl font-bold ${netProfit >= 0 ? "text-emerald-700" : "text-red-700"}`}>{netProfit.toFixed(2)}</div>
                    <div className="text-xs text-muted-foreground">Net {netProfit >= 0 ? "Profit" : "Loss"}</div>
                    <div className={`text-xs ${netProfit >= 0 ? "text-emerald-600" : "text-red-600"}`}>
                      {totalIncome > 0 ? ((netProfit / totalIncome) * 100).toFixed(1) : "0"}% margin
                    </div>
                  </CardContent>
                </Card>
                <Card className="border-amber-200">
                  <CardContent className="p-4 text-center">
                    <DollarSign className="h-5 w-5 text-amber-600 mx-auto mb-1" />
                    <div className="text-2xl font-bold text-amber-700">{totalTips.toFixed(2)}</div>
                    <div className="text-xs text-muted-foreground">Tips Received</div>
                  </CardContent>
                </Card>
              </div>

              {/* Breakdown */}
              <div className="grid md:grid-cols-2 gap-4 mb-6">
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-sm text-green-700">Income Breakdown</CardTitle></CardHeader>
                  <CardContent className="space-y-1">
                    {Object.entries(byMethod).map(([k, v]) => (
                      <div key={k} className="flex justify-between text-sm"><span>{k}</span><span className="font-semibold text-green-700">{v.toFixed(2)}</span></div>
                    ))}
                    {Object.keys(byMethod).length === 0 && <p className="text-sm text-muted-foreground">No income in this period</p>}
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-sm text-red-700">Expense Breakdown</CardTitle></CardHeader>
                  <CardContent className="space-y-1">
                    {Object.entries(byCategory).sort((a, b) => b[1] - a[1]).map(([k, v]) => (
                      <div key={k} className="flex justify-between text-sm"><span>{k}</span><span className="font-semibold text-red-700">{v.toFixed(2)}</span></div>
                    ))}
                    {Object.keys(byCategory).length === 0 && <p className="text-sm text-muted-foreground">No expenses in this period</p>}
                  </CardContent>
                </Card>
              </div>

              {/* Detailed Tables */}
              <Tabs defaultValue="income">
                <TabsList className="mb-4">
                  <TabsTrigger value="income">Income ({filteredOrders.length})</TabsTrigger>
                  <TabsTrigger value="expenses">Expenses ({filteredExpenses.length})</TabsTrigger>
                </TabsList>

                <TabsContent value="income">
                  <Card>
                    <CardContent className="p-0">
                      <table className="w-full text-sm">
                        <thead className="bg-gray-50 border-b">
                          <tr>
                            <th className="text-left p-3">Date</th>
                            <th className="text-left p-3">Order #</th>
                            <th className="text-left p-3">Customer</th>
                            <th className="text-left p-3">Type</th>
                            <th className="text-right p-3">Amount</th>
                            <th className="text-right p-3">Paid</th>
                            <th className="text-left p-3">Status</th>
                          </tr>
                        </thead>
                        <tbody>
                          {filteredOrders.map(o => (
                            <tr key={o.orderId} className="border-b hover:bg-green-50">
                              <td className="p-3 text-xs">{o.createdAt?.slice(0, 10)}</td>
                              <td className="p-3 font-mono font-semibold">{o.orderNumber}</td>
                              <td className="p-3">{o.customerName || "Walk-in"}</td>
                              <td className="p-3"><Badge variant="outline" className="text-xs">{o.orderType}</Badge></td>
                              <td className="p-3 text-right">{o.totalAmount.toFixed(2)}</td>
                              <td className="p-3 text-right font-semibold text-green-700">{o.paidAmount.toFixed(2)}</td>
                              <td className="p-3"><Badge className="bg-green-100 text-green-700 text-xs">{o.paymentStatus}</Badge></td>
                            </tr>
                          ))}
                          {filteredOrders.length === 0 && <tr><td colSpan={7} className="p-8 text-center text-muted-foreground">No paid orders in this period.</td></tr>}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                </TabsContent>

                <TabsContent value="expenses">
                  <Card>
                    <CardContent className="p-0">
                      <table className="w-full text-sm">
                        <thead className="bg-gray-50 border-b">
                          <tr>
                            <th className="text-left p-3">Date</th>
                            <th className="text-left p-3">Description</th>
                            <th className="text-left p-3">Category</th>
                            <th className="text-left p-3">Supplier</th>
                            <th className="text-left p-3">Payment</th>
                            <th className="text-right p-3">Amount</th>
                          </tr>
                        </thead>
                        <tbody>
                          {filteredExpenses.map((exp: any) => (
                            <tr key={exp.expenseId} className="border-b hover:bg-red-50">
                              <td className="p-3 text-xs">{exp.expenseDate?.split("T")[0]}</td>
                              <td className="p-3 font-medium">{exp.description}</td>
                              <td className="p-3"><Badge variant="secondary" className="text-xs bg-rose-50 text-rose-700">{exp.categoryName || "—"}</Badge></td>
                              <td className="p-3 text-xs">{exp.supplierName || "—"}</td>
                              <td className="p-3"><Badge variant="outline" className="text-xs">{exp.paymentMethod || "—"}</Badge></td>
                              <td className="p-3 text-right font-semibold text-red-700">{(exp.amount ?? 0).toFixed(2)}</td>
                            </tr>
                          ))}
                          {filteredExpenses.length === 0 && <tr><td colSpan={6} className="p-8 text-center text-muted-foreground">No expenses in this period.</td></tr>}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                </TabsContent>
              </Tabs>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, BarChart3, TrendingUp, TrendingDown } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listDailyClosings, listHotelBookings, listHotelPayments, listHotelExpenses, listHotelStaff, type HotelDailyClosing } from "@/lib/api/hotel"
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line, Legend } from "recharts"

export default function HotelReportsPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [closings, setClosings] = useState<HotelDailyClosing[]>([]); const [loading, setLoading] = useState(true)
  const [totalBookings, setTotalBookings] = useState(0); const [totalPayments, setTotalPayments] = useState(0)
  const [totalExpenses, setTotalExpenses] = useState(0); const [staffCount, setStaffCount] = useState(0)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() {
    setLoading(true)
    try {
      const [c, b, p, e, s] = await Promise.all([listDailyClosings(), listHotelBookings(), listHotelPayments(), listHotelExpenses(), listHotelStaff()])
      setClosings(c); setTotalBookings(b.length)
      setTotalPayments(p.reduce((s: number, x: any) => s + Number(x.amount ?? 0), 0))
      setTotalExpenses(e.reduce((s: number, x: any) => s + Number(x.amount ?? 0), 0))
      setStaffCount(s.length)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // Chart data from daily closings
  const chartData = closings.slice(0, 30).reverse().map((c: any) => ({
    date: (c.closingDate ?? c.closingdate)?.slice?.(5, 10) ?? "",
    revenue: Number(c.totalRevenue ?? c.totalrevenue ?? 0),
    expenses: Number(c.totalExpenses ?? c.totalexpenses ?? 0),
    occupancy: Number(c.occupancyRate ?? c.occupancyrate ?? 0),
    adr: Number(c.adr ?? 0),
    revpar: Number(c.revPar ?? c.revpar ?? 0),
  }))

  const totalRev = closings.reduce((s: number, c: any) => s + Number(c.totalRevenue ?? c.totalrevenue ?? 0), 0)
  const totalExp = closings.reduce((s: number, c: any) => s + Number(c.totalExpenses ?? c.totalexpenses ?? 0), 0)
  const avgOcc = closings.length > 0 ? closings.reduce((s: number, c: any) => s + Number(c.occupancyRate ?? c.occupancyrate ?? 0), 0) / closings.length : 0
  const avgAdr = closings.length > 0 ? closings.reduce((s: number, c: any) => s + Number(c.adr ?? 0), 0) / closings.length : 0

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><BarChart3 className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Reports & Analytics</h1></div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <>
            {/* KPI Cards */}
            <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3 mb-6">
              <Card><CardContent className="p-3 text-center"><div className="text-xl font-bold text-emerald-700">GH₵{totalRev.toFixed(0)}</div><div className="text-xs text-slate-500">Total Revenue</div></CardContent></Card>
              <Card><CardContent className="p-3 text-center"><div className="text-xl font-bold text-red-700">GH₵{totalExp.toFixed(0)}</div><div className="text-xs text-slate-500">Total Expenses</div></CardContent></Card>
              <Card><CardContent className="p-3 text-center"><div className={`text-xl font-bold ${totalRev - totalExp >= 0 ? "text-emerald-700" : "text-red-700"}`}>GH₵{(totalRev - totalExp).toFixed(0)}</div><div className="text-xs text-slate-500">Net Profit</div></CardContent></Card>
              <Card><CardContent className="p-3 text-center"><div className="text-xl font-bold text-violet-700">{avgOcc.toFixed(1)}%</div><div className="text-xs text-slate-500">Avg Occupancy</div></CardContent></Card>
              <Card><CardContent className="p-3 text-center"><div className="text-xl font-bold text-violet-700">GH₵{avgAdr.toFixed(0)}</div><div className="text-xs text-slate-500">Avg ADR</div></CardContent></Card>
              <Card><CardContent className="p-3 text-center"><div className="text-xl font-bold text-blue-700">{totalBookings}</div><div className="text-xs text-slate-500">Total Bookings</div></CardContent></Card>
            </div>

            {/* Revenue vs Expenses Chart */}
            {chartData.length > 0 && (
              <Card className="mb-6">
                <CardHeader><CardTitle className="text-base flex items-center gap-2"><TrendingUp className="h-5 w-5 text-violet-600" />Revenue vs Expenses</CardTitle></CardHeader>
                <CardContent>
                  <ResponsiveContainer width="100%" height={300}>
                    <BarChart data={chartData}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                      <XAxis dataKey="date" tick={{ fontSize: 12 }} />
                      <YAxis tick={{ fontSize: 12 }} />
                      <Tooltip formatter={(val: number) => `GH₵${val.toFixed(2)}`} />
                      <Legend />
                      <Bar dataKey="revenue" name="Revenue" fill="#7c3aed" radius={[4, 4, 0, 0]} />
                      <Bar dataKey="expenses" name="Expenses" fill="#ef4444" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </CardContent>
              </Card>
            )}

            {/* Occupancy Trend Chart */}
            {chartData.length > 0 && (
              <Card className="mb-6">
                <CardHeader><CardTitle className="text-base flex items-center gap-2"><TrendingUp className="h-5 w-5 text-emerald-600" />Occupancy & ADR Trend</CardTitle></CardHeader>
                <CardContent>
                  <ResponsiveContainer width="100%" height={250}>
                    <LineChart data={chartData}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                      <XAxis dataKey="date" tick={{ fontSize: 12 }} />
                      <YAxis yAxisId="left" tick={{ fontSize: 12 }} />
                      <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 12 }} />
                      <Tooltip />
                      <Legend />
                      <Line yAxisId="left" type="monotone" dataKey="occupancy" name="Occupancy %" stroke="#7c3aed" strokeWidth={2} dot={{ r: 3 }} />
                      <Line yAxisId="right" type="monotone" dataKey="adr" name="ADR (GH₵)" stroke="#10b981" strokeWidth={2} dot={{ r: 3 }} />
                    </LineChart>
                  </ResponsiveContainer>
                </CardContent>
              </Card>
            )}

            {chartData.length === 0 && (
              <Card className="mb-6"><CardContent className="p-12 text-center text-slate-400">No daily closing data yet. Close a day from the Daily Closing page to see charts.</CardContent></Card>
            )}

            {/* Daily Closing History */}
            <Card>
              <CardHeader><CardTitle className="text-base">Daily Closing History ({closings.length})</CardTitle></CardHeader>
              <CardContent className="p-0">
                <table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Date</th><th className="text-right p-3">Revenue</th><th className="text-right p-3">Expenses</th><th className="text-right p-3">Net</th><th className="text-right p-3">Occupancy</th><th className="text-right p-3">Rooms</th><th className="text-right p-3">ADR</th><th className="text-right p-3">RevPAR</th></tr></thead>
                  <tbody>{closings.map((c: any, idx: number) => {
                    const rev = Number(c.totalRevenue ?? c.totalrevenue ?? 0); const exp = Number(c.totalExpenses ?? c.totalexpenses ?? 0)
                    return (<tr key={c.hotelDailyClosingId ?? c.hoteldailyclosingid ?? `dc-${idx}`} className="border-b hover:bg-slate-50">
                      <td className="p-3 font-medium">{(c.closingDate ?? c.closingdate)?.slice?.(0, 10)}</td>
                      <td className="p-3 text-right text-emerald-700">GH₵{rev.toFixed(2)}</td>
                      <td className="p-3 text-right text-red-600">GH₵{exp.toFixed(2)}</td>
                      <td className={`p-3 text-right font-bold ${rev - exp >= 0 ? "text-emerald-700" : "text-red-700"}`}>GH₵{(rev - exp).toFixed(2)}</td>
                      <td className="p-3 text-right">{Number(c.occupancyRate ?? c.occupancyrate ?? 0).toFixed(1)}%</td>
                      <td className="p-3 text-right">{c.roomsOccupied ?? c.roomsoccupied ?? 0}/{c.totalRooms ?? c.totalrooms ?? 0}</td>
                      <td className="p-3 text-right">GH₵{Number(c.adr ?? 0).toFixed(2)}</td>
                      <td className="p-3 text-right">GH₵{Number(c.revPar ?? c.revpar ?? 0).toFixed(2)}</td>
                    </tr>)
                  })}
                    {closings.length === 0 && <tr><td colSpan={8} className="p-8 text-center text-slate-400">No closings yet.</td></tr>}
                  </tbody></table>
              </CardContent>
            </Card>

            {/* Footer stats */}
            <div className="mt-4 text-center text-xs text-slate-400">
              {staffCount} staff members | {totalBookings} total bookings | GH₵{totalPayments.toFixed(2)} collected
            </div>
          </>
        )}
      </main></div></div>
  )
}

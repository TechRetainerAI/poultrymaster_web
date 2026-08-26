"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Building2, DoorOpen, Users, Calendar, Loader2,
  TrendingUp, LogIn, LogOut, Sparkles, Wrench,
  Wallet, AlertTriangle, CreditCard, ShoppingCart,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getHotelRoomStatusSummary, listHotelBookings, listHotelPayments,
  listStayCharges, listHotelExpenses, listHotelStaff, listHousekeepingTasks,
  listMaintenanceRequests, listRestaurantOrders,
  type HotelRoomStatusSummary, type HotelBooking, type HotelPayment,
} from "@/lib/api/hotel"

function StatCard({ title, value, sub, icon: Icon, href, color = "violet" }: { title: string; value: string | number; sub?: string; icon: any; href?: string; color?: string }) {
  const colors: Record<string, string> = {
    violet: "bg-violet-50 text-violet-600 border-violet-200",
    emerald: "bg-emerald-50 text-emerald-600 border-emerald-200",
    blue: "bg-blue-50 text-blue-600 border-blue-200",
    amber: "bg-amber-50 text-amber-600 border-amber-200",
    orange: "bg-orange-50 text-orange-600 border-orange-200",
    red: "bg-red-50 text-red-600 border-red-200",
  }
  const content = (
    <Card className={`border ${colors[color] ?? colors.violet} hover:shadow-md transition-shadow`}>
      <CardContent className="p-4 flex items-center gap-4">
        <div className={`p-3 rounded-lg ${colors[color]}`}><Icon className="h-5 w-5" /></div>
        <div><div className="text-2xl font-bold">{value}</div><div className="text-sm text-slate-500">{title}</div>{sub && <div className="text-xs text-slate-400">{sub}</div>}</div>
      </CardContent>
    </Card>
  )
  return href ? <Link href={href}>{content}</Link> : content
}

export default function HotelDashboardPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const logout = useLogout()

  const [statusSummary, setStatusSummary] = useState<HotelRoomStatusSummary[]>([])
  const [bookings, setBookings] = useState<HotelBooking[]>([])
  const [payments, setPayments] = useState<HotelPayment[]>([])
  const [loading, setLoading] = useState(true)

  // Extra stats
  const [staffCount, setStaffCount] = useState(0)
  const [pendingHousekeeping, setPendingHousekeeping] = useState(0)
  const [openMaintenance, setOpenMaintenance] = useState(0)
  const [activeOrders, setActiveOrders] = useState(0)
  const [todayExpenses, setTodayExpenses] = useState(0)
  const [checkedInBalances, setCheckedInBalances] = useState<{ guest: string; room: string; balance: number; ref: string }[]>([])

  const [lastRefresh, setLastRefresh] = useState<string>("")

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    loadDashboard()
    // Auto-refresh every 30 seconds
    const interval = setInterval(() => { loadDashboard() }, 30000)
    return () => clearInterval(interval)
  }, [activeFarmType, router])

  async function loadDashboard() {
    setLoading(true)
    try {
      const [ss, allBookings, allPayments] = await Promise.all([
        getHotelRoomStatusSummary().catch(() => []),
        listHotelBookings().catch(() => []),
        listHotelPayments().catch(() => []),
      ])
      setStatusSummary(ss); setBookings(allBookings); setPayments(allPayments)

      // Load extra stats in parallel (non-blocking)
      const [staff, hk, maint, orders, expenses] = await Promise.all([
        listHotelStaff().catch(() => []),
        listHousekeepingTasks().catch(() => []),
        listMaintenanceRequests().catch(() => []),
        listRestaurantOrders().catch(() => []),
        listHotelExpenses().catch(() => []),
      ])
      setStaffCount(staff.length)
      setPendingHousekeeping(hk.filter((t: any) => t.status === "Pending" || t.Status === "Pending").length)
      setOpenMaintenance(maint.filter((m: any) => (m.status ?? m.Status) === "Open" || (m.status ?? m.Status) === "InProgress").length)
      setActiveOrders(orders.filter((o: any) => (o.status) === "Placed" || (o.status) === "Preparing").length)

      const today = new Date().toISOString().slice(0, 10)
      setTodayExpenses(expenses.filter((e: any) => (e.expenseDate ?? e.expensedate ?? "").slice(0, 10) === today).reduce((s: number, e: any) => s + Number(e.amount ?? 0), 0))

      // Build checked-in guest balances
      const checkedIn = allBookings.filter((b) => b.status === "CheckedIn")
      const balances: { guest: string; room: string; balance: number; ref: string }[] = []
      for (const b of checkedIn) {
        let charges = 0
        try { const c = await listStayCharges(b.hotelBookingId); charges = c.reduce((s: number, x: any) => s + Number(x.totalAmount ?? x.totalamount ?? 0), 0) } catch {}
        const paid = allPayments.filter((p: any) => (p.hotelBookingId ?? p.hotelbookingid) === b.hotelBookingId).reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
        const total = Number(b.totalAmount ?? 0) + charges
        balances.push({ guest: `${b.guestFirstName} ${b.guestLastName}`, room: b.roomNumber ?? "—", balance: total - paid, ref: b.bookingRef })
      }
      setCheckedInBalances(balances)

      setLastRefresh(new Date().toLocaleTimeString())
    } catch (e: any) {
      toast({ title: "Failed to load dashboard", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  const sc = (s: string) => statusSummary.find((x) => x.status === s)?.roomCount ?? 0
  const totalRooms = statusSummary.reduce((s, x) => s + x.roomCount, 0)
  const occupiedRooms = sc("Occupied")
  const occupancyRate = totalRooms > 0 ? Math.round((occupiedRooms / totalRooms) * 100) : 0

  const confirmedBookings = bookings.filter((b) => b.status === "Confirmed")
  const checkedInBookings = bookings.filter((b) => b.status === "CheckedIn")
  const todayArrivals = confirmedBookings.filter((b) => b.checkInDate?.slice(0, 10) === new Date().toISOString().slice(0, 10))
  const todayDepartures = checkedInBookings.filter((b) => b.checkOutDate?.slice(0, 10) === new Date().toISOString().slice(0, 10))

  const todayPayments = payments.filter((p: any) => (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10) === new Date().toISOString().slice(0, 10))
  const todayRevenue = todayPayments.reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
  const totalOutstanding = checkedInBalances.filter((b) => b.balance > 0).reduce((s, b) => s + b.balance, 0)
  const guestsOwing = checkedInBalances.filter((b) => b.balance > 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-3">
              <Building2 className="h-6 w-6 text-violet-600" />
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Hotel Dashboard</h1>
                <p className="text-sm text-slate-500">{activeFarmName} — {new Date().toLocaleDateString("en-GB", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}</p>
              </div>
            </div>
            <div className="text-right">
              {lastRefresh && <div className="text-xs text-slate-400">Auto-refreshes every 30s</div>}
              {lastRefresh && <div className="text-xs text-slate-500">Last: {lastRefresh}</div>}
            </div>
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <>
              {/* Row 1: Room Status */}
              <h2 className="text-sm font-semibold text-slate-400 uppercase tracking-wide mb-3">Room Status</h2>
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 mb-6">
                <StatCard title="Total Rooms" value={totalRooms} icon={DoorOpen} href="/hotel-rooms" color="violet" />
                <StatCard title="Available" value={sc("Available")} icon={DoorOpen} href="/hotel-rooms" color="emerald" />
                <StatCard title="Occupied" value={occupiedRooms} icon={Users} color="violet" />
                <StatCard title="Reserved" value={sc("Reserved")} icon={Calendar} href="/hotel-bookings" color="blue" />
                <StatCard title="Cleaning" value={sc("Cleaning")} icon={Sparkles} href="/hotel-housekeeping" color="orange" />
                <StatCard title="Maintenance" value={sc("Maintenance")} icon={Wrench} href="/hotel-maintenance" color="amber" />
              </div>

              {/* Row 2: Key Metrics */}
              <h2 className="text-sm font-semibold text-slate-400 uppercase tracking-wide mb-3">Today</h2>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
                <StatCard title="Occupancy Rate" value={`${occupancyRate}%`} icon={TrendingUp} color="violet" />
                <StatCard title="Today's Revenue" value={`GH₵${todayRevenue.toFixed(2)}`} icon={Wallet} href="/hotel-payments" color="emerald" sub={`${todayPayments.length} payment(s)`} />
                <StatCard title="Today's Expenses" value={`GH₵${todayExpenses.toFixed(2)}`} icon={Wallet} href="/hotel-expenses" color="red" />
                <StatCard title="Outstanding Balances" value={`GH₵${totalOutstanding.toFixed(2)}`} icon={AlertTriangle} href="/hotel-check-out" color={totalOutstanding > 0 ? "red" : "emerald"} sub={`${guestsOwing.length} guest(s) owe`} />
              </div>

              {/* Row 3: Operations */}
              <h2 className="text-sm font-semibold text-slate-400 uppercase tracking-wide mb-3">Operations</h2>
              <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
                <StatCard title="Arrivals Today" value={todayArrivals.length} icon={LogIn} href="/hotel-check-in" color="blue" />
                <StatCard title="Departures Today" value={todayDepartures.length} icon={LogOut} href="/hotel-check-out" color="amber" />
                <StatCard title="Pending Housekeeping" value={pendingHousekeeping} icon={Sparkles} href="/hotel-housekeeping" color={pendingHousekeeping > 0 ? "orange" : "emerald"} />
                <StatCard title="Active Orders" value={activeOrders} icon={ShoppingCart} href="/hotel-restaurant" color={activeOrders > 0 ? "amber" : "emerald"} />
                <StatCard title="Open Maintenance" value={openMaintenance} icon={Wrench} href="/hotel-maintenance" color={openMaintenance > 0 ? "red" : "emerald"} />
              </div>

              {/* Row 4: Detail panels */}
              <div className="grid md:grid-cols-2 gap-6 mb-6">
                {/* Checked-in guests with balances */}
                <Card>
                  <CardHeader><CardTitle className="flex items-center gap-2 text-base"><Users className="h-5 w-5 text-violet-600" /> In-House Guests ({checkedInBookings.length})</CardTitle></CardHeader>
                  <CardContent>
                    {checkedInBalances.length > 0 ? (
                      <div className="space-y-2">
                        {checkedInBalances.map((g, idx) => (
                          <div key={`guest-${idx}`} className="flex items-center justify-between p-2 rounded-lg bg-slate-50 border">
                            <div>
                              <div className="font-semibold text-sm">{g.guest}</div>
                              <div className="text-xs text-slate-400">Room {g.room} | {g.ref}</div>
                            </div>
                            {g.balance > 0
                              ? <Badge className="bg-red-100 text-red-700">Owes {g.balance.toFixed(2)}</Badge>
                              : <Badge className="bg-emerald-100 text-emerald-700">Paid</Badge>
                            }
                          </div>
                        ))}
                      </div>
                    ) : <div className="text-center py-6 text-slate-400 text-sm">No guests currently checked in</div>}
                  </CardContent>
                </Card>

                {/* Today's arrivals */}
                <Card>
                  <CardHeader><CardTitle className="flex items-center gap-2 text-base"><LogIn className="h-5 w-5 text-blue-600" /> Expected Arrivals ({todayArrivals.length})</CardTitle></CardHeader>
                  <CardContent>
                    {todayArrivals.length > 0 ? (
                      <div className="space-y-2">
                        {todayArrivals.map((a) => (
                          <div key={a.hotelBookingId} className="flex items-center justify-between p-2 rounded-lg bg-blue-50 border border-blue-100">
                            <div>
                              <div className="font-semibold text-sm">{a.guestFirstName} {a.guestLastName}</div>
                              <div className="text-xs text-slate-400">{a.roomTypeName} | {a.roomNumber ?? "Unassigned"}</div>
                            </div>
                            <Badge variant="outline" className="bg-blue-100 text-blue-700 text-xs">{a.bookingRef}</Badge>
                          </div>
                        ))}
                      </div>
                    ) : <div className="text-center py-6 text-slate-400 text-sm">No arrivals today</div>}
                  </CardContent>
                </Card>
              </div>

              {/* Row 5: Today's departures + recent payments */}
              <div className="grid md:grid-cols-2 gap-6">
                <Card>
                  <CardHeader><CardTitle className="flex items-center gap-2 text-base"><LogOut className="h-5 w-5 text-amber-600" /> Expected Departures ({todayDepartures.length})</CardTitle></CardHeader>
                  <CardContent>
                    {todayDepartures.length > 0 ? (
                      <div className="space-y-2">
                        {todayDepartures.map((d) => {
                          const gb = checkedInBalances.find((b) => b.ref === d.bookingRef)
                          return (
                            <div key={d.hotelBookingId} className="flex items-center justify-between p-2 rounded-lg bg-amber-50 border border-amber-100">
                              <div>
                                <div className="font-semibold text-sm">{d.guestFirstName} {d.guestLastName}</div>
                                <div className="text-xs text-slate-400">Room {d.roomNumber} | {Number(d.totalAmount ?? 0).toFixed(2)}</div>
                              </div>
                              {gb && gb.balance > 0
                                ? <Badge className="bg-red-100 text-red-700 text-xs">Owes {gb.balance.toFixed(2)}</Badge>
                                : <Badge className="bg-emerald-100 text-emerald-700 text-xs">Paid</Badge>
                              }
                            </div>
                          )
                        })}
                      </div>
                    ) : <div className="text-center py-6 text-slate-400 text-sm">No departures today</div>}
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader><CardTitle className="flex items-center gap-2 text-base"><CreditCard className="h-5 w-5 text-emerald-600" /> Recent Payments</CardTitle></CardHeader>
                  <CardContent>
                    {payments.length > 0 ? (
                      <div className="space-y-2">
                        {payments.slice(0, 6).map((p: any, idx: number) => (
                          <div key={p.hotelPaymentId ?? p.hotelpaymentid ?? `rp-${idx}`} className="flex items-center justify-between p-2 rounded-lg bg-emerald-50 border border-emerald-100">
                            <div>
                              <div className="font-semibold text-sm text-emerald-700">{Number(p.amount ?? 0).toFixed(2)}</div>
                              <div className="text-xs text-slate-400">{p.paymentMethod ?? p.paymentmethod} | {(p.paymentDate ?? p.paymentdate)?.slice?.(0, 10)}</div>
                            </div>
                            <span className="text-xs font-mono text-slate-400">{p.reference ?? "—"}</span>
                          </div>
                        ))}
                      </div>
                    ) : <div className="text-center py-6 text-slate-400 text-sm">No payments yet</div>}
                  </CardContent>
                </Card>
              </div>

              {/* Staff count footer */}
              <div className="mt-6 text-center text-xs text-slate-400">{staffCount} staff members registered</div>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

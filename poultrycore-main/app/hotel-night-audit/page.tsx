"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Loader2, Shield, Play, AlertTriangle, CheckCircle2,
  DoorOpen, DoorClosed, Users, Wrench, BedDouble, Wallet,
  TrendingUp, TrendingDown, ClipboardList
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  runNightAudit, listNightAudits,
  listHotelBookings, listHotelPayments, listHotelExpenses,
  getHotelRoomStatusSummary, listHousekeepingTasks, listMaintenanceRequests,
  type HotelNightAudit,
} from "@/lib/api/hotel"

export default function HotelNightAuditPage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [audits, setAudits] = useState<HotelNightAudit[]>([])
  const [loading, setLoading] = useState(true)
  const [running, setRunning] = useState(false)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [detailAudit, setDetailAudit] = useState<HotelNightAudit | null>(null)

  // Live pre-audit preview
  const [preview, setPreview] = useState({
    totalRooms: 0, occupied: 0, available: 0, revenue: 0, expenses: 0,
    checkedIn: 0, pendingCheckouts: 0, noshows: 0, pendingHousekeeping: 0, openMaintenance: 0,
    outstandingBalances: 0,
  })

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [auditList, roomStatus, bookings, payments, expenses, housekeeping, maintenance] = await Promise.all([
        listNightAudits().catch(() => []),
        getHotelRoomStatusSummary().catch(() => []),
        listHotelBookings().catch(() => []),
        listHotelPayments().catch(() => []),
        listHotelExpenses().catch(() => []),
        listHousekeepingTasks().catch(() => []),
        listMaintenanceRequests().catch(() => []),
      ])
      setAudits(auditList)

      const today = new Date().toISOString().slice(0, 10)
      const totalRooms = roomStatus.reduce((s: number, r: any) => s + (r.roomCount ?? r.RoomCount ?? 0), 0)
      const occupied = roomStatus.find((r: any) => (r.status ?? r.Status) === "Occupied")?.roomCount ?? 0
      const available = roomStatus.find((r: any) => (r.status ?? r.Status) === "Available")?.roomCount ?? 0

      const todayPayments = payments.filter((p: any) => (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10) === today)
      const todayExpenses = expenses.filter((e: any) => (e.expenseDate ?? e.expensedate ?? "").slice(0, 10) === today)
      const revenue = todayPayments.reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
      const expenseTotal = todayExpenses.reduce((s: number, e: any) => s + Number(e.amount ?? 0), 0)

      const checkedInBookings = bookings.filter((b) => b.status === "CheckedIn")
      const pendingCheckouts = bookings.filter((b) => b.checkOutDate?.slice(0, 10) === today && b.status === "CheckedIn").length
      const noshows = bookings.filter((b) => b.checkInDate?.slice(0, 10) === today && b.status === "Confirmed").length
      const pendingHousekeeping = housekeeping.filter((h: any) => (h.status ?? h.Status) === "Pending").length
      const openMaintenance = maintenance.filter((m: any) => ["Open", "InProgress", "Reported"].includes(m.status ?? m.Status ?? "")).length

      // Calculate outstanding balances
      let outstanding = 0
      for (const b of checkedInBookings) {
        const paid = payments.filter((p: any) => (p.hotelBookingId ?? p.hotelbookingid) === b.hotelBookingId).reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
        outstanding += Math.max(0, Number(b.totalAmount ?? 0) - paid)
      }

      setPreview({
        totalRooms, occupied, available, revenue, expenses: expenseTotal,
        checkedIn: checkedInBookings.length, pendingCheckouts, noshows,
        pendingHousekeeping, openMaintenance, outstandingBalances: outstanding,
      })
    } catch (e: any) {
      toast({ title: "Failed to load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function handleRunAudit() {
    setRunning(true)
    try {
      const result = await runNightAudit({ closingDate: new Date().toISOString().slice(0, 10) })
      const posted = (result as any)?.roomchargesposted ?? 0
      toast({ title: "Night audit completed successfully", description: posted > 0 ? `${posted} room charge(s) auto-posted` : "No room charges to post" })
      setDialogOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Night audit failed", description: e?.message, variant: "destructive" })
    } finally { setRunning(false) }
  }

  const occRate = preview.totalRooms > 0 ? Math.round((preview.occupied / preview.totalRooms) * 100) : 0
  const issueCount = (preview.outstandingBalances > 0 ? 1 : 0) + (preview.pendingHousekeeping > 0 ? 1 : 0) + (preview.openMaintenance > 0 ? 1 : 0) + (preview.noshows > 0 ? 1 : 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-3">
              <Shield className="h-6 w-6 text-violet-600" />
              <h1 className="text-2xl font-bold">Night Audit</h1>
            </div>
            <Button onClick={() => setDialogOpen(true)} className="bg-violet-600 hover:bg-violet-700">
              <Play className="h-4 w-4 mr-1" /> Run Night Audit
            </Button>
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <>
              {/* Pre-Audit Summary Cards */}
              <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3 mb-6">
                <Card><CardContent className="p-3 text-center">
                  <BedDouble className="h-5 w-5 mx-auto mb-1 text-violet-600" />
                  <div className="text-2xl font-bold text-violet-700">{preview.occupied}/{preview.totalRooms}</div>
                  <div className="text-xs text-slate-500">Rooms Occupied</div>
                  <div className="text-xs text-violet-600 font-medium">{occRate}% occupancy</div>
                </CardContent></Card>

                <Card><CardContent className="p-3 text-center">
                  <Users className="h-5 w-5 mx-auto mb-1 text-blue-600" />
                  <div className="text-2xl font-bold text-blue-700">{preview.checkedIn}</div>
                  <div className="text-xs text-slate-500">In-House Guests</div>
                </CardContent></Card>

                <Card><CardContent className="p-3 text-center">
                  <TrendingUp className="h-5 w-5 mx-auto mb-1 text-emerald-600" />
                  <div className="text-2xl font-bold text-emerald-700">{preview.revenue.toFixed(0)}</div>
                  <div className="text-xs text-slate-500">Today&apos;s Revenue</div>
                </CardContent></Card>

                <Card><CardContent className="p-3 text-center">
                  <TrendingDown className="h-5 w-5 mx-auto mb-1 text-red-600" />
                  <div className="text-2xl font-bold text-red-700">{preview.expenses.toFixed(0)}</div>
                  <div className="text-xs text-slate-500">Today&apos;s Expenses</div>
                </CardContent></Card>

                <Card className={preview.outstandingBalances > 0 ? "border-amber-300 bg-amber-50" : ""}>
                  <CardContent className="p-3 text-center">
                    <Wallet className="h-5 w-5 mx-auto mb-1 text-amber-600" />
                    <div className={`text-2xl font-bold ${preview.outstandingBalances > 0 ? "text-amber-700" : "text-emerald-700"}`}>{preview.outstandingBalances.toFixed(0)}</div>
                    <div className="text-xs text-slate-500">Outstanding</div>
                  </CardContent>
                </Card>

                <Card className={issueCount > 0 ? "border-amber-300 bg-amber-50" : "border-emerald-300 bg-emerald-50"}>
                  <CardContent className="p-3 text-center">
                    {issueCount > 0 ? <AlertTriangle className="h-5 w-5 mx-auto mb-1 text-amber-600" /> : <CheckCircle2 className="h-5 w-5 mx-auto mb-1 text-emerald-600" />}
                    <div className={`text-2xl font-bold ${issueCount > 0 ? "text-amber-700" : "text-emerald-700"}`}>{issueCount}</div>
                    <div className="text-xs text-slate-500">{issueCount > 0 ? "Issues Found" : "All Clear"}</div>
                  </CardContent>
                </Card>
              </div>

              {/* Issues / Alerts Panel */}
              {issueCount > 0 && (
                <Card className="mb-6 border-amber-200">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm flex items-center gap-2 text-amber-700">
                      <AlertTriangle className="h-4 w-4" /> Pre-Audit Alerts
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="space-y-2">
                      {preview.outstandingBalances > 0 && (
                        <div className="flex items-center gap-2 text-sm p-2 bg-amber-50 rounded">
                          <Wallet className="h-4 w-4 text-amber-600" />
                          <span>Outstanding guest balances: <strong className="text-amber-700">{preview.outstandingBalances.toFixed(2)}</strong></span>
                        </div>
                      )}
                      {preview.pendingHousekeeping > 0 && (
                        <div className="flex items-center gap-2 text-sm p-2 bg-amber-50 rounded">
                          <ClipboardList className="h-4 w-4 text-amber-600" />
                          <span><strong>{preview.pendingHousekeeping}</strong> pending housekeeping tasks</span>
                        </div>
                      )}
                      {preview.openMaintenance > 0 && (
                        <div className="flex items-center gap-2 text-sm p-2 bg-amber-50 rounded">
                          <Wrench className="h-4 w-4 text-amber-600" />
                          <span><strong>{preview.openMaintenance}</strong> open maintenance requests</span>
                        </div>
                      )}
                      {preview.noshows > 0 && (
                        <div className="flex items-center gap-2 text-sm p-2 bg-amber-50 rounded">
                          <Users className="h-4 w-4 text-amber-600" />
                          <span><strong>{preview.noshows}</strong> potential no-shows (confirmed but not checked in today)</span>
                        </div>
                      )}
                      {preview.pendingCheckouts > 0 && (
                        <div className="flex items-center gap-2 text-sm p-2 bg-blue-50 rounded">
                          <DoorClosed className="h-4 w-4 text-blue-600" />
                          <span><strong>{preview.pendingCheckouts}</strong> pending check-outs for today</span>
                        </div>
                      )}
                    </div>
                  </CardContent>
                </Card>
              )}

              {/* Audit History */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Audit History</CardTitle>
                </CardHeader>
                <CardContent className="p-0">
                  <table className="w-full text-sm">
                    <thead className="bg-slate-50 border-b">
                      <tr>
                        <th className="text-left p-3">Date</th>
                        <th className="text-center p-3">Rooms</th>
                        <th className="text-center p-3">Occupancy</th>
                        <th className="text-right p-3">Revenue</th>
                        <th className="text-right p-3">Expenses</th>
                        <th className="text-right p-3">Outstanding</th>
                        <th className="text-center p-3">Check-ins</th>
                        <th className="text-center p-3">Check-outs</th>
                        <th className="text-center p-3">No-shows</th>
                        <th className="text-left p-3">Status</th>
                        <th className="text-left p-3">Issues</th>
                      </tr>
                    </thead>
                    <tbody>
                      {audits.map((a: any, idx: number) => {
                        const hasIssues = a.issues ?? a.Issues
                        return (
                          <tr key={a.hotelnightauditid ?? `audit-${idx}`} className="border-b hover:bg-slate-50 cursor-pointer" onClick={() => setDetailAudit(a)}>
                            <td className="p-3 font-medium">{(a.auditdate ?? a.auditDate)?.slice?.(0, 10)}</td>
                            <td className="p-3 text-center">{a.occupiedrooms ?? a.occupiedRooms ?? 0}/{a.totalrooms ?? a.totalRooms ?? 0}</td>
                            <td className="p-3 text-center">{Number(a.occupancyrate ?? a.occupancyRate ?? 0).toFixed(1)}%</td>
                            <td className="p-3 text-right text-emerald-700 font-semibold">{Number(a.totalrevenue ?? a.totalRevenue ?? 0).toFixed(2)}</td>
                            <td className="p-3 text-right text-red-600">{Number(a.totalexpenses ?? a.totalExpenses ?? 0).toFixed(2)}</td>
                            <td className={`p-3 text-right font-semibold ${Number(a.outstandingbalances ?? a.outstandingBalances ?? 0) > 0 ? "text-amber-700" : "text-emerald-700"}`}>{Number(a.outstandingbalances ?? a.outstandingBalances ?? 0).toFixed(2)}</td>
                            <td className="p-3 text-center">{a.checkincount ?? a.checkinCount ?? 0}</td>
                            <td className="p-3 text-center">{a.checkoutcount ?? a.checkoutCount ?? 0}</td>
                            <td className="p-3 text-center">{a.noshowcount ?? a.noshowCount ?? 0}</td>
                            <td className="p-3">
                              <Badge variant="outline" className="bg-emerald-100 text-emerald-700 text-xs">
                                <CheckCircle2 className="h-3 w-3 mr-1" />{a.status ?? "Completed"}
                              </Badge>
                            </td>
                            <td className="p-3 text-xs text-slate-500 max-w-[200px] truncate">{hasIssues ?? "None"}</td>
                          </tr>
                        )
                      })}
                      {audits.length === 0 && (
                        <tr><td colSpan={11} className="p-8 text-center text-slate-400">No audits yet. Click &quot;Run Night Audit&quot; to perform your first audit.</td></tr>
                      )}
                    </tbody>
                  </table>
                </CardContent>
              </Card>
            </>
          )}

          {/* Run Audit Confirmation Dialog */}
          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <DialogContent className="max-w-lg">
              <DialogHeader>
                <DialogTitle className="flex items-center gap-2">
                  <Shield className="h-5 w-5 text-violet-600" /> Run Night Audit
                </DialogTitle>
              </DialogHeader>
              <div className="space-y-4">
                <p className="text-sm text-slate-600">
                  The night audit will automatically post nightly room charges for all checked-in guests and record the following for today:
                </p>
                <div className="p-4 bg-violet-50 rounded-lg space-y-2 text-sm">
                  <div className="grid grid-cols-2 gap-2">
                    <div>Rooms: <strong>{preview.occupied}/{preview.totalRooms} occupied</strong></div>
                    <div>Occupancy: <strong>{occRate}%</strong></div>
                    <div>Revenue: <strong className="text-emerald-700">{preview.revenue.toFixed(2)}</strong></div>
                    <div>Expenses: <strong className="text-red-700">{preview.expenses.toFixed(2)}</strong></div>
                    <div>Outstanding: <strong className={preview.outstandingBalances > 0 ? "text-amber-700" : "text-emerald-700"}>{preview.outstandingBalances.toFixed(2)}</strong></div>
                    <div>In-house: <strong>{preview.checkedIn} guests</strong></div>
                  </div>
                </div>
                {issueCount > 0 && (
                  <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg">
                    <p className="text-sm font-medium text-amber-700 flex items-center gap-1">
                      <AlertTriangle className="h-4 w-4" /> {issueCount} issue(s) will be recorded
                    </p>
                    <p className="text-xs text-amber-600 mt-1">Issues will be logged but won&apos;t block the audit.</p>
                  </div>
                )}
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
                <Button onClick={handleRunAudit} disabled={running} className="bg-violet-600 hover:bg-violet-700">
                  {running && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
                  Run Audit
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Audit Detail Dialog */}
          <Dialog open={!!detailAudit} onOpenChange={() => setDetailAudit(null)}>
            <DialogContent className="max-w-lg">
              <DialogHeader>
                <DialogTitle>Audit Details — {(detailAudit as any)?.auditdate?.slice?.(0, 10) ?? (detailAudit as any)?.auditDate?.slice?.(0, 10)}</DialogTitle>
              </DialogHeader>
              {detailAudit && (() => {
                const a = detailAudit as any
                const rev = Number(a.totalrevenue ?? a.totalRevenue ?? 0)
                const exp = Number(a.totalexpenses ?? a.totalExpenses ?? 0)
                const net = rev - exp
                return (
                  <div className="space-y-4">
                    <div className="grid grid-cols-2 gap-3 text-sm">
                      <div className="p-3 bg-violet-50 rounded-lg">
                        <div className="text-xs text-slate-500">Occupancy</div>
                        <div className="text-lg font-bold text-violet-700">{Number(a.occupancyrate ?? a.occupancyRate ?? 0).toFixed(1)}%</div>
                        <div className="text-xs">{a.occupiedrooms ?? a.occupiedRooms ?? 0} of {a.totalrooms ?? a.totalRooms ?? 0} rooms</div>
                      </div>
                      <div className="p-3 bg-emerald-50 rounded-lg">
                        <div className="text-xs text-slate-500">Net Revenue</div>
                        <div className={`text-lg font-bold ${net >= 0 ? "text-emerald-700" : "text-red-700"}`}>{net.toFixed(2)}</div>
                        <div className="text-xs">Rev: {rev.toFixed(2)} | Exp: {exp.toFixed(2)}</div>
                      </div>
                    </div>
                    <div className="grid grid-cols-3 gap-3 text-sm text-center">
                      <div className="p-2 bg-slate-50 rounded"><div className="font-bold text-blue-700">{a.checkincount ?? a.checkinCount ?? 0}</div><div className="text-xs text-slate-500">Check-ins</div></div>
                      <div className="p-2 bg-slate-50 rounded"><div className="font-bold text-slate-700">{a.checkoutcount ?? a.checkoutCount ?? 0}</div><div className="text-xs text-slate-500">Check-outs</div></div>
                      <div className="p-2 bg-slate-50 rounded"><div className="font-bold text-amber-700">{a.noshowcount ?? a.noshowCount ?? 0}</div><div className="text-xs text-slate-500">No-shows</div></div>
                    </div>
                    <div className="grid grid-cols-3 gap-3 text-sm text-center">
                      <div className="p-2 bg-slate-50 rounded"><div className="font-bold">{a.pendinghousetasks ?? a.pendingHouseTasks ?? 0}</div><div className="text-xs text-slate-500">Pending Housekeeping</div></div>
                      <div className="p-2 bg-slate-50 rounded"><div className="font-bold">{a.openmaintenance ?? a.openMaintenance ?? 0}</div><div className="text-xs text-slate-500">Open Maintenance</div></div>
                      <div className="p-2 bg-violet-50 rounded"><div className="font-bold text-violet-700">{a.roomchargesposted ?? 0}</div><div className="text-xs text-slate-500">Room Charges Posted</div></div>
                    </div>
                    {(a.issues ?? a.Issues) && (
                      <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg">
                        <div className="text-xs font-semibold text-amber-700 mb-1">Issues Recorded:</div>
                        <div className="text-sm text-amber-800">{a.issues ?? a.Issues}</div>
                      </div>
                    )}
                    <div className="text-right">
                      <Badge variant="outline" className="bg-emerald-100 text-emerald-700">
                        <CheckCircle2 className="h-3 w-3 mr-1" />{a.status ?? "Completed"}
                      </Badge>
                    </div>
                  </div>
                )
              })()}
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

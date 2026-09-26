"use client"

/**
 * Daily Closing — review a day's money and lock it.
 *
 * Closing a day locks it AND every earlier day: the server refuses any payment,
 * refund, expense, transfer, owner-money or loan entry dated on or before the
 * last closed day (migration 323, fnrestaurant_assert_day_open). Corrections
 * made later are dated the day they are made, so a closed day's figures never
 * change. Only the most recent closed day can be reopened, with a reason.
 */

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { AlertTriangle, CalendarCheck, Loader2, Lock, LockOpen, ShoppingBag, TrendingDown, TrendingUp } from "lucide-react"
import { PageHeader } from "@/components/restaurant/page-header"
import { StatCard } from "@/components/restaurant/stat-card"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { useAuthStore } from "@/lib/store/auth-store"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  previewDay, listClosings, closeDay, reopenDay, todayIso,
  type DayPreview, type DailyClosing,
} from "@/lib/api/restaurant-finance"

const nice = (iso?: string | null) => (iso ? new Date(`${iso.slice(0, 10)}T00:00:00`).toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short", year: "numeric" }) : "—")

export default function RestaurantDailyClosingPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const [date, setDate] = useState(todayIso())
  const [preview, setPreview] = useState<DayPreview | null>(null)
  const [history, setHistory] = useState<DailyClosing[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [closeOpen, setCloseOpen] = useState(false)
  const [notes, setNotes] = useState("")
  const [reopenFor, setReopenFor] = useState<DailyClosing | null>(null)
  const [reason, setReason] = useState("")

  const load = useCallback(async () => {
    try {
      const [p, h] = await Promise.all([previewDay(date), listClosings(60)])
      setPreview(p); setHistory(h)
    } catch (e: any) {
      toast({ title: "Could not load the day", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }, [date, toast])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  async function submitClose() {
    setSaving(true)
    try {
      await closeDay(date, notes || null)
      toast({ title: `${nice(date)} closed`, description: "Nothing dated on or before this day can be changed now." })
      setCloseOpen(false); setNotes(""); await load()
    } catch (e: any) { toast({ title: "Could not close the day", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function submitReopen() {
    if (!reopenFor || !reason.trim()) return
    setSaving(true)
    try {
      await reopenDay(reopenFor.closingDate.slice(0, 10), reason.trim())
      toast({ title: `${nice(reopenFor.closingDate)} reopened` })
      setReopenFor(null); setReason(""); await load()
    } catch (e: any) { toast({ title: "Could not reopen", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  if (!canView) return (
    <div className="flex h-screen bg-gray-50"><DashboardSidebar /><div className="flex-1 flex flex-col overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 md:p-6"><Card><CardContent className="py-12 text-center text-slate-600">You do not have access to Daily Closing.</CardContent></Card></main>
    </div></div>
  )
  if (loading) return <PageSkeleton statCards={4} listRows={6} />

  const latestClosed = history.find((h) => h.status === "Closed")
  const p = preview
  const takings = p ? p.takingsCash + p.takingsCard + p.takingsMobile + p.takingsGiftCard + p.takingsOther : 0

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6 pb-24 lg:pb-6">
          <div className="max-w-7xl mx-auto space-y-6">
            <PageHeader icon={CalendarCheck} title="Daily Closing" subtitle="Check the day's money, then close it so it cannot be changed">
              <Input type="date" className="h-10 sm:w-44" value={date} max={todayIso()} onChange={(e) => setDate(e.target.value)} />
            </PageHeader>

            {p && (
              <>
                {p.isClosed ? (
                  <Alert className="border-green-200 bg-green-50">
                    <Lock className="h-4 w-4 text-green-700" />
                    <AlertDescription className="text-green-900">
                      {nice(p.closingDate)} is closed. The books are locked up to {nice(p.lastClosedDate)}.
                    </AlertDescription>
                  </Alert>
                ) : (
                  <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 rounded-lg border bg-white p-4">
                    <div className="text-sm">
                      <div className="font-medium">{nice(p.closingDate)} is open.</div>
                      <div className="text-muted-foreground">Closing it locks this day{p.lastClosedDate ? ` and everything since ${nice(p.lastClosedDate)}` : " and every earlier day"}.</div>
                    </div>
                    <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => setCloseOpen(true)} disabled={p.openShifts > 0}>
                      <Lock className="h-4 w-4 mr-1" /> Close this day
                    </Button>
                  </div>
                )}

                {(p.openShifts > 0 || p.openOrders > 0 || p.unpaidOrders > 0) && !p.isClosed && (
                  <Alert className="border-amber-200 bg-amber-50">
                    <AlertTriangle className="h-4 w-4 text-amber-700" />
                    <AlertDescription className="text-amber-900 text-sm space-y-1">
                      {p.openShifts > 0 && <div><b>{p.openShifts} till shift{p.openShifts === 1 ? " is" : "s are"} still open.</b> Close {p.openShifts === 1 ? "it" : "them"} on <Link href="/restaurant-tills" className="underline">Tills & Shifts</Link> before closing the day.</div>}
                      {p.openOrders > 0 && <div>{p.openOrders} order{p.openOrders === 1 ? " is" : "s are"} not finished. Payments taken on them later will count on the day they are taken.</div>}
                      {p.unpaidOrders > 0 && <div>{p.unpaidOrders} order{p.unpaidOrders === 1 ? " has" : "s have"} money still owing.</div>}
                    </AlertDescription>
                  </Alert>
                )}

                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <StatCard label={`Net sales (${p.orderCount} orders)`} value={gh(p.netSales)} icon={ShoppingBag} color="rose" />
                  <StatCard label="Money in" value={gh(p.moneyIn)} icon={TrendingUp} color="green" />
                  <StatCard label="Money out" value={gh(p.moneyOut)} icon={TrendingDown} color="red" />
                  <StatCard label="Cash over / short" value={gh(p.cashVariance)} icon={AlertTriangle} color={p.cashVariance < 0 ? "red" : "amber"} />
                </div>

                <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                  <Card>
                    <CardHeader className="pb-2"><CardTitle className="text-base">Sales</CardTitle></CardHeader>
                    <CardContent className="text-sm space-y-1.5">
                      <Row label="Net sales (after discounts)" value={gh(p.netSales)} />
                      <Row label="Discounts given" value={gh(p.discounts)} muted />
                      <Row label="Service charge" value={gh(p.serviceCharge)} />
                      <Row label="Delivery fees" value={gh(p.deliveryFees)} />
                      <Row label="Tax collected (owed, not income)" value={gh(p.taxCollected)} muted />
                      <Row label="Tips received" value={gh(p.tips)} muted />
                      <Row label="Refunds given" value={gh(-p.refunds)} />
                    </CardContent>
                  </Card>
                  <Card>
                    <CardHeader className="pb-2"><CardTitle className="text-base">Takings by method</CardTitle></CardHeader>
                    <CardContent className="text-sm space-y-1.5">
                      <Row label="Cash" value={gh(p.takingsCash)} />
                      <Row label="Card" value={gh(p.takingsCard)} />
                      <Row label="Mobile money" value={gh(p.takingsMobile)} />
                      <Row label="Gift cards (no cash)" value={gh(p.takingsGiftCard)} muted />
                      {p.takingsOther > 0 && <Row label="Other" value={gh(p.takingsOther)} />}
                      <Row label="Total takings" value={gh(takings)} bold />
                      <Row label="Expenses dated this day" value={gh(-p.expenses)} />
                    </CardContent>
                  </Card>
                </div>
              </>
            )}

            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Closed days</CardTitle></CardHeader>
              <CardContent className="p-0">
                {history.length === 0 ? (
                  <p className="p-6 text-sm text-center text-muted-foreground">No day has been closed yet.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm min-w-[720px]">
                      <thead className="bg-gray-50 border-b"><tr>
                        <th className="text-left p-3">Day</th><th className="text-left p-3">Status</th><th className="text-right p-3">Orders</th>
                        <th className="text-right p-3">Net sales</th><th className="text-right p-3">In</th><th className="text-right p-3">Out</th>
                        <th className="text-right p-3">Over / short</th><th className="text-left p-3">Closed by</th><th className="p-3"></th>
                      </tr></thead>
                      <tbody>
                        {history.map((h) => (
                          <tr key={h.closingId} className="border-b">
                            <td className="p-3 font-medium"><button type="button" className="underline decoration-dotted" onClick={() => setDate(h.closingDate.slice(0, 10))}>{nice(h.closingDate)}</button></td>
                            <td className="p-3">{h.status === "Closed"
                              ? <Badge className="bg-green-600">Closed</Badge>
                              : <Badge variant="outline" title={h.reopenReason ?? undefined}>Reopened</Badge>}
                              {h.status === "Reopened" && h.reopenReason && <div className="text-xs text-muted-foreground mt-1">{h.reopenReason}</div>}</td>
                            <td className="p-3 text-right">{h.orderCount}</td>
                            <td className="p-3 text-right">{gh(h.netSales)}</td>
                            <td className="p-3 text-right text-green-700">{gh(h.moneyIn)}</td>
                            <td className="p-3 text-right text-red-600">{gh(h.moneyOut)}</td>
                            <td className={`p-3 text-right ${h.cashVariance < 0 ? "text-red-600" : ""}`}>{gh(h.cashVariance)}</td>
                            <td className="p-3 text-xs">{h.closedBy}<div className="text-muted-foreground">{new Date(h.closedAt).toLocaleString()}</div></td>
                            <td className="p-3 text-right">
                              {latestClosed?.closingId === h.closingId && (
                                <Button variant="outline" size="sm" onClick={() => { setReopenFor(h); setReason("") }}><LockOpen className="h-4 w-4 mr-1" />Reopen</Button>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>

      <Dialog open={closeOpen} onOpenChange={setCloseOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Close {nice(date)}?</DialogTitle>
            <DialogDescription>After this, no payment, refund, expense, transfer, owner-money or loan entry can be dated on or before this day. Corrections made later are dated the day they are made.</DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5"><Label>Notes (optional)</Label><Input value={notes} onChange={(e) => setNotes(e.target.value)} className="h-10" /></div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setCloseOpen(false)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={saving} onClick={submitClose}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Close the day</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!reopenFor} onOpenChange={(o) => { if (!o) setReopenFor(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Reopen {nice(reopenFor?.closingDate)}?</DialogTitle>
            <DialogDescription>Entries dated this day can be changed again until it is closed once more. The reason is kept on record.</DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5"><Label>Reason</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} className="h-10" placeholder="e.g. Supplier invoice arrived late" /></div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReopenFor(null)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={saving || !reason.trim()} onClick={submitReopen}>Reopen</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function Row({ label, value, muted, bold }: { label: string; value: string; muted?: boolean; bold?: boolean }) {
  return (
    <div className={`flex justify-between ${bold ? "font-semibold border-t pt-1.5" : ""} ${muted ? "text-muted-foreground" : ""}`}>
      <span>{label}</span><span className="tabular-nums">{value}</span>
    </div>
  )
}

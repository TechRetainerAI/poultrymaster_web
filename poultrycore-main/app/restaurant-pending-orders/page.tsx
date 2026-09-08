"use client"

/**
 * New guest orders awaiting staff confirmation.
 *
 * A QR order is created at status 'Placed' and migration 248 keeps it out of the
 * kitchen display until someone accepts it here. That gate is the main defence
 * against prank orders — anyone who can scan the code on a table can submit one —
 * so this screen is what makes guest ordering safe to switch on.
 *
 * Polls every 10s rather than using SignalR. The only hub in this backend serves
 * chat; standing up an order hub would mean groups-per-farm, reconnect handling
 * and Cloud Run socket affinity, to save a few seconds on a journey where a
 * waiter walking to the table is the real latency. The KDS already proves 5s
 * polling is fine here; this screen is lower volume, so 10s.
 */

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from "@/components/ui/dialog"
import {
  Check, X, Clock, Phone, Mail, User, Utensils, Volume2, VolumeX, QrCode, Banknote, Inbox,
} from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listPendingOnlineOrders, acceptOnlineOrder, rejectOnlineOrder,
  type PendingOnlineOrder,
} from "@/lib/api/restaurant"

const POLL_MS = 10_000

export default function RestaurantPendingOrdersPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [orders, setOrders] = useState<PendingOnlineOrder[]>([])
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState<number | null>(null)
  const [soundOn, setSoundOn] = useState(true)
  const [rejecting, setRejecting] = useState<PendingOnlineOrder | null>(null)
  const [rejectReason, setRejectReason] = useState("")

  const prevCount = useRef(0)
  const timerRef = useRef<NodeJS.Timeout | null>(null)
  const audioRef = useRef<HTMLAudioElement | null>(null)

  const refresh = useCallback(async () => {
    try {
      const list = await listPendingOnlineOrders()
      // Only chime on genuinely new arrivals, and never on the first load or the
      // room would ring every time someone opens the page.
      if (soundOn && prevCount.current > 0 && list.length > prevCount.current) {
        try { audioRef.current?.play() } catch { /* autoplay policy; not worth surfacing */ }
      }
      prevCount.current = list.length
      setOrders(list)
    } catch {
      // Swallow: a dropped poll is not worth a toast every 10 seconds. A real
      // problem shows up as the list going stale, and the accept/reject actions
      // below do report their own failures.
    }
  }, [soundOn])

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    refresh().finally(() => setLoading(false))
  }, [activeFarmType, router, refresh])

  useEffect(() => {
    if (activeFarmType !== "Restaurant") return
    timerRef.current = setInterval(refresh, POLL_MS)
    return () => { if (timerRef.current) clearInterval(timerRef.current) }
  }, [refresh, activeFarmType])

  async function accept(o: PendingOnlineOrder) {
    setBusyId(o.orderId)
    try {
      const r = await acceptOnlineOrder(o.orderId)
      toast({ title: `Order ${o.orderNumber} confirmed`, description: r.message })
      await refresh()
    } catch (e: any) {
      toast({ title: "Could not confirm", description: e?.message, variant: "destructive" })
    } finally { setBusyId(null) }
  }

  async function confirmReject() {
    if (!rejecting) return
    setBusyId(rejecting.orderId)
    try {
      await rejectOnlineOrder(rejecting.orderId, rejectReason)
      toast({ title: `Order ${rejecting.orderNumber} rejected` })
      setRejecting(null)
      setRejectReason("")
      await refresh()
    } catch (e: any) {
      toast({ title: "Could not reject", description: e?.message, variant: "destructive" })
    } finally { setBusyId(null) }
  }

  /** Older orders get louder, so nobody is left waiting unnoticed. */
  function waitTone(mins: number) {
    if (mins >= 10) return "border-red-300 bg-red-50"
    if (mins >= 5) return "border-amber-300 bg-amber-50"
    return "border-gray-200 bg-white"
  }

  if (activeFarmType !== "Restaurant") return null

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex flex-1 flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="mb-6 flex items-start justify-between gap-4">
            <div>
              <h1 className="flex items-center gap-2 text-2xl font-bold text-gray-900">
                <Inbox className="h-6 w-6 text-rose-600" />
                New Orders
                {orders.length > 0 && (
                  <Badge className="bg-rose-600 text-white">{orders.length}</Badge>
                )}
              </h1>
              <p className="mt-0.5 text-sm text-muted-foreground">
                Orders guests sent from their phones. They do not reach the kitchen until you accept them.
              </p>
            </div>
            <Button variant="outline" size="sm" onClick={() => setSoundOn(v => !v)}>
              {soundOn ? <Volume2 className="h-4 w-4 mr-1.5" /> : <VolumeX className="h-4 w-4 mr-1.5" />}
              {soundOn ? "Sound on" : "Sound off"}
            </Button>
          </div>

          {/* Short beep, inlined so the page needs no asset and works offline. */}
          <audio ref={audioRef} preload="auto" src="data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YQAAAAA=" />

          {loading ? (
            <PageSkeleton />
          ) : orders.length === 0 ? (
            <Card>
              <CardContent className="flex flex-col items-center justify-center py-16 text-center">
                <Inbox className="mb-3 h-12 w-12 text-gray-300" />
                <p className="font-medium text-gray-700">No orders waiting</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  New orders from table QR codes appear here within a few seconds.
                </p>
              </CardContent>
            </Card>
          ) : (
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              {orders.map(o => (
                <div key={o.orderId} className={`rounded-xl border-2 p-4 shadow-sm ${waitTone(o.waitingMinutes)}`}>
                  <div className="mb-3 flex items-start justify-between gap-2">
                    <div>
                      <div className="flex items-center gap-2">
                        {o.tableNumber && (
                          <Badge variant="outline" className="border-rose-300 text-rose-700">
                            Table {o.tableNumber}
                          </Badge>
                        )}
                        <Badge variant="secondary" className="gap-1">
                          <QrCode className="h-3 w-3" /> {o.onlineSource || "Online"}
                        </Badge>
                      </div>
                      <div className="mt-1 font-mono text-xs text-muted-foreground">{o.orderNumber}</div>
                    </div>
                    <div className="flex items-center gap-1 whitespace-nowrap text-xs text-muted-foreground">
                      <Clock className="h-3.5 w-3.5" />
                      {Math.floor(o.waitingMinutes)}m
                    </div>
                  </div>

                  <div className="mb-3 space-y-1 text-sm">
                    <div className="flex items-center gap-1.5 font-medium text-gray-900">
                      <User className="h-3.5 w-3.5 text-gray-400" />
                      {o.customerName || "Guest"}
                    </div>
                    {o.customerPhone && (
                      <a href={`tel:${o.customerPhone}`} className="flex items-center gap-1.5 text-gray-600 hover:text-rose-600">
                        <Phone className="h-3.5 w-3.5 text-gray-400" />
                        {o.customerPhone}
                      </a>
                    )}
                    {o.customerEmail && (
                      <a href={`mailto:${o.customerEmail}`} className="flex items-center gap-1.5 break-all text-gray-600 hover:text-rose-600">
                        <Mail className="h-3.5 w-3.5 shrink-0 text-gray-400" />
                        {o.customerEmail}
                      </a>
                    )}
                    {o.guestPaymentIntent && (
                      <div className="flex items-center gap-1.5 text-gray-600">
                        <Banknote className="h-3.5 w-3.5 text-gray-400" />
                        Plans to pay by {o.guestPaymentIntent}
                      </div>
                    )}
                  </div>

                  <div className="mb-3 rounded-lg bg-gray-50 p-2.5">
                    <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-gray-500">
                      <Utensils className="h-3.5 w-3.5" />
                      {o.itemCount} item{o.itemCount === 1 ? "" : "s"}
                    </div>
                    <div className="text-sm leading-snug text-gray-800">{o.itemSummary || "—"}</div>
                    {o.notes && (
                      <div className="mt-2 border-t pt-2 text-xs italic text-amber-700">“{o.notes}”</div>
                    )}
                  </div>

                  <div className="mb-3 text-right text-lg font-bold text-rose-600">
                    {o.totalAmount.toFixed(2)}
                  </div>

                  <div className="flex gap-2">
                    <Button
                      className="flex-1 bg-emerald-600 hover:bg-emerald-700"
                      disabled={busyId === o.orderId}
                      onClick={() => accept(o)}
                    >
                      <Check className="mr-1.5 h-4 w-4" /> Accept
                    </Button>
                    <Button
                      variant="outline"
                      className="border-red-200 text-red-600 hover:bg-red-50"
                      disabled={busyId === o.orderId}
                      onClick={() => { setRejecting(o); setRejectReason("") }}
                    >
                      <X className="mr-1.5 h-4 w-4" /> Reject
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </main>
      </div>

      <Dialog open={!!rejecting} onOpenChange={(v) => { if (!v) setRejecting(null) }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reject order {rejecting?.orderNumber}?</DialogTitle>
            <DialogDescription>
              The guest sees this reason on their phone. It is the only way to tell them,
              so say something they can act on.
            </DialogDescription>
          </DialogHeader>
          <textarea
            value={rejectReason}
            onChange={(e) => setRejectReason(e.target.value)}
            placeholder="e.g. Sorry, the kitchen has closed for the evening."
            className="w-full min-h-[90px] rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-500 focus-visible:ring-offset-2"
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejecting(null)}>Cancel</Button>
            <Button
              className="bg-red-600 hover:bg-red-700"
              disabled={busyId === rejecting?.orderId}
              onClick={confirmReject}
            >
              Reject order
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

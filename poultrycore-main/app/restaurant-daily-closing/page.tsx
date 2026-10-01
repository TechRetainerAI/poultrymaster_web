"use client"

/**
 * Daily Closing — review a day's money and lock it.
 *
 * Presented the Poultry way (app/poultry-daily-closing): a plain header with
 * "+ New closing", one card per closing with coloured tiles (Orders / Net sales
 * / Cash in − out) and Money in / Money out / Net / Over-short underneath, an
 * "Open closing" button, and "View table format" on a phone. Restaurant words
 * replace Poultry's production tiles.
 *
 * The Restaurant's behaviour is unchanged: closing a day locks it AND every
 * earlier day -- the server refuses any payment, refund, expense, transfer,
 * owner-money or loan entry dated on or before the last closed day (migration
 * 323, fnrestaurant_assert_day_open). Corrections made later are dated the day
 * they are made. Only the most recent closed day can be reopened, with a reason.
 * There is no draft step (Poultry's Submit / Approve): the day under review is
 * shown live, and "Close this day" is the approval.
 */

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { AlertTriangle, Eye, Loader2, Lock, LockOpen, Plus } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { useAuthStore } from "@/lib/store/auth-store"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  previewDay, listClosings, closeDay, reopenDay, todayIso,
  type DayPreview, type DailyClosing,
} from "@/lib/api/restaurant-finance"

const nice = (iso?: string | null) => (iso ? new Date(`${iso.slice(0, 10)}T00:00:00`).toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short", year: "numeric" }) : "—")

const STATUS_COLORS: Record<string, string> = {
  Open: "bg-slate-100 text-slate-700 hover:bg-slate-100",
  Closed: "bg-green-100 text-green-800 hover:bg-green-100",
  Reopened: "bg-amber-100 text-amber-800 hover:bg-amber-100",
}

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
  // "+ New closing" picks the day; "Open closing" shows its full review.
  const [newOpen, setNewOpen] = useState(false)
  const [newDate, setNewDate] = useState(todayIso())
  const [viewOpen, setViewOpen] = useState(false)

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

  const pg = usePagination(history, 20)

  async function submitClose() {
    setSaving(true)
    try {
      await closeDay(date, notes || null)
      toast({ title: `${nice(date)} closed`, description: "Nothing dated on or before this day can be changed now." })
      setCloseOpen(false); setViewOpen(false); setNotes(""); await load()
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

  const openClosing = (day: string) => { setDate(day.slice(0, 10)); setViewOpen(true) }

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
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4 pb-24 lg:pb-6">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <h1 className="text-2xl font-bold">Daily Closing</h1>
              <p className="text-sm text-slate-500">End-of-day orders, sales and cash snapshot. Closing a day locks it.</p>
            </div>
            <Button className="shrink-0 bg-rose-600 hover:bg-rose-700" onClick={() => { setNewDate(todayIso()); setNewOpen(true) }}>
              <Plus className="w-4 h-4 mr-1" /> New closing
            </Button>
          </div>

          {/* The day under review, in the same card as the list below. */}
          {p && (
            <div className="rounded-xl border shadow-sm overflow-hidden bg-rose-50 border-rose-200">
              <div className="px-3 py-3 space-y-3">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold text-slate-900">{nice(p.closingDate)}</span>
                  <Badge className={STATUS_COLORS[p.isClosed ? "Closed" : "Open"]}>{p.isClosed ? "Closed" : "Open"}</Badge>
                  <Input type="date" className="ml-auto h-8 w-40 bg-white" value={date} max={todayIso()} onChange={(e) => setDate(e.target.value)} aria-label="Day" />
                </div>
                <DayTiles orders={p.orderCount} sales={gh(p.netSales)} cash={gh(p.moneyIn - p.moneyOut)} />
                <div className="grid grid-cols-2 gap-2 text-sm pt-1 border-t border-rose-200/70">
                  <div><span className="text-slate-500">Money in</span> <span className="font-medium text-emerald-700">{gh(p.moneyIn)}</span></div>
                  <div><span className="text-slate-500">Money out</span> <span className="font-medium text-rose-700">{gh(p.moneyOut)}</span></div>
                  <div><span className="text-slate-500">Takings</span> <span className="font-medium">{gh(takings)}</span></div>
                  <div><span className="text-slate-500">Over / short</span> <span className={cn("font-medium", p.cashVariance < 0 ? "text-rose-700" : "")}>{gh(p.cashVariance)}</span></div>
                </div>
                <p className="text-xs text-slate-600">
                  {p.isClosed
                    ? `The books are locked up to ${nice(p.lastClosedDate)}.`
                    : `Closing it locks this day${p.lastClosedDate ? ` and everything since ${nice(p.lastClosedDate)}` : " and every earlier day"}.`}
                </p>
                <div className="flex flex-wrap gap-2">
                  <Button variant="outline" size="sm" className="h-10 flex-1 bg-white" onClick={() => setViewOpen(true)}>
                    <Eye className="h-4 w-4 mr-2" /> Open closing
                  </Button>
                  {!p.isClosed && (
                    <Button size="sm" className="h-10 flex-1 bg-rose-600 hover:bg-rose-700" onClick={() => setCloseOpen(true)} disabled={p.openShifts > 0}>
                      <Lock className="h-4 w-4 mr-2" /> Close this day
                    </Button>
                  )}
                </div>
              </div>
            </div>
          )}

          {p && (p.openShifts > 0 || p.openOrders > 0 || p.unpaidOrders > 0) && !p.isClosed && (
            <Alert className="border-amber-200 bg-amber-50">
              <AlertTriangle className="h-4 w-4 text-amber-700" />
              <AlertDescription className="text-amber-900 text-sm space-y-1">
                {p.openShifts > 0 && <div><b>{p.openShifts} till shift{p.openShifts === 1 ? " is" : "s are"} still open.</b> Close {p.openShifts === 1 ? "it" : "them"} on <Link href="/restaurant-tills" className="underline">Tills & Shifts</Link> before closing the day.</div>}
                {p.openOrders > 0 && <div>{p.openOrders} order{p.openOrders === 1 ? " is" : "s are"} not finished. Payments taken on them later will count on the day they are taken.</div>}
                {p.unpaidOrders > 0 && <div>{p.unpaidOrders} order{p.unpaidOrders === 1 ? " has" : "s have"} money still owing.</div>}
              </AlertDescription>
            </Alert>
          )}

          <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Closed days</h2>
          {history.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500">No closings yet.</CardContent></Card>
          ) : (
            <Card><CardContent className="p-0 lg:p-4">
              <MobileCardList
                striped
                items={pg.pageItems}
                pagination={pg.paginationProps}
                getKey={(h) => h.closingId}
                primary={(h) => (
                  <span className="flex flex-wrap items-center gap-2">
                    <span>{nice(h.closingDate)}</span>
                    <Badge className={STATUS_COLORS[h.status] ?? "bg-gray-100"}>{h.status}</Badge>
                  </span>
                )}
                secondary={(h) => h.status === "Reopened" && h.reopenReason ? <span className="text-xs">Reopened: {h.reopenReason}</span> : null}
                highlights={(h) => [
                  { label: "Orders", value: String(h.orderCount), accent: "emerald" },
                  { label: "Net sales", value: gh(h.netSales), accent: "blue" },
                  { label: "Cash in − out", value: gh(h.moneyIn - h.moneyOut), accent: "violet", wide: true },
                ]}
                details={(h) => [
                  { label: "Money in", value: <span className="text-emerald-700">{gh(h.moneyIn)}</span> },
                  { label: "Money out", value: <span className="text-rose-700">{gh(h.moneyOut)}</span> },
                  { label: "Over / short", value: <span className={h.cashVariance < 0 ? "text-rose-700" : ""}>{gh(h.cashVariance)}</span> },
                  { label: "Closed by", value: h.closedBy ?? "—" },
                ]}
                actions={(h) => (
                  <>
                    <Button variant="outline" size="sm" className="h-10 flex-1 bg-white" onClick={() => openClosing(h.closingDate)}>
                      <Eye className="h-4 w-4 mr-2" /> Open closing
                    </Button>
                    {latestClosed?.closingId === h.closingId && (
                      <Button variant="outline" size="sm" className="h-10 flex-1 bg-white" onClick={() => { setReopenFor(h); setReason("") }}>
                        <LockOpen className="h-4 w-4 mr-2" /> Reopen
                      </Button>
                    )}
                  </>
                )}
                desktopTable={
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Date</TableHead><TableHead className="text-right">Orders</TableHead><TableHead className="text-right">Net sales</TableHead>
                        <TableHead className="text-right">Money in</TableHead><TableHead className="text-right">Money out</TableHead>
                        <TableHead className="text-right">Over / short</TableHead><TableHead>Status</TableHead><TableHead>Closed by</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {pg.pageItems.map((h) => (
                          <TableRow key={h.closingId}>
                            <TableCell className="font-medium">{nice(h.closingDate)}</TableCell>
                            <TableCell className="text-right">{h.orderCount}</TableCell>
                            <TableCell className="text-right">{gh(h.netSales)}</TableCell>
                            <TableCell className="text-right text-green-700">{gh(h.moneyIn)}</TableCell>
                            <TableCell className="text-right text-red-600">{gh(h.moneyOut)}</TableCell>
                            <TableCell className={cn("text-right", h.cashVariance < 0 && "text-red-600")}>{gh(h.cashVariance)}</TableCell>
                            <TableCell>
                              <Badge className={STATUS_COLORS[h.status] ?? "bg-gray-100"}>{h.status}</Badge>
                              {h.status === "Reopened" && h.reopenReason && <div className="text-xs text-muted-foreground mt-1">{h.reopenReason}</div>}
                            </TableCell>
                            <TableCell className="text-xs">{h.closedBy}<div className="text-muted-foreground">{new Date(h.closedAt).toLocaleString()}</div></TableCell>
                            <TableCell className="text-right whitespace-nowrap">
                              <Button variant="ghost" size="sm" title="Open closing" onClick={() => openClosing(h.closingDate)}><Eye className="w-4 h-4" /></Button>
                              {latestClosed?.closingId === h.closingId && (
                                <Button variant="outline" size="sm" onClick={() => { setReopenFor(h); setReason("") }}><LockOpen className="h-4 w-4 mr-1" />Reopen</Button>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                }
              />
            </CardContent></Card>
          )}
        </main>
      </div>

      {/* + New closing: pick the day, then review it. */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader><DialogTitle>New daily closing</DialogTitle>
            <DialogDescription>Pick the day to review. Nothing is locked until you press Close this day.</DialogDescription></DialogHeader>
          <div className="space-y-2"><Label>Closing date</Label><Input type="date" value={newDate} max={todayIso()} onChange={(e) => setNewDate(e.target.value)} /></div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setNewOpen(false)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={!newDate} onClick={() => { setNewOpen(false); openClosing(newDate) }}>Review day</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Open closing: the day's full figures. */}
      <Dialog open={viewOpen} onOpenChange={setViewOpen}>
        <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              Closing — {nice(date)} {p && <Badge className={STATUS_COLORS[p.isClosed ? "Closed" : "Open"]}>{p.isClosed ? "Closed" : "Open"}</Badge>}
            </DialogTitle>
          </DialogHeader>
          {p && (
            <div className="space-y-4">
              <div>
                <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Sales</div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                  <Tile label={`Net sales (${p.orderCount} orders)`} value={gh(p.netSales)} accent="green" />
                  <Tile label="Discounts given" value={gh(p.discounts)} />
                  <Tile label="Service charge" value={gh(p.serviceCharge)} />
                  <Tile label="Delivery fees" value={gh(p.deliveryFees)} />
                  <Tile label="Tax collected (owed)" value={gh(p.taxCollected)} />
                  <Tile label="Tips received" value={gh(p.tips)} />
                  <Tile label="Refunds given" value={gh(-p.refunds)} accent="rose" />
                </div>
              </div>
              <div>
                <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Money</div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                  <Tile label="Cash" value={gh(p.takingsCash)} />
                  <Tile label="Card" value={gh(p.takingsCard)} />
                  <Tile label="Mobile money" value={gh(p.takingsMobile)} />
                  <Tile label="Gift cards (no cash)" value={gh(p.takingsGiftCard)} />
                  {p.takingsOther > 0 && <Tile label="Other" value={gh(p.takingsOther)} />}
                  <Tile label="Total takings" value={gh(takings)} accent="green" />
                  <Tile label="Expenses dated this day" value={gh(-p.expenses)} accent="rose" />
                  <Tile label="Money in" value={gh(p.moneyIn)} accent="green" />
                  <Tile label="Money out" value={gh(p.moneyOut)} accent="rose" />
                  <Tile label="Cash over / short" value={gh(p.cashVariance)} />
                </div>
                <p className="mt-2 text-xs text-slate-500">Money in and out are every account's ledger for the day (transfers between your own accounts excluded).</p>
              </div>
              <div className="border-t pt-4 flex flex-wrap justify-end gap-2">
                {!p.isClosed && (
                  <Button className="bg-rose-600 hover:bg-rose-700 mr-auto" onClick={() => setCloseOpen(true)} disabled={p.openShifts > 0}>
                    <Lock className="h-4 w-4 mr-1" /> Close this day
                  </Button>
                )}
                <Button variant="outline" onClick={() => setViewOpen(false)}>Close</Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

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

/** Poultry's closing-card tiles, with restaurant words: Orders / Net sales / Cash in − out. */
function DayTiles({ orders, sales, cash }: { orders: number; sales: string; cash: string }) {
  return (
    <div className="grid grid-cols-2 gap-2">
      <div className="rounded-lg bg-emerald-100 border border-emerald-300 px-3 py-2 shadow-sm">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">Orders</p>
        <p className="text-xl font-extrabold leading-tight text-emerald-800">{orders}</p>
      </div>
      <div className="rounded-lg bg-blue-100 border border-blue-300 px-3 py-2 shadow-sm">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-blue-900">Net sales</p>
        <p className="text-xl font-extrabold leading-tight text-blue-800 break-words">{sales}</p>
      </div>
      <div className="col-span-2 rounded-lg bg-violet-100 border border-violet-300 px-3 py-2 shadow-sm">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-violet-900">Cash in − out</p>
        <p className="text-xl font-extrabold leading-tight text-violet-900">{cash}</p>
      </div>
    </div>
  )
}

function Tile({ label, value, accent }: { label: string; value: string; accent?: "green" | "rose" }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-[11px] text-slate-500">{label}</div>
      <div className={cn("font-semibold tabular-nums", accent === "green" ? "text-emerald-700" : accent === "rose" ? "text-rose-700" : "text-slate-900")}>{value}</div>
    </div>
  )
}

"use client"

/**
 * Hotel Daily Closing — the end-of-day snapshot.
 *
 * Presented the Poultry way (app/poultry-daily-closing), through the Restaurant's
 * copy (app/restaurant-daily-closing): a plain header with "+ New closing", one
 * card per closing with coloured tiles (Rooms occupied / Revenue / Net) and the
 * rest of the day underneath, an "Open closing" button, and "View table format"
 * on a phone. Hotel words replace Poultry's production tiles.
 *
 * The Hotel's behaviour is unchanged: closing a day saves a snapshot of its
 * occupancy, revenue, expenses, ADR and RevPAR (createDailyClosing). It does not
 * lock the books, so there is nothing to reopen.
 */

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Eye, Loader2, Lock, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  listDailyClosings, createDailyClosing, getHotelRoomStatusSummary, listHotelBookings, listHotelPayments, listHotelExpenses,
  type HotelDailyClosing,
} from "@/lib/api/hotel"

const todayIso = () => new Date().toISOString().slice(0, 10)
const nice = (iso?: string | null) => (iso ? new Date(`${iso.slice(0, 10)}T00:00:00`).toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short", year: "numeric" }) : "—")

/** A saved closing, read whatever case the API returns. */
function closingOf(i: any) {
  const revenue = Number(i.totalRevenue ?? i.totalrevenue ?? 0)
  const expenses = Number(i.totalExpenses ?? i.totalexpenses ?? 0)
  return {
    id: i.hotelDailyClosingId ?? i.hoteldailyclosingid,
    date: String(i.closingDate ?? i.closingdate ?? "").slice(0, 10),
    revenue, expenses, net: revenue - expenses,
    occupancy: Number(i.occupancyRate ?? i.occupancyrate ?? 0),
    occupied: Number(i.roomsOccupied ?? i.roomsoccupied ?? 0),
    rooms: Number(i.totalRooms ?? i.totalrooms ?? 0),
    adr: Number(i.adr ?? 0),
    revpar: Number(i.revPar ?? i.revpar ?? 0),
    notes: (i.notes ?? "") as string,
    closedBy: (i.closedBy ?? i.closedby ?? i.createdBy ?? i.createdby ?? null) as string | null,
  }
}
type Closing = ReturnType<typeof closingOf>

export default function HotelDailyClosingPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelDailyClosing[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ closingDate: todayIso(), notes: "" })
  const [viewing, setViewing] = useState<Closing | null>(null)

  // The day as it stands now (the snapshot a closing will save).
  const [live, setLive] = useState({ totalRooms: 0, occupied: 0, available: 0, revenue: 0, expenses: 0, arrivals: 0, departures: 0, checkedIn: 0 })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router]) // eslint-disable-line react-hooks/exhaustive-deps

  async function load() {
    setLoading(true)
    try {
      setItems(await listDailyClosings())
      const [roomStatus, bookings, payments, expenses] = await Promise.all([
        getHotelRoomStatusSummary().catch(() => []),
        listHotelBookings().catch(() => []),
        listHotelPayments().catch(() => []),
        listHotelExpenses().catch(() => []),
      ])
      const today = todayIso()
      const count = (r: any) => Number(r.roomCount ?? r.roomcount ?? 0)
      const statusOf = (r: any) => r.status ?? r.Status
      const totalRooms = (roomStatus as any[]).reduce((s: number, r: any) => s + count(r), 0)
      const occupied = count((roomStatus as any[]).find((r: any) => statusOf(r) === "Occupied") ?? {})
      const available = count((roomStatus as any[]).find((r: any) => statusOf(r) === "Available") ?? {})
      const revenue = (payments as any[]).filter((p: any) => (p.paymentDate ?? p.paymentdate ?? "").slice(0, 10) === today && (p.status ?? "Posted") !== "Void")
        .reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
      const expenseTotal = (expenses as any[]).filter((e: any) => (e.expenseDate ?? e.expensedate ?? "").slice(0, 10) === today)
        .reduce((s: number, e: any) => s + Number(e.amount ?? 0), 0)
      const arrivals = bookings.filter((b) => b.checkInDate?.slice(0, 10) === today && b.status === "Confirmed").length
      const departures = bookings.filter((b) => b.checkOutDate?.slice(0, 10) === today && b.status === "CheckedIn").length
      const checkedIn = bookings.filter((b) => b.status === "CheckedIn").length
      setLive({ totalRooms, occupied, available, revenue, expenses: expenseTotal, arrivals, departures, checkedIn })
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function handleClose() {
    setSaving(true)
    try { await createDailyClosing(form); toast({ title: "Day closed successfully" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  const history = useMemo(() => items.map(closingOf).sort((a, b) => b.date.localeCompare(a.date)), [items])
  const pg = usePagination(history, 20)
  const occRate = live.totalRooms > 0 ? Math.round((live.occupied / live.totalRooms) * 100) : 0
  const liveNet = live.revenue - live.expenses
  const todayClosed = history.some((h) => h.date === todayIso())
  const openNew = (date = todayIso()) => { setForm({ closingDate: date, notes: "" }); setDialogOpen(true) }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4 pb-24 lg:pb-6">
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <h1 className="text-2xl font-bold">Daily Closing</h1>
            <p className="text-sm text-slate-500">End-of-day rooms, revenue and expenses snapshot.</p>
          </div>
          <Button className="shrink-0 bg-violet-600 hover:bg-violet-700" onClick={() => openNew()}>
            <Plus className="w-4 h-4 mr-1" /> New closing
          </Button>
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (<>
          {/* Today, as it stands now. */}
          <div className="rounded-xl border shadow-sm overflow-hidden bg-violet-50 border-violet-200">
            <div className="px-3 py-3 space-y-3">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-semibold text-slate-900">{nice(todayIso())}</span>
                <Badge className={todayClosed ? "bg-green-100 text-green-800 hover:bg-green-100" : "bg-slate-100 text-slate-700 hover:bg-slate-100"}>
                  {todayClosed ? "Closed" : "Open"}
                </Badge>
              </div>
              <DayTiles rooms={`${live.occupied}/${live.totalRooms}`} revenue={gh(live.revenue)} net={gh(liveNet)} netNegative={liveNet < 0} />
              <div className="grid grid-cols-2 gap-2 text-sm pt-1 border-t border-violet-200/70">
                <div><span className="text-slate-500">Expenses</span> <span className="font-medium text-rose-700">{gh(live.expenses)}</span></div>
                <div><span className="text-slate-500">Occupancy</span> <span className="font-medium">{occRate}%</span></div>
                <div><span className="text-slate-500">In-house</span> <span className="font-medium">{live.checkedIn}</span></div>
                <div><span className="text-slate-500">Arrivals / departures</span> <span className="font-medium">{live.arrivals} / {live.departures}</span></div>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button variant="outline" size="sm" className="h-10 flex-1 bg-white"
                        onClick={() => setViewing({ id: 0, date: todayIso(), revenue: live.revenue, expenses: live.expenses, net: liveNet,
                          occupancy: occRate, occupied: live.occupied, rooms: live.totalRooms,
                          adr: live.occupied > 0 ? live.revenue / live.occupied : 0,
                          revpar: live.totalRooms > 0 ? live.revenue / live.totalRooms : 0, notes: "", closedBy: null })}>
                  <Eye className="h-4 w-4 mr-2" /> Open closing
                </Button>
                {!todayClosed && (
                  <Button size="sm" className="h-10 flex-1 bg-violet-600 hover:bg-violet-700" onClick={() => openNew()}>
                    <Lock className="h-4 w-4 mr-2" /> Close this day
                  </Button>
                )}
              </div>
            </div>
          </div>

          <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Closed days</h2>
          {history.length === 0 ? (
            <Card><CardContent className="p-8 text-center text-slate-500">No closings yet. Use "New closing" to record today&apos;s snapshot.</CardContent></Card>
          ) : (
            <Card><CardContent className="p-0 lg:p-4">
              <MobileCardList
                striped
                items={pg.pageItems}
                pagination={pg.paginationProps}
                getKey={(h) => h.id ?? h.date}
                primary={(h) => (
                  <span className="flex flex-wrap items-center gap-2">
                    <span>{nice(h.date)}</span>
                    <Badge className="bg-green-100 text-green-800 hover:bg-green-100">Closed</Badge>
                  </span>
                )}
                secondary={(h) => (h.notes ? <span className="text-xs">{h.notes}</span> : null)}
                highlights={(h) => [
                  { label: "Rooms occupied", value: `${h.occupied}/${h.rooms}`, accent: "emerald" },
                  { label: "Revenue", value: gh(h.revenue), accent: "blue" },
                  { label: "Net (revenue − expenses)", value: gh(h.net), accent: "violet", wide: true },
                ]}
                details={(h) => [
                  { label: "Expenses", value: <span className="text-rose-700">{gh(h.expenses)}</span> },
                  { label: "Occupancy", value: `${h.occupancy.toFixed(1)}%` },
                  { label: "ADR", value: gh(h.adr) },
                  { label: "RevPAR", value: gh(h.revpar) },
                ]}
                actions={(h) => (
                  <Button variant="outline" size="sm" className="h-10 flex-1 bg-white" onClick={() => setViewing(h)}>
                    <Eye className="h-4 w-4 mr-2" /> Open closing
                  </Button>
                )}
                desktopTable={
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Date</TableHead><TableHead className="text-right">Revenue</TableHead><TableHead className="text-right">Expenses</TableHead>
                        <TableHead className="text-right">Net</TableHead><TableHead className="text-right">Occupancy</TableHead><TableHead className="text-right">Rooms</TableHead>
                        <TableHead className="text-right">ADR</TableHead><TableHead className="text-right">RevPAR</TableHead><TableHead>Notes</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {pg.pageItems.map((h) => (
                          <TableRow key={h.id ?? h.date}>
                            <TableCell className="font-medium">{nice(h.date)}</TableCell>
                            <TableCell className="text-right text-emerald-700 font-semibold">{gh(h.revenue)}</TableCell>
                            <TableCell className="text-right text-red-600">{gh(h.expenses)}</TableCell>
                            <TableCell className={cn("text-right font-bold", h.net >= 0 ? "text-emerald-700" : "text-red-700")}>{gh(h.net)}</TableCell>
                            <TableCell className="text-right">{h.occupancy.toFixed(1)}%</TableCell>
                            <TableCell className="text-right">{h.occupied}/{h.rooms}</TableCell>
                            <TableCell className="text-right">{gh(h.adr)}</TableCell>
                            <TableCell className="text-right">{gh(h.revpar)}</TableCell>
                            <TableCell className="text-xs text-slate-500">{h.notes}</TableCell>
                            <TableCell className="text-right"><Button variant="ghost" size="sm" title="Open closing" onClick={() => setViewing(h)}><Eye className="w-4 h-4" /></Button></TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                }
              />
            </CardContent></Card>
          )}
        </>)}

        {/* + New closing / Close this day */}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>New daily closing</DialogTitle>
            <DialogDescription>Saves the day&apos;s snapshot: occupancy, revenue, expenses, ADR and RevPAR.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="p-4 bg-violet-50 rounded-lg space-y-2">
              <p className="text-sm font-semibold text-violet-700">Today as it stands:</p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-sm">
                <div>Occupancy: <strong>{occRate}%</strong> ({live.occupied}/{live.totalRooms})</div>
                <div>Revenue: <strong className="text-emerald-700">{gh(live.revenue)}</strong></div>
                <div>Expenses: <strong className="text-red-700">{gh(live.expenses)}</strong></div>
                <div>Net: <strong className={liveNet >= 0 ? "text-emerald-700" : "text-red-700"}>{gh(liveNet)}</strong></div>
                <div>In-house guests: <strong>{live.checkedIn}</strong></div>
                <div>ADR: <strong>{gh(live.occupied > 0 ? live.revenue / live.occupied : 0)}</strong></div>
              </div>
            </div>
            <div className="space-y-1.5"><Label>Closing date</Label><Input type="date" value={form.closingDate} max={todayIso()} onChange={(e) => setForm({ ...form, closingDate: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>Notes</Label><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} placeholder="Optional notes about the day" /></div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
            <Button onClick={handleClose} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Close the day</Button>
          </DialogFooter>
        </DialogContent></Dialog>

        {/* Open closing: the day's full figures. */}
        <Dialog open={!!viewing} onOpenChange={(o) => { if (!o) setViewing(null) }}>
          <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
            <DialogHeader><DialogTitle>Closing — {nice(viewing?.date)}</DialogTitle></DialogHeader>
            {viewing && (
              <div className="space-y-4">
                <div>
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Rooms</div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                    <Tile label="Rooms occupied" value={`${viewing.occupied}/${viewing.rooms}`} />
                    <Tile label="Occupancy" value={`${viewing.occupancy.toFixed(1)}%`} />
                    <Tile label="ADR" value={gh(viewing.adr)} />
                    <Tile label="RevPAR" value={gh(viewing.revpar)} />
                  </div>
                </div>
                <div>
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Money</div>
                  <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
                    <Tile label="Revenue" value={gh(viewing.revenue)} accent="green" />
                    <Tile label="Expenses" value={gh(-viewing.expenses)} accent="rose" />
                    <Tile label="Net" value={gh(viewing.net)} accent={viewing.net < 0 ? "rose" : "green"} />
                  </div>
                  <p className="mt-2 text-xs text-slate-500">Revenue is the guest payments received that day; expenses are the expenses dated that day.</p>
                </div>
                {viewing.notes && <p className="text-sm text-slate-600">{viewing.notes}</p>}
                <div className="border-t pt-4 flex flex-wrap justify-end gap-2">
                  {viewing.id === 0 && !todayClosed && (
                    <Button className="bg-violet-600 hover:bg-violet-700 mr-auto" onClick={() => { setViewing(null); openNew() }}>
                      <Lock className="h-4 w-4 mr-1" /> Close this day
                    </Button>
                  )}
                  <Button variant="outline" onClick={() => setViewing(null)}>Close</Button>
                </div>
              </div>
            )}
          </DialogContent>
        </Dialog>
      </main></div></div>
  )
}

/** Poultry's closing-card tiles, with hotel words: Rooms occupied / Revenue / Net. */
function DayTiles({ rooms, revenue, net, netNegative }: { rooms: string; revenue: string; net: string; netNegative: boolean }) {
  return (
    <div className="grid grid-cols-2 gap-2">
      <div className="rounded-lg bg-emerald-100 border border-emerald-300 px-3 py-2 shadow-sm">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">Rooms occupied</p>
        <p className="text-xl font-extrabold leading-tight text-emerald-800">{rooms}</p>
      </div>
      <div className="rounded-lg bg-blue-100 border border-blue-300 px-3 py-2 shadow-sm">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-blue-900">Revenue</p>
        <p className="text-xl font-extrabold leading-tight text-blue-800 break-words">{revenue}</p>
      </div>
      <div className="col-span-2 rounded-lg bg-violet-100 border border-violet-300 px-3 py-2 shadow-sm">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-violet-900">Net (revenue − expenses)</p>
        <p className={cn("text-xl font-extrabold leading-tight", netNegative ? "text-rose-700" : "text-violet-900")}>{net}</p>
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

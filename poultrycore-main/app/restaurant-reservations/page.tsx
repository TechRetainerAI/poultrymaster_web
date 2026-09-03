"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Trash2, Edit2, CalendarDays, Users, Clock, ChevronLeft, ChevronRight, Star, MapPin, Phone, AlertTriangle } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listReservations, createReservation, updateReservation, updateReservationStatus, deleteReservation,
  getReservationStats, autoAssignTable,
  listWaitlist, addToWaitlist, updateWaitlistStatus, deleteFromWaitlist, getWaitlistStats,
  listTables,
  type Reservation, type ReservationInput, type ReservationStats,
  type WaitlistEntry, type WaitlistInput, type WaitlistStats, type RestaurantTable,
} from "@/lib/api/restaurant"

const STATUS_COLORS: Record<string, string> = { Pending: "bg-amber-100 text-amber-700", Confirmed: "bg-blue-100 text-blue-700", Seated: "bg-green-100 text-green-700", Completed: "bg-gray-100 text-gray-700", Cancelled: "bg-red-100 text-red-700", NoShow: "bg-red-200 text-red-800" }
const OCCASIONS = ["", "Birthday", "Anniversary", "Business", "Date", "Celebration", "Other"]
const SOURCES = ["Phone", "WalkIn", "Online", "App"]

export default function RestaurantReservationsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [selectedDate, setSelectedDate] = useState(new Date().toISOString().split("T")[0])
  const [reservations, setReservations] = useState<Reservation[]>([])
  const [resStats, setResStats] = useState<ReservationStats | null>(null)
  const [waitlist, setWaitlist] = useState<WaitlistEntry[]>([])
  const [waitStats, setWaitStats] = useState<WaitlistStats | null>(null)
  const [tables, setTables] = useState<RestaurantTable[]>([])
  const [resDialogOpen, setResDialogOpen] = useState(false)
  const [resEditing, setResEditing] = useState<Reservation | null>(null)
  const [resForm, setResForm] = useState<ReservationInput>({ reservationDate: selectedDate, reservationTime: "19:00", partySize: 2, guestName: "" })
  const [suggestedTables, setSuggestedTables] = useState<{ tableId: number; tableNumber: string; capacity: number }[]>([])
  const [waitDialogOpen, setWaitDialogOpen] = useState(false)
  const [waitForm, setWaitForm] = useState<WaitlistInput>({ guestName: "", partySize: 2, estimatedWaitMins: 15 })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])
  useEffect(() => { if (!loading) loadReservations() }, [selectedDate])

  async function loadAll() {
    setLoading(true)
    try { setTables(await listTables()); await loadReservations(); await loadWaitlist() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }
  async function loadReservations() { try { const [res, stats] = await Promise.all([listReservations(selectedDate), getReservationStats(selectedDate)]); setReservations(res); setResStats(stats) } catch {} }
  async function loadWaitlist() { try { const [wl, ws] = await Promise.all([listWaitlist(), getWaitlistStats()]); setWaitlist(wl.filter(w => w.status === "Waiting" || w.status === "Notified")); setWaitStats(ws) } catch {} }

  function changeDate(d: number) { const dt = new Date(selectedDate); dt.setDate(dt.getDate() + d); setSelectedDate(dt.toISOString().split("T")[0]) }

  function openResDialog(r?: Reservation) {
    if (r) { setResEditing(r); setResForm({ reservationDate: r.reservationDate.split("T")[0], reservationTime: r.reservationTime, endTime: r.endTime, partySize: r.partySize, guestName: r.guestName, guestPhone: r.guestPhone, guestEmail: r.guestEmail, tableId: r.tableId, tableNumber: r.tableNumber, specialRequests: r.specialRequests, occasion: r.occasion, source: r.source, isVip: r.isVip, notes: r.notes }) }
    else { setResEditing(null); setResForm({ reservationDate: selectedDate, reservationTime: "19:00", partySize: 2, guestName: "", source: "Phone" }) }
    setSuggestedTables([]); setResDialogOpen(true)
  }
  async function findTables() { try { setSuggestedTables(await autoAssignTable(resForm.partySize, resForm.reservationDate, resForm.reservationTime)) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function saveRes() {
    if (!resForm.guestName.trim()) { toast({ title: "Guest name required", variant: "destructive" }); return }
    try { if (resEditing) await updateReservation(resEditing.reservationId, resForm); else await createReservation(resForm)
      toast({ title: resEditing ? "Updated" : "Reservation created" }); setResDialogOpen(false); loadReservations()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function changeResStatus(id: number, s: string) { try { await updateReservationStatus(id, s); toast({ title: `${s}` }); loadReservations() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function removeRes(id: number) { try { await deleteReservation(id); loadReservations() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  async function saveWait() {
    if (!waitForm.guestName.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    try { await addToWaitlist(waitForm); toast({ title: "Added to waitlist" }); setWaitDialogOpen(false); loadWaitlist() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function changeWaitStatus(id: number, status: string, tableId?: number, tableNumber?: string) {
    try { await updateWaitlistStatus(id, status, tableId, tableNumber); toast({ title: status === "Seated" ? "Guest seated!" : status }); loadWaitlist() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function removeWait(id: number) { try { await deleteFromWaitlist(id); loadWaitlist() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center"><CalendarDays className="h-5 w-5 text-rose-600" /></div>
                <div><h1 className="text-2xl font-bold text-gray-900">Reservations & Waitlist</h1><p className="text-sm text-muted-foreground">Manage bookings and walk-in guests</p></div>
              </div>
            </div>

            <Tabs defaultValue="reservations" className="space-y-4">
              <TabsList className="bg-white border shadow-sm">
                <TabsTrigger value="reservations" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <CalendarDays className="h-4 w-4 mr-2" /> Reservations
                  {resStats && <Badge variant="secondary" className="ml-2 h-5 px-1.5">{resStats.totalCount}</Badge>}
                </TabsTrigger>
                <TabsTrigger value="waitlist" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <Users className="h-4 w-4 mr-2" /> Waitlist
                  {waitStats && waitStats.waitingCount > 0 && <Badge className="ml-2 h-5 px-1.5 bg-amber-500 text-white">{waitStats.waitingCount}</Badge>}
                </TabsTrigger>
              </TabsList>

              <TabsContent value="reservations" className="space-y-4">
                {/* Date nav + stats */}
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Button variant="outline" size="icon" className="h-9 w-9" onClick={() => changeDate(-1)}><ChevronLeft className="h-4 w-4" /></Button>
                    <Input type="date" className="w-[170px] h-9" value={selectedDate} onChange={e => setSelectedDate(e.target.value)} />
                    <Button variant="outline" size="icon" className="h-9 w-9" onClick={() => changeDate(1)}><ChevronRight className="h-4 w-4" /></Button>
                    <Button variant="outline" size="sm" className="h-9" onClick={() => setSelectedDate(new Date().toISOString().split("T")[0])}>Today</Button>
                  </div>
                  {resStats && (
                    <div className="flex gap-3 text-sm">
                      {[["Confirmed", resStats.confirmedCount, "text-blue-600"], ["Seated", resStats.seatedCount, "text-green-600"], ["Covers", resStats.totalCovers, "text-gray-900"],
                        ...(resStats.noShowCount > 0 ? [["No-Show", resStats.noShowCount, "text-red-600"]] : [])
                      ].map(([l, v, c]) => <span key={String(l)} className={String(c)}><strong>{String(v)}</strong> {l}</span>)}
                    </div>
                  )}
                  <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openResDialog()}><Plus className="h-4 w-4 mr-2" /> New Reservation</Button>
                </div>

                <Card>
                  <CardContent className="pt-4">
                    {reservations.length === 0 ? (
                      <div className="text-center py-16 border-2 border-dashed rounded-xl">
                        <CalendarDays className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No reservations for this date</h3>
                        <p className="text-sm text-muted-foreground mb-4">Create a reservation or try a different date</p>
                        <Button variant="outline" onClick={() => openResDialog()}><Plus className="h-4 w-4 mr-2" /> Add Reservation</Button>
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {reservations.map(r => (
                          <div key={r.reservationId} className="group flex items-center gap-4 p-4 border rounded-xl hover:border-rose-200 transition-all">
                            <div className="text-center min-w-[65px] flex-shrink-0">
                              <div className="font-bold text-xl text-gray-900">{r.reservationTime}</div>
                              {r.endTime && <div className="text-[10px] text-muted-foreground">to {r.endTime}</div>}
                            </div>
                            <div className="h-10 w-px bg-gray-200 flex-shrink-0" />
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2">
                                <span className="font-semibold text-gray-900">{r.guestName}</span>
                                {r.isVip && <Badge className="text-[10px] h-4 bg-purple-100 text-purple-700 hover:bg-purple-100"><Star className="h-2.5 w-2.5 mr-0.5" />VIP</Badge>}
                                <Badge className={`text-[10px] h-5 ${STATUS_COLORS[r.status] || "bg-gray-100 text-gray-700"} hover:${STATUS_COLORS[r.status]}`}>{r.status}</Badge>
                              </div>
                              <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground">
                                <span className="flex items-center gap-1"><Users className="h-3 w-3" />{r.partySize}</span>
                                {r.tableNumber && <span className="flex items-center gap-1"><MapPin className="h-3 w-3" />Table {r.tableNumber}</span>}
                                {r.occasion && <span>{r.occasion}</span>}
                                {r.guestPhone && <span className="flex items-center gap-1"><Phone className="h-3 w-3" />{r.guestPhone}</span>}
                              </div>
                              {r.specialRequests && <div className="text-xs text-amber-700 mt-1 flex items-center gap-1"><AlertTriangle className="h-3 w-3" />{r.specialRequests}</div>}
                            </div>
                            <div className="flex items-center gap-1 flex-shrink-0">
                              {r.status === "Pending" && <Button size="sm" className="h-7 text-xs bg-blue-600 hover:bg-blue-700" onClick={() => changeResStatus(r.reservationId, "Confirmed")}>Confirm</Button>}
                              {r.status === "Confirmed" && <Button size="sm" className="h-7 text-xs bg-green-600 hover:bg-green-700" onClick={() => changeResStatus(r.reservationId, "Seated")}>Seat</Button>}
                              {r.status === "Seated" && <Button size="sm" variant="outline" className="h-7 text-xs" onClick={() => changeResStatus(r.reservationId, "Completed")}>Complete</Button>}
                              {(r.status === "Confirmed" || r.status === "Pending") && (
                                <>
                                  <Button size="sm" variant="ghost" className="h-7 text-xs text-red-600" onClick={() => changeResStatus(r.reservationId, "NoShow")}>No-Show</Button>
                                  <Button size="sm" variant="ghost" className="h-7 text-xs text-red-500" onClick={() => changeResStatus(r.reservationId, "Cancelled")}>Cancel</Button>
                                </>
                              )}
                              <Button variant="ghost" size="icon" className="h-7 w-7 opacity-0 group-hover:opacity-100" onClick={() => openResDialog(r)}><Edit2 className="h-3 w-3" /></Button>
                              <Button variant="ghost" size="icon" className="h-7 w-7 opacity-0 group-hover:opacity-100" onClick={() => removeRes(r.reservationId)}><Trash2 className="h-3 w-3 text-red-500" /></Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="waitlist" className="space-y-4">
                <div className="flex items-center justify-between">
                  {waitStats && (
                    <div className="flex gap-4 text-sm">
                      <span className="text-amber-600"><strong>{waitStats.waitingCount}</strong> Waiting</span>
                      <span className="text-blue-600"><strong>{waitStats.notifiedCount}</strong> Notified</span>
                      {waitStats.avgWaitMins != null && <span>Avg: <strong>{Math.floor(waitStats.avgWaitMins)}m</strong></span>}
                      {waitStats.longestWaitMins != null && waitStats.longestWaitMins > 0 && (
                        <span className={waitStats.longestWaitMins > 30 ? "text-red-600 font-bold" : ""}>Max: {Math.floor(waitStats.longestWaitMins)}m</span>
                      )}
                    </div>
                  )}
                  <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => { setWaitForm({ guestName: "", partySize: 2, estimatedWaitMins: 15 }); setWaitDialogOpen(true) }}>
                    <Plus className="h-4 w-4 mr-2" /> Add to Waitlist
                  </Button>
                </div>

                <Card>
                  <CardContent className="pt-4">
                    {waitlist.length === 0 ? (
                      <div className="text-center py-16 border-2 border-dashed rounded-xl">
                        <Users className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No guests waiting</h3>
                        <p className="text-sm text-muted-foreground">Walk-in guests will appear here when added to the waitlist</p>
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {waitlist.map((w, idx) => (
                          <div key={w.waitlistId} className="flex items-center gap-4 p-4 border rounded-xl hover:border-rose-200 transition-all">
                            <div className="h-10 w-10 rounded-xl bg-amber-100 flex items-center justify-center font-bold text-amber-700 flex-shrink-0">{idx + 1}</div>
                            <div className="flex-1">
                              <div className="font-semibold text-gray-900">{w.guestName}</div>
                              <div className="flex items-center gap-3 mt-0.5 text-xs text-muted-foreground">
                                <span className="flex items-center gap-1"><Users className="h-3 w-3" />{w.partySize}</span>
                                {w.guestPhone && <span className="flex items-center gap-1"><Phone className="h-3 w-3" />{w.guestPhone}</span>}
                                <span className="flex items-center gap-1"><Clock className="h-3 w-3" />{w.actualWaitMins != null ? `${Math.floor(w.actualWaitMins)}m` : "—"}</span>
                                {w.quotedWaitMins && <span>(quoted {w.quotedWaitMins}m)</span>}
                              </div>
                            </div>
                            <Badge className={`text-xs ${w.status === "Waiting" ? "bg-amber-100 text-amber-700" : "bg-blue-100 text-blue-700"} hover:bg-amber-100`}>{w.status}</Badge>
                            <div className="flex items-center gap-1 flex-shrink-0">
                              {w.status === "Waiting" && <Button size="sm" className="h-7 text-xs bg-blue-600" onClick={() => changeWaitStatus(w.waitlistId, "Notified")}>Notify</Button>}
                              {(w.status === "Waiting" || w.status === "Notified") && (
                                <Select onValueChange={v => { const t = tables.find(t => t.tableId === parseInt(v)); if (t) changeWaitStatus(w.waitlistId, "Seated", t.tableId, t.tableNumber) }}>
                                  <SelectTrigger className="w-[120px] h-7 text-xs"><SelectValue placeholder="Seat at..." /></SelectTrigger>
                                  <SelectContent>{tables.filter(t => t.status === "Available").map(t => <SelectItem key={t.tableId} value={String(t.tableId)}>Table {t.tableNumber}</SelectItem>)}</SelectContent>
                                </Select>
                              )}
                              <Button variant="ghost" size="sm" className="h-7 text-xs text-red-500" onClick={() => changeWaitStatus(w.waitlistId, "Left")}>Left</Button>
                              <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => removeWait(w.waitlistId)}><Trash2 className="h-3 w-3 text-red-500" /></Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      {/* Reservation Dialog */}
      <Dialog open={resDialogOpen} onOpenChange={setResDialogOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader><DialogTitle>{resEditing ? "Edit Reservation" : "New Reservation"}</DialogTitle><DialogDescription>Book a table for your guest</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Guest Name <span className="text-rose-500">*</span></Label><Input value={resForm.guestName} onChange={e => setResForm({ ...resForm, guestName: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Phone</Label><Input value={resForm.guestPhone || ""} onChange={e => setResForm({ ...resForm, guestPhone: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Date</Label><Input type="date" value={resForm.reservationDate} onChange={e => setResForm({ ...resForm, reservationDate: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Time</Label><Input type="time" value={resForm.reservationTime} onChange={e => setResForm({ ...resForm, reservationTime: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Party Size</Label><Input type="number" min={1} value={resForm.partySize} onChange={e => setResForm({ ...resForm, partySize: parseInt(e.target.value) || 2 })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Occasion</Label>
                <Select value={resForm.occasion || ""} onValueChange={v => setResForm({ ...resForm, occasion: v || undefined })}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="None" /></SelectTrigger>
                  <SelectContent>{OCCASIONS.map(o => <SelectItem key={o || "none"} value={o || "none"}>{o || "None"}</SelectItem>)}</SelectContent>
                </Select></div>
            </div>
            <div className="space-y-1.5">
              <Label>Table</Label>
              <div className="flex gap-2">
                <Select value={resForm.tableId ? String(resForm.tableId) : "auto"} onValueChange={v => { if (v === "auto") setResForm({ ...resForm, tableId: undefined, tableNumber: undefined }); else { const t = tables.find(t => t.tableId === parseInt(v)); setResForm({ ...resForm, tableId: parseInt(v), tableNumber: t?.tableNumber }) } }}>
                  <SelectTrigger className="flex-1 h-10"><SelectValue placeholder="Auto-assign" /></SelectTrigger>
                  <SelectContent><SelectItem value="auto">Auto-assign</SelectItem>{tables.map(t => <SelectItem key={t.tableId} value={String(t.tableId)}>Table {t.tableNumber} ({t.capacity})</SelectItem>)}</SelectContent>
                </Select>
                <Button variant="outline" onClick={findTables}>Find</Button>
              </div>
              {suggestedTables.length > 0 && <div className="flex gap-1 mt-1">{suggestedTables.map(t => <Button key={t.tableId} variant="outline" size="sm" className="text-xs" onClick={() => setResForm({ ...resForm, tableId: t.tableId, tableNumber: t.tableNumber })}>T{t.tableNumber} ({t.capacity})</Button>)}</div>}
            </div>
            <div className="space-y-1.5"><Label>Special Requests</Label><Input value={resForm.specialRequests || ""} onChange={e => setResForm({ ...resForm, specialRequests: e.target.value })} placeholder="e.g. Window seat, high chair" className="h-10" /></div>
            <label className="flex items-center gap-2 cursor-pointer"><input type="checkbox" checked={resForm.isVip || false} onChange={e => setResForm({ ...resForm, isVip: e.target.checked })} className="h-4 w-4 rounded border-gray-300 text-rose-600" /><span className="text-sm font-medium">VIP Guest</span></label>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setResDialogOpen(false)}>Cancel</Button><Button onClick={saveRes} className="bg-rose-600 hover:bg-rose-700">{resEditing ? "Update" : "Create Reservation"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Waitlist Dialog */}
      <Dialog open={waitDialogOpen} onOpenChange={setWaitDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>Add to Waitlist</DialogTitle><DialogDescription>Walk-in guest waiting for a table</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Guest Name <span className="text-rose-500">*</span></Label><Input value={waitForm.guestName} onChange={e => setWaitForm({ ...waitForm, guestName: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Phone</Label><Input value={waitForm.guestPhone || ""} onChange={e => setWaitForm({ ...waitForm, guestPhone: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Party Size</Label><Input type="number" min={1} value={waitForm.partySize} onChange={e => setWaitForm({ ...waitForm, partySize: parseInt(e.target.value) || 2 })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Est. Wait (min)</Label><Input type="number" value={waitForm.estimatedWaitMins || 15} onChange={e => setWaitForm({ ...waitForm, estimatedWaitMins: parseInt(e.target.value) || 15 })} className="h-10" /></div>
            </div>
            <div className="space-y-1.5"><Label>Notes</Label><Input value={waitForm.notes || ""} onChange={e => setWaitForm({ ...waitForm, notes: e.target.value })} className="h-10" /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setWaitDialogOpen(false)}>Cancel</Button><Button onClick={saveWait} className="bg-rose-600 hover:bg-rose-700">Add to Waitlist</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

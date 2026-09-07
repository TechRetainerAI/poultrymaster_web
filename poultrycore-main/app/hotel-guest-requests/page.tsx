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
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, Bell, Plus, Play, CheckCircle2, XCircle, Search, Clock, AlertTriangle, User } from "lucide-react"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listGuestRequests, createGuestRequest, updateGuestRequestStatus,
  listHotelBookings, listHotelRooms, listHotelRequestTypes, listHotelStaff,
  type HotelBooking, type HotelRoom, type HotelRequestType, type HotelStaff,
} from "@/lib/api/hotel"

const STATUS_COLORS: Record<string, string> = {
  Pending: "bg-amber-100 text-amber-700",
  InProgress: "bg-blue-100 text-blue-700",
  Completed: "bg-emerald-100 text-emerald-700",
  Cancelled: "bg-red-100 text-red-700",
}

export default function HotelGuestRequestsPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<any[]>([])
  const [bookings, setBookings] = useState<HotelBooking[]>([])
  const [rooms, setRooms] = useState<HotelRoom[]>([])
  const [requestTypes, setRequestTypes] = useState<HotelRequestType[]>([])
  const [staff, setStaff] = useState<HotelStaff[]>([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState("ALL")
  const [search, setSearch] = useState("")
  const [page, setPage] = useState(1); const pageSize = 20
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({
    hotelBookingId: null as number | null,
    hotelRoomId: null as number | null,
    requestType: "",
    description: "",
    scheduledTime: "",
    assignedTo: "",
    notes: "",
  })
  const [typeSelection, setTypeSelection] = useState("")
  const [customType, setCustomType] = useState("")
  const [assignedSelection, setAssignedSelection] = useState("")
  const [customAssigned, setCustomAssigned] = useState("")

  // Detail dialog
  const [detailItem, setDetailItem] = useState<any>(null)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [r, b, rm, rt, st] = await Promise.all([
        listGuestRequests(),
        listHotelBookings(),
        listHotelRooms(),
        listHotelRequestTypes().catch(() => []),
        listHotelStaff().catch(() => []),
      ])
      setItems(r)
      setBookings(b.filter(x => x.status === "CheckedIn"))
      setRooms(rm)
      setRequestTypes(rt)
      setStaff(st.filter((s: any) => s.isActive ?? s.isactive))
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  function openCreate() {
    setForm({ hotelBookingId: null, hotelRoomId: null, requestType: "", description: "", scheduledTime: "", assignedTo: "", notes: "" })
    setTypeSelection(""); setCustomType("")
    setAssignedSelection(""); setCustomAssigned("")
    setOpen(true)
  }

  async function handleSave() {
    if (!form.requestType) { toast({ title: "Select a request type", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createGuestRequest(form)
      toast({ title: "Request created" })
      setOpen(false); await load()
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  async function doAction(id: number, status: string) {
    try {
      await updateGuestRequestStatus(id, status)
      toast({ title: `Request ${status.toLowerCase()}` })
      await load()
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" })
    }
  }

  const filtered = useMemo(() => items.filter((r: any) => {
    if (statusFilter !== "ALL" && (r.status ?? "") !== statusFilter) return false
    if (search) {
      const q = search.toLowerCase()
      if (!`${r.firstname ?? ""} ${r.lastname ?? ""} ${r.roomnumber ?? ""} ${r.requesttype ?? ""} ${r.description ?? ""}`.toLowerCase().includes(q)) return false
    }
    return true
  }), [items, statusFilter, search])

  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)
  const counts = {
    Pending: items.filter((r: any) => r.status === "Pending").length,
    InProgress: items.filter((r: any) => r.status === "InProgress").length,
    Completed: items.filter((r: any) => r.status === "Completed").length,
    Cancelled: items.filter((r: any) => r.status === "Cancelled").length,
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Header */}
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-3">
              <div className="rounded-xl bg-violet-100 p-2.5"><Bell className="h-6 w-6 text-violet-700" /></div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Guest Requests</h1>
                <p className="text-sm text-slate-500">{items.length} total requests</p>
              </div>
            </div>
            <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700">
              <Plus className="h-4 w-4 mr-1" /> New Request
            </Button>
          </div>

          {/* Summary Cards */}
          <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-4">
            {[
              { s: "ALL", l: "All", c: items.length, color: "text-violet-700", bg: "border-violet-200" },
              { s: "Pending", l: "Pending", c: counts.Pending, color: "text-amber-700", bg: "border-amber-200" },
              { s: "InProgress", l: "In Progress", c: counts.InProgress, color: "text-blue-700", bg: "border-blue-200" },
              { s: "Completed", l: "Completed", c: counts.Completed, color: "text-emerald-700", bg: "border-emerald-200" },
              { s: "Cancelled", l: "Cancelled", c: counts.Cancelled, color: "text-red-700", bg: "border-red-200" },
            ].map(f => (
              <Card key={f.s} className={`cursor-pointer hover:shadow-md transition-shadow ${statusFilter === f.s ? f.bg : ""}`} onClick={() => { setStatusFilter(f.s); setPage(1) }}>
                <CardContent className="p-3 text-center">
                  <div className={`text-2xl font-bold ${f.color}`}>{f.c}</div>
                  <div className="text-xs text-slate-500">{f.l}</div>
                </CardContent>
              </Card>
            ))}
          </div>

          {/* Search */}
          <div className="mb-4 relative max-w-sm">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
            <Input placeholder="Search guest, room, type..." className="pl-9" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} />
          </div>

          {/* Table */}
          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <Card>
              <CardContent className="p-0">
                <table className="w-full text-sm">
                  <thead className="bg-slate-50 border-b">
                    <tr>
                      <th className="text-left p-3">Date</th>
                      <th className="text-left p-3">Room</th>
                      <th className="text-left p-3">Guest</th>
                      <th className="text-left p-3">Type</th>
                      <th className="text-left p-3">Description</th>
                      <th className="text-left p-3">Assigned</th>
                      <th className="text-left p-3">Status</th>
                      <th className="text-right p-3">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {paged.map((r: any, i: number) => (
                      <tr key={r.hotelguestrequestid ?? i} className="border-b hover:bg-violet-50 cursor-pointer transition-colors" onClick={() => setDetailItem(r)}>
                        <td className="p-3 text-xs">{(r.createdat ?? "").slice(0, 10)}</td>
                        <td className="p-3"><Badge variant="outline">{r.roomnumber ?? "—"}</Badge></td>
                        <td className="p-3 font-semibold">{r.firstname ? `${r.firstname} ${r.lastname}` : "—"}</td>
                        <td className="p-3"><Badge variant="outline" className="bg-violet-50 text-violet-700">{r.requesttype}</Badge></td>
                        <td className="p-3 max-w-[200px] truncate">{r.description ?? "—"}</td>
                        <td className="p-3 text-xs">{r.assignedto ?? "—"}</td>
                        <td className="p-3"><Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge></td>
                        <td className="p-3 text-right whitespace-nowrap" onClick={(e) => e.stopPropagation()}>
                          {r.status === "Pending" && <Button size="sm" variant="ghost" onClick={() => doAction(r.hotelguestrequestid, "InProgress")} title="Start"><Play className="h-4 w-4 text-blue-600" /></Button>}
                          {(r.status === "Pending" || r.status === "InProgress") && <Button size="sm" variant="ghost" onClick={() => doAction(r.hotelguestrequestid, "Completed")} title="Complete"><CheckCircle2 className="h-4 w-4 text-emerald-600" /></Button>}
                          {r.status !== "Completed" && r.status !== "Cancelled" && <Button size="sm" variant="ghost" onClick={() => doAction(r.hotelguestrequestid, "Cancelled")} title="Cancel"><XCircle className="h-4 w-4 text-red-500" /></Button>}
                        </td>
                      </tr>
                    ))}
                    {filtered.length === 0 && (
                      <tr><td colSpan={8} className="p-8 text-center text-slate-400">No requests found.</td></tr>
                    )}
                  </tbody>
                </table>
                <PaginationControls page={page} pageSize={pageSize} total={filtered.length} onPageChange={setPage} />
              </CardContent>
            </Card>
          )}

          {/* Detail Dialog */}
          <Dialog open={!!detailItem} onOpenChange={() => setDetailItem(null)}>
            <DialogContent className="max-w-md">
              {detailItem && (
                <>
                  <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                      <Badge variant="outline" className="bg-violet-50 text-violet-700">{detailItem.requesttype}</Badge>
                      <Badge className={STATUS_COLORS[detailItem.status] ?? ""}>{detailItem.status}</Badge>
                    </DialogTitle>
                  </DialogHeader>
                  <div className="space-y-3 text-sm">
                    <div className="grid grid-cols-2 gap-3">
                      <div><span className="text-slate-500">Guest</span><div className="font-semibold">{detailItem.firstname ? `${detailItem.firstname} ${detailItem.lastname}` : "—"}</div></div>
                      <div><span className="text-slate-500">Room</span><div className="font-semibold">{detailItem.roomnumber ?? "—"}</div></div>
                      <div><span className="text-slate-500">Created</span><div>{detailItem.createdat ? new Date(detailItem.createdat).toLocaleString() : "—"}</div></div>
                      <div><span className="text-slate-500">Scheduled</span><div>{detailItem.scheduledtime ? new Date(detailItem.scheduledtime).toLocaleString() : "—"}</div></div>
                      <div><span className="text-slate-500">Assigned To</span><div className="font-semibold">{detailItem.assignedto ?? "Unassigned"}</div></div>
                      <div><span className="text-slate-500">Booking Ref</span><div className="font-mono text-xs">{detailItem.bookingref ?? "—"}</div></div>
                    </div>
                    {detailItem.description && (
                      <div className="bg-slate-50 rounded-lg p-3">
                        <span className="text-slate-500 text-xs uppercase">Description</span>
                        <p className="mt-1">{detailItem.description}</p>
                      </div>
                    )}
                    {detailItem.notes && (
                      <div className="bg-slate-50 rounded-lg p-3">
                        <span className="text-slate-500 text-xs uppercase">Notes</span>
                        <p className="mt-1">{detailItem.notes}</p>
                      </div>
                    )}
                    {detailItem.status !== "Completed" && detailItem.status !== "Cancelled" && (
                      <div className="flex gap-2 border-t pt-3">
                        {detailItem.status === "Pending" && <Button size="sm" className="flex-1 bg-blue-600 hover:bg-blue-700" onClick={() => { doAction(detailItem.hotelguestrequestid, "InProgress"); setDetailItem(null) }}><Play className="h-4 w-4 mr-1" /> Start</Button>}
                        <Button size="sm" className="flex-1 bg-emerald-600 hover:bg-emerald-700" onClick={() => { doAction(detailItem.hotelguestrequestid, "Completed"); setDetailItem(null) }}><CheckCircle2 className="h-4 w-4 mr-1" /> Complete</Button>
                        <Button size="sm" variant="outline" className="text-red-600" onClick={() => { doAction(detailItem.hotelguestrequestid, "Cancelled"); setDetailItem(null) }}><XCircle className="h-4 w-4 mr-1" /> Cancel</Button>
                      </div>
                    )}
                  </div>
                </>
              )}
            </DialogContent>
          </Dialog>

          {/* New Request Dialog */}
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogContent className="max-w-lg">
              <DialogHeader><DialogTitle>New Guest Request</DialogTitle></DialogHeader>
              <div className="space-y-4">
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label>Booking (optional)</Label>
                    <Select value={form.hotelBookingId ? String(form.hotelBookingId) : "__none__"} onValueChange={(v) => {
                      const bookingId = v === "__none__" ? null : Number(v)
                      if (bookingId) {
                        const booking = bookings.find(b => b.hotelBookingId === bookingId)
                        setForm({ ...form, hotelBookingId: bookingId, hotelRoomId: booking?.hotelRoomId ?? null })
                      } else {
                        setForm({ ...form, hotelBookingId: null, hotelRoomId: null })
                      }
                    }}>
                      <SelectTrigger><SelectValue placeholder="Select booking" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__none__">None</SelectItem>
                        {bookings.map(b => <SelectItem key={b.hotelBookingId} value={String(b.hotelBookingId)}>{b.guestFirstName} {b.guestLastName} - {b.roomNumber ?? b.bookingRef}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                  {!form.hotelBookingId && (
                    <div>
                      <Label>Room</Label>
                      <Select value={form.hotelRoomId ? String(form.hotelRoomId) : "__none__"} onValueChange={(v) => setForm({ ...form, hotelRoomId: v === "__none__" ? null : Number(v) })}>
                        <SelectTrigger><SelectValue placeholder="Select room" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="__none__">None</SelectItem>
                          {rooms.map((r: any) => <SelectItem key={r.hotelRoomId} value={String(r.hotelRoomId)}>Room {r.roomNumber}</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </div>
                  )}
                  {form.hotelBookingId && (() => {
                    const booking = bookings.find(b => b.hotelBookingId === form.hotelBookingId)
                    return booking?.roomNumber ? (
                      <div>
                        <Label>Room</Label>
                        <div className="flex items-center h-10 px-3 rounded-md border bg-slate-50 text-sm font-semibold text-violet-700">Room {booking.roomNumber}</div>
                      </div>
                    ) : null
                  })()}
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label>Type *</Label>
                    <Select value={typeSelection || "__none__"} onValueChange={(v) => {
                      const sel = v === "__none__" ? "" : v
                      setTypeSelection(sel)
                      if (sel !== "Other") { setCustomType(""); setForm({ ...form, requestType: sel }) }
                      else { setForm({ ...form, requestType: customType || "" }) }
                    }}>
                      <SelectTrigger><SelectValue placeholder="Select type" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__none__">Select type</SelectItem>
                        {requestTypes.map((t) => <SelectItem key={t.hotelRequestTypeId} value={t.description}>{t.description}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                  <div>
                    <Label>Scheduled Time</Label>
                    <Input type="datetime-local" value={form.scheduledTime} onChange={(e) => setForm({ ...form, scheduledTime: e.target.value })} />
                  </div>
                </div>

                {typeSelection === "Other" && (
                  <div>
                    <Label>Specify Request Type</Label>
                    <Input value={customType} onChange={(e) => { setCustomType(e.target.value); setForm({ ...form, requestType: e.target.value }) }} placeholder="e.g. Iron, Hairdryer, Adapter" />
                  </div>
                )}

                <div>
                  <Label>Description</Label>
                  <Textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} rows={3} />
                </div>

                <div>
                  <Label>Assigned To</Label>
                  <Select value={assignedSelection || "__none__"} onValueChange={(v) => {
                    const sel = v === "__none__" ? "" : v
                    setAssignedSelection(sel)
                    if (sel !== "__other__") { setCustomAssigned(""); setForm({ ...form, assignedTo: sel }) }
                    else { setForm({ ...form, assignedTo: customAssigned || "" }) }
                  }}>
                    <SelectTrigger><SelectValue placeholder="Select staff" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="__none__">Unassigned</SelectItem>
                      {staff.map((s: any) => {
                        const fn = s.firstName ?? s.firstname ?? ""
                        const ln = s.lastName ?? s.lastname ?? ""
                        const role = s.role ?? ""
                        const dept = s.department ?? ""
                        const id = s.hotelStaffId ?? s.hotelstaffid
                        return <SelectItem key={id} value={`${fn} ${ln}`}>{fn} {ln} — {role}{dept ? ` (${dept})` : ""}</SelectItem>
                      })}
                      <SelectItem value="__other__">Other (type name)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {assignedSelection === "__other__" && (
                  <div>
                    <Label>Staff Name</Label>
                    <Input value={customAssigned} onChange={(e) => { setCustomAssigned(e.target.value); setForm({ ...form, assignedTo: e.target.value }) }} placeholder="Type staff name" />
                  </div>
                )}

                <div>
                  <Label>Notes</Label>
                  <Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} placeholder="Internal notes" />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                <Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                  {saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Create
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

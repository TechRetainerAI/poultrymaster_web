"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Trash2, PartyPopper, CalendarDays, Users, DollarSign, Clock, Phone, Mail, MapPin } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listEvents, createEvent, updateEventStatus, deleteEvent,
  type CateringEvent, type CateringEventInput,
} from "@/lib/api/restaurant"

const EVENT_TYPES = ["Corporate", "Wedding", "Birthday", "HolidayParty", "Buffet", "Cocktail", "Other"]
const EVENT_STATUSES = ["All", "Inquiry", "Confirmed", "Deposit", "InProgress", "Completed", "Cancelled"] as const
const STATUS_COLORS: Record<string, string> = {
  Inquiry: "bg-blue-100 text-blue-700",
  Confirmed: "bg-green-100 text-green-700",
  Deposit: "bg-amber-100 text-amber-700",
  InProgress: "bg-purple-100 text-purple-700",
  Completed: "bg-gray-100 text-gray-700",
  Cancelled: "bg-red-100 text-red-700",
}
const NEXT_STATUS: Record<string, string[]> = {
  Inquiry: ["Confirmed", "Cancelled"],
  Confirmed: ["Deposit", "Cancelled"],
  Deposit: ["InProgress", "Cancelled"],
  InProgress: ["Completed", "Cancelled"],
  Completed: [],
  Cancelled: [],
}

const EMPTY_FORM: CateringEventInput = {
  name: "", eventType: "Corporate", eventDate: new Date().toISOString().split("T")[0],
  startTime: "18:00", endTime: "22:00", guestCount: 50,
  contactName: "", contactPhone: "", contactEmail: "",
  pricePerHead: undefined, depositAmount: undefined,
  venue: "InHouse", specialRequests: "", dietaryNotes: "",
}

export default function RestaurantEventsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [events, setEvents] = useState<CateringEvent[]>([])
  const [statusFilter, setStatusFilter] = useState<string>("All")
  const [dialogOpen, setDialogOpen] = useState(false)
  const [form, setForm] = useState<CateringEventInput>({ ...EMPTY_FORM })
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadEvents()
  }, [activeFarmType, router])

  async function loadEvents() {
    setLoading(true)
    try {
      const data = await listEvents()
      setEvents(data)
    } catch (e: any) {
      toast({ title: "Failed to load events", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  function openDialog() {
    setForm({ ...EMPTY_FORM })
    setDialogOpen(true)
  }

  async function handleCreate() {
    if (!form.name.trim()) { toast({ title: "Event name is required", variant: "destructive" }); return }
    if (!form.eventDate) { toast({ title: "Event date is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createEvent(form)
      toast({ title: "Event created successfully" })
      setDialogOpen(false)
      await loadEvents()
    } catch (e: any) {
      toast({ title: "Failed to create event", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  async function handleStatusChange(id: number, status: string) {
    try {
      await updateEventStatus(id, status)
      toast({ title: `Status updated to ${status}` })
      await loadEvents()
    } catch (e: any) {
      toast({ title: "Failed to update status", description: e?.message, variant: "destructive" })
    }
  }

  async function handleDelete(id: number) {
    if (!confirm("Delete this event? This cannot be undone.")) return
    try {
      await deleteEvent(id)
      toast({ title: "Event deleted" })
      await loadEvents()
    } catch (e: any) {
      toast({ title: "Failed to delete event", description: e?.message, variant: "destructive" })
    }
  }

  // --- Computed values ---
  const filtered = statusFilter === "All" ? events : events.filter((e) => e.status === statusFilter)
  const upcoming = events.filter((e) => new Date(e.eventDate) >= new Date() && e.status !== "Cancelled" && e.status !== "Completed")
  const totalRevenue = events.filter((e) => e.status !== "Cancelled").reduce((sum, e) => sum + (e.totalAmount ?? 0), 0)
  const avgGuests = events.length > 0 ? Math.round(events.reduce((s, e) => s + e.guestCount, 0) / events.length) : 0

  if (loading) return <PageSkeleton statCards={4} listRows={5} />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <PageHeader icon={PartyPopper} title="Events & Catering" subtitle="Manage private events, banquets, and catering orders">
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={openDialog}>
                <Plus className="h-4 w-4 mr-2" /> New Event
              </Button>
            </PageHeader>

            {/* Stats Row */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <StatCard label="Total Events" value={events.length} icon={PartyPopper} color="rose" />
              <StatCard label="Upcoming" value={upcoming.length} icon={CalendarDays} color="blue" />
              <StatCard label="Total Revenue" value={`$${totalRevenue.toLocaleString("en-US", { minimumFractionDigits: 2 })}`} icon={DollarSign} color="green" />
              <StatCard label="Avg Guests" value={avgGuests} icon={Users} color="amber" />
            </div>

            {/* Status Filter Pills */}
            <div className="flex flex-wrap gap-2">
              {EVENT_STATUSES.map((s) => (
                <button
                  key={s}
                  onClick={() => setStatusFilter(s)}
                  className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
                    statusFilter === s
                      ? "bg-rose-600 text-white"
                      : "bg-white text-gray-600 border hover:bg-gray-50"
                  }`}
                >
                  {s === "InProgress" ? "In Progress" : s === "HolidayParty" ? "Holiday Party" : s}
                  {s !== "All" && (
                    <span className="ml-1.5 text-xs opacity-75">
                      ({events.filter((e) => e.status === s).length})
                    </span>
                  )}
                </button>
              ))}
            </div>

            {/* Event Cards */}
            {filtered.length === 0 ? (
              <Card>
                <CardContent className="pt-6">
                  <EmptyState
                    icon={PartyPopper}
                    title={statusFilter === "All" ? "No events yet" : `No ${statusFilter} events`}
                    description="Create events for birthdays, weddings, corporate functions, and more"
                    actionLabel="Create First Event"
                    onAction={openDialog}
                  />
                </CardContent>
              </Card>
            ) : (
              <div className="grid gap-4">
                {filtered.map((ev) => (
                  <Card key={ev.eventId} className="hover:shadow-md transition-shadow">
                    <CardContent className="p-5">
                      <div className="flex flex-col md:flex-row md:items-start gap-4">
                        {/* Left: Main info */}
                        <div className="flex-1 space-y-3">
                          <div className="flex items-start gap-3">
                            <div>
                              <div className="flex items-center gap-2 flex-wrap">
                                <h3 className="text-lg font-semibold text-gray-900">{ev.name}</h3>
                                {ev.eventNumber && (
                                  <span className="text-xs text-muted-foreground font-mono">#{ev.eventNumber}</span>
                                )}
                                <Badge className={`${STATUS_COLORS[ev.status] ?? "bg-gray-100 text-gray-700"} border-0`}>
                                  {ev.status === "InProgress" ? "In Progress" : ev.status}
                                </Badge>
                              </div>
                              <p className="text-sm text-muted-foreground mt-0.5">
                                {ev.eventType === "HolidayParty" ? "Holiday Party" : ev.eventType}
                              </p>
                            </div>
                          </div>

                          <div className="flex flex-wrap gap-x-5 gap-y-1.5 text-sm text-gray-600">
                            <span className="flex items-center gap-1.5">
                              <CalendarDays className="h-3.5 w-3.5" />
                              {new Date(ev.eventDate).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric" })}
                            </span>
                            {(ev.startTime || ev.endTime) && (
                              <span className="flex items-center gap-1.5">
                                <Clock className="h-3.5 w-3.5" />
                                {ev.startTime ?? ""}{ev.startTime && ev.endTime ? " - " : ""}{ev.endTime ?? ""}
                              </span>
                            )}
                            <span className="flex items-center gap-1.5">
                              <Users className="h-3.5 w-3.5" />
                              {ev.guestCount} guests
                            </span>
                            {ev.venue && (
                              <span className="flex items-center gap-1.5">
                                <MapPin className="h-3.5 w-3.5" />
                                {ev.venue}
                              </span>
                            )}
                          </div>

                          {(ev.contactName || ev.contactPhone) && (
                            <div className="flex flex-wrap gap-x-5 gap-y-1 text-sm text-gray-600">
                              {ev.contactName && <span className="font-medium">{ev.contactName}</span>}
                              {ev.contactPhone && (
                                <span className="flex items-center gap-1.5">
                                  <Phone className="h-3.5 w-3.5" /> {ev.contactPhone}
                                </span>
                              )}
                              {ev.contactEmail && (
                                <span className="flex items-center gap-1.5">
                                  <Mail className="h-3.5 w-3.5" /> {ev.contactEmail}
                                </span>
                              )}
                            </div>
                          )}

                          {/* Pricing row */}
                          <div className="flex flex-wrap gap-x-5 gap-y-1 text-sm">
                            {ev.pricePerHead != null && ev.pricePerHead > 0 && (
                              <span className="text-gray-600">
                                <span className="font-medium">${ev.pricePerHead.toFixed(2)}</span>/head
                              </span>
                            )}
                            {ev.totalAmount != null && ev.totalAmount > 0 && (
                              <span className="text-green-700 font-semibold">
                                Total: ${ev.totalAmount.toLocaleString("en-US", { minimumFractionDigits: 2 })}
                              </span>
                            )}
                            {ev.depositAmount != null && ev.depositAmount > 0 && (
                              <span className="text-amber-700">
                                Deposit: ${ev.depositAmount.toFixed(2)}
                                {ev.depositPaid ? " (Paid)" : " (Unpaid)"}
                              </span>
                            )}
                          </div>

                          {ev.specialRequests && (
                            <p className="text-sm text-gray-500 italic border-l-2 border-rose-200 pl-3">
                              {ev.specialRequests}
                            </p>
                          )}
                        </div>

                        {/* Right: Actions */}
                        <div className="flex md:flex-col items-center gap-2 shrink-0">
                          {(NEXT_STATUS[ev.status] ?? []).map((ns) => (
                            <Button
                              key={ns}
                              size="sm"
                              variant="outline"
                              className="text-xs"
                              onClick={() => handleStatusChange(ev.eventId, ns)}
                            >
                              {ns === "InProgress" ? "Start" : ns}
                            </Button>
                          ))}
                          <Button
                            size="sm"
                            variant="ghost"
                            className="text-red-500 hover:text-red-700 hover:bg-red-50"
                            onClick={() => handleDelete(ev.eventId)}
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>
        </main>
      </div>

      {/* Create Event Dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>New Event</DialogTitle>
            <DialogDescription>Book a private event or catering order</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Event Name <span className="text-rose-500">*</span></Label>
                <Input className="h-10" placeholder="e.g. Smith Wedding Reception" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>Type</Label>
                <Select value={form.eventType} onValueChange={(v) => setForm({ ...form, eventType: v })}>
                  <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {EVENT_TYPES.map((t) => (
                      <SelectItem key={t} value={t}>{t === "HolidayParty" ? "Holiday Party" : t}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>Date <span className="text-rose-500">*</span></Label>
                <Input type="date" className="h-10" value={form.eventDate} onChange={(e) => setForm({ ...form, eventDate: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>Guest Count</Label>
                <Input type="number" min={1} className="h-10" value={form.guestCount} onChange={(e) => setForm({ ...form, guestCount: parseInt(e.target.value) || 0 })} />
              </div>
              <div className="space-y-1.5">
                <Label>Start Time</Label>
                <Input type="time" className="h-10" value={form.startTime ?? ""} onChange={(e) => setForm({ ...form, startTime: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>End Time</Label>
                <Input type="time" className="h-10" value={form.endTime ?? ""} onChange={(e) => setForm({ ...form, endTime: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>Contact Name</Label>
                <Input className="h-10" value={form.contactName ?? ""} onChange={(e) => setForm({ ...form, contactName: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>Contact Phone</Label>
                <Input className="h-10" value={form.contactPhone ?? ""} onChange={(e) => setForm({ ...form, contactPhone: e.target.value })} />
              </div>
              <div className="col-span-2 space-y-1.5">
                <Label>Contact Email</Label>
                <Input type="email" className="h-10" placeholder="email@example.com" value={form.contactEmail ?? ""} onChange={(e) => setForm({ ...form, contactEmail: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>Price per Head ($)</Label>
                <Input type="number" step="0.01" min={0} className="h-10" value={form.pricePerHead ?? ""} onChange={(e) => setForm({ ...form, pricePerHead: parseFloat(e.target.value) || undefined })} />
              </div>
              <div className="space-y-1.5">
                <Label>Deposit Amount ($)</Label>
                <Input type="number" step="0.01" min={0} className="h-10" value={form.depositAmount ?? ""} onChange={(e) => setForm({ ...form, depositAmount: parseFloat(e.target.value) || undefined })} />
              </div>
              <div className="col-span-2 space-y-1.5">
                <Label>Venue</Label>
                <Select value={form.venue ?? "InHouse"} onValueChange={(v) => setForm({ ...form, venue: v })}>
                  <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="InHouse">In-House</SelectItem>
                    <SelectItem value="Offsite">Offsite</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Special Requests</Label>
              <Textarea placeholder="Menu preferences, decorations, AV needs..." className="min-h-[60px]" value={form.specialRequests ?? ""} onChange={(e) => setForm({ ...form, specialRequests: e.target.value })} />
            </div>
            <div className="space-y-1.5">
              <Label>Dietary Notes</Label>
              <Textarea placeholder="Allergies, vegetarian count, halal requirements..." className="min-h-[60px]" value={form.dietaryNotes ?? ""} onChange={(e) => setForm({ ...form, dietaryNotes: e.target.value })} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleCreate} disabled={saving}>
              {saving ? "Creating..." : "Create Event"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

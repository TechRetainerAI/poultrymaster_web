"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, Plus, Search, Users, Star, Edit2, Trash2, Eye, Award, Gift, TrendingUp } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelGuests, createHotelGuest, updateHotelGuest, deleteHotelGuest, searchHotelGuests,
  listHotelBookings, listHotelPayments,
  getLoyaltyByGuest, enrollLoyalty, addLoyaltyPoints, listLoyaltyTransactions,
  type HotelGuest, type HotelGuestInput, type HotelBooking, type HotelPayment,
  type HotelLoyaltyMember, type HotelLoyaltyTransaction,
} from "@/lib/api/hotel"

export default function HotelGuestsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [guests, setGuests] = useState<HotelGuest[]>([])
  const [bookings, setBookings] = useState<HotelBooking[]>([])
  const [payments, setPayments] = useState<HotelPayment[]>([])
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState("")
  const [filterVIP, setFilterVIP] = useState(false)

  // Create/Edit dialog
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<HotelGuest | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<HotelGuestInput>({ firstName: "", lastName: "", email: "", phone: "", idType: "", idNumber: "", nationality: "", address: "", isVIP: false })

  // Profile dialog
  const [profileGuest, setProfileGuest] = useState<HotelGuest | null>(null)

  // Loyalty
  const [loyalty, setLoyalty] = useState<HotelLoyaltyMember | null>(null)
  const [loyaltyTxns, setLoyaltyTxns] = useState<HotelLoyaltyTransaction[]>([])
  const [enrolling, setEnrolling] = useState(false)
  const [pointsDialog, setPointsDialog] = useState(false)
  const [pointsForm, setPointsForm] = useState({ points: 100, type: "Earn", description: "" })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    loadGuests()
  }, [activeFarmType, router])

  async function loadGuests() {
    setLoading(true)
    try {
      const [g, b, p] = await Promise.all([
        searchQuery ? searchHotelGuests(searchQuery) : listHotelGuests(),
        listHotelBookings().catch(() => []),
        listHotelPayments().catch(() => []),
      ])
      setGuests(g); setBookings(b); setPayments(p)
    } catch (e: any) {
      toast({ title: "Failed to load guests", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  function openCreate() {
    setEditing(null)
    setForm({ firstName: "", lastName: "", email: "", phone: "", idType: "", idNumber: "", nationality: "", address: "", isVIP: false })
    setDialogOpen(true)
  }

  function openEdit(g: HotelGuest) {
    setEditing(g)
    setForm({ firstName: g.firstName, lastName: g.lastName, email: g.email ?? "", phone: g.phone ?? "", idType: g.idType ?? "", idNumber: g.idNumber ?? "", nationality: g.nationality ?? "", address: g.address ?? "", isVIP: g.isVIP })
    setDialogOpen(true)
  }

  async function handleSave() {
    if (!form.firstName?.trim() || !form.lastName?.trim()) { toast({ title: "Name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) { await updateHotelGuest(editing.hotelGuestId, form); toast({ title: "Guest updated" }) }
      else { await createHotelGuest(form); toast({ title: "Guest created" }) }
      setDialogOpen(false); await loadGuests()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function handleDelete(g: HotelGuest) {
    if (!confirm(`Delete ${g.firstName} ${g.lastName}?`)) return
    try { await deleteHotelGuest(g.hotelGuestId); toast({ title: "Guest deleted" }); await loadGuests() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  async function openProfile(g: HotelGuest) {
    setProfileGuest(g)
    setLoyalty(null); setLoyaltyTxns([])
    try {
      const data = await getLoyaltyByGuest(g.hotelGuestId)
      if ("enrolled" in data && data.enrolled === false) { setLoyalty(null) }
      else {
        const member = data as HotelLoyaltyMember
        setLoyalty(member)
        const txns = await listLoyaltyTransactions(member.hotelloyaltymemberid).catch(() => [])
        setLoyaltyTxns(txns)
      }
    } catch { setLoyalty(null) }
  }

  async function handleEnroll(guestId: number) {
    setEnrolling(true)
    try {
      const member = await enrollLoyalty(guestId)
      setLoyalty(member)
      toast({ title: "Guest enrolled in loyalty program!" })
    } catch (e: any) {
      toast({ title: "Enrollment failed", description: e?.message, variant: "destructive" })
    } finally { setEnrolling(false) }
  }

  async function handleAddPoints() {
    if (!loyalty) return
    try {
      await addLoyaltyPoints({
        hotelLoyaltyMemberId: loyalty.hotelloyaltymemberid,
        transactionType: pointsForm.type,
        points: pointsForm.points,
        description: pointsForm.description || `${pointsForm.type} points`,
      })
      toast({ title: `${pointsForm.points} points ${pointsForm.type === "Redeem" ? "redeemed" : "added"}` })
      setPointsDialog(false)
      // Refresh loyalty data
      const data = await getLoyaltyByGuest(loyalty.hotelguestid)
      if (!("enrolled" in data)) {
        setLoyalty(data as HotelLoyaltyMember)
        setLoyaltyTxns(await listLoyaltyTransactions((data as HotelLoyaltyMember).hotelloyaltymemberid).catch(() => []))
      }
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" })
    }
  }

  function getGuestBookings(guestId: number) { return bookings.filter(b => b.hotelGuestId === guestId) }
  function getGuestPayments(guestId: number) {
    const guestBookingIds = getGuestBookings(guestId).map(b => b.hotelBookingId)
    return payments.filter((p: any) => guestBookingIds.includes(p.hotelBookingId ?? p.hotelbookingid))
  }

  const filtered = guests.filter(g => {
    if (filterVIP && !g.isVIP) return false
    return true
  })
  const vipCount = guests.filter(g => g.isVIP).length
  const totalSpent = payments.reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-3"><Users className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Guests</h1></div>
            <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Guest</Button>
          </div>

          {/* Summary */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
            <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-violet-700">{guests.length}</div><div className="text-xs text-slate-500">Total Guests</div></CardContent></Card>
            <Card className="cursor-pointer" onClick={() => setFilterVIP(!filterVIP)}><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-amber-700">{vipCount}</div><div className="text-xs text-slate-500">VIP Guests</div></CardContent></Card>
            <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-blue-700">{bookings.length}</div><div className="text-xs text-slate-500">Total Bookings</div></CardContent></Card>
            <Card><CardContent className="p-3 text-center"><div className="text-2xl font-bold text-emerald-700">GH₵{totalSpent.toFixed(0)}</div><div className="text-xs text-slate-500">Total Revenue</div></CardContent></Card>
          </div>

          {/* Search + filters */}
          <div className="flex gap-3 mb-4">
            <div className="relative flex-1 max-w-sm">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
              <Input className="pl-9" placeholder="Search guests..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} onKeyDown={(e) => e.key === "Enter" && loadGuests()} />
            </div>
            <Button variant={filterVIP ? "default" : "outline"} size="sm" onClick={() => setFilterVIP(!filterVIP)} className={filterVIP ? "bg-amber-600" : ""}><Star className="h-4 w-4 mr-1" />VIP Only</Button>
          </div>

          {loading ? (
            <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          ) : (
            <Card><CardContent className="p-0">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Name</th><th className="text-left p-3">Phone</th><th className="text-left p-3">Email</th><th className="text-left p-3">ID</th><th className="text-left p-3">Nationality</th><th className="text-center p-3">Stays</th><th className="text-left p-3">Last Stay</th><th className="text-right p-3">Actions</th></tr></thead>
                <tbody>
                  {filtered.map((g) => (
                    <tr key={g.hotelGuestId} className="border-b hover:bg-slate-50 cursor-pointer" onClick={() => openProfile(g)}>
                      <td className="p-3 font-medium">{g.firstName} {g.lastName} {g.isVIP && <Badge className="ml-1 bg-amber-100 text-amber-700 text-[10px]"><Star className="h-3 w-3 mr-0.5 inline" />VIP</Badge>}</td>
                      <td className="p-3">{g.phone ?? "—"}</td>
                      <td className="p-3">{g.email ?? "—"}</td>
                      <td className="p-3 text-xs">{g.idType ? `${g.idType}: ${g.idNumber}` : "—"}</td>
                      <td className="p-3">{g.nationality ?? "—"}</td>
                      <td className="p-3 text-center"><Badge variant="outline">{g.totalStays}</Badge></td>
                      <td className="p-3 text-xs">{g.lastStayDate?.slice(0, 10) ?? "Never"}</td>
                      <td className="p-3 text-right space-x-1" onClick={(e) => e.stopPropagation()}>
                        <Button variant="ghost" size="icon" onClick={() => openProfile(g)}><Eye className="h-4 w-4" /></Button>
                        <Button variant="ghost" size="icon" onClick={() => openEdit(g)}><Edit2 className="h-4 w-4" /></Button>
                        <Button variant="ghost" size="icon" className="text-red-600" onClick={() => handleDelete(g)}><Trash2 className="h-4 w-4" /></Button>
                      </td>
                    </tr>
                  ))}
                  {filtered.length === 0 && <tr><td colSpan={8} className="p-8 text-center text-slate-400">No guests found.</td></tr>}
                </tbody>
              </table>
            </CardContent></Card>
          )}

          {/* Guest Profile Dialog */}
          <Dialog open={!!profileGuest} onOpenChange={() => setProfileGuest(null)}>
            <DialogContent className="max-w-lg">
              <DialogHeader><DialogTitle>Guest Profile</DialogTitle></DialogHeader>
              {profileGuest && (() => {
                const gb = getGuestBookings(profileGuest.hotelGuestId)
                const gp = getGuestPayments(profileGuest.hotelGuestId)
                const totalSpent = gp.reduce((s: number, p: any) => s + Number(p.amount ?? 0), 0)
                return (
                  <div className="space-y-4">
                    {/* Header */}
                    <div className="flex items-center justify-between">
                      <div>
                        <h2 className="text-xl font-bold">{profileGuest.firstName} {profileGuest.lastName}</h2>
                        {profileGuest.isVIP && <Badge className="bg-amber-100 text-amber-700"><Star className="h-3 w-3 mr-1 inline" />VIP Guest</Badge>}
                      </div>
                      <div className="text-right">
                        <div className="text-2xl font-bold text-violet-700">{profileGuest.totalStays}</div>
                        <div className="text-xs text-slate-500">Total Stays</div>
                      </div>
                    </div>

                    {/* Contact */}
                    <div className="grid grid-cols-2 gap-2 text-sm">
                      <div><span className="text-slate-500">Phone:</span> <strong>{profileGuest.phone ?? "—"}</strong></div>
                      <div><span className="text-slate-500">Email:</span> <strong>{profileGuest.email ?? "—"}</strong></div>
                      <div><span className="text-slate-500">ID:</span> <strong>{profileGuest.idType ? `${profileGuest.idType}: ${profileGuest.idNumber}` : "—"}</strong></div>
                      <div><span className="text-slate-500">Nationality:</span> <strong>{profileGuest.nationality ?? "—"}</strong></div>
                      <div><span className="text-slate-500">Address:</span> <strong>{profileGuest.address ?? "—"}</strong></div>
                      <div><span className="text-slate-500">Last Stay:</span> <strong>{profileGuest.lastStayDate?.slice(0, 10) ?? "Never"}</strong></div>
                    </div>

                    {/* Lifetime value */}
                    <div className="p-3 bg-violet-50 rounded-lg flex items-center justify-between">
                      <span className="text-sm font-medium text-violet-700">Lifetime Value</span>
                      <span className="text-lg font-bold text-violet-700">GH₵{totalSpent.toFixed(2)}</span>
                    </div>

                    {/* Stay History */}
                    <div>
                      <h4 className="text-sm font-semibold text-slate-500 mb-2">Stay History ({gb.length})</h4>
                      {gb.length > 0 ? (
                        <div className="space-y-2 max-h-[200px] overflow-y-auto">
                          {gb.map(b => (
                            <div key={b.hotelBookingId} className="flex items-center justify-between p-2 rounded-lg bg-slate-50 border text-sm">
                              <div>
                                <div className="font-medium">{b.bookingRef} — Room {b.roomNumber ?? "TBD"}</div>
                                <div className="text-xs text-slate-400">{b.checkInDate?.slice(0, 10)} to {b.checkOutDate?.slice(0, 10)} | {b.roomTypeName}</div>
                              </div>
                              <div className="text-right">
                                <div className="font-semibold">GH₵{Number(b.totalAmount ?? 0).toFixed(2)}</div>
                                <Badge variant="outline" className={`text-[10px] ${b.status === "CheckedOut" ? "bg-slate-100" : b.status === "CheckedIn" ? "bg-emerald-100 text-emerald-700" : "bg-blue-100 text-blue-700"}`}>{b.status}</Badge>
                              </div>
                            </div>
                          ))}
                        </div>
                      ) : <div className="text-sm text-slate-400">No booking history</div>}
                    </div>

                    {/* Loyalty Program */}
                    <div className="border-t pt-3">
                      <h4 className="text-sm font-semibold text-slate-500 mb-2 flex items-center gap-1"><Award className="h-4 w-4" /> Loyalty Program</h4>
                      {loyalty ? (() => {
                        const tierColors: Record<string, string> = { Bronze: "bg-orange-100 text-orange-700", Silver: "bg-slate-200 text-slate-700", Gold: "bg-amber-100 text-amber-700", Platinum: "bg-violet-100 text-violet-700" }
                        const tierThresholds = { Bronze: 0, Silver: 2000, Gold: 5000, Platinum: 10000 }
                        const currentTier = (loyalty.tier ?? "Bronze") as keyof typeof tierThresholds
                        const nextTier = currentTier === "Platinum" ? null : currentTier === "Gold" ? "Platinum" : currentTier === "Silver" ? "Gold" : "Silver"
                        const nextThreshold = nextTier ? tierThresholds[nextTier as keyof typeof tierThresholds] : 0
                        const progressPct = nextTier ? Math.min(100, Math.round((loyalty.lifetimepoints / nextThreshold) * 100)) : 100
                        return (
                          <div className="space-y-2">
                            <div className="flex items-center justify-between p-3 bg-gradient-to-r from-violet-50 to-amber-50 rounded-lg">
                              <div>
                                <Badge className={`${tierColors[currentTier] ?? tierColors.Bronze} text-xs`}>
                                  <Award className="h-3 w-3 mr-1 inline" />{currentTier}
                                </Badge>
                                <div className="text-[10px] text-slate-500 mt-1">#{loyalty.membershipnumber}</div>
                              </div>
                              <div className="text-right">
                                <div className="text-xl font-bold text-violet-700">{loyalty.totalpoints.toLocaleString()}</div>
                                <div className="text-[10px] text-slate-500">Available Points</div>
                              </div>
                            </div>
                            {/* Progress to next tier */}
                            {nextTier && (
                              <div className="text-xs">
                                <div className="flex justify-between text-slate-500 mb-1">
                                  <span>{loyalty.lifetimepoints.toLocaleString()} lifetime pts</span>
                                  <span>{nextThreshold.toLocaleString()} for {nextTier}</span>
                                </div>
                                <div className="w-full bg-slate-200 rounded-full h-1.5">
                                  <div className="bg-violet-600 h-1.5 rounded-full transition-all" style={{ width: `${progressPct}%` }} />
                                </div>
                              </div>
                            )}
                            {/* Quick actions */}
                            <div className="flex gap-2">
                              <Button size="sm" variant="outline" className="flex-1 text-xs" onClick={() => { setPointsForm({ points: 100, type: "Earn", description: "" }); setPointsDialog(true) }}>
                                <TrendingUp className="h-3 w-3 mr-1" /> Add Points
                              </Button>
                              <Button size="sm" variant="outline" className="flex-1 text-xs" onClick={() => { setPointsForm({ points: 100, type: "Redeem", description: "" }); setPointsDialog(true) }}>
                                <Gift className="h-3 w-3 mr-1" /> Redeem
                              </Button>
                            </div>
                            {/* Recent transactions */}
                            {loyaltyTxns.length > 0 && (
                              <div className="max-h-[100px] overflow-y-auto space-y-1">
                                {loyaltyTxns.slice(0, 5).map((t: any, i: number) => (
                                  <div key={t.hotelloyaltytransactionid ?? i} className="flex justify-between text-[11px] px-2 py-1 bg-slate-50 rounded">
                                    <span className="text-slate-600">{t.description ?? t.transactiontype}</span>
                                    <span className={t.transactiontype === "Redeem" ? "text-red-600" : "text-emerald-600"}>
                                      {t.transactiontype === "Redeem" ? "-" : "+"}{Math.abs(t.points)} pts
                                    </span>
                                  </div>
                                ))}
                              </div>
                            )}
                          </div>
                        )
                      })() : (
                        <div className="text-center py-3">
                          <p className="text-xs text-slate-400 mb-2">Not enrolled in loyalty program</p>
                          <Button size="sm" variant="outline" onClick={() => handleEnroll(profileGuest.hotelGuestId)} disabled={enrolling}>
                            {enrolling ? <Loader2 className="h-3 w-3 mr-1 animate-spin" /> : <Award className="h-3 w-3 mr-1" />}
                            Enroll Now
                          </Button>
                        </div>
                      )}
                    </div>

                    <div className="flex gap-2 border-t pt-3">
                      <Button variant="outline" className="flex-1" onClick={() => { setProfileGuest(null); openEdit(profileGuest) }}>Edit Guest</Button>
                      <Button variant="outline" className="flex-1" onClick={() => setProfileGuest(null)}>Close</Button>
                    </div>
                  </div>
                )
              })()}
            </DialogContent>
          </Dialog>

          {/* Create/Edit Dialog */}
          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <DialogContent className="max-w-lg">
              <DialogHeader><DialogTitle>{editing ? "Edit Guest" : "Add Guest"}</DialogTitle></DialogHeader>
              <div className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>First Name *</Label><Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} /></div>
                  <div><Label>Last Name *</Label><Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} /></div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>Phone</Label><Input value={form.phone ?? ""} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></div>
                  <div><Label>Email</Label><Input value={form.email ?? ""} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>ID Type</Label><Input value={form.idType ?? ""} onChange={(e) => setForm({ ...form, idType: e.target.value })} placeholder="Passport, National ID" /></div>
                  <div><Label>ID Number</Label><Input value={form.idNumber ?? ""} onChange={(e) => setForm({ ...form, idNumber: e.target.value })} /></div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div><Label>Nationality</Label><Input value={form.nationality ?? ""} onChange={(e) => setForm({ ...form, nationality: e.target.value })} /></div>
                  <div className="flex items-end gap-2"><label className="flex items-center gap-2 cursor-pointer"><input type="checkbox" checked={form.isVIP ?? false} onChange={(e) => setForm({ ...form, isVIP: e.target.checked })} className="rounded" /><Star className="h-4 w-4 text-amber-500" /><span className="text-sm">VIP Guest</span></label></div>
                </div>
                <div><Label>Address</Label><Input value={form.address ?? ""} onChange={(e) => setForm({ ...form, address: e.target.value })} /></div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
                <Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{editing ? "Update" : "Create"}</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Points Dialog */}
          <Dialog open={pointsDialog} onOpenChange={setPointsDialog}>
            <DialogContent className="max-w-sm">
              <DialogHeader><DialogTitle>{pointsForm.type === "Redeem" ? "Redeem Points" : "Add Points"}</DialogTitle></DialogHeader>
              <div className="space-y-4">
                {loyalty && (
                  <div className="text-sm text-slate-500">
                    Current balance: <strong className="text-violet-700">{loyalty.totalpoints.toLocaleString()} pts</strong>
                  </div>
                )}
                <div><Label>Points</Label><Input type="number" min={1} value={pointsForm.points} onChange={(e) => setPointsForm({ ...pointsForm, points: Number(e.target.value) })} /></div>
                <div><Label>Description</Label><Input value={pointsForm.description} onChange={(e) => setPointsForm({ ...pointsForm, description: e.target.value })} placeholder={pointsForm.type === "Redeem" ? "e.g. Room discount, Free breakfast" : "e.g. Stay bonus, Referral, Promotion"} /></div>
                {pointsForm.type === "Redeem" && loyalty && pointsForm.points > loyalty.totalpoints && (
                  <p className="text-xs text-red-600">Insufficient points (available: {loyalty.totalpoints})</p>
                )}
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setPointsDialog(false)}>Cancel</Button>
                <Button onClick={handleAddPoints} disabled={pointsForm.type === "Redeem" && !!loyalty && pointsForm.points > loyalty.totalpoints} className="bg-violet-600 hover:bg-violet-700">
                  {pointsForm.type === "Redeem" ? <Gift className="h-4 w-4 mr-1" /> : <TrendingUp className="h-4 w-4 mr-1" />}
                  {pointsForm.type === "Redeem" ? "Redeem" : "Add Points"}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

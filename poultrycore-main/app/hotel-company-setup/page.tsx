"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Building2, CheckCircle2, Clock, Coins, Loader2, MapPin, Settings } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getHotelProfile, upsertHotelProfile, type HotelProfileInput } from "@/lib/api/hotel"

export default function HotelCompanySetupPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [isSetUp, setIsSetUp] = useState(false)
  const [profile, setProfile] = useState<HotelProfileInput>({ hotelName: "" })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    loadProfile()
  }, [activeFarmType, router])

  async function loadProfile() {
    setLoading(true)
    try {
      // A hotel that has never been set up has no profile row yet — the API
      // answers 404, which is expected here rather than an error worth showing.
      const p = await getHotelProfile().catch(() => null)
      if (p) { setProfile(p); setIsSetUp(true) }
    } finally {
      setLoading(false)
    }
  }

  async function saveProfile() {
    if (!profile.hotelName?.trim()) { toast({ title: "Hotel name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await upsertHotelProfile(profile)
      setIsSetUp(true)
      toast({ title: "Profile saved" })
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-5xl mx-auto space-y-6">
            {/* Page Header */}
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-violet-100 flex items-center justify-center shrink-0">
                  <Settings className="h-5 w-5 text-violet-600" />
                </div>
                <div>
                  <div className="flex items-center gap-2 flex-wrap">
                    <h1 className="text-2xl font-bold text-slate-900">Hotel Company Setup</h1>
                    {isSetUp && (
                      <span className="text-xs px-2 py-1 rounded-full bg-green-100 text-green-700 flex items-center gap-1">
                        <CheckCircle2 className="h-3 w-3" /> Set up
                      </span>
                    )}
                  </div>
                  <p className="text-sm text-muted-foreground">Your hotel&apos;s identity, contact details, service hours and charges</p>
                </div>
              </div>
              <Button onClick={saveProfile} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <CheckCircle2 className="mr-2 h-4 w-4" />}
                Save Changes
              </Button>
            </div>

            {/* Basic Information */}
            <Card>
              <CardHeader className="pb-4">
                <div className="flex items-center gap-2">
                  <Building2 className="h-5 w-5 text-violet-500" />
                  <div>
                    <CardTitle className="text-lg">Basic Information</CardTitle>
                    <CardDescription>The name guests see on bookings, invoices and emails</CardDescription>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="sm:col-span-2">
                  <Label>Hotel Name *</Label>
                  <Input value={profile.hotelName ?? ""} onChange={(e) => setProfile({ ...profile, hotelName: e.target.value })} placeholder="e.g. Golden Palm Hotel" />
                </div>
                <div>
                  <Label>Star Rating</Label>
                  <Input type="number" min={1} max={5} value={profile.starRating ?? ""} onChange={(e) => setProfile({ ...profile, starRating: e.target.value ? Number(e.target.value) : null })} placeholder="1 – 5" />
                </div>
              </CardContent>
            </Card>

            {/* Contact & Location */}
            <Card>
              <CardHeader className="pb-4">
                <div className="flex items-center gap-2">
                  <MapPin className="h-5 w-5 text-violet-500" />
                  <div>
                    <CardTitle className="text-lg">Contact &amp; Location</CardTitle>
                    <CardDescription>How guests reach you, and where you are</CardDescription>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div><Label>Phone</Label><Input value={profile.phone ?? ""} onChange={(e) => setProfile({ ...profile, phone: e.target.value })} /></div>
                <div><Label>Email</Label><Input value={profile.email ?? ""} onChange={(e) => setProfile({ ...profile, email: e.target.value })} /></div>
                <div className="sm:col-span-2"><Label>Address</Label><Input value={profile.address ?? ""} onChange={(e) => setProfile({ ...profile, address: e.target.value })} /></div>
                <div><Label>City</Label><Input value={profile.city ?? ""} onChange={(e) => setProfile({ ...profile, city: e.target.value })} /></div>
                <div><Label>Country</Label><Input value={profile.country ?? ""} onChange={(e) => setProfile({ ...profile, country: e.target.value })} /></div>
              </CardContent>
            </Card>

            {/* Operations */}
            <Card>
              <CardHeader className="pb-4">
                <div className="flex items-center gap-2">
                  <Clock className="h-5 w-5 text-violet-500" />
                  <div>
                    <CardTitle className="text-lg">Operations</CardTitle>
                    <CardDescription>Standard check-in and check-out times for new bookings</CardDescription>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div><Label>Check-in Time</Label><Input value={profile.checkInTime ?? "14:00"} onChange={(e) => setProfile({ ...profile, checkInTime: e.target.value })} placeholder="14:00" /></div>
                <div><Label>Check-out Time</Label><Input value={profile.checkOutTime ?? "12:00"} onChange={(e) => setProfile({ ...profile, checkOutTime: e.target.value })} placeholder="12:00" /></div>
              </CardContent>
            </Card>

            {/* Currency & Charges */}
            <Card>
              <CardHeader className="pb-4">
                <div className="flex items-center gap-2">
                  <Coins className="h-5 w-5 text-violet-500" />
                  <div>
                    <CardTitle className="text-lg">Currency &amp; Charges</CardTitle>
                    <CardDescription>The currency rates are quoted in, and the percentages added to a bill</CardDescription>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <div><Label>Currency</Label><Input value={profile.defaultCurrency ?? "GHS"} onChange={(e) => setProfile({ ...profile, defaultCurrency: e.target.value })} /></div>
                <div><Label>Tax Rate (%)</Label><Input type="number" step="0.01" value={profile.taxRate ?? 0} onChange={(e) => setProfile({ ...profile, taxRate: Number(e.target.value) })} /></div>
                <div><Label>Service Charge (%)</Label><Input type="number" step="0.01" value={profile.serviceChargeRate ?? 0} onChange={(e) => setProfile({ ...profile, serviceChargeRate: Number(e.target.value) })} /></div>
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
    </div>
  )
}

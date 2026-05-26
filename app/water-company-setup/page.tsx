"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Building2, CheckCircle2, AlertCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getWaterCompanyProfile, setupWaterCompany, updateWaterCompanyProfile,
  type WaterCompanyProfile, type WaterCompanySetupInput,
} from "@/lib/api/water"

const EMPTY: WaterCompanySetupInput = {
  brandName: "",
  businessType: "Sachet",
  productionSiteAddress: "",
  mainLocation: "",
  waterSourceType: "Borehole",
  defaultCurrency: "GHC",
  defaultBagSachetCount: 30,
  ownerName: "",
  phoneNumber: "",
  notes: "",
}

export default function WaterCompanySetupPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [profile, setProfile] = useState<WaterCompanyProfile | null>(null)
  const [form, setForm] = useState<WaterCompanySetupInput>(EMPTY)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try {
      const p = await getWaterCompanyProfile()
      setProfile(p)
      // getWaterCompanyProfile now returns null on 404 ("not set up yet")
      // instead of throwing — so guard before reading fields.
      if (p) {
        setForm({
          brandName: p.brandName ?? "",
          businessType: p.businessType,
          productionSiteAddress: p.productionSiteAddress ?? "",
          mainLocation: p.mainLocation ?? "",
          waterSourceType: p.waterSourceType,
          defaultCurrency: p.defaultCurrency,
          defaultBagSachetCount: p.defaultBagSachetCount,
          ownerName: p.ownerName ?? "",
          phoneNumber: p.phoneNumber ?? "",
          notes: p.notes ?? "",
        })
      }
    } catch (e: any) {
      // Other errors (network, 5xx) still surface
      setError(e?.message ?? String(e))
    } finally { setLoading(false) }
  }

  async function save() {
    setSaving(true)
    try {
      if (profile) {
        const p = await updateWaterCompanyProfile(form)
        setProfile(p)
        toast({ title: "Profile updated" })
      } else {
        const p = await setupWaterCompany(form)
        setProfile(p)
        toast({ title: "Water Company set up", description: "Default expense categories and cash accounts seeded." })
      }
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Building2 className="h-6 w-6 text-sky-600" /> Water Company Setup
            </h1>
            {profile && <span className="text-xs px-2 py-1 rounded-full bg-green-100 text-green-700 flex items-center gap-1"><CheckCircle2 className="h-3 w-3" /> Set up</span>}
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700">
                <AlertCircle className="h-4 w-4" /> {error}
              </CardContent>
            </Card>
          )}

          <Card className="max-w-3xl">
            <CardHeader><CardTitle>Business details</CardTitle></CardHeader>
            <CardContent>
              {loading ? (
                <div className="text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="md:col-span-2"><Label>Brand name</Label>
                    <Input value={form.brandName ?? ""} onChange={(e) => setForm({ ...form, brandName: e.target.value })} placeholder="e.g. ProfOwusu Pure Water" /></div>

                  <div><Label>Business type</Label>
                    <Select value={form.businessType ?? "Sachet"} onValueChange={(v) => setForm({ ...form, businessType: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Sachet">Sachet</SelectItem>
                        <SelectItem value="Bottled">Bottled</SelectItem>
                        <SelectItem value="Both">Both</SelectItem>
                      </SelectContent>
                    </Select></div>

                  <div><Label>Water source</Label>
                    <Select value={form.waterSourceType ?? "Borehole"} onValueChange={(v) => setForm({ ...form, waterSourceType: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Borehole">Borehole</SelectItem>
                        <SelectItem value="GhanaWater">Ghana Water</SelectItem>
                        <SelectItem value="Tanker">Tanker</SelectItem>
                        <SelectItem value="Mixed">Mixed</SelectItem>
                      </SelectContent>
                    </Select></div>

                  <div className="md:col-span-2"><Label>Production site address</Label>
                    <Input value={form.productionSiteAddress ?? ""} onChange={(e) => setForm({ ...form, productionSiteAddress: e.target.value })} /></div>

                  <div><Label>Main location / town</Label>
                    <Input value={form.mainLocation ?? ""} onChange={(e) => setForm({ ...form, mainLocation: e.target.value })} /></div>

                  <div><Label>Owner name</Label>
                    <Input value={form.ownerName ?? ""} onChange={(e) => setForm({ ...form, ownerName: e.target.value })} /></div>

                  <div><Label>Phone</Label>
                    <Input value={form.phoneNumber ?? ""} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} placeholder="+233..." /></div>

                  <div><Label>Default currency</Label>
                    <Input value={form.defaultCurrency ?? "GHC"} onChange={(e) => setForm({ ...form, defaultCurrency: e.target.value })} /></div>

                  <div><Label>Sachets per bag</Label>
                    <Input type="number" min={1} value={form.defaultBagSachetCount ?? 30} onChange={(e) => setForm({ ...form, defaultBagSachetCount: Number(e.target.value) || 30 })} /></div>

                  <div className="md:col-span-2"><Label>Notes</Label>
                    <Textarea value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>

                  <div className="md:col-span-2 flex justify-end">
                    <Button onClick={save} disabled={saving}>
                      {saving ? "Saving…" : profile ? "Save changes" : "Set up Water Company"}
                    </Button>
                  </div>

                  {!profile && (
                    <p className="md:col-span-2 text-xs text-slate-500">
                      First-time setup seeds default expense categories and cash accounts automatically.
                    </p>
                  )}
                </div>
              )}
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}

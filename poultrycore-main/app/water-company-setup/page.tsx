"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Building2, CheckCircle2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getWaterCompanyProfile, setupWaterCompany, updateWaterCompanyProfile,
  type WaterCompanyProfile, type WaterCompanySetupInput,
} from "@/lib/api/water"
import { CurrencySelect } from "@/components/ui/currency-select"
import { fetchFarmSettings, updateFarmCurrency, useFarmSettingsStore } from "@/lib/currency"
import { currencySymbolFor } from "@/lib/constants/currencies"

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
  const applyFarmSettings = useFarmSettingsStore((st) => st.apply)

  const [profile, setProfile] = useState<WaterCompanyProfile | null>(null)
  const [form, setForm] = useState<WaterCompanySetupInput>(EMPTY)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
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
      toast({ title: "Could not load water profile", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function save() {
    setSaving(true)
    try {
      // James (2026-05-30): "BusinessType must be Sachet, Bottled, or Both"
      // came from the SP because the form was sending the raw loaded value
      // (which could be "" / lowercase / typo) even though the dropdown
      // trigger normalized for display. Normalize what we *send*, not just
      // what we display.
      const allowedBiz    = ["Sachet", "Bottled", "Both"]
      const allowedSource = ["Borehole", "GhanaWater", "Tanker", "Mixed"]
      const payload = {
        ...form,
        businessType:
          allowedBiz.find(o => o.toLowerCase() === (form.businessType ?? "").toLowerCase())
          ?? "Sachet",
        waterSourceType:
          allowedSource.find(o => o.toLowerCase() === (form.waterSourceType ?? "").toLowerCase())
          ?? "Borehole",
        // Default currency is required by the SP — if the user blanked it,
        // fall back to the same default the SP uses ('GHC') so we never send
        // an empty string and hit a different RAISERROR.
        defaultCurrency: (form.defaultCurrency ?? "").trim() || "GHC",
      }


      // Currency has to reach the Farms row too, not just the profile: that row
      // is what fmtMoney() reads, so every report and dashboard follows it.
      // Writing only the profile field would leave this page claiming one
      // currency while the rest of the app showed another. The symbol is only
      // replaced when the CODE changes — operators often prefer "GHC" over
      // ICU's "GH₵" and re-saving must not undo that.
      try {
        const current = await fetchFarmSettings()
        const picked = (payload.defaultCurrency ?? "").toUpperCase()
        if (picked && picked !== (current?.currencyCode ?? "").toUpperCase()) {
          const updated = await updateFarmCurrency({
            currencyCode: picked,
            currencySymbol: currencySymbolFor(picked),
            showCurrencySymbol: current?.showCurrencySymbol ?? true,
          })
          if (updated) applyFarmSettings(updated)
        }
      } catch {
        toast({ title: "Currency not applied app-wide", description: "The profile saved, but the display currency could not be updated. Set it in Water setup > Company.", variant: "destructive" })
      }
      if (profile) {
        const p = await updateWaterCompanyProfile(payload)
        setProfile(p)
        toast({ title: "Profile updated" })
      } else {
        const p = await setupWaterCompany(payload)
        setProfile(p)
        toast({ title: "Water Company set up", description: "Default expense categories and cash accounts seeded." })
      }
    } catch (e: any) {
      // Backend (GlobalExceptionMiddleware) returns JSON like
      //   { errorType, sqlNumber, message, hint, path }
      // for SqlException paths (Farms.Type='Poultry' mismatch is the common
      // one here). jsend turns that into an Error with the parsed message —
      // but if anything in that chain returns empty (no body, parse failure)
      // the description used to be blank. Always show *something* actionable.
      const desc = e?.message
        || (e?.hint ? String(e.hint) : "")
        || "Save returned a 500 with no detail. Check the Farm API logs or the active company's Farms.Type column — most often this is the 'Farm is not a Water company (Type=Poultry).' guard in spWaterCompany_Setup."
      toast({ title: "Save failed", description: desc, variant: "destructive" })
      // eslint-disable-next-line no-console
      console.error("[water-company-setup] save failed:", e)
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

          <Card className="max-w-3xl">
            <CardHeader><CardTitle>Business details</CardTitle></CardHeader>
            <CardContent>
              {loading ? (
                <div className="text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="md:col-span-2"><Label>Brand name</Label>
                    <Input value={form.brandName ?? ""} onChange={(e) => setForm({ ...form, brandName: e.target.value })} placeholder="e.g. ProfOwusu Pure Water" /></div>

                  {/* James (2026-05-30): "Business type Sachet or Bottle or Both
                      but in dropdown isn't part". Likely cause: when the loaded
                      profile.businessType doesn't *exactly* match one of the
                      SelectItem values (case mismatch, typo from an older row,
                      or empty), the trigger renders blank and Radix doesn't
                      highlight any item. Normalize against the allowed set so
                      the trigger always shows a valid option, and add an
                      explicit placeholder for the unset case. */}
                  <div><Label>Business type *</Label>
                    {(() => {
                      const allowed = ["Sachet", "Bottled", "Both"] as const
                      const match = allowed.find(o => o.toLowerCase() === (form.businessType ?? "").toLowerCase())
                      const value = match ?? "Sachet"
                      return (
                        <Select value={value} onValueChange={(v) => setForm({ ...form, businessType: v })}>
                          <SelectTrigger><SelectValue placeholder="Pick business type" /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="Sachet">Sachet</SelectItem>
                            <SelectItem value="Bottled">Bottled</SelectItem>
                            <SelectItem value="Both">Both</SelectItem>
                          </SelectContent>
                        </Select>
                      )
                    })()}
                  </div>

                  <div><Label>Water source *</Label>
                    {(() => {
                      const allowed = ["Borehole", "GhanaWater", "Tanker", "Mixed"] as const
                      const match = allowed.find(o => o.toLowerCase() === (form.waterSourceType ?? "").toLowerCase())
                      const value = match ?? "Borehole"
                      return (
                        <Select value={value} onValueChange={(v) => setForm({ ...form, waterSourceType: v })}>
                          <SelectTrigger><SelectValue placeholder="Pick water source" /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="Borehole">Borehole</SelectItem>
                            <SelectItem value="GhanaWater">Ghana Water</SelectItem>
                            <SelectItem value="Tanker">Tanker</SelectItem>
                            <SelectItem value="Mixed">Mixed</SelectItem>
                          </SelectContent>
                        </Select>
                      )
                    })()}
                  </div>

                  <div className="md:col-span-2"><Label>Production site address</Label>
                    <Input value={form.productionSiteAddress ?? ""} onChange={(e) => setForm({ ...form, productionSiteAddress: e.target.value })} /></div>

                  <div><Label>Main location / town</Label>
                    <Input value={form.mainLocation ?? ""} onChange={(e) => setForm({ ...form, mainLocation: e.target.value })} /></div>

                  <div><Label>Owner name</Label>
                    <Input value={form.ownerName ?? ""} onChange={(e) => setForm({ ...form, ownerName: e.target.value })} /></div>

                  <div><Label>Phone</Label>
                    <Input value={form.phoneNumber ?? ""} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} placeholder="+233..." /></div>

                  <div><Label htmlFor="default-currency">Default currency</Label>
                    <CurrencySelect id="default-currency" value={form.defaultCurrency ?? "GHC"}
                      onChange={(o) => setForm({ ...form, defaultCurrency: o.code })} /></div>

                  <div><Label>Sachets per bag</Label>
                    <NumberInput min={1} value={form.defaultBagSachetCount ?? 30} onChange={(e) => setForm({ ...form, defaultBagSachetCount: Number(e.target.value) || 30 })} /></div>

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

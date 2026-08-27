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
  getPoultryCompanyProfile, setupPoultryCompany, updatePoultryCompanyProfile,
  POULTRY_BUSINESS_TYPES, POULTRY_HOUSING_SYSTEMS, POULTRY_HOUSING_LABELS,
  type PoultryCompanyProfile, type PoultryCompanySetupInput,
} from "@/lib/api/poultry-company"
import { CurrencySelect } from "@/components/ui/currency-select"
import { fetchFarmSettings, updateFarmCurrency, useFarmSettingsStore } from "@/lib/currency"
import { currencySymbolFor } from "@/lib/constants/currencies"

const EMPTY: PoultryCompanySetupInput = {
  brandName: "",
  businessType: "Layers",
  farmSiteAddress: "",
  mainLocation: "",
  housingSystem: "DeepLitter",
  defaultCurrency: "GHC",
  defaultCrateEggCount: 30,
  totalCapacity: null,
  operatingHours: "",
  ownerName: "",
  phoneNumber: "",
  email: "",
  notes: "",
}

export default function PoultryCompanySetupPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const applyFarmSettings = useFarmSettingsStore((st) => st.apply)

  const [profile, setProfile] = useState<PoultryCompanyProfile | null>(null)
  const [form, setForm] = useState<PoultryCompanySetupInput>(EMPTY)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    // Water and Generic companies have their own setup pages; bounce anyone who
    // lands here with the wrong company active, the same guard
    // /water-company-setup uses.
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const p = await getPoultryCompanyProfile()
      setProfile(p)
      // null means "not set up yet" (the API 404s), so leave the empty form.
      if (p) {
        setForm({
          brandName: p.brandName ?? "",
          businessType: p.businessType,
          farmSiteAddress: p.farmSiteAddress ?? "",
          mainLocation: p.mainLocation ?? "",
          housingSystem: p.housingSystem,
          defaultCurrency: p.defaultCurrency,
          defaultCrateEggCount: p.defaultCrateEggCount,
          totalCapacity: p.totalCapacity ?? null,
          operatingHours: p.operatingHours ?? "",
          ownerName: p.ownerName ?? "",
          phoneNumber: p.phoneNumber ?? "",
          email: p.email ?? "",
          notes: p.notes ?? "",
        })
      }
    } catch (e: any) {
      toast({ title: "Could not load company profile", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function save() {
    setSaving(true)
    try {
      // Normalize what we SEND, not just what we display — the same trap the
      // water page hit (James, 2026-05-30): a value loaded from an older row
      // could be lowercase or blank, which the dropdown tolerated for display
      // but the database rejected on save.
      const payload: PoultryCompanySetupInput = {
        ...form,
        businessType:
          POULTRY_BUSINESS_TYPES.find(o => o.toLowerCase() === (form.businessType ?? "").toLowerCase())
          ?? "Layers",
        housingSystem:
          POULTRY_HOUSING_SYSTEMS.find(o => o.toLowerCase() === (form.housingSystem ?? "").toLowerCase())
          ?? "DeepLitter",
        defaultCurrency: (form.defaultCurrency ?? "").trim() || "GHC",
        defaultCrateEggCount: Math.max(1, Number(form.defaultCrateEggCount) || 30),
        // An empty capacity box means "not stated", not zero.
        totalCapacity:
          form.totalCapacity === null || form.totalCapacity === undefined || Number.isNaN(Number(form.totalCapacity))
            ? null
            : Number(form.totalCapacity),
      }


      // Currency has to reach the Farms row too, not just the profile: that row
      // is what fmtMoney()/formatCurrency() read, so every report, sale and
      // dashboard follows it. Writing only the profile field would leave this
      // page claiming one currency while the rest of the app showed another.
      // The symbol is only replaced when the CODE actually changes — operators
      // often prefer "GHC" over ICU's "GH₵" and re-saving must not undo that.
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
        // The profile saved; a currency-sync failure shouldn't lose that.
        toast({ title: "Currency not applied app-wide", description: "The profile saved, but the display currency could not be updated. Set it in Setup > Company.", variant: "destructive" })
      }
      if (profile) {
        const p = await updatePoultryCompanyProfile(payload)
        setProfile(p)
        toast({ title: "Profile updated" })
      } else {
        const p = await setupPoultryCompany(payload)
        setProfile(p)
        toast({ title: "Poultry Company set up", description: "Default cash accounts seeded." })
      }
    } catch (e: any) {
      const desc = e?.message
        || "Save returned an error with no detail. Check the Farm API logs, or the active company's Farms.Type column — the most common cause is the 'not a Poultry company' guard in sppoultrycompany_setup."
      toast({ title: "Save failed", description: desc, variant: "destructive" })
      // eslint-disable-next-line no-console
      console.error("[poultry-company-setup] save failed:", e)
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
              <Building2 className="h-6 w-6 text-amber-600" /> Poultry Company Setup
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
                  <div className="md:col-span-2"><Label>Farm / brand name</Label>
                    <Input value={form.brandName ?? ""} onChange={(e) => setForm({ ...form, brandName: e.target.value })} placeholder="e.g. Gyimah Farm" /></div>

                  <div><Label>Business type *</Label>
                    {(() => {
                      const match = POULTRY_BUSINESS_TYPES.find(o => o.toLowerCase() === (form.businessType ?? "").toLowerCase())
                      return (
                        <Select value={match ?? "Layers"} onValueChange={(v) => setForm({ ...form, businessType: v })}>
                          <SelectTrigger><SelectValue placeholder="Pick business type" /></SelectTrigger>
                          <SelectContent>
                            {POULTRY_BUSINESS_TYPES.map(o => <SelectItem key={o} value={o}>{o}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      )
                    })()}
                  </div>

                  <div><Label>Housing system *</Label>
                    {(() => {
                      const match = POULTRY_HOUSING_SYSTEMS.find(o => o.toLowerCase() === (form.housingSystem ?? "").toLowerCase())
                      return (
                        <Select value={match ?? "DeepLitter"} onValueChange={(v) => setForm({ ...form, housingSystem: v })}>
                          <SelectTrigger><SelectValue placeholder="Pick housing system" /></SelectTrigger>
                          <SelectContent>
                            {POULTRY_HOUSING_SYSTEMS.map(o => <SelectItem key={o} value={o}>{POULTRY_HOUSING_LABELS[o]}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      )
                    })()}
                  </div>

                  <div className="md:col-span-2"><Label>Farm site address</Label>
                    <Input value={form.farmSiteAddress ?? ""} onChange={(e) => setForm({ ...form, farmSiteAddress: e.target.value })} /></div>

                  <div><Label>Main location / town</Label>
                    <Input value={form.mainLocation ?? ""} onChange={(e) => setForm({ ...form, mainLocation: e.target.value })} /></div>

                  <div><Label>Owner name</Label>
                    <Input value={form.ownerName ?? ""} onChange={(e) => setForm({ ...form, ownerName: e.target.value })} /></div>

                  <div><Label>Phone</Label>
                    <Input value={form.phoneNumber ?? ""} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} placeholder="+233..." /></div>

                  <div><Label>Email</Label>
                    <Input type="email" value={form.email ?? ""} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>

                  <div><Label htmlFor="default-currency">Default currency</Label>
                    <CurrencySelect id="default-currency" value={form.defaultCurrency ?? "GHC"}
                      onChange={(o) => setForm({ ...form, defaultCurrency: o.code })} /></div>

                  <div><Label>Eggs per crate</Label>
                    <NumberInput min={1} value={form.defaultCrateEggCount ?? 30}
                      onChange={(e) => setForm({ ...form, defaultCrateEggCount: Number(e.target.value) || 30 })} />
                    <p className="mt-1 text-xs text-slate-500">Used to convert crates to eggs when a vehicle is loaded and a driver return is reconciled.</p>
                  </div>

                  <div><Label>Total capacity (birds)</Label>
                    <NumberInput min={0} value={form.totalCapacity ?? ""}
                      onChange={(e) => setForm({ ...form, totalCapacity: e.target.value === "" ? null : Number(e.target.value) })} /></div>

                  <div><Label>Operating hours</Label>
                    <Input value={form.operatingHours ?? ""} onChange={(e) => setForm({ ...form, operatingHours: e.target.value })} placeholder="e.g. 6:00 AM – 6:00 PM" /></div>

                  <div className="md:col-span-2"><Label>Notes</Label>
                    <Textarea value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>

                  <div className="md:col-span-2 flex justify-end">
                    <Button onClick={save} disabled={saving}>
                      {saving ? "Saving…" : profile ? "Save changes" : "Set up Poultry Company"}
                    </Button>
                  </div>

                  {!profile && (
                    <p className="md:col-span-2 text-xs text-slate-500">
                      First-time setup seeds the default cash accounts automatically.
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

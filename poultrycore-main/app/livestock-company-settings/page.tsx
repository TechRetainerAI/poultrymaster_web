"use client"

// Company settings -- the poultry Company settings for livestock: who the
// business is and how to reach it (migration 467), its currency, and its
// business time zone. Owner/admin can change it; everyone else sees it.

import { useEffect, useMemo, useState } from "react"
import { Building2, Loader2, Save } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { CurrencySelect } from "@/components/ui/currency-select"
import { CompanyTimeZoneField } from "@/components/settings/company-timezone-field"
import { currencySymbolFor } from "@/lib/constants/currencies"
import { fetchFarmSettings, updateFarmCurrency, useFarmSettingsStore } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { getCompanyProfile, saveCompanyProfile, type CompanyProfileInput } from "@/lib/api/livestock"
import { AMBER_BUTTON, LivestockPage, LoadError, Loading } from "@/components/livestock/livestock-page"

const EMPTY: CompanyProfileInput = {
  brandName: "", ownerName: "", phoneNumber: "", email: "", mainLocation: "", siteAddress: "",
  totalCapacity: null, operatingHours: "", notes: "",
}
type Currency = { code: string; symbol: string; show: boolean }
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)

export default function LivestockCompanySettingsPage() {
  const { toast } = useToast()
  const { isAdmin } = usePermissions()
  const apply = useFarmSettingsStore((s) => s.apply)
  const [saved, setSaved] = useState<CompanyProfileInput | null>(null)
  const [form, setForm] = useState<CompanyProfileInput>(EMPTY)
  const [isNew, setIsNew] = useState(false)
  const [cur, setCur] = useState<Currency>({ code: "GHS", symbol: "GHC", show: true })
  const [savedCur, setSavedCur] = useState<Currency>(cur)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const load = async () => {
    setError(null)
    try {
      const [p, fs] = await Promise.all([getCompanyProfile(), fetchFarmSettings().catch(() => null)])
      const f: CompanyProfileInput = {
        brandName: p.brandName ?? "", ownerName: p.ownerName ?? "", phoneNumber: p.phoneNumber ?? "", email: p.email ?? "",
        mainLocation: p.mainLocation ?? "", siteAddress: p.siteAddress ?? "", totalCapacity: p.totalCapacity,
        operatingHours: p.operatingHours ?? "", notes: p.notes ?? "",
      }
      setSaved(f); setForm(f); setIsNew(!p.exists)
      if (fs) {
        const c = { code: fs.currencyCode, symbol: fs.currencySymbol, show: fs.showCurrencySymbol }
        setCur(c); setSavedCur(c); apply(fs)
      }
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }
  useEffect(() => { load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const dirty = useMemo(() => !!saved && (isNew || !same(form, saved) || !same(cur, savedCur)), [form, saved, cur, savedCur, isNew])
  const ro = !isAdmin
  const set = <K extends keyof CompanyProfileInput>(k: K, v: CompanyProfileInput[K]) => setForm((f) => ({ ...f, [k]: v }))

  const submit = async () => {
    setSaving(true)
    try {
      await saveCompanyProfile(form)
      const symbol = cur.symbol.trim() || currencySymbolFor(cur.code) || cur.code
      const updated = await updateFarmCurrency({ currencyCode: cur.code, currencySymbol: symbol, showCurrencySymbol: cur.show })
      if (updated) apply(updated)
      const next = { ...cur, symbol }
      setCur(next); setSavedCur(next); setSaved(form); setIsNew(false)
      toast({ title: "Company settings saved" })
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <LivestockPage title="Company settings" description="Your business name and contacts, capacity, currency and time zone." icon={Building2}>
      {error ? <LoadError message={error} onRetry={load} /> : !saved ? <Loading /> : (
        <div className="space-y-4 max-w-4xl">
          {ro && <p className="text-sm text-stone-500">Only the owner or an admin can change these.</p>}
          {isNew && !ro && <p className="text-sm text-amber-800">Not saved yet — check the details and press Save.</p>}

          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Business profile</CardTitle></CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div className="space-y-1.5 sm:col-span-2"><Label htmlFor="cs-name">Farm / brand name</Label>
                <Input id="cs-name" value={form.brandName ?? ""} disabled={ro} placeholder="e.g. Emjude Farms" onChange={(e) => set("brandName", e.target.value)} /></div>
              <div className="space-y-1.5"><Label htmlFor="cs-owner">Owner name</Label>
                <Input id="cs-owner" value={form.ownerName ?? ""} disabled={ro} onChange={(e) => set("ownerName", e.target.value)} /></div>
              <div className="space-y-1.5"><Label htmlFor="cs-phone">Phone</Label>
                <Input id="cs-phone" value={form.phoneNumber ?? ""} disabled={ro} placeholder="+233..." onChange={(e) => set("phoneNumber", e.target.value)} /></div>
              <div className="space-y-1.5"><Label htmlFor="cs-email">Email</Label>
                <Input id="cs-email" type="email" value={form.email ?? ""} disabled={ro} onChange={(e) => set("email", e.target.value)} /></div>
              <div className="space-y-1.5"><Label htmlFor="cs-town">Main location / town</Label>
                <Input id="cs-town" value={form.mainLocation ?? ""} disabled={ro} onChange={(e) => set("mainLocation", e.target.value)} /></div>
              <div className="space-y-1.5 sm:col-span-2"><Label htmlFor="cs-addr">Farm site address</Label>
                <Input id="cs-addr" value={form.siteAddress ?? ""} disabled={ro} onChange={(e) => set("siteAddress", e.target.value)} /></div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Farm details</CardTitle></CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div className="space-y-1.5"><Label htmlFor="cs-cap">Total capacity (animals)</Label>
                <Input id="cs-cap" type="number" min={0} inputMode="numeric" value={form.totalCapacity ?? ""} disabled={ro}
                  onChange={(e) => set("totalCapacity", e.target.value === "" ? null : Number(e.target.value))} /></div>
              <div className="space-y-1.5 sm:col-span-2"><Label htmlFor="cs-hours">Operating hours</Label>
                <Input id="cs-hours" value={form.operatingHours ?? ""} disabled={ro} placeholder="e.g. 6:00 AM – 6:00 PM"
                  onChange={(e) => set("operatingHours", e.target.value)} /></div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Currency &amp; time zone</CardTitle></CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div className="space-y-1.5"><Label htmlFor="cs-currency">Currency</Label>
                <CurrencySelect id="cs-currency" value={cur.code} disabled={ro} onChange={(o) => setCur({ ...cur, code: o.code, symbol: o.symbol })} /></div>
              <div className="space-y-1.5"><Label htmlFor="cs-symbol">Symbol</Label>
                <Input id="cs-symbol" value={cur.symbol} disabled={ro} maxLength={10} placeholder={currencySymbolFor(cur.code) || "GHC"}
                  onChange={(e) => setCur({ ...cur, symbol: e.target.value })} /></div>
              <label htmlFor="cs-show" className="flex items-center gap-3 rounded-lg border border-stone-200 bg-stone-50/60 px-3 py-2.5 self-end sm:col-span-2">
                <Switch id="cs-show" checked={cur.show} disabled={ro} onCheckedChange={(v) => setCur({ ...cur, show: v })} />
                <span className="text-sm font-medium text-stone-700">Show symbol on amounts</span>
              </label>
              {/* Saves itself with its own button, so it is not part of this form's changes. */}
              <CompanyTimeZoneField className="sm:col-span-2 lg:col-span-4" />
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Notes</CardTitle></CardHeader>
            <CardContent>
              <Textarea value={form.notes ?? ""} disabled={ro} className="min-h-[100px]" onChange={(e) => set("notes", e.target.value)} />
            </CardContent>
          </Card>

          {!ro && (
            <div className="flex justify-end gap-2">
              <Button variant="outline" disabled={saving || !dirty || isNew} onClick={() => { setForm(saved); setCur(savedCur) }}>Discard</Button>
              <Button className={AMBER_BUTTON} disabled={saving || !dirty || !form.brandName?.trim()} onClick={submit}>
                {saving ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> Save company settings</>}
              </Button>
            </div>
          )}
        </div>
      )}
    </LivestockPage>
  )
}

"use client"

// Production Setup > Company settings: the poultry company profile (migration
// 212) in one form -- who the business is, how the farm runs, its currency and
// its business time zone. (Until 2026-11-07 it was two tabs: Farm profile under
// Production and Company profile under Business.)
//
// Saves the whole PoultryCompanyProfiles row. The first save on a farm with no
// profile creates it (setupPoultryCompany also seeds the default cash accounts).
// Currency lives on the Farms row and is saved alongside; the time zone also
// lives on Farms but saves itself (see CompanyTimeZoneField for why).

import { useEffect, useMemo, useRef, useState } from "react"
import { Loader2, Save, Undo2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { CurrencySelect } from "@/components/ui/currency-select"
import { currencySymbolFor } from "@/lib/constants/currencies"
import { fetchFarmSettings, updateFarmCurrency, useFarmSettingsStore } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useSetupDirty, useSetupEmbedded, SetupTaskBar } from "@/components/setup/setup-embed"
import { CompanyTimeZoneField } from "@/components/settings/company-timezone-field"
import {
  getPoultryCompanyProfile, setupPoultryCompany, updatePoultryCompanyProfile,
  POULTRY_BUSINESS_TYPES, POULTRY_HOUSING_SYSTEMS, POULTRY_HOUSING_LABELS,
} from "@/lib/api/poultry-company"

type Profile = {
  brandName: string
  businessType: string
  housingSystem: string
  farmSiteAddress: string
  mainLocation: string
  ownerName: string
  phoneNumber: string
  email: string
  defaultCurrency: string
  defaultCrateEggCount: number
  totalCapacity: number | null
  operatingHours: string
  notes: string
}

const EMPTY: Profile = {
  brandName: "", businessType: "Layers", housingSystem: "DeepLitter", farmSiteAddress: "",
  mainLocation: "", ownerName: "", phoneNumber: "", email: "", defaultCurrency: "GHC",
  defaultCrateEggCount: 30, totalCapacity: null, operatingHours: "", notes: "",
}

const pickType = (v: string) => POULTRY_BUSINESS_TYPES.find((o) => o.toLowerCase() === (v ?? "").toLowerCase()) ?? "Layers"
const pickHousing = (v: string) => POULTRY_HOUSING_SYSTEMS.find((o) => o.toLowerCase() === (v ?? "").toLowerCase()) ?? "DeepLitter"

/** Loads the profile row and saves it whole. */
function useProfile() {
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [hasProfile, setHasProfile] = useState(false)
  const [saved, setSaved] = useState<Profile>(EMPTY)

  const load = async () => {
    setLoading(true)
    try {
      const p = await getPoultryCompanyProfile().catch(() => null)
      if (p) {
        setHasProfile(true)
        setSaved({
          brandName: p.brandName ?? "", businessType: p.businessType ?? "Layers", housingSystem: p.housingSystem ?? "DeepLitter",
          farmSiteAddress: p.farmSiteAddress ?? "", mainLocation: p.mainLocation ?? "", ownerName: p.ownerName ?? "",
          phoneNumber: p.phoneNumber ?? "", email: p.email ?? "", defaultCurrency: p.defaultCurrency ?? "GHC",
          defaultCrateEggCount: p.defaultCrateEggCount ?? 30, totalCapacity: p.totalCapacity ?? null,
          operatingHours: p.operatingHours ?? "", notes: p.notes ?? "",
        })
      } else {
        setHasProfile(false)
        setSaved(EMPTY)
      }
    } catch (e: any) {
      toast({ title: "Could not load company settings", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }
  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [])

  /** Save `changes` on top of the loaded row. Throws on failure. */
  const save = async (changes: Partial<Profile>) => {
    const merged = { ...saved, ...changes }
    // Normalize what we SEND: an older row may hold lowercase or blank values
    // the dropdowns tolerate for display but the database rejects.
    const payload = {
      ...merged,
      businessType: pickType(merged.businessType),
      housingSystem: pickHousing(merged.housingSystem),
      defaultCrateEggCount: Math.max(1, Number(merged.defaultCrateEggCount) || 30),
      totalCapacity: merged.totalCapacity === null || Number.isNaN(Number(merged.totalCapacity)) ? null : Number(merged.totalCapacity),
    }
    if (hasProfile) await updatePoultryCompanyProfile(payload)
    else { await setupPoultryCompany(payload); setHasProfile(true) }
    setSaved(payload)
    return !hasProfile
  }

  return { loading, hasProfile, saved, save }
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)

function SaveBar({ dirty, saving, disabled, onSave, onDiscard, label }: {
  dirty: boolean; saving: boolean; disabled?: boolean; onSave: () => void; onDiscard: () => void; label: string
}) {
  return (
    <div className="flex flex-col-reverse gap-2 border-t border-slate-100 pt-4 sm:flex-row sm:items-center sm:justify-end">
      {dirty && <span className="text-xs text-amber-700 sm:mr-auto">You have unsaved changes.</span>}
      <Button variant="outline" onClick={onDiscard} disabled={saving || !dirty}>Discard</Button>
      <Button onClick={onSave} disabled={saving || disabled || !dirty} className="min-w-[150px]">
        {saving ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {label}</>}
      </Button>
    </div>
  )
}

function Loading() {
  return <div className="flex items-center gap-2 py-6 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
}

// ---------------------------------------------------------------------------
// Production Setup > Company settings
// ---------------------------------------------------------------------------
type Fields = Omit<Profile, "defaultCurrency">
const fieldsOf = (p: Profile): Fields => ({
  brandName: p.brandName, ownerName: p.ownerName, phoneNumber: p.phoneNumber, email: p.email,
  mainLocation: p.mainLocation, notes: p.notes,
  businessType: pickType(p.businessType), housingSystem: pickHousing(p.housingSystem), farmSiteAddress: p.farmSiteAddress,
  totalCapacity: p.totalCapacity, defaultCrateEggCount: p.defaultCrateEggCount, operatingHours: p.operatingHours,
})
type Currency = { code: string; symbol: string; show: boolean }

export function CompanySettingsForm() {
  const { toast } = useToast()
  const { canEdit } = usePermissions()
  const apply = useFarmSettingsStore((s) => s.apply)
  const { loading, saved, save } = useProfile()
  const [form, setForm] = useState<Fields>(fieldsOf(EMPTY))
  const [saving, setSaving] = useState(false)
  const base = useMemo(() => fieldsOf(saved), [saved])
  useEffect(() => { setForm(base) }, [base])

  // Currency lives on the Farms row, not the profile; the profile mirrors it.
  const [cur, setCur] = useState<Currency>({ code: "GHS", symbol: "GHC", show: true })
  const [savedCur, setSavedCur] = useState<Currency>({ code: "GHS", symbol: "GHC", show: true })
  const [curLoading, setCurLoading] = useState(true)
  const seededFromProfile = useRef(false)
  useEffect(() => {
    void (async () => {
      const fs = await fetchFarmSettings().catch(() => null)
      if (fs) {
        const c = { code: fs.currencyCode, symbol: fs.currencySymbol, show: fs.showCurrencySymbol }
        setCur(c); setSavedCur(c); apply(fs)
        seededFromProfile.current = true
      }
      setCurLoading(false)
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  // A company set up before the Farms row carried a currency would show the GHS
  // default while its profile said otherwise: seed from the profile then.
  useEffect(() => {
    if (loading || curLoading || seededFromProfile.current || !saved.defaultCurrency) return
    seededFromProfile.current = true
    const c = { code: saved.defaultCurrency.toUpperCase(), symbol: currencySymbolFor(saved.defaultCurrency), show: true }
    setCur(c); setSavedCur(c)
  }, [loading, curLoading, saved.defaultCurrency])

  const dirty = !loading && !curLoading && (!same(form, base) || !same(cur, savedCur))
  useSetupDirty(dirty)
  const ro = !canEdit
  const embedded = useSetupEmbedded()

  async function submit() {
    if (saving) return
    setSaving(true)
    try {
      // The Currency control is the single place currency is chosen; mirror it
      // into the profile so the two rows always agree.
      const created = await save({ ...form, defaultCurrency: cur.code })
      const symbol = cur.symbol.trim() || currencySymbolFor(cur.code) || cur.code
      const updated = await updateFarmCurrency({ currencyCode: cur.code, currencySymbol: symbol, showCurrencySymbol: cur.show })
      if (updated) apply(updated)
      const next = { ...cur, symbol }
      setCur(next); setSavedCur(next)
      toast({ title: created ? "Poultry Company set up" : "Company settings saved", description: created ? "Default cash accounts seeded." : undefined })
    } catch (e: any) {
      // Keep what was typed so the user can fix it and try again.
      toast({ title: "Save failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  if (loading || curLoading) return <Loading />
  return (
    <div className="space-y-6">
      <div className="divide-y divide-slate-100">
        {/* Business profile */}
        <section className="grid gap-x-10 gap-y-5 pb-8 lg:grid-cols-[minmax(0,240px)_1fr]">
          <div>
            <h3 className="text-sm font-semibold text-slate-900">Business profile</h3>
            <p className="mt-1 text-sm leading-relaxed text-slate-500">Your farm&apos;s name, owner and how customers and receipts reach you.</p>
          </div>
          <div className="grid gap-x-6 gap-y-5 sm:grid-cols-2">
            <div className="space-y-1.5 sm:col-span-2"><Label>Farm / brand name</Label>
              <Input value={form.brandName} disabled={ro} placeholder="e.g. Gyimah Farm" onChange={(e) => setForm({ ...form, brandName: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>Owner name</Label>
              <Input value={form.ownerName} disabled={ro} onChange={(e) => setForm({ ...form, ownerName: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>Phone</Label>
              <Input value={form.phoneNumber} disabled={ro} placeholder="+233..." onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>Email</Label>
              <Input type="email" value={form.email} disabled={ro} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>Main location / town</Label>
              <Input value={form.mainLocation} disabled={ro} onChange={(e) => setForm({ ...form, mainLocation: e.target.value })} /></div>
            <div className="space-y-1.5 sm:col-span-2"><Label>Farm site address</Label>
              <Input value={form.farmSiteAddress} disabled={ro} onChange={(e) => setForm({ ...form, farmSiteAddress: e.target.value })} /></div>
          </div>
        </section>

        {/* Farm details */}
        <section className="grid gap-x-10 gap-y-5 py-8 lg:grid-cols-[minmax(0,240px)_1fr]">
          <div>
            <h3 className="text-sm font-semibold text-slate-900">Farm details</h3>
            <p className="mt-1 text-sm leading-relaxed text-slate-500">Flock type, housing and the defaults your production records start from.</p>
          </div>
          <div className="grid gap-x-6 gap-y-5 sm:grid-cols-2">
            <div className="space-y-1.5"><Label>Business type</Label>
              <Select value={form.businessType} onValueChange={(v) => setForm({ ...form, businessType: v })} disabled={ro}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{POULTRY_BUSINESS_TYPES.map((o) => <SelectItem key={o} value={o}>{o}</SelectItem>)}</SelectContent>
              </Select></div>
            <div className="space-y-1.5"><Label>Housing system</Label>
              <Select value={form.housingSystem} onValueChange={(v) => setForm({ ...form, housingSystem: v })} disabled={ro}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{POULTRY_HOUSING_SYSTEMS.map((o) => <SelectItem key={o} value={o}>{POULTRY_HOUSING_LABELS[o]}</SelectItem>)}</SelectContent>
              </Select></div>
            <div className="space-y-1.5"><Label>Total capacity (birds)</Label>
              <NumberInput min={0} value={form.totalCapacity ?? ""} disabled={ro}
                onChange={(e) => setForm({ ...form, totalCapacity: e.target.value === "" ? null : Number(e.target.value) })} /></div>
            <div className="space-y-1.5"><Label>Eggs per crate</Label>
              <NumberInput min={1} value={form.defaultCrateEggCount} disabled={ro}
                onChange={(e) => setForm({ ...form, defaultCrateEggCount: Number(e.target.value) || 30 })} /></div>
            <div className="space-y-1.5 sm:col-span-2"><Label>Operating hours</Label>
              <Input value={form.operatingHours} disabled={ro} placeholder="e.g. 6:00 AM – 6:00 PM"
                onChange={(e) => setForm({ ...form, operatingHours: e.target.value })} /></div>
          </div>
        </section>

        {/* Currency & time zone */}
        <section className="grid gap-x-10 gap-y-5 py-8 lg:grid-cols-[minmax(0,240px)_1fr]">
          <div>
            <h3 className="text-sm font-semibold text-slate-900">Currency &amp; time zone</h3>
            <p className="mt-1 text-sm leading-relaxed text-slate-500">How money is shown on amounts, and the time zone your days and reports follow.</p>
          </div>
          <div className="grid gap-x-6 gap-y-5 sm:grid-cols-2">
            <div className="space-y-1.5"><Label htmlFor="farm-currency">Currency</Label>
              {/* Picking a currency fills in its standard symbol; the symbol stays
                  editable because many Ghanaian businesses write "GHC", not "₵". */}
              <CurrencySelect id="farm-currency" value={cur.code} disabled={ro}
                onChange={(o) => setCur({ ...cur, code: o.code, symbol: o.symbol })} /></div>
            <div className="space-y-1.5"><Label>Symbol</Label>
              <Input value={cur.symbol} disabled={ro} maxLength={10} placeholder={currencySymbolFor(cur.code) || "GHC"}
                onChange={(e) => setCur({ ...cur, symbol: e.target.value })}
                onBlur={() => { if (!cur.symbol.trim()) setCur({ ...cur, symbol: currencySymbolFor(cur.code) || cur.code }) }} />
              <p className="text-xs text-slate-500">To hide it, turn off &quot;Show symbol on amounts&quot;.</p></div>
            <label htmlFor="show-symbol" className="flex items-center gap-3 rounded-lg border border-slate-200 bg-slate-50/60 px-3 py-2.5 sm:col-span-2">
              <Switch checked={cur.show} disabled={ro} onCheckedChange={(v) => setCur({ ...cur, show: v })} id="show-symbol" />
              <span className="text-sm font-medium text-slate-700">Show symbol on amounts</span>
            </label>
            {/* Saves itself with its own button (it validates the zone and marks it
                confirmed), so it is not part of this form's unsaved changes. */}
            <CompanyTimeZoneField className="sm:col-span-2" />
          </div>
        </section>

        {/* Notes */}
        <section className="grid gap-x-10 gap-y-5 pt-8 lg:grid-cols-[minmax(0,240px)_1fr]">
          <div>
            <h3 className="text-sm font-semibold text-slate-900">Notes</h3>
            <p className="mt-1 text-sm leading-relaxed text-slate-500">Anything else you want kept on file for this company.</p>
          </div>
          <Textarea value={form.notes} disabled={ro} className="min-h-[120px]" onChange={(e) => setForm({ ...form, notes: e.target.value })} />
        </section>
      </div>

      {/* In Farm Setup, Save and Discard are on the task bar. */}
      {!ro && embedded && (
        <SetupTaskBar tasks={[
          { id: "save", label: saving ? "Saving…" : "Save company settings", icon: Save, primary: true, onClick: submit, disabled: !dirty || saving },
          { id: "discard", label: "Discard", icon: Undo2, onClick: () => { setForm(base); setCur(savedCur) }, disabled: saving, hidden: !dirty },
        ]} />
      )}
      {!ro && !embedded && (
        <SaveBar dirty={dirty} saving={saving} onSave={submit}
          onDiscard={() => { setForm(base); setCur(savedCur) }} label="Save company settings" />
      )}
    </div>
  )
}

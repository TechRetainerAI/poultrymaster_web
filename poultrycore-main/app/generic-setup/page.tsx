"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { CompanyTimeZoneField } from "@/components/settings/company-timezone-field"
import { Loader2, Settings, CheckCircle2, ArrowLeft, Save } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  GENERIC_BUSINESS_TYPES, businessTypeForIndustry, legacyCategoryIdFor,
} from "@/lib/companies/business-types"
import { applyBusinessTemplate, getBusinessTemplate } from "@/lib/api/generic-subscriptions"
import { invalidateGenericModules } from "@/hooks/use-generic-modules"
import {
  type BusinessCategory,
  type GenericCompanyProfile,
  getBusinessCategories,
  getProfile,
  setupProfile,
  updateProfile,
} from "@/lib/api/generic"

export default function GenericSetupPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [profile, setProfile] = useState<GenericCompanyProfile | null>(null)
  const [categories, setCategories] = useState<BusinessCategory[]>([])

  const [form, setForm] = useState({
    businessCategoryId: "",
    businessTypeId: "",
    businessDescription: "",
    defaultCurrency: "GHC",
    openingCashBalance: "0",
    businessStartDate: "",
    mainLocation: "",
    ownerName: "",
    phoneNumber: "",
    notes: "",
  })

  useEffect(() => {
    // Wait for the persisted store to hydrate before deciding. Reading this as
    // `activeFarmType && ...` skipped the redirect while it was still
    // undefined, and the fetch below then ran against whichever company was
    // active before -- which is how a Poultry company reached this page and got
    // a 409 it could not explain.
    if (!activeFarmType) return
    if (activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    let cancelled = false
    ;(async () => {
      // allSettled, NOT all. The business categories are a platform-wide list
      // that has nothing to do with which company is active, so a profile
      // failure must not take them down with it -- that is what left this page
      // showing an empty category dropdown AND an error at the same time.
      const [catsR, profileR, templateR] = await Promise.allSettled([
        getBusinessCategories(), getProfile(), getBusinessTemplate(),
      ])
      if (cancelled) return

      if (catsR.status === "fulfilled") {
        setCategories(catsR.value)
      } else {
        toast({
          title: "Could not load business categories",
          description: catsR.reason?.message ?? String(catsR.reason),
          variant: "destructive",
        })
      }

      if (profileR.status === "rejected") {
        const msg = profileR.reason?.message ?? String(profileR.reason)
        // The commonest cause by far, and the one the old message hid: you are
        // on a company of another type. The API says so in as many words, so
        // repeat it rather than replacing it with something vaguer.
        toast({
          title: /409/.test(msg) ? "Wrong company type" : "Could not load this company's setup",
          description: msg,
          variant: "destructive",
        })
        setLoading(false)
        return
      }

      // Preselect whatever this company is already on, so the page opens
      // showing the truth rather than a blank question.
      if (templateR.status === "fulfilled") {
        const bt = businessTypeForIndustry(templateR.value?.genericIndustryTemplate)
        if (bt) setForm((f) => ({ ...f, businessTypeId: bt.id }))
      }

      try {
        const p = profileR.value
        if (p) {
          setProfile(p)
          setForm((f) => ({
            ...f,   // keep the business type already preselected from the template
            businessCategoryId: p.businessCategoryId?.toString() ?? "",
            businessDescription: p.businessDescription ?? "",
            defaultCurrency: p.defaultCurrency ?? "GHC",
            openingCashBalance: (p.openingCashBalance ?? 0).toString(),
            businessStartDate: p.businessStartDate?.slice(0, 10) ?? "",
            mainLocation: p.mainLocation ?? "",
            ownerName: p.ownerName ?? "",
            phoneNumber: p.phoneNumber ?? "",
            notes: p.notes ?? "",
          }))
        }
      } catch (e: any) {
        toast({ title: "Could not read this company's setup", description: e?.message ?? String(e), variant: "destructive" })
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      const chosen = GENERIC_BUSINESS_TYPES.find((t) => t.id === form.businessTypeId)
      const body = {
        // Derived from the business type rather than asked for separately.
        businessCategoryId:
          legacyCategoryIdFor(chosen?.industryTemplate, categories)
          ?? (form.businessCategoryId ? Number(form.businessCategoryId) : null),
        businessDescription: form.businessDescription || null,
        defaultCurrency: form.defaultCurrency || "GHC",
        // Opening cash seeds the Main Cash Box once, at setup. After that it is
        // shown read-only and sent back unchanged.
        openingCashBalance: profile
          ? (profile.openingCashBalance ?? 0)
          : (Number(form.openingCashBalance) || 0),
        businessStartDate: form.businessStartDate || null,
        mainLocation: form.mainLocation || null,
        ownerName: form.ownerName || null,
        phoneNumber: form.phoneNumber || null,
        notes: form.notes || null,
      }
      // POST /setup only inserts a profile when none exists (it skips an
      // existing one), so an already set-up company must save with PUT or
      // every edit is silently dropped.
      const updated = profile ? await updateProfile(body) : await setupProfile(body)
      if (updated) {
        setProfile(updated)

        // The profile has to exist before a template can be stamped on it, so
        // this runs second, never first. Applying only ever inserts and every
        // insert is guarded, so re-saving is safe and keeps anything already
        // edited.
        if (chosen?.businessTemplate && chosen?.industryTemplate) {
          await applyBusinessTemplate({
            businessTemplate: chosen.businessTemplate,
            industryTemplate: chosen.industryTemplate,
          })
          // The sidebar, top nav and mobile bar cache module settings, so drop
          // the cache or the new menus only appear after a reload.
          invalidateGenericModules(activeFarmId ?? undefined)
        }

        toast({
          title: profile ? "Setup updated" : `Set up as ${chosen?.label ?? "a Generic company"}`,
          description: chosen
            ? "Menus, labels and starter categories now match this business."
            : "Default categories, cash accounts and lookups have been seeded.",
        })
        if (!profile) router.push("/generic-dashboard")
      }
    } catch (err: any) {
      toast({ title: "Could not save", description: err?.message ?? String(err), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const set = (key: keyof typeof form) =>
    (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
      setForm((f) => ({ ...f, [key]: e.target.value }))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <button type="button" onClick={() => router.back()} className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back
          </button>
          <form onSubmit={onSubmit}>
            <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
              <div>
                <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2 flex-wrap">
                  <Settings className="h-6 w-6 text-emerald-600" />
                  {profile ? "Business profile" : "Set up your business"}
                  {profile && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700">
                      <CheckCircle2 className="h-3.5 w-3.5" /> Already set up
                    </span>
                  )}
                </h1>
                <p className="text-sm text-slate-500">
                  {profile
                    ? "Who this company is. Default lookups stay as they are; saving does not re-seed them."
                    : "Pick your business type and basic details. We'll seed default expense categories, cash accounts, customer/supplier types and payment methods."}
                </p>
              </div>
              <div className="flex gap-2">
                <Button type="button" variant="outline" onClick={() => router.push("/generic-dashboard")}>Cancel</Button>
                <Button type="submit" disabled={saving || loading}>
                  {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
                  {profile ? "Save changes" : "Set up & continue"}
                </Button>
              </div>
            </div>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading…
              </div>
            ) : (
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                {/* ---- business type ------------------------------------- */}
                <Card className="lg:col-span-2">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Business type</CardTitle>
                    <CardDescription>
                      Sets what things are called, which menus appear, and the categories, accounts and
                      starter plans you begin with. You can change all of it afterwards.
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    {/* The old "business category" list is still stored underneath,
                        mapped from this choice, because some reports read it. */}
                    <Label>What kind of business is this?</Label>
                    <Select
                      value={form.businessTypeId}
                      onValueChange={(v) => setForm((f) => ({ ...f, businessTypeId: v }))}
                    >
                      <SelectTrigger><SelectValue placeholder="Choose…" /></SelectTrigger>
                      <SelectContent>
                        {GENERIC_BUSINESS_TYPES.map((t) => (
                          <SelectItem key={t.id} value={t.id}>
                            {t.label} — {t.description}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </CardContent>
                </Card>

                {/* ---- owner & contact ----------------------------------- */}
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Owner &amp; contact</CardTitle>
                    <CardDescription>Who runs the business and where to find it.</CardDescription>
                  </CardHeader>
                  <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div>
                      <Label>Owner name</Label>
                      <Input value={form.ownerName} maxLength={150} onChange={set("ownerName")} />
                    </div>
                    <div>
                      <Label>Phone number</Label>
                      <Input value={form.phoneNumber} maxLength={50} onChange={set("phoneNumber")} />
                    </div>
                    <div className="sm:col-span-2">
                      <Label>Main location</Label>
                      <Input value={form.mainLocation} maxLength={255} onChange={set("mainLocation")} />
                    </div>
                    <div className="sm:col-span-2">
                      <Label>Business description</Label>
                      <Textarea rows={3} maxLength={500} value={form.businessDescription} onChange={set("businessDescription")} />
                    </div>
                  </CardContent>
                </Card>

                {/* ---- money & time -------------------------------------- */}
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Money &amp; time</CardTitle>
                    <CardDescription>Currency, opening cash, start date and the company&apos;s timezone.</CardDescription>
                  </CardHeader>
                  <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div>
                      <Label>Default currency</Label>
                      <Input value={form.defaultCurrency} maxLength={10} onChange={set("defaultCurrency")} />
                    </div>
                    <div>
                      <Label>Business start date</Label>
                      <Input type="date" value={form.businessStartDate} onChange={set("businessStartDate")} />
                    </div>
                    <div>
                      <Label>Opening cash ({form.defaultCurrency})</Label>
                      <NumberInput
                        step="0.01"
                        value={form.openingCashBalance}
                        disabled={!!profile}
                        onChange={set("openingCashBalance")}
                      />
                      <p className="text-xs text-slate-500 mt-1">
                        {profile
                          ? "Set once, at setup. Correct a balance from Cash & accounts."
                          : "Seeds the \"Main Cash Box\" account."}
                      </p>
                    </div>
                    <CompanyTimeZoneField />
                  </CardContent>
                </Card>

                {/* ---- notes --------------------------------------------- */}
                <Card className="lg:col-span-2">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Notes</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <Textarea rows={3} maxLength={1000} value={form.notes} onChange={set("notes")} />
                  </CardContent>
                </Card>
              </div>
            )}
          </form>
        </main>
      </div>
    </div>
  )
}

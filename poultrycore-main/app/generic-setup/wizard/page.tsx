"use client"

// Setup wizard — the three questions a new service business has to answer
// before the app is useful to it.
//
// A NEW route, not a rewrite of /generic-setup. That page is how every existing
// Generic company edits its profile, and it has to keep working exactly as it
// does. This one runs once, after the company is created.
//
// Step 1 picks the industry, which decides the vocabulary and what gets seeded.
// Step 2 confirms which modules are on — a gym that also sells towels turns
// Products back on here and nothing was lost. Step 3 is the handover.
//
// Applying a template only ever inserts, and every insert is guarded, so
// running the wizard twice is safe: the owner gets any new seeds and keeps
// everything they have already edited.

import { useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Loader2, Check, ArrowRight, ArrowLeft, Sparkles } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  applyBusinessTemplate, getModuleSettings, saveModuleSettings, getBusinessTemplate,
  type GenericModuleSettings,
} from "@/lib/api/generic-subscriptions"
import { BUSINESS_TYPES, type BusinessType } from "@/lib/companies/business-types"
import { getProfile, setupProfile } from "@/lib/api/generic"
import { invalidateGenericModules } from "@/hooks/use-generic-modules"
import { templateLabels } from "@/lib/generic/template-labels"

// Only the Generic-based types are choices here — a company is already Generic
// by the time it reaches this page.
const CHOICES: BusinessType[] = BUSINESS_TYPES.filter((t) => t.companyType === "Generic")

const MODULE_ROWS: { key: keyof GenericModuleSettings; label: string; hint: string }[] = [
  { key: "enableSubscriptions", label: "Subscriptions", hint: "Bill the same customer every period" },
  { key: "enableInvoices", label: "Invoices", hint: "Raise bills and track what is owed" },
  { key: "enableCustomerBalances", label: "Customer balances", hint: "Who owes you, and take payment" },
  { key: "enableProducts", label: "Products", hint: "Things you sell off a shelf" },
  { key: "enableInventory", label: "Inventory", hint: "Stock levels and movements" },
  { key: "enableStockAdjustments", label: "Stock adjustments", hint: "Corrections to stock on hand" },
  { key: "enableInternalUse", label: "Internal use", hint: "Stock taken for the business itself" },
  { key: "enablePurchases", label: "Purchases", hint: "What you buy from suppliers" },
  { key: "enableStaffPayments", label: "Staff and payroll", hint: "Staff, attendance and pay runs" },
  { key: "enableCashAccounts", label: "Cash accounts", hint: "Till, bank and mobile money" },
]

export default function GenericSetupWizardPage() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const logout = useLogout()
  const { toast } = useToast()

  const [step, setStep] = useState(1)
  const [choice, setChoice] = useState<BusinessType | null>(null)
  const [settings, setSettings] = useState<GenericModuleSettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [applying, setApplying] = useState(false)
  const [saving, setSaving] = useState(false)

  const labels = templateLabels(choice?.industryTemplate)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    // Pre-select whatever this company is already on, so re-running the wizard
    // starts from the truth rather than from a blank form.
    Promise.all([getBusinessTemplate().catch(() => null), getModuleSettings().catch(() => null)])
      .then(([template, s]) => {
        // Already templated? Start from the truth. Otherwise fall back to the
        // business type picked at creation, which arrives as ?industry=.
        const existing = template?.genericIndustryTemplate ?? searchParams.get("industry")
        if (existing) {
          setChoice(CHOICES.find((c) => c.industryTemplate === existing) ?? null)
        }
        if (s) setSettings(s)
      })
      .finally(() => setLoading(false))
  }, [activeFarmType, router, searchParams])

  const onApply = async () => {
    if (!choice?.businessTemplate || !choice?.industryTemplate) return
    setApplying(true)
    try {
      // A template can only be stamped on a profile that exists, and a brand
      // new company reaches this page before anyone has opened Setup. Create
      // the profile with its defaults rather than sending the owner away to a
      // form they have nothing to say to yet.
      const profile = await getProfile().catch(() => null)
      if (!profile) await setupProfile({})

      const updated = await applyBusinessTemplate({
        businessTemplate: choice.businessTemplate,
        industryTemplate: choice.industryTemplate,
      })
      // The apply endpoint returns the module settings it just set, so step 2
      // opens showing what the template chose rather than what was there before.
      setSettings(updated ?? (await getModuleSettings()))
      setStep(2)
    } catch (e: any) {
      toast({
        title: "Could not set up this business type",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setApplying(false)
    }
  }

  const onSaveModules = async () => {
    if (!settings) return
    setSaving(true)
    try {
      const { farmId, ...rest } = settings
      await saveModuleSettings(rest)
      // The nav caches these, so drop the cache or the new menus only appear
      // after a reload.
      invalidateGenericModules(activeFarmId ?? undefined)
      setStep(3)
    } catch (e: any) {
      toast({
        title: "Could not save what is switched on",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  const toggle = (key: keyof GenericModuleSettings) =>
    setSettings((s) => (s ? { ...s, [key]: !s[key] } : s))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="max-w-3xl mx-auto space-y-4">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Sparkles className="h-6 w-6 text-indigo-600" /> Set up your business
              </h1>
              <p className="text-sm text-slate-500">Step {step} of 3</p>
            </div>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading…
              </div>
            ) : step === 1 ? (
              <Card>
                <CardHeader>
                  <CardTitle>What kind of business is this?</CardTitle>
                  <CardDescription>
                    This decides what things are called and what you start with — income
                    categories, cash accounts and a few plans. You can change any of it later.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="grid gap-2 sm:grid-cols-2">
                    {CHOICES.map((c) => {
                      const picked = choice?.id === c.id
                      return (
                        <button
                          key={c.id}
                          type="button"
                          onClick={() => setChoice(c)}
                          className={`text-left rounded-lg border p-3 transition ${
                            picked
                              ? "border-indigo-500 bg-indigo-50 ring-1 ring-indigo-500"
                              : "border-slate-200 bg-white hover:border-slate-300"
                          }`}
                        >
                          <div className="flex items-center justify-between gap-2">
                            <span className="font-medium text-slate-900">{c.label}</span>
                            {picked && <Check className="h-4 w-4 text-indigo-600 shrink-0" />}
                          </div>
                          <p className="text-sm text-slate-500 mt-0.5">{c.description}</p>
                        </button>
                      )
                    })}
                  </div>

                  {choice && (
                    <div className="rounded-md bg-slate-100 p-3 text-sm text-slate-700">
                      You&apos;ll see <strong>{labels.customerPlural}</strong>,{" "}
                      <strong>{labels.planPlural}</strong>, <strong>{labels.subscriptionPlural}</strong>{" "}
                      and <strong>{labels.invoicePlural}</strong>.
                    </div>
                  )}

                  <div className="flex justify-end">
                    <Button onClick={onApply} disabled={!choice || applying}>
                      {applying ? (
                        <>
                          <Loader2 className="h-4 w-4 mr-1 animate-spin" /> Setting up…
                        </>
                      ) : (
                        <>
                          Continue <ArrowRight className="h-4 w-4 ml-1" />
                        </>
                      )}
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : step === 2 ? (
              <Card>
                <CardHeader>
                  <CardTitle>What do you want to see?</CardTitle>
                  <CardDescription>
                    These are the menus this company shows. Turning something off only hides it —
                    nothing already recorded is deleted or lost.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="divide-y">
                    {MODULE_ROWS.map((m) => (
                      <div key={m.key} className="flex items-center justify-between gap-4 py-3">
                        <div>
                          <Label htmlFor={m.key} className="text-slate-900 cursor-pointer">
                            {m.label}
                          </Label>
                          <p className="text-sm text-slate-500">{m.hint}</p>
                        </div>
                        <Switch
                          id={m.key}
                          checked={Boolean(settings?.[m.key])}
                          onCheckedChange={() => toggle(m.key)}
                        />
                      </div>
                    ))}
                  </div>

                  <div className="flex justify-between">
                    <Button variant="ghost" onClick={() => setStep(1)}>
                      <ArrowLeft className="h-4 w-4 mr-1" /> Back
                    </Button>
                    <Button onClick={onSaveModules} disabled={saving}>
                      {saving ? (
                        <>
                          <Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…
                        </>
                      ) : (
                        <>
                          Continue <ArrowRight className="h-4 w-4 ml-1" />
                        </>
                      )}
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : (
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <Check className="h-5 w-5 text-emerald-600" /> Ready
                  </CardTitle>
                  <CardDescription>
                    {choice?.label} set up. Here is the order things usually happen in.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-3">
                  <ol className="space-y-2 text-sm">
                    <li className="flex items-start gap-2">
                      <Badge variant="outline" className="mt-0.5">1</Badge>
                      <span>
                        Check your <strong>{labels.planPlural}</strong> — a few starter ones are
                        already there. Set the price and how often they bill.
                      </span>
                    </li>
                    <li className="flex items-start gap-2">
                      <Badge variant="outline" className="mt-0.5">2</Badge>
                      <span>
                        Add your <strong>{labels.customerPlural}</strong>.
                      </span>
                    </li>
                    <li className="flex items-start gap-2">
                      <Badge variant="outline" className="mt-0.5">3</Badge>
                      <span>
                        Put each one on a plan — that is a{" "}
                        <strong>{labels.subscription.toLowerCase()}</strong>.
                      </span>
                    </li>
                    <li className="flex items-start gap-2">
                      <Badge variant="outline" className="mt-0.5">4</Badge>
                      <span>
                        When the period comes round, open <strong>Billing runs</strong> and raise
                        the {labels.invoicePlural.toLowerCase()}. Nothing bills on its own — you
                        press the button.
                      </span>
                    </li>
                    <li className="flex items-start gap-2">
                      <Badge variant="outline" className="mt-0.5">5</Badge>
                      <span>
                        Take payment on <strong>{labels.customerBalance}</strong>. One payment can
                        settle several {labels.invoicePlural.toLowerCase()} at once.
                      </span>
                    </li>
                  </ol>

                  <div className="flex flex-wrap gap-2 pt-2">
                    <Button onClick={() => router.push("/generic-service-plans")}>
                      Go to {labels.planPlural}
                    </Button>
                    <Button variant="outline" onClick={() => router.push("/generic-customers")}>
                      Add {labels.customerPlural.toLowerCase()}
                    </Button>
                    <Button variant="ghost" onClick={() => router.push("/generic-dashboard")}>
                      Skip to dashboard
                    </Button>
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

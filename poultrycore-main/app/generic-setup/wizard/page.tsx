"use client"

// Setup wizard — the guided onboarding flow a new business walks through.
//
// A NEW route, not a rewrite of /generic-setup. That page is how every existing
// Generic company edits its profile, and it has to keep working exactly as it
// does. This one runs once, after the company is created.
//
// Step 0: Welcome — explains what the system will do.
// Step 1: Pick business type — searchable grid with 25+ options.
// Step 2: Done — handover with first-action links.
//
// The wizard no longer asks the customer to choose or confirm individual
// features. VisibilityCore automatically applies the recommended feature
// configuration for the selected Business Template. Customers can customise
// features later through Setup → Business Features.
//
// Applying a template only ever inserts, and every insert is guarded, so
// running the wizard twice is safe: the owner gets any new seeds and keeps
// everything they have already edited.

import { Suspense, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import {
  Loader2, Check, ArrowRight, ArrowLeft, Sparkles, Search,
  ShoppingBag, Scissors, CalendarClock, LayoutGrid,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  applyBusinessTemplate, getModuleSettings, saveModuleSettings, getBusinessTemplate,
  type GenericModuleSettings,
} from "@/lib/api/generic-subscriptions"
import {
  BUSINESS_TYPES, type BusinessType, type BusinessCategory,
} from "@/lib/companies/business-types"
import { getProfile, setupProfile } from "@/lib/api/generic"
import { invalidateGenericModules } from "@/hooks/use-generic-modules"
import { templateLabels } from "@/lib/generic/template-labels"

// Only the Generic-based types are choices here
const CHOICES: BusinessType[] = BUSINESS_TYPES.filter((t) => t.companyType === "Generic")

const CATEGORY_META: { id: BusinessCategory; label: string; icon: React.ReactNode }[] = [
  { id: "retail", label: "Shops & retail", icon: <ShoppingBag className="h-4 w-4" /> },
  { id: "service", label: "Services", icon: <Scissors className="h-4 w-4" /> },
  { id: "subscription", label: "Subscription & billing", icon: <CalendarClock className="h-4 w-4" /> },
  { id: "other", label: "Other", icon: <LayoutGrid className="h-4 w-4" /> },
]

const TOTAL_STEPS = 3 // 0=welcome, 1=type, 2=done

function GenericSetupWizardContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const logout = useLogout()
  const { toast } = useToast()

  const [step, setStep] = useState(0) // Start at welcome
  const [choice, setChoice] = useState<BusinessType | null>(null)
  const [loading, setLoading] = useState(true)
  const [applying, setApplying] = useState(false)
  const [search, setSearch] = useState("")
  const [categoryFilter, setCategoryFilter] = useState<BusinessCategory | "all">("all")

  const labels = templateLabels(choice?.industryTemplate)

  // Filter choices by search and category
  const filtered = useMemo(() => {
    let items = CHOICES
    if (categoryFilter !== "all") {
      items = items.filter((c) => c.category === categoryFilter)
    }
    if (search.trim()) {
      const q = search.trim().toLowerCase()
      items = items.filter(
        (c) =>
          c.label.toLowerCase().includes(q) ||
          c.description.toLowerCase().includes(q)
      )
    }
    return items
  }, [search, categoryFilter])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }

    // When an industry param is present (from company creation), auto-apply
    // the template and go straight to the dashboard — no wizard needed.
    const industryParam = searchParams.get("industry")

    getBusinessTemplate().catch(() => null)
      .then(async (template) => {
        // Already templated → skip to dashboard
        if (template?.genericIndustryTemplate) {
          router.replace("/generic-dashboard")
          return
        }

        // Industry param from company creation → auto-apply and go to dashboard
        if (industryParam) {
          const match = CHOICES.find((c) => c.industryTemplate === industryParam)
          if (match?.businessTemplate && match?.industryTemplate) {
            try {
              const profile = await getProfile().catch(() => null)
              if (!profile) await setupProfile({})
              await applyBusinessTemplate({
                businessTemplate: match.businessTemplate,
                industryTemplate: match.industryTemplate,
              })
              invalidateGenericModules(activeFarmId ?? undefined)
            } catch {}
            router.replace("/generic-dashboard")
            return
          }
        }

        // No param → show wizard normally
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }, [activeFarmType, activeFarmId, router, searchParams])

  // Apply template and auto-configure — no manual feature selection needed
  const onApply = async () => {
    if (!choice?.businessTemplate || !choice?.industryTemplate) return
    setApplying(true)
    try {
      const profile = await getProfile().catch(() => null)
      if (!profile) await setupProfile({})

      await applyBusinessTemplate({
        businessTemplate: choice.businessTemplate,
        industryTemplate: choice.industryTemplate,
      })

      invalidateGenericModules(activeFarmId ?? undefined)

      toast({
        title: `Set up as ${choice.label}`,
        description: "Your workspace is ready with the recommended features enabled.",
      })

      setStep(2) // Go straight to done
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

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="max-w-3xl mx-auto space-y-4">
            {/* Header */}
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Sparkles className="h-6 w-6 text-indigo-600" /> Set up your business
              </h1>
              {step === 1 && (
                <p className="text-sm text-slate-500">
                  Step 1 of {TOTAL_STEPS - 1}
                </p>
              )}
            </div>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading…
              </div>
            ) : step === 0 ? (
              /* ============================================================
                 STEP 0: WELCOME
                 ============================================================ */
              <Card>
                <CardHeader className="text-center pb-2">
                  <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-indigo-100">
                    <Sparkles className="h-8 w-8 text-indigo-600" />
                  </div>
                  <CardTitle className="text-xl">Welcome to VisibilityCore</CardTitle>
                  <CardDescription className="text-base mt-2">
                    Tell us what kind of business you run and we&apos;ll configure
                    everything — menus, categories, cash accounts and reports — so
                    it feels like it was built just for you.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="rounded-lg bg-slate-50 p-4 space-y-2">
                    <p className="text-sm text-slate-600">Here&apos;s what happens next:</p>
                    <ul className="text-sm text-slate-600 space-y-1">
                      <li className="flex items-start gap-2">
                        <Badge variant="outline" className="mt-0.5 shrink-0">1</Badge>
                        <span>Choose your business type</span>
                      </li>
                      <li className="flex items-start gap-2">
                        <Badge variant="outline" className="mt-0.5 shrink-0">2</Badge>
                        <span>We automatically set up the recommended features</span>
                      </li>
                      <li className="flex items-start gap-2">
                        <Badge variant="outline" className="mt-0.5 shrink-0">3</Badge>
                        <span>Start using your system</span>
                      </li>
                    </ul>
                  </div>

                  <div className="rounded-lg border border-indigo-200 bg-indigo-50 p-4">
                    <p className="text-sm text-indigo-700">
                      VisibilityCore will automatically include the recommended features
                      for your business type. You can customise them anytime in{" "}
                      <strong>Setup → Business Features</strong>.
                    </p>
                  </div>

                  <div className="flex justify-center pt-2">
                    <Button size="lg" onClick={() => setStep(1)}>
                      Get started <ArrowRight className="h-4 w-4 ml-1" />
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : step === 1 ? (
              /* ============================================================
                 STEP 1: CHOOSE BUSINESS TYPE (searchable)
                 ============================================================ */
              <Card>
                <CardHeader>
                  <CardTitle>What kind of business is this?</CardTitle>
                  <CardDescription>
                    Pick the option closest to your business. We&apos;ll automatically
                    set up the right menus, categories and features for you.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  {/* Search */}
                  <div className="relative">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                    <Input
                      placeholder="Search business types…"
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                      className="pl-9"
                    />
                  </div>

                  {/* Category filter tabs */}
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() => setCategoryFilter("all")}
                      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium transition ${
                        categoryFilter === "all"
                          ? "bg-indigo-100 text-indigo-700"
                          : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                      }`}
                    >
                      All
                    </button>
                    {CATEGORY_META.map((cat) => (
                      <button
                        key={cat.id}
                        type="button"
                        onClick={() => setCategoryFilter(cat.id)}
                        className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium transition ${
                          categoryFilter === cat.id
                            ? "bg-indigo-100 text-indigo-700"
                            : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                        }`}
                      >
                        {cat.icon} {cat.label}
                      </button>
                    ))}
                  </div>

                  {/* Business type grid */}
                  {filtered.length === 0 ? (
                    <p className="text-sm text-slate-500 text-center py-8">
                      No business types match &ldquo;{search}&rdquo;.
                      Try a different search or pick &ldquo;Other business&rdquo;.
                    </p>
                  ) : (
                    <div className="grid gap-2 sm:grid-cols-2 max-h-[420px] overflow-y-auto pr-1">
                      {filtered.map((c) => {
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
                              <span className="font-medium text-slate-900 text-sm">{c.label}</span>
                              {picked && <Check className="h-4 w-4 text-indigo-600 shrink-0" />}
                            </div>
                            <p className="text-xs text-slate-500 mt-0.5">{c.description}</p>
                          </button>
                        )
                      })}
                    </div>
                  )}

                  {/* Reassuring message below the grid */}
                  {choice && (
                    <div className="rounded-lg border border-indigo-200 bg-indigo-50 p-3">
                      <p className="text-sm text-indigo-700">
                        Your business is ready to be set up. VisibilityCore will
                        automatically include the recommended features for{" "}
                        <strong>{choice.label}</strong>. You can customise them anytime.
                      </p>
                    </div>
                  )}

                  <div className="flex justify-between pt-2">
                    <Button variant="ghost" onClick={() => setStep(0)}>
                      <ArrowLeft className="h-4 w-4 mr-1" /> Back
                    </Button>
                    <Button onClick={onApply} disabled={!choice || applying}>
                      {applying ? (
                        <>
                          <Loader2 className="h-4 w-4 mr-1 animate-spin" /> Setting up…
                        </>
                      ) : (
                        <>
                          Create My Business <ArrowRight className="h-4 w-4 ml-1" />
                        </>
                      )}
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : (
              /* ============================================================
                 STEP 2: DONE
                 ============================================================ */
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <div className="flex h-8 w-8 items-center justify-center rounded-full bg-emerald-100">
                      <Check className="h-5 w-5 text-emerald-600" />
                    </div>
                    You&apos;re all set
                  </CardTitle>
                  <CardDescription>
                    Your <strong>{choice?.label}</strong> workspace is ready with
                    the recommended features already enabled.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-3">
                  <div className="rounded-lg bg-slate-50 p-4 space-y-2">
                    <p className="text-sm font-medium text-slate-700">
                      What we&apos;ve set up for you:
                    </p>
                    <ul className="text-sm text-slate-600 space-y-1 list-disc list-inside">
                      <li>Income and expense categories for your business</li>
                      <li>Cash accounts (cash box, mobile money, bank)</li>
                      {choice?.businessTemplate === "SubscriptionServiceBusiness" && (
                        <li>Starter {labels.planPlural.toLowerCase()} (you set the prices)</li>
                      )}
                      <li>Recommended features enabled in your menus</li>
                    </ul>
                    <p className="text-xs text-slate-500 mt-2">
                      You can customise which features are active anytime in{" "}
                      <strong>Setup → Business Features</strong>.
                    </p>
                  </div>

                  {choice?.businessTemplate === "SubscriptionServiceBusiness" ? (
                    // Subscription business next steps
                    <div>
                      <p className="text-sm font-medium text-slate-700 mb-2">
                        Here is the order things usually happen in:
                      </p>
                      <ol className="space-y-2 text-sm">
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">1</Badge>
                          <span>
                            Check your <strong>{labels.planPlural}</strong> — starter ones are
                            already there. Set the price and frequency.
                          </span>
                        </li>
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">2</Badge>
                          <span>Add your <strong>{labels.customerPlural}</strong>.</span>
                        </li>
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">3</Badge>
                          <span>
                            Put each one on a plan — that is a{" "}
                            <strong>{labels.subscription.toLowerCase()}</strong>.
                          </span>
                        </li>
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">4</Badge>
                          <span>
                            When the period comes round, open <strong>Billing runs</strong> and raise
                            the {labels.invoicePlural.toLowerCase()}.
                          </span>
                        </li>
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">5</Badge>
                          <span>
                            Take payment on <strong>{labels.customerBalance}</strong>.
                          </span>
                        </li>
                      </ol>
                    </div>
                  ) : (
                    // Retail / service business next steps
                    <div>
                      <p className="text-sm font-medium text-slate-700 mb-2">
                        Here is the order things usually happen in:
                      </p>
                      <ol className="space-y-2 text-sm">
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">1</Badge>
                          <span>Add your <strong>products or services</strong> with prices.</span>
                        </li>
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">2</Badge>
                          <span>Record your first <strong>sale</strong>.</span>
                        </li>
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">3</Badge>
                          <span>Add your <strong>suppliers</strong> and record a purchase.</span>
                        </li>
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">4</Badge>
                          <span>At the end of the day, do a <strong>daily closing</strong>.</span>
                        </li>
                        <li className="flex items-start gap-2">
                          <Badge variant="outline" className="mt-0.5 shrink-0">5</Badge>
                          <span>Check your <strong>reports</strong> to see how you are doing.</span>
                        </li>
                      </ol>
                    </div>
                  )}

                  <div className="flex flex-wrap gap-2 pt-2">
                    {choice?.businessTemplate === "SubscriptionServiceBusiness" ? (
                      <>
                        <Button onClick={() => router.push("/generic-service-plans")}>
                          Go to {labels.planPlural}
                        </Button>
                        <Button variant="outline" onClick={() => router.push("/generic-customers")}>
                          Add {labels.customerPlural.toLowerCase()}
                        </Button>
                      </>
                    ) : (
                      <>
                        <Button onClick={() => router.push("/generic-products")}>
                          Add products
                        </Button>
                        <Button variant="outline" onClick={() => router.push("/generic-sales")}>
                          Record a sale
                        </Button>
                      </>
                    )}
                    <Button variant="ghost" onClick={() => router.push("/generic-dashboard")}>
                      Go to dashboard
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

export default function GenericSetupWizardPage() {
  return (
    <Suspense fallback={null}>
      <GenericSetupWizardContent />
    </Suspense>
  )
}

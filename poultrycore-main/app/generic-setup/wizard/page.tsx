"use client"

// Setup wizard — the guided onboarding flow a new business walks through.
//
// A NEW route, not a rewrite of /generic-setup. That page is how every existing
// Generic company edits its profile, and it has to keep working exactly as it
// does. This one runs once, after the company is created.
//
// Step 0: Welcome — explains what the system will do.
// Step 1: Pick business type — searchable grid with 25+ options.
// Step 2: Confirm modules — the toggles the template set, adjustable.
// Step 3: Review — summary of what will be configured, confirm before applying.
// Step 4: Done — handover with first-action links.
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
import { Switch } from "@/components/ui/switch"
import { Label } from "@/components/ui/label"
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
  { key: "enableRecurringExpenses", label: "Recurring expenses", hint: "Rent, utilities and other regular costs" },
  { key: "enableSupplierBalances", label: "Supplier balances", hint: "What you owe your suppliers" },
]

// ---------------------------------------------------------------------------
// Conditional onboarding questions — asked between business type selection
// and module configuration. Questions are filtered by business category so
// a yam seller doesn't see subscription questions and a school doesn't see
// barcode questions.
// ---------------------------------------------------------------------------
interface OnboardingQuestion {
  id: string
  question: string
  hint: string
  /** Which business categories see this question. Empty = all. */
  showFor: BusinessCategory[]
  /** Which business categories NEVER see this (overrides showFor). */
  hideFor?: BusinessCategory[]
  /** Module toggles to turn ON when answered "yes". */
  enables: (keyof GenericModuleSettings)[]
  /** Module toggles to turn OFF when answered "no". */
  disablesOnNo?: (keyof GenericModuleSettings)[]
}

const ONBOARDING_QUESTIONS: OnboardingQuestion[] = [
  {
    id: "sells-products",
    question: "Do you sell physical products?",
    hint: "Items you buy or make and sell to customers",
    showFor: ["service", "other"],
    enables: ["enableProducts", "enableInventory", "enablePurchases"],
    disablesOnNo: ["enableProducts", "enableInventory", "enableStockAdjustments", "enableInternalUse", "enablePurchases"],
  },
  {
    id: "tracks-stock",
    question: "Do you need to track stock levels?",
    hint: "Know exactly how much of each item you have",
    showFor: ["retail"],
    enables: ["enableInventory", "enableStockAdjustments"],
    disablesOnNo: ["enableInventory", "enableStockAdjustments", "enableInternalUse"],
  },
  {
    id: "customer-credit",
    question: "Do customers sometimes pay later?",
    hint: "You give goods or services now, they pay over time",
    showFor: ["retail", "service", "other"],
    enables: ["enableCustomerBalances", "enableInvoices"],
    disablesOnNo: ["enableCustomerBalances"],
  },
  {
    id: "recurring-billing",
    question: "Do you bill customers on a regular schedule?",
    hint: "Monthly fees, term fees, memberships or subscriptions",
    showFor: ["service", "other"],
    enables: ["enableSubscriptions", "enableInvoices", "enableCustomerBalances"],
    disablesOnNo: ["enableSubscriptions"],
  },
  {
    id: "has-staff",
    question: "Do you have staff to pay?",
    hint: "Employees, contractors or commission-based workers",
    showFor: ["retail", "service", "subscription", "other"],
    enables: ["enableStaffPayments"],
    disablesOnNo: ["enableStaffPayments"],
  },
]

const TOTAL_STEPS = 6 // 0=welcome, 1=type, 2=questions, 3=modules, 4=review, 5=done

function GenericSetupWizardContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const logout = useLogout()
  const { toast } = useToast()

  const [step, setStep] = useState(0) // Start at welcome
  const [choice, setChoice] = useState<BusinessType | null>(null)
  const [settings, setSettings] = useState<GenericModuleSettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [applying, setApplying] = useState(false)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState("")
  const [categoryFilter, setCategoryFilter] = useState<BusinessCategory | "all">("all")
  const [answers, setAnswers] = useState<Record<string, boolean>>({})

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
    // Pre-select whatever this company is already on
    Promise.all([getBusinessTemplate().catch(() => null), getModuleSettings().catch(() => null)])
      .then(([template, s]) => {
        const existing = template?.genericIndustryTemplate ?? searchParams.get("industry")
        if (existing) {
          setChoice(CHOICES.find((c) => c.industryTemplate === existing) ?? null)
          // If already templated, skip the welcome
          if (template?.genericIndustryTemplate) setStep(1)
        }
        if (s) setSettings(s)
      })
      .finally(() => setLoading(false))
  }, [activeFarmType, router, searchParams])

  const onApply = async () => {
    if (!choice?.businessTemplate || !choice?.industryTemplate) return
    setApplying(true)
    try {
      const profile = await getProfile().catch(() => null)
      if (!profile) await setupProfile({})

      const updated = await applyBusinessTemplate({
        businessTemplate: choice.businessTemplate,
        industryTemplate: choice.industryTemplate,
      })
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

  // Questions filtered for the current business category
  const visibleQuestions = useMemo(() => {
    const cat = choice?.category
    if (!cat) return []
    return ONBOARDING_QUESTIONS.filter((q) => {
      if (q.hideFor?.includes(cat)) return false
      return q.showFor.length === 0 || q.showFor.includes(cat)
    })
  }, [choice])

  // Apply question answers to module settings
  const applyAnswersToSettings = () => {
    if (!settings) return
    const updated = { ...settings }
    for (const q of visibleQuestions) {
      const answered = answers[q.id]
      if (answered === true) {
        for (const key of q.enables) {
          ;(updated as any)[key] = true
        }
      } else if (answered === false && q.disablesOnNo) {
        for (const key of q.disablesOnNo) {
          ;(updated as any)[key] = false
        }
      }
    }
    setSettings(updated)
  }

  const onFinishQuestions = () => {
    applyAnswersToSettings()
    setStep(3) // Go to module toggles
  }

  const onSaveModules = async () => {
    if (!settings) return
    setSaving(true)
    try {
      const { farmId, ...rest } = settings
      await saveModuleSettings(rest)
      invalidateGenericModules(activeFarmId ?? undefined)
      setStep(5) // Go to done
    } catch (e: any) {
      toast({
        title: "Could not save settings",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  const toggle = (key: keyof GenericModuleSettings) =>
    setSettings((s) => (s ? { ...s, [key]: !s[key] } : s))

  // Count enabled modules for review
  const enabledModules = settings
    ? MODULE_ROWS.filter((m) => Boolean(settings[m.key]))
    : []

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
              {step > 0 && step < TOTAL_STEPS - 1 && (
                <p className="text-sm text-slate-500">
                  Step {step} of {TOTAL_STEPS - 2}
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
                    We&apos;ll set up your workspace in a few quick steps. Tell us what kind
                    of business you run, and we&apos;ll configure everything — menus, categories,
                    cash accounts and reports — so it feels like it was built just for you.
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
                        <span>Adjust which features you need</span>
                      </li>
                      <li className="flex items-start gap-2">
                        <Badge variant="outline" className="mt-0.5 shrink-0">3</Badge>
                        <span>Review and confirm</span>
                      </li>
                      <li className="flex items-start gap-2">
                        <Badge variant="outline" className="mt-0.5 shrink-0">4</Badge>
                        <span>Start using your system</span>
                      </li>
                    </ul>
                  </div>

                  <p className="text-sm text-slate-500">
                    Everything can be changed later in Settings. Nothing is permanent.
                  </p>

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
                    Pick the option closest to your business. This decides what things are called
                    and what you start with. You can change it later.
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
                          Continue <ArrowRight className="h-4 w-4 ml-1" />
                        </>
                      )}
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : step === 2 ? (
              /* ============================================================
                 STEP 2: QUICK QUESTIONS (conditional)
                 ============================================================ */
              <Card>
                <CardHeader>
                  <CardTitle>A few quick questions</CardTitle>
                  <CardDescription>
                    This helps us turn on the right features for your{" "}
                    <strong>{choice?.label?.toLowerCase()}</strong>. You can always change
                    these later in Settings.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  {visibleQuestions.length === 0 ? (
                    <p className="text-sm text-slate-500">
                      No additional questions for this business type. Your defaults are ready.
                    </p>
                  ) : (
                    <div className="space-y-3">
                      {visibleQuestions.map((q) => (
                        <div key={q.id} className="rounded-lg border p-4">
                          <p className="font-medium text-slate-900 text-sm">{q.question}</p>
                          <p className="text-xs text-slate-500 mt-0.5 mb-3">{q.hint}</p>
                          <div className="flex gap-2">
                            <button
                              type="button"
                              onClick={() => setAnswers((a) => ({ ...a, [q.id]: true }))}
                              className={`rounded-md px-4 py-1.5 text-sm font-medium transition ${
                                answers[q.id] === true
                                  ? "bg-indigo-600 text-white"
                                  : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                              }`}
                            >
                              Yes
                            </button>
                            <button
                              type="button"
                              onClick={() => setAnswers((a) => ({ ...a, [q.id]: false }))}
                              className={`rounded-md px-4 py-1.5 text-sm font-medium transition ${
                                answers[q.id] === false
                                  ? "bg-slate-700 text-white"
                                  : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                              }`}
                            >
                              No
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}

                  <div className="flex justify-between pt-2">
                    <Button variant="ghost" onClick={() => setStep(1)}>
                      <ArrowLeft className="h-4 w-4 mr-1" /> Back
                    </Button>
                    <Button onClick={onFinishQuestions}>
                      Continue <ArrowRight className="h-4 w-4 ml-1" />
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : step === 3 ? (
              /* ============================================================
                 STEP 3: CONFIGURE MODULES (fine-tune)
                 ============================================================ */
              <Card>
                <CardHeader>
                  <CardTitle>Fine-tune your features</CardTitle>
                  <CardDescription>
                    We&apos;ve set these based on your answers. Adjust anything that
                    doesn&apos;t look right — turning something off only hides it.
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
                    <Button variant="ghost" onClick={() => setStep(2)}>
                      <ArrowLeft className="h-4 w-4 mr-1" /> Back
                    </Button>
                    <Button onClick={() => setStep(4)}>
                      Review <ArrowRight className="h-4 w-4 ml-1" />
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : step === 4 ? (
              /* ============================================================
                 STEP 4: REVIEW & CONFIRM
                 ============================================================ */
              <Card>
                <CardHeader>
                  <CardTitle>Review your setup</CardTitle>
                  <CardDescription>
                    Check that everything looks right before we configure your workspace.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  {/* Business type */}
                  <div className="rounded-lg border p-4 space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-medium text-slate-500">Business type</span>
                      <button
                        type="button"
                        onClick={() => setStep(1)}
                        className="text-xs text-indigo-600 hover:text-indigo-800"
                      >
                        Change
                      </button>
                    </div>
                    <p className="text-lg font-semibold text-slate-900">{choice?.label}</p>
                    <p className="text-sm text-slate-500">{choice?.description}</p>
                  </div>

                  {/* Enabled modules */}
                  <div className="rounded-lg border p-4 space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-medium text-slate-500">
                        Features enabled ({enabledModules.length} of {MODULE_ROWS.length})
                      </span>
                      <button
                        type="button"
                        onClick={() => setStep(3)}
                        className="text-xs text-indigo-600 hover:text-indigo-800"
                      >
                        Change
                      </button>
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      {enabledModules.map((m) => (
                        <Badge key={m.key} variant="secondary" className="text-xs">
                          {m.label}
                        </Badge>
                      ))}
                    </div>
                  </div>

                  {/* What gets created */}
                  <div className="rounded-lg bg-slate-50 p-4 space-y-2">
                    <p className="text-sm font-medium text-slate-700">
                      When you confirm, we&apos;ll create:
                    </p>
                    <ul className="text-sm text-slate-600 space-y-1 list-disc list-inside">
                      <li>Income and expense categories for your business</li>
                      <li>Cash accounts (cash box, mobile money, bank)</li>
                      {choice?.businessTemplate === "SubscriptionServiceBusiness" && (
                        <li>Starter {labels.planPlural.toLowerCase()} (you set the prices)</li>
                      )}
                      <li>Menu items matching your enabled features</li>
                    </ul>
                    <p className="text-xs text-slate-500 mt-2">
                      You can edit or add to any of these after setup.
                    </p>
                  </div>

                  <div className="flex justify-between pt-2">
                    <Button variant="ghost" onClick={() => setStep(3)}>
                      <ArrowLeft className="h-4 w-4 mr-1" /> Back
                    </Button>
                    <Button onClick={onSaveModules} disabled={saving}>
                      {saving ? (
                        <>
                          <Loader2 className="h-4 w-4 mr-1 animate-spin" /> Configuring…
                        </>
                      ) : (
                        <>
                          Confirm & finish <Check className="h-4 w-4 ml-1" />
                        </>
                      )}
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : (
              /* ============================================================
                 STEP 5: DONE
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
                    Your <strong>{choice?.label}</strong> workspace is ready.
                    Here is the order things usually happen in.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-3">
                  {choice?.businessTemplate === "SubscriptionServiceBusiness" ? (
                    // Subscription business next steps
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
                  ) : (
                    // Retail / service business next steps
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

"use client"

import { Suspense, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { PageHeader } from "@/components/ui/info-section"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Loader2 } from "lucide-react"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import {
  createFarmTierCheckoutSession,
  getSubscriptionTiers,
  tierForBirdCount,
  type SubscriptionTiersResponse,
} from "@/lib/api/payments"
import { getFlocks } from "@/lib/api/flock"
import { getProductionRecords } from "@/lib/api/production-record"
import { sumActiveFlocksBirdsLeft } from "@/lib/utils/production-records"
import { toastFormGuide } from "@/lib/utils/validation-toast"

/** Major units (e.g. 500 GHS) — matches Login API tier amounts. */
function formatTierAmount(currencyCode: string, amount: number): string {
  const code = (currencyCode || "ghs").trim().toUpperCase()
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: code.length === 3 ? code : "GHS",
      maximumFractionDigits: 0,
    }).format(amount)
  } catch {
    return `${amount.toLocaleString()} ${code}`
  }
}

function cleanApiError(message?: string): string {
  if (!message) return "Could not start Paystack checkout."
  // Backend sometimes returns full HTML for 404/400 pages; show a user-friendly message.
  if (message.includes("<html") || message.includes("<body")) {
    return (
      "Payment API returned a web page instead of JSON. Usually: (1) NEXT_PUBLIC_ADMIN_API_URL / ADMIN_API_URL points at this website instead of the Login API host, or " +
      "(2) the deployed Login API is an old build without GET /api/Payments/subscription-tiers. Fix env on Cloud Run/Vercel, then redeploy User.Management.API from the repo that includes Paystack routes."
    )
  }
  return message
}

function PaymentsPageInner() {
  // Temporary business override while onboarding/whitelist is active.
  const TEMP_OPEN_PAYMENTS_ACCESS = true
  const TEMP_ALLOW_ALL_TO_START_CHECKOUT = true

  const router = useRouter()
  const searchParams = useSearchParams()
  const permissions = usePermissions()
  const { toast } = useToast()

  const [tiersInfo, setTiersInfo] = useState<SubscriptionTiersResponse | null>(null)
  const [tiersError, setTiersError] = useState("")
  const [totalBirds, setTotalBirds] = useState<number | null>(null)
  const [farmCheckoutLoading, setFarmCheckoutLoading] = useState(false)
  const [checkoutError, setCheckoutError] = useState("")

  const appliedTier = useMemo(() => {
    if (totalBirds === null || !tiersInfo?.tiers?.length) return null
    return tierForBirdCount(totalBirds, tiersInfo.tiers)
  }, [totalBirds, tiersInfo])

  const baseUrl =
    typeof window !== "undefined" ? `${window.location.origin}/payments` : "/payments"

  const canAccessPayments =
    TEMP_OPEN_PAYMENTS_ACCESS || permissions.isAdmin || permissions.featureAccess.canViewFinancial
  const canStartCheckout = TEMP_ALLOW_ALL_TO_START_CHECKOUT || permissions.isAdmin

  useEffect(() => {
    if (permissions.isLoading) return
    if (!canAccessPayments) {
      router.push("/dashboard")
      return
    }
  }, [canAccessPayments, permissions.isLoading, router])

  useEffect(() => {
    if (permissions.isLoading || !canAccessPayments) return
    let cancelled = false
    ;(async () => {
      const t = await getSubscriptionTiers()
      if (cancelled) return
      if (t.success && t.data) setTiersInfo(t.data)
      else setTiersError(cleanApiError(t.message) || "Could not load farm subscription tiers")
    })()
    return () => {
      cancelled = true
    }
  }, [canAccessPayments, permissions.isLoading])

  useEffect(() => {
    if (permissions.isLoading || !canAccessPayments) return
    const userId = typeof window !== "undefined" ? localStorage.getItem("userId") : null
    const farmId = typeof window !== "undefined" ? localStorage.getItem("farmId") : null
    if (!userId || !farmId) {
      setTotalBirds(0)
      return
    }
    let cancelled = false
    ;(async () => {
      const [flocksRes, productionRes] = await Promise.all([
        getFlocks(userId, farmId),
        getProductionRecords(userId, farmId),
      ])
      if (cancelled) return
      if (!flocksRes.success || !flocksRes.data) {
        setTotalBirds(0)
        return
      }

      const records =
        productionRes.success && productionRes.data?.length ? productionRes.data : []
      setTotalBirds(sumActiveFlocksBirdsLeft(flocksRes.data, records))
    })()
    return () => {
      cancelled = true
    }
  }, [canAccessPayments, permissions.isLoading])

  useEffect(() => {
    const status = searchParams.get("checkout")
    if (status === "success") {
      toast({ title: "Checkout completed", description: "Thank you. Your subscription will update shortly." })
    } else if (status === "cancel") {
      toast({ title: "Checkout cancelled", description: "No changes were made." })
    }
  }, [searchParams, toast])

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  const startFarmTierCheckout = async () => {
    if (totalBirds === null) {
      toastFormGuide(toast, "We are still loading your flock list. Wait a second and try again.", "One moment")
      return
    }
    setFarmCheckoutLoading(true)
    setCheckoutError("")
    try {
      const result = await createFarmTierCheckoutSession(
        totalBirds,
        `${baseUrl}?checkout=success`,
        `${baseUrl}?checkout=cancel`
      )
      if (!result.success || !result.data) {
        const msg = cleanApiError(result.message)
        setCheckoutError(msg)
        toast({
          variant: "destructive",
          title: "Checkout failed",
          description: msg,
        })
        return
      }
      if (!result.data.checkoutUrl) {
        toast({ variant: "destructive", title: "Paystack error", description: "Missing checkout URL." })
        return
      }
      window.location.href = result.data.checkoutUrl
    } finally {
      setFarmCheckoutLoading(false)
    }
  }

  if (permissions.isLoading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={handleLogout} />
        <div className="flex-1 flex flex-col">
          <DashboardHeader />
          <main className="overflow-y-visible p-6 flex items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
          </main>
        </div>
      </div>
    )
  }

  if (!canAccessPayments) return null

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4">
          <div className="space-y-6 w-full max-w-6xl mx-auto">
            <PageHeader
              title="Subscription & billing"
              subtitle={
                permissions.isAdmin
                  ? "Paystack subscription checkout. Tier is based on birds left across active flocks."
                  : "View-only access. Subscription checkout is limited to administrators."
              }
            />

            {!permissions.isAdmin && permissions.featureAccess.canViewFinancial && (
              <Alert>
                <AlertDescription>
                  You have <strong>view</strong> access to payments and billing. Starting a new subscription or using a
                  custom price ID is restricted to farm administrators.
                </AlertDescription>
              </Alert>
            )}
            {searchParams.get("subscription") === "required" && (
              <Alert variant="destructive">
                <AlertDescription>
                  Subscription required. Contact admin or renew plan.
                </AlertDescription>
              </Alert>
            )}
            {checkoutError && (
              <Alert variant="destructive">
                <AlertDescription>{checkoutError}</AlertDescription>
              </Alert>
            )}

            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Farm subscription (trial + tier by birds)</CardTitle>
                <CardDescription>
                  {tiersInfo?.note ??
                    "After a free trial, you are billed monthly. Tier is based on birds left across active flocks."}
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-5">
                {tiersError && (
                  <Alert variant="destructive">
                    <AlertDescription>{tiersError}</AlertDescription>
                  </Alert>
                )}
                {tiersInfo && (
                  <div className="space-y-5">
                    <div className="text-center space-y-1">
                      <p className="text-xl font-semibold tracking-tight text-slate-900">Upgrade your plan</p>
                      <p className="text-sm text-slate-600">
                        {tiersInfo.trialDays}-day free trial, then billed monthly
                      </p>
                    </div>
                    <div className="grid gap-4 md:grid-cols-3">
                      {tiersInfo.tiers.map((t) => {
                        const isCurrent = appliedTier?.id === t.id && totalBirds !== null
                        const isPopular = t.id === "tier2"
                        return (
                          <div
                            key={t.id}
                            className={`rounded-xl border p-4 transition-colors ${
                              isCurrent
                                ? "border-indigo-300 bg-indigo-50/70 shadow-sm"
                                : "border-slate-200 bg-white shadow-sm"
                            }`}
                          >
                            <div className="flex items-start justify-between gap-2 min-h-[24px]">
                              <div className="flex flex-wrap gap-1.5">
                                {isPopular ? (
                                  <span className="rounded-full bg-violet-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-violet-700">
                                    Popular
                                  </span>
                                ) : null}
                                {isCurrent ? (
                                  <span className="rounded-full bg-indigo-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-indigo-700">
                                    Current
                                  </span>
                                ) : null}
                              </div>
                            </div>
                            <p className="mt-2 text-sm font-semibold text-slate-900">{t.label}</p>
                            <p className="mt-3 text-3xl font-bold text-slate-900 leading-none">
                              {formatTierAmount(tiersInfo.currency, t.monthlyAmount)}
                            </p>
                            <p className="mt-2 text-xs text-slate-500">per month after trial</p>
                          </div>
                        )
                      })}
                    </div>
                  </div>
                )}
                {appliedTier && totalBirds !== null && tiersInfo && (
                  <p className="text-sm rounded-md bg-slate-100 border border-slate-200 px-3 py-2 text-slate-800">
                    At <strong>{totalBirds.toLocaleString()}</strong> birds left (active flocks), checkout uses{" "}
                    <strong>{appliedTier.label}</strong> —{" "}
                    <strong>{formatTierAmount(tiersInfo.currency, appliedTier.monthlyAmount)}</strong>/mo after the{" "}
                    {tiersInfo.trialDays}-day trial.
                  </p>
                )}
                <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 rounded-2xl border border-slate-200 bg-slate-50 px-5 py-5">
                  <div>
                    <p className="text-sm font-medium text-slate-900">Your farm (active flocks)</p>
                    <p className="text-sm text-slate-600">
                      {totalBirds === null ? (
                        <span className="inline-flex items-center gap-2">
                          <Loader2 className="h-4 w-4 animate-spin" /> Calculating birds…
                        </span>
                      ) : (
                        <>
                          <strong>{totalBirds.toLocaleString()}</strong> birds total. Your monthly price is based on
                          this count after your free trial.
                        </>
                      )}
                    </p>
                  </div>
                  {canStartCheckout ? (
                    <Button
                      type="button"
                      onClick={startFarmTierCheckout}
                      disabled={farmCheckoutLoading || totalBirds === null}
                      className="shrink-0 bg-indigo-600 hover:bg-indigo-700 text-white"
                    >
                      {farmCheckoutLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : "Start subscription (Paystack)"}
                    </Button>
                  ) : (
                    <span className="text-xs text-slate-500 self-center">Admins only</span>
                  )}
                </div>
              </CardContent>
            </Card>

          </div>
        </main>
      </div>
    </div>
  )
}

export default function PaymentsPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-slate-50">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      }
    >
      <PaymentsPageInner />
    </Suspense>
  )
}

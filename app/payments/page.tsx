"use client"

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { loadStripe } from "@stripe/stripe-js"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { PageHeader } from "@/components/ui/info-section"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Checkbox } from "@/components/ui/checkbox"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Loader2, CreditCard, ExternalLink } from "lucide-react"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import {
  getStripeProducts,
  createCheckoutSession,
  createFarmTierCheckoutSession,
  getSubscriptionTiers,
  openCustomerPortal,
  priceIdFromProduct,
  tierForBirdCount,
  type StripeProductLike,
  type SubscriptionTiersResponse,
} from "@/lib/api/payments"
import { getFlocks, type Flock } from "@/lib/api/flock"

function sumActiveBirds(flocks: Flock[]): number {
  return flocks.filter((f) => f.active).reduce((s, f) => s + (Number(f.quantity) || 0), 0)
}

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

function PaymentsPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const permissions = usePermissions()
  const { toast } = useToast()

  const [products, setProducts] = useState<StripeProductLike[]>([])
  const [loadError, setLoadError] = useState("")
  const [loadingProducts, setLoadingProducts] = useState(true)
  const [manualPriceId, setManualPriceId] = useState("")
  const [checkoutLoading, setCheckoutLoading] = useState<string | null>(null)
  const [portalLoading, setPortalLoading] = useState(false)
  const [tiersInfo, setTiersInfo] = useState<SubscriptionTiersResponse | null>(null)
  const [tiersError, setTiersError] = useState("")
  const [totalBirds, setTotalBirds] = useState<number | null>(null)
  const [farmCheckoutLoading, setFarmCheckoutLoading] = useState(false)
  const [includeTrialForPriceCheckout, setIncludeTrialForPriceCheckout] = useState(true)

  const appliedTier = useMemo(() => {
    if (totalBirds === null || !tiersInfo?.tiers?.length) return null
    return tierForBirdCount(totalBirds, tiersInfo.tiers)
  }, [totalBirds, tiersInfo])

  const baseUrl =
    typeof window !== "undefined" ? `${window.location.origin}/payments` : "/payments"

  const refreshProducts = useCallback(async () => {
    setLoadingProducts(true)
    setLoadError("")
    const result = await getStripeProducts()
    if (result.success && result.data) {
      setProducts(result.data)
    } else {
      setLoadError(result.message || "Could not load subscription plans")
    }
    setLoadingProducts(false)
  }, [])

  const canAccessPayments =
    permissions.isAdmin || permissions.featureAccess.canViewFinancial
  const canStartCheckout = permissions.isAdmin
  const canUseBillingPortal =
    permissions.isAdmin || permissions.featureAccess.canViewFinancial

  useEffect(() => {
    if (permissions.isLoading) return
    if (!canAccessPayments) {
      router.push("/dashboard")
      return
    }
    refreshProducts()
  }, [canAccessPayments, permissions.isLoading, router, refreshProducts])

  useEffect(() => {
    if (permissions.isLoading || !canAccessPayments) return
    let cancelled = false
    ;(async () => {
      const t = await getSubscriptionTiers()
      if (cancelled) return
      if (t.success && t.data) setTiersInfo(t.data)
      else setTiersError(t.message || "Could not load farm subscription tiers")
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
      const res = await getFlocks(userId, farmId)
      if (cancelled) return
      if (res.success && res.data) setTotalBirds(sumActiveBirds(res.data))
      else setTotalBirds(0)
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
      toast({ variant: "destructive", title: "Loading", description: "Still loading flock data. Try again in a moment." })
      return
    }
    setFarmCheckoutLoading(true)
    try {
      const result = await createFarmTierCheckoutSession(
        totalBirds,
        `${baseUrl}?checkout=success`,
        `${baseUrl}?checkout=cancel`
      )
      if (!result.success || !result.data) {
        toast({
          variant: "destructive",
          title: "Checkout failed",
          description: result.message || "Could not start Stripe Checkout.",
        })
        return
      }
      const stripe = await loadStripe(result.data.publicKey)
      if (!stripe) {
        toast({ variant: "destructive", title: "Stripe error", description: "Could not load Stripe." })
        return
      }
      const { error } = await stripe.redirectToCheckout({ sessionId: result.data.sessionId })
      if (error) {
        toast({ variant: "destructive", title: "Redirect failed", description: error.message })
      }
    } finally {
      setFarmCheckoutLoading(false)
    }
  }

  const startCheckout = async (priceId: string) => {
    if (!priceId.trim()) {
      toast({ variant: "destructive", title: "Missing price", description: "Select a plan or enter a Stripe price ID." })
      return
    }
    setCheckoutLoading(priceId)
    try {
      const result = await createCheckoutSession(
        priceId.trim(),
        `${baseUrl}?checkout=success`,
        `${baseUrl}?checkout=cancel`,
        { includeTrialWithPriceId: includeTrialForPriceCheckout }
      )
      if (!result.success || !result.data) {
        toast({
          variant: "destructive",
          title: "Checkout failed",
          description: result.message || "Could not start Stripe Checkout.",
        })
        return
      }
      const stripe = await loadStripe(result.data.publicKey)
      if (!stripe) {
        toast({ variant: "destructive", title: "Stripe error", description: "Could not load Stripe." })
        return
      }
      const { error } = await stripe.redirectToCheckout({ sessionId: result.data.sessionId })
      if (error) {
        toast({
          variant: "destructive",
          title: "Redirect failed",
          description: error.message,
        })
      }
    } finally {
      setCheckoutLoading(null)
    }
  }

  const handlePortal = async () => {
    setPortalLoading(true)
    try {
      const result = await openCustomerPortal(`${typeof window !== "undefined" ? window.location.origin : ""}/payments`)
      if (!result.success || !result.data) {
        toast({
          variant: "destructive",
          title: "Billing portal",
          description: result.message || "Could not open the billing portal.",
        })
        return
      }
      window.location.href = result.data
    } finally {
      setPortalLoading(false)
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
          <div className="space-y-6 max-w-3xl">
            <PageHeader
              title="Subscription & billing"
              subtitle={
                permissions.isAdmin
                  ? "Stripe plans and billing. Users with financial access can view plans and use the billing portal; only admins can start checkout."
                  : "View subscription plans and billing. New subscriptions and custom price checkout are limited to administrators."
              }
              action={
                <Button type="button" variant="outline" size="sm" onClick={refreshProducts} disabled={loadingProducts}>
                  {loadingProducts ? <Loader2 className="h-4 w-4 animate-spin" /> : "Refresh plans"}
                </Button>
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

            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Farm subscription (trial + tier by birds)</CardTitle>
                <CardDescription>
                  {tiersInfo?.note ??
                    "After a free trial, you are billed monthly. Tier is based on total birds across active flocks (sum of flock sizes)."}
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                {tiersError && (
                  <Alert variant="destructive">
                    <AlertDescription>{tiersError}</AlertDescription>
                  </Alert>
                )}
                {tiersInfo && (
                  <div className="rounded-lg border border-slate-200 bg-white p-4 text-sm space-y-2">
                    <p className="font-medium text-slate-900">
                      {tiersInfo.trialDays}-day free trial, then monthly ({String(tiersInfo.currency || "").toUpperCase() || "—"})
                    </p>
                    <ul className="list-disc list-inside text-slate-600 space-y-1">
                      {tiersInfo.tiers.map((t) => (
                        <li key={t.id}>
                          {t.label}:{" "}
                          <strong>
                            {formatTierAmount(tiersInfo.currency, t.monthlyAmount)}
                          </strong>
                          /mo
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
                {appliedTier && totalBirds !== null && tiersInfo && (
                  <p className="text-sm rounded-md bg-slate-100 border border-slate-200 px-3 py-2 text-slate-800">
                    At <strong>{totalBirds.toLocaleString()}</strong> birds, checkout uses{" "}
                    <strong>{appliedTier.label}</strong> —{" "}
                    <strong>{formatTierAmount(tiersInfo.currency, appliedTier.monthlyAmount)}</strong>/mo after the{" "}
                    {tiersInfo.trialDays}-day trial.
                  </p>
                )}
                <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                  <div>
                    <p className="text-sm font-medium text-slate-900">Your farm (active flocks)</p>
                    <p className="text-sm text-slate-600">
                      {totalBirds === null ? (
                        <span className="inline-flex items-center gap-2">
                          <Loader2 className="h-4 w-4 animate-spin" /> Calculating birds…
                        </span>
                      ) : (
                        <>
                          <strong>{totalBirds.toLocaleString()}</strong> birds total — sent as{" "}
                          <code className="text-xs bg-slate-100 px-1 rounded">totalBirds</code> to Login API checkout
                          (dynamic <code className="text-xs bg-slate-100 px-1 rounded">price_data</code> + trial).
                        </>
                      )}
                    </p>
                  </div>
                  {canStartCheckout ? (
                    <Button
                      type="button"
                      onClick={startFarmTierCheckout}
                      disabled={farmCheckoutLoading || totalBirds === null}
                      className="shrink-0"
                    >
                      {farmCheckoutLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : "Start subscription (Stripe)"}
                    </Button>
                  ) : (
                    <span className="text-xs text-slate-500 self-center">Admins only</span>
                  )}
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <CreditCard className="h-5 w-5" />
                  Customer billing portal
                </CardTitle>
                <CardDescription>
                  Update payment method, invoices, or cancel in Stripe. Requires a subscriber record on your account.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <Button
                  type="button"
                  onClick={handlePortal}
                  disabled={portalLoading || !canUseBillingPortal}
                  className="gap-2"
                >
                  {portalLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
                  Open billing portal
                </Button>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Plans</CardTitle>
                <CardDescription>
                  Stripe catalog from the Login API. Each checkout sends <code className="text-xs bg-slate-100 px-1 rounded">priceId</code>
                  {canStartCheckout ? ", optional trial, or a manual price ID below." : "."}
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                {canStartCheckout && (
                  <div className="flex items-center gap-2">
                    <Checkbox
                      id="trial-catalog"
                      checked={includeTrialForPriceCheckout}
                      onCheckedChange={(v) => setIncludeTrialForPriceCheckout(v === true)}
                    />
                    <Label htmlFor="trial-catalog" className="text-sm font-normal cursor-pointer">
                      Apply farm trial ({tiersInfo?.trialDays ?? "…"} days) when subscribing with a Stripe price ID
                    </Label>
                  </div>
                )}
                {loadingProducts && (
                  <div className="flex items-center gap-2 text-slate-600 text-sm">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Loading plans…
                  </div>
                )}
                {loadError && (
                  <Alert variant="destructive">
                    <AlertDescription className="whitespace-pre-line">{loadError}</AlertDescription>
                  </Alert>
                )}
                {!loadingProducts && !loadError && products.length === 0 && (
                  <p className="text-sm text-slate-600">No products returned. Check Stripe keys on Login API.</p>
                )}
                <ul className="space-y-3">
                  {products.map((p) => {
                    const pid = priceIdFromProduct(p)
                    return (
                      <li
                        key={p.id}
                        className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 rounded-lg border border-slate-200 bg-white p-4"
                      >
                        <div>
                          <p className="font-medium text-slate-900">{p.name || p.id}</p>
                          {p.description ? (
                            <p className="text-sm text-slate-600 mt-1">{p.description}</p>
                          ) : null}
                          {!pid && (
                            <p className="text-xs text-amber-700 mt-2">
                              No default price — set one in Stripe
                              {canStartCheckout ? " or use price ID below." : "."}
                            </p>
                          )}
                        </div>
                        {canStartCheckout ? (
                          <Button
                            type="button"
                            disabled={!pid || checkoutLoading !== null}
                            onClick={() => pid && startCheckout(pid)}
                            className="shrink-0"
                          >
                            {checkoutLoading === pid ? <Loader2 className="h-4 w-4 animate-spin" /> : "Subscribe"}
                          </Button>
                        ) : (
                          <span className="text-xs text-slate-500 shrink-0 self-center">View only</span>
                        )}
                      </li>
                    )
                  })}
                </ul>

                {canStartCheckout && (
                  <div className="pt-4 border-t border-slate-200 space-y-2">
                    <Label htmlFor="manual-price">Stripe price ID</Label>
                    <div className="flex flex-col sm:flex-row gap-2">
                      <Input
                        id="manual-price"
                        placeholder="price_…"
                        value={manualPriceId}
                        onChange={(e) => setManualPriceId(e.target.value)}
                        className="font-mono text-sm"
                      />
                      <Button
                        type="button"
                        disabled={!manualPriceId.trim() || checkoutLoading !== null}
                        onClick={() => startCheckout(manualPriceId)}
                        variant="secondary"
                        className="shrink-0"
                      >
                        {checkoutLoading && checkoutLoading === manualPriceId.trim() ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          "Checkout with this price"
                        )}
                      </Button>
                    </div>
                  </div>
                )}
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

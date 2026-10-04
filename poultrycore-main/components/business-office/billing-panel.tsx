"use client"

// Administration → Subscription & Billing (spec Part 22).
//
// Layout follows the shape of a professional SaaS billing centre: one hero
// card anchors the state (plan · market · trial) and the money (next bill +
// Pay — the CTA lives beside the number it pays), companies are a divided
// list rather than a card grid so six rows scan like a statement, totals are
// the list's footer, and invoices/payments share one tabbed card. Unpriced
// companies get a quiet "Pricing pending" pill, not an alarm-coloured card —
// they are informational, nothing is wrong.
//
// Payment truth: returning with ?billing=success only names a reference to
// VERIFY with the provider; the redirect itself never marks anything paid.

import { useCallback, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Inter } from "next/font/google"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { Loader2, CreditCard, Info, Building2, Bird, Droplets, ShoppingBag, BedDouble, UtensilsCrossed } from "lucide-react"
import {
  getBillingSummary,
  getPlatformInvoices,
  getPlatformPayments,
  startPlatformCheckout,
  verifyPlatformPayment,
  explainCompanyPricing,
  previewMarket,
  requestMarketChange,
  cancelMarketChange,
  setBillingCycle,
  cancelSubscription,
  reactivateSubscription,
  type BillingSummary,
  type PlatformInvoice,
  type PlatformPayment,
  type PricingExplain,
  type CompanyBillingRow,
  type MarketChangePreview,
} from "@/lib/api/platform-billing"
import { PUBLIC_PLANS } from "@/lib/billing/public-pricing"
import { PlanCard } from "@/components/billing/plan-card"

const RETURN_PATH = "/business-office/billing"

// The statement card is set in Inter — the numbers-heavy part of the page
// reads best with Inter's tabular figures; the rest of the app stays Geist.
const inter = Inter({ subsets: ["latin"], display: "swap" })

function money(v: number | null | undefined, currency: string) {
  if (v === null || v === undefined) return "—"
  return `${currency} ${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

/** Tier badges carry the plan ladder's visual weight: higher tier, warmer colour. */
function TierBadge({ name }: { name?: string | null }) {
  if (!name) return <span className="text-slate-400">—</span>
  const n = name.toLowerCase()
  const cls =
    n === "growth"
      ? "bg-indigo-50 text-indigo-700 ring-indigo-600/20"
      : n === "business"
        ? "bg-violet-50 text-violet-700 ring-violet-600/20"
        : n === "enterprise"
          ? "bg-amber-50 text-amber-800 ring-amber-600/20"
          : "bg-slate-50 text-slate-600 ring-slate-500/20"
  return (
    <span className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${cls}`}>
      {name}
    </span>
  )
}

function StatusBadge({ status }: { status: string }) {
  const s = status.toLowerCase()
  const cls =
    s === "active" || s === "paid" || s === "succeeded"
      ? "bg-green-50 text-green-700 ring-green-600/20"
      : s === "trial" || s === "open" || s === "evaluation"
        ? "bg-amber-50 text-amber-800 ring-amber-600/20"
        : s === "pastdue" || s === "failed" || s === "suspended"
          ? "bg-red-50 text-red-700 ring-red-600/20"
          : "bg-slate-50 text-slate-600 ring-slate-500/20"
  return (
    <span className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${cls}`}>
      {status}
    </span>
  )
}

/** Soft-tinted icon tile per business type — the row's visual anchor. */
function TypeTile({ type }: { type: string }) {
  const t = type.toLowerCase()
  const [Icon, cls] =
    t === "poultry"
      ? ([Bird, "bg-amber-50 text-amber-600 ring-amber-600/10"] as const)
      : t === "water"
        ? ([Droplets, "bg-sky-50 text-sky-600 ring-sky-600/10"] as const)
        : t === "hotel"
          ? ([BedDouble, "bg-rose-50 text-rose-600 ring-rose-600/10"] as const)
          : t === "restaurant"
            ? ([UtensilsCrossed, "bg-orange-50 text-orange-600 ring-orange-600/10"] as const)
            : t === "generic"
              ? ([ShoppingBag, "bg-violet-50 text-violet-600 ring-violet-600/10"] as const)
              : ([Building2, "bg-slate-100 text-slate-500 ring-slate-500/10"] as const)
  return (
    <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-lg ring-1 ring-inset ${cls}`}>
      <Icon className="h-[18px] w-[18px]" strokeWidth={1.75} />
    </div>
  )
}

/** One statement row per company. */
function CompanyRow({ c, onExplain }: { c: CompanyBillingRow; onExplain: (farmId: string) => void }) {
  const unpriced = c.pricingStatus === "PricingNotConfigured"
  const evaluation = c.pricingStatus === "Evaluation"
  const inactive = c.participationStatus !== "Active" && c.participationStatus !== "EnterpriseContract"

  return (
    <div className="group flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3.5 transition-colors hover:bg-slate-50/60 sm:px-6">
      <div className="flex min-w-0 flex-1 basis-56 items-center gap-3">
        <TypeTile type={c.businessType} />
        <div className="min-w-0">
          <p className="truncate text-[15px] font-medium leading-5 tracking-[-0.01em] text-slate-900">{c.companyName}</p>
          <p className="text-xs leading-4 text-slate-500">{c.businessType}</p>
        </div>
      </div>

      <div className="hidden w-32 text-sm sm:block">
        {c.metricType === "ManualScale" && c.metricValue === 0 ? (
          <span className="text-[13px] italic text-slate-400">No scale set</span>
        ) : (
          <span className="tabular-nums font-medium text-slate-700">
            {c.metricValue.toLocaleString()}
            <span className="font-normal text-slate-400"> {c.metricType === "ActiveBirdCount" ? "birds" : "units"}</span>
          </span>
        )}
      </div>

      <div className="w-24">
        {inactive ? <StatusBadge status={c.participationStatus} /> : <TierBadge name={c.tierName} />}
      </div>

      <div className="w-36 text-right">
        {unpriced ? (
          <span className="inline-flex items-center gap-1.5 text-xs font-medium text-amber-700">
            <span className="h-1.5 w-1.5 rounded-full bg-amber-500" aria-hidden />
            Pricing pending
          </span>
        ) : evaluation ? (
          <span className="text-xs text-slate-500">
            Free until {c.evaluationUntilUtc ? new Date(c.evaluationUntilUtc).toLocaleDateString() : "review"}
          </span>
        ) : inactive ? (
          <span className="text-slate-300">—</span>
        ) : (
          <span className="tabular-nums text-[15px] font-semibold tracking-[-0.01em] text-slate-900">
            {money(c.monthlyAmount, c.currencyCode)}
            <span className="ml-0.5 text-xs font-normal text-slate-400">/mo</span>
          </span>
        )}
      </div>

      <Button
        variant="ghost"
        size="sm"
        className="h-8 w-8 p-0 text-slate-300 transition-colors hover:text-indigo-600 group-hover:text-slate-400"
        title="Why this price?"
        onClick={() => onExplain(c.farmId)}
      >
        <Info className="h-4 w-4" />
      </Button>
    </div>
  )
}

export function BillingPanel() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { toast } = useToast()

  const [summary, setSummary] = useState<BillingSummary | null>(null)
  const [invoices, setInvoices] = useState<PlatformInvoice[]>([])
  const [payments, setPayments] = useState<PlatformPayment[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState("")
  const [checkoutBusy, setCheckoutBusy] = useState(false)
  const [verifying, setVerifying] = useState(false)
  const [explain, setExplain] = useState<PricingExplain | null>(null)
  const [explainOpen, setExplainOpen] = useState(false)
  const [marketOpen, setMarketOpen] = useState(false)
  const [marketTarget, setMarketTarget] = useState("NG")
  const [marketReason, setMarketReason] = useState("")
  const [marketPreviewData, setMarketPreviewData] = useState<MarketChangePreview | null>(null)
  const [marketBusy, setMarketBusy] = useState(false)

  const reload = useCallback(async () => {
    setLoading(true)
    setLoadError("")
    try {
      const [s, inv, pay] = await Promise.all([
        getBillingSummary(),
        getPlatformInvoices(),
        getPlatformPayments(),
      ])
      setSummary(s)
      setInvoices(inv)
      setPayments(pay)
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : "Could not load billing.")
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void reload()
  }, [reload])

  useEffect(() => {
    const status = searchParams.get("billing")
    const reference = searchParams.get("reference") || searchParams.get("trxref")
    if (status === "success" && reference) {
      setVerifying(true)
      verifyPlatformPayment(reference)
        .then((r) => {
          toast({
            title: r.ok ? "Payment confirmed" : "Payment not confirmed yet",
            description: r.message,
            variant: r.ok ? undefined : "destructive",
          })
          if (r.ok) void reload()
        })
        .finally(() => {
          setVerifying(false)
          router.replace(RETURN_PATH)
        })
    } else if (status === "cancel") {
      toast({ title: "Checkout cancelled", description: "No changes were made." })
      router.replace(RETURN_PATH)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchParams])

  const startCheckout = async () => {
    setCheckoutBusy(true)
    try {
      const base = `${window.location.origin}${RETURN_PATH}`
      const res = await startPlatformCheckout(`${base}?billing=success`, `${base}?billing=cancel`)
      if (!res.success || !res.checkoutUrl) {
        toast({ variant: "destructive", title: "Could not start checkout", description: res.message })
        return
      }
      window.location.href = res.checkoutUrl
    } finally {
      setCheckoutBusy(false)
    }
  }

  const openExplain = async (farmId: string) => {
    try {
      setExplain(await explainCompanyPricing(farmId))
      setExplainOpen(true)
    } catch (e) {
      toast({
        variant: "destructive",
        title: "No pricing details yet",
        description: e instanceof Error ? e.message : undefined,
      })
    }
  }

  const act = async (fn: () => Promise<{ ok: boolean; message: string }>) => {
    const r = await fn()
    toast({ title: r.ok ? "Done" : "Not changed", description: r.message, variant: r.ok ? undefined : "destructive" })
    if (r.ok) void reload()
  }

  const loadMarketPreview = async (code: string) => {
    setMarketTarget(code)
    setMarketPreviewData(null)
    try {
      setMarketPreviewData(await previewMarket(code))
    } catch {
      setMarketPreviewData(null)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center gap-2 py-16 text-slate-600">
        <Loader2 className="h-5 w-5 animate-spin" /> Loading your billing…
      </div>
    )
  }
  if (loadError || !summary) {
    return (
      <Alert variant="destructive">
        <AlertDescription>{loadError || "Could not load billing."}</AlertDescription>
      </Alert>
    )
  }

  const { account: acct, preview, companies } = summary
  const trialEnded = acct.status === "Trial" && (acct.trialDaysLeft ?? 0) <= 0
  const canPay = !preview.hasUnpricedCompanies && preview.total > 0

  return (
    <div className="space-y-5">
      {/* Notices — thin, informational, above the fold */}
      {summary.pendingTierChanges?.length > 0 && (
        <div className="rounded-lg border border-indigo-200 bg-indigo-50/60 px-4 py-3 text-sm text-indigo-900">
          {summary.pendingTierChanges.map((p) => (
            <p key={p.farmId}>
              <strong>{p.companyName}</strong> now qualifies for <strong>{p.toTierName}</strong> — its plan
              changes from {p.fromTierName} on {new Date(p.effectiveDate).toLocaleDateString()}. Nothing
              changes mid-period.
            </p>
          ))}
        </div>
      )}
      {acct.pendingMarketCode && (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700">
          <span>
            Billing market changes to <strong>{acct.pendingMarketCode}</strong> on{" "}
            {acct.pendingMarketEffective ? new Date(acct.pendingMarketEffective).toLocaleDateString() : "next cycle"}.
          </span>
          <Button size="sm" variant="ghost" className="h-7 text-slate-500" onClick={() => void act(cancelMarketChange)}>
            Undo
          </Button>
        </div>
      )}
      {acct.cancelAtPeriodEnd && (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-red-200 bg-red-50/60 px-4 py-3 text-sm text-red-900">
          <span>
            Your subscription will not renew. Full access continues through{" "}
            {acct.currentPeriodEnd ? new Date(acct.currentPeriodEnd).toLocaleDateString() : "the period end"}.
          </span>
          <Button size="sm" variant="outline" onClick={() => void act(reactivateSubscription)}>
            Reactivate
          </Button>
        </div>
      )}

      {/* Hero: state on the left, money + CTA on the right */}
      <Card className="overflow-hidden">
        <div className="flex flex-col sm:flex-row">
          <div className="flex-1 p-5 sm:p-6">
            <div className="flex items-center gap-2">
              <p className="text-sm font-medium text-slate-500">VisibilityCore subscription</p>
              <StatusBadge status={trialEnded ? "Trial ended" : acct.status} />
            </div>
            <p className="mt-2 text-2xl font-bold tracking-tight text-slate-900">
              {acct.marketCode} · {acct.currencyCode}
              <span className="ml-2 align-middle text-sm font-normal capitalize text-slate-500">
                billed {acct.billingCycle}
              </span>
            </p>
            {acct.status === "Trial" && !trialEnded && (
              <p className="mt-1 text-sm text-slate-500">{acct.trialDaysLeft} trial days remaining</p>
            )}
            <div className="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-sm">
              <button
                className="text-indigo-600 hover:underline"
                onClick={() => void act(() => setBillingCycle(acct.billingCycle === "annual" ? "monthly" : "annual"))}
              >
                Switch to {acct.billingCycle === "annual" ? "monthly" : "annual"} billing
              </button>
              <button
                className="text-indigo-600 hover:underline"
                onClick={() => {
                  setMarketOpen(true)
                  void loadMarketPreview(marketTarget)
                }}
              >
                Change billing market
              </button>
              {!acct.cancelAtPeriodEnd && (
                <button
                  className="text-slate-400 hover:text-red-600 hover:underline"
                  onClick={() => void act(() => cancelSubscription())}
                >
                  Cancel subscription
                </button>
              )}
            </div>
          </div>

          <div className="border-t border-slate-100 bg-slate-50/70 p-5 sm:w-80 sm:border-l sm:border-t-0 sm:p-6">
            <p className="text-sm font-medium text-slate-500">Next bill</p>
            <p className="mt-1 text-3xl font-bold tabular-nums tracking-tight text-slate-900">
              {money(preview.total, preview.currencyCode)}
            </p>
            <p className="mt-0.5 text-xs text-slate-500">
              {new Date(preview.periodStart).toLocaleDateString()} –{" "}
              {new Date(preview.periodEnd).toLocaleDateString()}
              {preview.discountAmount > 0 && (
                <span className="text-green-600"> · includes {preview.discountPercent}% discount</span>
              )}
            </p>
            <Button
              className="mt-4 w-full gap-2"
              onClick={() => void startCheckout()}
              disabled={checkoutBusy || verifying || !canPay}
            >
              {checkoutBusy || verifying ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <CreditCard className="h-4 w-4" />
              )}
              {verifying ? "Confirming payment…" : "Pay this period"}
            </Button>
            {preview.hasUnpricedCompanies && (
              <p className="mt-2 text-xs leading-relaxed text-slate-500">
                Checkout opens once pricing is configured for all your business types.
              </p>
            )}
          </div>
        </div>
      </Card>

      {/* Companies — a statement, not a card grid. Set in Inter. */}
      <Card className={`overflow-hidden ${inter.className}`}>
        <CardHeader className="border-b border-slate-100 bg-white py-4">
          <div className="flex items-center justify-between">
            <CardTitle className="flex items-center gap-2.5 text-[15px] font-semibold tracking-[-0.01em] text-slate-900">
              <span className="flex h-7 w-7 items-center justify-center rounded-md bg-indigo-50 ring-1 ring-inset ring-indigo-600/10">
                <Building2 className="h-4 w-4 text-indigo-600" strokeWidth={1.75} />
              </span>
              Companies on this bill
            </CardTitle>
            <span className="inline-flex items-center rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium tabular-nums text-slate-600">
              {preview.eligibleCompanyCount} of {companies.length} billed
            </span>
          </div>
        </CardHeader>
        <div className="divide-y divide-slate-100">
          {companies.map((c) => (
            <CompanyRow key={c.farmId} c={c} onExplain={(id) => void openExplain(id)} />
          ))}
        </div>
        <div className="border-t border-slate-200/70 bg-slate-50/80 px-4 py-5 sm:px-6">
          <div className="ml-auto w-full max-w-sm space-y-2 text-sm">
            <div className="flex items-baseline justify-between text-slate-500">
              <span>Subtotal</span>
              <span className="tabular-nums font-medium text-slate-700">{money(preview.subtotal, preview.currencyCode)}</span>
            </div>
            {preview.discountAmount > 0 && (
              <div className="flex items-baseline justify-between text-emerald-700">
                <span>Multi-company discount ({preview.discountPercent}%)</span>
                <span className="tabular-nums font-medium">-{money(preview.discountAmount, preview.currencyCode)}</span>
              </div>
            )}
            {preview.taxAmount > 0 && (
              <div className="flex items-baseline justify-between text-slate-500">
                <span>Tax</span>
                <span className="tabular-nums font-medium text-slate-700">{money(preview.taxAmount, preview.currencyCode)}</span>
              </div>
            )}
            <div className="flex items-baseline justify-between border-t border-slate-200 pt-3">
              <span className="font-medium text-slate-900">Total / month</span>
              <span className="tabular-nums text-lg font-semibold tracking-[-0.02em] text-slate-900">
                {money(preview.total, preview.currencyCode)}
              </span>
            </div>
          </div>
          {preview.hasUnpricedCompanies && (
            <div className="mt-4 flex items-start gap-2 rounded-lg bg-amber-50/70 px-3 py-2.5 ring-1 ring-inset ring-amber-600/10">
              <Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
              <p className="text-xs leading-relaxed text-amber-800">
                Pricing for some business types is being finalized. Those companies are listed but not charged;
                contact VisibilityCore support to enable them.
              </p>
            </div>
          )}
        </div>
      </Card>

      {/* Plan ladder — the same full cards as /pricing (shared PlanCard).
          Tiers are assigned automatically from each company's scale, so the
          CTA area shows how many of the org's companies sit on each plan;
          only Enterprise carries a real button. */}
      <div className={inter.className}>
        <div className="mb-4 flex items-baseline justify-between px-1">
          <h3 className="text-[15px] font-semibold tracking-[-0.01em] text-slate-900">Plans</h3>
          <span className="text-xs text-slate-500">Assigned automatically from each company's scale</span>
        </div>
        <div className="grid gap-6 pt-3 sm:grid-cols-2 xl:grid-cols-4 xl:gap-5">
          {PUBLIC_PLANS.map((p) => {
            const onPlan = companies.filter((c) => (c.tierName || "").toLowerCase() === p.name.toLowerCase()).length
            return (
              <PlanCard
                key={p.code}
                plan={p}
                cta={
                  p.code === "enterprise" ? (
                    <a
                      href="https://techretainer.com/contact/"
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex h-11 w-full items-center justify-center rounded-lg bg-slate-900 text-sm font-medium text-white transition-colors hover:bg-slate-800"
                    >
                      Request a price
                    </a>
                  ) : (
                    <div
                      className={`inline-flex h-11 w-full items-center justify-center rounded-lg text-sm font-medium ${
                        p.highlight
                          ? "bg-white/15 text-white ring-1 ring-inset ring-white/30"
                          : "bg-slate-50 text-slate-600 ring-1 ring-inset ring-slate-200"
                      }`}
                    >
                      {onPlan > 0
                        ? `${onPlan} of your ${onPlan === 1 ? "company is" : "companies are"} on this plan`
                        : "No companies at this scale yet"}
                    </div>
                  )
                }
              />
            )
          })}
        </div>
        <p className="mt-4 px-1 text-xs leading-relaxed text-slate-500">
          Every plan includes the complete platform — pricing scales with each company's size. Poultry companies
          are priced by active birds today; other business types are listed on your bill but not charged until
          their pricing is enabled.
        </p>
      </div>

      {/* History: invoices and payments share one card */}
      <Card>
        <CardContent className="pt-5">
          <Tabs defaultValue="invoices">
            <TabsList>
              <TabsTrigger value="invoices">Invoices</TabsTrigger>
              <TabsTrigger value="payments">Payments</TabsTrigger>
            </TabsList>
            <TabsContent value="invoices" className="pt-3">
              {invoices.length === 0 ? (
                <p className="py-6 text-center text-sm text-slate-500">
                  No invoices yet — your first invoice is created when you pay.
                </p>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Invoice</TableHead>
                        <TableHead>Period</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                        <TableHead className="text-right">Balance</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {invoices.map((inv) => (
                        <TableRow key={inv.id}>
                          <TableCell className="font-mono text-xs">{inv.invoiceNumber}</TableCell>
                          <TableCell className="text-xs text-slate-600">
                            {new Date(inv.periodStart).toLocaleDateString()} –{" "}
                            {new Date(inv.periodEnd).toLocaleDateString()}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {money(inv.totalAmount, inv.currencyCode)}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {money(inv.balance, inv.currencyCode)}
                          </TableCell>
                          <TableCell><StatusBadge status={inv.status} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </TabsContent>
            <TabsContent value="payments" className="pt-3">
              {payments.length === 0 ? (
                <p className="py-6 text-center text-sm text-slate-500">No payments yet.</p>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Provider</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                        <TableHead>Invoice</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {payments.map((p) => (
                        <TableRow key={p.id}>
                          <TableCell className="text-xs text-slate-600">
                            {p.paymentDateUtc ? new Date(p.paymentDateUtc).toLocaleString() : "—"}
                          </TableCell>
                          <TableCell className="capitalize">{p.provider}</TableCell>
                          <TableCell className="text-right tabular-nums">
                            {money(p.amount, p.currencyCode)}
                          </TableCell>
                          <TableCell className="font-mono text-xs">{p.invoiceNumber ?? "—"}</TableCell>
                          <TableCell><StatusBadge status={p.status} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>

      {/* Market change: request + shown price impact + confirmation (spec 3.7) */}
      <Dialog open={marketOpen} onOpenChange={setMarketOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Change billing market</DialogTitle>
            <DialogDescription>
              Takes effect at your next billing cycle — current invoices and the running period never change.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <Select value={marketTarget} onValueChange={(v) => void loadMarketPreview(v)}>
              <SelectTrigger><SelectValue placeholder="New market" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="GH">Ghana — GHS</SelectItem>
                <SelectItem value="NG">Nigeria — NGN</SelectItem>
                <SelectItem value="US">United States — USD</SelectItem>
              </SelectContent>
            </Select>

            {marketPreviewData && (
              <div className="rounded-lg border border-slate-200 bg-slate-50/70 p-3 text-sm">
                {!marketPreviewData.marketActive ? (
                  <p className="text-amber-800">
                    {marketPreviewData.marketName} is not open yet — the request will be declined until
                    VisibilityCore launches there.
                  </p>
                ) : marketPreviewData.preview.hasUnpricedCompanies ? (
                  <p className="text-amber-800">
                    Pricing for some of your business types is not configured in {marketPreviewData.marketName} yet.
                  </p>
                ) : (
                  <p>
                    Estimated new total:{" "}
                    <strong className="tabular-nums">
                      {marketPreviewData.preview.currencyCode}{" "}
                      {marketPreviewData.preview.total.toLocaleString()}
                    </strong>{" "}
                    /month <span className="text-slate-500">(currently {preview.currencyCode} {preview.total.toLocaleString()})</span>
                  </p>
                )}
              </div>
            )}

            <Input
              placeholder="Reason (e.g. business relocated)"
              value={marketReason}
              onChange={(e) => setMarketReason(e.target.value)}
            />
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setMarketOpen(false)}>Close</Button>
              <Button
                disabled={marketBusy || marketTarget === acct.marketCode}
                onClick={async () => {
                  setMarketBusy(true)
                  try {
                    await act(() => requestMarketChange(marketTarget, marketReason))
                    setMarketOpen(false)
                  } finally {
                    setMarketBusy(false)
                  }
                }}
              >
                {marketBusy ? <Loader2 className="h-4 w-4 animate-spin" /> : "Confirm request"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Why this price? — read from the stored evaluation (spec 22.5) */}
      <Dialog open={explainOpen} onOpenChange={setExplainOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>How this plan is calculated</DialogTitle>
            {explain && (
              <DialogDescription asChild>
                <div className="space-y-2 pt-2 text-sm text-slate-700">
                  <div className="font-medium text-slate-900">{explain.companyName}</div>
                  <div className="grid grid-cols-2 gap-x-4 gap-y-1">
                    <span className="text-slate-500">Billing profile</span>
                    <span>{explain.billingProfileName}</span>
                    <span className="text-slate-500">Current usage</span>
                    <span>{explain.metricValue.toLocaleString()}</span>
                    <span className="text-slate-500">Plan</span>
                    <span><TierBadge name={explain.tierName} /></span>
                    <span className="text-slate-500">Billing market</span>
                    <span>{explain.marketName}</span>
                    <span className="text-slate-500">Price</span>
                    <span className="tabular-nums">
                      {explain.pricingStatus === "PricingNotConfigured"
                        ? "Being finalized"
                        : `${money(explain.monthlyAmount, explain.currencyCode)}/month`}
                    </span>
                    {explain.nextTierName && explain.nextTierAtValue != null && (
                      <>
                        <span className="text-slate-500">Next plan</span>
                        <span>
                          {explain.nextTierName} at {explain.nextTierAtValue.toLocaleString()}
                        </span>
                      </>
                    )}
                  </div>
                  <p className="pt-1 text-xs text-slate-500">
                    Evaluated {new Date(explain.evaluatedAtUtc).toLocaleString()}. Your price only changes at
                    the start of a billing cycle — never mid-period.
                  </p>
                </div>
              </DialogDescription>
            )}
          </DialogHeader>
        </DialogContent>
      </Dialog>
    </div>
  )
}

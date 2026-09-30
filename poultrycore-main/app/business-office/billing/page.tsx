"use client"

// Business Office → Subscription & Billing (spec Part 22).
//
// The Business Office is the billing customer: one consolidated bill, one row
// per company, each row explainable ("why this price?") from its stored
// evaluation — customer-facing language, not engine terminology (Part 54).
//
// Payment truth: landing back here with ?billing=success only tells us which
// reference to VERIFY with the provider; nothing is marked paid by the
// redirect itself (Part 13.4).

import { Suspense, useCallback, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useToast } from "@/hooks/use-toast"
import { Loader2, CreditCard, Receipt, Building2, Info } from "lucide-react"
import {
  getBillingSummary,
  getPlatformInvoices,
  getPlatformPayments,
  startPlatformCheckout,
  verifyPlatformPayment,
  explainCompanyPricing,
  type BillingSummary,
  type PlatformInvoice,
  type PlatformPayment,
  type PricingExplain,
} from "@/lib/api/platform-billing"

function money(v: number | null | undefined, currency: string) {
  if (v === null || v === undefined) return "—"
  return `${currency} ${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function statusBadge(status: string) {
  const s = status.toLowerCase()
  const cls =
    s === "active" || s === "paid"
      ? "bg-green-100 text-green-800"
      : s === "trial" || s === "open"
        ? "bg-amber-100 text-amber-800"
        : s === "pastdue" || s === "failed"
          ? "bg-red-100 text-red-800"
          : "bg-slate-100 text-slate-700"
  return <Badge className={cls}>{status}</Badge>
}

// useSearchParams needs a Suspense boundary at prerender time — same
// wrapper the old /billing page uses.
export default function BusinessOfficeBillingPage() {
  return (
    <Suspense
      fallback={
        <div className="flex items-center gap-2 text-slate-600 py-12 justify-center">
          <Loader2 className="h-5 w-5 animate-spin" /> Loading…
        </div>
      }
    >
      <BusinessOfficeBillingInner />
    </Suspense>
  )
}

function BusinessOfficeBillingInner() {
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

  // Returning from checkout: verify with the provider, then refresh.
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
          router.replace("/business-office/billing")
        })
    } else if (status === "cancel") {
      toast({ title: "Checkout cancelled", description: "No changes were made." })
      router.replace("/business-office/billing")
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchParams])

  const startCheckout = async () => {
    setCheckoutBusy(true)
    try {
      const base = `${window.location.origin}/business-office/billing`
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

  const acct = summary?.account
  const preview = summary?.preview

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 min-w-0 lg:ml-64">
        <DashboardHeader />
        <main className="p-4 sm:p-6 pb-16 lg:pb-6 space-y-6">
          {/* Header */}
          <div>
            <h1 className="text-xl sm:text-3xl font-bold text-slate-900">Subscription &amp; Billing</h1>
            <p className="text-sm text-slate-600 mt-1">
              Manage your VisibilityCore subscription, companies, invoices and payment method.
            </p>
          </div>

          {loadError && (
            <Alert variant="destructive">
              <AlertDescription>{loadError}</AlertDescription>
            </Alert>
          )}

          {loading ? (
            <div className="flex items-center gap-2 text-slate-600 py-12 justify-center">
              <Loader2 className="h-5 w-5 animate-spin" /> Loading your billing…
            </div>
          ) : summary && acct && preview ? (
            <>
              {/* Account overview */}
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium text-slate-600">Billing market</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">{acct.marketCode}</div>
                    <p className="text-xs text-slate-500">{acct.currencyCode} · {acct.billingCycle}</p>
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium text-slate-600">Status</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">{statusBadge(acct.status)}</div>
                    {acct.status === "Trial" && acct.trialDaysLeft != null && (
                      <p className="text-xs text-slate-500 mt-1">{acct.trialDaysLeft} trial days left</p>
                    )}
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium text-slate-600">Companies billed</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">{preview.eligibleCompanyCount}</div>
                    <p className="text-xs text-slate-500">of {summary.companies.length} companies</p>
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium text-slate-600">Next bill estimate</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">{money(preview.total, preview.currencyCode)}</div>
                    <p className="text-xs text-slate-500">
                      {new Date(preview.periodStart).toLocaleDateString()} –{" "}
                      {new Date(preview.periodEnd).toLocaleDateString()}
                    </p>
                  </CardContent>
                </Card>
              </div>

              {/* Company subscription table (22.2) */}
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2 text-lg">
                    <Building2 className="h-5 w-5" /> Your companies
                  </CardTitle>
                  <CardDescription>
                    How each company&apos;s plan is calculated — from its own scale, in your billing market.
                  </CardDescription>
                </CardHeader>
                <CardContent className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Company</TableHead>
                        <TableHead>Business type</TableHead>
                        <TableHead>Usage</TableHead>
                        <TableHead>Plan</TableHead>
                        <TableHead className="text-right">Monthly</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead />
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {summary.companies.map((c) => (
                        <TableRow key={c.farmId}>
                          <TableCell className="font-medium">{c.companyName}</TableCell>
                          <TableCell>{c.businessType}</TableCell>
                          <TableCell>
                            {c.metricType === "ManualScale" && c.metricValue === 0
                              ? "—"
                              : c.metricValue.toLocaleString()}
                          </TableCell>
                          <TableCell>{c.tierName ?? "—"}</TableCell>
                          <TableCell className="text-right">
                            {c.pricingStatus === "PricingNotConfigured" ? (
                              <span className="text-amber-700 text-xs">Pricing being finalized</span>
                            ) : (
                              money(c.monthlyAmount, c.currencyCode)
                            )}
                          </TableCell>
                          <TableCell>{statusBadge(c.participationStatus)}</TableCell>
                          <TableCell>
                            <Button variant="ghost" size="sm" onClick={() => void openExplain(c.farmId)}>
                              <Info className="h-4 w-4 mr-1" /> Why this price?
                            </Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>

                  {/* Bill summary (22.4) */}
                  <div className="mt-4 border-t pt-4 max-w-sm ml-auto space-y-1 text-sm">
                    <div className="flex justify-between">
                      <span className="text-slate-600">Subtotal</span>
                      <span>{money(preview.subtotal, preview.currencyCode)}</span>
                    </div>
                    {preview.discountAmount > 0 && (
                      <div className="flex justify-between text-green-700">
                        <span>Multi-company discount ({preview.discountPercent}%)</span>
                        <span>-{money(preview.discountAmount, preview.currencyCode)}</span>
                      </div>
                    )}
                    {preview.taxAmount > 0 && (
                      <div className="flex justify-between">
                        <span className="text-slate-600">Tax</span>
                        <span>{money(preview.taxAmount, preview.currencyCode)}</span>
                      </div>
                    )}
                    <div className="flex justify-between font-bold text-base pt-1 border-t">
                      <span>Total / month</span>
                      <span>{money(preview.total, preview.currencyCode)}</span>
                    </div>
                  </div>

                  {preview.hasUnpricedCompanies && (
                    <Alert className="mt-4">
                      <AlertDescription>
                        Pricing for some of your business types is being finalized. Those companies are shown
                        above but not charged, and checkout is paused until pricing is configured. Please
                        contact VisibilityCore support.
                      </AlertDescription>
                    </Alert>
                  )}

                  <div className="mt-4 flex justify-end">
                    <Button
                      onClick={() => void startCheckout()}
                      disabled={checkoutBusy || verifying || preview.hasUnpricedCompanies || preview.total <= 0}
                      className="gap-2"
                    >
                      {checkoutBusy || verifying ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        <CreditCard className="h-4 w-4" />
                      )}
                      {verifying ? "Confirming payment…" : "Pay this period"}
                    </Button>
                  </div>
                </CardContent>
              </Card>

              {/* Invoices (22.6) */}
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2 text-lg">
                    <Receipt className="h-5 w-5" /> Invoices
                  </CardTitle>
                </CardHeader>
                <CardContent className="overflow-x-auto">
                  {invoices.length === 0 ? (
                    <p className="text-sm text-slate-500">No invoices yet. Your first invoice is created when you pay.</p>
                  ) : (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Invoice #</TableHead>
                          <TableHead>Period</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          <TableHead className="text-right">Paid</TableHead>
                          <TableHead className="text-right">Balance</TableHead>
                          <TableHead>Status</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {invoices.map((inv) => (
                          <TableRow key={inv.id}>
                            <TableCell className="font-mono text-xs">{inv.invoiceNumber}</TableCell>
                            <TableCell className="text-xs">
                              {new Date(inv.periodStart).toLocaleDateString()} –{" "}
                              {new Date(inv.periodEnd).toLocaleDateString()}
                            </TableCell>
                            <TableCell className="text-right">{money(inv.totalAmount, inv.currencyCode)}</TableCell>
                            <TableCell className="text-right">{money(inv.amountPaid, inv.currencyCode)}</TableCell>
                            <TableCell className="text-right">{money(inv.balance, inv.currencyCode)}</TableCell>
                            <TableCell>{statusBadge(inv.status)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  )}
                </CardContent>
              </Card>

              {/* Payments (22.7) */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">Payment history</CardTitle>
                </CardHeader>
                <CardContent className="overflow-x-auto">
                  {payments.length === 0 ? (
                    <p className="text-sm text-slate-500">No payments yet.</p>
                  ) : (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Date</TableHead>
                          <TableHead>Provider</TableHead>
                          <TableHead>Reference</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          <TableHead>Invoice</TableHead>
                          <TableHead>Status</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {payments.map((p) => (
                          <TableRow key={p.id}>
                            <TableCell className="text-xs">
                              {p.paymentDateUtc ? new Date(p.paymentDateUtc).toLocaleString() : "—"}
                            </TableCell>
                            <TableCell className="capitalize">{p.provider}</TableCell>
                            <TableCell className="font-mono text-xs">{p.externalReference ?? "—"}</TableCell>
                            <TableCell className="text-right">{money(p.amount, p.currencyCode)}</TableCell>
                            <TableCell className="font-mono text-xs">{p.invoiceNumber ?? "—"}</TableCell>
                            <TableCell>{statusBadge(p.status)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  )}
                </CardContent>
              </Card>
            </>
          ) : null}

          {/* Why this price? (22.5) — read from the stored evaluation */}
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
                        <span>{explain.tierName ?? "—"}</span>
                        <span className="text-slate-500">Billing market</span>
                        <span>{explain.marketName}</span>
                        <span className="text-slate-500">Price</span>
                        <span>
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
                      <p className="text-xs text-slate-500 pt-1">
                        Evaluated {new Date(explain.evaluatedAtUtc).toLocaleString()}. Your price only changes
                        at the start of a billing cycle — never mid-period.
                      </p>
                    </div>
                  </DialogDescription>
                )}
              </DialogHeader>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

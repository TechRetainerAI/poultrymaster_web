"use client"

// Administration → Subscription & Billing (spec Part 22, house-styled).
//
// Lives as a tab of the Business Office Administration hub, not a standalone
// page: billing is org administration, and the owner already comes here for
// employees, access and companies. Visual language follows the original
// billing page — rounded tier cards with Current badges — extended from one
// poultry plan to one card per company.
//
// Payment truth: returning with ?billing=success only names a reference to
// VERIFY with the provider; the redirect itself never marks anything paid.

import { useCallback, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useToast } from "@/hooks/use-toast"
import { Loader2, CreditCard, Receipt, Info, Landmark, CalendarClock, Building2, Wallet } from "lucide-react"
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
  type CompanyBillingRow,
} from "@/lib/api/platform-billing"

const RETURN_PATH = "/business-office/setup?tab=billing"

function money(v: number | null | undefined, currency: string) {
  if (v === null || v === undefined) return "—"
  return `${currency} ${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function StatusPill({ status }: { status: string }) {
  const s = status.toLowerCase()
  const cls =
    s === "active" || s === "paid" || s === "resolved" || s === "succeeded"
      ? "bg-green-100 text-green-800"
      : s === "trial" || s === "open"
        ? "bg-amber-100 text-amber-800"
        : s === "pastdue" || s === "failed"
          ? "bg-red-100 text-red-800"
          : "bg-slate-100 text-slate-700"
  return <Badge className={cls}>{status}</Badge>
}

/** One company as a plan card, in the original billing page's card language. */
function CompanyPlanCard({ c, onExplain }: { c: CompanyBillingRow; onExplain: (farmId: string) => void }) {
  const unpriced = c.pricingStatus === "PricingNotConfigured"
  const inactive = c.participationStatus !== "Active" && c.participationStatus !== "EnterpriseContract"
  return (
    <div
      className={`rounded-xl border p-4 shadow-sm transition-colors ${
        unpriced
          ? "border-amber-200 bg-amber-50/60"
          : inactive
            ? "border-slate-200 bg-slate-50"
            : "border-indigo-200 bg-indigo-50/50"
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-semibold text-slate-900 truncate">{c.companyName}</p>
          <p className="text-xs text-slate-500">{c.businessType}</p>
        </div>
        <StatusPill status={inactive ? c.participationStatus : (c.tierName ?? "—")} />
      </div>

      <div className="mt-3">
        {unpriced ? (
          <p className="text-sm font-medium text-amber-800">Pricing being finalized</p>
        ) : (
          <>
            <p className="text-2xl font-bold tracking-tight text-slate-900">
              {money(c.monthlyAmount, c.currencyCode)}
            </p>
            <p className="text-xs text-slate-500">per month</p>
          </>
        )}
      </div>

      <div className="mt-2 flex items-center justify-between text-xs text-slate-600">
        <span>
          {c.metricType === "ManualScale" && c.metricValue === 0
            ? "Scale not set"
            : `${c.metricValue.toLocaleString()} ${c.metricType === "ActiveBirdCount" ? "birds" : "scale"}`}
        </span>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 px-2 text-xs text-indigo-700"
          onClick={() => onExplain(c.farmId)}
        >
          <Info className="h-3.5 w-3.5 mr-1" /> Why this price?
        </Button>
      </div>
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
      const res = await startPlatformCheckout(`${base}&billing=success`, `${base}&billing=cancel`)
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

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-slate-600 py-12 justify-center">
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

  return (
    <div className="space-y-6">
      {/* Overview strip — same compact stat style the rest of Administration uses */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div className="rounded-xl border border-slate-200 bg-white p-3.5 shadow-sm">
          <div className="flex items-center gap-2 text-xs text-slate-500">
            <Landmark className="h-3.5 w-3.5" /> Billing market
          </div>
          <p className="mt-1 text-lg font-bold text-slate-900">
            {acct.marketCode} · {acct.currencyCode}
          </p>
          <p className="text-xs text-slate-500 capitalize">{acct.billingCycle}</p>
        </div>
        <div className="rounded-xl border border-slate-200 bg-white p-3.5 shadow-sm">
          <div className="flex items-center gap-2 text-xs text-slate-500">
            <CalendarClock className="h-3.5 w-3.5" /> Status
          </div>
          <div className="mt-1"><StatusPill status={acct.status} /></div>
          {acct.status === "Trial" && acct.trialDaysLeft != null && (
            <p className="text-xs text-slate-500 mt-1">{acct.trialDaysLeft} trial days left</p>
          )}
        </div>
        <div className="rounded-xl border border-slate-200 bg-white p-3.5 shadow-sm">
          <div className="flex items-center gap-2 text-xs text-slate-500">
            <Building2 className="h-3.5 w-3.5" /> Companies billed
          </div>
          <p className="mt-1 text-lg font-bold text-slate-900">
            {preview.eligibleCompanyCount}
            <span className="text-sm font-normal text-slate-500"> of {companies.length}</span>
          </p>
        </div>
        <div className="rounded-xl border border-indigo-200 bg-indigo-50/60 p-3.5 shadow-sm">
          <div className="flex items-center gap-2 text-xs text-indigo-700">
            <Wallet className="h-3.5 w-3.5" /> Next bill estimate
          </div>
          <p className="mt-1 text-lg font-bold text-indigo-900">{money(preview.total, preview.currencyCode)}</p>
          <p className="text-xs text-indigo-700/70">
            {new Date(preview.periodStart).toLocaleDateString()} – {new Date(preview.periodEnd).toLocaleDateString()}
          </p>
        </div>
      </div>

      {/* Company plan cards */}
      <div className="space-y-3">
        <div className="text-center space-y-1">
          <p className="text-xl font-semibold tracking-tight text-slate-900">Your companies&apos; plans</p>
          <p className="text-sm text-slate-600">
            Each company is priced from its own scale, in your billing market — one consolidated bill.
          </p>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {companies.map((c) => (
            <CompanyPlanCard key={c.farmId} c={c} onExplain={(id) => void openExplain(id)} />
          ))}
        </div>
      </div>

      {/* Bill summary + pay */}
      <Card>
        <CardContent className="pt-6">
          <div className="max-w-sm ml-auto space-y-1 text-sm">
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
                Pricing for some of your business types is being finalized. Those companies are shown above
                but not charged, and checkout is paused until pricing is configured. Please contact
                VisibilityCore support.
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

      {/* Invoices */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base">
            <Receipt className="h-4 w-4" /> Invoices
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
                    <TableCell className="text-right">{money(inv.balance, inv.currencyCode)}</TableCell>
                    <TableCell><StatusPill status={inv.status} /></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Payment history */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Payment history</CardTitle>
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
                    <TableCell className="text-right">{money(p.amount, p.currencyCode)}</TableCell>
                    <TableCell className="font-mono text-xs">{p.invoiceNumber ?? "—"}</TableCell>
                    <TableCell><StatusPill status={p.status} /></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Why this price? — read from the stored evaluation */}
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

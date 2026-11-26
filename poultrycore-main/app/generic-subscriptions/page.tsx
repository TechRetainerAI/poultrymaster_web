"use client"

// Subscriptions — who is on which plan, and when they next get billed.
//
// 499: Trial periods, coupon codes, and upgrade/downgrade with proration.

import { SUBSCRIPTION_CANCEL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useEffect, useMemo, useState } from "react"
import { useGenericModules } from "@/hooks/use-generic-modules"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import {
  Loader2, Plus, CalendarClock, Pause, Play, Ban, ArrowUpDown,
  Tag, Clock, Check, AlertCircle,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  getSubscriptions, createSubscription, setSubscriptionStatus,
  changePlan, validateCoupon,
  getServicePlans, getBusinessTemplate, getModuleSettings,
  type GenericSubscription, type GenericServicePlan,
  type CouponValidationResult,
} from "@/lib/api/generic-subscriptions"
import { getCustomers, type GenericCustomer } from "@/lib/api/generic"
import { templateLabels } from "@/lib/generic/template-labels"
import {
  BILLING_FREQUENCIES, FREQUENCY_LABELS, nextBillingDate, periodTotal,
  type BillingFrequency,
} from "@/lib/generic/billing-schedule"

const STATUS_STYLES: Record<string, string> = {
  Active: "border-emerald-300 bg-emerald-50 text-emerald-700",
  Paused: "border-amber-300 bg-amber-50 text-amber-700",
  Overdue: "border-rose-300 bg-rose-50 text-rose-700",
  Suspended: "border-rose-300 bg-rose-50 text-rose-700",
  Cancelled: "border-slate-300 bg-slate-100 text-slate-500",
  Expired: "border-slate-300 bg-slate-100 text-slate-500",
  Draft: "border-slate-300 bg-slate-50 text-slate-600",
}

const today = () => new Date().toISOString().slice(0, 10)

export default function GenericSubscriptionsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const { businessSettings: companySettings } = useGenericModules()
  const [rows, setRows] = useState<GenericSubscription[]>([])
  const [plans, setPlans] = useState<GenericServicePlan[]>([])
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [industry, setIndustry] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState("")
  const [statusFilter, setStatusFilter] = useState("All")
  const [open, setOpen] = useState(false)
  const [cancelling, setCancelling] = useState<GenericSubscription | null>(null)
  const [cancelReason, setCancelReason] = useState("")

  // 499: Change plan dialog
  const [changingPlan, setChangingPlan] = useState<GenericSubscription | null>(null)
  const [newPlanId, setNewPlanId] = useState("")
  const [newPlanAmount, setNewPlanAmount] = useState("")
  const [changeReason, setChangeReason] = useState("")

  // 499: Coupon validation on create form
  const [couponCode, setCouponCode] = useState("")
  const [couponResult, setCouponResult] = useState<CouponValidationResult | null>(null)
  const [validatingCoupon, setValidatingCoupon] = useState(false)

  // 499: Trial days on create form
  const [trialDays, setTrialDays] = useState("0")

  const labels = templateLabels(industry)

  const EMPTY = {
    genericCustomerId: "",
    genericServiceId: "",
    startDate: today(),
    endDate: "",
    billingFrequency: (companySettings?.defaultBillingFrequency ?? "Monthly") as BillingFrequency | string,
    billingAmount: "0",
    discountAmount: "0",
    taxAmount: "0",
    paymentDueDays: String(companySettings?.defaultPaymentDueDays ?? 0),
    autoGenerateInvoice: companySettings?.autoGenerateInvoices ?? true,
    notes: "",
  }
  const [form, setForm] = useState(EMPTY)

  useEffect(() => {
    if (!companySettings || open) return
    setForm((f) => (f.genericCustomerId === "" && f.genericServiceId === "" ? EMPTY : f))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [companySettings, open])

  const load = async () => {
    setLoading(true)
    try {
      const [subs, planRows, custs, template] = await Promise.all([
        getSubscriptions(),
        getServicePlans(true),
        getCustomers(),
        getBusinessTemplate().catch(() => null),
      ])
      setRows(subs)
      setPlans(planRows)
      setCustomers(custs)
      setIndustry(template?.genericIndustryTemplate ?? null)
    } catch (e: any) {
      toast({ title: "Could not load subscriptions", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    getModuleSettings()
      .then((s) => { if (!s.enableSubscriptions) router.replace("/generic-dashboard") })
      .catch(() => {})
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(() => {
    const byStatus = statusFilter === "All" ? rows : rows.filter((r) => r.status === statusFilter)
    return filterByDateAndSearch(byStatus, { search, searchKeys: ["customerName", "serviceName", "subscriptionNumber"] })
  }, [rows, search, statusFilter])
  const pg = usePagination(visible)

  // KPI stats
  const stats = useMemo(() => {
    const active = rows.filter((r) => r.status === "Active")
    return {
      active: active.length,
      paused: rows.filter((r) => r.status === "Paused").length,
      mrr: active.reduce((s, r) => s + r.totalBillingAmount, 0),
      openBalance: rows.reduce((s, r) => s + r.openBalance, 0),
    }
  }, [rows])

  const onPickPlan = (v: string) => {
    const plan = plans.find((p) => String(p.genericServiceId) === v)
    setForm((f) => ({
      ...f, genericServiceId: v,
      billingAmount: plan ? String(plan.defaultPrice) : f.billingAmount,
      billingFrequency: plan?.billingFrequency ?? f.billingFrequency,
    }))
    // Reset coupon when plan changes
    setCouponResult(null)
    setCouponCode("")
  }

  const previewNext = useMemo(() => {
    if (!form.startDate) return null
    return nextBillingDate(form.startDate, form.billingFrequency)
  }, [form.startDate, form.billingFrequency])

  const previewTotal = periodTotal(
    Number(form.billingAmount) || 0,
    Number(form.discountAmount) || 0,
    Number(form.taxAmount) || 0,
  )

  // 499: Validate coupon code
  const onValidateCoupon = async () => {
    if (!couponCode.trim()) return
    setValidatingCoupon(true)
    try {
      const result = await validateCoupon(couponCode.trim(), {
        customerId: Number(form.genericCustomerId) || undefined,
        serviceId: Number(form.genericServiceId) || undefined,
        billingAmount: Number(form.billingAmount) || undefined,
      })
      setCouponResult(result)
      if (result.valid && result.calculatedDiscount) {
        setForm((f) => ({ ...f, discountAmount: String(result.calculatedDiscount) }))
      }
    } catch {
      setCouponResult({ genericCouponId: null, code: couponCode, valid: false, reason: "Could not validate coupon.", discountType: null, discountValue: null, calculatedDiscount: null, description: null })
    } finally {
      setValidatingCoupon(false)
    }
  }

  const onSave = async () => {
    if (!form.genericCustomerId) { toast({ title: `Pick a ${labels.customer.toLowerCase()}`, variant: "destructive" }); return }
    if (!form.genericServiceId) { toast({ title: `Pick a ${labels.plan.toLowerCase()}`, variant: "destructive" }); return }
    if (previewTotal <= 0) { toast({ title: "The billing amount must be more than zero", variant: "destructive" }); return }
    setSaving(true)
    try {
      const id = await createSubscription({
        genericCustomerId: Number(form.genericCustomerId),
        genericServiceId: Number(form.genericServiceId),
        startDate: form.startDate,
        endDate: form.endDate || null,
        billingFrequency: form.billingFrequency,
        billingAmount: Number(form.billingAmount) || 0,
        discountAmount: Number(form.discountAmount) || 0,
        taxAmount: Number(form.taxAmount) || 0,
        paymentDueDays: Number(form.paymentDueDays) || 0,
        autoGenerateInvoice: form.autoGenerateInvoice,
        trialDays: Number(trialDays) || 0,
        couponCode: couponResult?.valid ? couponCode.trim() : null,
        notes: form.notes || null,
      })
      if (id) await setSubscriptionStatus(id, { status: "Active" })
      toast({ title: `${labels.subscription} created and activated.` })
      setOpen(false)
      setForm(EMPTY)
      setTrialDays("0")
      setCouponCode("")
      setCouponResult(null)
      await load()
    } catch (e: any) {
      toast({ title: `Could not create the ${labels.subscription.toLowerCase()}`, description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const changeStatus = async (s: GenericSubscription, status: string, reason?: string) => {
    try {
      await setSubscriptionStatus(s.genericSubscriptionId, { status, reason: reason ?? null })
      toast({ title: `${s.subscriptionNumber ?? labels.subscription} is now ${status}.` })
      await load()
    } catch (e: any) {
      toast({ title: "Could not change the status", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const onConfirmCancel = async () => {
    if (!cancelling || !cancelReason.trim()) {
      toast({ title: "A reason is required to cancel", variant: "destructive" }); return
    }
    await changeStatus(cancelling, "Cancelled", cancelReason.trim())
    setCancelling(null)
    setCancelReason("")
  }

  // 499: Change plan handler
  const openChangePlan = (s: GenericSubscription) => {
    setChangingPlan(s)
    setNewPlanId("")
    setNewPlanAmount("")
    setChangeReason("")
  }

  const onPickNewPlan = (v: string) => {
    const plan = plans.find((p) => String(p.genericServiceId) === v)
    setNewPlanId(v)
    setNewPlanAmount(plan ? String(plan.defaultPrice) : "")
  }

  const onConfirmChangePlan = async () => {
    if (!changingPlan || !newPlanId || !newPlanAmount) return
    setSaving(true)
    try {
      await changePlan(changingPlan.genericSubscriptionId, {
        newServiceId: Number(newPlanId),
        newBillingAmount: Number(newPlanAmount),
        reason: changeReason.trim() || null,
      })
      const newPlan = plans.find((p) => String(p.genericServiceId) === newPlanId)
      toast({ title: "Plan changed", description: `Moved to ${newPlan?.serviceName ?? "new plan"} at ${fmt(Number(newPlanAmount))}.` })
      setChangingPlan(null)
      await load()
    } catch (e: any) {
      toast({ title: "Could not change plan", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const statusBadge = (s: GenericSubscription) => {
    const isInTrial = s.trialDays > 0 && s.trialEndDate && new Date(s.trialEndDate) >= new Date()
    return (
      <div className="flex items-center gap-1 flex-wrap">
        <Badge variant="outline" className={STATUS_STYLES[s.status] ?? STATUS_STYLES.Draft}>{s.status}</Badge>
        {isInTrial && <Badge variant="outline" className="border-blue-300 bg-blue-50 text-blue-700"><Clock className="mr-0.5 h-3 w-3" /> Trial</Badge>}
      </div>
    )
  }

  const rowActions = (s: GenericSubscription) => {
    const live = s.status === "Active"
    const paused = s.status === "Paused"
    const finished = s.status === "Cancelled" || s.status === "Expired"
    return (
      <div className="flex gap-1 flex-wrap">
        {(live || paused) && (
          <Button size="sm" variant="ghost" className="h-8" onClick={() => openChangePlan(s)} title="Change plan">
            <ArrowUpDown className="h-3.5 w-3.5 mr-1" /> Change plan
          </Button>
        )}
        {live && (
          <Button size="sm" variant="ghost" className="h-8"
            onClick={() => changeStatus(s, "Paused", "Paused from the subscriptions page")}>
            <Pause className="h-3.5 w-3.5 mr-1" /> Pause
          </Button>
        )}
        {paused && (
          <Button size="sm" variant="ghost" className="h-8"
            onClick={() => changeStatus(s, "Active")}>
            <Play className="h-3.5 w-3.5 mr-1" /> Resume
          </Button>
        )}
        {!finished && (
          <Button size="sm" variant="ghost" className="h-8 text-rose-600"
            onClick={() => { setCancelling(s); setCancelReason("") }}>
            <Ban className="h-3.5 w-3.5 mr-1" /> Cancel
          </Button>
        )}
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Header */}
          <div className="mb-1 flex flex-wrap items-start justify-between gap-2">
            <h1 className="flex items-center gap-2 text-2xl font-semibold text-slate-900">
              <CalendarClock className="h-6 w-6 text-indigo-600" /> {labels.subscriptionPlural}
            </h1>
            <div className="flex gap-2">
              <Button asChild variant="outline" className="h-10">
                <Link href="/generic-coupons"><Tag className="mr-1.5 h-4 w-4" /> Coupons</Link>
              </Button>
              <Button asChild variant="outline" className="h-10">
                <Link href="/generic-billing-runs">Billing runs</Link>
              </Button>
              <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) { setCouponCode(""); setCouponResult(null); setTrialDays("0") } }}>
                <DialogTrigger asChild>
                  <Button className="h-10"><Plus className="h-4 w-4 mr-1" /> New {labels.subscription.toLowerCase()}</Button>
                </DialogTrigger>
                <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-[900px]")}>
                  <DialogHeader>
                    <FormDialogTitle icon={CalendarClock} color="blue">
                      New {labels.subscription.toLowerCase()}
                    </FormDialogTitle>
                    <DialogDescription>
                      The amount is copied from the plan and then belongs to this{" "}
                      {labels.subscription.toLowerCase()} — re-pricing the plan later does not re-price anyone already on it.
                    </DialogDescription>
                  </DialogHeader>

                  <div className="min-w-0 space-y-4">
                    <FormSection title="Who and what" color="indigo">
                      <FormField label={`${labels.customer} *`}>
                        <Select value={form.genericCustomerId} onValueChange={(v) => setForm((f) => ({ ...f, genericCustomerId: v }))}>
                          <SelectTrigger className="bg-white"><SelectValue placeholder={`Pick a ${labels.customer.toLowerCase()}`} /></SelectTrigger>
                          <SelectContent>
                            {customers.map((c) => <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>{c.customerName}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </FormField>
                      <FormField label={`${labels.plan} *`}>
                        <Select value={form.genericServiceId} onValueChange={onPickPlan}>
                          <SelectTrigger className="bg-white"><SelectValue placeholder={`Pick a ${labels.plan.toLowerCase()}`} /></SelectTrigger>
                          <SelectContent>
                            {plans.map((p) => <SelectItem key={p.genericServiceId} value={String(p.genericServiceId)}>{p.serviceName} — {fmt(p.defaultPrice)}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </FormField>
                    </FormSection>

                    <FormSection title="When and how often" color="emerald">
                      <FormField label="Starts *">
                        <Input type="date" className="bg-white" value={form.startDate} onChange={(e) => setForm((f) => ({ ...f, startDate: e.target.value }))} />
                      </FormField>
                      <FormField label="Ends (optional)">
                        <Input type="date" className="bg-white" value={form.endDate} onChange={(e) => setForm((f) => ({ ...f, endDate: e.target.value }))} />
                      </FormField>
                      <FormField label="Billing frequency">
                        <Select value={String(form.billingFrequency)} onValueChange={(v) => setForm((f) => ({ ...f, billingFrequency: v }))}>
                          <SelectTrigger className="bg-white"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {BILLING_FREQUENCIES.map((f) => <SelectItem key={f} value={f}>{FREQUENCY_LABELS[f]}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </FormField>
                      <FormField label="Payment terms (days)">
                        <NumberInput value={form.paymentDueDays} onChange={(e) => setForm((f) => ({ ...f, paymentDueDays: e.target.value }))} />
                      </FormField>
                    </FormSection>

                    <FormSection title="What it bills" color="amber">
                      <FormField label="Amount *">
                        <NumberInput step="0.01" value={form.billingAmount} onChange={(e) => setForm((f) => ({ ...f, billingAmount: e.target.value }))} />
                      </FormField>
                      <FormField label="Discount">
                        <NumberInput step="0.01" value={form.discountAmount} onChange={(e) => setForm((f) => ({ ...f, discountAmount: e.target.value }))} />
                      </FormField>
                      <FormField label="Tax">
                        <NumberInput step="0.01" value={form.taxAmount} onChange={(e) => setForm((f) => ({ ...f, taxAmount: e.target.value }))} />
                      </FormField>
                    </FormSection>

                    {/* 499: Trial period */}
                    <FormSection title="Trial period" color="blue">
                      <FormField label="Trial days" hint="Set to 0 for no trial. Billing is skipped until the trial ends.">
                        <NumberInput value={trialDays} min={0} onChange={(e) => setTrialDays(e.target.value)} />
                      </FormField>
                      {Number(trialDays) > 0 && form.startDate && (
                        <FormField label="Trial ends">
                          <div className="flex items-center gap-2 rounded-md border bg-blue-50 px-3 py-2 text-sm">
                            <Clock className="h-4 w-4 text-blue-600" />
                            <span className="font-medium">
                              {new Date(new Date(form.startDate).getTime() + Number(trialDays) * 86400000).toISOString().slice(0, 10)}
                            </span>
                            <span className="text-slate-500">({trialDays} days free)</span>
                          </div>
                        </FormField>
                      )}
                    </FormSection>

                    {/* 499: Coupon code */}
                    <FormSection title="Coupon code" color="orange">
                      <FormField label="Promo code (optional)" hint="Enter a code and click Apply to validate it.">
                        <div className="flex gap-2">
                          <Input className="bg-white flex-1 font-mono uppercase" placeholder="e.g. WELCOME20"
                            value={couponCode} onChange={(e) => { setCouponCode(e.target.value.toUpperCase()); setCouponResult(null) }} />
                          <Button type="button" variant="outline" onClick={onValidateCoupon}
                            disabled={!couponCode.trim() || validatingCoupon}>
                            {validatingCoupon ? <Loader2 className="h-4 w-4 animate-spin" /> : <Tag className="h-4 w-4 mr-1" />}
                            Apply
                          </Button>
                        </div>
                      </FormField>
                      {couponResult && (
                        <div className="col-span-full">
                          {couponResult.valid ? (
                            <div className="flex items-start gap-2 rounded-md border border-emerald-300 bg-emerald-50 p-3 text-sm">
                              <Check className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
                              <div>
                                <p className="font-medium text-emerald-800">
                                  {couponResult.discountType === "Percentage"
                                    ? `${couponResult.discountValue}% off`
                                    : `${fmt(couponResult.discountValue ?? 0)} off`}
                                  {" "}applied — saves {fmt(couponResult.calculatedDiscount ?? 0)}
                                </p>
                                {couponResult.description && <p className="text-emerald-700">{couponResult.description}</p>}
                              </div>
                            </div>
                          ) : (
                            <div className="flex items-start gap-2 rounded-md border border-rose-300 bg-rose-50 p-3 text-sm">
                              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-rose-600" />
                              <p className="text-rose-700">{couponResult.reason}</p>
                            </div>
                          )}
                        </div>
                      )}
                    </FormSection>

                    {/* Preview */}
                    <div className="overflow-hidden rounded-lg border border-indigo-200 bg-indigo-50/40">
                      <div className="flex items-center justify-between px-3 py-2 text-sm font-semibold text-slate-900">
                        <span>Billing summary</span>
                      </div>
                      <div className="divide-y divide-slate-100 bg-white text-sm">
                        <div className="flex justify-between gap-3 px-3 py-1.5">
                          <span>Amount per period</span>
                          <span className="tabular-nums font-semibold">{fmt(previewTotal)}</span>
                        </div>
                        <div className="flex justify-between gap-3 px-3 py-1.5">
                          <span>Frequency</span>
                          <span>{FREQUENCY_LABELS[form.billingFrequency as BillingFrequency]?.toLowerCase() ?? form.billingFrequency}</span>
                        </div>
                        {Number(trialDays) > 0 && (
                          <div className="flex justify-between gap-3 px-3 py-1.5 text-blue-700">
                            <span>Trial period</span>
                            <span>{trialDays} days free</span>
                          </div>
                        )}
                        {couponResult?.valid && (
                          <div className="flex justify-between gap-3 px-3 py-1.5 text-emerald-700">
                            <span>Coupon ({couponCode})</span>
                            <span>−{fmt(couponResult.calculatedDiscount ?? 0)}</span>
                          </div>
                        )}
                        <div className="flex justify-between gap-3 px-3 py-1.5">
                          <span>First billing</span>
                          <span className="font-medium">{Number(trialDays) > 0 && form.startDate
                            ? new Date(new Date(form.startDate).getTime() + Number(trialDays) * 86400000).toISOString().slice(0, 10)
                            : form.startDate}</span>
                        </div>
                        {previewNext && (
                          <div className="flex justify-between gap-3 px-3 py-1.5">
                            <span>Then</span>
                            <span>{previewNext}</span>
                          </div>
                        )}
                      </div>
                    </div>

                    <FormSection title="Notes" color="slate" columns={1}>
                      <FormField label="Notes">
                        <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                      </FormField>
                    </FormSection>
                  </div>

                  <FormDialogFooter onCancel={() => setOpen(false)}>
                    <Button onClick={onSave} disabled={saving} className={cn("px-6", FORM_DIALOG_PRIMARY.blue)}>
                      {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> Saving…</> : "Create and activate"}
                    </Button>
                  </FormDialogFooter>
                </DialogContent>
              </Dialog>
            </div>
          </div>
          <p className="mb-4 text-sm text-slate-500">
            {stats.active} active · {stats.paused} paused · MRR {fmt(stats.mrr)}
            {stats.openBalance > 0 && <> · <span className="text-rose-600">{fmt(stats.openBalance)} outstanding</span></>}
          </p>

          {/* Filters */}
          <div className="flex flex-wrap items-end gap-2 mb-3">
            <div className="flex-1 min-w-[220px]">
              <ListFilters search={search} setSearch={setSearch} searchOnly
                searchPlaceholder={`Search ${labels.customerPlural.toLowerCase()} or ${labels.planPlural.toLowerCase()}`} />
            </div>
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-[160px]"><SelectValue /></SelectTrigger>
              <SelectContent>
                {["All", "Active", "Paused", "Overdue", "Suspended", "Cancelled", "Expired", "Draft"].map((s) =>
                  <SelectItem key={s} value={s}>{s}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              No {labels.subscriptionPlural.toLowerCase()} yet. Create a {labels.plan.toLowerCase()} first, then put a {labels.customer.toLowerCase()} on it.
            </CardContent></Card>
          ) : (
            <Card><CardContent className="p-0">
              <MobileCardList
                items={pg.pageItems}
                getKey={(s) => s.genericSubscriptionId}
                primary={(s) => s.customerName ?? `#${s.genericCustomerId}`}
                secondary={(s) => <><span>{s.serviceName}</span><span> · {fmt(s.totalBillingAmount)}</span></>}
                trailing={(s) => statusBadge(s)}
                details={(s) => [
                  { label: "Number", value: s.subscriptionNumber ?? "—" },
                  { label: "Billing", value: FREQUENCY_LABELS[s.billingFrequency as BillingFrequency] ?? s.billingFrequency },
                  { label: "Next bill", value: s.nextBillingDate ?? "—" },
                  { label: "Open balance", value: fmt(s.openBalance) },
                  ...(s.trialDays > 0 ? [{ label: "Trial", value: `${s.trialDays} days${s.trialEndDate ? ` (until ${s.trialEndDate})` : ""}` }] : []),
                ]}
                actions={(s) => <div className="flex gap-2 w-full flex-wrap">{rowActions(s)}</div>}
                pagination={pg.paginationProps}
                desktopTable={
                  <div className="overflow-x-auto">
                    <Table className="w-full [&_td]:whitespace-normal [&_th]:whitespace-normal">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Number</TableHead>
                          <TableHead>{labels.customer}</TableHead>
                          <TableHead>{labels.plan}</TableHead>
                          <TableHead>Billing</TableHead>
                          <TableHead className="text-right">Per period</TableHead>
                          <TableHead>Next bill</TableHead>
                          <TableHead className="text-right">Open</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="w-56"><span className="sr-only">Actions</span></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((s) => (
                          <TableRow key={s.genericSubscriptionId} className={s.status === "Cancelled" || s.status === "Expired" ? "text-slate-400" : undefined}>
                            <TableCell className="font-mono text-xs whitespace-nowrap!">{s.subscriptionNumber ?? "—"}</TableCell>
                            <TableCell className="font-medium">{s.customerName ?? `#${s.genericCustomerId}`}</TableCell>
                            <TableCell>{s.serviceName ?? "—"}</TableCell>
                            <TableCell className="whitespace-nowrap!">{FREQUENCY_LABELS[s.billingFrequency as BillingFrequency] ?? s.billingFrequency}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold whitespace-nowrap!">{fmt(s.totalBillingAmount)}</TableCell>
                            <TableCell className="whitespace-nowrap!">{s.nextBillingDate ?? "—"}</TableCell>
                            <TableCell className="text-right whitespace-nowrap!">
                              <span className={s.openBalance > 0 ? "text-rose-700 font-semibold tabular-nums" : "tabular-nums"}>{fmt(s.openBalance)}</span>
                            </TableCell>
                            <TableCell>{statusBadge(s)}</TableCell>
                            <TableCell className="text-right">{rowActions(s)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                    <div className="px-4 pb-4 pt-2"><DataPagination {...pg.paginationProps} /></div>
                  </div>
                }
              />
            </CardContent></Card>
          )}
        </main>
      </div>

      {/* Cancel dialog */}
      <Dialog open={cancelling !== null} onOpenChange={(o) => !o && setCancelling(null)}>
        <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-md")}>
          <DialogHeader>
            <FormDialogTitle icon={Ban} color="red">
              Cancel {cancelling?.subscriptionNumber ?? labels.subscription.toLowerCase()}?
            </FormDialogTitle>
            <DialogDescription>Invoices already raised stay exactly as they are. This only stops future billing.</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <ReasonSelect options={SUBSCRIPTION_CANCEL_REASONS} value={cancelReason} onChange={setCancelReason} />
          </div>
          <FormDialogFooter onCancel={() => setCancelling(null)}>
            <Button className={cn("px-6", FORM_DIALOG_PRIMARY.red)} onClick={onConfirmCancel}>
              Cancel {labels.subscription.toLowerCase()}
            </Button>
          </FormDialogFooter>
        </DialogContent>
      </Dialog>

      {/* 499: Change plan dialog */}
      <Dialog open={changingPlan !== null} onOpenChange={(o) => { if (!o) setChangingPlan(null) }}>
        <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-lg")}>
          <DialogHeader>
            <FormDialogTitle icon={ArrowUpDown} color="blue">
              Change plan
            </FormDialogTitle>
            <DialogDescription>
              Switch {changingPlan?.customerName ?? "this customer"} to a different plan.
              Proration is calculated automatically for the remaining billing period.
            </DialogDescription>
          </DialogHeader>

          {changingPlan && (
            <div className="min-w-0 space-y-4">
              <FormSection title="Current plan" color="slate" columns={1}>
                <div className="rounded-md border bg-white p-3 text-sm">
                  <div className="flex items-center justify-between">
                    <span className="font-medium">{changingPlan.serviceName}</span>
                    <span className="font-semibold tabular-nums">{fmt(changingPlan.billingAmount)}</span>
                  </div>
                  <div className="mt-1 text-xs text-slate-500">
                    {FREQUENCY_LABELS[changingPlan.billingFrequency as BillingFrequency] ?? changingPlan.billingFrequency}
                    {changingPlan.nextBillingDate && <> · Next billing: {changingPlan.nextBillingDate}</>}
                  </div>
                </div>
              </FormSection>

              <FormSection title="New plan" color="blue">
                <FormField label={`${labels.plan} *`}>
                  <Select value={newPlanId} onValueChange={onPickNewPlan}>
                    <SelectTrigger className="bg-white"><SelectValue placeholder="Pick a new plan" /></SelectTrigger>
                    <SelectContent>
                      {plans.filter((p) => String(p.genericServiceId) !== String(changingPlan.genericServiceId)).map((p) =>
                        <SelectItem key={p.genericServiceId} value={String(p.genericServiceId)}>{p.serviceName} — {fmt(p.defaultPrice)}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="New billing amount *">
                  <NumberInput step="0.01" value={newPlanAmount} onChange={(e) => setNewPlanAmount(e.target.value)} />
                </FormField>
              </FormSection>

              {newPlanId && newPlanAmount && (
                <div className="overflow-hidden rounded-lg border border-blue-200 bg-blue-50/40 text-sm">
                  <div className="px-3 py-2 font-semibold text-slate-900">Change summary</div>
                  <div className="divide-y divide-slate-100 bg-white">
                    <div className="flex justify-between gap-3 px-3 py-1.5">
                      <span>Direction</span>
                      <span className={cn("font-medium",
                        Number(newPlanAmount) > changingPlan.billingAmount ? "text-emerald-700" : Number(newPlanAmount) < changingPlan.billingAmount ? "text-amber-700" : "")}>
                        {Number(newPlanAmount) > changingPlan.billingAmount ? "Upgrade" : Number(newPlanAmount) < changingPlan.billingAmount ? "Downgrade" : "Same price"}
                      </span>
                    </div>
                    <div className="flex justify-between gap-3 px-3 py-1.5">
                      <span>Old amount</span>
                      <span className="tabular-nums">{fmt(changingPlan.billingAmount)}</span>
                    </div>
                    <div className="flex justify-between gap-3 px-3 py-1.5">
                      <span>New amount</span>
                      <span className="tabular-nums font-semibold">{fmt(Number(newPlanAmount))}</span>
                    </div>
                  </div>
                </div>
              )}

              <FormSection title="Reason (optional)" color="slate" columns={1}>
                <Input className="bg-white" placeholder="Why are they changing?" value={changeReason} onChange={(e) => setChangeReason(e.target.value)} />
              </FormSection>
            </div>
          )}

          <FormDialogFooter onCancel={() => setChangingPlan(null)} cancelDisabled={saving}>
            <Button onClick={onConfirmChangePlan} disabled={saving || !newPlanId || !newPlanAmount}
              className={cn("px-6", FORM_DIALOG_PRIMARY.blue)}>
              {saving ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Changing…</> : "Change plan"}
            </Button>
          </FormDialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

"use client"

// Subscriptions — who is on which plan, and when they next get billed.
//
// A subscription does not raise invoices by itself. Nothing in this codebase
// runs on a schedule: no hosted service, no Hangfire, no cron. Billing is a
// button on the Billing Runs page, which is why "next bill" here is a promise
// about what that button will do rather than a countdown.

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
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Loader2, Plus, CalendarClock, Pause, Play, Ban } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getSubscriptions, createSubscription, setSubscriptionStatus,
  getServicePlans, getBusinessTemplate, getModuleSettings,
  type GenericSubscription, type GenericServicePlan,
} from "@/lib/api/generic-subscriptions"
import { getCustomers, type GenericCustomer } from "@/lib/api/generic"
import { templateLabels } from "@/lib/generic/template-labels"
import {
  BILLING_FREQUENCIES, FREQUENCY_LABELS, nextBillingDate, periodTotal,
  type BillingFrequency,
} from "@/lib/generic/billing-schedule"

const STATUS_STYLES: Record<string, string> = {
  Active: "bg-emerald-100 text-emerald-800 hover:bg-emerald-100",
  Paused: "bg-amber-100 text-amber-800 hover:bg-amber-100",
  Overdue: "bg-rose-100 text-rose-800 hover:bg-rose-100",
  Suspended: "bg-rose-100 text-rose-800 hover:bg-rose-100",
  Cancelled: "bg-slate-200 text-slate-700 hover:bg-slate-200",
  Expired: "bg-slate-200 text-slate-700 hover:bg-slate-200",
  Draft: "bg-slate-100 text-slate-600 hover:bg-slate-100",
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
  // The subscription being cancelled, if any. Cancelling asks for a reason
  // because the server requires one -- prompting is friendlier than a 500.
  const [cancelling, setCancelling] = useState<GenericSubscription | null>(null)
  const [cancelReason, setCancelReason] = useState("")

  const labels = templateLabels(industry)

  // The company's defaults (251), not hardcoded ones. A school opens this form
  // on Termly and 0 days; an agency on Monthly and 14. Falls back to the old
  // hardcoded values while the settings load or if they fail, so the form is
  // never blocked on them.
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

  // The settings arrive after the first render, so a form the user has not
  // opened yet has to pick them up. Only while it is untouched and closed --
  // resetting a half-typed form under someone's hands would be worse than
  // showing them a stale default.
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
      toast({
        title: "Could not load subscriptions",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    getModuleSettings()
      .then((s) => {
        if (!s.enableSubscriptions) router.replace("/generic-dashboard")
      })
      .catch(() => {})
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(() => {
    const byStatus =
      statusFilter === "All" ? rows : rows.filter((r) => r.status === statusFilter)
    return filterByDateAndSearch(byStatus, {
      search,
      searchKeys: ["customerName", "serviceName", "subscriptionNumber"],
    })
  }, [rows, search, statusFilter])
  const pg = usePagination(visible)

  // Picking a plan pre-fills its price and frequency. The subscription keeps
  // its own copy, so re-pricing the plan later does not silently re-price
  // everyone already on it.
  const onPickPlan = (v: string) => {
    const plan = plans.find((p) => String(p.genericServiceId) === v)
    setForm((f) => ({
      ...f,
      genericServiceId: v,
      billingAmount: plan ? String(plan.defaultPrice) : f.billingAmount,
      billingFrequency: plan?.billingFrequency ?? f.billingFrequency,
    }))
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

  const onSave = async () => {
    if (!form.genericCustomerId) {
      toast({ title: `Pick a ${labels.customer.toLowerCase()}`, variant: "destructive" })
      return
    }
    if (!form.genericServiceId) {
      toast({ title: `Pick a ${labels.plan.toLowerCase()}`, variant: "destructive" })
      return
    }
    if (previewTotal <= 0) {
      toast({ title: "The billing amount must be more than zero", variant: "destructive" })
      return
    }
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
        notes: form.notes || null,
      })
      // A new subscription starts as Draft. Activating it is what puts it in
      // front of the billing run, and that is a deliberate second step.
      if (id) await setSubscriptionStatus(id, { status: "Active" })
      toast({ title: `${labels.subscription} created and activated.` })
      setOpen(false)
      setForm(EMPTY)
      await load()
    } catch (e: any) {
      toast({
        title: `Could not create the ${labels.subscription.toLowerCase()}`,
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  const changeStatus = async (
    s: GenericSubscription,
    status: string,
    reason?: string,
  ) => {
    try {
      await setSubscriptionStatus(s.genericSubscriptionId, { status, reason: reason ?? null })
      toast({ title: `${s.subscriptionNumber ?? labels.subscription} is now ${status}.` })
      await load()
    } catch (e: any) {
      toast({
        title: "Could not change the status",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    }
  }

  const onConfirmCancel = async () => {
    if (!cancelling) return
    if (!cancelReason.trim()) {
      toast({ title: "A reason is required to cancel", variant: "destructive" })
      return
    }
    await changeStatus(cancelling, "Cancelled", cancelReason.trim())
    setCancelling(null)
    setCancelReason("")
  }

  const statusBadge = (s: GenericSubscription) => (
    <Badge className={STATUS_STYLES[s.status] ?? "bg-slate-100 text-slate-600 hover:bg-slate-100"}>
      {s.status}
    </Badge>
  )

  const rowActions = (s: GenericSubscription) => {
    const live = s.status === "Active"
    const paused = s.status === "Paused"
    const finished = s.status === "Cancelled" || s.status === "Expired"
    return (
      <>
        {live && (
          <Button
            size="sm"
            variant="outline"
            className="flex-1 h-10"
            onClick={() => changeStatus(s, "Paused", "Paused from the subscriptions page")}
          >
            <Pause className="h-4 w-4 mr-1" /> Pause
          </Button>
        )}
        {paused && (
          <Button
            size="sm"
            variant="outline"
            className="flex-1 h-10"
            onClick={() => changeStatus(s, "Active")}
          >
            <Play className="h-4 w-4 mr-1" /> Resume
          </Button>
        )}
        {!finished && (
          <Button
            size="sm"
            variant="outline"
            className="flex-1 h-10 text-red-600 border-red-200"
            onClick={() => {
              setCancelling(s)
              setCancelReason("")
            }}
          >
            <Ban className="h-4 w-4 mr-1" /> Cancel
          </Button>
        )}
      </>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <CalendarClock className="h-6 w-6 text-indigo-600" /> {labels.subscriptionPlural}
              </h1>
              <p className="text-sm text-slate-500">
                {rows.filter((r) => r.status === "Active").length} active of {rows.length}
              </p>
            </div>
            <div className="flex gap-2">
              <Link href="/generic-billing-runs">
                <Button variant="outline" className="h-11 sm:h-10">Billing runs</Button>
              </Link>
              <Dialog open={open} onOpenChange={setOpen}>
                <DialogTrigger asChild>
                  <Button className="h-11 sm:h-10">
                    <Plus className="h-4 w-4 mr-1" /> New {labels.subscription.toLowerCase()}
                  </Button>
                </DialogTrigger>
                <DialogContent className="w-[95vw] max-w-[900px] max-h-[90vh] overflow-y-auto">
                  <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                      <CalendarClock className="w-5 h-5 text-blue-600" /> New {labels.subscription.toLowerCase()}
                    </DialogTitle>
                    <DialogDescription>
                      The amount is copied from the plan and then belongs to this{" "}
                      {labels.subscription.toLowerCase()} — re-pricing the plan later does not
                      re-price anyone already on it.
                    </DialogDescription>
                  </DialogHeader>

                  <div className="space-y-4">
                    <FormSection title="Who and what" color="indigo">
                      <FormField label={`${labels.customer} *`}>
                        <Select
                          value={form.genericCustomerId}
                          onValueChange={(v) => setForm((f) => ({ ...f, genericCustomerId: v }))}
                        >
                          <SelectTrigger>
                            <SelectValue placeholder={`Pick a ${labels.customer.toLowerCase()}`} />
                          </SelectTrigger>
                          <SelectContent>
                            {customers.map((c) => (
                              <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>
                                {c.customerName}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </FormField>
                      <FormField label={`${labels.plan} *`}>
                        <Select value={form.genericServiceId} onValueChange={onPickPlan}>
                          <SelectTrigger>
                            <SelectValue placeholder={`Pick a ${labels.plan.toLowerCase()}`} />
                          </SelectTrigger>
                          <SelectContent>
                            {plans.map((p) => (
                              <SelectItem key={p.genericServiceId} value={String(p.genericServiceId)}>
                                {p.serviceName}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </FormField>
                    </FormSection>

                    <FormSection title="When and how often" color="emerald">
                      <FormField label="Starts *">
                        <Input
                          type="date"
                          value={form.startDate}
                          onChange={(e) => setForm((f) => ({ ...f, startDate: e.target.value }))}
                        />
                      </FormField>
                      <FormField label="Ends (optional)">
                        <Input
                          type="date"
                          value={form.endDate}
                          onChange={(e) => setForm((f) => ({ ...f, endDate: e.target.value }))}
                        />
                      </FormField>
                      <FormField label="Billing frequency">
                        <Select
                          value={String(form.billingFrequency)}
                          onValueChange={(v) => setForm((f) => ({ ...f, billingFrequency: v }))}
                        >
                          <SelectTrigger>
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {BILLING_FREQUENCIES.map((f) => (
                              <SelectItem key={f} value={f}>
                                {FREQUENCY_LABELS[f]}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </FormField>
                      <FormField label="Payment terms (days)">
                        <NumberInput
                          value={form.paymentDueDays}
                          onChange={(e) => setForm((f) => ({ ...f, paymentDueDays: e.target.value }))}
                        />
                      </FormField>
                    </FormSection>

                    <FormSection title="What it bills" color="amber">
                      <FormField label="Amount *">
                        <NumberInput
                          step="0.01"
                          value={form.billingAmount}
                          onChange={(e) => setForm((f) => ({ ...f, billingAmount: e.target.value }))}
                        />
                      </FormField>
                      <FormField label="Discount">
                        <NumberInput
                          step="0.01"
                          value={form.discountAmount}
                          onChange={(e) => setForm((f) => ({ ...f, discountAmount: e.target.value }))}
                        />
                      </FormField>
                      <FormField label="Tax">
                        <NumberInput
                          step="0.01"
                          value={form.taxAmount}
                          onChange={(e) => setForm((f) => ({ ...f, taxAmount: e.target.value }))}
                        />
                      </FormField>
                    </FormSection>

                    <div className="rounded-md bg-slate-100 p-3 text-sm text-slate-700">
                      Bills <strong>{fmt(previewTotal)}</strong>{" "}
                      {FREQUENCY_LABELS[form.billingFrequency as BillingFrequency]?.toLowerCase() ??
                        String(form.billingFrequency).toLowerCase()}
                      {previewNext ? (
                        <>
                          {" "}
                          — first on <strong>{form.startDate}</strong>, then <strong>{previewNext}</strong>.
                        </>
                      ) : (
                        <> — once, on <strong>{form.startDate}</strong>.</>
                      )}
                    </div>

                    <FormSection title="Notes" color="slate" columns={1}>
                      <FormField label="Notes">
                        <Textarea
                          rows={2}
                          value={form.notes}
                          onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
                        />
                      </FormField>
                    </FormSection>

                    <div className="flex gap-3 justify-end pt-2">
                      <Button
                        type="button"
                        onClick={() => setOpen(false)}
                        className="bg-red-600 hover:bg-red-700 text-white"
                      >
                        Cancel
                      </Button>
                      <Button onClick={onSave} disabled={saving}>
                        {saving ? (
                          <>
                            <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                            Saving…
                          </>
                        ) : (
                          "Create and activate"
                        )}
                      </Button>
                    </div>
                  </div>
                </DialogContent>
              </Dialog>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <Card>
              <CardContent className="py-8 text-center text-slate-500">
                No {labels.subscriptionPlural.toLowerCase()} yet. Create a{" "}
                {labels.plan.toLowerCase()} first, then put a {labels.customer.toLowerCase()} on it.
              </CardContent>
            </Card>
          ) : (
            <>
              <div className="flex flex-wrap items-end gap-2 mb-3">
                <div className="flex-1 min-w-[220px]">
                  <ListFilters
                    search={search}
                    setSearch={setSearch}
                    searchOnly
                    searchPlaceholder={`Search ${labels.customerPlural.toLowerCase()} or ${labels.planPlural.toLowerCase()}`}
                  />
                </div>
                <Select value={statusFilter} onValueChange={setStatusFilter}>
                  <SelectTrigger className="w-[180px]">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {["All", "Active", "Paused", "Overdue", "Suspended", "Cancelled", "Expired", "Draft"].map(
                      (s) => (
                        <SelectItem key={s} value={s}>
                          {s}
                        </SelectItem>
                      ),
                    )}
                  </SelectContent>
                </Select>
              </div>

              <Card>
                <CardContent className="p-0">
                  <MobileCardList
                    items={pg.pageItems}
                    getKey={(s) => s.genericSubscriptionId}
                    primary={(s) => s.customerName ?? `#${s.genericCustomerId}`}
                    secondary={(s) => (
                      <>
                        <span>{s.serviceName}</span>
                        <span> · {fmt(s.totalBillingAmount)}</span>
                      </>
                    )}
                    trailing={(s) => statusBadge(s)}
                    details={(s) => [
                      { label: "Number", value: s.subscriptionNumber ?? "—" },
                      {
                        label: "Billing",
                        value:
                          FREQUENCY_LABELS[s.billingFrequency as BillingFrequency] ?? s.billingFrequency,
                      },
                      { label: "Next bill", value: s.nextBillingDate ?? "—" },
                      { label: "Open balance", value: fmt(s.openBalance) },
                    ]}
                    actions={rowActions}
                    pagination={pg.paginationProps}
                    desktopTable={
                      <div className="overflow-x-auto">
                        <Table>
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
                              <TableHead />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pg.pageItems.map((s) => (
                              <TableRow key={s.genericSubscriptionId}>
                                <TableCell className="font-mono text-xs">
                                  {s.subscriptionNumber ?? "—"}
                                </TableCell>
                                <TableCell className="font-medium">
                                  {s.customerName ?? `#${s.genericCustomerId}`}
                                </TableCell>
                                <TableCell>{s.serviceName ?? "—"}</TableCell>
                                <TableCell>
                                  {FREQUENCY_LABELS[s.billingFrequency as BillingFrequency] ??
                                    s.billingFrequency}
                                </TableCell>
                                <TableCell className="text-right">
                                  {fmt(s.totalBillingAmount)}
                                </TableCell>
                                <TableCell>{s.nextBillingDate ?? "—"}</TableCell>
                                <TableCell className="text-right">
                                  <span className={s.openBalance > 0 ? "text-rose-700 font-semibold" : ""}>
                                    {fmt(s.openBalance)}
                                  </span>
                                </TableCell>
                                <TableCell>{statusBadge(s)}</TableCell>
                                <TableCell className="text-right whitespace-nowrap">
                                  <div className="inline-flex gap-1">{rowActions(s)}</div>
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                        <DataPagination {...pg.paginationProps} />
                      </div>
                    }
                  />
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>

      <Dialog open={cancelling !== null} onOpenChange={(o) => !o && setCancelling(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Cancel {cancelling?.subscriptionNumber ?? labels.subscription.toLowerCase()}?</DialogTitle>
            <DialogDescription>
              Invoices already raised stay exactly as they are. This only stops future billing.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Textarea
              rows={3}
              placeholder="Why is it being cancelled?"
              value={cancelReason}
              onChange={(e) => setCancelReason(e.target.value)}
            />
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setCancelling(null)}>
              Keep it
            </Button>
            <Button className="bg-red-600 hover:bg-red-700 text-white" onClick={onConfirmCancel}>
              Cancel {labels.subscription.toLowerCase()}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
